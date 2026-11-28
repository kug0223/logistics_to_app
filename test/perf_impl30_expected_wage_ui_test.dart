// [F293-WAGE-01 · impl_30] 하루 예상 금액 — 실제 위젯에서 주금액·보조·짧은 말·고지 + 좁은 폭·큰 글자(넘침 0).
// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/expected_daily_wage.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/apply/apply_confirm_dialog.dart';
import 'package:ALfit/widgets/user/cards/user_to_card.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _UserDouble extends UserProvider {
  @override
  UserModel? get currentUser =>
      UserModel(uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER, accountStatus: 'active');
}

DateTime _day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: offset));
}

// 대표 예제: 시급 11,000 · 2시간 → 하루 예상 22,000원.
const _h2 = WorkDetailData(wdId: 'wdA', workType: '분류', wage: 11000, requiredCount: 3, startTime: '09:00', endTime: '11:00');
const _h4 = WorkDetailData(wdId: 'wdB', workType: '상차', wage: 11000, requiredCount: 2, startTime: '14:00', endTime: '18:00');
const _d1 = WorkDetailData(
    wdId: 'wdC', workType: '포장', wage: 100000, wageType: 'daily', requiredCount: 1, startTime: '09:00', endTime: '18:00');

TOModel _to(List<WorkDetailData> works) => TOModel(
      id: 'T1', businessId: 'biz1', businessName: 'QA 사업장', businessCity: '평택시', type: 'contract',
      title: '물류센터 공고', creatorUID: 'admin1', status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0,
      workDetails: works, slotDateKeys: const [], totalSlots: 0, totalRequired: 5, totalConfirmed: 0, totalPending: 0,
      isPublished: true, publishMode: 'immediate', rangeStart: _day(2), rangeEnd: _day(30), createdAt: _day(-3),
      statusUpdatedAt: _day(-3),
    );

String _allText(WidgetTester t) => t
    .widgetList<RichText>(find.byType(RichText, skipOffstage: false))
    .map((w) => TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)))
    .join(' | ');

Future<List<String>> _pump(WidgetTester t, Widget child, {required double w, required double h, required double s}) async {
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
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
    value: _UserDouble(),
    child: MaterialApp(
      theme: RoleTheme.workerTheme,
      builder: (ctx, c) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(s)), child: c!),
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(12), child: child)),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  return overflows;
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'N', w: 320.0, h: 640.0, s: 2.0)];

  for (final v in views) {
    for (final compact in [true, false]) {
      testWidgets('UI-1-${v.id}-${compact ? 'compact' : 'normal'} 공고 카드 — 하루 예상 범위(주) · 시급(보조) · 예상·세전 · 넘침 0',
          (t) async {
        final ovf = await _pump(
            t,
            UserTOCard(to: _to(const [_h2, _h4]), myApplications: const [], onApplySuccess: () {}, compact: compact,
                selectedNotifier: ValueNotifier<String?>(null)),
            w: v.w, h: v.h, s: v.s);
        final all = _allText(t);
        expect(all, contains('하루 예상 22,000~44,000원'), reason: '같은 시급 · 다른 시간은 범위');
        expect(all, contains(ExpectedWageText.shortNote));
        expect(all, contains('시급 11,000원'), reason: '보조 시급');
        expect(all.contains('44,000~'), isFalse);
        expect(ovf, isEmpty, reason: ovf.join(' | '));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('UI-2-${v.id} 시급·일급 혼합 카드 — 업무별 급여 확인(첫 업무 유형으로 전체를 시급이라 부르지 않음)', (t) async {
      final ovf = await _pump(
          t, UserTOCard(to: _to(const [_h2, _d1]), myApplications: const [], onApplySuccess: () {}, selectedNotifier: ValueNotifier<String?>(null)),
          w: v.w, h: v.h, s: v.s);
      final all = _allText(t);
      expect(all, contains('업무별 급여 확인'));
      expect(all.contains('하루 예상 22,000'), isFalse);
      expect(ovf, isEmpty, reason: ovf.join(' | '));
    });

    testWidgets('UI-3-${v.id} 일급만 — 하루 예상을 만들지 않는다(기존 표시)', (t) async {
      await _pump(t, UserTOCard(to: _to(const [_d1]), myApplications: const [], onApplySuccess: () {}, selectedNotifier: ValueNotifier<String?>(null)),
          w: v.w, h: v.h, s: v.s);
      final all = _allText(t);
      expect(all.contains('하루 예상'), isFalse);
      expect(all, contains('100,000원'));
    });

    testWidgets('UI-4-${v.id} 지원 확인 — 하루 예상 + 시급 · 고지 정본 · 넘침 0', (t) async {
      final ovf = await _pump(
          t,
          ApplyConfirmDialog(businessName: 'QA 사업장', work: _h2, isLongTerm: false, workDate: _day(3)),
          w: v.w, h: v.h, s: v.s);
      final all = _allText(t);
      expect(all, contains('하루 예상 22,000원 · 시급 11,000원'));
      expect(all, contains(ExpectedWageText.disclosure));
      expect(ovf, isEmpty, reason: ovf.join(' | '));
    });
  }

  testWidgets('UI-5 시각 없는 원문(map) 업무는 카드에 하루 예상을 만들지 않는다', (t) async {
    final noTime = WorkDetailData.fromMap({'workType': '분류', 'wage': 11000, 'wageType': 'hourly', 'requiredCount': 1});
    await _pump(t, UserTOCard(to: _to([noTime]), myApplications: const [], onApplySuccess: () {}, selectedNotifier: ValueNotifier<String?>(null)),
        w: 390, h: 844, s: 1.0);
    final all = _allText(t);
    expect(all.contains('하루 예상 88,000'), isFalse, reason: '기본 09–18 로 금액을 만들었다');
    expect(all, contains('예상 금액 확인 필요'));
  });
}
