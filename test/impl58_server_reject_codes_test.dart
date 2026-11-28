// [impl_58 · server_296–298] 관리자 화면 — 서버 거절 코드 안내 · 입력 경계 · 연결(원문 핀).
//   판정 = details['code'] 만(서버 문구 판별 0). 거절 자체(저장·처리 0)는 그대로 — 안내만 고른다.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/services/payroll_payment_service.dart';
import 'package:ALfit/utils/approve_review_error_message.dart';
import 'package:ALfit/utils/id_card_helper.dart';
import 'package:ALfit/utils/responsive_helper.dart';
import 'package:ALfit/utils/server_reject_codes.dart';

FirebaseFunctionsException _fx(String httpCode, String? code, {String message = '서버 문구'}) =>
    FirebaseFunctionsException(message: message, code: httpCode, details: code == null ? null : <String, Object?>{'code': code});

String _src(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// [anchor] 가 처음 나오는 곳부터 [len] 글자.
String _slice(String s, String anchor, [int len = 4000]) {
  final i = s.indexOf(anchor);
  expect(i, greaterThanOrEqualTo(0), reason: '앵커 없음: $anchor');
  return s.substring(i, (i + len).clamp(0, s.length));
}

void main() {
  group('코드 → 안내(details.code 만)', () {
    test('공고 입력 4종', () {
      expect(postingInputRejectMessageOf(_fx('invalid-argument', 'TO_FIELD_NOT_ALLOWED')), toFieldNotAllowedMessage);
      expect(postingInputRejectMessageOf(_fx('invalid-argument', 'REQUIRED_COUNT_INVALID')), requiredCountInvalidMessage);
      expect(postingInputRejectMessageOf(_fx('invalid-argument', 'INVALID_CALENDAR_DATE')), invalidCalendarDateMessage);
      expect(postingInputRejectMessageOf(_fx('invalid-argument', 'TOO_MANY_DATES')), tooManyDatesMessage);
      expect(postingInputRejectMessageOf(_fx('invalid-argument', 'SOMETHING_ELSE')), isNull);
      expect(postingInputRejectMessageOf(_fx('invalid-argument', null, message: 'TO_FIELD_NOT_ALLOWED')), isNull,
          reason: '문구에 코드가 있어도 판정 0');
      expect(postingInputRejectMessageOf(Exception('TOO_MANY_DATES')), isNull);
      expect(postingInputRejectMessageOf(const PostingInputInvalid(ServerRejectCode.tooManyDates)), tooManyDatesMessage,
          reason: '앱 사전 검사도 같은 안내');
    });
    test('일괄 출근 · 열람 요청 · 확정 · 계약해지', () {
      expect(batchCheckInRejectMessageOf(_fx('invalid-argument', 'CHECKIN_ENTRY_CONFLICT')), checkInEntryConflictMessage);
      expect(batchCheckInRejectMessageOf(_fx('invalid-argument', null)), isNull);
      expect(idCardRequestRejectMessageOf(_fx('permission-denied', 'APPLICATION_MISMATCH')), applicationMismatchMessage);
      expect(idCardRequestRejectMessageOf(_fx('permission-denied', null)), isNull);
      expect(overlapCheckIncompleteMessageOf(_fx('failed-precondition', 'OVERLAP_CHECK_INCOMPLETE')),
          '근무 겹침 확인을 끝내지 못해 확정하지 않았어요 · 다시 시도해 주세요');
      expect(overlapCheckIncompleteMessageOf(_fx('failed-precondition', null, message: '근무 일정 겹침을 확인하지 못했습니다.')), isNull);
      expect(contractScanTruncatedMessageOf(_fx('failed-precondition', 'CONTRACT_SCAN_TRUNCATED')),
          '관련 계약을 모두 확인하지 못해 처리하지 않았어요 · 다시 시도해 주세요');
      expect(contractScanTruncatedMessageOf(_fx('failed-precondition', 'OTHER')), isNull);
    });
    test('급여 정정 3종 · 중간정산 금액 형식', () {
      expect(wageUpdateRejectMessageOf(_fx('invalid-argument', 'WAGE_FIELD_MISSING')), wageFieldMissingMessage);
      expect(wageUpdateRejectMessageOf(_fx('invalid-argument', 'WAGE_TYPE_CHANGED')), wageTypeChangedMessage);
      expect(wageUpdateRejectMessageOf(_fx('failed-precondition', 'WAGE_VALUE_INVALID')), wageValueInvalidMessage);
      expect(wageUpdateRejectMessageOf(_fx('failed-precondition', 'WAGE_CHANGED')), isNull, reason: '기존 stale 갈래는 그대로');
      expect(wageValueInvalidMessageOf(_fx('failed-precondition', 'WAGE_VALUE_INVALID')), wageValueInvalidMessage);
      // 중간정산 공용 안내 — 근태 id 가 섞인 서버 문구 대신 다음 할 일.
      expect(interimProcessErrorMessage(_fx('failed-precondition', 'WAGE_VALUE_INVALID', message: '급여 금액 형식이 올바르지 않은 근무가 있습니다: att1.')),
          wageValueInvalidMessage);
      expect(interimProcessErrorMessage(_fx('failed-precondition', 'stalePaymentSnapshot')), interimProcessStaleSnapshotMessage,
          reason: '기존 계좌 갈래 그대로');
      expect(interimProcessErrorMessage(Exception('x')), '처리에 실패했습니다. 잠시 뒤 다시 시도해주세요.');
    });
    test('확정 승인(검토) — 겹침 확인 미완료는 다시 시도 · reload 0', () {
      final e = ApproveReviewError.of(_fx('failed-precondition', 'OVERLAP_CHECK_INCOMPLETE',
          message: '근무 일정 겹침을 확인하지 못했습니다. 관리자에게 문의해 주세요.'), canSetUp: true);
      expect(e.message, overlapCheckIncompleteMessage);
      expect(e.reload, isFalse);
      final other = ApproveReviewError.of(_fx('failed-precondition', null, message: '서버 사유'), canSetUp: true);
      expect(other.message, '서버 사유', reason: '그 밖의 사유는 서버 문장 그대로');
    });
    test('그 밖 실패 — 서버 문구 또는 기본(예외 문자열 0)', () {
      expect(serverMessageOr(_fx('internal', null, message: '  서버  '), '기본'), '서버');
      expect(serverMessageOr(Exception('Exception: raw'), '기본'), '기본');
    });
  });

  group('입력 경계 = 서버 경계', () {
    test('정원 1–999 정수', () {
      expect(isValidRequiredCount(1), isTrue);
      expect(isValidRequiredCount(999), isTrue);
      for (final bad in <Object?>[0, -1, 1000, 1.5, '3', null, double.infinity]) {
        expect(isValidRequiredCount(bad), isFalse, reason: '$bad');
      }
    });
    test('실제 달력 날짜', () {
      expect(isRealCalendarDateString('2028-02-29'), isTrue);
      expect(isRealCalendarDateString('2027-02-29'), isFalse);
      expect(isRealCalendarDateString('2026-02-30'), isFalse);
      expect(isRealCalendarDateString('2026-13-01'), isFalse);
      expect(isRealCalendarDateString('2026-1-01'), isFalse);
    });
    test('사전 검사 — 정원 · 날짜 수(≤366) · 날짜', () {
      final ok = List.generate(366, (i) => '2027-01-01');
      expect(() => assertPostingInputWithinServerBounds(requiredCounts: [1, 999], dateStrings: ok), returnsNormally);
      expect(() => assertPostingInputWithinServerBounds(requiredCounts: [1000]),
          throwsA(isA<PostingInputInvalid>().having((e) => e.code, 'code', 'REQUIRED_COUNT_INVALID')));
      expect(() => assertPostingInputWithinServerBounds(requiredCounts: [0]),
          throwsA(isA<PostingInputInvalid>().having((e) => e.code, 'code', 'REQUIRED_COUNT_INVALID')));
      expect(() => assertPostingInputWithinServerBounds(requiredCounts: [1], dateStrings: [...ok, '2027-01-02']),
          throwsA(isA<PostingInputInvalid>().having((e) => e.code, 'code', 'TOO_MANY_DATES')));
      expect(() => assertPostingInputWithinServerBounds(requiredCounts: [1], dateStrings: ['2026-02-30']),
          throwsA(isA<PostingInputInvalid>().having((e) => e.code, 'code', 'INVALID_CALENDAR_DATE')));
      expect(() => assertPostingInputWithinServerBounds(requiredCounts: [1], dateStrings: null), returnsNormally,
          reason: '장기(날짜 없음)');
    });
  });

  group('지급정보 갱신 skipped — permissionRevoked', () {
    String label(String c) => c == 'alreadyTransferred' ? '이미 이체됨' : '급여계좌 확인 필요';
    test('권한 회수는 건수와 함께 따로 · 나머지는 이름만 중복 없이', () {
      final lines = refreshSkippedLines(
          {'a1': 'permissionRevoked', 'a2': 'permissionRevoked', 'a3': 'alreadyTransferred', 'a4': 'alreadyTransferred', 'a5': 'x'},
          label);
      expect(lines, ['• 권한이 바뀌어 처리하지 않은 2건', '• 이미 이체됨', '• 급여계좌 확인 필요']);
      expect(refreshSkippedLines({'a1': 'alreadyTransferred'}, label), ['• 이미 이체됨'], reason: '권한 줄 없음');
      expect(permissionRevokedSkippedLine(3), '권한이 바뀌어 처리하지 않은 3건');
    });
  });

  group('신분증 열람 권한 회수 사유', () {
    IdCardAccessRequestModel m(String status, {String? why, DateTime? expiresAt}) => IdCardAccessRequestModel.fromMap(<String, dynamic>{
          'requesterId': 'r', 'targetUserId': 't', 'status': status, 'requestedAt': Timestamp.fromDate(DateTime(2026, 11, 1)),
          if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
          if (why != null) 'unusableReason': why,
        }, 'id1');
    test('모델 — unusableReason 읽기 · 저장 0', () {
      final x = m('revoked', why: 'LEGACY_AUTO_GRANT');
      expect(x.unusableReason, 'LEGACY_AUTO_GRANT');
      expect(x.toMap().containsKey('unusableReason'), isFalse);
      expect(m('revoked').unusableReason, isNull);
    });
    test('상태 문자열 · 요청 가능', () {
      expect(IdCardHelper.statusStringOf(m('revoked', why: 'LEGACY_AUTO_GRANT')), 'revokedLegacy');
      expect(IdCardHelper.statusStringOf(m('revoked', why: 'MANUAL_GRANT_EXPIRED')), 'revokedExpired');
      // [impl_59] 소속 아님 사유도 따로 말한다(예전 'none') — 사유 없는 revoked 는 아래처럼 그대로 'none'.
      expect(IdCardHelper.statusStringOf(m('revoked', why: 'NOT_CURRENT_MEMBER')), 'revokedNotMember');
      expect(IdCardHelper.statusStringOf(m('revoked')), 'none');
      expect(IdCardHelper.statusStringOf(null), 'none');
      expect(IdCardHelper.statusStringOf(m('approved', expiresAt: DateTime.now().add(const Duration(days: 2)))), 'approved');
      expect(IdCardHelper.isRequestable('revokedLegacy'), isTrue);
      expect(IdCardHelper.isRequestable('revokedExpired'), isTrue);
      expect(IdCardHelper.getStatusInfo('revokedLegacy').label, '자동 열람 종료');
      expect(IdCardHelper.getStatusInfo('revokedExpired').label, '열람 7일 지남');
    });

    // 새 배지 상태 — 좁은 폭·큰 글자에서 넘침 0 · 글 전문 · 화면 안.
    for (final v in const [(w: 320.0, s: 1.3), (w: 320.0, s: 2.0), (w: 392.0, s: 2.0)]) {
      for (final st in const ['revokedLegacy', 'revokedExpired']) {
        testWidgets('배지 $st ${v.w.toInt()}@${v.s}', (t) async {
          t.view.physicalSize = Size(v.w, 700);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          final errors = <String>[];
          final prev = FlutterError.onError;
          FlutterError.onError = (d) => errors.add(d.exceptionAsString());
          addTearDown(() => FlutterError.onError = prev);
          await t.pumpWidget(MaterialApp(
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                // 지원자 행 배치와 같은 꼴: 이름(남은 폭) + 배지
                child: Builder(builder: (c) => Row(children: [
                  Expanded(child: Text('큐에이일', style: ResponsiveHelper.bodyStyle(c))),
                  IdCardHelper.buildStatusBadge(c, st),
                ])),
              ),
            ),
          ));
          await t.pump();
          FlutterError.onError = prev;
          final label = IdCardHelper.getStatusInfo(st).label;
          expect(find.text(label), findsOneWidget);
          final r = t.getRect(find.text(label));
          expect(r.right <= v.w + 0.5 && r.left >= -0.5, isTrue, reason: '화면 안 $r');
          expect(errors.where((e) => e.contains('overflowed')), isEmpty, reason: errors.join(' | '));
        });
      }
    }
  });

  group('연결(원문 핀)', () {
    test('1·2 공고 생성·수정 · 입력 경계', () {
      final create = _src('lib/screens/business_admin/to_management/create_to_screen.dart');
      final cCatch = _slice(create, "debugPrint('❌ TO 생성 실패: \$e');", 2600);
      expect(cCatch, contains('postingInputRejectMessageOf(e) case final inputMsg?'));
      expect(cCatch.indexOf('postingInputRejectMessageOf'), lessThan(cCatch.indexOf("ToastHelper.showError('공고 등록에 실패했습니다');")));
      expect(create, contains('(w.requiredCount ?? 0) > kRequiredCountMax'));
      expect(create, contains('_selectedDates.length > kPostingDatesMaxPerRequest'));
      expect(create.contains('> 10000'), isFalse, reason: '서버가 거절하는 상한 제거');
      final edit = _src('lib/screens/business_admin/to_management/edit_to_screen.dart');
      final cf = _slice(edit, 'String? _cfErrorMessage(Object e) {', 900);
      expect(cf, contains('if (postingInputRejectMessageOf(e) case final inputMsg?) return inputMsg;'));
      expect(cf.indexOf('postingInputRejectMessageOf'), lessThan(cf.indexOf("const safeCodes")), reason: '서버 문구보다 먼저');
      expect(edit, contains('w.requiredCount > kRequiredCountMax'));
      // 슬롯 단건·일괄·공고 수정 세 갈래 모두 _cfErrorMessage 를 쓴다.
      expect(RegExp(r"_cfErrorMessage\(e\) \?\? '수정에 실패했습니다'").allMatches(edit).length, 3);
      final dlg = _src('lib/widgets/pickers/create_edit_work_detail_dialog.dart');
      expect(RegExp(r'!isValidRequiredCount\(count\)').allMatches(dlg).length, 2, reason: '수정·추가 두 모드');
      final to = _src('lib/services/firestore/to_firestore.dart');
      final ct = _slice(to, "NetworkChecker.instance.assertOnline('공고 등록을 하려면 인터넷 연결이 필요합니다.');", 900);
      // 조건 없이 부른다(앞에 if 등 0) — 들여쓰기 4칸으로 줄 맨 앞에서 시작.
      expect(ct, contains('\n    assertPostingInputWithinServerBounds(\n      requiredCounts: workDetails.map((w) => w.requiredCount),'));
      expect(ct.indexOf('assertPostingInputWithinServerBounds'), lessThan(ct.indexOf("GlobalLoadingController.show('공고 등록 중...')")));
      expect(_slice(to, 'Future<void> _callCreateFlexSlots({', 1400), contains('final dateStrings = _flexDateStrings(dates);'));
      final card = _src('lib/widgets/admin/cards/admin_to_group_card.dart');
      expect(card, contains("postingInputRejectMessageOf(e) ?? '제목 변경에 실패했습니다'"));
    });
    test('3 일괄 출근 — 거절 안내 + 근태 재조회(두 경로)', () {
      final att = _src('lib/screens/business_admin/dialogs/attendance_status_dialog.dart');
      final a = _slice(att, "debugPrint('❌ 일괄 출근 처리 실패: \$e');", 500);
      final b = _slice(att, "debugPrint('❌ 파트별 일괄 출근 처리 실패: \$e');", 500);
      for (final s in [a, b]) {
        expect(s, contains('batchCheckInRejectMessageOf(e) case final conflictMsg?'));
        expect(s, contains('await _reloadAttendanceAfterReject();'));
      }
      final r = _slice(att, 'Future<void> _reloadAttendanceAfterReject() async {', 700);
      expect(r.contains('처리는 완료됐어요'), isFalse, reason: '거절 뒤 재조회는 처리 완료라고 말하지 않는다');
    });
    test('4·5 신분증 — 회수 사유 · 열람 요청 APPLICATION_MISMATCH', () {
      final svc = _src('lib/services/firestore/id_card_firestore.dart');
      expect(_slice(svc, "debugPrint('❌ [createIdCardAccessRequest] 실패: \$e');", 300),
          contains("idCardRequestRejectMessageOf(e) ?? '요청 실패'"));
      final helper = _src('lib/utils/id_card_helper.dart');
      expect(helper, contains('static String _toStatusString(dynamic access) => statusStringOf('));
    });
    test('6 급여 정정 · 중간정산 승인/직접', () {
      final w = _src('lib/screens/business_admin/dialogs/wage_confirm_dialog.dart');
      final s = _slice(w, "debugPrint('❌ 급여 수정 실패: \$e');", 2200);
      expect(s, contains('wageUpdateRejectMessageOf(e) case final wageMsg?'));
      expect(s.indexOf('wageUpdateRejectMessageOf'), lessThan(s.indexOf("(e.message ?? '급여 수정에 실패했습니다')")));
      final dash = _src('lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart');
      final ap = _slice(dash, "ToastHelper.showSuccess('중간정산 승인 완료", 700);
      expect(ap, contains('ToastHelper.showError(interimProcessErrorMessage(e))'));
      expect(ap.contains(r"'처리에 실패했습니다\n$e'"), isFalse);
      final det = _src('lib/screens/business_admin/payroll/payroll_worker_detail_screen.dart');
      expect(det, contains('final msg = wageValueInvalidMessageOf(e) ??'));
    });
    test('7 확정 — 겹침 확인 미완료(단건 3 · 일괄 1 · 검토 승인)', () {
      final day = _src('lib/screens/business_admin/dialogs/day_applicants_dialog.dart');
      expect(day, contains("overlapCheckIncompleteMessageOf(e) ?? e.message ?? '확정 처리 중 오류가 발생했습니다'"));
      expect(day, contains('if (overlapCheckIncompleteMessageOf(e) != null) overlapIncompleteCount++;'));
      expect(day, contains("'\\n\${overlapIncompleteBatchNote(overlapIncompleteCount)}'"));
      final work = _src('lib/screens/business_admin/dialogs/work_applicants_dialog.dart');
      expect(work, contains("overlapCheckIncompleteMessageOf(e) ?? '확정 처리 중 오류가 발생했습니다'"));
      final wd = _src('lib/widgets/dialogs/worker_detail_dialog.dart');
      expect(wd, contains("overlapCheckIncompleteMessageOf(e) ?? '\$actionText 처리 중 오류가 발생했습니다'"));
    });
    test('8 지급정보 갱신 — permissionRevoked 줄', () {
      final dash = _src('lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart');
      expect(_slice(dash, 'Future<void> _refreshSnapshots(List<AttendanceModel> recs) async {', 3200),
          contains('refreshSkippedLines(res.skipped, PayrollReadinessReason.labelOf)'));
    });
    test('9 계약해지 — CONTRACT_SCAN_TRUNCATED 는 false 로 뭉개지 않고 화면이 이유를 말한다', () {
      final fs = _src('lib/services/firestore_service.dart');
      for (final a in ["debugPrint('❌ requestTermination 실패: \$e');", "debugPrint('❌ cancelTerminationRequest 실패: \$e');"]) {
        expect(_slice(fs, a, 400), contains('if (contractScanTruncatedMessageOf(e) != null) rethrow;'));
      }
      final fw = _src('lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart');
      expect(fw, contains("contractScanTruncatedMessageOf(e) ?? '계약해지 요청 중 오류가 발생했습니다'"));
      expect(fw, contains("contractScanTruncatedMessageOf(e) ?? '해지 요청 취소 중 오류가 발생했습니다'"));
    });
    test('10 확정 취소 false — 성공 안내 0 · 서버 재조회 · 실패 안내', () {
      final day = _src('lib/screens/business_admin/dialogs/day_applicants_dialog.dart');
      // [impl_59] 결과판(cancelConfirmedApplicationWithResult)으로 바뀌었고 실패 안내는 결과의 사유(adminToast)다.
      final d = _slice(day, 'final cancel = await _svc.cancelConfirmedApplicationWithResult(', 900);
      expect(d, contains('if (!cancel.success) {'));
      final dFalse = d.substring(d.indexOf('if (!cancel.success) {'), d.indexOf("ToastHelper.showSuccess('확정이 취소되었습니다');"));
      expect(dFalse, contains('await _load();'));
      expect(dFalse, contains('ToastHelper.showError(cancel.adminToast);'));
      expect(dFalse, contains('return;'));
      expect(_slice(day, 'Future<void> _cancelConfirmation(ApplicationModel app) async {', 2200).contains(r"'처리 실패: $e'"), isFalse,
          reason: '이 함수의 예외 문자열 0');
      final work = _src('lib/screens/business_admin/dialogs/work_applicants_dialog.dart');
      // [impl_59] 위와 같은 이유로 결과판 · 사유 안내.
      final w = _slice(work, 'final cancel = await _firestoreService.cancelConfirmedApplicationWithResult(', 900);
      final wFalse = w.substring(w.indexOf('if (!cancel.success) {'), w.indexOf('ToastHelper.showSuccess('));
      expect(wFalse, contains('await _loadApplicants();'));
      expect(wFalse, contains('ToastHelper.showError(cancel.adminToast);'));
      expect(wFalse, contains('return;'));
    });
    test('11 리뷰 — 권한 축 canManageWorkers · 입구 숨김 · 실행 시점 재확인', () {
      final wd = _src('lib/widgets/dialogs/worker_detail_dialog.dart');
      expect(_slice(wd, 'PermissionCheck _reviewPermission({bool listen = false}) {', 400),
          contains('.checkForBusiness(bizId, (p) => p.canManageWorkers)'));
      expect(wd, contains('_reviewPermission(listen: true) == PermissionCheck.denied'));
      expect(wd, contains("label: '리뷰 권한 없음'"));
      final open = _slice(wd, 'Future<void> _openReviewDialog() async {', 900);
      expect(open, contains('switch (_reviewPermission()) {'));
      expect(wd, contains('_reviewPermission() != PermissionCheck.denied)\n            ? _checkReviewWritten(app)'));
      // rules 쓰기 축과 같은지(읽기만) — ADMIN_TO_USER create 는 subAdminCanManageWorkers.
      final rules = _src('firestore.rules');
      final mr = _slice(rules, 'match /monthly_reviews/{reviewId} {', 6000);
      expect(mr, contains('subAdminCanManageWorkers(request.resource.data.businessId)'));
    });
  });
}
