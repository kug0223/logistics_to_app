import 'dart:async';
import 'dart:isolate';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_font_cache.dart';

/// [PERF impl_19 · 판정291 §4] 무거운 생성(PDF · xlsx)을 **메인 isolate 밖**에서 돌리는 공용 부품.
///
///   impl_17 계약서 빌더의 offMain 경로와 같은 규칙을 한 곳에 모은 것이다(계약서 빌더 자체는 그대로 —
///   그 이름을 여기 적지 않는 것은 '계약서 생성 지점 1곳' 계약 시험이 lib 문자열을 세기 때문이다).
///   · 결과는 같다 — 같은 함수가 같은 인자로 돈다(시험이 PDF 바이트 · xlsx 되읽기 값으로 비교한다).
///   · isolate 를 쓸 수 없거나(웹) 보낼 수 없는 값 · isolate 실패 · 시간 초과면 **이 isolate 에서** 예전과
///     똑같이 만든다 — 결과가 사라지지 않는다. 시간 초과 뒤 저쪽 계산은 취소되지 않는다(버려진다).
///   · isolate 로 넘기는 closure 는 **이 파일의 static 함수 안에서만** 만든다. 화면 State 메서드 안에서
///     만든 closure 는 `this`(위젯 트리)를 함께 잡아 보내지 못하거나 통째로 복사하려 든다.
///   · PDF 폰트: 번들 읽기(rootBundle)는 이 isolate 에서만 된다 → [PdfFontCache.loadBytes] 로 원본 바이트를
///     **차례로** 읽어 넘기고(번들 읽기가 SynchronousFuture 일 때 `Future.wait` 가 값을 놓친다 · PF-5),
///     해석(`pw.Font.ttf`)은 저쪽에서 한다.
class OffMain {
  OffMain._();

  static const Duration defaultTimeout = Duration(seconds: 20);

  /// 마지막 실행 경로 — 시험이 "정말 다른 isolate 에서 돌았는가"를 본다. `isolate` · `main` · `main-fallback`.
  @visibleForTesting
  static String? debugLastPath;

  /// [compute] 를 다른 isolate 에서 돌리고, 못 하면 이 isolate 에서 돌린다.
  ///   [compute] 는 보낼 수 있는 값만 잡아야 한다(호출자는 static 함수 안에서 만든다).
  static Future<T> run<T>(
    String tag,
    FutureOr<T> Function() compute, {
    bool enabled = true,
    Duration timeout = defaultTimeout,
  }) async {
    if (!enabled || kIsWeb) {
      debugLastPath = 'main';
      return await compute();
    }
    try {
      final r = await Isolate.run<T>(compute).timeout(timeout);
      debugLastPath = 'isolate';
      return r;
    } catch (e) {
      debugPrint('⚠️ [OffMain:$tag] 별도 isolate 실패 — 이 isolate 에서 만든다: $e');
      debugLastPath = 'main-fallback';
      return await compute();
    }
  }

  /// xlsx 인코딩(가장 무거운 단계 — XML 생성 + zip)만 넘긴다. 시트 채우기는 호출자가 이미 끝낸 상태.
  ///   closure 가 [excel] 하나만 잡도록 여기서 만든다.
  static Future<List<int>?> encodeExcel(Excel excel, {String tag = 'xlsx', bool enabled = true}) =>
      run<List<int>?>(tag, () => excel.encode(), enabled: enabled);

  /// 한글 폰트 2종으로 PDF 를 만든다. [build] 는 (regular, bold) 를 받아 문서 바이트를 돌려준다.
  ///   [offMain] false 거나 웹이면 예전처럼 이 isolate 의 세션 캐시 폰트([PdfFontCache.regular]/[bold])로 만든다.
  static Future<Uint8List> buildPdf(
    String tag,
    Future<Uint8List> Function(pw.Font regular, pw.Font bold) build, {
    bool offMain = false,
    Duration timeout = defaultTimeout,
  }) async {
    Future<Uint8List> here() async {
      final regular = await PdfFontCache.regular();
      final bold = await PdfFontCache.bold();
      return build(regular, bold);
    }

    if (!offMain || kIsWeb) {
      debugLastPath = 'main';
      return here();
    }
    final ByteData regularBytes;
    final ByteData boldBytes;
    try {
      // 차례로 읽는다 — SynchronousFuture 를 Future.wait 에 넣으면 값을 놓친다(PF-5).
      regularBytes = await PdfFontCache.loadBytes(PdfFontCache.regularAsset);
      boldBytes = await PdfFontCache.loadBytes(PdfFontCache.boldAsset);
    } catch (e) {
      debugPrint('⚠️ [OffMain:$tag] 폰트 바이트 읽기 실패 — 이 isolate 에서 만든다: $e');
      debugLastPath = 'main-fallback';
      return here();
    }
    return _pdfIsolate(tag, build, regularBytes, boldBytes, timeout, here);
  }

  // closure 가 build · 두 바이트만 잡도록 따로 둔다(here 는 실패 때만 쓴다 · 보내지 않는다).
  static Future<Uint8List> _pdfIsolate(
    String tag,
    Future<Uint8List> Function(pw.Font regular, pw.Font bold) build,
    ByteData regularBytes,
    ByteData boldBytes,
    Duration timeout,
    Future<Uint8List> Function() here,
  ) async {
    try {
      final r = await _sendPdf(build, regularBytes, boldBytes).timeout(timeout);
      debugLastPath = 'isolate';
      return r;
    } catch (e) {
      debugPrint('⚠️ [OffMain:$tag] 별도 isolate PDF 실패 — 이 isolate 에서 다시 만든다: $e');
      debugLastPath = 'main-fallback';
      return here();
    }
  }

  static Future<Uint8List> _sendPdf(
    Future<Uint8List> Function(pw.Font regular, pw.Font bold) build,
    ByteData regularBytes,
    ByteData boldBytes,
  ) =>
      Isolate.run<Uint8List>(() => build(pw.Font.ttf(regularBytes), pw.Font.ttf(boldBytes)));
}
