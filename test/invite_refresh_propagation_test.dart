// [ISG2-REFRESH] 초대를 보낸 뒤 **같은 세션에서** 대기 수가 올라간다.
//
// ── 무엇이 끊겨 있었나 ────────────────────────────────────────────────
//   `_hasChanges` 는 확정·거절 경로에서만 세워졌다. 초대 경로는
//   `day_applicants_dialog` 에서 아예 세워지지 않았고,
//   `work_applicants_dialog` 는 자기 목록만 다시 읽고 상위에는 알리지
//   않았다. 그래서 초대를 보내고 닫아도 공고 카드의 `대기` 가 그대로였다.
//
//   그리고 결과 네 가지(성공·취소·실패·응답 불명확)가 구분되지 않았다.
//   `work_applicants_dialog` 는 취소해도 매번 다시 읽었고,
//   `day_applicants_dialog` 는 응답 불명확(`null`)에서 읽지 않아
//   **실제로 저장된 초대가 화면에 안 나타날 수 있었다.**
//
// ── 이 테스트가 보는 것 ───────────────────────────────────────────────
//   IRP-A  판단 식 자체(실제 함수 호출)
//   IRP-B  두 다이얼로그가 그 식을 쓰고, 성공에서만 상위로 전파한다
//   IRP-C  상위(공고 카드·업무 행·홈·알림)가 그 신호를 받는다
//   IRP-D  재조회 실패를 "대기 0"이나 "저장 실패"로 바꾸지 않는다
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/ui/invite_refresh_outcome.dart';

String _read(String p) => File(p).readAsStringSync();

const _day = 'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';
const _work = 'lib/screens/business_admin/dialogs/work_applicants_dialog.dart';
const _sheet =
    'lib/screens/business_admin/dialogs/available_workers_bottom_sheet.dart';
const _groupCard = 'lib/widgets/admin/cards/admin_to_group_card.dart';
const _workDetail = 'lib/widgets/admin/cards/admin_work_detail.dart';
const _notif = 'lib/screens/common/notification_screen.dart';
const _attendance =
    'lib/screens/business_admin/dialogs/attendance_status_dialog.dart';

void main() {
  group('IRP-A 판단 식', () {
    test('IRP-01 성공(sent) — 상위 전파 + 재조회', () {
      expect(inviteDialogOutcome(const InviteDialogResult.sent()),
          const InviteRefreshOutcome(propagate: true, reload: true));
    });

    test('IRP-02 취소(canceled) — 아무것도 하지 않는다', () {
      expect(inviteDialogOutcome(const InviteDialogResult.canceled()),
          const InviteRefreshOutcome(propagate: false, reload: false));
    });

    test('IRP-03 바깥에서 닫힘(null) — 성공으로 세지 않되 **다시 읽는다**', () {
      final o = inviteDialogOutcome(null);
      expect(o.propagate, isFalse, reason: '모르는 것을 성공으로 표시하지 않는다');
      expect(o.reload, isTrue,
          reason: '쓰기가 들어갔을 수 있다 — 진실은 서버에서 다시 읽는다');
      expect(o.verify, isNull);
    });

    test('IRP-03b 시도 뒤 불명확(unconfirmed) — 전파 없이 읽고, 대상 확인을 요구한다',
        () {
      const t = InviteVerifyTarget(toId: 'to1', targetUid: 'u1', slotId: 's1');
      expect(inviteDialogOutcome(const InviteDialogResult.unconfirmed(t)),
          const InviteRefreshOutcome(propagate: false, reload: true, verify: t));
    });

    test('IRP-04 가능일 시트 — 한 명이라도 성공해야 전파, 읽기는 항상', () {
      expect(inviteSheetOutcome(anySucceeded: true),
          const InviteRefreshOutcome(propagate: true, reload: true));
      expect(inviteSheetOutcome(anySucceeded: false),
          const InviteRefreshOutcome(propagate: false, reload: true));
    });
  });

  group('IRP-B 두 다이얼로그의 배선', () {
    test('IRP-05 시트는 **성공 직후에만** 콜백을 부른다', () {
      final s = _read(_sheet);
      expect(s.contains('final VoidCallback? onInviteSucceeded'), isTrue);
      final cbAt = s.indexOf('widget.onInviteSucceeded?.call()');
      expect(cbAt, greaterThan(0));
      final successAt = s.indexOf("ToastHelper.showSuccess('근무 제안을 보냈습니다.')");
      expect(successAt, greaterThan(0));
      expect(cbAt, greaterThan(successAt),
          reason: '성공 표시 뒤에 있어야 한다 — 실패 경로에서 불리면 안 된다');
      // 콜백은 두 곳에만 있다 — 응답 성공 직후, 그리고 [E1] 불명확한 응답 뒤
      //   다시 읽어 **저장이 확인된** 분기. 실패·취소·unknown 에는 없다.
      expect('onInviteSucceeded?.call()'.allMatches(s).length, 2);
      final savedAt = s.indexOf('case InviteSaveCheck.saved:');
      final notSavedAt = s.indexOf('case InviteSaveCheck.notSaved:');
      final secondCb = s.lastIndexOf('widget.onInviteSucceeded?.call()');
      expect(secondCb > savedAt && secondCb < notSavedAt, isTrue,
          reason: '확인된 저장 분기 안에서만 부른다');
    });

    test('IRP-06 day/work 모두 공용 식을 쓴다', () {
      for (final p in [_day, _work]) {
        final s = _read(p);
        expect(s.contains("import '../../../models/ui/invite_refresh_outcome.dart';"),
            isTrue, reason: p);
        expect(s.contains('outcome.propagate') && s.contains('outcome.reload'),
            isTrue, reason: p);
        expect(s.contains('inviteSheetOutcome('), isTrue, reason: p);
        expect(s.contains('inviteDialogOutcome('), isTrue, reason: p);
      }
    });

    test('IRP-07 직접 초대 다이얼로그 결과를 **InviteDialogResult 로** 받는다', () {
      // 예전에는 `showDialog<void>` 라 성공 신호가 버려졌고, 그 뒤 bool 은
      //   "시도 뒤 닫힘"을 취소와 구분하지 못했다.
      for (final p in [_day, _work]) {
        final s = _read(p);
        final i = s.indexOf('InviteWorkerDialog.contextual(');
        expect(i, greaterThan(0), reason: p);
        final head = s.substring(i - 400, i);
        expect(head.contains('showDialog<InviteDialogResult>'), isTrue,
            reason: p);
        // 닫힌 결과는 다시 읽어 확정한 뒤에 쓴다.
        expect(s.contains('InviteSaveVerifier.resolve('), isTrue, reason: p);
      }
    });

    test('IRP-08 day 는 `_hasChanges`, work 는 `_inviteChanged` 로 기록한다', () {
      // day 다이얼로그는 bool 하나를 돌려준다 — 그 소비자(Home·근무 탭·
      //   알림·근태)에는 공고 탭으로 가는 local 경로가 없어서
      //   `notifyDataChanged` 가 유일한 전파 채널이다.
      expect(_read(_day).contains('if (outcome.propagate) _hasChanges = true;'),
          isTrue);
      // work 다이얼로그는 공고 카드가 local `onChanged()` 를 갖고 있다 —
      //   초대만으로 Home full refresh 를 깨우지 않도록 따로 센다.
      final w = _read(_work);
      expect(w.contains('if (outcome.propagate) _inviteChanged = true;'), isTrue);
      expect(w.contains('hasChanges: _hasChanges || _inviteChanged,'), isTrue);
      expect(w.contains('homeRelevant: _hasChanges,'), isTrue);
    });

    test('IRP-08b 초대만 바뀐 경우 공고 카드는 Home 을 깨우지 않는다', () {
      // 기록된 결정: "공고 탭 인력 초대는 Home staffing/summary 를 바꾸지
      //   않으므로 Posting local refresh 만 하고 이 신호를 보내지 않는다"
      //   (WorkforceController.notifyDataChanged 주석).
      for (final p in [_groupCard, _workDetail]) {
        final s = _read(p);
        expect(
            RegExp(r'if \(result\.homeRelevant\)\s*\{\s*WorkforceController\.notifyDataChanged')
                .hasMatch(s),
            isTrue,
            reason: '$p — Home 알림이 homeRelevant 로 묶여 있지 않다');
      }
      expect(_read(_notif).contains('waResult.homeRelevant'), isTrue);
    });
  });

  group('IRP-C 상위가 신호를 받는다', () {
    test('IRP-09 공고 카드·업무 행은 hasChanges 에서 재조회+전역 알림', () {
      for (final p in [_groupCard, _workDetail]) {
        final s = _read(p);
        expect(s.contains('result.hasChanges'), isTrue, reason: p);
        expect(s.contains('WorkforceController.notifyDataChanged'), isTrue,
            reason: p);
      }
    });

    test('IRP-10 day 다이얼로그는 닫을 때 `_hasChanges` 를 돌려준다', () {
      final s = _read(_day);
      expect(s.contains('Navigator.pop(context, _hasChanges)'), isTrue);
    });

    test('IRP-11 알림·근태 진입도 결과를 버리지 않는다', () {
      // 이 셋은 결과를 받아 두고 아무것도 하지 않았다 — 알림에서 들어와
      //   초대·확정을 해도 공고 탭·홈이 모르고 있었다.
      final n = _read(_notif);
      expect('WorkforceController.notifyDataChanged'.allMatches(n).length, 2,
          reason: 'Day·WorkApplicants 두 진입점');
      final a = _read(_attendance);
      expect(a.contains('WorkforceController.notifyDataChanged'), isTrue);
    });
  });

  group('IRP-D 재조회 실패를 오해로 바꾸지 않는다', () {
    test('IRP-12 work 목록은 ERROR 와 EMPTY 를 구분해 말한다', () {
      final s = _read(_work);
      expect(s.contains('applicantLoadOutcome('), isTrue);
      expect(s.contains("ToastHelper.showError('최신 정보를 불러오지 못했습니다."), isTrue,
          reason: '재조회 실패는 저장 실패가 아니라 "최신 정보" 실패로 말한다');
    });

    test('IRP-13 재조회는 저장 실패 문구를 쓰지 않는다', () {
      for (final p in [_day, _work]) {
        final s = _read(p);
        expect(s.contains('초대에 실패했습니다'), isFalse, reason: p);
      }
    });
  });
}
