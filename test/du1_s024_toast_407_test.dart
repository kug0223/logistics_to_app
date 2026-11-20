// [DU407 r2 S024] 팀원 관리 오류 토스트 정책 B — 교정 시험(소급 35 §4–§5). 원 9461d4bc 은 보존한다. 새 파일 · 정확 6 public(W/B × ERRINIT · REFRESH · EMPTYREF).
//   기준본: DU406 r1 후보 b2a6f0e9(before) → DU407 B 후보 378672d7(strict). 문구는 두 모드 모두 '…못했어요'(wording=new) 강제.
//   모드: DU_BEFORE_OBSERVE=407 이면 before(정책 B 미적용 — 첫/재시도 실패에도 토스트), 아니면 strict.
//   ERRINIT 하위 4(members · invites · multi · retry) · REFRESH(목록 → 새로고침 실패) · EMPTYREF(성공 EMPTY → 새로고침 실패).
//   교정(소급 35 F407-1): skipOffstage:false 개수 대신 대상별 필수 집합(존재 · 원문 · 조판 검사 완료 · 가시 확인)을 정확 대조한다.
//     조판 검사 완료 = rect ⊂ 실제 viewport(본문 Scrollable, 없으면 화면) · onstage(skipOffstage:true) · 크기 > 0 · 가로 글자 넘침 0 ·
//       말줄임 0(허용 대상: 사업장별 초대 행의 사업장 이름만). 가시 확인 = 거기에 토스트 표면(IgnorePointer 상자) 비가림.
//     strict 단언: ERRINIT 4 · REFRESH 의 가시 확인 = 필수. before 는 기존 토스트 가림을 관측으로 기록한다.
//     EMPTYREF 는 정책상 토스트가 남는 경우라 두 모드 모두 조판 검사 완료 = 필수까지만 단언하고 토스트 가림은 관측으로 기록한다(Codex 판단 요청).
//     모든 scroll 위치의 전역 겹침 0 은 요구하지 않는다(대상별 한 번 이상).
//   누름: 상단 새로고침 IconButton 만(읽기만 다시 부른다). 쓰기 · 초대 · 취소 · 메뉴는 누르지 않는다.
//   보존: 공용 ToastHelper(errorDark · 원문 semantics · IgnorePointer · 4초 수명 · 교체) 무변경. fake 읽기 throw 는 production 관대한 사업장 조회와 같은 경로가 아니다.
// [H-2 E 추종 · DU413] REFRESH · EMPTYREF: 새로고침 실패 = 화면 안 결과 띠 1 · overlay 토스트 0. 띠 가시를 필수 집합에 넣는다(strict 약화 0). ERRINIT 그대로.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

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

const _shortBiz = '강남 물류센터';
const _longBiz2 = '[QA] 아주 긴 이름의 송파 신선 분류센터 제3공장 냉동 보관동';
const _emptyText = '등록된 멤버가 없습니다';
const _errSub = '아래에서 새 멤버를 초대하거나 새로고침을 시도해 보세요';
const _emptySub = '멤버를 초대하고 사업장을 함께 관리해보세요';
const _errOld = '멤버 목록을 불러오지 못했습니다';
const _errNew = '멤버 목록을 불러오지 못했어요';

class _Reads {
  _Reads({required this.biz, this.members = const {}, this.invites = const {}});

  final List<BusinessModel> biz;
  final Map<String, List<BusinessMemberModel>> members;
  final Map<String, List<MemberInvitationModel>> invites;
  final failMembers = <String>{};
  final failInvites = <String>{};
  var bizCalls = 0, memberCalls = 0, inviteCalls = 0;

  MemberManagementReads get reads => MemberManagementReads(
        businessesByIds: (ids) async {
          bizCalls++;
          return [for (final b in biz) if (ids.contains(b.id)) b];
        },
        members: (id) async {
          memberCalls++;
          if (failMembers.contains(id)) throw StateError('DU407 fake members 실패 $id');
          return members[id] ?? const [];
        },
        sentPendingInvitations: (id) async {
          inviteCalls++;
          if (failInvites.contains(id)) throw StateError('DU407 fake 초대 조회 실패 $id');
          return invites[id] ?? const [];
        },
      );

  String get counts => '$bizCalls/$memberCalls/$inviteCalls';
}

/// 필수 대상 — 키 · 찾기(build 됐으면 정확 1, 아니면 0) · 말줄임 허용 · 토스트 자신 여부.
class _T {
  _T(this.key, this.find, {this.allowEll = false, this.toast = false});

  final String key;
  final List<Element> Function() find;
  final bool allowEll;
  final bool toast;
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '407';
final String _manifest = Platform.environment['DU407_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');
const _wj = '\u2060';
const _zw = '\u200B';
const _nb = '\u00A0';
bool _visible(String ch) => ch != ' ' && ch != _nb && ch != '\n' && ch != _wj && ch != _zw;

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _r(Rect r) => '${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)},${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)}';

/// 로컬 조판 측정(DU406 과 같은 규칙): 낱말 분절 · 가시 가로 초과 · 말줄임 · 줄 수.
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

List<Element> _under(Element scope, bool Function(Widget w) p) =>
    find.descendant(of: _el(scope), matching: find.byWidgetPredicate(p, skipOffstage: false), skipOffstage: false).evaluate().toList();

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    const codec = StandardMessageCodec();
    for (final m in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
          'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$m',
          (_) async => codec.encodeMessage(<Object?>['du407.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du407.fake.$m'), (_) async => null);
    }
  });

  const views = [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const states = [
    (key: 'ERRINIT', title: '첫·재시도 로드 실패·본문 1·토스트 정책'),
    (key: 'REFRESH', title: '목록 뒤 새로고침 실패·기존 정보 유지·결과 띠 1'),
    (key: 'EMPTYREF', title: '정상 빈 뒤 새로고침 실패·빈 문구 유지·결과 띠 1'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S024T-${v.id}-${st.key} ${st.title}', (t) async {
        final tok = 'S024T-${v.id}-${st.key}';
        final mode = _before ? 'before' : 'strict';
        _out('D407 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
        void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        Future<void> settle([int n = 10]) async {
          for (var i = 0; i < n; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
        }

        var captures = 0;
        var subs = 0;
        var refreshes = 0;
        var covers = 0;
        final key = GlobalKey();
        final cond = {'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode};
        final scaf = find.byType(MemberManagementScreen);

        List<Element> texts(bool Function(String s) p) =>
            find.descendant(of: scaf, matching: find.byWidgetPredicate((w) => w is Text && p(_vt(w)), skipOffstage: false), skipOffstage: false)
                .evaluate()
                .toList();

        // 화면 밖(overlay) 토스트 Text — 오류 문장(두 문구) 중 화면 안에 없는 것
        List<Element> toastTexts() {
          final inside = {...texts((s) => s == _errOld || s == _errNew)};
          return [for (final e in _vis(_errOld).evaluate().followedBy(_vis(_errNew).evaluate())) if (!inside.contains(e)) e];
        }

        Rect? toastRect() {
          final ts = toastTexts();
          if (ts.isEmpty) return null;
          final box = _ancestor(ts.first, (w) => w is IgnorePointer);
          return box == null ? null : t.getRect(_el(box));
        }

        Future<void> open(_Reads r) async {
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

        Future<void> refresh() async {
          final f = find.byTooltip('새로고침');
          must('상단 새로고침 버튼 정확 1', f.evaluate().length == 1, '${f.evaluate().length}');
          await t.tap(f);
          await settle(12);
          refreshes++;
        }

        ({int body, int toast, String wording}) errState() {
          final bOld = texts((s) => s == _errOld).length, bNew = texts((s) => s == _errNew).length;
          final tOld = _vis(_errOld).evaluate().length - bOld, tNew = _vis(_errNew).evaluate().length - bNew;
          final anyOld = bOld + tOld > 0, anyNew = bNew + tNew > 0;
          final wording = anyOld && anyNew ? 'mixed' : (anyOld ? 'old' : (anyNew ? 'new' : 'none'));
          return (body: bOld + bNew, toast: tOld + tNew, wording: wording);
        }

        // 초대 진입 InkWell — 글 ['멤버 초대'] 단일 / [사업장 이름, '초대'] 사업장별 행
        List<Element> inks() => find.descendant(of: scaf, matching: find.byType(InkWell), skipOffstage: false).evaluate().toList();
        List<Element> singleEntry() => [
              for (final ink in inks())
                for (final e in _under(ink, (w) => w is Text))
                  if (_under(ink, (w) => w is Text).length == 1 && _vt(e.widget) == '멤버 초대') e
            ];
        List<Element> rowText(String biz, bool act) {
          final out = <Element>[];
          for (final ink in inks()) {
            final ts = _under(ink, (w) => w is Text);
            if (ts.length == 2 && _vt(ts.first.widget) == biz && _vt(ts.last.widget) == '초대') out.add(act ? ts.last : ts.first);
          }
          return out;
        }

        ({int single, List<String> rows}) entries() {
          final rows = <(double, String)>[];
          for (final ink in inks()) {
            final ts = [for (final e in _under(ink, (w) => w is Text)) _vt(e.widget)];
            if (ts.length == 2 && ts.last == '초대') rows.add((t.getRect(_el(ink)).top, ts.first));
          }
          rows.sort((a, b) => a.$1.compareTo(b.$1));
          return (single: singleEntry().length, rows: [for (final x in rows) x.$2]);
        }

        Finder? bodyScroll() {
          final all = find.descendant(of: scaf, matching: find.byType(Scrollable));
          final cands = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
              .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
              .toList()
            ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
          return cands.isEmpty ? null : cands.first;
        }

        // 필수 대상 훑기 — 매 위치(120px drag, 최대 30)에서 조판 검사 · 토스트 가림 판정, 끝에서 필수 집합 정확 대조
        Future<void> sweep(String fx, List<_T> ts, {required bool strictVisible}) async {
          final req = {for (final x in ts) x.key};
          final exists = <String>{}, text = <String>{}, measured = <String>{}, seen = <String>{}, covered = <String>{};
          final sf = bodyScroll();
          final pos = sf == null ? null : t.state<ScrollableState>(sf).position;
          var p = 0;

          void scan() {
            final vp = sf == null ? screen : t.getRect(sf);
            final tr = toastRect();
            for (final x in ts) {
              final els = x.find();
              if (els.isEmpty) continue;
              must('${x.key} 대상 정확 1', els.length == 1, '${els.length}');
              final e = els.single;
              exists.add(x.key);
              text.add(x.key);
              final r = t.getRect(_el(e));
              final box = x.toast ? screen : vp;
              final inBox = r.top >= box.top - 0.5 && r.bottom <= box.bottom + 0.5 && r.left >= box.left - 0.5 && r.right <= box.right + 0.5;
              final rp = t.renderObject<RenderParagraph>(find.descendant(of: _el(e), matching: find.byType(RichText, skipOffstage: false), matchRoot: true, skipOffstage: false).first);
              if (!(inBox && _onstage(e) && rp.size.width > 0 && rp.size.height > 0)) continue;
              final m = _measure(rp);
              must('${x.key} 가로 넘침 0 · 말줄임 ${x.allowEll ? '허용' : '0'}', m.glyphX == 0 && (x.allowEll || !m.ell), '$m');
              if (measured.add(x.key)) {
                _out('D407 $tok item $fx ${x.key} measured pos=$p lines=${m.lines} bad=${m.bad} ell=${m.ell} glyphX=${m.glyphX} rect=${_r(r)}');
              }
              String? coverBy;
              if (!x.toast && tr != null) {
                final i = r.intersect(tr);
                if (i.width > 0.5 && i.height > 0.5) coverBy = _r(tr);
              }
              if (coverBy != null) {
                if (covered.add(x.key)) _out('D407 $tok item $fx ${x.key} covered pos=$p rect=${_r(r)} toast=$coverBy');
              } else if (seen.add(x.key)) {
                _out('D407 $tok item $fx ${x.key} visible pos=$p rect=${_r(r)}');
              }
            }
            _out('D407 $tok scan $fx pos=$p px=${(pos?.pixels ?? 0).toStringAsFixed(1)} toast=${tr == null ? '-' : _r(tr)}');
          }

          scan();
          var drags = 0;
          while (sf != null && pos != null && pos.pixels < pos.maxScrollExtent - 0.5 && drags < 30) {
            await t.drag(sf, const Offset(0, -120));
            drags++;
            await settle(6);
            p++;
            scan();
          }
          final reached = pos == null || pos.pixels >= pos.maxScrollExtent - 0.5;
          _out('D407 $tok scroll $fx end=${(pos?.pixels ?? 0).toStringAsFixed(1)} max=${(pos?.maxScrollExtent ?? 0).toStringAsFixed(1)} drags=$drags reached=$reached');
          must('$fx 본문 말단 도달', reached);
          final notSeen = [for (final k in req) if (!seen.contains(k)) k]..sort();
          _out('D407 $tok cover $fx required=${req.length} exists=${exists.length} text=${text.length} measured=${measured.length} visible=${seen.length} '
              'missing=${notSeen.isEmpty ? '-' : notSeen.join(',')}');
          covers++;
          must('$fx 존재 집합 = 필수', _sameSet(exists, req), '${req.difference(exists)}');
          must('$fx 원문 집합 = 필수', _sameSet(text, req), '${req.difference(text)}');
          must('$fx 조판 검사 완료 집합 = 필수', _sameSet(measured, req), '${req.difference(measured)}');
          if (strictVisible) must('$fx strict 가시 확인 집합 = 필수(토스트 비가림)', _sameSet(seen, req), '$notSeen');
        }

        if (st.key == 'ERRINIT') {
          for (final sub in const [
            (id: 'members', ids: ['b1'], failM: ['b1'], failI: <String>[], retry: false, want: '1/1/1', single: 1, rows: 0, state: '멤버 조회 실패(한 사업장)'),
            (id: 'invites', ids: ['b1'], failM: <String>[], failI: ['b1'], retry: false, want: '1/1/1', single: 1, rows: 0, state: '초대 조회 실패(한 사업장)'),
            (id: 'multi', ids: ['b1', 'b2'], failM: ['b2'], failI: <String>[], retry: false, want: '1/2/2', single: 0, rows: 2, state: '두 사업장 중 한 곳 멤버 실패'),
            (id: 'retry', ids: ['b1'], failM: ['b1'], failI: <String>[], retry: true, want: '2/2/2', single: 1, rows: 0, state: '첫 실패 뒤 새로고침도 실패'),
          ]) {
            final r = _Reads(biz: [for (final id in sub.ids) _biz(id, id == 'b1' ? _shortBiz : _longBiz2)], members: {
              'b1': [_member('b1', 'm1', '김민준')],
            });
            r.failMembers.addAll(sub.failM);
            r.failInvites.addAll(sub.failI);
            await open(r);
            if (sub.retry) await refresh();
            final es = errState();
            final en = entries();
            final normalEmpty = _vis(_emptyText).evaluate().isNotEmpty;
            final listShown = _vis('김민준').evaluate().isNotEmpty;
            final subtitle = texts((s) => s == _errSub).length;
            final rowsOk = sub.rows == 0 ? en.rows.isEmpty : _same(en.rows, [_shortBiz, _longBiz2]);
            final wantToast = _before ? 1 : 0;
            _out('D407 $tok sub ${sub.id} errorBody=${es.body} toast=${es.toast} wording=${es.wording} normalEmpty=$normalEmpty partialList=$listShown '
                'subtitle=$subtitle single=${en.single} rows=${en.rows.length} rowsOk=$rowsOk reads=${r.counts}');
            must('${sub.id} 오류 본문 1 · 토스트 $wantToast · 문구 new', es.body == 1 && es.toast == wantToast && es.wording == 'new', '${es.body}/${es.toast}/${es.wording}');
            must('${sub.id} 정상 빈 아님 · 부분 목록 없음 · 부제 1', !normalEmpty && !listShown && subtitle == 1, 'empty=$normalEmpty list=$listShown subtitle=$subtitle');
            must('${sub.id} 초대 진입 단일 ${sub.single} · 사업장별 ${sub.rows}(이름 · 순서)', en.single == sub.single && en.rows.length == sub.rows && rowsOk, '${en.single} ${en.rows}');
            must('${sub.id} 읽기 호출', r.counts == sub.want, r.counts);
            await shot(sub.id == 'members' ? '1members' : (sub.id == 'invites' ? '2invites' : (sub.id == 'multi' ? '3multi' : '4retry')), sub.state);
            await sweep(sub.id, [
              _T('title', () => texts((s) => s == _errNew)),
              _T('sub', () => texts((s) => s == _errSub)),
              if (sub.rows == 0) _T('entry:single', singleEntry),
              if (sub.rows == 2) ...[
                _T('entry:b1', () => rowText(_shortBiz, false), allowEll: true),
                _T('entry:b1:act', () => rowText(_shortBiz, true)),
                _T('entry:b2', () => rowText(_longBiz2, false), allowEll: true),
                _T('entry:b2:act', () => rowText(_longBiz2, true)),
              ],
            ], strictVisible: !_before);
            subs++;
            await close();
          }
        } else if (st.key == 'REFRESH') {
          final r = _Reads(biz: [_biz('b1', _shortBiz)], members: {
            'b1': [_member('b1', 'm1', '김민준')],
          }, invites: {
            'b1': [_invite('b1', _shortBiz, 'i1', '이도윤')],
          });
          await open(r);
          final before0 = errState();
          must('성공 목록 — 멤버 · 초대 · 오류 0', _vis('김민준').evaluate().isNotEmpty && _vis('이도윤').evaluate().isNotEmpty && before0.body == 0 && before0.toast == 0 && r.counts == '1/1/1',
              '${before0.body}/${before0.toast} ${r.counts}');
          await shot('1list', '성공 목록(새로고침 전)');
          r.failMembers.add('b1');
          await refresh();
          final es = errState();
          final kept = _vis('김민준').evaluate().isNotEmpty && _vis('이도윤').evaluate().isNotEmpty;
          final loading = find.byType(LoadingWidget).evaluate().isNotEmpty;
          _out('D407 $tok refresh list errorBody=${es.body} toast=${es.toast} wording=${es.wording} kept=$kept loading=$loading reads=${r.counts}');
          // [H-2 E] 결과 띠(화면 안 같은 문장)가 errState 의 body 로 잡힌다 — 띠 1 · overlay 토스트 0
          must('새로고침 실패 — 기존 카드 유지 · 로딩 0 · 결과 띠 1 · 토스트 0 · 문구 new', kept && !loading && es.body == 1 && es.toast == 0 && es.wording == 'new',
              'kept=$kept loading=$loading ${es.body}/${es.toast}/${es.wording}');
          must('읽기 2/2/2', r.counts == '2/2/2', r.counts);
          await shot('2fail', '목록 뒤 새로고침 실패');
          await sweep('list', [
            _T('m1:name', () => texts((s) => s == '김민준')),
            _T('i1:name', () => texts((s) => s == '이도윤')),
            // [H-2 E] 띠는 목록 viewport 바깥(본문 위 Column)이라 화면 기준으로 잰다 — toast 플래그는 '판정 상자 = 화면'으로만 쓴다
            _T('band', () => texts((s) => s == _errNew), toast: true),
          ], strictVisible: !_before);
          await close();
        } else {
          final r = _Reads(biz: [_biz('b1', _shortBiz)]);
          await open(r);
          final e0 = entries();
          must('성공 EMPTY — 정상 빈 1 · 부제 1 · 단일 진입 1 · 오류 0',
              texts((s) => s == _emptyText).length == 1 && texts((s) => s == _emptySub).length == 1 && e0.single == 1 && errState().body == 0 && errState().toast == 0 && r.counts == '1/1/1',
              r.counts);
          await shot('1empty', '정상 빈 목록(새로고침 전)');
          r.failMembers.add('b1');
          await refresh();
          final es = errState();
          final en = entries();
          final title = texts((s) => s == _emptyText).length, subtitle = texts((s) => s == _emptySub).length;
          _out('D407 $tok refresh empty errorBody=${es.body} toast=${es.toast} wording=${es.wording} title=$title subtitle=$subtitle single=${en.single} rows=${en.rows.length} reads=${r.counts}');
          // [H-2 E] 부제 아래 결과 띠(화면 안 같은 문장) — 띠 1 · overlay 토스트 0
          must('빈 뒤 새로고침 실패 — 정상 빈 1 · 부제 1 · 단일 진입 1 · 결과 띠 1 · 토스트 0 · 문구 new',
              title == 1 && subtitle == 1 && en.single == 1 && en.rows.isEmpty && es.body == 1 && es.toast == 0 && es.wording == 'new',
              'title=$title subtitle=$subtitle single=${en.single} ${es.body}/${es.toast}/${es.wording}');
          must('읽기 2/2/2', r.counts == '2/2/2', r.counts);
          await shot('2fail', '빈 뒤 새로고침 실패');
          await sweep('empty', [
            _T('title', () => texts((s) => s == _emptyText)),
            _T('sub', () => texts((s) => s == _emptySub)),
            _T('entry:single', singleEntry),
            _T('band', () => texts((s) => s == _errNew)),
          ], strictVisible: !_before); // [H-2 E] 가림 0 이 되어 strict 가시(기존 false)
          await close();
        }
        final exc = t.takeException();
        _out('D407 $tok done state=${st.key} mode=$mode reached=true subs=$subs refreshes=$refreshes captures=$captures covers=$covers '
            'overflows=${overflows.length} exc=${exc != null}');
        expect(exc, isNull);
        expect(overflows, isEmpty, reason: '$tok 넘침');
      });
    }
  }
}
