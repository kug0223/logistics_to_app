// [S024 표시 셀 p3 · 판정52] '취소' = 확인창 진입 중립(textSecondary) · F52-1 ONE 끝 실패 띠 실제 장면 3fail(두 모드 같은 전환 — TB 진한 · TA 옅은 띠).
// [S024 표시 셀 p2 · 판정51] ONE 에 색 검사 추가 — 섹션 제목 중립 · 막대 0 · 초대 카드 흰 면/중립 테두리 · 시계 칸/안내 따뜻한 경고 · 취소 errorDark · 대비 ≥ 4.5.
// [S024 초대 · DU415 · 판정48 (가) · 판정50 §5] 팀원 관리 초대 행동 — 떠 있는 FAB 대신 사업장 머리 옆 '+ 멤버 초대' 글자 행동 · 정상 단일 빈 화면은 공용 주 버튼.
//   새 파일 · 정확 6 public(W 392x844@1.0 · B 320x640@2.0 × ONE · MULTI · EMPTY) · 캡처 4 단계(× W/B = 8쌍).
//   하네스: du1_s024_band_h2 와 같은 fake core · _Provider(BUSINESS_ADMIN 고정) · 읽기 seam · 전역 navigatorKey 홈 위 push. 쓰기 · 검색 · 초대 전송 0(대화창은 열고 닫기만).
//   모드: DU_BEFORE_OBSERVE=415 이면 before(현행 da66f1b0 — FAB 1 · 말단 +72 · 빈 진입 테두리형 관측), 아니면 strict(후보).
//   ONE  : 첫 화면 FAB 수 · 머리 초대 수 · 말단 여분 · 머리 행동 줄(같은 줄/다음 줄) · 머리 묶음 안(첫 섹션 머리 위) · receiver ≥48 · 중앙 hit · 화면 안 · 글 전문(말줄임 0 · 가로 0)
//          → 실제 탭(strict 머리 행동 / before FAB) → 대화창 '멤버 초대' 1 → 닫기 → 다시 읽기 0 → 끝까지 끌어 마지막 카드 viewport 안 · FAB 겹침
//   MULTI: FAB 0 · 머리 단일 행동 0 · 사업장별 '초대' 2(두 모드 같음) → 첫 '초대' 실제 탭 → 대화창 → 닫기
//   EMPTY: 정상 단일 빈 화면 진입 1 · 채운 brand 면(strict) · 높이 ≥52 · 전체 폭 · 중앙 hit → 실제 탭 → 대화창 → 닫기
//   SubAdmin 은 이 fake(BUSINESS_ADMIN 고정)에서 시험하지 않는다(화면 진입 가드 · 머리 행동 분기 코드 보존만).
//   출력 줄: lkit 선언형 계약 'D415 <tok> <kind> k=v …' — 값 공백 0.
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
import 'package:ALfit/utils/responsive_helper.dart';

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
const _pendHdr = '초대 대기 중 (1건)';
const _err = '멤버 목록을 불러오지 못했어요';

class _Reads {
  _Reads({required this.biz, this.members = const {}, this.invites = const {}});

  final List<BusinessModel> biz;
  final Map<String, List<BusinessMemberModel>> members;
  final Map<String, List<MemberInvitationModel>> invites;
  // [F52-1] 다음 members 읽기만 실패(H-2 시험과 같은 전환)
  final failMembers = <String>{};
  var bizCalls = 0, memberCalls = 0, inviteCalls = 0;

  MemberManagementReads get reads => MemberManagementReads(
        businessesByIds: (ids) async {
          bizCalls++;
          return [for (final b in biz) if (ids.contains(b.id)) b];
        },
        members: (id) async {
          memberCalls++;
          if (failMembers.contains(id)) throw StateError('DU415 fake members 실패 $id');
          return members[id] ?? const [];
        },
        sentPendingInvitations: (id) async {
          inviteCalls++;
          return invites[id] ?? const [];
        },
      );

  String get counts => '$bizCalls/$memberCalls/$inviteCalls';
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '415';
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

/// 로컬 조판 측정(406 · 407 · 413 · 414 와 같은 규칙): 낱말 분절 · 가시 가로 초과 · 말줄임 · 줄 수.
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

// [판정51] 기대 색(시험 안 값 — TB 기준 app_colors 에는 새 토큰이 없어 이름으로 참조하지 않는다)
const _amberSurface = Color(0xFFFEEAC5);
const _amberInk = Color(0xFF702601);

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
          (_) async => codec.encodeMessage(<Object?>['du415.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du415.fake.$m'), (_) async => null);
    }
  });

  const views = [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const states = [
    (key: 'ONE', title: '한 사업장 목록 — 머리 옆 멤버 초대 글자 행동 · FAB 0 · 말단 여분 0'),
    (key: 'MULTI', title: '여러 사업장 목록 — 사업장별 초대 유지 · 단일 행동 0'),
    (key: 'EMPTY', title: '정상 빈 화면 — 공용 주 버튼 초대 진입'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S024I-${v.id}-${st.key} ${st.title}', (t) async {
        final tok = 'S024I-${v.id}-${st.key}';
        final mode = _before ? 'before' : 'strict';
        _out('D415 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
        List<Element> buttonsWith(String label) => [
              for (final e in find.descendant(of: scaf, matching: find.byWidgetPredicate((w) => w is TextButton), skipOffstage: false).evaluate())
                if (_under(e, (w) => w is Text).any((x) => _vt(x.widget) == label)) e
            ];
        int fabN() => find.byType(FloatingActionButton).evaluate().length;
        bool hitAt(Element target, Offset p) {
          final hr = HitTestResult();
          WidgetsBinding.instance.hitTestInView(hr, p, t.view.viewId);
          final ro = target.findRenderObject();
          return hr.path.any((e) => e.target == ro);
        }

        Rect clipOf(Element e) {
          final sc = _ancestor(e, (w) => w is Scrollable);
          return sc == null ? screen : t.getRect(_el(sc));
        }

        // 실제 탭 → 초대 대화창 '멤버 초대' 1 → 닫기 아이콘 → 대화창 0 · 다시 읽기 0
        Future<({int dialog, bool titled, bool closed, bool rereads})> tapToDialog(Element target, _Reads r) async {
          await t.ensureVisible(_el(target));
          await settle(4);
          final before = r.counts;
          await t.tapAt(t.getRect(_el(target)).center);
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
          return (dialog: dialogN, titled: titled, closed: find.byType(Dialog).evaluate().isEmpty, rereads: r.counts == before);
        }

        void tapLine(String target, ({int dialog, bool titled, bool closed, bool rereads}) x) {
          _out('D415 $tok tap target=$target dialog=${x.dialog} titled=${x.titled} closed=${x.closed} rereads=${x.rereads}');
          must('$target 실제 탭 → 초대 대화창 1(제목) → 닫힘 · 다시 읽기 0', x.dialog == 1 && x.titled && x.closed && x.rereads, '$x');
        }

        final r = st.key == 'ONE'
            ? _Reads(biz: [_biz('b1', _bizA)], members: {
                'b1': [_member('b1', 'm1', '김민준'), _member('b1', 'm2', '최지우'), _member('b1', 'm3', '박서연')],
              }, invites: {
                'b1': [_invite('b1', _bizA, 'i1', '이도윤')],
              })
            : st.key == 'MULTI'
                ? _Reads(biz: [_biz('b1', _bizA), _biz('b2', _bizB)], members: {
                    'b1': [_member('b1', 'm1', '김민준')],
                  })
                : _Reads(biz: [_biz('b1', _bizA)]);
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

        // 단일 사업장 머리 이름 = 가장 가까운 Row 에 storefront 아이콘이 있는 '강남 물류센터'(406 과 같은 판별 — 초대 카드 등 다른 곳 이름과 구별)
        Element? headName() {
          for (final e in inside(_bizA)) {
            final row = _ancestor(e, (w) => w is Row);
            if (row != null && _under(row, (w) => w is Icon && w.icon == Icons.storefront_outlined).isNotEmpty) return e;
          }
          return null;
        }

        if (st.key == 'ONE') {
          must('목록 — 사업장 머리 · 멤버 · 초대 대기', headName() != null && inside('김민준').length == 1 && inside('이도윤').length == 1);
          // 말단 여분 = ListView 아래 padding − (기본 listPadding + 하단 inset)
          final lv = find.descendant(of: scaf, matching: find.byType(ListView));
          final pad = (t.widget<ListView>(lv.first).padding as EdgeInsets?)?.bottom ?? -1;
          final base = ResponsiveHelper.listPadding(t.element(lv.first)).bottom + MediaQuery.paddingOf(t.element(lv.first)).bottom;
          final extra = pad - base;
          final heads = buttonsWith('멤버 초대');
          final fab = fabN();
          var line = 'none', inGroup = '-', h = '-', minOk = '-', hit = '-', inScreen = '-', ell = '-', glyphX = '-', lines = '-';
          if (heads.length == 1) {
            final e = heads.single;
            final rr = t.getRect(_el(e));
            final nameEl = headName()!;
            final nameRow = _ancestor(nameEl, (w) => w is Row);
            final nr = t.getRect(_el(nameRow ?? nameEl));
            final overlapY = rr.top < nr.bottom - 0.5 && rr.bottom > nr.top + 0.5;
            line = overlapY ? 'same' : (rr.top >= nr.bottom - 0.5 ? 'next' : 'other');
            final firstHdr = inside(_pendHdr);
            // 머리 묶음 안 = 이름 줄과 같은 줄 또는 바로 다음 줄 · 첫 섹션 머리보다 위(터치 영역 48 이 이름 줄보다 위로 나올 수 있어 top 비교는 하지 않는다)
            inGroup = '${firstHdr.length == 1 && rr.bottom <= t.getRect(_el(firstHdr.single)).top + 0.5 && (line == 'same' || line == 'next')}';
            h = rr.height.toStringAsFixed(1);
            minOk = '${rr.height >= 47.99 && rr.width >= 47.99}';
            hit = '${hitAt(e, rr.center)}';
            inScreen = '${inR(screen, rr) && inR(clipOf(e), rr)}';
            final label = _under(e, (w) => w is Text).where((x) => _vt(x.widget) == '멤버 초대').single;
            final rp = t.renderObject<RenderParagraph>(find.descendant(of: _el(label), matching: find.byType(RichText, skipOffstage: false), matchRoot: true, skipOffstage: false).first);
            final m = _measure(rp);
            ell = '${m.ell}';
            glyphX = '${m.glyphX}';
            lines = '${m.lines}';
          }
          _out('D415 $tok head fab=$fab invite=${heads.length} pad=${extra.toStringAsFixed(1)} line=$line inGroup=$inGroup h=$h minOk=$minOk hit=$hit '
              'inScreen=$inScreen ell=$ell glyphX=$glyphX lines=$lines');
          if (_before) {
            must('before: FAB 1 · 머리 초대 0 · 말단 +72', fab == 1 && heads.isEmpty && (extra - 72).abs() < 0.01, '$fab/${heads.length}/$extra');
          } else {
            must('strict: FAB 0 · 머리 초대 1 · 말단 여분 0 · 머리 묶음 안 · receiver ≥48 · 중앙 hit · 화면/clip 안 · 글 말줄임 0 · 가로 0',
                fab == 0 && heads.length == 1 && extra.abs() < 0.01 && inGroup == 'true' && minOk == 'true' && hit == 'true' && inScreen == 'true' &&
                    ell == 'false' && glyphX == '0',
                '$fab/${heads.length}/$extra/$line/$inGroup/$h/$hit/$inScreen/$ell/$glyphX');
          }
          // [판정51] S024 색 — 섹션 제목 중립(textPrimary · 막대 0) · 초대 대기 카드 흰 면/중립 테두리 · 작은 시계 칸 · 안내 글 따뜻한 경고 · 취소 errorDark · 대비 ≥ 4.5
          final hdrTexts = [for (final x in [_pendHdr, '등록된 멤버 (3명)']) ...inside(x)];
          final hdrPrimary = hdrTexts.length == 2 && hdrTexts.every((e) => (e.widget as Text).style?.color == AppColors.textPrimary);
          var bars = 0;
          for (final e in hdrTexts) {
            final pad = _ancestor(e, (w) => w is Padding);
            if (pad != null) bars += _under(pad, (w) => w is Container && w.decoration is BoxDecoration).length;
          }
          final cardEl = _ancestor(inside('이도윤').single,
              (w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).borderRadius == BorderRadius.circular(12));
          final deco = cardEl == null ? null : (cardEl.widget as Container).decoration as BoxDecoration;
          final cardBg = deco?.color;
          final borderC = deco?.border is Border ? (deco!.border as Border).top.color : null;
          final card = cardBg == AppColors.surface ? 'white' : (cardBg == AppColors.warningBg ? 'yellow' : 'other');
          final borderKind = borderC == AppColors.grey200 ? 'neutral' : 'other';
          final avatars = cardEl == null ? const <Element>[] : _under(cardEl, (w) => w is CircleAvatar);
          final tileBg = avatars.isEmpty ? null : (avatars.first.widget as CircleAvatar).backgroundColor;
          final clocks = cardEl == null ? const <Element>[] : _under(cardEl, (w) => w is Icon && w.icon == Icons.schedule);
          final clockC = clocks.isEmpty ? null : (clocks.first.widget as Icon).color;
          final tile = (tileBg == _amberSurface && clockC == _amberInk) ? 'amber' : 'other';
          final metas = cardEl == null ? const <Element>[] : _under(cardEl, (w) => w is Text && _vt(w).startsWith('초대 발송'));
          final metaColor = metas.isEmpty ? null : (metas.first.widget as Text).style?.color;
          final cancels = cardEl == null ? const <Element>[] : _under(cardEl, (w) => w is Text && _vt(w) == '취소');
          final cancelColor = cancels.isEmpty ? null : (cancels.first.widget as Text).style?.color;
          final bgC = cardBg ?? AppColors.surface;
          final metaCr = metaColor == null ? 0.0 : _contrast(metaColor, bgC);
          final cancelCr = cancelColor == null ? 0.0 : _contrast(cancelColor, bgC);
          final meta = metaColor == _amberInk ? 'amber' : 'other';
          final cancel = cancelColor == AppColors.textSecondary
              ? 'neutral'
              : (cancelColor == AppColors.errorDark ? 'errorDark' : (cancelColor == AppColors.errorMedium ? 'errorMedium' : 'other'));
          _out('D415 $tok color hdr=${hdrPrimary ? 'primary' : 'other'} bar=$bars card=$card border=$borderKind tile=$tile meta=$meta '
              'metaC=${metaCr.toStringAsFixed(2)} cancel=$cancel cancelC=${cancelCr.toStringAsFixed(2)}');
          if (!_before) {
            must('strict 색 — 제목 중립 · 막대 0 · 흰 카드 · 중립 테두리 · 시계 칸/안내 따뜻한 경고 · 취소 진입 중립(판정52) · 대비 ≥ 4.5',
                hdrPrimary && bars == 0 && card == 'white' && borderKind == 'neutral' && tile == 'amber' && meta == 'amber' && cancel == 'neutral' &&
                    metaCr >= 4.5 && cancelCr >= 4.5,
                '$hdrPrimary/$bars/$card/$borderKind/$tile/$meta/$metaCr/$cancel/$cancelCr');
          }
          await shot('1top', '한 사업장 첫 화면');
          final target = _before ? find.byType(FloatingActionButton).evaluate().single : heads.single;
          tapLine(_before ? 'fab' : 'head', await tapToDialog(target, r));
          // 끝까지 끌어 마지막 카드(박서연) — viewport 안 · FAB 겹침
          final sf = find.descendant(of: lv, matching: find.byType(Scrollable)).first;
          final pos = t.state<ScrollableState>(sf).position;
          var drags = 0;
          while (pos.pixels < pos.maxScrollExtent - 0.5 && drags < 20) {
            await t.drag(sf, const Offset(0, -300));
            await settle(6);
            drags++;
          }
          final lastR = t.getRect(_el(inside('박서연').single));
          final lastIn = inR(t.getRect(sf), lastR);
          final fabF = find.byType(FloatingActionButton);
          final fabR = fabF.evaluate().isEmpty ? null : t.getRect(fabF);
          final overlap = _hit(lastR, fabR) ? 1 : 0;
          _out('D415 $tok end lastIn=$lastIn overlap=$overlap fab=${fabR == null ? '-' : _r(fabR)}');
          if (!_before) must('strict 말단 마지막 카드 viewport 안 · FAB 0 · 겹침 0', lastIn && overlap == 0 && fabR == null, '$lastIn/$overlap');
          await shot('2end', '한 사업장 말단');
          // [F52-1 · 판정52 §5] 실패 띠 실제 장면 — 처음으로 돌린 뒤 다음 members 읽기만 실패 · 실제 새로고침 탭 → 결과가 처음 보이는 frame 을 3fail 로.
          //   두 모드 같은 fixture/전환: TB(da66f1b0) 진한 errorDark 면 · 흰 글/아이콘, TA 옅은 errorBg 면 · errorDark 글/아이콘. 수명 · 도달 · 복구는 H-2 회귀가 본다.
          var ups = 0;
          while (pos.pixels > 0.5 && ups < 20) {
            await t.drag(sf, const Offset(0, 300));
            await settle(6);
            ups++;
          }
          must('처음으로 복귀', pos.pixels <= 0.5, '${pos.pixels}');
          r.failMembers.add('b1');
          final rf = find.byTooltip('새로고침');
          must('상단 새로고침 정확 1', rf.evaluate().length == 1, '${rf.evaluate().length}');
          await t.tap(rf);
          var fsteps = 0;
          do {
            await t.pump(const Duration(milliseconds: 16));
            fsteps++;
          } while (_vis(_err).evaluate().isEmpty && fsteps < 60);
          final bandEls = inside(_err);
          final allN = _vis(_err).evaluate().length;
          final overlayN = allN - bandEls.length;
          final ctx = headName() != null && inside('이도윤').length == 1 && inside('김민준').length == 1;
          Element? faceEl;
          if (bandEls.length == 1) {
            faceEl = _ancestor(bandEls.single, (w) {
              if (w is! Container || w.decoration is! BoxDecoration) return false;
              final c = (w.decoration as BoxDecoration).color;
              return c == AppColors.errorDark || c == AppColors.errorBg;
            });
          }
          final faceC = faceEl == null ? null : ((faceEl.widget as Container).decoration as BoxDecoration).color;
          Color? inkC, iconC;
          if (bandEls.length == 1) {
            final rp = t.renderObject<RenderParagraph>(
                find.descendant(of: _el(bandEls.single), matching: find.byType(RichText, skipOffstage: false), matchRoot: true, skipOffstage: false).first);
            inkC = rp.text.style?.color;
            final row = _ancestor(bandEls.single, (w) => w is Row);
            final icons = row == null ? const <Element>[] : _under(row, (w) => w is Icon);
            iconC = icons.isEmpty ? null : (icons.first.widget as Icon).color;
          }
          String kind(Color? c) => c == AppColors.errorDark ? 'dark' : (c == AppColors.errorBg ? 'light' : (c == AppColors.textOnDark ? 'white' : 'other'));
          final fcr = (inkC == null || faceC == null) ? 0.0 : _contrast(inkC, faceC);
          _out('D415 $tok fail band=${bandEls.length} overlay=$overlayN ctx=$ctx face=${kind(faceC)} ink=${kind(inkC)} icon=${kind(iconC)} '
              'cr=${fcr.toStringAsFixed(2)} steps=$fsteps');
          must('실패 첫 frame — 결과 띠 1 · overlay 0 · 사업장 머리 · 초대 카드 · 멤버 맥락 유지', bandEls.length == 1 && overlayN == 0 && ctx,
              '${bandEls.length}/$overlayN/$ctx');
          if (_before) {
            must('before 실패 띠 — 진한 errorDark 면 · 흰 글/아이콘', kind(faceC) == 'dark' && kind(inkC) == 'white' && kind(iconC) == 'white', '$faceC $inkC $iconC');
          } else {
            must('strict 실패 띠 — 옅은 errorBg 면 · errorDark 글/아이콘 · 대비 ≥ 4.5', kind(faceC) == 'light' && kind(inkC) == 'dark' && kind(iconC) == 'dark' && fcr >= 4.5,
                '$faceC $inkC $iconC ${fcr.toStringAsFixed(2)}');
          }
          await shot('3fail', '새로고침 실패 결과 띠(첫 frame)');
        } else if (st.key == 'MULTI') {
          final heads = buttonsWith('멤버 초대');
          final rows = buttonsWith('초대');
          _out('D415 $tok multi fab=${fabN()} single=${heads.length} rows=${rows.length}');
          must('여러 사업장 — FAB 0 · 단일 머리 행동 0 · 사업장별 초대 2', fabN() == 0 && heads.isEmpty && rows.length == 2, '${fabN()}/${heads.length}/${rows.length}');
          await shot('1top', '여러 사업장 첫 화면');
          rows.sort((a, b) => t.getRect(_el(a)).top.compareTo(t.getRect(_el(b)).top));
          tapLine('row', await tapToDialog(rows.first, r));
        } else {
          // 정상 단일 빈 화면 진입: InkWell 안 글이 정확히 ['멤버 초대']
          final inks = [
            for (final ink in find.descendant(of: scaf, matching: find.byType(InkWell), skipOffstage: false).evaluate())
              if (_under(ink, (w) => w is Text).length == 1 && _vt(_under(ink, (w) => w is Text).single.widget) == '멤버 초대') ink
          ];
          var filled = false, h = 0.0, full = false, hit = false, inScreen = false;
          if (inks.length == 1) {
            final ink = inks.single;
            final box = _ancestor(ink, (w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == AppColors.brand);
            filled = box != null;
            final rr = t.getRect(_el(box ?? ink));
            h = rr.height;
            // 전체 폭 = 바로 위 좌우 여백 칸(Padding · horizontal 16·s)을 꽉 채움 — 빈 상태 위젯 자체 여백이 있어 화면 폭과 비교하지 않는다
            final side = ResponsiveHelper.spacing(t.element(scaf), 16);
            final padEl = _ancestor(box ?? ink, (w) => w is Padding);
            final padW = padEl == null ? 0.0 : t.getRect(_el(padEl)).width;
            full = padEl != null && (rr.width - (padW - 2 * side)).abs() <= 1.0;
            hit = hitAt(ink, rr.center);
            inScreen = inR(screen, rr) && inR(clipOf(ink), rr);
          }
          final minOk = h >= 51.99;
          _out('D415 $tok entry single=${inks.length} filled=$filled h=${h.toStringAsFixed(1)} minOk=$minOk full=$full hit=$hit inScreen=$inScreen');
          if (_before) {
            must('before: 빈 진입 1 · 테두리형(채움 0)', inks.length == 1 && !filled, '${inks.length}/$filled');
          } else {
            must('strict: 빈 진입 1 · brand 채움 · 높이 ≥52 · 전체 폭 · 중앙 hit · 화면/clip 안', inks.length == 1 && filled && minOk && full && hit && inScreen,
                '${inks.length}/$filled/$h/$full/$hit/$inScreen');
          }
          await shot('1empty', '정상 빈 화면');
          tapLine('entry', await tapToDialog(inks.single, r));
        }

        final exc = t.takeException();
        _out('D415 $tok done state=${st.key} mode=$mode captures=$captures overflows=${overflows.length} exc=${exc != null}');
        await t.pumpWidget(const SizedBox.shrink());
        await settle(4);
        expect(exc, isNull);
        expect(overflows, isEmpty, reason: '$tok 넘침');
      });
    }
  }
}
