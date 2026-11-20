// [S014 띠 색 · DU416 · 판정51] S014 사업장 목록 운영 종료 결과 띠 — 진한 의미색 면 + 흰 글 → 옅은 의미 바탕 + 진한 글 · 아이콘.
//   새 파일 · 정확 6 public(W 392x844@1.0 · B 320x640@2.0 × ARCHOK · ARCHFAIL · ARCHLOOP) · 캡처 1 단계(2result × 3 상태 × W/B = 6쌍).
//   하네스 · ① 결과 첫 frame 측정은 du1_s014_band_h3_test(7fb79439)에서 그대로 가져왔다(fake core · 4곳 · 사전 조회 · debugPreview/debugArchive seam · writer 0).
//   모드: DU_BEFORE_OBSERVE=416 이면 before(현행 7a77990a 진한 띠 관측), 아니면 strict(옅은 띠). ① 결과 계약은 두 모드 같은 값(H-3 수용 동작).
//   색 줄: face(면 dark/light) · ink(글 RenderParagraph 색 white/dark) · icon(white/dark) · cr(글/면 대비, WCAG 상대 휘도).
//   ②–⑦(수명 · 전문 · 교체 · 교차 · 재조회 · 이탈)은 이 시험에 없다 — H-3 추종 시험이 회귀로 돈다.
//   출력 줄: lkit 선언형 계약 'D416 <tok> <kind> [<sub>] k=v …' — 값 공백 0.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_list_reads.dart';
import 'package:ALfit/screens/business_admin/business_list_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options =>
      const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p', storageBucket: 'p.appspot.com');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _Provider extends UserProvider {
  _Provider({required this.ids});

  final List<String> ids;

  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김사장',
        email: 'u1@alfit.local',
        role: UserRole.BUSINESS_ADMIN,
        managedBusinessIds: ids,
        subAdminBusinessIds: const [],
      );
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => true;
  @override
  String? get effectiveBusinessId => null;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
}

BusinessModel _biz(String id, String name,
        {bool approved = true,
        String address = '서울특별시 강남구 테헤란로 152',
        double? rating,
        bool parking = false,
        List<String>? meals,
        bool closed = false}) =>
    BusinessModel(
      id: id,
      businessNumber: '000-00-00000',
      name: name,
      category: '물류',
      subCategory: '창고',
      address: address,
      ownerId: 'u1',
      isApproved: approved,
      createdAt: DateTime(2026, 10, 1),
      rating: rating,
      parkingAvailable: parking,
      mealsProvided: meals,
      deactivatedAt: closed ? DateTime(2026, 11, 1) : null,
      archivedAt: closed ? DateTime(2026, 11, 1) : null,
    );

// 396 · 400 · 410 과 같은 4곳
final _four = [
  _biz('b1', '강남 물류센터', rating: 4.6, parking: true, meals: const ['중식']),
  _biz('b2', '송파 신선 분류센터', approved: false),
  _biz('b3', '성수 소형 창고', closed: true),
  _biz('b4', '[QA] 아주 긴 이름의 강남 물류센터 평택 제2공장 냉장 분류동',
      address: '경기도 평택시 포승읍 평택항로 268번길 45-12 물류단지 B동 3층', rating: 3.9, parking: true),
];

// 400 · 410 과 같은 사전 조회(차단 0 · truncated false)
const _preview = <String, dynamic>{
  'inProgressShifts': 0,
  'ongoingLongTerm': 0,
  'contractPendingWorked': 0,
  'openPostings': 2,
  'pendingApplications': 3,
  'invites': 1,
  'futureConfirmed': 4,
  'contractsVoided': 2,
  'keptStarted': 5,
  'contractsKept': 1,
  'unpaidWages': 6,
  'workedUncalculated': 7,
  'interimPending': 1,
  'interimApproved': 2,
  'truncated': false,
};

// 독립 기대 문장(제품에서 가져오지 않는다)
const _okNew = '사업장 운영을 종료했어요';
const _failNew = '사업장 운영을 종료하지 못했어요';
const _loopNew = '정리 대상이 계속 바뀌고 있어요. 잠시 후 다시 시도해 주세요';
const _changedTitle = '정리 대상이 바뀌었어요';

class _Reads {
  var calls = 0;
  // [⑥] 읽기 보류 — 실제 Loading frame 을 만든다(ARCHOK 재조회 구간만)
  Completer<void>? gate;

  BusinessListReads get reads => BusinessListReads(
        businessById: (_) async {
          calls++;
          final g = gate;
          if (g != null) await g.future;
          return _four.first;
        },
        businessesByIds: (_) async {
          calls++;
          final g = gate;
          if (g != null) await g.future;
          return _four;
        },
      );
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '416';
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _vt(Widget w) => w is Text ? visibleText(w.data ?? w.textSpan?.toPlainText() ?? '') : '';
Finder _vis(String text) => find.byWidgetPredicate((w) => w is Text && _vt(w) == text, skipOffstage: false);
Finder _el(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);

Element? _ancestor(Element e, bool Function(Widget w) p) {
  Element? out;
  e.visitAncestorElements((a) {
    if (p(a.widget)) {
      out = a;
      return false;
    }
    return true;
  });
  return out;
}

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

bool _hit(Rect a, Rect? b) {
  if (b == null) return false;
  final i = a.intersect(b);
  return i.width > 0.5 && i.height > 0.5;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    const codec = StandardMessageCodec();
    for (final m in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
          'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$m',
          (_) async => codec.encodeMessage(<Object?>['du416.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du416.fake.$m'), (_) async => null);
    }
  });

  const views = [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const states = [
    (key: 'ARCHOK', title: '운영 종료 성공 띠 — 옅은 successBg 면 · successDark 글 아이콘'),
    (key: 'ARCHFAIL', title: '운영 종료 실패 띠 — 옅은 errorBg 면 · errorDark 글 아이콘'),
    (key: 'ARCHLOOP', title: '정리 대상 계속 바뀜 띠 — 옅은 errorBg 면 · errorDark 글 아이콘 · 긴 문장'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S014C-${v.id}-${st.key} ${st.title}', (t) async {
        final tok = 'S014C-${v.id}-${st.key}';
        final mode = _before ? 'before' : 'strict';
        _out('D416 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
        final overflows = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            overflows.add(m.split('\n').first);
          } else {
            prev?.call(d);
          }
        };
        addTearDown(() => FlutterError.onError = prev);
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final screen = Offset.zero & Size(v.w, v.h);
        bool inR(Rect o, Rect r) => r.top >= o.top - 0.5 && r.bottom <= o.bottom + 0.5 && r.left >= o.left - 0.5 && r.right <= o.right + 0.5;
        void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        Future<void> settle([int n = 10]) async {
          for (var i = 0; i < n; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
        }

        DateTime now() => t.binding.clock.now();

        var captures = 0;
        final key = GlobalKey();
        final cond = {'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': st.key};
        Future<void> shot(String id, String stage) async {
          await vqCapture(t, key, '${tok}_$id', conditions: {...cond, 'state': stage});
          captures++;
        }

        final resText = st.key == 'ARCHOK' ? _okNew : (st.key == 'ARCHFAIL' ? _failNew : _loopNew);
        final scr = find.byType(BusinessListScreen);
        List<Element> inside(String s) =>
            find.descendant(of: scr, matching: find.byWidgetPredicate((w) => w is Text && _vt(w) == s, skipOffstage: false), skipOffstage: false).evaluate().toList();
        List<Element> overlayEls(String s) {
          final ins = inside(s).toSet();
          return [for (final e in _vis(s).evaluate()) if (!ins.contains(e)) e];
        }

        int overlayN(String s) => overlayEls(s).length;
        int resN() => inside(resText).length + overlayN(resText);
        Rect? toastFace() {
          final o = overlayEls(resText);
          if (o.isEmpty) return null;
          final box = _ancestor(o.first, (w) => w is IgnorePointer);
          return box == null ? null : t.getRect(_el(box));
        }

        // 띠 면 — 두 모드 모두 찾는다(before 진한 successDark/errorDark · strict 옅은 successBg/errorBg). 글 rect 가 아니라 면 기준
        const faces = [AppColors.errorDark, AppColors.successDark, AppColors.errorBg, AppColors.successBg];
        Element? bandBox() {
          final b = inside(resText);
          if (b.length != 1) return null;
          return _ancestor(b.single, (w) => w is Container && w.decoration is BoxDecoration && faces.contains((w.decoration as BoxDecoration).color));
        }

        Rect? bandFace() {
          final box = bandBox();
          return box == null ? null : t.getRect(_el(box));
        }

        int semExact() => find.semantics.byPredicate((n) => n.label == resText).evaluate().length;
        int semAny() => find.semantics.byPredicate((n) => n.label.contains(resText)).evaluate().length;
        int semLive() => find.semantics.byPredicate((n) => n.label.contains(resText) && n.flagsCollection.isLiveRegion).evaluate().length;

        Rect bodyBox() {
          final ab = find.descendant(of: scr, matching: find.byType(AppBar));
          final top = ab.evaluate().isEmpty ? 0.0 : t.getRect(ab.first).bottom;
          return Rect.fromLTRB(0, top, v.w, v.h);
        }

        Rect clipOf(Element e) {
          final sc = _ancestor(e, (w) => w is Scrollable);
          if (sc != null) return t.getRect(_el(sc));
          if (_ancestor(e, (w) => w is BusinessListScreen) != null) return bodyBox();
          return screen;
        }

        Element nameEl(BusinessModel b) => inside(b.name).single;
        Element cardEl(BusinessModel b) => _ancestor(nameEl(b), (w) => w is InkWell)!;

        final r = _Reads();
        final previewCalls = <String>[];
        final archived = <String>[];
        BusinessListScreen.debugPreview = (id) async {
          previewCalls.add(id);
          return Map<String, dynamic>.from(_preview);
        };
        BusinessListScreen.debugArchive = (id, expected) async {
          archived.add(id);
          if (st.key == 'ARCHFAIL') throw StateError('DU414 fake 운영 종료 실패');
          if (st.key == 'ARCHLOOP') {
            throw FirebaseFunctionsException(
                code: 'failed-precondition',
                message: 'DU414 fake 정리 대상 바뀜',
                details: <String, dynamic>{'code': 'ARCHIVE_PREVIEW_CHANGED', 'preview': Map<String, dynamic>.from(_preview)});
          }
        };
        addTearDown(() {
          BusinessListScreen.debugPreview = null;
          BusinessListScreen.debugArchive = null;
        });

        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>(create: (_) => _Provider(ids: [for (final b in _four) b.id])),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
            ],
            child: MaterialApp(
              navigatorKey: navigatorKey,
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.businessAdminTheme,
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: const Scaffold(body: SizedBox.expand()),
            ),
          ),
        ));
        await settle(4);
        unawaited(navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => BusinessListScreen(reads: r.reads))));
        await settle(16);

        // 카드가 아직 만들어지지 않았으면(B 의 화면 밖 · cache 밖) 목록을 끌어 도달시킨다 — 첫 카드는 위로, 나머지는 아래로
        Future<void> reach(BusinessModel b) async {
          var n = 0;
          while (inside(b.name).isEmpty && n < 20) {
            final sc = find.descendant(of: find.descendant(of: scr, matching: find.byType(ListView)), matching: find.byType(Scrollable)).first;
            await t.drag(sc, Offset(0, b.id == 'b1' ? 300 : -300));
            await settle(6);
            n++;
          }
          must('${b.id} 카드 도달', inside(b.name).length == 1, '$n');
        }

        // 더보기 → 시트 '운영 종료' → 사전 조회 → 확인창(열린 채로 돌아온다). 더보기가 이미 보이면 스크롤하지 않는다(이동 0 유지).
        Future<void> openConfirm(BusinessModel b) async {
          await reach(b);
          // [수리 2/3] 스크롤로 카드가 viewport 밖에 걸치면 기본 finder 는 더보기를 건너뛴다 — 화면 밖 포함으로 찾고 아래 분기에서 ensureVisible
          Finder more() => find.descendant(of: _el(cardEl(b)), matching: find.byType(IconButton, skipOffstage: false), skipOffstage: false);
          must('${b.id} 카드 귀속 더보기 1', more().evaluate().length == 1, '${more().evaluate().length}');
          final m0 = t.getRect(more());
          if (!(inR(clipOf(more().evaluate().single), m0) && inR(screen, m0))) {
            await t.ensureVisible(_el(cardEl(b)));
            await settle(6);
          }
          await t.tapAt(t.getRect(more()).center);
          await settle(12);
          final sheet = find.byType(BottomSheet);
          must('더보기 → 시트 1', sheet.evaluate().length == 1);
          final endItem = find.descendant(of: sheet, matching: findVisibleText('운영 종료'));
          must('시트 운영 종료 1', endItem.evaluate().length == 1);
          await t.tapAt(t.getRect(endItem).center);
          await settle(16);
          must('확인창 1', find.byType(Dialog).evaluate().length == 1);
        }

        Future<void> tapOk() async {
          final okText = find.descendant(of: find.byType(Dialog), matching: findVisibleText('운영 종료'));
          must('확인창 운영 종료 버튼 1', okText.evaluate().length == 1, '${okText.evaluate().length}');
          final okInk = find.ancestor(of: okText, matching: find.byType(InkWell)).first;
          await t.tapAt(t.getRect(okInk).center);
        }

        // 16ms 단계로 결과가 보이는 첫 frame 까지 — 최소 1단계(교체면 첫 단계에서 새 결과가 생긴다)
        Future<({DateTime at, int steps})> waitResult() async {
          var steps = 0;
          do {
            await t.pump(const Duration(milliseconds: 16));
            steps++;
          } while (resN() == 0 && steps < 60);
          must('결과 첫 frame 도달(≤60 단계)', resN() > 0, '$steps');
          return (at: now(), steps: steps);
        }

        // 확인창이 사라진 첫 frame 까지(모달 장벽 아래 semantics 는 막힌다)
        Future<int> waitNoDialog() async {
          var steps = 0;
          while (find.byType(Dialog).evaluate().isNotEmpty && steps < 40) {
            await t.pump(const Duration(milliseconds: 16));
            steps++;
          }
          must('확인창 닫힘(≤40 단계)', find.byType(Dialog).evaluate().isEmpty, '$steps');
          return steps;
        }

        // 확인 → 결과 첫 가시 frame. LOOP 는 대상 바뀜 확인창 두 번을 넘긴 뒤 마지막 확인에서 잰다.
        Future<({DateTime at, int steps})> confirmToResult() async {
          if (st.key == 'ARCHLOOP') {
            for (var i = 0; i < 2; i++) {
              await tapOk();
              await settle(16);
              must('대상 바뀜 확인창 ${i + 2}번째', findVisibleText(_changedTitle).evaluate().length == 1);
            }
          }
          await tapOk();
          return waitResult();
        }

        Future<({DateTime at, int steps})> actNow(BusinessModel b) async {
          await openConfirm(b);
          return confirmToResult();
        }

        final b1 = _four[0], b2 = _four[1];
        // 성공 목록(결과 전)
        must('목록 — b1 · b2 제목 1 · 결과 0', inside(b1.name).length == 1 && inside(b2.name).length == 1 && resN() == 0);

        // ① 결과(b1)
        final f1 = await actNow(b1);
        final clear = await waitNoDialog();
        final toastN = overlayN(resText), bandN = inside(resText).length;
        final sx = semExact(), sa = semAny(), sl = semLive();
        final bf = bandFace();
        final face = toastFace();
        final t1 = t.getRect(_el(nameEl(b1))), t2 = t.getRect(_el(nameEl(b2)));
        final c1 = clipOf(nameEl(b1)), c2 = clipOf(nameEl(b2));
        final bandIn = bf != null && inR(clipOf(inside(resText).single), bf) && inR(screen, bf);
        final orderOk = bf != null && bf.bottom <= t1.top + 0.5;
        final t1cov = _hit(t1, face), t2cov = _hit(t2, face);
        final t1in = inR(c1, t1) && inR(screen, t1), t2in = inR(c2, t2) && inR(screen, t2);
        final wantReads = st.key == 'ARCHOK' ? 2 : 1;
        final wantArch = st.key == 'ARCHLOOP' ? 3 : 1;
        _out('D416 $tok result toast=$toastN band=$bandN semExact=$sx semAny=$sa live=$sl orderOk=$orderOk bandIn=$bandIn steps=${f1.steps} clear=$clear '
            't1cov=$t1cov t2cov=$t2cov t1in=$t1in t2in=$t2in reads=${r.calls} archive=${archived.length} preview=${previewCalls.length}');
        must('읽기 $wantReads · archive $wantArch · 사전 조회 1', r.calls == wantReads && archived.length == wantArch && previewCalls.length == 1,
            '${r.calls}/${archived.length}/${previewCalls.length}');
        must('두 모드 확인창 닫힌 첫 frame: overlay 0 · 띠 1 · semantics 원문 정확 1/포함 1 · liveRegion 0 · 띠 면 clip/화면 안 · 첫 제목 위 · 제목 가림 0(H-3 수용 동작)',
            toastN == 0 && bandN == 1 && sx == 1 && sa == 1 && sl == 0 && bandIn && orderOk && !t1cov && !t2cov,
            '$toastN/$bandN/$sx/$sa/$sl/$bandIn/$orderOk/$t1cov/$t2cov');
        // [판정51] 색 — 면 · 글(실제 RenderParagraph 색) · 아이콘 · 글/면 대비
        final isOk = st.key == 'ARCHOK';
        final darkC = isOk ? AppColors.successDark : AppColors.errorDark;
        final lightC = isOk ? AppColors.successBg : AppColors.errorBg;
        final box = bandBox();
        final faceC = box == null ? null : ((box.widget as Container).decoration as BoxDecoration).color;
        final tEl = inside(resText).single;
        final rp = t.renderObject<RenderParagraph>(
            find.descendant(of: _el(tEl), matching: find.byType(RichText, skipOffstage: false), matchRoot: true, skipOffstage: false).first);
        final tc = rp.text.style?.color;
        final row = _ancestor(tEl, (w) => w is Row);
        final icons = row == null
            ? const <Element>[]
            : find.descendant(of: _el(row), matching: find.byWidgetPredicate((w) => w is Icon, skipOffstage: false), skipOffstage: false).evaluate().toList();
        final ic = icons.isEmpty ? null : (icons.first.widget as Icon).color;
        String kind(Color? c) => c == darkC ? 'dark' : (c == lightC ? 'light' : (c == AppColors.textOnDark ? 'white' : 'other'));
        final cr = (tc == null || faceC == null) ? 0.0 : _contrast(tc, faceC);
        _out('D416 $tok color face=${kind(faceC)} ink=${kind(tc)} icon=${kind(ic)} cr=${cr.toStringAsFixed(2)}');
        if (_before) {
          must('before: 진한 면 · 흰 글/아이콘', kind(faceC) == 'dark' && kind(tc) == 'white' && kind(ic) == 'white', '$faceC $tc $ic');
        } else {
          must('strict 색 — 옅은 면 · 진한 글/아이콘 · 대비 ≥ 4.5', kind(faceC) == 'light' && kind(tc) == 'dark' && kind(ic) == 'dark' && cr >= 4.5,
              '$faceC $tc $ic ${cr.toStringAsFixed(2)}');
        }
        await shot('2result', '운영 종료 결과(확인창 닫힌 첫 frame)');

        final exc = t.takeException();
        _out('D416 $tok done state=${st.key} mode=$mode captures=$captures overflows=${overflows.length} exc=${exc != null}');
        await t.pumpWidget(const SizedBox.shrink());
        await settle(4);
        expect(exc, isNull);
        expect(overflows, isEmpty, reason: '$tok 넘침');
      });
    }
  }
}
