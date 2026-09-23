// [R7-P1] STAFFING + NOTIFICATION UX PATCH — 계약 고정.
//
// 이 파일이 지키는 것은 하나로 요약된다:
//
//   Same entity + Same event = Same business truth across every surface.
//
// 그리고 그 truth가 **상태를 뭉뚱그리지 않는 것**:
//   ERROR != ZERO   UNKNOWN != EMPTY   UNKNOWN != TODAY
//   FULL != DONE    CLOSED != DONE     Notification != Task

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/notification_model.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';
import 'package:ALfit/utils/notification_retention.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String s) =>
    s.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

const _card = 'lib/widgets/admin/cards/admin_to_group_card.dart';
const _day = 'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';
const _work = 'lib/screens/business_admin/dialogs/work_applicants_dialog.dart';
const _notifCard = 'lib/widgets/common/notification_card.dart';
const _notifScreen = 'lib/screens/common/notification_screen.dart';
const _notifProvider = 'lib/providers/notification_provider.dart';

void main() {
  // ══════════════════════════════════════════════════════════════
  // §3 Posting — 공고 identity
  // ══════════════════════════════════════════════════════════════
  group('P1-2 Posting hierarchy', () {
    final src = _codeOf(_src(_card));

    test('P1-2-a FLEX 다중 날짜는 하루를 공고 정체성처럼 보이지 않게 한다', () {
      expect(src.contains('String? _collapsedDateRangeText('), true);
      final body = src.substring(src.indexOf('String? _collapsedDateRangeText('));
      // 상세를 못 읽었으면 범위를 주장하지 않는다 — UNKNOWN != 단일 날짜
      expect(body.contains('isGroupDetailLoaded'), true);
      expect(body.contains('dates.length < 2'), true);
    });

    test('P1-2-b 범위를 말할 때 한 날짜의 시간을 범위 전체의 시간처럼 붙이지 않는다', () {
      final body = _codeOf(_src(_card));
      final i = body.indexOf('String? _collapsedWhenText(');
      final seg = body.substring(i, i + 500);
      // range가 있으면 그대로 반환하고 끝 — time을 이어 붙이지 않는다.
      expect(seg.contains('if (range != null) return range;'), true);
    });

    test('P1-2-c 제목이 비어도 침묵하지 않는다', () {
      final i = src.indexOf('Widget _buildTitleLine(');
      final seg = src.substring(i, i + 900);
      expect(seg.contains('제목 없는 공고'), true);
      expect(seg.contains('masterTO.title'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §5 §6 §7 Staffing — 한 식, 두 화면
  // ══════════════════════════════════════════════════════════════
  group('P1-3 Staffing parity', () {
    test('P1-3-a shortage 식은 한 벌이다', () {
      final canon = _codeOf(_src('lib/models/ui/invite_capacity_state.dart'));
      expect(canon.contains('int? staffingShortageOf('), true);
      for (final p in [_day, _work]) {
        expect(_codeOf(_src(p)).contains('staffingShortageOf('), true,
            reason: p);
      }
    });

    test('P1-3-b UNKNOWN은 0이 아니라 null이다', () {
      expect(
        staffingShortageOf(
            capacity: InviteCapacityState.unknown,
            requiredCount: 3,
            seatedConfirmed: 0),
        isNull,
      );
      // 종료된 모집은 채울 수 없으므로 부족이 아니다 — 이건 진짜 0이다.
      expect(
        staffingShortageOf(
            capacity: InviteCapacityState.closed,
            requiredCount: 3,
            seatedConfirmed: 0),
        0,
      );
    });

    test('P1-3-c 초대·대기는 자리를 확보하지 않는다', () {
      // 필요 3 · 확정 1 → 대기가 몇이든 부족은 2다.
      expect(
        staffingShortageOf(
            capacity: InviteCapacityState.available,
            requiredCount: 3,
            seatedConfirmed: 1),
        2,
      );
    });

    test('P1-3-d 과충원은 음수가 되지 않는다', () {
      expect(
        staffingShortageOf(
            capacity: InviteCapacityState.available,
            requiredCount: 2,
            seatedConfirmed: 5),
        0,
      );
    });

    test('P1-3-e WorkApplicants도 부족·정원 UNKNOWN·초대를 말한다', () {
      final s = _codeOf(_src(_work));
      expect(s.contains("_buildStatItem(context, '부족'"), true);
      expect(s.contains('정원 확인 불가'), true);
      expect(s.contains('_buildStaffingActionRow('), true);
      expect(s.contains('인력 초대 (\$shortage명 부족)'), true);
    });

    test('P1-3-f UNKNOWN에서 초대 CTA가 서지 않는다 — 대신 이유를 말한다', () {
      final s = _codeOf(_src(_work));
      final i = s.indexOf('Widget _buildStaffingActionRow(');
      final seg = s.substring(i, i + 1200);
      expect(seg.contains('capacity == InviteCapacityState.unknown'), true);
      expect(seg.contains('_buildCapacityUnknownNotice('), true);
      // available이 아니면 CTA 없음 — `!= closed`처럼 두 상태를 뭉치지 않는다.
      expect(seg.contains('capacity != InviteCapacityState.available'), true);
    });

    test('P1-3-g capacity는 지원서가 아니라 slot이 말한다', () {
      final s = _codeOf(_src(_work));
      final i = s.indexOf('int? get _canonicalConfirmed');
      final seg = s.substring(i, i + 700);
      expect(seg.contains('workDetailStatsFailed'), true,
          reason: '통계 조회 실패는 정원 0이 아니라 UNKNOWN이다');
      expect(seg.contains('return null'), true);
    });

    test('P1-3-h FULL/CLOSED에서는 ⋮ 메뉴의 초대도 내린다', () {
      final s = _codeOf(_src(_card));
      expect(s.contains('bool _canInviteNow()'), true);
      final i = s.indexOf('bool _canInviteNow()');
      final seg = s.substring(i, i + 400);
      expect(seg.contains('_computeAllClosed('), true);
      expect(seg.contains('_isFull'), true);
      // 세 곳 모두 게이트를 지난다.
      expect('if (_canInviteNow())'.allMatchesIn(s), 3);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §11 §12 §13 §14 카드 taxonomy
  // ══════════════════════════════════════════════════════════════
  group('P1-4/5/6 카드 taxonomy', () {
    test('P1-4-a 리뷰 배지가 staffing 카드에서 사라졌다', () {
      // 주석에 남은 설명은 계약이 아니다 — 코드만 본다.
      for (final p in [_day, _work]) {
        final s = _codeOf(_src(p));
        expect(s.contains('_buildReviewBadge'), false, reason: p);
        expect(s.contains('리뷰미작성'), false, reason: p);
        expect(s.contains('_reviewWrittenMap'), false, reason: p);
      }
    });

    test('P1-4-b 실근무 판정은 status와 wageStatus를 함께 본다', () {
      // NO_SHOW는 0원으로 마감되지만 실근무가 아니다.
      expect(
          AttendanceModel.isActualFinalizedWork(
              AttendanceModel.statusNoShow, AttendanceModel.wageConfirmed),
          false);
      // 아직 마감 전인 오늘 근무도 아니다.
      expect(
          AttendanceModel.isActualFinalizedWork(
              AttendanceModel.statusPresent, AttendanceModel.wagePending),
          false);
      // 지각·조퇴는 실근무다.
      for (final s in [
        AttendanceModel.statusPresent,
        AttendanceModel.statusLate,
        AttendanceModel.statusEarlyLeave,
      ]) {
        expect(
            AttendanceModel.isActualFinalizedWork(
                s, AttendanceModel.wageTransferred),
            true,
            reason: s);
      }
      expect(AttendanceModel.isActualFinalizedWork(null, null), false);
    });

    test('P1-4-c 리뷰 화면 근무일 집계가 canonical 판정을 쓴다', () {
      final s = _codeOf(
          _src('lib/screens/business_admin/admin_review_list_screen.dart'));
      expect(s.contains('AttendanceModel.isActualFinalizedWork('), true);
      // wageStatus만 보던 옛 식이 남아 있지 않다.
      expect(s.contains("status == 'confirmed' || status == 'transferred'"),
          false);
    });

    test('P1-4-d 신분증 집계는 원천 상태를 합치지 않고 뜻에 맞는 이름을 쓴다', () {
      for (final p in [_day, _work]) {
        final s = _codeOf(_src(p));
        expect(s.contains('요청 가능 \$requestableCount명'), true, reason: p);
        expect(s.contains('미요청 \$requestableCount명'), false, reason: p);
      }
      // 개별 상태는 그대로 각자 남는다 — 합치지 않았다.
      final helper = _codeOf(_src('lib/utils/id_card_helper.dart'));
      expect(helper.contains("case 'expired'"), true);
      expect(helper.contains("case 'rejected'"), true);
      expect(helper.contains("case 'none'"), true);
    });

    test('P1-5-a bulk UI는 2명 이상일 때만 선다', () {
      for (final p in [_day, _work]) {
        final s = _codeOf(_src(p));
        expect(s.contains('if (requestableCount < 2)'), true, reason: p);
        expect(s.contains('if (noContractCount < 2)'), true, reason: p);
      }
    });

    test('P1-6-a 부족은 red가 아니다 — red는 실제 문제에 남긴다', () {
      final s = _codeOf(_src(_day));
      final i = s.indexOf('final shortageColor =');
      final seg = s.substring(i, i + 160);
      expect(seg.contains('AppColors.warningDark'), true);
      expect(seg.contains('AppColors.errorDark'), false);
      // 노쇼는 red 유지.
      expect(s.contains('최근 90일 노쇼'), true);
    });

    test('P1-6-b 완료된 것은 gray — green은 확정에 쓴다', () {
      final helper = _codeOf(_src('lib/utils/id_card_helper.dart'));
      final i = helper.indexOf("case 'approved':");
      expect(helper.substring(i, i + 200).contains('AppColors.grey500'), true);
      for (final p in [_day, _work]) {
        final s = _codeOf(_src(p));
        final j = s.indexOf("'계약완료'");
        expect(s.substring(j - 200, j + 200).contains('successDark'), false,
            reason: p);
      }
    });

    test('P1-6-c 계약 미작성·신분증 거절은 다음 행동으로 말한다', () {
      for (final p in [_day, _work]) {
        expect(_codeOf(_src(p)).contains('계약서 작성 필요'), true, reason: p);
      }
      expect(_codeOf(_src('lib/utils/id_card_helper.dart'))
          .contains('신분증 재요청 필요'), true);
    });

    test('P1-7-a 같은 일에 이름이 하나다', () {
      expect(_codeOf(_src(_day)).contains("title: '인력 현황'"), true);
      expect(_codeOf(_src(_work)).contains('인력 현황'), true);
      expect(_codeOf(_src(_card)).contains("'인력 현황'"), true);
      for (final p in [_day, _work]) {
        final s = _codeOf(_src(p));
        expect(s.contains("'지원명단'"), false, reason: p);
        expect(s.contains('지원자 관리'), false, reason: p);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §16 §17 §18 Notification interaction
  // ══════════════════════════════════════════════════════════════
  group('P1-8 Notification interaction', () {
    test('P1-8-a full swipe 즉시 삭제로 바꾸지 않았다', () {
      final s = _codeOf(_src(_notifCard));
      expect(s.contains('Dismissible'), false,
          reason: '계약·확정·급여 알림을 손가락 한 번으로 잃을 수 있는 구조는 만들지 않는다');
      expect(s.contains('onTap: widget.onDismiss'), true,
          reason: '버튼을 눌러야 실행된다');
    });

    test('P1-8-b 미읽음은 [읽음 | 삭제], 읽음은 [삭제]', () {
      final s = _codeOf(_src(_notifCard));
      expect(s.contains("'읽음'"), true);
      expect(s.contains('if (isUnread)'), true);
      expect(s.contains('isUnread ? _revealWidth : _revealWidth / 2'), true);
      // `취소`는 사라졌다 — 바깥 탭으로 이미 닫힌다.
      expect(s.contains("'취소',"), false);
    });

    test('P1-8-c 읽음 action은 읽은 알림에 전달되지 않는다', () {
      final s = _codeOf(_src(_notifScreen));
      expect(s.contains('onMarkRead: notification.isRead'), true);
      expect(s.contains('? null'), true);
    });

    test('P1-8-d Undo는 복원이 아니라 지연 커밋이다', () {
      final s = _codeOf(_src(_notifProvider));
      expect(s.contains('void deleteNotificationDeferred('), true);
      expect(s.contains('bool undoDeleteNotification('), true);
      // 클라이언트가 알림 문서를 만들지 않는다.
      expect(s.contains('createNotification'), false);
      expect(s.contains('.set('), false);
    });

    test('P1-8-e 유예 창을 지나면 취소했다고 말하지 않는다', () {
      final prov = _codeOf(_src(_notifProvider));
      final i = prov.indexOf('bool undoDeleteNotification(');
      expect(prov.substring(i, i + 300).contains('if (timer == null) return false;'),
          true);
      final scr = _codeOf(_src(_notifScreen));
      expect(scr.contains('이미 삭제되어 되돌릴 수 없습니다'), true);
    });

    test('P1-8-f 화면을 떠나면 예약된 삭제를 커밋한다', () {
      final s = _codeOf(_src(_notifProvider));
      expect(s.contains('void flushPendingDeletes()'), true);
      // dispose는 _disposed=true 이전에 flush해야 커밋이 막히지 않는다.
      final i = s.indexOf('void dispose() {');
      expect(i, greaterThan(-1));
      final seg = s.substring(i);
      expect(seg.indexOf('flushPendingDeletes()'),
          lessThan(seg.indexOf('_disposed = true')));
    });

    test('P1-8-g Undo 안내가 실제로 누를 수 있는 것이다', () {
      final s = _codeOf(_src(_notifScreen));
      expect(s.contains('SnackBarAction('), true);
      expect(s.contains("label: '실행 취소'"), true);
      // 토스트는 누를 곳이 없다 — 삭제 경로에서 쓰지 않는다.
      final i = s.indexOf('void _deleteWithUndo(');
      expect(s.substring(i, i + 1200).contains('ToastHelper.showSuccess'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §19 §20 §21 §22 Visible window
  // ══════════════════════════════════════════════════════════════
  group('P1-9 Notification visible window', () {
    final now = DateTime(2026, 9, 23, 12);

    test('P1-9-a 89일 보이고 91일 안 보인다', () {
      expect(
          NotificationRetention.isVisible(
              now.subtract(const Duration(days: 89)), now),
          true);
      expect(
          NotificationRetention.isVisible(
              now.subtract(const Duration(days: 91)), now),
          false);
    });

    test('P1-9-b 90일 경계는 보인다 — 창은 닫힌 구간이다', () {
      expect(
          NotificationRetention.isVisible(
              now.subtract(const Duration(days: 90)), now),
          true);
      expect(
          NotificationRetention.isVisible(
              now.subtract(const Duration(days: 90, seconds: 1)), now),
          false);
    });

    test('P1-9-c 시각을 모르면 숨기지 않는다 — UNKNOWN != OLD', () {
      expect(NotificationRetention.isVisible(null, now), true);
    });

    test('P1-9-d 시각을 모르는 알림을 오늘로 취급하지 않는다', () {
      final m = NotificationModel.fromMap(
          {'userId': 'u', 'type': 'other', 'title': 't', 'body': 'b'}, 'id1');
      expect(m.createdAtKnown, false);
      // 그룹핑이 이 플래그를 본다.
      final scr = _codeOf(_src(_notifScreen));
      expect(scr.contains('if (!n.createdAtKnown) {'), true);
      final i = scr.indexOf('if (!n.createdAtKnown) {');
      expect(scr.substring(i, i + 120).contains('olderItems.add(n)'), true);
    });

    test('P1-9-e copyWith가 UNKNOWN을 지우지 않는다', () {
      final m = NotificationModel.fromMap(
          {'userId': 'u', 'type': 'other', 'title': 't', 'body': 'b'}, 'id1');
      expect(m.copyWith(isRead: true).createdAtKnown, false,
          reason: '읽는 순간 `오늘`로 올라오면 안 된다');
    });

    test('P1-9-f 물리 보존 기준이 화면 기준과 같은 상수다', () {
      final s = _codeOf(
          _src('lib/services/firestore/notification_firestore.dart'));
      expect(s.contains('NotificationRetention.cutoffFrom('), true);
      expect(s.contains('Duration(days: 30)'), false,
          reason: '30일에 지우면서 90일을 보여 준다고 말할 수 없다');
    });

    test('P1-9-g 새 삭제 scheduler를 만들지 않았다', () {
      // 이미 있던 job의 기준만 정책에 맞췄다.
      final s = _src('lib/services/firestore/notification_firestore.dart');
      expect('Future<int> deleteOldNotifications('.allMatchesIn(s), 1);
      final cf = _src('functions/src/index.ts');
      expect(cf.contains('onSchedule') && cf.contains('deleteOldNotifications'),
          false,
          reason: '서버 스케줄러를 추가하지 않았다');
    });

    test('P1-9-h 창을 쿼리 where로 넣지 않았다 — legacy row 은폐 방지', () {
      final s = _codeOf(
          _src('lib/services/firestore/notification_firestore.dart'));
      final i = s.indexOf('Stream<List<NotificationModel>> watchUserNotifications(');
      final seg = s.substring(i, i + 500);
      expect(seg.contains("where('createdAt'"), false);
      expect(seg.contains('limit(31)'), true, reason: 'hasMore 계약 무변경');
    });

    test('P1-9-i pagination이 창 안에서만 돈다', () {
      final s = _codeOf(_src(_notifProvider));
      expect(s.contains('NotificationRetention.cutoffFrom('), true);
      expect(s.contains('if (!oldest.isAfter(cutoff))'), true);
      expect(s.contains('_hasMore = page.hasMore && '), true);
    });

    test('P1-9-j 목록·안읽음 수가 같은 창을 쓴다', () {
      final s = _codeOf(_src(_notifProvider));
      // unreadCount·hasUnread가 모두 notifications를 지난다.
      expect(s.contains('int get unreadCount => notifications.where'), true);
      expect(s.contains('bool get hasUnread => notifications.any'), true);
      // 창 적용은 _buildMerged 한 곳.
      expect('NotificationRetention.isVisible('.allMatchesIn(s), 3);
    });

    test('P1-9-k 창 안내를 업계 표준이라고 말하지 않는다', () {
      final s = _src('lib/utils/notification_retention.dart');
      expect(s.contains('업계 표준'), true, reason: '아니라고 명시한 문장이 있다');
      expect(s.contains('업계 표준이라고 말하지 않는다'), true);
      final scr = _codeOf(_src(_notifScreen));
      expect(scr.contains('최근 \${NotificationRetention.visibleDays}일의 알림만 표시됩니다'),
          true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §24 Notification != Task
  // ══════════════════════════════════════════════════════════════
  group('P1-8/9 Notification != Task', () {
    test('NT-a 읽음·삭제·age-out이 domain 컬렉션을 건드리지 않는다', () {
      final prov = _codeOf(_src(_notifProvider));
      for (final forbidden in [
        'applications',
        'employment_contracts',
        'attendance',
        'payroll',
      ]) {
        expect(prov.contains(forbidden), false,
            reason: '알림 provider가 $forbidden 를 건드리면 안 된다');
      }
    });

    test('NT-b 알림 삭제는 알림 문서 하나만 지운다', () {
      final s = _codeOf(
          _src('lib/services/firestore/notification_firestore.dart'));
      final i = s.indexOf('deleteOldNotifications(String userId)');
      final seg = s.substring(i, i + 900);
      expect(seg.contains('_notificationsFor(userId)'), true);
      expect(seg.contains("collection('applications')"), false);
    });

    test('NT-c Task는 여전히 domain state에서 나온다', () {
      // Home의 처리할 일은 canonical summary에서 파생된다 — 알림 수가 아니다.
      final home = _codeOf(
          _src('lib/screens/business_admin/business_admin_home_screen.dart'));
      expect(home.contains('_makeActionRows('), true);
      final i = home.indexOf('_makeActionRows(BuildContext context');
      final seg = home.substring(i, i + 3000);
      expect(seg.contains('NotificationProvider'), false,
          reason: '알림을 task source로 쓰지 않는다');
    });
  });
}

extension on String {
  int allMatchesIn(String haystack) =>
      RegExp(RegExp.escape(this)).allMatches(haystack).length;
}
