// [S014 띠 색 추종 · 판정51 · DU416] 띠 = 옅은 successBg/errorBg 면 · 진한 successDark/errorDark 글/아이콘(대비 ≥ 4.5) — finder 와 strict 색 단언.
// [H-3 수리 2/3] more() finder 화면 밖 포함 — 그 밖 변경 0. 원본 4b3f6808 보존.
// [H-3 · DU414 · 판정45 E N2 · 판정47 §6] S014 사업장 목록 — 운영 종료 결과를 overlay 토스트 대신 목록 위 결과 띠로.
//   새 파일 · 정확 6 public(W 392x844@1.0 · B 320x640@2.0 × ARCHOK · ARCHFAIL · ARCHLOOP) · 캡처 9 단계(× W/B = 18쌍).
//   하네스: du1_s014_toast_410 과 같은 fake core · _Provider · 4곳 fixture · 사전 조회 fixture · debugPreview/debugArchive seam(서버 · writer 0).
//     차이: 전역 navigatorKey 홈 위에 화면을 push 한다(활성 이탈 시험) · 읽기 보류(gate)로 실제 Loading frame 을 만든다(ARCHOK 재조회).
//   모드: DU_BEFORE_OBSERVE=414 이면 before(현행 1ce17649 관측 — overlay · 공유 채널 교체 · 재조회 offset 상실 · route 잔류는 typed), 아니면 strict(E exact).
//   결과: ARCHOK '사업장 운영을 종료했어요'(성공 2s) · ARCHFAIL '사업장 운영을 종료하지 못했어요'(4s) ·
//         ARCHLOOP '정리 대상이 계속 바뀌고 있어요. 잠시 후 다시 시도해 주세요'(서버가 대상 바뀜을 3번 돌려준 뒤 · 4s).
//   시각은 테스트 시계(binding.clock). 확인창이 닫히는 동안 결과가 먼저 보일 수 있어, 수명은 결과가 처음 보인 frame(at)부터 재고
//   개수 · semantics · 순서 · 가림 · 캡처는 확인창이 사라진 첫 frame 에서 잰다(모달 장벽 아래 semantics 는 막히기 때문).
//   단계:
//     ① 결과(b1 운영 종료): overlay 수 · 띠 수 · 활성 semantics 원문 정확/포함 · liveRegion · 띠 면 clip/화면 안 · 순서(띠 ≤ 첫 카드 제목) ·
//        첫/둘째 카드 제목의 overlay 가림 · 화면 안(관측) · 읽기/사전 조회/archive 계수 → 2result.
//     ② 수명: at + (L−0.4s) 남음 · at + (L+0.2s) 사라짐 → 같은 데이터 · 이동 0 첫 카드 제목 ±0.5 → 3expire.
//     ③ 다시 결과 → 결과 전문 · 첫/둘째 카드 제목을 하나씩 ensureVisible 뒤 같은 frame 에서 clip · 화면 안 · 가림 · 조판 측정.
//     ④ 교체(ARCHFAIL): 앞 결과가 살아 있을 때 다시 실패 → 하나 · 새 결과 기준 수명.
//     ⑤ 교차(ARCHOK · ARCHFAIL): 다른 공용 안내 overlay(테스트 표시만)와 서로 지우거나 수명을 늘리지 않음.
//     ⑥ 재조회(ARCHOK): 마지막 카드(b4)로 가능한 비영 offset → 읽기 보류 → 결과 + 실제 Loading frame(띠 유지 · 목록 분리) → 풀기 → 만료 뒤 pixels · anchor ±0.5.
//     ⑦ 이탈: 결과가 살아 있을 때 route pop → 다음 화면 결과 수 → 원 만료 뒤 추가 pump · 예외 0.
//   누름: 더보기 · 시트 '운영 종료' · 확인창 '운영 종료'(LOOP 는 3번). SubAdmin 은 이 fake(BUSINESS_ADMIN 고정)에서 시험하지 않는다.
//   출력 줄: lkit 선언형 계약 'D414 <tok> <kind> [<sub>] k=v …' — 값 공백 0.
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
import 'package:ALfit/utils/toast_helper.dart';
import 'package:ALfit/widgets/common/loading_widget.dart';

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
const _other1 = '다른 안내 확인 하나';
const _other2 = '다른 안내 확인 둘';

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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '414';
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _wj = '⁠';
const _zw = '​';
const _nb = ' ';
bool _visible(String ch) => ch != ' ' && ch != _nb && ch != '\n' && ch != _wj && ch != _zw;

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _r(Rect r) => '${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)},${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)}';
String _vt(Widget w) => w is Text ? visibleText(w.data ?? w.textSpan?.toPlainText() ?? '') : '';
Finder _vis(String text) => find.byWidgetPredicate((w) => w is Text && _vt(w) == text, skipOffstage: false);
Finder _el(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);

/// 로컬 조판 측정(406 · 407 · 410 · 413 과 같은 규칙): 낱말 분절 · 가시 가로 초과 · 말줄임 · 줄 수.
({int bad, int glyphX, bool ell, int lines}) _measure(RenderParagraph rp) {
  final s = rp.text.toPlainText();
  final w = rp.size.width;
  final tops = <double>[];
  var bad = 0, glyphX = 0;
  int? prevI;
  double? prevTop;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final b = bx.first;
    if ((b.right - b.left).abs() < 0.01 || !_visible(ch)) continue;
    if (b.right > w + 0.5 || b.left < -0.5) glyphX++;
    if (prevTop != null && (b.top - prevTop).abs() > 1.0) {
      final between = s.substring(prevI! + 1, i);
      if (!between.contains('\n') && !between.contains(' ')) bad++;
    }
    if (!tops.any((x) => (x - b.top).abs() <= 1.0)) tops.add(b.top);
    prevI = i;
    prevTop = b.top;
  }
  return (bad: bad, glyphX: glyphX, ell: rp.didExceedMaxLines, lines: tops.length);
}

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
          (_) async => codec.encodeMessage(<Object?>['du414.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du414.fake.$m'), (_) async => null);
    }
  });

  const views = [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const states = [
    (key: 'ARCHOK', title: '운영 종료 성공 — 목록 위 결과 띠 2초 · 재조회 중 유지'),
    (key: 'ARCHFAIL', title: '운영 종료 일반 실패 — 목록 위 결과 띠 4초 · 목록 유지'),
    (key: 'ARCHLOOP', title: '정리 대상 계속 바뀜 3회 — 목록 위 결과 띠 4초 · 긴 문장'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S014H-${v.id}-${st.key} ${st.title}', (t) async {
        final tok = 'S014H-${v.id}-${st.key}';
        final mode = _before ? 'before' : 'strict';
        _out('D414 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
        int ageMs(DateTime from) => now().difference(from).inMilliseconds;
        Future<void> pumpTo(DateTime from, int ms) async {
          while (ageMs(from) < ms) {
            final left = ms - ageMs(from);
            await t.pump(Duration(milliseconds: left < 50 ? left : 50));
          }
        }

        var captures = 0;
        final key = GlobalKey();
        final cond = {'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': st.key};
        Future<void> shot(String id, String stage) async {
          await vqCapture(t, key, '${tok}_$id', conditions: {...cond, 'state': stage});
          captures++;
        }

        final life = st.key == 'ARCHOK' ? 2000 : 4000;
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

        // 띠 면(successBg / errorBg Container · 판정51 옅은 면) — 글 rect 가 아니라 면 기준
        Rect? bandFace() {
          final b = inside(resText);
          if (b.length != 1) return null;
          final box = _ancestor(b.single, (w) {
            if (w is! Container || w.decoration is! BoxDecoration) return false;
            final c = (w.decoration as BoxDecoration).color;
            return c == AppColors.errorBg || c == AppColors.successBg;
          });
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
        Element resultEl() {
          final ins = inside(resText);
          if (ins.length == 1) return ins.single;
          return overlayEls(resText).first;
        }

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

        final b1 = _four[0], b2 = _four[1], b4 = _four[3];
        // 성공 목록(결과 전)
        must('목록 — b1 · b2 제목 1 · 결과 0', inside(b1.name).length == 1 && inside(b2.name).length == 1 && resN() == 0);
        final anchor0 = t.getRect(_el(nameEl(b1)));
        await shot('1list', '운영 종료 전 목록');

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
        _out('D414 $tok result toast=$toastN band=$bandN semExact=$sx semAny=$sa live=$sl orderOk=$orderOk bandIn=$bandIn steps=${f1.steps} clear=$clear '
            't1cov=$t1cov t2cov=$t2cov t1in=$t1in t2in=$t2in reads=${r.calls} archive=${archived.length} preview=${previewCalls.length}');
        // [판정51] strict 띠 색 — 면 = 상태 옅은 색 · 글(실제 RenderParagraph)/아이콘 = 상태 진한 색 · 글/면 대비 ≥ 4.5
        if (!_before && bf != null) {
          final isOk = st.key == 'ARCHOK';
          final wantInk = isOk ? AppColors.successDark : AppColors.errorDark;
          final wantBg = isOk ? AppColors.successBg : AppColors.errorBg;
          final tEl = inside(resText).single;
          final rp = t.renderObject<RenderParagraph>(
              find.descendant(of: _el(tEl), matching: find.byType(RichText, skipOffstage: false), matchRoot: true, skipOffstage: false).first);
          final tc = rp.text.style?.color;
          final row = _ancestor(tEl, (w) => w is Row);
          final icons = row == null
              ? const <Element>[]
              : find.descendant(of: _el(row), matching: find.byWidgetPredicate((w) => w is Icon, skipOffstage: false), skipOffstage: false).evaluate().toList();
          final ic = icons.isEmpty ? null : (icons.first.widget as Icon).color;
          final faceC = (_ancestor(tEl, (w) => w is Container && w.decoration is BoxDecoration)?.widget as Container?)?.decoration as BoxDecoration?;
          final cr = tc == null ? 0.0 : _contrast(tc, wantBg);
          must('strict 띠 색 — 면 옅은 상태색 · 글/아이콘 진한 상태색 · 대비 ≥ 4.5', faceC?.color == wantBg && tc == wantInk && ic == wantInk && cr >= 4.5,
              '${faceC?.color} $tc $ic ${cr.toStringAsFixed(2)}');
        }
        must('읽기 $wantReads · archive $wantArch · 사전 조회 1', r.calls == wantReads && archived.length == wantArch && previewCalls.length == 1,
            '${r.calls}/${archived.length}/${previewCalls.length}');
        if (_before) {
          must('before: overlay 토스트 1 · 띠 0', toastN == 1 && bandN == 0, '$toastN/$bandN');
        } else {
          must('strict 확인창 닫힌 첫 frame: overlay 0 · 띠 1 · semantics 원문 정확 1/포함 1 · liveRegion 0 · 띠 면 clip/화면 안 · 첫 제목 위 · 제목 가림 0',
              toastN == 0 && bandN == 1 && sx == 1 && sa == 1 && sl == 0 && bandIn && orderOk && !t1cov && !t2cov,
              '$toastN/$bandN/$sx/$sa/$sl/$bandIn/$orderOk/$t1cov/$t2cov');
        }
        await shot('2result', '운영 종료 결과(확인창 닫힌 첫 frame)');

        // ② 수명 · 이동 0 기준 위치 복구
        await pumpTo(f1.at, life - 400);
        final alive = resN() == 1;
        await pumpTo(f1.at, life + 200);
        final gone = resN() == 0;
        await settle(4);
        final a1 = t.getRect(_el(nameEl(b1)));
        final dy = a1.top - anchor0.top;
        final restored = dy.abs() <= 0.5 && (a1.left - anchor0.left).abs() <= 0.5;
        _out('D414 $tok expire alive=$alive gone=$gone restored=$restored dy=${dy.toStringAsFixed(2)}');
        must('결과 +${life - 400}ms 남음 · +${life + 200}ms 사라짐 · 첫 제목 복구(같은 데이터 · 이동 0)', alive && gone && restored, '$alive/$gone/$dy');
        await shot('3expire', '결과 만료 뒤');

        // ③ 결과 전문 · 첫/둘째 카드 제목 — 하나씩 ensureVisible 뒤 같은 frame 측정
        final f3 = await actNow(b1);
        await waitNoDialog();
        final keys = <({String sub, Element Function() el})>[
          (sub: 'res', el: resultEl),
          (sub: 't1', el: () => nameEl(b1)),
          (sub: 't2', el: () => nameEl(b2)),
        ];
        for (final k in keys) {
          await t.ensureVisible(_el(k.el()));
          await settle(4);
          final e = k.el(); // 같은 frame 재취득
          final rr = t.getRect(_el(e));
          final clip = clipOf(e);
          final rp = t.renderObject<RenderParagraph>(
              find.descendant(of: _el(e), matching: find.byType(RichText, skipOffstage: false), matchRoot: true, skipOffstage: false).first);
          final m = _measure(rp);
          final cov = k.sub == 'res' ? (inside(resText).isNotEmpty && overlayN(resText) > 0) : (_hit(rr, toastFace()) || _hit(rr, bandFace()));
          final inClip = inR(clip, rr), inScreen = inR(screen, rr);
          final aliveR = resN() > 0;
          _out('D414 $tok read ${k.sub} inClip=$inClip inScreen=$inScreen covered=$cov ell=${m.ell} glyphX=${m.glyphX} lines=${m.lines} alive=$aliveR');
          if (!_before) {
            must('${k.sub} 전문 읽기 — clip · 화면 안 · 가림 0 · 말줄임 0 · 가로 0 · 결과 살아 있음',
                inClip && inScreen && !cov && !m.ell && m.glyphX == 0 && m.lines >= 1 && aliveR, '${_r(rr)} clip=${_r(clip)} $m');
          }
        }

        if (st.key == 'ARCHFAIL') {
          // ④ 교체 — 앞 결과(f3)가 살아 있을 때 다시 실패 → 하나 · 새 결과 기준 수명
          await openConfirm(b1);
          must('교체 직전 앞 결과 살아 있음', resN() == 1, '${ageMs(f3.at)}');
          final f4 = await confirmToResult();
          final countAfter = resN();
          await pumpTo(f4.at, life - 400);
          final aliveAfter = resN() == 1;
          await pumpTo(f4.at, life + 200);
          final goneAfter = resN() == 0;
          _out('D414 $tok replace count=$countAfter alive=$aliveAfter gone=$goneAfter');
          must('연속 실패 = 결과 하나 · 새 결과 기준 수명', countAfter == 1 && aliveAfter && goneAfter, '$countAfter/$aliveAfter/$goneAfter');
          await settle(4);
        }

        if (st.key != 'ARCHLOOP') {
          // ⑤ 교차 — 다른 공용 안내 overlay 와 결과가 서로 지우거나 수명을 늘리지 않는다
          final w0 = now();
          while ((resN() > 0 || _vis(_other1).evaluate().isNotEmpty || _vis(_other2).evaluate().isNotEmpty) && ageMs(w0) < 6000) {
            await t.pump(const Duration(milliseconds: 50));
          }
          must('교차 선행 — 결과 · 다른 안내 0', resN() == 0 && _vis(_other1).evaluate().isEmpty && _vis(_other2).evaluate().isEmpty);
          await openConfirm(b1);
          ToastHelper.showInfo(_other1);
          await t.pump();
          final o0 = now();
          await t.pump(const Duration(milliseconds: 300));
          final fb = await confirmToResult();
          final o = _vis(_other1).evaluate().length == 1;
          final res = resN() == 1;
          await pumpTo(o0, 2150);
          final oGone = _vis(_other1).evaluate().isEmpty;
          final bAlive1 = resN() == 1;
          ToastHelper.showInfo(_other2);
          await t.pump();
          final o20 = now();
          final b = resN() == 1;
          await pumpTo(fb.at, life - 400);
          final bAlive = resN() == 1;
          final o2Alive = _vis(_other2).evaluate().length == 1;
          await pumpTo(fb.at, life + 200);
          final bGone = resN() == 0;
          final o2AtGone = _vis(_other2).evaluate().length == 1;
          await pumpTo(o20, 2200);
          final o2Gone = _vis(_other2).evaluate().isEmpty;
          _out('D414 $tok cross o=$o res=$res oGone=$oGone bAlive1=$bAlive1 b=$b bAlive=$bAlive bGone=$bGone o2Alive=$o2Alive o2AtGone=$o2AtGone o2Gone=$o2Gone');
          must('교차 — 결과 생성 · 다른 안내 각자 수명 · 결과 만료', res && oGone && bAlive1 && bGone && o2Alive && o2Gone,
              '$res/$oGone/$bAlive1/$bGone/$o2Alive/$o2Gone');
          must('결과 만료 시점의 둘째 안내 = 수명 기준(L ${life}ms)', o2AtGone == (life == 2000), '$o2AtGone');
          if (!_before) must('strict 교차 독립 — 결과가 다른 안내를 지우지 않음 · 다른 안내가 결과를 지우지 않음', o && b && bAlive, '$o/$b/$bAlive');
          await settle(4);
        }

        if (st.key == 'ARCHOK') {
          // ⑥ 재조회 — 마지막 카드(b4) 운영 종료로 가능한 비영 offset → 읽기 보류 → 결과 + 실제 Loading frame(결과 유지 · 목록 분리)
          final w6 = now();
          while (resN() > 0 && ageMs(w6) < 6000) {
            await t.pump(const Duration(milliseconds: 50));
          }
          await openConfirm(b4);
          final lists = find.descendant(of: scr, matching: find.byType(ListView));
          must('목록 정확 1', lists.evaluate().length == 1, '${lists.evaluate().length}');
          final scr0 = find.descendant(of: lists, matching: find.byType(Scrollable)).first;
          final p0 = t.state<ScrollableState>(scr0).position.pixels;
          final possible = p0 > 0.5;
          final a0 = t.getRect(_el(nameEl(b4)));
          final g = Completer<void>();
          r.gate = g;
          final f6 = await confirmToResult();
          await waitNoDialog();
          final loading = find.descendant(of: scr, matching: find.byType(LoadingWidget)).evaluate().length == 1;
          final listGone = find.descendant(of: scr, matching: find.byType(ListView)).evaluate().isEmpty;
          // [impl_27b · 판정291 B8 핀 갱신] 처리 뒤 다시 읽기는 이제 목록을 지우지 않고(Loading frame 0) 잠근다 —
          //   예전 기대(실제 Loading frame · 목록 분리)는 바뀐 계약의 옛 핀이다. 의도(결과 띠 유지 · 풀면 목록 · offset 복원)는 그대로 본다.
          final listKeptLocked = !loading &&
              !listGone &&
              find.byKey(const ValueKey('business-list-refresh-after-mutation')).evaluate().length == 1 &&
              t.widgetList<AbsorbPointer>(find.ancestor(
                      of: find.descendant(of: scr, matching: find.byType(ListView)).first,
                      matching: find.byType(AbsorbPointer)))
                  .any((w) => w.absorbing);
          final resDuring = resN() == 1;
          final bandDuring = inside(resText).length;
          r.gate = null;
          g.complete();
          await settle(4);
          final listBack = find.descendant(of: scr, matching: find.byType(ListView)).evaluate().length == 1;
          final resAfter = resN() == 1;
          await pumpTo(f6.at, life + 200);
          await settle(4);
          final scr1 = find.descendant(of: find.descendant(of: scr, matching: find.byType(ListView)), matching: find.byType(Scrollable)).first;
          final p1 = t.state<ScrollableState>(scr1).position.pixels;
          // before 는 재조회로 offset 을 잃어 b4 가 아직 만들어지지 않았을 수 있다 — 예외 대신 관측(dy=none · restored false)
          final b4now = inside(b4.name);
          final a6 = b4now.length == 1 ? t.getRect(_el(b4now.single)) : null;
          final dy6 = a6 == null ? null : a6.top - a0.top;
          final restored6 = a6 != null && (p1 - p0).abs() <= 0.5 && dy6!.abs() <= 0.5 && (a6.left - a0.left).abs() <= 0.5;
          _out('D414 $tok reload possible=$possible p0=${p0.toStringAsFixed(1)} loading=$loading listGone=$listGone resDuring=$resDuring '
              'bandDuring=$bandDuring listBack=$listBack resAfter=$resAfter p1=${p1.toStringAsFixed(1)} dy=${dy6 == null ? 'none' : dy6.toStringAsFixed(2)} '
              'restored=$restored6 reads=${r.calls}');
          must('읽기 보류 중 목록 유지·잠금(전체 Loading 0) · 결과 유지 → 풀면 목록 · 결과 유지', listKeptLocked && resDuring && listBack && resAfter,
              '$loading/$listGone/$listKeptLocked/$resDuring/$listBack/$resAfter');
          if (!_before) {
            must('strict Loading 중 띠 1 · 만료 뒤 pixels · anchor ±0.5', bandDuring == 1 && restored6, '$bandDuring $p0→$p1 dy=$dy6');
          }
        }

        // ⑦ 결과가 살아 있을 때 route 이탈 → 다음 화면 결과 수 → 원 만료 뒤 추가 pump · 예외 0
        final w7 = now();
        while (resN() > 0 && ageMs(w7) < 6000) {
          await t.pump(const Duration(milliseconds: 50));
        }
        final f7 = await actNow(b1);
        await waitNoDialog();
        final aliveX = resN() == 1;
        navigatorKey.currentState!.pop();
        await settle(12);
        final goneX = find.byType(BusinessListScreen).evaluate().isEmpty;
        final left = _vis(resText).evaluate().length;
        await pumpTo(f7.at, life + 600);
        await settle(4);
        final after = _vis(resText).evaluate().length;
        final excX = t.takeException();
        _out('D414 $tok exit alive=$aliveX gone=$goneX left=$left after=$after exc=${excX != null}');
        must('이탈 — 결과 살아 있음 · 화면 사라짐 · 원 만료 뒤 결과 0 · 예외 0', aliveX && goneX && after == 0 && excX == null, '$aliveX/$goneX/$after $excX');
        if (!_before) must('strict 이탈 → 다음 화면 결과 0', left == 0, '$left');

        final exc = t.takeException();
        _out('D414 $tok done state=${st.key} mode=$mode captures=$captures overflows=${overflows.length} exc=${exc != null}');
        await t.pumpWidget(const SizedBox.shrink());
        await settle(4);
        expect(exc, isNull);
        expect(overflows, isEmpty, reason: '$tok 넘침');
      });
    }
  }
}
