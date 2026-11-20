// [DU410 · 소급 39 §6.2 채택 셀] S014 사업장 목록 토스트 묶음(plan_r1) — 새 파일 · 정확 6 public(W 392x844@1.0 · B 320x640@2.0 × ERR · ARCHOK · ARCHFAIL) · 캡처 8쌍.
//   출력 줄은 공용 L 도구(lkit v1) 선언형 계약 형식: 'D410 <tok> <kind> [<sub>] k=v …' — 값에 공백 0.
//   하네스: du1_s014_confirm_400 와 같은 fake core · _Provider · 4곳 fixture · 사전 조회 fixture. 그 파일 · 공용 VQ · support · ToastHelper 는 수정 0.
//   토스트가 실제로 뜨도록 MaterialApp 에 전역 navigatorKey 를 건다(ToastHelper 는 navigatorKey.overlay 에 넣는다 — 400 시험은 걸지 않아 토스트 0 이었다).
//   모드: DU_BEFORE_OBSERVE=410 이면 before(현행 7783c70f — 읽기 실패 토스트 1 · 옛 문장), 아니면 strict(후보 — 읽기 실패 토스트 0 · 새 문장).
//   ERR     : 읽기 throw → 오류 본문 1 → '다시 시도' 실제 탭 → 다시 throw. 두 시점 모두 본문 1 · 토스트(before 1 / strict 0) · 재시도 receiver ≥48 · hit.
//             토스트 = 화면(BusinessListScreen) 밖에 있는 같은 계열 문장. 본문 제목과 같은 문장이 토스트로 하나 더 떠도 strict 실패다(문구만 바꾼 대안 A 차단).
//   ARCHOK  : 목록 → b1 더보기 → '운영 종료' → 사전 조회 1 → 확인창 '운영 종료' 실제 탭 → archive 1(확인한 사전 조회 그대로) → 성공 토스트 → 재조회 1.
//   ARCHFAIL: 위와 같으나 archive 가 일반 예외 → 실패 토스트 · 재조회 0 · 목록 유지.
//   토스트 글: 낱말 내부 분절 0 · 가시 가로 안 · 말줄임 0 · 화면 안. 토스트 가림은 관측으로만 기록한다(위치는 공용 셀 후보).
//   누름: 더보기 · 시트 '운영 종료' · 확인창 '운영 종료' · '다시 시도'. 실제 서버 · writer 0(fake seam).
// [H-3 E 추종 · DU414] ARCHOK · ARCHFAIL strict: 운영 종료 결과 = 화면 안 결과 띠 1 · overlay 토스트 0(같은 새 문장). before · ERR 그대로.
// ignore_for_file: depend_on_referenced_packages
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
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_list_reads.dart';
import 'package:ALfit/screens/business_admin/business_list_screen.dart';
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

// 396 · 400 과 같은 4곳
final _four = [
  _biz('b1', '강남 물류센터', rating: 4.6, parking: true, meals: const ['중식']),
  _biz('b2', '송파 신선 분류센터', approved: false),
  _biz('b3', '성수 소형 창고', closed: true),
  _biz('b4', '[QA] 아주 긴 이름의 강남 물류센터 평택 제2공장 냉장 분류동',
      address: '경기도 평택시 포승읍 평택항로 268번길 45-12 물류단지 B동 3층', rating: 3.9, parking: true),
];

// 400 과 같은 사전 조회(차단 0 · truncated false)
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
const _errBody = '사업장 목록을 불러오지 못했어요'; // 오류 본문 제목(두 모드 같음)
const _errSub = '잠시 후 다시 시도해 주세요';
const _errToastOld = '사업장 목록을 불러오는데 실패했습니다';
const _okOld = '사업장 운영을 종료했습니다';
const _okNew = '사업장 운영을 종료했어요';
const _failOld = '사업장 운영 종료에 실패했습니다';
const _failNew = '사업장 운영을 종료하지 못했어요';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '410';
// 공용 L 도구(lkit v1)의 고정 env 14 키 — 셀 번호 키를 더 늘리지 않고 manifest 는 DUL_MANIFEST 하나로 받는다.
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

/// 로컬 조판 측정(406 · 407 과 같은 규칙): 낱말 분절 · 가시 가로 초과 · 말줄임 · 줄 수.
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

class _Reads {
  _Reads({this.fail = false});

  final bool fail;
  var calls = 0;

  BusinessListReads get reads => BusinessListReads(
        businessById: (_) async {
          calls++;
          if (fail) throw StateError('DU410 fake 사업장 조회 실패');
          return _four.first;
        },
        businessesByIds: (_) async {
          calls++;
          if (fail) throw StateError('DU410 fake 사업장 목록 조회 실패');
          return _four;
        },
      );
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
          (_) async => codec.encodeMessage(<Object?>['du410.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du410.fake.$m'), (_) async => null);
    }
  });

  const views = [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const states = [
    (key: 'ERR', title: '첫·재시도 읽기 실패 — 오류 본문 1 · 토스트 정책'),
    (key: 'ARCHOK', title: '운영 종료 성공 — 성공 결과 띠 해요체 · 재조회 1'),
    (key: 'ARCHFAIL', title: '운영 종료 일반 실패 — 실패 결과 띠 해요체 · 목록 유지'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S014T-${v.id}-${st.key} ${st.title}', (t) async {
        final tok = 'S014T-${v.id}-${st.key}';
        final mode = _before ? 'before' : 'strict';
        _out('D410 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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

        bool hitIn(Finder f, Offset p) {
          final hr = HitTestResult();
          WidgetsBinding.instance.hitTestInView(hr, p, t.view.viewId);
          final ro = t.renderObject(f);
          return hr.path.any((e) => e.target == ro);
        }

        final key = GlobalKey();
        // run.txt 7 키(407 관례): viewport · textScaler · run · manifest · mode · fixture(=상태 키) · state(단계 문구)
        final cond = {'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': st.key};
        var captures = 0;
        Future<void> shot(String id, String stage) async {
          await vqCapture(t, key, '${tok}_$id', conditions: {...cond, 'state': stage});
          captures++;
        }

        final scr = find.byType(BusinessListScreen);
        // 화면 안(본문) / 화면 밖(overlay 토스트) 개수 — 같은 문장이 둘 다에 있으면 각각 센다
        int inside(String s) => find.descendant(of: scr, matching: _vis(s), skipOffstage: false).evaluate().length;
        int outside(String s) => _vis(s).evaluate().length - inside(s);
        Element? toastEl(List<String> ss) {
          for (final s in ss) {
            final ins = find.descendant(of: scr, matching: _vis(s), skipOffstage: false).evaluate().toSet();
            for (final e in _vis(s).evaluate()) {
              if (!ins.contains(e)) return e;
            }
          }
          return null;
        }

        Rect? toastRect(Element? e) {
          if (e == null) return null;
          final box = _ancestor(e, (w) => w is IgnorePointer);
          return box == null ? null : t.getRect(_el(box));
        }

        void toastText(String label, Element e) {
          final rp = t.renderObject<RenderParagraph>(find.descendant(of: _el(e), matching: find.byType(RichText), matchRoot: true).first);
          final m = _measure(rp);
          final tr = toastRect(e);
          _out('D410 $tok toast $label lines=${m.lines} bad=${m.bad} glyphX=${m.glyphX} ell=${m.ell} rect=${tr == null ? '-' : _r(tr)}');
          must('$label 토스트 낱말 분절 0 · 가시 가로 안 · 말줄임 0', m.bad == 0 && m.glyphX == 0 && !m.ell, '${m.bad}/${m.glyphX}/${m.ell}');
          must('$label 토스트 면 화면 안', tr != null && inRect(screen, tr), '$tr');
        }

        // [H-3 E 추종] strict = 화면 안 결과 띠(같은 새 문장) — 토스트와 같은 조판 단언 · 띠 글 화면 안
        void bandText(String label, String s) {
          final els = find.descendant(of: scr, matching: _vis(s), skipOffstage: false).evaluate().toList();
          must('$label 결과 띠 글 정확 1', els.length == 1, '${els.length}');
          final rp = t.renderObject<RenderParagraph>(find.descendant(of: _el(els.single), matching: find.byType(RichText), matchRoot: true).first);
          final m = _measure(rp);
          final br = t.getRect(_el(els.single));
          _out('D410 $tok band $label lines=${m.lines} bad=${m.bad} glyphX=${m.glyphX} ell=${m.ell} rect=${_r(br)}');
          must('$label 결과 띠 낱말 분절 0 · 가시 가로 안 · 말줄임 0', m.bad == 0 && m.glyphX == 0 && !m.ell, '${m.bad}/${m.glyphX}/${m.ell}');
          must('$label 결과 띠 글 화면 안', inRect(screen, br), '$br');
        }

        final reads = _Reads(fail: st.key == 'ERR');
        final previewCalls = <String>[];
        final archived = <Map<String, dynamic>>[];
        BusinessListScreen.debugPreview = (id) async {
          previewCalls.add(id);
          return Map<String, dynamic>.from(_preview);
        };
        BusinessListScreen.debugArchive = (id, expected) async {
          archived.add(Map<String, dynamic>.from(expected));
          if (st.key == 'ARCHFAIL') throw StateError('DU410 fake 운영 종료 실패');
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
              home: BusinessListScreen(reads: reads.reads),
            ),
          ),
        ));
        await settle(16);

        if (st.key == 'ERR') {
          void errCheck(String stage, int wantReads) {
            final body = inside(_errBody), sub = inside(_errSub);
            final tOld = outside(_errToastOld), tSame = outside(_errBody), bOld = inside(_errToastOld);
            final te = toastEl([_errToastOld, _errBody]);
            final tr = toastRect(te);
            final retryText = find.descendant(of: scr, matching: _vis('다시 시도'));
            must('$stage 다시 시도 글 1', retryText.evaluate().length == 1, '${retryText.evaluate().length}');
            final ink = _ancestor(retryText.evaluate().first, (w) => w is InkWell);
            must('$stage 다시 시도 InkWell', ink != null);
            final rr = t.getRect(_el(ink!));
            final hit = hitIn(_el(ink), rr.center);
            final covered = tr != null && rr.intersect(tr).width > 0.5 && rr.intersect(tr).height > 0.5;
            _out('D410 $tok $stage body=$body sub=$sub toastOld=$tOld toastSame=$tSame bodyOld=$bOld retry=${_r(rr)} hit=$hit '
                'toast=${tr == null ? '-' : _r(tr)} covered=$covered reads=${reads.calls}');
            must('$stage 읽기 호출 $wantReads', reads.calls == wantReads, '${reads.calls}');
            must('$stage 오류 본문 제목 1 · 부제 1 · 본문 옛 토스트 문장 0', body == 1 && sub == 1 && bOld == 0, '$body/$sub/$bOld');
            if (_before) {
              must('$stage before: 옛 토스트 1 · 본문 같은 문장 토스트 0', tOld == 1 && tSame == 0, '$tOld/$tSame');
              toastText(stage, te!);
            } else {
              must('$stage strict: 토스트 0(옛 문장 0 · 본문과 같은 문장 0)', tOld == 0 && tSame == 0 && te == null, '$tOld/$tSame');
            }
            must('$stage 다시 시도 receiver 화면 안 · ≥48 · 중앙 hit', inRect(screen, rr) && rr.height >= 47.99 && hit, '${_r(rr)} $hit');
          }

          errCheck('first', 1);
          await shot('1first', '첫 읽기 실패');
          final retry = find.descendant(of: scr, matching: _vis('다시 시도'));
          await t.tapAt(t.getRect(_el(_ancestor(retry.evaluate().first, (w) => w is InkWell)!)).center);
          await settle(16);
          errCheck('retry', 2);
          await shot('2retry', '다시 시도 뒤 다시 실패');
          must('ERR 사전 조회 · archive 0', previewCalls.isEmpty && archived.isEmpty);
        } else {
          final b1 = _four.first;
          final name = findVisibleText(b1.name);
          must('b1 이름 1', name.evaluate().length == 1);
          final card = find.ancestor(of: name, matching: find.byType(InkWell)).first;
          await t.ensureVisible(card);
          await settle(6);
          final more = find.descendant(of: card, matching: find.byType(IconButton));
          must('b1 카드 귀속 더보기 1', more.evaluate().length == 1);
          final mr = t.getRect(more);
          must('b1 더보기 화면 안 · 중앙 hit', inRect(screen, mr) && hitIn(more, mr.center), '$mr');
          await t.tapAt(mr.center);
          await settle(12);
          final sheet = find.byType(BottomSheet);
          must('더보기 탭 → 시트 1', sheet.evaluate().length == 1);
          final endItem = find.descendant(of: sheet, matching: findVisibleText('운영 종료'));
          must('시트 운영 종료 1', endItem.evaluate().length == 1);
          await t.tapAt(t.getRect(endItem).center);
          await settle(16);
          must('사전 조회 = b1 정확 1회', previewCalls.length == 1 && previewCalls.first == b1.id, '$previewCalls');
          final title = findVisibleText('사업장 운영 종료');
          must('확인창 제목 1', title.evaluate().length == 1);
          final dialog = find.ancestor(of: title, matching: find.byType(Dialog));
          final okText = find.descendant(of: dialog, matching: findVisibleText('운영 종료'));
          must('확인창 운영 종료 버튼 1', okText.evaluate().length == 1);
          final okInk = find.ancestor(of: okText, matching: find.byType(InkWell)).first;
          final okR = t.getRect(okInk);
          must('확인창 운영 종료 receiver 화면 안 · 중앙 hit', inRect(screen, okR) && hitIn(okInk, okR.center), '$okR');
          await t.tapAt(okR.center);
          await settle(16);
          must('확인창 닫힘', title.evaluate().isEmpty && find.byType(Dialog).evaluate().isEmpty);
          must('archive 정확 1 · 확인한 사전 조회 그대로', archived.length == 1 && archived.first.length == _preview.length &&
              _preview.entries.every((e) => archived.first[e.key] == e.value), '$archived');
          final ok = st.key == 'ARCHOK';
          final oldS = ok ? _okOld : _failOld, newS = ok ? _okNew : _failNew;
          final tOld = outside(oldS), tNew = outside(newS);
          final others = [_okOld, _okNew, _failOld, _failNew, _errToastOld, _errBody].where((s) => s != oldS && s != newS).map(outside).fold<int>(0, (a, b) => a + b);
          _out('D410 $tok result toastOld=$tOld toastNew=$tNew others=$others reads=${reads.calls} b1=${findVisibleText(b1.name).evaluate().length}');
          if (_before) {
            must('before: 옛 문장 토스트 1 · 새 0', tOld == 1 && tNew == 0, '$tOld/$tNew');
          } else {
            // [H-3 E] 결과는 화면 안 띠 — overlay 새 문장 0 · 화면 안 새 문장 1 · 옛 문장 0(안 · 밖)
            must('strict: 새 문장 결과 띠 1 · overlay 0 · 옛 0', inside(newS) == 1 && tNew == 0 && tOld == 0 && inside(oldS) == 0,
                '${inside(newS)}/$tNew/$tOld/${inside(oldS)}');
          }
          must('다른 토스트 문장 0', others == 0, '$others');
          if (_before) {
            toastText(st.key, toastEl([oldS])!);
          } else {
            bandText(st.key, newS);
          }
          must(ok ? '성공 뒤 재조회 1(읽기 2)' : '실패 뒤 재조회 0(읽기 1)', reads.calls == (ok ? 2 : 1), '${reads.calls}');
          must('목록 유지(b1 이름 1)', findVisibleText(b1.name).evaluate().length == 1);
          await shot('1done', ok ? '운영 종료 성공 토스트' : '운영 종료 실패 토스트');
        }

        final exc = t.takeException();
        _out('D410 $tok done state=${st.key} mode=$mode captures=$captures reads=${reads.calls} preview=${previewCalls.length} archive=${archived.length} '
            'overflows=${overflows.length} exc=${exc != null}');
        await t.pump(const Duration(seconds: 5)); // 토스트 수명 timer 소진
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 1));
        expect(exc, isNull);
        expect(overflows, isEmpty, reason: '$tok 넘침');
      });
    }
  }
}
