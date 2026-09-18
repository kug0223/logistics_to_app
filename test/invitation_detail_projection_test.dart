// [CROSS-DOMAIN-R5.3D] 통합 초대 상세 projection
//
// 초대 상세는 "공고를 다시 보는 화면"이 아니라
// **"내가 받은 제안의 내용을 보고 수락하는 화면"** 이다.
//
// 이 파일이 고정하는 것:
//
//   1. 화면에 오는 값이 세 층으로 갈린다.
//        PROMISE       — Application 스냅샷. 수락하면 적용될 조건.
//        CONTEXT       — 공고·사업장의 현재 정보. 설명일 뿐이다.
//        ACCEPTABILITY — 지금 수락할 수 있는가. fresh 상태로 판정한다.
//
//   2. 공고를 못 읽어도 초대는 남는다. UNKNOWN ≠ EMPTY.
//
//   3. FULL/CLOSED/UNKNOWN에서도 조건은 보이고 버튼만 잠긴다.
//
//   4. 현재 공고 금액을 수락 조건과 같은 수준으로 나란히 놓지 않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/invitation_projection.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _load(String p) => _flat(_codeOf(_src(p)));

const _screen = 'lib/screens/common/job_posting_screen.dart';
const _card = 'lib/widgets/user/invitation_promise_card.dart';
const _myApps = 'lib/screens/user/my_applications_screen.dart';
const _notifScreen = 'lib/screens/common/notification_screen.dart';
const _fcm = 'lib/services/fcm_service.dart';

ApplicationModel _invited({
  int wage = 100000,
  String wageType = 'daily',
  String status = 'INVITED',
  InviteCapacityState capacity = InviteCapacityState.available,
  String? offerKind,
  String? compensationOption,
  int? breakMinutes = 60,
  String workType = '사무업무',
  String start = '10:00',
  String end = '17:00',
}) {
  return ApplicationModel(
    id: 'app1', businessId: 'b1', businessName: '위워커', toTitle: 't',
    workDate: DateTime(2026, 11, 11), startTime: start, endTime: end,
    uid: 'u1', selectedWorkType: workType, wdId: 'wd1',
    toId: 'to1', slotId: 'slot1',
    wage: wage, wageType: wageType,
    breakMinutes: breakMinutes, nightAllowanceApplied: true,
    nightIncluded: false, taxDeductionType: 'none',
    status: status, appliedAt: DateTime(2026, 11, 1),
    workInstanceCapacityState: capacity,
    offerKind: offerKind, compensationOption: compensationOption,
  );
}

WorkDetailData _liveWd({
  int wage = 100000,
  String wageType = 'daily',
  int breakMinutes = 60,
  String workType = '사무업무',
  String start = '10:00',
  String end = '17:00',
}) {
  return WorkDetailData(
    wdId: 'wd1', workType: workType, wage: wage, wageType: wageType,
    requiredCount: 2, startTime: start, endTime: end,
    breakMinutes: breakMinutes,
  );
}

void main() {
  // ══════════════════════════════════════════════════════════════════
  // 세 층 분리
  // ══════════════════════════════════════════════════════════════════

  group('PROMISE / CONTEXT / ACCEPTABILITY가 분리돼 있다', () {
    test('promise는 Application에서만 온다', () {
      final p = InvitationProjection.of(
        application: _invited(wage: 100000),
        postingLoaded: true,
        liveWorkDetail: _liveWd(wage: 110000), // 공고는 그 사이 올랐다
      );
      // 화면이 읽는 금액은 약속 하나다.
      expect(p.application.wage, 100000);
      expect(p.drift.wage, true, reason: '차이는 감지하되 금액을 바꾸지는 않는다');
    });

    test('공고를 못 읽어도 초대는 남는다', () {
      final p = InvitationProjection.of(
        application: _invited(), postingLoaded: false);
      expect(p.contextState, InvitationContextState.unavailable);
      expect(p.application.wage, 100000, reason: 'promise는 그대로다');
      expect(p.canAccept, true, reason: '공고 부재가 수락 불가 사유는 아니다');
    });

    test('못 읽은 공고를 "달라졌다"고 말하지 않는다', () {
      final p = InvitationProjection.of(
        application: _invited(), postingLoaded: false, liveWorkDetail: null);
      expect(p.drift.hasAny, false);
      expect(p.driftNotice, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // acceptability — 정보 접근과 수락 가능 여부 분리
  // ══════════════════════════════════════════════════════════════════

  group('수락 가능 여부는 조건 표시와 별개다', () {
    test('FULL — 조건은 보이고 이유를 말한다', () {
      final p = InvitationProjection.of(
        application: _invited(capacity: InviteCapacityState.full),
        postingLoaded: true);
      expect(p.canAccept, false);
      expect(p.blockedReason, contains('인원이 모두 차서'));
      expect(p.application.wage, 100000, reason: '약속은 계속 보인다');
    });

    test('CLOSED는 FULL과 다른 이유를 말한다', () {
      final p = InvitationProjection.of(
        application: _invited(capacity: InviteCapacityState.closed),
        postingLoaded: true);
      expect(p.blockedReason, contains('모집이 종료'));
      expect(p.blockedReason, isNot(contains('모두 차서')));
    });

    test('UNKNOWN을 FULL로 바꾸지 않는다', () {
      final p = InvitationProjection.of(
        application: _invited(capacity: InviteCapacityState.unknown),
        postingLoaded: true);
      expect(p.canAccept, false);
      expect(p.blockedReason, contains('확인하지 못했'));
      expect(p.blockedReason, isNot(contains('모두 차서')));
      expect(p.blockedReason, isNot(contains('종료')));
    });

    test('이미 답한 초대는 수락 대상이 아니다', () {
      for (final st in ['CONFIRMED', 'REJECTED', 'EXPIRED', 'AUTO_CANCELED']) {
        final p = InvitationProjection.of(
          application: _invited(status: st), postingLoaded: true);
        expect(p.acceptability, InvitationAcceptability.alreadyResolved,
            reason: st);
        expect(p.canAccept, false);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // drift advisory — 두 숫자를 나란히 놓지 않는다
  // ══════════════════════════════════════════════════════════════════

  group('차이는 안내일 뿐 경쟁하는 진실이 아니다', () {
    test('차이가 없으면 안내도 없다', () {
      final p = InvitationProjection.of(
        application: _invited(), postingLoaded: true,
        liveWorkDetail: _liveWd());
      expect(p.drift.hasAny, false);
      expect(p.driftNotice, isNull);
    });

    test('금액이 바뀌면 무엇이 적용되는지만 말한다', () {
      final p = InvitationProjection.of(
        application: _invited(wage: 100000), postingLoaded: true,
        liveWorkDetail: _liveWd(wage: 110000));
      expect(p.driftNotice, contains('초대 조건이 적용됩니다'));
      // 현재 금액을 문구에 넣지 않는다 — 두 숫자를 경쟁시키지 않는다.
      expect(p.driftNotice, isNot(contains('110')));
      expect(p.driftNotice, isNot(contains('100,000')));
    });

    test('시간·휴게·업무명 변경도 감지한다', () {
      final p = InvitationProjection.of(
        application: _invited(), postingLoaded: true,
        liveWorkDetail: _liveWd(
            start: '09:00', breakMinutes: 30, workType: '주방보조'));
      expect(p.drift.time, true);
      expect(p.drift.breakMinutes, true);
      expect(p.drift.workType, true);
    });

    test('약속에 없는 항목은 다르다고 하지 않는다', () {
      // 레거시 지원서는 휴게를 모른다 — 모르는 것을 차이로 세지 않는다.
      final p = InvitationProjection.of(
        application: _invited(breakMinutes: null), postingLoaded: true,
        liveWorkDetail: _liveWd(breakMinutes: 30));
      expect(p.drift.breakMinutes, false);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 개별 급여 / 다른 업무 제안
  // ══════════════════════════════════════════════════════════════════

  group('개별 급여와 제안을 구분한다', () {
    test('MATCH_SOURCE_WAGE면 개별 급여로 표시한다', () {
      final p = InvitationProjection.of(
        application: _invited(
            wage: 120000,
            offerKind: 'ALTERNATIVE_WORK',
            compensationOption: 'MATCH_SOURCE_WAGE'),
        postingLoaded: true,
        liveWorkDetail: _liveWd(wage: 100000));
      expect(p.hasIndividualCompensation, true);
      expect(p.isAlternativeOffer, true);
      expect(p.application.wage, 120000, reason: '수락 조건은 120,000이다');
    });

    test('TARGET_BASE 제안은 개별 급여가 아니다', () {
      final p = InvitationProjection.of(
        application: _invited(
            offerKind: 'ALTERNATIVE_WORK', compensationOption: 'TARGET_BASE'),
        postingLoaded: true);
      expect(p.isAlternativeOffer, true);
      expect(p.hasIndividualCompensation, false);
    });

    test('cross-type TARGET_BASE는 target 단위를 그대로 쓴다', () {
      final p = InvitationProjection.of(
        application: _invited(
            wage: 13000, wageType: 'hourly',
            offerKind: 'ALTERNATIVE_WORK', compensationOption: 'TARGET_BASE'),
        postingLoaded: true, liveWorkDetail: _liveWd(
            wage: 13000, wageType: 'hourly'));
      expect(p.application.wageType, 'hourly');
      expect(p.application.wage, 13000);
      expect(p.drift.hasAny, false, reason: 'source A의 일급이 섞이지 않는다');
    });

    test('일반 초대는 제안이 아니다', () {
      final p = InvitationProjection.of(
        application: _invited(), postingLoaded: true);
      expect(p.isAlternativeOffer, false);
      expect(p.hasIndividualCompensation, false);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 화면 배선
  // ══════════════════════════════════════════════════════════════════

  group('상세 화면이 promise를 primary로 놓는다', () {
    final s = _load(_screen);

    test('promise 카드가 공고 업무 목록보다 먼저 온다', () {
      final card = s.indexOf('InvitationPromiseCard(');
      final work = s.indexOf('_buildWorkSection(context),');
      expect(card, greaterThan(-1));
      expect(card < work, true,
          reason: '결정의 근거가 되는 숫자가 공고 목록보다 뒤에 오면 안 된다');
    });

    test('INVITED가 아니면 일반 공고 상세 그대로다', () {
      expect(
          s.contains('if (app == null || app.status != AppStatus.invited) return null;'),
          true);
    });

    test('공고를 못 읽으면 초대 fallback을 연다', () {
      expect(s.contains('InvitationFallbackDetail('), true);
      expect(
          s.contains("? (_invitationProjection(postingLoaded: false) != null "
              '? InvitationFallbackDetail('),
          true,
          reason: '초대가 아니면 기존 error state 그대로다');
    });

    test('공고 식별자가 없어도 초대는 열린다', () {
      expect(
          s.contains('assert(toId != null || to != null || myApplication != null,'),
          true);
      expect(s.contains("} else if ((widget.toId ?? '').isEmpty) {"), true);
    });

    test('수락 버튼만 잠기고 조건은 남는다', () {
      expect(
          s.contains('!(_invitationProjection(postingLoaded: _to != null) '
              '?.canAccept ?? true))'),
          true);
    });

    test('차이 계산은 wdId로만 한다', () {
      expect(
          s.contains("if (app.wdId != null && app.wdId!.isNotEmpty && "
              'w.wdId == app.wdId) {'),
          true,
          reason: '업무명만 보고 같은 업무라고 하지 않는다');
    });

    test('원 지원은 본인 것일 때만 맥락으로 쓴다', () {
      expect(s.contains('if (one != null && one.uid == app.uid) {'), true);
    });
  });

  group('promise 카드가 하나의 금액만 말한다', () {
    final c = _load(_card);

    test('카드의 모든 값이 Application에서 온다', () {
      for (final f in [
        'app.selectedWorkType', 'app.startTime', 'app.endTime',
        'app.breakMinutes', 'app.formattedWage', 'app.wageTypeLabel',
      ]) {
        expect(c.contains(f), true, reason: '누락: $f');
      }
    });

    test('공고 현재값을 카드에 넣지 않는다', () {
      for (final forbidden in [
        'WorkDetailModel live', '_to!.', 'workDetails[', 'posting.wage',
      ]) {
        expect(c.contains(forbidden), false, reason: '현재값 혼입: $forbidden');
      }
    });

    test('개별 급여면 그 사실을 말한다', () {
      expect(c.contains("'회원님께 제안된 급여입니다',"), true);
    });

    test('제안이면 기존 지원을 맥락으로만 보여준다', () {
      expect(c.contains("'기존 지원',"), true);
      expect(c.contains('수락하면 기존 지원은 자동으로 정리됩니다.'), true);
      // A는 두 번째 수락 대상이 아니다 — 버튼이 붙지 않는다.
      expect(c.contains('sourceApplication!.id'), false);
    });

    test('공고 부재를 초대 부재로 표현하지 않는다', () {
      expect(c.contains('현재 공고 상세를 불러올 수 없습니다.'), true);
      expect(c.contains('위 초대 조건은 그대로 유효합니다.'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 진입 경로
  // ══════════════════════════════════════════════════════════════════

  group('모든 진입점이 같은 상세로 간다', () {
    test('내 지원 카드 탭', () {
      expect(_load(_myApps).contains('builder: (_) => JobPostingScreen('), true);
    });

    test('삭제된 공고의 초대도 열린다', () {
      final m = _load(_myApps);
      expect(m.contains("if (app.status != 'INVITED') {"), true);
      expect(m.contains('toId: app.toId, myApplication: app,'), true);
    });

    test('알림은 payload 상태가 아니라 Application을 다시 읽는다', () {
      final m = _load(_myApps);
      expect(m.contains('Future<void> _focusRequestedApplication() async {'), true);
      expect(m.contains('await _firestoreService.getApplicationOnce(wanted);'), true);
    });

    test('toInvite와 제안 알림이 같은 목적지를 쓴다', () {
      final n = _load(_notifScreen);
      expect(n.contains('case NotificationType.toInvite:'), true);
      expect(n.contains('case NotificationType.workReassignmentOffered:'), true);
      expect(_load(_fcm).contains("case 'workReassignmentOffered':"), true);
    });
  });

  group('수락 payload는 한 벌이다', () {
    test('상세 화면도 My Applications와 같은 계약을 쓴다', () {
      final s = _load(_screen);
      expect(s.contains('if (!meetsApplyPrerequisites(user, isFlexType: isFlex)) {'),
          true);
      expect(
          s.contains("'documentAccessConsentGiven': true, "
              "'documentAccessConsentVersion': DocumentAccessConsent.version,"),
          true);
    });
  });
}
