import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/utils/posting_partial_revoke.dart';

import 'support/visible_text.dart';

/// [F295-CLOSE-01 · impl_41] 종료한 날짜 '다시 정리'(cleanupOnly) 재진입 — 서버 계약 server_295_impl §8 + 조정자 확정(index 8f2e9b6b).
///   C1  resumable 두 갈래: true = '자동으로 이어서 정리' + 다시 정리 유지 · false/모름 = '같은 요청을 다시 보내 주세요'
///   C2  다시 보낼 때는 cleanupOnly(최초 종료 기록 보존) · 다시 묻는 문구도 매번 마지막 거절로 고른다
///   C3  성공 응답 notClosedSlotIds(그 사이 다시 열린 날짜) 해석
///   C4  재진입 진입점(메뉴 · 선택 창 closedOnly · 서비스 cleanupOnly 전송) · 서버 계약 원문 핀
///   C5  안내 확인창 320·1.3 / 320·2.0 / 392·2.0
void main() {
  FirebaseFunctionsException inc({bool? resumable, List<String> failed = const ['s2']}) => FirebaseFunctionsException(
        code: 'aborted',
        message: '일부 슬롯 정리를 마치지 못했습니다. 다시 시도해 주세요.',
        details: <String, Object?>{
          'code': 'CLOSE_SLOTS_INCOMPLETE', 'mode': 'cleanupOnly', 'slotsClosed': 0, 'applicationsRejected': 3,
          'failedSlotIds': failed, 'toStatusFailed': false,
          if (resumable != null) 'resumable': resumable,
        },
      );

  test('C1 resumable 두 갈래 문구', () {
    expect(postingCloseResumable(inc(resumable: true)), isTrue);
    expect(postingCloseResumable(inc(resumable: false)), isFalse);
    expect(postingCloseResumable(inc()), isNull, reason: '구서버 — 모름');
    expect(postingCloseResumable(FirebaseFunctionsException(code: 'aborted', message: 'x', details: {'resumable': 'true'})), isNull,
        reason: '문자열은 bool 이 아니다');
    expect(postingCloseIncompleteMessageFor(inc(resumable: true)), postingCloseAutoResumeMessage);
    expect(postingCloseIncompleteMessageFor(inc(resumable: false)), postingCloseIncompleteMessage);
    expect(postingCloseIncompleteMessageFor(inc()), postingCloseIncompleteMessage, reason: '모르면 다시 보내라고 안내');
    expect(postingCloseAutoResumeMessage.contains('자동으로 이어서'), isTrue);
    expect(postingCloseAutoResumeMessage.contains('다시 정리'), isTrue, reason: '다시 정리 버튼은 유지');
    expect(postingCloseIncompleteMessage.contains('같은 요청을 다시 보내 주세요'), isTrue);
    for (final m in [postingCloseAutoResumeMessage, postingCloseIncompleteMessage]) {
      expect(RegExp(r'[A-Za-z_]{4,}').hasMatch(m), isFalse, reason: m);
    }
  });

  test('C2 다시 시도 고리 — 마지막 거절을 묻는 쪽에 넘긴다(두 번째 거절이 resumable:true 로 바뀌면 문구도 바뀐다)', () async {
    final asked = <String>[];
    var n = 0;
    final (o, _) = await runPostingCloseRetry(
      initialError: inc(resumable: false),
      slotIds: ['s1', 's2'],
      ask: (err) async { asked.add(postingCloseIncompleteMessageFor(err)); return true; },
      send: (ids) async { n++; if (n == 1) throw inc(resumable: true, failed: ['s2']); },
      refresh: () {},
      isMounted: () => true,
    );
    expect(o, PostingCloseRetryOutcome.completed);
    expect(asked, [postingCloseIncompleteMessage, postingCloseAutoResumeMessage]);
    expect(n, 2);
  });

  test('C3 notClosedSlotIds 해석', () {
    expect(postingNotClosedSlotIds({'success': true, 'mode': 'cleanupOnly', 'notClosedSlotIds': ['s3', 's3', '', 4]}), ['s3']);
    expect(postingNotClosedSlotIds({'success': true, 'canceledCount': 2}), isEmpty, reason: '구서버');
    expect(postingNotClosedSlotIds({'notClosedSlotIds': 's3'}), isEmpty);
  });

  test('C4 진입점 · 전송 · 서버 계약 원문 핀', () {
    final svc = File('lib/services/firestore/to_firestore.dart').readAsStringSync();
    final b = svc.substring(svc.indexOf('Future<Map<String, dynamic>> batchCloseSlots('));
    expect(b.contains('bool cleanupOnly = false,'), isTrue);
    expect(b.contains("if (cleanupOnly) 'cleanupOnly': true,"), isTrue, reason: '일반 닫기는 키를 보내지 않는다(구서버 호환)');
    final card = File('lib/widgets/admin/cards/admin_to_group_card.dart').readAsStringSync();
    expect(card.contains("label: '종료한 날짜 다시 정리',"), isTrue);
    expect(card.contains("_handleSingleTOMenuAction(context, 'batchCleanup')"), isTrue);
    final cleanup = card.substring(card.indexOf("case 'batchCleanup':"), card.indexOf("case 'batchReopen':"));
    expect(cleanup.contains('closedOnly: true,'), isTrue);
    expect(cleanup.contains('cleanupOnly: true,'), isTrue);
    expect(cleanup.contains('postingNotClosedSlotIds(res)'), isTrue);
    expect(cleanup.contains('await _offerCloseRetry('), isTrue, reason: '재진입에서 또 미완료면 같은 다시 정리 고리');
    final retry = card.substring(card.indexOf('Future<void> _offerCloseRetry('), card.indexOf('@override\n  void didUpdateWidget'));
    expect(retry.contains('cleanupOnly: true,'), isTrue, reason: '다시 보낼 때 최초 종료 기록을 덮지 않는다');
    expect(retry.contains('message: postingCloseIncompleteMessageFor(err),'), isTrue);
    final dlg = File('lib/screens/business_admin/dialogs/slot_batch_select_dialog.dart').readAsStringSync();
    expect(dlg.contains('if (widget.closedOnly) return slots.where((s) => s.isClosed).toList();'), isTrue);
    final idx = File('functions/src/index.ts').readAsStringSync();
    final cs = idx.substring(idx.indexOf('export const callableCloseSlots'), idx.indexOf('export const callableReopenSlots'));
    expect(cs.contains('cleanupOnly'), isTrue, reason: '서버가 cleanupOnly 를 안다');
    expect(cs.contains('notClosedSlotIds'), isTrue);
    expect(cs.contains('resumable'), isTrue);
  });

  for (final (w, s) in [(320.0, 1.3), (320.0, 2.0), (392.0, 2.0)]) {
    for (final resumable in [true, false]) {
      testWidgets('C5 $w·$s resumable=$resumable 안내 확인창 — 예외 0 · 다시 정리/나중에', (t) async {
        t.view.physicalSize = Size(w, 800);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        await t.pumpWidget(MaterialApp(
          home: Builder(
            builder: (ctx) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(s)),
              child: Scaffold(
                body: Center(
                  child: Builder(
                    builder: (c2) => TextButton(
                      onPressed: () => DialogHelper.showConfirm(c2,
                          title: postingCloseIncompleteTitle,
                          message: postingCloseIncompleteMessageFor(inc(resumable: resumable)),
                          confirmText: '다시 정리',
                          cancelText: '나중에'),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(findVisibleTextContaining(resumable ? '자동으로 이어서' : '같은 요청을 다시 보내 주세요'), findsOneWidget);
        expect(findVisibleText('다시 정리'), findsOneWidget);
        expect(findVisibleText('나중에'), findsOneWidget);
      });
    }
  }
}
