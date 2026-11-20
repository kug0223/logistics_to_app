// [S024 확인창 문구 · DU417 · 판정52 §6 · 54 §5-4 CORRECTION_OPEN] 공용 삭제 결합 문구 두 경로를 업무의 말로:
//   초대 취소: '"이도윤" 초대을(를) 삭제하시겠습니까?' · 제목/최종 '삭제' · 닫기 '취소' → 제목 · 최종 '초대 취소' · '이도윤님에게 보낸 초대를 취소하시겠습니까?' + 기존 결과 설명 · 닫기 '닫기'
//   멤버 제거: '"김민준" 멤버을(를) 삭제하시겠습니까?' · 제목/최종 '삭제' · 닫기 '취소' → 제목 · 최종 '멤버 제거' · '김민준님을 멤버에서 제거하시겠습니까?' · 닫기 '닫기'
//   새 파일 · 정확 4 public(W 392x844@1.0 · B 320x640@2.0 × CANCEL · REMOVE) · 캡처 1 단계(1dialog × 2 상태 × W/B = 4쌍).
//   하네스: du1_s024_invite_415(DU415) 와 같은 fake core · _Provider(BUSINESS_ADMIN 고정) · 읽기 seam · 전역 navigatorKey 홈 위 push.
//   모드: DU_BEFORE_OBSERVE=417 이면 before(DU415 뒤 A af7920c3 — 옛 결합 문구 관측), 아니면 strict(후보).
//   실제 탭: CANCEL = 카드 '취소' 진입 / REMOVE = 카드 ⋮ → 메뉴 시트 '멤버 제거' → 확인창 → 창 닫기 버튼만. 최종 실행 버튼은 누르지 않는다(writer 0).
//   출력 줄: lkit 선언형 계약 'D417 <tok> <kind> k=v …' — 값 공백 0(문구는 new/old/other 로 분류).
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '417';
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

// 독립 기대 문구(제품에서 가져오지 않는다)
const _exp = {
  'CANCEL': (
    oldMsg: '"이도윤" 초대을(를) 삭제하시겠습니까?\n\n취소하면 상대방이 더 이상 수락할 수 없습니다.',
    newMsg: '이도윤님에게 보낸 초대를 취소하시겠습니까?\n\n취소하면 상대방이 더 이상 수락할 수 없습니다.',
    newTitle: '초대 취소',
    keep: '이도윤',
    toasts: ['초대를 취소했습니다', '초대 취소에 실패했습니다'],
  ),
  'REMOVE': (
    oldMsg: '"김민준" 멤버을(를) 삭제하시겠습니까?',
    newMsg: '김민준님을 멤버에서 제거하시겠습니까?',
    newTitle: '멤버 제거',
    keep: '김민준',
    toasts: ['멤버가 제거되었습니다', '멤버 제거에 실패했습니다'],
  ),
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    const codec = StandardMessageCodec();
    for (final m in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
          'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$m',
          (_) async => codec.encodeMessage(<Object?>['du417.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du417.fake.$m'), (_) async => null);
    }
  });

  const views = [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const states = [
    (key: 'CANCEL', title: '초대 대기 카드 취소 진입 — 확인창 제목 본문 버튼 문구 · 닫기'),
    (key: 'REMOVE', title: '멤버 카드 메뉴 멤버 제거 — 확인창 제목 본문 버튼 문구 · 닫기'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S024K-${v.id}-${st.key} ${st.title}', (t) async {
        final tok = 'S024K-${v.id}-${st.key}';
        final mode = _before ? 'before' : 'strict';
        final ex = _exp[st.key]!;
        _out('D417 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
        final key = GlobalKey();
        final cond = {'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': st.key};
        Future<void> shot(String id, String stage) async {
          await vqCapture(t, key, '${tok}_$id', conditions: {...cond, 'state': stage});
          captures++;
        }

        final r = _Reads(biz: [_biz('b1', _bizA)], members: {
          'b1': [_member('b1', 'm1', '김민준')],
        }, invites: {
          'b1': [_invite('b1', _bizA, 'i1', '이도윤')],
        });
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

        final scaf = find.byType(MemberManagementScreen);
        List<Element> named(String s) => find
            .descendant(of: scaf, matching: find.byWidgetPredicate((w) => w is Text && _vt(w) == s, skipOffstage: false), skipOffstage: false)
            .evaluate()
            .toList();
        final nameEls = named(ex.keep);
        must('대상 카드 이름 1', nameEls.length == 1, '${nameEls.length}');
        final cardEl = _ancestor(nameEls.single, (w) => w is Container && w.decoration is BoxDecoration);
        must('대상 카드 1', cardEl != null);
        final c0 = r.counts;
        var path = '-';
        if (st.key == 'CANCEL') {
          // 초대 대기 카드의 '취소' 진입(TextButton 계열) 실제 탭
          final entries = [
            for (final e in _under(cardEl!, (w) => w is TextButton))
              if (_under(e, (w) => w is Text).any((x) => _vt(x.widget) == '취소')) e
          ];
          must('카드 취소 진입 1', entries.length == 1, '${entries.length}');
          await t.ensureVisible(_el(entries.single));
          await settle(4);
          await t.tapAt(t.getRect(_el(entries.single)).center);
          await settle(12);
          path = 'card';
        } else {
          // 멤버 카드 ⋮(InkWell · more_vert) 실제 탭 → 메뉴 시트 '멤버 제거' 실제 탭
          final menus = [
            for (final e in _under(cardEl!, (w) => w is InkWell))
              if (_under(e, (w) => w is Icon && w.icon == Icons.more_vert).isNotEmpty) e
          ];
          must('멤버 카드 ⋮ 1', menus.length == 1, '${menus.length}');
          await t.ensureVisible(_el(menus.single));
          await settle(4);
          await t.tapAt(t.getRect(_el(menus.single)).center);
          await settle(12);
          final sheet = find.byType(BottomSheet);
          must('⋮ → 메뉴 시트 1', sheet.evaluate().length == 1, '${sheet.evaluate().length}');
          final item = find.descendant(of: sheet, matching: findVisibleText('멤버 제거'));
          must('시트 멤버 제거 1', item.evaluate().length == 1, '${item.evaluate().length}');
          await t.tapAt(t.getRect(item).center);
          await settle(16);
          path = 'sheet';
        }

        // 확인창
        final dlg = find.byType(Dialog);
        must('확인창 1', dlg.evaluate().length == 1, '${dlg.evaluate().length}');
        final scrollF = find.descendant(of: dlg, matching: find.byType(Scrollable));
        must('본문 스크롤 주인 1', scrollF.evaluate().length == 1, '${scrollF.evaluate().length}');
        final bodyText = find.descendant(of: scrollF, matching: find.byType(Text));
        must('본문 Text 1', bodyText.evaluate().length == 1, '${bodyText.evaluate().length}');
        final shown = visibleText(t.widget<Text>(bodyText).data ?? '');
        final msg = shown == ex.newMsg ? 'new' : (shown == ex.oldMsg ? 'old' : 'other');
        // 버튼 = 확인창 안 InkWell 이 감싼 글 하나씩(제목 글은 InkWell 밖)
        final labels = <String, Element>{};
        for (final e in find.descendant(of: dlg, matching: find.byType(InkWell)).evaluate()) {
          final ts = _under(e, (w) => w is Text);
          if (ts.length == 1) labels[_vt(ts.single.widget)] = ts.single;
        }
        final allTexts = [for (final e in find.descendant(of: dlg, matching: find.byType(Text)).evaluate()) _vt(e.widget)];
        final titleNew = allTexts.where((x) => x == ex.newTitle).length == 2 && labels.containsKey(ex.newTitle);
        final titleOld = allTexts.where((x) => x == '삭제').length == 2 && labels.containsKey('삭제');
        final title = titleNew ? 'new' : (titleOld ? 'old' : 'other');
        final closeLabel = labels.containsKey('닫기') ? 'new' : (labels.containsKey('취소') ? 'old' : 'other');
        final okEl = labels[ex.newTitle] ?? labels['삭제'];
        final okFill = okEl == null ? null : t.widget<Material>(find.ancestor(of: _el(okEl), matching: find.byType(Material)).first).color;
        final rp = t.renderObject<RenderParagraph>(find.descendant(of: bodyText, matching: find.byType(RichText), matchRoot: true).first);
        final m = _measure(rp);
        _out('D417 $tok dialog path=$path title=$title msg=$msg close=$closeLabel fill=${okFill == AppColors.errorDark ? 'errorDark' : 'other'} '
            'bad=${m.bad} ell=${m.ell} glyphX=${m.glyphX} lines=${m.lines}');
        must('최종 버튼 위험색 errorDark 그대로', okFill == AppColors.errorDark, '$okFill');
        if (_before) {
          must('before: 옛 결합 문구(제목 · 최종 삭제 · 닫기 취소)', title == 'old' && msg == 'old' && closeLabel == 'old', '$title/$msg/$closeLabel');
        } else {
          must('strict: 제목 · 최종 업무 동사 · 대상 질문(+기존 결과 설명) · 닫기 · 낱말 분절 0 · 말줄임 0 · 가로 0',
              title == 'new' && msg == 'new' && closeLabel == 'new' && m.bad == 0 && !m.ell && m.glyphX == 0, '$title/$msg/$closeLabel $m');
        }
        await shot('1dialog', '확인창');

        // 창 닫기만 — 최종 버튼은 누르지 않는다(writer 0)
        final closeEl = labels['닫기'] ?? labels['취소'];
        must('닫기 버튼 1', closeEl != null);
        await t.tapAt(t.getRect(find.ancestor(of: _el(closeEl!), matching: find.byType(InkWell)).first).center);
        await settle(12);
        final closed = find.byType(Dialog).evaluate().isEmpty;
        final kept = named(ex.keep).length;
        final toasts = [for (final x in ex.toasts) _vis(x).evaluate().length].fold<int>(0, (a, b) => a + b);
        _out('D417 $tok close closed=$closed kept=$kept rereads=${r.counts != c0} toast=$toasts');
        must('닫기 → 확인창 0 · 대상 그대로 · 다시 읽기 0 · 결과 안내 0', closed && kept == 1 && r.counts == c0 && toasts == 0, '$closed/$kept/${r.counts}/$toasts');

        final exc = t.takeException();
        _out('D417 $tok done state=${st.key} mode=$mode captures=$captures overflows=${overflows.length} exc=${exc != null}');
        await t.pumpWidget(const SizedBox.shrink());
        await settle(4);
        expect(exc, isNull);
        expect(overflows, isEmpty, reason: '$tok 넘침');
      });
    }
  }
}
