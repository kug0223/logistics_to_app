/// 기존 계약서 텍스트 → ContractArticle 배열 변환 파서
///
/// 목표:
///   - 제N조 경계만 인식 (①②③ 등 nested 항목은 분리하지 않음)
///   - 원문 내용 변경 금지 (transformation not generation)
///   - 경고 분류만 수행 (SYSTEM/CUSTOM hard-label 없음)
///
/// [DESIGN] 외부 의존성 없음 — 순수 Dart
library;

// ─── 경고 유형 ────────────────────────────────────────────────────

enum ArticleWarningType {
  /// 제1~3조: ALfit PDF 고정 섹션(제1조 당사자, 제2조 근무조건, 제3조 임금)과 번호 충돌
  exactSystemRange,

  /// 임금·근무조건 관련 keyword 포함 — 자동 작성 내용과 겹칠 가능성
  likelyDuplicate,

  /// 고확신 개인정보 패턴 감지 (주민번호·전화번호·이메일)
  piiDetected,
}

// ─── 분석된 조항 ─────────────────────────────────────────────────

class ParsedArticle {
  final String title;
  final String content;

  /// 제N조에서 파싱된 N 값. 번호가 없으면 -1.
  final int articleNumber;

  final Set<ArticleWarningType> warnings;

  /// 사용자가 UI에서 변경 가능한 포함 여부
  bool included;

  ParsedArticle({
    required this.title,
    required this.content,
    required this.articleNumber,
    required this.warnings,
    required this.included,
  });

  bool get hasAnyWarning => warnings.isNotEmpty;
  bool get isExactSystemRange =>
      warnings.contains(ArticleWarningType.exactSystemRange);
  bool get isLikelyDuplicate =>
      warnings.contains(ArticleWarningType.likelyDuplicate);
  bool get hasPii => warnings.contains(ArticleWarningType.piiDetected);
}

// ─── 파싱 결과 ────────────────────────────────────────────────────

class ParseResult {
  final List<ParsedArticle> articles;
  final bool hasAnyPii;

  const ParseResult({required this.articles, required this.hasAnyPii});

  bool get isEmpty => articles.isEmpty;
  int get totalCount => articles.length;
  int get systemRangeCount =>
      articles.where((a) => a.isExactSystemRange).length;
  int get likelyDuplicateCount => articles
      .where((a) => a.isLikelyDuplicate && !a.isExactSystemRange)
      .length;
}

// ─── 파서 ────────────────────────────────────────────────────────

class ArticleParser {
  ArticleParser._();

  // 제N조 경계 — multiLine 모드: ^ 가 각 줄 시작에 매칭
  // 지원:  제1조  /  제 1 조  /  제1조 (제목)  /  제1조（제목）
  //        제1조【제목】 /  제1조 [제목]  /  제1조. 제목  /  제1조,  /  제1조
  // 조 뒤에 lookahead: 줄끝($ multiline) OR 공백 OR 다양한 여는 문자
  static final _boundary = RegExp(
    r'^제\s*(\d{1,3})\s*조(?=$|[\s\(（【\[\.,，])',
    multiLine: true,
  );

  // 제목 공백 정규화: "제 1 조 ..." → "제1조 ..."
  static final _titleNorm = RegExp(r'^제\s+(\d{1,3})\s+조');

  // ─── SYSTEM 번호 범위 (ALfit PDF 고정 제1~3조)
  static bool _isSystemRange(int n) => n >= 1 && n <= 3;

  // ─── LIKELY_DUPLICATE 최소 keyword set
  static const _dupKeywords = [
    '임금', '시급', '일급', '월급', '급여', '지급일',
    '지급 방법', '지급방법',
    '근무 장소', '근무장소',
    '근무 시간', '근무시간', '소정근로',
    '계약기간', '계약 기간', '근로기간', '근로 기간',
    '근로자 성명', '근로자성명',
    '사업장명', '사업자번호',
  ];

  // ─── PII 고확신 패턴만
  // 주민등록번호형: 800101-1234567
  // [PII-B4-R1.3A] 내국인 1~4에 더해 외국인등록번호 5~8까지 본다.
  //   이전에는 [1-4]뿐이라 관리자가 특약에 외국인등록번호를 적어도
  //   경고가 뜨지 않았다. 같은 자리의 같은 위험인데 한쪽만 보고 있었다.
  //   9·0은 넣지 않는다 — normalizeForeignId가 여는 범위와 같게 둔다.
  static final _rrn = RegExp(r'\d{6}-[1-8]\d{6}');
  // 전화번호: 010-1234-5678 / 010 1234 5678
  static final _phone = RegExp(r'0\d{1,2}[-\s]\d{3,4}[-\s]\d{4}');
  // 이메일
  static final _email =
      RegExp(r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}');

  // ─── 공개 API ─────────────────────────────────────────────────

  /// [text]를 파싱해 [ParseResult]를 반환한다.
  ///
  /// 제N조 경계가 0개이면 [ParseResult.isEmpty] == true.
  /// 호출자는 이 경우 fallback UX를 표시한다.
  static ParseResult parse(String text) {
    if (text.trim().isEmpty) {
      return const ParseResult(articles: [], hasAnyPii: false);
    }

    final matches = _boundary.allMatches(text).toList();
    if (matches.isEmpty) {
      return const ParseResult(articles: [], hasAnyPii: false);
    }

    final List<ParsedArticle> articles = [];

    for (int i = 0; i < matches.length; i++) {
      final match = matches[i];
      final int num = int.parse(match.group(1)!);

      // 제목: match 시작 ~ 줄 끝
      final lineEnd = text.indexOf('\n', match.start);
      final String rawTitle = lineEnd == -1
          ? text.substring(match.start).trim()
          : text.substring(match.start, lineEnd).trim();
      final String title = _normalizeTitle(rawTitle);

      // 내용: 제목 줄 다음 ~ 다음 경계 바로 앞
      final contentStart = lineEnd == -1 ? text.length : lineEnd + 1;
      final contentEnd =
          i + 1 < matches.length ? matches[i + 1].start : text.length;
      final String content = contentStart >= contentEnd
          ? ''
          : text.substring(contentStart, contentEnd).trim();

      final warnings = _warnings(num, title, content);
      // 기본 포함: 제1~3조는 false, 나머지는 true
      final bool included = !_isSystemRange(num);

      articles.add(ParsedArticle(
        title: title,
        content: content,
        articleNumber: num,
        warnings: warnings,
        included: included,
      ));
    }

    return ParseResult(
      articles: articles,
      hasAnyPii: articles.any((a) => a.hasPii),
    );
  }

  // ─── 내부 helpers ─────────────────────────────────────────────

  static String _normalizeTitle(String raw) =>
      raw.replaceFirstMapped(_titleNorm, (m) => '제${m[1]}조');

  static Set<ArticleWarningType> _warnings(
      int num, String title, String content) {
    final out = <ArticleWarningType>{};
    final combined = '$title $content';

    if (_isSystemRange(num)) {
      out.add(ArticleWarningType.exactSystemRange);
    } else {
      // keyword 중복 검사는 제4조 이상에서만
      if (_dupKeywords.any((kw) => combined.contains(kw))) {
        out.add(ArticleWarningType.likelyDuplicate);
      }
    }

    // PII: 번호에 관계없이 전체 검사
    if (_rrn.hasMatch(combined) ||
        _phone.hasMatch(combined) ||
        _email.hasMatch(combined)) {
      out.add(ArticleWarningType.piiDetected);
    }

    return out;
  }
}
