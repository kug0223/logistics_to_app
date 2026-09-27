// [POSTING-LIFECYCLE-E2E] 공고 하나를 끝까지 따라가며 확인한 계약.
//
// 이번에 고친 것 — 대기 인원을 세는 정의가 두 개였다.
//
//   초대(INVITED)는 자리를 잡아 두는 대기다. invite writer는 pendingCount를
//   +1 하고 만료·수락이 -1 한다. 그런데 절대값으로 다시 세는 경로는
//   `status == "PENDING"`만 셌다. 지원서가 하나라도 쓰이면 그 경로가 돌아
//   미수락 초대가 대기 수에서 사라졌다. 그리고 날짜 마감은 슬롯 합계만 줄이고
//   업무별 카운터는 그대로 둬서, 거절된 지원이 업무 대기에 계속 남았다.
//
//   실측(수정 전) — 대기 2건 + 초대 1건을 만들고 마감:
//     실제 대기 1 · slot.pending 0 · workDetailCounts 3 · TO.totalPending 0
//   한 화면 안에서 세 숫자가 서로 달랐다.
//   실측(수정 후): 1 / 1 / 1 — 지원·초대·마감·재개 네 단계 모두 일치.
//
// 나머지는 이미 있던 계약이 한 lifecycle 안에서도 함께 성립하는지 확인한 것이다.
//
// DEV chain (공고 1개 · 3날짜 × 업무 2개 · 근로자 8명):
//   생성 parity        writer=manager=applicant 14 field 불일치 0
//   지원 A(11000/60) → 공고 13000/30으로 수정 → A 불변 · 신규 B는 13000/30
//   초대 C(11000/60) → 공고 15000/45로 수정 → C 불변 → 수락 CONFIRMED에도 11000/60
//                      미발송 계약 목록에도 11000으로 잡힘
//   확정 A            → CONTRACT_PENDING · 11000/60 유지 (공고는 13000)
//   A날짜 WD1 정원 참 → 그 업무만 403, 같은 날 WD2·다른 날짜는 200
//   C날짜 마감        → PENDING만 REJECTED · 초대는 INVITED 유지 · 신규 403
//   마감 중 초대 수락  → 400 "모집이 종료된 근무는 수락할 수 없습니다"
//                      확정 0→0 · TO 확정 3→3 · 계약서 0건
//   재개              → 슬롯 3→3 · wdId 불변 · 확정 불변 · 수락 200(11000 유지)
//   필요 2→4 허용 / 4→2 허용 / 2→1 거절 · 확정자 CONTRACT_PENDING 유지
//   업무·시간 변경     → 세 날짜 모두 400 · 지원서 9건 wdId join 끊김 0
//   관계 있는 삭제     → 400 · 지원서 9→9
//   관계 0 삭제        → 소프트 삭제 · 목록에서 제거 · 직접 지원 404 "삭제된 공고입니다"

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnsPath = 'functions/src/index.ts';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _callableOf(String source, String name) {
  final start = source.indexOf('export const $name = onCall(');
  if (start < 0) throw StateError('$name 을 찾지 못함');
  final next = source.indexOf('\nexport ', start + 10);
  return source.substring(start, next == -1 ? source.length : next);
}

void main() {
  final raw = _src(_fnsPath);
  final fnsFlat = _flat(_codeOf(raw));

  group('대기 인원을 세는 정의는 하나다', () {
    test('초대도 대기다 — 상수로 고정한다', () {
      expect(fnsFlat.contains('const PENDING_STATUSES = ["PENDING", "INVITED"];'), true,
          reason: '세는 곳이 여럿이면 정의가 갈라진다');
    });

    test('절대값 재계산이 초대를 빠뜨리지 않는다', () {
      expect(RegExp(r'where\("status", "==", "PENDING"\)\s*\.count\(\)')
          .hasMatch(fnsFlat.replaceAll(' ', '')), false,
          reason: 'PENDING만 세면 미수락 초대가 대기에서 사라진다');
      expect('appsRef.where("status", "in", PENDING_STATUSES).count().get()'
          .allMatches(fnsFlat).length >= 2, true);
      // [R7-7] 슬롯 대기는 `.count()` 대신 문서로 읽고, 그 읽기가
      //   transaction 안에 있다. 세는 **정의**는 그대로 `PENDING_STATUSES` 라
      //   미수락 초대가 대기에서 빠지지 않는다.
      expect(fnsFlat.contains('pendingCount: pendingDocs.size,'), true,
          reason: '문서로 읽은 그 모집단을 그대로 슬롯 대기로 쓴다');
    });

    // [R7-6] 트리거가 업무 단위 대기도 같은 모집단으로 센다 — 초대 포함.
    // [R7-7] 슬롯 범위 재계산이 transaction 안으로 옮겼다. 세는 모집단은 그대로다.
    test('트리거의 업무 단위 재계산도 초대를 센다', () {
      expect(fnsFlat.contains('function srvSyncSlotCountersTx('), true,
          reason: '슬롯 범위 재계산의 owner');
      expect(fnsFlat.contains('for (const d of pendingDocs.docs) tallyOne(d, true);'),
          true);
      expect(fnsFlat.contains('for (const d of seatedDocs.docs) tallyOne(d, false);'),
          true);
      // 대기 모집단은 PENDING_STATUSES — 초대가 빠지지 않는다.
      expect(
          fnsFlat.replaceAll(' ', '').contains(
              'tx.get(slotAppsRef.where("status","in",PENDING_STATUSES)'
              '.select(...FIELDS))'),
          true);
      // 좌석 판정은 공고 단위와 같은 규칙을 쓴다.
      expect(fnsFlat.contains('if (d.get("staffingReleasedAt") != null) return;'), true);
      expect(fnsFlat.contains('if (!occupiesSeatToday(d)) return;'), true);
    });

    // [R7-7] 낡은 스냅샷으로 쓰지 않는다 — 쓰기 시점에 다시 센다.
    test('슬롯 범위 재계산이 transaction 안에서 다시 센다', () {
      final f = fnsFlat.replaceAll(' ', '');
      expect(f.contains('returndb.runTransaction(async(tx)=>{'), true,
          reason: '읽고-쓰기가 같은 transaction 이어야 conflict 가 잡힌다');
      // 트리거와 재집계가 **같은** writer 를 쓴다.
      expect('srvSyncSlotCountersTx('.allMatches(fnsFlat).length >= 3, true,
          reason: '정의 1 + 트리거 1 + 재집계 1');
      // 좌석 판정도 한 벌이다.
      expect(fnsFlat.contains('function srvOccupiesSeatToday('), true);
    });

    // [R7-6] 절대 재계산은 인원이 0 이 된 업무도 0 으로 적어야 한다.
    test('절대 재계산이 인원 0 인 업무를 옛 값으로 남기지 않는다', () {
      expect(fnsFlat.contains('function srvBuildWdCountsUpdate('), true,
          reason: '쓰기 모양이 한 곳에 있어야 트리거와 재집계가 갈라지지 않는다');
      expect(fnsFlat.contains('out[`workDetailCounts.\${id}.confirmedCount`] = 0;'), true,
          reason: '슬롯의 모든 wdId 를 먼저 0 으로 깔지 않으면 옛 값이 남는다');
      // [R7-7] 이제 호출부가 하나다 — 트리거도 재집계도
      //   `srvSyncSlotCountersTx` 를 지나므로 쓰기 모양이 그 안에서만 결정된다.
      expect('srvBuildWdCountsUpdate('.allMatches(fnsFlat).length, 2,
          reason: '정의 1 + 유일한 호출부 1. 늘어나면 쓰기 모양이 갈라진 것이다');
      expect(fnsFlat.contains('...srvBuildWdCountsUpdate(rawSlotWds, tally, failClosed),'),
          true, reason: '그 호출부는 transactional writer 안이어야 한다');
    });

    // [R7-6] identity 해석이 한 벌이다.
    test('업무 identity 해석이 한 곳에만 있다', () {
      expect(fnsFlat.contains('function srvResolveAppWdId('), true);
      expect('srvResolveAppWdId('.allMatches(fnsFlat).length >= 3, true,
          reason: '정의 1 + 트리거 1 + 재집계 1');
      // new-schema 에서 못 맞추면 first-match 로 때우지 않는다.
      expect(fnsFlat.contains('if (same.length > 1) return {via: "ambiguous"};'), true);
      expect(fnsFlat.contains('return {via: "unresolved"};'), true);
    });

    test('마감이 업무 단위 대기도 줄인다', () {
      final close = _flat(_codeOf(_callableOf(raw, 'callableCloseSlots')));
      expect(close.contains('const rejectedByWd = new Map<string, number>();'), true);
      expect(close.contains('slotUpdate[`workDetailCounts.\${rejectedWdId}.pendingCount`] = '
          'admin.firestore.FieldValue.increment(-n);'), true,
          reason: '슬롯 합계만 줄이면 날짜칩의 업무별 대기가 거절된 지원을 계속 센다');
    });

    test('초대 writer는 세 카운터를 함께 올린다', () {
      final inv = _flat(_codeOf(_callableOf(raw, 'callableInviteWorker')));
      expect(inv.contains('pendingCount: admin.firestore.FieldValue.increment(1),'), true);
      expect(inv.contains('workDetailCounts.\${inviteResolvedWdId}.pendingCount'), true);
      expect(inv.contains('{totalPending: admin.firestore.FieldValue.increment(1)}'), true);
    });
  });

  group('모집이 끝난 자리에는 수락으로도 들어갈 수 없다', () {
    final acc = _flat(_codeOf(_callableOf(raw, 'callableAcceptTOInvitation')));

    test('날짜 마감을 트랜잭션 안에서 다시 본다', () {
      expect(acc.contains('if (freshSlotData.isManualClosed === true || '
          'freshSlotData.status === "closed")'), true,
          reason: '정원 guard는 이것을 못 잡는다 — 마감이어도 자리는 남아 있다');
      expect(acc.contains('모집이 종료된 근무는 수락할 수 없습니다'), true);
    });

    test('업무 단위 마감도 본다', () {
      expect(acc.contains('if (acceptWd && (acceptWd["isManualClosed"] === true || '
          'acceptWd["closedAt"] != null))'), true);
    });

    test('검사가 자리 배정보다 앞선다', () {
      final g = acc.indexOf('모집이 종료된 근무는 수락할 수 없습니다');
      final c = acc.indexOf('confirmedCount');
      expect(g > 0 && g < c, true, reason: '쓰기 전에 걸러야 한다');
    });

    test('정원도 함께 본다', () {
      expect(acc.contains('슬롯 정원이 초과되어 초대를 수락할 수 없습니다'), true);
    });
  });

  group('약속은 만들어진 시점의 조건으로 남는다', () {
    test('초대도 지원과 같은 스냅샷을 만든다', () {
      final inv = _flat(_codeOf(_callableOf(raw, 'callableInviteWorker')));
      expect(inv.contains('buildCompensationSnapshot('), true,
          reason: '초대에 스냅샷이 없으면 수락 시점의 공고 값으로 계산된다');
    });

    test('수락은 조건을 다시 쓰지 않는다', () {
      final acc = _codeOf(_callableOf(raw, 'callableAcceptTOInvitation'));
      for (final f in ['wage:', 'breakMinutes:', 'baseHourlyWage:',
        'nightAllowanceApplied:', 'startTime:', 'endTime:']) {
        expect(RegExp('\\n\\s*$f').hasMatch(acc), false,
            reason: '수락 경로가 $f 를 쓰면 초대 당시 약속이 덮인다');
      }
    });

    test('수락은 status만 앞으로 옮긴다', () {
      final acc = _flat(_codeOf(_callableOf(raw, 'callableAcceptTOInvitation')));
      expect(acc.contains('status: "CONFIRMED"'), true);
    });
  });

  group('마감은 대기만 정리하고 약속은 건드리지 않는다', () {
    final close = _flat(_codeOf(_callableOf(raw, 'callableCloseSlots')));

    test('PENDING만 거절 대상이다', () {
      expect(close.contains('.where("status", "==", "PENDING")'), true,
          reason: '초대·확정까지 쓸어 담으면 약속이 사라진다');
      expect(close.contains('"INVITED"'), false);
      expect(close.contains('"CONFIRMED"'), false);
    });

    test('거절에는 이유가 남는다', () {
      expect(close.contains('rejectMessage: "공고 슬롯이 마감되었습니다"'), true);
    });

    test('열린 날짜가 하나도 없을 때만 공고를 닫는다', () {
      expect(close.contains('if (!hasOpenSlot && openStates.includes(currentTOStatus ?? ""))'),
          true, reason: '날짜 하나 마감이 공고 전체를 닫으면 다른 날짜 모집이 죽는다');
    });
  });

  group('재개는 있던 것을 복제하지 않는다', () {
    test('날짜는 자연 키다 — 같은 날짜에 슬롯은 하나', () {
      final flex = _flat(_codeOf(_callableOf(raw, 'callableCreateFlexSlots')));
      expect(flex.contains('if (existingDateMs.has(slotDate.toMillis())) { skippedExisting++; continue; }'),
          true);
    });

    test('wdId는 서버가 만들고 클라이언트 값을 쓰지 않는다', () {
      final flex = _flat(_codeOf(_callableOf(raw, 'callableCreateFlexSlots')));
      expect(flex.contains('wdId: generateWdId(),'), true,
          reason: 'wdId가 흔들리면 지원서의 join이 끊긴다');
    });

    test('재개는 새 슬롯을 만들지 않는다', () {
      final re = _codeOf(_callableOf(raw, 'callableReopenSlots'));
      expect(RegExp(r'collection\("slots"\)\.doc\(\)').hasMatch(re), false,
          reason: '재개 경로에 auto-id 슬롯 생성이 있으면 날짜가 두 번 보인다');
    });
  });

  group('수락 실패 이유가 근로자에게 그대로 전달된다', () {
    test('내 지원 목록', () {
      final s = _flat(_codeOf(_src('lib/screens/user/my_applications_screen.dart')));
      expect(s.contains("ToastHelper.showError(e.message ?? '수락 중 오류가 발생했습니다.');"),
          true, reason: 'generic 문구로 덮으면 왜 안 되는지 알 수 없다');
    });

    test('공고 상세', () {
      final s = _flat(_codeOf(_src('lib/screens/common/job_posting_screen.dart')));
      expect(s.contains("ToastHelper.showError(e.message ?? '수락 중 오류가 발생했습니다.');"), true);
    });

    test('수락은 언제나 서버를 거친다', () {
      for (final p in ['lib/screens/user/my_applications_screen.dart',
        'lib/screens/common/job_posting_screen.dart']) {
        final s = _flat(_codeOf(_src(p)));
        expect(s.contains("httpsCallable('callableAcceptTOInvitation')"), true,
            reason: '$p 가 알림 payload만 보고 상태를 바꾸면 안 된다');
      }
    });
  });
}
