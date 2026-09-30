// [R7-P4.4E.2] Home ↔ 공고 root ↔ CreateTO 가 **같은 진실**을 말한다.
//
//   실기기에서 같은 사업장을 두고 세 화면이 다른 말을 했다:
//     Home       "공고 등록까지 3단계 남았어요"
//     공고 root   "등록된 공고가 없습니다" + [+ 새 공고 등록]
//     CreateTO   5가지 체크리스트 + "사업자등록증" 미등록
//   그런데 서버는 그 등록증을 READY 로 보고 있었다.
//
//   사용자를 할 수 없는 행동으로 안내하지 않는 것이 이 파일의 계약이다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/services/business_posting_readiness.dart';

String _jobsRoot() =>
    File('lib/screens/business_admin/jobs_root_screen.dart').readAsStringSync();
String _createTO() => File(
        'lib/screens/business_admin/to_management/create_to_screen.dart')
    .readAsStringSync();
String _home() =>
    File('lib/screens/business_admin/business_admin_home_screen.dart')
        .readAsStringSync();
String _service() =>
    File('lib/services/business_posting_readiness.dart').readAsStringSync();

FirstPostingReadiness _readiness({
  bool business = true,
  bool workTypes = false,
  bool template = false,
  bool seal = false,
}) {
  return FirstPostingReadiness(
    hasAnyBusiness: true,
    businessReady: business,
    workTypesReady: workTypes,
    workTypesUnknown: false,
    contractTemplateReady: template,
    sealReady: seal,
  );
}

void main() {
  setUp(FirstPostingReadinessBroadcast.clear);
  tearDown(FirstPostingReadinessBroadcast.clear);

  group('[R7-P4.4E.2] Home ↔ 공고 root parity', () {
    test('SETUP-ROOT-01 Home 1/4 면 공고 root 는 SETUP_REQUIRED 다', () {
      final r = _readiness();
      expect(r.completedCount, 1);
      expect(r.allReady, isFalse);

      final src = _jobsRoot();
      expect(src.contains('final setupRequired = readiness != null && !readiness.allReady;'),
          isTrue, reason: '공고 root 가 Home 과 같은 값을 본다');
      expect(src.contains('_JobsSetupRequiredView('), isTrue);
    });

    test('SETUP-ROOT-02 Home 4/4 면 정상 root 다', () {
      final r = _readiness(workTypes: true, template: true, seal: true);
      expect(r.completedCount, FirstPostingReadiness.totalTasks);
      expect(r.allReady, isTrue);

      expect(
        _jobsRoot().contains(': WorkforceListView(targetToId: _targetToId)'),
        isTrue,
        reason: '준비가 끝나면 운영 목록을 그대로 그린다',
      );
    });

    test('SETUP-ROOT-03 SETUP_REQUIRED 에서 정상 empty 문구를 쓰지 않는다', () {
      final src = _jobsRoot();
      final setupView = src.substring(src.indexOf('class _JobsSetupRequiredView'));
      expect(setupView.contains('등록된 공고가 없습니다'), isFalse,
          reason: '아직 등록할 수 없는 상태를 "없다" 로 말하면 잘못된 행동을 유도한다');
      expect(setupView.contains('아직 공고를 등록할 준비가 끝나지 않았어요'), isTrue);
    });

    test('SETUP-ROOT-04 SETUP_REQUIRED 에서 + create affordance 가 없다', () {
      final src = _jobsRoot();
      expect(src.contains('!setupRequired)'), isTrue,
          reason: '권한만 보고 버튼을 띄우면 막힐 행동을 권하는 것이다');
      // disabled 로 두지 않는다 — 왜 안 되는지 말하지 못한다.
      expect(src.contains('onTap: null'), isFalse);
    });

    test('SETUP-ROOT-05 모르면(null) 화면을 바꾸지 않는다', () {
      // §25 — UNKNOWN 은 SETUP_REQUIRED 가 아니다.
      expect(FirstPostingReadinessBroadcast.current.value, isNull);
      expect(_jobsRoot().contains('readiness != null &&'), isTrue,
          reason: 'null 을 미완료로 읽으면 준비된 관리자에게 거짓을 말한다');
    });

    test('SETUP-ROOT-07 헤더는 빌더의 context 로 구독한다', () {
      // 실기기에서 공고 탭이 빨간 화면이 됐다:
      //   'Tried to use context.select outside of the build method of a widget.'
      // 헤더를 ValueListenableBuilder 콜백 안에서 만들면서, 그 안의 select 가
      // State 의 context(그 순간 build 중이 아니다)를 쓰고 있었다.
      final src = _jobsRoot();
      expect(
          src.contains(
              'Widget _buildHeader(BuildContext context, double s, bool setupRequired)'),
          isTrue,
          reason: '호출하는 빌더의 context 를 받아야 select 가 성립한다');
      expect(src.contains('_buildHeader(ctx, s, setupRequired)'), isTrue,
          reason: 'State 의 context 를 넘기면 같은 assert 로 다시 죽는다');
    });

    test('SETUP-ROOT-06 공고 탭 자체는 유지한다', () {
      final shell = File('lib/screens/business_admin/business_admin_shell.dart')
          .readAsStringSync();
      expect(shell.contains('JobsRootScreen(postingController: _postingController)'),
          isTrue, reason: '§8 — 탭 숨김·disable·자동 redirect 를 하지 않는다');
    });
  });

  group('[R7-P4.4E.2] CreateTO license parity', () {
    test('LICENSE-PARITY-01 CreateTO 가 license 를 다시 판정하지 않는다', () {
      final src = _createTO();
      expect(
        src.contains(
            'await BusinessPostingReadiness.hasLicenseForBusiness(biz)'),
        isTrue,
        reason: '공용 resolver 한 벌만 쓴다',
      );
      // 인라인 레거시 전용 술어가 되살아나지 않는다.
      expect(
        src.contains("ownerSnap.data()?['businessLicenseImageUrl']"),
        isFalse,
        reason: 'path 를 못 보는 술어는 신규 등록자를 미등록으로 만든다',
      );
    });

    test('LICENSE-PARITY-02 공용 resolver 는 서버와 같은 순서로 본다', () {
      final src = _service();
      final i = src.indexOf('static bool _ownerHasLicense');
      final body = src.substring(i, i + 500);
      final pathIdx = body.indexOf('businessLicenseImagePath');
      final urlIdx = body.indexOf('businessLicenseImageUrl');
      expect(pathIdx, greaterThan(-1));
      expect(urlIdx, greaterThan(pathIdx),
          reason: 'canonical path 우선, 레거시 URL 폴백 — checkBusinessLicense 와 같다');
    });

    test('LICENSE-PARITY-03 둘 다 없으면 NOT_READY 다', () {
      const r = BusinessPostingReadiness(
        bizId: 'b1',
        isApproved: true,
        hasCanonicalLicense: false,
        hasOwnerLegacyLicense: false,
        hasActiveWorkTypes: true,
        workTypesUnknown: false,
        hasEmployerSeal: true,
        employerSealUnknown: false,
      );
      expect(r.hasLicense, isFalse);
      expect(r.isReady, isFalse);
    });

    test('LICENSE-PARITY-04 owner 경로만 있어도 READY 다', () {
      const r = BusinessPostingReadiness(
        bizId: 'b1',
        isApproved: true,
        hasCanonicalLicense: false,
        hasOwnerLegacyLicense: true,
        hasActiveWorkTypes: true,
        workTypesUnknown: false,
        hasEmployerSeal: true,
        employerSealUnknown: false,
      );
      expect(r.hasLicense, isTrue, reason: '신규 등록은 owner 경로로만 남는다');
      expect(r.isReady, isTrue);
    });
  });

  group('[R7-P4.4E.2] task owner 는 Home 하나다', () {
    test('READINESS-TASKS-01 사용자에게 보이는 task 는 4개다', () {
      expect(FirstPostingReadiness.totalTasks, 4);
    });

    test('READINESS-TASKS-02 CreateTO 가 5개짜리 체크리스트를 다시 소유하지 않는다', () {
      final src = _createTO();
      expect(src.contains('_buildPrerequisiteCard'), isFalse,
          reason: '§15 — Home 과 별도 task owner 가 되지 않는다');
      expect(src.contains('가지를 모두 완료해야 공고를 등록할 수 있습니다'), isFalse);
      expect(src.contains('공고 등록 준비가 필요해요'), isTrue,
          reason: 'gate + 돌아갈 길만 맡는다');
    });

    test('READINESS-TASKS-03 사업자등록증을 사용자 task 로 다시 노출하지 않는다', () {
      final src = _createTO();
      final i = src.indexOf('Widget _buildPrerequisiteScreen');
      // 주석은 제외한다 — 계약은 **화면에 그려지는 문자열**에 대한 것이고,
      // 왜 뺐는지 설명한 주석까지 금지하면 근거를 남길 수 없다.
      final screen = src
          .substring(i, i + 3000)
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(screen.contains('사업자등록증'), isFalse,
          reason: '§24 — 서버 기술 축을 사용자 task 로 다시 세우지 않는다');
    });

    test('READINESS-TASKS-05 목적 설명은 라벨 아래 줄이다', () {
      // 실기기에서 라벨이 '계약 / 서 템 / 플릿' 으로 쪼개졌다 —
      // 오른쪽 힌트 슬롯은 폭을 나눠 갖는 자리라 문장이 들어가면 라벨이 눌린다.
      final src = _home();
      expect(src.contains("purpose: '한 번 만들면 이후 계약에도 계속 사용할 수 있어요'"),
          isTrue, reason: '안내는 남는다 — 자리만 옮겼다');
      expect(src.contains("pendingHint: '한 번 만들면"), isFalse,
          reason: '긴 문장을 짧은 상태 슬롯에 넣지 않는다');
      expect(src.contains('if (purpose != null && !done)'), isTrue,
          reason: '이미 끝난 항목에 이유를 다시 말하지 않는다');
    });

    test('READINESS-TASKS-04 남은 개수는 Home 이 센 값을 쓴다', () {
      final src = _createTO();
      expect(src.contains('FirstPostingReadinessBroadcast.current.value'), isTrue);
      expect(src.contains('FirstPostingReadiness.totalTasks - r.completedCount'),
          isTrue, reason: '여기서 다시 세면 두 화면이 다른 숫자를 말한다');
    });
  });

  group('[R7-P4.4E.2] 목적지·갱신', () {
    test('NAV-01 준비 단계 보기는 Home 탭으로 간다', () {
      expect(
        _jobsRoot().contains(
            'AdminTabSwitcher.instance.switchToTab(AdminTabSwitcher.homeTab)'),
        isTrue,
        reason: 'readiness 카드가 Home 첫 화면에 있으므로 새 목적지를 만들지 않는다(§17)',
      );
      expect(
        _createTO().contains('switchToTab(AdminTabSwitcher.homeTab)'),
        isTrue,
      );
    });

    test('REFRESH-01 Home 이 계산할 때마다 결과를 흘린다', () {
      final src = _home();
      final publish = src.indexOf('FirstPostingReadinessBroadcast.publish');
      final build = src.indexOf('_firstPosting = FirstPostingReadiness(');
      expect(publish, greaterThan(build),
          reason: '계산 직후에 흘려야 공고 root 가 낡은 값을 들고 있지 않다');
    });

    test('REFRESH-02 계산은 여전히 Home 한 곳에서만 한다', () {
      expect(_jobsRoot().contains('FirstPostingReadiness('), isFalse,
          reason: '§6 — 복제 술어를 만들지 않는다');
      expect(_createTO().contains('= FirstPostingReadiness('), isFalse);
    });

    test('REFRESH-03 계정 경계에서 이전 판정을 이어 쓰지 않는다', () {
      FirstPostingReadinessBroadcast.publish(_readiness());
      expect(FirstPostingReadinessBroadcast.current.value, isNotNull);
      FirstPostingReadinessBroadcast.clear();
      expect(FirstPostingReadinessBroadcast.current.value, isNull);
    });
  });
}
