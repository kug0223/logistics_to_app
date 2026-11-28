// ignore_for_file: depend_on_referenced_packages
// [DU539 · 이 창의 로컬 상태 · 응답 귀속] 고정근무자 관리 창(FixedWorkerManagementDialog) — 사업장 전환 시 이전 명단 제거 · 응답 귀속(사업장 + 조회 세대) · 실패 문구 말끝.
//   판정 = reports/DU_audit_self_review_retro135_2026-11-19.md §4(PP-FIXEDWORKER-READERROR-SCOPE 2 · 3항) · §5(PP-READERROR-TONE). §4-1(같은 사업장 stale 안내 · 비활성)은 다음 셀.
//   before = 현재 A(fixed_worker_management_dialog 97bea765 = DU538 채택판) 기록 전용 · strict = 후보(2ef19181).
//   하네스 = DU536 · DU537 · DU538 그대로 + 두 사업장 대역(읽기 CF 3종 + workTypes 질의를 사업장별 · 호출 순번별로 성공/실패/보류 · 그 밖 CF/Firestore 쓰기는 차단하고 센다).
//   사례 5: SWITCHFAIL(A 성공 → B 선택 → B 실패 → 다시 시도 → B 성공) · LATE(A 보류 중 B 선택 → B 성공 → 늦은 A 응답) · 회귀 RENEW · EMPTY · FAIL(첫 조회 실패 · 새 말끝).
//   누르는 것 = 사업장 선택 칸 · 선택 목록의 행 · (strict) 다시 시도 — 모두 읽기만 일으킨다. 상태변경 버튼(연장 · 종료 · 일괄 연장 · 카드 · 승인 · 거절)은 누르지 않는다.
//   SAME(같은 사업장 재조회 실패)은 이 시험에 없다 — 쓰기를 거치지 않고 같은 사업장을 다시 읽는 화면 경로가 제품에 없다(README).
//   기본 skip — TB before/du539-tb/DU_BEFORE_OBSERVE=539 · TA after/du539-ta/없음.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:ALfit/widgets/app_select_field.dart';

import 'support/du1_vq_capture.dart';
import 'support/du_word_break.dart';
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
const _biz2 = 'biz2';
const _bizName2 = '역삼 카페';

/// 소유자(BUSINESS_ADMIN) — DU536 _Owner 와 같은 override(창은 `canForBusiness` · `watchBusinessPermissions` 를 부른다).
class _Owner extends UserProvider {
  final watched = <String>[];
  @override
  UserModel? get currentUser => UserModel(
      uid: 'admin1', username: 'admin1', name: '김관리', email: 'admin1@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const [_biz1, _biz2], sealBase64: 'seal');
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

/// 장기 확정 지원서 한 건 — 종료일 = 오늘 + [endIn]일.
Map<String, Object?> _app(String id, String applicant, int endIn,
        {String status = 'CONFIRMED', Map<String, Object?> extra = const <String, Object?>{}, String biz = _biz1, String bizName = _bizName}) =>
    <String, Object?>{
      'id': id, 'uid': 'u_$id', 'businessId': biz, 'businessName': bizName, 'toId': 'to1', 'toTitle': '장기 모집',
      'selectedWorkType': '홀서빙', 'startTime': '09:00', 'endTime': '18:00', 'status': status, 'type': 'long_term',
      'applicantName': applicant, 'wage': 12000, 'wageType': 'hourly', 'workDays': const <Object?>['월', '화', '수', '목', '금'],
      'workDate': _ts(_kstDayMs(-30)), 'workEndDate': _ts(_kstDayMs(endIn)),
      'appliedAt': _ts(_kstDayMs(-32)), 'confirmedAt': _ts(_kstDayMs(-31)),
      ...extra,
    };

const _names = <String, String>{
  'u_a1': '김연장', 'u_a2': '이대기', 'u_a3': '박서명', 'u_a4': '최종료', 'u_a5': '정해지',
  'u_c1': '김가람', 'u_c2': '이나래', 'u_c3': '서다솜', 'u_d1': '박다온', 'u_d2': '최라희',
};

/// 두 사업장 사례의 근무자 이름 — A(biz1) 3명 · B(biz2) 2명(수가 달라 머리 통계 '전체'로도 어느 사업장 자료인지 갈린다).
const _namesA = <String>['김가람', '이나래', '서다솜'];
const _namesB = <String>['박다온', '최라희'];

/// 두 사업장 사례의 지원서 — 모두 만료가 멀다(만료 임박 띠 · 위험 통계 칩 없음). 호출마다 새로 만든다.
List<Object?> _apps2(String biz) => biz == _biz1
    ? <Object?>[_app('c1', '김가람', 60), _app('c2', '이나래', 90), _app('c3', '서다솜', 120)]
    : <Object?>[_app('d1', '박다온', 70, biz: _biz2, bizName: _bizName2), _app('d2', '최라희', 100, biz: _biz2, bizName: _bizName2)];

/// 대역 5명(DU536 과 같다 · 호출마다 새로 만든다) — a1 만료 10일 전 · a2 만료 5일 전 + 연장 제안 응답 대기 ·
///   a3 계약 처리 필요 · a4 종료 결정 · a5 해지 요청 중(통계 '해지대기').
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
String _wtPathOf(String biz) => 'businesses/$biz/workTypes';
const _appsFn = 'callableGetApplicationsByBiz';

/// 첫 화면이 부르는 읽기 CF(일반 모드) — 이 밖의 CF 이름은 차단하고 센다.
const _readFns = <String>{'callableGetApplicationsByBiz', 'callableGetRenewalProposalsByBiz', 'callableGetUsersBatch'};

/// Firestore 쓰기 연산 — 하나라도 오면 writes 로 센다.
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

/// 사례@사업장별 — 지원서 조회 CF 의 앞 몇 번을 실패시키는가(FAIL = 첫 조회 · SWITCHFAIL = B 사업장의 첫 조회).
const _failFirst = <String, int>{'FAIL@biz1': 1, 'SWITCHFAIL@biz2': 1};

/// [DU526 · DU534 · DU536 과 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널.
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du539.fake.auth.';
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

  /// 사례 이름 — EMPTY(성공 0명) · FAIL(지원서 조회 실패) · SWITCHFAIL/LATE(두 사업장 대역) · 그 밖(5명 대역).
  final String kind;

  /// LATE — A 사업장의 첫 지원서 조회 응답을 붙잡아 둔다. 부르면 그 응답(성공 · A 명단)을 그때 보낸다.
  void Function()? held;
  bool _holdNext = false;
  final unexpected = <String>[];
  final blocked = <String>[];
  final otherFs = <String>[];
  final auth = <String>[];
  final harness = <String>[];
  final calls = <String, int>{};
  void _hit(String k) => calls[k] = (calls[k] ?? 0) + 1;

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
    if (channel == _cfChannel) {
      final reply = _cf(message);
      if (_holdNext) {
        _holdNext = false;
        final pending = Completer<ByteData?>();
        held = () => pending.complete(reply);
        return pending.future;
      }
      return Future<ByteData?>.value(reply);
    }
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
        return codec.encodeMessage(<Object?>['not-found', 'du539-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      final biz = (params['businessId'] ?? '-').toString();
      final two = kind == 'SWITCHFAIL' || kind == 'LATE';
      _hit(fn);
      _hit('$fn@$biz');
      if (fn == _appsFn) {
        final nth = calls['$fn@$biz'] ?? 0;
        if (nth <= (_failFirst['$kind@$biz'] ?? 0)) {
          return codec.encodeMessage(<Object?>['unavailable', 'du539 local failure', <String, Object?>{'code': 'unavailable', 'message': 'du539 local failure'}]);
        }
        if (kind == 'LATE' && biz == _biz1 && nth == 1) _holdNext = true;
        return codec.encodeMessage(<Object?>[<String, Object?>{'applications': kind == 'EMPTY' ? const <Object?>[] : (two ? _apps2(biz) : _apps())}]);
      }
      if (fn == 'callableGetRenewalProposalsByBiz') {
        return codec.encodeMessage(<Object?>[<String, Object?>{'proposals': (kind == 'EMPTY' || two) ? const <Object?>[] : <Object?>[_proposal()]}]);
      }
      final uids = (params['uids'] as List).cast<String>();
      return codec.encodeMessage(<Object?>[
        <String, Object?>{
          'users': <String, Object?>{for (final u in uids) u: <String, Object?>{'name': _names[u] ?? '근로자', 'role': 'USER'}},
        },
      ]);
    } catch (e) {
      harness.add('cf $e');
      return codec.encodeMessage(<Object?>['internal', 'du539-harness', null]);
    }
  }

  ByteData? _fs(String op, ByteData? message) {
    const codec = FirebaseFirestoreHostApi.codec;
    try {
      if (op == 'queryGet' && message != null) {
        // 요청 본문은 codec 으로 되읽을 수 없다(선례 du1_c1_edit_discard_test.dart:92–98) — 원본 바이트의 경로 문자열로 구분한다.
        final raw = String.fromCharCodes(message.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes));
        final wtBiz = raw.contains(_wtPathOf(_biz2)) ? _biz2 : _biz1;
        final wtPath = _wtPathOf(wtBiz);
        if (raw.contains(wtPath)) {
          _hit('workTypes');
          return codec.encodeMessage(<Object?>[
            PigeonQuerySnapshot(
              documents: [
                PigeonDocumentSnapshot(
                  path: '$wtPath/wt1',
                  data: <String?, Object?>{
                    'businessId': wtBiz, 'name': '포장', 'icon': 'box', 'color': '#3859E8', 'backgroundColor': '#EEF2FF',
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
      return codec.encodeMessage(<Object?>['du539-blocked', '$op 차단', null]);
    } catch (e) {
      harness.add('fs $op $e');
      return codec.encodeMessage(<Object?>['du539-harness', '대역 오류', null]);
    }
  }
}

/// 외부 HTTP 차단 — 만들려는 시도를 기록하고 실패시킨다.
class _NoHttp extends HttpOverrides {
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    throw const SocketException('DU539 관측 — 외부 HTTP 차단');
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

final String _wantWhite = _hex(Colors.white);
final String _wantLine = _hex(AppColors.border);
final String _wantText1 = _hex(AppColors.textPrimary);
final String _wantText2 = _hex(AppColors.textSecondary);
final String _wantGrey100 = _hex(AppColors.grey100);
final String _wantErr = _hex(AppColors.error);
final String _wantErrDark = _hex(AppColors.errorDark);

/// 통계 줄 바탕(grey50) — 칩 면이 반투명일 때 대비를 재는 밑색.
const Color _statsUnder = AppColors.grey50;

typedef _ChipObs = ({int n, String face, String bd, String lab, String bub, String num, bool cr});

/// 통계 칸 하나([label]) — 칸 면 · 선 · 라벨 글 · 숫자 방울 면 · 숫자 글 색과 대비(라벨/칸 면 · 숫자/방울 면). 위젯 값만 읽는다(DU536 과 같은 식).
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

/// 통계 줄 — '전체' · '근무중' · (있으면) '해지대기'. 출력 한 줄(키 고정 · DU536 과 같은 키).
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
  _out('D539 $tok att stats n0=${c0.n} n1=${c1.n} nx=${cx.n} face=$face bd=$bd lab=$lab bub=$bub num0=${c0.num} num1=${c1.num} numx=${cx.num} cr45=$cr');
  return (
    n0: c0.n, n1: c1.n, nx: cx.n, face: face, bd: bd, lab: lab, bub: bub, num0: c0.num, num1: c1.num, numx: cx.num, cr: cr,
    raw: 'n ${c0.n}/${c1.n}/${cx.n} face $face bd $bd lab $lab bub $bub num ${c0.num}/${c1.num}/${cx.num} cr $cr',
  );
}

/// 통계 칸 단언(두 모드 — base 가 이미 DU536 · DU537 채택판이다): 바깥 면 · 선 · 라벨 중립 · 방울 grey100 · 전체/근무중 숫자 textPrimary · (있으면) 해지대기 숫자 errorDark.
List<(String, bool, String)> _statsChecks(_StatsObs so, {required bool withRisk}) => [
      ('통계 칸 면 = 흰색 · 선 = border · 라벨 = textSecondary · 숫자 방울 = grey100(DU536 그대로)', so.face == _wantWhite && so.bd == _wantLine && so.lab == _wantText2 && so.bub == _wantGrey100, so.raw),
      ('전체 · 근무중 숫자 = textPrimary(DU536 그대로)', so.num0 == _wantText1 && so.num1 == _wantText1, so.raw),
      if (withRisk) ('해지대기 칸 1 · 숫자 = errorDark(DU536 그대로)', so.nx == 1 && so.numx == _wantErrDark, so.raw),
      ('통계 칸 글/면 대비 ≥4.5', so.cr, so.raw),
    ];

typedef _BodyObs = ({int emptyN, int failN, int toastN, String icon});

/// 본문 — 빈 상태 문구 수 · 조회 실패 안내 수(창 안) · 실패 토스트 수(창 밖 — 후보는 본문과 토스트가 같은 글이라 화면 전체 수에서 창 안 수를 뺀다) ·
///   창 안 오류 아이콘 색(하나일 때만 · 아니면 '-'). 보이는 글 기준(DU537 과 같은 식).
_BodyObs _bodyNow(WidgetTester t, Finder dlg) {
  final emptyN = find.descendant(of: dlg, matching: findVisibleText(_emptyText), skipOffstage: true).evaluate().length;
  final failN = find.descendant(of: dlg, matching: findVisibleText(_failText), skipOffstage: true).evaluate().length;
  final toastAll = findVisibleText(_failToast).evaluate().length;
  final toastIn = find.descendant(of: dlg, matching: findVisibleText(_failToast), skipOffstage: true).evaluate().length;
  final toastN = toastAll - toastIn;
  final icons = find.descendant(of: dlg, matching: find.byIcon(Icons.error_outline), skipOffstage: true).evaluate().toList();
  final ic = icons.length == 1 ? (icons.first.widget as Icon).color : null;
  return (emptyN: emptyN, failN: failN, toastN: toastN, icon: ic == null ? '-' : _hex(ic));
}

bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

/// 버튼 하나가 끌기 없이 보이고 눌리는가 — 창 상자 ∩ 화면(∩ 가까운 Scrollable 이 있으면 그 칸) 안 + 중심 hit(DU517 · DU537 `_retryNow` 와 같은 식).
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

/// 상자 하나의 화면 좌표(l,t,r,b · 소수 1자리) — 하나가 아니면 '-'.
String _rs(WidgetTester t, Finder f) {
  if (f.evaluate().length != 1) return '-';
  final r = t.getRect(f);
  return '${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)},${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)}';
}

/// Icon 글리프의 RichText 인가(Icon 도 안에서 RichText 로 그려진다) — 글의 RichText 만 세려고 뺀다.
bool _underIcon(Element e) {
  var under = false;
  e.visitAncestorElements((a) {
    if (a.widget is Icon) under = true;
    return !under;
  });
  return under;
}

/// 글 하나([textF] = Text 위젯)의 낱말 안 줄바꿈 수(공용 판정기 du_word_break — 피할 수 있는 것 + 불가피한 것)와 문단 높이.
({int n, int wb, String h, String raw}) _wordsOf(WidgetTester t, Finder textF) {
  final n = textF.evaluate().length;
  if (n != 1) return (n: n, wb: 0, h: '0.0', raw: 'n $n');
  final rts = find.descendant(of: textF, matching: find.byType(RichText), skipOffstage: true).evaluate().where((e) => !_underIcon(e)).toList();
  final nRt = rts.length;
  if (nRt != 1) return (n: 0, wb: 0, h: '0.0', raw: 'richtext $nRt');
  final rp = rts.first.renderObject! as RenderParagraph;
  final wbs = wordBreaks(rp);
  final h = rp.size.height.toStringAsFixed(1);
  return (n: 1, wb: wbs.length, h: h, raw: 'h $h w ${rp.size.width.toStringAsFixed(1)} wb ${wbs.join(' / ')}');
}

/// 통계 칩 — 보이는 칩 수 · 줄 수(칩 윗변 값의 가짓수) · 칩 안 라벨이 모두 한 줄인가(라벨 높이가 '전체' 라벨과 같다).
const _chipLabels = ['전체', '근무중', '계약 종료', '계약 확인', '퇴사대기', '해지대기'];
({int chips, int rows, bool oneline}) _chipsNow(WidgetTester t) {
  final tops = <String>{};
  final hs = <double>[];
  for (final lab in _chipLabels) {
    final f = find.text(lab);
    if (f.evaluate().length != 1) continue;
    tops.add(t.getRect(find.ancestor(of: f, matching: find.byType(Container)).first).top.toStringAsFixed(1));
    hs.add(t.getSize(f).height);
  }
  final oneline = hs.isNotEmpty && hs.every((h) => (h - hs.first).abs() < 0.5);
  return (chips: hs.length, rows: tops.length, oneline: oneline);
}

/// 통계 칸 하나([label])의 숫자 — 칸이 하나가 아니거나 숫자가 아니면 -1.
int _chipVal(WidgetTester t, String label) {
  final labF = find.text(label);
  if (labF.evaluate().length != 1) return -1;
  final chipF = find.ancestor(of: labF, matching: find.byType(Container)).first;
  final texts = find.descendant(of: chipF, matching: find.byType(Text), skipOffstage: true).evaluate().map((e) => e.widget as Text).toList();
  if (texts.length != 2) return -1;
  return int.tryParse(texts.last.data ?? '') ?? -1;
}

typedef _SceneObs = ({int an, int bn, int cards, int bulkN, int loading, int tot, int act, int selA, int selB});

/// 두 사업장 사례의 한 시점 — 창 안의 A/B 사업장 근무자 이름 글 수 · 카드 수(카드 오른쪽 화살표) · 일괄 연장 글 수 · 로딩 문구 수 ·
///   머리 통계 숫자(전체 · 근무중) · 선택 칸에 선 사업장 이름 수. 위젯 값만 읽는다.
_SceneObs _sceneNow(WidgetTester t, Finder dlg) {
  int inDlg(Finder f) => find.descendant(of: dlg, matching: f, skipOffstage: true).evaluate().length;
  var an = 0;
  for (final x in _namesA) {
    an += inDlg(find.text(x));
  }
  var bn = 0;
  for (final x in _namesB) {
    bn += inDlg(find.text(x));
  }
  return (
    an: an, bn: bn, cards: inDlg(find.byIcon(Icons.chevron_right)), bulkN: inDlg(find.text(_bulkText)), loading: inDlg(find.text(_loadingText)),
    tot: _chipVal(t, '전체'), act: _chipVal(t, '근무중'), selA: inDlg(find.text(_bizName)), selB: inDlg(find.text(_bizName2)),
  );
}

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
const _cases = <({String id, int shots})>[(id: 'SWITCHFAIL', shots: 3), (id: 'LATE', shots: 2), (id: 'RENEW', shots: 2), (id: 'EMPTY', shots: 1), (id: 'FAIL', shots: 1)];

/// 두 사업장으로 여는 사례(사업장 선택 칸이 선다) — 그 밖은 DU538 과 같은 한 사업장.
const _twoBiz = <String>{'SWITCHFAIL', 'LATE'};

/// 사례별 — 한 사람 카드만 세우는 uid(창의 initialWorkerUid) · 그 카드의 D-day 글 · 카드 띠 글(보이는 글의 앞부분). RENEW 만(DU538 과 같은 대역).
const _focus = <String, String>{'RENEW': 'u_a1'};
const _dday = <String, String>{'RENEW': 'D-10'};
const _bandText = <String, String>{'RENEW': '계약 만료 D-10'};
/// 글 원문.
const _titleText = '고정근무자 관리';
const _emptyText = '고정근무자가 없습니다';
const _loadingText = '고정근무자 로딩 중...';
const _retryText = '다시 시도';
const _expiringText = '계약 만료 임박';
const _bulkText = '일괄 연장';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '539';
/// 조회 실패 본문 · 같은 조회의 토스트 — before(현재 A)는 이전 말끝, strict(후보)는 PP-READERROR-TONE 의 '불러오지 못했어요'(본문 = 토스트 같은 글).
final String _failText = _before ? '고정근무자 목록을 불러오지 못했습니다' : '고정근무자 목록을 불러오지 못했어요';
final String _failToast = _before ? '고정근무자 목록을 불러올 수 없습니다' : '고정근무자 목록을 불러오지 못했어요';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du539-tb' && _env['DU_BEFORE_OBSERVE'] == '539') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du539-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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
    _out('R539 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S907FS-${v.id}-${c.id} 고정근무자 관리 창 사업장 스코프 — 전환 시 이전 명단 제거 · 응답 귀속 · 실패 문구 말끝', (t) async {
        final tok = 'S907FS-${v.id}-${c.id}';
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
        _out('D539 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        final owner = _Owner();
        final isList = _focus.containsKey(c.id);
        final isTwo = _twoBiz.contains(c.id);
        final isB = v.id == 'B';
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
                  body: isTwo
                      ? FixedWorkerManagementDialog(
                          key: UniqueKey(),
                          businessIds: const [_biz1, _biz2],
                          initialBusinessId: _biz1,
                          businesses: [_business(_biz1, _bizName), _business(_biz2, _bizName2)],
                          onChanged: () {},
                        )
                      : FixedWorkerManagementDialog(
                          key: UniqueKey(),
                          initialBusinessId: _biz1,
                          businesses: [_business(_biz1, _bizName)],
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
            _out('D539 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          // 사업장 선택 칸을 눌러 목록에서 [name] 을 고른다(읽기만 일으킨다 — 서버 쓰기 0). 고른 뒤 조회가 끝날 시간을 준다.
          Future<void> switchTo(String name) async {
            final selF = find.descendant(of: dlg, matching: find.byWidgetPredicate((w) => w is AppSelectField<String>), skipOffstage: true);
            final nSel = selF.evaluate().length;
            need('사업장 선택 칸 1', nSel == 1, '개수 $nSel');
            await t.tap(selF);
            for (var i = 0; i < 12; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final rowF = find.text(name);
            final nRow = rowF.evaluate().length;
            need('선택 목록의 $name 1', nRow == 1, '개수 $nRow');
            await t.tap(rowF);
            for (var i = 0; i < 40; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
          }

          // 그려진 글 집합(첫 화면 · 보이는 글 기준 · 숫자는 # 으로). 기록용.
          final words = <String>{};
          for (final e in find.descendant(of: dlg, matching: find.byType(Text), skipOffstage: true).evaluate()) {
            final d = (e.widget as Text).data;
            if (d != null && d.isNotEmpty) words.add(visibleText(d).replaceAll(RegExp(r'\d+'), '#'));
          }
          final wordList = words.toList()..sort();
          _out('D539 $tok att txt n=${wordList.length} set=${_enc(wordList.join('|'))}');

          // ① 머리 통계(색 = DU536 그대로) · 본문 · 칩 배치 — 모든 사례 공통(첫 화면).
          final so = _statsLine(t, tok);
          final b0 = _bodyNow(t, dlg);
          _out('D539 $tok att body emptyn=${b0.emptyN} failn=${b0.failN} toastn=${b0.toastN} icon=${b0.icon}');
          final lay = _chipsNow(t);
          _out('D539 $tok att lay chips=${lay.chips} rows=${lay.rows} oneline=${lay.oneline}');
          final wantChips = isList ? 3 : 2;
          need('통계 칸 전체 · 근무중 각 1 · 해지대기 ${isList ? 1 : 0} · 칩 $wantChips', so.n0 == 1 && so.n1 == 1 && so.nx == (isList ? 1 : 0) && lay.chips == wantChips, so.raw);
          for (final x in _statsChecks(so, withRisk: isList)) {
            chk(x.$1, x.$2, x.$3);
          }
          final lr = 'chips ${lay.chips} rows ${lay.rows} oneline ${lay.oneline}';
          chk('통계 칩 안 줄바꿈 0(라벨 한 줄)', lay.oneline, lr);
          if (!isB) chk('W 통계 칩 한 줄(이전과 같다)', lay.rows == 1, lr);
          final br0 = 'empty ${b0.emptyN} fail ${b0.failN} toast ${b0.toastN} icon ${b0.icon}';
          raw = 'stats ${so.raw} body $br0 lay $lr';

          // ② 배치 좌표 기록(없는 요소는 '-').
          final bulkBtn = find.descendant(of: dlg, matching: find.widgetWithText(TextButton, _bulkText), skipOffstage: true);
          final extInk = find.ancestor(of: findVisibleText('연장'), matching: find.byType(InkWell));
          final endInk = find.ancestor(of: findVisibleText('종료'), matching: find.byType(InkWell));
          final ddF = find.text(_dday[c.id] ?? '(없음)');
          String chipRect(String lab) {
            final f = find.text(lab);
            return f.evaluate().length == 1 ? _rs(t, find.ancestor(of: f, matching: find.byType(Container)).first) : '-';
          }

          final gC0 = chipRect('전체');
          final gC1 = chipRect('근무중');
          final gCx = chipRect('해지대기');
          final gBico = _rs(t, find.descendant(of: dlg, matching: find.byIcon(Icons.event_busy), skipOffstage: true));
          final gBulk = _rs(t, bulkBtn);
          final gRico = _rs(t, find.descendant(of: dlg, matching: find.byIcon(Icons.event_note), skipOffstage: true));
          final gExt = extInk.evaluate().isEmpty ? '-' : _rs(t, extInk.first);
          final gEnd = endInk.evaluate().isEmpty ? '-' : _rs(t, endInk.first);
          final gDate = _rs(t, find.descendant(of: dlg, matching: findVisibleTextContaining(' ~ '), skipOffstage: true));
          final gDday = ddF.evaluate().length == 1 ? _rs(t, find.ancestor(of: ddF, matching: find.byType(Container)).first) : '-';
          _out('D539 $tok att geo c0=$gC0 c1=$gC1 cx=$gCx bico=$gBico bulk=$gBulk rico=$gRico ext=$gExt end=$gEnd date=$gDate dday=$gDday');

          if (c.id == 'SWITCHFAIL') {
            // ③ A 조회 성공 → B 선택 → B 조회 실패 → (strict) 다시 시도 → B 조회 성공. 누르는 것 = 사업장 선택 칸 · 목록 행 · 다시 시도(모두 읽기).
            final s1 = _sceneNow(t, dlg);
            _out('D539 $tok att sa an=${s1.an} bn=${s1.bn} cards=${s1.cards} loading=${s1.loading} tot=${s1.tot} act=${s1.act} sela=${s1.selA} selb=${s1.selB}');
            final r1 = 'an ${s1.an} bn ${s1.bn} cards ${s1.cards} loading ${s1.loading} tot ${s1.tot} act ${s1.act} sel ${s1.selA}/${s1.selB}';
            need('A 조회 성공 첫 화면 — A 이름 ≥1 · B 이름 0 · 전체 3 · 선택 칸 = A', s1.an >= 1 && s1.bn == 0 && s1.tot == 3 && s1.selA == 1 && s1.selB == 0 && s1.loading == 0, r1);
            await shot('1a', 'biz-a-loaded');

            await switchTo(_bizName2);
            final s2 = _sceneNow(t, dlg);
            final b2 = _bodyNow(t, dlg);
            _out('D539 $tok att sf an=${s2.an} bn=${s2.bn} cards=${s2.cards} bulkn=${s2.bulkN} loading=${s2.loading} tot=${s2.tot} act=${s2.act} emptyn=${b2.emptyN} failn=${b2.failN} toastn=${b2.toastN} sela=${s2.selA} selb=${s2.selB}');
            final r2 = 'an ${s2.an} bn ${s2.bn} cards ${s2.cards} bulk ${s2.bulkN} loading ${s2.loading} tot ${s2.tot} act ${s2.act} '
                'empty ${b2.emptyN} fail ${b2.failN} toast ${b2.toastN} sel ${s2.selA}/${s2.selB}';
            need('B 선택 뒤 선택 칸 = B', s2.selA == 0 && s2.selB == 1, r2);
            // 실패 토스트(4초)가 내려간 뒤의 본문에서 다시 시도를 잰다(토스트가 버튼을 덮는 동안의 hit 은 이 셀이 다루지 않는다).
            for (var i = 0; i < 5; i++) {
              await t.pump(const Duration(seconds: 1));
            }
            final retryF = find.descendant(of: dlg, matching: find.widgetWithText(TextButton, _retryText), skipOffstage: true);
            final nRetry = retryF.evaluate().length;
            var rVis = false;
            var rHit = false;
            var rMin48 = false;
            var rr = '-';
            if (nRetry == 1) {
              final p0 = _tapNow(t, retryF, dlg, screen);
              rVis = p0.vis;
              rHit = p0.hit;
              rMin48 = p0.min48;
              rr = p0.r.toString();
            }
            _out('D539 $tok att retry n=$nRetry vis=$rVis hit=$rHit min48=$rMin48');
            raw = '$raw sa $r1 sf $r2 retry n $nRetry vis $rVis hit $rHit min48 $rMin48 r $rr';
            if (!_before) {
              chk('strict B 조회 실패 — A 이름 0 · 카드 0 · 일괄 연장 0(이전 사업장 명단 · 행동 혼입 0)', s2.an == 0 && s2.bn == 0 && s2.cards == 0 && s2.bulkN == 0, r2);
              chk('strict B 조회 실패 — 실패 안내 1 · 빈 상태 문구 0 · 로딩 0 · 토스트 1', b2.failN == 1 && b2.emptyN == 0 && s2.loading == 0 && b2.toastN == 1, r2);
              chk('strict B 조회 실패 — 머리 통계 전체 0 · 근무중 0', s2.tot == 0 && s2.act == 0, r2);
              chk('strict 다시 시도 1 · 끌기 없이 보임 · 중심 hit · ≥48', nRetry == 1 && rVis && rHit && rMin48, 'n $nRetry vis $rVis hit $rHit r $rr');
            }
            await shot('2fail', 'biz-b-load-failed');

            // 다시 시도 — strict 만 실제로 누른다(읽기 재호출 · 쓰기 0). before 는 버튼이 없다(이전 명단이 그대로 남는다) — 누르지 않고 같은 화면을 기록한다.
            var tapped = false;
            if (!_before) {
              final nTap = retryF.evaluate().length;
              need('다시 시도 1(탭 직전)', nTap == 1, '개수 $nTap');
              await t.tap(retryF);
              tapped = true;
            }
            for (var i = 0; i < 40; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final s3 = _sceneNow(t, dlg);
            final b3 = _bodyNow(t, dlg);
            final nRetry3 = find.descendant(of: dlg, matching: find.widgetWithText(TextButton, _retryText), skipOffstage: true).evaluate().length;
            final appsB = wire.calls['$_appsFn@$_biz2'] ?? 0;
            _out('D539 $tok att sr tapped=$tapped an=${s3.an} bn=${s3.bn} cards=${s3.cards} loading=${s3.loading} tot=${s3.tot} act=${s3.act} emptyn=${b3.emptyN} failn=${b3.failN} retryn=$nRetry3 toastn=${b3.toastN} appsb=$appsB');
            final r3 = 'tapped $tapped an ${s3.an} bn ${s3.bn} cards ${s3.cards} loading ${s3.loading} tot ${s3.tot} act ${s3.act} '
                'empty ${b3.emptyN} fail ${b3.failN} retry $nRetry3 toast ${b3.toastN} appsB $appsB';
            raw = '$raw sr $r3';
            if (!_before) {
              chk('strict 다시 시도 → B 조회 1 → 2 · B 이름 ≥1 · A 이름 0 · 카드 ≥1 · 전체 2 · 근무중 2',
                  appsB == 2 && s3.bn >= 1 && s3.an == 0 && s3.cards >= 1 && s3.tot == 2 && s3.act == 2, r3);
              chk('strict 다시 시도 성공 뒤 — 실패 안내 0 · 빈 상태 문구 0 · 다시 시도 0 · 로딩 0 · 토스트 0',
                  b3.failN == 0 && b3.emptyN == 0 && nRetry3 == 0 && s3.loading == 0 && b3.toastN == 0, r3);
            }
            await shot('3retry', 'biz-b-after-retry');
          } else if (c.id == 'LATE') {
            // ④ A 조회 지연(응답 보류) 중 B 선택 → B 조회 성공 → 늦은 A 응답 도착. 화면은 B 그대로여야 한다(strict).
            final l1 = _sceneNow(t, dlg);
            final heldNow = wire.held != null;
            _out('D539 $tok att la held=$heldNow an=${l1.an} bn=${l1.bn} cards=${l1.cards} loading=${l1.loading} tot=${l1.tot} act=${l1.act} sela=${l1.selA} selb=${l1.selB}');
            final q1 = 'held $heldNow an ${l1.an} bn ${l1.bn} cards ${l1.cards} loading ${l1.loading} tot ${l1.tot} act ${l1.act} sel ${l1.selA}/${l1.selB}';
            need('A 조회 보류 중 — 로딩 1 · 이름 0 · 전체 0 · 선택 칸 = A', heldNow && l1.loading == 1 && l1.an == 0 && l1.bn == 0 && l1.tot == 0 && l1.selA == 1 && l1.selB == 0, q1);

            await switchTo(_bizName2);
            final l2 = _sceneNow(t, dlg);
            final c2 = _bodyNow(t, dlg);
            _out('D539 $tok att lb an=${l2.an} bn=${l2.bn} cards=${l2.cards} loading=${l2.loading} tot=${l2.tot} act=${l2.act} emptyn=${c2.emptyN} failn=${c2.failN} toastn=${c2.toastN} sela=${l2.selA} selb=${l2.selB}');
            final q2 = 'an ${l2.an} bn ${l2.bn} cards ${l2.cards} loading ${l2.loading} tot ${l2.tot} act ${l2.act} '
                'empty ${c2.emptyN} fail ${c2.failN} toast ${c2.toastN} sel ${l2.selA}/${l2.selB}';
            need('B 조회 성공(A 는 아직 보류) — B 이름 ≥1 · A 이름 0 · 전체 2 · 로딩 0 · 선택 칸 = B',
                l2.bn >= 1 && l2.an == 0 && l2.tot == 2 && l2.loading == 0 && l2.selA == 0 && l2.selB == 1 && c2.failN == 0, q2);
            await shot('1b', 'biz-b-loaded-a-pending');

            // 늦은 A 응답을 지금 보낸다(성공 응답 · A 명단 3명).
            final release = wire.held;
            need('보류 중인 A 응답 1', release != null);
            wire.held = null;
            release!();
            for (var i = 0; i < 40; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final l3 = _sceneNow(t, dlg);
            final c3 = _bodyNow(t, dlg);
            _out('D539 $tok att lc released=true an=${l3.an} bn=${l3.bn} cards=${l3.cards} loading=${l3.loading} tot=${l3.tot} act=${l3.act} emptyn=${c3.emptyN} failn=${c3.failN} toastn=${c3.toastN} sela=${l3.selA} selb=${l3.selB}');
            final q3 = 'an ${l3.an} bn ${l3.bn} cards ${l3.cards} loading ${l3.loading} tot ${l3.tot} act ${l3.act} '
                'empty ${c3.emptyN} fail ${c3.failN} toast ${c3.toastN} sel ${l3.selA}/${l3.selB}';
            raw = '$raw la $q1 lb $q2 lc $q3';
            need('늦은 A 응답 뒤에도 선택 칸 = B', l3.selA == 0 && l3.selB == 1, q3);
            if (!_before) {
              chk('strict 늦은 A 응답 뒤 — 화면은 B 그대로(B 이름 ≥1 · A 이름 0 · 카드 ≥1 · 전체 2 · 근무중 2)',
                  l3.bn >= 1 && l3.an == 0 && l3.cards >= 1 && l3.tot == 2 && l3.act == 2, q3);
              chk('strict 늦은 A 응답 뒤 — 로딩 0 · 실패 안내 0 · 빈 상태 문구 0 · 토스트 0(덮어쓰기 0)',
                  l3.loading == 0 && c3.failN == 0 && c3.emptyN == 0 && c3.toastN == 0, q3);
            }
            await shot('2late', 'late-a-response-arrived');
          } else if (isList) {
            // ⑤ (회귀 · DU538 측정 그대로) 만료 임박 띠 — 글 낱말 안 끊김 · 일괄 연장(색 · 보임 · hit · 받는 자리 기록 · 글 아래로 내려갔는가). 누르지 않는다.
            final bulkF = find.text(_bulkText);
            final nBulk = bulkF.evaluate().length;
            need('일괄 연장 1 · 버튼 1', nBulk == 1 && bulkBtn.evaluate().length == 1, '글 $nBulk');
            final fgC = t.widget<Text>(bulkF).style?.color ?? Colors.black;
            final faceC = _faceOf(t, bulkF);
            final resolved = t.widget<TextButton>(bulkBtn).style?.foregroundColor?.resolve(<WidgetState>{});
            final bulkCr = _contrast(fgC, Color.alphaBlend(faceC, Colors.white)) >= 4.5;
            final btnFg = resolved == null ? '-' : _hex(resolved);
            _out('D539 $tok att bulk n=$nBulk fg=${_hex(fgC)} btnfg=$btnFg face=${_hex(faceC)} cr45=$bulkCr');
            final bandF = find.descendant(of: dlg, matching: findVisibleTextContaining(_expiringText), skipOffstage: true);
            final bw = _wordsOf(t, bandF);
            need('만료 임박 띠 글 1', bw.n == 1, bw.raw);
            final bp = _tapNow(t, bulkBtn, dlg, screen);
            final stack = bp.r.top >= t.getRect(bandF).bottom - 0.5;
            _out('D539 $tok att band n=${bw.n} wb=${bw.wb} h=${bw.h} bvis=${bp.vis} bhit=${bp.hit} bmin48=${bp.min48} stack=$stack');
            final bandRaw = '${bw.raw} bulk ${bp.r} vis ${bp.vis} hit ${bp.hit} min48 ${bp.min48} stack $stack';
            raw = '$raw band $bandRaw';
            chk('만료 임박 띠 글 낱말 안 끊김 0(DU538 그대로)', bw.wb == 0, bandRaw);
            chk('일괄 연장 화면 안 · 중심 hit(DU538 그대로)', bp.vis && bp.hit, bandRaw);
            chk(isB ? 'B 일괄 연장이 글 아래로(DU538 그대로)' : 'W 일괄 연장이 글 옆(DU538 그대로)', stack == isB, bandRaw);

            // ⑥ 카드 — D-day 칩(색 = DU536 그대로) · 카드 띠 글의 낱말 안 끊김.
            final nDd = ddF.evaluate().length;
            need('D-day 칩 1', nDd == 1, '개수 $nDd');
            final ddFg = t.widget<Text>(ddF).style?.color ?? Colors.black;
            final ddFace = _faceOf(t, ddF);
            final ddCr = _contrast(ddFg, Color.alphaBlend(ddFace, Colors.white)) >= 4.5;
            _out('D539 $tok att dday n=$nDd fg=${_hex(ddFg)} face=${_hex(ddFace)} bd=${_edgeOf(t, ddF)} cr45=$ddCr');
            final cbF = find.descendant(of: dlg, matching: findVisibleTextContaining(_bandText[c.id]!), skipOffstage: true);
            final cw = _wordsOf(t, cbF);
            need('카드 띠 글 1', cw.n == 1, cw.raw);
            _out('D539 $tok att cband n=${cw.n} wb=${cw.wb} h=${cw.h}');
            raw = '$raw cband ${cw.raw}';
            chk('카드 결정 필요 띠 글 낱말 안 끊김 0(DU538 그대로)', cw.wb == 0, cw.raw);

            // ⑦ 연장 · 종료 — 색(DU536 그대로) → 첫 화면 캡처 → 명단을 끌어 버튼을 보이는 칸에 넣고 보임 · hit · 받는 자리(기록). 누르지 않는다.
            final extF = findVisibleText('연장');
            final endF = findVisibleText('종료');
            final nExt = extF.evaluate().length;
            final nEnd = endF.evaluate().length;
            need('연장 · 종료 각 1', nExt == 1 && nEnd == 1, 'ext $nExt end $nEnd');
            final under = Color.alphaBlend(_faceOf(t, extF), Colors.white);
            final extBgC = t.widget<Material>(find.ancestor(of: extF, matching: find.byType(Material)).first).color ?? Colors.transparent;
            final endBgC = t.widget<Material>(find.ancestor(of: endF, matching: find.byType(Material)).first).color ?? Colors.transparent;
            final extFgC = _fgOf(t, extF);
            final endFgC = _fgOf(t, endF);
            final rnCr = _contrast(extFgC, Color.alphaBlend(extBgC, under)) >= 4.5 && _contrast(endFgC, Color.alphaBlend(endBgC, under)) >= 4.5;
            _out('D539 $tok att renew extn=$nExt endn=$nEnd extbg=${_hex(extBgC)} extfg=${_hex(extFgC)} endbg=${_hex(endBgC)} endfg=${_hex(endFgC)} cr45=$rnCr');
            await shot('1renew', 'list-first-screen');
            await t.ensureVisible(extInk.first);
            for (var i = 0; i < 10; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final pe = _tapNow(t, extInk.first, dlg, screen);
            final pd = _tapNow(t, endInk.first, dlg, screen);
            final a48 = pe.min48 && pd.min48;
            _out('D539 $tok att acts extvis=${pe.vis} exthit=${pe.hit} endvis=${pd.vis} endhit=${pd.hit} min48=$a48');
            final actRaw = 'ext ${pe.r} vis ${pe.vis} hit ${pe.hit} end ${pd.r} vis ${pd.vis} hit ${pd.hit} min48 $a48';
            raw = '$raw acts $actRaw';
            chk('연장 · 종료 — 명단 칸 안(끌어 넣은 뒤 · hit 은 기록 · DU538 그대로)', pe.vis && pd.vis, actRaw);
            await shot('2acts', 'list-actions-in-view');
          } else if (c.id == 'EMPTY') {
            need('성공 0명 — 빈 상태 문구 1 · 실패 안내 0 · 토스트 0', b0.emptyN == 1 && b0.failN == 0 && b0.toastN == 0, br0);
            await shot('1empty', 'empty-success');
          } else {
            need('첫 조회 실패 — 빈 상태 문구 0 · 실패 안내 1(이 모드의 말끝) · 토스트 1 · 오류 아이콘 = error(DU537 그대로)',
                b0.emptyN == 0 && b0.failN == 1 && b0.toastN == 1 && b0.icon == _wantErr, br0);
            // 실패 토스트(4초)가 내려간 뒤의 본문.
            for (var i = 0; i < 5; i++) {
              await t.pump(const Duration(seconds: 1));
            }
            await shot('1fail', 'load-failed');
          }
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ⑧ 성공 · 실패 공통 정리 — 창을 내리고 남은 timer · 지연 응답이 끝날 시간을 준다.
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

        // ⑨ 집계 — 읽기 호출 수 · 차단된 쓰기/허용 밖 CF 수 · 그 밖 Firestore 연산 · 예상 밖 채널 · HTTP.
        final nApps = wire.calls[_appsFn] ?? 0;
        final nProps = wire.calls['callableGetRenewalProposalsByBiz'] ?? 0;
        final nUsers = wire.calls['callableGetUsersBatch'] ?? 0;
        final nWt = wire.calls['workTypes'] ?? 0;
        final nWrites = wire.blocked.length;
        final nOtherFs = wire.otherFs.length;
        final nUnexp = wire.unexpected.length;
        final nHttp = net.tries.length;
        final nHarness = wire.harness.length;
        final unText = [...wire.unexpected, ...wire.blocked, ...wire.otherFs.map((x) => 'fs $x'), ...wire.harness].join(' | ');
        _out('D539 $tok att wire apps=$nApps props=$nProps users=$nUsers wt=$nWt writes=$nWrites otherfs=$nOtherFs unexpected=$nUnexp http=$nHttp harness=$nHarness');

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
        _out('R539 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D539 $tok att fw n=$nFw');
        _out('D539 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        // 지원서 조회 수 — 한 사업장 사례 1 · LATE 2(A 보류 1 + B 1) · SWITCHFAIL 은 strict 3(A 1 + B 실패 1 + 다시 시도 1) / before 2(다시 시도 버튼이 없다).
        final wantApps = c.id == 'LATE' ? 2 : (c.id == 'SWITCHFAIL' ? (_before ? 2 : 3) : 1);
        chk('쓰기 · 허용 밖 CF 0 · HTTP 0 · 대역 오류 0', nWrites == 0 && nHttp == 0 && nHarness == 0, unText);
        chk('읽기 대역 호출(지원서 $wantApps · 업무유형 ≥1)', nApps == wantApps && nWt >= 1, 'apps $nApps wt $nWt');
        if (!_before) chk('strict 화면 전체 넘침 0(W · B 모두)', nOvf == 0, ovfRaw);
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
