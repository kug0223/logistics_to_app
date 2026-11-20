// [.54] SA 약관 발행 → 동의 저장 연결 — 재동의 화면과 SA 약관 관리 화면의 경계.
//
//   근거(LOCAL, DEV 배포 원본 직접 실행): perf-20261028/c54/ap54.json
//     · 동의 writer(00072-nab)는 같은 판·같은 값 재전송도 다시 쓴다(이력 +1, 동의 시각 이동) — 화면이
//       "저장 실패" 로 말한 뒤 사용자가 다시 누르면 실제로 두 번 저장된다.
//     · 발행(00001-zuc)은 시행일을 받지 않고 지금 바로 시행한다(응답에 effectiveAtMs 없음).
//     · 같은 버전·같은 본문에 제목만 바꾸면 목록 제목만 바뀌고 사용자에게는 발행본 제목이 보인다.
import 'dart:io';

import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:ALfit/screens/legal/legal_consent_reads.dart';
import 'package:ALfit/screens/legal/legal_consent_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// [.54] 동의 목록·재동의 화면 글자가 낱말 단위(TextLayout)로 바뀌어 보이는 글자로 찾는다.
import 'support/visible_text.dart';

LegalTermsItem _item(String id, String title, bool required_) => LegalTermsItem(
      id: id,
      title: title,
      content: '$title 본문입니다.\n' * 3,
      isRequired: required_,
      version: 'b',
      revisionId: '${id}__b',
      order: 1,
    );

EffectiveLegalTerms _terms() => EffectiveLegalTerms(
      serverNow: DateTime.utc(2026, 11, 1),
      upcoming: const [],
      items: [_item('service_terms', '서비스 이용약관', true)],
    );

const _reconsent = LegalReadiness(
    status: LegalReadinessStatus.reconsentRequired, reconsentRequired: ['service_terms']);

Future<void> _agreeAndSubmit(WidgetTester t) async {
  await t.tap(find.descendant(
      of: find.ancestor(of: findVisibleTextContaining('서비스 이용약관'), matching: find.byType(Row)),
      matching: find.widgetWithText(TextButton, '보기')));
  await t.pumpAndSettle();
  await t.tap(find.widgetWithText(ElevatedButton, '동의하고 닫기'));
  await t.pumpAndSettle();
  await _submit(t);
}

Future<void> _submit(WidgetTester t) async {
  await t.tap(find.widgetWithText(ElevatedButton, '동의하고 계속하기'));
  await t.pump();
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

String _src(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  testWidgets('L54-1 저장은 성공했는데 상태 재확인만 실패하면 "저장 실패" 라고 말하지 않는다', (t) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    var readinessCalls = 0;
    final reads = LegalConsentReads(
      readiness: () async {
        readinessCalls++;
        if (readinessCalls > 1) throw Exception('network');
        return _reconsent;
      },
      terms: () async => _terms(),
      storedConsent: () async => <String, dynamic>{},
      recordConsent: (r) async {},
    );
    await t.pumpWidget(MaterialApp(home: LegalConsentScreen(reads: reads)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
    await _agreeAndSubmit(t);
    expect(findVisibleTextContaining('동의는 저장됐지만'), findsOneWidget);
    expect(findVisibleTextContaining('저장에 실패'), findsNothing);
  });

  testWidgets('L54-2 응답을 못 받았는데 서버에는 저장됐으면 다시 눌러도 같은 동의를 또 보내지 않는다', (t) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final sent = <Map<String, dynamic>>[];
    var storedReads = 0;
    final reads = LegalConsentReads(
      readiness: () async => _reconsent,
      terms: () async => _terms(),
      // 첫 읽기(진입)는 비어 있고, 실패 뒤 다시 읽으면 서버에 저장된 기록이 보인다.
      storedConsent: () async => storedReads++ == 0
          ? <String, dynamic>{}
          : {'service_terms': {'agreed': true, 'version': 'b', 'revisionId': 'service_terms__b'}},
      recordConsent: (r) async {
        sent.add(r);
        throw Exception('deadline-exceeded'); // 응답 유실
      },
    );
    await t.pumpWidget(MaterialApp(home: LegalConsentScreen(reads: reads)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
    await _agreeAndSubmit(t);
    expect(sent, hasLength(1));
    expect(findVisibleTextContaining('저장에 실패했을 수 있습니다'), findsOneWidget);
    await _submit(t);
    expect(sent, hasLength(1), reason: '서버에 이미 있는 동의를 다시 보내면 이력이 겹치고 동의 시각이 밀린다');
  });

  testWidgets('L54-5 옛 기록 확인(LEGACY) 화면은 항목에 "(변경됨)" 을 붙이지 않는다 — 약관이 바뀐 것이 아니다', (t) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final reads = LegalConsentReads(
      readiness: () async => const LegalReadiness(
          status: LegalReadinessStatus.legacyConsentUnknown, legacyUnknown: ['service_terms']),
      terms: () async => _terms(),
      storedConsent: () async => <String, dynamic>{},
      recordConsent: (r) async {},
    );
    await t.pumpWidget(MaterialApp(home: LegalConsentScreen(reads: reads)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
    expect(findVisibleTextContaining('약관 동의 정보를 다시 확인해 주세요'), findsOneWidget);
    expect(findVisibleTextContaining('(변경됨)'), findsNothing);
  });

  test('L54-3 SA 약관 관리 — 읽기 실패를 기본값으로 바꾸지 않고, 시행일을 받지 않은 서버에는 시행일 약속을 하지 않는다', () {
    final svc = _src('lib/services/legal_terms_service.dart');
    final scr = _src('lib/screens/super_admin/legal_terms_management_screen.dart');
    final edit = svc.substring(svc.indexOf('Future<LegalTerms> getTermsForEditing()'), svc.indexOf('static bool isTermsVersionStale'));
    expect(edit.contains('catch'), isFalse, reason: '읽기 실패가 기본값으로 바뀐다');
    expect(svc.contains("data['effectiveAtMs'] is int"), isTrue);
    expect(scr.contains("ToastHelper.showSuccess('발행했습니다. 시행일부터 적용됩니다');"), isFalse);
    expect(scr.contains('서버가 시행일을 받지 않아 지금부터 적용됩니다'), isTrue);
  });

  test('L54-4 SA 약관 관리 — 시행 예정 판을 보이고, 제목만 바꾼 같은 버전 발행·버전 재사용 거절을 말한다', () {
    final scr = _src('lib/screens/super_admin/legal_terms_management_screen.dart');
    expect(scr.contains('if (item.upcoming != null)'), isTrue);
    expect(scr.contains('if (widget.item.upcoming != null) ...['), isTrue);
    expect(scr.contains('제목을 바꾸려면 버전도 바꿔 새 판으로 발행해 주세요'), isTrue);
    expect(scr.contains('LegalTermsService.isVersionReused(e)'), isTrue);
    expect(scr.contains('up.effectiveAt?.toUtc().add(const Duration(hours: 9))'), isTrue,
        reason: '시행 예정일은 KST 날짜로 보인다(GMT 기기에서 하루 앞으로 보였다)');
  });
}
