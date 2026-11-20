// [DU406 r1 S024] 팀원 관리 국소 배치 · 스타일 · 문구 · FAB — 교정 시험(소급 34 §3). 원 aea671a3 은 보존한다. 새 파일 · 정확 10 public(W/B × 5 상태).
//   하네스는 401 과 같다(읽기 seam fake · fake core · 가짜 auth · navigatorKey · 누르지 않음 · begin 줄 child env 12 키).
//   모드: DU_BEFORE_OBSERVE=406 이면 before(현행 5fdb0079 — 옛 값 정확), 아니면 strict(후보 b2a6f0e9 — 새 값 · 기하).
//   교정(소급 34 §3):
//   ① 카드 귀속 필수 집합 — fixture 별 카드(멤버/초대) · 머리 · 인라인 빈 문구를 고정한다. 카드 안 보이는 글 다중집합 = 기대(누락 · 추가 0)이고
//      알 수 없는 카드 0이다. 항목별 존재 · 원문 · 조판 검사 완료 · 가시 확인 집합을 따로 쌓아 끝에서 필수 집합과 정확 대조한다
//      (finder 0개 · 검사 0회로는 통과할 수 없다).
//   ② top/end 만이 아니라 유한 drag(120px, 최대 60) 매 위치에서 검사한다. 항목 rect ⊂ 실제 목록 viewport · onstage(skipOffstage:true) · 크기 > 0 이면
//      조판 검사 완료, 거기에 FAB 비겹침까지면 가시 확인이다. 모든 위치의 FAB 겹침 0 은 요구하지 않는다(정보별 한 번 이상).
//   ③ ONE 말단: 마지막 박서연 카드의 이름 · 전화 · 공고/급여 칩 · 메뉴 정확 5 — 누락 0 · viewport 안 · FAB 비겹침(strict).
//      메뉴는 충분히 보이는(FAB 비겹침) 위치에서 receiver 48 · 중앙 hit · 이웃 글 비겹침을 본다.
//   ④ ERROR members/invites/multi: 읽기 · 부분 실패 · 정상 빈 분리 보존 + 초대 진입 단일 1 / 다중 2(사업장 이름 귀속 · 위→아래 순서).
//   ⑤ begin env 12 키(DU406_MANIFEST 포함).
//   보존(두 모드 엄격): SubAdmin 직접 route → pop · 읽기 0 · 읽기 호출 수 · 정상 빈 ≠ 실패 · 두 사업장 중 한 곳 실패 → 전체 오류 · 넘침 0 · 예외 0 · 쓰기 조작 0.
// [S024 표시 셀 p2 · 판정51] 초대 대기 카드 strict = 흰 면(before 노란 면 그대로).
// [S024 초대 추종 · DU415] FAB 제거 · 머리 옆 '+ 멤버 초대' · 말단 +72 제거 · ERROR 정책 B(본문 1 · 토스트 0) — strict 만. before 그대로.
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
  _Provider({required this.subAdmin, required this.ids});

  final bool subAdmin;
  final List<String> ids;

  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김사장',
        email: 'u1@alfit.local',
        role: subAdmin ? UserRole.USER : UserRole.BUSINESS_ADMIN,
        managedBusinessIds: subAdmin ? const [] : ids,
        subAdminBusinessIds: subAdmin ? ids : const [],
      );
  @override
  bool get isSubAdmin => subAdmin;
  @override
  bool get isBusinessAdmin => !subAdmin;
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

BusinessMemberModel _member(String biz, String uid, String name, {String? phone, MemberPermissions perms = const MemberPermissions()}) =>
    BusinessMemberModel(uid: uid, businessId: biz, name: name, phone: phone, permissions: perms, addedAt: DateTime(2026, 11, 1), addedBy: 'u1');

MemberInvitationModel _invite(String biz, String bizName, String id, String name, {String? phone}) => MemberInvitationModel(
      id: id,
      businessId: biz,
      businessName: bizName,
      targetUid: 't_$id',
      targetName: name,
      targetPhone: phone,
      invitedBy: 'u1',
      invitedByName: '김사장',
      permissions: const MemberPermissions(canManageTo: true),
      status: InvitationStatus.pending,
      createdAt: DateTime(2026, 11, 15, 10),
    );

const _longBiz = '[QA] 아주 긴 이름의 강남 물류센터 평택 제2공장 냉장 분류동';
const _longBiz2 = '[QA] 아주 긴 이름의 송파 신선 분류센터 제3공장 냉동 보관동';
const _shortBiz = '강남 물류센터';
const _longMember = '알렉산드라 크리스티나 페트로바 바실리예브나';
const _longInvite = '모하메드 압둘라 알라시드 빈 칼리드';
const _phones = ['010-1234-5678', '010-2222-3333', '010-9876-5432'];
const _permLabels = ['공고', '근무자', '급여', '계약서', '이체취소'];
const _emptyText = '등록된 멤버가 없습니다';
const _errSub = '아래에서 새 멤버를 초대하거나 새로고침을 시도해 보세요';
const _emptySub = '멤버를 초대하고 사업장을 함께 관리해보세요';
final _metaRe = RegExp(r'^초대 발송 (방금 전|\d+시간 전|\d+일 전) · 3일 내 미수락 시 자동 만료$');

class _Reads {
  _Reads({required this.biz, this.members = const {}, this.invites = const {}, this.failMembers = const {}, this.failInvites = const {}, this.gate});

  final List<BusinessModel> biz;
  final Map<String, List<BusinessMemberModel>> members;
  final Map<String, List<MemberInvitationModel>> invites;
  final Set<String> failMembers;
  final Set<String> failInvites;
  final Completer<void>? gate;
  var bizCalls = 0, memberCalls = 0, inviteCalls = 0;

  MemberManagementReads get reads => MemberManagementReads(
        businessesByIds: (ids) async {
          bizCalls++;
          if (gate != null) await gate!.future;
          return [for (final b in biz) if (ids.contains(b.id)) b];
        },
        members: (id) async {
          memberCalls++;
          if (failMembers.contains(id)) throw StateError('DU406 fake members 실패 $id');
          return members[id] ?? const [];
        },
        sentPendingInvitations: (id) async {
          inviteCalls++;
          if (failInvites.contains(id)) throw StateError('DU406 fake 초대 조회 실패 $id');
          return invites[id] ?? const [];
        },
      );

  String get counts => '$bizCalls/$memberCalls/$inviteCalls';
}

/// fixture 카드 — 카드 식별자(id)와 카드 안에 있어야 하는 정보.
class _Card {
  _Card(this.id, this.name, {this.invite = false, this.phone, this.chips = const [], this.menu = false, this.biz});

  final String id;
  final String name;
  final bool invite;
  final String? phone;
  final List<String> chips;
  final bool menu;
  final String? biz;

  /// 필수 항목 키(카드 귀속).
  List<String> get keys => [
        '$id:name',
        if (phone != null) '$id:phone',
        if (invite) '$id:meta',
        if (!invite && chips.isEmpty) '$id:none',
        if (!invite)
          for (final c in chips) '$id:chip:$c',
        if (menu) '$id:menu',
        if (biz != null) '$id:biz',
      ];

  /// 카드 안 보이는 글 다중집합(정렬) — 아바타 글자 · '취소' 포함, 안내는 '<meta>' 로 정규화.
  List<String> get texts => [
        if (!invite) (name.isNotEmpty ? name[0] : '?'),
        name,
        if (phone != null) phone!,
        if (invite) '<meta>',
        if (invite) '취소',
        if (biz != null) biz!,
        if (!invite && chips.isEmpty) '권한 없음',
        if (!invite) ...chips,
      ]..sort();
}

/// 카드 밖 머리 · 인라인 빈 문구.
class _Hdr {
  _Hdr(this.key, this.text, this.kind, {this.anchor});

  final String key; // hdr:b1 · bizhdr:b1 · empty:b2
  final String text;
  final String kind; // single · multi · empty
  final String? anchor; // empty 가 속한 사업장 머리 글
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '406';
final String _manifest = Platform.environment['DU406_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST', 'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU296_PHASE'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');
const _titleOld = '멤버 관리';
const _titleNew = '팀원 관리';
const _errOld = '멤버 목록을 불러오지 못했습니다';
const _errNew = '멤버 목록을 불러오지 못했어요';
const _wj = '\u2060';
const _zw = '\u200B';
const _nb = '\u00A0';
bool _visible(String ch) => ch != ' ' && ch != _nb && ch != '\n' && ch != _wj && ch != _zw;

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _hex(Color? c) => '0x${(c ?? Colors.transparent).toARGB32().toRadixString(16)}';

String _r(Rect r) => '${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)},${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)}';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

// 실제 바탕 — 401 과 같은 규칙
Color _bgOf(Element e) {
  final layers = <Color>[];
  Color? base;
  Decoration? lastDeco;
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is Container && w.decoration != null && identical(w.decoration, lastDeco)) {
      return true;
    }
    if (w is DecoratedBox) lastDeco = w.decoration;
    if (w is Container && w.decoration is BoxDecoration) {
      c = (w.decoration! as BoxDecoration).color;
    } else if (w is Container && w.color != null) {
      c = w.color;
    } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
      c = (w.decoration as BoxDecoration).color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color ?? Theme.of(a).colorScheme.surface;
    } else if (w is ColoredBox) {
      c = w.color;
    } else if (w is Scaffold) {
      c = w.backgroundColor ?? Theme.of(a).scaffoldBackgroundColor;
    }
    if (c == null || c.a == 0) return true;
    if (c.a >= 0.999) {
      base = c;
      return false;
    }
    layers.add(c);
    return true;
  });
  var out = base ?? Colors.white;
  for (final l in layers.reversed) {
    out = Color.alphaBlend(l, out);
  }
  return out;
}

/// 로컬 조판 측정(401 · DU400 과 같은 규칙): 낱말 분절 · 가시 가로 초과 · 말줄임 · 줄 수.
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

String _vt(Widget w) => w is Text ? visibleText(w.data ?? w.textSpan?.toPlainText() ?? '') : '';

String _norm(String s) => _metaRe.hasMatch(s) ? '<meta>' : s;

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

Finder _vis(String text) => find.byWidgetPredicate((w) => w is Text && _vt(w) == text, skipOffstage: false);

Finder _el(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);

bool _onstage(Element e) => find.byElementPredicate((x) => identical(x, e)).evaluate().isNotEmpty;

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

bool _isCardDeco(Widget w) {
  if (w is! Container) return false;
  final d = w.decoration;
  return d is BoxDecoration && (d.color == AppColors.surface || d.color == AppColors.warningBg);
}

Element? _cardOf(Element e) => _ancestor(e, _isCardDeco);

List<Element> _under(Element scope, bool Function(Widget w) p) =>
    find.descendant(of: _el(scope), matching: find.byWidgetPredicate(p, skipOffstage: false), skipOffstage: false).evaluate().toList();

/// 가장 가까운 Row 안에 조건 위젯이 있는가(머리 귀속).
bool _rowHas(Element e, bool Function(Widget w) p) {
  final row = _ancestor(e, (w) => w is Row);
  return row != null && _under(row, p).isNotEmpty;
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
          (_) async => codec.encodeMessage(<Object?>['du406.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du406.fake.$m'), (_) async => null);
    }
  });

  const views = [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const states = [
    (key: 'ONE', title: '한 사업장·제목·전화 전문·대비·메뉴 48·말단'),
    (key: 'MULTI', title: '여러 사업장·섹션·전화 전문·말단 여백 없음'),
    (key: 'LOADING', title: '읽기 대기·로딩·제목'),
    (key: 'ERROR', title: '조회 실패·해요체 본문(토스트 0)·빈 목록 구별'),
    (key: 'EMPTY', title: '정상 빈 목록·초대 진입·제목'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S024S-${v.id}-${st.key} ${st.title}', (t) async {
        final tok = 'S024S-${v.id}-${st.key}';
        final mode = _before ? 'before' : 'strict';
        _out('D406 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
        void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        Future<void> settle([int n = 10]) async {
          for (var i = 0; i < n; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
        }

        var captures = 0;
        var subs = 0;
        var covers = 0;
        var prelude = '-';
        var readsStr = '-';
        final key = GlobalKey();
        final cond = {'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode};
        final scaf = find.byType(MemberManagementScreen);

        List<Element> texts(bool Function(String s) p) =>
            find.descendant(of: scaf, matching: find.byWidgetPredicate((w) => w is Text && p(_vt(w)), skipOffstage: false), skipOffstage: false)
                .evaluate()
                .toList();

        Future<void> open(_Reads r, {bool subAdmin = false, bool settleAll = true}) async {
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider<UserProvider>(create: (_) => _Provider(subAdmin: subAdmin, ids: [for (final b in r.biz) b.id])),
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
          if (settleAll) await settle(12);
        }

        Future<void> close() async {
          await t.pump(const Duration(seconds: 5));
          await t.pumpWidget(const SizedBox.shrink());
          await settle(4);
        }

        Future<void> shot(String id, String state) async {
          await vqCapture(t, key, '${tok}_$id', conditions: {...cond, 'state': state, 'fixture': st.key});
          captures++;
        }

        // 제목 — 모드별 정확 1, 다른 쪽 0
        void checkTitle() {
          final want = _before ? _titleOld : _titleNew;
          final other = _before ? _titleNew : _titleOld;
          final n = texts((s) => s == want).length;
          final o = texts((s) => s == other).length;
          _out('D406 $tok title want=${_before ? 'old' : 'new'} n=$n other=$o');
          must('제목 $want 정확 1 · $other 0', n == 1 && o == 0, '$n/$o');
        }

        // ListView 말단 여분(FAB 있는 ONE · LOADING 만 strict + 72, 그 밖 0)
        void checkPad(bool fab) {
          final lv = find.descendant(of: scaf, matching: find.byType(ListView));
          must('목록 ListView 존재', lv.evaluate().isNotEmpty);
          final pad = (t.widget<ListView>(lv.first).padding as EdgeInsets?)?.bottom ?? -1;
          final base = ResponsiveHelper.listPadding(t.element(lv.first)).bottom + MediaQuery.paddingOf(t.element(lv.first)).bottom;
          final extra = pad - base;
          final want = (!_before && fab) ? 72.0 : 0.0;
          _out('D406 $tok pad fab=$fab extra=${extra.toStringAsFixed(1)} want=${want.toStringAsFixed(1)}');
          must('목록 말단 여분 = ${want.toStringAsFixed(0)}', (extra - want).abs() < 0.01, '$extra');
        }

        Finder listScroll() {
          final all = find.descendant(of: scaf, matching: find.byType(Scrollable));
          final cands = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
              .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
              .toList()
            ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
          must('목록 세로 스크롤 주인 존재', cands.isNotEmpty);
          return cands.first;
        }

        // 머리 Text 찾기 — single: 가까운 Row 에 storefront 아이콘 · 카드 밖 / multi: 가까운 Row 에 '초대' 버튼 글
        Element? hdrEl(String text, String kind) {
          final xs = texts((s) => s == text);
          final hs = [
            for (final e in xs)
              if (kind == 'single'
                  ? (_rowHas(e, (w) => w is Icon && w.icon == Icons.storefront_outlined) && _cardOf(e) == null)
                  : _rowHas(e, (w) => w is Text && _vt(w) == '초대'))
                e
          ];
          must('$text 머리 후보 ≤ 1', hs.length <= 1, '${hs.length}');
          return hs.isEmpty ? null : hs.single;
        }

        // 유한 drag 훑기 — 매 위치에서 카드 귀속 · 원문 · 조판 · 가시 검사, 끝에서 필수 집합 정확 대조
        Future<void> sweep(String fx, List<_Card> cards, List<_Hdr> hdrs) async {
          final req = <String>{for (final c in cards) ...c.keys, for (final h in hdrs) h.key};
          final exists = <String>{}, text = <String>{}, measured = <String>{}, seen = <String>{};
          final sf = listScroll();
          final pos = t.state<ScrollableState>(sf).position;
          var p = 0;

          void scan() {
            final vp = t.getRect(sf);
            final fabF = find.byType(FloatingActionButton);
            final fab = fabF.evaluate().isEmpty ? null : t.getRect(fabF);
            bool inVp(Rect r) => r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5 && r.left >= vp.left - 0.5 && r.right <= vp.right + 0.5;
            bool clearFab(Rect r) {
              if (fab == null) return true;
              final x = r.intersect(fab);
              return !(x.width > 0.5 && x.height > 0.5);
            }

            void textItem(String k, Element e, String kind, {String? want}) {
              final w = e.widget as Text;
              final raw = _vt(w);
              exists.add(k);
              final labelKind = kind == 'name' || kind == 'phone' || kind == 'meta';
              final okText = (kind == 'meta' ? _metaRe.hasMatch(raw) : raw == want) && (_before || !labelKind || w.semanticsLabel == raw);
              must('$k 원문${_before ? '' : ' · 원문 label'}', okText, '"$raw" label=${w.semanticsLabel}');
              text.add(k);
              final r = t.getRect(_el(e));
              final rp = t.renderObject<RenderParagraph>(find.descendant(of: _el(e), matching: find.byType(RichText, skipOffstage: false), matchRoot: true, skipOffstage: false).first);
              if (!(inVp(r) && _onstage(e) && rp.size.width > 0 && rp.size.height > 0)) return;
              final m = _measure(rp);
              final col = rp.text.style?.color;
              final c = col == null ? 0.0 : _contrast(col, _bgOf(e));
              switch (kind) {
                case 'name':
                  if (!_before) must('strict 이름 말줄임 0 · 가로 0', !m.ell && m.glyphX == 0, '$k $m');
                case 'phone':
                  if (_before) {
                    must('before 전화 색 grey500', col == AppColors.grey500, '$k ${_hex(col)}');
                  } else {
                    must('strict 전화 전문 1줄 · 말줄임 0 · 가로 0 · 분절 0', m.lines == 1 && !m.ell && m.glyphX == 0 && m.bad == 0, '$k $m');
                    must('strict 전화 textSecondary · 대비 ≥ 4.5', col == AppColors.textSecondary && c >= 4.5, '$k ${_hex(col)} $c');
                  }
                case 'meta':
                  if (!_before) must('strict 초대 안내 분절 0 · 말줄임 0 · 가로 0', m.bad == 0 && !m.ell && m.glyphX == 0, '$k $m');
                case 'none':
                  must(_before ? 'before 권한 없음 grey400' : 'strict 권한 없음 textTertiary · ≥ 4.5',
                      _before ? col == AppColors.grey400 : (col == AppColors.textTertiary && c >= 4.5), '$k ${_hex(col)} $c');
                case 'hdr':
                  must(_before ? 'before 단일 머리 grey600' : 'strict 단일 머리 textSecondary · ≥ 4.5',
                      _before ? col == AppColors.grey600 : (col == AppColors.textSecondary && c >= 4.5), '$k ${_hex(col)} $c');
                default:
                  break; // chip · biz · bizhdr · empty — 기록만(범위 밖 표시)
              }
              if (measured.add(k)) {
                _out('D406 $tok item $fx $k measured pos=$p lines=${m.lines} bad=${m.bad} ell=${m.ell} glyphX=${m.glyphX} color=${_hex(col)} c=${c.toStringAsFixed(2)} label=${w.semanticsLabel == raw}');
              }
              if (clearFab(r) && seen.add(k)) _out('D406 $tok item $fx $k visible pos=$p rect=${_r(r)}');
            }

            void menuItem(String k, Element card) {
              final icons = _under(card, (w) => w is Icon && w.icon == Icons.more_vert);
              must('$k 메뉴 아이콘 정확 1', icons.length == 1, '${icons.length}');
              final inkEl = _ancestor(icons.single, (w) => w is InkWell);
              if (inkEl == null) {
                must('$k 메뉴 InkWell', false);
                return;
              }
              exists.add(k);
              text.add(k);
              final r = t.getRect(_el(inkEl));
              if (!(inVp(r) && _onstage(inkEl) && r.width > 0 && r.height > 0)) return;
              final col = (icons.single.widget as Icon).color;
              must(_before ? 'before 메뉴 아이콘 grey400' : 'strict 메뉴 아이콘 textTertiary', col == (_before ? AppColors.grey400 : AppColors.textTertiary), '$k ${_hex(col)}');
              if (measured.add(k)) _out('D406 $tok item $fx $k measured pos=$p size=${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)} color=${_hex(col)}');
              if (!clearFab(r)) return;
              final hr = HitTestResult();
              WidgetsBinding.instance.hitTestInView(hr, r.center, t.view.viewId);
              final hit = hr.path.any((x) => x.target == inkEl.renderObject);
              var over = 0;
              for (final te in _under(card, (w) => w is Text)) {
                final x = r.intersect(t.getRect(_el(te)));
                if (x.width > 0.5 && x.height > 0.5) over++;
              }
              if (_before) {
                must('before 메뉴 receiver < 48', r.width < 47.99 || r.height < 47.99, '$k $r');
              } else {
                must('strict 메뉴 receiver ≥ 48 · 중앙 hit · 이웃 글 비겹침', r.width >= 47.99 && r.height >= 47.99 && hit && over == 0, '$k $r hit=$hit over=$over');
              }
              if (seen.add(k)) _out('D406 $tok item $fx $k visible pos=$p size=${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)} hit=$hit over=$over');
            }

            var built = 0;
            for (final c in cards) {
              final ns = texts((s) => s == c.name);
              if (ns.isEmpty) continue;
              must('${c.id} 이름 Text 정확 1', ns.length == 1, '${ns.length}');
              final card = _cardOf(ns.single);
              if (card == null) {
                must('${c.id} 카드 귀속', false);
                return;
              }
              built++;
              final deco = ((card.widget as Container).decoration! as BoxDecoration).color;
              // [판정51] 초대 대기 카드도 strict 흰 면(멤버 카드와 같음) — before(DU406 당시)는 노란 면
              must('${c.id} 카드 바탕', deco == ((c.invite && _before) ? AppColors.warningBg : AppColors.surface), _hex(deco));
              final tels = _under(card, (w) => w is Text);
              final got = [for (final e in tels) _norm(_vt(e.widget))]..sort();
              must('${c.id} 카드 안 글 다중집합 = 기대(누락 · 추가 0)', _same(got, c.texts), '$got ≠ ${c.texts}');
              Element one(bool Function(String s) pr, String what) {
                final xs = [for (final e in tels) if (pr(_vt(e.widget))) e];
                must('${c.id} $what 정확 1', xs.length == 1, '${xs.length}');
                return xs.single;
              }

              textItem('${c.id}:name', one((s) => s == c.name, '이름'), 'name', want: c.name);
              if (c.phone != null) textItem('${c.id}:phone', one((s) => s == c.phone, '전화'), 'phone', want: c.phone);
              if (c.invite) textItem('${c.id}:meta', one((s) => _metaRe.hasMatch(s), '안내'), 'meta');
              if (!c.invite) {
                final chipEls = [for (final e in tels) if (_permLabels.contains(_vt(e.widget))) e];
                must('${c.id} 칩 목록(순서) = 기대', _same([for (final e in chipEls) _vt(e.widget)], c.chips), '${[for (final e in chipEls) _vt(e.widget)]}');
                for (final e in chipEls) {
                  textItem('${c.id}:chip:${_vt(e.widget)}', e, 'chip', want: _vt(e.widget));
                }
                if (c.chips.isEmpty) textItem('${c.id}:none', one((s) => s == '권한 없음', '권한 없음'), 'none', want: '권한 없음');
              }
              if (c.biz != null) textItem('${c.id}:biz', one((s) => s == c.biz, '사업장 행'), 'biz', want: c.biz);
              if (c.menu) {
                menuItem('${c.id}:menu', card);
              } else {
                must('${c.id} 메뉴 없음', _under(card, (w) => w is Icon && w.icon == Icons.more_vert).isEmpty);
              }
            }
            // 알 수 없는 카드 0 — 이번 위치에 build 된 카드 장식 = 기대 이름으로 찾은 카드
            final allCards = find.descendant(of: scaf, matching: find.byWidgetPredicate(_isCardDeco, skipOffstage: false), skipOffstage: false).evaluate().toList();
            for (final cd in allCards) {
              final ts = {for (final e in _under(cd, (w) => w is Text)) _vt(e.widget)};
              final k = cards.where((c) => ts.contains(c.name)).length;
              must('카드 식별(기대 카드 정확 1)', k == 1, '$ts');
            }
            must('이번 위치 카드 수 = 기대 이름 카드 수', allCards.length == built, '${allCards.length}/$built');
            for (final h in hdrs) {
              if (h.kind == 'empty') {
                final xs = texts((s) => s == h.text);
                must('${h.key} 인라인 빈 문구 ≤ 1', xs.length <= 1, '${xs.length}');
                if (xs.isEmpty) continue;
                final anchor = hdrEl(h.anchor!, 'multi');
                if (anchor == null) {
                  must('${h.key} 사업장 머리와 함께 build', false);
                  return;
                }
                must('${h.key} 사업장 머리 아래', t.getRect(_el(xs.single)).top >= t.getRect(_el(anchor)).bottom - 0.5);
                textItem(h.key, xs.single, 'empty', want: h.text);
              } else {
                final e = hdrEl(h.text, h.kind);
                if (e == null) continue;
                textItem(h.key, e, h.kind == 'single' ? 'hdr' : 'bizhdr', want: h.text);
              }
            }
            _out('D406 $tok scan $fx pos=$p px=${pos.pixels.toStringAsFixed(1)} built=$built');
          }

          scan();
          var drags = 0;
          while (pos.pixels < pos.maxScrollExtent - 0.5 && drags < 60) {
            await t.drag(sf, const Offset(0, -120));
            drags++;
            await settle(6);
            p++;
            scan();
          }
          final reached = pos.pixels >= pos.maxScrollExtent - 0.5;
          _out('D406 $tok scroll $fx end=${pos.pixels.toStringAsFixed(1)} max=${pos.maxScrollExtent.toStringAsFixed(1)} drags=$drags reached=$reached');
          must('$fx 목록 말단 도달', reached, '${pos.pixels}/${pos.maxScrollExtent}');
          final missing = [for (final k in req) if (!(_before ? measured : seen).contains(k)) k]..sort();
          final notSeen = [for (final k in req) if (!seen.contains(k)) k]..sort();
          _out('D406 $tok cover $fx required=${req.length} exists=${exists.length} text=${text.length} measured=${measured.length} visible=${seen.length} '
              'missing=${notSeen.isEmpty ? '-' : notSeen.join(',')}');
          covers++;
          must('$fx 존재 집합 = 필수', _sameSet(exists, req), '${req.difference(exists)} 추가 ${exists.difference(req)}');
          must('$fx 원문 집합 = 필수', _sameSet(text, req), '${req.difference(text)}');
          must('$fx 조판 검사 완료 집합 = 필수', _sameSet(measured, req), '${req.difference(measured)}');
          if (!_before) must('$fx 가시 확인 집합 = 필수', _sameSet(seen, req), '$missing');
        }

        if (st.key == 'ONE') {
          final r0 = _Reads(biz: [_biz('b1', _longBiz)]);
          await open(r0, subAdmin: true);
          final gone = find.byType(MemberManagementScreen).evaluate().isEmpty;
          _out('D406 $tok prelude subAdmin pop=$gone reads=${r0.counts}');
          must('SubAdmin 직접 route → pop · 읽기 0', gone && r0.counts == '0/0/0', r0.counts);
          prelude = 'pop';
          await close();
          final r = _Reads(biz: [_biz('b1', _longBiz)], members: {
            'b1': [
              _member('b1', 'm1', '김민준', phone: _phones[0]),
              _member('b1', 'm2', _longMember, perms: MemberPermissions.all()),
              _member('b1', 'm3', '박서연', phone: _phones[1], perms: const MemberPermissions(canManageTo: true, canManageWage: true)),
            ],
          }, invites: {
            'b1': [_invite('b1', _longBiz, 'i1', '이도윤', phone: _phones[2]), _invite('b1', _longBiz, 'i2', _longInvite)],
          });
          await open(r);
          // [S024 초대] 떠 있는 FAB 대신 사업장 머리 옆 '+ 멤버 초대' 글자 행동 하나(TextButton 계열)
          final headInvite = find
              .descendant(of: scaf, matching: find.byWidgetPredicate((w) => w is TextButton), skipOffstage: false)
              .evaluate()
              .where((e) => _under(e, (w) => w is Text).any((x) => _vt(x.widget) == '멤버 초대'))
              .length;
          must('첫 화면 — 긴 사업장 머리 · FAB 0 · 머리 초대 1',
              _vis(_longBiz).evaluate().isNotEmpty && find.byType(FloatingActionButton).evaluate().isEmpty && headInvite == 1, '$headInvite');
          must('읽기 1/1/1', r.counts == '1/1/1', r.counts);
          checkTitle();
          checkPad(false); // [S024 초대] FAB 제거 → FAB 전용 말단 여분 0
          await shot('1top', '한 사업장 첫 화면');
          final last = _Card('m3', '박서연', phone: _phones[1], chips: ['공고', '급여'], menu: true);
          await sweep('ONE', [
            _Card('i1', '이도윤', invite: true, phone: _phones[2]),
            _Card('i2', _longInvite, invite: true),
            _Card('m1', '김민준', phone: _phones[0], menu: true),
            _Card('m2', _longMember, chips: _permLabels, menu: true),
            last,
          ], [
            _Hdr('hdr:b1', _longBiz, 'single'),
          ]);
          // 말단: 마지막 박서연 카드 정확 5 항목 — 누락 0 · viewport 안 · FAB 비겹침
          final sf = listScroll();
          final vp = t.getRect(sf);
          // [S024 초대] FAB 가 없으면 겹침 대상 0 — 예외 대신 null
          final fabF = find.byType(FloatingActionButton);
          final fab = fabF.evaluate().isEmpty ? null : t.getRect(fabF);
          final ns = texts((s) => s == last.name);
          must('말단 박서연 이름 정확 1', ns.length == 1, '${ns.length}');
          final card = _cardOf(ns.single);
          if (card == null) {
            must('말단 박서연 카드', false);
            return;
          }
          final tels = _under(card, (w) => w is Text);
          final icons = _under(card, (w) => w is Icon && w.icon == Icons.more_vert);
          final menuEl = icons.length == 1 ? _ancestor(icons.single, (w) => w is InkWell) : null;
          final targets = <String, Element?>{
            'name': [for (final e in tels) if (_vt(e.widget) == last.name) e].singleOrNull,
            'phone': [for (final e in tels) if (_vt(e.widget) == last.phone) e].singleOrNull,
            'chip:공고': [for (final e in tels) if (_vt(e.widget) == '공고') e].singleOrNull,
            'chip:급여': [for (final e in tels) if (_vt(e.widget) == '급여') e].singleOrNull,
            'menu': menuEl,
          };
          var found = 0, inView = 0, overlap = 0;
          for (final e in targets.values) {
            if (e == null) continue;
            found++;
            final rr = t.getRect(_el(e));
            if (rr.top >= vp.top - 0.5 && rr.bottom <= vp.bottom + 0.5 && _onstage(e)) inView++;
            if (fab != null) {
              final x = rr.intersect(fab);
              if (x.width > 0.5 && x.height > 0.5) overlap++;
            }
          }
          _out('D406 $tok fabEnd items=${targets.length} found=$found inView=$inView overlap=$overlap fab=${fab == null ? '-' : _r(fab)} card=${_r(t.getRect(_el(card)))}');
          must('말단 박서연 5 항목 찾음', found == 5, '$found');
          if (!_before) must('strict 말단 박서연 5 항목 viewport 안 · FAB 0 · 겹침 0', inView == 5 && overlap == 0 && fab == null, 'inView=$inView overlap=$overlap');
          await shot('2end', '한 사업장 말단');
          readsStr = r.counts;
          await close();
        } else if (st.key == 'MULTI') {
          final r = _Reads(biz: [_biz('b1', _shortBiz), _biz('b2', _longBiz2)], members: {
            'b1': [_member('b1', 'm1', '김민준', phone: _phones[0]), _member('b1', 'm2', _longMember, perms: MemberPermissions.all())],
          }, invites: {
            'b1': [_invite('b1', _shortBiz, 'i1', '이도윤', phone: _phones[2])],
          });
          await open(r);
          must('첫 화면 — 첫 사업장 머리 · FAB 0', _vis(_shortBiz).evaluate().isNotEmpty && find.byType(FloatingActionButton).evaluate().isEmpty);
          must('읽기 1/2/2', r.counts == '1/2/2', r.counts);
          checkTitle();
          checkPad(false);
          await shot('1top', '여러 사업장 첫 화면');
          await sweep('MULTI', [
            _Card('i1', '이도윤', invite: true, phone: _phones[2]),
            _Card('m1', '김민준', phone: _phones[0], menu: true, biz: _shortBiz),
            _Card('m2', _longMember, chips: _permLabels, menu: true, biz: _shortBiz),
          ], [
            _Hdr('bizhdr:b1', _shortBiz, 'multi'),
            _Hdr('bizhdr:b2', _longBiz2, 'multi'),
            _Hdr('empty:b2', _emptyText, 'empty', anchor: _longBiz2),
          ]);
          await shot('2end', '여러 사업장 말단');
          readsStr = r.counts;
          await close();
        } else if (st.key == 'LOADING') {
          final gate = Completer<void>();
          final r = _Reads(biz: [_biz('b1', _shortBiz)], members: {
            'b1': [_member('b1', 'm1', '김민준', phone: _phones[0])],
          }, gate: gate);
          await open(r, settleAll: false);
          await t.pump();
          _out('D406 $tok first-frame emptyText=${_vis(_emptyText).evaluate().isNotEmpty} progress=${find.byType(LoadingWidget).evaluate().isNotEmpty} reads=${r.counts}');
          await settle(12);
          final loading = find.byType(LoadingWidget).evaluate().isNotEmpty;
          _out('D406 $tok stage loading progress=$loading reads=${r.counts}');
          must('읽기 대기 중 로딩', loading && r.counts == '1/0/0', r.counts);
          checkTitle();
          await shot('1loading', '사업장 이름 읽기 대기(로딩)');
          gate.complete();
          await settle(12);
          must('대기 해제 뒤 목록', _vis('김민준').evaluate().isNotEmpty && r.counts == '1/1/1', r.counts);
          checkPad(false); // [S024 초대] FAB 제거 → FAB 전용 말단 여분 0
          await shot('2done', '대기 해제 뒤 목록');
          await sweep('LOADING', [
            _Card('m1', '김민준', phone: _phones[0], menu: true),
          ], [
            _Hdr('hdr:b1', _shortBiz, 'single'),
          ]);
          readsStr = r.counts;
          await close();
        } else if (st.key == 'ERROR') {
          final errWant = _before ? _errOld : _errNew;
          final errOther = _before ? _errNew : _errOld;
          for (final sub in const [
            (id: 'members', ids: ['b1'], failM: {'b1'}, failI: <String>{}, want: '1/1/1', single: 1, rows: 0, state: '멤버 조회 실패(한 사업장)'),
            (id: 'invites', ids: ['b1'], failM: <String>{}, failI: {'b1'}, want: '1/1/1', single: 1, rows: 0, state: '초대 조회 실패(한 사업장)'),
            (id: 'multi', ids: ['b1', 'b2'], failM: {'b2'}, failI: <String>{}, want: '1/2/2', single: 0, rows: 2, state: '두 사업장 중 한 곳 멤버 실패'),
          ]) {
            final r = _Reads(
                biz: [for (final id in sub.ids) _biz(id, id == 'b1' ? _shortBiz : _longBiz2)],
                members: {'b1': [_member('b1', 'm1', '김민준')]},
                failMembers: sub.failM,
                failInvites: sub.failI);
            await open(r);
            final body = texts((s) => s == errWant).length;
            final total = _vis(errWant).evaluate().length;
            final other = _vis(errOther).evaluate().length;
            final normalEmpty = _vis(_emptyText).evaluate().isNotEmpty;
            final listShown = _vis('김민준').evaluate().isNotEmpty;
            final subtitle = texts((s) => s == _errSub).length;
            // 초대 진입: InkWell 안 글이 ['멤버 초대'] 이면 단일, [사업장 이름, '초대'] 이면 사업장별 행(위→아래)
            var single = 0;
            final rows = <(double, String)>[];
            for (final ink in find.descendant(of: scaf, matching: find.byType(InkWell), skipOffstage: false).evaluate()) {
              final ts = [for (final e in _under(ink, (w) => w is Text)) _vt(e.widget)];
              if (ts.length == 1 && ts.single == '멤버 초대') single++;
              if (ts.length == 2 && ts.last == '초대') rows.add((t.getRect(_el(ink)).top, ts.first));
            }
            rows.sort((a, b) => a.$1.compareTo(b.$1));
            final rowNames = [for (final x in rows) x.$2];
            final rowsOk = sub.rows == 0 ? rowNames.isEmpty : _same(rowNames, [_shortBiz, _longBiz2]);
            _out('D406 $tok sub ${sub.id} errorBody=$body errorTotal=$total other=$other normalEmpty=$normalEmpty partialList=$listShown '
                'subtitle=$subtitle single=$single rows=${rows.length} rowsOk=$rowsOk reads=${r.counts}');
            // [정책 B · DU407 수용] 첫 로드 실패는 오류 본문만 — strict 토스트 0(total 1). before(DU406 당시 기준)는 그대로 2.
            final wantTotal = _before ? 2 : 1;
            must('${sub.id} 오류 본문 1 · 토스트 ${wantTotal - 1} = $errWant $wantTotal · 다른 문장 0 · 정상 빈 아님 · 부분 목록 없음',
                body == 1 && total == wantTotal && other == 0 && !normalEmpty && !listShown, 'body=$body total=$total other=$other empty=$normalEmpty list=$listShown');
            must('${sub.id} 부제 1 · 초대 진입 단일 ${sub.single} · 사업장별 ${sub.rows}(이름 귀속 · 순서)',
                subtitle == 1 && single == sub.single && rows.length == sub.rows && rowsOk, 'subtitle=$subtitle single=$single rows=$rowNames');
            must('${sub.id} 읽기 호출', r.counts == sub.want, r.counts);
            checkTitle();
            await shot(sub.id == 'members' ? '1members' : (sub.id == 'invites' ? '2invites' : '3multi'), sub.state);
            subs++;
            await close();
          }
        } else {
          final r = _Reads(biz: [_biz('b1', _shortBiz)]);
          await open(r);
          final title = texts((s) => s == _emptyText).length;
          final err = _vis(_errOld).evaluate().length + _vis(_errNew).evaluate().length;
          final subtitle = texts((s) => s == _emptySub).length;
          var single = 0, rows = 0;
          for (final ink in find.descendant(of: scaf, matching: find.byType(InkWell), skipOffstage: false).evaluate()) {
            final ts = [for (final e in _under(ink, (w) => w is Text)) _vt(e.widget)];
            if (ts.length == 1 && ts.single == '멤버 초대') single++;
            if (ts.length == 2 && ts.last == '초대') rows++;
          }
          final fabN = find.byType(FloatingActionButton).evaluate().length;
          _out('D406 $tok entry empty title=$title err=$err subtitle=$subtitle single=$single rows=$rows fab=$fabN reads=${r.counts}');
          must('정상 빈 1 · 오류 0 · 부제 1 · 초대 진입 단일 1 · 사업장별 0 · FAB 0', title == 1 && err == 0 && subtitle == 1 && single == 1 && rows == 0 && fabN == 0,
              'title=$title err=$err subtitle=$subtitle single=$single rows=$rows fab=$fabN');
          must('읽기 1/1/1', r.counts == '1/1/1', r.counts);
          checkTitle();
          await shot('1empty', '정상 빈 목록(멤버 · 초대 0)');
          readsStr = r.counts;
          await close();
        }
        final exc = t.takeException();
        _out('D406 $tok done state=${st.key} mode=$mode reached=true reads=$readsStr subs=$subs prelude=$prelude captures=$captures covers=$covers '
            'overflows=${overflows.length} exc=${exc != null}');
        expect(exc, isNull);
        expect(overflows, isEmpty, reason: '$tok 넘침');
      });
    }
  }
}
