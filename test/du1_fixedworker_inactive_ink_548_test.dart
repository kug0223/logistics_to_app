// ignore_for_file: depend_on_referenced_packages
// [DU548 · F137-INACTIVE-CONTRAST] 고정근무자 관리 창(FixedWorkerManagementDialog) 날짜 모드 '오늘 비근무' 구역 — 비근무일 · 계약기간 외 배지 글 grey100/textSecondary ·
//   카드 전체를 덮던 흰 70% 필터(ColorFiltered srcATop) 제거 · 이름/기간/요일/업무 읽기 잉크 보존 · 카드 탭(InkWell.onTap) 그대로.
//   판정 = reports/DU_audit_self_review_retro137_2026-11-20.md §4 PP-FIXEDWORKER-INACTIVE-INK-20261120 + retro141 :76 + retro142 :100–104(요청 방향/집계/승인/철회 변경 0).
//   before = 현재 A(fixed_worker_management_dialog b0cccab2 = DU543 r3 채택판) 기록 전용 · strict = 후보(f38608f2).
//   하네스 = DU540 날짜 모드 대역 그대로(한 사업장 · 같은 CF 채널 대역 · 같은 4명 fixture) + DU543 r3 끌기 도달(명단 칸을 실제로 끌어 지연 생성 카드에 닿는다).
//   사례 2: WKND(DU540 DATEWKND 그대로 — 토요일 · 이나래 · 박다온 = 비근무일) · OUTP(DU540 DATENONE 의 평일 · 이나래의 계약 시작만 보는 날 + 7일 = 계약기간 외).
//   누르는 것 0 — 카드 · 승인 · 거절 모두 누르지 않는다(끌기와 ensureVisible 만). 색은 위젯 값 · 덮개는 조상 ColorFiltered 수와 같음 비교로 잰다(화소 측정 아님).
//   날짜 모드 B(320×640 · 글자 2.0)의 넘침 · framework 오류는 기록만(DU540 · DU543 처럼 · TB ≥ TA 손 대조 · 고치지 않는다).
//   기본 skip — TB before/du548-tb/DU_BEFORE_OBSERVE=548 · TA after/du548-ta/없음.
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
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/fixed_worker_management_dialog.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';

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

const _biz1 = 'biz1';
const _bizName = '강남 물류센터';

/// 소유자(BUSINESS_ADMIN) — DU540 _Owner 와 같은 override(창은 `canForBusiness` · `watchBusinessPermissions` 를 부른다).
class _Owner extends UserProvider {
  final watched = <String>[];
  @override
  UserModel? get currentUser => UserModel(
      uid: 'admin1', username: 'admin1', name: '김관리', email: 'admin1@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const [_biz1], sealBase64: 'seal');
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

BusinessModel _business(String id, String name) => BusinessModel(
    id: id, name: name, ownerId: 'admin1', businessNumber: '000-00-00000', address: '서울시 어딘가',
    category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1));

/// 오늘(KST) + [d]일의 KST 자정(UTC ms) — 창의 `FormatHelper.toKstDate` 와 같은 달력.
int _kstDayMs(int d) {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day + d).subtract(const Duration(hours: 9)).millisecondsSinceEpoch;
}

/// CF 응답의 시각 표기(서버 serializeFirestoreData 형식 — 앱이 `_cfHydrate` 로 Timestamp 로 되돌린다).
Map<String, Object?> _ts(int ms) => <String, Object?>{'_seconds': ms ~/ 1000, '_nanoseconds': 0};

/// 장기 확정 지원서 한 건 — 종료일 = 오늘 + [endIn]일(DU540 과 같다).
Map<String, Object?> _app(String id, String applicant, int endIn, {Map<String, Object?> extra = const <String, Object?>{}}) => <String, Object?>{
      'id': id, 'uid': 'u_$id', 'businessId': _biz1, 'businessName': _bizName, 'toId': 'to1', 'toTitle': '장기 모집',
      'selectedWorkType': '홀서빙', 'startTime': '09:00', 'endTime': '18:00', 'status': 'CONFIRMED', 'type': 'long_term',
      'applicantName': applicant, 'wage': 12000, 'wageType': 'hourly', 'workDays': const <Object?>['월', '화', '수', '목', '금'],
      'workDate': _ts(_kstDayMs(-30)), 'workEndDate': _ts(_kstDayMs(endIn)),
      'appliedAt': _ts(_kstDayMs(-32)), 'confirmedAt': _ts(_kstDayMs(-31)),
      ...extra,
    };

const _names = <String, String>{'u_c1': '김가람', 'u_c2': '이나래', 'u_c3': '서다솜', 'u_c4': '박다온'};

/// 오늘(KST)에서 며칠 뒤가 [ok] 요일인가(0–7 · 없으면 0).
int _aheadTo(bool Function(int weekday) ok) {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  for (var d = 0; d < 8; d++) {
    if (ok(DateTime.utc(k.year, k.month, k.day + d).weekday)) return d;
  }
  return 0;
}

/// 날짜 모드로 보는 날 — 오늘(KST) 이후 첫 평일(월–금) / 첫 토요일(DU540 과 같다).
int _weekdayAhead() => _aheadTo((wd) => wd <= DateTime.friday);
int _saturdayAhead() => _aheadTo((wd) => wd == DateTime.saturday);

/// 창에 넘기는 focusDate — 그 날의 로컬 자정(달력 화면 workforce_operational_view 가 넘기는 값과 같은 모양 `DateTime(y, m, d)`).
DateTime _focusDay(int ahead) {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime(k.year, k.month, k.day + ahead);
}

/// 날짜 모드 대역 4명(DU540 과 같다 · 호출마다 새로 만든다) —
///   c1 김가람: 월–금 · 가장 최근 확정(명단 맨 위 카드 · 활성 카드 기준 잉크) · 토요일 = 추가근무 요청 중(WKND)
///   c2 이나래: 월–금(토요일 = 비근무일) — [kind] = OUTP 이면 계약 시작(workDate)만 보는 평일 + 7일로 옮긴다(= 계약기간 외 · 그 밖 값 그대로)
///   c3 서다솜: 토 · 일 + 그 평일에 승인된 추가근무 · c4 박다온: 월–금 + 그 평일에 승인된 휴무(토요일 = 비근무일)
List<Object?> _appsDate(String kind) => <Object?>[
      _app('c1', '김가람', 60, extra: <String, Object?>{'confirmedAt': _ts(_kstDayMs(-20))}),
      _app('c2', '이나래', 90, extra: kind == 'OUTP' ? <String, Object?>{'workDate': _ts(_kstDayMs(_weekdayAhead() + 7))} : const <String, Object?>{}),
      _app('c3', '서다솜', 120, extra: <String, Object?>{'workDays': const <Object?>['토', '일'], 'extraWorkDates': <Object?>[_ts(_kstDayMs(_weekdayAhead()))]}),
      _app('c4', '박다온', 100, extra: <String, Object?>{'leaveDates': <Object?>[_ts(_kstDayMs(_weekdayAhead()))]}),
    ];

/// c1 의 대기 중인 추가 근무 요청 한 건(토요일 · 관리자가 보낸 EXTRA_WORK — DU540 DATEWKND 와 같다). 이 셀은 요청 방향 · 승인/거절을 바꾸지 않는다.
Map<String, Object?> _schedReq(int ahead) => <String, Object?>{
      'id': 'sr1', 'businessId': _biz1, 'applicationId': 'c1', 'applicantUid': 'u_c1', 'applicantName': '김가람',
      'targetDate': _ts(_kstDayMs(ahead)), 'requestType': 'EXTRA_WORK', 'requestedBy': 'ADMIN',
      'requestedByUid': 'admin1', 'requestedAt': _ts(_kstDayMs(-1)), 'reason': '일정 조정 부탁드립니다', 'status': 'PENDING',
    };

const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
const _wtPath = 'businesses/$_biz1/workTypes';
const _appsFn = 'callableGetApplicationsByBiz';
const _schedFn = 'callableGetScheduleChangeRequestsForDate';

/// 첫 화면이 부르는 읽기 CF(DU540 과 같은 4종) — 이 밖의 CF 이름(승인 · 거절 포함)은 차단하고 센다.
const _readFns = <String>{'callableGetApplicationsByBiz', 'callableGetRenewalProposalsByBiz', 'callableGetUsersBatch', _schedFn};

/// Firestore 쓰기 연산 — 하나라도 오면 writes 로 센다.
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

/// [DU526 · DU534 · DU536 · DU540 과 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널.
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du548.fake.auth.';
const _authListeners = ['registerIdTokenListener', 'registerAuthStateListener'];

/// 원래 경로로 보내는 Flutter 기반 채널과 이유.
const _frameworkAllow = <String, String>{
  'flutter/assets': 'AssetBundle(아이콘 글꼴 · 이미지 매니페스트) 읽기',
  'flutter/platform': 'MaterialApp Title · SystemSound/Haptic(InkWell 탭 피드백)',
  'flutter/navigation': '루트 Navigator 경로 보고',
  'flutter/mousecursor': 'MouseRegion 커서 갱신(시험 포인터)',
  'flutter/restoration': 'RootRestorationScope 상태 복원 조회',
  'flutter/keyboard': 'HardwareKeyboard 상태 동기화',
  'flutter/accessibility': '의미 트리/알림 전달',
};

/// 모든 플랫폼 메시지 관찰 — 읽기 CF 4종 · workTypes 질의는 대역 응답, 그 밖 CF/Firestore 는 차단 응답 + 기록,
///   기반 채널은 원래 경로, 나머지는 이름을 기록하고 응답 null. 예외를 삼키지 않는다 — 수는 줄로 남긴다(DU540 _Wire 와 같다).
class _Wire {
  _Wire(this.kind);

  /// 사례 이름 — WKND(토요일 · c1 추가근무 요청 대기 1건) · OUTP(평일 · 요청 0 · c2 계약 시작이 보는 날 뒤) · SETUP(호출 0).
  final String kind;
  final unexpected = <String>[];
  final blocked = <String>[];
  final otherFs = <String>[];
  final auth = <String>[];
  final harness = <String>[];
  final calls = <String, int>{};
  void _hit(String k) => calls[k] = (calls[k] ?? 0) + 1;

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
    if (channel == _cfChannel) return Future<ByteData?>.value(_cf(message));
    if (channel.startsWith('$_fsBase.')) return Future<ByteData?>.value(_fs(channel.substring(_fsBase.length + 1), message));
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
      final params = (args['parameters'] as Map?) ?? const <Object?, Object?>{};
      if (region != 'asia-northeast3' || !_readFns.contains(fn)) {
        blocked.add('fn $fn@$region');
        return codec.encodeMessage(<Object?>['not-found', 'du548-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      _hit(fn);
      if (fn == _appsFn) {
        return codec.encodeMessage(<Object?>[<String, Object?>{'applications': _appsDate(kind)}]);
      }
      if (fn == 'callableGetRenewalProposalsByBiz') {
        return codec.encodeMessage(<Object?>[<String, Object?>{'proposals': const <Object?>[]}]);
      }
      if (fn == _schedFn) {
        // 날짜 모드의 일정 요청 조회(서비스가 businessIds · dateMs 를 보낸다) — 응답 = {items: [...]}(시각은 _ts 형식 · DU540 과 같다).
        final items = kind == 'WKND' ? <Object?>[_schedReq(_saturdayAhead())] : const <Object?>[];
        return codec.encodeMessage(<Object?>[<String, Object?>{'items': items}]);
      }
      final uids = (params['uids'] as List).cast<String>();
      return codec.encodeMessage(<Object?>[
        <String, Object?>{
          'users': <String, Object?>{for (final u in uids) u: <String, Object?>{'name': _names[u] ?? '근로자', 'role': 'USER'}},
        },
      ]);
    } catch (e) {
      harness.add('cf $e');
      return codec.encodeMessage(<Object?>['internal', 'du548-harness', null]);
    }
  }

  ByteData? _fs(String op, ByteData? message) {
    const codec = FirebaseFirestoreHostApi.codec;
    try {
      if (op == 'queryGet' && message != null) {
        // 요청 본문은 codec 으로 되읽을 수 없다(선례 du1_c1_edit_discard_test.dart:92–98) — 원본 바이트의 경로 문자열로 구분한다.
        final raw = String.fromCharCodes(message.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes));
        if (raw.contains(_wtPath)) {
          _hit('workTypes');
          return codec.encodeMessage(<Object?>[
            PigeonQuerySnapshot(
              documents: [
                PigeonDocumentSnapshot(
                  path: '$_wtPath/wt1',
                  data: <String?, Object?>{
                    'businessId': _biz1, 'name': '포장', 'icon': 'box', 'color': '#3859E8', 'backgroundColor': '#EEF2FF',
                    'displayOrder': 0, 'isActive': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
                  },
                  metadata: PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false),
                ),
              ],
              documentChanges: const [],
              metadata: PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false),
            ),
          ]);
        }
      }
      if (_fsWrites.contains(op)) {
        blocked.add('firestore $op');
      } else {
        otherFs.add(op);
      }
      return codec.encodeMessage(<Object?>['du548-blocked', '$op 차단', null]);
    } catch (e) {
      harness.add('fs $op $e');
      return codec.encodeMessage(<Object?>['du548-harness', '대역 오류', null]);
    }
  }
}

/// 외부 HTTP 차단 — 만들려는 시도를 기록하고 실패시킨다.
class _NoHttp extends HttpOverrides {
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    throw const SocketException('DU548 관측 — 외부 HTTP 차단');
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

/// Text 하나의 글자색(style 에 색이 없으면 검정으로 적는다).
Color _fgOf(WidgetTester t, Finder f) => t.widget<Text>(f).style?.color ?? Colors.black;

/// 행동 위젯 하나가 눌릴 수 있는가(값만 읽는다 · 누르지 않는다) — InkWell.onTap · GestureDetector.onTap 이 있으면 'true'. 없으면 '-'(DU543 `_on` 과 같다).
String _on(WidgetTester t, Finder f) {
  if (f.evaluate().isEmpty) return '-';
  final w = t.widget(f.first);
  if (w is InkWell) return (w.onTap != null).toString();
  if (w is GestureDetector) return (w.onTap != null).toString();
  return '?';
}

bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

/// 요소 하나가 끌기 없이 보이고 눌리는가 — 창 상자 ∩ 화면(∩ 가까운 Scrollable 이 있으면 그 칸) 안 + 중심 hit(DU537 · DU538 r2 · DU540 · DU543 r3 `_tapNow` 와 같은 식).
({bool vis, bool hit, bool min48, Rect r}) _tapNow(WidgetTester t, Finder f, Finder dlg, Rect screen) {
  final boxF = find.descendant(of: dlg, matching: find.byType(Dialog), skipOffstage: true);
  var area = boxF.evaluate().isEmpty ? screen : t.getRect(boxF.first).intersect(screen);
  final scF = find.ancestor(of: f, matching: find.byType(Scrollable));
  final nSc = scF.evaluate().length;
  if (nSc > 0) area = area.intersect(t.getRect(scF.first));
  final r = t.getRect(f);
  final vis = _inside(r, area);
  final hit = t.hitTestOnBinding(r.center).path.any((x) => identical(x.target, t.renderObject(f)));
  final min48 = r.width >= 48 - 0.01 && r.height >= 48 - 0.01;
  return (vis: vis, hit: hit, min48: min48, r: r);
}

/// base 의 비근무 카드 덮개(fixed_worker_management_dialog b0cccab2 :1220–:1224 — 흰 70% · srcATop)와 같은 필터 · 그 색.
final ColorFilter _white70 = ColorFilter.mode(Colors.white.withValues(alpha: 0.7), BlendMode.srcATop);
final Color _white70c = Colors.white.withValues(alpha: 0.7);

/// [f](위젯 하나) 위 조상 ColorFiltered — 수 · 모두 base 덮개와 같은가(같음 비교 · 다르면 실제 표시 색을 계산하지 않는다).
({int n, bool known}) _filtersOf(Finder f) {
  final ws = find.ancestor(of: f, matching: find.byType(ColorFiltered)).evaluate().map((e) => e.widget as ColorFiltered).toList();
  return (n: ws.length, known: ws.every((w) => w.colorFilter == _white70));
}

/// 덮개 [n] 겹을 지난 표시 색 — srcATop 은 칠한 화소(불투명 바탕 위)에 흰 70% 를 올린다(알파는 그대로) → alphaBlend(흰 70%, 화소). 선언 산술(화소 측정 아님).
Color _through(Color pixel, int n) {
  var x = pixel;
  for (var i = 0; i < n; i++) {
    x = Color.alphaBlend(_white70c, x);
  }
  return x;
}

final String _wantWhite = _hex(Colors.white);
final String _wantText2 = _hex(AppColors.textSecondary);
final String _wantGrey100 = _hex(AppColors.grey100);
final String _wantGrey400 = _hex(AppColors.grey400);
final String _wantGrey500 = _hex(AppColors.grey500);
final String _wantGrey600 = _hex(AppColors.grey600);
final String _wantGrey700 = _hex(AppColors.grey700);

typedef _BodyObs = ({int emptyN, int failN, int toastN, String icon});

/// 본문 — 빈 상태 문구 수 · 조회 실패 안내 수(창 안) · 실패 토스트 수(창 밖) · 창 안 오류 아이콘 색(하나일 때만). 보이는 글 기준(DU540 과 같은 식).
_BodyObs _bodyNow(WidgetTester t, Finder dlg) {
  final emptyN = find.descendant(of: dlg, matching: findVisibleText(_emptyText), skipOffstage: true).evaluate().length;
  final failN = find.descendant(of: dlg, matching: findVisibleText(_failText), skipOffstage: true).evaluate().length;
  final toastAll = findVisibleText(_failText).evaluate().length;
  final icons = find.descendant(of: dlg, matching: find.byIcon(Icons.error_outline), skipOffstage: true).evaluate().toList();
  final ic = icons.length == 1 ? (icons.first.widget as Icon).color : null;
  return (emptyN: emptyN, failN: failN, toastN: toastAll - failN, icon: ic == null ? '-' : _hex(ic));
}

typedef _HeadObs = ({int nn, int nl, int nx, int np, int vn, int pc});

/// 날짜 머리 띠 — 통계 칸(출근예정 · 휴무 · 추가근무 · 대기) 수 · 출근예정 숫자 · '대기 n건' 칩 수(fixture 확인 · 색은 DU540 이 이미 잰 값이라 재지 않는다).
_HeadObs _headNow(WidgetTester t, Finder dlg) {
  final titleF = find.descendant(of: dlg, matching: findVisibleTextContaining(_dateTitleTail), skipOffstage: true);
  if (titleF.evaluate().length != 1) return (nn: -1, nl: -1, nx: -1, np: -1, vn: -1, pc: -1);
  final subF = find.ancestor(of: titleF, matching: find.byType(Container)).first;
  Finder lab(String s) => find.descendant(of: subF, matching: find.text(s), skipOffstage: true);
  var vn = -1;
  final nF = lab('출근예정');
  if (nF.evaluate().length == 1) {
    final chipF = find.ancestor(of: nF, matching: find.byType(Container)).first;
    final texts = find.descendant(of: chipF, matching: find.byType(Text), skipOffstage: true).evaluate().map((e) => e.widget as Text).toList();
    if (texts.length == 2) vn = int.tryParse(texts.last.data ?? '') ?? -1;
  }
  return (
    nn: nF.evaluate().length, nl: lab('휴무').evaluate().length, nx: lab('추가근무').evaluate().length, np: lab('대기').evaluate().length,
    vn: vn, pc: lab(_pendChipText).evaluate().length,
  );
}

typedef _Ink = ({String name, String per, String wd, String wt, int nf, String on, String face});

/// 카드 하나(이름 [who])의 글 잉크(선언 색 · 위젯 값 · 화면 밖이어도 트리에 있으면 읽는다) — 이름 · 기간 · 요일 · 업무 · 덮개 수 · 카드 탭 · 카드 면.
_Ink _inkOf(WidgetTester t, Finder dlg, String who) {
  final nameF = find.descendant(of: dlg, matching: find.text(who, skipOffstage: false), skipOffstage: false);
  if (nameF.evaluate().length != 1) return (name: '-', per: '-', wd: '-', wt: '-', nf: -1, on: '-', face: '-');
  final cardF = find.ancestor(of: nameF, matching: find.byType(InkWell)).first;
  final perF = find.descendant(of: cardF, matching: findVisibleTextContaining(' ~ '), skipOffstage: false);
  final calF = find.descendant(of: cardF, matching: find.byIcon(Icons.calendar_today_outlined, skipOffstage: false), skipOffstage: false);
  final wdF = calF.evaluate().length == 1
      ? find.descendant(of: find.ancestor(of: calF, matching: find.byType(Row)).first, matching: find.byType(Text, skipOffstage: false), skipOffstage: false)
      : calF;
  final wtF = find.descendant(of: cardF, matching: find.text(_wtText, skipOffstage: false), skipOffstage: false);
  String one(Finder f) => f.evaluate().length == 1 && f.evaluate().first.widget is Text ? _hex(_fgOf(t, f)) : '-';
  final mat = t.widget<Material>(find.ancestor(of: nameF, matching: find.byType(Material)).first);
  return (
    name: one(nameF), per: one(perF), wd: one(wdF), wt: one(wtF), nf: _filtersOf(nameF).n,
    on: _on(t, find.ancestor(of: nameF, matching: find.byType(InkWell))), face: _hex(mat.color ?? Colors.transparent),
  );
}

typedef _CardObs = ({
  String lab, int nf, bool known, String bface, String bfg, String bico, bool bcr, String bcv,
  String name, String nameEff, bool namecr, String namecv, String per, String perEff, String percv,
  bool same, String on, String face, bool nvis, bool nhit, bool bvis, bool pvis, String raw
});

/// 비근무 구역 카드 하나(이름 [who] · 이미 트리에 있다) — 배지(면 · 글 · 아이콘 · 덮개를 지난 대비) · 이름/기간 잉크(선언 · 덮개를 지난 표시 색 · 대비) ·
///   활성 카드 [ref] 와 같은 잉크인가 · 카드 탭 · 도달(이름 · 배지 · 기간을 각각 ensureVisible 뒤 명단 칸 안 · 이름 중심 hit). 누르지 않는다.
Future<_CardObs> _cardNow(WidgetTester t, Finder dlg, Rect screen, String who, _Ink ref) async {
  final ink = _inkOf(t, dlg, who);
  final nameF = find.descendant(of: dlg, matching: find.text(who, skipOffstage: false), skipOffstage: false);
  final cardF = find.ancestor(of: nameF, matching: find.byType(InkWell)).first;
  final labs = [
    for (final l in _inactiveLabels)
      if (find.descendant(of: cardF, matching: find.text(l, skipOffstage: false), skipOffstage: false).evaluate().length == 1) l,
  ];
  final lab = labs.length == 1 ? labs.first : '';
  final badgeF = find.descendant(of: cardF, matching: find.text(lab, skipOffstage: false), skipOffstage: false);
  final perF = find.descendant(of: cardF, matching: findVisibleTextContaining(' ~ '), skipOffstage: false);
  if (lab.isEmpty || perF.evaluate().length != 1) {
    final miss = 'labs ${labs.length} per ${perF.evaluate().length}';
    return (
      lab: '-', nf: -1, known: false, bface: '-', bfg: '-', bico: '-', bcr: false, bcv: '0.00', name: '-', nameEff: '-', namecr: false, namecv: '0.00',
      per: '-', perEff: '-', percv: '0.00', same: false, on: '-', face: '-', nvis: false, nhit: false, bvis: false, pvis: false, raw: miss,
    );
  }
  final f0 = _filtersOf(nameF);
  final faceC = Color.alphaBlend(t.widget<Material>(find.ancestor(of: nameF, matching: find.byType(Material)).first).color ?? Colors.transparent, Colors.white);
  final bfaceC = _faceOf(t, badgeF);
  final bfgC = _fgOf(t, badgeF);
  final icons = find.descendant(of: find.ancestor(of: badgeF, matching: find.byType(Container)).first, matching: find.byType(Icon), skipOffstage: false).evaluate().toList();
  final bicoC = icons.length == 1 ? (icons.first.widget as Icon).color : null;
  final bUnder = Color.alphaBlend(bfaceC, faceC);
  // 덮개를 지난 표시 색(글 화소 · 바탕 화소 모두 같은 필터를 지난다) — 덮개가 base 의 것이 아니면 '?' · 대비 0.
  String effHex(Color ink0, Color under) => f0.known ? _hex(_through(Color.alphaBlend(ink0, under), f0.n)) : '?';
  double effCv(Color ink0, Color under) => f0.known ? _contrast(_through(Color.alphaBlend(ink0, under), f0.n), _through(under, f0.n)) : 0.0;
  final nameC = _fgOf(t, nameF);
  final perC = _fgOf(t, perF);
  final bCv = effCv(bfgC, bUnder);
  final nCv = effCv(nameC, faceC);
  final pCv = effCv(perC, faceC);
  final nameEff = effHex(nameC, faceC);
  final perEff = effHex(perC, faceC);
  final calF = find.descendant(of: cardF, matching: find.byIcon(Icons.calendar_today_outlined, skipOffstage: false), skipOffstage: false);
  final wdF = find.descendant(of: find.ancestor(of: calF, matching: find.byType(Row)).first, matching: find.byType(Text, skipOffstage: false), skipOffstage: false);
  final wtF = find.descendant(of: cardF, matching: find.text(_wtText, skipOffstage: false), skipOffstage: false);
  final wdEff = wdF.evaluate().length == 1 ? effHex(_fgOf(t, wdF), faceC) : '-';
  final wtEff = wtF.evaluate().length == 1 ? effHex(_fgOf(t, wtF), faceC) : '-';
  // 활성 카드와 같은 잉크인가 — 비근무 카드의 이름 · 기간 · 요일 · 업무 표시 색 = 활성 카드의 선언 색.
  final same = nameEff == ref.name && perEff == ref.per && wdEff == ref.wd && wtEff == ref.wt;
  // 도달 — 이름 · 배지 · 기간을 하나씩 명단 칸 안으로(ensureVisible) 넣고 칸 안인가 · 이름 중심 hit(DU543 r3 reach 와 같은 식).
  await t.ensureVisible(nameF);
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final pn = _tapNow(t, nameF, dlg, screen);
  await t.ensureVisible(badgeF);
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final pb = _tapNow(t, badgeF, dlg, screen);
  await t.ensureVisible(perF);
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final pp = _tapNow(t, perF, dlg, screen);
  final raw = 'who $who lab $lab nf ${f0.n} known ${f0.known} badge ${_hex(bfaceC)}/${_hex(bfgC)} cv ${bCv.toStringAsFixed(2)} name ${_hex(nameC)}->$nameEff cv ${nCv.toStringAsFixed(2)} '
      'per ${_hex(perC)}->$perEff cv ${pCv.toStringAsFixed(2)} wd $wdEff wt $wtEff ref ${ref.name}/${ref.per}/${ref.wd}/${ref.wt} same $same on ${ink.on} '
      'name ${pn.r} vis ${pn.vis} hit ${pn.hit} badge ${pb.r} vis ${pb.vis} per ${pp.r} vis ${pp.vis}';
  return (
    lab: _enc(lab), nf: f0.n, known: f0.known, bface: _hex(bfaceC), bfg: _hex(bfgC), bico: bicoC == null ? '-' : _hex(bicoC), bcr: bCv >= 4.5,
    bcv: bCv.toStringAsFixed(2), name: _hex(nameC), nameEff: nameEff, namecr: nCv >= 4.5, namecv: nCv.toStringAsFixed(2), per: _hex(perC),
    perEff: perEff, percv: pCv.toStringAsFixed(2), same: same, on: ink.on, face: ink.face, nvis: pn.vis, nhit: pn.hit, bvis: pb.vis, pvis: pp.vis, raw: raw,
  );
}

typedef _SectObs = ({int n, String cnt, String fg, String cv, bool vis});

/// 비근무 구역 이름('오늘 비근무 (n명)') — ensureVisible 뒤 수 · 괄호 안 숫자 · 글 색 · 흰 바탕 가정 대비(기록) · 명단 칸 안인가. 이 셀은 바꾸지 않는다(판정 범위 밖 · 후보).
Future<_SectObs> _sectNow(WidgetTester t, Finder sectF, Finder dlg, Rect screen) async {
  await t.ensureVisible(sectF);
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final fgC = _fgOf(t, sectF);
  final m = RegExp(r'\((\d+)명\)').firstMatch(visibleText(t.widget<Text>(sectF).data ?? ''));
  final p = _tapNow(t, sectF, dlg, screen);
  return (n: 1, cnt: m?.group(1) ?? '-', fg: _hex(fgC), cv: _contrast(fgC, Colors.white).toStringAsFixed(2), vis: p.vis);
}

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
const _cases = <({String id, int shots})>[(id: 'WKND', shots: 2), (id: 'OUTP', shots: 2)];

/// 사례별 — 비근무 구역 카드 이름(이 순서로 정렬된다는 가정 없음 · 먼저 보이는 것부터 잰다) · 그 배지 글 · 구역 이름의 인원 수.
const _inactive = <String, List<String>>{'WKND': ['이나래', '박다온'], 'OUTP': ['이나래']};
const _labOff = '비근무일';
const _labOut = '계약기간 외';
const _inactiveLabels = <String>[_labOff, _labOut];
const _wantLab = <String, String>{'WKND': _labOff, 'OUTP': _labOut};
/// 글 원문.
const _titleText = '고정근무자 관리';
const _emptyText = '고정근무자가 없습니다';
const _failText = '고정근무자 목록을 불러오지 못했어요';
const _dateTitleTail = '근무 현황';
const _pendChipText = '대기 1건';
const _sectPart = '오늘 비근무';
const _wtText = '홀서빙';
/// 활성 카드 기준(맨 위 카드 · 두 사례 모두 활성 구역).
const _refName = '김가람';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '548';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du548-tb' && _env['DU_BEFORE_OBSERVE'] == '548') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du548-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
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
    _out('R548 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S948FI-${v.id}-${c.id} 고정근무자 관리 창 날짜 모드 비근무 구역 — 비근무일 · 계약기간 외 배지 textSecondary · 카드 흰 덮개 제거 · 이름 기간 잉크 보존', (t) async {
        final tok = 'S948FI-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');

        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final wire = _Wire(c.id);
        final net = _NoHttp();
        final prevAll = messenger.allMessagesHandler;
        final prevHttp = HttpOverrides.current;
        final prevOnError = FlutterError.onError;
        messenger.allMessagesHandler = (channel, handler, message) => wire.route(messenger, channel, handler, message);
        HttpOverrides.global = net;
        addTearDown(() {
          messenger.allMessagesHandler = prevAll;
          HttpOverrides.global = prevHttp;
          FlutterError.onError = prevOnError;
        });
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final screen = Offset.zero & Size(v.w, v.h);
        final mode = _before ? 'before' : 'strict';
        _out('D548 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        final owner = _Owner();
        final isWknd = c.id == 'WKND';
        final isB = v.id == 'B';
        final who = _inactive[c.id]!;
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
                  body: FixedWorkerManagementDialog(
                    key: UniqueKey(),
                    initialBusinessId: _biz1,
                    businesses: [_business(_biz1, _bizName)],
                    focusDate: _focusDay(isWknd ? _saturdayAhead() : _weekdayAhead()),
                    onChanged: () {},
                  ),
                ),
              ),
            ),
          ));
          for (var i = 0; i < 40; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          final dlg = find.byType(FixedWorkerManagementDialog);
          final nDlg = dlg.evaluate().length;
          need('창 1', nDlg == 1, '개수 $nDlg');
          final nTitle = find.text(_titleText).evaluate().length;
          need('창 제목 1', nTitle == 1, '개수 $nTitle');

          Future<void> shot(String id, String state) async {
            _out('D548 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          // 그려진 글 집합(첫 화면 · 보이는 글 기준 · 숫자는 # 으로). 기록용 — TB = TA 는 로그 대조(후보는 문구를 바꾸지 않는다).
          final words = <String>{};
          for (final e in find.descendant(of: dlg, matching: find.byType(Text), skipOffstage: true).evaluate()) {
            final d = (e.widget as Text).data;
            if (d != null && d.isNotEmpty) words.add(visibleText(d).replaceAll(RegExp(r'\d+'), '#'));
          }
          final wordList = words.toList()..sort();
          _out('D548 $tok att txt n=${wordList.length} set=${_enc(wordList.join('|'))}');

          // ① 첫 화면 — 본문 · 날짜 머리 띠 통계 칸 수(fixture 확인) · 활성 카드(맨 위 김가람) 기준 잉크.
          final b0 = _bodyNow(t, dlg);
          _out('D548 $tok att body emptyn=${b0.emptyN} failn=${b0.failN} toastn=${b0.toastN} icon=${b0.icon}');
          final br0 = 'empty ${b0.emptyN} fail ${b0.failN} toast ${b0.toastN} icon ${b0.icon}';
          need('날짜 모드 본문 — 빈 상태 문구 0 · 실패 안내 0 · 토스트 0', b0.emptyN == 0 && b0.failN == 0 && b0.toastN == 0, br0);
          final h0 = _headNow(t, dlg);
          _out('D548 $tok att head nn=${h0.nn} nl=${h0.nl} nx=${h0.nx} np=${h0.np} vn=${h0.vn} pc=${h0.pc}');
          final hr = 'chips ${h0.nn}/${h0.nl}/${h0.nx}/${h0.np} vn ${h0.vn} pc ${h0.pc}';
          // WKND = 토요일(출근예정 서다솜 · 대기 김가람 · 비근무 2) · OUTP = 평일(출근예정 김가람 · 휴무 박다온 · 추가근무 서다솜 · 계약기간 외 이나래 — 출근예정 1 이 이나래를 뺀 증거).
          need(isWknd ? '머리 띠 — 출근예정 1(1명) · 휴무 0 · 추가근무 0 · 대기 1 · 대기 1건 칩 1' : '머리 띠 — 출근예정 1(1명) · 휴무 1 · 추가근무 1 · 대기 0 · 대기 칩 0',
              isWknd
                  ? (h0.nn == 1 && h0.nl == 0 && h0.nx == 0 && h0.np == 1 && h0.vn == 1 && h0.pc == 1)
                  : (h0.nn == 1 && h0.nl == 1 && h0.nx == 1 && h0.np == 0 && h0.vn == 1 && h0.pc == 0),
              hr);
          final ref = _inkOf(t, dlg, _refName);
          _out('D548 $tok att ref name=${ref.name} per=${ref.per} wd=${ref.wd} wt=${ref.wt} nf=${ref.nf} on=${ref.on} face=${ref.face}');
          final rr = 'name ${ref.name} per ${ref.per} wd ${ref.wd} wt ${ref.wt} nf ${ref.nf} on ${ref.on} face ${ref.face}';
          raw = 'body $br0 head $hr ref $rr';
          chk('활성 카드(김가람) 기준 잉크 — 이름 grey700 · 기간 grey500 · 요일 grey500 · 업무 grey600 · 덮개 0 · 카드 탭 있음 · 흰 면(base 소스 그대로)',
              ref.name == _wantGrey700 && ref.per == _wantGrey500 && ref.wd == _wantGrey500 && ref.wt == _wantGrey600 && ref.nf == 0 && ref.on == 'true' && ref.face == _wantWhite, rr);
          await shot(isWknd ? '1wkend' : '1outp', isWknd ? 'date-weekend-first-screen' : 'date-outperiod-first-screen');

          // ② 비근무 구역 도달 — 명단 칸(창 안 ListView 하나의 Scrollable)을 실제로 끌어(한 번 60px · 최대 40번 · 개수 가드) 구역 이름과 카드 이름이
          //   트리(구역 이름)/onstage(카드 이름)가 되면 그 자리에서 잰다(DU543 r3 끌기 도달과 같은 식 · W 는 끌기 0 일 수 있다). 누르지 않는다.
          final listV = find.descendant(of: dlg, matching: find.byType(ListView), skipOffstage: false);
          final nLv = listV.evaluate().length;
          need('명단 ListView 1', nLv == 1, '개수 $nLv');
          final listSc = find.descendant(of: listV, matching: find.byType(Scrollable), skipOffstage: false).first;
          final sectF = find.descendant(of: dlg, matching: findVisibleTextContaining(_sectPart), skipOffstage: false);
          final measured = <String>{};
          var sect = (n: 0, cnt: '-', fg: '-', cv: '0.00', vis: false);
          var sectDone = false;
          var drags = 0;
          var cardRaw = '';
          while ((measured.length < who.length || !sectDone) && drags < 40) {
            if (!sectDone && sectF.evaluate().length == 1) {
              sect = await _sectNow(t, sectF, dlg, screen);
              sectDone = true;
              continue;
            }
            String? next;
            for (final n in who) {
              if (!measured.contains(n) && find.descendant(of: dlg, matching: find.text(n), skipOffstage: true).evaluate().length == 1) {
                next = n;
                break;
              }
            }
            if (next != null) {
              final co = await _cardNow(t, dlg, screen, next, ref);
              measured.add(next);
              _out('D548 $tok att card lab=${co.lab} nf=${co.nf} known=${co.known} bface=${co.bface} bfg=${co.bfg} bico=${co.bico} bcr=${co.bcr} bcv=${co.bcv} name=${co.name} nameeff=${co.nameEff} namecr=${co.namecr} namecv=${co.namecv} per=${co.per} pereff=${co.perEff} percv=${co.percv} same=${co.same} on=${co.on} face=${co.face} nvis=${co.nvis} nhit=${co.nhit} bvis=${co.bvis} pvis=${co.pvis}');
              cardRaw = '$cardRaw | ${co.raw}';
              chk('$next 배지 글 = ${_wantLab[c.id]}(이 사례의 비근무 배지) · 면 grey100(그대로) · 카드 흰 면 · 카드 탭 있음(onTap 그대로 · 누르지 않음)',
                  co.lab == _enc(_wantLab[c.id]!) && co.bface == _wantGrey100 && co.face == _wantWhite && co.on == 'true', co.raw);
              chk('$next 이름 grey700 · 기간 grey500(선언 잉크 — 이 셀은 카드 글 색을 바꾸지 않는다)', co.name == _wantGrey700 && co.per == _wantGrey500, co.raw);
              if (!_before) {
                chk('strict $next 배지 — 글 · 아이콘 textSecondary · 덮개를 지난 글/면 대비 ≥4.5', co.bfg == _wantText2 && co.bico == _wantText2 && co.bcr, co.raw);
                chk('strict $next 카드 덮개(ColorFiltered) 0 — 이름 · 기간 표시 색 = 선언 잉크 · 이름 대비 ≥4.5', co.nf == 0 && co.nameEff == co.name && co.perEff == co.per && co.namecr, co.raw);
                chk('strict $next 이름 · 기간 · 요일 · 업무 표시 색 = 활성 카드(김가람) 잉크', co.same, co.raw);
                chk('strict $next 도달 — 이름 · 배지 · 기간 각각 명단 칸 안 · 이름 중심 hit', co.nvis && co.nhit && co.bvis && co.pvis, co.raw);
              }
              continue;
            }
            await t.drag(listSc, const Offset(0, -60));
            await t.pump(const Duration(milliseconds: 50));
            drags++;
          }
          need('비근무 구역 이름 1 · 비근무 카드 ${who.length}장 모두 잼(끌기 최대 40번)', sectDone && measured.length == who.length, 'sect $sectDone cards ${measured.length} drags $drags');
          _out('D548 $tok att sect n=${sect.n} cnt=${sect.cnt} fg=${sect.fg} cv=${sect.cv} vis=${sect.vis}');
          final sr = 'n ${sect.n} cnt ${sect.cnt} fg ${sect.fg} cv ${sect.cv} vis ${sect.vis}';
          final wantCnt = who.length.toString();
          chk('비근무 구역 이름 — 인원 $wantCnt · 글 grey400(이 셀은 바꾸지 않는다 · 대비는 기록)', sect.cnt == wantCnt && sect.fg == _wantGrey400, sr);
          final nCf = find.descendant(of: dlg, matching: find.byType(ColorFiltered), skipOffstage: false).evaluate().length;
          _out('D548 $tok att filt n=$nCf cards=${measured.length} drags=$drags');
          final fr = 'colorfiltered $nCf cards ${measured.length} drags $drags';
          raw = '$raw sect $sr filt $fr cards$cardRaw';
          if (!_before) chk('strict 창 안 ColorFiltered 0(비근무 카드 덮개 제거)', nCf == 0, fr);
          // 둘째 캡처 자리 — 구역 이름이 트리에 있으면 그것을 칸 맨 위로(구역 이름 + 비근무 카드), 없으면 마지막 비근무 카드 이름을 맨 위로. 측정은 위에서 끝났다.
          final lastF = find.descendant(of: dlg, matching: find.text(who.last, skipOffstage: false), skipOffstage: false);
          final capF = sectF.evaluate().length == 1 ? sectF : lastF;
          if (capF.evaluate().length == 1) {
            await t.ensureVisible(capF);
            for (var i = 0; i < 10; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
          }
          await shot(isWknd ? '2wkinact' : '2outinact', isWknd ? 'date-weekend-inactive-in-view' : 'date-outperiod-inactive-in-view');
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ③ 성공 · 실패 공통 정리 — 창을 내리고 남은 timer 가 끝날 시간을 준다.
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

        // ④ 집계 — 읽기 호출 수 · 차단된 쓰기/허용 밖 CF 수 · 그 밖 Firestore 연산 · 예상 밖 채널 · HTTP.
        final nApps = wire.calls[_appsFn] ?? 0;
        final nProps = wire.calls['callableGetRenewalProposalsByBiz'] ?? 0;
        final nUsers = wire.calls['callableGetUsersBatch'] ?? 0;
        final nSched = wire.calls[_schedFn] ?? 0;
        final nWt = wire.calls['workTypes'] ?? 0;
        final nWrites = wire.blocked.length;
        final nOtherFs = wire.otherFs.length;
        final nUnexp = wire.unexpected.length;
        final nHttp = net.tries.length;
        final nHarness = wire.harness.length;
        final unText = [...wire.unexpected, ...wire.blocked, ...wire.otherFs.map((x) => 'fs $x'), ...wire.harness].join(' | ');
        _out('D548 $tok att wire apps=$nApps props=$nProps users=$nUsers wt=$nWt sched=$nSched writes=$nWrites otherfs=$nOtherFs unexpected=$nUnexp http=$nHttp harness=$nHarness');

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
        _out('R548 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D548 $tok att fw n=$nFw');
        _out('D548 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        // 날짜 모드 B(320×640 · 글자 2.0)의 넘침 · 그에 딸린 framework 오류는 기록만(DU540 · DU543 B 날짜 모드 overflows=3 관측 · TB ≥ TA 손 대조 · 이 셀은 배치를 바꾸지 않는다).
        chk('쓰기 · 허용 밖 CF 0 · HTTP 0 · 대역 오류 0', nWrites == 0 && nHttp == 0 && nHarness == 0, unText);
        chk('읽기 대역 호출(지원서 1 · 업무유형 ≥1 · 일정 요청 1)', nApps == 1 && nWt >= 1 && nSched == 1, 'apps $nApps wt $nWt sched $nSched');
        if (!_before && !isB) chk('strict W 화면 전체 넘침 0', nOvf == 0, ovfRaw);
        if (!_before && !isB) chk('strict W 미처리 framework 예외 0', nFw == 0, fwRaw);
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
