// [CROSS-DOMAIN-R5.1E] 권한이 바뀌면 화면도 같은 말을 해야 한다.
//
// 이번에 확인·수정한 것:
//
//   1. 관리자 Home은 권한을 `context.read`로 읽어 섹션마다 내려준다 — 구독이
//      아니다. 그런데 유일한 구독(Selector)이 사용자 이름만 보고 있었다.
//      권한 listener가 값을 갱신해도 선택값이 그대로라 Home은 다시 그려지지
//      않았고, 누를 수 없는 CTA와 처리할 수 없는 Task가 화면에 남았다.
//      (서버는 전부 막는다 — 실측 403 — 그래서 BLOCKER가 아니라 CORRECTION.)
//      이제 Selector가 네 권한을 함께 지켜본다.
//
//   2. 고정근무 관리의 일정변경 요청 영역은 403을 catch해서 빈 목록으로
//      바꾸고 있었다. `볼 수 없다`가 `요청 없음`이 되는 형태다.
//      권한이 없으면 아예 호출하지 않고, 불러오기 실패는 실패라고 말한다.
//
// 테스트 가능 범위에 대한 사실:
//   UserProvider는 필드 초기화에서 AuthService→FirebaseAuth/Firestore를 잡아
//   Firebase 초기화 없이는 생성되지 않는다(probe 실측: FirebaseException).
//   provider/widget 전이 테스트는 core provider의 DI refactor를 요구하므로
//   이번 Phase 범위 밖이고, 실기기 확인은 R7 PRODUCT PENDING으로 남긴다.
//   여기서는 "무엇을 구독하는가"와 "어떤 상태를 구분하는가"를 고정한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  group('권한이 바뀌면 Home이 다시 그려진다', () {
    final home = _flat(_codeOf(
        _src('lib/screens/business_admin/business_admin_home_screen.dart')));

    test('Selector가 네 권한을 함께 지켜본다', () {
      expect(home.contains('canManageTo: p.can((x) => x.canManageTo),'), true);
      expect(home.contains('canManageWorkers: p.can((x) => x.canManageWorkers),'), true);
      expect(home.contains('canManageContract: p.can((x) => x.canManageContract),'), true);
      expect(home.contains('canManageWage: p.can((x) => x.canManageWage),'), true);
    });

    test('이름만 보던 구독이 아니다', () {
      expect(home.contains("selector: (_, p) => (userName: p.currentUser?.name ?? '관리자'),"),
          false, reason: '이름만 보면 권한 회수가 화면에 닿지 않는다');
    });

    test('구독 대상 타입에도 권한이 들어 있다', () {
      expect(home.contains('typedef _AdminHomeData = ({ String userName, '
          'bool canManageTo, bool canManageWorkers, '
          'bool canManageContract, bool canManageWage, });'), true);
    });
  });

  group('일정변경 요청 영역은 네 상태를 섞지 않는다', () {
    final d = _flat(_codeOf(_src(
        'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart')));

    test('권한이 없으면 호출하지 않는다', () {
      expect(d.contains('final canSeeScheduleReq = context .read<UserProvider>() '
          '.canForBusiness(businessId, (p) => p.canManageWorkers);'), true);
      expect(d.contains('final scheduleRequestsFuture = (_isDateMode && canSeeScheduleReq)'),
          true, reason: '거절을 받아 빈 목록으로 바꾸면 "요청 없음"과 같아진다');
    });

    test('대상 사업장 기준으로 판정한다', () {
      expect(d.contains('.canForBusiness(businessId,'), true,
          reason: '선택 사업장이 이 화면의 사업장과 다를 수 있다');
    });

    test('불러오기 실패를 0건으로 말하지 않는다', () {
      expect(d.contains('_scheduleReqState = _ScheduleReqState.error;'), true);
      expect(d.contains("'변경 요청 확인 불가'"), true);
    });

    test('권한 없음·실패·데이터가 각각 다른 상태다', () {
      expect(d.contains('enum _ScheduleReqState { notPermitted, error, loaded }'), true);
      expect(d.contains('_scheduleReqState == _ScheduleReqState.loaded && '
          '_pendingRequestsForDate.isNotEmpty'), true,
          reason: '데이터가 있을 때만 대기 건수를 말한다');
    });

    test('처리 action은 이미 같은 권한을 요구한다', () {
      expect(d.contains("if (!context.read<UserProvider>().can((p) => p.canManageWorkers))"),
          true);
    });
  });

  group('사업장별 권한 판정이 존재한다', () {
    final up = _flat(_codeOf(_src('lib/providers/user_provider.dart')));

    test('대상 사업장을 명시하는 계약이 있다', () {
      expect(up.contains('bool canForBusiness( String businessId,'), true);
      expect(up.contains('final perms = _subAdminPermissionsByBusinessView[businessId]; '
          'if (perms == null) return false;'), true,
          reason: '그 사업장 권한을 모르면 거부다 — 전역 값으로 대신하지 않는다');
    });

    test('can()은 선택된 사업장 기준임이 문서화돼 있다', () {
      final raw = _src('lib/providers/user_provider.dart');
      expect(raw.contains('can()은 **선택된 사업장** 기준이고'), true);
    });

    test('권한 변경은 listener로 들어온다', () {
      expect(up.contains(".collection('members') .doc(uid) .snapshots() .listen((snap) {"),
          true, reason: '폴링이나 재로그인이 아니라 실시간 구독이어야 한다');
      expect(up.contains('_setBusinessPermission(businessId, _memberPermissions);'), true,
          reason: '선택 사업장 값과 사업장별 map이 같은 snapshot에서 갱신돼야 한다');
    });

    test('membership이 사라지면 fail-closed다', () {
      expect(up.contains('_setBusinessPermission(businessId, null);'), true);
      expect(up.contains('_switchGeneration++;'), true,
          reason: '진행 중이던 전환이 옛 권한을 되살리면 안 된다');
    });
  });
}
