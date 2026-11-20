// [DOC-RACE.6 · E] LOCAL 전용 디버그 진입점 — 실제 화면 + 실제 기기 OCR + LOCAL 서버.
//
//   flutter run --debug -t integration_test/e6_local_main.dart -d emulator-5554
//
//   - 릴리스 빌드는 lib/main.dart 만 컴파일한다. 이 파일은 `-t` 로 지정할 때만 들어간다.
//     릴리스 모드에서 실행되면 즉시 멈춘다.
//   - DEV 에 닿지 않는다: Firestore·Storage·Functions 를 호스트 에뮬레이터(10.0.2.2)로 돌리고,
//     가입 화면의 서버 호출은 ForeignRegisterHooks 로 호스트 다리(10.0.2.2:6190)에 보낸다.
//     다리는 배포본과 같은 lib 의 실핸들러를 에뮬레이터 위에서 돌린다. FirebaseAuth 는 부르지 않는다.
//   - 사진은 합성 이미지(실존 아님)를 다리에서 받아 **기기의 실제 ML Kit** 로 읽는다.
//   - 로그에는 이름·번호를 남기지 않는다 — 기대값과 같은지(true/false)와 출처만 남긴다.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/screens/auth/foreign_register_screen.dart';
import 'package:ALfit/services/foreign_id_ocr_service.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/services/fcm_service.dart';
import 'package:ALfit/firebase_options.dart';
import 'package:ALfit/main.dart' show AuthWrapper;
import 'package:ALfit/providers/badge_provider.dart';
import 'package:ALfit/providers/network_provider.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/theme_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
// cloud_functions 가 함께 끌어오는 플랫폼 인터페이스 — 이 디버그 진입점만 쓴다(pubspec 변경 없음).
// ignore: depend_on_referenced_packages
import 'package:cloud_functions_platform_interface/cloud_functions_platform_interface.dart'
    show FirebaseFunctionsPlatform, HttpsCallablePlatform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

const _host = '10.0.2.2';
const _bucket = 'demo-full13.appspot.com';
// 합성 이미지에 적힌 값 — 기기 OCR 이 같은 값을 읽었는지 비교만 한다(로그에 값 없음).
const _synthName = 'NGUYEN VAN AN';
const _synthId = '9001015000001';

String _uid = '';
bool _collection = true;
String _fixture = 'arc_synth.png';

Future<dynamic> _bridge(String method, String path, [Object? body]) async {
  final c = HttpClient();
  try {
    final rq = await c.openUrl(method, Uri.parse('http://$_host:6190$path'));
    if (body != null) {
      rq.headers.contentType = ContentType.json;
      rq.add(utf8.encode(jsonEncode(body)));
    }
    final rs = await rq.close();
    final s = await rs.transform(utf8.decoder).join();
    return s.isEmpty ? null : jsonDecode(s);
  } finally {
    c.close();
  }
}

Future<List<int>> _bridgeBytes(String path) async {
  final c = HttpClient();
  try {
    final rs = await (await c.getUrl(Uri.parse('http://$_host:6190$path'))).close();
    final b = <int>[];
    await for (final x in rs) {
      b.addAll(x);
    }
    return b;
  } finally {
    c.close();
  }
}

// 에뮬레이터 전용 서명 없는 토큰 — 에뮬레이터만 받는다.
String _token(String uid) {
  String b64(Map<String, Object> o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return '${b64({'alg': 'none', 'typ': 'JWT'})}.${b64({
    'iss': 'https://securetoken.google.com/demo-full13', 'aud': 'demo-full13', 'sub': uid, 'user_id': uid,
    'auth_time': 1, 'iat': now, 'exp': now + 3600, 'firebase': {'sign_in_provider': 'password'},
  })}.';
}

Future<int> _storageRest(String method, String storagePath, {List<int>? bytes, List<int>? out}) async {
  final c = HttpClient();
  try {
    final enc = Uri.encodeComponent(storagePath);
    final url = method == 'POST'
        ? 'http://$_host:6172/v0/b/$_bucket/o?name=$enc'
        : 'http://$_host:6172/v0/b/$_bucket/o/$enc?alt=media';
    final rq = await c.openUrl(method, Uri.parse(url));
    rq.headers.set('Authorization', 'Bearer ${_token(_uid)}');
    if (bytes != null) {
      rq.headers.contentType = ContentType('image', 'jpeg');
      rq.add(bytes);
    }
    final rs = await rq.close();
    await for (final x in rs) {
      out?.addAll(x);
    }
    return rs.statusCode;
  } finally {
    c.close();
  }
}

Future<ForeignIdOcrResult> _realOcr(String path) async {
  final r = await ForeignIdOcrService.recognizeFromPath(path);
  final digits = (r.foreignIdRaw ?? '').replaceAll(RegExp(r'\D'), '');
  debugPrint('E6OCR uid=$_uid nameEq=${r.legalName != null && ForeignIdOcrService.normalizeForeignLatinName(r.legalName!) == _synthName} '
      'nameFailed=${r.legalNameFailed} src=${r.legalNameOcrSource} idEq=${digits == _synthId} idFailed=${r.foreignIdFailed} visa=${r.visaType}');
  return r;
}

void _installHooks() {
  ForeignRegisterHooks.currentUid = () => _uid;
  ForeignRegisterHooks.collectionEnabled = () => _collection;
  ForeignRegisterHooks.pickAndOcr = () async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/e6_pick_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(await _bridgeBytes('/fixture/$_fixture'));
    try {
      return (path: f.path, result: await _realOcr(f.path));
    } catch (e) {
      debugPrint('E6OCR uid=$_uid threw=${e.runtimeType}');
      return (path: f.path, result: null);
    }
  };
  ForeignRegisterHooks.reuseOcr = (storagePath) async {
    final out = <int>[];
    final s = await _storageRest('GET', storagePath, out: out);
    debugPrint('E6REUSE uid=$_uid download=$s bytes=${out.length}');
    if (s != 200) throw StateError('download $s');
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/idCard_resume_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await f.writeAsBytes(out);
    try {
      return await _realOcr(f.path);
    } finally {
      await f.delete();
    }
  };
  ForeignRegisterHooks.upload = (localPath, storagePath) async {
    final s = await _storageRest('POST', storagePath, bytes: await File(localPath).readAsBytes());
    debugPrint('E6UPLOAD uid=$_uid status=$s');
    if (s != 200) throw StateError('upload $s');
  };
  ForeignRegisterHooks.readUser = (uid) async => (await _bridge('GET', '/user/$uid')) as Map<String, dynamic>?;
  // AuthService.finalizeForeignIdentity 와 같은 payload·같은 오류 문구 표.
  ForeignRegisterHooks.finalize = (rawId, legalName, koreanName, visaType, ev) async {
    final payload = <String, dynamic>{'rawForeignId': rawId};
    if (ev != null) payload['documentEvidence'] = ev;
    if (legalName.isNotEmpty) payload['legalName'] = legalName;
    if (koreanName.isNotEmpty) payload['koreanName'] = koreanName;
    if (visaType.isNotEmpty) payload['visaType'] = visaType;
    final r = await _bridge('POST', '/call', {'fn': 'callableFinalizeForeignIdentity', 'uid': _uid, 'data': payload}) as Map;
    debugPrint('E6FINALIZE uid=$_uid ok=${r['ok']} code=${r['code']} evidence=${ev != null}');
    if (r['ok'] == true) return null;
    return switch (r['code']) {
      'already-exists' => '이미 동일 역할로 가입된 외국인등록번호입니다.',
      'not-found' => '계정 정보를 확인할 수 없습니다. 다시 시도해주세요.',
      'invalid-argument' => '입력 정보를 확인하고 다시 시도해주세요.',
      'failed-precondition' => '만 19세 이상만 가입할 수 있습니다.',
      'permission-denied' => '가입이 제한된 계정입니다. 고객센터에 문의해주세요.',
      'unauthenticated' => '인증이 만료되었습니다. 앱을 재시작해주세요.',
      _ => '정보를 확인하는 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.',
    };
  };
  ForeignRegisterHooks.mark = (payload) async {
    final r = await _bridge('POST', '/call', {'fn': 'callableMarkIdCardVerified', 'uid': _uid, 'data': payload}) as Map;
    final sc = payload['selfCheck'] as Map?;
    debugPrint('E6MARK uid=$_uid ok=${r['ok']} code=${r['code']} name=${sc?['name']} identifier=${sc?['identifier']} '
        'candidates=${(sc?['identifierCandidates'] as List?)?.length}');
    if (r['ok'] != true) throw StateError('mark ${r['code']}');
  };
}

class _Scenario {
  final String label, uid, fixture;
  final bool collection, existing;
  final int delay;
  final String? blockNumber;
  const _Scenario(this.label, this.uid,
      {this.fixture = 'arc_synth.png', this.collection = true, this.existing = false, this.delay = 0, this.blockNumber});
}

const _scenarios = [
  _Scenario('S1 ON 일치', 'e6on1'),
  _Scenario('S2 ON 번호다름', 'e6on2'),
  _Scenario('S3 ON 이름다름', 'e6on3'),
  _Scenario('S4 ON 빈사진', 'e6on4', fixture: 'blank_synth.png'),
  _Scenario('S5 OFF 일치', 'e6off1', collection: false),
  _Scenario('S6 ON 현재사진 복구', 'e6c1', existing: true),
  _Scenario('S7 ON 늦은 거절', 'e6late', delay: 4000, blockNumber: _synthId),
];

class _Menu extends StatelessWidget {
  const _Menu();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('E6 LOCAL')),
        body: ListView(children: [
          for (final s in _scenarios)
            ListTile(
              title: Text(s.label),
              onTap: () async {
                _uid = s.uid;
                _collection = s.collection;
                _fixture = s.fixture;
                await _bridge('POST', '/setup', {
                  'uid': s.uid, 'collection': s.collection, 'existing': s.existing, 'delay': s.delay,
                  if (s.blockNumber != null) 'blockNumber': s.blockNumber,
                });
                if (!context.mounted) return;
                await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ForeignRegisterScreen(
                        role: UserRole.USER,
                        isResume: true,
                        existingIdCardPath: s.existing ? 'users/${s.uid}/idCard_1700000000001.jpg' : null)));
              },
            ),
        ]),
      );
}

// [DOC-LATE-DELETE.7 · D] --dart-define=E7_MODE=app 이면 실제 앱 화면(AuthWrapper 부터)을 LOCAL 백엔드에 붙인다.
//   Auth·Firestore·Storage = 호스트 에뮬레이터(앱 프로젝트 ID 이름공간), Functions = 호스트 callable 다리(6190).
//   스플래시의 최소 버전 게이트는 Remote Config(원격)를 읽으므로 건너뛴다 — 이 실행의 검증 대상이 아니다.
//   사진 선택만 합성 이미지로 바꾸고 OCR 은 기기 ML Kit 그대로다. App Check 는 켜지 않는다.
const _mode = String.fromEnvironment('E7_MODE', defaultValue: 'menu');

// [E7] Functions **전송만** Dart HTTP 로 바꾼다. 네이티브 Functions SDK 는 호출마다 Instance ID 토큰을
//   먼저 받는데, 그 토큰은 원격 Firebase Installations 등록이 있어야 나온다 — 앱 단위 방화벽으로
//   LOCAL 만 허용한 상태에서는 그 단계에서 UNAVAILABLE 로 끝났다(기기 로그 · 소켓 관측).
//   호출 이름·인자·Auth(에뮬레이터) ID 토큰은 앱 그대로 실리고, 다리의 실핸들러가 처리한다.
class _E7Functions extends FirebaseFunctionsPlatform {
  _E7Functions(super.app, super.region);
  @override
  FirebaseFunctionsPlatform delegateFor({FirebaseApp? app, required String region}) =>
      _E7Functions(app, region);
  @override
  HttpsCallablePlatform httpsCallable(String? origin, String name, HttpsCallableOptions options) =>
      _E7Callable(this, origin, name, options);
}

class _E7Callable extends HttpsCallablePlatform {
  _E7Callable(FirebaseFunctionsPlatform f, String? origin, String name, HttpsCallableOptions options)
      : super(f, origin, name, options, null);

  @override
  Future<dynamic> call([dynamic parameters]) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final c = HttpClient();
    try {
      final rq = await c.postUrl(Uri.parse('http://$_host:6190/alfit-89567/${functions.region}/$name'));
      rq.headers.contentType = ContentType.json;
      if (token != null) rq.headers.set('Authorization', 'Bearer $token');
      rq.add(utf8.encode(jsonEncode({'data': parameters})));
      final rs = await rq.close().timeout(options.timeout);
      final j = jsonDecode(await rs.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final err = j['error'] as Map<String, dynamic>?;
      if (err != null) {
        // ignore: invalid_use_of_protected_member
        throw FirebaseFunctionsException(
            code: (err['status'] as String? ?? 'INTERNAL').toLowerCase().replaceAll('_', '-'),
            message: err['message'] as String? ?? '',
            details: err['details']);
      }
      return j['result'];
    } on TimeoutException {
      // ignore: invalid_use_of_protected_member
      throw FirebaseFunctionsException(code: 'deadline-exceeded', message: 'deadline-exceeded');
    } on SocketException catch (e) {
      // ignore: invalid_use_of_protected_member
      throw FirebaseFunctionsException(code: 'unavailable', message: e.message);
    } finally {
      c.close();
    }
  }
}

Future<void> _appMain() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.useFirestoreEmulator(_host, 6171);
  await FirebaseStorage.instance.useStorageEmulator(_host, 6172);
  FirebaseFunctionsPlatform.instance = _E7Functions(null, 'us-central1');
  await FirebaseAuth.instance.useAuthEmulator(_host, 6174);
  ForeignRegisterHooks.pickAndOcr = () async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/e7_pick_${DateTime.now().millisecondsSinceEpoch}.png');
    final c = HttpClient();
    try {
      final rs = await (await c.getUrl(Uri.parse('http://$_host:6190/__e7/fixture/$_fixture'))).close();
      final b = <int>[];
      await for (final x in rs) {
        b.addAll(x);
      }
      await f.writeAsBytes(b);
    } finally {
      c.close();
    }
    try {
      return (path: f.path, result: await _realOcr(f.path));
    } catch (e) {
      debugPrint('E6OCR threw=${e.runtimeType}');
      return (path: f.path, result: null);
    }
  };
  debugPrint('E7APP 시작 — LOCAL 에뮬레이터 연결');
  // [.69] 운영 main.dart 와 같은 앱 시작 시 기기 토큰 폐기 이어받기.
  unawaited(FCMService().settlePendingRevoke());
  // [.68] 운영 main.dart 와 같은 로그아웃 이동 등록 — 이게 없으면 위에 올라간 화면(설정 등)에서 로그아웃해도
  //   그 화면이 남는다(.65 관찰 '사용자 없는 설정 화면'은 이 하네스 차이였다).
  setLoginRedirectCallback(() {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthWrapper()),
      (route) => false,
    );
  });
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ChangeNotifierProxyProvider<NotificationProvider, UserProvider>(
        create: (_) => UserProvider()..initialize(),
        update: (_, n, u) => u!..setNotificationProvider(n),
      ),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => NetworkProvider()),
      ChangeNotifierProvider(create: (_) => BadgeProvider()),
    ],
    child: Consumer<ThemeProvider>(
      builder: (context, theme, _) => MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: scaffoldMessengerKey,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
        theme: theme.theme,
        home: const AuthWrapper(),
      ),
    ),
  ));
}

Future<void> main() async {
  if (kReleaseMode) throw StateError('E6 LOCAL 진입점은 디버그 전용이다');
  WidgetsFlutterBinding.ensureInitialized();
  if (_mode == 'app') {
    await initializeDateFormatting('ko_KR', null);
    return _appMain();
  }
  await Firebase.initializeApp();
  // 화면이 직접 부르는 SDK 호출(약관 로딩 등)도 DEV 로 나가지 않게 전부 호스트로 돌린다.
  FirebaseFirestore.instance.useFirestoreEmulator(_host, 6171);
  await FirebaseStorage.instance.useStorageEmulator(_host, 6172);
  FirebaseFunctions.instanceFor(region: 'asia-northeast3').useFunctionsEmulator(_host, 6199);
  _installHooks();
  // ToastHelper 는 전역 navigatorKey 의 overlay 에 띄운다 — 실제 앱과 같은 키를 쓴다.
  runApp(MaterialApp(navigatorKey: navigatorKey, home: const _Menu()));
}
