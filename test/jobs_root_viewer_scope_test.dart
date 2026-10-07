// [R7-P4.4E.3B.2] 공고 탭이 **보는 사람의 사실**과 **사업장의 사실**을 구분한다.
//
//   공고 관리 권한이 없는 하위관리자가 이 탭을 열면, 고용주 날인을 읽을 수
//   없어 `sealUnknown` → `allReady=false` → "아직 공고를 등록할 준비가
//   끝나지 않았어요" 가 떴다. 그 사람의 진실은 준비 미완료가 아니라
//   **권한 없음**이다. 준비는 사업장의 사실이고 권한은 보는 사람의 사실이다.
//
//   공고 목록 자체도 서버가 `canManageTo` 를 요구하므로(`srvAssertToAuthority`),
//   읽을 수 없는 사람에게 read-only 목록을 클라이언트에서 만들지 않는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/providers/user_provider.dart';

String _jobs() =>
    File('lib/screens/business_admin/jobs_root_screen.dart').readAsStringSync();
String _shell() =>
    File('lib/screens/business_admin/business_admin_shell.dart')
        .readAsStringSync();
String _cf() => File('functions/src/index.ts').readAsStringSync();
String _contract() =>
    File('lib/screens/business_admin/admin_contract_management_screen.dart')
        .readAsStringSync();

/// 주석을 뺀 실행 코드 — 계약은 그려지는 것에 대한 것이다.
String _code(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('[R7-P4.4E.3B.2] 전제 — 목록은 서버가 막는다', () {
    test('JOBS-VIEWER-00 공고 목록 read 권한은 canManageTo 다', () {
      final cf = _cf();
      final i = cf.indexOf('공고 목록 read 권한 = canManageTo');
      expect(i, greaterThan(-1), reason: '서버가 막으니 client read-only 를 만들지 않는다');
      expect(cf.contains('srvAssertToAuthority(callerUid, id)'), isTrue);
    });

    test('JOBS-VIEWER-00b 탭 자체는 숨기지 않는다', () {
      // 숨기면 "권한을 빼앗겼다" 가 아니라 "기능이 사라졌다" 로 읽힌다.
      expect(_shell().contains('canManageTo'), isFalse,
          reason: '셸은 권한으로 탭을 거르지 않는다 — 기존 설계 유지');
      expect(_shell().contains('JobsRootScreen(postingController:'), isTrue);
    });
  });

  group('[R7-P4.4E.3B.2] 순서 — 권한을 먼저 본다', () {
    test('JOBS-VIEWER-01 권한 판정이 준비 판정보다 앞이다', () {
      final s = _code(_jobs());
      final perm = s.indexOf('final toPermission = context.select<UserProvider');
      final ready = s.indexOf('valueListenable: FirstPostingReadinessStore.current');
      expect(perm, greaterThan(-1));
      expect(ready, greaterThan(perm),
          reason: '준비부터 계산하면 권한 없는 사람에게 준비 문구가 먼저 닿는다');
    });

    test('JOBS-VIEWER-02 확정된 거부면 NO_PERMISSION 으로 끝난다', () {
      final s = _code(_jobs());
      expect(s.contains('if (toPermission.hidesAffordance) {'), isTrue);
      final deny = s.indexOf('toPermission.hidesAffordance');
      final ready = s.indexOf('valueListenable: FirstPostingReadinessStore.current');
      expect(deny, lessThan(ready), reason: '거부면 준비 분기에 도달하지 않는다');
    });

    test('JOBS-VIEWER-05/06/07 거부 화면에 setup·생성 유도가 없다', () {
      final s = _jobs();
      final i = s.indexOf('class _JobsPermissionSurface');
      final surface = s.substring(i);
      for (final banned in const [
        '공고 등록 준비가 필요해요',
        '아직 공고를 등록할 준비가 끝나지 않았어요',
        '준비 단계 보기',
        '등록된 공고가 없습니다',
        '_JobsCreateButton',
      ]) {
        expect(surface.contains(banned), isFalse,
            reason: '권한 없는 사용자에게 "$banned" 로 책임을 주지 않는다');
      }
    });

    test('JOBS-VIEWER-05b 거부 문구는 무엇을 하면 되는지 말한다', () {
      final s = _jobs();
      expect(s.contains("title: '접근 권한이 없습니다'"), isTrue);
      expect(s.contains('공고 관리 권한이 있는 관리자에게 문의하세요.'), isTrue);
    });
  });

  group('[R7-P4.4E.3B.2] 모름·실패는 거부가 아니다', () {
    test('JOBS-VIEWER-08/09 pending 은 따로 말한다', () {
      final s = _code(_jobs());
      expect(s.contains('if (toPermission.isPending) {'), isTrue);
      expect(_jobs().contains("title: '권한을 확인하지 못했습니다'"), isTrue);
      expect(_jobs().contains('권한이 없다는 뜻이 아닙니다.'), isTrue);
    });

    test('JOBS-VIEWER-08b 네 상태 규칙은 canonical 한 곳에서 온다', () {
      // bool 하나로 접으면 모름·실패가 거부와 같은 모습이 된다.
      expect(PermissionCheck.values.length, 4);
      expect(PermissionCheck.denied.hidesAffordance, isTrue);
      expect(PermissionCheck.unknown.hidesAffordance, isFalse);
      expect(PermissionCheck.error.hidesAffordance, isFalse);
      expect(PermissionCheck.unknown.isPending, isTrue);
      expect(PermissionCheck.error.isPending, isTrue);
      expect(PermissionCheck.allowed.isPending, isFalse);
    });

    test('JOBS-VIEWER-09b 기존 canonical surface 를 재사용했다', () {
      // 계약 관리 화면이 쓰는 것과 같은 모양이다 — 새 컴포넌트를 만들지 않았다.
      expect(_contract().contains("title: '접근 권한이 없습니다'"), isTrue);
      expect(_contract().contains("title: '권한을 확인하지 못했습니다'"), isTrue);
      expect(_jobs().contains('AppEmptyState('), isTrue);
    });
  });

  group('[R7-P4.4E.3B.2] 준비 조회는 허용 뒤에만', () {
    test('JOBS-VIEWER-05c 권한 없는 사람 때문에 날인 조회를 부르지 않는다', () {
      final s = _code(_jobs());
      final perm = s.indexOf('if (toPermission.isPending) {');
      final trigger = s.indexOf('if (!_readinessRequested) {');
      expect(trigger, greaterThan(perm),
          reason: '허용이 확인된 뒤에만 준비 상태를 묻는다');
      // initState 에서 무조건 부르던 자리는 사라졌다.
      final init = s.indexOf('void initState()');
      final build = s.indexOf('Widget build(BuildContext context)');
      final seg = s.substring(init, build);
      expect(seg.contains('_ensureReadiness()'), isFalse);
    });

    test('JOBS-VIEWER-11 권한이 생기면 그때 평가한다', () {
      final s = _code(_jobs());
      // select 구독이라 권한 전이가 build 까지 닿고, 거기서 한 번 건다.
      expect(s.contains('_readinessRequested = true;'), isTrue);
      expect(s.contains('unawaited(_ensureReadiness());'), isTrue);
      // 새 listener·polling 을 만들지 않았다.
      expect(s.contains('Timer.periodic'), isFalse);
    });

    test('JOBS-VIEWER-10 권한이 회수되면 이전 화면이 남지 않는다', () {
      final s = _code(_jobs());
      // read 가 아니라 select — 회수가 여기까지 닿는다.
      expect(s.contains('context.select<UserProvider, PermissionCheck>'), isTrue);
      expect(s.contains('context.read<UserProvider>().checkCurrentBusiness'), isFalse,
          reason: '한 번 읽고 끝내면 회수된 뒤에도 목록·+ 가 남는다');
    });
  });

  group('[R7-P4.4E.3B.2] 허용된 사용자 회귀', () {
    test('JOBS-VIEWER-03/04 준비 분기는 그대로다', () {
      final s = _code(_jobs());
      expect(s.contains('final setupRequired = r != null && !r.allReady;'), isTrue);
      // [R7-ONBOARDING.1] 하위관리자 분기가 더해지면서 인자가 늘었다.
      //   지켜야 하는 것은 **분기 구조**이지 인자 철자가 아니다.
      expect(s.contains('_JobsSetupRequiredView('), isTrue);
      expect(s.contains('readiness: r'), isTrue);
      expect(s.contains('WorkforceListView(targetToId: _targetToId)'), isTrue);
    });

    test('JOBS-VIEWER-04b + 는 허용 + 준비 완료일 때만 남는다', () {
      final s = _code(_jobs());
      expect(s.contains('!setupRequired'), isTrue);
      expect(s.contains('_JobsCreateButton('), isTrue);
    });

    test('JOBS-VIEWER-12 계정·사업장 경계는 기존 store 가 지킨다', () {
      final r = File('lib/services/business_posting_readiness.dart')
          .readAsStringSync();
      expect(r.contains('bool matches(String? currentUid'), isTrue);
      expect(
          File('lib/providers/user_provider.dart')
              .readAsStringSync()
              .contains('FirstPostingReadinessStore.reset()'),
          isTrue);
    });
  });
}
