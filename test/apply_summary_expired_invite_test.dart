// [SIM-EXPIRED-INVITE-SUMMARY] 만료된 초대가 공고 상세 '내 지원 일정'에 "대기"로 보였다
//
// DEVICE(10-18, 원본 APK, 7oZZ): DEV 에서 EXPIRED 인 초대(10/19 14:00–15:00)가 다른 공고
//   상세의 '내 지원 일정'에 "대기"로 나왔다. 같은 건이 '내 지원'에서는 "초대 종료"였다.
//
// 원인: `ApplySummarySection._active` 는 `AppStatus.inactiveStates`
//   (REJECTED·CANCELED·AUTO_CANCELED)만 거르고, 남은 것은 확정이 아니면 전부 "대기"로
//   그린다. EXPIRED 는 그 목록에 없다. 전역 목록은 지원서 조회·상태 전이 판정도 쓰므로
//   건드리지 않고, 이 요약에서만 만료 초대를 뺀다.
//
//   ASE-1  EXPIRED 초대(미래 근무일)는 보이지 않는다 (반례)
//   ASE-2  대조군: CONFIRMED → 확정, PENDING → 대기, CANCELED → 안 보임
//   ASE-3  유효한 INVITED 는 기존대로 보인다(문구 정책 미정 — 보존)
//   ASE-4  건수 배지도 만료 초대를 세지 않는다
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/widgets/dialogs/apply/apply_summary_section.dart';

DateTime _day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: offset));
}

ApplicationModel _app(String id, String status, {required String start, required String end, int dayOffset = 2}) => ApplicationModel(
      id: id, toId: 'to_$id', slotId: 'slot_$id', wdId: 'wd1', businessId: 'biz1', businessName: '골든패스 테스트 사업장',
      toTitle: '공고 $id', uid: 'u1', applicantName: '김근로', status: status, appliedAt: _day(-1),
      workDate: _day(dayOffset), selectedWorkType: 'QA 분류', startTime: start, endTime: end, wage: 12000, wageType: 'hourly',
    );

Future<void> _pump(WidgetTester tester, List<ApplicationModel> apps) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
    child: ApplySummarySection(myApplications: apps, currentToId: 'to_other'),
  ))));
  await tester.pump();
}

bool _row(String time) => find.textContaining('QA 분류  $time').evaluate().isNotEmpty;

void main() {
  setUpAll(() async => initializeDateFormatting('ko_KR', null));

  testWidgets('ASE-1 EXPIRED 초대는 내 지원 일정에 보이지 않는다', (tester) async {
    await _pump(tester, [_app('exp', AppStatus.expired, start: '14:00', end: '15:00')]);
    expect(_row('14:00 ~ 15:00'), isFalse, reason: '만료된 초대를 현재 대기 중인 지원처럼 보이지 않는다');
    expect(find.text('대기'), findsNothing);
  });

  testWidgets('ASE-2 대조군: 확정·대기·취소', (tester) async {
    await _pump(tester, [
      _app('conf', AppStatus.confirmed, start: '09:00', end: '10:00'),
      _app('pend', AppStatus.pending, start: '11:00', end: '12:00', dayOffset: 3),
      _app('canc', AppStatus.canceled, start: '13:00', end: '14:00'),
    ]);
    expect(_row('09:00 ~ 10:00'), isTrue);
    expect(_row('11:00 ~ 12:00'), isTrue);
    expect(_row('13:00 ~ 14:00'), isFalse);
    expect(find.text('확정'), findsOneWidget);
    expect(find.text('대기'), findsOneWidget);
  });

  testWidgets('ASE-3 유효한 INVITED 는 기존대로 보인다', (tester) async {
    await _pump(tester, [_app('inv', AppStatus.invited, start: '16:00', end: '17:00')]);
    expect(_row('16:00 ~ 17:00'), isTrue);
  });

  testWidgets('ASE-4 건수 배지가 만료 초대를 세지 않는다', (tester) async {
    await _pump(tester, [
      _app('exp', AppStatus.expired, start: '14:00', end: '15:00'),
      _app('conf', AppStatus.confirmed, start: '09:00', end: '10:00'),
    ]);
    expect(find.text('1건'), findsOneWidget);
    expect(find.text('2건'), findsNothing);
  });
}
