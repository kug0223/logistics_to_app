// [판정283 A안 · 대표 결정 2026-11-26] 관리자 홈 「처리할 일」 행 밀도 — 수량 알약을 제목 옆으로, 설명의 같은 총수 반복 제거,
//   오른쪽은 꺾쇠만. 판정283 §4 1–4 의 최소 검증이다(§4-5 기기 캡처는 조정 담당).
//
//   TD-360   360dp/1.0 · 기기 캡처와 같은 3행(이체 대기 1 · 연체 1 / 계약 미발송 6 / 마감 2일 · 2026.10.07) — 행 높이·글 줄 수를 로그로 남긴다.
//            이 사례는 이전/이후 어느 코드에서도 돈다(제목 글로 행을 찾는다 · 버전별 단언 없음) — 이전 값은 HEAD 대조 실행으로 얻는다.
//   TD-9     320dp/1.0 · 320dp/2.0 · 9종 최소 fixture(3–4자리 수량 · 마감 날짜 · 보조줄 여럿).
//            넘침·겹침·말줄임·축소 0, 알약 총수+단위 보존, 제목/알약 자연 전환, 보조정보·날짜 연도, 의미 노드 버튼 하나·총수+단위 1회,
//            행 본문·알약·꺾쇠 위치가 같은 행 콜백에 닿음, 행 순서(연체 이체 상향 포함).
//
//   production 경계(AdminHomeReads)만 갈아끼운다 — 행 데이터·권한 게이트·문구 구성은 실제 코드 그대로(admin_home_content_render_test 와 같은 방식).
//   번들 NotoSansKR 로 잰다(시험 기본 글꼴은 한글 폭이 실제와 다르다).
import 'dart:io';
import 'dart:ui' show SemanticsFlag;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/ui/admin_home_summary_model.dart';
import 'package:ALfit/models/ui/staffing_readiness_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_home_reads.dart';
import 'package:ALfit/screens/business_admin/business_admin_home_screen.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

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

/// 모든 권한이 있는 BUSINESS_ADMIN — 9종 행이 모두 권한 게이트를 지난다.
class _AdminProvider extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'admin1', username: 'admin1', name: '김관리', email: 'admin1@alfit.local',
        role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const ['biz1'], sealBase64: 'seal',
      );
  @override
  bool get isSubAdmin => false;
  @override
  String? get effectiveBusinessId => null;
  @override
  bool get subAdminPermissionsLoaded => true;
  @override
  PermissionWatchState get currentBusinessPermissionHealth => PermissionWatchState.verified;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForAnyBusiness(bool Function(MemberPermissions p) check, {required bool whenUnknown}) => true;
}

class _Template extends Fake implements ContractTemplateModel {
  @override
  bool get isSupportedForNewUse => true;
}

final String _todayStr = () {
  final d = FormatHelper.toKstDate(vqNow());
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}();

Map<String, dynamic> _sec(int count, [Map<String, dynamic> extra = const {}]) => {
      'available': true,
      'count': count,
      'byBusiness': [
        {'businessId': 'biz1', 'count': count},
      ],
      ...extra,
    };

/// CF 직렬화 모양 그대로 — 모델 파싱도 production 경로.
AdminHomeSummaryModel _summary({
  int resign = 0, int? resignManual, int resignSoon = 0,
  int approval = 0, int approvalOverdue = 0,
  int schedule = 0, int unsent = 0,
  int unclosed = 0, String? unclosedOldest,
  int settlement = 0, int wageChange = 0,
  int unpaid = 0, int unpaidOverdue = 0, int unpaidMissing = 0,
  int expiring = 0, int expired = 0,
}) =>
    AdminHomeSummaryModel.fromMap({
      'actions': {
        'resignRequest': _sec(resign, {'soonCount': resignSoon, if (resignManual != null) 'manualReviewCount': resignManual}),
        'approval': _sec(approval, {'overdueCount': approvalOverdue}),
        'scheduleChangeRequest': _sec(schedule),
        'unsentContract': _sec(unsent),
        'unclosed': _sec(unclosed, {'oldestDate': unclosedOldest}),
        'settlementRequest': _sec(settlement),
        'wageChangeRequest': _sec(wageChange),
        'unpaidWage': _sec(unpaid, {'overdueCount': unpaidOverdue, 'missingDueDateCount': unpaidMissing}),
      },
      'upcoming': {
        'expiringContract': _sec(expiring, {'upcomingCount': expiring - expired, 'expiredCount': expired}),
      },
    });

AdminHomeReads _reads(AdminHomeSummaryModel summary) {
  BusinessModel biz() => BusinessModel(
        id: 'biz1', name: '강남 물류센터', ownerId: 'admin1', businessNumber: '000-00-00000', address: '서울시 어딘가',
        category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1));
  return AdminHomeReads(
    summary: ({String? selectedBusinessId}) async => summary,
    businessesByIds: (ids) async => [biz()],
    staffingReadiness: ({String? selectedBusinessId}) async => StaffingReadinessModel(
      available: true, partial: false, failedBusinessCount: 0, publishedPostingCount: 1,
      days: [
        StaffingDayData.fromMap({
          'date': _todayStr, 'requiredCount': 0, 'confirmedCount': 0, 'shortageCount': 0,
          'pendingAvailable': false, 'byBusiness': const <Map<String, dynamic>>[],
        }),
      ],
    ),
    attendanceByDate: ({required String businessId, required DateTime date}) async => const [],
    confirmedWorkers: ({required DateTime date, required String businessId}) async => const [],
    workDetailTimes: (_) async => <String, dynamic>{},
    postingReadiness: (bizs) async => {
      for (final b in bizs)
        b.id: BusinessPostingReadiness(
          bizId: b.id, isApproved: true, hasCanonicalLicense: true, hasOwnerLegacyLicense: false,
          hasActiveWorkTypes: true, hasEmployerSeal: true),
    },
    contractTemplates: (_) async => <ContractTemplateModel>[_Template()],
    tourCompleted: () => Future<bool>.value(true),
  );
}

Future<void> _pump(WidgetTester t, AdminHomeSummaryModel summary, {required Size size, required double scale, GlobalKey? key}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _AdminProvider()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RoleTheme.businessAdminTheme,
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: BusinessAdminHomeScreen(reads: _reads(summary)),
      ),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// 한 행의 기대 — 제목 · 알약(총수+단위) · 설명(총수 없음) · 보조줄.
typedef _Row = ({String title, String pill, String desc, List<String> subs});

String _label(_Row r) => [r.title, r.pill, r.desc, ...r.subs, '열기'].join(', ');

/// 9종 fixture — 3–4자리 수량 · 연체 이체 상향 · 마감 날짜(연도) · 보조줄 여럿.
final _nineSummary = _summary(
  resign: 1234, resignManual: 12, resignSoon: 3,
  approval: 4321, approvalOverdue: 99,
  schedule: 987, unsent: 1000,
  unclosed: 2345, unclosedOldest: '2026-10-07',
  settlement: 765, wageChange: 4567,
  unpaid: 1200, unpaidOverdue: 5, unpaidMissing: 34,
  expiring: 3456, expired: 78,
);

/// 화면 순서 그대로(연체 이체가 퇴사 요청 바로 뒤로 올라간다 — `_makeActionRows` 의 atIndex 규칙).
const List<_Row> _nineRows = [
  (title: '퇴사 요청', pill: '1234건', desc: '퇴사 요청을 검토해 주세요', subs: ['수동 검토 12건', '빠른 검토 필요 3건']),
  (title: '이체 대기', pill: '1234건', desc: '이체 확인이 필요한 급여가 있어요', subs: ['연체 5건', '지급일 확인 필요 34건']),
  (title: '지원 검토', pill: '4321건', desc: '대기 중인 지원을 확인해 주세요', subs: ['긴급 99건']),
  (title: '일정 변경 요청', pill: '987건', desc: '근로자의 일정 변경 요청이 있어요', subs: <String>[]),
  (title: '계약 미발송', pill: '1000건', desc: '발송이 필요한 계약이 있어요', subs: <String>[]),
  (title: '마감 필요', pill: '2345일', desc: '사업장별 미마감 근무일 합계', subs: ['가장 오래된 날 2026.10.07']),
  (title: '중간정산 요청', pill: '765건', desc: '대기 중인 중간정산 요청이 있어요', subs: <String>[]),
  (title: '급여 변경 요청', pill: '4567건', desc: '지급방식 변경 요청을 확인해 주세요', subs: <String>[]),
  (title: '계약 확인 필요', pill: '3456건', desc: '연장·종료를 정할 계약을 확인해 주세요', subs: ['만료 후 미결정 78건']),
];

/// 기기 캡처(x0_device/11_admin_home_todo.png)와 같은 3행.
final _threeSummary = _summary(unpaid: 1, unpaidOverdue: 1, unsent: 6, unclosed: 2, unclosedOldest: '2026-10-07');
const List<_Row> _threeRows = [
  (title: '이체 대기', pill: '1건', desc: '이체 확인이 필요한 급여가 있어요', subs: ['연체 1건']),
  (title: '계약 미발송', pill: '6건', desc: '발송이 필요한 계약이 있어요', subs: <String>[]),
  (title: '마감 필요', pill: '2일', desc: '사업장별 미마감 근무일 합계', subs: ['가장 오래된 날 2026.10.07']),
];

Finder _rowSem(_Row r) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.button == true && w.properties.label == _label(r));

Finder _txtIn(Finder host, String s) => find.descendant(of: host, matching: findVisibleText(s));

RenderParagraph _para(WidgetTester t, Finder text) =>
    t.renderObject<RenderParagraph>(find.descendant(of: text, matching: find.byType(RichText)).first);

/// 문단의 줄 수 — 전체 선택 상자의 서로 다른 top 수.
int _lines(RenderParagraph rp) {
  final s = rp.text.toPlainText();
  final tops = rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: s.length)).map((b) => b.top.round()).toSet();
  return tops.length;
}

/// 낱말(공백으로 나눈 조각)이 한 줄 안에 있는가 — 음절 끊김 0.
List<String> _brokenWords(RenderParagraph rp) {
  final s = rp.text.toPlainText();
  final broken = <String>[];
  var i = 0;
  for (final w in s.split(' ')) {
    if (w.isNotEmpty) {
      final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + w.length));
      if (boxes.map((b) => b.top.round()).toSet().length > 1) broken.add(visibleText(w));
    }
    i += w.length + 1;
  }
  return broken;
}

bool _overlap(Rect a, Rect b) => a.intersect(b).width > 0.5 && a.intersect(b).height > 0.5;
bool _inside(Rect inner, Rect outer) =>
    inner.left >= outer.left - 0.5 && inner.top >= outer.top - 0.5 && inner.right <= outer.right + 0.5 && inner.bottom <= outer.bottom + 0.5;

/// 점 [p] 의 hit 경로가 이 행 InkWell 의 receiver 에 닿고, 그 사이에 다른 탭 receiver 가 없는가.
bool _hitsRow(WidgetTester t, Finder rowInk, Offset p) {
  final listener = t.renderObject(find.descendant(of: rowInk, matching: find.byType(Listener)).first);
  final result = HitTestResult();
  t.binding.hitTestInView(result, p, t.view.viewId);
  for (final e in result.path) {
    final target = e.target;
    if (identical(target, listener)) return true;
    // 행 receiver 보다 먼저(더 깊이) 다른 제스처 receiver 를 만나면 같은 콜백이 아니다.
    if (target is RenderPointerListener) return false;
  }
  return false;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'tour_completed_admin_home': true}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  // ── §4-1 360dp/1.0 같은 3행 — 이전/이후 공통 관측(단언은 예외 0 뿐) ──
  testWidgets('TD-360 360dp/1.0 기기와 같은 3행 — 행 높이·글 줄 수 관측', (t) async {
    await t.runAsync(vqLoadFonts);
    final key = GlobalKey();
    await _pump(t, _threeSummary, size: const Size(360, 1600), scale: 1.0, key: key);
    expect(t.takeException(), isNull);
    final out = StringBuffer();
    var total = 0.0;
    for (final r in _threeRows) {
      final title = findVisibleText(r.title);
      expect(title, findsOneWidget, reason: '${r.title} 제목');
      final ink = find.ancestor(of: title, matching: find.byType(InkWell)).first;
      final rr = t.getRect(ink);
      total += rr.height;
      final texts = find.descendant(of: ink, matching: find.byType(RichText)).evaluate().toList();
      final parts = <String>[];
      for (final e in texts) {
        final rp = e.renderObject! as RenderParagraph;
        if (find.ancestor(of: find.byElementPredicate((x) => identical(x, e)), matching: find.byType(Icon)).evaluate().isNotEmpty) continue;
        parts.add('${visibleText(rp.text.toPlainText())}=${_lines(rp)}');
      }
      out.writeln('TD360 row=${r.title} h=${rr.height.toStringAsFixed(1)} w=${rr.width.toStringAsFixed(1)} lines[${parts.join(' | ')}]');
    }
    out.writeln('TD360 total3=${total.toStringAsFixed(1)}');
    // ignore: avoid_print
    print(out.toString().trimRight());
    await vqCapture(t, key, 'TD-360_admin_home_todo_3rows', conditions: {
      'screen': 'BusinessAdminHomeScreen(reads)', 'theme': 'RoleTheme.businessAdminTheme', 'viewport': '360x1600',
      'dpr': 1, 'textScaler': 1.0, 'rows': '이체 대기 1(연체1) · 계약 미발송 6 · 마감 2일(2026.10.07)',
      'source': Platform.environment['TD_SOURCE'] ?? '(unset)',
    });
  });

  // ── §4-1/2/3 — 9종 · 320dp 1.0/2.0 ──
  for (final scale in const [1.0, 2.0]) {
    testWidgets('TD-9 320dp/$scale 9종 — 넘침·말줄임·축소 0 · 알약 총수+단위 · 자연 전환 · 의미 노드 · 같은 콜백 · 순서', (t) async {
      await t.runAsync(vqLoadFonts);
      final sem = t.ensureSemantics();
      final key = GlobalKey();
      await _pump(t, _nineSummary, size: const Size(320, 6000), scale: scale, key: key);
      expect(t.takeException(), isNull, reason: '320dp/$scale 예외(넘침 포함) 0');
      final out = StringBuffer();
      var lastTop = -1.0;
      for (final r in _nineRows) {
        final id = '320/$scale ${r.title}';
        final row = _rowSem(r);
        expect(row, findsOneWidget, reason: '$id 의미 이름 = 제목, 총수+단위, 설명[, 보조줄], 열기');

        // ── 의미 노드: 버튼 하나 · 자식 0 · 총수+단위 1회 · 설명엔 총수 없음 ──
        final node = t.getSemantics(row);
        expect(node.hasFlag(SemanticsFlag.isButton), isTrue, reason: '$id 버튼');
        expect(node.label, _label(r), reason: '$id 의미 이름');
        expect(node.childrenCount, 0, reason: '$id 자식 의미 0(알약·꺾쇠·아이콘은 장식)');
        expect(find.bySemanticsLabel(_label(r)), findsOneWidget, reason: '$id 같은 의미 이름 노드 하나');
        final segs = _label(r).split(', ');
        expect(segs.where((s) => s == r.pill).length, 1, reason: '$id 총수+단위 `${r.pill}` 1회');
        expect(r.desc.contains(RegExp(r'\d')), isFalse, reason: '$id 설명에 총수 반복 0');

        // ── 받는 자리 하나 · 같은 콜백 ──
        final inks = find.descendant(of: row, matching: find.byType(InkWell));
        expect(inks, findsOneWidget, reason: '$id 행 InkWell 하나');
        expect(find.descendant(of: row, matching: find.byType(GestureDetector)), findsOneWidget, reason: '$id 탭 receiver 하나(알약·꺾쇠 별도 탭 0)');
        final ink = t.widget<InkWell>(inks);
        final semW = t.widget<Semantics>(row);
        expect(ink.onTap, isNotNull);
        expect(identical(ink.onTap, semW.properties.onTap), isTrue, reason: '$id 의미 탭 = 행 탭 같은 콜백');

        // ── 글: 전문 · 말줄임 0 · 축소 0 · 낱말 끊김 0 ──
        final rowRect = t.getRect(inks);
        final titleF = _txtIn(row, r.title);
        final pillF = _txtIn(row, r.pill);
        final descF = _txtIn(row, r.desc);
        expect(titleF, findsOneWidget, reason: '$id 제목 전문');
        expect(pillF, findsOneWidget, reason: '$id 알약 `${r.pill}` 전문(총수+단위) 한 번');
        expect(descF, findsOneWidget, reason: '$id 설명 전문');
        for (final s in r.subs) {
          expect(_txtIn(row, s), findsOneWidget, reason: '$id 보조줄 `$s` 전문');
        }
        final paras = find.descendant(of: row, matching: find.byType(RichText)).evaluate()
            .map((e) => e.renderObject! as RenderParagraph)
            .where((rp) => rp.text.toPlainText().trim().isNotEmpty && rp.text.toPlainText().runes.first < 0xE000) // 아이콘 글리프(사설 영역 · 보충 평면 포함)는 장식 — 글 검사 밖
            .toList();
        for (final rp in paras) {
          final txt = visibleText(rp.text.toPlainText());
          expect(rp.overflow == TextOverflow.ellipsis, isFalse, reason: '$id `$txt` 말줄임 0');
          expect(rp.didExceedMaxLines, isFalse, reason: '$id `$txt` 줄 수 한도 넘김 0');
          expect(rp.textScaler, TextScaler.linear(scale), reason: '$id `$txt` 글자 배율 그대로(축소 0)');
          expect(_brokenWords(rp), isEmpty, reason: '$id `$txt` 낱말 안 끊김 0');
          expect(_inside(t.getRect(find.byElementPredicate((e) => e.widget is RichText && e.renderObject == rp)), rowRect), isTrue, reason: '$id `$txt` 행 안');
        }
        expect(_para(t, titleF).text.style?.fontSize, 17, reason: '$id 제목 17 그대로');
        expect(find.descendant(of: row, matching: find.byType(FittedBox)), findsNothing, reason: '$id FittedBox 0');

        // ── 배치: 꺾쇠 하나(오른쪽) · 알약은 제목 묶음 안 · 겹침 0 · 자연 전환 ──
        final chev = find.descendant(of: row, matching: find.byIcon(Icons.chevron_right));
        expect(chev, findsOneWidget, reason: '$id 꺾쇠 하나');
        final cr = t.getRect(chev), tr = t.getRect(titleF), dr = t.getRect(descF);
        final pillBox = find.ancestor(of: pillF, matching: find.byType(Container)).first;
        final pr = t.getRect(pillBox);
        expect(_inside(pr, rowRect) && _inside(cr, rowRect), isTrue, reason: '$id 알약·꺾쇠 행 안');
        expect(_overlap(pr, tr), isFalse, reason: '$id 알약↔제목 겹침 0');
        expect(_overlap(pr, dr), isFalse, reason: '$id 알약↔설명 겹침 0');
        for (final rp in paras) {
          expect(_overlap(cr, t.getRect(find.byElementPredicate((e) => e.widget is RichText && e.renderObject == rp))), isFalse, reason: '$id 꺾쇠↔글 겹침 0');
        }
        expect(pr.right <= cr.left + 0.5, isTrue, reason: '$id 오른쪽 끝은 꺾쇠만(알약은 꺾쇠 왼쪽)');
        expect(pr.left >= tr.left - 0.5, isTrue, reason: '$id 알약은 본문 열 안');
        expect(pr.bottom <= dr.top + 0.5, isTrue, reason: '$id 알약은 설명 위(제목 묶음)');
        final sameLine = pr.left >= tr.right - 0.5 && pr.top < tr.bottom && pr.bottom > tr.top;
        final nextLine = pr.top >= tr.bottom - 0.5 && (pr.left - tr.left).abs() <= 0.5;
        expect(sameLine || nextLine, isTrue, reason: '$id 알약 = 제목 옆 또는 다음 줄 왼쪽(자연 전환)');
        final sub = r.subs.isEmpty ? null : _txtIn(row, r.subs.last);
        if (sub != null) expect(t.getRect(sub).top >= dr.bottom - 0.5, isTrue, reason: '$id 보조줄은 설명 아래');

        // ── 같은 콜백: 본문 · 알약 · 꺾쇠 위치가 같은 행 receiver 에 닿는다 ──
        for (final (what, p) in [('본문', dr.center), ('알약', pr.center), ('꺾쇠', cr.center)]) {
          expect(_hitsRow(t, inks, p), isTrue, reason: '$id $what 위치 → 같은 행 receiver');
        }

        // ── 순서 ──
        expect(rowRect.top > lastTop, isTrue, reason: '$id 행 순서');
        lastTop = rowRect.top;
        out.writeln('TD9 $id h=${rowRect.height.toStringAsFixed(1)} pill=${sameLine ? 'side' : 'next'} chev=${cr.top >= t.getRect(sub ?? descF).bottom - 0.5 ? 'below' : 'side'} '
            'titleLines=${_lines(_para(t, titleF))} descLines=${_lines(_para(t, descF))}');
      }
      // 마감 날짜 연도 보존
      expect(findVisibleText('가장 오래된 날 2026.10.07'), findsOneWidget, reason: '날짜 연도 보존');
      // ignore: avoid_print
      print(out.toString().trimRight());
      await vqCapture(t, key, 'TD-9_admin_home_todo_320x$scale', conditions: {
        'screen': 'BusinessAdminHomeScreen(reads)', 'theme': 'RoleTheme.businessAdminTheme', 'viewport': '320x6000',
        'dpr': 1, 'textScaler': scale, 'rows': '9종 3–4자리',
      });
      sem.dispose();
    });
  }
}
