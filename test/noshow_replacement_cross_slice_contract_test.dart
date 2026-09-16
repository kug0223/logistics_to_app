// [POSTING-CROSS-SLICE.1] 당일 NO_SHOW × 날짜 마감/재개 × 대체 충원
//
// 두 가지를 고쳤다.
//
//   1. 반납한 좌석이 재계산으로 되살아났다.
//      좌석 반납은 지원서의 status를 바꾸지 않는다 — NO_SHOW 이력을 남겨야
//      하므로 CONFIRMED 그대로 두고 staffingReleasedAt 표식만 찍는다. 원래
//      설계는 "status가 안 바뀌니 재계산이 돌지 않는다"에 기대고 있었는데,
//      그 말은 그 지원서 자신의 write에 대해서만 맞다. 같은 공고에 다른
//      지원서가 하나라도 쓰이면 — 대체 인력 초대가 바로 그것이다 — 재계산이
//      돌고, 재계산은 status만 세므로 반납한 자리를 다시 占有로 되돌렸다.
//
//      실측(수정 전): 반납 직후 TO 1/2 → 대체 초대 직후 2/2 →
//                     대체 인력 수락 400 "마감 또는 정원 초과된 공고"
//                     즉 대체 충원 기능 자체가 성립하지 않았다.
//      실측(수정 후): 반납 1/2 → 재계산 후 1/2 · slot full→open →
//                     대체 수락 200 → 최종 2/2 (대체자가 자리를 차지)
//
//   2. 모집이 끝난 날짜의 좌석을 반납할 수 있었다.
//      지원·초대·초대수락은 전부 마감을 보고 거절하는데 반납만 보지 않았다.
//      다중 날짜 공고에서 오늘 날짜만 마감하고 반납하면 TO가 FULL에서
//      ACTIVE로 되살아났고, 그 날짜는 여전히 closed여서 아무도 넣을 수 없는
//      자리에 부족 1이 생겼다. (실측: TO FULL→ACTIVE · 부족 0→1 ·
//      그 자리에 초대 400 "마감된 슬롯에는 초대를 보낼 수 없습니다")
//
// 마감의 뜻을 새로 정한 것이 아니라, 이미 있는 뜻을 빠져 있던 한 곳에 적용했다.
// 되돌리는 길은 재오픈이고 메시지가 그것을 알린다. NO_SHOW 기록은 그대로 둔다.
//
// DEV chain (오늘 날짜 · 두 순서):
//   A순서 NO_SHOW → 반납 → 마감 → 재개 → 대체 초대/수락 200 → TO 2/2
//   B순서 NO_SHOW → 마감 → 반납 400(사유+경로) → 재개 → 대체 초대/수락 200
//   FULL 잠금 NO_SHOW → 마감 → 반납 400 → 재개 400("확정 취소를 통해서만")
//            → 확정취소 → 재개 200 → 대체 충원 200
//   세 경우 모두 NO_SHOW 근태 기록 생존 · 슬롯 복제 0 · wdId 불변
//   재시도 시 alreadyReleased · 이중 감소 0
//   close/reopen/replacement 자체 알림 emitter 없음

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
  final rel = _flat(_codeOf(_callableOf(raw, 'callableReleaseNoshowSeat')));

  group('반납한 좌석은 다시 세어도 빈 자리다', () {
    test('반납 표식은 staffingReleasedAt 하나다', () {
      expect(rel.contains('staffingReleasedAt: now, staffingReleaseReason: "NO_SHOW",'), true);
      expect(rel.contains('staffingReleased: true'), false,
          reason: '표식이 둘이면 그 필드가 없는 기존 반납 문서가 다시 좌석으로 세어진다');
    });

    test('재계산이 확정 문서를 직접 읽고 반납된 것을 뺀다', () {
      // 집계 쿼리는 "필드가 있는 문서"를 셀 수 없다 — == null 은 명시적 null만
      // 잡고, != null·orderBy 는 새 인덱스를 요구한다(실측). 그래서 읽고 거른다.
      expect(fnsFlat.contains('if (d.get("staffingReleasedAt") != null) continue;'), true);
      expect(fnsFlat.contains('.select("slotId", "staffingReleasedAt")'), true);
      expect(fnsFlat.contains('const confirmedCount = seats.bySlot.get(slotId) ?? 0;'), true);
      expect(fnsFlat.contains('const flexConfirmedCnt = seats.to;'), true);
      expect(fnsFlat.contains('const confirmedCnt = seats.to;'), true);
    });

    test('불리언 표식에 의존하는 집계가 남아 있지 않다', () {
      expect(fnsFlat.contains('.where("staffingReleased", "==", true)'), false,
          reason: '필드가 없는 문서를 자동 제외하는 구조는 legacy를 놓친다');
    });

    test('한 번 읽어 공고 단위와 슬롯 단위를 함께 만든다', () {
      expect(fnsFlat.contains('to: number; bySlot: Map<string, number>;'), true,
          reason: '두 숫자가 다른 읽기에서 나오면 서로 어긋날 수 있다');
    });

    test('복구(노쇼 취소)는 남아 있을 수 있는 표식까지 지운다', () {
      final cancel = _flat(_codeOf(_callableOf(raw, 'callableBatchCancelNoShow')));
      expect(cancel.contains('staffingReleasedAt: admin.firestore.FieldValue.delete(), '
          'staffingReleased: admin.firestore.FieldValue.delete(),'), true);
    });

    test('반납해도 지원서 status는 그대로다', () {
      // NO_SHOW 이력이 사라지면 안 된다 — 자리만 비우고 기록은 남긴다.
      expect(RegExp(r'status:\s*"(CANCELED|AUTO_CANCELED|REJECTED)"').hasMatch(rel), false);
      expect(rel.contains('staffingReleaseReason: "NO_SHOW"'), true);
    });

    test('판정 쪽도 같은 사실을 본다', () {
      expect(fnsFlat.contains('if (appData["staffingReleasedAt"] != null) return false;'), true,
          reason: '좌석 판정과 카운터가 같은 사실을 봐야 한다');
    });
  });

  group('모집이 끝난 날짜의 자리는 반납하지 않는다', () {
    test('날짜 마감을 본다', () {
      expect(rel.contains('relSlotPreData["isManualClosed"] === true || '
          'relSlotPreData["status"] === "closed"'), true);
      expect(rel.contains('종료된 근무일입니다. 대체 인력을 충원하려면 먼저 날짜를 재오픈해주세요.'),
          true, reason: '막기만 하고 다음 행동을 알려주지 않으면 갇힌다');
    });

    test('공고 종료도 본다', () {
      expect(rel.contains('["CLOSED", "POSTING_EXPIRED", "DELETED"].includes(relToStatus ?? "")'),
          true);
      expect(rel.contains('종료된 공고입니다. 대체 인력을 충원하려면 먼저 공고를 재오픈해주세요.'), true);
    });

    test('검사가 카운터를 건드리기 전에 끝난다', () {
      final g = rel.indexOf('종료된 근무일입니다');
      final t = rel.indexOf('await db.runTransaction');
      expect(g > 0 && g < t, true);
    });

    test('자리를 채우는 나머지 writer와 같은 규칙이다', () {
      // 하나라도 마감을 안 보면 "채울 수 없는 자리"가 생긴다.
      expect(_flat(_codeOf(_callableOf(raw, 'callableApplyToTO')))
          .contains('해당 날짜는 마감되었습니다'), true);
      expect(_flat(_codeOf(_callableOf(raw, 'callableInviteWorker')))
          .contains('마감된 슬롯에는 초대를 보낼 수 없습니다'), true);
      expect(_flat(_codeOf(_callableOf(raw, 'callableAcceptTOInvitation')))
          .contains('모집이 종료된 근무는 수락할 수 없습니다'), true);
    });
  });

  group('대체 충원은 당일 한 번만', () {
    test('오늘 근무만 대상이다', () {
      expect(rel.contains('if (wdKstStartMs !== todayKstStartMs)'), true);
      expect(rel.contains('이미 지난 근무는 대체 인력을 충원할 수 없습니다'), true);
      expect(rel.contains('당일 근무만 대체 인력을 충원할 수 있습니다'), true);
    });

    test('재시도는 두 번 빼지 않는다', () {
      expect(rel.contains('if (appData.staffingReleasedAt != null) '
          '{ return {alreadyReleased: true, toId: appData.toId}; }'), true);
      final i = rel.indexOf('alreadyReleased');
      final t = rel.indexOf('await db.runTransaction');
      expect(i > 0 && i < t, true, reason: '멱등 판정이 감소보다 앞서야 한다');
    });

    test('확정된 자리이고 NO_SHOW 기록이 있어야 한다', () {
      expect(rel.contains('확정된 지원서만 좌석 반납이 가능합니다'), true);
      expect(rel.contains('NO_SHOW 출근 기록이 없는 지원서입니다'), true);
    });

    test('권한은 TO 관리 권한이다', () {
      expect(rel.contains('canManageTo'), true);
      expect(rel.contains('인력 관리 권한이 없습니다'), true);
    });
  });

  group('화면과 서버가 같은 조건을 쓴다', () {
    test('지원자 화면도 종료된 모집 단위에는 대체충원을 권하지 않는다', () {
      final d = _flat(_codeOf(
          _src('lib/screens/business_admin/dialogs/day_applicants_dialog.dart')));
      expect('_isReplacementActionable && !isRecruitClosed'.allMatches(d).length >= 1, true);
      expect(d.contains('_isReplacementActionable && !isRecruitClosed) ...['), true);
      expect(d.contains('isRecruitClosed: g.canonicalClosed))'), true,
          reason: '마감 여부는 이미 slot에서 내려오는 canonical 값을 쓴다');
    });

    test('당일 게이트는 두 화면이 같다', () {
      final d = _flat(_codeOf(
          _src('lib/screens/business_admin/dialogs/day_applicants_dialog.dart')));
      expect(d.contains('return dateKst.isAtSameMomentAs(todayKst);'), true);
      final a = _flat(_codeOf(
          _src('lib/screens/business_admin/dialogs/attendance_status_dialog.dart')));
      expect(a.contains('if (app.isStaffingReleased) return const SizedBox.shrink();'), true);
      expect(a.contains('return const SizedBox.shrink(); // 과거/미래 날짜 → CTA 숨김'), true);
    });

    test('근태 화면도 종료된 모집 단위에는 권하지 않는다', () {
      final a = _flat(_codeOf(
          _src('lib/screens/business_admin/dialogs/attendance_status_dialog.dart')));
      expect(a.contains('if (wdId != null && _closedUnitByWdId?[wdId] == true) '
          '{ return const SizedBox.shrink(); }'), true);
    });

    test('종료 여부를 지원자 화면과 같은 source에서 읽는다', () {
      final a = _flat(_codeOf(
          _src('lib/screens/business_admin/dialogs/attendance_status_dialog.dart')));
      expect(a.contains('_firestoreService.getDayStaffingDetail('), true,
          reason: '슬롯 상태를 따로 캐시하거나 추측하면 두 화면이 갈린다');
      expect(a.contains('closedByUnit = {for (final r in rows) r.wdId: r.isClosed};'), true);
      final d = _flat(_codeOf(
          _src('lib/screens/business_admin/dialogs/day_applicants_dialog.dart')));
      expect(d.contains('_svc.getDayStaffingDetail('), true);
    });

    test('모르는 상태를 종료로 바꾸지 않는다', () {
      final a = _flat(_codeOf(
          _src('lib/screens/business_admin/dialogs/attendance_status_dialog.dart')));
      expect(a.contains('Map<String, bool>? _closedUnitByWdId;'), true,
          reason: 'null = UNKNOWN. 조회 실패를 종료로 읽으면 멀쩡한 CTA가 사라진다');
    });

    test('거절 사유가 그대로 관리자에게 전달된다', () {
      final s = _flat(_codeOf(_src('lib/services/firestore/application_firestore.dart')));
      expect(s.contains("ToastHelper.showError(e.message ?? '대체 충원 처리에 실패했습니다');"),
          true, reason: 'generic 문구로 덮으면 재오픈하면 된다는 것을 알 수 없다');
      expect(s.contains("if (e.code == 'already-exists')"), true);
    });
  });

  // 당일 지원 창 — 슬롯 date는 그 날 KST 자정이다. 시각으로 비교하면
  // 00:00을 지나는 순간 오늘 슬롯이 전부 '지난 날짜'가 되어, 시작 2시간 전
  // 마감이 한 번도 열리지 않는다. 클라이언트 canonical 판정은 오늘을 제외하지
  // 않는다 — 같은 action의 판정이 화면과 서버에서 갈려 있었다.
  // 실측(수정 후): 어제 차단 · 오늘 마감 전 허용 · 오늘 마감 후 차단 · 내일 허용
  group('당일 지원 창은 마감시각이 판단한다', () {
    final apply = _flat(_codeOf(_callableOf(raw, 'callableApplyToTO')));

    test('과거는 날짜 단위로 막는다', () {
      expect(apply.contains(
          'if (kstDayStartOf(slotWorkDateTs.toMillis()) < kstDayStartOf(Date.now()))'), true);
      expect(apply.contains('slotWorkDateTs.toDate() < new Date()'), false,
          reason: '시각 비교는 오늘을 통째로 과거로 만든다');
    });

    test('오늘은 마감시각이 판단한다', () {
      final d = apply.indexOf('kstDayStartOf(slotWorkDateTs.toMillis())');
      final w = apply.indexOf('해당 업무의 지원 마감 시간이 지났습니다');
      expect(d > 0 && w > d, true, reason: '날짜 게이트를 지나야 마감 검사에 닿는다');
      expect(apply.contains('if (wdDeadlineTs && wdDeadlineTs.toDate() < new Date())'), true);
    });

    test('클라이언트 판정도 오늘을 제외하지 않는다', () {
      final m = _flat(_codeOf(_src('lib/models/core/work_detail_data.dart')));
      expect(m.contains('if (isClosed || isTimeExpired) return true;'), true);
      expect(m.contains(
          'return FormatHelper.toKstDate(slotDate).isBefore(FormatHelper.toKstDate(today));'),
          true, reason: 'isBefore — 오늘은 포함되지 않는다. 서버와 같은 기준이어야 한다');
    });

    test('마감 계산은 서버가 만든다', () {
      final flex = _flat(_codeOf(_callableOf(raw, 'callableCreateFlexSlots')));
      expect(flex.contains('newWd.applicationDeadline = admin.firestore.Timestamp.fromMillis( '
          'calcDeadlineMs(dateStr, wd.startTime as string, hoursBeforeStart)'), true);
      expect(flex.contains('if (dateStr < todayStr)'), true,
          reason: '오늘 날짜 공고 생성은 허용된다 — 당일 모집이 정상 경로다');
    });
  });

  group('마감과 재개가 기록을 건드리지 않는다', () {
    test('마감은 대기만 정리한다', () {
      final c = _flat(_codeOf(_callableOf(raw, 'callableCloseSlots')));
      expect(c.contains('.where("status", "==", "PENDING")'), true);
      expect(c.contains('staffingReleased'), false,
          reason: '마감이 좌석을 자동 반납하면 관리자가 하지 않은 결정을 하게 된다');
    });

    test('재개는 슬롯을 새로 만들지 않는다', () {
      final r = _codeOf(_callableOf(raw, 'callableReopenSlots'));
      expect(RegExp(r'collection\("slots"\)\.doc\(\)').hasMatch(r), false);
    });

    test('재개가 정원 충족 공고를 우회하지 않는다', () {
      final r = _flat(_codeOf(_callableOf(raw, 'callableReopenSlots')));
      expect(r.contains('정원이 충족된 공고는 확정 취소를 통해서만 모집 상태로 변경됩니다'), true,
          reason: '막되 다음 행동을 알려준다');
    });
  });
}
