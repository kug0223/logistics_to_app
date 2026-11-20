// [DU390] L 흐름 메뉴 탭은 같은 사업장 카드 기준(위치 · finder 귀속 교정, 소급 21 §6).
// [DU386] S014 내 사업장 관리(BusinessListScreen) — 기존 reads seam(R7-PREDEVICE-STABILIZATION.1A) 재사용 before 관측. 제품 변경 0.
//   하네스는 business_form_subadmin_entry_test 바탕(_reads · _Provider). 이 셀의 단언은 흐름(장면 도달)뿐, 나머지는 KNOWN 기록.
//   W 392x844@1.0 · B 320x640@2.0. 흐름:
//     L(관리자 · 4곳: 승인 · 승인 대기 · 운영 종료 · 긴 이름/주소) 첫 화면 → 끝(새 사업장 추가) → 첫 카드 더보기 메뉴
//     S(로딩) · F(조회 실패) · E(관리자 0개) · U(SubAdmin 배정 0)
//   기록: 넘침 · 대비 < 4.5 · 낱말 안 끊김 · 말줄임 · 터치 < 48.
//   메뉴 항목 · 카드 · 등록은 누르지 않는다(목적지 · 서버 호출 0).
// ignore_for_file: depend_on_referenced_packages, unused_element
import 'dart:async';
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

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_list_reads.dart';
import 'package:ALfit/screens/business_admin/business_list_screen.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/widgets/common/loading_widget.dart';

import 'support/du1_vq_capture.dart';
import 'support/du_word_break.dart';
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
  _Provider({required this.subAdmin, this.bizId});
  final bool subAdmin;
  final String? bizId;

  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김사장',
        email: 'u1@alfit.local',
        role: subAdmin ? UserRole.USER : UserRole.BUSINESS_ADMIN,
        managedBusinessIds: subAdmin ? (bizId == null ? const [] : [bizId!]) : const ['b1', 'b2', 'b3', 'b4'],
        subAdminBusinessIds: subAdmin && bizId != null ? [bizId!] : const [],
      );
  @override
  bool get isSubAdmin => subAdmin;
  @override
  bool get isBusinessAdmin => !subAdmin;
  @override
  String? get effectiveBusinessId => bizId;
  // 관리자 메뉴의 '공고 등록' 표시 조건(소유자 = 허용)을 그대로 보이게 한다
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) =>
      subAdmin ? PermissionCheck.denied : PermissionCheck.allowed;
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

final _four = [
  _biz('b1', '강남 물류센터', rating: 4.6, parking: true, meals: const ['중식']),
  _biz('b2', '송파 신선 분류센터', approved: false),
  _biz('b3', '성수 소형 창고', closed: true),
  _biz('b4', '[QA] 아주 긴 이름의 강남 물류센터 평택 제2공장 냉장 분류동',
      address: '경기도 평택시 포승읍 평택항로 268번길 45-12 물류단지 B동 3층', rating: 3.9, parking: true),
];

BusinessListReads _reads({bool throws = false, bool hang = false, List<BusinessModel> items = const []}) {
  Future<T> pick<T>(T v) async {
    if (hang) return Completer<T>().future;
    if (throws) throw StateError('read failed');
    return v;
  }

  return BusinessListReads(
    businessById: (_) => pick<BusinessModel?>(items.isEmpty ? null : items.first),
    businessesByIds: (_) => pick<List<BusinessModel>>(items),
  );
}

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

Color _overWhite(Color c) => Color.alphaBlend(c, Colors.white);

Color _bgOf(Element e) {
  Color? found;
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is ButtonStyleButton) {
      c = w.style?.backgroundColor?.resolve(w.enabled ? <WidgetState>{} : {WidgetState.disabled});
      if (c == null && w is ElevatedButton) c = Theme.of(a).colorScheme.primary;
      if (c == null) return true;
    } else if (w is Container && w.decoration is BoxDecoration) {
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
    found = _overWhite(c);
    return false;
  });
  return found ?? Colors.white;
}

void _out(String s) {
  // ignore: avoid_print
  print(s);
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
          (_) async => codec.encodeMessage(<Object?>['du386.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du386.fake.$m'), (_) async => null);
    }
  });

  for (final c in const [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)]) {
    final cond = <String, Object?>{'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s};

    Future<void> run(WidgetTester t, String flow) async {
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
      final subAdmin = flow == 'U';
      final reads = switch (flow) {
        'S' => _reads(hang: true),
        'F' => _reads(throws: true),
        'E' || 'U' => _reads(),
        _ => _reads(items: _four),
      };
      await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => _Provider(subAdmin: subAdmin, bizId: subAdmin ? 'bx' : null)),
            ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.businessAdminTheme,
            builder: (ctx, child) =>
                MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: BusinessListScreen(reads: reads),
          ),
        ),
      ));
      Future<void> settle([int n = 10]) async {
        for (var i = 0; i < n; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
      }

      await settle(16);
      final tagBase = 'S014-${c.id}_$flow';
      var low = 0, avoid = 0, ell = 0;
      final seen = <String>{};
      void dump(String tg) {
        for (final e in find.byType(RichText).evaluate()) {
          final rp = e.renderObject! as RenderParagraph;
          final s = visibleText(rp.text.toPlainText());
          if (s.trim().isEmpty) continue;
          final self = find.byElementPredicate((x) => identical(x, e));
          final r = t.getRect(self);
          if (r.bottom < 0 || r.top > c.h || r.width == 0) continue;
          if (find.ancestor(of: self, matching: find.byType(Icon)).evaluate().isNotEmpty) continue;
          final col = rp.text.style?.color;
          final bg = _bgOf(e);
          final k = '$s@${bg.toARGB32()}@${col?.toARGB32()}';
          if (seen.contains(k)) continue;
          seen.add(k);
          if (rp.didExceedMaxLines) {
            ell++;
            _out('$tg ellipsis "$s" w=${r.width.toStringAsFixed(1)}');
          }
          for (final b in wordBreaks(rp)) {
            if (!b.forced) {
              avoid++;
              _out('$tg avoidable "$s" $b');
            }
          }
          final cst = col == null ? 99.0 : _contrast(_overWhite(col), bg);
          if (cst < 4.5) {
            low++;
            _out('$tg low "${s.length > 40 ? s.substring(0, 40) : s}" contrast=${cst.toStringAsFixed(2)} color=0x${col!.toARGB32().toRadixString(16)} bg=0x${bg.toARGB32().toRadixString(16)}');
          }
        }
      }

      void targets(String tg) {
        final rows = <String>[];
        for (final e in find.byType(IconButton).evaluate()) {
          final r = t.getRect(find.byElementPredicate((x) => identical(x, e)));
          if (r.bottom < 0 || r.top > c.h) continue;
          final tip = (e.widget as IconButton).tooltip ?? '-';
          rows.add('IconButton($tip) ${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)}${r.width >= 47.99 && r.height >= 47.99 ? '' : ' <48'}');
        }
        final add = find.ancestor(of: find.text('새 사업장 추가'), matching: find.byType(InkWell));
        if (add.evaluate().isNotEmpty) {
          final r = t.getRect(add.first);
          rows.add('새 사업장 추가 ${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)}');
        }
        _out('$tg targets $rows');
      }

      switch (flow) {
        case 'L':
          // [수리 2/3] B 는 첫 화면 아래 카드를 ListView.builder 가 아직 만들지 않는다 — 첫 카드만 첫 화면에서, 나머지는 스크롤 도달로 확인
          expect(findVisibleText(_four.first.name), findsOneWidget, reason: '${_four.first.name} 카드(첫 화면)'); // [DU387] identity 표시
          dump('${tagBase}_1top');
          targets('${tagBase}_1top');
          await vqCapture(t, key, '${tagBase}_1top', conditions: {...cond, 'state': '관리자 4곳 첫 화면'});
          for (final b in _four.skip(1)) {
            await t.scrollUntilVisible(findVisibleText(b.name), 120, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
            await settle(4);
            expect(findVisibleText(b.name), findsOneWidget, reason: '${b.name} 카드(스크롤 도달)');
            dump('${tagBase}_1scroll');
          }
          await t.scrollUntilVisible(find.text('새 사업장 추가'), 200, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
          await settle(6);
          dump('${tagBase}_2end');
          targets('${tagBase}_2end');
          await vqCapture(t, key, '${tagBase}_2end', conditions: {...cond, 'state': '끝(새 사업장 추가)'});
          // [DU390] 소급 21 §6 위치 · finder 귀속 교정 — 전역 첫 메뉴가 아니라 같은 business identity('강남 물류센터') 카드의 메뉴.
          //   DU387 큰 글자 쌓기에서는 메뉴가 이름보다 위 줄이라, 이름 기준 위치에서 전역 첫 메뉴를 누르면 시트가 열리지 않았다(S1 B L).
          final b1Name = findVisibleText(_four.first.name);
          await t.scrollUntilVisible(b1Name, -200, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
          await settle(6);
          final b1Card = find.ancestor(of: b1Name, matching: find.byType(InkWell)).first;
          await t.ensureVisible(b1Card);
          await settle(6);
          final b1Menu = find.descendant(of: b1Card, matching: find.byType(IconButton));
          expect(b1Menu, findsOneWidget, reason: '첫 카드 안 메뉴 1');
          final lvp = t.getRect(find.byType(Scrollable).first);
          final mr = t.getRect(b1Menu);
          final inside = mr.top >= lvp.top - 0.5 && mr.bottom <= lvp.bottom + 0.5 && mr.left >= lvp.left - 0.5 && mr.right <= lvp.right + 0.5;
          final hit = HitTestResult();
          WidgetsBinding.instance.hitTestInView(hit, mr.center, t.view.viewId);
          final glyph = t.renderObject(find.descendant(of: b1Menu, matching: find.byType(RichText)).first);
          final menuHit = hit.path.any((e) => e.target == glyph);
          _out('${tagBase}_3menu card=${t.getRect(b1Card)} menu=$mr vp=$lvp inside=$inside hit=$menuHit');
          expect(inside && mr.width >= 47.99 && mr.height >= 47.99 && menuHit, isTrue, reason: '첫 카드 메뉴 표시 영역 안 · 48 · 중앙 hit $mr / $lvp');
          await t.tapAt(mr.center);
          await settle(12);
          final sheet = find.byType(BottomSheet);
          expect(sheet, findsOneWidget, reason: '더보기 메뉴 시트 1');
          expect(find.descendant(of: sheet, matching: findVisibleText('상세보기')), findsOneWidget, reason: '더보기 메뉴 시트');
          dump('${tagBase}_3menu');
          await vqCapture(t, key, '${tagBase}_3menu', conditions: {...cond, 'state': '첫 카드(승인 · 소유자) 더보기 메뉴'});
          // 비파괴 닫힘 — 항목을 누르지 않고 시트만 닫는다
          await Navigator.of(t.element(sheet)).maybePop();
          await settle(12);
          expect(find.byType(BottomSheet), findsNothing, reason: '시트 비파괴 닫힘');
          expect(b1Name, findsOneWidget, reason: '목록 그대로');
        case 'S':
          expect(find.byType(LoadingWidget), findsOneWidget, reason: '로딩');
          await vqCapture(t, key, '${tagBase}_1loading', conditions: {...cond, 'state': '로딩'});
        case 'F':
          expect(findVisibleText('사업장 목록을 불러오지 못했어요'), findsOneWidget, reason: '조회 실패');
          dump('${tagBase}_1error');
          await settle(30); // 실패 토스트가 지나간 뒤 화면
          await vqCapture(t, key, '${tagBase}_1error', conditions: {...cond, 'state': '조회 실패'});
        case 'E':
          expect(findVisibleText('등록된 사업장이 없어요'), findsOneWidget, reason: '관리자 0개'); // [DU395] 문구 계약 변경(소급 24 §3)
          dump('${tagBase}_1empty');
          targets('${tagBase}_1empty');
          await vqCapture(t, key, '${tagBase}_1empty', conditions: {...cond, 'state': '관리자 0개'});
        case 'U':
          expect(findVisibleText('배정된 사업장이 없어요'), findsOneWidget, reason: 'SubAdmin 배정 0'); // [DU395] 문구 계약 변경(소급 24 §3)
          dump('${tagBase}_1empty');
          await vqCapture(t, key, '${tagBase}_1empty', conditions: {...cond, 'state': 'SubAdmin 배정 0'});
      }
      _out('KNOWN ${overflows.isEmpty ? 'ok' : 'NG'} $tagBase 넘침 ${overflows.length} ${overflows.toSet()}');
      _out('KNOWN $tagBase 대비<4.5 $low · 낱말 안 끊김 $avoid · 말줄임 $ell');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 5));
    }

    for (final flow in const ['L', 'S', 'F', 'E', 'U']) {
      testWidgets('S014-${c.id} $flow 관측 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) => run(t, flow));
    }
  }
}
