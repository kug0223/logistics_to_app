import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/services/payroll_payment_service.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/posting_partial_revoke.dart';
import 'package:ALfit/utils/toast_helper.dart';

import 'support/visible_text.dart';

/// [impl_35 · 판정294 서버 수리의 클라 영향]
///
///   S  공고·날짜 정리 미완료(aborted · CLOSE_SLOTS_INCOMPLETE / CLEANUP_INCOMPLETE)와
///      확인 뒤 관계(RELATION_AFTER_CHECK)를 일반 실패와 가르고, 목록을 새로 읽고, 다시 시도를 안내한다.
///   M  관리자 직접 중간정산 응답(netAmount = 실수령 합 · requestedAmount · transferredAttendanceIds · excluded)을
///      서버가 말한 대로 알린다 — 구서버(netAmount = 세전 합)는 금액을 단정하지 않는다.
///   응답 모양은 서버 원문(functions/src/index.ts dbed3203)의 HttpsError details / return 객체 그대로다.
void main() {
  FirebaseFunctionsException fx(String code, String msg, [Object? details]) =>
      FirebaseFunctionsException(code: code, message: msg, details: details);

  // 서버 원문: callableCloseSlots 끝 · srvPostingCleanupAll 끝 · DeleteTO/DeleteSlots 마지막 거래
  final closeIncomplete = fx('aborted', '일부 슬롯 정리를 마치지 못했습니다. 다시 시도해 주세요.', <String, Object?>{
    'code': 'CLOSE_SLOTS_INCOMPLETE', 'slotsClosed': 3, 'applicationsRejected': 7,
    'failedSlotIds': ['s2'], 'toStatusFailed': false,
  });
  final closeToStatusOnly = fx('aborted', '일부 슬롯 정리를 마치지 못했습니다. 다시 시도해 주세요.', <String, Object?>{
    'code': 'CLOSE_SLOTS_INCOMPLETE', 'slotsClosed': 3, 'applicationsRejected': 0,
    'failedSlotIds': <String>[], 'toStatusFailed': true,
  });
  final cleanupIncomplete = fx('aborted', '일부 지원서 정리를 마치지 못했습니다. 잠시 뒤 다시 시도해 주세요.', <String, Object?>{
    'code': 'CLEANUP_INCOMPLETE', 'lateApplicationsCleaned': 2, 'contractsVoided': 1,
    'unresolvedCount': 1, 'unresolved': [<String, Object?>{'id': 'a9', 'reason': 'STATE_CHANGED'}],
  });
  final relationAfter = fx('failed-precondition',
      '선택한 날짜에 지원 또는 근무 기록이 있어 삭제할 수 없습니다. 해당 날짜의 모집을 중단하려면 날짜 종료를 이용해주세요.',
      <String, Object?>{'code': 'RELATION_AFTER_CHECK'});
  final revoked = fx('permission-denied', 'TO 관리 권한이 없습니다.',
      <String, Object?>{'code': 'PERMISSION_REVOKED_MIDWAY', 'slotsClosed': 1});

  group('S 공고 정리 미완료 판정', () {
    test('S1 aborted + 두 코드만 미완료다(문구가 아니라 code)', () {
      expect(isPostingIncomplete(closeIncomplete), isTrue);
      expect(isPostingIncomplete(closeToStatusOnly), isTrue);
      expect(isPostingIncomplete(cleanupIncomplete), isTrue);
      expect(isPostingIncomplete(fx('aborted', '경합')), isFalse, reason: '코드 없는 aborted(거래 경합)는 일반 실패');
      expect(isPostingIncomplete(fx('aborted', 'x', {'code': 'OTHER'})), isFalse);
      expect(isPostingIncomplete(fx('failed-precondition', 'x', {'code': 'CLEANUP_INCOMPLETE'})), isFalse);
      expect(isPostingIncomplete(revoked), isFalse);
      expect(isPostingPartialRevoke(revoked), isTrue, reason: '기존 판정 불변');
      expect(isPostingPartialRevoke(cleanupIncomplete), isFalse);
      expect(isPostingIncomplete(Exception('x')), isFalse);
    });

    test('S2 RELATION_AFTER_CHECK 는 failed-precondition + code 일 때만', () {
      expect(isPostingRelationAfterCheck(relationAfter), isTrue);
      expect(isPostingRelationAfterCheck(fx('failed-precondition', relationAfter.message!)), isFalse,
          reason: '사전 관계 거절(details 없음)은 정리 반영이 없다 — 기존 경로');
      expect(isPostingRelationAfterCheck(fx('aborted', 'x', {'code': 'RELATION_AFTER_CHECK'})), isFalse);
      expect(isPostingRelationAfterCheck(Exception('x')), isFalse);
    });

    test('S3 다시 보낼 날짜 = 서버가 말한 실패 날짜(처음 요청 안) · 없으면 처음 요청 그대로', () {
      expect(postingIncompleteRetrySlotIds(closeIncomplete, fallback: ['s1', 's2', 's3']), ['s2']);
      expect(postingIncompleteRetrySlotIds(closeToStatusOnly, fallback: ['s1', 's2']), ['s1', 's2'],
          reason: '공고 상태 갱신만 남음 — 같은 요청 재전송');
      expect(postingIncompleteRetrySlotIds(
              fx('aborted', 'x', {'code': 'CLOSE_SLOTS_INCOMPLETE', 'failedSlotIds': ['zz', 3, '', 's1', 's1']}),
              fallback: ['s1', 's2']),
          ['s1'], reason: '처음 요청 밖·비문자·빈 값·중복은 버린다');
      expect(postingIncompleteRetrySlotIds(Exception('x'), fallback: ['s1']), ['s1']);
    });
  });

  group('S4 날짜 종료 다시 시도 고리(가짜 callable)', () {
    Future<(PostingCloseRetryOutcome, Object?, List<List<String>>, int, int)> run(
      List<Object?> sendResults, {List<bool>? answers, bool Function()? mounted}) async {
      final sent = <List<String>>[];
      var asked = 0;
      var refreshed = 0;
      final ans = answers ?? List.filled(10, true);
      final (o, err) = await runPostingCloseRetry(
        initialError: closeIncomplete,
        slotIds: ['s1', 's2', 's3'],
        ask: (_) async => ans[asked++],
        send: (ids) async {
          sent.add(ids);
          final r = sendResults[sent.length - 1];
          if (r != null) throw r;
        },
        refresh: () => refreshed++,
        isMounted: mounted ?? () => true,
      );
      return (o, err, sent, asked, refreshed);
    }

    test('S4a 나중에 → 보내지 않음', () async {
      final (o, _, sent, asked, refreshed) = await run([], answers: [false]);
      expect(o, PostingCloseRetryOutcome.declined);
      expect(sent, isEmpty);
      expect((asked, refreshed), (1, 0));
    });

    test('S4b 다시 시도 → 또 미완료 → 다시 묻고 → 성공. 매 전송 뒤 목록 갱신', () async {
      final second = fx('aborted', 'x', {'code': 'CLOSE_SLOTS_INCOMPLETE', 'failedSlotIds': <String>[], 'toStatusFailed': true});
      final (o, _, sent, asked, refreshed) = await run([second, null]);
      expect(o, PostingCloseRetryOutcome.completed);
      expect(sent, [['s2'], ['s1', 's2', 's3']]);
      expect((asked, refreshed), (2, 2));
    });

    test('S4c 다시 보낸 요청이 권한 회수로 일부만 → revoked · 일반 실패 → failed(오류 전달)', () async {
      final (o1, _, _, _, r1) = await run([revoked]);
      expect(o1, PostingCloseRetryOutcome.revoked);
      expect(r1, 1);
      final boom = fx('internal', '내부 오류');
      final (o2, e2, _, _, _) = await run([boom]);
      expect(o2, PostingCloseRetryOutcome.failed);
      expect(identical(e2, boom), isTrue);
    });

    test('S4d 묻는 사이 화면이 사라지면 보내지 않는다', () async {
      var alive = true;
      final sent = <List<String>>[];
      final (o, _) = await runPostingCloseRetry(
        initialError: closeIncomplete,
        slotIds: ['s1'],
        ask: (_) async { alive = false; return true; },
        send: (ids) async => sent.add(ids),
        refresh: () {},
        isMounted: () => alive,
      );
      expect(o, PostingCloseRetryOutcome.declined);
      expect(sent, isEmpty);
    });
  });

  group('S5 문구·호출부', () {
    test('S5a 안내 문구 — 개발 용어 0 · 다시 할 행동을 말한다 · 완료를 단정하지 않는다', () {
      for (final m in [postingDeleteIncompleteMessage, postingCloseIncompleteMessage, postingCloseIncompleteTitle]) {
        expect(RegExp(r'[A-Z_]{4,}').hasMatch(m), isFalse, reason: m);
      }
      expect(postingDeleteIncompleteMessage.contains('다시 삭제'), isTrue);
      // [impl_41] 버튼 이름이 '다시 정리'로 바뀌었다(cleanupOnly 재전송) — 같은 요청을 다시 보내라는 안내.
      expect(postingCloseIncompleteMessage.contains('다시 정리'), isTrue);
      expect(postingDeleteIncompleteMessage.contains('완료'), isFalse);
    });

    test('S5b deleteTO — 미완료·확인 뒤 관계는 일반 실패보다 먼저, 목록 갱신(true)', () {
      final svc = File('lib/services/firestore/to_firestore.dart').readAsStringSync();
      final body = svc.substring(svc.indexOf('Future<bool> deleteTO('));
      final generic = body.indexOf("'공고 삭제에 실패했습니다.';");
      final inc = body.indexOf('if (isPostingIncomplete(e)) {');
      final rel = body.indexOf('if (isPostingRelationAfterCheck(e)) {');
      expect(inc > 0 && rel > inc && generic > rel, isTrue);
      expect(RegExp(r'if \(isPostingIncomplete\(e\)\) \{\s*clearCache\(toId: toId\);\s*ToastHelper\.showWarning\(postingDeleteIncompleteMessage\);\s*return true;')
          .hasMatch(body), isTrue);
      expect(RegExp(r'if \(isPostingRelationAfterCheck\(e\)\) \{\s*clearCache\(toId: toId\);[\s\S]{0,260}?return true;')
          .hasMatch(body), isTrue);
    });

    test('S5c 카드 — 날짜 종료 미완료는 갱신 + 다시 시도 제안 · 날짜 삭제는 미완료/확인 뒤 관계 모두 갱신', () {
      final card = File('lib/widgets/admin/cards/admin_to_group_card.dart').readAsStringSync();
      expect(RegExp(r'else if \(mounted && isPostingIncomplete\(e\)\) \{[^}]*_refreshAfterClose\(masterTO\.id\);\s*await _offerCloseRetry\(')
          .hasMatch(card), isTrue);
      expect(RegExp(r'else if \(mounted && isPostingIncomplete\(e\)\) \{[^}]*widget\.onChanged\(\);\s*ToastHelper\.showWarning\(postingDeleteIncompleteMessage\);')
          .hasMatch(card), isTrue);
      expect(RegExp(r'else if \(mounted && isPostingRelationAfterCheck\(e\)\) \{[^}]*widget\.onChanged\(\);')
          .hasMatch(card), isTrue);
      expect(card.contains('runPostingCloseRetry('), isTrue);
    });
  });

  group('S6 다시 시도 확인창 — 좁은 폭·큰 글자', () {
    for (final (w, s) in [(320.0, 1.3), (320.0, 2.0), (392.0, 2.0)]) {
      testWidgets('S6 $w·$s 제목·본문·두 버튼이 예외 없이 보인다', (t) async {
        t.view.physicalSize = Size(w, 800);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        bool? got;
        await t.pumpWidget(MaterialApp(
          home: Builder(
            builder: (ctx) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(s)),
              child: Scaffold(
                body: Center(
                  child: Builder(
                    builder: (c2) => TextButton(
                      onPressed: () async {
                        got = await DialogHelper.showConfirm(c2,
                            title: postingCloseIncompleteTitle,
                            message: postingCloseIncompleteMessage,
                            confirmText: '다시 시도',
                            cancelText: '나중에',
                            icon: Icons.warning_amber_rounded);
                      },
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
        expect(findVisibleText(postingCloseIncompleteTitle), findsOneWidget);
        expect(findVisibleTextContaining('남은 정리를 마치지 못했어요'), findsOneWidget);
        expect(findVisibleText('다시 시도'), findsOneWidget);
        expect(findVisibleText('나중에'), findsOneWidget);
        await t.tap(findVisibleText('다시 시도'));
        await t.pumpAndSettle();
        expect(got, isTrue);
      });
    }
  });

  group('M 관리자 직접 중간정산 응답', () {
    test('M1 새 서버 · 제외 0 → 실제 처리 건수·실수령 합(세전 아님)', () {
      final r = DirectSettlementResult.fromResponse(<String, Object?>{
        'success': true, 'settlementId': 'st1', 'netAmount': 180000, 'requestedAmount': 200000,
        'transferredAttendanceIds': ['a1', 'a2'], 'excluded': <String, Object?>{},
      }, requestedCount: 2);
      expect(r.hasServerBreakdown, isTrue);
      expect(r.hasExclusions, isFalse);
      expect((r.netAmount, r.requestedAmount), (180000, 200000));
      expect(r.toastMessage(), '중간정산 2건을 처리했어요 · 실수령 180,000원');
      expect(r.toastMessage().contains('200,000'), isFalse);
    });

    test('M2 일부 제외 → 처리 건수 + 제외 건수·사유(정해진 순서 · 모르는 코드는 기타)', () {
      final r = DirectSettlementResult.fromResponse(<String, Object?>{
        'netAmount': 90000, 'requestedAmount': 100000, 'transferredAttendanceIds': ['a1'],
        'excluded': <String, Object?>{
          'a5': 'SETTLEMENT_LOCKED', 'a3': 'ALREADY_TRANSFERRED', 'a4': 'ALREADY_TRANSFERRED', 'a6': 'NEW_CODE',
          'a7': 'NON_PAYABLE',
        },
      }, requestedCount: 6);
      expect(r.hasExclusions, isTrue);
      expect(r.excludedSummary(), '이미 이체됨 2 · 정산 진행 중 1 · 지급할 금액 없음 1 · 기타 1');
      expect(r.toastMessage(),
          '중간정산 1건을 처리했어요 · 실수령 90,000원\n5건은 제외됐어요(이미 이체됨 2 · 정산 진행 중 1 · 지급할 금액 없음 1 · 기타 1)');
      expect(RegExp(r'[A-Z_]{4,}').hasMatch(r.toastMessage()), isFalse);
    });

    test('M3 구서버(새 필드 0) — netAmount 는 세전 합이라 실수령으로 보이지 않는다(예전 문구)', () {
      final r = DirectSettlementResult.fromResponse(
          <String, Object?>{'success': true, 'settlementId': 'st1', 'netAmount': 200000}, requestedCount: 3);
      expect(r.hasServerBreakdown, isFalse);
      expect(r.netAmount, isNull);
      expect(r.hasExclusions, isFalse, reason: '제외 0건으로 단정하지 않는다 — 모름');
      expect(r.toastMessage(), '중간정산이 처리되었습니다');
    });

    test('M4 모양이 틀린 응답 → unknown(합성 0) · 금액만 틀리면 금액 없이', () {
      for (final bad in <Object?>[
        null, 'x', <String, Object?>{'transferredAttendanceIds': [1, 2], 'netAmount': 5},
        <String, Object?>{'transferredAttendanceIds': 'a1'},
      ]) {
        final r = DirectSettlementResult.fromResponse(bad, requestedCount: 1);
        expect(r.hasServerBreakdown, isFalse, reason: '$bad');
        expect(r.toastMessage(), '중간정산이 처리되었습니다');
      }
      final r = DirectSettlementResult.fromResponse(<String, Object?>{
        'transferredAttendanceIds': ['a1'], 'netAmount': '90000', 'excluded': ['a2'],
      }, requestedCount: 2);
      expect(r.hasServerBreakdown, isTrue);
      expect(r.netAmount, isNull);
      expect(r.excluded, isEmpty);
      expect(r.toastMessage(), '중간정산 1건을 처리했어요');
    });

    test('M5 화면 — 결과 안내는 서버 응답으로 · 제외 있으면 경고 · 실패에 예외 문자열을 붙이지 않는다', () {
      final src = File('lib/screens/business_admin/payroll/payroll_worker_detail_screen.dart').readAsStringSync();
      final body = src.substring(src.indexOf('Future<void> _showInterimSettlementDialog('),
          src.indexOf('Future<void> _showPayslipSheet('));
      expect(body.contains('final result = await svc.adminDirectSettlement('), isTrue);
      expect(RegExp(r'if \(result\.hasExclusions\) \{\s*ToastHelper\.showWarning\(result\.toastMessage\(\)\);\s*\} else \{\s*ToastHelper\.showSuccess\(result\.toastMessage\(\)\);')
          .hasMatch(body), isTrue);
      expect(body.contains("'중간정산이 처리되었습니다'"), isFalse, reason: '고정 성공 문구는 결과 객체로 옮김');
      expect(body.contains(r'$e'), isFalse);
      expect(body.contains('e.message!'), isTrue);
    });

    for (final (w, s) in [(320.0, 1.3), (320.0, 2.0), (392.0, 2.0)]) {
      testWidgets('M6 $w·$s 제외 안내 토스트가 예외 없이 두 줄 모두 보인다', (t) async {
        t.view.physicalSize = Size(w, 800);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        await t.pumpWidget(MaterialApp(
          navigatorKey: navigatorKey,
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(s)),
            child: child!,
          ),
          home: const Scaffold(body: SizedBox()),
        ));
        final r = DirectSettlementResult.fromResponse(<String, Object?>{
          'netAmount': 1234560, 'transferredAttendanceIds': List.generate(12, (i) => 'a$i'),
          'excluded': <String, Object?>{'x1': 'ALREADY_TRANSFERRED', 'x2': 'SETTLEMENT_LOCKED', 'x3': 'NOT_CONFIRMED'},
        }, requestedCount: 15);
        ToastHelper.showWarning(r.toastMessage());
        await t.pump();
        expect(t.takeException(), isNull);
        expect(findVisibleTextContaining('실수령 1,234,560원'), findsOneWidget);
        expect(findVisibleTextContaining('3건은 제외됐어요'), findsOneWidget);
        await t.pump(const Duration(seconds: 3));
      });
    }
  });
}
