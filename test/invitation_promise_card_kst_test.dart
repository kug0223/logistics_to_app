// [E1-INVITE-DETAIL-KST] 근로자 초대 상세(InvitationPromiseCard) — 근무일·응답 기한.
//
// 근거(설치 앱 1.0.21+25, 기기 TZ=GMT, DEV E1 초대 C28L/Vn5j/ZloV):
//   · 원장 workDate = 2026-10-19(월) KST 자정인데 상세는 **10월 18일(일)**
//     (`app.workDate` 의 기기 성분을 그대로 썼다)
//   · 목록 카드에 있는 만료(~10.18 22:46)가 상세에는 없었다
//
// 픽스처는 저장 원장과 같은 절대 시각을 **기기 local** 로 준다
// (`Timestamp.toDate()` 와 같은 모양 — utc 플래그면 KST 실행도 GMT 처럼 보인다).
//
// KST 기본 환경과 `TZ=UTC0` 양쪽에서 통과해야 한다:
//   flutter test test/invitation_promise_card_kst_test.dart
//   TZ=UTC0 flutter test test/invitation_promise_card_kst_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/ui/invitation_projection.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/user/invitation_promise_card.dart';

/// KST 벽시계 → 절대 시각(기기 local).
DateTime _kst(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h - 9, min).toLocal();

ApplicationModel _invite({
  required DateTime workDate,
  String start = '14:00',
  String end = '15:00',
  DateTime? invitedAt,
  DateTime? inviteExpiresAt,
  DateTime? inviteAcceptDeadline,
  String status = 'INVITED',
}) =>
    ApplicationModel(
      id: 'C28L_Vn5j_ZloV_7oZZ',
      businessId: 'b1',
      businessName: '골든패스 테스트 사업장',
      toTitle: 'QA-N E2 consent 1019 1400-1500',
      workDate: workDate,
      startTime: start,
      endTime: end,
      uid: '7oZZ',
      selectedWorkType: 'QA 분류',
      wage: 12000,
      wageType: 'hourly',
      breakMinutes: 0,
      status: status,
      appliedAt: invitedAt ?? workDate,
      invitedAt: invitedAt,
      inviteExpiresAt: inviteExpiresAt,
      inviteAcceptDeadline: inviteAcceptDeadline,
    );

Future<List<String>> _render(WidgetTester t, ApplicationModel app,
    {InvitationAcceptability acceptability =
        InvitationAcceptability.acceptable}) async {
  t.view.physicalSize = const Size(390, 1200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: InvitationPromiseCard(
        projection: InvitationProjection(
          application: app,
          contextState: InvitationContextState.loaded,
          acceptability: acceptability,
          drift: const InvitationDrift(),
        ),
      ),
    ),
  ));
  await t.pump();
  expect(t.takeException(), isNull);
  return t
      .widgetList<Text>(find.byType(Text))
      // [DU475 r2 지원 패치] 응답 기한은 낱말 조판(보이지 않는 결합 문자)으로 그린다 — 원문 data 를 보이는 글자로 맞춰 비교한다.
      .map((x) => TextLayout.plain(x.data ?? ''))
      .toList();
}

void main() {
  final tz = 'UTC+${DateTime(2026, 10, 17).timeZoneOffset.inHours}';

  testWidgets('IC-1 [$tz] E1 원장 — 근무일 10/19(월), 10/18 22:46까지 응답', (t) async {
    final app = _invite(
      workDate: _kst(2026, 10, 19),
      invitedAt: _kst(2026, 10, 17, 22, 46),
      inviteExpiresAt: _kst(2026, 10, 18, 22, 46),
    );
    final texts = await _render(t, app);
    expect(texts, contains('10월 19일(월)'));
    expect(texts, isNot(contains('10월 18일(일)')));
    expect(texts, contains('14:00 ~ 15:00'));
    expect(texts, contains('10월 18일 22:46까지 응답'));

    // 목록 카드(`~MM.dd HH:mm 만료`)와 같은 시각을 가리킨다 — 한 getter.
    expect(FormatHelper.formatKstMonthDayTime(app.effectiveInviteDeadline!),
        '10.18 22:46');
  });

  testWidgets('IC-2 [$tz] 월말 — 10/31(토) 근무, 10/30 23:30까지 응답', (t) async {
    final texts = await _render(
        t,
        _invite(
          workDate: _kst(2026, 10, 31),
          start: '09:00',
          end: '18:00',
          inviteExpiresAt: _kst(2026, 10, 30, 23, 30),
        ));
    expect(texts, contains('10월 31일(토)'));
    expect(texts, contains('10월 30일 23:30까지 응답'));
  });

  testWidgets('IC-3 [$tz] 연말 — 2027-01-01(금) 근무, 12/31 23:59까지 응답', (t) async {
    final texts = await _render(
        t,
        _invite(
          workDate: _kst(2027, 1, 1),
          start: '09:00',
          end: '18:00',
          inviteExpiresAt: _kst(2026, 12, 31, 23, 59),
        ));
    expect(texts, contains('1월 1일(금)'));
    expect(texts, contains('12월 31일 23:59까지 응답'));
  });

  testWidgets('IC-4 [$tz] 만료 필드 없음 — 24시간 규칙으로 시각을 만들지 않는다', (t) async {
    final texts = await _render(
        t,
        _invite(
          workDate: _kst(2026, 10, 19),
          invitedAt: _kst(2026, 10, 17, 22, 46), // +24h 로 지어낼 재료는 있다
        ));
    expect(texts, contains('10월 19일(월)'));
    expect(texts.where((s) => s.contains('까지 응답')), isEmpty);
    expect(texts.where((s) => s.contains('22:46')), isEmpty);
  });

  testWidgets('IC-5 [$tz] 서버 마감이 더 이르면 그 시각 — 목록과 같은 값', (t) async {
    final app = _invite(
      workDate: _kst(2026, 10, 19),
      inviteExpiresAt: _kst(2026, 10, 18, 22, 46),
      inviteAcceptDeadline: DateTime.utc(2026, 10, 18, 12, 0), // KST 21:00
    );
    final texts = await _render(t, app);
    expect(texts, contains('10월 18일 21:00까지 응답'));
    expect(FormatHelper.formatKstMonthDayTime(app.effectiveInviteDeadline!),
        '10.18 21:00');
  });

  testWidgets('IC-6 [$tz] 이미 처리된 초대에는 응답 기한을 말하지 않는다', (t) async {
    final texts = await _render(
        t,
        _invite(
          workDate: _kst(2026, 10, 19),
          inviteExpiresAt: _kst(2026, 10, 18, 22, 46),
          status: 'CONFIRMED',
        ),
        acceptability: InvitationAcceptability.alreadyResolved);
    expect(texts, contains('10월 19일(월)'));
    expect(texts.where((s) => s.contains('까지 응답')), isEmpty);
  });
}
