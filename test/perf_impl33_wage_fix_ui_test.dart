// [F294-WAGE-01 · impl_33] 하루 예상 금액 후속 — 유형 모름 · 비시급 혼합 · 누락 단가 '0원' · 일정 상세 급여 행.
//   실제 위젯(공고 카드 · 공고 상세 업무 카드 · 초대 약속 카드 · 일정 상세)을 390×844@1.0 · 320×640@2.0 에서 그린다.
//   넘침 0 · 바뀐 급여 글의 말줄임(didExceedMaxLines) 0 · 새 조회 0(일정 상세 reads 호출 수).
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/invitation_projection.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/job_posting_reads.dart';
import 'package:ALfit/screens/common/job_posting_screen.dart';
import 'package:ALfit/services/work_type_guide_resolver.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/expected_daily_wage.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/schedule_detail_dialog.dart';
import 'package:ALfit/widgets/dialogs/schedule_detail_reads.dart';
import 'package:ALfit/widgets/user/cards/user_to_card.dart';
import 'package:ALfit/widgets/user/invitation_promise_card.dart';

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

class _UserDouble extends UserProvider {
  @override
  UserModel? get currentUser =>
      UserModel(uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER, accountStatus: 'active');
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
}

DateTime _day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: offset));
}

DateTime _kstDay(int plusDays) {
  final k = DateTime.now().toUtc().add(Duration(hours: 9, days: plusDays));
  return DateTime.utc(k.year, k.month, k.day).subtract(const Duration(hours: 9));
}

// 원문(map)에 급여 유형이 없는 업무 — 모델은 'hourly' 를 채우지만 출처는 false.
WorkDetailData _noType({String id = 'wdU', int wage = 11000}) => WorkDetailData.fromMap({
      'wdId': id, 'workType': '분류', 'wage': wage, 'requiredCount': 1, 'startTime': '09:00', 'endTime': '11:00'});

// 원문에 시급이 없는 시급 업무 — 모델 wage = 0.
WorkDetailData _noWage({String id = 'wdZ'}) => WorkDetailData.fromMap({
      'wdId': id, 'workType': '분류', 'wageType': 'hourly', 'requiredCount': 1, 'startTime': '09:00', 'endTime': '11:00'});

const _d1 = WorkDetailData(
    wdId: 'wdD', workType: '포장', wage: 100000, wageType: 'daily', requiredCount: 1, startTime: '09:00', endTime: '18:00');
const _m1 = WorkDetailData(
    wdId: 'wdM', workType: '사무', wage: 2500000, wageType: 'monthly', requiredCount: 1, startTime: '09:00', endTime: '18:00');

TOModel _to(List<WorkDetailData> works, {String type = 'contract'}) => TOModel(
      id: 'T1', businessId: 'biz1', businessName: 'QA 사업장', businessCity: '평택시', type: type,
      title: '물류센터 공고', creatorUID: 'admin1', status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0,
      workDetails: works, slotDateKeys: const [], totalSlots: 0, totalRequired: 5, totalConfirmed: 0, totalPending: 0,
      isPublished: true, publishMode: 'immediate', rangeStart: _day(2), rangeEnd: _day(30), createdAt: _day(-3),
      statusUpdatedAt: _day(-3),
    );

ApplicationModel _app({String? wageType = 'hourly', int wage = 11000, int? brk = 0, String status = AppStatus.confirmed}) =>
    ApplicationModel(
      id: 'app1', businessId: 'biz1', businessName: 'QA 사업장', toTitle: '단기 모집', workDate: _kstDay(3),
      startTime: '09:00', endTime: '11:00', uid: 'u1', selectedWorkType: '분류', workDetailId: 'wd1',
      wage: wage, wageType: wageType, breakMinutes: brk, status: status, appliedAt: _day(-2), workTypeIcon: 'box',
    );

BusinessModel _business() => BusinessModel(
      id: 'biz1', name: 'QA 사업장', ownerId: 'admin1', businessNumber: '0000000000',
      address: '경기도 평택시 진위면 마산8로 10', category: '물류', subCategory: '창고', isApproved: true,
      createdAt: DateTime(2025), attendanceRules: AttendanceRules.defaults());

/// 화면에 그려진 모든 글(보이는 글자 기준).
String _allText(WidgetTester t) => t
    .widgetList<RichText>(find.byType(RichText, skipOffstage: false))
    .map((w) => TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)))
    .join(' | ');

/// [needle] 을 담은 문단이 하나 이상 있고, 그 어느 것도 말줄임(maxLines 초과)되지 않았다.
void _fullyShown(WidgetTester t, String needle) {
  final ps = t
      .renderObjectList<RenderParagraph>(find.byType(RichText, skipOffstage: false))
      .where((p) => TextLayout.plain(p.text.toPlainText(includeSemanticsLabels: false)).contains(needle))
      .toList();
  expect(ps, isNotEmpty, reason: "'$needle' 문단이 없다");
  for (final p in ps) {
    expect(p.didExceedMaxLines, isFalse, reason: "'$needle' 가 말줄임됐다");
  }
}

Future<List<String>> _pump(WidgetTester t, Widget home,
    {required double w, required double h, required double s, bool scroll = true}) async {
  final overflows = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final m = d.exceptionAsString();
    if (m.contains('overflowed')) {
      // 어느 위젯인지 남긴다(원인 위치 줄).
      final where = d.toString().split('\n').where((l) => l.contains('lib/')).take(2).join(' / ');
      overflows.add('${m.split('\n').first} @ $where');
    } else {
      prev?.call(d);
    }
  };
  addTearDown(() => FlutterError.onError = prev);
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _UserDouble()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      theme: RoleTheme.workerTheme,
      builder: (ctx, c) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(s)), child: c!),
      home: scroll
          ? Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(12), child: home))
          : home,
    ),
  ));
  for (var i = 0; i < 14; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  // 단언 전에 원래 처리기로 되돌린다(덮어쓴 채로 expect 하면 실패가 시험 틀 오류로 바뀐다).
  FlutterError.onError = prev;
  return overflows;
}

class _CountingReads {
  int biz = 0, to = 0, catalog = 0;
  final TOModel? liveTo;
  _CountingReads(this.liveTo);
  ScheduleDetailReads get reads => ScheduleDetailReads(
        businessById: (id) async {
          biz++;
          return _business();
        },
        toByApplication: (a) async {
          to++;
          return liveTo;
        },
        workTypeCatalog: (id) async {
          catalog++;
          return WorkTypeCatalog.empty;
        },
      );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
    await initializeDateFormatting('ko', null);
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'N', w: 320.0, h: 640.0, s: 2.0)];

  for (final v in views) {
    // ── ① 유형 모름 · ② 비시급 혼합 — 공고 카드 ───────────────────────────
    for (final compact in [true, false]) {
      final tag = compact ? 'compact' : 'normal';
      testWidgets('F294-A-${v.id}-$tag 유형 모름 공고 카드 — 시급 · 원시 금액으로 돌아가지 않는다', (t) async {
        final ovf = await _pump(
            t,
            UserTOCard(to: _to([_noType()]), myApplications: const [], onApplySuccess: () {}, compact: compact,
                selectedNotifier: ValueNotifier<String?>(null)),
            w: v.w, h: v.h, s: v.s);
        final all = _allText(t);
        expect(all, contains(ExpectedWageText.wageUnknown));
        expect(all.contains('11,000원'), isFalse, reason: '유형을 모르는 원시 금액을 단위처럼 보였다');
        expect(all.contains('시급'), isFalse, reason: '모델 기본 유형으로 시급이라 불렀다');
        _fullyShown(t, ExpectedWageText.wageUnknown);
        expect(ovf, isEmpty, reason: ovf.join(' | '));
        expect(t.takeException(), isNull);
      });

      testWidgets('F294-B-${v.id}-$tag 일급+월급 공고 카드 — 첫 업무 단위+원시 min/max 로 합치지 않는다', (t) async {
        final ovf = await _pump(
            t,
            UserTOCard(to: _to(const [_d1, _m1]), myApplications: const [], onApplySuccess: () {}, compact: compact,
                selectedNotifier: ValueNotifier<String?>(null)),
            w: v.w, h: v.h, s: v.s);
        final all = _allText(t);
        expect(all, contains(ExpectedWageText.perWorkWage));
        expect(all.contains('2,500,000'), isFalse);
        expect(all.contains('100,000원~'), isFalse);
        expect(all.contains('일급'), isFalse, reason: '첫 업무 유형으로 전체를 불렀다');
        _fullyShown(t, ExpectedWageText.perWorkWage);
        expect(ovf, isEmpty, reason: ovf.join(' | '));
      });
    }

    // ── ③ 누락 시급 — 초대 약속 카드 ───────────────────────────────────
    testWidgets('F294-C1-${v.id} 초대 — 누락 시급(모델 0) · 휴게 null → 큰 \'0원\' 없음 · 확인 필요', (t) async {
      final ovf = await _pump(
          t,
          InvitationPromiseCard(
            projection: InvitationProjection(
              application: _app(wage: 0, brk: null, status: AppStatus.invited),
              contextState: InvitationContextState.loaded,
              acceptability: InvitationAcceptability.acceptable,
              drift: const InvitationDrift(),
            ),
          ),
          w: v.w, h: v.h, s: v.s);
      final all = _allText(t);
      expect(all.contains('0원'), isFalse, reason: '누락 단가를 0원으로 보였다');
      expect(all, contains(ExpectedWageText.needsCheck));
      _fullyShown(t, ExpectedWageText.needsCheck);
      expect(ovf, isEmpty, reason: ovf.join(' | '));
    });

    testWidgets('F294-C2-${v.id} 초대 — 유효 시급 · 휴게 null → 시급은 보조, 큰 자리는 확인 필요', (t) async {
      final ovf = await _pump(
          t,
          InvitationPromiseCard(
            projection: InvitationProjection(
              application: _app(wage: 11000, brk: null, status: AppStatus.invited),
              contextState: InvitationContextState.loaded,
              acceptability: InvitationAcceptability.acceptable,
              drift: const InvitationDrift(),
            ),
          ),
          w: v.w, h: v.h, s: v.s);
      final texts = t.widgetList<Text>(find.byType(Text)).map((x) => TextLayout.plain(x.data ?? '')).toList();
      expect(texts, contains(ExpectedWageText.needsCheck));
      expect(texts, contains('시급 11,000원'));
      expect(texts.contains('11,000원'), isFalse, reason: '유효 시급을 큰 금액 자리에 두었다');
      expect(texts.any((s) => s.contains('하루 예상')), isFalse);
      expect(ovf, isEmpty, reason: ovf.join(' | '));
    });

    testWidgets('F294-C3-${v.id} 초대 — 지원하지 않는 유형(weekly) → \'급여\' · 급여 확인 필요(시급 0)', (t) async {
      await _pump(
          t,
          InvitationPromiseCard(
            projection: InvitationProjection(
              application: _app(wageType: 'weekly', wage: 50000, status: AppStatus.invited),
              contextState: InvitationContextState.loaded,
              acceptability: InvitationAcceptability.acceptable,
              drift: const InvitationDrift(),
            ),
          ),
          w: v.w, h: v.h, s: v.s);
      final all = _allText(t);
      expect(all, contains(ExpectedWageText.wageUnknown));
      expect(all.contains('시급'), isFalse);
      expect(all.contains('50,000원'), isFalse);
    });

    // ── ③ 누락 시급 — 공고 상세 업무 카드 · 업무 시트 ─────────────────────
    testWidgets('F294-C4-${v.id} 공고 상세 — 누락 시급 업무 카드에 큰 \'0원\' 없음', (t) async {
      final wd = _noWage();
      final reads = JobPostingReads(
        toOrFailure: (id) async => (to: _to(const [], type: 'flex'), failed: false),
        workDetails: (id) async => const <WorkDetailData>[],
        businessById: (id) async => _business(),
        slots: (id, {bool visibleOnly = true}) async => [
          SlotModel(id: 's1', toId: 'T1', date: _kstDay(3), workDetails: [wd], status: SlotStatus.open,
              confirmedCount: 0, createdAt: DateTime(2025)),
        ],
        myApplications: (uid) async => const <ApplicationModel>[],
        workTypeCatalog: (id) async => WorkTypeCatalog.empty,
        applicationOnce: (id) async => null,
      );
      final ovf = await _pump(
          t, JobPostingScreen(to: _to(const [], type: 'flex'), workDetails: const [], reads: reads),
          w: v.w, h: v.h, s: v.s, scroll: false);
      final all = _allText(t);
      expect(all, contains(ExpectedWageText.needsCheck), reason: '업무 카드가 그려지지 않았다');
      expect(RegExp(r'(^|[^0-9,])0원').hasMatch(all), isFalse, reason: '누락 시급을 0원으로 보였다');
      expect(ovf, isEmpty, reason: ovf.join(' | '));
    });

    // ── ④ 일정 상세 급여 행 ─────────────────────────────────────────────
    testWidgets('F294-D1-${v.id} 일정 상세 · 예상 단계 — 약속 시각·휴게로 하루 예상 + 시급 · 고지 · 새 조회 0', (t) async {
      final c = _CountingReads(_to([
        const WorkDetailData(wdId: 'wd1', workType: '분류', wage: 11000, requiredCount: 1, startTime: '09:00', endTime: '11:00',
            breakMinutes: 60),
      ]));
      final ovf = await _pump(
          t, Scaffold(body: ScheduleDetailDialog(application: _app(brk: 0), reads: c.reads, showExpectedWage: true)),
          w: v.w, h: v.h, s: v.s, scroll: false);
      final all = _allText(t);
      expect(all, contains('하루 예상 22,000원 · 시급 11,000원'), reason: '약속 휴게 0 · 09–11 · 11,000');
      expect(all, contains(ExpectedWageText.disclosure));
      expect(all.contains('11,000원 / 시급'), isFalse);
      expect((c.biz, c.to, c.catalog), (1, 1, 1), reason: '기존 세 조회 외 새 조회 0');
      // [F295-TIME-01] 시간 보조도 같은 기준(약속 휴게 0 · 09–11 = 2시간) — 공고 현재 휴게 60 의 '1h' 가 아니다.
      expect(all, contains('09:00 ~ 11:00'));
      expect(all, contains('· 예정 ${FormatHelper.formatCompactHours(120)}'));
      expect(all.contains('· 예정 ${FormatHelper.formatCompactHours(60)}'), isFalse, reason: 'live 휴게로 시간 보조를 만들었다');
      expect(ovf, isEmpty, reason: ovf.join(' | '));
    });

    testWidgets('F294-D2-${v.id} 일정 상세 · 약속 휴게 null — live 휴게(60)로 채우지 않고 확인 필요', (t) async {
      final c = _CountingReads(_to([
        const WorkDetailData(wdId: 'wd1', workType: '분류', wage: 11000, requiredCount: 1, startTime: '09:00', endTime: '11:00',
            breakMinutes: 60),
      ]));
      final ovf = await _pump(
          t, Scaffold(body: ScheduleDetailDialog(application: _app(brk: null), reads: c.reads, showExpectedWage: true)),
          w: v.w, h: v.h, s: v.s, scroll: false);
      final all = _allText(t);
      expect(all, contains('시급 11,000원 · 예상 금액 확인 필요'));
      expect(all.contains('하루 예상 11,000원'), isFalse, reason: 'live 휴게 60 으로 계산했다');
      expect(all.contains('하루 예상 22,000원'), isFalse, reason: '휴게 null 을 0 으로 만들었다');
      // [F295-TIME-01] 약속 휴게를 모르면 순시간을 숨긴다 — 시작~끝은 그대로.
      expect(all, contains('09:00 ~ 11:00'));
      expect(all.contains('· 예정'), isFalse, reason: '휴게 모름인데 순시간을 보였다(live 60 → 1h 또는 0 → 2h)');
      expect(ovf, isEmpty, reason: ovf.join(' | '));
    });

    testWidgets('F294-D3-${v.id} 일정 상세 · 산정/확정 단계(기본) — 기존 행 · 누락 단가는 \'0원\' 없음', (t) async {
      final c = _CountingReads(null);
      await _pump(t, Scaffold(body: ScheduleDetailDialog(application: _app(), reads: c.reads)),
          w: v.w, h: v.h, s: v.s, scroll: false);
      expect(_allText(t), contains('11,000원 / 시급'));
      expect(_allText(t).contains('하루 예상'), isFalse);
      await _pump(t, Scaffold(body: ScheduleDetailDialog(application: _app(wage: 0), reads: c.reads)),
          w: v.w, h: v.h, s: v.s, scroll: false);
      final all = _allText(t);
      expect(all, contains('${ExpectedWageText.wageUnknown} / 시급'));
      expect(RegExp(r'(^|[^0-9,])0원').hasMatch(all), isFalse);
    });
  }

  // ── ④ 일정 카드 → 상세: 같은 단계 판정을 넘긴다 ───────────────────────────
  group('F294-D4 단계 판정', () {
    AttendanceModel att(String status, String wageStatus) => AttendanceModel(
        id: 'a1', applicationId: 'app1', userId: 'u1', businessId: 'biz1', businessName: 'QA 사업장',
        workDate: _day(1), workType: '분류', status: status, createdAt: _day(-1), wageStatus: wageStatus);

    test('근태 없음 · 산정 전 = 예상 단계 · 산정/확정 · 노쇼 · 결근 = 아님', () {
      expect(ExpectedDailyWage.isExpectedStage(null), isTrue);
      expect(ExpectedDailyWage.isExpectedStage(att(AttendanceModel.statusPresent, AttendanceModel.wagePending)), isTrue);
      expect(ExpectedDailyWage.isExpectedStage(att(AttendanceModel.statusPresent, 'calculated')), isFalse);
      expect(ExpectedDailyWage.isExpectedStage(att(AttendanceModel.statusPresent, 'confirmed')), isFalse);
      expect(ExpectedDailyWage.isExpectedStage(att(AttendanceModel.statusNoShow, AttendanceModel.wagePending)), isFalse);
      expect(ExpectedDailyWage.isExpectedStage(att(AttendanceModel.statusAbsent, AttendanceModel.wagePending)), isFalse);
    });

    test('일정 카드는 상세를 열 때 카드와 같은 판정을 넘긴다(소스)', () {
      final src = File('lib/widgets/calendar/schedule_card.dart').readAsStringSync();
      expect(src.contains('showExpectedWage: ExpectedDailyWage.isExpectedStage(attendance),'), isTrue);
      expect(src.contains('if (ExpectedDailyWage.isExpectedStage(attendance)) {'), isTrue);
    });
  });
}
