// [SYSTEM-INTEGRATION-R2.4] 초대/인원의 cross-surface 무결성
//
// 최상위 invariant:
//
//     같은 entity + 같은 event = 모든 surface에서 같은 business truth
//
// 표현은 달라도 된다. `부족 3 · 초대 중 2`와 `필요 5 / 확정 2`는 같은 사실의
// 다른 문장이다. 숫자나 상태의 **의미**가 다르면 BLOCKER다.
//
// 이 파일이 고정하는 것:
//   · 부족은 확정만 뺀다 — 초대도 지원도 자리를 확보하지 않는다
//   · 좌석 반납(staffingReleasedAt)은 어느 표면에서도 자리로 세지 않는다
//   · 모집 종료는 어느 표면에서도 부족이 아니다
//   · 한 화면 안에서 같은 수치를 두 번 계산하지 않는다
//   · mutation은 모든 관련 탭에 도달한다

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _after(String source, String signature, [int chars = 2000]) {
  final a = source.indexOf(signature);
  if (a == -1) throw StateError('$signature 를 찾지 못함');
  final end = a + chars;
  return source.substring(a, end > source.length ? source.length : end);
}

String _tsSliceOf(String source, String from, String to) {
  final a = source.indexOf(from);
  if (a == -1) throw StateError('$from 를 찾지 못함');
  final b = source.indexOf(to, a + from.length);
  if (b == -1) throw StateError('$to 를 찾지 못함');
  return source.substring(a, b);
}

const _cfPath = 'functions/src/index.ts';
const _dayPath = 'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';
const _cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';
const _wadPath = 'lib/screens/business_admin/dialogs/work_applicants_dialog.dart';
const _wfPath =
    'lib/screens/business_admin/workforce_management/workforce_operational_view.dart';
const _svcPath = 'lib/services/firestore_service.dart';
const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';

void main() {
  final cfRaw = _src(_cfPath);
  final dayRaw = _src(_dayPath);
  final day = _codeOf(dayRaw);
  final readiness = _tsSliceOf(cfRaw,
      'export const callableGetStaffingReadiness', '      days: aggDays,');

  // ═════════════════════════════════════════════════════════════
  // 1. 부족 = 필요 − 확정. 초대도 지원도 빼지 않는다 (§5)
  // ═════════════════════════════════════════════════════════════
  group('R2.4-01 shortage 정의', () {
    test('01-a 어느 reader도 초대/지원을 부족에서 빼지 않는다', () {
      // `required - confirmed - invited` 나 `- pending` 형태 금지.
      for (final p in const [_dayPath, _homePath, _cardPath]) {
        final s = _codeOf(_src(p));
        for (final banned in const [
          '- invited',
          '- invitedApps',
          '- activeInvites',
          'confirmed - pending',
          'confirmedCount - pendingCount',
        ]) {
          expect(s.contains(banned), isFalse, reason: '$p 에 $banned');
        }
      }
    });

    test('01-b 서버 readiness도 확정만 뺀다', () {
      expect(
          readiness.contains(
              'Math.max(0, wd.required - confirmed)'),
          isTrue);
      // INVITED를 confirmed로 세지 않는다
      expect(readiness.contains('"INVITED"'), isFalse);
    });

    test('01-c 초대는 자리를 확보하지 않는다 — 초대 후 confirmed 불변', () {
      // canonical counter를 올리는 것은 수락뿐이다.
      final invite = _tsSliceOf(cfRaw, 'export const callableInviteWorker',
          'export const callableAcceptTOInvitation');
      expect(invite.contains('confirmedCount`]'), isFalse);
      expect(
          invite.contains('workDetailCounts.\${inviteWdId}.confirmedCount'),
          isFalse);
      final accept = _tsSliceOf(cfRaw, 'export const callableAcceptTOInvitation',
          'export const callableDeclineTOInvitation');
      expect(accept.contains('.confirmedCount`]'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 2. 좌석 반납 — 모든 표면이 같이 뺀다 (§4/§19)
  // ═════════════════════════════════════════════════════════════
  group('R2.4-02 staffingReleased', () {
    test('02-a status만 보고 자리를 세는 reader가 없다', () {
      // 반납된 확정은 status가 CONFIRMED로 남지만 정원을 소모하지 않는다.
      final svc = _codeOf(_src(_svcPath));
      final f = _after(svc, 'loadTOWorkDetails(', 2200);
      expect(f.contains('!a.isStaffingReleased'), isTrue,
          reason: '공고 카드 통계가 반납 좌석을 확정으로 센다');
      expect(f.contains('countsAsSeat'), isTrue);
    });

    test('02-b 당일명단도 같은 기준이다', () {
      final g = _after(dayRaw, 'int get seatedConfirmed', 260);
      expect(g.contains('!a.isStaffingReleased'), isTrue);
    });

    test('02-c 서버 canonical counter도 반납 시 내려간다', () {
      final rel = _after(cfRaw, 'staffingReleaseReason: "NO_SHOW"', 2200);
      expect(rel.contains('confirmedCount'), isTrue);
      expect(rel.contains('totalConfirmed'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 3. 모집 종료 — 어느 표면에서도 부족이 아니다 (§4/§19, FULL != CLOSED)
  // ═════════════════════════════════════════════════════════════
  group('R2.4-03 CLOSED', () {
    test('03-a Home readiness가 종료를 읽는다', () {
      expect(
          readiness.contains(
              'sd["isManualClosed"] === true || sd["status"] === "closed"'),
          isTrue,
          reason: 'Home이 종료된 단위를 계속 부족으로 센다');
      expect(readiness.contains('wd.closed ?'), isTrue);
      // 업무 단위 종료도 같다
      expect(readiness.contains('w["closedAt"] != null'), isTrue);
    });

    test('03-b 당일명단 부족도 종료를 읽는다', () {
      final g = _after(dayRaw, 'int get shortage {', 400);
      expect(g.contains('capacityState == InviteCapacityState.closed'), isTrue);
      expect(g.contains('return 0;'), isTrue);
    });

    test('03-c 서버 두 reader가 같은 종료 신호를 쓴다', () {
      final detail = _tsSliceOf(cfRaw,
          'export const callableGetDayStaffingDetail', 'return {rows};');
      for (final s in const [
        'sd["isManualClosed"] === true || sd["status"] === "closed"',
      ]) {
        expect(detail.contains(s), isTrue, reason: 'detail: $s');
        expect(readiness.contains(s), isTrue, reason: 'readiness: $s');
      }
    });

    test('03-d 존재하지 않는 필드로 종료를 판정하지 않는다', () {
      // `slot.isClosed`는 Firestore 문서에 없다 (R2 FINAL에서 확인).
      expect(readiness.contains('sd["isClosed"]'), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 4. 한 화면 안에서 같은 수치를 두 번 계산하지 않는다 (§19)
  // ═════════════════════════════════════════════════════════════
  group('R2.4-04 단일 계산식', () {
    test('04-a 당일명단의 부족은 _GroupData.shortage 하나다', () {
      // 통계 스트립 · 초대 CTA · 초대 방법 시트가 모두 같은 값을 쓴다.
      expect(day.contains('acc + g.shortage'), isTrue);
      final n = RegExp(r'final shortage = g\.shortage;')
          .allMatches(day)
          .length;
      expect(n, 2, reason: 'CTA/시트 중 자체 계산이 남았다');
      // 로컬 재계산이 남아 있으면 안 된다
      expect(
          day.contains(
              'g.requiredCount - g.confirmedApps.where((a) => !a.isStaffingReleased).length'),
          isFalse,
          reason: '부족을 다시 계산하는 곳이 남았다');
    });

    test('04-b 초대 시트에 넘기는 확정도 같은 기준이다', () {
      // 눌렀을 때의 `부족 N`과 열린 시트의 `확정 M · 부족 N`이 어긋나면 안 된다.
      expect(day.contains('confirmedCount: g.seatedConfirmed'), isTrue);
      expect(day.contains('confirmedCount: g.confirmedApps.length'), isFalse);
    });

    test('04-c 공고 카드 헤더와 날짜 칩이 같은 source를 쓴다', () {
      final card = _codeOf(_src(_cardPath));
      final agg = _after(card, 'void _updateGroupCache()', 1400);
      expect(agg.contains('t.resolveStats()'), isTrue);
      // legacy 슬롯 카운터 직접 합산이 남아 있으면 안 된다
      expect(agg.contains('p += t.pendingCount'), isFalse,
          reason: 'slot.pendingCount를 사용자 truth로 쓰고 있다');
      expect(agg.contains('c += t.confirmedCount'), isFalse);
    });

    test('04-d 초대 CTA 노출 조건도 같은 값을 쓴다', () {
      expect(day.contains('g.shortage > 0'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 5. mutation이 모든 관련 탭에 도달한다 (§14/§19)
  // ═════════════════════════════════════════════════════════════
  group('R2.4-05 refresh contract', () {
    test('05-a 세 탭 모두 dataRevision을 구독한다', () {
      for (final e in {
        'Home': _homePath,
        'Jobs': 'lib/screens/business_admin/jobs_root_screen.dart',
        'Workforce': _wfPath,
      }.entries) {
        final s = _src(e.value);
        expect(s.contains('WorkforceController.dataRevision.addListener'), isTrue,
            reason: '${e.key} 가 다른 탭의 mutation을 받지 않는다');
        expect(s.contains('WorkforceController.dataRevision.removeListener'),
            isTrue, reason: '${e.key} 가 listener를 해제하지 않는다');
      }
    });

    test('05-b 자기 mutation은 무시한다 — 중복 로드 방지', () {
      final wf = _codeOf(_src(_wfPath));
      expect(
          wf.contains(
              'WorkforceController.lastMutationOrigin ==\n        AdminMutationOrigin.workforce'),
          isTrue);
    });

    test('05-c 새 polling/listener를 만들지 않았다', () {
      final wf = _src(_wfPath);
      for (final banned in const [
        'Timer.periodic',
        'snapshots()',
        'Stream.periodic',
      ]) {
        expect(wf.contains(banned), isFalse, reason: '$banned 가 추가됐다');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 6. 알림 payload를 truth로 쓰지 않는다 (§16)
  // ═════════════════════════════════════════════════════════════
  group('R2.4-06 notification', () {
    test('06-a 알림에서 연 다이얼로그가 실제 지원서로 수치를 만든다', () {
      final wad = _codeOf(_src(_wadPath));
      // [CROSS-DOMAIN-R5.1F.2] initState에 대상 사업장 권한 구독이 더해져
      //   창이 좁아졌다. 보는 성질은 그대로 — 창 크기만 맞춘다.
      final init = _after(_src(_wadPath), 'void initState() {', 1500);
      expect(init.contains('_updateLocalStats(markChanged: false)'), isTrue,
          reason: '알림 진입 시 확정 0으로 표시된다');
      expect(wad.contains('Future<void> _updateLocalStats({bool markChanged = true})'),
          isTrue);
    });

    test('06-b 첫 로드를 변경으로 표시하지 않는다', () {
      final wad = _codeOf(_src(_wadPath));
      expect(wad.contains('if (markChanged) _hasChanges = true;'), isTrue);
    });

    test('06-c 항상 0을 돌려주는 getter가 truth로 남지 않는다', () {
      // WorkDetailData.currentCount/pendingCount는 구 아키텍처 잔재다.
      final wd = _src('lib/models/core/work_detail_data.dart');
      expect(wd.contains('int get currentCount => 0;'), isTrue,
          reason: '이 stub이 바뀌면 위 보정의 전제가 달라진다');
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 7. 근무 탭은 확정자만 보여준다 (§10)
  // ═════════════════════════════════════════════════════════════
  group('R2.4-07 work/staffing', () {
    test('07-a INVITED를 근무 확정자로 표시하지 않는다', () {
      final wf = _codeOf(_src(_wfPath));
      expect(wf.contains('getConfirmedWorkersByDateAndBusiness'), isTrue);
      expect(wf.contains('AppStatus.invited'), isFalse);
      // 그 reader는 CONFIRMED/CONTRACT_PENDING만 담는다
      final svc = _codeOf(_src('lib/services/firestore/application_firestore.dart'));
      expect(
          svc.contains(
              'const confirmedStatuses = {AppStatus.confirmed, AppStatus.contractPending};'),
          isTrue);
    });

    test('07-b 근무 탭도 canonical destination을 연다 (§11)', () {
      final wf = _codeOf(_src(_wfPath));
      expect(wf.contains('DayApplicantsDialog('), isTrue);
      // 별도 invitation management 화면을 만들지 않았다
      final dir = Directory('lib/screens');
      final invScreens = dir
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path.replaceAll('\\', '/'))
          .where((p) =>
              p.contains('invitation_management') || p.contains('invite_management'))
          .toList();
      expect(invScreens, isEmpty);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 8. FLEX 날짜 truth (§7)
  // ═════════════════════════════════════════════════════════════
  group('R2.4-08 FLEX date-level', () {
    test('08-a 공고 전체 FULL로 다른 날짜 지원을 막지 않는다', () {
      final apply = _tsSliceOf(cfRaw, 'export const callableApplyToTO',
          'export const callableGetMyApplications');
      expect(
          apply.contains('(toData["status"] === "FULL" && !applyIsSlotBased)'),
          isTrue);
    });

    test('08-b Home·detail 모두 슬롯 단위로 센다', () {
      for (final s in [readiness, _tsSliceOf(cfRaw,
          'export const callableGetDayStaffingDetail', 'return {rows};')]) {
        expect(s.contains('workDetailCounts'), isTrue);
        expect(s.contains('slots'), isTrue);
      }
      // 공고 전체 카운터를 날짜 truth로 쓰지 않는다
      expect(readiness.contains('d["totalConfirmed"]'), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 10. [R2.4.1 §2] 지원자 화면도 같은 shortage truth를 쓴다
  //
  //   PENDING은 관심, INVITED는 제안. 자리를 차지하는 것은
  //   CONTRACT_PENDING과 CONFIRMED뿐이다. 지원자 화면이라고 예외가 아니다.
  // ═════════════════════════════════════════════════════════════
  group('R2.4.1-10 지원자 공고 잔여 좌석', () {
    final jp = _codeOf(_src('lib/screens/common/job_posting_screen.dart'));

    test('10-a 잔여 좌석에서 대기를 빼지 않는다', () {
      expect(
          jp.contains('(workRequired - workConfirmed).clamp(0, workRequired)'),
          isTrue);
      expect(jp.contains('workRequired - workConfirmed - workPending'), isFalse,
          reason: '지원자만 다른 부족을 본다');
    });

    test('10-b 잔여 0은 정원 마감이라는 뜻이다', () {
      // 예전에는 대기까지 빼서 0이 될 수 있어 `대기중`으로 얼버무렸다.
      expect(jp.contains("workPending > 0 ? '대기중' : '마감'"), isFalse);
      expect(jp.contains("workAvailable > 0\n                                    ? '\$workAvailable명'\n                                    : '마감'"),
          isTrue);
    });

    test('10-c FULL 판정도 확정만 본다', () {
      expect(
          jp.contains('workConfirmed >= workRequired && workRequired > 0'),
          isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 11. [R2.4.1 §4] 인원을 못 읽었으면 인원 기반 action을 막는다
  // ═════════════════════════════════════════════════════════════
  group('R2.4.1-11 ERROR != ZERO (mutation 가능 화면)', () {
    test('11-a 업무별 마감 관리가 통계 실패 시 열리지 않는다', () {
      final d = _codeOf(
          _src('lib/screens/business_admin/dialogs/work_detail_management_dialog.dart'));
      expect(d.contains('if (toItem.workDetailStatsFailed) {'), isTrue,
          reason: '0/N을 보고 마감할 수 있다');
      expect(d.contains('인원 현황을 불러오지 못했어요'), isTrue);
      // 가드가 showDialog보다 앞에 있어야 한다
      final guard = d.indexOf('if (toItem.workDetailStatsFailed) {');
      final show = d.indexOf('showDialog(');
      expect(guard, greaterThan(0));
      expect(show, greaterThan(guard));
    });

    test('11-b 실패 플래그가 실제로 세워진다', () {
      final ctl = _codeOf(_src('lib/controllers/workforce_controller.dart'));
      expect(ctl.contains('slot.markWorkDetailStatsFailed()'), isTrue);
      final m = _codeOf(_src('lib/models/ui/admin_to_list_ui_models.dart'));
      expect(m.contains('workDetailStatsFailed = true;'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 12. [R2.4.1 §5] composite identity 고유성 — 모든 writer에서
  //
  //   Posting은 아직 `workType_startTime_endTime`으로 workDetail을 조인한다.
  //   그 조인이 안전하려면 같은 슬롯에 같은 조합이 둘 생길 수 없어야 한다.
  //   "현재 fixture에서 숫자가 같았다"가 아니라 writer가 막는다는 증거다.
  // ═════════════════════════════════════════════════════════════
  group('R2.4.1-12 composite identity', () {
    test('12-a 생성 경로가 중복을 막는다', () {
      expect(cfRaw.contains('function srvAssertUniqueWorkDetailIds('), isTrue);
      final create = _tsSliceOf(cfRaw, 'export const callableCreateTO',
          'export const callableCreateFlexSlots');
      expect(create.contains('srvAssertUniqueWorkDetailIds(toWorkDetailsCreate)'),
          isTrue, reason: '공고 생성이 중복 composite를 통과시킨다');
    });

    test('12-b 슬롯 생성 경로도 막는다', () {
      final flex = _tsSliceOf(cfRaw, 'export const callableCreateFlexSlots',
          'export const callablePublishTO');
      expect(flex.contains('srvAssertUniqueWorkDetailIds(workDetails)'), isTrue);
    });

    test('12-c 수정 경로는 이미 막고 있었다', () {
      expect(
          cfRaw.contains(
              '"같은 업무 유형과 근무 시간의 업무가 중복되었습니다. 각 업무의 조합은 고유해야 합니다."'),
          isTrue);
      expect(cfRaw.contains('const checkDuplicateIds ='), isTrue);
    });

    test('12-d 클라이언트도 같은 규칙을 안내한다', () {
      final edit = _codeOf(
          _src('lib/screens/business_admin/to_management/edit_to_screen.dart'));
      expect(edit.contains('같은 업무와 근무 시간이 이미 있습니다.'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 13. [R2.4.2 §1] 일괄 마감 화면이 잘못된 `대기` 수를 말하지 않는다
  // ═════════════════════════════════════════════════════════════
  group('R2.4.2-13 SlotBatch pending truth', () {
    final sb = _codeOf(
        _src('lib/screens/business_admin/dialogs/slot_batch_select_dialog.dart'));

    test('13-a slot.pendingCount를 사용자 truth로 쓰지 않는다', () {
      // 초대 발송 시 +1 되었다가 syncTOStats가 PENDING만 세며 내려가는 값이다.
      expect(sb.contains('slot.pendingCount'), isFalse,
          reason: '지원 대기 0 · 초대 중 2가 `대기 2명`으로 보인다');
      expect(sb.contains("대기 \${slot.pendingCount}명"), isFalse);
    });

    test('13-b 마감 판단에 필요한 확정 수는 남겼다', () {
      expect(sb.contains(r"'확정 ${slot.confirmedCount}/${slot.totalRequired}명'"),
          isTrue);
    });

    test('13-c 대신 새 aggregate를 만들지 않았다', () {
      for (final banned in const [
        'pendingApplicationCount',
        'invitedCount',
        'inviteCount',
      ]) {
        expect(sb.contains(banned), isFalse, reason: '$banned 가 추가됐다');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 14. [R2.4.2 §2] 지원 검토 task는 PENDING만 센다
  // ═════════════════════════════════════════════════════════════
  group('R2.4.2-14 task lifecycle', () {
    test('14-a task reader가 PENDING만 센다 — 초대는 task가 아니다', () {
      final f = _after(cfRaw, 'async function srvHomeApproval(', 900);
      expect(f.contains('.where("status", "==", "PENDING")'), isTrue);
      expect(f.contains('INVITED'), isFalse,
          reason: '관리자가 먼저 보낸 제안이 지원 검토 task로 잡힌다');
    });

    test('14-b task는 applications를 세지 notifications를 세지 않는다', () {
      final f = _after(cfRaw, 'async function srvHomeApproval(', 900);
      expect(f.contains('collection("applications")'), isTrue);
      expect(f.contains('notifications'), isFalse,
          reason: 'Notification != Task');
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 9. 권한 (§12)
  // ═════════════════════════════════════════════════════════════
  group('R2.4-09 permission', () {
    test('09-a 초대 관련 서버 경로가 모두 canManageTo다', () {
      for (final fn in const [
        'export const callableGetAvailableWorkers',
        'export const callableGetDayStaffingDetail',
      ]) {
        final s = _after(cfRaw, fn, 3000);
        expect(s.contains('canManageTo !== true'), isTrue, reason: fn);
        expect(s.contains('TO 관리 권한이 없습니다.'), isTrue, reason: fn);
      }
      final invite = _tsSliceOf(cfRaw, 'export const callableInviteWorker',
          'export const callableAcceptTOInvitation');
      expect(invite.contains('canManageTo'), isTrue);
    });

    test('09-b 알림 deep link도 같은 capability를 본다', () {
      final n = _codeOf(_src('lib/screens/common/notification_screen.dart'));
      expect(n.contains('targetPermissions.canManageTo'), isTrue);
    });
  });
}
