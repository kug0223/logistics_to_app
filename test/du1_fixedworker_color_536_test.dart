// ignore_for_file: depend_on_referenced_packages
// [DU536 · 표시만] 고정근무자 관리 창(FixedWorkerManagementDialog) 일반(목록) 모드 색 1차 — 감사134 §4 PP-FIXEDWORKER-COLOR-20261119.
//   J4 · J5 통계 칸(면 · 선 · 라벨 중립 · 숫자만 뜻 색)  J6 연장 = brand 채움 · 종료(진입) = 면 없는 textSecondary  J7 결정 완료 띠 중립
//   J8 '계약 처리 필요' = 중립 본문 + 작은 warning 표기  B2 '일괄 연장' brand 글  B3 '연장 응답 대기' 띠 중립  B4 D-day 칩(16일 이상 = 중립 · 15일 이하 = 진한 글 + 옅은 짝 면)
//   before = 현재 A(fixed_worker_management_dialog f4967dea) 기록 전용 · strict = 후보(5ace123c).
//   이 창을 그리는 첫 하네스다(생성자 주입 0 · FirestoreService 싱글턴) — 첫 화면 읽기를 플랫폼 채널 대역으로 답한다:
//     CF callableGetApplicationsByBiz · callableGetRenewalProposalsByBiz · callableGetUsersBatch(선례 du1_o097_workforce_month_calendar_293_test.dart:221–263)
//     Firestore queryGet businesses/biz1/workTypes(선례 du1_c1_edit_discard_test.dart:87–115). 그 밖 CF · Firestore 쓰기는 차단하고 센다(writes = 0 단언).
//   상태 6: RENEW · WAIT · SIGN · ENDED(같은 5명 대역 · initialWorkerUid 로 한 사람 카드만 세운다) · EMPTY(성공 빈 목록) · FAIL(지원서 조회 실패 — 지금 모습 기록 · DU537 대상).
//   서버로 가는 버튼(연장 · 종료 · 일괄 연장 · 카드 탭)은 누르지 않는다 — 열고 색만 잰다(위젯 값 · rect 0).
//   기본 skip — TB before/du536-tb/DU_BEFORE_OBSERVE=536 · TA after/du536-ta/없음.
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

/// 소유자(BUSINESS_ADMIN) — DU526 · DU534 _Owner 와 같은 override(창은 `canForBusiness` · `watchBusinessPermissions` 를 부른다).
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

BusinessModel _business() => BusinessModel(
    id: _biz1, name: _bizName, ownerId: 'admin1', businessNumber: '000-00-00000', address: '서울시 어딘가',
    category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1));

/// 오늘(KST) + [d]일의 KST 자정(UTC ms) — 창의 `FormatHelper.toKstDate` 와 같은 달력.
int _kstDayMs(int d) {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day + d).subtract(const Duration(hours: 9)).millisecondsSinceEpoch;
}

/// CF 응답의 시각 표기(서버 serializeFirestoreData 형식 — 앱이 `_cfHydrate` 로 Timestamp 로 되돌린다).
Map<String, Object?> _ts(int ms) => <String, Object?>{'_seconds': ms ~/ 1000, '_nanoseconds': 0};

/// 장기 확정 지원서 한 건 — 종료일 = 오늘 + [endIn]일.
Map<String, Object?> _app(String id, String applicant, int endIn, {String status = 'CONFIRMED', Map<String, Object?> extra = const <String, Object?>{}}) => <String, Object?>{
      'id': id, 'uid': 'u_$id', 'businessId': _biz1, 'businessName': _bizName, 'toId': 'to1', 'toTitle': '장기 모집',
      'selectedWorkType': '홀서빙', 'startTime': '09:00', 'endTime': '18:00', 'status': status, 'type': 'long_term',
      'applicantName': applicant, 'wage': 12000, 'wageType': 'hourly', 'workDays': const <Object?>['월', '화', '수', '목', '금'],
      'workDate': _ts(_kstDayMs(-30)), 'workEndDate': _ts(_kstDayMs(endIn)),
      'appliedAt': _ts(_kstDayMs(-32)), 'confirmedAt': _ts(_kstDayMs(-31)),
      ...extra,
    };

const _names = <String, String>{'u_a1': '김연장', 'u_a2': '이대기', 'u_a3': '박서명', 'u_a4': '최종료', 'u_a5': '정해지'};

/// 대역 5명(호출마다 새로 만든다) — a1 만료 10일 전(결정 필요 띠 · 연장/종료) · a2 만료 5일 전 + 연장 제안 응답 대기 ·
///   a3 계약 처리 필요(CONTRACT_PENDING · 25일) · a4 종료 결정(TERMINATE · 40일) · a5 해지 요청 중(60일 · 통계 '해지대기').
List<Object?> _apps() => <Object?>[
      _app('a1', '김연장', 10),
      _app('a2', '이대기', 5),
      _app('a3', '박서명', 25, status: 'CONTRACT_PENDING'),
      _app('a4', '최종료', 40, extra: <String, Object?>{'renewalDecision': 'TERMINATE'}),
      _app('a5', '정해지', 60, extra: <String, Object?>{'terminationStatus': 'PENDING', 'terminationRequestedAt': _ts(_kstDayMs(-1))}),
    ];

/// a2 의 연장 제안(응답 대기) — 효력 시작 = 지금 종료일 다음 날(미래 → 응답 가능).
Map<String, Object?> _proposal() => <String, Object?>{
      'id': 'rp1', 'businessId': _biz1, 'businessName': _bizName, 'workerUid': 'u_a2', 'oldApplicationId': 'a2', 'status': 'PENDING',
      'effectiveStart': _ts(_kstDayMs(6)), 'effectiveEnd': _ts(_kstDayMs(36)), 'selectedWorkType': '홀서빙',
    };

const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
const _wtPath = 'businesses/$_biz1/workTypes';

/// 첫 화면이 부르는 읽기 CF(일반 모드) — 이 밖의 CF 이름은 차단하고 센다.
const _readFns = <String>{'callableGetApplicationsByBiz', 'callableGetRenewalProposalsByBiz', 'callableGetUsersBatch'};

/// Firestore 쓰기 연산 — 하나라도 오면 writes 로 센다.
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

/// [DU526 · DU534 와 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널.
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du536.fake.auth.';
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

/// 모든 플랫폼 메시지 관찰 — 읽기 CF 3종 · workTypes 질의는 대역 응답, 그 밖 CF/Firestore 는 차단 응답 + 기록,
///   기반 채널은 원래 경로, 나머지는 이름을 기록하고 응답 null. 예외를 삼키지 않는다 — 수는 줄로 남긴다.
class _Wire {
  _Wire(this.kind);

  /// 사례 이름 — EMPTY(성공 빈 목록) · FAIL(지원서 조회만 실패) · 그 밖(5명 대역).
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
        return codec.encodeMessage(<Object?>['not-found', 'du536-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      _hit(fn);
      if (fn == 'callableGetApplicationsByBiz') {
        if (kind == 'FAIL') {
          return codec.encodeMessage(<Object?>['unavailable', 'du536 local failure', <String, Object?>{'code': 'unavailable', 'message': 'du536 local failure'}]);
        }
        return codec.encodeMessage(<Object?>[<String, Object?>{'applications': kind == 'EMPTY' ? const <Object?>[] : _apps()}]);
      }
      if (fn == 'callableGetRenewalProposalsByBiz') {
        return codec.encodeMessage(<Object?>[<String, Object?>{'proposals': kind == 'EMPTY' || kind == 'FAIL' ? const <Object?>[] : <Object?>[_proposal()]}]);
      }
      final uids = (params['uids'] as List).cast<String>();
      return codec.encodeMessage(<Object?>[
        <String, Object?>{
          'users': <String, Object?>{for (final u in uids) u: <String, Object?>{'name': _names[u] ?? '근로자', 'role': 'USER'}},
        },
      ]);
    } catch (e) {
      harness.add('cf $e');
      return codec.encodeMessage(<Object?>['internal', 'du536-harness', null]);
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
      return codec.encodeMessage(<Object?>['du536-blocked', '$op 차단', null]);
    } catch (e) {
      harness.add('fs $op $e');
      return codec.encodeMessage(<Object?>['du536-harness', '대역 오류', null]);
    }
  }
}

/// 외부 HTTP 차단 — 만들려는 시도를 기록하고 실패시킨다.
class _NoHttp extends HttpOverrides {
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    throw const SocketException('DU536 관측 — 외부 HTTP 차단');
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

/// [f](글)에서 가장 가까운 Container 안 [icon] 의 수와 색(하나일 때만 색 · 아니면 '-').
(int, String) _iconIn(WidgetTester t, Finder f, IconData icon) {
  final box = find.ancestor(of: f, matching: find.byType(Container)).first;
  final icons = find.descendant(of: box, matching: find.byIcon(icon), skipOffstage: true).evaluate().toList();
  if (icons.length != 1) return (icons.length, '-');
  final ic = (icons.first.widget as Icon).color;
  return (1, ic == null ? '-' : _hex(ic));
}

final String _wantBrand = _hex(AppColors.brand);
final String _wantWhite = _hex(Colors.white);
final String _wantClear = _hex(Colors.transparent);
final String _wantLine = _hex(AppColors.border);
final String _wantText1 = _hex(AppColors.textPrimary);
final String _wantText2 = _hex(AppColors.textSecondary);
final String _wantGrey100 = _hex(AppColors.grey100);
final String _wantGrey600 = _hex(AppColors.grey600);
final String _wantWarnBg = _hex(AppColors.warningBg);
final String _wantWarnDark = _hex(AppColors.warningDark);
final String _wantErrBg = _hex(AppColors.errorBg);
final String _wantErrDark = _hex(AppColors.errorDark);

/// 통계 줄 바탕(grey50) — 칩 면이 반투명일 때 대비를 재는 밑색.
const Color _statsUnder = AppColors.grey50;

typedef _ChipObs = ({int n, String face, String bd, String lab, String bub, String num, bool cr});

/// 통계 칸 하나([label]) — 칸 면 · 선 · 라벨 글 · 숫자 방울 면 · 숫자 글 색과 대비(라벨/칸 면 · 숫자/방울 면). 위젯 값만 읽는다.
_ChipObs _chip(WidgetTester t, String label) {
  final labF = find.text(label);
  final n = labF.evaluate().length;
  if (n != 1) return (n: n, face: '-', bd: '-', lab: '-', bub: '-', num: '-', cr: false);
  final chipF = find.ancestor(of: labF, matching: find.byType(Container)).first;
  final faceC = _faceOf(t, labF);
  final labC = _fgOf(t, labF);
  final bd = _edgeOf(t, labF);
  final texts = find.descendant(of: chipF, matching: find.byType(Text), skipOffstage: true).evaluate().map((e) => e.widget as Text).toList();
  final boxes = find.descendant(of: chipF, matching: find.byType(Container), skipOffstage: true).evaluate().map((e) => e.widget as Container).toList();
  if (texts.length != 2 || boxes.length != 1) return (n: n, face: _hex(faceC), bd: bd, lab: _hex(labC), bub: '-', num: '-', cr: false);
  final bubDeco = boxes.first.decoration;
  final bubC = bubDeco is BoxDecoration ? (bubDeco.color ?? Colors.transparent) : Colors.transparent;
  final numC = texts.last.style?.color ?? Colors.black;
  final under = Color.alphaBlend(faceC, _statsUnder);
  final cr = _contrast(labC, under) >= 4.5 && _contrast(numC, Color.alphaBlend(bubC, under)) >= 4.5;
  return (n: n, face: _hex(faceC), bd: bd, lab: _hex(labC), bub: _hex(bubC), num: _hex(numC), cr: cr);
}

typedef _StatsObs = ({int n0, int n1, int nx, String face, String bd, String lab, String bub, String num0, String num1, String numx, bool cr, String raw});

/// 통계 줄 — '전체' · '근무중' · (있으면) '해지대기'. 출력 한 줄(키 고정).
_StatsObs _statsLine(WidgetTester t, String tok) {
  final c0 = _chip(t, '전체');
  final c1 = _chip(t, '근무중');
  final cx = _chip(t, '해지대기');
  final shown = [c0, c1, if (cx.n == 1) cx];
  final face = _one(shown.map((x) => x.face));
  final bd = _one(shown.map((x) => x.bd));
  final lab = _one(shown.map((x) => x.lab));
  final bub = _one(shown.map((x) => x.bub));
  final cr = shown.every((x) => x.cr);
  _out('D536 $tok att stats n0=${c0.n} n1=${c1.n} nx=${cx.n} face=$face bd=$bd lab=$lab bub=$bub num0=${c0.num} num1=${c1.num} numx=${cx.num} cr45=$cr');
  return (
    n0: c0.n, n1: c1.n, nx: cx.n, face: face, bd: bd, lab: lab, bub: bub, num0: c0.num, num1: c1.num, numx: cx.num, cr: cr,
    raw: 'n ${c0.n}/${c1.n}/${cx.n} face $face bd $bd lab $lab bub $bub num ${c0.num}/${c1.num}/${cx.num} cr $cr',
  );
}

/// 통계 칸 단언(strict) — 바깥 면 · 선 · 라벨 중립 · 방울 grey100 · 전체/근무중 숫자 textPrimary · (있으면) 해지대기 숫자 errorDark.
List<(String, bool, String)> _statsChecks(_StatsObs so, {required bool withRisk}) => [
      ('strict 통계 칸 면 = 흰색 · 선 = border · 라벨 = textSecondary · 숫자 방울 = grey100', so.face == _wantWhite && so.bd == _wantLine && so.lab == _wantText2 && so.bub == _wantGrey100, so.raw),
      ('strict 전체 · 근무중 숫자 = textPrimary', so.num0 == _wantText1 && so.num1 == _wantText1, so.raw),
      if (withRisk) ('strict 해지대기 칸 1 · 숫자 = errorDark', so.nx == 1 && so.numx == _wantErrDark, so.raw),
      ('strict 통계 칸 글/면 대비 ≥4.5', so.cr, so.raw),
    ];

typedef _BulkObs = ({int n, String fg, String btnFg, String face, bool cr, String raw});

/// 만료 임박 띠의 '일괄 연장' — 글자색 · 버튼 foreground · 띠 면 · 대비. 누르지 않는다.
_BulkObs _bulkLine(WidgetTester t, String tok) {
  final f = find.text('일괄 연장');
  final n = f.evaluate().length;
  var fg = '-';
  var btnFg = '-';
  var face = '-';
  var cr = false;
  if (n == 1) {
    final fgC = _fgOf(t, f);
    final faceC = _faceOf(t, f);
    final btns = find.ancestor(of: f, matching: find.byType(TextButton)).evaluate().toList();
    final style = btns.isEmpty ? null : (btns.first.widget as TextButton).style;
    final resolved = style?.foregroundColor?.resolve(<WidgetState>{});
    fg = _hex(fgC);
    btnFg = resolved == null ? '-' : _hex(resolved);
    face = _hex(faceC);
    cr = _contrast(fgC, Color.alphaBlend(faceC, Colors.white)) >= 4.5;
  }
  _out('D536 $tok att bulk n=$n fg=$fg btnfg=$btnFg face=$face cr45=$cr');
  return (n: n, fg: fg, btnFg: btnFg, face: face, cr: cr, raw: 'n $n fg $fg btnfg $btnFg face $face cr $cr');
}

typedef _DdayObs = ({int n, String fg, String face, String bd, bool cr, String raw});

/// 카드의 D-day 칩([label] = 'D-n') — 글 · 면 · 선 색과 대비(카드 흰 면 기준).
_DdayObs _ddayLine(WidgetTester t, String tok, String label) {
  final f = find.text(label);
  final n = f.evaluate().length;
  var fg = '-';
  var face = '-';
  var bd = '-';
  var cr = false;
  if (n == 1) {
    final fgC = _fgOf(t, f);
    final faceC = _faceOf(t, f);
    fg = _hex(fgC);
    face = _hex(faceC);
    bd = _edgeOf(t, f);
    cr = _contrast(fgC, Color.alphaBlend(faceC, Colors.white)) >= 4.5;
  }
  _out('D536 $tok att dday n=$n fg=$fg face=$face bd=$bd cr45=$cr');
  return (n: n, fg: fg, face: face, bd: bd, cr: cr, raw: '$label n $n fg $fg face $face bd $bd cr $cr');
}

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
const _cases = <({String id, int shots})>[(id: 'RENEW', shots: 1), (id: 'WAIT', shots: 1), (id: 'SIGN', shots: 1), (id: 'ENDED', shots: 1), (id: 'EMPTY', shots: 1), (id: 'FAIL', shots: 1)];

/// 사례별 — 한 사람 카드만 세우는 uid(창의 initialWorkerUid) · 그 카드의 D-day 글 · 캡처 이름.
const _focus = <String, String>{'RENEW': 'u_a1', 'WAIT': 'u_a2', 'SIGN': 'u_a3', 'ENDED': 'u_a4'};
const _dday = <String, String>{'RENEW': 'D-10', 'WAIT': 'D-5', 'SIGN': 'D-25', 'ENDED': 'D-40'};

/// 글 원문 — 문구 불변 기준(두 모드에서 같은 수로 보여야 한다).
const _titleText = '고정근무자 관리';
const _waitText = '연장 응답 대기 — 근무자가 제안을 확인하고 있습니다';
const _signTitle = '계약 처리 필요';
const _signDesc = '계약서를 작성하거나 계약 진행 상태를 확인해 주세요.';
const _endedText = '계약 종료 예정';
const _emptyText = '고정근무자가 없습니다';
const _failToast = '고정근무자 목록을 불러올 수 없습니다';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '536';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du536-tb' && _env['DU_BEFORE_OBSERVE'] == '536') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du536-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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
    _out('R536 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S904FW-${v.id}-${c.id} 고정근무자 관리 창 색 1차 — 통계 · 연장/종료 · 띠 · D-day', (t) async {
        final tok = 'S904FW-${v.id}-${c.id}';
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
        final mode = _before ? 'before' : 'strict';
        _out('D536 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        final owner = _Owner();
        final isList = _focus.containsKey(c.id);
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
                    businesses: [_business()],
                    initialWorkerUid: _focus[c.id],
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
            _out('D536 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          // 그려진 글 집합(숫자는 # 으로 — 날짜 · 인원 수는 실행일에 따라 달라진다). 기록용: TB · TA 의 set 을 손으로 대조한다.
          final words = <String>{};
          for (final e in find.descendant(of: dlg, matching: find.byType(Text), skipOffstage: true).evaluate()) {
            final d = (e.widget as Text).data;
            if (d != null && d.isNotEmpty) words.add(d.replaceAll(RegExp(r'\d+'), '#'));
          }
          final wordList = words.toList()..sort();
          _out('D536 $tok att txt n=${wordList.length} set=${_enc(wordList.join('|'))}');

          if (isList) {
            // ① 통계 줄 · 만료 임박 띠('일괄 연장') · 카드의 D-day 칩 — 네 사례 공통.
            final so = _statsLine(t, tok);
            final bo = _bulkLine(t, tok);
            final dd = _ddayLine(t, tok, _dday[c.id]!);
            need('통계 칸 전체 · 근무중 · 해지대기 각 1', so.n0 == 1 && so.n1 == 1 && so.nx == 1, so.raw);
            need('일괄 연장 1', bo.n == 1, bo.raw);
            need('D-day 칩 1', dd.n == 1, dd.raw);
            final nName = find.text(_names[_focus[c.id]]!).evaluate().length;
            need('한 사람 카드(이름 글 ≥1)', nName >= 1, '개수 $nName');
            raw = 'stats ${so.raw} bulk ${bo.raw} dday ${dd.raw}';
            if (!_before) {
              for (final x in _statsChecks(so, withRisk: true)) {
                chk(x.$1, x.$2, x.$3);
              }
              chk('strict 일괄 연장 = brand 글(버튼 foreground · 자식 글 둘 다) · 띠 면 대비 ≥4.5', bo.fg == _wantBrand && bo.btnFg == _wantBrand && bo.cr, bo.raw);
              final alert = c.id == 'RENEW' || c.id == 'WAIT';
              final wantFg = c.id == 'RENEW' ? _wantWarnDark : (c.id == 'WAIT' ? _wantErrDark : _wantText2);
              final wantFace = c.id == 'RENEW' ? _wantWarnBg : (c.id == 'WAIT' ? _wantErrBg : _wantGrey100);
              chk('strict D-day 칩 글 · 면 = 단계 기대값(≤7 errorDark/errorBg · ≤15 warningDark/warningBg · 그 밖 textSecondary/grey100)',
                  dd.fg == wantFg && dd.face == wantFace, dd.raw);
              chk('strict D-day 칩 선(16일 이상 = border · 15일 이하 = 글 색 50%)', alert ? dd.bd == '80${wantFg.substring(2)}' : dd.bd == _wantLine, dd.raw);
              chk('strict D-day 칩 글/면 대비 ≥4.5', dd.cr, dd.raw);
            }

            // ② 사례별 카드 요소.
            if (c.id == 'RENEW') {
              // 결정 필요 띠의 '연장'(주요) · '종료'(확인창을 여는 진입) — 누르지 않는다.
              final extF = find.text('연장');
              final endF = find.text('종료');
              final nExt = extF.evaluate().length;
              final nEnd = endF.evaluate().length;
              var extBg = '-';
              var extFg = '-';
              var endBg = '-';
              var endFg = '-';
              var cr = false;
              if (nExt == 1 && nEnd == 1) {
                final under = Color.alphaBlend(_faceOf(t, extF), Colors.white);
                final extBgC = t.widget<Material>(find.ancestor(of: extF, matching: find.byType(Material)).first).color ?? Colors.transparent;
                final endBgC = t.widget<Material>(find.ancestor(of: endF, matching: find.byType(Material)).first).color ?? Colors.transparent;
                final extFgC = _fgOf(t, extF);
                final endFgC = _fgOf(t, endF);
                extBg = _hex(extBgC);
                extFg = _hex(extFgC);
                endBg = _hex(endBgC);
                endFg = _hex(endFgC);
                cr = _contrast(extFgC, Color.alphaBlend(extBgC, under)) >= 4.5 && _contrast(endFgC, Color.alphaBlend(endBgC, under)) >= 4.5;
              }
              _out('D536 $tok att renew extn=$nExt endn=$nEnd extbg=$extBg extfg=$extFg endbg=$endBg endfg=$endFg cr45=$cr');
              need('연장 · 종료 각 1', nExt == 1 && nEnd == 1, 'ext $nExt end $nEnd');
              final rr = 'ext $extBg/$extFg end $endBg/$endFg cr $cr';
              raw = '$raw renew $rr';
              if (!_before) {
                chk('strict 연장 = brand 채움 + 흰 글', extBg == _wantBrand && extFg == _wantWhite, rr);
                chk('strict 종료(진입) = 면 없음 + textSecondary 글', endBg == _wantClear && endFg == _wantText2, rr);
                chk('strict 연장 · 종료 글/면 대비 ≥4.5', cr, rr);
              }
              await shot('1renew', 'renew-banner');
            } else if (c.id == 'WAIT') {
              final wF = find.text(_waitText);
              final nW = wF.evaluate().length;
              var face = '-';
              var bd = '-';
              var fg = '-';
              var icon = '-';
              var cr = false;
              if (nW == 1) {
                final faceC = _faceOf(t, wF);
                final fgC = _fgOf(t, wF);
                face = _hex(faceC);
                bd = _edgeOf(t, wF);
                fg = _hex(fgC);
                icon = _iconIn(t, wF, Icons.hourglass_empty).$2;
                cr = _contrast(fgC, Color.alphaBlend(faceC, Colors.white)) >= 4.5;
              }
              _out('D536 $tok att wait n=$nW face=$face bd=$bd fg=$fg icon=$icon cr45=$cr');
              need('연장 응답 대기 띠 1', nW == 1, '개수 $nW');
              final wr = 'face $face bd $bd fg $fg icon $icon cr $cr';
              raw = '$raw wait $wr';
              if (!_before) {
                chk('strict 연장 응답 대기 띠 = 흰 면 · border 선 · textPrimary 글 · grey600 아이콘', face == _wantWhite && bd == _wantLine && fg == _wantText1 && icon == _wantGrey600, wr);
                chk('strict 연장 응답 대기 띠 글/면 대비 ≥4.5', cr, wr);
              }
              await shot('1wait', 'waiting-band');
            } else if (c.id == 'SIGN') {
              final tF = find.text(_signTitle);
              final dF = find.text(_signDesc);
              final nT = tF.evaluate().length;
              final nD = dF.evaluate().length;
              var tFg = '-';
              var tFace = '-';
              var dFg = '-';
              var face = '-';
              var bd = '-';
              var icon = '-';
              var cr = false;
              if (nT == 1 && nD == 1) {
                final tFgC = _fgOf(t, tF);
                final tFaceC = _faceOf(t, tF);
                final dFgC = _fgOf(t, dF);
                final faceC = _faceOf(t, dF);
                final under = Color.alphaBlend(faceC, Colors.white);
                tFg = _hex(tFgC);
                tFace = _hex(tFaceC);
                dFg = _hex(dFgC);
                face = _hex(faceC);
                bd = _edgeOf(t, dF);
                icon = _iconIn(t, dF, Icons.draw_outlined).$2;
                cr = _contrast(tFgC, Color.alphaBlend(tFaceC, under)) >= 4.5 && _contrast(dFgC, under) >= 4.5;
              }
              _out('D536 $tok att sign tn=$nT dn=$nD tfg=$tFg tface=$tFace dfg=$dFg face=$face bd=$bd icon=$icon cr45=$cr');
              need('계약 처리 필요 제목 · 설명 각 1', nT == 1 && nD == 1, 't $nT d $nD');
              final sr = 't $tFg/$tFace d $dFg face $face bd $bd icon $icon cr $cr';
              raw = '$raw sign $sr';
              if (!_before) {
                chk('strict 계약 처리 필요 = 작은 warningBg/warningDark 표기', tFg == _wantWarnDark && tFace == _wantWarnBg, sr);
                chk('strict 계약 처리 필요 띠 본문 = 흰 면 · border 선 · textPrimary 설명 · grey600 아이콘', face == _wantWhite && bd == _wantLine && dFg == _wantText1 && icon == _wantGrey600, sr);
                chk('strict 계약 처리 필요 글/면 대비 ≥4.5', cr, sr);
              }
              await shot('1sign', 'contract-pending-band');
            } else {
              final eF = find.text(_endedText);
              final nE = eF.evaluate().length;
              var face = '-';
              var bd = '-';
              var fg = '-';
              var icon = '-';
              var cr = false;
              if (nE == 1) {
                final faceC = _faceOf(t, eF);
                final fgC = _fgOf(t, eF);
                face = _hex(faceC);
                bd = _edgeOf(t, eF);
                fg = _hex(fgC);
                icon = _iconIn(t, eF, Icons.stop_circle_outlined).$2;
                cr = _contrast(fgC, Color.alphaBlend(faceC, Colors.white)) >= 4.5;
              }
              _out('D536 $tok att ended n=$nE face=$face bd=$bd fg=$fg icon=$icon cr45=$cr');
              need('계약 종료 예정 띠 1', nE == 1, '개수 $nE');
              final er = 'face $face bd $bd fg $fg icon $icon cr $cr';
              raw = '$raw ended $er';
              if (!_before) {
                chk('strict 계약 종료 예정 띠 = grey100 면 · border 선 · textSecondary 글 · grey600 아이콘', face == _wantGrey100 && bd == _wantLine && fg == _wantText2 && icon == _wantGrey600, er);
                chk('strict 계약 종료 예정 띠 글/면 대비 ≥4.5', cr, er);
              }
              await shot('1ended', 'decision-band');
            }
          } else {
            // ③ 빈 목록(EMPTY = 조회 성공 · 0명) / 조회 실패(FAIL = 지금은 토스트 + 같은 빈 안내 — 교정 전 모습 기록 · DU537 대상).
            final so = _statsLine(t, tok);
            final nEmpty = find.text(_emptyText).evaluate().length;
            final nToast = find.text(_failToast).evaluate().length;
            _out('D536 $tok att body emptyn=$nEmpty toastn=$nToast');
            need('통계 칸 전체 · 근무중 각 1 · 해지대기 0', so.n0 == 1 && so.n1 == 1 && so.nx == 0, so.raw);
            need('빈 안내 글 1', nEmpty == 1, '개수 $nEmpty');
            if (c.id == 'EMPTY') need('성공 빈 목록에는 실패 토스트 0', nToast == 0, '개수 $nToast');
            raw = 'stats ${so.raw} empty $nEmpty toast $nToast';
            if (!_before) {
              for (final x in _statsChecks(so, withRisk: false)) {
                chk(x.$1, x.$2, x.$3);
              }
            }
            if (c.id == 'EMPTY') {
              await shot('1empty', 'empty-success');
            } else {
              await shot('1fail', 'load-failed-as-empty');
              // 실패 토스트(4초)가 창이 살아 있는 동안 스스로 내려가게 둔다.
              for (var i = 0; i < 5; i++) {
                await t.pump(const Duration(seconds: 1));
              }
            }
          }
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ④ 성공 · 실패 공통 정리 — 창을 내리고 남은 timer · 지연 응답이 끝날 시간을 준다.
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

        // ⑤ 집계 — 읽기 호출 수 · 차단된 쓰기/허용 밖 CF 수 · 그 밖 Firestore 연산 · 예상 밖 채널 · HTTP.
        final nApps = wire.calls['callableGetApplicationsByBiz'] ?? 0;
        final nProps = wire.calls['callableGetRenewalProposalsByBiz'] ?? 0;
        final nUsers = wire.calls['callableGetUsersBatch'] ?? 0;
        final nWt = wire.calls['workTypes'] ?? 0;
        final nWrites = wire.blocked.length;
        final nOtherFs = wire.otherFs.length;
        final nUnexp = wire.unexpected.length;
        final nHttp = net.tries.length;
        final nHarness = wire.harness.length;
        final unText = [...wire.unexpected, ...wire.blocked, ...wire.otherFs.map((x) => 'fs $x'), ...wire.harness].join(' | ');
        _out('D536 $tok att wire apps=$nApps props=$nProps users=$nUsers wt=$nWt writes=$nWrites otherfs=$nOtherFs unexpected=$nUnexp http=$nHttp harness=$nHarness');

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
        _out('R536 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D536 $tok att fw n=$nFw');
        _out('D536 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        chk('쓰기 · 허용 밖 CF 0 · HTTP 0 · 대역 오류 0', nWrites == 0 && nHttp == 0 && nHarness == 0, unText);
        chk('읽기 대역 호출(지원서 ≥1 · 업무유형 ≥1)', nApps >= 1 && nWt >= 1, 'apps $nApps wt $nWt');
        if (!_before && v.id == 'W') chk('strict W 화면 전체 넘침 0', nOvf == 0, ovfRaw);
        if (!_before && c.id != 'FAIL') chk('strict 미처리 framework 예외 0(FAIL 은 기록만)', nFw == 0, fwRaw);
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
