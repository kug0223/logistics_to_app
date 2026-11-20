// [DU418 추종 · 판정55 §4-1] 빠른 정보 긍정 라벨('주차 가능' · '식사 제공') 기대색 successDark → textTertiary(단순 사실 중립 메타색). 그 밖 변경 0.
// [DU395] S014 사업장 목록 문구(소급 24 §3–§4) — 하네스는 du1_s014_color_392 바탕(_Provider · 4곳 fixture · vqLoadFonts).
//   W 392x844@1.0 · B 320x640@2.0 × 목록(L) / 소유자 빈 상태(E) / SubAdmin 빈 상태(U) = 정확 6 public 시험.
//   제품 기대(기본 단언, DU_BEFORE_OBSERVE=395 는 기록만):
//     L ① 카드마다 새 라벨 2개('주차 가능/불가' · '식사 제공/미제공', fixture 판정식으로 기대) 각 정확 1 · 옛 'O/X' 라벨 0
//       ② 라벨 전문(보이는 글자 = 라벨) · 실제 도달(표시 영역 · 화면 안) · 말줄임 0 · 낱말 안 줄바꿈 0
//       ③ 평점 · 주차 · 식사 서로 겹침 0 · 읽는 순서 평점 → 주차 → 식사
//       ④ 구분선마다 같은 줄 왼쪽 · 오른쪽에 항목이 있다(혼자 남는 구분선 0)
//       ⑤ 라벨 색 = 가능/제공 successDark · 불가/미제공 textTertiary, 실제 바탕 대비 ≥ 4.5 — 카드마다 2건을 실제로 검사
//     E 제목 '등록된 사업장이 없어요' · 안내 '사업장을 등록하고 공고를 관리해 보세요' 각 1 · 옛 문구 0
//     U 제목 '배정된 사업장이 없어요' 1 · 옛 문구 0
//   불변(항상 단언): 4곳 도달 · 넘침 0 · 예외 0 · 소유자 등록 CTA 있음 · SubAdmin 등록 CTA 없음 · SubAdmin 안내 문구 그대로.
//   기록만: 카드 높이 · 빠른 정보 줄 수 · 더보기 메뉴 rect(카드 위로 맞춘 뒤).
// ignore_for_file: depend_on_referenced_packages, unused_element
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
        managedBusinessIds: ids,
        subAdminBusinessIds: subAdmin ? ids : const [],
      );
  @override
  bool get isSubAdmin => subAdmin;
  @override
  bool get isBusinessAdmin => !subAdmin;
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

// 392 와 같은 4곳: 평점 유무 · 주차/식사 양음성(b1 가능·제공 / b2·b3 불가·미제공 / b4 가능·미제공)
final _four = [
  _biz('b1', '강남 물류센터', rating: 4.6, parking: true, meals: const ['중식']),
  _biz('b2', '송파 신선 분류센터', approved: false),
  _biz('b3', '성수 소형 창고', closed: true),
  _biz('b4', '[QA] 아주 긴 이름의 강남 물류센터 평택 제2공장 냉장 분류동',
      address: '경기도 평택시 포승읍 평택항로 268번길 45-12 물류단지 B동 3층', rating: 3.9, parking: true),
];

// fixture 판정식(제품과 독립으로 적은 기대): 주차 = parkingAvailable, 식사 = mealsProvided 가 비어 있지 않음
(String, Color) _parkingExpect(BusinessModel b) =>
    b.parkingAvailable ? ('주차 가능', AppColors.textTertiary) : ('주차 불가', AppColors.textTertiary);
(String, Color) _mealExpect(BusinessModel b) => (b.mealsProvided != null && b.mealsProvided!.isNotEmpty)
    ? ('식사 제공', AppColors.textTertiary)
    : ('식사 미제공', AppColors.textTertiary);

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '395';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

// 글자의 실제 바탕 — 가장 가까운 불투명(흰 위 합성) 면(392 와 같은 helper)
Color _bgOf(Element e) {
  Color? found;
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
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
    }
    if (c == null || c.a == 0) return true;
    found = Color.alphaBlend(c, Colors.white);
    return false;
  });
  return found ?? Colors.white;
}

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

RenderParagraph _para(WidgetTester t, Finder f) =>
    t.renderObject<RenderParagraph>(find.descendant(of: f, matching: find.byType(RichText), matchRoot: true).first);

// 줄 수와 낱말 안 줄바꿈: 글자별 첫 box top 이 바뀌는 자리의 앞 글자가 공백이 아니면 낱말 안 줄바꿈
(int, bool) _lines(RenderParagraph rp) {
  final s = rp.text.toPlainText();
  final tops = <double>[];
  var wordOk = true;
  double? prev;
  for (var i = 0; i < s.length; i++) {
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty || (bx.first.right - bx.first.left).abs() < 0.01) continue;
    final top = bx.first.top;
    if (prev == null || (top - prev).abs() > 1.0) {
      if (prev != null && (i == 0 || s[i - 1] != ' ')) wordOk = false;
      if (!tops.any((x) => (x - top).abs() <= 1.0)) tops.add(top);
    }
    prev = top;
  }
  return (tops.length, wordOk);
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
          (_) async => codec.encodeMessage(<Object?>['du395.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du395.fake.$m'), (_) async => null);
    }
  });

  Future<(GlobalKey, List<String>)> pump(WidgetTester t, ({String id, double w, double h, double s}) c,
      {required bool subAdmin, required List<BusinessModel> items}) async {
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
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>(
              create: (_) => _Provider(subAdmin: subAdmin, ids: [for (final b in items) b.id])),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.businessAdminTheme,
          builder: (ctx, child) =>
              MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
          home: BusinessListScreen(
              reads: BusinessListReads(
                  businessById: (_) async => items.isEmpty ? null : items.first, businessesByIds: (_) async => items)),
        ),
      ),
    ));
    for (var i = 0; i < 16; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    return (key, overflows);
  }

  Future<void> settle(WidgetTester t, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  for (final c in const [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)]) {
    // ── L: 목록 빠른 정보 문구 ──
    testWidgets('S014T-${c.id}-L 사업장 목록 빠른 정보 문구 · 전문 · 줄바꿈 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
      final (key, overflows) = await pump(t, c, subAdmin: false, items: _four);
      final tag = 'S014T-${c.id}-L';
      final cond = {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s};
      await vqCapture(t, key, '${tag}_1top', conditions: {...cond, 'state': '관리자 4곳 첫 화면'});
      final scroll = find.byType(Scrollable).first;
      final screen = Offset.zero & Size(c.w, c.h);
      bool inRect(Rect o, Rect r) => r.top >= o.top - 0.5 && r.bottom <= o.bottom + 0.5 && r.left >= o.left - 0.5 && r.right <= o.right + 0.5;
      final checks = <String, bool>{};
      var colorChecks = 0;
      for (final b in _four) {
        final name = findVisibleText(b.name);
        await t.scrollUntilVisible(name, 120, scrollable: scroll, maxScrolls: 40);
        await settle(t, 4);
        expect(name, findsOneWidget, reason: '${b.id} 도달(불변)');
        final ink = find.ancestor(of: name, matching: find.byType(InkWell)).first;
        await t.ensureVisible(ink);
        await settle(t);
        final cardH = t.getRect(ink).height;
        // 빠른 정보 가용 폭(기록) — 같은 정보 열의 주소 Row 폭
        final addrRow = find.ancestor(of: find.descendant(of: ink, matching: findVisibleText(b.address)), matching: find.byType(Row));
        final availW = addrRow.evaluate().isEmpty ? -1.0 : t.getRect(addrRow.first).width;
        final more = find.descendant(of: ink, matching: find.byType(IconButton));
        final menuR = more.evaluate().length == 1 ? t.getRect(more) : null;
        final (pLabel, pColor) = _parkingExpect(b);
        final (mLabel, mColor) = _mealExpect(b);
        final oldLabels = [for (final x in const ['주차O', '주차X', '식사O', '식사X']) if (find.descendant(of: ink, matching: findVisibleText(x)).evaluate().isNotEmpty) x];
        checks['${b.id} 옛 O/X 라벨 0'] = oldLabels.isEmpty;
        final rects = <String, Rect>{};
        final lineInfo = <String>[];
        for (final (lbl, want) in [(pLabel, pColor), (mLabel, mColor)]) {
          final f = find.descendant(of: ink, matching: findVisibleText(lbl));
          final n = f.evaluate().length;
          checks['${b.id} "$lbl" 정확 1'] = n == 1;
          if (n != 1) continue;
          await t.ensureVisible(f);
          await settle(t, 4);
          final vp = t.getRect(scroll);
          final r = t.getRect(f);
          final rp = _para(t, f);
          final (lines, wordOk) = _lines(rp);
          final col = rp.text.style?.color;
          final cr = _contrast(col ?? Colors.black, _bgOf(t.element(f)));
          checks['${b.id} "$lbl" 전문 · 도달(표시 영역 · 화면 안)'] = visibleText(rp.text.toPlainText()) == lbl && inRect(vp, r) && inRect(screen, r);
          checks['${b.id} "$lbl" 말줄임 0 · 낱말 안 줄바꿈 0'] = !rp.didExceedMaxLines && wordOk;
          checks['${b.id} "$lbl" 색'] = col == want;
          checks['${b.id} "$lbl" 대비 ≥ 4.5'] = cr >= 4.5;
          colorChecks++;
          rects[lbl] = r;
          lineInfo.add('$lbl lines=$lines rect=$r color=0x${(col ?? Colors.black).toARGB32().toRadixString(16)} contrast=${cr.toStringAsFixed(2)}');
        }
        // 평점(있을 때)
        Rect? ratingR;
        if (b.rating != null) {
          final rf = find.descendant(of: ink, matching: find.text(b.rating!.toStringAsFixed(1)));
          checks['${b.id} 평점 정확 1'] = rf.evaluate().length == 1;
          if (rf.evaluate().length == 1) {
            ratingR = t.getRect(rf);
            checks['${b.id} 평점 말줄임 0'] = !_para(t, rf).didExceedMaxLines;
          }
        }
        // ③ 겹침 0 · 읽는 순서
        // [DU395 수리 2/3] 겹침 · 순서 · 구분선은 **같은 스크롤 상태**에서 다시 잰 rect 로 본다. 라벨마다 ensureVisible 로
        //   스크롤이 바뀌면 따로 잰 전역 좌표가 섞인다(TA 1차 B b1: 주차 가능만 40.4px 이전 상태). 단언은 그대로.
        Rect? now(Finder f) => f.evaluate().length == 1 ? t.getRect(f) : null;
        final pR = rects.containsKey(pLabel) ? now(find.descendant(of: ink, matching: findVisibleText(pLabel))) : null;
        final mR = rects.containsKey(mLabel) ? now(find.descendant(of: ink, matching: findVisibleText(mLabel))) : null;
        if (ratingR != null) ratingR = now(find.descendant(of: ink, matching: find.text(b.rating!.toStringAsFixed(1))));
        final seq = <Rect>[if (ratingR != null) ratingR, if (pR != null) pR, if (mR != null) mR];
        var overlap = false;
        for (var i = 0; i < seq.length; i++) {
          for (var j = i + 1; j < seq.length; j++) {
            final x = seq[i].intersect(seq[j]);
            if (x.width > 0.5 && x.height > 0.5) overlap = true;
          }
        }
        bool before(Rect a, Rect z) => (a.center.dy - z.center.dy).abs() <= a.height / 2 ? a.right <= z.left + 0.5 : a.bottom <= z.top + 0.5;
        var ordered = true;
        for (var i = 1; i < seq.length; i++) {
          if (!before(seq[i - 1], seq[i])) ordered = false;
        }
        checks['${b.id} 빠른 정보 겹침 0'] = seq.length == (b.rating != null ? 3 : 2) && !overlap;
        checks['${b.id} 순서 평점 → 주차 → 식사'] = seq.length == (b.rating != null ? 3 : 2) && ordered;
        // ④ 구분선: 1×12 grey300 — 같은 줄 양쪽에 항목
        final seps = [
          for (final e in find.descendant(of: ink, matching: find.byType(Container)).evaluate())
            if ((e.widget as Container).color == AppColors.grey300) (e.renderObject! as RenderBox)
        ].where((ro) => (ro.size.width - 1).abs() < 0.01 && (ro.size.height - 12).abs() < 0.01).map((ro) => ro.localToGlobal(Offset.zero) & ro.size).toList();
        var lonely = 0;
        for (final s in seps) {
          bool sameLine(Rect r) => r.top < s.bottom && r.bottom > s.top;
          final left = seq.any((r) => sameLine(r) && r.right <= s.left + 0.5);
          final right = seq.any((r) => sameLine(r) && r.left >= s.right - 0.5);
          if (!left || !right) lonely++;
        }
        checks['${b.id} 혼자 남는 구분선 0'] = lonely == 0;
        _out('$tag ${b.id} card_h=${cardH.toStringAsFixed(1)} avail_w=${availW.toStringAsFixed(1)} menu=$menuR old=$oldLabels seps=${seps.length} lonely=$lonely '
            'rating=$ratingR ${lineInfo.join(' | ')} same_state p=$pR m=$mR overlap=$overlap ordered=$ordered');
        if (b.id == 'b4') {
          await vqCapture(t, key, '${tag}_2quick_b4', conditions: {...cond, 'state': '긴 이름 카드 빠른 정보(평점 · 주차 가능 · 식사 미제공)'});
        }
      }
      checks['카드마다 주차 · 식사 색 · 대비 실제 검사 = 4×2'] = colorChecks == 8;
      await t.scrollUntilVisible(findVisibleText('새 사업장 추가'), 200, scrollable: scroll, maxScrolls: 40);
      await settle(t);
      await vqCapture(t, key, '${tag}_3end', conditions: {...cond, 'state': '끝'});
      _out('$tag checks=$checks overflows=${overflows.length} beforeObs=$_beforeObs');
      final ok = checks.values.every((v) => v);
      _out('KNOWN ${ok ? 'ok' : 'NG'} $tag ${checks.entries.where((e) => !e.value).map((e) => e.key).toList()}');
      final exc = t.takeException();
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 1));
      expect(exc, isNull);
      expect(overflows, isEmpty, reason: '$tag 넘침(불변)');
      if (!_beforeObs) {
        for (final e in checks.entries) {
          expect(e.value, isTrue, reason: '$tag ${e.key}');
        }
      }
    });

    // ── E / U: 두 역할 빈 상태 문구 ──
    for (final role in const ['E', 'U']) {
      final sub = role == 'U';
      testWidgets('S014T-${c.id}-$role ${sub ? 'SubAdmin' : '소유자'} 빈 상태 문구 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
        final (key, overflows) = await pump(t, c, subAdmin: sub, items: const []);
        final tag = 'S014T-${c.id}-$role';
        final cond = {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s};
        final screen = Offset.zero & Size(c.w, c.h);
        bool inRect(Rect o, Rect r) => r.top >= o.top - 0.5 && r.bottom <= o.bottom + 0.5 && r.left >= o.left - 0.5 && r.right <= o.right + 0.5;
        final checks = <String, bool>{};
        final want = sub ? const ['배정된 사업장이 없어요'] : const ['등록된 사업장이 없어요', '사업장을 등록하고 공고를 관리해 보세요'];
        final old = sub ? const ['배정된 사업장이 없습니다'] : const ['등록된 사업장이 없습니다', '사업장을 등록하고 공고를 관리해보세요'];
        final info = <String>[];
        for (final s in want) {
          final f = findVisibleText(s);
          checks['"$s" 정확 1'] = f.evaluate().length == 1;
          if (f.evaluate().length != 1) continue;
          await t.ensureVisible(f);
          await settle(t, 4);
          final r = t.getRect(f);
          final rp = _para(t, f);
          final (lines, wordOk) = _lines(rp);
          checks['"$s" 전문 · 화면 안 · 말줄임 0 · 낱말 안 줄바꿈 0'] = inRect(screen, r) && !rp.didExceedMaxLines && wordOk;
          info.add('$s lines=$lines rect=$r');
        }
        for (final s in old) {
          checks['옛 문구 "$s" 0'] = findVisibleText(s).evaluate().isEmpty;
        }
        // 불변: 역할 CTA · SubAdmin 안내
        final cta = findVisibleText('사업장 등록하기').evaluate().length;
        final subHint = findVisibleText('권한을 부여한 관리자에게 사업장 배정을 확인해 주세요').evaluate().length;
        _out('$tag ${info.join(' | ')} cta=$cta subHint=$subHint');
        await vqCapture(t, key, '${tag}_1empty', conditions: {...cond, 'state': sub ? 'SubAdmin 배정 0' : '관리자 0개'});
        _out('$tag checks=$checks overflows=${overflows.length} beforeObs=$_beforeObs');
        final ok = checks.values.every((v) => v);
        _out('KNOWN ${ok ? 'ok' : 'NG'} $tag ${checks.entries.where((e) => !e.value).map((e) => e.key).toList()}');
        final exc = t.takeException();
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 1));
        expect(exc, isNull);
        expect(overflows, isEmpty, reason: '$tag 넘침(불변)');
        if (sub) {
          expect(cta, 0, reason: '$tag SubAdmin 등록 CTA 없음(불변)');
          expect(subHint, 1, reason: '$tag SubAdmin 안내 그대로(불변)');
        } else {
          expect(cta, greaterThanOrEqualTo(1), reason: '$tag 소유자 등록 CTA 있음(불변)');
        }
        if (!_beforeObs) {
          for (final e in checks.entries) {
            expect(e.value, isTrue, reason: '$tag ${e.key}');
          }
        }
      });
    }
  }
}
