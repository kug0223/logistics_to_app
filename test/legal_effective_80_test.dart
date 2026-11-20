// [.80] 약관 T·RC DEV 적용 뒤 화면 연결 — 발행 서버(callablePublishLegalRevision 00002-sok)가 시행일 예약을 처리한다.
//
//   근거: perf-20261028/c80/ap80.json T1 · Pixel5 LOCAL 여정(c80/shots)
//     · SA 약관 관리 띠가 "약관 수정 시 … 즉시 반영됩니다" 라고 말해, 서버와 반대되는 안내를 했다.
//       사전 확인 창의 유보 문구("처리하지 못하면 즉시 적용될 수 있습니다", .55)는 그대로 둔다 — 모순이 아니다.
//     · 동의 화면의 예정 안내가 KST 11/12 0시 시행을 GMT 기기에서 "2026년 11월 11일부터" 라고 그렸다(SA 목록은 11.12).
import 'dart:io';

import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:ALfit/screens/legal/legal_consent_reads.dart';
import 'package:ALfit/screens/legal/legal_consent_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/visible_text.dart';

String _src(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  const screen = 'lib/screens/super_admin/legal_terms_management_screen.dart';

  test('E80-1 안내 띠가 새 버전을 즉시 반영한다고 말하지 않고 시행일 기준을 말한다', () {
    final s = _src(screen);
    expect(s.contains('즉시 반영됩니다'), isFalse);
    expect(s.contains('새 버전은 정한 시행일(한국 시간 0시)부터 적용되고'), isTrue);
    expect(s.contains('비활성화하면 회원가입 화면에서 숨겨집니다.'), isTrue);
  });

  test('E80-2 사전 확인 창의 유보 문구(.55)는 남아 있다', () {
    expect(_src(screen).contains('즉시 적용될 수 있습니다'), isTrue);
  });

  testWidgets('E80-3 예정 안내 날짜는 KST 날짜다 — KST 11/12 0시(= UTC 11/11 15:00)는 11월 12일', (t) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    // UTC 로 만든 instant — 호스트 시간대와 무관하게 GMT 기기와 같은 필드 값을 갖는다.
    final upcoming = [
      UpcomingLegalItem(itemId: 'service_terms', version: '2026-11-12', effectiveAt: DateTime.utc(2026, 11, 11, 15)),
    ];
    final reads = LegalConsentReads(
      readiness: () async => LegalReadiness(
          status: LegalReadinessStatus.legacyConsentUnknown, legacyUnknown: const ['service_terms'], upcoming: upcoming),
      terms: () async => EffectiveLegalTerms(
            serverNow: DateTime.utc(2026, 11, 4),
            upcoming: const [],
            items: const [
              LegalTermsItem(id: 'service_terms', title: '서비스 이용약관', content: '본문', isRequired: true,
                  version: '1.0', revisionId: 'service_terms__1.0', order: 1),
            ],
          ),
      storedConsent: () async => <String, dynamic>{},
      recordConsent: (r) async {},
    );
    await t.pumpWidget(MaterialApp(home: LegalConsentScreen(reads: reads)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
    expect(findVisibleTextContaining('2026년 11월 12일부터 적용됩니다'), findsOneWidget);
    expect(findVisibleTextContaining('11월 11일'), findsNothing);
  });
}
