// [CROSS-DOMAIN-R5.1F.3] 권한 신선도 / canCancelTransfer canonical
//
// 세 가지를 닫는다.
//
//   1. [VERIFY-CANCEL-TRANSFER-CAPABILITY-CONTRACT]
//      canCancelTransfer는 실제로 저장되는 5번째 권한이다 — 다만 독립이 아니라
//      canManageWage 위에 얹히는 하위 권한이다. 서버가 두 권한을 차례로 보고,
//      멤버 관리 UI가 canManageWage를 끄면 자동으로 함께 꺼진다.
//      DEV 실측 PASS 8/0 (WAGE+CANCEL만 통과, 한쪽만으로는 불가).
//
//   2. [CORRECTION-TARGET-PERMISSION-WATCH-ERROR-STALE]
//      구독이 에러를 받으면 기존 권한 값을 지우지 않는다(ERROR ≠ NO_PERMISSION).
//      그런데 bool 하나로는 "검증된 허용"과 "마지막으로 봤을 때 허용"이
//      구분되지 않아, 확인하지 못한 값으로 금전 mutation CTA가 열려 있었다.
//      권한 bool과 **다른 축**으로 신선도를 둔다 — 새 권한 프레임워크가 아니라
//      기존 사업장별 map 옆의 작은 상태 하나다.
//
//   3. 지원 검토 큐의 민감 데이터 — read 자체가 canManageTo로 막혀 있는지.
//      CTA 숨김만으로 보호하고 있었다면 결함이다.
//
// 여기서 고정하는 것은 "무엇을 구분하는가"이고, 전이 자체는 R7 실기기 확인이다.

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

String _load(String p) => _flat(_codeOf(_src(p)));

const _provider = 'lib/providers/user_provider.dart';
const _model = 'lib/models/core/business_member_model.dart';
const _memberUi = 'lib/screens/business_admin/member_management_screen.dart';
const _payDash = 'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';
const _queue = 'lib/screens/business_admin/support_review_queue_screen.dart';
const _cf = 'functions/src/index.ts';

void main() {
  // ── PART A. canCancelTransfer canonical ────────────────────────────

  group('canCancelTransfer는 저장되는 권한이다', () {
    test('schema에 있다', () {
      final m = _load(_model);
      expect(m.contains("'canCancelTransfer': canCancelTransfer,"), true,
          reason: 'toMap — member 문서에 실제로 저장된다');
      expect(m.contains("canCancelTransfer: m['canCancelTransfer'] ?? false,"), true,
          reason: 'fromMap — 없으면 false(fail-closed)');
    });

    test('소유자가 멤버 관리 UI에서 부여한다', () {
      final ui = _load(_memberUi);
      expect(ui.contains('(v) => permissions.copyWith(canCancelTransfer: v),'), true);
    });

    test('canManageWage 없이는 켤 수 없다 — 의존 invariant', () {
      final ui = _load(_memberUi);
      expect(
          ui.contains(': permissions.copyWith(canManageWage: false, '
              'canCancelTransfer: false),'),
          true,
          reason: '급여 권한을 끄면 이체 취소도 함께 꺼진다');
      expect(
          ui.contains(': _permissions.copyWith(canManageWage: false, '
              'canCancelTransfer: false),'),
          true);
    });
  });

  group('이체 취소는 두 권한을 함께 요구한다', () {
    final cf = _flat(_codeOf(_src(_cf)));

    test('서버가 canManageWage를 먼저 본다', () {
      expect(
          cf.contains('if (perms.canManageWage !== true) { throw new HttpsError('
              '"permission-denied", "급여 관리 권한이 없습니다."); }'),
          true);
    });

    test('서버가 canCancelTransfer를 이어서 본다', () {
      expect(
          cf.contains('if (perms.canCancelTransfer !== true) { throw new HttpsError('
              '"permission-denied", "이체 취소 권한이 없습니다."); }'),
          true);
    });

    test('클라이언트도 같은 AND 조건이다', () {
      final s = _load(_payDash);
      expect(s.contains('(p) => p.canManageWage && p.canCancelTransfer,'), true);
      expect('p.canManageWage && p.canCancelTransfer'.allMatches(s).length,
          greaterThanOrEqualTo(2),
          reason: '렌더 판정과 전송 직전 재확인이 같은 조건이어야 한다');
    });
  });

  // ── PART B. watch freshness / error semantics ──────────────────────

  group('권한 값의 신선도를 권한 bool과 섞지 않는다', () {
    final up = _load(_provider);

    test('신선도가 별도 축으로 존재한다', () {
      expect(up.contains('enum PermissionWatchState { unknown, verified, error, }'), true);
      expect(up.contains('enum PermissionCheck { allowed, denied, unknown, error, }'), true);
    });

    test('구독 에러는 권한 값을 지우지 않는다', () {
      final i = up.indexOf('}, onError: (e) {');
      final body = up.substring(i, i + 400);
      expect(body.contains('_setBusinessPermission'), false,
          reason: 'ERROR를 DENIED로 바꾸지 않는다');
      expect(body.contains('_setPermissionWatchState(businessId, PermissionWatchState.error);'),
          true, reason: '대신 그 값이 검증된 것이 아니라고 표시한다');
    });

    test('에러 상태에서는 예전 허용으로 열어주지 않는다', () {
      expect(
          up.contains('if (watch == PermissionWatchState.error) return PermissionCheck.error;'),
          true);
      final i = up.indexOf('PermissionCheck checkForBusiness(');
      final body =
          up.substring(i, up.indexOf('VoidCallback watchBusinessPermissions', i));
      expect(body.indexOf('PermissionWatchState.error') <
              body.indexOf('_subAdminPermissionsByBusinessView[businessId]'),
          true,
          reason: 'error 판정이 기존 map 값보다 먼저여야 한다');
    });

    test('snapshot을 받으면 verified다 — 나중 복구가 가능하다', () {
      expect(
          up.contains('_setPermissionWatchState(businessId, PermissionWatchState.verified);'),
          true,
          reason: '에러 뒤 정상 snapshot이 오면 상태가 되돌아온다(고착 금지)');
    });

    test('membership 삭제는 에러가 아니라 확인된 거부다', () {
      final i = up.indexOf('VoidCallback watchBusinessPermissions');
      final body = up.substring(i, i + 2600);
      // 문서가 없을 때도 같은 성공 경로에서 verified로 표시된다.
      expect(body.contains('data == null ? null : MemberPermissions.fromMap('), true);
      expect(
          body.indexOf('_setPermissionWatchState(businessId, PermissionWatchState.verified);') >
              body.indexOf('data == null ? null : MemberPermissions.fromMap('),
          true);
      expect(up.contains('if (watch == PermissionWatchState.verified) return PermissionCheck.denied;'),
          true, reason: 'map에 없고 확인까지 됐으면 거부다');
    });

    test('하이드레이션 전은 unknown이지 denied가 아니다', () {
      expect(
          up.contains('return _subAdminPermissionsLoaded ? PermissionCheck.denied '
              ': PermissionCheck.unknown;'),
          true);
    });

    test('구독을 끊으면 "지금 검증됨"도 사라진다', () {
      expect(up.contains('_clearPermissionWatchState(businessId);'), true);
    });

    test('소유자는 member 문서로 판정하지 않는다', () {
      final i = up.indexOf('PermissionCheck checkForBusiness(');
      final body = up.substring(i, i + 900);
      expect(body.contains('if (user.isBusinessAdmin || user.isSuperAdmin) '
          'return PermissionCheck.allowed;'), true);
    });
  });

  group('금전 mutation CTA는 검증된 허용에서만 열린다', () {
    final s = _load(_payDash);

    test('진입 시점 bool을 화면에 들고 다니지 않는다', () {
      expect(s.contains('final bool canCancelTransfer;'), false,
          reason: '넘겨받은 bool은 머무는 동안 갱신되지 않는다');
      expect(s.contains('canCancelTransfer: canCancel,'), false);
      expect(s.contains('required this.businessId,'), true,
          reason: '대상 사업장을 받아 현재 권한을 직접 본다');
    });

    test('allowed일 때만 CTA를 그린다', () {
      expect(s.contains('if (_cancelCheck(ctx) == PermissionCheck.allowed) ...['), true);
    });

    test('unknown/error는 이유를 말하고 누르게 하지 않는다', () {
      expect(
          s.contains('] else if (_cancelCheck(ctx) == PermissionCheck.unknown || '
              '_cancelCheck(ctx) == PermissionCheck.error) ...['),
          true);
      expect(s.contains("Text('권한 정보를 확인하지 못했습니다',"), true);
    });

    test('전송 직전에 한 번 더 본다', () {
      expect(
          s.contains('if (context.read<UserProvider>().checkForBusiness( widget.businessId, '
              '(p) => p.canManageWage && p.canCancelTransfer) != PermissionCheck.allowed) {'),
          true,
          reason: '다이얼로그를 띄운 사이에 회수될 수 있다');
    });

    test('화면 자체도 확인된 거부일 때만 잠근다', () {
      expect(s.contains('body: wageAccess == PermissionCheck.denied'), true);
      expect(s.contains("title: '접근 권한이 없습니다',"), true,
          reason: '0건이 아니라 권한 없음으로 말한다');
    });

    test('이 화면도 대상 사업장을 구독하고 해제한다', () {
      expect(s.contains('_releasePermsWatch = context .read<UserProvider>() '
          '.watchBusinessPermissions(widget.businessId);'), true);
      expect('_releasePermsWatch?.call();'.allMatches(s).length, 2,
          reason: '대시보드와 상세 화면 각각 dispose에서 해제');
    });
  });

  // ── PART D. 지원 검토 큐 민감 데이터 ────────────────────────────────

  group('지원 검토 큐는 read 자체가 권한이다', () {
    final cf = _flat(_codeOf(_src(_cf)));

    test('목록 조회 서버 guard가 canManageTo다', () {
      final i = cf.indexOf('export const callableGetPendingApplicationsForReview = onCall(');
      expect(i, greaterThan(-1));
      final body = cf.substring(i, i + 2600);
      expect(
          body.contains('if (memberPerms.canManageTo !== true) { throw new HttpsError('
              '"permission-denied", "TO 관리 권한이 없습니다."); }'),
          true,
          reason: 'CTA 숨김이 아니라 read가 막혀야 한다');
    });

    test('지원자 신원 조회도 purpose로 좁힌다', () {
      final svc = _load('lib/services/support_review_queue_service.dart');
      expect(svc.contains("purpose: 'applicantReview',"), true,
          reason: '계좌·정확한 주소 등은 서버가 응답에서 제외한다');
    });

    test('권한이 확인된 거부인 사업장은 묻지 않는다', () {
      final s = _load(_queue);
      expect(
          s.contains('final scoped = widget.businessIds .where((id) => '
              'up.checkForBusiness(id, (p) => p.canManageTo) != PermissionCheck.denied) '
              '.toList();'),
          true);
      expect(s.contains('_queueSvc.loadPendingApplications(scoped)'), true);
    });

    test('unknown/error는 서버에 물어본다 — 거절을 empty로 바꾸지 않는다', () {
      final s = _load(_queue);
      expect(s.contains('!= PermissionCheck.denied'), true,
          reason: 'denied만 뺀다. unknown까지 빼면 못 읽은 것이 없는 것이 된다');
      expect(s.contains('_hasLoadError = true;'), true,
          reason: '남은 사업장의 실패는 여전히 ERROR다');
    });

    test('행 CTA도 거부와 확인불가를 구분한다', () {
      final s = _load(_queue);
      expect(s.contains('PermissionCheck _actCheck(ApplicationModel app) =>'), true);
      expect(
          s.contains("_actCheck(app) == PermissionCheck.denied ? '권한 없음' : '권한 확인 불가',"),
          true);
    });
  });

  // ── PART E. canonical schema 전수 ──────────────────────────────────

  group('권한은 다섯 개뿐이다', () {
    test('모델이 정확히 다섯 개를 담는다', () {
      final m = _codeOf(_src(_model));
      final keys = RegExp(r"'(can[A-Za-z]+)':")
          .allMatches(m)
          .map((x) => x.group(1)!)
          .toSet();
      expect(keys, {
        'canManageTo',
        'canManageWorkers',
        'canManageWage',
        'canManageContract',
        'canCancelTransfer',
      });
    });

    test('서버가 보는 권한 키도 같은 다섯이다', () {
      final cf = _codeOf(_src(_cf));
      final keys = RegExp(r'(?:perms|memberPerms|prePerms|rejectPerms|scrDPerms)\??\.(can[A-Za-z]+)')
          .allMatches(cf)
          .map((x) => x.group(1)!)
          .toSet();
      expect(keys, {
        'canManageTo',
        'canManageWorkers',
        'canManageWage',
        'canManageContract',
        'canCancelTransfer',
      }, reason: '숨은 여섯 번째 권한이 생기면 여기서 걸린다');
    });

    test('멤버 관리는 소유자 전용이다', () {
      final ui = _load(_memberUi);
      expect(ui.contains('if (!(up.currentUser?.isBusinessAdmin == true)) {'), true,
          reason: 'SUB_ADMIN에게는 권한 항목 자체가 없다');
    });

    test('provider가 노출하는 판정 helper가 셋이다', () {
      final up = _load(_provider);
      expect(up.contains('bool can(bool Function(MemberPermissions p) check) {'), true,
          reason: '선택 사업장');
      expect(up.contains('bool canForBusiness( String businessId,'), true,
          reason: '대상 사업장(bool)');
      expect(up.contains('PermissionCheck checkForBusiness( String businessId,'), true,
          reason: '대상 사업장(4상태)');
    });
  });
}
