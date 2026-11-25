// ignore_for_file: depend_on_referenced_packages, avoid_print
// [X1-a · 서비스 응답 키] 중간정산 요청 CF(callableRequestInterimSettlement)의 성공 응답 키 `settlementRequestId` 를
//   PayrollPaymentService.requestInterimSettlement 가 그대로 읽는지 실제 서비스로 본다(G1 판정 §6 · §9 · 감사148 §5 X1-a).
//   before = 현재 A(payroll_payment_service fabb863b) — DU_BEFORE_OBSERVE=x1a 일 때만 · strict(기본) = 후보 안 1(3e68cbf1).
//   서버 응답 근거 = functions/src/index.ts 5b128d71 :56013 {success:true, settlementRequestId} · :55955 already-exists 원문.
//   하네스 = transfer_processed_count_test(a465aa40)의 가짜 Firebase core + Pigeon CF 채널 대역,
//     DU554(du1_s071_myapps_stale_554_test 7bf7ce78)의 플랫폼 메시지 전수 관찰 · Firestore 차단 · HTTP 차단 틀.
//   범위: 서비스 반환값 · 예외 · 호출 수 · 보낸 값만. 화면(InterimSettlementRequestScreen)의 토스트 · pop(true) · 부모 재조회는 범위 밖.
//   서버 · 금액 · 이름(workerName/businessName 미전송 그대로) · 중복 안내(X1-b) 변경 0 — 보낸 값이 그대로인지도 단언한다.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/services/payroll_payment_service.dart';

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

const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
const _fn = 'callableRequestInterimSettlement';
const _region = 'asia-northeast3';

/// Firestore 쓰기 연산 — 하나라도 오면 fsw 로 센다(DU554 와 같은 목록).
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

/// 한 사례의 CF 응답. body 가 있으면 성공 응답(맵 그대로), 없으면 네이티브 플러그인과 같은 오류 봉투
///   ['firebase_functions', message, {code, message}] (cloud_functions 5.6.2 FlutterFirebaseFunctionsPlugin.kt:182–186 · :144–145).
class _Reply {
  _Reply.ok(Map<String, Object?> b)
      : body = b,
        code = null,
        message = null;
  _Reply.err(String c, String m)
      : body = null,
        code = c,
        message = m;
  final Map<String, Object?>? body;
  final String? code;
  final String? message;
}

/// 모든 플랫폼 메시지 관찰 — 대상 CF 1종만 사례 응답, 그 밖 CF · Firestore 는 차단 응답 + 기록, 나머지는 이름만 기록하고 응답 null.
class _Wire {
  _Wire(this.reply);
  final _Reply? reply;
  final calls = <Map<Object?, Object?>>[];
  final cfOther = <String>[];
  final fsWrites = <String>[];
  final fsOther = <String>[];
  final unexpected = <String>[];
  final harness = <String>[];

  Future<ByteData?>? route(String channel, MessageHandler? handler, ByteData? message) {
    if (channel == _cfChannel) return Future<ByteData?>.value(_cf(message));
    if (channel.startsWith('$_fsBase.')) return Future<ByteData?>.value(_fs(channel.substring(_fsBase.length + 1)));
    unexpected.add(channel);
    return null;
  }

  ByteData? _cf(ByteData? message) {
    const codec = StandardMessageCodec();
    try {
      final args = (codec.decodeMessage(message) as List).first as Map;
      final fn = args['functionName'].toString();
      final region = args['region'].toString();
      final r = reply;
      if (fn != _fn || region != _region || r == null) {
        cfOther.add('$fn@$region');
        return codec.encodeMessage(<Object?>['firebase_functions', 'x1a-blocked', <String, Object?>{'code': 'not-found', 'message': 'x1a-blocked'}]);
      }
      calls.add(Map<Object?, Object?>.from(args));
      final body = r.body;
      if (body != null) return codec.encodeMessage(<Object?>[body]);
      return codec.encodeMessage(<Object?>['firebase_functions', r.message, <String, Object?>{'code': r.code, 'message': r.message}]);
    } catch (e) {
      harness.add('cf $e');
      return codec.encodeMessage(<Object?>['firebase_functions', 'x1a-harness', <String, Object?>{'code': 'internal', 'message': 'x1a-harness'}]);
    }
  }

  ByteData? _fs(String op) {
    const codec = StandardMessageCodec();
    if (_fsWrites.contains(op)) {
      fsWrites.add(op);
    } else {
      fsOther.add(op);
    }
    return codec.encodeMessage(<Object?>['x1a-blocked', '$op 차단', null]);
  }
}

/// 외부 HTTP 차단 — 클라이언트 생성은 세고, 어떤 요청이든 기록하고 실패시킨다(DU554 와 같은 틀).
class _NoHttp extends HttpOverrides {
  final tries = <String>[];
  var clients = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    return _BlockedHttpClient(tries);
  }
}

class _BlockedHttpClient implements HttpClient {
  _BlockedHttpClient(this.tries);
  final List<String> tries;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    tries.add('HttpClient ${invocation.memberName}');
    throw const SocketException('X1A 관측 — 외부 HTTP 차단');
  }
}

/// 서비스 결과 — kind ∈ ok(반환 ID) · fx(FirebaseFunctionsException 코드) · type(TypeError — 응답 키 cast 실패) · other.
///   text = 예외의 toString() 원문(화면 IS:196 이 토스트 재료로 쓰는 값) — 기록만, 단언 0.
class _Outcome {
  _Outcome(this.kind, this.value, this.message, [this.text = '']);
  final String kind;
  final String value;
  final String message;
  final String text;
  String get key => '$kind:$value';
}

/// 한 사례 — 같은 입력을 두 모드에서 보내고, 모드별 기대 결과를 미리 고정한다.
class _Case {
  _Case(this.id, this.reply, this.wantBefore, this.wantStrict);
  final String id;
  final _Reply reply;
  final String wantBefore;
  final String wantStrict;
}

const _kId = 'isr-x1a-0001';
const _kOld = 'old-x1a-0001';
const _dupMsg = '이미 처리 대기 중인 중간정산 요청이 있습니다.'; // F:55955 원문
const _errMsg = 'INTERNAL'; // onCall 이 HttpsError 아닌 예외(예: 커밋 뒤 F:55975 사업장 읽기 실패)를 감쌀 때의 모양 [추론]

final _ok = _Case('OK', _Reply.ok({'success': true, 'settlementRequestId': _kId}), 'type:TypeError', 'ok:$_kId');
final _dup = _Case('DUP', _Reply.err('already-exists', _dupMsg), 'fx:already-exists', 'fx:already-exists');
final _err = _Case('ERR', _Reply.err('internal', _errMsg), 'fx:internal', 'fx:internal');
// 안 1(권고)은 옛 키만 온 응답을 성공으로 읽지 않는다. 안 2(호환)를 채택하면 wantStrict = 'ok:$_kOld' 로 바뀐다(README §2).
final _old = _Case('OLD', _Reply.ok({'success': true, 'requestId': _kOld}), 'ok:$_kOld', 'type:TypeError');

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == 'x1a';
final String _mode = _before ? 'before' : 'strict';

/// 보내는 값(화면 IS:179–190 이 넘기는 모양과 같은 형식의 시험값) — 서비스가 이 값을 그대로 보내는지 단언한다.
final DateTime _pStart = DateTime(2026, 11, 3);
final DateTime _pEnd = DateTime(2026, 11, 14);
const _reason = '생활비 x1a';
final Map<String, Object?> _wantParams = {
  'applicationId': 'app-x1a',
  'businessId': 'biz-x1a',
  'attendanceIds': ['att-x1a-1', 'att-x1a-2'],
  'requestedAmount': 200000,
  'netAmount': 180000,
  'requestReason': _reason,
  'periodStart': DateTime(2026, 11, 3).toIso8601String(),
  'periodEnd': DateTime(2026, 11, 14).toIso8601String(),
};

late final PayrollPaymentService _svc;
String? _halt;

void _out(String s) => print(s);

String _enc(String s) => s.isEmpty ? '-' : base64Url.encode(utf8.encode(s)).replaceAll('=', '');

String _psSha() {
  try {
    return sha256.convert(File('lib/services/payroll_payment_service.dart').readAsBytesSync()).toString().substring(0, 16);
  } catch (_) {
    return 'unreadable';
  }
}

Future<_Outcome> _invoke() async {
  try {
    final id = await _svc.requestInterimSettlement(
      applicationId: 'app-x1a',
      businessId: 'biz-x1a',
      attendanceIds: const ['att-x1a-1', 'att-x1a-2'],
      requestedAmount: 200000,
      netAmount: 180000,
      requestReason: _reason,
      periodStart: _pStart,
      periodEnd: _pEnd,
    );
    return _Outcome('ok', id, '');
  } on FirebaseFunctionsException catch (e) {
    return _Outcome('fx', e.code, e.message ?? '', e.toString());
  } on TypeError catch (e) {
    return _Outcome('type', 'TypeError', e.toString(), e.toString());
  } catch (e) {
    return _Outcome('other', e.runtimeType.toString(), e.toString(), e.toString());
  }
}

Future<void> _run(_Case c) async {
  if (_halt != null) fail('X1A-${c.id} 진입 0 — 앞 실패: $_halt');
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final w = _Wire(c.reply);
  final net = _NoHttp();
  final prevAll = m.allMessagesHandler;
  final prevHttp = HttpOverrides.current;
  m.allMessagesHandler = (channel, handler, message) => w.route(channel, handler, message);
  HttpOverrides.global = net;
  _Outcome o;
  try {
    o = await _invoke();
  } finally {
    m.allMessagesHandler = prevAll;
    HttpOverrides.global = prevHttp;
  }
  final want = _before ? c.wantBefore : c.wantStrict;
  final call = w.calls.isEmpty ? const <Object?, Object?>{} : w.calls.first;
  final params = Map<Object?, Object?>.from((call['parameters'] as Map?) ?? const {});
  final keys = params.keys.map((k) => k.toString()).toList()..sort();
  _out('X1A $_mode ${c.id} got=${o.key} want=$want calls=${w.calls.length} fn=${call['functionName']} region=${call['region']} '
      'timeout=${call['timeout']} luat=${call['limitedUseAppCheckToken']} keys=${keys.join(',')} cfx=${w.cfOther.length} '
      'fsw=${w.fsWrites.length} fso=${w.fsOther.length} http=${net.tries.length} hcl=${net.clients} unexpected=${w.unexpected.length} '
      'harness=${w.harness.length} msg64=${_enc(o.message)} ts1=${_enc(o.text.split('\n').first)} tsl=${o.text.isEmpty ? 0 : o.text.split('\n').length}');

  expect(w.harness, isEmpty, reason: 'X1A-${c.id} 하네스 오류 ${w.harness}');
  // 격리 — 대상 CF 1회 · 자동 재시도 0 · 다른 CF 0 · Firestore 쓰기 0 · HTTP 0
  expect(w.calls.length, 1, reason: 'X1A-${c.id} 대상 CF 호출 1회(재시도 0)');
  expect(w.cfOther, isEmpty, reason: 'X1A-${c.id} 다른 CF 0');
  expect(w.fsWrites, isEmpty, reason: 'X1A-${c.id} Firestore 쓰기 0');
  expect(net.tries, isEmpty, reason: 'X1A-${c.id} HTTP 0');
  // 보낸 값 — 이 셀이 이름 · 금액 · 기간 payload 를 바꾸지 않았다(X4 · X7 분리)
  expect(call['functionName'], _fn);
  expect(call['region'], _region);
  expect(call['timeout'], 30000);
  expect(params, equals(_wantParams), reason: 'X1A-${c.id} 보낸 값 그대로');
  expect(params.containsKey('workerName') || params.containsKey('businessName'), isFalse, reason: 'X1A-${c.id} 이름 전송 추가 0(X4 분리)');
  // 결과 — 모드별 고정 기대
  expect(o.key, want, reason: 'X1A-${c.id} $_mode 결과');
  if (o.kind == 'fx') {
    expect(o.message, c.reply.message, reason: 'X1A-${c.id} 서버 문구를 서비스가 바꾸지 않는다(X1-b 안내는 별도)');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final w = _Wire(null);
    final net = _NoHttp();
    final prevAll = m.allMessagesHandler;
    final prevHttp = HttpOverrides.current;
    m.allMessagesHandler = (channel, handler, message) => w.route(channel, handler, message);
    HttpOverrides.global = net;
    try {
      FirebasePlatform.instance = _FakeCore();
      await Firebase.initializeApp();
      // Firebase 초기화 뒤에 만든다(생성자가 FirebaseFirestore.instance · FirebaseFunctions.instanceFor 를 잡는다 — 싱글턴).
      _svc = PayrollPaymentService();
    } finally {
      m.allMessagesHandler = prevAll;
      HttpOverrides.global = prevHttp;
    }
    _out('X1A setup mode=$_mode before_env=${Platform.environment['DU_BEFORE_OBSERVE'] ?? '(unset)'} ps=${_psSha()} '
        'cf=${w.calls.length + w.cfOther.length} fsw=${w.fsWrites.length} fso=${w.fsOther.length} unexpected=${w.unexpected.length} '
        'http=${net.tries.length} hcl=${net.clients} un64=${_enc(w.unexpected.join('|'))}');
    final initOk = w.calls.isEmpty && w.cfOther.isEmpty && w.fsWrites.isEmpty && net.tries.isEmpty && w.harness.isEmpty;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · Firestore 쓰기 0 · HTTP 0');
  });

  test('X1A-OK 성공 응답 settlementRequestId — 서비스가 요청 ID 를 돌려준다', () => _run(_ok));
  test('X1A-DUP already-exists — 예외 그대로 전파 · 재호출 0', () => _run(_dup));
  test('X1A-ERR internal — 예외 그대로 전파 · 재호출 0', () => _run(_err));
  test('X1A-OLD 옛 키 requestId 만 온 응답 — 안 1 은 성공으로 읽지 않는다', () => _run(_old));
}
