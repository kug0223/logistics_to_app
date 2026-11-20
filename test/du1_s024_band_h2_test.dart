// [H-2 fix1 · DU413 · 감사46 §4 지정 예방 보완] v2 cf49316f · v1 399257e2 보존. 같은 6 public(W 392x844@1.0 · B 320x640@2.0 × REFRESH · EMPTYS · EMPTYM) · 캡처 8쌍.
// [H-2 · 소급 45 E] S024 팀원 관리 — 새로고침 실패를 화면 안 결과 띠로(N2′ 목록 위 · N3 빈 상태 부제 아래).
//   하네스: du1_s024_toast_407 와 같은 fake core · _Provider · 읽기 seam(MemberManagementReads) · 전역 navigatorKey(ToastHelper overlay).
//   모드: DU_BEFORE_OBSERVE=413 이면 before(현행 fb1653df 관측 — overlay · 공유 채널 교체 · offset 상실 · route 잔류는 typed 기록), 아니면 strict(E 계약 exact).
//   시각은 테스트 시계(binding.clock) 기준이다. 결과 생성은 그 결과가 처음 보인 frame 직전 16ms 단계 안이다(생성 ∈ (at−16ms, at]).
//   단계:
//     ① 실패 첫 가시 frame(16ms 단계 · 스크롤 0): overlay 수 · 띠 수 · 활성 semantics 트리 원문 label 정확/포함 · liveRegion · 순서(띠 면 기준) ·
//        띠 면 clip/화면 안 · 첫 보호 대상 overlay 가림 → 같은 frame 캡처 2fail. 보호 대상 receiver 는 이동 없이 관측만(scan).
//     ② 수명(REFRESH/EMPTYS): 생성 +3.6s 남음 · +4.2s 사라짐 → 같은 데이터 · 이동 0 기준 위치 ±0.5 → 3expire.
//     ③ 다시 실패 → 결과 전문 · 필수 정보(이름 / 제목 · 부제 · 진입 / 행)를 하나씩 ensureVisible 뒤 같은 frame 에서 clip · 화면 안 · 가림 · 조판(말줄임 · 가로) 측정(EMPTYM 포함).
//        REFRESH/EMPTYS 는 이어서 교체: 앞 결과가 살아 있을 때 다시 실패 → 하나 · 새 결과 생성 기준 +3.6s 남음 · +4.2s 사라짐.
//     ④ 다시 실패 → 보호 대상마다 ensureVisible → 같은 frame rect · 중앙 hit · ≥48 · 화면/clip 안 · 가림 · 결과 살아 있음 → 실제 tapAt → 초대 대화창 1 → 닫기 → 다시 읽기 0.
//     ⑤ 성공 새로고침(REFRESH/EMPTYS) → 띠 0 · 내용 유지.
//     ⑥ 교차(REFRESH/EMPTYS): 다른 안내 overlay(ToastHelper.showInfo · 테스트 표시만)를 결과 전후에 띄워 서로 지우거나 수명을 늘리지 않음.
//     ⑦ offset(REFRESH): 실제 drag 로 가능한 비영 offset → 읽기 보류로 실제 Loading frame · 목록 분리 → 같은 데이터 실패 → 결과 만료 뒤 pixels · anchor ±0.5.
//     ⑧ 이탈: 결과가 살아 있을 때 route pop → 다음 화면 결과 수 → 원 만료 시각 뒤 추가 pump · 예외 0.
//   SubAdmin: 이 fake 는 BUSINESS_ADMIN 고정 세션이라 SubAdmin 분기를 시험하지 않는다(역할 전이 · 실권한 미완료 — 전역 미도달로 쓰지 않는다).
//   출력 줄: lkit 선언형 계약 'D413 <tok> <kind> [<sub>] k=v …' — 값 공백 0.
// [S024 표시 셀 p2 · 판정51] 띠 = 옅은 errorBg 면 · errorDark 글/아이콘(대비 ≥ 4.5) — finder 와 strict 색 단언.
// [S024 초대 추종 · DU415] REFRESH 보호 대상 = 사업장 머리 옆 '+ 멤버 초대'(FAB 제거). 그 밖 변경 0.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
import 'package:ALfit/models/core/member_invitation_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/member_management_reads.dart';
import 'package:ALfit/screens/business_admin/member_management_screen.dart';
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
}

BusinessModel _biz(String id, String name) => BusinessModel(
      id: id,
      businessNumber: '000-00-00000',
      name: name,
      category: '물류',
      subCategory: '창고',
      address: '서울특별시 강남구 테헤란로 152',
      ownerId: 'u1',
      isApproved: true,
      createdAt: DateTime(2026, 10, 1),
    );

BusinessMemberModel _member(String biz, String uid, String name) =>
    BusinessMemberModel(uid: uid, businessId: biz, name: name, permissions: const MemberPermissions(), addedAt: DateTime(2026, 11, 1), addedBy: 'u1');

MemberInvitationModel _invite(String biz, String bizName, String id, String name) => MemberInvitationModel(
      id: id,
      businessId: biz,
      businessName: bizName,
      targetUid: 't_$id',
      targetName: name,
      invitedBy: 'u1',
      invitedByName: '김사장',
      permissions: const MemberPermissions(canManageTo: true),
      status: InvitationStatus.pending,
      createdAt: DateTime(2026, 11, 15, 10),
    );

const _bizA = '강남 물류센터';
const _bizB = '송파 신선 분류센터';
const _err = '멤버 목록을 불러오지 못했어요';
const _emptyText = '등록된 멤버가 없습니다';
const _emptySub1 = '멤버를 초대하고 사업장을 함께 관리해보세요';
const _emptySubM = '초대할 사업장을 선택하세요';
// [fix1 ⑥] 테스트가 직접 띄우는 다른 공용 안내(서버 · 업무 writer 호출 0)
const _other1 = '다른 안내 확인 하나';
const _other2 = '다른 안내 확인 둘';

class _Reads {
  _Reads({required this.biz, this.members = const {}, this.invites = const {}});

  final List<BusinessModel> biz;
  final Map<String, List<BusinessMemberModel>> members;
  final Map<String, List<MemberInvitationModel>> invites;
  final failMembers = <String>{};
  // [fix1 ⑦] 읽기 보류 — 실제 Loading frame 을 만든다(REFRESH offset 구간만 쓴다)
  Completer<void>? gate;
  var bizCalls = 0, memberCalls = 0, inviteCalls = 0;

  MemberManagementReads get reads => MemberManagementReads(
        businessesByIds: (ids) async {
          bizCalls++;
          final g = gate;
          if (g != null) await g.future;
          return [for (final b in biz) if (ids.contains(b.id)) b];
        },
        members: (id) async {
          memberCalls++;
          if (failMembers.contains(id)) throw StateError('DU413 fake members 실패 $id');
          return members[id] ?? const [];
        },
        sentPendingInvitations: (id) async {
          inviteCalls++;
          return invites[id] ?? const [];
        },
      );

  String get counts => '$bizCalls/$memberCalls/$inviteCalls';
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '413';
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

/// 로컬 조판 측정(du1_s024_toast_407 · DU406 과 같은 규칙): 낱말 분절 · 가시 가로 초과 · 말줄임 · 줄 수.
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

List<Element> _under(Element scope, bool Function(Widget w) p) =>
    find.descendant(of: _el(scope), matching: find.byWidgetPredicate(p, skipOffstage: false), skipOffstage: false).evaluate().toList();

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
          (_) async => codec.encodeMessage(<Object?>['du413.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du413.fake.$m'), (_) async => null);
    }
  });

  const views = [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const states = [
    (key: 'REFRESH', title: '목록 뒤 새로고침 실패 — 목록 위 결과 띠 · 머리 초대 보호'),
    (key: 'EMPTYS', title: '빈 화면 뒤 새로고침 실패 — 부제 아래 결과 띠 · 단일 초대 진입'),
    (key: 'EMPTYM', title: '두 사업장 빈 화면 뒤 새로고침 실패 — 부제 아래 결과 띠 · 사업장별 초대 행'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S024H-${v.id}-${st.key} ${st.title}', (t) async {
        final tok = 'S024H-${v.id}-${st.key}';
        final mode = _before ? 'before' : 'strict';
        _out('D413 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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

        // 테스트 시계 — 수명 경계는 결과 생성(첫 가시 frame) 기준
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

        final scaf = find.byType(MemberManagementScreen);
        List<Element> inside(String s) =>
            find.descendant(of: scaf, matching: find.byWidgetPredicate((w) => w is Text && _vt(w) == s, skipOffstage: false), skipOffstage: false).evaluate().toList();
        List<Element> overlayEls(String s) {
          final ins = inside(s).toSet();
          return [for (final e in _vis(s).evaluate()) if (!ins.contains(e)) e];
        }

        int overlayN(String s) => overlayEls(s).length;
        // 결과 수 = 화면 안 띠 + overlay 토스트(같은 문장)
        int resN() => inside(_err).length + overlayN(_err);
        Rect? toastFace() {
          final o = overlayEls(_err);
          if (o.isEmpty) return null;
          final box = _ancestor(o.first, (w) => w is IgnorePointer);
          return box == null ? null : t.getRect(_el(box));
        }

        // 띠 면(errorBg Container · 판정51 옅은 면) — 글 rect 가 아니라 면 기준
        Rect? bandFace() {
          final b = inside(_err);
          if (b.length != 1) return null;
          final box = _ancestor(b.single, (w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == AppColors.errorBg);
          return box == null ? null : t.getRect(_el(box));
        }

        // 활성 semantics 트리(위젯 수가 아니다)
        int semExact() => find.semantics.byPredicate((n) => n.label == _err).evaluate().length;
        int semAny() => find.semantics.byPredicate((n) => n.label.contains(_err)).evaluate().length;
        int semLive() => find.semantics.byPredicate((n) => n.label.contains(_err) && n.flagsCollection.isLiveRegion).evaluate().length;

        Rect bodyBox() {
          final ab = find.descendant(of: scaf, matching: find.byType(AppBar));
          final top = ab.evaluate().isEmpty ? 0.0 : t.getRect(ab.first).bottom;
          return Rect.fromLTRB(0, top, v.w, v.h);
        }

        // 실제 clip: 가장 가까운 Scrollable viewport → 없으면 화면 본문(AppBar 아래) → 화면 밖 overlay 는 화면
        Rect clipOf(Element e) {
          final sc = _ancestor(e, (w) => w is Scrollable);
          if (sc != null) return t.getRect(_el(sc));
          if (_ancestor(e, (w) => w is MemberManagementScreen) != null) return bodyBox();
          return screen;
        }

        bool hitAt(Element target, Offset p) {
          final hr = HitTestResult();
          WidgetsBinding.instance.hitTestInView(hr, p, t.view.viewId);
          final ro = target.findRenderObject();
          return hr.path.any((e) => e.target == ro);
        }

        // 보호 대상 receiver — REFRESH: 사업장 머리 옆 '+ 멤버 초대'(TextButton 계열) · EMPTYS: 단일 진입 InkWell · EMPTYM: 사업장별 행 InkWell(위에서부터)
        List<Element> inks() => find.descendant(of: scaf, matching: find.byType(InkWell), skipOffstage: false).evaluate().toList();
        List<Element> targets() {
          if (st.key == 'REFRESH') {
            return [
              for (final e in find.descendant(of: scaf, matching: find.byWidgetPredicate((w) => w is TextButton), skipOffstage: false).evaluate())
                if (_under(e, (w) => w is Text).any((x) => _vt(x.widget) == '멤버 초대')) e
            ];
          }
          if (st.key == 'EMPTYS') {
            return [
              for (final ink in inks())
                if (_under(ink, (w) => w is Text).length == 1 && _vt(_under(ink, (w) => w is Text).single.widget) == '멤버 초대') ink
            ];
          }
          return [
            for (final ink in inks())
              if (_under(ink, (w) => w is Text).length == 2 && _vt(_under(ink, (w) => w is Text).last.widget) == '초대') ink
          ]..sort((a, b) => t.getRect(_el(a)).top.compareTo(t.getRect(_el(b)).top));
        }

        final subs = st.key == 'REFRESH' ? const ['invite'] : (st.key == 'EMPTYS' ? const ['entry'] : const ['row1', 'row2']);
        Rect anchorRect() => st.key == 'REFRESH' ? t.getRect(_el(inside('김민준').single)) : t.getRect(_el(targets().first));
        Element resultEl() {
          final ins = inside(_err);
          if (ins.length == 1) return ins.single;
          return overlayEls(_err).first;
        }

        final r = st.key == 'REFRESH'
            ? _Reads(biz: [_biz('b1', _bizA)], members: {
                'b1': [_member('b1', 'm1', '김민준')],
              }, invites: {
                'b1': [_invite('b1', _bizA, 'i1', '이도윤')],
              })
            : st.key == 'EMPTYS'
                ? _Reads(biz: [_biz('b1', _bizA)])
                : _Reads(biz: [_biz('b1', _bizA), _biz('b2', _bizB)]);
        final nBiz = r.biz.length;
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>(create: (_) => _Provider(ids: [for (final b in r.biz) b.id])),
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
        unawaited(navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => MemberManagementScreen(reads: r.reads))));
        await settle(12);

        Future<void> tapRefresh() async {
          final f = find.byTooltip('새로고침');
          must('상단 새로고침 버튼 정확 1', f.evaluate().length == 1, '${f.evaluate().length}');
          await t.tap(f);
        }

        Future<void> refresh() async {
          await tapRefresh();
          await settle(12);
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

        Future<({DateTime at, int steps})> failNow() async {
          r.failMembers.add('b1');
          await tapRefresh();
          return waitResult();
        }

        // 성공 화면(새로고침 전)
        if (st.key == 'REFRESH') {
          must('성공 목록 — 멤버 · 초대 · 머리 초대 1', inside('김민준').length == 1 && inside('이도윤').length == 1 && targets().length == 1);
        } else {
          must('성공 빈 화면 — 제목 1 · 부제 1 · 진입 ${st.key == 'EMPTYS' ? 1 : 2}',
              inside(_emptyText).length == 1 && inside(st.key == 'EMPTYS' ? _emptySub1 : _emptySubM).length == 1 && targets().length == (st.key == 'EMPTYS' ? 1 : 2));
        }
        must('성공 화면 오류 0', resN() == 0);
        final anchor0 = anchorRect();
        await shot(st.key == 'REFRESH' ? '1list' : '1empty', '성공 화면(새로고침 전)');

        // ① 실패 첫 가시 frame(스크롤 0)
        final f1 = await failNow();
        final toastN = overlayN(_err), bandN = inside(_err).length;
        final sx = semExact(), sa = semAny(), sl = semLive();
        final bf = bandFace();
        final face = toastFace();
        final tg = targets();
        must('보호 대상 정확 ${subs.length}', tg.length == subs.length, '${tg.length}');
        final tr0 = t.getRect(_el(tg.first));
        var orderOk = false;
        var bandIn = false;
        if (bf != null) {
          bandIn = inR(clipOf(inside(_err).single), bf) && inR(screen, bf);
          if (st.key == 'REFRESH') {
            orderOk = bf.bottom <= t.getRect(_el(inside('김민준').single)).top + 0.5 && bf.bottom <= t.getRect(_el(inside('이도윤').single)).top + 0.5;
          } else {
            final sub = t.getRect(_el(inside(st.key == 'EMPTYS' ? _emptySub1 : _emptySubM).single));
            orderOk = sub.bottom <= bf.top + 0.5 && bf.bottom <= tr0.top + 0.5;
          }
        }
        final covered = _hit(tr0, face);
        // [판정51] strict 띠 색 — 면 errorBg · 글/아이콘 errorDark · 글/면 대비 ≥ 4.5(실제 RenderParagraph 색)
        if (!_before && bf != null) {
          final tEl = inside(_err).single;
          final rp = t.renderObject<RenderParagraph>(
              find.descendant(of: _el(tEl), matching: find.byType(RichText, skipOffstage: false), matchRoot: true, skipOffstage: false).first);
          final tc = rp.text.style?.color;
          final row = _ancestor(tEl, (w) => w is Row);
          final icons = row == null ? const <Element>[] : _under(row, (w) => w is Icon);
          final ic = icons.isEmpty ? null : (icons.first.widget as Icon).color;
          final cr = tc == null ? 0.0 : _contrast(tc, AppColors.errorBg);
          must('strict 띠 색 — 글/아이콘 errorDark · 면 errorBg 대비 ≥ 4.5', tc == AppColors.errorDark && ic == AppColors.errorDark && cr >= 4.5,
              '$tc $ic ${cr.toStringAsFixed(2)}');
        }
        _out('D413 $tok fail toast=$toastN band=$bandN semExact=$sx semAny=$sa live=$sl orderOk=$orderOk bandIn=$bandIn steps=${f1.steps} '
            'target=${_r(tr0)} covered=$covered reads=${r.counts}');
        if (_before) {
          must('before: overlay 토스트 1 · 띠 0', toastN == 1 && bandN == 0, '$toastN/$bandN');
        } else {
          must('strict 첫 frame: overlay 0 · 띠 1 · semantics 원문 정확 1/포함 1 · liveRegion 0 · 순서 · 띠 면 clip/화면 안 · 보호 대상 가림 0',
              toastN == 0 && bandN == 1 && sx == 1 && sa == 1 && sl == 0 && orderOk && bandIn && !covered, '$toastN/$bandN/$sx/$sa/$sl/$orderOk/$bandIn/$covered');
        }
        for (var i = 0; i < tg.length; i++) {
          // 이동 없는 최초 관측(판정은 ④) — B 에서 화면 밖이어도 여기서 실패로 단정하지 않는다
          final rr = t.getRect(_el(tg[i]));
          _out('D413 $tok scan ${subs[i]} h=${rr.height.toStringAsFixed(1)} minOk=${rr.height >= 47.99 && rr.width >= 47.99} hit=${hitAt(tg[i], rr.center)} inScreen=${inR(screen, rr)}');
        }
        await shot('2fail', '새로고침 실패 첫 frame');

        if (st.key != 'EMPTYM') {
          // ② 수명 · 이동 0 기준 위치 복구
          await pumpTo(f1.at, 3600);
          final alive = resN() == 1;
          await pumpTo(f1.at, 4200);
          final gone = resN() == 0;
          await settle(4);
          final a1 = anchorRect();
          final dy = a1.top - anchor0.top;
          final restored = dy.abs() <= 0.5 && (a1.left - anchor0.left).abs() <= 0.5;
          _out('D413 $tok expire alive=$alive gone=$gone restored=$restored dy=${dy.toStringAsFixed(2)}');
          must('생성 +3.6s 남음 · +4.2s 사라짐 · 기준 위치 복구(같은 데이터 · 이동 0)', alive && gone && restored, '$alive/$gone/$dy');
          await shot('3expire', '결과 만료 뒤');
        }

        // ③ 결과 전문 · 필수 정보 도달(EMPTYM 포함) — 하나씩 ensureVisible 뒤 같은 frame 측정
        final f3 = await failNow();
        Element textOf(Element ink, {bool last = false}) {
          final ts = _under(ink, (w) => w is Text);
          return last ? ts.last : ts.single;
        }

        final keys = <({String sub, Element Function() el})>[
          (sub: 'res', el: resultEl),
          if (st.key == 'REFRESH') ...[
            (sub: 'm1', el: () => inside('김민준').single),
            (sub: 'i1', el: () => inside('이도윤').single),
          ] else ...[
            (sub: 'title', el: () => inside(_emptyText).single),
            (sub: 'subtitle', el: () => inside(st.key == 'EMPTYS' ? _emptySub1 : _emptySubM).single),
            if (st.key == 'EMPTYS')
              (sub: 'entry', el: () => textOf(targets().first))
            else ...[
              (sub: 'row1', el: () => textOf(targets()[0], last: true)),
              (sub: 'row2', el: () => textOf(targets()[1], last: true)),
            ],
          ],
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
          final cov = k.sub == 'res' ? (inside(_err).isNotEmpty && overlayN(_err) > 0) : (_hit(rr, toastFace()) || _hit(rr, bandFace()));
          final inClip = inR(clip, rr), inScreen = inR(screen, rr);
          final alive = resN() > 0;
          _out('D413 $tok read ${k.sub} inClip=$inClip inScreen=$inScreen covered=$cov ell=${m.ell} glyphX=${m.glyphX} lines=${m.lines} alive=$alive');
          if (!_before) {
            must('${k.sub} 전문 읽기 — clip · 화면 안 · 가림 0 · 말줄임 0 · 가로 0 · 결과 살아 있음',
                inClip && inScreen && !cov && !m.ell && m.glyphX == 0 && m.lines >= 1 && alive, '${_r(rr)} clip=${_r(clip)} $m');
          }
        }

        if (st.key != 'EMPTYM') {
          // 교체 — 앞 결과(f3)가 살아 있을 때 다시 실패 → 하나 · 새 결과 기준 수명(옛 timer 가 새 결과를 지우지 않는다)
          await pumpTo(f3.at, 2400);
          must('교체 직전 앞 결과 살아 있음', resN() == 1);
          final f4 = await failNow();
          final countAfter = resN();
          await pumpTo(f4.at, 3600);
          final aliveAfter = resN() == 1;
          await pumpTo(f4.at, 4200);
          final goneAfter = resN() == 0;
          _out('D413 $tok replace count=$countAfter alive=$aliveAfter gone=$goneAfter');
          must('연속 실패 = 결과 하나 · 새 결과 기준 수명', countAfter == 1 && aliveAfter && goneAfter, '$countAfter/$aliveAfter/$goneAfter');
          await settle(4);
        }

        // ④ 이동 뒤 receiver · 실제 탭(결과가 살아 있는 채)
        await failNow();
        final tg4 = targets();
        must('보호 대상 정확 ${subs.length}(④)', tg4.length == subs.length, '${tg4.length}');
        for (var i = 0; i < subs.length; i++) {
          await t.ensureVisible(_el(targets()[i]));
          await settle(4);
          final e = targets()[i]; // 같은 frame 재취득
          final rr = t.getRect(_el(e));
          final hit = hitAt(e, rr.center);
          final minOk = rr.height >= 47.99 && rr.width >= 47.99;
          final inScreen = inR(screen, rr);
          final inClip = inR(clipOf(e), rr);
          final cov = _hit(rr, toastFace());
          final alive = resN() > 0;
          final readsBefore = r.counts;
          await t.tapAt(rr.center);
          await settle(12);
          final dlg = find.byType(Dialog);
          final dialogN = dlg.evaluate().length;
          final titled = dialogN == 1 && find.descendant(of: dlg, matching: _vis('멤버 초대')).evaluate().isNotEmpty;
          if (dialogN == 1) {
            final closeIcon = find.descendant(of: dlg, matching: find.byIcon(Icons.close));
            final closeInk = find.ancestor(of: closeIcon, matching: find.byType(InkWell)).first;
            await t.tapAt(t.getRect(closeInk).center);
            await settle(12);
          }
          final closed = find.byType(Dialog).evaluate().isEmpty;
          final rereads = r.counts == readsBefore;
          _out('D413 $tok recv ${subs[i]} h=${rr.height.toStringAsFixed(1)} minOk=$minOk hit=$hit inScreen=$inScreen inClip=$inClip covered=$cov alive=$alive '
              'dialog=$dialogN titled=$titled closed=$closed rereads=$rereads');
          if (!_before) {
            must('${subs[i]} 이동 뒤 receiver ≥48 · 중앙 hit · 화면/clip 안 · 가림 0 · 결과 살아 있음', minOk && hit && inScreen && inClip && !cov && alive,
                '${_r(rr)} $hit $inClip $cov $alive');
          }
          must('${subs[i]} 실제 탭 → 초대 대화창 1(제목) → 닫힘 · 다시 읽기 0', dialogN == 1 && titled && closed && rereads, '$dialogN/$titled/$closed ${r.counts}');
        }

        if (st.key != 'EMPTYM') {
          // ⑤ 성공 새로고침 → 띠 0 · 내용 유지
          r.failMembers.remove('b1');
          await refresh();
          final kept = st.key == 'REFRESH' ? inside('김민준').length == 1 && inside('이도윤').length == 1 : inside(_emptyText).length == 1;
          final bandAfter = inside(_err).length;
          _out('D413 $tok clear band=$bandAfter toast=${overlayN(_err)} kept=$kept');
          must('성공 새로고침 → 띠 0 · 내용 유지', bandAfter == 0 && kept, '$bandAfter/$kept');
          if (!_before) must('strict 성공 새로고침 → overlay 0', overlayN(_err) == 0);

          // ⑥ 교차 — 다른 공용 안내 overlay 와 결과가 서로 지우거나 수명을 늘리지 않는다
          final w0 = now();
          while ((resN() > 0 || _vis(_other1).evaluate().isNotEmpty || _vis(_other2).evaluate().isNotEmpty) && ageMs(w0) < 6000) {
            await t.pump(const Duration(milliseconds: 50));
          }
          must('교차 선행 — 결과 · 다른 안내 0', resN() == 0 && _vis(_other1).evaluate().isEmpty && _vis(_other2).evaluate().isEmpty);
          ToastHelper.showInfo(_other1);
          await t.pump();
          final o0 = now();
          await t.pump(const Duration(milliseconds: 300));
          final fb = await failNow();
          final o = _vis(_other1).evaluate().length == 1;
          final res = resN() == 1;
          await pumpTo(o0, 2150);
          final oGone = _vis(_other1).evaluate().isEmpty;
          final bAlive1 = resN() == 1;
          ToastHelper.showInfo(_other2);
          await t.pump();
          final o20 = now();
          final b = resN() == 1;
          await pumpTo(fb.at, 3600);
          final bAlive = resN() == 1;
          final o2Alive = _vis(_other2).evaluate().length == 1;
          await pumpTo(fb.at, 4200);
          final bGone = resN() == 0;
          await pumpTo(o20, 2200);
          final o2Gone = _vis(_other2).evaluate().isEmpty;
          _out('D413 $tok cross o=$o res=$res oGone=$oGone bAlive1=$bAlive1 b=$b bAlive=$bAlive bGone=$bGone o2Alive=$o2Alive o2Gone=$o2Gone');
          must('교차 — 결과 생성 · 다른 안내 각자 수명 · 결과 만료', res && oGone && bAlive1 && bGone && o2Alive && o2Gone, '$res/$oGone/$bAlive1/$bGone/$o2Alive/$o2Gone');
          if (!_before) must('strict 교차 독립 — 결과가 다른 안내를 지우지 않음 · 다른 안내가 결과를 지우지 않음', o && b && bAlive, '$o/$b/$bAlive');
          await settle(4);
        }

        if (st.key == 'REFRESH') {
          // ⑦ 비영 offset → 실제 Loading frame · 목록 분리 → 같은 데이터 실패 → 만료 뒤 pixels · anchor ±0.5
          final lists = find.descendant(of: scaf, matching: find.byType(ListView));
          must('목록 정확 1', lists.evaluate().length == 1, '${lists.evaluate().length}');
          final scr = find.descendant(of: lists, matching: find.byType(Scrollable)).first;
          await t.drag(scr, const Offset(0, -200));
          await settle(10);
          final p0 = t.state<ScrollableState>(scr).position.pixels;
          final possible = p0 > 0.5;
          final a0 = t.getRect(_el(inside('김민준').single));
          final g = Completer<void>();
          r.gate = g;
          r.failMembers.add('b1');
          await tapRefresh();
          await t.pump(const Duration(milliseconds: 16));
          await t.pump(const Duration(milliseconds: 16));
          final loading = find.descendant(of: scaf, matching: find.byType(LoadingWidget)).evaluate().length == 1;
          final listGone = find.descendant(of: scaf, matching: find.byType(ListView)).evaluate().isEmpty;
          r.gate = null;
          g.complete();
          final f7 = await waitResult();
          await pumpTo(f7.at, 4200);
          await settle(4);
          final scr1 = find.descendant(of: find.descendant(of: scaf, matching: find.byType(ListView)), matching: find.byType(Scrollable)).first;
          final p1 = t.state<ScrollableState>(scr1).position.pixels;
          final a1 = t.getRect(_el(inside('김민준').single));
          final dy = a1.top - a0.top;
          final restored = (p1 - p0).abs() <= 0.5 && dy.abs() <= 0.5 && (a1.left - a0.left).abs() <= 0.5;
          _out('D413 $tok offset possible=$possible p0=${p0.toStringAsFixed(1)} loading=$loading listGone=$listGone p1=${p1.toStringAsFixed(1)} '
              'dy=${dy.toStringAsFixed(2)} restored=$restored');
          must('읽기 보류 중 실제 Loading frame · 목록 분리', loading && listGone, '$loading/$listGone');
          if (!_before) must('strict 같은 데이터 실패 · 결과 만료 뒤 pixels · anchor ±0.5', restored, '$p0→$p1 dy=$dy');
        }

        // ⑧ 결과가 살아 있을 때 route 이탈 → 다음 화면 결과 수 → 원 만료 시각 뒤 추가 pump · 예외 0
        final f8 = await failNow();
        final aliveX = resN() == 1;
        navigatorKey.currentState!.pop();
        await settle(12);
        final goneX = find.byType(MemberManagementScreen).evaluate().isEmpty;
        final left = _vis(_err).evaluate().length;
        await pumpTo(f8.at, 4600);
        await settle(4);
        final after = _vis(_err).evaluate().length;
        final excX = t.takeException();
        _out('D413 $tok exit alive=$aliveX gone=$goneX left=$left after=$after exc=${excX != null}');
        must('이탈 — 결과 살아 있음 · 화면 사라짐 · 원 만료 뒤 결과 0 · 예외 0', aliveX && goneX && after == 0 && excX == null, '$aliveX/$goneX/$after $excX');
        if (!_before) must('strict 이탈 → 다음 화면 결과 0', left == 0, '$left');

        final exc = t.takeException();
        _out('D413 $tok done state=${st.key} mode=$mode captures=$captures biz=$nBiz overflows=${overflows.length} exc=${exc != null}');
        await t.pumpWidget(const SizedBox.shrink());
        await settle(4);
        expect(exc, isNull);
        expect(overflows, isEmpty, reason: '$tok 넘침');
      });
    }
  }
}
