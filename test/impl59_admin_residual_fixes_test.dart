// ignore_for_file: depend_on_referenced_packages
// [impl_59] 관리자 화면 잔여 결함 3종.
//   1. 확정 취소 — 서비스가 사유를 돌려준다(결과판) · 관리자 화면은 그 사유로 한 번만 안내(이중 토스트 0) · 근무자 쪽 bool 판 유지.
//   2. 원시 예외 토스트 — 급여 지급 현황 5곳 · 당일 명단 3곳 → 공용 안내(서버 코드·문구 → 기본 안내).
//   3. 신분증 열람 권한 회수 나머지 두 사유 — '열람 대상이 아니에요' · '확정된 근무가 아니라 열람할 수 없어요'.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/services/payroll_payment_service.dart';
import 'package:ALfit/utils/id_card_helper.dart';
import 'package:ALfit/utils/network_checker.dart';
import 'package:ALfit/utils/server_reject_codes.dart';

FirebaseFunctionsException _fx(String httpCode, {String? message, String? code}) =>
    FirebaseFunctionsException(message: message ?? '', code: httpCode, details: code == null ? null : <String, Object?>{'code': code});

String _src(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// [anchor] 가 처음 나오는 곳부터 [end] 앵커 앞까지(없으면 [len] 글자).
String _slice(String s, String anchor, {String? end, int len = 4000}) {
  final i = s.indexOf(anchor);
  expect(i, greaterThanOrEqualTo(0), reason: '앵커 없음: $anchor');
  if (end != null) {
    final j = s.indexOf(end, i + anchor.length);
    expect(j, greaterThan(i), reason: '끝 앵커 없음: $end');
    return s.substring(i, j);
  }
  return s.substring(i, (i + len).clamp(0, s.length));
}

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

const _channel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

const _admin = [
  'lib/screens/business_admin/dialogs/day_applicants_dialog.dart',
  'lib/screens/business_admin/dialogs/work_applicants_dialog.dart',
  'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart',
  'lib/widgets/dialogs/worker_detail_dialog.dart',
];
const _dash = 'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';
const _day = 'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';

/// 토스트 호출 안에 예외 변수를 문자열로 넣는 꼴(`$e` · `${e}` · `${e.toString()}` · `${e.message}` · `e.toString()`).
///   예외의 숫자 필드(`${e.confirmedProcessedCount}` 등)는 원시 예외 문자열이 아니다.
final _rawToast = RegExp(r'ToastHelper\.show\w+\([^;]*(\$e\b|\$\{e(\}|\.toString|\.message)|\be\.toString\(\))');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1 확정 취소 결과 — 사유 매핑', () {
    test('서버 거절(결과 앎) — 고정 안내 · 보여도 되는 서버 문구 · 개발 문장은 기본 안내', () {
      final nf = ConfirmCancelResult.fromError(_fx('not-found', message: '지원서를 찾을 수 없습니다.'));
      expect((nf.success, nf.outcomeUnknown, nf.code, nf.message), (false, false, 'not-found', confirmCancelNotFoundMessage));
      expect(ConfirmCancelResult.fromError(_fx('permission-denied', message: 'TO 관리 권한이 없습니다.')).message, confirmCancelPermissionMessage);
      expect(ConfirmCancelResult.fromError(_fx('failed-precondition', message: '확정된 지원만 취소할 수 있습니다.')).message, '확정된 지원만 취소할 수 있습니다.');
      const work = '이미 근무가 시작된 건은 확정을 취소할 수 없습니다. 근태 수정 또는 급여 처리 화면에서 처리해주세요.';
      expect(ConfirmCancelResult.fromError(_fx('failed-precondition', message: work)).message, work);
      final dev = ConfirmCancelResult.fromError(
          _fx('failed-precondition', message: '[Fix-A] new-schema slot에서 wdId resolve 실패 — aggregate-only mutation 금지 (app=a1)'));
      expect((dev.outcomeUnknown, dev.message), (false, confirmCancelRejectedFallback), reason: '개발 문장은 보이지 않는다');
      expect(ConfirmCancelResult.fromError(_fx('invalid-argument', message: 'applicationId 필수')).message, confirmCancelRejectedFallback);
      // 거절이면 관리자 안내 = 사유 그대로
      expect(nf.adminToast, confirmCancelNotFoundMessage);
    });
    test('결과 모름 — 시간 초과·연결 끊김·모르는 예외·응답 이상', () {
      for (final c in ['deadline-exceeded', 'unavailable', 'internal', 'unknown']) {
        final r = ConfirmCancelResult.fromError(_fx(c, message: '일시 오류'));
        expect((r.success, r.outcomeUnknown, r.message), (false, true, confirmCancelUnknownMessage), reason: c);
        expect(r.adminToast, confirmCancelUnknownReloadedMessage, reason: '취소하지 못했다고 단정하지 않는다');
      }
      expect(ConfirmCancelResult.fromError(StateError('x')).outcomeUnknown, isTrue);
      expect(const ConfirmCancelResult.unknown().outcomeUnknown, isTrue);
    });
    test('오프라인 — 연결 안내 · 결과 앎(보내지 않았다)', () {
      final r = ConfirmCancelResult.fromError(const NetworkOfflineException('확정 취소를 하려면 인터넷 연결이 필요합니다.'));
      expect((r.success, r.outcomeUnknown, r.code, r.message), (false, false, 'offline', '확정 취소를 하려면 인터넷 연결이 필요합니다.'));
    });
    test('성공', () {
      const r = ConfirmCancelResult.succeeded();
      expect((r.success, r.outcomeUnknown, r.message), (true, false, ''));
    });
  });

  group('2 관리자 처리 실패 공용 안내', () {
    test('보여도 되는 서버 문구 거르기(표시 안전 · 판정 아님)', () {
      expect(isUserFacingServerMessage('급여 관리 권한이 없습니다.'), isTrue);
      expect(isUserFacingServerMessage('TO 관리 권한이 없습니다.'), isTrue);
      expect(isUserFacingServerMessage('attendanceIds가 필요합니다.'), isFalse);
      expect(isUserFacingServerMessage('이체완료 상태가 아닙니다. (현재: confirmed)'), isFalse);
      expect(isUserFacingServerMessage('NO_SHOW 출근 기록이 없는 지원서입니다.'), isFalse);
      expect(isUserFacingServerMessage('[Fix-A] 실패'), isFalse);
      expect(isUserFacingServerMessage('  '), isFalse);
      expect(isUserFacingServerMessage(null), isFalse);
    });
    test('code → 안내 · 오프라인 · 서버 문구 · 결과 모름/모르는 예외 = 기본 안내', () {
      const fb = '기본';
      expect(adminActionErrorMessage(_fx('failed-precondition', message: '서버', code: 'X1'), fallback: fb, byCode: const {'X1': '코드 안내'}), '코드 안내');
      expect(adminActionErrorMessage(const NetworkOfflineException('연결 필요'), fallback: fb), '연결 필요');
      expect(adminActionErrorMessage(_fx('permission-denied', message: '이체 취소 권한이 없습니다.'), fallback: fb), '이체 취소 권한이 없습니다.');
      expect(adminActionErrorMessage(_fx('internal', message: '내부 오류입니다'), fallback: fb), fb, reason: '결과 모름은 서버 문구를 쓰지 않는다');
      expect(adminActionErrorMessage(_fx('invalid-argument', message: 'businessId가 필요합니다.'), fallback: fb), fb);
      expect(adminActionErrorMessage(Exception('Exception: 원시'), fallback: fb), fb);
    });
    test('일괄 이체 — 첫 실패 원인이 안내를 고른다', () {
      final e = PartialBatchException(
          confirmedProcessedCount: 0, chunkErrors: const ['청크 1: 급여 관리 권한이 없습니다.'],
          firstError: _fx('permission-denied', message: '급여 관리 권한이 없습니다.'));
      expect(adminActionErrorMessage(e.firstError ?? e, fallback: transferBatchFailedMessage), '급여 관리 권한이 없습니다.');
      expect(adminActionErrorMessage(e, fallback: transferBatchFailedMessage), transferBatchFailedMessage,
          reason: '예외 문자열(청크 목록)을 띄우지 않는다');
    });
  });

  group('2 일괄 이체 — 실제 서비스가 첫 실패 예외를 싣는다', () {
    setUpAll(() async {
      FirebasePlatform.instance = _FakeCore();
      await Firebase.initializeApp();
    });
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_channel, null));
    test('첫 청크 거절 → firstError = 그 FirebaseFunctionsException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_channel, (message) async {
        const c = StandardMessageCodec();
        return c.encodeMessage(<Object?>['permission-denied', 'x', {'code': 'permission-denied', 'message': '급여 관리 권한이 없습니다.'}]);
      });
      Object? caught;
      try {
        await PayrollPaymentService().markTransferredBatch(attendanceIds: const ['a1', 'a2'], businessId: 'b1');
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<PartialBatchException>());
      final p = caught as PartialBatchException;
      expect(p.firstError, isA<FirebaseFunctionsException>());
      expect(adminActionErrorMessage(p.firstError!, fallback: transferBatchFailedMessage), '급여 관리 권한이 없습니다.');
    });
  });

  group('3 신분증 열람 권한 회수 — 나머지 두 사유', () {
    IdCardAccessRequestModel m(String status, {String? why}) => IdCardAccessRequestModel.fromMap(<String, dynamic>{
          'requesterId': 'r', 'targetUserId': 't', 'status': status, 'requestedAt': Timestamp.fromDate(DateTime(2026, 11, 1)),
          if (why != null) 'unusableReason': why,
        }, 'id1');
    test('상태 문자열 · 배지 글 · 요청 가능(예전 none 과 같다)', () {
      expect(IdCardHelper.statusStringOf(m('revoked', why: 'NOT_CURRENT_MEMBER')), 'revokedNotMember');
      expect(IdCardHelper.statusStringOf(m('revoked', why: 'GRANT_APPLICATION_INACTIVE')), 'revokedInactive');
      expect(IdCardHelper.statusStringOf(m('revoked', why: 'SOMETHING_NEW')), 'none', reason: '모르는 사유는 예전 그대로');
      expect(IdCardHelper.statusStringOf(m('revoked')), 'none');
      expect(IdCardHelper.getStatusInfo('revokedNotMember').label, '열람 대상이 아니에요');
      expect(IdCardHelper.getStatusInfo('revokedInactive').label, '확정된 근무가 아니라 열람할 수 없어요');
      expect(IdCardHelper.isRequestable('revokedNotMember'), isTrue);
      expect(IdCardHelper.isRequestable('revokedInactive'), isTrue);
      expect(IdCardHelper.filterRequestableUsers(statusMap: const {'u1': 'revokedInactive', 'u2': 'approved'}, userIds: const ['u1', 'u2']), ['u1']);
    });

    // 지원자 행의 실제 배치(배지 Wrap) — 좁은 폭·큰 글자에서 넘침 0 · 글 전문 · 화면 안.
    for (final v in const [(w: 320.0, s: 1.3), (w: 320.0, s: 2.0), (w: 392.0, s: 2.0)]) {
      for (final st in const ['revokedNotMember', 'revokedInactive', 'approved']) {
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
                child: Builder(builder: (c) => Wrap(spacing: 4, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), child: const Text('계약 완료')),
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
          // 글 전체가 그려진다(잘림·말줄임 0) — 줄을 넘겨도 마지막 글자까지 측정 폭 안.
          final para = t.renderObject<RenderParagraph>(find.text(label));
          expect(para.didExceedMaxLines, isFalse);
        });
      }
    }
  });

  group('연결(원문 핀)', () {
    test('1 서비스 — 결과판은 토스트 0 · bool 판은 결과판의 얇은 포장(오프라인 던짐 · 실패 토스트 1)', () {
      final svc = _src('lib/services/firestore/application_firestore.dart');
      final wrap = _slice(svc, 'Future<bool> cancelConfirmedApplication(', end: 'Future<ConfirmCancelResult> cancelConfirmedApplicationWithResult(');
      expect(wrap, contains("NetworkChecker.instance.assertOnline('확정 취소를 하려면 인터넷 연결이 필요합니다.');"));
      expect(wrap, contains('await cancelConfirmedApplicationWithResult('));
      expect(wrap, contains('if (!r.success) ToastHelper.showError(r.message);'));
      expect(RegExp('ToastHelper').allMatches(wrap).length, 1);
      final body = _slice(svc, 'Future<ConfirmCancelResult> cancelConfirmedApplicationWithResult(', end: '/// 리컨펌(재확인) 알림 응답');
      expect(body.contains('ToastHelper'), isFalse, reason: '결과판은 안내를 띄우지 않는다(이중 토스트 0)');
      expect(body, contains('if (uid.isEmpty) return const ConfirmCancelResult.unknown();'));
      expect(RegExp(r'return ConfirmCancelResult\.fromError\(e\);').allMatches(body).length, 3);
      expect(body, contains('return const ConfirmCancelResult.succeeded();'));
    });
    test('1 관리자 화면 4곳 — 결과판만 쓰고 실패 안내는 결과의 사유', () {
      for (final p in _admin) {
        final s = _src(p);
        expect(s.contains('.cancelConfirmedApplication('), isFalse, reason: '$p — bool 판 호출 0');
        expect(s, contains('cancelConfirmedApplicationWithResult('), reason: p);
      }
      final day = _slice(_src(_day), 'final cancel = await _svc.cancelConfirmedApplicationWithResult(', len: 900);
      final dFail = day.substring(day.indexOf('if (!cancel.success) {'), day.indexOf("ToastHelper.showSuccess('확정이 취소되었습니다');"));
      expect(dFail, contains('await _load();'));
      expect(dFail, contains('ToastHelper.showError(cancel.adminToast);'));
      expect(RegExp('ToastHelper').allMatches(dFail).length, 1);
      final work = _slice(_src(_admin[1]), 'final cancel = await _firestoreService.cancelConfirmedApplicationWithResult(', len: 900);
      final wFail = work.substring(work.indexOf('if (!cancel.success) {'), work.indexOf('ToastHelper.showSuccess('));
      expect(wFail, contains('await _loadApplicants();'));
      expect(wFail, contains('ToastHelper.showError(cancel.adminToast);'));
      final wd = _slice(_src(_admin[3]), 'final cancel = await _firestoreService.cancelConfirmedApplicationWithResult(', len: 1100);
      expect(wd, contains('ToastHelper.showError(cancel.message);'));
      expect(wd.contains('확정 취소 처리 중 오류가 발생했습니다'), isFalse);
      final fx = _slice(_src(_admin[2]), 'ConfirmCancelResult? immediateCancel;', len: 3200);
      expect(fx, contains('immediateCancel = cancel;'));
      final fToast = fx.substring(fx.indexOf('if (immediateCancel != null && !immediateCancel.success) {'));
      expect(fToast.indexOf("ToastHelper.showWarning('계약 종료는 통보했지만 바로 종료하지 못했어요 · \${immediateCancel.message}');"),
          lessThan(fToast.indexOf("ToastHelper.showSuccess('계약 종료가 통보되었습니다');")));
      expect(fToast, contains('} else {'));
    });
    test('1 근무자 화면은 bool 판 그대로(원본 무수정)', () {
      expect(_src('lib/widgets/dialogs/apply/apply_work_dialog.dart'), contains('final canceled = await _firestoreService.cancelConfirmedApplication('));
    });
    test('2 급여 지급 현황 · 당일 명단 — 토스트에 예외 문자열 0 · 자리마다 공용 안내', () {
      for (final p in [_dash, _day]) {
        final hits = _rawToast.allMatches(_src(p)).map((m) => m.group(0)).toList();
        expect(hits, isEmpty, reason: '$p: $hits');
      }
      final dash = _src(_dash);
      for (final fb in [
        'adminActionErrorMessage(e, fallback: transferMarkFailedMessage)',
        'adminActionErrorMessage(cause, fallback: transferBatchFailedMessage)',
        'adminActionErrorMessage(e, fallback: interimApprovalCancelFailedMessage)',
        'adminActionErrorMessage(e, fallback: interimRejectFailedMessage)',
        'adminActionErrorMessage(e, fallback: transferCancelFailedMessage)',
      ]) {
        expect(dash, contains(fb));
      }
      expect(dash, contains('final cause = e is PartialBatchException ? (e.firstError ?? e) : e;'));
      final day = _src(_day);
      expect(day, contains('adminActionErrorMessage(e, fallback: noshowReleaseFailedMessage)'));
      expect(day, contains('adminActionErrorMessage(e, fallback: contractSendFailedMessage)'));
      expect(day, contains('adminActionErrorMessage(e, fallback: applicantRejectFailedMessage)'));
      final svc = _src('lib/services/payroll_payment_service.dart');
      expect(svc, contains('firstChunkError ??= e;'));
      expect(svc, contains('firstError: firstChunkError,'));
    });
    test('3 배지 — 긴 사유가 남은 폭 안에서 줄을 넘긴다', () {
      final h = _slice(_src('lib/utils/id_card_helper.dart'), 'static Widget buildStatusBadge(BuildContext context, String status) {', len: 1400);
      expect(h, contains('Flexible(\n            child: Text(\n              info.label,'));
    });
  });
}
