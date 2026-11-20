// [DU387] S014 사업장 카드 배치 — 하네스는 du1_s014_list_obs_386 바탕(_reads · _Provider · 4곳 fixture).
//   W 392x844@1.0 · B 320x640@2.0. 카드마다 스크롤로 들여 보고 단언한다.
//   제품 기대(기본 단언, DU_BEFORE_OBSERVE=387 은 기록만):
//     ① 사업장명 전문 — 말줄임 0 · 보이는 글자 = 원문 · 문단 폭 > 0 · 화면 안
//     ② 카드 안 모든 글(이름 · 배지 · 주소 · 평점 · 주차 · 식사) 말줄임 0
//     ③ 상태 배지 보임 · 이름과 겹침 0 · 더보기 48×48 · 중앙 hit
//     ④ 배치: B(배율 2.0) = 이름이 이미지 아래(쌓기), W = 이름이 이미지 오른쪽(한 줄)
//   불변(항상 단언): 넘침 0 · 예외 0 · 4곳 도달.
// [DU387 r2] 소급 20 (가) — 위치 계측 교정. 꼬리표:
//   [r2 위치 수리] = 원 기대(이름 전문 · 말줄임 0 · 더보기 48 · hit)를 그대로 두고, 재는 위치를 '이름 기준'에서 '카드 위 기준 실제 스크롤'로 바꾼 것.
//   [r2 보강]     = 새 단언: 이름 전문 + 더보기 48 이 같은 시점에 본문 표시 영역(Scrollable, 고정 머리 밖 · clip) 안 · 카드 귀속 유일성 ·
//                   그 카드 메뉴 실제 탭 → BottomSheet 열림(상태별 항목 그대로) → 비파괴 닫힘 · 주소/빠른 정보 따로 도달.
//   단언은 즉시 expect(첫 필수 실패에서 이후 장면 · 캡처 중단). 메뉴 항목은 누르지 않는다(목적지 · 서버 호출 0).
// ignore_for_file: depend_on_referenced_packages, unused_element
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
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김사장',
        email: 'u1@alfit.local',
        role: UserRole.BUSINESS_ADMIN,
        managedBusinessIds: const ['b1', 'b2', 'b3', 'b4'],
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

final _four = [
  _biz('b1', '강남 물류센터', rating: 4.6, parking: true, meals: const ['중식']),
  _biz('b2', '송파 신선 분류센터', approved: false),
  _biz('b3', '성수 소형 창고', closed: true),
  _biz('b4', '[QA] 아주 긴 이름의 강남 물류센터 평택 제2공장 냉장 분류동',
      address: '경기도 평택시 포승읍 평택항로 268번길 45-12 물류단지 B동 3층', rating: 3.9, parking: true),
];

// [r2 보강] 상태별 메뉴 항목 — 제품 규칙과 독립으로 적은 기대(관리자 · 소유자 u1 · 권한 허용):
//   공고 등록 = 승인 && 권한, 상세보기 = 항상, 수정 = SubAdmin 아님, 운영 종료 = 소유자 && 운영 종료/중지 아님
List<String> _menuExpect(BusinessModel b) => [
      if (b.isApproved) '공고 등록',
      '상세보기',
      '수정',
      if (!b.isDeactivated) '운영 종료',
    ];

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '387';

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
          (_) async => codec.encodeMessage(<Object?>['du387.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du387.fake.$m'), (_) async => null);
    }
  });

  for (final c in const [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('S014L-${c.id} 사업장 카드 배치 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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
      final reads = BusinessListReads(
        businessById: (_) async => null,
        businessesByIds: (_) async => _four,
      );
      await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => _Provider()),
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
      final tag = 'S014L-${c.id}';
      final cond = {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s};
      final scroll = find.byType(Scrollable).first;
      final pos = t.state<ScrollableState>(scroll).position;
      // [r2 보강] 본문 표시 영역 = 목록 Scrollable 의 전역 사각형(고정 머리 밖 · viewport clip)
      final vp = t.getRect(scroll);
      bool inVp(Rect r) => r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5 && r.left >= vp.left - 0.5 && r.right <= vp.right + 0.5;
      _out('$tag top offset=${pos.pixels.toStringAsFixed(1)} viewport=$vp');
      await vqCapture(t, key, '${tag}_1top', conditions: {...cond, 'state': '관리자 4곳 첫 화면(offset ${pos.pixels.toStringAsFixed(0)})'});
      final checks = <String, bool>{};
      // 단언: 기본은 즉시 expect(첫 필수 실패에서 중단), DU_BEFORE_OBSERVE=387 이면 기록만
      void check(String k, bool v, [String why = '']) {
        checks[k] = v;
        if (!_beforeObs) expect(v, isTrue, reason: '$tag $k $why');
      }

      RenderParagraph para(Finder f) =>
          t.renderObject<RenderParagraph>(find.descendant(of: f, matching: find.byType(RichText), matchRoot: true).first);
      for (final b in _four) {
        final name = findVisibleText(b.name);
        // lazy builder — 이름이 만들어질 때까지 실제 스크롤
        await t.scrollUntilVisible(name, 120, scrollable: scroll, maxScrolls: 40);
        await settle(4);
        expect(name, findsOneWidget, reason: '${b.id} 도달(불변)');
        final card = find.ancestor(of: name, matching: find.byType(InkWell)).first;
        // [r2 보강] 카드 귀속 유일성 — 원문 identity 로 찾은 이름 하나 · 그 카드 안 메뉴 하나
        final more = find.descendant(of: card, matching: find.byType(IconButton));
        check('${b.id} 카드 귀속 이름 1 · 메뉴 1',
            find.descendant(of: card, matching: findVisibleText(b.name)).evaluate().length == 1 && more.evaluate().length == 1);
        // [r2 위치 수리] 카드 위를 본문 표시 영역 위에 맞춘다(실제 스크롤 — Scrollable.ensureVisible, alignment 0)
        await t.ensureVisible(card);
        await settle(6);
        final cr = t.getRect(card);
        final nr = t.getRect(name);
        final mr = t.getRect(more.first);
        final badge = find.descendant(of: card, matching: findVisibleText(b.operationStatusLabel));
        final br = badge.evaluate().isEmpty ? null : t.getRect(badge.first);
        _out('$tag ${b.id} offset=${pos.pixels.toStringAsFixed(1)} card=$cr name=$nr badge=$br more=$mr');
        final rp = para(name);
        // 원 기대 ① · ③(위치 수리) + [r2 보강] 같은 시점 표시 영역 안
        check('${b.id} 이름 전문', !rp.didExceedMaxLines && visibleText(rp.text.toPlainText()) == b.name && rp.size.width > 1, '$nr');
        check('${b.id} 이름 · 더보기 48 같은 시점 표시 영역 안', inVp(nr) && inVp(mr), 'name=$nr more=$mr vp=$vp');
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, mr.center, t.view.viewId);
        final glyph = t.renderObject(find.descendant(of: more.first, matching: find.byType(RichText)).first);
        check('${b.id} 더보기 48 · 중앙 hit', mr.width >= 47.99 && mr.height >= 47.99 && hit.path.any((e) => e.target == glyph), '$mr');
        check('${b.id} 배지 보임 · 이름과 겹침 0',
            br != null && br.width > 1 && !(br.intersect(nr).width > 0.5 && br.intersect(nr).height > 0.5), 'badge=$br name=$nr');
        final img = t.getRect(find.descendant(of: card, matching: find.byIcon(Icons.business)).first);
        check('${b.id} 배치 ${c.id == 'B' ? '쌓기' : '한 줄'}', c.id == 'B' ? nr.top >= img.bottom - 0.5 : nr.left >= img.right - 0.5);
        // [r2 보강] 주소 · 빠른 정보 — 필요한 지점에서 따로 실제 도달 · 말줄임 0
        final addr = find.descendant(of: card, matching: findVisibleText(b.address));
        await t.ensureVisible(addr);
        await settle(4);
        final ar = t.getRect(addr);
        check('${b.id} 주소 전문 · 표시 영역 안', !para(addr).didExceedMaxLines && inVp(ar), '$ar');
        // [DU395] 문구 계약 변경(소급 24 §3) — fixture 판정식(parkingAvailable)의 정확 라벨로 찾는다
        final quick = find.descendant(of: card, matching: findVisibleText(b.parkingAvailable ? '주차 가능' : '주차 불가'));
        await t.ensureVisible(quick);
        await settle(4);
        final qr = t.getRect(quick);
        final ellipsized = <String>[];
        for (final e in find.descendant(of: card, matching: find.byType(RichText)).evaluate()) {
          final r = e.renderObject! as RenderParagraph;
          final s = visibleText(r.text.toPlainText());
          if (s.trim().isEmpty) continue;
          if (find.ancestor(of: find.byElementPredicate((x) => identical(x, e)), matching: find.byType(Icon)).evaluate().isNotEmpty) continue;
          if (r.didExceedMaxLines) ellipsized.add(s);
        }
        check('${b.id} 빠른 정보 표시 영역 안 · 카드 말줄임 0', inVp(qr) && ellipsized.isEmpty, 'quick=$qr ell=$ellipsized');
        // [r2 보강] 그 카드 메뉴 실제 탭 → BottomSheet 열림(상태별 항목 그대로) → 비파괴 닫힘
        await t.ensureVisible(card);
        await settle(6);
        final m2 = t.getRect(more.first);
        await t.tapAt(m2.center);
        await settle(12);
        final sheet = find.byType(BottomSheet);
        check('${b.id} 메뉴 탭 → 시트 1', sheet.evaluate().length == 1);
        final want = _menuExpect(b);
        final got = [
          for (final label in const ['공고 등록', '상세보기', '수정', '운영 종료'])
            if (find.descendant(of: sheet, matching: findVisibleText(label)).evaluate().isNotEmpty) label
        ];
        check('${b.id} 시트 항목 = 상태별 기대', got.join('/') == want.join('/'), 'got=$got want=$want');
        _out('$tag ${b.id} menu tap=${m2.center} sheet=${sheet.evaluate().length} items=$got');
        if (b.id == 'b1') {
          await vqCapture(t, key, '${tag}_3menu_b1', conditions: {...cond, 'state': '첫 카드 메뉴 시트'});
        }
        // 비파괴 닫힘 — 항목을 누르지 않고 시트만 닫는다(Navigator.maybePop)
        await Navigator.of(t.element(sheet)).maybePop();
        await settle(12);
        check('${b.id} 시트 닫힘 · 목록 그대로', find.byType(BottomSheet).evaluate().isEmpty && find.byType(BusinessListScreen).evaluate().length == 1 && name.evaluate().length == 1);
        if (b.id == 'b4') {
          await t.ensureVisible(card);
          await settle(6);
          await vqCapture(t, key, '${tag}_2long', conditions: {...cond, 'state': '긴 이름 카드 위 맞춤(이름 · 더보기 같은 시점)'});
        }
      }
      await t.scrollUntilVisible(findVisibleText('새 사업장 추가'), 200, scrollable: scroll, maxScrolls: 40);
      await settle(6);
      await vqCapture(t, key, '${tag}_4end', conditions: {...cond, 'state': '끝(새 사업장 추가)'});

      _out('$tag checks=$checks overflows=${overflows.length} beforeObs=$_beforeObs');
      final ok = checks.values.every((v) => v);
      _out('KNOWN ${ok ? 'ok' : 'NG'} $tag ${checks.entries.where((e) => !e.value).map((e) => e.key).toList()}');
      final exc = t.takeException();
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 1));
      expect(exc, isNull);
      expect(overflows, isEmpty, reason: '$tag 넘침(불변)');
    });
  }
}
