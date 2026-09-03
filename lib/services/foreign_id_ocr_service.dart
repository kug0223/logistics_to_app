import 'dart:io';
import 'dart:math' show max;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// 외국인등록증 OCR 결과
class ForeignIdOcrResult {
  /// 성명 (외국인등록증 기재 공식 이름, 정규화된 ASCII)
  final String? legalName;

  /// 외국인등록번호 13자리 평문 (서버 전송용 — 화면 표시는 maskedForeignId 사용)
  final String? foreignIdRaw;

  /// 체류자격 (예: E-9, F-4, H-2)
  final String? visaType;

  /// 체류기간만료일 (ISO 8601: YYYY-MM-DD)
  final String? stayExpiryDate;

  final bool legalNameFailed;
  final bool foreignIdFailed;
  final bool visaTypeFailed;
  final bool stayExpiryFailed;

  // ── [Phase A.4] OCR quality tracking ─────────────────────────────────────

  /// Full-card Korean OCR에서 diacritic normalization이 발생했는지.
  final bool legalNameHadDiacritic;

  /// 성명 최종 선택 OCR source.
  /// - 'LATIN_REGION' : 2차 Latin region OCR 결과 (더 정확)
  /// - 'FULL_OCR'     : 1차 Korean OCR 정규화 결과 (fallback)
  /// - 'NONE'         : 인식 실패
  final String legalNameOcrSource;

  const ForeignIdOcrResult({
    this.legalName,
    this.foreignIdRaw,
    this.visaType,
    this.stayExpiryDate,
    this.legalNameFailed = false,
    this.foreignIdFailed = false,
    this.visaTypeFailed = false,
    this.stayExpiryFailed = false,
    this.legalNameHadDiacritic = false,
    this.legalNameOcrSource = 'NONE',
  });

  String? get maskedForeignId {
    if (foreignIdRaw == null || foreignIdRaw!.length < 7) return null;
    final front = foreignIdRaw!.substring(0, 6);
    final genderDigit = foreignIdRaw!.substring(6, 7);
    return '$front-$genderDigit******';
  }

  bool get isFullyRecognized =>
      !legalNameFailed && !foreignIdFailed && !visaTypeFailed;

  bool get shouldPromptNameVerification =>
      legalNameHadDiacritic || legalNameOcrSource == 'FULL_OCR';

  ForeignIdOcrResult copyWith({
    String? legalName,
    String? foreignIdRaw,
    String? visaType,
    String? stayExpiryDate,
    bool? legalNameFailed,
    bool? foreignIdFailed,
    bool? visaTypeFailed,
    bool? stayExpiryFailed,
    bool? legalNameHadDiacritic,
    String? legalNameOcrSource,
  }) {
    return ForeignIdOcrResult(
      legalName: legalName ?? this.legalName,
      foreignIdRaw: foreignIdRaw ?? this.foreignIdRaw,
      visaType: visaType ?? this.visaType,
      stayExpiryDate: stayExpiryDate ?? this.stayExpiryDate,
      legalNameFailed: legalNameFailed ?? this.legalNameFailed,
      foreignIdFailed: foreignIdFailed ?? this.foreignIdFailed,
      visaTypeFailed: visaTypeFailed ?? this.visaTypeFailed,
      stayExpiryFailed: stayExpiryFailed ?? this.stayExpiryFailed,
      legalNameHadDiacritic:
          legalNameHadDiacritic ?? this.legalNameHadDiacritic,
      legalNameOcrSource: legalNameOcrSource ?? this.legalNameOcrSource,
    );
  }
}

/// 외국인등록증 OCR 서비스
///
/// [PRODUCT-POLICY] OCR은 입력 보조수단.
///   목표: 카드에 인쇄된 영문 이름 문자열을 그대로 prefill.
///   언어별 발음 복원, 이름 dictionary 교정, fuzzy matching 금지.
///
/// [TWO-PASS OCR 구조 — Phase A.4/A.5]
///   Pass 1: Full-card Korean OCR → semantic zone 이름 추출
///   Pass 2: Name candidate bbox union crop → Latin OCR
///
/// [Phase A.5 이름 추출 개선]
///   - 인라인 레이블 분리: "명 NAM PON-" → "NAM PON-" (CARD B 대응)
///   - 멀티라인 하이픈 체인: "NAM NATALIYA PON-" + "ENOVNA" → "NAM NATALIYA PON-ENOVNA"
///   - 다중 토큰 우선: 단일 토큰 "KORI"보다 2+토큰 "SUKHMINDER SINGH" 우선 (CARD C 대응)
///   - 등록번호 유연 구분자: "710308- 6140893" (하이픈+공백) 지원 (CARD B 대응)
///
/// [알려진 제약사항]
///   - EXIF rotation: dart:ui bbox 좌표와 ML Kit bbox 좌표 불일치 가능.
///     P2 crop 실패 또는 유효 이름 없을 시 Full OCR name으로 자동 fallback.
class ForeignIdOcrService {
  // ── 외국인등록번호 패턴 ──────────────────────────────────────────────────────
  // [Phase A.5] 유연한 구분자: [-–—\s]{0,3} (하이픈+공백 2자 허용 — CARD B 대응)
  static final _foreignIdPattern =
      RegExp(r'\b(\d{6})[-–—\s]{0,3}([5-9]\d{6})\b');

  // OCR confusion 허용 패턴 (O→0, I/l→1 혼용) — 구분자 동일하게 유연화
  static final _foreignIdPatternConfusion =
      RegExp(r'\b([0-9O]{6})[-–—\s]{0,3}([5-9OI1l][0-9OIl]{6})\b');

  // 체류자격 패턴 (E-9, F-4, H-2, D-10 등)
  static final _visaTypePattern =
      RegExp(r'\b([A-HJ-Z]-\d{1,2}(?:-\d)?)\b');

  // [A.9] OCR 왜곡 체류자격 변형 패턴 (Fi4 / F4 / F - 4 → F-X 정규화용)
  // 체류자격/Status context 줄에서만 사용. 전역 적용 금지.
  static final _visaContextFallbackPattern =
      RegExp(r'([A-HJ-Z])\s*(?:[i]|[-]\s*)?\s*(\d{1,2}(?:[-]\d)?)');

  // [A.10] 외국인등록번호 레이블 패턴 (context-aware digit extraction용)
  // 체류자격·이름 레이블과 분리된 registration 전용 context.
  static final _registrationLabelPattern = RegExp(
      r'(?:외국인\s*등록\s*번호|등록\s*번호|Registration\s*No\.?|거\S*번호)',
      caseSensitive: false);

  // 성명 레이블 위치 탐지
  static final _nameLabelPattern =
      RegExp(r'(?:성\s*명|Name)');

  // 순수 라틴 이름 패턴 — fallback 탐색용 (Unicode 라틴 확장 포함)
  static final _latinNamePattern =
      RegExp(r'^([A-Z][A-Za-zÀ-ỿ \-]{2,60})$', multiLine: true);

  // 체류기간만료일 레이블 + 날짜
  static final _expiryAfterLabelPattern = RegExp(
      r'(?:체류기간\s*만료일|Date of Expiry|Expiry Date)'
      r'[^\d]*(\d{4})[.\-]\s*(\d{1,2})[.\-]\s*(\d{1,2})',
      caseSensitive: false);

  // 성명 레이블 키워드 차단
  static const _nameLabelKeywords = {
    'NAME', 'NAMES', 'LEGAL NAME', 'FULL NAME',
  };

  // 국가/지역 레이블 패턴 (fallback 국가명 제외용)
  static final _nationalityLabelPattern = RegExp(
      r'(?:국가|지역|국적|Country|Region|Nationality)',
      caseSensitive: false);

  // [Phase A.5] 필드 경계 패턴 — anchor scan 전진 중단 조건
  static final _fieldBoundaryPattern = RegExp(
      r'(?:국가|지역|Country|Region|체류자격|Status|발급|Issue\s*Date|체류기간|Expiry)',
      caseSensitive: false);

  // ──────────────────────────────────────────────────────────────────────────
  // [Phase A.3/A.4] 외국인 이름 Latin diacritic 정규화
  // ──────────────────────────────────────────────────────────────────────────

  @visibleForTesting
  static String normalizeForeignLatinName(String raw) {
    final normalized = raw.split('').map((c) => _diacriticMap[c] ?? c).join('');
    return normalized.toUpperCase().replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  static const _diacriticMap = <String, String>{
    'À':'A','Á':'A','Â':'A','Ã':'A','Ä':'A','Å':'A',
    'à':'A','á':'A','â':'A','ã':'A','ä':'A','å':'A',
    'Æ':'AE','æ':'AE',
    'Ç':'C','ç':'C',
    'È':'E','É':'E','Ê':'E','Ë':'E',
    'è':'E','é':'E','ê':'E','ë':'E',
    'Ì':'I','Í':'I','Î':'I','Ï':'I',
    'ì':'I','í':'I','î':'I','ï':'I',
    'Ñ':'N','ñ':'N',
    'Ò':'O','Ó':'O','Ô':'O','Õ':'O','Ö':'O','Ø':'O',
    'ò':'O','ó':'O','ô':'O','õ':'O','ö':'O','ø':'O',
    'Ù':'U','Ú':'U','Û':'U','Ü':'U',
    'ù':'U','ú':'U','û':'U','ü':'U',
    'Ý':'Y','ý':'Y','ÿ':'Y',
    'Ā':'A','ā':'A','Ă':'A','ă':'A','Ą':'A','ą':'A',
    'Ć':'C','ć':'C','Č':'C','č':'C',
    'Ď':'D','Đ':'D','đ':'D',
    'Ē':'E','ē':'E','Ě':'E','ě':'E','Ę':'E','ę':'E',
    'Ğ':'G','ğ':'G',
    'İ':'I','ı':'I','Į':'I','į':'I',
    'Ł':'L','ł':'L',
    'Ń':'N','ń':'N','Ň':'N','ň':'N',
    'Ő':'O','ő':'O',
    'Ř':'R','ř':'R',
    'Ś':'S','ś':'S','Ş':'S','ş':'S','Š':'S','š':'S',
    'Ţ':'T','ţ':'T','Ť':'T','ť':'T',
    'Ū':'U','ū':'U','Ů':'U','ů':'U','Ű':'U','ű':'U','Ų':'U','ų':'U',
    'Ÿ':'Y',
    'Ź':'Z','ź':'Z','Ż':'Z','ż':'Z','Ž':'Z','ž':'Z',
    'Ư':'U','ư':'U','Ơ':'O','ơ':'O',
    'Ắ':'A','ắ':'A','Ặ':'A','ặ':'A','Ẳ':'A','ẳ':'A','Ằ':'A','ằ':'A','Ẵ':'A','ẵ':'A',
    'Ấ':'A','ấ':'A','Ậ':'A','ậ':'A','Ẩ':'A','ẩ':'A','Ầ':'A','ầ':'A','Ẫ':'A','ẫ':'A',
    'Ạ':'A','ạ':'A','Ả':'A','ả':'A',
    'Ế':'E','ế':'E','Ệ':'E','ệ':'E','Ể':'E','ể':'E','Ề':'E','ề':'E','Ễ':'E','ễ':'E',
    'Ẹ':'E','ẹ':'E','Ẻ':'E','ẻ':'E','Ẽ':'E','ẽ':'E',
    'Ị':'I','ị':'I','Ỉ':'I','ỉ':'I',
    'Ố':'O','ố':'O','Ộ':'O','ộ':'O','Ổ':'O','ổ':'O','Ồ':'O','ồ':'O','Ỗ':'O','ỗ':'O',
    'Ớ':'O','ớ':'O','Ợ':'O','ợ':'O','Ở':'O','ở':'O','Ờ':'O','ờ':'O','Ỡ':'O','ỡ':'O',
    'Ọ':'O','ọ':'O','Ỏ':'O','ỏ':'O',
    'Ứ':'U','ứ':'U','Ự':'U','ự':'U','Ử':'U','ử':'U','Ừ':'U','ừ':'U','Ữ':'U','ữ':'U',
    'Ụ':'U','ụ':'U','Ủ':'U','ủ':'U',
    'Ỳ':'Y','ỳ':'Y','Ỵ':'Y','ỵ':'Y','Ỷ':'Y','ỷ':'Y','Ỹ':'Y','ỹ':'Y',
  };

  // ──────────────────────────────────────────────────────────────────────────
  // [Phase A.5] 이름 추출 헬퍼
  // ──────────────────────────────────────────────────────────────────────────

  /// 한글/한자 및 이름 레이블 접두사 제거.
  ///
  /// CARD B: "명 NAM NATALIYA PON-" → "NAM NATALIYA PON-"
  /// CARD B: "Name ENOVNA" → "ENOVNA" (단, anchor에서 레이블 제거 후 inline 처리)
  static String _stripNameLabelAndKorean(String s) {
    // 성명·명·Name 접두사 제거
    String r = s.replaceFirst(
        RegExp(r'^(?:성\s*명|명|Name)\s*', caseSensitive: false), '');
    // 선행 한글/한자 및 공백 제거 (Hangul: AC00-D7A3, Jamo: 1100-11FF, 3130-318F)
    r = r.replaceAll(
        RegExp(r'^[ᄀ-ᇿ㄰-㆏가-힣\s]+'), '');
    return r.trim();
  }

  /// 이름 후보 검증 (normalized 결과 기준).
  static bool _isValidNameNormalized(String normalized) {
    if (!RegExp(r'^[A-Z]').hasMatch(normalized)) return false;
    if (normalized.length < 2) return false;
    if (_nameLabelKeywords.contains(normalized)) return false;
    if (_isCardBoilerplate(normalized)) return false;
    if (_foreignIdPattern.hasMatch(normalized)) return false;
    if (_visaTypePattern.hasMatch(normalized)) return false;
    if (_isFieldLabelLike(normalized)) return false; // [Phase A.6] 퍼지 레이블 차단
    return true;
  }

  /// 공백으로 구분된 토큰 수 (다중 토큰 우선 선택용).
  static int _wordCount(String name) =>
      name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  /// 프래그먼트 리스트를 하이픈 체인 기반으로 candidate 조합.
  ///
  /// 입력: [(normalized, rawLine)] 순서 리스트
  /// 출력: [(assembledName, hadDiacritic, contributingRawLines)] candidate 리스트
  ///
  /// 예: ["NAM NATALIYA PON-", "ENOVNA"] → ["NAM NATALIYA PON-ENOVNA"] (하이픈 체인)
  ///      ["KORI", "SUKHMINDER SINGH"]   → ["KORI", "SUKHMINDER SINGH"] (독립 candidate)
  static List<(String, bool, List<String>)> _assembleNameFragments(
    List<(String, String)> fragments, // (normalized, rawLine)
  ) {
    final candidates = <(String, bool, List<String>)>[];
    int i = 0;
    while (i < fragments.length) {
      final (norm, raw) = fragments[i];
      if (norm.endsWith('-') && i + 1 < fragments.length) {
        // 하이픈 체인: 다음 프래그먼트와 연결
        var chain = norm;
        final rawLines = [raw];
        bool hadDiac = _fragmentHasDiacritic(norm, raw);
        i++;
        while (i < fragments.length && chain.endsWith('-')) {
          final (nextNorm, nextRaw) = fragments[i];
          chain += nextNorm;
          rawLines.add(nextRaw);
          if (_fragmentHasDiacritic(nextNorm, nextRaw)) hadDiac = true;
          i++;
        }
        if (_isValidNameNormalized(chain)) {
          candidates.add((chain, hadDiac, rawLines));
        }
      } else {
        // 독립 candidate
        final hadDiac = _fragmentHasDiacritic(norm, raw);
        candidates.add((norm, hadDiac, [raw]));
        i++;
      }
    }
    return candidates;
  }

  /// 프래그먼트에 diacritic이 있는지 판단.
  ///
  /// stripped raw가 normalize 결과와 다른지로 확인.
  /// 대소문자/공백 차이는 제외하고 실제 diacritic 치환 여부만 감지.
  static bool _fragmentHasDiacritic(String normalized, String rawLine) {
    final stripped = _stripNameLabelAndKorean(rawLine);
    if (stripped.isEmpty) return false;
    // 실제 diacritic 문자가 포함된 경우만 true
    return stripped.contains(RegExp(r'[À-ỿ]'));
  }

  // ──────────────────────────────────────────────────────────────────────────
  // [Phase A.5] P2 crop 지오메트리 헬퍼
  // ──────────────────────────────────────────────────────────────────────────

  /// RecognizedText 라인 중 rawLines와 매칭되는 라인의 bbox 리스트 반환.
  ///
  /// 매칭 방식: line.text와 rawLine 간 contains 양방향 검사 (최소 길이 4).
  static List<Rect> _findLineBboxes(
      RecognizedText recognized, List<String> rawLines) {
    final result = <Rect>[];
    final checked = <Rect>{};
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final lineText = line.text.trim();
        if (lineText.length < 4) continue;
        for (final raw in rawLines) {
          if (raw.length < 4) continue;
          if (lineText == raw ||
              lineText.contains(raw) ||
              raw.contains(lineText)) {
            final bbox = line.boundingBox;
            if (!checked.contains(bbox)) {
              result.add(bbox);
              checked.add(bbox);
            }
            break;
          }
        }
      }
    }
    return result;
  }

  /// bbox 리스트의 union Rect 계산.
  static Rect _bboxUnion(List<Rect> rects) {
    var l = rects.first.left;
    var t = rects.first.top;
    var r = rects.first.right;
    var b = rects.first.bottom;
    for (final rect in rects.skip(1)) {
      if (rect.left < l) l = rect.left;
      if (rect.top < t) t = rect.top;
      if (rect.right > r) r = rect.right;
      if (rect.bottom > b) b = rect.bottom;
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  /// bbox union → P2 crop Rect 계산.
  ///
  /// [§16-18 Phase A.5]:
  ///   Priority A: name candidate line(s) bbox union
  ///   - 비율 패딩 (lineH * 0.5 수직, lineH 수평)
  ///   - 최소 64×64 보장 (ML Kit 최소 32×32의 2× 안전 마진)
  ///   - 이미지 범위 내 clamp
  ///
  /// [§21] EXIF rotation 주의: ML Kit bbox는 display 방향, dart:ui는 raw 픽셀.
  ///   일부 기기에서 crop 좌표 불일치 가능 → 실기기 검증 필요.
  static Rect? _computeP2CropRect(
      List<Rect> nameBboxes, double imageW, double imageH) {
    if (nameBboxes.isEmpty) return null;

    final union = _bboxUnion(nameBboxes);
    final lineH = union.height.clamp(10.0, 200.0);
    final padH = max(lineH, 20.0);
    final padV = max(lineH * 0.5, 16.0);

    var l = union.left - padH;
    var t = union.top - padV;
    var r = union.right + padH;
    var b = union.bottom + padV;

    // 최소 64×64 보장
    final w = r - l;
    final h = b - t;
    if (w < 64) {
      final extra = (64 - w) / 2;
      l -= extra;
      r += extra;
    }
    if (h < 64) {
      final extra = (64 - h) / 2;
      t -= extra;
      b += extra;
    }

    // 이미지 범위 내 clamp
    l = l.clamp(0.0, imageW);
    t = t.clamp(0.0, imageH);
    r = r.clamp(0.0, imageW);
    b = b.clamp(0.0, imageH);

    return Rect.fromLTRB(l, t, r, b);
  }

  /// [visibleForTesting] P2 crop 지오메트리 단위 테스트용 진입점.
  @visibleForTesting
  static Rect? computeP2CropRectFromBboxes(
    List<Rect> nameBboxes, {
    required double imageWidth,
    required double imageHeight,
  }) {
    return _computeP2CropRect(nameBboxes, imageWidth, imageHeight);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // [Phase A.4] Name region anchor-derived fallback crop
  // ──────────────────────────────────────────────────────────────────────────

  /// P1 candidate bbox를 찾지 못했을 때의 anchor-derived fallback 영역 (Priority C).
  static Rect? _nameZoneRectFallback(RecognizedText recognized) {
    TextLine? nameLabelLine;
    outer:
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        if (_nameLabelPattern.hasMatch(line.text)) {
          nameLabelLine = line;
          break outer;
        }
      }
    }

    if (nameLabelLine == null) return null;
    final labelBox = nameLabelLine.boundingBox;
    final lineH = labelBox.height.clamp(10.0, double.infinity);

    final nextAnchorPatterns = [
      RegExp(r'(?:국가|지역|Country|Region|Nationality)', caseSensitive: false),
      RegExp(r'\d{6}'),
      RegExp(r'(?:체류자격|Status)', caseSensitive: false),
      RegExp(r'(?:발급|Issue)', caseSensitive: false),
    ];

    double? nextAnchorTop;
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final box = line.boundingBox;
        if (box.top <= labelBox.bottom) continue;
        for (final pat in nextAnchorPatterns) {
          if (pat.hasMatch(line.text)) {
            if (nextAnchorTop == null || box.top < nextAnchorTop) {
              nextAnchorTop = box.top.toDouble();
            }
            break;
          }
        }
      }
    }

    double maxRight = labelBox.right + 400;
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        if (line.boundingBox.right > maxRight) {
          maxRight = line.boundingBox.right.toDouble();
        }
      }
    }

    // [Phase A.5] 위쪽으로도 확장 (인라인 레이블 케이스 대응)
    final regionTop = labelBox.top - lineH * 2;
    final regionBottom = nextAnchorTop != null
        ? nextAnchorTop + lineH * 0.5
        : labelBox.bottom + lineH * 3.5;
    final regionLeft = labelBox.left - lineH;
    final regionRight = maxRight + lineH;

    return Rect.fromLTRB(
      regionLeft.clamp(0.0, double.infinity),
      regionTop.clamp(0.0, double.infinity),
      regionRight,
      regionBottom,
    );
  }

  /// Name region crop → 임시 PNG 파일로 저장.
  ///
  /// [알려진 제약] EXIF rotation: dart:ui는 EXIF를 무시하므로 일부 기기에서
  ///   bbox와 픽셀 좌표가 불일치할 수 있음. 실패 시 Full OCR fallback.
  ///
  /// 호출자가 반드시 반환된 경로의 파일을 삭제해야 함 (CLAUDE.md TMP-01).
  static Future<String?> _cropToTempFile(String imagePath, Rect region) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final srcImage = frame.image;

      try {
        final iw = srcImage.width.toDouble();
        final ih = srcImage.height.toDouble();

        if (kDebugMode) {
          debugPrint('[OCR P2] DECODED IMAGE SIZE: ${iw.toInt()}×${ih.toInt()}');
          debugPrint('[OCR P2] ROTATION: UNKNOWN (dart:ui EXIF 무시 — 불일치 가능)');
        }

        final l = region.left.clamp(0.0, iw);
        final t = region.top.clamp(0.0, ih);
        final r = region.right.clamp(0.0, iw);
        final b = region.bottom.clamp(0.0, ih);
        final cropW = r - l;
        final cropH = b - t;

        if (kDebugMode) {
          final dimValid = cropW >= 32 && cropH >= 32;
          debugPrint('[OCR P2] CROP REGION: L=${l.toInt()} T=${t.toInt()} '
              'R=${r.toInt()} B=${b.toInt()} → ${cropW.toInt()}×${cropH.toInt()}');
          debugPrint('[OCR P2] CROP DIMENSION VALID: ${dimValid ? 'PASS' : 'FAIL'} '
              '(≥32×32 required, got ${cropW.toInt()}×${cropH.toInt()})');
        }

        // [Phase A.5] 최소 32×32 강제 (ML Kit 요구사항)
        if (cropW < 32 || cropH < 32) {
          if (kDebugMode) {
            debugPrint('[OCR P2] CROP CONTENT VALID: FAIL (dimension too small)');
          }
          return null;
        }

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImageRect(
          srcImage,
          Rect.fromLTWH(l, t, cropW, cropH),
          Rect.fromLTWH(0, 0, cropW, cropH),
          Paint(),
        );
        final picture = recorder.endRecording();
        final cropped = await picture.toImage(cropW.toInt(), cropH.toInt());

        try {
          final byteData = await cropped.toByteData(format: ui.ImageByteFormat.png);
          if (byteData == null) return null;

          final tempDir = await getTemporaryDirectory();
          final path = '${tempDir.path}/ocr_name_region_tmp.png';
          await File(path).writeAsBytes(byteData.buffer.asUint8List());

          if (kDebugMode) {
            debugPrint('[OCR P2] CROP CONTENT VALID: PASS (${cropW.toInt()}×${cropH.toInt()})');
          }
          return path;
        } finally {
          cropped.dispose();
        }
      } finally {
        srcImage.dispose();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ [OCR P2 crop] 실패: $e');
      return null;
    }
  }

  /// [Phase A.6/A.7/A.7.1/A.8] Latin region OCR / Full OCR 중 최선 선택 — P2 arbitration.
  ///
  /// p2HasSpatialInfo: P2 crop이 P1 name bbox 기반이고 per-line matching 수행됨.
  /// p2IsComplete: P2 expected line 모두 매칭됨 (dangling 없음).
  ///   - true: completeness gate 통과
  ///   - false: missing lines / dangling / no spatial evidence
  ///
  /// p2SourceLabel: P2가 최종 선택될 때 반환할 source 식별자.
  ///   'LATIN_REGION_EXPECTED_LINES' — A.7 per-line matching 완전 매칭
  ///   'LATIN_REGION_NAME_ANCHOR'    — A.8 P2 local Name anchor rescue
  ///   'LATIN_REGION'               — A.6 union 기반 / generic fallback
  ///
  /// [Phase A.7.1] Arbitration 3-way:
  ///
  ///   Case A: p2HasSpatialInfo=true, p2IsComplete=true, confidence≥0.20
  ///           → P2 override (per-line 완전 매칭 + spatial 확인)
  ///             단, [A.8] P2 = [single letter] + P1 exact → P1 preserved.
  ///
  ///   Case B: p2HasSpatialInfo=false, fullOcrName==null
  ///           → P2 last-resort fallback (P1이 아무것도 못 찾음)
  ///
  ///   Case C: p2HasSpatialInfo=false, fullOcrName!=null  (P1 VALID + P2 NO SPATIAL)
  ///           → P1 유지 (공간 증거 없는 P2가 P1을 override하면 안 됨)
  ///           [A.7.1 핵심 수정]
  ///
  ///   모든 나머지 → P1 (또는 NONE)
  ///
  /// Returns (finalName, source, hadDiacritic)
  static (String?, String, bool) _selectFinalName({
    required String? fullOcrName,
    required bool fullOcrHadDiacritic,
    required String? latinRegionName,
    required double p2Confidence,
    required bool p2HasSpatialInfo,
    bool p2IsComplete = true,
    String p2SourceLabel = 'LATIN_REGION', // [A.8] default → 기존 경로 호환
  }) {
    const p2SpatialThreshold = 0.20;

    bool p2Accepted;
    if (latinRegionName == null || latinRegionName.isEmpty) {
      // P2 결과 없음
      p2Accepted = false;
    } else if (p2HasSpatialInfo) {
      // [Phase A.7] Spatial per-line matching 경로.
      // completeness gate + confidence threshold 모두 충족해야 P2 override.
      p2Accepted = p2IsComplete && p2Confidence >= p2SpatialThreshold;
    } else {
      // [Phase A.7.1] Spatial evidence 없는 fallback crop 경로.
      // P1 valid → P1 wins (spatial 증거 없는 P2가 P1을 override 불가).
      // P1 null  → P2 last-resort (P1이 이름을 전혀 못 찾은 경우만).
      p2Accepted = fullOcrName == null;
    }

    // [Phase A.8] P1/P2 단일 문자 prefix arbitration.
    // P2 = [single ASCII 대문자] + " " + P1 exact → P1 preserved.
    // 이유: 레이블 열 OCR bleed ("S NAM…") — 문자 삭제가 아닌 trusted P1 선택.
    // 보호: P1="S KUMAR", P2="S KUMAR" → p2.length < p1.length+2 → false (정상 경로).
    if (p2Accepted && fullOcrName != null && latinRegionName != null) {
      if (_p2HasSingleLetterPrefix(fullOcrName, latinRegionName)) {
        p2Accepted = false;
      }
    }

    if (p2Accepted) {
      final diff = fullOcrName != null && fullOcrName != latinRegionName;
      return (latinRegionName, p2SourceLabel, diff || fullOcrHadDiacritic);
    }
    if (fullOcrName != null) {
      return (fullOcrName, 'FULL_OCR', fullOcrHadDiacritic);
    }
    return (null, 'NONE', false);
  }

  /// [visibleForTesting] _selectFinalName 단위 테스트 진입점.
  ///
  /// p2IsComplete 기본값 true → A.6 기존 테스트 100% 호환.
  /// A.7 completeness gate: p2IsComplete: false 명시.
  /// A.7.1 no-spatial: p2HasSpatialInfo: false 명시 + p1 null 여부로 결정.
  /// A.8 source: p2SourceLabel 기본값 'LATIN_REGION' → 기존 테스트 호환.
  @visibleForTesting
  static (String?, String, bool) selectFinalNameForTesting({
    required String? fullOcrName,
    required bool fullOcrHadDiacritic,
    required String? latinRegionName,
    required double p2Confidence,
    required bool p2HasSpatialInfo,
    bool p2IsComplete = true,
    String p2SourceLabel = 'LATIN_REGION', // [A.8] default → 기존 테스트 호환
  }) =>
      _selectFinalName(
        fullOcrName: fullOcrName,
        fullOcrHadDiacritic: fullOcrHadDiacritic,
        latinRegionName: latinRegionName,
        p2Confidence: p2Confidence,
        p2HasSpatialInfo: p2HasSpatialInfo,
        p2IsComplete: p2IsComplete,
        p2SourceLabel: p2SourceLabel,
      );

  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// 이미지 파일 경로로 OCR 실행 (Two-pass).
  static Future<ForeignIdOcrResult> recognizeFromPath(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);

    // ── Pass 1: Full-card Korean OCR ──────────────────────────────────────
    final koreanRecognizer =
        TextRecognizer(script: TextRecognitionScript.korean);
    late RecognizedText fullOcrResult;
    try {
      fullOcrResult = await koreanRecognizer.processImage(inputImage);
    } finally {
      await koreanRecognizer.close();
    }

    // DEBUG: Full OCR raw blocks (등록번호 masking)
    if (kDebugMode) {
      debugPrint('');
      debugPrint('════════════════════════════════════════');
      debugPrint('[OCR P1] FULL-CARD KOREAN OCR RAW BLOCKS');
      debugPrint('════════════════════════════════════════');
      for (int bi = 0; bi < fullOcrResult.blocks.length; bi++) {
        final block = fullOcrResult.blocks[bi];
        debugPrint('BLOCK[$bi]:');
        for (int li = 0; li < block.lines.length; li++) {
          final masked = block.lines[li].text
              .replaceAll(RegExp(r'\d{6}[-–—\s]{0,3}\d{7}'), '******-*******');
          debugPrint('  LINE[$li]: "$masked"'
              '  bbox=${block.lines[li].boundingBox}');
        }
      }
      debugPrint('[END P1 BLOCKS]');
      debugPrint('');
    }

    // Pass 1 파싱: 등록번호/체류자격/만료일 + Full OCR name
    // _parse() 반환: (result, dbgRawName, rawNameLines)
    final (pass1, fullOcrRawName, rawNameLines) = _parse(fullOcrResult.text);

    // ── Pass 2: Name region Latin OCR ─────────────────────────────────────
    String? latinNormalized;
    String? latinRaw;
    bool p2Executed = false;
    bool cropGenerated = false;
    bool cropDimValid = false;
    double p2Confidence = 0.0;
    bool p2HasSpatialInfo = false;
    bool p2IsComplete = true; // [Phase A.7] completeness gate; default true (A.6 compat)
    String p2SourceLabel = 'LATIN_REGION'; // [Phase A.8] P2 wins 시 반환 source
    Rect? expectedNameRegion; // [Phase A.6] P2 local coords (union)
    List<Rect> p2ExpectedLineRegions = const []; // [Phase A.7] per-line regions

    try {
      // [Phase A.5 §16-18] P2 crop 우선순위:
      //   A. name candidate lines bbox union (rawNameLines 기반)
      //   B/C. anchor-derived fallback
      Rect? p2Region;
      List<Rect> nameBboxes = const [];
      String p2RegionSource = 'NONE';

      if (kDebugMode) {
        debugPrint('════════════════════════════════════════');
        debugPrint('[OCR P2] TWO-PASS LATIN OCR DIAGNOSTIC');
        debugPrint('════════════════════════════════════════');
        debugPrint('[OCR P2] rawNameLines: $rawNameLines');
      }

      if (rawNameLines.isNotEmpty) {
        // Priority A: candidate line bbox union
        nameBboxes = _findLineBboxes(fullOcrResult, rawNameLines);
        if (kDebugMode) {
          debugPrint('[OCR P2] NAME_LINES_BBOX: $nameBboxes (${nameBboxes.length}개)');
        }
        if (nameBboxes.isNotEmpty) {
          p2Region = _computeP2CropRect(nameBboxes, 99999, 99999); // image dims unknown here
          p2RegionSource = 'CANDIDATE_BBOX_UNION';
          p2HasSpatialInfo = true;
        }
      }

      if (p2Region == null) {
        // Priority B/C: anchor-derived fallback
        p2Region = _nameZoneRectFallback(fullOcrResult);
        p2RegionSource = p2Region != null ? 'ANCHOR_DERIVED_FALLBACK' : 'NONE';
        p2HasSpatialInfo = false;
      }

      // [Phase A.6/A.7] P2 local 좌표 변환.
      // _computeP2CropRect를 imageW=99999로 호출했으므로 p2Region.left/top은 이미 ≥0.
      if (p2Region != null && nameBboxes.isNotEmpty) {
        // [Phase A.6] union region (fallback scoring용)
        final union = _bboxUnion(nameBboxes);
        expectedNameRegion = Rect.fromLTRB(
          union.left - p2Region.left,
          union.top - p2Region.top,
          union.right - p2Region.left,
          union.bottom - p2Region.top,
        );
        // [Phase A.7] per-line regions (expected line matching용)
        final cropLeft = p2Region.left;
        final cropTop = p2Region.top;
        p2ExpectedLineRegions = nameBboxes
            .map((bbox) => Rect.fromLTRB(
                  bbox.left - cropLeft,
                  bbox.top - cropTop,
                  bbox.right - cropLeft,
                  bbox.bottom - cropTop,
                ))
            .toList();
      }
      if (kDebugMode) {
        debugPrint('[OCR P2] p2ExpectedLineRegions (${p2ExpectedLineRegions.length}개):');
        for (int i = 0; i < p2ExpectedLineRegions.length; i++) {
          debugPrint('  [$i] ${p2ExpectedLineRegions[i]}');
        }
      }

      if (kDebugMode) {
        debugPrint('[OCR P2] P2_REGION (source: $p2RegionSource): $p2Region');
        debugPrint('[OCR P2] expectedNameRegion (P2 local): $expectedNameRegion');
        debugPrint('[OCR P2] p2HasSpatialInfo: $p2HasSpatialInfo');
      }

      if (p2Region != null) {
        final cropPath = await _cropToTempFile(imagePath, p2Region);
        cropGenerated = cropPath != null;

        if (kDebugMode) {
          debugPrint('[OCR P2] CROP GENERATED: ${cropGenerated ? 'PASS' : 'FAIL'}');
        }

        if (cropPath != null) {
          cropDimValid = true;
          p2Executed = true;
          try {
            final latinRecognizer =
                TextRecognizer(script: TextRecognitionScript.latin);
            try {
              final latinOcr = await latinRecognizer.processImage(
                InputImage.fromFilePath(cropPath),
              );

              if (kDebugMode) {
                debugPrint('[OCR P2] LATIN OCR EXECUTED: YES');
                debugPrint('[OCR P2] LATIN REGION RAW BLOCKS:');
                for (int bi = 0; bi < latinOcr.blocks.length; bi++) {
                  debugPrint('  BLOCK[$bi]:');
                  for (int li = 0;
                      li < latinOcr.blocks[bi].lines.length;
                      li++) {
                    debugPrint(
                        '    LINE[$li]: "${latinOcr.blocks[bi].lines[li].text}"'
                        '  bbox=${latinOcr.blocks[bi].lines[li].boundingBox}');
                  }
                }
              }

              // [Phase A.7] per-line expected-line matching 우선; 없으면 A.6 union 기반
              if (p2ExpectedLineRegions.isNotEmpty) {
                // ── [Phase A.7] P1-Authoritative per-line matching ──────────
                final p2Lines = <(String, Rect)>[
                  for (final block in latinOcr.blocks)
                    for (final line in block.lines)
                      (line.text.trim(), line.boundingBox),
                ];

                if (kDebugMode) {
                  debugPrint('[OCR P2 A7] per-line matching'
                      ' (expectedLines: ${p2ExpectedLineRegions.length})');
                }

                final (matchedPairs, matchedCount) =
                    _matchP2ExpectedLines(p2Lines, p2ExpectedLineRegions);
                final (p2Assembled, isDangling) =
                    _assembleP2MatchedLines(matchedPairs);
                final expectedCount = p2ExpectedLineRegions.length;
                p2IsComplete = matchedCount >= expectedCount &&
                    matchedCount > 0 &&
                    !isDangling;

                // [Phase A.7.1] 선두 노이즈 제거는 _matchP2ExpectedLines 내부에서
                // geometry evidence 기반으로 완료됨. 여기서 추가 strip 금지.
                latinNormalized = p2Assembled;
                latinRaw = p2Assembled ?? '';
                // A.7 완전 매칭: confidence=1.0 → threshold(0.20) 자동 통과
                p2Confidence = p2IsComplete ? 1.0 : 0.0;
                p2SourceLabel = 'LATIN_REGION_EXPECTED_LINES'; // [A.8]

                if (kDebugMode) {
                  debugPrint('[OCR P2 A7] matchedCount: $matchedCount'
                      ' / expectedCount: $expectedCount');
                  debugPrint('[OCR P2 A7] isDangling: $isDangling');
                  debugPrint('[OCR P2 A7] p2IsComplete: $p2IsComplete');
                  debugPrint('[OCR P2 A7] p2Assembled (geometry noise strip 완료): '
                      '${p2Assembled != null ? '"$p2Assembled"' : "(none)"}');
                  debugPrint('[OCR P2 A7] latinNormalized (final): '
                      '${latinNormalized != null ? '"$latinNormalized"' : "(none)"}');
                }
              } else {
                // ── [Phase A.6/A.8] P2 fallback (no per-line bboxes) ────────

                if (expectedNameRegion != null) {
                  // [Phase A.6] P1 union region 존재 — 공간 overlap 스코어링
                  final (norm, raw, conf) =
                      _selectLatinNameSpatially(latinOcr, expectedNameRegion);
                  latinNormalized = norm;
                  latinRaw = raw;
                  p2Confidence = conf;
                  p2SourceLabel = 'LATIN_REGION';
                  if (kDebugMode) {
                    debugPrint('[OCR P2 A6] latinNormalizedCandidate: '
                        '${latinNormalized != null ? '"$latinNormalized"' : "(none)"}');
                    debugPrint('[OCR P2 A6] p2Confidence: '
                        '${p2Confidence.toStringAsFixed(3)}');
                  }
                } else {
                  // [Phase A.8] P1 region 없음 — Name anchor rescue만 허용.
                  // generic word-count fallback 금지 (wrong-autofill 방지).
                  final p2FallbackLines = <(String, Rect)>[
                    for (final block in latinOcr.blocks)
                      for (final line in block.lines)
                        (line.text.trim(), line.boundingBox),
                  ];
                  final (anchorNorm, anchorConf) =
                      _selectLatinNameByNameAnchor(p2FallbackLines);
                  latinNormalized = anchorNorm;
                  latinRaw = anchorNorm ?? '';
                  p2Confidence = anchorConf;
                  p2SourceLabel = anchorNorm != null
                      ? 'LATIN_REGION_NAME_ANCHOR'
                      : 'LATIN_REGION';
                  if (kDebugMode) {
                    debugPrint('[OCR P2 A8] Name anchor rescue: '
                        '${anchorNorm != null ? '"$anchorNorm"' : "(none)"}');
                  }
                }

                p2IsComplete = false; // [A.7.1] 공간 증거 없음 — P1 valid면 P1 유지
              }
            } finally {
              await latinRecognizer.close();
            }
          } finally {
            // 임시 파일 삭제 (CLAUDE.md TMP-01)
            File(cropPath)
                .delete()
                .catchError((Object _) => File(cropPath));
          }
        }
      }

      if (kDebugMode) debugPrint('[END P2]');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [OCR P2] 실패 → Full OCR fallback: $e');
      }
    }

    // ── Final name selection ───────────────────────────────────────────────
    final (finalName, nameSource, hadDiacritic) = _selectFinalName(
      fullOcrName: pass1.legalName,
      fullOcrHadDiacritic: pass1.legalNameHadDiacritic,
      latinRegionName: latinNormalized,
      p2Confidence: p2Confidence,
      p2HasSpatialInfo: p2HasSpatialInfo,
      p2IsComplete: p2IsComplete, // [Phase A.7]
      p2SourceLabel: p2SourceLabel, // [Phase A.8]
    );

    // DEBUG: FINAL SELECTION
    if (kDebugMode) {
      final rawId = pass1.foreignIdRaw;
      final maskedReg = rawId != null && rawId.length == 13
          ? '${rawId.substring(0, 6)}-${rawId[6]}******'
          : '(none)';
      debugPrint('');
      debugPrint('════════════════════════════════════════');
      debugPrint('[OCR FINAL SELECTION]');
      debugPrint('════════════════════════════════════════');
      debugPrint('fullOcrRawName: '
          '${fullOcrRawName.isNotEmpty ? '"$fullOcrRawName"' : '(not set)'}');
      debugPrint('fullOcrNormalizedName: ${pass1.legalName != null ? '"${pass1.legalName}"' : '(none)'}');
      debugPrint('latinRawName: ${latinRaw != null ? '"$latinRaw"' : '(none)'}');
      debugPrint('latinNormalizedName: ${latinNormalized != null ? '"$latinNormalized"' : '(none)'}');
      debugPrint('');
      debugPrint('P2 EXECUTED: ${p2Executed ? 'YES' : 'NO'}');
      debugPrint('CROP GENERATED: ${cropGenerated ? 'PASS' : 'FAIL'}');
      debugPrint('CROP DIMENSION VALID: ${cropDimValid ? 'PASS' : 'FAIL (≥32×32 required)'}');
      debugPrint('LATIN OCR EXECUTED: ${p2Executed ? 'YES' : 'NO'}');
      debugPrint('P2 HAS SPATIAL INFO: $p2HasSpatialInfo');
      debugPrint('P2 IS COMPLETE: $p2IsComplete');
      debugPrint('P2 CONFIDENCE: ${p2Confidence.toStringAsFixed(3)}');
      debugPrint('P2 SOURCE LABEL: $p2SourceLabel');
      debugPrint('');
      debugPrint('FINAL NAME: ${finalName != null ? '"$finalName"' : '(none)'}');
      debugPrint('FINAL SOURCE: $nameSource');
      debugPrint('');
      debugPrint('registrationCandidate: $maskedReg');
      debugPrint('visaType: ${pass1.visaType ?? "(none)"}');
      debugPrint('stayExpiryDate: ${pass1.stayExpiryDate ?? "(none)"}');
      debugPrint('[END FINAL SELECTION]');
      debugPrint('');
    }

    return pass1.copyWith(
      legalName: finalName,
      legalNameFailed: finalName == null,
      legalNameHadDiacritic: hadDiacritic,
      legalNameOcrSource: nameSource,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Internal parser (Full OCR text → ForeignIdOcrResult)
  // ──────────────────────────────────────────────────────────────────────────

  // [Phase A.5] _parse() returns (result, rawName, rawNameLines).
  //   - result: ForeignIdOcrResult (Full OCR pass)
  //   - rawName: 이름 raw 텍스트 (debug FINAL SELECTION 출력용)
  //   - rawNameLines: 이름 추출에 사용된 원본 라인들 (P2 crop bbox 탐색용)
  static (ForeignIdOcrResult, String, List<String>) _parse(String rawText) {
    final text = rawText.trim();

    String? legalName;
    String? foreignIdRaw;
    String? visaType;
    String? stayExpiryDate;
    bool legalNameHadDiacritic = false;
    final rawNameLines = <String>[];

    var dbgNameSrc  = 'NONE';
    var dbgRegSrc   = 'NONE';
    var dbgRawName  = '';
    final dbgRejected = <Map<String, String>>[];

    // ── 외국인등록번호 ──
    // [Phase A.5] 유연한 구분자: [-–—\s]{0,3} (하이픈+공백 2자 허용)
    final idMatch = _foreignIdPattern.firstMatch(text);
    if (idMatch != null) {
      foreignIdRaw = '${idMatch.group(1)}${idMatch.group(2)}';
      if (kDebugMode) dbgRegSrc = 'PRIMARY';
    } else {
      final confusionMatch = _foreignIdPatternConfusion.firstMatch(text);
      if (confusionMatch != null) {
        final front = (confusionMatch.group(1) ?? '').replaceAll('O', '0');
        final back = (confusionMatch.group(2) ?? '')
            .replaceAll('O', '0').replaceAll('I', '1').replaceAll('l', '1');
        if (RegExp(r'^\d{6}$').hasMatch(front) &&
            RegExp(r'^[5-9]\d{6}$').hasMatch(back)) {
          foreignIdRaw = '$front$back';
          if (kDebugMode) dbgRegSrc = 'CONFUSION';
        }
      }
    }

    // [A.10] Context-aware registration extraction:
    // 앞부분 6자리 내부에 공백이 있는 OCR 변형 처리 (예: "941 205-6760126").
    // 등록번호 레이블 인접 줄에서만 digit 추출 → 전역 digit concat 금지.
    if (foreignIdRaw == null) {
      final ctxLines = text.split(RegExp(r'[\n\r]+'));
      for (int i = 0; i < ctxLines.length; i++) {
        if (!_registrationLabelPattern.hasMatch(ctxLines[i])) continue;
        // 레이블 same line(offset=0) 및 바로 다음 line(offset=1) 검사
        for (var offset = 0; offset <= 1 && i + offset < ctxLines.length; offset++) {
          final digits =
              ctxLines[i + offset].replaceAll(RegExp(r'[^0-9]'), '');
          if (digits.length == 13 &&
              RegExp(r'^[5-9]').hasMatch(digits.substring(6))) {
            foreignIdRaw = digits;
            if (kDebugMode) dbgRegSrc = 'CONTEXT_SPACED';
            break;
          }
        }
        if (foreignIdRaw != null) break;
      }
    }

    // ── 체류자격 ──
    final visaMatch = _visaTypePattern.firstMatch(text);
    if (visaMatch != null) visaType = visaMatch.group(1);

    // ── 체류기간만료일 ──
    final expiryLabelMatch = _expiryAfterLabelPattern.firstMatch(text);
    if (expiryLabelMatch != null) {
      final y = expiryLabelMatch.group(1)!;
      final m = expiryLabelMatch.group(2)!.padLeft(2, '0');
      final d = expiryLabelMatch.group(3)!.padLeft(2, '0');
      stayExpiryDate = '$y-$m-$d';
    }

    // ── 성명 — semantic zone anchor 기반 ──────────────────────────────────
    //
    // [Phase A.5 개선]:
    //   1. Pre-look: anchor 직전 2줄에서 인라인 레이블 제거 후 Latin 콘텐츠 추출
    //      (CARD B: "명 NAM NATALIYA PON-" — Name anchor 직전 줄)
    //   2. Inline: anchor 라인에서 레이블 제거 후 동일 라인 값 추출
    //      (CARD B: "Name ENOVNA" → "ENOVNA")
    //   3. Forward: anchor 이후 최대 5줄 스캔 (field boundary에서 중단)
    //   4. 하이픈 체인 조합 후 다중 토큰 우선 선택
    //      (CARD C: 단일 토큰 "KORI"보다 2+ 토큰 "SUKHMINDER SINGH" 우선)

    final allLines = text.split(RegExp(r'[\n\r]+'));

    // [A.9/A.10] Context-aware visa normalization: Fi4 / F4 / F - 4 → F-X
    // context 증거 없이 전역 적용 금지.
    // [A.10] Extended context:
    //   same-line: 체류자격 | 자격 | 재외동포 | Status
    //   OR: 인접 줄(±1)에 "Status" 단독 등장
    if (visaType == null) {
      final visaCtxSameLinePattern =
          RegExp(r'(?:자격|재외동포|Status)', caseSensitive: false);
      final statusOnlyPattern = RegExp(r'^Status\s*$', caseSensitive: false);
      for (var ci = 0; ci < allLines.length; ci++) {
        final line = allLines[ci];
        final hasSameLineCtx = visaCtxSameLinePattern.hasMatch(line);
        final prevTrimmed = ci > 0 ? allLines[ci - 1].trim() : '';
        final nextTrimmed =
            ci + 1 < allLines.length ? allLines[ci + 1].trim() : '';
        final hasAdjacentStatus = statusOnlyPattern.hasMatch(prevTrimmed) ||
            statusOnlyPattern.hasMatch(nextTrimmed);
        if (!hasSameLineCtx && !hasAdjacentStatus) continue;
        final m = _visaContextFallbackPattern.firstMatch(line);
        if (m != null) {
          final letter = m.group(1)!.toUpperCase();
          final digits = m.group(2)!;
          visaType = '$letter-$digits';
          break;
        }
      }
    }

    anchorLoop:
    for (int ai = 0; ai < allLines.length; ai++) {
      final anchorLine = allLines[ai];
      if (!_nameLabelPattern.hasMatch(anchorLine)) continue;

      // anchor 라인에서 레이블 제거 후 inline 값
      final inlineRaw =
          anchorLine.replaceFirst(_nameLabelPattern, '').trim();

      // 프래그먼트 수집 (normalized, rawLine) 순서 리스트
      final fragments = <(String, String)>[];

      // 1. Pre-look: anchor 직전 최대 2줄
      for (int pi = max(0, ai - 2); pi < ai; pi++) {
        final rawLine = allLines[pi].trim();
        if (rawLine.isEmpty) continue;
        if (_fieldBoundaryPattern.hasMatch(rawLine)) continue;
        final stripped = _stripNameLabelAndKorean(rawLine);
        if (stripped.isEmpty) continue;
        final norm = normalizeForeignLatinName(stripped);
        if (_isValidNameNormalized(norm)) {
          fragments.add((norm, rawLine));
        } else {
          if (kDebugMode) {
            dbgRejected.add({'text': rawLine, 'reason': 'prelook:invalid'});
          }
        }
      }

      // 2. Inline: anchor 라인 레이블 이후 값
      var inlineFragmentAdded = false; // [A.9]
      if (inlineRaw.isNotEmpty) {
        final norm = normalizeForeignLatinName(inlineRaw);
        if (_isValidNameNormalized(norm)) {
          fragments.add((norm, anchorLine));
          inlineFragmentAdded = true; // [A.9] inline 성공 → forward scan skip
        } else {
          if (kDebugMode) {
            dbgRejected.add({'text': inlineRaw, 'reason': 'inline:invalid'});
          }
        }
      }

      // 3. Forward: anchor 이후 최대 5줄
      // [A.9] inline에서 유효한 이름을 이미 찾았으면 forward scan skip.
      // (예: "성명BAI YUEE" → inline "BAI YUEE" 성공 후 "CHINA P. R." 수집 방지)
      if (!inlineFragmentAdded) {
        for (int fi = ai + 1; fi < allLines.length && fi <= ai + 5; fi++) {
          final rawLine = allLines[fi].trim();
          if (rawLine.isEmpty) continue;
          if (_fieldBoundaryPattern.hasMatch(rawLine)) break;

          final stripped = _stripNameLabelAndKorean(rawLine);
          final norm = normalizeForeignLatinName(
              stripped.isNotEmpty ? stripped : rawLine);
          if (_isValidNameNormalized(norm)) {
            fragments.add((norm, rawLine));
          } else {
            if (kDebugMode) {
              dbgRejected.add({'text': rawLine, 'reason': 'forward:invalid'});
            }
          }
        }
      }

      if (fragments.isEmpty) continue;

      // 하이픈 체인 조합 → candidate 리스트
      final candidates = _assembleNameFragments(fragments);
      if (candidates.isEmpty) continue;

      // 다중 토큰 우선 정렬 (CARD C: KORI 1토큰 < SUKHMINDER SINGH 2토큰)
      candidates.sort((a, b) => _wordCount(b.$1).compareTo(_wordCount(a.$1)));

      final best = candidates.first;
      legalName = best.$1;
      legalNameHadDiacritic = best.$2;
      rawNameLines.addAll(best.$3);

      if (kDebugMode) {
        dbgNameSrc = 'ANCHOR';
        // dbgRawName: contributing rawLines에서 diacritic 포함 줄 우선
        dbgRawName = best.$3.firstWhere(
          (r) => r.contains(RegExp(r'[À-ỿ]')),
          orElse: () => best.$3.isNotEmpty ? best.$3.first : '',
        );
      }
      break anchorLoop;
    }

    // ── 성명 — 라틴 대문자 fallback ──────────────────────────────────────
    if (legalName == null) {
      final excludedFromFallback = <String>{};
      for (int i = 0; i < allLines.length - 1; i++) {
        if (_nationalityLabelPattern.hasMatch(allLines[i])) {
          final next = normalizeForeignLatinName(allLines[i + 1].trim());
          if (next.isNotEmpty) excludedFromFallback.add(next);
        }
      }

      for (final m in _latinNamePattern.allMatches(text)) {
        final rawCandidate = m.group(1)?.trim() ?? '';
        if (rawCandidate.isEmpty) continue;

        final candidate = normalizeForeignLatinName(rawCandidate);

        if (candidate.length < 4) {
          if (kDebugMode) dbgRejected.add({'text': rawCandidate, 'reason': 'fallback:too_short'});
          continue;
        }
        if (_foreignIdPattern.hasMatch(candidate)) {
          if (kDebugMode) dbgRejected.add({'text': rawCandidate, 'reason': 'fallback:looks_like_id'});
          continue;
        }
        if (_visaTypePattern.hasMatch(candidate)) {
          if (kDebugMode) dbgRejected.add({'text': rawCandidate, 'reason': 'fallback:looks_like_visa'});
          continue;
        }
        if (_nameLabelKeywords.contains(candidate)) {
          if (kDebugMode) dbgRejected.add({'text': rawCandidate, 'reason': 'fallback:label_keyword'});
          continue;
        }
        if (_isCardBoilerplate(candidate)) {
          if (kDebugMode) dbgRejected.add({'text': rawCandidate, 'reason': 'fallback:boilerplate'});
          continue;
        }
        if (excludedFromFallback.contains(candidate)) {
          if (kDebugMode) dbgRejected.add({'text': rawCandidate, 'reason': 'fallback:nationality_label_next'});
          continue;
        }

        String finalCandidate = candidate;
        if (finalCandidate.endsWith('-')) {
          final afterPos = text.indexOf(rawCandidate) + rawCandidate.length;
          if (afterPos < text.length) {
            final rest = text.substring(afterPos);
            final contMatch =
                RegExp(r'^[ \t]*[\n\r]+([A-Za-zÀ-ỿ][A-Za-zÀ-ỿ \-]{1,40})')
                    .firstMatch(rest);
            if (contMatch != null) {
              final cont = normalizeForeignLatinName(contMatch.group(1)!.trim());
              if (cont.isNotEmpty &&
                  !_isCardBoilerplate(cont) &&
                  !_nameLabelKeywords.contains(cont) &&
                  !excludedFromFallback.contains(cont)) {
                finalCandidate = finalCandidate + cont;
              }
            }
          }
        }

        // [Phase A.5 §10] doc-wide fallback: 단일 단어 → null (LOW confidence)
        // wrong autofill보다 NONE 우선. anchor zone 밖에서 single token은 신뢰도 낮음.
        if (_wordCount(finalCandidate) < 2) {
          if (kDebugMode) {
            dbgRejected.add({
              'text': rawCandidate,
              'reason': 'fallback:single_token_low_confidence',
            });
          }
          continue;
        }

        legalName = finalCandidate;
        // [Phase A.5 closure] diacritic flag는 실제 accent/extended-Latin 문자가
        // 정규화된 경우에만 true. 단순 대소문자 변환·공백 정규화는 해당 없음.
        legalNameHadDiacritic = rawCandidate.contains(RegExp(r'[À-ỿ]'));
        rawNameLines.add(rawCandidate);
        if (kDebugMode) {
          dbgNameSrc = 'FALLBACK';
          dbgRawName = rawCandidate;
        }
        break;
      }
    }

    // ── Parser I/O 디버그 출력 ──────────────────────────────────────────────
    if (kDebugMode) {
      debugPrint('=== OCR PARSER (pass1) ===');
      if (dbgRawName.isNotEmpty && dbgRawName != legalName) {
        debugPrint('  rawNameCandidate: $dbgRawName');
        debugPrint('  normalizedNameCandidate: ${legalName ?? "(none)"}');
      } else {
        debugPrint('  nameCandidate: ${legalName ?? "(none)"}');
      }
      debugPrint('  nameCandidateSource: $dbgNameSrc');
      debugPrint('  legalNameHadDiacritic: $legalNameHadDiacritic');
      debugPrint('  rawNameLines: $rawNameLines');
      final rawId = foreignIdRaw;
      final maskedReg = rawId != null && rawId.length == 13
          ? '${rawId.substring(0, 6)}-${rawId[6]}******'
          : '(none)';
      debugPrint('  registrationCandidate: $maskedReg');
      debugPrint('  registrationSource: $dbgRegSrc');
      debugPrint('  visaType: ${visaType ?? "(none)"}');
      debugPrint('  stayExpiryDate: ${stayExpiryDate ?? "(none)"}');
      if (dbgRejected.isNotEmpty) {
        debugPrint('  rejectedNameCandidates:');
        for (final r in dbgRejected) {
          debugPrint('    { text: "${r['text']}", reason: ${r['reason']} }');
        }
      }
      debugPrint('=== END OCR PARSER ===');
    }

    return (
      ForeignIdOcrResult(
        legalName: legalName,
        foreignIdRaw: foreignIdRaw,
        visaType: visaType,
        stayExpiryDate: stayExpiryDate,
        legalNameFailed: legalName == null,
        foreignIdFailed: foreignIdRaw == null,
        visaTypeFailed: visaType == null,
        stayExpiryFailed: stayExpiryDate == null,
        legalNameHadDiacritic: legalNameHadDiacritic,
        legalNameOcrSource: legalName != null ? 'FULL_OCR' : 'NONE',
      ),
      dbgRawName,
      List<String>.unmodifiable(rawNameLines),
    );
  }

  /// 테스트 전용 production parser 직접 호출 진입점.
  @visibleForTesting
  static ForeignIdOcrResult parseForTesting(String rawText) => _parse(rawText).$1;

  // ──────────────────────────────────────────────────────────────────────────
  // [Phase A.6] 필드 레이블 퍼지 분류 / P2 공간 기반 후보 선택
  // ──────────────────────────────────────────────────────────────────────────

  /// [Phase A.6] 카드 필드 레이블 퍼지 사전.
  /// OCR 오타가 있어도 edit-distance 기반으로 감지.
  /// 이름 교정이 아닌 rejection 전용.
  static const _fieldLabelDictionary = [
    'REGISTRATION NO',
    'COUNTRY REGION',
    'COUNTRY / REGION',
    'ISSUE DATE',
    'EXPIRY DATE',
    'STATUS',
    'RESIDENCE CARD',
    'IMMIGRATION OFFICE',
    'ALIEN REGISTRATION',
    'REGISTRATION',
  ];

  /// [Phase A.6] Levenshtein edit distance.
  static int _editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final prev = List<int>.generate(b.length + 1, (i) => i);
    final curr = List<int>.filled(b.length + 1, 0);
    for (int i = 0; i < a.length; i++) {
      curr[0] = i + 1;
      for (int j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;
        final del = curr[j] + 1;
        final ins = prev[j + 1] + 1;
        final sub = prev[j] + cost;
        curr[j + 1] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      prev.setAll(0, curr);
    }
    return prev[b.length];
  }

  /// [Phase A.6] 필드 레이블처럼 보이는 candidate 차단.
  ///
  /// OCR 오타 허용 임계값: 길이 ≤15 → 최대 2 오류, >15 → 최대 3 오류.
  /// "REGISIRATION NO" (edit=1 vs "REGISTRATION NO") → true (CARD A 수정).
  static bool _isFieldLabelLike(String normalized) {
    final len = normalized.length;
    if (len < 4 || len > 30) return false;
    final threshold = len <= 15 ? 2 : 3;
    return _fieldLabelDictionary.any((label) {
      // 길이 차이가 임계값+2 초과이면 빠른 제외
      if ((len - label.length).abs() > threshold + 2) return false;
      return _editDistance(normalized, label) <= threshold;
    });
  }

  /// [Phase A.6] overlap fraction: candidate bbox ∩ expected / candidate area.
  static double _computeOverlapFraction(Rect candidate, Rect expected) {
    final il = candidate.left > expected.left ? candidate.left : expected.left;
    final it = candidate.top > expected.top ? candidate.top : expected.top;
    final ir = candidate.right < expected.right ? candidate.right : expected.right;
    final ib = candidate.bottom < expected.bottom ? candidate.bottom : expected.bottom;
    if (ir <= il || ib <= it) return 0.0;
    final intersection = (ir - il) * (ib - it);
    final cArea = candidate.width * candidate.height;
    if (cArea <= 0) return 0.0;
    return intersection / cArea;
  }

  /// [Phase A.6] P2 후보 공간 기반 스코어링 — 테스트 가능 단위.
  ///
  /// 입력: [(rawText, bbox)] 순서 리스트, expectedNameRegion (P2 local coords).
  /// 출력: (normalizedName, rawText, confidence).
  ///
  /// expectedNameRegion이 null이면 word-count 기반 점수만 사용 (fallback crop).
  static (String?, String?, double) _scoreCandidates(
    List<(String rawText, Rect bbox)> lines,
    Rect? expectedNameRegion,
  ) {
    String? bestName;
    String? bestRaw;
    double bestScore = -1;

    for (final (rawLine, bbox) in lines) {
      if (rawLine.isEmpty) continue;
      final candidate = normalizeForeignLatinName(rawLine);
      if (!_isValidNameNormalized(candidate)) {
        if (kDebugMode) {
          debugPrint('[OCR P2 SPATIAL] REJECTED: "$candidate" reason=invalid bbox=$bbox');
        }
        continue;
      }

      double score;
      if (expectedNameRegion != null) {
        final overlap = _computeOverlapFraction(bbox, expectedNameRegion);
        // 공간 점수: overlap fraction + 다중 토큰 소폭 보너스
        score = overlap + (_wordCount(candidate) >= 2 ? 0.05 : 0.0);
      } else {
        // expectedRegion 없음 (fallback crop): word count 기반
        score = _wordCount(candidate) >= 2 ? 0.5 : 0.3;
      }

      if (kDebugMode) {
        debugPrint('[OCR P2 SPATIAL] candidate: "$candidate"'
            ' bbox=$bbox expectedRegion=$expectedNameRegion'
            ' score=${score.toStringAsFixed(3)}');
      }

      if (score > bestScore) {
        bestScore = score;
        bestName = candidate;
        bestRaw = rawLine;
      }
    }

    if (kDebugMode) {
      debugPrint('[OCR P2 SPATIAL] SELECTED: '
          '${bestName != null ? '"$bestName"' : "(none)"}'
          ' confidence=${bestScore.toStringAsFixed(3)}');
    }
    return (bestName, bestRaw, bestScore < 0 ? 0.0 : bestScore);
  }

  /// [Phase A.6] P2 Latin OCR RecognizedText에서 공간 기반 이름 선택.
  static (String?, String?, double) _selectLatinNameSpatially(
    RecognizedText p2Ocr,
    Rect? expectedNameRegion,
  ) {
    final lines = <(String, Rect)>[
      for (final block in p2Ocr.blocks)
        for (final line in block.lines)
          (line.text.trim(), line.boundingBox),
    ];
    return _scoreCandidates(lines, expectedNameRegion);
  }

  /// [visibleForTesting] P2 공간 후보 선택 — 단위 테스트 진입점.
  @visibleForTesting
  static (String?, String?, double) selectP2CandidatesForTesting(
    List<(String rawText, Rect bbox)> lines,
    Rect? expectedNameRegion,
  ) =>
      _scoreCandidates(lines, expectedNameRegion);

  // ──────────────────────────────────────────────────────────────────────────
  // [Phase A.8] P2 Name Anchor Rescue + P1/P2 Single-Letter Arbitration
  // ──────────────────────────────────────────────────────────────────────────

  /// [Phase A.8] P2 crop 내 "Name" field label 텍스트 여부 확인.
  ///
  /// 보수적 매칭 — 정확한 "Name" / "성명" / "이름"만 허용 (fuzzy 금지).
  static bool _isNameLabelP2(String rawText) {
    final upper = rawText.trim().toUpperCase();
    return upper == 'NAME' || upper == '성명' || upper == '이름';
  }

  /// [Phase A.8] 두 Rect의 수직(vertical) overlap 비율 — candidate 높이 기준.
  ///
  /// 반환: 0.0 (overlap 없음) ~ 1.0 (완전 포함).
  static double _verticalOverlapFraction(Rect candidate, Rect reference) {
    final overlapTop =
        candidate.top > reference.top ? candidate.top : reference.top;
    final overlapBottom =
        candidate.bottom < reference.bottom ? candidate.bottom : reference.bottom;
    if (overlapBottom <= overlapTop) return 0.0;
    final candidateHeight = candidate.bottom - candidate.top;
    if (candidateHeight <= 0) return 0.0;
    return (overlapBottom - overlapTop) / candidateHeight;
  }

  /// [Phase A.8] P2 crop 내 "Name" label anchor 기반 이름 후보 선택.
  ///
  /// P1이 이름 bbox를 제공하지 못했을 때(expectedNameRegion=null),
  /// P2 crop 안의 "Name" 레이블을 anchor로 삼아 수직 band 인접 + 오른쪽 Latin 후보를 선택.
  ///
  /// CARD A 예:
  ///   "on No." → top<label.top, overlap=0 → 제외
  ///   "Name"   → 레이블 자체 → skip
  ///   "VU NGUYEN TRUONG" → vertOverlap=0.16 > 0, bbox.left=67 ≥ label.left=2 → 선택
  ///
  /// generic document-order 또는 word-count fallback 금지 — anchor 없으면 (null, 0.0).
  static (String?, double) _selectLatinNameByNameAnchor(
    List<(String rawText, Rect bbox)> p2Lines,
  ) {
    // Step 1: "Name" 레이블 bbox 탐색
    Rect? nameLabelBbox;
    for (final (text, bbox) in p2Lines) {
      if (_isNameLabelP2(text)) {
        nameLabelBbox = bbox;
        break;
      }
    }
    if (nameLabelBbox == null) return (null, 0.0);

    // Step 2: 레이블 기준 공간 인접 이름 후보 수집
    final candidates = <(String norm, double score)>[];
    for (final (rawText, bbox) in p2Lines) {
      if (_isNameLabelP2(rawText)) continue; // 레이블 자체 제외

      // 공간 조건: 수직 overlap > 0 + 레이블 오른쪽
      final vertOverlap = _verticalOverlapFraction(bbox, nameLabelBbox);
      if (vertOverlap <= 0.0) continue;
      if (bbox.left < nameLabelBbox.left) continue;

      // 텍스트 정규화 및 유효성
      final stripped = _stripNameLabelAndKorean(rawText.trim());
      final norm = normalizeForeignLatinName(
        stripped.isNotEmpty ? stripped : rawText.trim(),
      );
      if (!_isValidNameNormalized(norm)) continue;
      if (_isFieldLabelLike(norm)) continue;

      // 점수: verticalOverlap × wordCount 보너스
      final wc = _wordCount(norm);
      final score = vertOverlap * (wc >= 2 ? 1.0 : 0.7);
      candidates.add((norm, score));

      if (kDebugMode) {
        debugPrint('[OCR P2 A8 ANCHOR] candidate: "$norm"'
            ' vertOverlap=${vertOverlap.toStringAsFixed(3)}'
            ' score=${score.toStringAsFixed(3)}');
      }
    }

    if (candidates.isEmpty) return (null, 0.0);

    // Step 3: 점수 내림차순 → 동점 시 word count 내림차순
    candidates.sort((a, b) {
      final scoreDiff = b.$2.compareTo(a.$2);
      if (scoreDiff != 0) return scoreDiff;
      return _wordCount(b.$1).compareTo(_wordCount(a.$1));
    });

    final best = candidates[0];
    if (kDebugMode) {
      debugPrint('[OCR P2 A8 ANCHOR] selected: "${best.$1}"'
          ' conf=${best.$2.toStringAsFixed(3)}');
    }
    return (best.$1, best.$2);
  }

  /// [visibleForTesting] _selectLatinNameByNameAnchor 단위 테스트 진입점.
  @visibleForTesting
  static (String?, double) selectLatinNameByNameAnchorForTesting(
    List<(String rawText, Rect bbox)> p2Lines,
  ) =>
      _selectLatinNameByNameAnchor(p2Lines);

  /// [Phase A.8] P2 단일 문자 prefix arbitration 확인.
  ///
  /// P2 = [single ASCII 대문자] + " " + P1 exact인지 검사.
  ///
  /// 조건:
  ///   - P1 ≥ 2 tokens (단일 토큰 P1은 arbitration 대상 아님 — 이니셜 보호)
  ///   - P2 첫 글자 = 단일 대문자 + 공백 + P1 그대로
  ///
  /// 예:
  ///   P1="NAM NATALIYA PON-ENOVNA", P2="S NAM NATALIYA PON-ENOVNA" → true (P1 preserved)
  ///   P1="S KUMAR",  P2="S KUMAR"  → false (p2.length < p1.length+2 — 정상 경로)
  ///   P1="SUKHMINDER SINGH", P2="SUKHMINDER SINGH" → false (firstSpace≠1)
  static bool _p2HasSingleLetterPrefix(String p1, String p2) {
    if (_wordCount(p1) < 2) return false; // 단일 토큰 P1은 arbitration 제외
    if (p2.length < p1.length + 2) return false; // "X " + p1 최소 길이
    final firstSpace = p2.indexOf(' ');
    if (firstSpace != 1) return false; // prefix 정확히 1글자
    if (!RegExp(r'^[A-Z]$').hasMatch(p2.substring(0, 1))) return false;
    return p2.substring(2) == p1;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // [Phase A.7] P2 Expected Line Matching — P1 authority 기반 per-line 매칭
  // ──────────────────────────────────────────────────────────────────────────

  /// [Phase A.7] P2 expected line matching.
  ///
  /// P1 이름 라인별 bbox(P2 local coords)를 기준으로, 각 expected region에
  /// overlap이 가장 높은 P2 TextLine을 매칭.
  ///
  /// overlap threshold(15%) 미달 시 해당 expected line은 매칭 없음.
  /// 레이블 제거 후 _isValidNameNormalized() 검증 필수.
  ///
  /// Returns: (matchedPairs [(normalized, raw)], matchedCount)
  /// [Phase A.7/A.7.1] P2 expected line matching.
  ///
  /// P1 이름 라인별 bbox(P2 local coords)를 기준으로, 각 expected region에
  /// overlap이 가장 높은 P2 TextLine을 매칭.
  ///
  /// [Phase A.7.1] 선두 단일문자 노이즈 제거는 GEOMETRY EVIDENCE 기반:
  ///   - line bbox.left < expected.left - expected.height*0.5 이면 label column 침범
  ///   - 해당 경우에만 "_stripLeadingOcrNoise" 적용
  ///   - bbox.left ≥ expected.left - expected.height*0.5 이면 legitimate initial 보존
  static (List<(String, String)>, int) _matchP2ExpectedLines(
    List<(String rawText, Rect bbox)> p2Lines,
    List<Rect> expectedLineRegions,
  ) {
    const overlapThreshold = 0.15; // 15% overlap = 해당 영역 line으로 인정
    final matched = <(String, String)?>[]; // expected line당 1 slot

    for (final expected in expectedLineRegions) {
      String? bestNorm;
      String? bestRaw;
      Rect? bestBbox; // [Phase A.7.1] geometry-based 노이즈 제거용
      double bestOverlap = overlapThreshold;

      for (final (rawLine, bbox) in p2Lines) {
        final trimmed = rawLine.trim();
        if (trimmed.isEmpty) continue;
        final overlap = _computeOverlapFraction(bbox, expected);
        if (overlap < bestOverlap) continue;

        final stripped = _stripNameLabelAndKorean(trimmed);
        final candidate =
            normalizeForeignLatinName(stripped.isNotEmpty ? stripped : trimmed);
        if (!_isValidNameNormalized(candidate)) {
          if (kDebugMode) {
            debugPrint('[OCR P2 A7] LINE-MATCH REJECT:'
                ' "$candidate" overlap=${overlap.toStringAsFixed(3)}'
                ' reason=invalid bbox=$bbox expected=$expected');
          }
          continue;
        }

        if (kDebugMode) {
          debugPrint('[OCR P2 A7] LINE-MATCH ACCEPT:'
              ' "$candidate" overlap=${overlap.toStringAsFixed(3)}'
              ' bbox=$bbox expected=$expected');
        }
        bestOverlap = overlap;
        bestNorm = candidate;
        bestRaw = trimmed;
        bestBbox = bbox;
      }

      if (bestNorm != null && bestBbox != null) {
        // [Phase A.7.1] Geometry-based 선두 단일문자 노이즈 제거.
        //
        // 조건: line bbox left가 expected region left보다 expected.height*0.5 이상
        //       왼쪽에 위치 → 레이블 컬럼 영역에 걸침 → leading artifact 제거 가능.
        //
        // "S NAM NATALIYA PON-": bbox.left=0, expected.left=65 →
        //   overhang=65 > height(37)*0.5=18.5 → strip "S"
        //
        // "S KUMAR" 합법적 initial: bbox.left=65, expected.left=65 →
        //   overhang=0 ≤ 18.5 → 보존
        var finalNorm = bestNorm;
        final leftOverhang = expected.left - bestBbox.left;
        final heightThreshold = expected.height * 0.5;
        if (leftOverhang > heightThreshold) {
          final stripped = _stripLeadingOcrNoise(finalNorm);
          if (stripped != null) {
            if (kDebugMode) {
              debugPrint('[OCR P2 A7.1] LABEL-GEOMETRY NOISE STRIP:'
                  ' "$finalNorm" → "$stripped"'
                  ' (overhang=${leftOverhang.toStringAsFixed(1)}'
                  ' threshold=${heightThreshold.toStringAsFixed(1)})');
            }
            finalNorm = stripped;
          }
        }
        matched.add((finalNorm, bestRaw!));
      } else {
        matched.add(null);
      }
    }

    if (kDebugMode) {
      for (int i = 0; i < matched.length; i++) {
        final m = matched[i];
        debugPrint('[OCR P2 A7] SLOT[$i]: '
            '${m != null ? '"${m.$1}"' : "(no match)"}');
      }
    }

    final found = matched.whereType<(String, String)>().toList();
    return (found, found.length);
  }

  /// [Phase A.7.1] 선두 단일문자 OCR 노이즈 후보 제거 — GEOMETRY EVIDENCE 필요.
  ///
  /// GEOMETRY CHECK 통과 후에만 호출 (_matchP2ExpectedLines 내부 전용).
  /// "S NAM NATALIYA PON-" → "NAM NATALIYA PON-"
  /// 단: 나머지가 2토큰 이상이고 _isValidNameNormalized() 통과해야 함.
  ///
  /// ⚠️ 이 함수를 geometry 없이 직접 호출 금지.
  ///    합법적 initial(S KUMAR, A JOHN)은 호출 전 bbox 검사에서 걸러짐.
  static String? _stripLeadingOcrNoise(String candidate) {
    final m = RegExp(r'^([A-Z]) (.+)$').firstMatch(candidate);
    if (m == null) return null;
    final rest = m.group(2)!;
    if (_wordCount(rest) >= 2 && _isValidNameNormalized(rest)) return rest;
    return null;
  }

  /// [Phase A.7] 매칭된 P2 라인 하이픈 체인 조합 + dangling 판정.
  ///
  /// 입력: expected line 순서의 [(normalized, raw)] 리스트.
  /// 완성된 체인 우선(dangling 없음), 모두 dangling이면 isDangling=true.
  ///
  /// Returns: (assembledName, isDangling)
  static (String?, bool) _assembleP2MatchedLines(
      List<(String, String)> matches) {
    if (matches.isEmpty) return (null, false);

    final assembled = _assembleNameFragments(matches);
    if (assembled.isEmpty) return (null, false);

    // dangling 없는 후보 우선 (완성된 이름)
    final complete = assembled.where((c) => !c.$1.endsWith('-')).toList();
    if (complete.isNotEmpty) {
      complete.sort((a, b) => _wordCount(b.$1).compareTo(_wordCount(a.$1)));
      return (complete.first.$1, false);
    }

    // 모두 dangling (last expected line 미매칭으로 마지막 하이픈 미연결)
    assembled.sort((a, b) => _wordCount(b.$1).compareTo(_wordCount(a.$1)));
    return (assembled.first.$1, true); // isDangling=true
  }

  /// [Phase A.7/A.7.1] @visibleForTesting — P2 expected line matching 단위 테스트 진입점.
  ///
  /// 반환: (assembledName, matchedLineCount, expectedLineCount, isDangling)
  ///
  /// 선두 단일문자 geometry-based 노이즈 제거는 _matchP2ExpectedLines 내부에서 처리.
  /// (bbox.left < expected.left - expected.height*0.5 조건 충족 시에만 제거)
  ///
  /// 호출자는 completeness를 직접 검증:
  ///   p2IsComplete = (matchedCount == expectedCount) && !isDangling && matchedCount > 0
  @visibleForTesting
  static (String?, int, int, bool) matchP2LinesForTesting(
    List<(String rawText, Rect bbox)> p2Lines,
    List<Rect> expectedLineRegions,
  ) {
    final (matchedPairs, matchedCount) =
        _matchP2ExpectedLines(p2Lines, expectedLineRegions);
    final (assembled, isDangling) = _assembleP2MatchedLines(matchedPairs);
    // geometry-based 노이즈 제거는 _matchP2ExpectedLines에서 완료됨
    return (assembled, matchedCount, expectedLineRegions.length, isDangling);
  }

  static bool _isCardBoilerplate(String s) {
    const boilerplate = [
      // 국가/기관
      'REPUBLIC', 'KOREA', 'MINISTRY', 'JUSTICE', 'ALIEN',
      'IMMIGRATION', 'CHIEF', 'OFFICE', 'BRANCH',
      // 카드 종류
      'REGISTRATION', 'CARD', 'SOJOURN',
      'OVERSEAS', 'RESIDENT', 'RESIDENCE',
      // 이름 레이블 (정규화 후 비교)
      'NAME', 'NAMES',
      // 국가/지역 레이블
      'COUNTRY', 'REGION',
      // 상태
      'STATUS',
      // 날짜 레이블 — field-label이 fallback candidate로 올라오는 것 차단
      // 'ISSUE'는 ISSUE DATE / 발급일자 차단, 'PERIOD'는 Period of Sojourn 차단
      'ISSUE', 'PERIOD',
      // [Phase A.5 closure] Expiry 계열 — "Expiry Date" → EXPIRY DATE가
      // legalName fallback으로 올라오는 false positive 차단
      'EXPIRY',
    ];
    return boilerplate.any((w) => s.contains(w));
  }
}
