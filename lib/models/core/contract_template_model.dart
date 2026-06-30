import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// ─── 계약서 유형 상수 ─────────────────────────────────────────────
abstract class ContractTemplateType {
  static const String daily      = 'daily';       // 단기 일용직
  static const String period     = 'period';      // 기간제(장기)
  static const String outsource  = 'outsource';   // 업무위탁(3.3% 도급)

  static String label(String type) {
    switch (type) {
      case daily:     return '단기 일용직';
      case period:    return '기간제(장기)';
      case outsource: return '업무위탁(도급)';
      default:        return '기타';
    }
  }

  static String description(String type) {
    switch (type) {
      case daily:
        return '하루~수주 단기 알바 · 일급/시급 · 산재보험 필수';
      case period:
        return '1개월~2년 장기 계약 · 4대보험 전부 · 연차 발생';
      case outsource:
        return '독립 수행 · 사업소득세 3.3% 원천징수 · 4대보험 없음';
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

  // ──────────────────────────────────────────────────────────────
  // 유형별 기본 조항 (2026 근로기준법·최저임금 기준)
  // ──────────────────────────────────────────────────────────────

  /// 유형별 기본 조항 반환
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
  static const List<ContractArticle> _dailyArticles = [
    ContractArticle(
      title: '제4조 (4대보험 적용)',
      content:
          '① 산업재해보상보험: 첫날부터 필수 가입 (모든 사업장 의무)\n\n'
          '② 국민연금·건강보험·고용보험:\n'
          '   아래 조건 중 하나를 충족하는 경우 가입 의무 발생\n'
          '   · 1개월 이상 근무 + 월 소정근로시간 60시간 이상 (주 15시간 이상)\n'
          '   · 1개월 이상 근무 + 월 8일 이상 근무\n\n'
          '③ 본 계약의 근무 조건 기준 예상 적용 여부:\n'
          '   □ 산재보험: 적용\n'
          '   □ 고용·국민연금·건강보험: □ 적용 / □ 미적용 (위 기준 확인 후 체크)\n\n'
          '※ 4대보험 신고는 사업주 의무입니다. 미가입 시 과태료 및 소급 납부 부담이 발생합니다.',
    ),
    ContractArticle(
      title: '제5조 (근태 및 휴일)',
      content:
          '① 주휴일: 1주 소정근로일을 개근한 경우 1일 유급휴일을 부여한다.\n'
          '   단, 1주 소정근로시간이 15시간 미만인 경우 유급휴일은 적용되지 않는다.\n\n'
          '② 결근·지각·조퇴 시 실 근로시간에 비례하여 임금을 공제한다.\n\n'
          '③ 사전 통보 없이 결근하거나 무단으로 작업 현장을 이탈하는 경우 '
          '계약 해지 사유가 될 수 있다.',
    ),
    ContractArticle(
      title: '제6조 (연장·야간·휴일근로 수당)',
      content:
          '【상시근로자 5인 이상 사업장에만 적용 — 5인 미만은 이 조항을 삭제하거나 "해당 없음"으로 수정하세요】\n\n'
          '① 연장근로(1일 8시간·주 40시간 초과): 통상임금의 150%\n'
          '② 야간근로(오후 10시 ~ 오전 6시): 통상임금의 150%\n'
          '③ 휴일근로:\n'
          '   · 8시간 이내: 통상임금의 150%\n'
          '   · 8시간 초과분: 통상임금의 200%\n'
          '④ 연장+야간 중복 시 각 가산율 합산 적용\n\n'
          '【5인 미만 사업장 대체 문구】\n'
          '"현재 상시근로자 5인 미만 사업장으로 근로기준법 제11조에 따라 '
          '가산수당(연장·야간·휴일) 규정이 적용되지 않는다. '
          '단, 향후 고용노동부 고시에 따라 변경될 수 있다."',
    ),
    ContractArticle(
      title: '제7조 (계약 해지 및 해고예고)',
      content:
          '① 계약 기간 만료 시 본 계약은 자동 종료된다.\n\n'
          '② 사업주가 근로자를 계약 기간 중 해고하려는 경우 '
          '근로기준법 제26조에 따라 30일 전에 예고하거나, '
          '30일분 통상임금을 해고예고수당으로 지급하여야 한다.\n'
          '   단, 계속 근로기간 3개월 미만인 경우 해고예고 규정이 적용되지 않는다.\n\n'
          '③ 근로자가 귀책사유(무단결근, 업무방해, 범죄행위 등)로 해고 시 '
          '해고예고 없이 즉시 해고할 수 있다.\n\n'
          '④ 상시근로자 5인 이상 사업장에서 정당한 이유 없는 해고는 부당해고로 '
          '노동위원회에 구제신청이 가능하다.',
    ),
    ContractArticle(
      title: '제8조 (임금명세서 교부)',
      content:
          '사업주는 근로기준법 제48조에 따라 임금 지급 시마다 아래 사항이 포함된 '
          '임금명세서를 근로자에게 교부한다(서면 또는 전자적 방법 가능).\n\n'
          '· 임금 지급일 및 임금 총액\n'
          '· 근로일수 및 총 근로시간\n'
          '· 연장·야간·휴일 근로시간 (해당 시)\n'
          '· 기본급, 주휴수당 등 항목별 금액\n'
          '· 공제 항목 및 공제액 (소득세, 4대보험료 등)\n'
          '· 실수령액\n\n'
          '※ 임금명세서 미교부 시 500만 원 이하 과태료 (2021년 11월부터 전 사업장 의무).',
    ),
    ContractArticle(
      title: '제9조 (안전·보건 및 산업재해)',
      content:
          '① 사업주는 산업안전보건법에 따라 근로자가 안전한 환경에서 근무하도록 '
          '필요한 조치를 취하여야 한다.\n'
          '② 근로자는 사업주의 안전·보건 지시를 성실히 준수하여야 하며, '
          '위험 상황 발생 시 즉시 사업주에게 보고하여야 한다.\n'
          '③ 업무상 재해 발생 시 산업재해보상보험법에 따라 처리된다.\n\n'
          '※ 일용직이라도 산재보험은 첫날부터 적용됩니다. '
          '현장 안전 수칙 위반 행위는 계약 해지 사유가 될 수 있습니다.',
    ),
    ContractArticle(
      title: '제10조 (개인정보 보호)',
      content:
          '사업주는 근로계약 체결 및 임금 지급 목적으로 수집한 근로자의 개인정보를 '
          '개인정보보호법에 따라 적법하게 처리하며, 목적 외 이용 및 제3자 제공을 금지한다.\n\n'
          '근로자의 개인정보는 근로관계 종료 후 관계 법령이 정한 기간까지만 보관되며, '
          '이후 안전하게 파기된다.',
    ),
    ContractArticle(
      title: '제11조 (기타)',
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
    ContractArticle(
      title: '제4조 (수습기간)',
      content:
          '【수습을 적용하는 경우에만 사용하세요. 해당 없으면 이 조항을 삭제하세요.】\n\n'
          '입사일로부터 __개월을 수습기간으로 정한다.\n'
          '수습기간 중에는 최저임금법 제5조 제2항에 따라 '
          '법정 최저시급의 90%를 지급할 수 있다 (최저시급은 매년 고용노동부 고시 기준).\n\n'
          '단, 다음의 경우 수습 감액이 적용되지 않는다.\n'
          '· 계속 근로기간 1년 미만의 기간제 근로계약\n'
          '· 단순노무 직종(고용노동부 고시 제2023-65호 기준)\n\n'
          '수습기간 종료 후 직무 적합성이 현저히 미달한다고 판단되는 경우 '
          '취업규칙 및 관계 법령에 따라 처리한다.',
    ),
    ContractArticle(
      title: '제5조 (4대보험 가입)',
      content:
          '갑은 관련 법령에 따라 다음 4대보험에 을을 가입시킨다.\n\n'
          '① 국민연금: 보험료의 50% 갑 부담, 50% 을 부담 (급여에서 공제)\n'
          '② 건강보험(장기요양보험 포함): 50% 갑 부담, 50% 을 부담\n'
          '③ 고용보험: 갑·을 각각 법정 요율 부담\n'
          '④ 산업재해보상보험: 전액 갑 부담\n\n'
          '※ 주 15시간(월 60시간) 미만 초단시간 근로자는 고용보험·산재보험만 적용됩니다. '
          '계약서 작성 전 시간 요건을 확인하세요.',
    ),
    ContractArticle(
      title: '제6조 (주휴일 및 공휴일)',
      content:
          '① 1주 소정근로일을 개근한 경우 유급 주휴일 1일을 부여한다.\n'
          '② 관공서 공휴일(근로기준법 제55조 제2항)을 유급 공휴일로 부여한다.\n'
          '   【5인 미만 사업장: 위 ②항은 적용 제외, 2027년부터 단계 적용 예정】\n\n'
          '③ 주휴일·공휴일에 불가피하게 근무한 경우 대체휴무 또는 휴일근로수당을 지급한다.',
    ),
    ContractArticle(
      title: '제7조 (연장·야간·휴일근로 수당)',
      content:
          '【상시근로자 5인 이상 사업장에 적용 — 5인 미만은 조항 삭제 또는 수정하세요】\n\n'
          '① 연장근로(1일 8시간·주 40시간 초과): 통상임금의 150%\n'
          '② 야간근로(오후 10시 ~ 오전 6시): 통상임금의 150%\n'
          '③ 휴일근로: 8시간 이내 150%, 8시간 초과분 200%\n'
          '④ 중복 적용 시 각 가산율 합산\n\n'
          '연장근로는 을의 동의가 있는 경우에만 실시하며, 주 12시간을 초과할 수 없다.',
    ),
    ContractArticle(
      title: '제8조 (연차유급휴가)',
      content:
          '① 계속 근로기간 1년 미만: 1개월 개근 시 1일 유급휴가 발생 (최대 11일)\n'
          '② 계속 근로기간 1년 이상: 15일 유급휴가 발생 (3년 이상 시 2년마다 1일 가산, 최대 25일)\n'
          '③ 연차 사용 촉진: 사업주는 근로기준법 제61조에 따라 연차 사용 촉진 조치를 취할 수 있다.\n'
          '④ 연차 미사용 시 계약 종료 또는 연도 말에 통상임금 기준으로 연차수당을 지급한다.\n\n'
          '【5인 미만 사업장: 2027년까지 연차유급휴가 규정 미적용 (단계 확대 중)】',
    ),
    ContractArticle(
      title: '제9조 (퇴직급여)',
      content:
          '① 계속 근로기간 1년 이상이고 주 15시간 이상 근무한 근로자에게는 '
          '근로자퇴직급여보장법에 따라 퇴직급여를 지급한다.\n'
          '② 퇴직금은 계속근로 1년에 대해 30일분의 평균임금으로 산정하며, '
          '퇴직일로부터 14일 이내에 지급한다.\n\n'
          '※ 계속 근로기간 1년 미만 또는 주 15시간 미만 근무자는 대상에서 제외됩니다.',
    ),
    ContractArticle(
      title: '제10조 (기간제 차별금지)',
      content:
          '갑은 기간제 및 단시간근로자 보호 등에 관한 법률 제8조에 따라 '
          '기간의 정함이 없는 근로자(정규직)와 동일·유사한 업무를 수행하는 을에게 '
          '합리적 이유 없이 임금·교육·배치·승진 등에서 불합리한 차별을 해서는 안 된다.\n\n'
          '불합리한 차별을 받은 경우 노동위원회에 차별 시정을 신청할 수 있다.',
    ),
    ContractArticle(
      title: '제11조 (근태 및 복무)',
      content:
          '① 지각·조퇴 시 실 근로시간에 비례하여 임금을 공제한다.\n'
          '② 무단결근 시 해당일 일급을 공제하며, 3일 이상 지속 시 징계 사유가 될 수 있다.\n'
          '③ 결근·지각이 예상되는 경우 근무 시작 전 사전에 사업주에게 통보하여야 한다.\n'
          '④ 근무 중 임의 자리 이탈 및 사적 업무 수행을 금지한다.',
    ),
    ContractArticle(
      title: '제12조 (직장 내 괴롭힘 금지)',
      content:
          '사업주 및 근로자는 직장에서의 지위 또는 관계 우위를 이용하여 업무상 '
          '적정 범위를 넘어 다른 근로자에게 신체적·정신적 고통을 주거나 '
          '근무환경을 악화시키는 행위(직장 내 괴롭힘)를 금지한다 (근로기준법 제76조의2).\n\n'
          '직장 내 성희롱도 남녀고용평등법 제14조에 따라 동일하게 처리한다.\n\n'
          '위반 시 사업주에게 500만 원 이상 과태료 부과 가능.',
    ),
    ContractArticle(
      title: '제13조 (계약 해지 및 해고예고)',
      content:
          '① 사업주는 근로기준법 제23조에 따라 정당한 이유 없이 을을 해고할 수 없다.\n'
          '② 사업주가 을을 해고하려는 경우 30일 전에 서면으로 예고하거나, '
          '30일분 통상임금을 해고예고수당으로 지급하여야 한다.\n'
          '③ 을이 사직하려는 경우 최소 30일 이전에 서면으로 통보하여야 한다.\n\n'
          '【5인 미만 사업장: 부당해고 구제신청(근로기준법 제23조) 미적용 — 2028년 이후 적용 예정】',
    ),
    ContractArticle(
      title: '제14조 (개인정보 보호 및 비밀유지)',
      content:
          '사업주는 근로계약 이행을 위해 수집한 근로자의 개인정보를 '
          '개인정보보호법에 따라 처리하며 목적 외 사용을 금지한다.\n\n'
          '근로자는 재직 중 및 퇴직 후에도 업무상 취득한 사업장의 '
          '영업비밀, 고객정보, 내부 운영 정보를 외부에 누설해서는 안 된다.\n'
          '위반 시 민·형사상 책임을 질 수 있다.',
    ),
    ContractArticle(
      title: '제15조 (기타)',
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
              ?.map((a) => ContractArticle.fromMap(
                  Map<String, dynamic>.from(a as Map)))
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
