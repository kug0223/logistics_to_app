// ignore_for_file: depend_on_referenced_packages
// [DU552 · F135-FIXEDWORKER-LAYOUT 후속 · 일반 모드 받는 자리] 고정근무자 관리 창(FixedWorkerManagementDialog) 일반 모드 — 만료 임박 띠 일괄 연장 · 카드 결정 띠 연장 · 종료의 받는 자리 48 이상.
//   판정 = reports/DU_audit_self_review_retro144_2026-11-21.md §5(:74–76) + retro143 :62(W 세 종류 미달 · B 일괄 연장만 미달/연장 · 종료 충족).
//   before = 현재 A(fixed_worker_management_dialog 83c5f7ae = DU551 r3 채택판) 기록 전용 · strict = 후보(767862da).
//   하네스 = DU551 LIST 그대로(= DU543 r3 RENEW 일반 모드 대역 — 5명 · 연장 제안 1 · 첫 진입 대상 u_a1 자동 검색 · 한 사업장 · 읽기 CF 4종) — 날짜 모드 분기는 뺐다.
//   측정(읽기만) = 받는 자리(InkWell) · 버튼 전체(TextButton · Material) 폭/높이 · 48 이상 · 창/화면/명단 칸 안 · 중심 hit(DU538 r2 · DU543 r3 · DU551 _tapNow 식) ·
//     이름표 글 줄 수 · 말줄임(DU551 _txtNow) · 띠 상자 안 · 서로/띠 글과 겹침 · 자리(띠 글 옆/아래 · 한 줄) · 띠 상자 · 카드 · 명단 칸 높이 · 닫기 도달 ·
//     버튼이 눌릴 수 있는가(값만 · DU543 r3 _on — stale 아님 · 잠금 아님 · 카드 상세 진입 있음).
//   누르는 것 0 · 입력 0 · 끌기 0(ensureVisible 한 번 — DU538 r2 · DU543 r3 RENEW 와 같다 · 업무 writer 불실행). 넘침 · framework 오류: 두 모드 0.
//   기본 skip — TB before/du552-tb/DU_BEFORE_OBSERVE=552 · TA after/du552-ta/없음.
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
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';

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

/// 소유자(BUSINESS_ADMIN) — DU540 · DU548 · DU551 _Owner 와 같은 override(창은 `canForBusiness` · `watchBusinessPermissions` 를 부른다).
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

/// 장기 확정 지원서 한 건 — 종료일 = 오늘 + [endIn]일(DU540 · DU543 r3 · DU551 과 같은 꼴 · status 기본 CONFIRMED).
Map<String, Object?> _app(String id, String applicant, int endIn, {String status = 'CONFIRMED', Map<String, Object?> extra = const <String, Object?>{}}) =>
    <String, Object?>{
      'id': id, 'uid': 'u_$id', 'businessId': _biz1, 'businessName': _bizName, 'toId': 'to1', 'toTitle': '장기 모집',
      'selectedWorkType': '홀서빙', 'startTime': '09:00', 'endTime': '18:00', 'status': status, 'type': 'long_term',
      'applicantName': applicant, 'wage': 12000, 'wageType': 'hourly', 'workDays': const <Object?>['월', '화', '수', '목', '금'],
      'workDate': _ts(_kstDayMs(-30)), 'workEndDate': _ts(_kstDayMs(endIn)),
      'appliedAt': _ts(_kstDayMs(-32)), 'confirmedAt': _ts(_kstDayMs(-31)),
      ...extra,
    };

const _names = <String, String>{
  'u_a1': '김연장', 'u_a2': '이대기', 'u_a3': '박서명', 'u_a4': '최종료', 'u_a5': '정해지',
  'u_c1': '김가람', 'u_c2': '이나래', 'u_c3': '서다솜', 'u_c4': '박다온',
};

/// 일반 모드 대역 5명(DU536 · DU540 · DU543 r3 RENEW · DU551 LIST 와 같다 · 호출마다 새로 만든다) — a1 만료 10일 전 · a2 만료 5일 전 + 연장 제안 응답 대기 ·
///   a3 계약 처리 필요 · a4 종료 결정 · a5 해지 요청 중. 첫 진입 대상 u_a1(김연장) 자동 검색 — 카드 1장(결정 띠 연장 · 종료) · 만료 임박 띠(일괄 연장)는 전체 명단 기준.
List<Object?> _apps() => <Object?>[
      _app('a1', '김연장', 10),
      _app('a2', '이대기', 5),
      _app('a3', '박서명', 25, status: 'CONTRACT_PENDING'),
      _app('a4', '최종료', 40, extra: <String, Object?>{'renewalDecision': 'TERMINATE'}),
      _app('a5', '정해지', 60, extra: <String, Object?>{'terminationStatus': 'PENDING', 'terminationRequestedAt': _ts(_kstDayMs(-1))}),
    ];

/// a2 의 연장 제안(응답 대기) — 효력 시작 = 지금 종료일 다음 날(DU543 r3 · DU551 과 같다).
Map<String, Object?> _proposal() => <String, Object?>{
      'id': 'rp1', 'businessId': _biz1, 'businessName': _bizName, 'workerUid': 'u_a2', 'oldApplicationId': 'a2', 'status': 'PENDING',
      'effectiveStart': _ts(_kstDayMs(6)), 'effectiveEnd': _ts(_kstDayMs(36)), 'selectedWorkType': '홀서빙',
    };

const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
const _wtPath = 'businesses/$_biz1/workTypes';
const _appsFn = 'callableGetApplicationsByBiz';
const _schedFn = 'callableGetScheduleChangeRequestsForDate';

/// 첫 화면이 부르는 읽기 CF(DU540 · DU548 · DU551 과 같은 4종) — 이 밖의 CF 이름(일괄 연장 · 연장 제안 · 종료 포함)은 차단하고 센다.
const _readFns = <String>{'callableGetApplicationsByBiz', 'callableGetRenewalProposalsByBiz', 'callableGetUsersBatch', _schedFn};

/// Firestore 쓰기 연산 — 하나라도 오면 writes 로 센다.
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

/// [DU526 · DU534 · DU536 · DU540 · DU548 · DU551 과 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널.
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du552.fake.auth.';
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
///   기반 채널은 원래 경로, 나머지는 이름을 기록하고 응답 null. 예외를 삼키지 않는다 — 수는 줄로 남긴다.
///   (DU551 _Wire 의 LIST 응답 분기 그대로 — 날짜 모드 대역 분기만 뺐다 · 응답 모양 · 값 같음.)
class _Wire {
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
        return codec.encodeMessage(<Object?>['not-found', 'du552-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      _hit(fn);
      if (fn == _appsFn) {
        return codec.encodeMessage(<Object?>[<String, Object?>{'applications': _apps()}]);
      }
      if (fn == 'callableGetRenewalProposalsByBiz') {
        return codec.encodeMessage(<Object?>[<String, Object?>{'proposals': <Object?>[_proposal()]}]);
      }
      if (fn == _schedFn) {
        // 일반 모드는 일정 요청을 부르지 않는다(DU551 LIST sched 0) — 오면 DU551 LIST 와 같은 빈 목록.
        return codec.encodeMessage(<Object?>[<String, Object?>{'items': const <Object?>[]}]);
      }
      final uids = (params['uids'] as List).cast<String>();
      return codec.encodeMessage(<Object?>[
        <String, Object?>{
          'users': <String, Object?>{for (final u in uids) u: <String, Object?>{'name': _names[u] ?? '근로자', 'role': 'USER'}},
        },
      ]);
    } catch (e) {
      harness.add('cf $e');
      return codec.encodeMessage(<Object?>['internal', 'du552-harness', null]);
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
      return codec.encodeMessage(<Object?>['du552-blocked', '$op 차단', null]);
    } catch (e) {
      harness.add('fs $op $e');
      return codec.encodeMessage(<Object?>['du552-harness', '대역 오류', null]);
    }
  }
}

/// 외부 HTTP 차단 — 만들려는 시도를 기록하고 실패시킨다.
class _NoHttp extends HttpOverrides {
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    throw const SocketException('DU552 관측 — 외부 HTTP 차단');
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

bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

/// 두 상자가 겹치는가(겹친 넓이의 가로 · 세로 모두 0.5 초과).
bool _overlap(Rect a, Rect b) {
  final i = a.intersect(b);
  return i.width > 0.5 && i.height > 0.5;
}

/// 두 상자가 같은가(네 변 모두 0.5 안).
bool _same(Rect a, Rect b) =>
    (a.left - b.left).abs() <= 0.5 && (a.top - b.top).abs() <= 0.5 && (a.right - b.right).abs() <= 0.5 && (a.bottom - b.bottom).abs() <= 0.5;

/// 폭 · 높이 모두 48 이상인가(getRect 소수 오차 허용 — `>= 48 - 0.01` · _tapNow 의 min48 과 같은 식).
bool _ge48(Rect r) => r.width >= 48 - 0.01 && r.height >= 48 - 0.01;

/// 상자 [r] 를 [o] 기준 상대 좌표 'l,t,r,b'(소수 1자리)로.
String _rel(Rect r, Rect o) =>
    [r.left - o.left, r.top - o.top, r.right - o.left, r.bottom - o.top].map((x) => x.toStringAsFixed(1)).join(',');

/// 요소 하나가 끌기 없이 보이고 눌리는가 — 창 상자 ∩ 화면(∩ 가까운 Scrollable 이 있으면 그 칸) 안 + 중심 hit(DU537 · DU538 r2 · DU540 · DU543 r3 · DU548 · DU551 `_tapNow` 와 같은 식).
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

typedef _Txt = ({int n, String s, bool ex, int wb, int lines, Rect r});

/// 글 하나([f] = Text 위젯 하나)의 그려진 문단(읽기만) — 보이는 글(표시 제어 문자 제거) · 말줄임/줄 제한 넘음(didExceedMaxLines) ·
///   피할 수 있는 낱말 안 끊김 수(공용 판정기 du_word_break) · 줄 수(글자 상자 윗변이 1px 넘게 내려간 횟수 + 1) · 자리(DU551 _txtNow 그대로).
_Txt _txtNow(WidgetTester t, Finder f) {
  final n = f.evaluate().length;
  if (n != 1) return (n: n, s: '', ex: false, wb: -1, lines: 0, r: Rect.zero);
  final rts = find.descendant(of: f, matching: find.byType(RichText, skipOffstage: false), skipOffstage: false).evaluate().toList();
  final nRt = rts.length;
  if (nRt != 1) return (n: -nRt, s: '', ex: false, wb: -1, lines: 0, r: Rect.zero);
  final rp = rts.first.renderObject! as RenderParagraph;
  final plain = rp.text.toPlainText();
  var lines = 0;
  double? lastTop;
  for (var i = 0; i < plain.length; i++) {
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final top = bx.first.top;
    if (lastTop == null || top > lastTop + 1) {
      lines++;
      lastTop = top;
    }
  }
  final wb = wordBreaks(rp).where((x) => !x.forced).length;
  return (n: 1, s: visibleText(plain), ex: rp.didExceedMaxLines, wb: wb, lines: lines, r: t.getRect(f));
}

typedef _BodyObs = ({int emptyN, int failN, int toastN, String icon});

/// 본문 — 빈 상태 문구 수 · 조회 실패 안내 수(창 안) · 실패 토스트 수(창 밖) · 창 안 오류 아이콘이 있는가. 보이는 글 기준(DU540 · DU548 · DU551 과 같은 식).
_BodyObs _bodyNow(WidgetTester t, Finder dlg) {
  final emptyN = find.descendant(of: dlg, matching: findVisibleText(_emptyText), skipOffstage: true).evaluate().length;
  final failN = find.descendant(of: dlg, matching: findVisibleText(_failText), skipOffstage: true).evaluate().length;
  final toastAll = findVisibleText(_failText).evaluate().length;
  final icons = find.descendant(of: dlg, matching: find.byIcon(Icons.error_outline), skipOffstage: true).evaluate().length;
  return (emptyN: emptyN, failN: failN, toastN: toastAll - failN, icon: icons == 0 ? '-' : 'n$icons');
}

/// [DU551 r2] 화면 글(Text 위젯)만 — find.text 는 검색 칸(EditableText) 글도 잡는다(일반 모드 첫 진입 자동 검색).
Finder _plainText(String s) => find.byWidgetPredicate((w) => w is Text && w.data == s, skipOffstage: false);

/// 화면 글(Text 위젯) 중 보이는 글(표시 제어 문자 제거)에 [part] 가 든 것 — 화면 밖 포함(끌어 넣은 뒤 띠 제목이 칸 위로 나가도 잰다).
Finder _plainTextHas(String part) => find.byWidgetPredicate((w) => w is Text && visibleText(w.data ?? '').contains(part), skipOffstage: false);

/// 행동 위젯 하나가 눌릴 수 있는가(값만 읽는다 · 누르지 않는다) — TextButton.onPressed · InkWell.onTap · GestureDetector.onTap 이 있으면 'true'. 없으면 '-'(DU543 r3 _on 그대로).
String _on(WidgetTester t, Finder f) {
  if (f.evaluate().isEmpty) return '-';
  final w = t.widget(f.first);
  if (w is TextButton) return (w.onPressed != null).toString();
  if (w is InkWell) return (w.onTap != null).toString();
  if (w is GestureDetector) return (w.onTap != null).toString();
  return '?';
}

typedef _LiveObs = ({int staleN, String bulkOn, String extOn, String endOn, String cardOn});

/// stale 안내 수(트리 · 화면 밖 포함) · 일괄 연장(TextButton) · 카드 결정 띠 연장/종료(이름표의 가장 가까운 InkWell) · 카드(이름의 가장 가까운 InkWell = 상세 진입 행동 시트)가
///   눌릴 수 있는가 — 위젯 값만('-' = 없음 · DU543 r3 _liveNow 의 finder + 카드 1). 후보는 콜백 · stale guard · 잠금 식을 바꾸지 않는다(두 모드 같은 값).
_LiveObs _liveNow(WidgetTester t, Finder dlg) {
  Finder inDlg(Finder f) => find.descendant(of: dlg, matching: f, skipOffstage: false);
  return (
    staleN: inDlg(findVisibleText(_staleText)).evaluate().length,
    bulkOn: _on(t, inDlg(find.widgetWithText(TextButton, _bulkText, skipOffstage: false))),
    extOn: _on(t, find.ancestor(of: inDlg(_plainText(_extText)), matching: find.byType(InkWell))),
    endOn: _on(t, find.ancestor(of: inDlg(_plainText(_endText)), matching: find.byType(InkWell))),
    cardOn: _on(t, find.ancestor(of: inDlg(_plainText(_listWho)), matching: find.byType(InkWell))),
  );
}

typedef _BandObs = ({
  int wb, bool bvis, bool bhit, bool stack, String bw, String bh, bool b48, String rw, String rh, bool r48, bool rvis, bool rhit, bool req,
  int bl, bool bex, bool bin, bool bclr, String bnh, String geo, String raw
});

/// 만료 임박 띠(첫 화면 · 끌기 전 · 고정 영역) — 띠 글(낱말 안 끊김 · DU538 그대로) · 일괄 연장 버튼 전체(TextButton — DU538 r2 · DU543 r3 band 와 같은 finder)와
///   받는 자리(그 안 InkWell — 눌림을 받는 상자)의 폭/높이 · 48 이상 · 창/화면 안 · 중심 hit · 두 상자가 같은가 · 이름표 글 줄 수/말줄임 · 띠 상자 안 · 띠 글과 겹침 0 ·
///   띠 글 아래로 내려갔는가(stack · DU538 과 같은 식) · 띠 상자 높이(Container 상자 · 위 여백 포함) · 띠 상자 기준 상대 좌표(버튼 · 받는 자리 · 띠 글). 누르지 않는다.
_BandObs _bandNow(WidgetTester t, Finder dlg, Rect screen) {
  final textF = find.descendant(of: dlg, matching: findVisibleTextContaining(_expiringText), skipOffstage: true);
  final btnF = find.descendant(of: dlg, matching: find.widgetWithText(TextButton, _bulkText), skipOffstage: true);
  final inkF = find.descendant(of: btnF, matching: find.byType(InkWell), skipOffstage: true);
  final tt = _txtNow(t, textF);
  final lab = _txtNow(t, find.descendant(of: btnF, matching: _plainText(_bulkText), skipOffstage: true));
  final boxR = t.getRect(find.ancestor(of: textF, matching: find.byType(Container)).first);
  final o = _tapNow(t, btnF, dlg, screen);
  final r = _tapNow(t, inkF, dlg, screen);
  final stack = o.r.top >= tt.r.bottom - 0.5;
  final geo = '${_rel(o.r, boxR)};${_rel(r.r, boxR)};${_rel(tt.r, boxR)}';
  final raw = 'text n ${tt.n} "${tt.s}" wb ${tt.wb} l ${tt.lines} ex ${tt.ex} btn ${o.r} ${o.vis}/${o.hit} ink ${r.r} ${r.vis}/${r.hit} '
      'label n ${lab.n} "${lab.s}" l ${lab.lines} ex ${lab.ex} box ${boxR.height.toStringAsFixed(1)} geo $geo';
  return (
    wb: tt.wb, bvis: o.vis, bhit: o.hit, stack: stack, bw: o.r.width.toStringAsFixed(1), bh: o.r.height.toStringAsFixed(1), b48: o.min48,
    rw: r.r.width.toStringAsFixed(1), rh: r.r.height.toStringAsFixed(1), r48: r.min48, rvis: r.vis, rhit: r.hit, req: _same(o.r, r.r),
    bl: lab.lines, bex: lab.ex, bin: _inside(o.r, boxR) && _inside(r.r, boxR), bclr: !_overlap(o.r, tt.r) && !_overlap(r.r, tt.r),
    bnh: boxR.height.toStringAsFixed(1), geo: geo, raw: raw,
  );
}

typedef _ActsObs = ({
  bool extvis, bool exthit, bool endvis, bool endhit, String ew, String eh, String dw, String dh, bool e48, bool d48, bool eo48, bool do48,
  int el, int dl, bool eex, bool dex, bool ein, bool din, bool edclr, bool row, String rbh, String ch, String geo, String raw
});

/// 카드 결정 띠(ensureVisible 뒤) — 연장 · 종료의 받는 자리(이름표의 가장 가까운 InkWell — DU538 r2 · DU543 r3 acts 와 같은 finder · 식)의 폭/높이 · 48 이상 ·
///   명단 칸 안 · 중심 hit / 버튼 전체(그 InkWell 의 가장 가까운 Material — 보이는 면) 48 이상 / 이름표 글 줄 수 · 말줄임 / 띠 상자 안 · 연장과 종료 · 띠 제목과 겹침 0 ·
///   한 줄(윗변 · 아랫변 같음) / 띠 상자 높이(Container 상자 · 아래 여백 포함) · 카드 높이 · 띠 상자 기준 상대 좌표. 누르지 않는다.
_ActsObs _actsNow(WidgetTester t, Finder dlg, Rect screen) {
  Finder inDlg(Finder f) => find.descendant(of: dlg, matching: f, skipOffstage: false);
  final titleF = inDlg(_plainTextHas(_renewTitle));
  final titleR = t.getRect(titleF);
  final boxR = t.getRect(find.ancestor(of: titleF, matching: find.byType(Container)).first);
  final cardR = t.getRect(find.ancestor(of: titleF, matching: find.byType(InkWell)).first);
  final extL = inDlg(_plainText(_extText));
  final endL = inDlg(_plainText(_endText));
  final extInk = find.ancestor(of: extL, matching: find.byType(InkWell)).first;
  final endInk = find.ancestor(of: endL, matching: find.byType(InkWell)).first;
  final pe = _tapNow(t, extInk, dlg, screen);
  final pd = _tapNow(t, endInk, dlg, screen);
  final oe = t.getRect(find.ancestor(of: extInk, matching: find.byType(Material)).first);
  final od = t.getRect(find.ancestor(of: endInk, matching: find.byType(Material)).first);
  final le = _txtNow(t, extL);
  final ld = _txtNow(t, endL);
  final row = (pe.r.top - pd.r.top).abs() <= 0.5 && (pe.r.bottom - pd.r.bottom).abs() <= 0.5;
  final edclr = !_overlap(pe.r, pd.r) && !_overlap(pe.r, titleR) && !_overlap(pd.r, titleR);
  final geo = '${_rel(pe.r, boxR)};${_rel(pd.r, boxR)};${_rel(oe, boxR)};${_rel(od, boxR)};${_rel(titleR, boxR)}';
  final raw = 'ext ${pe.r} ${pe.vis}/${pe.hit} face $oe label "${le.s}" l ${le.lines} ex ${le.ex} · end ${pd.r} ${pd.vis}/${pd.hit} face $od label "${ld.s}" l ${ld.lines} ex ${ld.ex} '
      'box ${boxR.height.toStringAsFixed(1)} card ${cardR.height.toStringAsFixed(1)} geo $geo';
  return (
    extvis: pe.vis, exthit: pe.hit, endvis: pd.vis, endhit: pd.hit,
    ew: pe.r.width.toStringAsFixed(1), eh: pe.r.height.toStringAsFixed(1), dw: pd.r.width.toStringAsFixed(1), dh: pd.r.height.toStringAsFixed(1),
    e48: pe.min48, d48: pd.min48, eo48: _ge48(oe), do48: _ge48(od), el: le.lines, dl: ld.lines, eex: le.ex, dex: ld.ex,
    ein: _inside(pe.r, boxR), din: _inside(pd.r, boxR), edclr: edclr, row: row,
    rbh: boxR.height.toStringAsFixed(1), ch: cardR.height.toStringAsFixed(1), geo: geo, raw: raw,
  );
}

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
const _cases = <({String id, int shots})>[(id: 'ACTS', shots: 2)];

/// 일반 모드 카드(첫 진입 대상 u_a1 자동 검색).
const _listWho = '김연장';
/// 글 원문(대상 소스와 같다 — mkcell 이 원문 대조).
const _titleText = '고정근무자 관리';
const _emptyText = '고정근무자가 없습니다';
const _failText = '고정근무자 목록을 불러오지 못했어요';
const _staleText = '최신 정보를 불러오지 못했어요. 아래는 이전에 받은 내용입니다.';
const _expiringText = '계약 만료 임박';
const _bulkText = '일괄 연장';
const _extText = '연장';
const _endText = '종료';
const _renewTitle = '계약 만료 D-10';
const _closeText = '닫기';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '552';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du552-tb' && _env['DU_BEFORE_OBSERVE'] == '552') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du552-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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
    final wire = _Wire();
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
    _out('R552 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S952FR-${v.id}-${c.id} 고정근무자 관리 창 일반 모드 일괄 연장 · 연장 · 종료 받는 자리 48 이상 — 폭 · 높이 · 중심 hit · 줄바꿈 · 겹침 · 스크롤 도달', (t) async {
        final tok = 'S952FR-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');

        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final wire = _Wire();
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
        _out('D552 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        final owner = _Owner();
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
                  body: FixedWorkerManagementDialog(
                    key: UniqueKey(),
                    initialBusinessId: _biz1,
                    businesses: [_business(_biz1, _bizName)],
                    initialWorkerUid: 'u_a1',
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
            _out('D552 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          // 그려진 글 집합(첫 화면 · 보이는 글 기준 · 숫자는 # 으로). 기록용 — 후보는 문구를 바꾸지 않는다(W · B 모두 TB = TA 손 대조).
          final words = <String>{};
          for (final e in find.descendant(of: dlg, matching: find.byType(Text), skipOffstage: true).evaluate()) {
            final d = (e.widget as Text).data;
            if (d != null && d.isNotEmpty) words.add(visibleText(d).replaceAll(RegExp(r'\d+'), '#'));
          }
          final wordList = words.toList()..sort();
          _out('D552 $tok att txt n=${wordList.length} set=${_enc(wordList.join('|'))}');

          // ① 첫 화면 — 본문 · 명단 칸(창 안 ListView 하나의 Scrollable) · 카드 1장(첫 진입 대상 자동 검색).
          final b0 = _bodyNow(t, dlg);
          _out('D552 $tok att body emptyn=${b0.emptyN} failn=${b0.failN} toastn=${b0.toastN} icon=${b0.icon}');
          final br0 = 'empty ${b0.emptyN} fail ${b0.failN} toast ${b0.toastN} icon ${b0.icon}';
          need('본문 — 빈 상태 문구 0 · 실패 안내 0 · 토스트 0', b0.emptyN == 0 && b0.failN == 0 && b0.toastN == 0, br0);
          final listV = find.descendant(of: dlg, matching: find.byType(ListView), skipOffstage: false);
          final nLv = listV.evaluate().length;
          need('명단 ListView 1', nLv == 1, '개수 $nLv');
          final listSc = find.descendant(of: listV, matching: find.byType(Scrollable), skipOffstage: false).first;
          final lv = t.getRect(listSc).height.toStringAsFixed(1);
          final nameN = find.descendant(of: dlg, matching: _plainText(_listWho), skipOffstage: false).evaluate().length;
          need('일반 모드 카드 이름 1(첫 진입 대상 자동 검색)', nameN == 1, '개수 $nameN');
          raw = 'body $br0 lv $lv';

          // ② 눌릴 수 있는가(값만) — stale 아님 · 잠금 아님 · 일괄 연장 · 연장 · 종료 · 카드(상세 진입). 후보는 콜백 · guard 를 바꾸지 않는다 → 두 모드 같은 값.
          final lo = _liveNow(t, dlg);
          _out('D552 $tok att live stalen=${lo.staleN} bulkon=${lo.bulkOn} exton=${lo.extOn} endon=${lo.endOn} cardon=${lo.cardOn}');
          final lr = 'stale ${lo.staleN} bulk ${lo.bulkOn} ext ${lo.extOn} end ${lo.endOn} card ${lo.cardOn}';
          raw = '$raw live $lr';
          chk('stale 아님 — 안내 0 · 일괄 연장 · 연장 · 종료 · 카드(상세 진입) 눌릴 수 있다(값만 · 두 모드)',
              lo.staleN == 0 && lo.bulkOn == 'true' && lo.extOn == 'true' && lo.endOn == 'true' && lo.cardOn == 'true', lr);

          // ③ 만료 임박 띠 — 일괄 연장 버튼 전체(TextButton) · 받는 자리(그 안 InkWell) · 이름표 · 자리 · 띠 상자. 누르지 않는다.
          final bandF = find.descendant(of: dlg, matching: findVisibleTextContaining(_expiringText), skipOffstage: true);
          final bulkF = find.descendant(of: dlg, matching: find.widgetWithText(TextButton, _bulkText), skipOffstage: true);
          final nBand = bandF.evaluate().length;
          final nBulk = bulkF.evaluate().length;
          final nBulkInk = find.descendant(of: bulkF, matching: find.byType(InkWell), skipOffstage: true).evaluate().length;
          final nBulkLab = find.descendant(of: bulkF, matching: _plainText(_bulkText), skipOffstage: true).evaluate().length;
          need('만료 임박 띠 글 1 · 일괄 연장 버튼 1 · 그 안 InkWell 1 · 이름표 1', nBand == 1 && nBulk == 1 && nBulkInk == 1 && nBulkLab == 1,
              'band $nBand bulk $nBulk ink $nBulkInk label $nBulkLab');
          final bo = _bandNow(t, dlg, screen);
          _out('D552 $tok att band n=$nBand wb=${bo.wb} bvis=${bo.bvis} bhit=${bo.bhit} stack=${bo.stack} bw=${bo.bw} bh=${bo.bh} b48=${bo.b48} rw=${bo.rw} rh=${bo.rh} r48=${bo.r48} rvis=${bo.rvis} rhit=${bo.rhit} req=${bo.req} bl=${bo.bl} bex=${bo.bex} bin=${bo.bin} bclr=${bo.bclr} bnh=${bo.bnh} geo=${bo.geo}');
          raw = '$raw band ${bo.raw}';
          chk('만료 임박 띠 글 낱말 안 끊김 0(DU538 그대로 · 두 모드)', bo.wb == 0, bo.raw);
          chk('일괄 연장 버튼 화면 안 · 중심 hit(DU538 그대로 · 두 모드)', bo.bvis && bo.bhit, bo.raw);
          chk(isB ? 'B 일괄 연장이 띠 글 아래(DU538 그대로 · 두 모드)' : 'W 일괄 연장이 띠 글 옆(이전 한 줄 그대로 · 두 모드)', bo.stack == isB, bo.raw);
          if (!_before) {
            chk('strict 일괄 연장 버튼 전체 · 받는 자리 폭 · 높이 48 이상 · 받는 자리 화면 안 · 중심 hit', bo.b48 && bo.r48 && bo.rvis && bo.rhit, bo.raw);
            chk('strict 일괄 연장 이름표 한 줄 · 말줄임 0 · 띠 상자 안 · 띠 글과 겹침 0', bo.bl == 1 && !bo.bex && bo.bin && bo.bclr, bo.raw);
          }

          // ④ 명단 칸 높이(고정 띠가 커진 만큼 줄어든다 — 기록) · 아래 닫기 도달.
          final kF = find.descendant(of: dlg, matching: find.text(_closeText), skipOffstage: true);
          final nK = kF.evaluate().length;
          need('닫기 글 1', nK == 1, '개수 $nK');
          final kp = _tapNow(t, kF, dlg, screen);
          _out('D552 $tok att lay lv=$lv kn=$nK kvis=${kp.vis} khit=${kp.hit}');
          final kr = 'lv $lv close ${kp.r} ${kp.vis}/${kp.hit}';
          raw = '$raw lay $kr';
          if (!_before) chk('strict 닫기(아래 닫기 글) 창 안 · 중심 hit — 고정 띠가 커져도 닿는다', kp.vis && kp.hit, kr);
          await shot('1band', 'list-first-screen-bulk-band');

          // ⑤ 카드 결정 띠 연장 · 종료 — 끌기 전 보임(기록) → 연장 받는 자리를 명단 칸에 넣는다(ensureVisible 한 번 · DU543 r3 RENEW 와 같다) → 잰다. 누르지 않는다.
          final extL = find.descendant(of: dlg, matching: _plainText(_extText), skipOffstage: false);
          final endL = find.descendant(of: dlg, matching: _plainText(_endText), skipOffstage: false);
          final nExt = extL.evaluate().length;
          final nEnd = endL.evaluate().length;
          final nRenew = find.descendant(of: dlg, matching: _plainTextHas(_renewTitle), skipOffstage: false).evaluate().length;
          need('연장 · 종료 이름표 각 1 · 카드 결정 띠 제목 1', nExt == 1 && nEnd == 1 && nRenew == 1, 'ext $nExt end $nEnd title $nRenew');
          final extInk = find.ancestor(of: extL, matching: find.byType(InkWell)).first;
          final evis0 = _tapNow(t, extInk, dlg, screen).vis;
          await t.ensureVisible(extInk);
          for (var i = 0; i < 10; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          final ao = _actsNow(t, dlg, screen);
          _out('D552 $tok att acts evis0=$evis0 extvis=${ao.extvis} exthit=${ao.exthit} endvis=${ao.endvis} endhit=${ao.endhit} ew=${ao.ew} eh=${ao.eh} dw=${ao.dw} dh=${ao.dh} e48=${ao.e48} d48=${ao.d48} eo48=${ao.eo48} do48=${ao.do48} el=${ao.el} dl=${ao.dl} eex=${ao.eex} dex=${ao.dex} ein=${ao.ein} din=${ao.din} edclr=${ao.edclr} row=${ao.row} rbh=${ao.rbh} ch=${ao.ch} geo=${ao.geo}');
          raw = '$raw acts pre $evis0 ${ao.raw}';
          chk('연장 · 종료 — 끌어 넣은 뒤 명단 칸 안 · 중심 hit · 한 줄(DU543 r3 그대로 · 두 모드)', ao.extvis && ao.exthit && ao.endvis && ao.endhit && ao.row, ao.raw);
          if (!_before) {
            chk('strict 연장 · 종료 받는 자리(InkWell) · 버튼 전체(Material) 폭 · 높이 48 이상', ao.e48 && ao.d48 && ao.eo48 && ao.do48, ao.raw);
            chk('strict 연장 · 종료 이름표 한 줄 · 말줄임 0 · 띠 상자 안 · 서로 · 띠 제목과 겹침 0', ao.el == 1 && ao.dl == 1 && !ao.eex && !ao.dex && ao.ein && ao.din && ao.edclr, ao.raw);
          }
          await shot('2acts', 'list-renew-actions-in-view');
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ⑥ 성공 · 실패 공통 정리 — 창을 내리고 남은 timer 가 끝날 시간을 준다.
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

        // ⑦ 집계 — 읽기 호출 수 · 차단된 쓰기/허용 밖 CF 수 · 그 밖 Firestore 연산 · 예상 밖 채널 · HTTP.
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
        _out('D552 $tok att wire apps=$nApps props=$nProps users=$nUsers wt=$nWt sched=$nSched writes=$nWrites otherfs=$nOtherFs unexpected=$nUnexp http=$nHttp harness=$nHarness');

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
        _out('R552 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D552 $tok att fw n=$nFw');
        _out('D552 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        chk('쓰기 · 허용 밖 CF 0 · HTTP 0 · 대역 오류 0(업무 writer 불실행)', nWrites == 0 && nHttp == 0 && nHarness == 0, unText);
        chk('읽기 대역 호출(지원서 1 · 업무유형 1 이상 · 일정 요청 0 — 일반 모드)', nApps == 1 && nWt >= 1 && nSched == 0, 'apps $nApps wt $nWt sched $nSched');
        // 넘침: 두 모드 0(DU551 r3 LIST · DU543 r3 RENEW W · B 관측 0 — 후보는 받는 자리만 키운다).
        chk('화면 전체 넘침 0(두 모드)', nOvf == 0, ovfRaw);
        chk('미처리 framework 예외 0', nFw == 0, fwRaw);
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
