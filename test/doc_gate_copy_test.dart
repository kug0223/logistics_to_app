// [CONFIRM-CANCEL-COPY · CONSENT-PENDING-COPY] 10-23 문구 정정 — 확정 취소 창 · 동의 전 안내.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/visible_text.dart'; // [DU255] keepWords 문구는 보이는 글자로 찾는다

import 'package:ALfit/services/applicant_document_review_service.dart';
import 'package:ALfit/utils/dialog_helper.dart';

Future<void> _open(WidgetTester t, Future<String?> Function(BuildContext) show) async {
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(child: ElevatedButton(onPressed: () => show(ctx), child: const Text('열기'))),
      ),
    ),
  ));
  await t.tap(find.text('열기'));
  await t.pumpAndSettle();
}

void main() {
  group('CC 확정 취소 창', () {
    testWidgets('CC-1 확정 취소 의미로 통일 — 거절 문구·버튼이 없다', (t) async {
      await _open(t, (c) => DialogHelper.showConfirmCancelReasonPicker(c, message: '홍길동님의 확정된 근무를 취소합니다.'));
      expect(findVisibleText('확정 취소'), findsNWidgets(2), reason: '제목 + 확인 버튼');
      expect(findVisibleText('닫기'), findsOneWidget, reason: '창 닫기 버튼');
      expect(findVisibleText('거절'), findsNothing);
      expect(findVisibleTextContaining('거절'), findsNothing);
      for (final r in ['경력/경험 부족', '다른 지원자 확정', '서류 미비']) {
        expect(find.text(r), findsNothing, reason: '지원 거절 사유를 쓰지 않는다: $r');
      }
      await t.tap(findVisibleText('기타'));
      await t.pump();
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text.contains('인연'), isFalse, reason: '지원 거절 기본 문구 재사용 금지');
    });

    testWidgets('CC-2 사유를 고르면 그 사유를 돌려준다 · 닫기는 null', (t) async {
      String? got = 'unset';
      await _open(t, (c) async => got = await DialogHelper.showConfirmCancelReasonPicker(c));
      await t.tap(find.text('근무 일정 변경'));
      await t.pump();
      await t.tap(findVisibleText('확정 취소').last); // 확인 버튼(제목은 first)
      await t.pumpAndSettle();
      expect(got, '근무 일정 변경');
      await t.tap(find.text('열기'));
      await t.pumpAndSettle();
      await t.tap(findVisibleText('닫기'));
      await t.pumpAndSettle();
      expect(got, isNull);
    });

    testWidgets('CC-3 대조 — 지원 거절 창은 그대로(거절 버튼·기존 사유·기본 문구)', (t) async {
      await _open(t, (c) => DialogHelper.showRejectReasonPicker(c, title: '지원 거절', message: '거절 사유를 선택해주세요.'));
      expect(findVisibleText('거절'), findsOneWidget);
      expect(findVisibleText('취소'), findsOneWidget);
      expect(find.text('경력/경험 부족'), findsOneWidget);
      await t.tap(findVisibleText('기타'));
      await t.pump();
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text.contains('인연'), isTrue);
    });
  });

  group('ID 초대 거절 확인창', () {
    testWidgets('ID-1 확인은 `초대 거절`, 창만 닫는 버튼은 `닫기` — `취소하기` 없음', (t) async {
      bool? got;
      await _open(t, (c) async { got = await DialogHelper.showDeclineInviteConfirm(c); return null; });
      expect(findVisibleText('초대를 거절하시겠습니까?'), findsOneWidget);
      expect(find.text('초대 거절'), findsNWidgets(2), reason: '제목 + 확인 버튼');
      expect(findVisibleText('닫기'), findsOneWidget);
      expect(find.text('취소하기'), findsNothing);
      await t.tap(findVisibleText('닫기'));
      await t.pumpAndSettle();
      expect(got, isFalse, reason: '닫기는 거절하지 않는다');
      await t.tap(find.text('열기'));
      await t.pumpAndSettle();
      await t.tap(find.text('초대 거절').last);
      await t.pumpAndSettle();
      expect(got, isTrue);
    });
    test('ID-2 두 호출부 모두 같은 확인창을 쓴다(거절 writer 는 그대로)', () {
      for (final f in ['lib/screens/user/my_applications_screen.dart', 'lib/screens/common/job_posting_screen.dart']) {
        final s = File(f).readAsStringSync();
        expect(s.contains('DialogHelper.showDeclineInviteConfirm(context)'), isTrue, reason: f);
        expect(s.contains("httpsCallable('callableDeclineTOInvitation')"), isTrue, reason: f);
        expect(RegExp(r"showCancelConfirm\(\s*context,\s*title: '초대 거절'").hasMatch(s), isFalse, reason: f);
      }
    });
  });

  group('CL 동의 전 안내', () {
    test('CL-1 서버의 "동의하지 않았습니다"는 화면에서 "아직 동의하지 않아"로', () {
      final r = ApplicantDocumentReview.fromMap({'consentBlock': ApplicantDocumentReview.serverConsentMissingText});
      expect(r.consentBlockLabel, '근로자가 아직 서류 열람에 동의하지 않아 지금은 서류를 볼 수 없어요.');
      expect(r.consentBlock, ApplicantDocumentReview.serverConsentMissingText, reason: '판정 값은 그대로');
    });
    test('CL-2 만료·옛 버전 등 다른 사유는 그대로 보인다', () {
      for (final s in ['초대 수락 기한이 지나 서류를 열람할 수 없습니다.', '근로자의 서류 열람 동의(최신 버전)가 필요합니다.', '검토 중인 지원서가 아닙니다.']) {
        expect(ApplicantDocumentReview.fromMap({'consentBlock': s}).consentBlockLabel, s);
      }
      expect(ApplicantDocumentReview.fromMap(const {}).consentBlockLabel, isNull);
    });
  });
}
