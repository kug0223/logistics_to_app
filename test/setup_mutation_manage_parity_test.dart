// [R7-P4.4E.3] Home 준비 CTA 에서 한 일이 관리 탭에서도 같은 사실이어야 한다.
//
//   실기기 반례: Home 준비 카드에서 인감을 등록하면 Home 은 완료로 바뀌는데
//   관리 탭은 계속 '미등록' 이었다. 같은 값을 두고 두 화면이 다른 말을 했다.
//
//   원인은 데이터가 갈린 것이 아니라 **화면이 값을 복사해 들고 있던 것**이다.
//   관리 탭 root 는 IndexedStack 안에서 계속 살아 있고, 인감 값을 initState
//   에서 한 번 읽어 둔 뒤 다시 읽는 곳이 없었다. Home 의 CTA 가 여는 것은
//   **다른 인스턴스**라 그쪽에서 저장해도 이쪽은 모른다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _settings() =>
    File('lib/screens/common/settings_screen.dart').readAsStringSync();
String _home() =>
    File('lib/screens/business_admin/business_admin_home_screen.dart')
        .readAsStringSync();
String _resolver() =>
    File('lib/services/business_posting_readiness.dart').readAsStringSync();
String _picker() =>
    File('lib/utils/business_picker_helper.dart').readAsStringSync();

void main() {
  group('[R7-P4.4E.3] 업무 — 같은 사업장·같은 질의', () {
    test('SETUP-PARITY-01 Home CTA 와 관리 탭이 같은 화면·같은 businessId 로 간다', () {
      expect(_home().contains('WorkTypeManagementScreen('), isTrue);
      expect(_home().contains('businessId: wtTarget.id'), isTrue);
      final s = _settings();
      expect(s.contains('WorkTypeManagementScreen('), isTrue);
      expect(s.contains('businessId: biz.id'), isTrue,
          reason: '두 입구가 다른 사업장으로 가면 쓴 곳과 읽는 곳이 갈린다');
    });

    test('SETUP-PARITY-02 준비 판정과 관리 화면이 같은 질의를 쓴다', () {
      // readiness 는 resolver → BusinessPostingReadiness.forBusiness 경유로
      // 같은 서비스 메서드를 부른다.
      expect(_resolver().contains('firestoreService.getBusinessWorkTypes(biz.id)'),
          isTrue);
      final manage =
          File('lib/screens/business_admin/work_type_management_screen.dart')
              .readAsStringSync();
      expect(manage.contains('getBusinessWorkTypes(widget.businessId)'), isTrue,
          reason: '술어가 두 벌이면 한쪽만 0개로 보인다');
    });

    test('SETUP-PARITY-02b 관리 화면은 진입할 때마다 다시 읽는다', () {
      final manage =
          File('lib/screens/business_admin/work_type_management_screen.dart')
              .readAsStringSync();
      // push 될 때마다 새 State 가 만들어지고 거기서 읽는다 — 복사본이 없다.
      expect(manage.contains('void initState()'), isTrue);
      expect(manage.contains('getBusinessWorkTypes(widget.businessId)'), isTrue);
    });
  });

  group('[R7-P4.4E.3] 계약서 템플릿 — 같은 사업장·같은 질의', () {
    test('SETUP-PARITY-03 두 입구가 같은 화면·같은 businessId 로 간다', () {
      expect(_home().contains('ContractTemplateListScreen('), isTrue);
      expect(_home().contains('businessId: tplTarget.id'), isTrue);
      expect(
          _settings().contains('ContractTemplateListScreen(businessId: biz.id)'),
          isTrue);
    });

    test('SETUP-PARITY-04 준비 판정과 목록이 같은 서비스를 쓴다', () {
      final reads =
          File('lib/screens/business_admin/admin_home_reads.dart')
              .readAsStringSync();
      expect(reads.contains('contractTemplates: templateSvc.getTemplates'), isTrue);
      final list = File(
              'lib/screens/business_admin/contract_template_list_screen.dart')
          .readAsStringSync();
      expect(list.contains('_service.getTemplates(widget.businessId)'), isTrue,
          reason: '사업장 전용 template 정책(P4.4C.0)을 양쪽이 같게 읽는다');
    });
  });

  group('[R7-P4.4E.3] 인감 — 복사본을 들고 있지 않는다', () {
    test('SETUP-PARITY-05 관리 탭 인감 카드는 provider 에서 읽는다', () {
      final s = _settings();
      expect(s.contains('final sealBase64 = user?.sealBase64;'), isTrue,
          reason: '바로 옆 서명 카드와 같은 규칙이다');
      expect(s.contains('final hasSeal = sealBase64 != null && sealBase64.isNotEmpty;'),
          isTrue);
    });

    test('SETUP-PARITY-05b 한 번 읽어 두는 필드가 사라졌다', () {
      // 주석은 제외한다 — 왜 없앴는지 남긴 설명까지 금지하면 근거가 사라진다.
      final code = _settings()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code.contains('_businessSealBase64'), isFalse,
          reason: '복사본이 남아 있으면 다시 같은 방식으로 갈라진다');
    });

    test('SETUP-PARITY-06 저장 경로가 provider 를 갱신한다', () {
      final s = _settings();
      // 저장·삭제 모두 refreshUserData 를 거친다 — 그래야 다른 화면까지 닿는다.
      expect('await userProvider.refreshUserData();'.allMatches(s).length,
          greaterThanOrEqualTo(2));
    });

    test('SETUP-PARITY-06b 새 listener 나 polling 을 추가하지 않았다', () {
      final s = _settings();
      expect(s.contains('Timer.periodic'), isFalse);
      // 이미 있는 provider 알림을 쓴다 — 갱신 경로를 새로 만들지 않는다(§20).
      expect(s.contains('Selector<UserProvider'), isTrue);
    });

    test('SETUP-PARITY-06c 서명 카드의 규칙은 그대로다', () {
      expect(_settings().contains('final signatureBase64 = user?.signatureBase64;'),
          isTrue, reason: '인감을 여기에 맞춘 것이다 — 반대로 바꾸지 않는다');
    });
  });

  group('[R7-P4.4E.3] 사업장 context', () {
    test('SETUP-PARITY-07 단일 사업장이면 관리 탭도 그 사업장으로 간다', () {
      expect(_picker().contains('if (businesses.length == 1) return businesses.first;'),
          isTrue, reason: '고르라고 묻지 않고 그 하나로 간다');
      expect(_picker().contains('businesses.where((b) => b.isApproved)'), isTrue);
    });

    test('SETUP-PARITY-07b 조회 실패를 "사업장 없음" 으로 바꾸지 않는다', () {
      final p = _picker();
      expect(p.contains('getBusinessesByIdsOrThrow'), isTrue);
      expect(p.contains('사업장 목록을 불러오지 못했습니다'), isTrue,
          reason: '못 읽은 것과 0개는 다른 말이다');
    });

    test('SETUP-PARITY-08 계정이 바뀌면 인감이 따라 바뀐다', () {
      // provider 에서 읽으므로 로그아웃·전환 시 이전 계정 값이 남지 않는다.
      final s = _settings();
      expect(s.contains('user?.sealBase64'), isTrue);
      expect(s.contains('_loadBusinessSeal()'), isTrue,
          reason: '사업장 id 해석은 남는다 — 인감 값만 provider 로 옮겼다');
    });
  });
}
