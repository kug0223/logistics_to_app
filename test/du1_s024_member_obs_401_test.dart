// [DU401 S024] 팀원 관리(MemberManagementScreen) 무스타일 관측(소급 31 §5) — 새 파일 · 정확 10 public(W 392x844@1.0 · B 320x640@2.0 × 5 상태).
//   읽기 seam(MemberManagementReads 3개)만 fake 로 넣는다. 서비스 eager 생성 시점은 그대로라 S014 와 같은 fake core · 가짜 auth 채널을 쓴다.
//   누르지 않는다: 초대 · FAB · 취소 · 멤버 메뉴 · 권한 · 제거 · 알림 · 홈 · 새로고침(쓰기 · 검색 · CF 연결 조작 0).
//   성공 조건(단언): 목적 장면 도달 · fake 읽기 호출 수 · ONE 머리의 SubAdmin 직접 route → pop · 읽기 0 · 넘침 0 · 예외 0.
//   관측(기록만, 판정은 감사): 글 낱말/말줄임/가시 가로 · 글 대비 · receiver 크기 · viewport · 중앙 hit · 목록 말단 · FAB 겹침 · 토스트 · 초기 frame.
//   이 PNG 는 seam 이 들어간 현재 무스타일 before 다(스타일 after 쌍이 아니다).
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
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
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
const _longMember = '알렉산드라 크리스티나 페트로바 바실리예브나';
const _longInvite = '모하메드 압둘라 알라시드 빈 칼리드';

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
          if (failMembers.contains(id)) throw StateError('DU401 fake members 실패 $id');
          return members[id] ?? const [];
        },
        sentPendingInvitations: (id) async {
          inviteCalls++;
          if (failInvites.contains(id)) throw StateError('DU401 fake 초대 조회 실패 $id');
          return invites[id] ?? const [];
        },
      );

  String get counts => '$bizCalls/$memberCalls/$inviteCalls';
}

final String _manifest = Platform.environment['DU401_MANIFEST'] ?? '(unset)';
// [인계 32 §2] child 가 받은 계약 env 전부(키:값, 쉼표) — post 가 manifest env 와 대조한다.
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST', 'DU401_MANIFEST', 'DU296_PHASE'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');
const _wj = '\u2060';
const _zw = '\u200B';
const _nb = '\u00A0';
bool _visible(String ch) => ch != ' ' && ch != _nb && ch != '\n' && ch != _wj && ch != _zw;

Finder _vis(String text) => find.byWidgetPredicate(
    (w) => w is Text && visibleText(w.data ?? w.textSpan?.toPlainText() ?? '') == text,
    skipOffstage: false);

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _hex(Color? c) => '0x${(c ?? Colors.transparent).toARGB32().toRadixString(16)}';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

// 실제 바탕 — 가장 가까운 불투명 면(396 helper 와 같은 규칙, 반투명 면은 그 아래 첫 불투명 면과 합성).
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

/// 로컬 조판 측정(DU400 과 같은 규칙): 낱말 내부 분절 · 가시 글자 가로 초과 목록 · 말줄임.
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    const codec = StandardMessageCodec();
    for (final m in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
          'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$m',
          (_) async => codec.encodeMessage(<Object?>['du401.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du401.fake.$m'), (_) async => null);
    }
  });

  const views = [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const states = [
    (key: 'ONE', title: '한 사업장·긴 이름·멤버·대기 초대'),
    (key: 'MULTI', title: '여러 사업장·섹션·긴 사업장명'),
    (key: 'LOADING', title: '읽기 대기·로딩'),
    (key: 'ERROR', title: '멤버·초대 조회 실패·빈 목록 구별'),
    (key: 'EMPTY', title: '정상 빈 목록·초대 진입 존재'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S024O-${v.id}-${st.key} ${st.title}', (t) async {
        final tok = 'S024O-${v.id}-${st.key}';
        _out('D401 $tok begin mode=observe phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
        bool inRect(Rect o, Rect r) => r.top >= o.top - 0.5 && r.bottom <= o.bottom + 0.5 && r.left >= o.left - 0.5 && r.right <= o.right + 0.5;
        void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        Future<void> settle([int n = 10]) async {
          for (var i = 0; i < n; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
        }

        var captures = 0;
        var subs = 0;
        var prelude = '-';
        var readsStr = '-';
        final key = GlobalKey();
        final cond = {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}',
          'textScaler': v.s,
          'run': vqRun,
          'manifest': _manifest,
        };

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
          await t.pump(const Duration(seconds: 5)); // 토스트 4초 타이머 소진
          await t.pumpWidget(const SizedBox.shrink());
          await settle(4);
        }

        // 관측 — 글(낱말 · 말줄임 · 가시 가로 · 대비) · receiver(크기 · viewport · 중앙 hit) 기록만
        void observe(String stage) {
          final scaf = find.byType(MemberManagementScreen);
          final texts = find.descendant(of: scaf, matching: find.byType(Text));
          var n = 0, badN = 0, ellN = 0, gxN = 0, lowC = 0;
          for (var i = 0; i < texts.evaluate().length; i++) {
            final f = texts.at(i);
            final w = t.widget<Text>(f);
            final s = visibleText(w.data ?? w.textSpan?.toPlainText() ?? '');
            if (s.trim().isEmpty) continue;
            final rpF = find.descendant(of: f, matching: find.byType(RichText), matchRoot: true);
            if (rpF.evaluate().isEmpty) continue;
            final rp = t.renderObject<RenderParagraph>(rpF.first);
            final m = _measure(rp);
            final col = rp.text.style?.color;
            final bg = _bgOf(t.element(f));
            final c = col == null ? 0.0 : _contrast(col, bg);
            final r = t.getRect(f);
            n++;
            if (m.bad > 0) badN++;
            if (m.ell) ellN++;
            if (m.glyphX > 0) gxN++;
            if (col != null && c < 4.5) lowC++;
            _out('D401 $tok text $stage "${s.length > 40 ? '${s.substring(0, 40)}…' : s}" lines=${m.lines} bad=${m.bad} ell=${m.ell} glyphX=${m.glyphX} '
                'color=${_hex(col)} bg=${_hex(bg)} c=${c.toStringAsFixed(2)} rect=${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)},${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)} '
                'onscreen=${inRect(screen, r)}');
          }
          final recvTypes = [InkWell, IconButton, TextButton, FloatingActionButton];
          var rn = 0, small = 0, nohit = 0;
          for (final ty in recvTypes) {
            final rf = find.descendant(of: scaf, matching: find.byType(ty));
            for (var i = 0; i < rf.evaluate().length; i++) {
              final f = rf.at(i);
              final r = t.getRect(f);
              if (!r.overlaps(screen)) continue;
              final label = find.descendant(of: f, matching: find.byType(Text)).evaluate().map((e) => visibleText((e.widget as Text).data ?? '')).join('/');
              final hr = HitTestResult();
              WidgetsBinding.instance.hitTestInView(hr, r.center, t.view.viewId);
              final ro = t.renderObject(f);
              final hit = hr.path.any((e) => e.target == ro);
              rn++;
              if (r.width < 47.99 || r.height < 47.99) small++;
              if (!hit) nohit++;
              _out('D401 $tok recv $stage $ty "${label.isEmpty ? '-' : label}" rect=${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)},${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)} '
                  'size=${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)} onscreen=${inRect(screen, r)} hit=$hit');
            }
          }
          _out('D401 $tok stage $stage texts=$n bad=$badN ell=$ellN glyphX=$gxN lowContrast=$lowC recv=$rn small=$small nohit=$nohit');
        }

        Future<void> shot(String id, String state) async {
          await vqCapture(t, key, '${tok}_$id', conditions: {...cond, 'state': state, 'fixture': st.key});
          captures++;
        }

        // 목록 말단까지 실제 drag(세로 Scrollable 중 가장 큰 것) — offset · maxScroll · 이동 횟수 기록
        Future<Set<String>> scrollEnd(List<String> targets) async {
          final seen = <String>{};
          void look() {
            for (final n in targets) {
              if (_vis(n).evaluate().isNotEmpty) seen.add(n);
            }
          }

          final all = find.descendant(of: find.byType(MemberManagementScreen), matching: find.byType(Scrollable));
          final cands = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
              .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
              .toList()
            ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
          must('목록 세로 스크롤 주인 존재', cands.isNotEmpty);
          final sf = cands.first;
          final pos = t.state<ScrollableState>(sf).position;
          final max0 = pos.maxScrollExtent;
          var drags = 0;
          look();
          for (var k = 0; k < 30 && pos.pixels < pos.maxScrollExtent - 0.5; k++) {
            await t.drag(sf, const Offset(0, -300));
            drags++;
            await settle(6);
            look();
          }
          must('목록 말단 도달', pos.pixels >= pos.maxScrollExtent - 0.5, '${pos.pixels}/${pos.maxScrollExtent}');
          final vp = t.getRect(sf);
          final fab = find.byType(FloatingActionButton);
          final fr = fab.evaluate().isEmpty ? null : t.getRect(fab);
          final s = 'max=${max0.toStringAsFixed(1)} end=${pos.pixels.toStringAsFixed(1)} drags=$drags vp=$vp fab=$fr seen=${seen.length}/${targets.length}';
          _out('D401 $tok scroll $s');
          return seen;
        }

        if (st.key == 'ONE') {
          // 머리: SubAdmin 직접 route → 화면 가드 pop · 읽기 0
          final r0 = _Reads(biz: [_biz('b1', _longBiz)]);
          await open(r0, subAdmin: true);
          final gone = find.byType(MemberManagementScreen).evaluate().isEmpty;
          must('SubAdmin 직접 route → pop', gone);
          must('SubAdmin 읽기 0', r0.counts == '0/0/0', r0.counts);
          prelude = 'pop';
          _out('D401 $tok prelude subAdmin pop=$gone reads=${r0.counts}');
          await close();
          final r = _Reads(biz: [_biz('b1', _longBiz)], members: {
            'b1': [
              _member('b1', 'm1', '김민준', phone: '010-1234-5678'),
              _member('b1', 'm2', _longMember, perms: MemberPermissions.all()),
              _member('b1', 'm3', '박서연', phone: '010-2222-3333', perms: const MemberPermissions(canManageTo: true, canManageWage: true)),
            ],
          }, invites: {
            'b1': [_invite('b1', _longBiz, 'i1', '이도윤', phone: '010-9876-5432'), _invite('b1', _longBiz, 'i2', _longInvite)],
          });
          await open(r);
          must('목록 첫 화면 도달 — 긴 사업장명 머리 · FAB 1', _vis(_longBiz).evaluate().isNotEmpty && find.byType(FloatingActionButton).evaluate().length == 1);
          must('읽기 = 사업장 1 · 멤버 1 · 초대 1', r.counts == '1/1/1', r.counts);
          observe('top');
          await shot('1top', '한 사업장 목록 첫 화면');
          final seen1 = await scrollEnd(['이도윤', _longInvite, '김민준', _longMember, '박서연']);
          must('첫 화면~말단 drag 동안 초대 2 · 멤버 3 모두 표시', seen1.length == 5, '$seen1');
          must('말단에 마지막 멤버 표시', _vis('박서연').evaluate().isNotEmpty);
          observe('end');
          await shot('2end', '한 사업장 목록 말단');
          readsStr = r.counts;
          await close();
        } else if (st.key == 'MULTI') {
          final r = _Reads(biz: [_biz('b1', '강남 물류센터'), _biz('b2', _longBiz2)], members: {
            'b1': [_member('b1', 'm1', '김민준', phone: '010-1234-5678'), _member('b1', 'm2', _longMember, perms: MemberPermissions.all())],
          }, invites: {
            'b1': [_invite('b1', '강남 물류센터', 'i1', '이도윤')],
          });
          await open(r);
          must('목록 첫 화면 도달 — 첫 사업장 머리 · FAB 0', _vis('강남 물류센터').evaluate().isNotEmpty && find.byType(FloatingActionButton).evaluate().isEmpty);
          must('읽기 = 사업장 1 · 멤버 2 · 초대 2', r.counts == '1/2/2', r.counts);
          observe('top');
          await shot('1top', '여러 사업장 목록 첫 화면');
          final seen2 = await scrollEnd([_longBiz2, '김민준', _longMember, '이도윤']);
          must('첫 화면~말단 drag 동안 둘째(긴 이름) 사업장 · 멤버 2 · 초대 1 표시', seen2.length == 4, '$seen2');
          observe('end');
          await shot('2end', '여러 사업장 목록 말단');
          readsStr = r.counts;
          await close();
        } else if (st.key == 'LOADING') {
          final gate = Completer<void>();
          final r = _Reads(biz: [_biz('b1', '강남 물류센터')], members: {
            'b1': [_member('b1', 'm1', '김민준', phone: '010-1234-5678')],
          }, gate: gate);
          await open(r, settleAll: false);
          await t.pump();
          final flashEmpty = findVisibleText('등록된 멤버가 없습니다').evaluate().isNotEmpty;
          final flashLoading = find.byType(LoadingWidget).evaluate().isNotEmpty;
          _out('D401 $tok first-frame emptyText=$flashEmpty progress=$flashLoading reads=${r.counts}');
          await settle(12);
          final loading = find.byType(LoadingWidget).evaluate().isNotEmpty;
          must('읽기 대기 중 로딩 표시 도달', loading && r.counts == '1/0/0', 'reads=${r.counts}');
          _out('D401 $tok stage loading progress=$loading emptyText=${findVisibleText('등록된 멤버가 없습니다').evaluate().isNotEmpty} reads=${r.counts}');
          await shot('1loading', '사업장 이름 읽기 대기(로딩)');
          gate.complete();
          await settle(12);
          must('대기 해제 뒤 목록 도달', _vis('김민준').evaluate().isNotEmpty && r.counts == '1/1/1', r.counts);
          observe('done');
          await shot('2done', '대기 해제 뒤 목록');
          readsStr = r.counts;
          await close();
        } else if (st.key == 'ERROR') {
          const errTitle = '멤버 목록을 불러오지 못했습니다';
          for (final sub in const [
            (id: 'members', ids: ['b1'], failM: {'b1'}, failI: <String>{}, want: '1/1/1', state: '멤버 조회 실패(한 사업장)'),
            (id: 'invites', ids: ['b1'], failM: <String>{}, failI: {'b1'}, want: '1/1/1', state: '초대 조회 실패(한 사업장)'),
            (id: 'multi', ids: ['b1', 'b2'], failM: {'b2'}, failI: <String>{}, want: '1/2/2', state: '두 사업장 중 한 곳 멤버 실패'),
          ]) {
            final r = _Reads(
                biz: [for (final id in sub.ids) _biz(id, id == 'b1' ? '강남 물류센터' : _longBiz2)],
                members: {'b1': [_member('b1', 'm1', '김민준')]},
                failMembers: sub.failM,
                failInvites: sub.failI);
            await open(r);
            final titleN = findVisibleText(errTitle).evaluate().length;
            final normalEmpty = findVisibleText('등록된 멤버가 없습니다').evaluate().isNotEmpty;
            final listShown = _vis('김민준').evaluate().isNotEmpty;
            final inviteN = find.descendant(of: find.byType(MemberManagementScreen), matching: findVisibleTextContaining('초대')).evaluate().length;
            must('${sub.id} 오류 본문 도달 · 정상 빈 아님 · 부분 목록 없음', titleN >= 1 && !normalEmpty && !listShown, 'title=$titleN empty=$normalEmpty list=$listShown');
            must('${sub.id} 읽기 호출', r.counts == sub.want, r.counts);
            _out('D401 $tok sub ${sub.id} errorTitle=$titleN(본문+토스트) normalEmpty=$normalEmpty partialList=$listShown inviteTexts=$inviteN reads=${r.counts}');
            observe(sub.id);
            await shot(sub.id == 'members' ? '1members' : (sub.id == 'invites' ? '2invites' : '3multi'), sub.state);
            subs++;
            await close();
          }
        } else {
          final r = _Reads(biz: [_biz('b1', '강남 물류센터')]);
          await open(r);
          final title = findVisibleText('등록된 멤버가 없습니다').evaluate().isNotEmpty;
          final err = findVisibleText('멤버 목록을 불러오지 못했습니다').evaluate().isNotEmpty;
          final action = find.descendant(of: find.byType(MemberManagementScreen), matching: findVisibleText('멤버 초대')).evaluate().length;
          must('정상 빈 상태 도달 · 오류 아님 · 초대 진입 1 · FAB 0', title && !err && action == 1 && find.byType(FloatingActionButton).evaluate().isEmpty,
              'title=$title err=$err action=$action');
          must('읽기 = 사업장 1 · 멤버 1 · 초대 1', r.counts == '1/1/1', r.counts);
          observe('empty');
          await shot('1empty', '정상 빈 목록(멤버 · 초대 0)');
          readsStr = r.counts;
          await close();
        }
        final exc = t.takeException();
        _out('D401 $tok done state=${st.key} reached=true reads=$readsStr subs=$subs prelude=$prelude captures=$captures overflows=${overflows.length} exc=${exc != null}');
        expect(exc, isNull);
        expect(overflows, isEmpty, reason: '$tok 넘침');
      });
    }
  }
}
