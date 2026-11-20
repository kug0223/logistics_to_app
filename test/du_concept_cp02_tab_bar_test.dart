// ignore_for_file: depend_on_referenced_packages
// [CP02] 두 셸 하단 탭 표시부 — 지원자 4탭·전체 관리자 5탭·제한 SubAdmin(비연속)·권한 미확인·현재 탭 권한 회수.
//   지시: records/requests/DU_concept_CP02_start_2026-11-11.md · 정본 §7. phase = DU1_VQ_PHASE=before|after(없으면 실패).
//   before = 원본 관측 기록(사전 결손은 실패로 만들지 않는다), after = 사양 단언. 두 phase 공통 = 라우팅·권한 보존 단언.
//   [C1] c1 = CP02 C1 교정 확인(requests/DU_concept_CP02_c1_followup·_c1_decision_2026-11-11.md): ①②×W/B 4사례만.
//        새 비선택 색 textPrimary·수평 padding 6·표시값 keepWords(원문/의미 이름 exact)·낱말별 줄 위치·글자 상자 화면좌표·자연 높이.
//        원 10사례 경로·기대는 그대로 둔다. 공통 정합화는 라벨 측정 adapter(RichText 경유·표시 문자열 길이)뿐이다.
//   [C2] c2 = CP02 C2 아이콘 줄 정렬 확인(requests/DU_concept_CP02_c2_followup_2026-11-11.md): C1 기대 전부 계승(c1 분기 = c1·c2)
//        + receiver 안 Icon 정확 1개·아이콘 24 상자 top = receiver top + 6·같은 행 편차 ≤0.01·라벨 top = 아이콘 bottom + 4.
//        원 before/after/c1 경로·기대·계수는 그대로 둔다.
//   기존 LOCAL 진입 재사용: 실제 셸 루트(user_root_tab_navigation_test.dart·du1_s037_*_test.dart 와 같은 MaterialApp(home: 셸)).
//   셸에 탭 본문 seam 이 없어 실제 탭 화면이 함께 뜬다 — Firestore·Functions 채널은 전부 오류로 막고(fail-closed) 계수한다.
//   navigatorKey 는 붙이지 않는다(URN 시험과 같음 — 전역 토스트·FCM 이동 0). 새 위젯 타입은 import 하지 않는다(before 컴파일).
import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/foundation.dart';
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
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_admin_shell.dart';
import 'package:ALfit/screens/user/user_root_screen.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/services/posting_quota_summary.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/admin_tab_switcher.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/user/pending_contract_bar.dart';

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

// ── 역할 대역(게터 덮개 — 실 구독·실서비스 0). 판정 의미는 user_provider.dart 의 각 함수 분기를 그대로 옮긴다 ──
class _Worker extends UserProvider {
  _Worker({this.pending = false});
  bool pending;
  void setPending(bool v) {
    pending = v;
    notifyListeners();
  }

  @override
  UserModel? get currentUser => UserModel(
      uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구', district: '역삼동'),
      accountStatus: 'active', passVerifiedAt: DateTime.utc(2026, 10, 1), totalWorkDays: 3);
  @override
  bool get isUser => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
  @override
  bool get hasPendingContract => pending;
  @override
  int get pendingContractCount => pending ? 1 : 0;
  @override
  EmploymentContractModel? get nearestPendingContract => null;
}

enum _Mode { full, restricted, unknown }

/// 관리자 셸 대역. owner=true 는 BUSINESS_ADMIN(모든 판정 첫 분기 허용), 아니면 SubAdmin(모드별).
///   unknown: checkCurrentBusiness → unknown(!_permissionsLoaded 분기), canForAnyBusiness → whenUnknown(!_subAdminPermissionsLoaded 분기),
///            can → false(_memberPermissions null 분기). 그래서 공고 = can(canManageTo)=false 로 숨김, 근무·급여 = unknown 이라 유지.
class _Admin extends UserProvider {
  _Admin({required this.owner, required this.mode, MemberPermissions? perms}) : perms = perms ?? MemberPermissions.all();
  final bool owner;
  final _Mode mode;
  MemberPermissions perms;

  /// 현재 탭 권한 회수 — 근무(canManageWorkers)만 끈다.
  void revokeWorkers() {
    perms = const MemberPermissions(
        canManageTo: true, canManageWorkers: false, canManageWage: true, canManageContract: true, canCancelTransfer: true);
    notifyListeners();
  }

  @override
  UserModel? get currentUser => owner
      ? UserModel(uid: 'admin1', username: 'admin1', name: '김관리', email: 'admin1@alfit.local', role: UserRole.BUSINESS_ADMIN,
          businessId: 'biz1', managedBusinessIds: const ['biz1'], sealBase64: 'seal')
      : UserModel(uid: 'sub1', username: 'sub1', name: '박하위', email: 'sub1@alfit.local', role: UserRole.USER,
          subAdminBusinessIds: const ['biz1'], sealBase64: 'seal');
  @override
  bool get isUser => !owner;
  @override
  bool get isSubAdmin => !owner;
  @override
  bool get isBusinessAdmin => owner;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => mode != _Mode.unknown;
  @override
  bool get subAdminPermissionsLoaded => mode != _Mode.unknown;
  @override
  String? get effectiveBusinessId => owner ? null : 'biz1';
  @override
  Map<String, String> get subAdminBusinessNames => owner ? const {} : const {'biz1': 'QA 물류센터'};
  @override
  PermissionWatchState get currentBusinessPermissionHealth =>
      !owner && mode == _Mode.unknown ? PermissionWatchState.unknown : PermissionWatchState.verified;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => owner
      ? PermissionCheck.allowed
      : mode == _Mode.unknown
          ? PermissionCheck.unknown
          : (check(perms) ? PermissionCheck.allowed : PermissionCheck.denied);
  @override
  bool can(bool Function(MemberPermissions p) check) => owner || (mode != _Mode.unknown && check(perms));
  @override
  bool canForAnyBusiness(bool Function(MemberPermissions p) check, {required bool whenUnknown}) =>
      owner || (mode == _Mode.unknown ? whenUnknown : check(perms));
  @override
  VoidCallback watchBusinessPermissions(String businessId) => () {};
}

// ── 채널 차단(fail-closed) — du1_s037_*_test.dart 의 채널 이름·오류 응답 모양 그대로 ──
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
const _fnCh = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsReads = ['documentReferenceGet', 'queryGet', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot'];
const _fsWrites = ['documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit',
  'transactionCreate', 'transactionStoreResult', 'transactionGet'];
final _calls = <String, int>{};

void _stubChannels(WidgetTester t) {
  final m = t.binding.defaultBinaryMessenger;
  const codec = FirebaseFirestoreHostApi.codec;
  for (final op in [..._fsReads, ..._fsWrites]) {
    m.setMockMessageHandler('$_fsBase.$op', (msg) async {
      _calls['fs.$op'] = (_calls['fs.$op'] ?? 0) + 1;
      return codec.encodeMessage(<Object?>['cp02-blocked', '$op 차단', null]);
    });
  }
  m.setMockMessageHandler(_fnCh, (msg) async {
    const c = StandardMessageCodec();
    final args = (c.decodeMessage(msg) as List).first as Map;
    final k = 'fn.${args['functionName']}';
    _calls[k] = (_calls[k] ?? 0) + 1;
    return c.encodeMessage(<Object?>['not-found', 'cp02-blocked', <String, Object?>{'code': 'not-found', 'message': 'cp02-blocked'}]);
  });
  addTearDown(() {
    for (final op in [..._fsReads, ..._fsWrites]) {
      m.setMockMessageHandler('$_fsBase.$op', null);
    }
    m.setMockMessageHandler(_fnCh, null);
  });
}

// CP01 과 같은 폰트 로드(번들 NotoSansKR Regular+Bold, Roboto 별칭, FlutterTest=Regular, SDK MaterialIcons)
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

// ── 계수(phase 상한: 사례 10 · tap 64 · drag 8 · pump+mount 700 · PNG 8쌍) ──
int _mounts = 0, _pumps = 0, _pngs = 0, _taps = 0;
const _drags = 0;
final _cases = <String>{};
final _diag = Expando<String>('cp02-diag');

typedef _V = ({String id, Size size, double scale});
const _V _w = (id: 'W', size: Size(390, 844), scale: 1.0);
const _V _b = (id: 'B', size: Size(320, 640), scale: 2.0);
const _inset = 34.0;
// 셸·탭 표시부 소유 파일 — 이 파일이 오류 진단에 나오면 셸 오류로 분류한다(before 의 SDK 탭 포함).
const _shellFiles = ['app_bottom_tab_bar.dart', 'user_root_screen.dart', 'business_admin_shell.dart', 'bottom_navigation_bar.dart'];

/// [C2] 실제 실행일(KST) 'YYYY-MM-DD'.
String _kstToday() {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  String p(int x) => x.toString().padLeft(2, '0');
  return '${k.year}-${p(k.month)}-${p(k.day)}';
}

void main() {
  final phase = vqPhase ?? '';
  final env = Platform.environment;
  final meta = env['CP02_META'] ?? '';
  // [C1] c1 은 새 표시부(after 와 같은 위젯)를 C1 기대로 본다.
  // [C2] c2 는 C1 기대를 모두 계승한다 — c1 분기는 c1·c2 둘 다, c2 만의 차이는 c2 분기.
  final c2 = phase == 'c2';
  final c1 = phase == 'c1' || c2;
  final after = phase == 'after' || c1;
  test('CP02 실행 조건', () {
    expect(phase == 'before' || phase == 'after' || phase == 'c1' || phase == 'c2', isTrue, reason: 'DU1_VQ_PHASE=before|after|c1|c2');
    if (c1 && !c2) expect((env['DU1_VQ_OUT'] ?? '').contains('followup/c1'), isTrue, reason: 'C1 산출 폴더');
    if (c2) expect((env['DU1_VQ_OUT'] ?? '').contains('followup/c2'), isTrue, reason: 'C2 산출 폴더');
    // [C2] c2 는 실제 실행일(KST)을 기대한다 — 다른 모드는 원 날짜 그대로.
    expect(env['DU1_VQ_DATE'], c2 ? _kstToday() : '2026-11-11');
    expect((env['DU1_VQ_RUN'] ?? '').isNotEmpty, isTrue);
    expect((env['DU1_VQ_OUT'] ?? '').contains('cp02-tab-bar'), isTrue);
    expect(meta.isNotEmpty, isTrue, reason: 'CP02_META');
  });
  // CP01 과 같은 온보딩·투어 완료 값
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed_u1': true,
      'onboarding_completed_sub1': true,
      'onboarding_completed_admin1': true,
      'tour_completed_user_home': true,
      'tour_completed_admin_home': true,
    });
    FirstPostingReadinessStore.reset();
    PostingQuotaStore.reset();
  });
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    await _loadFonts();
  });

  /// 사례 본문 동안 렌더 오류를 모은다. 진단문은 오류가 들어오는 순간 렌더해 둔다(CP01 r2 와 같은 조기 포착).
  Future<void> collecting(WidgetTester t, Future<void> Function(List<FlutterErrorDetails> errors) body) async {
    final errors = <FlutterErrorDetails>[];
    final prev = FlutterError.onError;
    final sem = t.ensureSemantics();
    FlutterError.onError = (d) {
      _diag[d] = TextTreeRenderer(wrapWidth: 400).render(d.toDiagnosticsNode(style: DiagnosticsTreeStyle.error));
      errors.add(d);
    };
    try {
      await body(errors);
    } finally {
      FlutterError.onError = prev;
      sem.dispose();
    }
  }

  Future<void> settle(WidgetTester t, int n) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 100));
      _pumps++;
    }
  }

  /// 사례 끝 — 트리를 내리고 남은 지연(토스트 4초 등)을 흘린다. 둘 다 계수한다.
  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    _pumps++;
    await t.pump(const Duration(seconds: 5));
    _pumps++;
  }

  Future<GlobalKey> open(WidgetTester t, {required Widget home, required UserProvider up, required ThemeData theme,
      required _V v, double inset = 0}) async {
    final key = GlobalKey();
    t.view.physicalSize = v.size;
    t.view.devicePixelRatio = 1.0;
    if (inset > 0) {
      t.view.padding = FakeViewPadding(bottom: inset);
      t.view.viewPadding = FakeViewPadding(bottom: inset);
    }
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: up),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          locale: const Locale('ko', 'KR'),
          supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (ctx, child) =>
              MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.scale)), child: child!),
          home: home,
        ),
      ),
    ));
    _mounts++;
    await settle(t, 12);
    return key;
  }

  // 두 phase 공통 읽기 — 두 탭 위젯이 같은 이름으로 가진 items/currentIndex 만 쓴다.
  Finder bar() => after
      ? find.byWidgetPredicate((w) => w.runtimeType.toString() == 'AppBottomTabBar')
      : find.byType(BottomNavigationBar);
  List<String> labels(WidgetTester t) =>
      ((t.widget(bar()) as dynamic).items as List<BottomNavigationBarItem>).map((i) => i.label ?? '').toList();
  int barIndex(WidgetTester t) => (t.widget(bar()) as dynamic).currentIndex as int;
  int stackIndex(WidgetTester t) => t.widget<IndexedStack>(find.byType(IndexedStack).first).index ?? -1;
  // [C1] 표시값에 U+2060 이 들어가므로 c1 은 바 안에서 TextLayout.plain(표시값) == 정확 라벨로 찾는다. 원 경로는 그대로.
  Finder labelText(String l) => c1
      ? find.descendant(of: bar(), matching: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? '') == l))
      : find.descendant(of: bar(), matching: find.text(l));

  /// [C1] 낱말별 줄 위치 — 표시 문자열을 공백으로 낱말로 나누고(U+2060 은 건너뜀) 글자마다 상자 윗변으로 줄 번호를 매긴다.
  ///   결과 '낱말@줄'(한 낱말이 두 줄에 걸치면 '낱말@0-1'). 줄 번호는 윗변 오름차순, 줄 높이 절반 안이면 같은 줄.
  List<String> wordLines(RenderParagraph rp, String raw, double lineH) {
    final wj = String.fromCharCode(0x2060);
    final recs = <(int, String, double)>[];
    var w = 0;
    for (var o = 0; o < raw.length; o++) {
      final ch = raw[o];
      if (ch == ' ') {
        w++;
        continue;
      }
      if (ch == wj) continue;
      final bs = rp.getBoxesForSelection(TextSelection(baseOffset: o, extentOffset: o + 1));
      recs.add((w, ch, bs.isEmpty ? double.nan : bs.first.top));
    }
    final tops = <double>[];
    for (final r in recs) {
      if (!r.$3.isNaN && !tops.any((x) => (x - r.$3).abs() < lineH / 2)) tops.add(r.$3);
    }
    tops.sort();
    int idx(double top) => top.isNaN ? -1 : tops.indexWhere((x) => (x - top).abs() < lineH / 2);
    return [
      for (var i = 0; i <= w; i++)
        '${recs.where((r) => r.$1 == i).map((r) => r.$2).join()}@'
            '${(recs.where((r) => r.$1 == i).map((r) => idx(r.$3)).toSet().toList()..sort()).join('-')}',
    ];
  }
  Finder receiverOf(String l) => find.ancestor(of: labelText(l), matching: find.byWidgetPredicate((w) => w is InkResponse)).first;

  bool centerHits(WidgetTester t, Finder f) {
    final ro = t.renderObject(f);
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, t.getRect(f).center, t.view.viewId);
    return hit.path.any((e) => identical(e.target, ro));
  }

  Future<void> tapLabel(WidgetTester t, String l) async {
    await t.tapAt(t.getRect(receiverOf(l)).center);
    _taps++;
    await settle(t, 6);
  }

  /// 탭 표시부 측정(두 phase 공통 기록·공통 라벨/위치 단언) + after 사양 단언.
  Map<String, Object?> measureBar(WidgetTester t, _V v, List<String> want, int sel, {double inset = 0}) {
    final ls = labels(t);
    final items = (t.widget(bar()) as dynamic).items as List<BottomNavigationBarItem>;
    final br = t.getRect(bar());
    final tabs = <Map<String, Object?>>[];
    for (var i = 0; i < ls.length; i++) {
      if (c1) expect(labelText(ls[i]), findsOneWidget, reason: '${v.id} ${ls[i]} 라벨이 바 안에 정확히 하나');
      final rf = receiverOf(ls[i]);
      if (c2) expect(find.descendant(of: rf, matching: find.byType(Icon)), findsOneWidget, reason: '${v.id} ${ls[i]} receiver 안 Icon 정확히 하나');
      final r = t.getRect(rf);
      // [C1 공통 정합화] 라벨 Text 안 RichText 의 RenderParagraph — semanticsLabel 이 있으면 Text 의 render object 는 의미 상자다.
      //   전 범위 길이는 표시 문자열(U+2060 포함, 의미 이름 제외). semanticsLabel 이 없는 원 경로에서는 같은 값이다.
      final rp = t.renderObject<RenderParagraph>(find.descendant(of: labelText(ls[i]), matching: find.byType(RichText)).first);
      final text = rp.text.toPlainText(includeSemanticsLabels: false);
      final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.length));
      final node = t.getSemantics(labelText(ls[i]));
      final st = rp.text.style;
      final iconF = find.descendant(of: rf, matching: find.byType(Icon));
      final icon = iconF.evaluate().isEmpty ? null : t.widget<Icon>(iconF.first);
      final iconTheme = iconF.evaluate().isEmpty ? null : IconTheme.of(t.element(iconF.first));
      final wantIcon = ((i == sel ? items[i].activeIcon : items[i].icon) as Icon).icon;
      final rec = <String, Object?>{
        'labelColor': st?.color?.toARGB32().toRadixString(16), 'labelWeight': st?.fontWeight?.value, 'labelSize': st?.fontSize,
        'labelHeight': st?.height, 'labelTracking': st?.letterSpacing,
        'iconColor': (icon?.color ?? iconTheme?.color)?.toARGB32().toRadixString(16), 'iconSize': icon?.size ?? iconTheme?.size,
        'iconIsActivePair': icon?.icon == wantIcon,
        'label': ls[i], 'rect': [r.left, r.top, r.width, r.height], 'hit': centerHits(t, rf),
        'inScreen': r.left >= -0.01 && r.top >= -0.01 && r.right <= v.size.width + 0.01 && r.bottom <= v.size.height + 0.01,
        'text': text, 'maxLines': rp.maxLines, 'exceeded': rp.didExceedMaxLines, 'overflow': rp.overflow.name,
        'textScale': rp.textScaler.scale(12) / 12, 'lines': boxes.map((b) => b.top.round()).toSet().length,
        'paraH': rp.size.height,
        'semSelected': containsSemantics(isSelected: true).matches(node, <dynamic, dynamic>{}),
        'semButton': containsSemantics(isButton: true).matches(node, <dynamic, dynamic>{}),
        'semLabel': node.label,
      };
      if (c1) {
        // [C1] 글자 상자(전 범위)를 화면 좌표로 — receiver 안 포함·이웃 간격 확인용.
        Rect? ink;
        for (final b in boxes) {
          final r0 = Rect.fromPoints(rp.localToGlobal(Offset(b.left, b.top)), rp.localToGlobal(Offset(b.right, b.bottom)));
          ink = ink == null ? r0 : ink.expandToInclude(r0);
        }
        final pad = t.widget<Padding>(find.descendant(of: rf, matching: find.byType(Padding)).first).padding.resolve(TextDirection.ltr);
        final recvNode = t.getSemantics(rf);
        rec.addAll({
          'raw': text,
          'rawCodes': text.runes.map((r) => r.toRadixString(16)).join(' '),
          'plain': TextLayout.plain(text),
          'wordLines': wordLines(rp, text, 12 * v.scale * 1.2),
          'ink': ink == null ? null : [ink.left, ink.top, ink.right, ink.bottom],
          'pad': [pad.left, pad.top, pad.right, pad.bottom],
          'recvSemSame': recvNode.id == node.id,
          'recvSemLabel': recvNode.label,
        });
      }
      if (c2) {
        // [C2] 아이콘 24 레이아웃 상자(Icon 의 SizedBox)와 라벨 문단 윗변 — 화면 좌표. 글리프 잉크가 아니다.
        final ib = t.getRect(find.descendant(of: rf, matching: find.byType(Icon)).first);
        rec.addAll({
          'iconBox': [ib.left, ib.top, ib.width, ib.height],
          'paraTop': rp.localToGlobal(Offset.zero).dy,
        });
      }
      tabs.add(rec);
    }
    double? rowH;
    double? lineW;
    String? lineColor;
    if (after) {
      final row = find.descendant(of: bar(), matching: find.byType(Row)).first;
      rowH = t.getSize(row).height;
      // 위 선 = 탭 위젯 안에서 테두리를 가진 첫 BoxDecoration
      final deco = t.widget<DecoratedBox>(find.descendant(of: bar(), matching: find.byWidgetPredicate(
          (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null)).first).decoration;
      final top = (deco as BoxDecoration).border!.top;
      lineW = top.width;
      lineColor = top.color.toARGB32().toRadixString(16);
    }
    final m = <String, Object?>{
      'labels': ls, 'barIndex': barIndex(t), 'stackIndex': stackIndex(t), 'bar': [br.left, br.top, br.width, br.height],
      'barBottom': br.bottom, 'rowH': rowH, 'lineW': lineW, 'lineColor': lineColor, 'inset': inset, 'tabs': tabs,
    };
    // 단언 전에 원측정을 먼저 남긴다(실패해도 값이 보이게)
    // ignore: avoid_print
    print('CP02-MEASURE-PRE ${v.id} ${jsonEncode(m)}');
    expect(ls, want, reason: '${v.id} 라벨·순서·개수');
    expect(barIndex(t), sel, reason: '${v.id} 현재 보이는 위치');
    if (after) {
      expect(br.bottom, closeTo(v.size.height, 0.01), reason: '${v.id} 탭이 화면 바닥');
      expect(lineW, closeTo(1.0, 0.0001), reason: '${v.id} 위 선 1 physical px(DPR1)');
      expect(lineColor, AppColors.conceptTabLine.toARGB32().toRadixString(16), reason: '${v.id} 위 선 색 conceptTabLine');
      expect(rowH!, greaterThanOrEqualTo(56), reason: '${v.id} 내용 높이 ≥56');
      expect(br.height, closeTo(1.0 + rowH + inset, 0.01), reason: '${v.id} 높이 = 선 + 내용 + inset(1회)');
      for (var i = 0; i < tabs.length; i++) {
        final x = tabs[i];
        final rr = x['rect'] as List;
        expect(rr[2] as double, greaterThanOrEqualTo(48), reason: '${v.id} ${x['label']} 폭 ≥48');
        expect(rr[3] as double, greaterThanOrEqualTo(48), reason: '${v.id} ${x['label']} 높이 ≥48');
        expect(x['inScreen'], isTrue, reason: '${v.id} ${x['label']} 화면 안');
        expect(x['hit'], isTrue, reason: '${v.id} ${x['label']} 중심 hit');
        expect(c1 ? x['plain'] : x['text'], x['label'], reason: '${v.id} 라벨 전문');
        expect(x['maxLines'], isNull, reason: '${v.id} 라벨 줄 제한 없음');
        expect(x['exceeded'], isFalse, reason: '${v.id} 라벨 줄 초과 없음');
        expect(x['overflow'], 'clip', reason: '${v.id} 라벨 말줄임 없음(기본 clip, 줄 제한 없음)');
        expect(x['textScale'], closeTo(v.scale, 0.0001), reason: '${v.id} 라벨 실제 글자 배율(clamp 없음)');
        expect(x['semButton'], isTrue, reason: '${v.id} ${x['label']} 버튼 의미');
        expect(x['semSelected'], i == sel, reason: '${v.id} ${x['label']} 선택 의미');
        expect(x['semLabel'], x['label'], reason: '${v.id} ${x['label']} 의미 이름 = 라벨 1개(아이콘 중복 없음)');
        final s = i == sel;
        String hex(Color c) => c.toARGB32().toRadixString(16);
        expect(x['labelColor'], hex(s ? AppColors.brandDark : (c1 ? AppColors.textPrimary : AppColors.textTertiary)), reason: '${v.id} ${x['label']} 라벨 색');
        expect(x['labelWeight'], s ? 700 : 500, reason: '${v.id} ${x['label']} 라벨 굵기');
        expect(x['labelSize'], 12, reason: '${v.id} 라벨 12(배율은 TextScaler)');
        expect(x['labelHeight'], 1.2, reason: '${v.id} 라벨 줄높이 1.2');
        expect(x['labelTracking'], 0, reason: '${v.id} 라벨 자간 0');
        expect(x['iconColor'], hex(s ? AppColors.brand : (c1 ? AppColors.textPrimary : AppColors.grey600)), reason: '${v.id} ${x['label']} 아이콘 색');
        expect(x['iconSize'], 24, reason: '${v.id} 아이콘 24(배율 미적용)');
        expect(x['iconIsActivePair'], isTrue, reason: '${v.id} ${x['label']} 선택=activeIcon/비선택=icon');
      }
      if (c1) {
        // [C1] 자연 높이: 행 = max(56, 위6 + 아이콘24 + 4 + 가장 높은 라벨 + 아래6). 고정 69 아님.
        final maxParaH = tabs.map((x) => x['paraH'] as double).reduce((a, b) => math.max(a, b));
        expect(rowH, closeTo(math.max(56.0, 40 + maxParaH), 0.01), reason: '${v.id} 행 높이 = 가장 높은 탭의 자연 높이');
        // [C1] 낱말별 줄 위치 목표: W 는 모두 한 줄, B 지원자 홈·일자리 한 줄 + 내/일정·내/정보, B 관리자 5라벨 한 줄.
        const workerB = {'홈': ['홈@0'], '일자리': ['일자리@0'], '내 일정': ['내@0', '일정@1'], '내 정보': ['내@0', '정보@1']};
        final isWorker = want.contains('내 정보');
        for (var i = 0; i < tabs.length; i++) {
          final x = tabs[i];
          final label = x['label'] as String;
          final rr = (x['rect'] as List).cast<double>();
          final ink = (x['ink'] as List).cast<double>();
          expect(x['raw'], TextLayout.keepWords(label), reason: '${v.id} $label 표시값 = keepWords(원문)');
          expect(x['recvSemSame'], isTrue, reason: '${v.id} $label 라벨과 receiver 가 같은 의미 노드');
          expect(x['recvSemLabel'], label, reason: '${v.id} $label receiver 의미 이름 = 원문');
          expect(x['pad'], [6.0, 6.0, 6.0, 6.0], reason: '${v.id} $label padding 상하6·좌우6');
          expect(rr[3], closeTo(rowH, 0.01), reason: '${v.id} $label 탭 높이 = 행 높이');
          expect(ink[0] >= rr[0] + 6 - 0.01 && ink[2] <= rr[0] + rr[2] - 6 + 0.01, isTrue,
              reason: '${v.id} $label 글자 상자 가로가 receiver 안쪽(좌우 6) $ink / $rr');
          expect(ink[1] >= rr[1] - 0.01 && ink[3] <= rr[1] + rr[3] + 0.01, isTrue,
              reason: '${v.id} $label 글자 상자 세로가 receiver 안 $ink / $rr');
          expect(ink[0] >= -0.01 && ink[2] <= v.size.width + 0.01 && ink[1] >= -0.01 && ink[3] <= v.size.height + 0.01, isTrue,
              reason: '${v.id} $label 글자 상자 화면 안');
          if (i > 0) {
            final prev = (tabs[i - 1]['ink'] as List).cast<double>();
            expect(ink[0] - prev[2], greaterThanOrEqualTo(12 - 0.01), reason: '${v.id} $label 이웃 라벨 간격 ≥ 2×6');
          }
          final wantWords = (v.id == 'B' && isWorker) ? workerB[label] : [for (final w in label.split(' ')) '$w@0'];
          expect(x['wordLines'], wantWords, reason: '${v.id} $label 낱말별 줄 위치');
        }
      }
      if (c2) {
        // [C2] 아이콘 줄: 24×24 상자 top = receiver top + 6, 같은 행 편차 ≤0.01, 라벨 top = 아이콘 bottom + 4.
        final iconTops = <double>[];
        for (final x in tabs) {
          final label = x['label'] as String;
          final rr = (x['rect'] as List).cast<double>();
          final ib = (x['iconBox'] as List).cast<double>();
          expect(ib[2], closeTo(24, 0.01), reason: '${v.id} $label 아이콘 상자 폭 24');
          expect(ib[3], closeTo(24, 0.01), reason: '${v.id} $label 아이콘 상자 높이 24');
          expect(ib[1], closeTo(rr[1] + 6, 0.01), reason: '${v.id} $label 아이콘 top = receiver top + 6');
          expect(x['paraTop'] as double, closeTo(ib[1] + ib[3] + 4, 0.01), reason: '${v.id} $label 라벨 top = 아이콘 bottom + 4');
          iconTops.add(ib[1]);
        }
        final spread = iconTops.reduce((a, b) => math.max(a, b)) - iconTops.reduce((a, b) => math.min(a, b));
        expect(spread, lessThanOrEqualTo(0.01), reason: '${v.id} 같은 행 아이콘 top 편차 $iconTops');
      }
    }
    return m;
  }

  /// 셸·탭 표시부가 만든 오류는 after 에서 0이어야 한다. 탭 본문(채널 차단 환경)의 오류는 기록만 한다(실행 전 고정 규칙).
  void judgeErrors(String id, List<FlutterErrorDetails> errs) {
    final shell = <String>[];
    final body = <String>[];
    for (final e in errs) {
      final s = _diag[e] ?? e.toString();
      final first = e.exceptionAsString().split(String.fromCharCode(10)).first;
      final at = RegExp(r'[A-Za-z_]+[.]dart:[0-9]+:[0-9]+').allMatches(s).map((x) => x.group(0)).toSet().join(',');
      (_shellFiles.any(s.contains) ? shell : body).add('$first @ $at');
    }
    // ignore: avoid_print
    print('CP02-ERRORS $id ${jsonEncode({'shell': shell, 'body': body})}');
    if (after) expect(shell, isEmpty, reason: '$id 셸·탭 표시부 오류 0');
  }

  Future<void> shot(WidgetTester t, GlobalKey key, String id, _V v, String fixture) async {
    await vqCapture(t, key, id, conditions: {
      'id': id, 'phase': phase, 'fixture': fixture, 'viewport': '${v.size.width.toInt()}x${v.size.height.toInt()}', 'dpr': 1.0,
      'textScaler': v.scale, 'locale': 'ko_KR', 'inset': t.view.padding.bottom, 'date': env['DU1_VQ_DATE'],
      'run': env['DU1_VQ_RUN'], 'meta': meta,
      'fonts': 'NotoSansKR Regular+Bold(Roboto 별칭) · FlutterTest=Regular · MaterialIcons(SDK)',
      'body': '탭 본문은 채널 차단 상태(실제 데이터 아님) — 판정 대상은 하단 탭',
    });
    if (vqEnabled) _pngs++;
  }

  void log(String id, Map<String, Object?> m) {
    // ignore: avoid_print
    print('CP02-MEASURE $id ${jsonEncode(m)}');
  }

  // 현재 탭의 Navigator — IndexedStack 은 선택된 자식만 onstage 로 방문한다(_IndexedStackElement).
  NavigatorState currentTabNavigator(WidgetTester t) =>
      t.state<NavigatorState>(find.descendant(of: find.byType(IndexedStack).first, matching: find.byType(Navigator)).first);

  Future<void> pushInTab(WidgetTester t, String marker) async {
    unawaited(currentTabNavigator(t).push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text(marker)))));
    await settle(t, 6);
    expect(find.text(marker), findsOneWidget, reason: '탭 안 화면 올라감 $marker');
  }

  Future<void> systemBack(WidgetTester t) async {
    await t.binding.handlePopRoute();
    await settle(t, 6);
  }

  final workerLabels = after ? const ['홈', '일자리', '내 일정', '내 정보'] : const ['홈', '일자리', '일정', 'MY'];
  const adminAll = ['홈', '공고', '근무', '급여', '관리'];

  for (final v in const [_w, _b]) {
    // ① 지원자 4탭 — 전 탭 전환·재탭 root·back·배너 on/off·하단 inset 34 · PNG
    testWidgets('CP02 ① 지원자 4탭 ${v.id}', (t) async {
      _cases.add('worker-${v.id}');
      _stubChannels(t);
      await collecting(t, (errs) async {
        final up = _Worker(pending: true);
        final key = await open(t, home: const UserRootScreen(), up: up, theme: RoleTheme.workerTheme, v: v, inset: _inset);
        if (c1) await shot(t, key, 'CP02-worker-${v.id}', v, '${c2 ? 'C2' : 'C1'} worker 4 tabs · pending contract banner on · bottom inset 34');
        final m0 = measureBar(t, v, workerLabels, 0, inset: _inset);
        // 셸 배너만(탭 안 화면 배너는 useSafeArea:true 이고 UserTabScope 안에서 스스로 숨는다)
        final pb = t.getRect(find.byWidgetPredicate((w) => w is PendingContractBar && !w.useSafeArea));
        m0['banner'] = [pb.top, pb.bottom];
        m0['bannerVisible'] = find.text('계약서 서명이 필요해요').evaluate().isNotEmpty;
        m0['bannerAboveBar'] = (pb.bottom - (m0['bar'] as List)[1]).abs() < 0.01;
        expect(m0['bannerVisible'], isTrue, reason: '${v.id} 배너 on');
        expect(m0['bannerAboveBar'], isTrue, reason: '${v.id} 계약 배너가 탭 바로 위');
        log('worker-${v.id}-open', m0);
        if (!c1) await shot(t, key, 'CP02-worker-${v.id}', v, 'worker 4 tabs · pending contract banner on · bottom inset 34');
        for (var i = 1; i < 4; i++) {
          await tapLabel(t, workerLabels[i]);
          expect(stackIndex(t), i, reason: '${v.id} ${workerLabels[i]} → 실제 탭 $i');
          expect(barIndex(t), i);
        }
        await tapLabel(t, workerLabels[0]);
        expect(stackIndex(t), 0);
        // 재탭 root: 홈 탭 안에 화면을 올린 뒤 같은 탭을 다시 누른다
        await pushInTab(t, 'CP02-PUSHED');
        await tapLabel(t, workerLabels[0]);
        expect(find.text('CP02-PUSHED'), findsNothing, reason: '${v.id} 재탭 → 탭 첫 화면');
        expect(stackIndex(t), 0);
        // back: 일자리 탭 안 화면 → 시스템 뒤로 → 탭 안에서만 닫힘
        await tapLabel(t, workerLabels[1]);
        await pushInTab(t, 'CP02-BACK');
        await systemBack(t);
        expect(find.text('CP02-BACK'), findsNothing, reason: '${v.id} back → 탭 안 화면 닫힘');
        expect(stackIndex(t), 1, reason: '${v.id} back 뒤에도 일자리 탭');
        // 배너 off
        up.setPending(false);
        await settle(t, 3);
        final m1 = measureBar(t, v, workerLabels, 1, inset: _inset);
        m1['bannerVisible'] = find.text('계약서 서명이 필요해요').evaluate().isNotEmpty;
        expect(m1['bannerVisible'], isFalse, reason: '${v.id} 배너 off');
        log('worker-${v.id}-end', m1);
        await close(t);
        judgeErrors('worker-${v.id}', errs);
      });
    });

    // ② 전체 관리자 5탭 — 전 탭 전환(지연 mount)·재탭 root·back·전환기 · PNG
    testWidgets('CP02 ② 전체 관리자 5탭 ${v.id}', (t) async {
      _cases.add('admin-${v.id}');
      _stubChannels(t);
      await collecting(t, (errs) async {
        final up = _Admin(owner: true, mode: _Mode.full);
        final key = await open(t, home: const BusinessAdminShell(), up: up, theme: RoleTheme.businessAdminTheme, v: v);
        if (c1) await shot(t, key, 'CP02-admin-${v.id}', v, '${c2 ? 'C2' : 'C1'} owner all 5 tabs');
        log('admin-${v.id}-open', measureBar(t, v, adminAll, 0));
        if (!c1) await shot(t, key, 'CP02-admin-${v.id}', v, 'owner all 5 tabs');
        for (var i = 1; i < 5; i++) {
          await tapLabel(t, adminAll[i]);
          expect(stackIndex(t), i, reason: '${v.id} ${adminAll[i]} → 실제 탭 $i');
          expect(barIndex(t), i);
        }
        await pushInTab(t, 'CP02-PUSHED');
        await tapLabel(t, adminAll[4]);
        expect(find.text('CP02-PUSHED'), findsNothing, reason: '${v.id} 관리 재탭 → 첫 화면');
        await pushInTab(t, 'CP02-BACK');
        await systemBack(t);
        expect(find.text('CP02-BACK'), findsNothing, reason: '${v.id} back → 탭 안 화면 닫힘');
        expect(stackIndex(t), 4);
        expect(AdminTabSwitcher.instance.switchToTab(0), isTrue, reason: '${v.id} 전환기 → 홈');
        await settle(t, 6);
        expect(stackIndex(t), 0);
        log('admin-${v.id}-end', measureBar(t, v, adminAll, 0));
        await close(t);
        judgeErrors('admin-${v.id}', errs);
      });
    });

    // ③ 제한 SubAdmin — 근무만: 보이는 홈·근무·관리 = 실제 0·2·4, 숨긴 탭 진입 거부 · PNG
    testWidgets('CP02 ③ 제한 SubAdmin 비연속 ${v.id}', (t) async {
      _cases.add('restricted-${v.id}');
      _stubChannels(t);
      await collecting(t, (errs) async {
        final up = _Admin(owner: false, mode: _Mode.restricted, perms: const MemberPermissions(canManageWorkers: true));
        final key = await open(t, home: const BusinessAdminShell(), up: up, theme: RoleTheme.businessAdminTheme, v: v);
        const vis = ['홈', '근무', '관리'];
        log('restricted-${v.id}-open', measureBar(t, v, vis, 0));
        await shot(t, key, 'CP02-restricted-${v.id}', v, 'SubAdmin canManageWorkers only (visible actual 0,2,4)');
        await tapLabel(t, '관리');
        expect(barIndex(t), 2, reason: '${v.id} 보이는 위치 2');
        expect(stackIndex(t), 4, reason: '${v.id} 실제 탭 4');
        await tapLabel(t, '근무');
        expect(barIndex(t), 1);
        expect(stackIndex(t), 2, reason: '${v.id} 보이는 1 → 실제 2');
        expect(AdminTabSwitcher.instance.switchToTab(1), isFalse, reason: '${v.id} 숨긴 공고 진입 거부');
        expect(AdminTabSwitcher.instance.switchToTab(3), isFalse, reason: '${v.id} 숨긴 급여 진입 거부');
        await settle(t, 2);
        expect(stackIndex(t), 2, reason: '${v.id} 거부 뒤 그대로');
        log('restricted-${v.id}-end', measureBar(t, v, vis, 1));
        await close(t);
        judgeErrors('restricted-${v.id}', errs);
      });
    }, skip: c1); // [C1] 원 TA 승계(셸·매핑 미변경)

    // ④ 권한 미확인 — 근무·급여 유지(hidesAffordance=denied 만), 공고 숨김(canManagePostingAnywhere → can=false) · PNG
    testWidgets('CP02 ④ 권한 미확인 ${v.id}', (t) async {
      _cases.add('unknown-${v.id}');
      _stubChannels(t);
      await collecting(t, (errs) async {
        final up = _Admin(owner: false, mode: _Mode.unknown);
        final key = await open(t, home: const BusinessAdminShell(), up: up, theme: RoleTheme.businessAdminTheme, v: v);
        const vis = ['홈', '근무', '급여', '관리'];
        log('unknown-${v.id}-open', measureBar(t, v, vis, 0));
        await shot(t, key, 'CP02-unknown-${v.id}', v, 'SubAdmin permissions unknown (visible actual 0,2,3,4)');
        const actual = [0, 2, 3, 4];
        for (var i = 1; i < vis.length; i++) {
          await tapLabel(t, vis[i]);
          expect(barIndex(t), i);
          expect(stackIndex(t), actual[i], reason: '${v.id} ${vis[i]} → 실제 ${actual[i]}');
        }
        expect(AdminTabSwitcher.instance.switchToTab(1), isFalse, reason: '${v.id} 미확인 중 공고 진입 거부');
        await tapLabel(t, vis[0]);
        expect(stackIndex(t), 0);
        log('unknown-${v.id}-end', measureBar(t, v, vis, 0));
        await close(t);
        judgeErrors('unknown-${v.id}', errs);
      });
    }, skip: c1); // [C1] 원 TA 승계(셸·매핑 미변경)

    // ⑤ 현재 탭 권한 회수 → 홈 (raw 단언만, PNG 없음)
    testWidgets('CP02 ⑤ 현재 탭 권한 회수 ${v.id}', (t) async {
      _cases.add('revoke-${v.id}');
      _stubChannels(t);
      await collecting(t, (errs) async {
        final up = _Admin(owner: false, mode: _Mode.full);
        await open(t, home: const BusinessAdminShell(), up: up, theme: RoleTheme.businessAdminTheme, v: v);
        expect(labels(t), adminAll, reason: '${v.id} 전 권한 SubAdmin 5탭');
        await tapLabel(t, '근무');
        expect(stackIndex(t), 2);
        expect(barIndex(t), 2);
        up.revokeWorkers();
        await settle(t, 3);
        const vis = ['홈', '공고', '급여', '관리'];
        expect(stackIndex(t), 0, reason: '${v.id} 회수 → 홈');
        log('revoke-${v.id}-end', measureBar(t, v, vis, 0));
        await close(t);
        judgeErrors('revoke-${v.id}', errs);
      });
    }, skip: c1); // [C1] 원 TA 승계(셸·매핑 미변경)
  }

  tearDownAll(() {
    final writes = _fsWrites.map((o) => _calls['fs.$o'] ?? 0).fold<int>(0, (a, b) => a + b);
    // ignore: avoid_print
    print('CP02-FINAL phase=$phase cases=${_cases.length} mounts=$_mounts pumps=$_pumps pumpPlusMount=${_pumps + _mounts} '
        'taps=$_taps drags=$_drags pngPairs=$_pngs fsWrites=$writes calls=${jsonEncode(_calls)}');
    expect(writes, 0, reason: 'Firestore 쓰기 시도 0');
    // [C1] c1 상한: 사례 4·tap 32·pump+mount 400·PNG 4(URN 과 합산한 총량은 보고서에서 대조)
    expect(_cases.length, lessThanOrEqualTo(c1 ? 4 : 10));
    // [C2] c2 상한: 사례 4·tap 24·pump+mount 300·PNG 4
    expect(_taps, lessThanOrEqualTo(c2 ? 24 : (c1 ? 32 : 64)));
    expect(_pumps + _mounts, lessThanOrEqualTo(c2 ? 300 : (c1 ? 400 : 700)));
    expect(_pngs, lessThanOrEqualTo(c1 ? 4 : 8));
  });
}
