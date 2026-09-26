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
          version: '2026.08',
          updatedAt: now,
          order: 1,
        ),
        LegalTermsItem(
          id: 'privacy_policy',
          title: '개인정보 처리방침',
          content: _defaultPrivacyPolicy,
          isRequired: true,
          // [PII-B4-R1.3A] 외국인등록번호·외국인등록증·공식이름·체류자격 수집 고지 추가,
          //   주민등록번호 항목을 실제 동작(신규 미수집)에 맞게 정정.
          // [PRIVACY-REWRITE.1] 앱 없이 삭제를 요청할 수 있는 웹 경로와
          //   계정 삭제 시 데이터 처리(즉시 삭제·법정 보존·식별자 제거·재가입
          //   제한 보관) 고지 추가. 공개 페이지는 이 원문에서 생성한다.
          version: kPrivacyPolicyRevision,
          updatedAt: now,
          order: 2,
        ),
        LegalTermsItem(
          id: 'privacy_third_party',
          title: '개인정보 제3자 제공 동의',
          content: _defaultPrivacyThirdParty,
          isRequired: true,
          version: '2026.08',
          updatedAt: now,
          order: 3,
        ),
        LegalTermsItem(
          id: 'location_terms',
          title: '위치정보 이용 동의',
          content: _defaultLocationTerms,
          isRequired: true,
          version: '2026.08',
          updatedAt: now,
          order: 4,
        ),
        LegalTermsItem(
          id: 'marketing_consent',
          title: '마케팅 정보 수신 동의 (선택)',
          content: _defaultMarketingConsent,
          isRequired: false,
          version: '2026.08',
          updatedAt: now,
          order: 5,
        ),
      ],
    );
  }
}

// ── 기본 약관 텍스트 (한국 법령 기준) ─────────────────────────────

const _defaultServiceTerms = '''제1조 (목적 및 사업자 정보)
본 약관은 AlFit(이하 "회사")이 제공하는 인력 매칭 플랫폼 서비스(이하 "서비스")의 이용에 관한 기본적인 사항을 규정합니다.

[사업자 정보]
서비스명: AlFit
대표자: [대표자명 기재 필요]
사업장 소재지: [사업장 주소 기재 필요]
사업자등록번호: [사업자등록번호 기재 필요]
고객센터: corebridge87@gmail.com

제2조 (정의)
① "서비스"란 회사가 제공하는 인력 매칭, 근무 관리, 급여 정산 등 제반 서비스를 의미합니다.
② "회원"이란 본 약관에 동의하고 회원가입을 완료한 자를 말합니다.
③ "지원자"란 공고에 지원하여 근무하는 회원을 말합니다.
④ "사업장 관리자"란 근무 공고를 등록하고 지원자를 관리하는 회원을 말합니다.

제3조 (약관의 효력 및 변경)
① 본 약관은 서비스 화면에 게시하거나 기타 방법으로 회원에게 공지함으로써 효력이 발생합니다.
② 회사는 합리적인 사유가 발생할 경우 약관을 변경할 수 있으며, 변경 시 다음 기간 전 앱 내 공지합니다.
  - 이용자에게 유리하거나 중립적인 변경: 최소 7일 전
  - 이용자에게 불리한 변경: 최소 30일 전 (불리한 변경 사항을 명확히 표시)
③ 이용자는 변경된 약관에 동의하지 않을 경우 서비스 이용을 중단하고 탈퇴할 수 있습니다. 공지 후 계속 이용 시 변경 약관에 동의한 것으로 봅니다.

제4조 (이용계약 체결)
① 이용계약은 회원이 되려는 자가 약관에 동의하고 가입 신청을 하면, 회사가 이를 승낙함으로써 체결됩니다.
② 만 19세 미만인 자는 서비스에 가입할 수 없습니다. (본인인증으로 자동 확인)
③ 회사는 다음의 경우 가입 신청을 거부할 수 있습니다.
  - 실명이 아니거나 타인의 정보를 도용한 경우
  - 허위 정보를 기재한 경우
  - 이전에 서비스 이용 제한을 받은 경우

제5조 (회원의 의무)
① 회원은 정확하고 최신의 정보를 제공하며, 변경 시 즉시 수정해야 합니다.
② 회원은 본인 명의로 가입한 계정(본인인증 기반)을 타인에게 양도·대여할 수 없습니다.
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

제9조 (분쟁 해결 및 관할)
① 서비스 이용과 관련한 분쟁은 고객센터(corebridge87@gmail.com)를 통해 우선 해결합니다.
② 본 약관은 대한민국 법률에 따라 해석되며, 소송이 제기될 경우 회사 소재지를 관할하는 법원을 합의 관할 법원으로 합니다.

■ 시행일: 2026년 8월 1일''';

/// [PRIVACY-REWRITE.1] 개인정보처리방침 개정 번호 — 앱과 공개 웹이 같은 값을
/// 보여야 한다. 공개 페이지(public/privacy.html)는 `scripts/render-privacy.js`
/// 가 아래 원문에서 생성하므로, 내용이 갈라지려면 이 파일을 고쳐야 한다.
/// 값은 **시행일과 같은 날짜**다. `2026.10` 처럼 월만 적으면 시행일보다
/// 나중처럼 읽혀 어느 판이 적용 중인지 헷갈린다.
const kPrivacyPolicyRevision = '2026-09-26';

/// 공개 페이지 렌더러가 읽는 원문의 시작 표식. 바꾸면 렌더러도 함께 고쳐야 한다.
// [PRIVACY-FIX 2026-08-10] 이메일 corebridge87@gmail.com로 통일, 카카오 위탁업체 추가, 아동 개인정보 조항 추가, 시행일 업데이트
const _defaultPrivacyPolicy = '''AlFit은 「개인정보보호법」 제30조에 따라 이용자의 개인정보를 보호하고 관련 고충을 신속하게 처리하기 위해 다음과 같이 개인정보 처리방침을 수립·공개합니다.

■ 수집하는 개인정보의 항목 및 수집 방법

[회원가입 시 필수 수집 항목]
이름, 생년월일, 성별, 휴대폰 번호, 주소
(본인인증을 통해 자동 수집되며, 이용자가 직접 입력하지 않습니다)

[본인인증 결과 수집 항목]
암호화된 이용자 확인값(CI) — 동일인 식별을 위한 고유값, AES 암호화 저장

[외국인 회원가입 시 수집 항목 — 필수]
외국인등록번호 13자리 — 동일인 식별(중복 가입 방지)을 위해 입력받습니다.
  서버에서 복원이 불가능한 고유값으로 변환해 보관하며, 번호 원문은 저장하지 않습니다.
외국인등록증 사진 — 신분 확인 서류
외국인등록증에 기재된 공식 이름(영문 등)
체류자격(비자 종류) — 근로 조건 안내 및 제출 서류 확인 목적으로만 보관합니다.
  회사는 취업 가능 여부나 체류 자격의 적법성을 심사·판정하지 않습니다.

[이용 중 추가 수집 항목 — 선택]
신분증 사진, 통장 사본, 계좌번호·은행명·예금주, 프로필 사진, 자기소개
주민등록번호 — 현재 수집하지 않습니다.
  (과거 가입 시 입력된 값이 남아 있는 경우 AES 암호화 상태로 보관하며,
   파기 기준은 아래 '보유 및 이용 기간'에 따릅니다)

[근로계약 체결 시 수집 항목 — 선택]
전자 서명 이미지, 날인(도장) 이미지

[사업장 관리자 추가 수집 항목]
사업자등록번호, 사업장명, 대표자명, 사업자등록증 사본

[자동 수집 항목]
서비스 이용 기록, 접속 로그
기기 식별자(FCM 토큰) — 푸시 알림 전송 목적, 기기당 1개, 최대 5개 저장
출퇴근 시 GPS 위도·경도 좌표 — 출퇴근 기록에 포함되어 저장
신분증·외국인등록증 OCR 텍스트 인식 — 기기 내에서 처리하며 인식된 원문은 서버에 저장하지 않습니다.
  다만 외국인등록번호는 동일인 식별을 위해 서버로 전송되며, 고유값 변환 후 원문은 저장되지 않습니다.
블루투스 기기 정보 — 비콘 방식 출퇴근 사용 시에만 수집

■ 개인정보의 수집 및 이용 목적
• 본인 확인 및 회원 식별
• 급여 지급을 위한 계좌 정보 처리
• 급여 공제 계산 및 소득신고·원천징수 등 법정 세무 처리
• 본인 및 제출 서류 정보의 정합성 확인
• 근로계약 체결 및 인력 매칭
• GPS·비콘 기반 출퇴근 인증 및 기록 관리
• 부정 이용 방지 및 보안 유지 (위치 스푸핑 감지 포함)
• 푸시 알림 발송
• 앱 충돌 분석 및 서비스 품질 개선
• 이용 통계 분석

■ 개인정보의 보유 및 이용 기간

[보유 기간]
• 회원 탈퇴 시 즉시 파기 (법령에 따른 보존 의무 항목 제외)
• 법령에 따른 보존 항목:
  - 근로자 명부, 근로계약서 등 근로계약에 관한 중요한 서류: 3년 (근로기준법 제42조)
  - 임금대장 및 임금의 결정·지급 방법에 관한 서류: 3년 (근로기준법 제42조)
  - 출퇴근 기록: 임금 계산의 근거가 되는 기록으로 보존하며,
    위 근로계약 관련 서류와 같은 기간을 적용합니다.
  - 소득신고·원천징수 등 세무 관련 자료: 관계 세법이 정한 기간
  - 이용자 문의 및 분쟁 처리 기록: 분쟁 대응에 필요한 기간
  - 서비스 접속·이용 로그: 서비스 보안, 오류 분석, 부정 이용 방지에 필요한
    기간 (특정 법률에 따른 의무 보관이 아니며, 목적이 끝나면 파기합니다)
  - 계정 삭제 요청 처리 기록: 삭제 요청의 처리 경위를 확인하기 위한 기록으로,
    요청번호·대상 계정 식별자·계정 유형·처리자·처리 사유·처리 시각·수행 결과가
    남으며, 신분증·통장 사본·계좌번호·세무 식별번호는 포함하지 않습니다.

  위 항목 중 구체적인 기간이 적혀 있지 않은 것은, 근거가 확인되지 않은 기간을
  임의로 적지 않기 위해서입니다. 관련 법령 및 세무·법률 검토에 따라 확정한 뒤
  이 방침에 반영합니다.

[민감 원본과 근무·지급 기록의 구분]
• 신분증·외국인등록증 이미지, 통장 사본, 세무 식별번호와 같은 민감 원본은
  이용 목적이 끝나면 지체 없이 파기하며, 탈퇴 시에는 즉시 삭제합니다.
• 근무 사실, 임금 산정 결과와 지급 여부, 이체·취소 이력, 계약과 근태·임금의
  연결 관계, 세무·회계 증빙은 법적·세무·분쟁 대응 목적의 별도 보존 대상이며,
  현재 자동 삭제는 적용하지 않습니다. 구체적인 보존기간·기산점·삭제 방식은
  관련 법령 및 세무·법률 검토에 따라 확정합니다.
• 민감 원본을 목적 종료 시 삭제한다고 해서, 위 지급 증빙이 함께 삭제된다는
  뜻은 아닙니다.

[파기 절차 및 방법]
• 보유 기간이 경과하거나 처리 목적이 달성된 개인정보는 지체 없이 파기합니다.
• 전자적 파일 형태: 복원이 불가능한 방법으로 영구 삭제

■ 개인정보의 제3자 제공
회사는 원칙적으로 이용자의 개인정보를 외부에 제공하지 않습니다. 다만, 아래의 경우에는 예외로 합니다.
• 이용자의 동의가 있는 경우
• 급여 지급 목적으로 사업장 관리자에게 지원자의 이름·계좌정보 제공 (별도 동의)
• 법령에 따른 수사기관의 적법한 요청이 있는 경우

■ 개인정보 처리의 위탁

[수탁 업체 및 위탁 업무]
• 포트원(PortOne Inc.): 본인인증 SDK 중계
• KG이니시스: 본인인증(KG이니시스 통합인증) 서비스 제공
• 카카오(Kakao Corp.): 지도 서비스(카카오맵) — 출퇴근 위치 시각화 목적

각 수탁 업체는 위탁 목적 범위를 초과하여 개인정보를 이용하지 않습니다.

■ 개인정보의 국외 이전

회사는 서비스 제공을 위해 아래와 같이 개인정보를 국외로 이전합니다.

[이전받는 자]
Google LLC (미국)

[이전 목적]
데이터베이스 저장(Firestore), 파일 저장소(Storage), 서버리스 함수 실행(Cloud Functions), 앱 무결성 검증(App Check), 앱 충돌 분석(Crashlytics), 이용 통계 분석(Analytics), 인증 관리(Authentication)

[이전되는 항목]
회원가입 시 수집된 개인정보 및 서비스 이용 중 생성된 데이터 전반

[이전 국가]
미국

[보유 및 이용 기간]
서비스 이용 기간 및 법령상 보존 기간

[이전 방법]
네트워크를 통한 전송 (HTTPS 암호화)

Google LLC는 EU-US Data Privacy Framework 인증을 보유하며, Google의 개인정보처리방침(https://policies.google.com/privacy)에 따라 데이터를 보호합니다.

■ 개인정보 안전성 확보 조치

회사는 「개인정보보호법」 제29조에 따라 다음과 같은 안전성 확보 조치를 취하고 있습니다.
• 개인정보 암호화: 이용자 확인값(CI)과 외국인등록번호는 복원이 불가능한 고유값으로 변환해 보관하며,
  과거 저장된 주민등록번호·계좌번호 등 민감 정보는 AES 암호화 상태로 보관
• 전송 구간 암호화: 모든 통신은 HTTPS(TLS) 암호화 적용
• 접근 권한 제한: Firebase Security Rules를 통해 본인 데이터에만 접근 허용
• 접속 기록 보관: Firebase 감사 로그를 통해 접근 기록 보관 및 관리
• 해킹 방지: Firebase App Check를 통한 앱 무결성 검증

■ 이용자의 권리 및 행사 방법

이용자는 언제든지 다음 권리를 행사할 수 있습니다.
• 개인정보 열람, 정정, 삭제, 처리 정지 요구
• 회원 탈퇴 (계정 삭제)

[권리 행사 방법]
• 앱 내: 설정 화면 > 프로필 수정 (열람·정정)
• 앱 내: 설정 화면 > 회원탈퇴 (계정 삭제, 즉시 처리)
• 앱 없이 웹에서 요청: https://alfit-89567.web.app/account-deletion
  앱을 설치하거나 다시 로그인하지 않아도 계정 삭제를 요청할 수 있습니다.
• 이메일 문의: corebridge87@gmail.com
  (본인 확인과 법령상 보존 대상 여부를 확인한 뒤 처리하며, 완료 시 회신합니다)

■ 계정 삭제 시 데이터 처리

계정을 삭제하면 아래와 같이 처리됩니다. 앱에서 직접 탈퇴하든 웹으로 요청하든
같은 기준을 적용합니다.

[즉시 삭제]
• 계정(로그인 정보) 및 회원 정보
• 신분증·외국인등록증·통장 사본 등 업로드한 문서 파일
• 세무 처리용으로 보관하던 식별번호 정보
• 신분증 열람 요청 기록, 받은 멤버 초대 기록

[법령·계약에 따라 보존]
• 위 '보유 및 이용 기간'에 적힌 항목은 해당 기간 동안 보존됩니다.
• 이미 일한 근무 기록과 임금 산정·지급 결과, 이체 이력은 법적·세무·분쟁 대응
  목적의 별도 보존 대상이며, 탈퇴로 함께 삭제되지 않습니다. 임금을 지급했다는
  사실이 법적 증빙이기 때문입니다.
• 진행 중이던 지원은 취소 처리되고, 예정 근무는 미근무로 정리됩니다.

[직접 식별정보를 제거한 뒤 유지]
• 주고받은 평가, 신뢰도 변동 이력, 초대 발송 기록에서는 이용자 식별자를
  다른 값으로 바꿔 직접 식별정보를 제거하고, 기록 자체는 남깁니다.
• 이 처리는 직접 식별정보를 지우는 것이며, 남은 기록의 시점이나 사업장
  관계까지 지우는 완전한 비식별 처리를 뜻하지는 않습니다.

[삭제 처리 기록]
• 삭제 요청을 접수해 처리한 경위는 별도로 남깁니다. 요청번호, 대상 계정
  식별자, 계정 유형, 처리자, 처리 사유, 처리 시각과 수행 결과가 기록되며,
  신분증·통장 사본·계좌번호·세무 식별번호는 포함하지 않습니다.
• 대상 계정 식별자는 어느 요청을 어떻게 처리했는지 확인하기 위한 값으로,
  삭제 요청 처리·보안·분쟁 대응 목적에 한해 제한적으로 보관될 수 있습니다.
• 보존 기간은 관련 법령 검토에 따라 확정합니다.

[재가입 제한을 위한 최소 보관]
• 탈퇴 후 30일간 동일인 재가입을 제한하기 위해, 본인확인 결과에서 만들어진
  복원 불가능한 고유값과 탈퇴 시각을 별도로 보관합니다.
• 이 값은 재가입 제한과 부정 이용 차단 외의 목적으로 사용하지 않습니다.

■ 아동 개인정보 보호

본 서비스는 만 19세 이상 성인만 이용 가능합니다. 본인인증 과정에서 만 19세 미만으로 확인될 경우 가입이 즉시 차단됩니다.

본 서비스는 만 14세 미만 아동을 대상으로 하지 않으며, 만 14세 미만의 개인정보를 의도적으로 수집하지 않습니다. 만 14세 미만 이용자의 정보가 수집된 사실이 확인될 경우, 해당 정보를 즉시 삭제합니다.

■ 개인정보보호 책임자
• 서비스명: AlFit
• 담당자: AlFit 운영팀
• 문의 이메일: corebridge87@gmail.com
• 개인정보 침해 신고: 개인정보 침해신고센터 (privacy.kisa.or.kr / 국번없이 118)

■ 처리방침의 개정
서비스 변경으로 수집 항목이나 이용 목적이 달라지는 경우, 변경 내용과 시행일을
사전에 고지하고 필요한 경우 별도의 동의를 받은 뒤 개정된 처리방침을 적용합니다.

■ 개인정보 처리방침 시행일
본 처리방침은 2026년 9월 26일부터 적용됩니다. (개정 2026-09-26)
이전 시행일: 2026년 9월 20일''';

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
• 신분증 사본 (신원 확인 목적, 사업장 관리자가 별도 요청 시 공개)
• 출퇴근 기록 (근무 시작·종료 시각, GPS 좌표 포함)
• 지원 이력 및 근무 기록

[보유 및 이용 기간]
근로 관계 종료 후 5년 (급여 관련 법령에 따름)

※ 위 동의를 거부할 권리가 있으나, 거부 시 서비스 이용(공고 지원 및 근무)이 제한될 수 있습니다.''';

const _defaultLocationTerms = '''■ 위치정보 이용 동의

AlFit은 「위치정보의 보호 및 이용 등에 관한 법률」에 따라 아래와 같이 위치정보를 수집·이용합니다.

[위치기반서비스 사업자 정보]
서비스명: AlFit
사업자: [회사명 기재 필요]
연락처: corebridge87@gmail.com

[수집 목적]
• GPS 기반 출퇴근 체크 (근무지 반경 내 위치 확인)
• 출퇴근 시 위치 기반 알림 발송 (관리자·근로자에게 체크인/아웃 알림)
• 위치 스푸핑(Mock GPS) 감지를 통한 부정 출퇴근 방지

[수집 항목]
• GPS 위도·경도 좌표 (출퇴근 체크 시 1회 수집)
• 블루투스 기기 신호 (비콘 방식 출퇴근 사용 시에만 수집)

[이용 및 보유 기간]
• 출퇴근 시 체크한 GPS 좌표는 출퇴근 기록과 함께 5년간 보존 (근로기준법)
• 위치 정보는 출퇴근 체크 시 1회만 수집되며, 근무 중 지속 수집되지 않습니다.

[이용 거부 시]
• GPS 방식 출퇴근 체크 불가
• 비콘 또는 수동 방식으로 대체 가능

※ 위치정보 이용 동의를 거부하실 수 있으나, GPS 기반 출퇴근 기능 이용이 제한됩니다.''';

const _defaultMarketingConsent = '''■ 마케팅 정보 수신 동의 (선택)

AlFit은 아래와 같이 마케팅 정보를 발송합니다.

[발송 유형]
• 앱 푸시 알림

[발송 내용]
• 새 공고 알림
• 이벤트 및 프로모션
• 서비스 업데이트 소식

[수신 거부]
• 설정 > 알림 설정에서 언제든지 수신 거부 가능

※ 마케팅 수신 동의를 거부하셔도 서비스 이용에 불이익은 없습니다.''';
