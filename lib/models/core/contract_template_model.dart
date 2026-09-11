import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// ─── 템플릿 분류 상수 ─────────────────────────────────────────────
//
// [V1 SEMANTICS] 이 값은 "생성될 문서의 종류"가 아니라
//   ① 기본 조항 세트 선택  ② 목록/배지에서의 용도 분류
// 두 가지만 결정한다.
//
// ALfit이 생성하는 문서 renderer는 V1에서 근로계약서 하나뿐이며,
// 제1조(당사자)·제2조(근무조건)·제3조(임금) 고정 섹션은
// templateType이 아니라 Application/TO snapshot(isLongTerm·slots·임금 등)으로
// 결정된다. ContractTemplateWidget은 templateType을 인자로 받지도 않는다.
// → copy는 "계약서 종류"가 아니라 "어떤 근무 형태에 쓸 템플릿인가"로 표현한다.
abstract class ContractTemplateType {
  static const String daily      = 'daily';       // 단기·일용 근무용
  static const String period     = 'period';      // 기간제·장기 근무용

  /// [LEGACY-ONLY] 신규 생성에서는 선택할 수 없다.
  /// UI가 "업무위탁계약서"를 약속했지만 실제 산출물은 근로계약서 구조여서
  /// V1 신규 생성 대상에서 제외했다(제품 약속-산출물 불일치).
  /// 기존 문서를 읽고 편집하는 하위 호환은 그대로 유지한다.
  static const String outsource  = 'outsource';

  /// 신규 사용(계약 선택·복사)에 쓸 수 있는 분류인가.
  ///
  /// [LEGACY_OUTSOURCE_POLICY = READ_COMPATIBILITY_ONLY]
  ///   조회·편집 = 허용 / 신규 계약 선택·복사 = 금지
  ///
  /// 신규 생성 UI에서 outsource를 숨기는 것만으로는 부족했다 —
  /// 기존 outsource 템플릿을 복사(duplicate / cross-business copy)하면
  /// 신규 생성 금지를 우회해 새 outsource 문서가 계속 생겨났고,
  /// 계약 선택 다이얼로그에서 골라 그대로 발송할 수도 있었다.
  /// 선택·복사·readiness 판정이 모두 이 하나의 기준을 쓴다.
  static bool isSupportedForNewUse(String type) =>
      type == daily || type == period;

  static String label(String type) {
    switch (type) {
      case daily:     return '단기 근무용';
      case period:    return '기간제 근무용';
      // outsource 등 신규 미지원 값은 중립 라벨로 표시 — 지원하지 않는
      // 문서 종류를 UI가 약속하지 않도록 한다.
      default:        return '기타';
    }
  }

  static String description(String type) {
    switch (type) {
      case daily:
        return '하루~수주 단기 근무에 쓰는 기본 조항';
      case period:
        return '1개월~2년 기간제 근무에 쓰는 기본 조항';
      default:
        return '';
    }
  }
}

// ─── 계약서 조항 ─────────────────────────────────────────────────

class ContractArticle {
  final String title;
  final String content;

  const ContractArticle({required this.title, required this.content});

  Map<String, dynamic> toMap() => {'title': title, 'content': content};

  factory ContractArticle.fromMap(Map<String, dynamic> m) => ContractArticle(
        title: m['title'] as String? ?? '',
        content: m['content'] as String? ?? '',
      );

  ContractArticle copyWith({String? title, String? content}) => ContractArticle(
        title: title ?? this.title,
        content: content ?? this.content,
      );
}

// ─── 계약서 템플릿 ────────────────────────────────────────────────

class ContractTemplateModel {
  final String id;
  final String businessId;
  final String name;
  final String templateType; // ContractTemplateType 상수
  final List<ContractArticle> articles;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const ContractTemplateModel({
    required this.id,
    required this.businessId,
    required this.name,
    required this.templateType,
    required this.articles,
    required this.createdAt,
    this.updatedAt,
  });

  /// 이 템플릿을 신규 계약 선택·복사에 쓸 수 있는가.
  /// 조회·편집에는 영향이 없다 — legacy 문서는 계속 열고 고칠 수 있다.
  bool get isSupportedForNewUse =>
      ContractTemplateType.isSupportedForNewUse(templateType);

  /// 신규 계약에 사용할 수 있는 템플릿만 남긴다.
  ///
  /// 계약 선택 후보(SelectorDialog)와 공고 사전조건(readiness)이 **같은 기준**을
  /// 써야 한다. 한쪽만 legacy를 세면 "템플릿 준비 완료"로 공고는 열리는데
  /// 정작 계약 단계에서 고를 템플릿이 0개인 dead-end가 생긴다.
  static List<ContractTemplateModel> selectableForNewContract(
          Iterable<ContractTemplateModel> all) =>
      all.where((t) => t.isSupportedForNewUse).toList();

  // ──────────────────────────────────────────────────────────────
  // 유형별 기본 조항 (2026 근로기준법·최저임금 기준)
  // ──────────────────────────────────────────────────────────────

  /// 분류별 기본 조항 반환
  ///
  /// outsource는 신규 생성 경로가 제거되어 실질적으로 호출되지 않으나,
  /// 기존 문서 하위 호환과 조항 세트 보존을 위해 분기를 유지한다.
  static List<ContractArticle> defaultArticlesFor(String type) {
    switch (type) {
      case ContractTemplateType.daily:     return _dailyArticles;
      case ContractTemplateType.period:    return _periodArticles;
      case ContractTemplateType.outsource: return _outsourceArticles;
      default: return _dailyArticles;
    }
  }

  // ──────────────────────────────────────────────────────────────
  // 1. 단기 일용직 근로계약서 조항
  //    적용법: 근로기준법, 최저임금법, 고용보험법, 산업재해보상보험법
  //    2026 최저시급: 10,320원
  // ──────────────────────────────────────────────────────────────
  // ※ 제1~3조(계약 당사자·근무조건·임금)는 고정 섹션에서 공고 데이터로 자동입력됨
  // [SEND-SAFE] 기본 조항은 관리자 수정 없이 그대로 발송돼도 문서가 완결돼야 한다.
  //   renderer가 article.content를 그대로 PDF에 출력하므로(ContractTemplateWidget),
  //   편집 지시문·빈칸·미체크 박스·관리자 교육용 경고는 default에 두지 않는다.
  //   조건부 조항(상시근로자 수 판단 필요 등)은 default에서 제외 — ALfit이
  //   canonical fact로 갖지 않는 값을 시스템이 대신 고를 수 없기 때문이다.
  //   관리자는 필요 시 편집 화면에서 직접 추가할 수 있다.
  static const List<ContractArticle> _dailyArticles = [
    // [REFERENCE-CORE 제외] 4대보험 적용 —
    //   당사자 간 약정이 아니라 "언제 가입 의무가 생기는지"에 대한 법령 설명이었다.
    //   판정 기준(월 소정근로시간 60h / 월 8일)을 ALfit이 집계·판정하지 않고,
    //   공제 방식은 시스템 제3조가 taxDeductionType으로 이미 표시한다.
    //
    // [REFERENCE-CORE 제외] 근태 및 휴일 —
    //   ① 주휴(ALfit이 산정하지 않음) ② 실근로시간 비례 임금 ③ 해지 사유(사업장 정책)
    //   세 성격이 섞여 있었다. ②는 제품과 정합하지만 이를 살리려고 새 조항을
    //   재작성하지 않는다 — 임금은 시스템 제3조와 실제 급여 산출이 canonical이다.
    // [SEND-SAFE 제외] 연장·야간·휴일근로 수당 조항은 상시근로자 5인 기준에 따라
    //   본문 자체가 달라지며, 원문이 관리자에게 "삭제하거나 수정하세요" + 대체 문구를
    //   제시하는 구조였다. ALfit은 상시근로자 수를 canonical fact로 갖지 않아
    //   시스템이 어느 문구를 쓸지 고를 수 없으므로 default에서 제외한다.
    //   필요한 관리자는 편집 화면에서 직접 조항을 추가할 수 있다.
    // [REFERENCE-CORE 제외] 계약 해지 및 해고예고 —
    //   해고예고 / 예고 예외 / 즉시해고 / 5인 기준 / 부당해고 구제 /
    //   근로자 사직통보 / 계약기간 만료가 한 조항에 섞여 있었고, 외부 검증에서
    //   부정확·조건부·사업장 정책·재작성 필요 fragment가 다수 확인됐다.
    //   이를 정확한 법률 설명문으로 다시 쓰는 것보다, 상세한 해지 법률 설명을
    //   ALfit 기본값에서 제공하지 않는 편이 제품 책임 원칙과 일치한다.
    //   대체 문장을 새로 쓰지 않고 제외만 한다.
    //   실제 계약기간은 시스템 고정 제2조가 ContractSnapshot으로 이미 담당한다.
    //
    // [REFERENCE-CORE 제외] 임금명세서 교부 —
    //   ALfit에는 실제 급여명세 기능이 있다(payroll/payslip). 계약서가 명세 항목을
    //   텍스트로 고정하면 실제 산출물과 drift하고, 이미 "주휴수당 항목"이 어긋나
    //   있었다. 중복 자체가 리스크이므로 제외한다.
    ContractArticle(
      title: '제4조 (안전·보건 및 산업재해)',
      // [BUSINESS-POLICY 제외] 원문 말미의
      //   "현장 안전 수칙 위반 행위는 계약 해지 사유가 될 수 있습니다." 삭제 —
      //   어떤 위반을 계약 해지 사유로 삼을지는 사업장 운영·징계 정책 영역이고
      //   ALfit에는 징계 절차 기능도 없다. 일반 안전·보건 내용만 남긴다.
      content:
          '① 사업주는 산업안전보건법에 따라 근로자가 안전한 환경에서 근무하도록 '
          '필요한 조치를 취하여야 한다.\n'
          '② 근로자는 사업주의 안전·보건 지시를 성실히 준수하여야 하며, '
          '위험 상황 발생 시 즉시 사업주에게 보고하여야 한다.\n'
          '③ 업무상 재해 발생 시 산업재해보상보험법에 따라 처리된다.\n\n'
          '※ 일용직이라도 산재보험은 첫날부터 적용됩니다.',
    ),
    ContractArticle(
      title: '제5조 (개인정보 보호)',
      content:
          '사업주는 근로계약 체결 및 임금 지급 목적으로 수집한 근로자의 개인정보를 '
          '개인정보보호법에 따라 적법하게 처리하며, 목적 외 이용 및 제3자 제공을 금지한다.\n\n'
          '근로자의 개인정보는 근로관계 종료 후 관계 법령이 정한 기간까지만 보관되며, '
          '이후 안전하게 파기된다.',
    ),
    ContractArticle(
      title: '제6조 (기타)',
      content:
          '본 계약에서 정하지 않은 사항은 근로기준법, 최저임금법, '
          '고용보험법, 산업재해보상보험법 등 관계 법령에 따른다.\n\n'
          '계약 내용에 분쟁이 발생할 경우 관할 고용노동청 또는 노동위원회에 신청할 수 있다.',
    ),
  ];

  // ──────────────────────────────────────────────────────────────
  // 2. 기간제 근로계약서 조항
  //    적용법: 근로기준법, 기간제및단시간근로자보호법, 퇴직급여법
  //    계약 기간: 1개월 이상 ~ 2년(이하)
  // ──────────────────────────────────────────────────────────────
  // ※ 제1~3조(계약 당사자·근무조건·임금)는 고정 섹션에서 공고 데이터로 자동입력됨
  static const List<ContractArticle> _periodArticles = [
    // [SEND-SAFE 제외] 수습기간 조항은 원문이 "입사일로부터 __개월"이라는
    //   미완성 값을 포함했다. placeholder만 지우면 조항이 성립하지 않고,
    //   개월수를 임의로 정하는 것은 계약 조건을 시스템이 창작하는 일이다.
    //   수습을 적용하는 관리자가 편집 화면에서 직접 추가하도록 default에서 제외한다.
    // [REFERENCE-DEFAULT 제외] 4대보험 가입 조항 —
    //   부담 비율(50:50)과 "급여에서 공제"를 ALfit 기본안이 확정하는 구조였다.
    //   공제 방식은 시스템 제3조가 taxDeductionType(세금 없음 / 3.3% 원천징수 /
    //   일용직 소득세 / 4대보험 고정)으로 렌더하므로 같은 문서 안에서 모순될 수 있었다.
    //   보험 적용·부담은 사업장과 근로조건에 따라 달라지는 정책 영역이므로
    //   ALfit이 대신 확정하지 않는다. 대체 문구를 새로 쓰지 않고 제외만 한다.
    // [REFERENCE-CORE 제외] 주휴일 및 공휴일 —
    //   ALfit은 주휴 자격을 판정하지도, 수당을 가산하지도 않는데 조항은
    //   "부여한다"로 확정했다. 공휴일은 사업장 규모 조건에 의존한다.
    //   문구를 고쳐 남기려면 임금 구성·급여 산출까지 함께 바꿔야 하므로
    //   기본값에서 빼고 실제 임금 구성과 사업장 판단에 맡긴다.
    //
    // [REFERENCE-CORE 제외] 연차유급휴가 / 퇴직급여 —
    //   발생 요건(1개월 개근, 1년 이상, 주 15시간 등)을 ALfit이 추적하지 않고
    //   연차·퇴직금 계산 기능도 없다. 법정 기준 낭독문에 가깝다.
    //
    // [REFERENCE-CORE 제외] 기간제 차별금지 —
    //   사업주 대상 법정 금지의 낭독이며, 양 당사자가 이행할 계약 조항으로
    //   작동하지 않는다. "법적으로 좋은 내용"이라는 이유만으로 두지 않는다.
    // [REFERENCE-DEFAULT 제외] 근태 및 복무 조항 —
    //   "3일 이상 지속 시 징계 사유", "자리 이탈·사적 업무 금지"는
    //   사업장 취업규칙·복무정책 영역이고, ALfit에는 징계 절차 기능도 없다.
    //   임금 미지급 부분만 떼어 새 조항으로 쓰는 것은 별도 content 결정이므로
    //   여기서는 제외만 한다.
    ContractArticle(
      title: '제4조 (직장 내 괴롭힘 금지)',
      content:
          '사업주 및 근로자는 직장에서의 지위 또는 관계 우위를 이용하여 업무상 '
          '적정 범위를 넘어 다른 근로자에게 신체적·정신적 고통을 주거나 '
          '근무환경을 악화시키는 행위(직장 내 괴롭힘)를 금지한다 (근로기준법 제76조의2).\n\n'
          '직장 내 성희롱도 남녀고용평등법 제14조에 따라 동일하게 처리한다.',
    ),
    // [REFERENCE-CORE 제외] 계약 해지 및 해고예고 —
    //   daily와 동일한 이유로 조항 전체를 제외한다. 이 period 문안은 외부 검증에서
    //   ① 적용 조건(5인 이상) 누락 ② 근로기준법 제26조에 없는 서면 요건
    //   ③ 법정 의무가 아닌 근로자 사직 통보 의무가 확인됐다.
    //   특히 ③은 ALfit 기본값이 근로자에게 법에 없는 의무를 지우는 방향이었다.
    //   문구를 고쳐 남기지 않고 제외만 한다 — 대체 문장을 쓰지 않는다.
    ContractArticle(
      // [BUSINESS-POLICY 제외] 원제목 '제6조 (개인정보 보호 및 비밀유지)'에서
      //   '및 비밀유지' 삭제 — 아래 본문에서 비밀유지 부분을 제외했기 때문이다.
      //   영업비밀·고객정보·내부 운영 정보의 범위, 비밀유지 기간, 위반 시
      //   민·형사상 책임 범위는 사업장별 정책 영역이며 ALfit이 기본값으로
      //   대신 확정하지 않는다. 개인정보 보호 일반 내용만 남긴다.
      //   daily 조항을 복사해 오지 않았다 — 남은 문장은 period 원문 그대로다.
      title: '제5조 (개인정보 보호)',
      content:
          '사업주는 근로계약 이행을 위해 수집한 근로자의 개인정보를 '
          '개인정보보호법에 따라 처리하며 목적 외 사용을 금지한다.',
    ),
    ContractArticle(
      title: '제6조 (기타)',
      content:
          '본 계약에서 정하지 않은 사항은 근로기준법, 기간제및단시간근로자보호법, '
          '최저임금법, 근로자퇴직급여보장법, 산업안전보건법 등 관계 법령 및 '
          '취업규칙에 따른다.\n\n'
          '계약 내용에 분쟁이 발생할 경우 관할 고용노동청 또는 노동위원회에 '
          '조정·구제를 신청할 수 있다.',
    ),
  ];

  // ──────────────────────────────────────────────────────────────
  // 3. 업무위탁계약서 (3.3% 도급/프리랜서)
  //    적용법: 민법(도급), 소득세법(사업소득 원천징수)
  //    주의: 근로기준법 비적용 계약 유형
  // ──────────────────────────────────────────────────────────────
  // ※ 제1~3조(계약 당사자·업무내용·계약기간·보수)는 고정 섹션에서 공고 데이터로 자동입력됨
  static const List<ContractArticle> _outsourceArticles = [
    ContractArticle(
      title: '제4조 (원천징수 및 세금 처리)',
      content:
          '① 갑은 위탁보수 지급 시 소득세법 제127조에 따라 '
          '사업소득에 대한 원천징수세 3.3%(소득세 3% + 지방소득세 0.3%)를 공제하고 지급한다.\n\n'
          '② 갑은 원천징수한 세액을 신고·납부하고, '
          '다음 연도 3월 10일까지 지급명세서를 관할 세무서에 제출한다.\n\n'
          '③ 을은 매년 5월 종합소득세 신고 기간에 사업소득을 신고·정산하여야 한다.\n\n'
          '④ 경비·재료비 등 업무 관련 비용은 □ 갑 부담 / □ 을 부담 / □ 별도 협의',
    ),
    ContractArticle(
      title: '제5조 (4대보험 미적용 및 사회보험 안내)',
      content:
          '① 본 업무위탁 계약에서 을은 근로자가 아닌 독립 사업자로서, '
          '4대보험(국민연금, 건강보험, 고용보험, 산업재해보상보험)의 직장가입자 자격이 발생하지 않는다.\n\n'
          '② 갑은 을의 사회보험료를 부담하지 않는다.\n\n'
          '③ 을은 아래 사항을 직접 처리하여야 한다.\n'
          '   · 국민연금: 지역가입자로 직접 납부\n'
          '   · 건강보험: 지역가입자로 직접 납부 (또는 사업자 등록 후 처리)\n'
          '   · 고용보험: 원칙적 미적용 (일부 자영업자 선택 가입 가능)\n'
          '   · 산재보험: 특수형태근로종사자 해당 시 선택 가입 가능\n\n'
          '※ 사회보험 관련 문의: 국민연금공단(☎1355), 국민건강보험공단(☎1577-1000)',
    ),
    ContractArticle(
      title: '제6조 (결과물의 귀속 및 지식재산권)',
      content:
          '① 을이 본 계약에 따라 제작·납품하는 모든 결과물(문서, 데이터, 설계물 등)에 대한 '
          '소유권 및 지식재산권(저작권 포함)은 납품 및 보수 지급 완료 시 갑에게 귀속된다.\n\n'
          '② 을은 계약 종료 후 결과물을 갑의 동의 없이 사용하거나 제3자에게 제공할 수 없다.\n\n'
          '③ 을이 업무 수행 중 취득한 갑의 영업비밀, 고객정보, 내부 정보는 '
          '계약 종료 후에도 외부에 공개하거나 타 목적에 사용할 수 없다.\n\n'
          '④ 미지급 보수가 있는 경우 갑은 결과물의 최종 인수를 유보할 수 있다.',
    ),
    ContractArticle(
      title: '제7조 (독립성 보장 조항)',
      content:
          '① 을은 갑의 지휘·명령 없이 스스로의 판단으로 업무를 수행한다.\n'
          '② 을은 근무시간·장소를 자유롭게 결정할 수 있으며, '
          '갑은 이에 대한 제한을 두지 않는다.\n'
          '③ 을은 갑의 복무규정·취업규칙 적용 대상이 아니다.\n'
          '④ 을은 갑의 사업장에 상주하지 않으며, 필요 시에만 방문한다.\n'
          '⑤ 을은 고정급 없이 납품된 결과물에 대한 보수만을 수령한다.\n\n'
          '※ 위 조항이 실제로 지켜지지 않을 경우 근로자성 판단을 받을 수 있으며, '
          '이 경우 갑은 4대보험 소급 납부 및 근로기준법상 제재 대상이 됩니다.',
    ),
    ContractArticle(
      title: '제8조 (계약 해지)',
      content:
          '① 다음 사유 발생 시 갑·을 일방이 계약을 해지할 수 있다.\n'
          '   · 계약 기간 만료\n'
          '   · 쌍방 합의\n'
          '   · 상대방의 계약 조건 중대한 위반 (시정 요구 후 __일 이내 미시정 시)\n'
          '   · 사업 상 불가피한 사정 (사전 __일 이내 서면 통보)\n\n'
          '② 일방의 귀책 사유로 인한 해지 시 상대방은 실제 손해에 대한 '
          '배상을 청구할 수 있다.\n\n'
          '③ 불가항력(천재지변, 정부 정책 변경 등)으로 인한 계약 종료는 '
          '양측 귀책 없는 것으로 보며, 상호 손해배상 청구 대상이 아니다.\n\n'
          '④ 본 계약 해지는 근로기준법상 해고가 아니므로 '
          '해고예고수당 지급 의무가 발생하지 않는다.',
    ),
    ContractArticle(
      title: '제9조 (면책 및 손해배상)',
      content:
          '① 을의 업무 수행 중 발생한 제3자에 대한 손해는 을 본인이 책임진다. '
          '갑은 이에 대한 연대책임을 지지 않는다.\n\n'
          '② 을의 귀책사유로 인해 결과물에 하자가 발생한 경우 '
          '을은 이를 무상으로 보완하거나 그에 상당하는 손해를 배상한다.\n\n'
          '③ 을이 갑으로부터 제공받은 자료·장비를 분실·파손한 경우 실손 배상한다.',
    ),
    ContractArticle(
      title: '제10조 (기타)',
      content:
          '① 본 계약에서 정하지 않은 사항은 민법(도급 조항, 제664조~제674조) 및 '
          '소득세법 등 관계 법령에 따른다.\n\n'
          '② 분쟁 발생 시 갑의 소재지를 관할하는 법원을 합의 관할 법원으로 한다.\n\n'
          '③ 본 계약서는 2부를 작성하여 갑·을 각 1부씩 보관한다.',
    ),
  ];

  // ──────────────────────────────────────────────────────────────
  // Firestore 직렬화
  // ──────────────────────────────────────────────────────────────

  factory ContractTemplateModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) {
      throw ArgumentError('ContractTemplateModel.fromFirestore: 문서 데이터 없음 (id: ${doc.id})');
    }
    final d = raw as Map<String, dynamic>;
    return ContractTemplateModel(
      id: doc.id,
      businessId: d['businessId'] as String? ?? '',
      name: d['name'] as String? ?? '',
      templateType: d['templateType'] as String? ?? ContractTemplateType.daily,
      articles: (d['articles'] as List<dynamic>?)
              ?.map((a) { try { return ContractArticle.fromMap(Map<String, dynamic>.from(a as Map)); } catch (_) { return null; } })
              .whereType<ContractArticle>()
              .toList() ??
          [],
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate().toLocal()
          : (throw ArgumentError('ContractTemplateModel: createdAt 필드 누락 (id: ${doc.id})')),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate().toLocal(),
    );
  }

  // [SCHEMA-09] 역직렬화 실패 격리 — 손상 문서 1건이 목록 전체 크래시 방지
  static ContractTemplateModel? tryFromFirestore(DocumentSnapshot doc) {
    try {
      return ContractTemplateModel.fromFirestore(doc);
    } catch (e, st) {
      debugPrint('[ContractTemplateModel] 역직렬화 실패 id=${doc.id}: $e\n$st');
      return null;
    }
  }

  Map<String, dynamic> toMap() => {
        'businessId': businessId,
        'name': name,
        'templateType': templateType,
        'articles': articles.map((a) => a.toMap()).toList(),
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt':
            updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      };

  ContractTemplateModel copyWith({
    String? name,
    String? templateType,
    List<ContractArticle>? articles,
    DateTime? updatedAt,
  }) =>
      ContractTemplateModel(
        id: id,
        businessId: businessId,
        name: name ?? this.name,
        templateType: templateType ?? this.templateType,
        articles: articles ?? this.articles,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
