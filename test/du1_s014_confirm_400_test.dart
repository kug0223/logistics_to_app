// [DU400] S014 운영 종료 최종 확인 본문(소급 31 §3–§4) — 새 파일 · 정확 2 public(W 392x844@1.0 · B 320x640@2.0).
//   하네스: du1_s014_action_396 와 같은 fake core · 공용 vqLoadFonts · BusinessListReads(4곳) 패턴. 그 파일 · 공용 VQ · support 는 수정 0.
//   fixture: owner · 미종료 b1 '강남 물류센터' · preflight 3키 0 · truncated false · post 11 건수 2,3,1,4,2,5,1,6,7,1,2.
//   경로: 실제 목록 → b1 더보기 → '운영 종료' → debugPreview 정확 1회 → 최종 확인창 → 본문 실제 drag → 취소(실제 탭).
//   기대 문구는 제품 함수가 아닌 독립 전문(_oldMsg · _newMsg). DU_BEFORE_OBSERVE=400 이면 before(옛 두 문장 전문 정확), 아니면 strict(새 두 문장 전문 정확).
//   나머지 — 전 항목 · 건수 · 원문 semantics · 낱말 · 말줄임 · 가시 글자 가로 · 말단 도달 · 제목/버튼 receiver · hit · errorDark · 취소 · archive 0 ·
//   예외/넘침 0 — 은 두 모드 모두 엄격하다.
//   로컬 조판 측정(VQ 와 무관):
//     가시 글자 = U+0020 · U+00A0 · 개행 · U+2060 · U+200B 가 아닌 글자.
//     줄 전환 = 이웃 가시 글자의 줄(top)이 바뀐 곳. 그 사이 원문 구간에 개행이 있으면 명시 개행(허용), U+0020 이 있으면 공백 경계(허용),
//       그 밖(WJ 만 · 빈 구간 · NBSP)은 낱말 내부 분절(실패).
//     가로: 가시 글자 상자만 문단 폭 경계(±0.5)로 본다 — U+0020/U+00A0 상자의 가로 초과는 DU397 측정 수리 규칙대로 제외(기록).
//     세로(insideY · yOver)는 기록만. 말줄임(didExceedMaxLines)은 실패.
//     말단: 마지막 문장 원문 범위의 가시 글자 상자를 global 로 바꿔 본문 스크롤 viewport · 화면 안인지 본다.
// ignore_for_file: depend_on_referenced_packages
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
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_list_reads.dart';
import 'package:ALfit/screens/business_admin/business_list_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';

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

// 396 과 같은 4곳: b1 승인(owner · 미종료) · b2 승인 대기 · b3 운영 종료 · b4 승인(긴 이름)
final _four = [
  _biz('b1', '강남 물류센터', rating: 4.6, parking: true, meals: const ['중식']),
  _biz('b2', '송파 신선 분류센터', approved: false),
  _biz('b3', '성수 소형 창고', closed: true),
  _biz('b4', '[QA] 아주 긴 이름의 강남 물류센터 평택 제2공장 냉장 분류동',
      address: '경기도 평택시 포승읍 평택항로 268번길 45-12 물류단지 B동 3층', rating: 3.9, parking: true),
];

// 사전 조회 fixture — preflight 3키 0(차단 없음) · post 11 건수(PO-01 과 같은 값) · truncated false
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

// 독립 전문(제품 함수로 만들지 않는다). 옛 = 현행 e283b0b0, 새 = 승인 후보 7783c70f 의 두 어미.
const _old1 = '강남 물류센터 운영을 종료할까요? 일시 정지가 아니라 앞으로의 운영을 마치는 것입니다.';
const _new1 = '강남 물류센터 운영을 종료할까요? 일시 정지가 아니라 앞으로의 운영을 마치는 거예요.';
const _old2 = '기록은 지워지지 않고, 급여 탭과 계약 관리에서 계속 처리할 수 있습니다.';
const _new2 = '기록은 지워지지 않고, 급여 탭과 계약 관리에서 계속 처리할 수 있어요.';
const _middle = '\n'
    '\n'
    '종료하면서 정리되는 것 (근로자에게 알림)\n'
    '· 모집 중·예약 공고 2건 마감\n'
    '· 대기 중인 지원 3건 마감 (마감된 공고 포함)\n'
    '· 초대 1건 철회\n'
    '· 시작 전 확정·계약 대기 근무 4건 취소\n'
    '· 취소되는 근무의 미서명 계약 2건 무효\n'
    '\n'
    '종료 후에도 남아 계속 처리하는 것\n'
    '· 이미 시작했거나 지난 확정 근무 5건 · 그 미서명 계약 1건\n'
    '· 미지급 급여 6건 · 계산 전 근무 7건\n'
    '· 중간정산 대기 1건 · 승인 후 미이체 2건\n';
const _oldMsg = '$_old1$_middle$_old2';
const _newMsg = '$_new1$_middle$_new2';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '400';
final String _manifest = Platform.environment['DU400_MANIFEST'] ?? '(unset)';

const _wj = '\u2060';
const _zw = '\u200B';
const _nb = '\u00A0';
bool _visible(String ch) => ch != ' ' && ch != _nb && ch != '\n' && ch != _wj && ch != _zw;
String _hx(String s) => s.codeUnits.map((u) => u.toRadixString(16)).join('.');

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _hex(Color? c) => '0x${(c ?? Colors.transparent).toARGB32().toRadixString(16)}';

String _firstDiff(String a, String b) {
  var i = 0;
  while (i < a.length && i < b.length && a[i] == b[i]) {
    i++;
  }
  String win(String s) => s.substring(math.max(0, i - 12), math.min(s.length, i + 12)).replaceAll('\n', '⏎');
  return 'len ${a.length}/${b.length} 첫 차이 $i 실제=「${win(a)}」 기대=「${win(b)}」';
}

/// 로컬 조판 측정(위 머리 규칙). bad · glyphX 는 실패 목록, blankX · yOver 는 기록.
({int glyphs, int lines, int nl, int sp, List<String> bad, List<String> glyphX, List<String> blankX, double yOver, bool ell}) _measure(
    RenderParagraph rp) {
  final s = rp.text.toPlainText();
  final w = rp.size.width;
  final h = rp.size.height;
  final tops = <double>[];
  final bad = <String>[];
  final glyphX = <String>[];
  final blankX = <String>[];
  var glyphs = 0, nl = 0, sp = 0;
  var yOver = 0.0;
  int? prevI;
  double? prevTop;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final b = bx.first;
    if ((b.right - b.left).abs() < 0.01) continue;
    final xOut = b.right > w + 0.5 || b.left < -0.5;
    if (xOut && (ch == ' ' || ch == _nb)) blankX.add('$i:${_hx(ch)}:${b.left.toStringAsFixed(2)}-${b.right.toStringAsFixed(2)}');
    if (!_visible(ch)) continue;
    if (xOut) glyphX.add('$i:${_hx(ch)}:${b.left.toStringAsFixed(2)}-${b.right.toStringAsFixed(2)}');
    yOver = math.max(yOver, math.max(-b.top, b.bottom - h));
    glyphs++;
    if (prevTop != null && (b.top - prevTop).abs() > 1.0) {
      final between = s.substring(prevI! + 1, i);
      if (between.contains('\n')) {
        nl++;
      } else if (between.contains(' ')) {
        sp++;
      } else {
        bad.add('$i[${_hx(s[prevI])}→${_hx(ch)} 사이=${_hx(between)}]');
      }
    }
    if (!tops.any((x) => (x - b.top).abs() <= 1.0)) tops.add(b.top);
    prevI = i;
    prevTop = b.top;
  }
  return (glyphs: glyphs, lines: tops.length, nl: nl, sp: sp, bad: bad, glyphX: glyphX, blankX: blankX, yOver: yOver, ell: rp.didExceedMaxLines);
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
          (_) async => codec.encodeMessage(<Object?>['du400.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du400.fake.$m'), (_) async => null);
    }
  });

  for (final c in const [
    (id: 'W', w: 392.0, h: 844.0, s: 1.0, name: 'S014F-W 최종 확인 본문 392x844@1.0 — 해요체·전 항목·낱말·스크롤 말단·고정 버튼·취소'),
    (id: 'B', w: 320.0, h: 640.0, s: 2.0, name: 'S014F-B 최종 확인 본문 320x640@2.0 — 해요체·전 항목·낱말·스크롤 말단·고정 버튼·취소'),
  ]) {
    testWidgets(c.name, (t) async {
      final tok = 'S014F-${c.id}';
      final mode = _before ? 'before' : 'strict';
      final expected = _before ? _oldMsg : _newMsg;
      _out('D400 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} manifest=$_manifest');
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
      t.view.physicalSize = Size(c.w, c.h);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final previewCalls = <String>[];
      var archiveCalls = 0;
      BusinessListScreen.debugPreview = (id) async {
        previewCalls.add(id);
        return Map<String, dynamic>.from(_preview);
      };
      BusinessListScreen.debugArchive = (id, counts) async {
        archiveCalls++;
      };
      addTearDown(() {
        BusinessListScreen.debugPreview = null;
        BusinessListScreen.debugArchive = null;
      });
      final screen = Offset.zero & Size(c.w, c.h);
      bool inRect(Rect o, Rect r) => r.top >= o.top - 0.5 && r.bottom <= o.bottom + 0.5 && r.left >= o.left - 0.5 && r.right <= o.right + 0.5;
      void must(String k, bool v, [String why = '']) => expect(v, isTrue, reason: '$tok $k $why');
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

      // ── 목록 ──
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => _Provider(ids: [for (final b in _four) b.id])),
            ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.businessAdminTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: BusinessListScreen(
                reads: BusinessListReads(businessById: (_) async => _four.first, businessesByIds: (_) async => _four)),
          ),
        ),
      ));
      await settle(16);
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
      final er = t.getRect(endItem);
      must('운영 종료 항목 화면 안', inRect(screen, er), '$er');
      await t.tapAt(er.center);
      await settle(16);

      // ── 최종 확인창 ──
      must('사전 조회 = 같은 businessId 정확 1회', previewCalls.length == 1 && previewCalls.first == b1.id, '$previewCalls');
      final title = findVisibleText('사업장 운영 종료');
      must('확인창 제목 1', title.evaluate().length == 1);
      final dialog = find.ancestor(of: title, matching: find.byType(Dialog));
      must('확인창 Dialog 1', dialog.evaluate().length == 1);
      final surface = find.descendant(of: dialog, matching: find.byType(Material)).first; // 확인창 면(Dialog 자체 rect 는 inset 을 포함한 화면 전체)
      final scrollF = find.descendant(of: dialog, matching: find.byType(Scrollable));
      must('확인창 본문 스크롤 주인 정확 1', scrollF.evaluate().length == 1, '${scrollF.evaluate().length}');
      final bodyText = find.descendant(of: scrollF, matching: find.byType(Text));
      must('본문 Text 정확 1(한 Text)', bodyText.evaluate().length == 1, '${bodyText.evaluate().length}');
      final data = t.widget<Text>(bodyText).data ?? '';
      final shown = visibleText(data);
      _out('D400 $tok sentences new1=${shown.contains(_new1)} new2=${shown.contains(_new2)} old1=${shown.contains(_old1)} old2=${shown.contains(_old2)}');
      final lineMiss = [for (final l in expected.split('\n')) if (!shown.split('\n').contains(l)) l];
      must('본문 줄 전부 존재(건수 · 정리/존치 · 알림 · 비삭제 · 후속)', lineMiss.isEmpty, '$lineMiss');
      must('본문 전문 = 독립 기대($mode)', shown == expected, _firstDiff(shown, expected));
      if (_before) {
        must('before: 옛 두 문장 정확 · 새 두 문장 0', shown.contains(_old1) && shown.contains(_old2) && !shown.contains(_new1) && !shown.contains(_new2));
      } else {
        must('strict: 새 두 문장 정확 · 옛 두 문장 0', shown.contains(_new1) && shown.contains(_new2) && !shown.contains(_old1) && !shown.contains(_old2));
      }
      // 원문 semantics — 낱말 묶기 표시(WJ)면 원문 label 의 Semantics 가 감싸고, 아니면 Text 자신이 원문이다.
      final keep = data != shown;
      final semOk = keep
          ? find
                  .ancestor(
                      of: bodyText,
                      matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.label == expected))
                  .evaluate()
                  .length ==
              1
          : data == expected;
      must('원문 semantics 연결(keep=$keep)', semOk);
      final okText = find.descendant(of: dialog, matching: findVisibleText('운영 종료'));
      final cancelText = find.descendant(of: dialog, matching: findVisibleText('취소'));
      must('확인창 버튼 운영 종료 1 · 취소 1', okText.evaluate().length == 1 && cancelText.evaluate().length == 1);
      final okInk = find.ancestor(of: okText, matching: find.byType(InkWell)).first;
      final cancelInk = find.ancestor(of: cancelText, matching: find.byType(InkWell)).first;
      final okFill = t.widget<Material>(find.ancestor(of: okText, matching: find.byType(Material)).first).color;
      must('최종 실행 채움 errorDark(그대로)', okFill == AppColors.errorDark, _hex(okFill));
      final rp = t.renderObject<RenderParagraph>(find.descendant(of: bodyText, matching: find.byType(RichText), matchRoot: true).first);
      final pos = t.state<ScrollableState>(scrollF).position;

      // 마지막 문장 가시 글자 상자(global) — 원문 범위를 표시 문자열 인덱스로 옮긴다(WJ · ZWSP 만 표시에 더해진다)
      final plain = rp.text.toPlainText();
      final idx = <int>[];
      final norm = StringBuffer();
      for (var i = 0; i < plain.length; i++) {
        if (plain[i] == _wj || plain[i] == _zw) continue;
        idx.add(i);
        norm.write(plain[i] == _nb ? ' ' : plain[i]);
      }
      final tail = _before ? _old2 : _new2;
      final ns = norm.toString();
      must('표시 문자열 정규화 = 기대 · 마지막 문장이 끝', ns == expected && ns.endsWith(tail));
      final tailRaw = [for (var k = ns.length - tail.length; k < ns.length; k++) if (_visible(ns[k])) idx[k]];
      List<Rect> tailRects() {
        final m = rp.getTransformTo(null);
        final out = <Rect>[];
        for (final i in tailRaw) {
          final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
          if (bx.isEmpty) continue;
          out.add(MatrixUtils.transformRect(m, bx.first.toRect()));
        }
        return out;
      }

      String stageCheck(String stage) {
        final dr = t.getRect(surface);
        final vp = t.getRect(scrollF);
        final tr = t.getRect(title);
        must('$stage 제목 화면 · 확인창 안 · 본문 viewport 위', inRect(screen, tr) && inRect(dr, tr) && tr.bottom <= vp.top + 0.5, '$tr / $vp');
        must('$stage 본문 viewport 화면 · 확인창 안', inRect(screen, vp) && inRect(dr, vp), '$vp');
        for (final (label, ink, txt) in [('운영 종료', okInk, okText), ('취소', cancelInk, cancelText)]) {
          final r = t.getRect(ink);
          final lr = t.getRect(txt);
          final hits = [r.center, r.topLeft + const Offset(5, 5), r.bottomRight - const Offset(5, 5)].every((p) => hitIn(ink, p));
          must('$stage $label receiver 화면 · 확인창 안 · 본문 viewport 아래 · ≥48 · 글 안 · 중앙/모서리 hit',
              inRect(screen, r) && inRect(dr, r) && r.top >= vp.bottom - 0.5 && r.height >= 47.99 && inRect(r, lr) && hits, '$r / $vp');
        }
        final rs = tailRects();
        final inside = rs.isNotEmpty && rs.length == tailRaw.length && rs.every((r) => inRect(vp, r) && inRect(screen, r));
        final s = '$stage offset=${pos.pixels.toStringAsFixed(2)}/${pos.maxScrollExtent.toStringAsFixed(2)} vp=$vp tail=${rs.where((r) => inRect(vp, r)).length}/${tailRaw.length} '
            'last=${rs.isEmpty ? '-' : rs.last} ok=${t.getRect(okInk)} cancel=${t.getRect(cancelInk)}';
        _out('D400 $tok stage $s');
        return inside ? 'in' : 'out';
      }

      final cond = {
        'viewport': '${c.w.toInt()}x${c.h.toInt()}',
        'textScaler': c.s,
        'fixture': 'owner b1 강남 물류센터 · preflight 0/0/0 · post 2,3,1,4,2,5,1,6,7,1,2 · truncated false',
        'mode': mode,
        'run': vqRun,
        'manifest': _manifest,
      };
      final m0 = _measure(rp);
      _out('D400 $tok measure glyphs=${m0.glyphs} lines=${m0.lines} nl=${m0.nl} sp=${m0.sp} bad=${m0.bad} glyphX=${m0.glyphX} '
          'blankX=${m0.blankX} yOver=${m0.yOver.toStringAsFixed(3)} ell=${m0.ell} keep=$keep para=${rp.size}');
      must('본문 낱말 내부 분절 0', m0.bad.isEmpty, '${m0.bad}');
      must('본문 가시 글자 가로 경계 안', m0.glyphX.isEmpty, '${m0.glyphX}');
      must('본문 말줄임 0', !m0.ell);
      must('본문 명시 개행 전환 11(비어 있지 않은 원문 줄 12)', m0.nl == 11, '${m0.nl}');
      for (final (label, f) in [('제목', title), ('운영 종료', okText), ('취소', cancelText)]) {
        final mm = _measure(t.renderObject<RenderParagraph>(find.descendant(of: f, matching: find.byType(RichText), matchRoot: true).first));
        must('$label 낱말 내부 분절 0 · 가시 가로 안 · 말줄임 0', mm.bad.isEmpty && mm.glyphX.isEmpty && !mm.ell, '${mm.bad} ${mm.glyphX}');
      }
      final max0 = pos.maxScrollExtent;
      final px0 = pos.pixels;
      final top = stageCheck('초기');
      await vqCapture(t, key, '${tok}_1top', conditions: {...cond, 'stage': '초기', 'offset': px0, 'maxScroll': max0, 'tail': top});
      var drags = 0;
      String mid;
      String end;
      if (c.id == 'B') {
        must('B 본문 maxScroll > 0(스크롤 필요)', max0 > 0.5, '$max0');
      }
      if (max0 > 0.5) {
        await t.drag(scrollF, Offset(0, -(max0 / 2)));
        drags++;
        await settle(8);
        must('첫 drag 뒤 offset 증가', pos.pixels > px0 + 0.5, '${pos.pixels}');
        mid = stageCheck('중간');
        await vqCapture(t, key, '${tok}_2mid', conditions: {...cond, 'stage': '중간', 'offset': pos.pixels, 'maxScroll': pos.maxScrollExtent, 'tail': mid});
        for (var k = 0; k < 20 && pos.pixels < pos.maxScrollExtent - 0.5; k++) {
          await t.drag(scrollF, const Offset(0, -200));
          drags++;
          await settle(8);
        }
        must('본문 말단 도달(offset = maxScroll)', pos.pixels >= pos.maxScrollExtent - 0.5, '${pos.pixels}/${pos.maxScrollExtent}');
        end = stageCheck('말단');
      } else {
        _out('D400 $tok noscroll 전문 이미 표시 · maxScroll ${max0.toStringAsFixed(2)} · 이동 0');
        mid = stageCheck('중간(이동 0)');
        await vqCapture(t, key, '${tok}_2mid', conditions: {...cond, 'stage': '중간(이동 0 — 초기와 같은 상태)', 'offset': pos.pixels, 'maxScroll': max0, 'tail': mid});
        end = stageCheck('말단(이동 0)');
      }
      must('말단에서 마지막 문장 가시 글자 전부 본문 viewport · 화면 안', end == 'in');
      await vqCapture(t, key, '${tok}_3end', conditions: {...cond, 'stage': '말단', 'offset': pos.pixels, 'maxScroll': pos.maxScrollExtent, 'tail': end, 'drags': drags});
      final m1 = _measure(rp);
      must('말단 측정 = 초기 측정(배치 불변)', m1.glyphs == m0.glyphs && m1.lines == m0.lines && m1.bad.isEmpty && m1.glyphX.isEmpty && !m1.ell);

      // ── 취소(실제 탭) — 실행 버튼은 hit 만 확인했다 ──
      final cr = t.getRect(cancelInk);
      await t.tapAt(cr.center);
      await settle(16);
      must('취소 → 확인창 닫힘', title.evaluate().isEmpty && find.byType(Dialog).evaluate().isEmpty);
      must('취소 뒤 archive 호출 0', archiveCalls == 0, '$archiveCalls');
      must('취소 뒤 목록 유지', findVisibleText(b1.name).evaluate().length == 1);
      must('사전 조회 총 1', previewCalls.length == 1);
      final exc = t.takeException();
      _out('D400 $tok done mode=$mode maxScroll=${max0.toStringAsFixed(2)} drags=$drags tail=$top/$mid/$end glyphs=${m0.glyphs} lines=${m0.lines} '
          'nl=${m0.nl} sp=${m0.sp} bad=${m0.bad.length} glyphX=${m0.glyphX.length} blankX=${m0.blankX.length} yOver=${m0.yOver.toStringAsFixed(3)} '
          'ell=${m0.ell} archive=$archiveCalls preview=${previewCalls.length} overflows=${overflows.length} exc=${exc != null}');
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 1));
      expect(exc, isNull);
      expect(overflows, isEmpty, reason: '$tok 넘침');
    });
  }
}
