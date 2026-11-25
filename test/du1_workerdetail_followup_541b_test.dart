// ignore_for_file: depend_on_referenced_packages
// [DU541b · 표시만] 근무자 상세 창(WorkerDetailDialog) 보완 — 감사138 §3 R1–R8(R6 · R10 유지 · R9 하위 창은 다음 셀).
//   before = 현재 A(worker_detail_dialog 9fbdf4b2 · DU541 채택판) 기록 전용 · strict = 후보(a9f45df1).
//   하네스 = DU541 r2(du1_workerdetail_color_541_test 의 서류 검토 대역 + 플랫폼 채널 전수 관찰 + 요청 차단 HttpClient) 그대로 · 이름 · 토큰 · 상태만 바꿈.
//   상태 9: READY · DOCS · FAIL · WARN(대기 지원자 · DU541 회귀) · CONFW · CONFC(확정 · DU541 회귀) · VOID(계약 무효 + 리뷰 1) · LONG(장기 · 출근 기록 있음) · CPEND(계약 대기).
//   누르는 것 0 — ensureVisible(끌기)만. rect 는 끌어 넣은 뒤(또는 늘 보이는 하단 칸)만 재고 보이는 칸 안인지 함께 적는다.
//   기본 skip — TB before/du541b-tb/DU_BEFORE_OBSERVE=541 · TA after/du541b-ta/없음.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/services/applicant_document_review_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/widgets/dialogs/worker_detail_dialog.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

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

const _biz = 'biz1';
const _bizName = '테스트 사업장';
const _worker = 'w9';

/// 소유자(BUSINESS_ADMIN) — DU541 r2 _Owner 와 같다. 이 창은 checkForBusiness(확정 권한) · checkCurrentBusiness(급여 · 계약 권한)를 부른다.
class _Owner extends UserProvider {
  final watched = <String>[];
  @override
  UserModel? get currentUser => UserModel(
      uid: 'admin1', username: 'admin1', name: '김관리', email: 'admin1@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const [_biz], sealBase64: 'seal');
  @override
  bool get isSubAdmin => false;
  @override
  String? get effectiveBusinessId => null;
  @override
  bool get subAdminPermissionsLoaded => true;
  @override
  PermissionWatchState get currentBusinessPermissionHealth => PermissionWatchState.verified;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForAnyBusiness(bool Function(MemberPermissions p) check, {required bool whenUnknown}) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  VoidCallback watchBusinessPermissions(String businessId) {
    watched.add(businessId);
    return () {};
  }
}

/// 서류 검토 대역 — admin_document_review_ux_test · auto_ready_selective_view_test 의 _FakeReview 와 같은 방식(성공 = 서버 응답 지도 · 실패 = 예외).
class _FakeReview extends Fake implements ApplicantDocumentReviewService {
  _FakeReview(this.result);
  final Object result;
  int loads = 0;
  @override
  Future<ApplicantDocumentReview> load({required String applicationId, required String businessId}) async {
    loads++;
    final r = result;
    if (r is Exception) throw r;
    return ApplicantDocumentReview.fromMap(r as Map<String, dynamic>);
  }
}

/// callableGetApplicantDocumentReview 응답 모양(두 기존 시험의 _map · _autoReady 와 같은 키).
Map<String, dynamic> _docMap({bool ready = false, String state = 'ID_UNASSESSED', String? consentBlock, bool hasBankbook = true}) => <String, dynamic>{
      'workerUid': _worker,
      'canReviewDocuments': true,
      'consentBlock': consentBlock,
      'versions': <String, dynamic>{'id': 2, 'bankbook': 1, 'account': 1},
      'readiness': <String, dynamic>{'ready': false, 'idDecision': 'NOT_REVIEWED', 'bankDecision': 'NOT_REVIEWED', 'idStale': false},
      'documents': <String, dynamic>{'hasIdCard': true, 'hasBankbook': hasBankbook},
      'bank': <String, dynamic>{'bankName': 'QA테스트은행', 'accountNumber': '0000000000', 'accountHolder': '큐에이일'},
      'matchingReadiness': <String, dynamic>{'ready': ready, 'state': state, 'reason': ready ? null : '신분증 확인이 필요합니다. 지원자 상세에서 확인해주세요.'},
    };

/// 사례별 서류 검토 — 확정자(CONFW · CONFC · VOID · LONG · CPEND)는 이 창이 서류 검토를 읽지 않는다(null).
Object? _docFor(String kind) => switch (kind) {
      'READY' => _docMap(ready: true, state: 'READY_AUTO'),
      'DOCS' => _docMap(consentBlock: ApplicantDocumentReview.serverConsentMissingText, hasBankbook: false),
      'FAIL' => Exception('du541b local failure'),
      'WARN' => _docMap(),
      _ => null,
    };

const _confKinds = <String>{'CONFW', 'CONFC', 'VOID', 'LONG', 'CPEND'};
bool _isConf(String kind) => _confKinds.contains(kind);

/// 근로자 — WARN 만 이력(노쇼 2 · 지각 1 · 평점 3.5 · 재고용 50% · 이용 제한). 확정자는 급여계좌 · 통장사본 등록.
UserModel _user(String kind) {
  final warn = kind == 'WARN';
  final conf = _isConf(kind);
  return UserModel(
    uid: _worker, username: _worker, name: '큐에이일', email: 'w9@test.local', role: UserRole.USER,
    gender: '여성', birthDate: DateTime(1995, 3, 2), contactPhone: '010-0000-0000',
    bankName: conf ? 'QA테스트은행' : null, accountNumber: conf ? '0000000000' : null, accountHolder: conf ? '큐에이일' : null,
    bankbookImagePath: conf ? 'users/w9/bankbook.jpg' : null,
    totalWorkDays: warn ? 12 : 0, averageRating: warn ? 3.5 : 0.0, reviewCount: warn ? 4 : 0, rehireRate: warn ? 0.5 : 0.0,
    recentNoShowCount: warn ? 2 : 0, recentLateCount: warn ? 1 : 0, isBlacklisted: warn,
  );
}

/// 지원서 한 건 — 대기(PENDING) · 확정(CONFIRMED) · 계약 대기(CONTRACT_PENDING · CPEND). LONG 만 장기(슬롯 없음 · 종료일). DOCS 만 서류 열람 동의 전.
ApplicationModel _application(String kind) {
  final conf = _isConf(kind);
  final long = kind == 'LONG';
  final consent = kind != 'DOCS';
  return ApplicationModel(
    id: 'app1', uid: _worker, toId: 'to1', slotId: long ? null : 'slot1', wdId: 'wd1', businessId: _biz, businessName: _bizName, toTitle: '테스트 공고',
    selectedWorkType: 'QA 분류', startTime: '10:00', endTime: '11:00', wage: 12000, wageType: 'hourly',
    status: kind == 'CPEND' ? AppStatus.contractPending : conf ? AppStatus.confirmed : AppStatus.pending,
    workDate: DateTime.utc(2030, 1, 14, 15), workEndDate: long ? DateTime.utc(2030, 4, 14, 15) : null,
    applicationType: long ? AppType.longTerm : null, appliedAt: DateTime.utc(2030, 1, 10, 1),
    confirmedAt: conf ? DateTime.utc(2030, 1, 11, 2) : null,
    documentAccessConsentGiven: consent, documentAccessConsentVersion: consent ? '2026-09-18-v3' : null,
  );
}

/// 사례별 계약서 상태 — 서명 대기(CONFW · CPEND) · 서명 완료(CONFC · LONG) · 무효(VOID).
String _contractStatus(String kind) => switch (kind) {
      'CONFC' || 'LONG' => 'completed',
      'VOID' => 'voided',
      _ => 'pending_worker',
    };

/// callableGetContractsByBiz 의 계약서 한 건(EmploymentContractModel.fromMap 이 요구하는 snapshot · createdAt 포함 · DU541 r2 와 같다).
Map<String, Object?> _contract(String status) => <String, Object?>{
      'id': 'ct1', 'applicationId': 'app1', 'businessId': _biz, 'workerId': _worker, 'isLongTerm': false, 'toId': 'to1', 'workDetailId': 'wd1',
      'status': status,
      'snapshot': <String, Object?>{'businessName': _bizName, 'workerName': '큐에이일', 'workType': 'QA 분류'},
      'createdAt': <String, Object?>{'_seconds': DateTime.utc(2030, 1, 11, 3).millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0},
    };

/// callableGetTaxIdentityReview 응답(TaxIdentityReview.fromMap 의 키) — 확인 전(CONFW · CPEND) · 확인 완료(CONFC · VOID · LONG).
Map<String, Object?> _tax(bool done) => <String, Object?>{
      'state': done ? 'REVIEWED_OK' : 'UNREVIEWED', 'valid': true, 'idDocumentVersion': 1, 'taxIdentityFingerprint': 'fp1', 'hasIdDocument': true,
      'reviewedAtMs': done ? DateTime.utc(2030, 1, 12).millisecondsSinceEpoch : null, 'officialName': '큐에이일', 'hasTaxIdentity': false,
    };

/// callableGetReviewsForUser 의 공개 리뷰 한 건(MonthlyReviewModel.tryFromMap 필수 키 reviewYear · reviewMonth · createdAt) — VOID 만.
Map<String, Object?> _review() => <String, Object?>{
      'id': 'rv1', 'reviewType': 'ADMIN_TO_USER', 'businessId': _biz, 'businessName': _bizName, 'targetUserId': _worker,
      'reviewYear': 2030, 'reviewMonth': 1, 'rating': 4, 'isPublished': true,
      'createdAt': <String, Object?>{'_seconds': DateTime.utc(2030, 2, 3, 3).millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0},
    };

const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';

/// 첫 화면이 부르는 읽기 CF(서비스 소스 그대로) — 이 밖의 CF 이름은 차단하고 센다.
const _readFns = <String>{
  'callableGetApplicationsByBiz', 'callableGetMonthlyReviewsForUser', 'callableGetReviewsForUser', 'callableCheckIdCardAccess',
  'callableAdminHasAttendanceRecord', 'callableGetContractsByBiz', 'callableGetTaxIdentityReview',
};

/// Firestore 쓰기 연산 — 하나라도 오면 fsw 로 센다.
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

/// [DU541 r2 와 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널.
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du541b.fake.auth.';
const _authListeners = ['registerIdTokenListener', 'registerAuthStateListener'];

/// 원래 경로로 보내는 Flutter 기반 채널과 이유.
const _frameworkAllow = <String, String>{
  'flutter/assets': 'AssetBundle(아이콘 글꼴 · 이미지 매니페스트) 읽기',
  'flutter/platform': 'MaterialApp Title · SystemSound/Haptic',
  'flutter/navigation': '루트 Navigator 경로 보고',
  'flutter/mousecursor': 'MouseRegion 커서 갱신(시험 포인터)',
  'flutter/restoration': 'RootRestorationScope 상태 복원 조회',
  'flutter/keyboard': 'HardwareKeyboard 상태 동기화',
  'flutter/accessibility': '의미 트리/알림 전달',
};

/// 모든 플랫폼 메시지 관찰 — 읽기 CF 7종은 대역 응답, 그 밖 CF 와 Firestore 는 차단 응답 + 기록,
///   기반 채널은 원래 경로, 나머지는 이름을 기록하고 응답 null. 예외를 삼키지 않는다 — 수는 줄로 남긴다.
class _Wire {
  _Wire(this.kind);

  /// 사례 이름 — 확정자만 계약서 · 세무 · 출근 기록 응답이 의미가 있다(대기 지원자 사례는 부르지 않는다).
  final String kind;
  final unexpected = <String>[];
  final blocked = <String>[];
  final fsWrites = <String>[];
  final fsOther = <String>[];
  final auth = <String>[];
  final harness = <String>[];
  final calls = <String, int>{};
  void _hit(String k) => calls[k] = (calls[k] ?? 0) + 1;

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
    if (channel == _cfChannel) return Future<ByteData?>.value(_cf(message));
    if (channel.startsWith('$_fsBase.')) return Future<ByteData?>.value(_fs(channel.substring(_fsBase.length + 1)));
    for (final name in _authListeners) {
      if (channel == '$_authBase$name' || channel == '$_authFake$name') {
        auth.add(name);
        return handler?.call(message);
      }
    }
    if (_frameworkAllow.containsKey(channel)) {
      return handler != null ? handler(message) : m.delegate.send(channel, message);
    }
    unexpected.add(channel);
    return null;
  }

  ByteData? _cf(ByteData? message) {
    const codec = StandardMessageCodec();
    try {
      final args = (codec.decodeMessage(message) as List).first as Map;
      final fn = args['functionName'].toString();
      final region = args['region'].toString();
      if (region != 'asia-northeast3' || !_readFns.contains(fn)) {
        blocked.add('fn $fn@$region');
        return codec.encodeMessage(<Object?>['not-found', 'du541b-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      _hit(fn);
      final Object data = switch (fn) {
        'callableGetApplicationsByBiz' => <String, Object?>{'applications': const <Object?>[]},
        'callableGetMonthlyReviewsForUser' => <String, Object?>{'items': const <Object?>[]},
        'callableGetReviewsForUser' => <String, Object?>{'reviews': kind == 'VOID' ? <Object?>[_review()] : const <Object?>[]},
        'callableCheckIdCardAccess' => <String, Object?>{'request': null},
        'callableAdminHasAttendanceRecord' => <String, Object?>{'hasRecord': kind == 'LONG'},
        'callableGetContractsByBiz' => <String, Object?>{'contracts': <Object?>[_contract(_contractStatus(kind))]},
        _ => _tax(kind == 'CONFC' || kind == 'VOID' || kind == 'LONG'),
      };
      return codec.encodeMessage(<Object?>[data]);
    } catch (e) {
      harness.add('cf $e');
      return codec.encodeMessage(<Object?>['internal', 'du541b-harness', null]);
    }
  }

  ByteData? _fs(String op) {
    const codec = FirebaseFirestoreHostApi.codec;
    try {
      if (_fsWrites.contains(op)) {
        fsWrites.add(op);
      } else {
        fsOther.add(op);
      }
      return codec.encodeMessage(<Object?>['du541b-blocked', '$op 차단', null]);
    } catch (e) {
      harness.add('fs $op $e');
      return null;
    }
  }
}

/// 외부 HTTP 차단 — 클라이언트 객체 생성은 허용하고 센다(ContractService 생성자가 서명 이미지용 http.Client() 를 만든다 · 요청 0),
///   실제 요청(모든 HttpClient 멤버 호출)은 [tries] 에 이름을 기록하고 실패시킨다(DU541 r2 수리 그대로).
class _NoHttp extends HttpOverrides {
  final tries = <String>[];
  var clients = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    return _BlockedHttpClient(tries);
  }
}

/// 요청을 하나도 보내지 않는 HttpClient — 어떤 멤버든 부르면 기록하고 SocketException.
class _BlockedHttpClient implements HttpClient {
  _BlockedHttpClient(this.tries);
  final List<String> tries;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    tries.add('HttpClient ${invocation.memberName}');
    throw const SocketException('DU541b 관측 — 외부 HTTP 차단');
  }
}

Future<void> _loadFonts() async {
  Future<ByteData> b(String p) => File(p).readAsBytes().then((x) => ByteData.view(x.buffer));
  for (final fam in const ['NotoSansKR', 'Roboto']) {
    await (FontLoader(fam)
          ..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))
          ..addFont(b('assets/fonts/NotoSansKR-Bold.ttf')))
        .load();
  }
  await (FontLoader('FlutterTest')..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))).load();
  await (FontLoader('MaterialIcons')
        ..addFont(b('C:/Users/kug02/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')))
      .load();
}

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _enc(String s) => s.isEmpty ? '-' : base64Url.encode(utf8.encode(s)).replaceAll('=', '');

String _hex(Color col) {
  String h(double x) => (x * 255).round().toRadixString(16).padLeft(2, '0');
  return '${h(col.a)}${h(col.r)}${h(col.g)}${h(col.b)}';
}

/// WCAG 대비 — [fg] 글자 · [bg] 불투명 바탕.
double _contrast(Color fg, Color bg) {
  final a = Color.alphaBlend(fg, bg).computeLuminance();
  final b = bg.computeLuminance();
  final hi = a > b ? a : b;
  final lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

/// 값이 모두 같으면 그 값, 아니면 '-'.
String _one(Iterable<String> xs) {
  final s = xs.toSet();
  return s.length == 1 ? s.first : '-';
}

/// 시각 오류 수집 — 넘침은 원문 + 위치, 그 밖 framework 오류는 원문.
class _Seen {
  final overflows = <String>[];
  final other = <String>[];

  void add(FlutterErrorDetails d) {
    final m = d.exceptionAsString();
    if (m.contains('overflowed')) {
      final full = d.toString();
      final k = full.indexOf('The relevant error-causing widget was');
      final loc = k < 0
          ? ''
          : full.substring(k).split('\n').skip(1).where((l) => l.trim().isNotEmpty).take(2).map((l) => l.trim()).join(' ');
      overflows.add('${m.split('\n').first} @ $loc');
    } else {
      other.add(m);
    }
  }
}

/// [f](글)에서 가장 가까운 Container 의 면 색(BoxDecoration.color · 없으면 Container.color · 그것도 없으면 투명).
Color _faceOf(WidgetTester t, Finder f) {
  final box = t.widget<Container>(find.ancestor(of: f, matching: find.byType(Container)).first);
  final d = box.decoration;
  if (d is BoxDecoration) return d.color ?? Colors.transparent;
  return box.color ?? Colors.transparent;
}

/// [f](글)에서 가장 가까운 Container 의 테두리 색(BoxDecoration.border 가 Border 일 때 윗변 색) — 테두리가 없으면 '-'.
String _edgeOf(WidgetTester t, Finder f) {
  final d = t.widget<Container>(find.ancestor(of: f, matching: find.byType(Container)).first).decoration;
  final b = d is BoxDecoration ? d.border : null;
  return b is Border ? _hex(b.top.color) : '-';
}

/// Text 하나의 글자색(style 에 색이 없으면 검정으로 적는다).
Color _fgOf(WidgetTester t, Finder f) => t.widget<Text>(f).style?.color ?? Colors.black;

/// [box] 안의 Icon 이 정확히 하나면 그 색, 아니면 '-'.
String _iconIn(WidgetTester t, Finder box) {
  final ics = find.descendant(of: box, matching: find.byType(Icon), skipOffstage: true).evaluate().toList();
  if (ics.length != 1) return '-';
  final col = (ics.first.widget as Icon).color;
  return col == null ? '-' : _hex(col);
}

typedef _Ink = ({int n, String face, String fg, bool cr});

/// 글 하나([f]) — 개수 · 가장 가까운 Container 면 · 글 색 · 대비(면을 흰 바탕 위에 합성). 하나가 아니면 '-'.
_Ink _inkOf(WidgetTester t, Finder f) {
  final n = f.evaluate().length;
  if (n != 1) return (n: n, face: '-', fg: '-', cr: false);
  final faceC = _faceOf(t, f);
  final fgC = _fgOf(t, f);
  return (n: n, face: _hex(faceC), fg: _hex(fgC), cr: _contrast(fgC, Color.alphaBlend(faceC, Colors.white)) >= 4.5);
}

typedef _Cell = ({int n, String face, String icon, String lab, String num, bool cr});

/// 근무 통계 한 칸([label]) — 칸 면 · 아이콘 · 라벨 글 · 숫자 글 색과 대비(라벨/칸 면 · 숫자/칸 면). 위젯 값만 읽는다(rect 0).
_Cell _cell(WidgetTester t, Finder dlg, String label) {
  final labF = find.descendant(of: dlg, matching: find.text(label), skipOffstage: true);
  final n = labF.evaluate().length;
  if (n != 1) return (n: n, face: '-', icon: '-', lab: '-', num: '-', cr: false);
  final box = find.ancestor(of: labF, matching: find.byType(Container)).first;
  final faceC = _faceOf(t, labF);
  final labC = _fgOf(t, labF);
  final icon = _iconIn(t, box);
  final texts = find.descendant(of: box, matching: find.byType(Text), skipOffstage: true).evaluate().map((e) => e.widget as Text).toList();
  if (texts.length != 2) return (n: n, face: _hex(faceC), icon: icon, lab: _hex(labC), num: '-', cr: false);
  final numC = texts.first.style?.color ?? Colors.black;
  final under = Color.alphaBlend(faceC, Colors.white);
  final cr = _contrast(labC, under) >= 4.5 && _contrast(numC, under) >= 4.5;
  return (n: n, face: _hex(faceC), icon: icon, lab: _hex(labC), num: _hex(numC), cr: cr);
}

typedef _Sect = ({bool ok, String bar, String icon, bool cr});

/// 구역 머리 하나([title]) — 제목 글의 가장 가까운 Row 안 막대(Container 1) 면 색 · 기능 아이콘(Icon 1) 색 · 아이콘/흰 대비. 위젯 값만(rect 0).
_Sect _sect(WidgetTester t, Finder dlg, String title) {
  final tf = find.descendant(of: dlg, matching: find.text(title), skipOffstage: true);
  if (tf.evaluate().length != 1) return (ok: false, bar: '-', icon: '-', cr: false);
  final rowF = find.ancestor(of: tf, matching: find.byType(Row)).first;
  final boxes = find.descendant(of: rowF, matching: find.byType(Container), skipOffstage: true).evaluate().toList();
  final ics = find.descendant(of: rowF, matching: find.byType(Icon), skipOffstage: true).evaluate().toList();
  if (boxes.length != 1 || ics.length != 1) return (ok: false, bar: '-', icon: '-', cr: false);
  final d = (boxes.first.widget as Container).decoration;
  final barC = d is BoxDecoration ? d.color : null;
  final icC = (ics.first.widget as Icon).color;
  if (barC == null || icC == null) return (ok: false, bar: '-', icon: '-', cr: false);
  return (ok: true, bar: _hex(barC), icon: _hex(icC), cr: _contrast(icC, Colors.white) >= 4.5);
}

bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

/// 버튼 하나가 끌기 없이 보이고 눌리는가 — 창 상자 ∩ 화면(∩ 가까운 Scrollable 이 있으면 그 칸) 안 + 중심 hit(DU541 r2 와 같은 식 · 누르지 않는다).
({bool vis, bool hit, Rect r}) _tapNow(WidgetTester t, Finder f, Finder dlg, Rect screen) {
  final boxF = find.descendant(of: dlg, matching: find.byType(Dialog), skipOffstage: true);
  var area = boxF.evaluate().isEmpty ? screen : t.getRect(boxF.first).intersect(screen);
  final scF = find.ancestor(of: f, matching: find.byType(Scrollable));
  final nSc = scF.evaluate().length;
  if (nSc > 0) area = area.intersect(t.getRect(scF.first));
  final r = t.getRect(f);
  final vis = _inside(r, area);
  final hit = t.hitTestOnBinding(r.center).path.any((x) => identical(x.target, t.renderObject(f)));
  return (vis: vis, hit: hit, r: r);
}

final String _wantWhite = _hex(Colors.white);
final String _wantNone = _hex(Colors.transparent);
final String _wantLine = _hex(AppColors.border);
final String _wantText1 = _hex(AppColors.textPrimary);
final String _wantText2 = _hex(AppColors.textSecondary);
final String _wantGrey50 = _hex(AppColors.grey50);
final String _wantGrey100 = _hex(AppColors.grey100);
final String _wantGrey600 = _hex(AppColors.grey600);
final String _wantBrand = _hex(AppColors.brand);
final String _wantBrand8 = _hex(AppColors.brand.withValues(alpha: 0.08));
final String _wantWarnBg = _hex(AppColors.warningBg);
final String _wantWarnDark = _hex(AppColors.warningDark);
final String _wantErrBg = _hex(AppColors.errorBg);
final String _wantErrDark = _hex(AppColors.errorDark);
final String _wantSuccBg = _hex(AppColors.successBg);
final String _wantSuccDark = _hex(AppColors.successDark);
final String _wantConfBg = _hex(AppColors.confirmedBg);
final String _wantConfDark = _hex(AppColors.confirmedDark);

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
const _cases = <({String id, int shots})>[
  (id: 'READY', shots: 1), (id: 'DOCS', shots: 1), (id: 'FAIL', shots: 2), (id: 'WARN', shots: 2), (id: 'CONFW', shots: 2), (id: 'CONFC', shots: 2),
  (id: 'VOID', shots: 3), (id: 'LONG', shots: 1), (id: 'CPEND', shots: 2),
];

/// 글 원문(대상 소스 · 서비스 소스 그대로 — mkcell 이 base · 후보에서 확인한다).
const _statLabels = ['총 근무', '평균 평점', '노쇼(90일)', '지각(90일)'];
const _sectTitles = ['기본 정보', '근무 통계', '최근 리뷰'];
const _bannerPart = <String, String>{'READY': '자동 대조로 일치해 확정할 수 있어요', 'DOCS': '서류 열람에 동의하면', 'WARN': '[확인 완료]를 누르면 확정할 수 있어요'};
const _consentPart = '서류 열람에 동의하지 않아';
const _retryText = '다시 불러오기';
const _blockText = '이용 제한 근무자';
const _rehireLabel = '재고용 추천률';
const _rehirePct = '50%';
const _rehireCnt = '(4건)';
const _cbandTitle = <String, String>{'CONFW': '근무자 서명 대기 중', 'CONFC': '계약서 서명 완료', 'CPEND': '근무자 서명 대기 중'};
const _cbandSub = '근무자에게 서명 요청 알림이 발송되었습니다';
const _taxLabel = <String, String>{'CONFW': '확인 필요', 'CONFC': '확인 완료'};
const _taxBtn = <String, String>{'CONFW': '신분증 확인', 'CONFC': '다시 보기'};
const _cancelKinds = <String>{'CONFW', 'CONFC', 'VOID', 'CPEND'};
const _cancelText = '확정취소';
const _voidText = '계약 무효 처리됨';
const _fixText = '고정근무 관리';

/// 머리 상태 칩 글 — 대기 지원자 '대기중' · 계약 대기 '계약 대기' · 그 밖 확정자 '확정'.
String _badgeText(String kind) => kind == 'CPEND' ? '계약 대기' : _isConf(kind) ? '확정' : '대기중';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '541';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du541b-tb' && _env['DU_BEFORE_OBSERVE'] == '541') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du541b-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  setUpAll(() async {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final wire = _Wire('SETUP');
    final net = _NoHttp();
    final prevAll = m.allMessagesHandler;
    final prevHttp = HttpOverrides.current;
    m.allMessagesHandler = (channel, handler, message) => wire.route(m, channel, handler, message);
    HttpOverrides.global = net;
    try {
      FirebasePlatform.instance = _FakeCore();
      await Firebase.initializeApp();
      await initializeDateFormatting('ko_KR');
      await _loadFonts();
      // FirebaseAuth 생성 때의 두 listener 등록 채널 모의(이벤트 0 · 로그인 상태 불변) — 창이 읽지 않으면 쓰이지 않는다.
      const codec = StandardMessageCodec();
      for (final name in _authListeners) {
        m.setMockMessageHandler('$_authBase$name', (_) async => codec.encodeMessage(<Object?>['$_authFake$name']));
        m.setMockMethodCallHandler(MethodChannel('$_authFake$name'), (_) async => null);
      }
    } finally {
      m.allMessagesHandler = prevAll;
      HttpOverrides.global = prevHttp;
    }
    final nCf = wire.calls.length + wire.blocked.length;
    final nUnexp = wire.unexpected.length;
    final nHttp = net.tries.length;
    _out('R541b setup init cf=$nCf unexpected=$nUnexp http=$nHttp hcl=${net.clients} auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S919WF-${v.id}-${c.id} 근무자 상세 창 보완 — 구역 머리 · 재고용 · 서명 대기 · 무효 · 별점 · 고정근무 관리 · 계약 대기', (t) async {
        final tok = 'S919WF-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');

        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final wire = _Wire(c.id);
        final net = _NoHttp();
        final doc = _docFor(c.id);
        final fake = doc == null ? null : _FakeReview(doc);
        final prevAll = messenger.allMessagesHandler;
        final prevHttp = HttpOverrides.current;
        final prevOnError = FlutterError.onError;
        ApplicantDocumentReviewService.debugOverride = fake;
        messenger.allMessagesHandler = (channel, handler, message) => wire.route(messenger, channel, handler, message);
        HttpOverrides.global = net;
        addTearDown(() {
          messenger.allMessagesHandler = prevAll;
          HttpOverrides.global = prevHttp;
          FlutterError.onError = prevOnError;
          ApplicantDocumentReviewService.debugOverride = null;
        });
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final screen = Offset.zero & Size(v.w, v.h);
        final mode = _before ? 'before' : 'strict';
        _out('D541 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        final owner = _Owner();
        final isB = v.id == 'B';
        final conf = _isConf(c.id);
        Object? failure;
        StackTrace? failureSt;
        var shots = 0;
        var raw = '';
        try {
          FlutterError.onError = seen.add;
          final key = GlobalKey();
          await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
            value: owner,
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                navigatorKey: navigatorKey,
                theme: RoleTheme.businessAdminTheme,
                locale: const Locale('ko', 'KR'),
                supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder: (ctx, child) =>
                    MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: Scaffold(
                  body: WorkerDetailDialog(
                    key: UniqueKey(),
                    user: _user(c.id),
                    application: _application(c.id),
                    businessId: _biz,
                    isConfirmed: conf,
                    showApprovalButtons: !conf,
                  ),
                ),
              ),
            ),
          ));
          for (var i = 0; i < 40; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          final dlg = find.byType(WorkerDetailDialog);
          final nDlg = dlg.evaluate().length;
          need('창 1', nDlg == 1, '개수 $nDlg');

          Future<void> shot(String id, String state) async {
            _out('D541 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          Future<void> settle() async {
            for (var i = 0; i < 10; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
          }

          // 그려진 글 집합(보이는 글 기준 · 숫자는 # 으로). 기록용: TB · TA 의 set 이 같아야 한다(글 변경 0 — 손 대조).
          final words = <String>{};
          for (final e in find.descendant(of: dlg, matching: find.byType(Text), skipOffstage: true).evaluate()) {
            final d = (e.widget as Text).data;
            if (d != null && d.isNotEmpty) words.add(visibleText(d).replaceAll(RegExp(r'\d+'), '#'));
          }
          final wordList = words.toList()..sort();
          _out('D541 $tok att txt n=${wordList.length} set=${_enc(wordList.join('|'))}');

          // ① 머리 상태 칩(모든 사례) — 대기 지원자 '대기중' · 확정 '확정' · 계약 대기 '계약 대기'(R8).
          final badgeF = find.descendant(of: dlg, matching: find.text(_badgeText(c.id)), skipOffstage: true);
          final bg = _inkOf(t, badgeF);
          _out('D541 $tok att badge n=${bg.n} face=${bg.face} fg=${bg.fg} cr45=${bg.cr}');
          need('상태 칩 1', bg.n == 1, '개수 ${bg.n}');
          final bgRaw = 'badge ${bg.face}/${bg.fg} cr ${bg.cr}';
          if (!_before) {
            final wantFace = c.id == 'CPEND' ? _wantConfBg : conf ? _wantSuccBg : _wantWarnBg;
            final wantFg = c.id == 'CPEND' ? _wantConfDark : conf ? _wantSuccDark : _wantWarnDark;
            chk(c.id == 'CPEND' ? 'strict 계약 대기 칩 = 중앙 confirmedBg/confirmedDark 짝(R8)' : 'strict 상태 칩 = 옅은 짝 면 + 진한 짝 글(DU541 그대로)',
                bg.face == wantFace && bg.fg == wantFg, bgRaw);
            chk('strict 상태 칩 대비 ≥4.5', bg.cr, bgRaw);
          }

          // ② 근무 통계 4칸(모든 사례 · DU541 그대로) — 면 · 아이콘 · 라벨 · 숫자.
          final cells = [for (final l in _statLabels) _cell(t, dlg, l)];
          final nCells = cells.where((x) => x.n == 1).length;
          final stFace = _one(cells.map((x) => x.face));
          final stIcon = _one(cells.map((x) => x.icon));
          final stLab = _one(cells.map((x) => x.lab));
          final stCr = cells.every((x) => x.cr);
          _out('D541 $tok att stats n=$nCells face=$stFace icon=$stIcon lab=$stLab n0=${cells[0].num} n1=${cells[1].num} n2=${cells[2].num} n3=${cells[3].num} cr45=$stCr');
          need('근무 통계 4칸', nCells == 4, 'n $nCells');
          final stRaw = 'face $stFace icon $stIcon lab $stLab num ${cells.map((x) => x.num).join('/')} cr $stCr';
          raw = '$bgRaw stats $stRaw';
          if (!_before) {
            final warn = c.id == 'WARN';
            chk('strict 통계 칸 면 grey100 · 아이콘 grey600 · 라벨 textSecondary', stFace == _wantGrey100 && stIcon == _wantGrey600 && stLab == _wantText2, stRaw);
            chk('strict 통계 숫자 — 일반 textPrimary · 노쇼/지각 양수만 errorDark/warningDark',
                cells[0].num == _wantText1 && cells[1].num == _wantText1 && cells[2].num == (warn ? _wantErrDark : _wantText1) && cells[3].num == (warn ? _wantWarnDark : _wantText1),
                stRaw);
            chk('strict 통계 글/면 대비 ≥4.5', stCr, stRaw);
          }

          // ③ 구역 머리(모든 사례 · R5) — 모든 사례에 서는 제목 셋의 막대 · 기능 아이콘.
          final heads = [for (final x in _sectTitles) _sect(t, dlg, x)];
          final nSect = heads.where((x) => x.ok).length;
          final scBar = _one(heads.map((x) => x.bar));
          final scIcon = _one(heads.map((x) => x.icon));
          final scCr = heads.every((x) => x.cr);
          _out('D541 $tok att sect n=$nSect bar=$scBar icon=$scIcon cr45=$scCr');
          need('구역 머리 3', nSect == 3, 'n $nSect');
          final scRaw = 'sect $scBar/$scIcon cr $scCr';
          raw = '$raw $scRaw';
          if (!_before) chk('strict 구역 머리 막대 border · 기능 아이콘 grey600 · 대비 ≥4.5(R5)', scBar == _wantLine && scIcon == _wantGrey600 && scCr, scRaw);

          // ④ 승인 준비 안내(대기 지원자 · 서류 검토 성공 사례) — 확정 가능 = 중립 띠 · 확정 불가 = 대표 안내(R6 유지 · DU541 그대로).
          final bPart = _bannerPart[c.id];
          if (bPart != null) {
            final bnF = find.descendant(of: dlg, matching: findVisibleTextContaining(bPart), skipOffstage: true);
            final bn = _inkOf(t, bnF);
            final bnIcon = bn.n == 1 ? _iconIn(t, find.ancestor(of: bnF, matching: find.byType(Container)).first) : '-';
            _out('D541 $tok att banner n=${bn.n} face=${bn.face} icon=$bnIcon fg=${bn.fg} cr45=${bn.cr}');
            need('승인 준비 안내 1', bn.n == 1, bPart);
            final bnRaw = 'banner ${bn.face}/$bnIcon/${bn.fg} cr ${bn.cr}';
            raw = '$raw $bnRaw';
            if (!_before) {
              final ok = c.id == 'READY';
              chk(ok ? 'strict 확정 가능 띠 = grey100 · grey600 아이콘 · textPrimary' : 'strict 확정 불가 띠 = warningBg · warningDark(R6 E-NOTICE 유지)',
                  bn.face == (ok ? _wantGrey100 : _wantWarnBg) && bnIcon == (ok ? _wantGrey600 : _wantWarnDark) && bn.fg == (ok ? _wantText1 : _wantWarnDark), bnRaw);
              chk('strict 승인 준비 안내 대비 ≥4.5', bn.cr, bnRaw);
            }
          }

          // ⑤ 동의 전 안내(DOCS · DU541 그대로) — 중립 면 + textPrimary.
          if (c.id == 'DOCS') {
            final csF = find.descendant(of: dlg, matching: findVisibleTextContaining(_consentPart), skipOffstage: true);
            final cs = _inkOf(t, csF);
            _out('D541 $tok att consent n=${cs.n} face=${cs.face} fg=${cs.fg} cr45=${cs.cr}');
            need('동의 전 안내 1', cs.n == 1, _consentPart);
            final csRaw = 'consent ${cs.face}/${cs.fg} cr ${cs.cr}';
            raw = '$raw $csRaw';
            if (!_before) chk('strict 동의 전 안내 = grey100 · textPrimary · 대비 ≥4.5', cs.face == _wantGrey100 && cs.fg == _wantText1 && cs.cr, csRaw);
          }

          // ⑥ 이용 제한 칩 · 재고용 추천률(WARN) — 칩은 DU541 그대로, 추천률은 R2(집계값 · 아이콘 · 선 중립 · 건수 보강).
          if (c.id == 'WARN') {
            final bkF = find.descendant(of: dlg, matching: find.text(_blockText), skipOffstage: true);
            final bk = _inkOf(t, bkF);
            final bkIcon = bk.n == 1 ? _iconIn(t, find.ancestor(of: bkF, matching: find.byType(Container)).first) : '-';
            _out('D541 $tok att block n=${bk.n} face=${bk.face} fg=${bk.fg} icon=$bkIcon cr45=${bk.cr}');
            need('이용 제한 칩 1', bk.n == 1, '개수 ${bk.n}');
            final bkRaw = 'block ${bk.face}/${bk.fg}/$bkIcon cr ${bk.cr}';
            raw = '$raw $bkRaw';
            if (!_before) chk('strict 이용 제한 칩 = errorBg · errorDark 글/아이콘 · 대비 ≥4.5', bk.face == _wantErrBg && bk.fg == _wantErrDark && bkIcon == _wantErrDark && bk.cr, bkRaw);

            final rhF = find.descendant(of: dlg, matching: find.text(_rehireLabel), skipOffstage: true);
            final nRh = rhF.evaluate().length;
            need('재고용 추천률 1', nRh == 1, '개수 $nRh');
            final rhBox = find.ancestor(of: rhF, matching: find.byType(Container)).first;
            final rhFace = _faceOf(t, rhF);
            final rhBd = _edgeOf(t, rhF);
            final rhIcon = _iconIn(t, rhBox);
            final pF = find.descendant(of: rhBox, matching: find.text(_rehirePct), skipOffstage: true);
            final qF = find.descendant(of: rhBox, matching: find.text(_rehireCnt), skipOffstage: true);
            final nP = pF.evaluate().length;
            final nQ = qF.evaluate().length;
            need('재고용 % · 건수 1', nP == 1 && nQ == 1, 'pct $nP cnt $nQ');
            final pC = _fgOf(t, pF);
            final qC = _fgOf(t, qF);
            final rhUnder = Color.alphaBlend(rhFace, Colors.white);
            final rhCr = _contrast(pC, rhUnder) >= 4.5 && _contrast(qC, rhUnder) >= 4.5;
            _out('D541 $tok att rehire n=$nRh face=${_hex(rhFace)} bd=$rhBd icon=$rhIcon pfg=${_hex(pC)} cfg=${_hex(qC)} cr45=$rhCr');
            final rhRaw = 'rehire ${_hex(rhFace)}/$rhBd/$rhIcon/${_hex(pC)}/${_hex(qC)} cr $rhCr';
            raw = '$raw $rhRaw';
            if (!_before) {
              chk('strict 재고용 추천률 = grey50 면 · border 선 · grey600 아이콘 · % textPrimary · 건수 textSecondary(R2)',
                  _hex(rhFace) == _wantGrey50 && rhBd == _wantLine && rhIcon == _wantGrey600 && _hex(pC) == _wantText1 && _hex(qC) == _wantText2, rhRaw);
              chk('strict 재고용 % · 건수 대비 ≥4.5', rhCr, rhRaw);
            }
          }

          // ⑦ 계약 상태 띠(CONFW · CONFC · CPEND) · 세무(CONFW · CONFC · DU541 그대로) — 서명 대기 제목은 R7 로 textPrimary.
          final ctTitle = _cbandTitle[c.id];
          if (ctTitle != null) {
            final ctF = find.descendant(of: dlg, matching: find.text(ctTitle), skipOffstage: true);
            final ct = _inkOf(t, ctF);
            final ctBox = find.ancestor(of: ctF, matching: find.byType(Container));
            final ctIcon = ct.n == 1 ? _iconIn(t, ctBox.first) : '-';
            final ctBd = ct.n == 1 ? _edgeOf(t, ctF) : '-';
            final w = c.id != 'CONFC';
            var sfg = '-';
            var scr = true;
            if (w) {
              final subF = find.descendant(of: dlg, matching: find.text(_cbandSub), skipOffstage: true);
              final nSub = subF.evaluate().length;
              need('서명 대기 설명 1', nSub == 1, '개수 $nSub');
              final subC = _fgOf(t, subF);
              sfg = _hex(subC);
              scr = _contrast(subC, Color.alphaBlend(_faceOf(t, subF), Colors.white)) >= 4.5;
            }
            final cbCr = ct.cr && scr;
            _out('D541 $tok att cband n=${ct.n} face=${ct.face} bd=$ctBd icon=$ctIcon tfg=${ct.fg} sfg=$sfg cr45=$cbCr');
            need('계약 상태 띠 1', ct.n == 1, ctTitle);
            final cbRaw = 'cband ${ct.face}/$ctBd/$ctIcon/${ct.fg}/$sfg cr $cbCr';
            raw = '$raw $cbRaw';
            if (!_before) {
              chk(w ? 'strict 서명 대기 띠 = 흰 면 · border · grey600 아이콘 · 제목 textPrimary(R7) · 설명 textSecondary' : 'strict 서명 완료 띠 = 흰 면 · border · grey600 아이콘 · textPrimary',
                  ct.face == _wantWhite && ctBd == _wantLine && ctIcon == _wantGrey600 && ct.fg == _wantText1 && sfg == (w ? _wantText2 : '-'), cbRaw);
              chk('strict 계약 상태 띠 대비 ≥4.5', cbCr, cbRaw);
            }
          }
          final txLabel = _taxLabel[c.id];
          final txBtn = _taxBtn[c.id];
          if (txLabel != null && txBtn != null) {
            final txF = find.descendant(of: dlg, matching: find.text(txLabel), skipOffstage: true);
            final txN = txF.evaluate().length;
            need('세무 확인 상태 글 1', txN == 1, '개수 $txN');
            final txC = _fgOf(t, txF);
            final txIcon = _iconIn(t, find.ancestor(of: txF, matching: find.byType(Row)).first);
            final tbF = find.descendant(of: dlg, matching: find.text(txBtn), skipOffstage: true);
            final tbN = tbF.evaluate().length;
            need('세무 확인 버튼 1', tbN == 1, '개수 $tbN');
            final tbFace = t.widget<Material>(find.ancestor(of: tbF, matching: find.byType(Material)).first).color ?? Colors.transparent;
            final tbFg = _fgOf(t, tbF);
            final txCr = _contrast(txC, Colors.white) >= 4.5 && _contrast(tbFg, Color.alphaBlend(tbFace, Colors.white)) >= 4.5;
            _out('D541 $tok att tax n=$txN fg=${_hex(txC)} icon=$txIcon bn=$tbN bface=${_hex(tbFace)} bfg=${_hex(tbFg)} cr45=$txCr');
            final txRaw = 'tax ${_hex(txC)}/$txIcon btn ${_hex(tbFace)}/${_hex(tbFg)} cr $txCr';
            raw = '$raw $txRaw';
            if (!_before) {
              final w = c.id == 'CONFW';
              chk(w ? 'strict 세무 확인 필요 = warningDark 글 · 아이콘' : 'strict 세무 확인 완료 = successDark(그대로)',
                  txIcon == (w ? _wantWarnDark : _wantSuccDark) && _hex(txC) == (w ? _wantWarnDark : _wantSuccDark), txRaw);
              chk('strict 세무 확인 버튼 = brand 8% 면 · brand 글', _hex(tbFace) == _wantBrand8 && _hex(tbFg) == _wantBrand, txRaw);
              chk('strict 세무 확인 글/버튼 대비 ≥4.5', txCr, txRaw);
            }
          }

          // ⑧ 하단 '확정취소' 진입(출근 기록 없는 확정자) — 면 없는 errorDark 그대로(R9 하위 창 최종 버튼은 다음 셀 · 이 셀 변경 0).
          if (_cancelKinds.contains(c.id)) {
            final cnF = find.descendant(of: dlg, matching: find.text(_cancelText), skipOffstage: true);
            final nCn = cnF.evaluate().length;
            need('확정취소 진입 1', nCn == 1, '개수 $nCn');
            final cnFace = t.widget<Material>(find.ancestor(of: cnF, matching: find.byType(Material)).first).color ?? Colors.transparent;
            final cnFg = _fgOf(t, cnF);
            final cnCr = _contrast(cnFg, Color.alphaBlend(cnFace, Colors.white)) >= 4.5;
            _out('D541 $tok att cancel n=$nCn face=${_hex(cnFace)} fg=${_hex(cnFg)} cr45=$cnCr');
            final cnRaw = 'cancel ${_hex(cnFace)}/${_hex(cnFg)} cr $cnCr';
            raw = '$raw $cnRaw';
            if (!_before) chk('strict 확정취소 진입 = 면 없음 · errorDark · 대비 ≥4.5(변경 0)', _hex(cnFace) == _wantNone && _hex(cnFg) == _wantErrDark && cnCr, cnRaw);
          }

          // ⑨ '고정근무 관리'(LONG · R1) — 관리 창 진입 = 면 없음 · textSecondary 글 · 아이콘. 하단 칸은 늘 보인다(끌기 0) — 창 상자 ∩ 화면 안인지 함께.
          if (c.id == 'LONG') {
            final fxF = find.descendant(of: dlg, matching: find.text(_fixText), skipOffstage: true);
            final nFx = fxF.evaluate().length;
            need('고정근무 관리 1', nFx == 1, '개수 $nFx');
            final fxMat = find.ancestor(of: fxF, matching: find.byType(Material)).first;
            final fxFace = t.widget<Material>(fxMat).color ?? Colors.transparent;
            final fxFg = _fgOf(t, fxF);
            final fxIcon = _iconIn(t, fxMat);
            final fxCr = _contrast(fxFg, Color.alphaBlend(fxFace, Colors.white)) >= 4.5;
            final boxF = find.descendant(of: dlg, matching: find.byType(Dialog), skipOffstage: true);
            final fxArea = boxF.evaluate().isEmpty ? screen : t.getRect(boxF.first).intersect(screen);
            final fxR = t.getRect(fxMat);
            final fxVis = _inside(fxR, fxArea);
            _out('D541 $tok att fixbtn n=$nFx face=${_hex(fxFace)} fg=${_hex(fxFg)} icon=$fxIcon cr45=$fxCr vis=$fxVis');
            final fxRaw = 'fixbtn ${_hex(fxFace)}/${_hex(fxFg)}/$fxIcon cr $fxCr rect $fxR vis $fxVis';
            raw = '$raw $fxRaw';
            if (!_before) {
              chk('strict 고정근무 관리 = 면 없음 · textSecondary 글/아이콘 · 대비 ≥4.5(R1)', _hex(fxFace) == _wantNone && _hex(fxFg) == _wantText2 && fxIcon == _wantText2 && fxCr, fxRaw);
              chk('strict 고정근무 관리 — 창 상자 ∩ 화면 안', fxVis, fxRaw);
            }
          }

          // ⑩ 캡처 — 첫 화면 → (사례별) 끌어 넣은 화면. 누르지 않는다.
          if (c.id == 'READY') {
            await shot('1ready', 'pending-ready-first-screen');
          } else if (c.id == 'DOCS') {
            await shot('1docs', 'pending-consent-first-screen');
          } else if (c.id == 'FAIL') {
            // 서류 조회 실패 — '다시 불러오기'(TextButton · brand). 첫 화면 보임/hit 은 기록, 끌어 넣은 뒤 보임 · hit 은 strict(DU541 r2 의 식).
            final retryF = find.descendant(of: dlg, matching: find.widgetWithText(TextButton, _retryText), skipOffstage: true);
            final nRetry = retryF.evaluate().length;
            need('다시 불러오기 버튼 1', nRetry == 1, '개수 $nRetry');
            final rtF = find.descendant(of: retryF, matching: find.text(_retryText), skipOffstage: true);
            final nRt = rtF.evaluate().length;
            need('다시 불러오기 글 1', nRt == 1, '개수 $nRt');
            final rfg = _fgOf(t, rtF);
            final rcr = _contrast(rfg, Colors.white) >= 4.5;
            final p0 = _tapNow(t, retryF, dlg, screen);
            await shot('1fail', 'review-load-failed-first-screen');
            await t.ensureVisible(retryF);
            await settle();
            final p1 = _tapNow(t, retryF, dlg, screen);
            _out('D541 $tok att retry n=$nRetry fg=${_hex(rfg)} cr45=$rcr vis0=${p0.vis} hit0=${p0.hit} vis=${p1.vis} hit=${p1.hit}');
            final rr = 'retry ${_hex(rfg)} cr $rcr first ${p0.r} ${p0.vis}/${p0.hit} after ${p1.r} ${p1.vis}/${p1.hit}';
            raw = '$raw $rr';
            if (!_before) {
              chk('strict 다시 불러오기 = brand · 대비 ≥4.5', _hex(rfg) == _wantBrand && rcr, rr);
              chk('strict 다시 불러오기 — 끌어 넣은 뒤 칸 안 · 중심 hit(TextButton)', p1.vis && p1.hit, rr);
            }
            await shot('2retry', 'review-load-failed-retry-in-view');
          } else if (c.id == 'WARN') {
            await shot('1warn', 'pending-history-first-screen');
            await t.ensureVisible(find.descendant(of: dlg, matching: find.text(_statLabels[2]), skipOffstage: true));
            await settle();
            await shot('2stats', 'pending-history-stats-in-view');
          } else if (c.id == 'CONFW' || c.id == 'CONFC') {
            final tbIn = find.descendant(of: dlg, matching: find.text(_taxBtn[c.id]!), skipOffstage: true);
            if (c.id == 'CONFW') {
              await shot('1confw', 'confirmed-sign-wait-first-screen');
            } else {
              await shot('1confc', 'confirmed-signed-first-screen');
            }
            await t.ensureVisible(tbIn);
            await settle();
            if (c.id == 'CONFW') {
              await shot('2wtax', 'confirmed-sign-wait-tax-in-view');
            } else {
              await shot('2ctax', 'confirmed-signed-tax-in-view');
            }
          } else if (c.id == 'VOID') {
            // 계약 무효 띠(R3) — 색은 위젯 값(끌기 전), rect 는 끌어 넣은 뒤 보이는 칸 안에서만. 작은 표시 = 아이콘의 가장 가까운 Container.
            final vtF = find.descendant(of: dlg, matching: find.text(_voidText), skipOffstage: true);
            final vb = _inkOf(t, vtF);
            need('무효 띠 1', vb.n == 1, '개수 ${vb.n}');
            final vBox = find.ancestor(of: vtF, matching: find.byType(Container)).first;
            final vBd = _edgeOf(t, vtF);
            final vIcF = find.descendant(of: vBox, matching: find.byType(Icon), skipOffstage: true);
            final nVi = vIcF.evaluate().length;
            need('무효 띠 아이콘 1', nVi == 1, '개수 $nVi');
            final vIc = t.widget<Icon>(vIcF).color ?? Colors.black;
            final mBoxF = find.ancestor(of: vIcF, matching: find.byType(Container)).first;
            final mDeco = t.widget<Container>(mBoxF).decoration;
            final mFace = mDeco is BoxDecoration ? (mDeco.color ?? Colors.transparent) : Colors.transparent;
            final mShape = mDeco is BoxDecoration && mDeco.shape == BoxShape.circle ? 'circle' : 'rect';
            final vUnder = Color.alphaBlend(mFace, Color.alphaBlend(_faceOf(t, vtF), Colors.white));
            final vCr = vb.cr && _contrast(vIc, vUnder) >= 4.5;
            // 리뷰 별 5개(R4) — 색 · 채움 수는 위젯 값.
            final starF = find.descendant(
                of: dlg, matching: find.byWidgetPredicate((w) => w is Icon && (w.icon == Icons.star || w.icon == Icons.star_border)), skipOffstage: true);
            final stEls = starF.evaluate().toList();
            final nSt = stEls.length;
            need('리뷰 별 5', nSt == 5, '개수 $nSt');
            final nFill = stEls.where((e) => (e.widget as Icon).icon == Icons.star).length;
            final starFg = _one(stEls.map((e) => _hex((e.widget as Icon).color ?? Colors.black)));
            final rvFace = _faceOf(t, starF.first);
            final starCr3 = stEls.every((e) => _contrast((e.widget as Icon).color ?? Colors.black, Color.alphaBlend(rvFace, Colors.white)) >= 3.0);
            await shot('1void', 'confirmed-void-first-screen');
            // 띠 상자(Container)를 끌어 넣는다 — 글을 기준으로 끌면 띠 위 여백이 보이는 칸 위로 잘린다(r0 정적 재검토).
            await t.ensureVisible(vBox);
            await settle();
            final scF = find.ancestor(of: vtF, matching: find.byType(Scrollable));
            final vArea = scF.evaluate().isEmpty ? screen : screen.intersect(t.getRect(scF.first));
            final bandR = t.getRect(vBox);
            final markR = t.getRect(mBoxF);
            final vVis = _inside(bandR, vArea);
            final vInb = _inside(markR, bandR);
            _out('D541 $tok att vband n=${vb.n} face=${vb.face} bd=$vBd fg=${vb.fg} icon=${_hex(vIc)} mface=${_hex(mFace)} mshape=$mShape cr45=$vCr vis=$vVis inb=$vInb '
                'bh=${bandR.height.toStringAsFixed(1)}');
            final vRaw = 'vband ${vb.face}/$vBd/${vb.fg}/${_hex(vIc)}/${_hex(mFace)}/$mShape cr $vCr band $bandR mark $markR vis $vVis inb $vInb';
            raw = '$raw $vRaw';
            if (!_before) {
              chk('strict 무효 띠 = 흰 면 · border · 글 textPrimary · 작은 원 errorBg + errorDark 아이콘(R3)',
                  vb.face == _wantWhite && vBd == _wantLine && vb.fg == _wantText1 && _hex(vIc) == _wantErrDark && _hex(mFace) == _wantErrBg && mShape == 'circle', vRaw);
              chk('strict 무효 띠 글/면 · 아이콘/원 대비 ≥4.5', vCr, vRaw);
              chk('strict 무효 띠 — 끌어 넣은 뒤 보이는 칸 안 · 작은 원이 띠 안', vVis && vInb, vRaw);
            }
            await shot('2vband', 'confirmed-void-band-in-view');
            _out('D541 $tok att stars n=$nSt fill=$nFill fg=$starFg face=${_hex(rvFace)} cr3=$starCr3');
            final sRaw = 'stars $nSt/$nFill/$starFg/${_hex(rvFace)} cr3 $starCr3';
            raw = '$raw $sRaw';
            if (!_before) chk('strict 리뷰 별 = grey600(채움/윤곽 그대로) · 면 grey50 · 그래픽 대비 ≥3(R4)', starFg == _wantGrey600 && _hex(rvFace) == _wantGrey50 && starCr3, sRaw);
            await t.ensureVisible(starF.first);
            await settle();
            await shot('3review', 'confirmed-void-review-in-view');
          } else if (c.id == 'LONG') {
            await shot('1long', 'confirmed-longterm-fixed-entry-first-screen');
          } else {
            await shot('1cpend', 'contract-pending-first-screen');
            await t.ensureVisible(find.descendant(of: dlg, matching: find.text(_cbandTitle['CPEND']!), skipOffstage: true));
            await settle();
            await shot('2cband', 'contract-pending-sign-wait-in-view');
          }
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ⑪ 성공 · 실패 공통 정리 — 창을 내리고 남은 지연 응답이 끝날 시간을 준다.
        var cleanupErr = '';
        try {
          await t.pumpWidget(const SizedBox.shrink());
          for (var i = 0; i < 6; i++) {
            await t.pump(const Duration(seconds: 1));
          }
        } catch (e, st) {
          cleanupErr = e.toString();
          if (failure == null) {
            failure = e;
            failureSt = st;
          }
        }

        // ⑫ 집계 — 읽기 호출 수 · 허용 밖 CF · Firestore 쓰기/그 밖 연산 · 예상 밖 채널 · HTTP · 서류 검토 대역 호출.
        final nAp = wire.calls['callableGetApplicationsByBiz'] ?? 0;
        final nMr = wire.calls['callableGetMonthlyReviewsForUser'] ?? 0;
        final nRv = wire.calls['callableGetReviewsForUser'] ?? 0;
        final nIc = wire.calls['callableCheckIdCardAccess'] ?? 0;
        final nAt = wire.calls['callableAdminHasAttendanceRecord'] ?? 0;
        final nCt = wire.calls['callableGetContractsByBiz'] ?? 0;
        final nTx = wire.calls['callableGetTaxIdentityReview'] ?? 0;
        final nDr = fake?.loads ?? 0;
        final nCfx = wire.blocked.length;
        final nFsw = wire.fsWrites.length;
        final nFso = wire.fsOther.length;
        final nUnexp = wire.unexpected.length;
        final nHttp = net.tries.length;
        final nHcl = net.clients;
        final nHarness = wire.harness.length;
        final unText = [...wire.unexpected, ...wire.blocked, ...wire.fsWrites.map((x) => 'fsw $x'), ...wire.fsOther.map((x) => 'fs $x'), ...wire.harness].join(' | ');
        _out('D541 $tok att wire ap=$nAp mr=$nMr rv=$nRv ic=$nIc at=$nAt ct=$nCt tx=$nTx dr=$nDr cfx=$nCfx fsw=$nFsw fso=$nFso unexpected=$nUnexp http=$nHttp hcl=$nHcl harness=$nHarness');

        messenger.allMessagesHandler = prevAll;
        HttpOverrides.global = prevHttp;
        final exc = t.takeException();
        if (exc != null && failure == null) {
          failure = exc;
          failureSt = StackTrace.current;
        }
        final nOvf = seen.overflows.length;
        final nFw = seen.other.length;
        final ovfRaw = seen.overflows.take(8).join('\n----\n');
        final fwRaw = seen.other.take(4).map((m) => m.length > 400 ? m.substring(0, 400) : m).join('\n----\n');
        _out('R541b $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D541 $tok att fw n=$nFw');
        _out('D541 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        final wantOne = conf ? 1 : 0;
        chk('쓰기 · 허용 밖 CF 0 · HTTP 0 · 대역 오류 0', nCfx == 0 && nFsw == 0 && nHttp == 0 && nHarness == 0, unText);
        chk('읽기 대역 호출(근무 이력 2 · 공개 리뷰 1 · 확정자 4종 ${conf ? '1' : '0'} · 서류 검토 ${conf ? '0' : '1'})',
            nAp == 1 && nMr == 1 && nRv == 1 && nIc == wantOne && nAt == wantOne && nCt == wantOne && nTx == wantOne && nDr == 1 - wantOne,
            'ap $nAp mr $nMr rv $nRv ic $nIc at $nAt ct $nCt tx $nTx dr $nDr');
        if (!_before && !isB) chk('strict W 화면 전체 넘침 0', nOvf == 0, ovfRaw);
        if (!_before) chk('strict 미처리 framework 예외 0', nFw == 0, fwRaw);
        chk('캡처 수 = 선언', shots == c.shots, 'shots $shots want ${c.shots}');
        final bad = checks.where((x) => !x.$2).toList();
        if (bad.isNotEmpty) _halt ??= '$tok ${bad.first.$1}';
        for (final x in checks) {
          expect(x.$2, isTrue, reason: '$tok ${x.$1} ${x.$3}');
        }
      }, skip: !_optIn);
    }
  }
}
