// [.55] 시행일 경계 — 홈 약관 카드가 서버 판정을 다시 읽는 계기, 지원 거절 문구, SA 발행 전·후 안내.
//
//   근거(LOCAL, DEV 원본 + 후보 T): perf-20261028/c55/ap55.json
//     · 시행 경계를 넘으면 지원(00105)은 재동의를 요구하는데, 홈 카드는 진입할 때 읽은 "정상" 을 계속 들고 있었다.
//     · 지원 거절 문구가 'LEGAL_RECONSENT_REQUIRED …' 내부 코드째 사용자에게 보였다.
//     · 앱은 서버가 시행일 예약을 처리하는 판인지 발행 전에는 알 수 없다 — 예약을 보장하는 문구를 쓰지 않는다.
import 'dart:io';

import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/widgets/common/legal_task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/visible_text.dart';

String _src(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

const _current = LegalReadiness(status: LegalReadinessStatus.current);
const _reconsent = LegalReadiness(
    status: LegalReadinessStatus.reconsentRequired, reconsentRequired: ['service_terms']);

Future<int Function()> _pumpCard(WidgetTester t, List<LegalReadiness> answers) async {
  var calls = 0;
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: LegalTaskCard(loadReadiness: () async => answers[(calls++).clamp(0, answers.length - 1)]),
    ),
  ));
  await t.pump();
  return () => calls;
}

void main() {
  testWidgets('E55-1 지원이 "새 약관 미동의" 로 거절되면 홈 카드가 서버 판정을 다시 읽어 나타난다', (t) async {
    final calls = await _pumpCard(t, [_current, _reconsent]);
    expect(findVisibleTextContaining('이용약관이 변경되었습니다'), findsNothing);
    LegalReadinessSignal.bump();
    await t.pump();
    await t.pump();
    expect(calls(), 2);
    expect(findVisibleTextContaining('이용약관이 변경되었습니다'), findsOneWidget);
  });

  testWidgets('E55-2 앱으로 돌아오면(resume) 카드가 서버 판정을 다시 읽는다', (t) async {
    final calls = await _pumpCard(t, [_current, _reconsent]);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    await t.pump();
    expect(calls(), greaterThanOrEqualTo(2));
    expect(findVisibleTextContaining('이용약관이 변경되었습니다'), findsOneWidget);
  });

  test('E55-3 지원 거절 문구에 내부 코드를 보이지 않고 카드에 다시 읽기를 알린다', () {
    final s = _src('lib/services/firestore/application_firestore.dart');
    final i = s.indexOf("if (msg.startsWith('LEGAL_RECONSENT_REQUIRED'))");
    expect(i, greaterThan(0));
    final blk = s.substring(i, s.indexOf('}', i));
    expect(blk.contains('LegalReadinessSignal.bump();'), isTrue);
    expect(blk.contains("ApplyResult.failed('변경된 약관에 동의한 뒤 지원할 수 있어요."), isTrue);
  });

  test('E55-4 SA 발행 — 본 예정 판을 보내고, 누르기 전에 예약을 보장하지 않는다고 말한다', () {
    final svc = _src('lib/services/legal_terms_service.dart');
    final scr = _src('lib/screens/super_admin/legal_terms_management_screen.dart');
    expect(svc.contains("'expectedUpcomingVersion': item.upcoming?.version,"), isTrue);
    expect(scr.contains('서버가 시행일 예약을 처리하지 못하면 발행 즉시 적용될 수 있습니다'), isTrue);
    expect(scr.contains("0시(한국 시간)부터 적용됩니다"), isTrue);
    expect(scr.contains('LegalTermsService.isUpcomingStale(e)'), isTrue);
    expect(scr.contains('LegalTermsService.isVersionMeaningChanged(e)'), isTrue);
    expect(scr.contains("발행 결과를 확인하지 못했습니다"), isTrue, reason: '응답 유실을 실패로 단정하거나 재전송하지 않는다');
  });
}
