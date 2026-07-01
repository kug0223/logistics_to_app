// 앱 법적 동의 약관 모델 — Firestore app_settings/legal_terms에서 관리
// 슈퍼관리자가 앱 업데이트 없이 약관 내용·항목 수정 가능

import 'package:cloud_firestore/cloud_firestore.dart';

class LegalTermsItem {
  /// 고정 식별자 (코드에서 참조용)
  final String id;

  /// 화면 표시 제목 (예: '서비스 이용약관')
  final String title;

  /// 약관 전문 내용
  final String content;

  /// 필수 동의 여부 (false = 선택 동의)
  final bool isRequired;

  /// 활성 여부 (false면 동의 목록에서 숨김)
  final bool isActive;

  /// 버전 문자열 (예: '2024.01')
  final String version;

  /// 마지막 수정일
  final DateTime? updatedAt;

  /// 표시 순서
  final int order;

  const LegalTermsItem({
    required this.id,
    required this.title,
    required this.content,
    required this.isRequired,
    this.isActive = true,
    this.version = '1.0',
    this.updatedAt,
    this.order = 0,
  });

  factory LegalTermsItem.fromMap(Map<String, dynamic> map) {
    return LegalTermsItem(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      isRequired: map['isRequired'] as bool? ?? true,
      isActive: map['isActive'] as bool? ?? true,
      version: map['version'] as String? ?? '1.0',
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate().toLocal(),
      order: (map['order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'content': content,
    'isRequired': isRequired,
    'isActive': isActive,
    'version': version,
    'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    'order': order,
  };

  LegalTermsItem copyWith({
    String? title,
    String? content,
    bool? isRequired,
    bool? isActive,
    String? version,
    DateTime? updatedAt,
    int? order,
  }) => LegalTermsItem(
    id: id,
    title: title ?? this.title,
    content: content ?? this.content,
    isRequired: isRequired ?? this.isRequired,
    isActive: isActive ?? this.isActive,
    version: version ?? this.version,
    updatedAt: updatedAt ?? this.updatedAt,
    order: order ?? this.order,
  );
}

class LegalTerms {
  final List<LegalTermsItem> items;
  final DateTime? updatedAt;
  final String? updatedBy;

  const LegalTerms({
    required this.items,
    this.updatedAt,
    this.updatedBy,
  });

  /// 활성 항목만, 순서대로
  List<LegalTermsItem> get activeItems =>
      items.where((t) => t.isActive).toList()
        ..sort((a, b) => a.order.compareTo(b.order));

  factory LegalTerms.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) throw ArgumentError('Document ${doc.id} has no data');
    final data = raw as Map<String, dynamic>;
    final rawItems = (data['items'] as List<dynamic>?) ?? [];
    return LegalTerms(
      items: rawItems
          .map((e) { try { return LegalTermsItem.fromMap(e as Map<String, dynamic>); } catch (_) { return null; } })
          .whereType<LegalTermsItem>()
          .toList(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate().toLocal(),
      updatedBy: data['updatedBy'] as String?,
    );
  }

  static LegalTerms? tryFromFirestore(DocumentSnapshot doc) {
    try { return LegalTerms.fromFirestore(doc); } catch (_) { return null; }
  }

  /// Firestore에 존재하지 않을 때 기본값 (한국 법령 기준)
  static LegalTerms defaultTerms() {
    final now = DateTime.now();
    return LegalTerms(
      items: [
        LegalTermsItem(
          id: 'service_terms',
          title: '서비스 이용약관',
          content: _defaultServiceTerms,
          isRequired: true,
          version: '2025.01',
          updatedAt: now,
          order: 1,
        ),
        LegalTermsItem(
          id: 'privacy_policy',
          title: '개인정보 처리방침',
          content: _defaultPrivacyPolicy,
          isRequired: true,
          version: '2025.01',
          updatedAt: now,
          order: 2,
        ),
        LegalTermsItem(
          id: 'privacy_third_party',
          title: '개인정보 제3자 제공 동의',
          content: _defaultPrivacyThirdParty,
          isRequired: true,
          version: '2025.01',
          updatedAt: now,
          order: 3,
        ),
        LegalTermsItem(
          id: 'location_terms',
          title: '위치정보 이용 동의',
          content: _defaultLocationTerms,
          isRequired: true,
          version: '2025.01',
          updatedAt: now,
          order: 4,
        ),
        LegalTermsItem(
          id: 'marketing_consent',
          title: '마케팅 정보 수신 동의 (선택)',
          content: _defaultMarketingConsent,
          isRequired: false,
          version: '2025.01',
          updatedAt: now,
          order: 5,
        ),
      ],
    );
  }
}

// ── 기본 약관 텍스트 (한국 법령 기준) ─────────────────────────────

const _defaultServiceTerms = '''제1조 (목적)
본 약관은 AlFit(이하 "회사")이 제공하는 인력 매칭 플랫폼 서비스(이하 "서비스")의 이용에 관한 기본적인 사항을 규정합니다.

제2조 (정의)
① "서비스"란 회사가 제공하는 인력 매칭, 근무 관리, 급여 정산 등 제반 서비스를 의미합니다.
② "회원"이란 본 약관에 동의하고 회원가입을 완료한 자를 말합니다.
③ "지원자"란 공고에 지원하여 근무하는 회원을 말합니다.
④ "사업장 관리자"란 근무 공고를 등록하고 지원자를 관리하는 회원을 말합니다.

제3조 (약관의 효력 및 변경)
① 본 약관은 서비스 화면에 게시하거나 기타 방법으로 회원에게 공지함으로써 효력이 발생합니다.
② 회사는 합리적인 사유가 발생할 경우 약관을 변경할 수 있으며, 변경 시 최소 7일 전 앱 내 공지합니다.

제4조 (이용계약 체결)
① 이용계약은 회원이 되려는 자가 약관에 동의하고 가입 신청을 하면, 회사가 이를 승낙함으로써 체결됩니다.
② 만 18세 미만인 자는 서비스에 가입할 수 없습니다.
③ 회사는 다음의 경우 가입 신청을 거부할 수 있습니다.
  - 실명이 아니거나 타인의 정보를 도용한 경우
  - 허위 정보를 기재한 경우
  - 이전에 서비스 이용 제한을 받은 경우

제5조 (회원의 의무)
① 회원은 정확하고 최신의 정보를 제공하며, 변경 시 즉시 수정해야 합니다.
② 회원은 계정(아이디, 비밀번호)을 타인에게 양도·대여할 수 없습니다.
③ 회원은 다음 행위를 해서는 안 됩니다.
  - 타인의 정보를 도용하거나 허위 정보 입력
  - 회사의 운영을 방해하거나 서비스의 정상적인 이용을 저해하는 행위
  - 다른 회원의 개인정보를 무단 수집·이용·제공하는 행위
  - 범죄적 행위를 목적으로 서비스를 이용하는 행위

제6조 (서비스의 내용)
① 회사는 사업장과 구직자를 연결하는 중개 플랫폼을 운영합니다.
② 실제 근로계약은 사업장과 지원자 간에 직접 체결되며, 회사는 중개자로서의 역할만을 합니다.
③ 서비스는 연중무휴 24시간 제공을 원칙으로 하나, 시스템 점검 등의 사유로 일시 중단될 수 있습니다.

제7조 (책임의 한계)
① 회사는 중개 플랫폼으로서 사업장과 지원자 간 근로관계에서 발생하는 분쟁에 대해 직접적인 책임을 지지 않습니다.
② 천재지변, 불가항력으로 인한 서비스 중단에 대하여 책임을 지지 않습니다.
③ 회원이 게재한 정보, 자료의 신뢰도·정확성에 대한 책임은 해당 회원에게 있습니다.

제8조 (서비스 이용 제한)
회사는 회원이 본 약관의 의무를 위반하거나 서비스의 정상적인 운영을 방해한 경우, 경고·이용 정지·영구 이용 제한 등의 조치를 취할 수 있습니다.

제9조 (준거법 및 관할)
본 약관은 대한민국 법률에 따라 해석되며, 분쟁 발생 시 관할 법원은 회사 소재지 관할 법원으로 합니다.''';

const _defaultPrivacyPolicy = '''AlFit은 「개인정보보호법」 제30조에 따라 이용자의 개인정보를 보호하고 관련 고충을 신속하게 처리하기 위해 다음과 같이 개인정보 처리방침을 수립·공개합니다.

■ 수집하는 개인정보의 항목 및 수집 방법
[필수 항목]
이름, 생년월일, 성별, 이메일 주소, 비밀번호, 휴대폰 번호, 주소, 주민등록번호 앞 7자리(연령·성별 확인 목적)

[선택 항목]
신분증 사진, 통장 사본, 계좌번호, 예금주, 프로필 사진, 자기소개

[사업장 관리자 추가 항목]
사업자등록번호, 사업장명, 대표자명, 사업자등록증 사본

[자동 수집 항목]
서비스 이용 기록, 접속 로그, 기기 정보, 위치 정보(GPS)

■ 개인정보의 수집 및 이용 목적
• 회원 식별 및 서비스 제공
• 급여 지급을 위한 계좌 정보 처리
• 근로계약 체결 및 인력 매칭
• 출퇴근 관리 및 위치 인증
• 부정 이용 방지 및 보안 유지
• 고객 상담 및 민원 처리
• 서비스 개선 및 통계 분석

■ 개인정보의 보유 및 이용 기간
• 회원 탈퇴 시 즉시 파기 (법령에 따른 보존 의무 항목 제외)
• 법령에 따른 보존 항목:
  - 계약 또는 청약철회 기록: 5년 (전자상거래법)
  - 소비자 불만·분쟁처리 기록: 3년 (전자상거래법)
  - 서비스 이용 기록: 3개월 (통신비밀보호법)
  - 급여 관련 회계 기록: 5년 (근로기준법)

■ 개인정보의 제3자 제공
회사는 원칙적으로 이용자의 개인정보를 외부에 제공하지 않습니다. 다만, 아래의 경우에는 예외로 합니다.
• 이용자의 동의가 있는 경우
• 급여 지급 목적으로 사업장 관리자에게 지원자의 이름·계좌정보 제공 (별도 동의)

■ 개인정보 처리의 위탁
현재 개인정보 처리를 외부에 위탁하는 업체는 없습니다.

■ 이용자의 권리
이용자는 언제든지 개인정보 열람, 정정, 삭제, 처리 정지를 요구할 수 있습니다.
요청은 앱 내 설정 > 프로필 수정에서 직접 처리하거나, 고객센터로 문의하시기 바랍니다.

■ 개인정보보호 책임자
개인정보 관련 문의는 서비스 내 고객센터를 통해 접수해주세요.

■ 개인정보 처리방침 시행일
본 처리방침은 2025년 1월 1일부터 적용됩니다.''';

const _defaultPrivacyThirdParty = '''■ 개인정보 제3자 제공 동의

AlFit은 아래와 같이 이용자의 개인정보를 제3자에게 제공합니다.

[제공받는 자]
근무 확정된 사업장의 관리자

[제공 목적]
• 근로계약 체결
• 출퇴근 관리
• 급여 지급

[제공하는 개인정보 항목]
• 이름, 휴대폰 번호
• 계좌번호, 은행명, 예금주 (급여 지급 목적)
• 신분증 사본 (신원 확인 목적, 별도 열람 동의 필요)

[보유 및 이용 기간]
근로 관계 종료 후 5년 (급여 관련 법령에 따름)

※ 위 동의를 거부할 권리가 있으나, 거부 시 서비스 이용(공고 지원 및 근무)이 제한될 수 있습니다.''';

const _defaultLocationTerms = '''■ 위치정보 이용 동의

AlFit은 「위치정보의 보호 및 이용 등에 관한 법률」에 따라 아래와 같이 위치정보를 수집·이용합니다.

[수집 목적]
• GPS 기반 출퇴근 체크 (근무지 반경 내 확인)
• 관리자의 실시간 출퇴근 현황 모니터링
• 출근 전 위치 공유 (관리자 사전 모니터링)

[수집 항목]
• GPS 위도·경도 좌표

[이용 및 보유 기간]
• 출퇴근 기록 보존 기간과 동일 (5년)
• 실시간 위치 정보는 출근 처리 후 즉시 중지

[이용 거부 시]
• GPS 방식 출퇴근 체크 불가
• 비콘 또는 수동 방식으로 대체 가능

※ 위치정보 이용 동의를 거부하실 수 있으나, GPS 기반 출퇴근 기능 이용이 제한됩니다.''';

const _defaultMarketingConsent = '''■ 마케팅 정보 수신 동의 (선택)

AlFit은 아래와 같이 마케팅 정보를 발송합니다.

[발송 유형]
• 앱 푸시 알림
• 이메일

[발송 내용]
• 새 공고 알림
• 이벤트 및 프로모션
• 서비스 업데이트 소식

[수신 거부]
• 설정 > 알림 설정에서 언제든지 수신 거부 가능

※ 마케팅 수신 동의를 거부하셔도 서비스 이용에 불이익은 없습니다.''';
