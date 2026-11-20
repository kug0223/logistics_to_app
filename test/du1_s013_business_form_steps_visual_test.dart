// ignore_for_file: depend_on_referenced_packages
// [DU1 구현97] S013 사업장 수정 폼 step1(기본 정보)·step2(상세 정보) — P96 sectionHeader 실제 소비처 캡처.
//
//   fixture·경로: test/business_form_responsive_render_test.dart:67~107 의 BUSINESS_ADMIN provider·승인 사업장
//   `_business()` 수정 모드를 원문 그대로 쓴다(새 DEV fixture 아님). 공개 BusinessFormScreen 을 직접 띄우고,
//   본문을 실제 drag 해 `다음` 을 화면에 들인 뒤 중심을 실제 탭(두 번만)해 step1·step2 에 간다.
//   최종 `저장하기` 는 누르지 않는다. 신규 등록 step1/2·저장 성공은 이 시험의 범위가 아니다.
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
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_form_screen.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p', storageBucket: 'p.appspot.com');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

// business_form_responsive_render_test.dart:67~83 원문
class _AdminProvider extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'admin1', username: 'admin1', name: '김의관', email: 'admin1@alfit.local',
        role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const ['biz1']);
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
}

// business_form_responsive_render_test.dart:87~107 원문
BusinessModel _business() => BusinessModel(
      id: 'biz1', name: '중앙물류센터 수도권 1센터', ownerId: 'admin1',
      companyName: '주식회사 중앙물류', ownerName: '김의관', businessNumber: '0000000000',
      address: '경기도 화성시 동탄순환대로 1길 23', detailAddress: '3층 물류동 A구역',
      category: '물류', subCategory: '창고', phone: '031-000-0000',
      latitude: 37.2, longitude: 127.07, city: '화성시', district: '동탄면',
      isApproved: true, createdAt: DateTime(2026, 1, 1));

const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';

/// 소비처의 sectionHeader 제목(소스에서 그대로 모은다 — SWC-CONSUMER 와 같은 방식)
const _step1Titles = ['대표 이미지', '사업장 정보', '사업자등록증 (잠금)']; // business_form_screen.dart:603·614·754 (수정·승인 사업장)
const _step2Titles = ['사업장 소개', '시설 및 환경', '사업장 사진 (최대 5장)', '교통편 안내', '준비사항 / 주의사항', '출퇴근 방식', '근태 및 급여 처리 기준']; // :1071~1187

Future<void> _cell(WidgetTester t, {required String id, required Size size, required double scale, required bool insets, required double dragDy}) async {
  await t.runAsync(vqLoadFonts);
  SharedPreferences.setMockInitialValues({});
  final calls = <String, int>{};
  void inc(String k) => calls[k] = (calls[k] ?? 0) + 1;
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMessageHandler(fnChannel, (msg) async {
    inc('functions');
    return const StandardMessageCodec().encodeMessage(<Object?>['not-found', 'blocked', <String, Object?>{'code': 'not-found'}]);
  });
  for (final op in const ['documentReferenceGet', 'queryGet', 'documentReferenceSet', 'documentReferenceUpdate',
    'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
    m.setMockMessageHandler('$fsBase.$op', (msg) async {
      inc('firestore $op');
      return null;
    });
  }
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  if (insets) {
    t.view.padding = const FakeViewPadding(top: 30, bottom: 24);
    t.view.viewPadding = const FakeViewPadding(top: 30, bottom: 24);
  }
  addTearDown(t.view.reset);
  final overflows = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final s = d.exceptionAsString();
    if (s.contains('overflowed')) {
      overflows.add(s.split('\n').first);
    } else {
      prev?.call(d);
    }
  };
  addTearDown(() => FlutterError.onError = prev);
  final key = GlobalKey();
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _AdminProvider()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RoleTheme.getThemeByRole('BUSINESS_ADMIN'),
        builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: BusinessFormScreen(business: _business()),
      ),
    ),
  ));
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  expect(t.takeException(), isNull);
  final screen = find.byType(BusinessFormScreen);
  final mq = MediaQuery.of(t.element(screen));
  bool hits(Finder f, Offset p) {
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
    return hit.path.any((e) => e.target == t.renderObject(f));
  }

  ScrollableState bodyScroll() {
    final all = find.descendant(of: screen, matching: find.byType(Scrollable));
    final cands = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
        .where((f) =>
            t.state<ScrollableState>(f).position.axis == Axis.vertical &&
            find.ancestor(of: f, matching: find.byType(TextField)).evaluate().isEmpty)
        .toList()
      ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
    return t.state<ScrollableState>(cands.first);
  }

  final out = <String>['mq padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} size=${mq.size}'];

  /// 본문 viewport 와 교차하는 Text 전부(보이는 높이/전체 높이)
  String visible(String when, Rect vp, ScrollPosition pos) {
    final parts = <String>[];
    for (final e in find.descendant(of: screen, matching: find.byType(Text)).evaluate()) {
      final w = e.widget as Text;
      final s = visibleText(w.data ?? w.textSpan?.toPlainText() ?? '');
      if (s.trim().isEmpty) continue;
      final box = e.renderObject as RenderBox;
      if (!box.hasSize || !box.attached) continue;
      final r = box.localToGlobal(Offset.zero) & box.size;
      final v = r.intersect(vp);
      if (v.width > 0 && v.height > 0) parts.add('"${s.replaceAll('\n', '⏎')}"(${v.height.toStringAsFixed(0)}/${r.height.toStringAsFixed(0)})');
    }
    return '$when off=${pos.pixels.toStringAsFixed(1)} 보이는 글 ${parts.length}: ${parts.join(' ')}';
  }

  /// 섹션 제목(sectionHeader) 의 rect·높이 — 줄바꿈 여부 판단용
  final titleSeen = <String, String>{};
  void titles(List<String> list, Rect vp, ScrollPosition pos) {
    for (final s in list) {
      final f = findVisibleText(s);
      for (var i = 0; i < f.evaluate().length; i++) {
        final r = t.getRect(f.at(i));
        if (r.intersect(vp).height > 0) {
          titleSeen.putIfAbsent('$s#$i', () => 'rect=$r h=${r.height.toStringAsFixed(1)} @off${pos.pixels.toStringAsFixed(0)}');
        }
      }
    }
  }

  /// 실제 drag 로 본문 끝까지 — 프레임별 로그·mid/end 캡처
  Future<void> walk(String step, List<String> titleList) async {
    final st = bodyScroll();
    final pos = st.position;
    final vp = t.getRect(find.byWidget(st.widget));
    out.add('$step 진입 직후 본문 viewport=$vp max=${pos.maxScrollExtent.toStringAsFixed(1)} off=${pos.pixels.toStringAsFixed(1)}');
    // 단계 전환 뒤 본문이 이전 단계의 offset 을 이어받으면 첫 섹션이 위로 밀려 있다 — 실제 drag 로 맨 위까지 올린다(관측 기록)
    var up = 0;
    while (pos.pixels > 0.5 && up < 80) {
      await t.dragFrom(Offset(vp.left + 4, vp.center.dy), Offset(0, dragDy));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      up++;
    }
    out.add('$step 맨 위로 실제 drag $up회 → off=${pos.pixels.toStringAsFixed(1)}');
    out.add(visible('$step 초기', vp, pos));
    titles(titleList, vp, pos);
    await vqCapture(t, key, '${id}_${step}_top', conditions: {
      'screen': "BusinessFormScreen(business: _business()) 수정 모드 — 공개 화면 직접 · 실제 '다음' 탭으로 진입",
      'theme': "RoleTheme.getThemeByRole('BUSINESS_ADMIN')", 'viewport': '${size.width.toInt()}x${size.height.toInt()}',
      'dpr': 1.0, 'textScaler': scale, 'inset': insets ? '선언 padding/viewPadding top30 bottom24 · viewInsets 0' : '모두 0',
      'prefs': '{}', 'fonts': 'vqLoadFonts 근사', 'fixture': 'business_form_responsive_render_test.dart:87~107 _business()',
      'scroll': 'off 0', 'measure': out.last});
    var k = 0;
    var midDone = false;
    while (pos.pixels < pos.maxScrollExtent - 0.5 && k < 80) {
      await t.dragFrom(Offset(vp.left + 4, vp.center.dy), Offset(0, -dragDy));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      k++;
      out.add(visible('$step drag$k', vp, pos));
      titles(titleList, vp, pos);
      if (!midDone && pos.pixels >= pos.maxScrollExtent / 2) {
        midDone = true;
        await vqCapture(t, key, '${id}_${step}_mid', conditions: {
          'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'textScaler': scale,
          'scroll': '본문 실제 dragFrom(left+4,center) -${dragDy.toInt()} × $k · off ${pos.pixels.toStringAsFixed(1)}', 'measure': out.last});
      }
    }
    final atEnd = (pos.pixels - pos.maxScrollExtent).abs() < 0.5 || pos.maxScrollExtent < 0.5;
    out.add('$step 말단=$atEnd off=${pos.pixels.toStringAsFixed(1)} max=${pos.maxScrollExtent.toStringAsFixed(1)} drag=$k');
    expect(atEnd, isTrue, reason: '$step 말단');
    await vqCapture(t, key, '${id}_${step}_end', conditions: {
      'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'textScaler': scale,
      'scroll': '본문 실제 drag → 말단 off ${pos.pixels.toStringAsFixed(1)}', 'measure': out.last});
  }

  /// 보이는 '다음'/'저장하기' receiver 측정(누르기는 tapNext 일 때 '다음' 만)
  Future<void> action(String step, String label, {required bool tapIt}) async {
    final txt = find.text(label);
    expect(txt, findsWidgets, reason: '$step $label 라벨');
    final recv = find.ancestor(of: txt.first, matching: find.byWidgetPredicate((w) =>
        w is ButtonStyleButton || (w is InkWell && w.onTap != null) || (w is GestureDetector && w.onTap != null))).first;
    final r = t.getRect(recv);
    final st = bodyScroll();
    final vp = t.getRect(find.byWidget(st.widget));
    final inView = r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5;
    final hit = hits(recv, r.center);
    out.add('$step $label receiver ${t.widget(recv).runtimeType} $r ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} hit=$hit inBodyViewport=$inView');
    expect(r.width >= 48 - 0.01 && r.height >= 48 - 0.01 && hit && inView, isTrue, reason: '$step $label receiver 48·hit·보임');
    if (tapIt) {
      await t.tapAt(r.center);
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }
  }

  // step0 → (본문 말단까지 실제 drag) → 다음 실제 탭 → step1
  {
    final st = bodyScroll();
    final vp = t.getRect(find.byWidget(st.widget));
    var k = 0;
    while (st.position.pixels < st.position.maxScrollExtent - 0.5 && k < 40) {
      await t.dragFrom(Offset(vp.left + 4, vp.center.dy), Offset(0, -dragDy));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      k++;
    }
    await action('step0', '다음', tapIt: true);
  }
  expect(find.text('이전'), findsWidgets, reason: 'step1 진입');
  await walk('step1', _step1Titles);
  await action('step1', '다음', tapIt: true);
  expect(find.text('저장하기'), findsWidgets, reason: 'step2 진입');
  await walk('step2', _step2Titles);
  await action('step2', '저장하기', tapIt: false);
  out.add('섹션 제목 관측: ${titleSeen.entries.map((e) => '${e.key} ${e.value}').join(' · ')}');
  out.add('calls=$calls · overflows=${overflows.length}');
  for (final l in out) {
    // ignore: avoid_print
    print('$id $l');
  }
  for (final s in [..._step1Titles, ..._step2Titles]) {
    expect(titleSeen.keys.any((k) => k.startsWith('$s#')), isTrue, reason: '섹션 제목 "$s" 가 본문 viewport 에 보인 프레임이 있다');
  }
  expect(calls, isEmpty, reason: 'Firestore·Functions 0');
  expect(overflows, isEmpty, reason: overflows.join(' | '));
  expect(t.takeException(), isNull);
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('S013-ST N 사업장 수정 step1·step2 392×851@1.0 — 실제 다음 2회·말단·receiver', (t) async {
    await _cell(t, id: 'S013-ST_392x1', size: const Size(392, 851), scale: 1.0, insets: true, dragDy: 200);
  });

  testWidgets('S013-ST B 사업장 수정 step1·step2 320×640@2.0 — 연속 읽기·receiver·overflow 0', (t) async {
    await _cell(t, id: 'S013-STB_320x2', size: const Size(320, 640), scale: 2.0, insets: false, dragDy: 150);
  });
}
