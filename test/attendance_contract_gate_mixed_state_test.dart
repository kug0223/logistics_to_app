// [CONTRACT-BEFORE-CHECKIN] 배포 혼합 상태 — 구 앱 + 새 서버(callableCheckIn 계약 gate)
//
//   구 앱(설치본)은 계약 상태로 출근 버튼을 막지 않는다(a713dbc). 새 서버가 거절하면 구 앱이
//   무엇을 보여 주는가 — 출근 요청 경로(FirestoreService.checkIn → 오류 대화상자)는 이번에
//   바꾸지 않았으므로 구 앱과 새 앱이 같은 코드다(app-unit diff 에 _checkIn 변경 없음).
//
//   여기서는 실제 서비스 코드에 callable 채널로 **후보 서버의 거절 응답**(LOCAL 실핸들러 출력과 같은
//   code·message·details)을 돌려주고, 화면 대화상자가 띄울 문장을 확인한다.
//   MX-1~3 세 거절 사유 → 서버 문장 그대로(내부 코드·영문 없음), 근태 id 없음(성공으로 오인 없음)
//   MX-4 서버 문장은 functions/src/index.ts 의 판정 문구와 같다(문구 출처 하나)
//   회복 경로: 서명 대기면 구 앱의 하단 서명 배너(PendingContractBar)·출근 화면 '계약서 확인' CTA 가
//   그대로 있다(코드 무변경). 계약 없음·사업주 대기는 사업장이 발송·서명해야 풀린다.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/services/firestore_service.dart';

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp(
          {String? name, FirebaseOptions? options}) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

const _ch =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// 후보 서버(cand/callableCheckIn)의 거절 — LOCAL 실핸들러 실행(run-cand)에서 나온 code·reason 과 같은 사유
const _server = {
  'CONTRACT_MISSING':
      '사업주가 아직 이 근무의 근로계약서를 보내지 않았어요. 계약서를 받고 동의하면 출근할 수 있어요.',
  'CONTRACT_EMPLOYER_PENDING':
      '사업주의 근로계약서 서명이 아직 끝나지 않았어요. 사업주 서명 후 동의하면 출근할 수 있어요.',
  'CONTRACT_WORKER_PENDING': '근로계약서에 동의(서명)한 뒤 출근할 수 있어요.',
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  var i = 0;
  for (final e in _server.entries) {
    i++;
    test('MX-$i 구 앱 + 새 서버: ${e.key} → 대화상자 문장은 서버 문장 그대로', () async {
      final asked = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(_ch, (data) async {
        final args = (const StandardMessageCodec().decodeMessage(data) as List)
            .first as Map;
        asked.add('${args['functionName']}');
        // pigeon 오류 응답: [code, message, details]
        return const StandardMessageCodec().encodeMessage(<Object?>[
          'failed-precondition',
          e.value,
          {'code': e.key},
        ]);
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMessageHandler(_ch, null));

      Object? thrown;
      String? attendanceId;
      try {
        attendanceId = await FirestoreService().checkIn(
          applicationId: 'app1',
          userId: 'u1',
          businessId: 'biz1',
          businessName: 'QA 사업장',
          workDate: DateTime.utc(2026, 10, 24, 15),
          workType: '분류',
          latitude: 37.5,
          longitude: 127.03,
        );
      } catch (err) {
        thrown = err;
      }
      expect(asked, ['callableCheckIn']);
      expect(attendanceId, isNull, reason: '거절을 출근 성공으로 오인하지 않는다');
      expect(thrown, isNotNull);
      // 출근 화면 _checkIn 의 catch 와 같은 변환(구·신 앱 동일 코드)
      final shown = thrown.toString().replaceAll('Exception: ', '');
      expect(shown, e.value);
      expect(shown.contains('CONTRACT_'), isFalse, reason: '내부 코드를 사용자에게 보이지 않는다');
    });
  }

  test('MX-4 서버 문장의 출처는 functions/src/index.ts 판정 문구 하나다', () {
    final src = File('functions/src/index.ts').readAsStringSync();
    for (final e in _server.entries) {
      expect(src.contains('${e.key}: "${e.value}"'), isTrue,
          reason: '${e.key} 문구가 서버 소스와 다르면 이 시험의 기대가 낡은 것이다');
    }
  });
}
