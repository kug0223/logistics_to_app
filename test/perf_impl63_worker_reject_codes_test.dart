// [impl_63] 근로자 화면 — 서버 거절 코드(details.code)를 일반 실패 · 성공으로 접지 않는다.
//   CONTRACT_SCAN_TRUNCATED(계약해지 요청 거절) · OVERLAP_CHECK_INCOMPLETE(초대 수락).
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/utils/server_reject_codes.dart';
import 'package:ALfit/utils/worker_reject_messages.dart';

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

const _cf = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

FirebaseFunctionsException _ex(String? code) => FirebaseFunctionsException(
    message: '서버 문구', code: 'failed-precondition', details: code == null ? null : {'code': code});

String _code(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  test('초대 수락 OVERLAP_CHECK_INCOMPLETE → 다시 시도 안내 · 다른 코드는 null(서버 문구로)', () {
    expect(inviteAcceptRejectMessageOf(_ex(ServerRejectCode.overlapCheckIncomplete)),
        '근무 겹침 확인을 끝내지 못해 수락하지 않았어요 · 다시 시도해 주세요');
    expect(inviteAcceptRejectMessageOf(_ex('SOMETHING_ELSE')), isNull);
    expect(inviteAcceptRejectMessageOf(_ex(null)), isNull);
  });

  test('계약해지 CONTRACT_SCAN_TRUNCATED → 공용 안내(처리하지 않았어요 · 다시 시도)', () {
    expect(terminationRejectMessageOf(_ex(ServerRejectCode.contractScanTruncated)), contractScanTruncatedMessage);
    expect(contractScanTruncatedMessage, contains('처리하지 않았어요'));
    expect(terminationRejectMessageOf(_ex('OTHER')), isNull);
  });

  group('계약해지 거절 서비스', () {
    void respondError(String? detailsCode) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_cf, (msg) async =>
          const StandardMessageCodec().encodeMessage(<Object?>[
            'failed-precondition',
            '연결된 계약이 너무 많아 처리할 수 없습니다.',
            // 실제 플랫폼 꼴: details = {code(HttpsError 코드), message, additionalData(서버 details)}.
            <String, Object?>{
              'code': 'failed-precondition',
              'message': '연결된 계약이 너무 많아 처리할 수 없습니다.',
              if (detailsCode != null) 'additionalData': <String, Object?>{'code': detailsCode},
            },
          ]));
    }

    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_cf, null));

    test('CONTRACT_SCAN_TRUNCATED 는 false 로 접지 않고 던진다(화면이 다시 시도 안내)', () async {
      respondError(ServerRejectCode.contractScanTruncated);
      Object? thrown;
      try {
        await FirestoreService().rejectTermination(applicationId: 'app1');
      } catch (e) {
        thrown = e;
      }
      expect(serverRejectCodeOf(thrown!), ServerRejectCode.contractScanTruncated);
    });

    test('그 밖의 실패는 기존 그대로 false', () async {
      respondError(null);
      expect(await FirestoreService().rejectTermination(applicationId: 'app1'), isFalse);
    });
  });

  test('화면 연결(원문 보조)', () {
    expect(_code('lib/screens/user/dialogs/my_requests_dialog.dart').contains('final known = terminationRejectMessageOf(e);'),
        isTrue);
    expect(
        _code('lib/screens/user/my_applications_screen.dart')
            .contains("inviteAcceptRejectMessageOf(e) ?? e.message ?? '수락하지 못했어요.'"),
        isTrue);
    expect(
        _code('lib/screens/common/job_posting_screen.dart')
            .contains("inviteAcceptRejectMessageOf(e) ?? e.message ?? '수락하지 못했어요.'"),
        isTrue);
  });
}
