// ignore_for_file: depend_on_referenced_packages
// [DU397] 소급 26 §3–§4 — 이번 주 숫자 폭 수리 추종: 주간 숫자 finder 표시 정규화 · paraOf · 칸 = cell Column · 기본 B/N fits 단언 ·
//   계약표 11-16 행 · 새 public DU397-WEEK-OVERFLOW-B(320×640@3.0 가로 스크롤 분기, 이름 끝 ' · D397FB').
// [DU394] 소급 23 §3–§4 날짜 (b) test-only — 기준일(DU1_VQ_DATE) 11-06 · 11-08 · 11-30 에서 날짜 줄 7칸 · 이번 주 점 · 날짜 시트 월 · 주간 숫자 · 월 링크를
//   실제 값으로 단언한다. 고정 표본(H100 11-08 숫자 9~12 · H101 평일 11-04 3점)은 원 조판 단언 그대로. 8 public 이름은 ' · D394DATE' 로 고정.
// [DU383 r4] 소급 22 (a″) — DU195-b 는 원 위치 단언 · 캡처 뒤 월 링크를 실제 스크롤 도달해 receiver · C201-2 재확인 · 월 링크 캡처(비동등 개정).
// [DU383 r3] 소급 21 (a′) — DU195-a 는 CTA · '내 지원 현황' 제목을 각각 실제 스크롤 도달(한 화면 동시 배치 단언 제거 — 비동등 계약 개정, 두 위치 캡처).
// [DU383 r2] 소급 19 — VQ-01d · H35-B 는 (a) 실제 스크롤 뒤 Hero 전문 도달(비동등 시험 계약 개정, 원 첫 화면 실패 보존) · DU195 CP03 추종.
// [DU383] CP03 홈 추종(시험만) — 확정 카드 시간 = Semantics('시작–끝') 안 두 토큰 · 날짜는 따로 보조 줄 · 사업장/업무 따로(Hero 말줄임 없음),
//   날짜 띠 질문 시각 삭제(그룹 의미 '일할 날짜 선택') · '날짜 더보기' → '날짜 선택'(시트 제목과 같은 글자 — 시트 쪽은 BottomSheet 범위),
//   문구표 UH098 · 099 · 101 · 102 · 123 · 144 · 150 · 151 · 섹션 제목 낱말 조판(findVisibleText). DU195 는 따로 추종.
// [DU382] CP05 일자리 상세 CTA '지원 준비하기' · '업무 자세히 보기' 는 낱말 조판 표시라 보이는 글자 정규화 찾기(findVisibleText)로 추종(같은 대상).
// [DU1 VQ · 후속10 §1] 대표 화면 LOCAL 렌더 PNG — 실제 production 화면 + production 역할 theme + 번들 NotoSansKR(Regular/Bold).
//   기기 캡처가 아니다. 같은 fixture·clock·viewport(390×844, DPR 1)·textScaler 1.0 로 전후를 그려 직접 비교 근거로 쓴다.
//   출력: build/du1_vq/<phase>/<run>/<id>.png → 회차 끝에 D:/AlFit-evidence/DU1/vq/png-runs 로 이동  (DU1_VQ_PHASE 없거나 비면 캡처 안 함 · DU1_VQ_RUN 없으면 실행 시각) — 같은 파일이 있으면 실패(덮어쓰지 않음)
//   기준일: DU1_VQ_DATE=YYYY-MM-DD(KST). 없으면 실행일. 실행 조건은 <phase>/<run>/run.json 에 남긴다.
//   무쓰기: reads 는 메모리 fixture, Firebase 는 가짜 플랫폼.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart' as cni;
import 'package:file/memory.dart' as memfs;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as fcm;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_model.dart';
import 'package:ALfit/screens/common/job_posting_reads.dart';
import 'package:ALfit/screens/common/job_posting_screen.dart';
import 'package:ALfit/services/work_type_guide_resolver.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/screens/user/my_applications_screen.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';
import 'support/checkin_contract_fixture.dart';

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

class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구', district: '역삼동'),
      accountStatus: 'active', passVerifiedAt: DateTime.now().subtract(const Duration(days: 30)), totalWorkDays: 3);
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

// [DU1 구현118 S041 사진 미리보기 의미] 이 probe 동안만 CachedNetworkImageProvider.defaultCacheManager 를 바꿔 지정 URL 에
//   LOCAL 사진 bytes(메모리 파일 — package:file MemoryFileSystem)를 돌려준다. 네트워크·디스크·path_provider 를 쓰지 않는다.
//   cached_network_image 3.4.1 의 로더는 ImageCacheManager 가 아니면 getFileStream 만 부른다(_image_loader.dart:96~124). 나머지는 쓰이지 않는다.
class _LocalPhotoCacheManager implements fcm.BaseCacheManager {
  _LocalPhotoCacheManager(this.url, this.bytes);
  final String url;
  final List<int> bytes;
  final calls = <String>[];
  @override
  Stream<fcm.FileResponse> getFileStream(String url, {String? key, Map<String, String>? headers, bool withProgress = false}) {
    calls.add(url);
    if (url != this.url) return Stream.error(StateError('LOCAL 사진 없음: $url'));
    final f = memfs.MemoryFileSystem().file('/local-photo.png')..writeAsBytesSync(bytes);
    return Stream.value(fcm.FileInfo(f, fcm.FileSource.Cache, DateTime(2100), url));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final DateTime? _baseDate = () {
  final v = Platform.environment['DU1_VQ_DATE'];
  if (v == null || v.isEmpty) return null;
  final p = v.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]).subtract(const Duration(hours: 9)); // KST 자정 instant
}();
final DateTime _today = FormatHelper.toKstDate(_baseDate ?? DateTime.now());
DateTime _day(int o) => _today.add(Duration(days: o));
final DateTime _clock = () {
  final k = (_baseDate ?? DateTime.now()).toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day, 10).subtract(const Duration(hours: 9));
}();

// ── [DU394] 날짜 (b) helper — 제품 clock seam 0(UserHomeScreen.clock 만), 기준일 = DU1_VQ_DATE(없으면 실행일) ──
//   고정 표본: H100 숫자 9~12(한/두 자리) = 11-08 · H101 평일 3점 = 11-04(오늘 · +1 · +2 가 같은 주).
//   계약표 = Codex 소급 23 독립 기대(audits/du-self-review-23-20261116/agent383/date_contract.json) 그대로.
DateTime _kstAt394(DateTime d) => DateTime.utc(d.year, d.month, d.day, 10).subtract(const Duration(hours: 9)); // 그날 KST 10:00 instant
final DateTime _sampleStrip394 = DateTime.utc(2026, 11, 8);
final DateTime _sampleWeek394 = DateTime.utc(2026, 11, 4);
String _ymd394(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
List<DateTime> _stripDays394(DateTime today) => [for (var i = 0; i < 7; i++) today.add(Duration(days: i))];
List<DateTime> _weekDays394(DateTime today) {
  final mon = today.subtract(Duration(days: today.weekday - 1));
  return [for (var i = 0; i < 7; i++) mon.add(Duration(days: i))];
}

const _contract394 = <String, Map<String, Object>>{
  '2026-11-06': {
    'strip': ['2026-11-06', '2026-11-07', '2026-11-08', '2026-11-09', '2026-11-10', '2026-11-11', '2026-11-12'],
    'week': ['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06', '2026-11-07', '2026-11-08'],
    'h100w': ['2026-11-07'],
    'h101': [['2026-11-06', 'pending'], ['2026-11-07', 'confirmed'], ['2026-11-08', 'pending']],
    'select': '2026-11-09',
  },
  '2026-11-08': {
    'strip': ['2026-11-08', '2026-11-09', '2026-11-10', '2026-11-11', '2026-11-12', '2026-11-13', '2026-11-14'],
    'week': ['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06', '2026-11-07', '2026-11-08'],
    'h100w': [],
    'h101': [['2026-11-08', 'pending']],
    'select': '2026-11-11',
  },
  '2026-11-30': {
    'strip': ['2026-11-30', '2026-12-01', '2026-12-02', '2026-12-03', '2026-12-04', '2026-12-05', '2026-12-06'],
    'week': ['2026-11-30', '2026-12-01', '2026-12-02', '2026-12-03', '2026-12-04', '2026-12-05', '2026-12-06'],
    'h100w': ['2026-12-01'],
    'h101': [['2026-11-30', 'pending'], ['2026-12-01', 'confirmed'], ['2026-12-02', 'pending']],
    'select': '2026-12-03',
  },
  // [DU397] 인계 26 §4 독립 행 — 11-16(월): 7칸 · 이번 주 11/16–22, H100-W 11/17 확정 1점, H101 11/16 대기 · 11/17 확정 · 11/18 대기, 확정 +3 = 11/19
  '2026-11-16': {
    'strip': ['2026-11-16', '2026-11-17', '2026-11-18', '2026-11-19', '2026-11-20', '2026-11-21', '2026-11-22'],
    'week': ['2026-11-16', '2026-11-17', '2026-11-18', '2026-11-19', '2026-11-20', '2026-11-21', '2026-11-22'],
    'h100w': ['2026-11-17'],
    'h101': [['2026-11-16', 'pending'], ['2026-11-17', 'confirmed'], ['2026-11-18', 'pending']],
    'select': '2026-11-19',
  },
};

// 계산값(시험 helper)이 계약표와 같은지. 표에 없는 기준일은 'computed'(gate394 는 'table' 만 통과).
String _contractCheck394(String tok) {
  final row = _contract394[_ymd394(_today)];
  if (row == null) return 'computed';
  expect(_stripDays394(_today).map(_ymd394).toList(), row['strip'], reason: '$tok 표시 7칸 = 계약표');
  expect(_weekDays394(_today).map(_ymd394).toList(), row['week'], reason: '$tok 이번 주 = 계약표');
  return 'table';
}

void _d394(String line) {
  // ignore: avoid_print
  print(line);
}

String _start394(String tok) =>
    'D394 $tok base=${_ymd394(_today)} today=${_ymd394(_today)} clock=${_clock.toIso8601String()} env=${Platform.environment['DU1_VQ_DATE'] ?? '(unset)'}';

// [DU394] 이번 주 일정 7칸 점 — 섹션(흰 Container · Column) 안 숫자 칸(Expanded)에 채운 점(지름 4~8 · 불투명)을 매핑한다.
//   칸에 들지 않는 점 = 범례 점(범례 줄). 점은 모두 보이는 영역 안이어야 한다. 한 칸에 점 2개면 실패.
({Map<int, int> days, int legend, String desc}) _weekDots394(WidgetTester t, List<DateTime> week, bool Function(Rect) visible) {
  final title = findVisibleText('이번 주 일정');
  expect(title, findsOneWidget, reason: '이번 주 일정 제목 1');
  final sec = find
      .ancestor(of: title, matching: find.byWidgetPredicate((w) => w is Container && w.color == Colors.white && w.padding != null && w.child is Column))
      .first;
  // [DU397] 기본 배율(N@1.0)은 7칸 균등 — 가로 스크롤 분기가 아니다
  expect(find.descendant(of: sec, matching: find.byType(Scrollable)), findsNothing, reason: '이번 주 7칸 균등(가로 스크롤 0)');
  final cols = <Rect>[];
  for (final d in week) {
    // [DU397] 숫자는 묶음 표시(제어문자) — 보이는 글자 정확 원문 1개 · 칸 = 그 숫자를 가진 cell Column
    final df = find.descendant(of: sec, matching: findVisibleText('${d.day}'));
    expect(df, findsOneWidget, reason: '이번 주 숫자 ${d.day} 정확히 1');
    cols.add(t.getRect(find.ancestor(of: df, matching: find.byType(Column)).first));
  }
  final days = <int, int>{};
  var legend = 0;
  var hidden = 0;
  final desc = <String>[];
  for (final e in find.descendant(of: sec, matching: find.byType(Container)).evaluate()) {
    final c = e.widget as Container;
    final dd = c.decoration;
    if (dd is! BoxDecoration || dd.shape != BoxShape.circle || dd.color == null || dd.color!.a == 0) continue;
    final ro = e.renderObject! as RenderBox;
    final r = ro.localToGlobal(Offset.zero) & ro.size;
    if (r.width < 4 || r.width > 8) continue;
    if (!visible(r)) hidden++;
    final ix = [
      for (var i = 0; i < 7; i++)
        if (r.center.dx >= cols[i].left && r.center.dx < cols[i].right && r.top >= cols[i].top - 0.5 && r.bottom <= cols[i].bottom + 0.5) i
    ];
    final col = dd.color!.toARGB32();
    if (ix.length == 1) {
      expect(days.containsKey(ix.first), isFalse, reason: '이번 주 칸 ${ix.first} 점 2개');
      days[ix.first] = col;
    } else {
      legend++;
    }
    desc.add('${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)} #${col.toRadixString(16).toUpperCase()} 칸=${ix.length == 1 ? ix.first : '-'}');
  }
  expect(hidden, 0, reason: '이번 주 점 · 범례 점 모두 보이는 영역 안');
  return (days: days, legend: legend, desc: desc.join(' ; '));
}

ApplicationModel _short(String id, int dayOffset,
        {DateTime? confirmedAt, String type = '피킹', String start = '09:00', String end = '18:00', DateTime? today}) =>
    ApplicationModel(
      id: id, toId: 'to_$id', uid: 'u1', businessId: 'biz1', businessName: '강남 물류센터', toTitle: '단기 공고',
      status: AppStatus.confirmed, selectedWorkType: type, startTime: start, endTime: end, wage: 12000, wageType: 'hourly',
      // [DU394] today 를 주면 그날 기준(고정 표본), 없으면 원래대로 _today 기준
      workDate: today == null ? _day(dayOffset) : today.add(Duration(days: dayOffset)), confirmedAt: confirmedAt,
      appliedAt: today == null ? _day(-3) : today.add(const Duration(days: -3)));

// [DU383] CP03 Q4 확정 카드 큰 시간 — Semantics(label '시작–끝') 안에 보이는 두 토큰 '시작' · '–끝'(토큰 사이에서만 줄바꿈).
//   의미 노드와 보이는 두 토큰이 함께 있는 것만 잡는다.
Finder _promiseTimeFinder(String start, String end) => find.byElementPredicate((e) {
      final w = e.widget;
      if (w is! Semantics || w.properties.label != '$start–$end') return false;
      final seen = <String>{};
      void walk(Element x) {
        final xw = x.widget;
        if (xw is Text && xw.data != null) seen.add(xw.data!);
        x.visitChildren(walk);
      }
      e.visitChildren(walk);
      return seen.contains(start) && seen.contains('–$end');
    });
// [DU383] CP03 UH086 — 질문 `언제 일하고 싶으세요?` 시각 삭제, 날짜 띠 그룹 의미 `일할 날짜 선택`
Finder _dateExplorerGroup() => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '일할 날짜 선택');
// [DU383] CP03 UH089 — 홈 행동과 날짜 시트 제목이 같은 `날짜 선택` 이다. 시트 쪽은 BottomSheet 안의 것만.
Finder _dateSheetTitle() => find.descendant(of: find.byType(BottomSheet), matching: find.text('날짜 선택'));

// [DU383 r2] 소급 19 (a) — CP03 순서(날짜 띠 → 필수응답 → Hero)와 2.0 배율을 그대로 두고, 새 확정 Hero 의 날짜 · 시간 · 사업장 · 업무를
//   각각 실제 스크롤(Scrollable.ensureVisible)로 들여 본문 Scrollable 표시 영역(고정 머리 아래 · clip) 안에 전문이 들어오는지 본다.
//   Hero = '근무 확인하기'를 품은 가장 가까운 탭 가능 GestureDetector. 찾기는 그 범위 안으로 좁히고 유일성을 단언한다.
Future<void> _heroReach(WidgetTester t,
    {required String tag, required String date, required String start, required String end, required String biz, required String work}) async {
  final hero = find.ancestor(of: find.text('근무 확인하기'), matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onTap != null)).first;
  Finder inHero(Finder f) => find.descendant(of: hero, matching: f);
  final targets = <String, Finder>{
    '날짜': inHero(findVisibleText(date)),
    '시간': inHero(_promiseTimeFinder(start, end)),
    '사업장': inHero(findVisibleText(biz)),
    '업무': inHero(findVisibleText(work)),
  };
  for (final e in targets.entries) {
    expect(e.value, findsOneWidget, reason: '$tag Hero 안 ${e.key} 1개');
  }
  // 사업장 · 업무 원문 Text 는 Hero 밖에 없다(아래 일정 카드는 '사업장 · 업무' 합친 한 줄)
  expect(findVisibleText(biz), findsOneWidget, reason: '$tag 사업장 원문 Text 전역 1개(= Hero)');
  expect(findVisibleText(work), findsOneWidget, reason: '$tag 업무 원문 Text 전역 1개(= Hero)');
  for (final k in const ['사업장', '업무']) {
    expect(t.widget<Text>(targets[k]!).maxLines, isNull, reason: '$tag Hero $k 말줄임 없이 줄바꿈');
  }
  final all = find.byType(Scrollable);
  final cands = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
      .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
      .toList()
    ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
  final body = cands.first;
  final pos = t.state<ScrollableState>(body).position;
  final vp = t.getRect(body);
  bool inside(Rect r) => r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5 && r.left >= vp.left - 0.5 && r.right <= vp.right + 0.5;
  // ignore: avoid_print
  print('$tag 도달 시작 offset=${pos.pixels.toStringAsFixed(1)} viewport=$vp max=${pos.maxScrollExtent.toStringAsFixed(1)}');
  final contentTop = <String, double>{};
  for (final e in targets.entries) {
    await t.ensureVisible(e.value);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final r = t.getRect(e.value);
    // ignore: avoid_print
    print('$tag 도달 ${e.key} offset=${pos.pixels.toStringAsFixed(1)} rect=$r inside=${inside(r)}');
    expect(inside(r), isTrue, reason: '$tag ${e.key} 전문이 본문 표시 영역 안 $r / $vp');
    contentTop[e.key] = r.top + pos.pixels;
    if (e.key == '시간') {
      final a = t.getRect(find.descendant(of: e.value, matching: find.text(start)));
      final b = t.getRect(find.descendant(of: e.value, matching: find.text('–$end')));
      final ordered = (a.top - b.top).abs() < 2 ? a.left < b.left : a.top < b.top;
      // ignore: avoid_print
      print('$tag 시간 토큰 $start=$a –$end=$b 순서=$ordered');
      expect(inside(a) && inside(b) && ordered, isTrue, reason: '$tag 시간 두 토큰 보임 · 순서');
    }
  }
  final order = targets.keys.toList();
  for (var i = 1; i < order.length; i++) {
    expect(contentTop[order[i - 1]]! < contentTop[order[i]]!, isTrue,
        reason: '$tag Hero 순서 ${order[i - 1]} → ${order[i]} $contentTop');
  }
}

UserHomeReads _reads(List<ApplicationModel> apps, {LegalReadiness legal = const LegalReadiness(status: LegalReadinessStatus.current)}) {
  Future<List<ApplicationModel>>? last;
  return UserHomeReads(
    slotsForTO: (_) async => const <SlotModel>[],
    myContracts: (_) async => completedContractsFor(await (last ?? Future.value(const <ApplicationModel>[]))),
    myApplications: (_) => last = Future.value(apps),
    myMonthlyAttendances: ({required String userId, required int year, required int month}) async => const [],
    publishedTOs: () async => const [],
    pendingIdCardRequests: (_) async => const [],
    myRenewalProposals: () async => const <RenewalProposalModel>[],
    businessById: (_) async => BusinessModel(
        id: 'biz1', name: '강남 물류센터', ownerId: 'a1', businessNumber: '000-00-00000', address: '서울특별시 강남구 테헤란로 1',
        category: '물류', subCategory: '창고', isApproved: true, createdAt: _day(-200)),
    invalidatePublishedTOsCache: () {},
    documentCorrections: () async => DocumentCorrectionSurface.empty,
    legalReadiness: () async => legal,
  );
}

// ── VQ-02 일자리 상세 fixture — 여러 날짜 × 업무 2개, 한 날짜는 정원 찬 상태 ──
DateTime _kstMid(int plus) {
  final k = (_baseDate ?? DateTime.now()).toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day + plus).subtract(const Duration(hours: 9));
}

WorkDetailData _wd(String id, String type, String start, String end, int wage, int req) => WorkDetailData(
    wdId: id, workType: type, workTypeIcon: 'box', workTypeColor: '#3859E8', workTypeBackgroundColor: '#EEF2FF',
    wage: wage, wageType: 'hourly', requiredCount: req, startTime: start, endTime: end, order: 0,
    breakMinutes: 60);

SlotModel _slot(String id, int plus, {bool full = false}) => SlotModel(
    id: id, toId: 'to1', date: _kstMid(plus),
    workDetails: [
      _wd('wdA', '피킹', '09:00', '18:00', 12000, 3),
      _wd('wdB', '상하차', '13:00', '22:00', 13500, 2),
    ],
    status: full ? SlotStatus.full : SlotStatus.open, confirmedCount: full ? 5 : 1, createdAt: DateTime(2026, 10, 1));

TOModel _to() => TOModel(
    id: 'to1', businessId: 'biz1', businessName: '강남 물류센터 평택 2공장', type: 'flex', title: '주말 물류 단기 모집',
    creatorUID: 'a1', status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0, workDetails: const [],
    totalRequired: 15, totalConfirmed: 7, totalPending: 0, isPublished: true, publishMode: 'immediate',
    createdAt: DateTime(2026, 10, 1), statusUpdatedAt: DateTime(2026, 10, 1));

// [DU1 구현126 C124-2] rules 는 선택 인자 — 기본 null 이면 예전과 같은 BusinessModel(근태 기준 없음)이다.
JobPostingReads _jobReads(List<SlotModel> slots, {AttendanceRules? rules}) => JobPostingReads(
    toOrFailure: (id) async => (to: _to(), failed: false),
    workDetails: (id) async => const <WorkDetailModel>[],
    businessById: (id) async => BusinessModel(
        id: 'biz1', name: '강남 물류센터 평택 2공장', ownerId: 'a1', businessNumber: '000-00-00000', address: '경기도 평택시 포승읍 1',
        category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2025), attendanceRules: rules),
    slots: (id, {bool visibleOnly = true}) async => slots,
    myApplications: (uid) async => const <ApplicationModel>[],
    workTypeCatalog: (id) async => WorkTypeCatalog.empty,
    applicationOnce: (id) async => null);

// [후속12 §1] PHASE 가 없거나 비면 **파일을 쓰지 않는다**(관련 시험 일괄 실행은 렌더 예외만 본다) — 10:56 before 덮어쓰기 사고 뒤
final String _phaseRaw = Platform.environment['DU1_VQ_PHASE'] ?? '';
final bool _captureOn = _phaseRaw.isNotEmpty;
final _phase = _phaseRaw;
final _run = Platform.environment['DU1_VQ_RUN'] ?? DateTime.now().toIso8601String().replaceAll(':', '').split('.').first;
// 캡처는 확인용으로 build/du1_vq 에 쓰고 회차 끝에 D:/AlFit-evidence/DU1/vq/png-runs 로 옮긴다(작은 PNG, C 용량 영향 미미)
// [DU1 후속35 §3.4] DU1_VQ_OUT 이 있으면 그 폴더(records 새 차수)에 직접 쓴다 — 없으면 기존 build/du1_vq
final _outDir = Directory('${(Platform.environment['DU1_VQ_OUT'] ?? '').isNotEmpty ? Platform.environment['DU1_VQ_OUT'] : 'build/du1_vq'}/$_phase/$_run');
// [후속13 §1-2] null=아직, true=기록함, false=충돌로 실패 — 충돌 뒤 다음 셀도 새 PNG 를 쓰지 않는다
bool? _runJsonState;
void _writeRunJson() {
  if (_runJsonState == true) return;
  if (_runJsonState == false) throw StateError('이 run 은 기록 충돌로 실패했다 — 새 PNG 를 쓰지 않는다');
  _outDir.createSync(recursive: true);
  final rj = File('${_outDir.path}/run.json');
  if (rj.existsSync()) {
    _runJsonState = false;
    throw StateError('run.json 이 이미 있다 — 다른 DU1_VQ_RUN 을 쓴다: ${rj.path}');
  }
  _runJsonState = true;
  rj.writeAsStringSync('{"phase":"$_phase","run":"$_run","baseDate":"${Platform.environment['DU1_VQ_DATE'] ?? 'now'}",'
      '"clockUtc":"${_clock.toIso8601String()}","viewport":"셀별 — <id>.cell.txt","dpr":"셀별","textScaler":"셀별","inset":0,'
      '"fonts":"$_fontsNote",'
      '"startedAt":"${DateTime.now().toIso8601String()}"}');
}

// [후속16 §1] 이 하네스(_loadFonts)가 실제로 등록하는 글꼴 — VQ-03(admin_home_content_render_test, vqLoadFonts)은 FlutterTest 를 등록하지 않는다
const _fontsNote = 'NotoSansKR Regular+Bold · Roboto=NotoSansKR Regular+Bold · FlutterTest=NotoSansKR Regular 만(굵기 합성) · MaterialIcons(SDK) — 기기 글꼴 아님(근사)';

Future<void> _capture(WidgetTester t, Widget screen, String id,
    {UserProvider? up, ThemeData? theme, Size size = const Size(390, 844), double scale = 1.0, Future<void> Function()? beforeShot,
    String scroll = 'none — 첫 화면', String? topId}) async {
  final key = GlobalKey();
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: up ?? _Worker()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: RepaintBoundary(
      key: key,
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme ?? RoleTheme.workerTheme,
          builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: screen),
    ),
  ));
  for (var i = 0; i < 25; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  // [후속17 §1.3] scroll 전후 실제 offset(첫 Scrollable 기준 — 없으면 none)
  String offsetNow() {
    final sc = find.byType(Scrollable);
    if (sc.evaluate().isEmpty) return 'none';
    return t.state<ScrollableState>(sc.first).position.pixels.toStringAsFixed(0);
  }
  final offsetBefore = offsetNow();
  // [DU383 r2] topId 가 있으면 beforeShot(스크롤 도달) 전에 첫 화면(offset 0)을 먼저 남긴다 — 없는 호출은 이 블록을 지나지 않는다.
  if (topId != null && _captureOn) {
    final tb = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      final image = await tb.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      _writeRunJson();
      final out = File('${_outDir.path}/$topId.png');
      if (out.existsSync()) throw StateError('이미 있는 캡처를 덮지 않는다: ${out.path}');
      out.writeAsBytesSync(bytes!.buffer.asUint8List());
      final cell = File('${_outDir.path}/$topId.cell.txt');
      if (cell.existsSync()) throw StateError('이미 있는 셀 기록을 덮지 않는다: ${cell.path}');
      cell.writeAsStringSync([
        'id=$topId', 'viewport=${size.width.toInt()}x${size.height.toInt()}', 'dpr=1.0', 'textScaler=$scale',
        'theme=${theme == null ? 'RoleTheme.workerTheme(기본값 — _capture 가 적용)' : '호출자 주입 ThemeData'}',
        'fonts=$_fontsNote', 'scroll=스크롤 전 첫 화면', 'scrollOffset=$offsetBefore',
        'baseDate=${Platform.environment['DU1_VQ_DATE'] ?? 'now'}', 'clockUtc=${_clock.toIso8601String()}',
      ].join('\n'));
    });
  }
  if (beforeShot != null) await beforeShot();
  final offsetAfter = offsetNow();
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  if (_captureOn) {
    await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    _writeRunJson();
    final out = File('${_outDir.path}/$id.png');
    if (out.existsSync()) throw StateError('이미 있는 캡처를 덮지 않는다: ${out.path}');
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    // [후속16 §1] 셀별 실제 조건 — run.json 의 run 공통값과 따로, 이 PNG 가 찍힌 조건 그대로
    final cell = File('${_outDir.path}/$id.cell.txt');
    if (cell.existsSync()) throw StateError('이미 있는 셀 기록을 덮지 않는다: ${cell.path}');
    cell.writeAsStringSync([
      'id=$id', 'viewport=${size.width.toInt()}x${size.height.toInt()}', 'dpr=1.0', 'textScaler=$scale',
      // [후속17 §1.3] RoleTheme getter 는 호출마다 새 ThemeData 라 identical 판별이 'custom' 으로 틀렸다(r7) — 주입 여부로 기록
      'theme=${theme == null ? 'RoleTheme.workerTheme(기본값 — _capture 가 적용)' : '호출자 주입 ThemeData'}',
      'inset=padding(${t.view.padding.left},${t.view.padding.top},${t.view.padding.right},${t.view.padding.bottom}) '
          'viewInsets(${t.view.viewInsets.left},${t.view.viewInsets.top},${t.view.viewInsets.right},${t.view.viewInsets.bottom})',
      'fonts=$_fontsNote', 'scroll=$scroll', 'scrollOffsetBefore=$offsetBefore', 'scrollOffsetAfter=$offsetAfter',
      'baseDate=${Platform.environment['DU1_VQ_DATE'] ?? 'now'}', 'clockUtc=${_clock.toIso8601String()}',
    ].join('\n'));
    });
  }
  expect(t.takeException(), isNull, reason: '$id 렌더 예외');
  await t.pumpWidget(const SizedBox.shrink());
}

Future<void> _loadFonts() async {
  final loader = FontLoader('NotoSansKR')
    ..addFont(File('assets/fonts/NotoSansKR-Regular.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)))
    ..addFont(File('assets/fonts/NotoSansKR-Bold.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)));
  await loader.load();
  // theme fontFamily 를 따르지 않는 글자(버튼 label 등)는 기기에서 시스템 기본(Android Roboto→한글 대체)으로 그려진다.
  //   시험 기본 글꼴은 네모라, 같은 번들 NotoSansKR 을 'Roboto' 이름으로도 등록해 기기 대체를 근사한다(정확한 기기 글꼴 아님).
  final roboto = FontLoader('Roboto')
    ..addFont(File('assets/fonts/NotoSansKR-Regular.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)))
    ..addFont(File('assets/fonts/NotoSansKR-Bold.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)));
  await roboto.load();
  // fontFamily 가 아예 없는 글자(예: 버튼 textStyle 이 ResponsiveHelper.tinyStyle 을 그대로 쓰는 경우)는 시험 기본 글꼴(FlutterTest)로 간다.
  //   기기에서는 시스템 글꼴로 그려진다 — 근사로 같은 NotoSansKR 을 등록한다(이 글자들이 theme 글꼴을 안 따르는 것 자체는 보고 대상).
  final testDefault = FontLoader('FlutterTest')
    ..addFont(File('assets/fonts/NotoSansKR-Regular.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)));
  await testDefault.load();
  // 아이콘 글꼴(시험 기본은 네모로 그린다) — 설치 Flutter SDK 의 MaterialIcons
  final icons = FontLoader('MaterialIcons')
    ..addFont(File('C:/Users/kug02/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf').readAsBytes().then((b) => ByteData.view(b.buffer)));
  await icons.load();
}

final bool _ns1Skip = DateTime.now().toUtc().add(const Duration(hours: 9)).hour >= 22;

void main() {
  // 첫 실행 안내(onboarding_completed_<uid>)·홈 투어(tour_completed_*)는 본 사용자 상태로 — 홈 본문을 그린다
  setUp(() => SharedPreferences.setMockInitialValues({'onboarding_completed_u1': true, 'onboarding_completed_a1': true, 'tour_completed_user_home': true, 'tour_completed_admin_home': true}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    await _loadFonts();
  });

  testWidgets('VQ-01a 지원자 홈 — 새 확정(미열람) + 다가오는 확정 + 약관 재동의 할 일', (t) async {
    await _capture(
      t,
      UserHomeScreen(
        reads: _reads([
          _short('new1', 3, confirmedAt: _clock.subtract(const Duration(hours: 2))),
          _short('next2', 5, type: '상하차', start: '13:00', end: '22:00'),
        ], legal: const LegalReadiness(status: LegalReadinessStatus.reconsentRequired, reconsentRequired: ['service_terms'])),
        clock: () => _clock,
      ),
      'VQ-01a_user_home_new_confirm',
    );
  });

  testWidgets('VQ-02 일자리 상세 — 여러 날짜(1개 정원 참) × 업무 2개, 첫 날짜 선택', (t) async {
    final slots = [_slot('s1', 1), _slot('s2', 2, full: true), _slot('s3', 3)];
    await _capture(t, JobPostingScreen(to: _to(), workDetails: const [], slotDate: slots.first.date, reads: _jobReads(slots)),
        'VQ-02_job_detail_multi_date');
  });

  // [DU1 후속70 §2 VQ-02] 업무별 카드·보조정보 반복 구간 — 두 번째 업무(상하차) 행이 보이는 위치까지 실제 스크롤
  testWidgets('VQ-02b 일자리 상세 390×844 — 업무 2개 반복 구간(상하차까지 스크롤)', (t) async {
    final slots = [_slot('s1', 1), _slot('s2', 2, full: true), _slot('s3', 3)];
    await _capture(t, JobPostingScreen(to: _to(), workDetails: const [], slotDate: slots.first.date, reads: _jobReads(slots)),
        'VQ-02b_job_detail_work_repeat',
        scroll: "scrollUntilVisible(Text '상하차', 120) 뒤 표시 영역 정렬",
        beforeShot: () async {
          final target = find.text('상하차');
          await t.scrollUntilVisible(target.first, 120, scrollable: find.byType(Scrollable).first);
          await t.pump(const Duration(milliseconds: 300));
          expect(target, findsWidgets);
        });
  });

  // [DU1 후속36 §2] S041 버튼 행 여백을 바꿨다 → 대표 두 날짜에서 선택 → 다른 날짜 → 되돌아옴 → 선택 유지·개수·다음 행동 대상 보존
  testWidgets('S041-SEL 일자리 상세 390×844 — 11/6 피킹 선택 → 11/8 → 11/6 재방문 · 선택 유지 · CTA 대상 그대로', (t) async {
    final slots = [_slot('s1', 1), _slot('s2', 2, full: true), _slot('s3', 3)];
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(theme: RoleTheme.workerTheme,
          home: JobPostingScreen(to: _to(), workDetails: const [], slotDate: slots.first.date, reads: _jobReads(slots))),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    String ctaText() => t.widgetList<Text>(find.descendant(of: find.byType(ElevatedButton), matching: find.byType(Text)))
        .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '').where((s) => s.contains('지원')).join('|');
    final before = ctaText();
    await t.tap(find.text('선택').first);
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('선택됨'), findsOneWidget, reason: '11/6 피킹 선택');
    final afterSelect = ctaText();
    final d1 = _kstMid(1).add(const Duration(hours: 9)); final d3 = _kstMid(3).add(const Duration(hours: 9));
    await t.tap(find.text('${d3.month}/${d3.day}'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final otherDaySelected = find.text('선택됨').evaluate().length;
    await t.tap(find.text('${d1.month}/${d1.day}'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('선택됨'), findsOneWidget, reason: '재방문 — 11/6 피킹 선택 유지');
    final revisit = ctaText();
    // ignore: avoid_print
    print('S041-SEL cta before="$before" afterSelect="$afterSelect" otherDay선택됨=$otherDaySelected revisit="$revisit"');
    expect(revisit, afterSelect, reason: '다음 행동 대상·개수 그대로');
    expect(t.takeException(), isNull);
  });

  // ── [DU1 후속37 §1] S041 보완 — 실제 스크롤 표시 영역 기준(root 0..844 아님) · 정확한 선택 목록/합계 · 실제 다음 행동(준비 시트)
  Future<void> s041Pump(WidgetTester t, List<SlotModel> slots) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(theme: RoleTheme.workerTheme,
          home: JobPostingScreen(to: _to(), workDetails: const [], slotDate: slots.first.date, reads: _jobReads(slots))),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }
  // 업무명(카드 제목)이 들어 있는 업무 카드의 선택 버튼 — 카드 = 제목의 가장 가까운 조상 Container(clipBehavior antiAlias, 업무 카드 외곽)
  Finder s041Card(String workName) =>
      find.ancestor(of: find.text(workName), matching: find.byWidgetPredicate((w) => w is Container && w.clipBehavior == Clip.antiAlias)).first;
  Finder s041CardButton(String workName) {
    final card = s041Card(workName);
    return find.descendant(of: card, matching: find.byWidgetPredicate((w) => w is Text && (w.data == '선택' || w.data == '선택됨')));
  }
  Future<({Rect viewport, Rect button, Rect cta, double before, double after})> s041ShowButton(WidgetTester t, String workName) async {
    final sc = find.byType(Scrollable).first;
    final pos = t.state<ScrollableState>(sc).position;
    final before = pos.pixels;
    final label = s041CardButton(workName);
    await t.scrollUntilVisible(label, 80, scrollable: sc, maxScrolls: 40);
    await t.pump(const Duration(milliseconds: 100));
    final vp = t.getRect(sc);
    final ctaRect = t.getRect(find.ancestor(of: findVisibleText('지원 준비하기'), matching: find.byType(ElevatedButton)).first);
    final btn = find.ancestor(of: label.first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
    var r = t.getRect(btn);
    final limit = vp.bottom < ctaRect.top ? vp.bottom : ctaRect.top; // 고정 CTA 위까지만 '보이는 영역'
    if (r.bottom > limit - 8) pos.jumpTo((pos.pixels + (r.bottom - (limit - 8))).clamp(pos.minScrollExtent, pos.maxScrollExtent));
    if (r.top < vp.top + 8) pos.jumpTo((pos.pixels - (vp.top + 8 - r.top)).clamp(pos.minScrollExtent, pos.maxScrollExtent));
    await t.pump(const Duration(milliseconds: 100));
    r = t.getRect(btn);
    return (viewport: vp, button: r, cta: ctaRect, before: before, after: pos.pixels);
  }

  testWidgets('S041-VIS 390×844 — 두 번째 업무(상하차) 선택 버튼 모양 전체가 표시 영역·고정 CTA 위 · 실제 탭 → 선택됨', (t) async {
    final slots = [_slot('s1', 1), _slot('s2', 2, full: true), _slot('s3', 3)];
    final overflows = <String>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      final m = d.exceptionAsString();
      if (m.contains('overflowed')) {
        overflows.add(m.split('\n').first);
      } else {
        prevOnError?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prevOnError);
    await _capture(t, JobPostingScreen(to: _to(), workDetails: const [], slotDate: slots.first.date, reads: _jobReads(slots)),
        'S041-VIS_job_detail_second_button', scroll: "상하차 카드 선택 버튼이 고정 CTA 위 표시 영역 안에 오도록 실제 스크롤 → 탭 → 선택됨",
        beforeShot: () async {
      final p = await s041ShowButton(t, '상하차');
      final inside = p.button.top >= p.viewport.top && p.button.bottom <= p.viewport.bottom && p.button.bottom <= p.cta.top &&
          p.button.left >= p.viewport.left && p.button.right <= p.viewport.right;
      // ignore: avoid_print
      print('S041-VIS viewport=${p.viewport} button=${p.button} fixedCta=${p.cta} offset ${p.before.toStringAsFixed(1)}→${p.after.toStringAsFixed(1)} inside=$inside');
      expect(inside, isTrue, reason: '버튼 전체가 표시 영역 안·고정 CTA 위');
      await t.tapAt(p.button.center);
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.descendant(of: s041Card('상하차'), matching: find.text('선택됨')), findsOneWidget, reason: '상하차 선택됨');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
    });
  });

  testWidgets('S041-SEL2 11/6 피킹 + 11/8 상하차 선택 → 각 날짜 재방문 선택 유지 · 합계 2 · 지원 준비 시트 열기/닫기 후 보존', (t) async {
    final slots = [_slot('s1', 1), _slot('s2', 2, full: true), _slot('s3', 3)];
    await s041Pump(t, slots);
    final d1 = _kstMid(1).add(const Duration(hours: 9)); final d3 = _kstMid(3).add(const Duration(hours: 9));
    final c1 = '${d1.month}/${d1.day}'; final c3 = '${d3.month}/${d3.day}';
    Future<void> settle() async { for (var i = 0; i < 8; i++) { await t.pump(const Duration(milliseconds: 100)); } }
    Future<Map<String, String>> stateOf() async {
      final m = <String, String>{};
      for (final w in ['피킹', '상하차']) {
        await t.scrollUntilVisible(s041CardButton(w), 80, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
        await t.pump(const Duration(milliseconds: 50));
        m[w] = (t.widget<Text>(s041CardButton(w).first).data)!;
      }
      return m;
    }
    Future<void> goDate(String chip) async {
      // 날짜 칩은 맨 위 — scrollUntilVisible 은 화면 밖(−y)에 이미 지어진 칩을 '보임'으로 쳐서 탭이 빗나갔다(r3). 맨 위로 실제 이동 후 탭
      t.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.text(chip));
      await settle();
    }
    // 11/6 피킹 선택
    final s1 = await s041ShowButton(t, '피킹');
    await t.tapAt(s1.button.center);
    await settle();
    // 11/8 상하차 선택
    await goDate(c3);
    final s3 = await s041ShowButton(t, '상하차');
    await t.tapAt(s3.button.center);
    await settle();
    final at3 = await stateOf();
    await goDate(c1);
    final at1 = await stateOf();
    await goDate(c3);
    final at3b = await stateOf();
    // ignore: avoid_print
    print('S041-SEL2 $c1=$at1 $c3=$at3 → 재방문 $c3=$at3b');
    expect(at1, {'피킹': '선택됨', '상하차': '선택'}, reason: '$c1 피킹만 선택 유지');
    expect(at3, {'피킹': '선택', '상하차': '선택됨'});
    expect(at3b, at3, reason: '$c3 재방문 유지');
    final total = [...at1.values, ...at3b.values].where((v) => v == '선택됨').length;
    expect(total, 2, reason: '날짜별 선택 합계 2(화면 재방문 근거 — _newApplyTargets 는 날짜 키별 _flexSelected 를 같은 순회로 센다)');
    // 실제 다음 행동: 서류 준비 차단 fixture → 지원 준비 시트
    final cta = find.ancestor(of: findVisibleText('지원 준비하기'), matching: find.byType(ElevatedButton)).first;
    await t.tap(cta);
    await settle();
    expect(findVisibleText('지원 준비가 필요해요'), findsOneWidget, reason: '지원 준비 시트 열림'); // [DU279] 제목 낱말 묶기
    await t.tapAt(const Offset(195, 30));
    await settle();
    expect(findVisibleText('지원 준비가 필요해요'), findsNothing, reason: '시트 닫힘');
    final after = await stateOf();
    expect(after, at3b, reason: '시트 열고 닫은 뒤 선택 보존');
    await goDate(c1);
    expect(await stateOf(), at1);
    expect(t.takeException(), isNull);
    // ignore: avoid_print
    print('S041-SEL2 ok total=$total sheet open/close preserved');
  });

  // [DU1 후속111 S041 V2/V11] 스크롤 뒤 공고 식별 맥락 표본 — 첫 화면 → 본문 실제 dragFrom → 둘째 업무(상하차) 구간 → 상하차 '선택' 실제 탭 → 말단.
  //   같은 fixture(_to/_jobReads, 다중 날짜 s1·s2(FULL)·s3, 업무 피킹·상하차, 서류 준비 차단)·USER workerTheme·_loadFonts 근사·DPR1·inset0.
  //   jumpTo / scrollUntilVisible 없이 dragFrom 만 쓴다. 매 프레임 공고 제목·사업장·날짜 칩·업무 카드·고정 CTA 의 rect 와
  //   본문 표시 영역 안 여부를 출력한다(관측). 단언은 도달·선택됨·overflow 0·예외 없음만. 지원 제출·writer 는 누르지 않는다.
  testWidgets('S041-SCR 390×844 — 스크롤 뒤 공고 식별 맥락: 첫 화면·둘째 업무 구간·선택 뒤·말단(실제 drag)', (t) async {
    final slots = [_slot('s1', 1), _slot('s2', 2, full: true), _slot('s3', 3)];
    final overflows = <String>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      final m = d.exceptionAsString();
      if (m.contains('overflowed')) {
        overflows.add(m.split('\n').first);
      } else {
        prevOnError?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prevOnError);
    final key = GlobalKey();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)), child: child!),
            home: JobPostingScreen(to: _to(), workDetails: const [], slotDate: slots.first.date, reads: _jobReads(slots))),
      ),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final sc = find.byType(Scrollable).first;
    final pos = t.state<ScrollableState>(sc).position;
    final vp = t.getRect(sc);
    final cta = find.ancestor(of: findVisibleText('지원 준비하기'), matching: find.byType(ElevatedButton)).first;
    final d1 = _kstMid(1).add(const Duration(hours: 9));
    final d2 = _kstMid(2).add(const Duration(hours: 9));
    final d3 = _kstMid(3).add(const Duration(hours: 9));
    final chips = ['${d1.month}/${d1.day}', '${d2.month}/${d2.day}', '${d3.month}/${d3.day}'];
    String where(Finder f) {
      if (f.evaluate().isEmpty) return '없음';
      final r = t.getRect(f.first);
      final ctaTop = t.getRect(cta).top;
      final inside = r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5 && r.bottom <= ctaTop + 0.5;
      final part = !inside && r.bottom > vp.top && r.top < ctaTop;
      return '${r.left.toStringAsFixed(0)},${r.top.toStringAsFixed(1)}~${r.bottom.toStringAsFixed(1)}${inside ? ' 보임' : (part ? ' 일부' : ' 밖')}';
    }
    final out = <String>[];
    void frame(String name) {
      out.add('[$name] off=${pos.pixels.toStringAsFixed(1)}/${pos.maxScrollExtent.toStringAsFixed(1)} vp=$vp CTA=${t.getRect(cta)}'
          ' · 제목 "주말 물류 단기 모집" ${where(find.text('주말 물류 단기 모집'))}'
          ' · 사업장 ${where(find.text('강남 물류센터 평택 2공장'))}'
          ' · 날짜칩 ${chips.map((c) => '$c ${where(find.text(c))}').join(' / ')}'
          ' · 피킹 ${where(find.text('피킹'))} · 상하차 ${where(find.text('상하차'))}'
          ' · 뒤로 ${where(find.byType(BackButton))}');
    }
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }
    Map<String, Object?> cond(String scene) => {
          'screen': 'JobPostingScreen(to: _to(), slotDate: s1, reads: _jobReads([s1, s2 FULL, s3])) — 사진 없음, USER',
          'theme': 'RoleTheme.workerTheme', 'viewport': '390x844', 'dpr': 1.0, 'textScaler': 1.0, 'inset': '0',
          'fonts': _fontsNote, 'clockUtc': _clock.toIso8601String(), 'baseDate': Platform.environment['DU1_VQ_DATE'] ?? 'now',
          'chips': chips.join(','), 'scene': scene, 'measure': out.last};
    frame('첫 화면');
    await vqCapture(t, key, 'S041-SCR_1_first', conditions: cond('첫 화면 offset 0'));
    // 둘째 업무(상하차) 카드의 선택 버튼 전체가 고정 CTA 위 표시 영역 안에 들어올 때까지 실제 drag
    final btnLabel = s041CardButton('상하차');
    bool btnInside() {
      if (btnLabel.evaluate().isEmpty) return false;
      final b = t.getRect(find.ancestor(of: btnLabel.first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first);
      return b.top >= vp.top && b.bottom <= t.getRect(cta).top - 8;
    }
    var k = 0;
    while (!btnInside() && k < 30) {
      await t.dragFrom(Offset(vp.center.dx, vp.center.dy + 120), const Offset(0, -120));
      await settle();
      k++;
    }
    expect(btnInside(), isTrue, reason: '상하차 선택 버튼이 실제 drag 로 CTA 위 표시 영역에 들어온다');
    frame('둘째 업무 구간 drag $k회');
    await vqCapture(t, key, 'S041-SCR_2_second_work', conditions: cond('실제 dragFrom -120 × $k'));
    final b = t.getRect(find.ancestor(of: btnLabel.first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first);
    await t.tapAt(b.center);
    await settle();
    expect(find.descendant(of: s041Card('상하차'), matching: find.text('선택됨')), findsOneWidget, reason: '상하차 선택됨(화면 상태만)');
    frame('상하차 선택 뒤');
    await vqCapture(t, key, 'S041-SCR_3_selected', conditions: cond('상하차 선택 실제 탭 뒤(같은 offset)'));
    var e = 0;
    while (pos.pixels < pos.maxScrollExtent - 0.5 && e < 30) {
      await t.dragFrom(Offset(vp.center.dx, vp.center.dy + 120), const Offset(0, -160));
      await settle();
      e++;
    }
    frame('말단 drag $e회');
    await vqCapture(t, key, 'S041-SCR_4_end', conditions: cond('말단까지 실제 dragFrom -160 × $e'));
    for (final l in out) {
      // ignore: avoid_print
      print('S041-SCR $l');
    }
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });

  // [DU1 후속112 S041 뒤로 hit] 사진 없는 분기의 뒤로 receiver 실측 — 같은 fixture(_to/_jobReads, s1·s2 FULL·s3, 피킹·상하차, 서류 준비 차단)를
  //   dummy route('S041-BACK 이전 화면') 위에 MaterialPageRoute 로 push 한 LOCAL 상태. USER workerTheme·_loadFonts 근사·390×844·DPR1·inset0.
  //   receiver = 뒤로 아이콘(Icons.arrow_back)의 가장 가까운 onTap 있는 GestureDetector. hit 판정 = 그 GestureDetector 의 Listener(RenderPointerListener)가
  //   hitTestOnBinding 경로에 있는가. 바깥 = AppBar leading 슬롯(NavigationToolbar LayoutId leading)·툴바(NavigationToolbar) rect 를 따로 잰다.
  //   점: receiver 상자 9점(중심·네 변 중점·네 안쪽 모서리, 모두 안쪽 1) + 중심 기준 48×48 상자 8점(변 중점·모서리, 안쪽 0.5).
  //   단계: 첫 화면(offset 0)·본문 실제 dragFrom(−120) 뒤 pinned. 각 점마다 **새 route 로 진입**해 실제 tapAt → 이전 route 복귀 여부(hitTest 와 따로 기록).
  //   MEASURE 는 관측(중심 복귀만 단언)·PNG 2장, ASSERT 는 receiver ≥48×48·17점 hit·17점 실제 복귀를 단언한다(현행 판별력 확인에도 쓴다).
  //   지원 제출·writer 는 누르지 않는다. 미복귀 점은 하네스가 navigator.pop 으로 되돌린다(제품 동작 아님, 로그에 '하네스 pop').
  Future<void> s041BackProbe(WidgetTester t, {required bool strict}) async {
    final tag = strict ? 'ASSERT' : 'MEASURE';
    final slots = [_slot('s1', 1), _slot('s2', 2, full: true), _slot('s3', 3)];
    final overflows = <String>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      final m = d.exceptionAsString();
      if (m.contains('overflowed')) {
        overflows.add(m.split('\n').first);
      } else {
        prevOnError?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prevOnError);
    final key = GlobalKey();
    final nav = GlobalKey<NavigatorState>();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
            navigatorKey: nav,
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)), child: child!),
            home: const Scaffold(body: Center(child: Text('S041-BACK 이전 화면')))),
      ),
    ));
    await t.pump();
    Future<void> settle(int n) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }
    final prev = find.text('S041-BACK 이전 화면');
    bool onDetail() => find.byType(JobPostingScreen).evaluate().isNotEmpty;
    Finder receiver() => find
        .ancestor(of: find.byIcon(Icons.arrow_back), matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onTap != null))
        .first;
    Future<void> open({required bool pinned}) async {
      nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => JobPostingScreen(to: _to(), workDetails: const [], slotDate: slots.first.date, reads: _jobReads(slots))));
      await settle(25);
      expect(onDetail(), isTrue, reason: '상세 진입');
      expect(prev, findsNothing, reason: '이전 화면은 가려진다(offstage)');
      if (pinned) {
        final vp = t.getRect(find.byType(Scrollable).first);
        await t.dragFrom(Offset(vp.center.dx, vp.center.dy + 120), const Offset(0, -120));
        await settle(12);
      }
    }
    List<(String, Offset)> boxPts(Rect r, double inset) => [
          ('중심', r.center),
          ('좌변', Offset(r.left + inset, r.center.dy)), ('우변', Offset(r.right - inset, r.center.dy)),
          ('상변', Offset(r.center.dx, r.top + inset)), ('하변', Offset(r.center.dx, r.bottom - inset)),
          ('좌상', Offset(r.left + inset, r.top + inset)), ('우상', Offset(r.right - inset, r.top + inset)),
          ('좌하', Offset(r.left + inset, r.bottom - inset)), ('우하', Offset(r.right - inset, r.bottom - inset)),
        ];
    String f(Offset o) => '(${o.dx.toStringAsFixed(1)},${o.dy.toStringAsFixed(1)})';
    String fr(Rect r) => '(${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)})~(${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)}) ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)}';
    final out = <String>[];
    // 실패 단언 전에 이미 잰 값이 로그에 남도록 줄마다 바로 출력한다
    void log(String l) {
      out.add(l);
      // ignore: avoid_print
      print('S041-BACK $l');
    }
    for (final pinned in [false, true]) {
      final stage = pinned ? 'pinned(drag −120)' : '첫 화면';
      await open(pinned: pinned);
      final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
      final rv = receiver();
      final rRect = t.getRect(rv);
      final ro = t.renderObject(find.descendant(of: rv, matching: find.byType(Listener)).first);
      final lead = t.getRect(find.ancestor(of: rv, matching: find.byWidgetPredicate((w) => w is LayoutId && '${w.id}'.endsWith('.leading'))).first);
      final bar = t.getRect(find.ancestor(of: rv, matching: find.byType(NavigationToolbar)).first);
      final icon = t.getRect(find.byIcon(Icons.arrow_back));
      final gd = t.widget<GestureDetector>(rv);
      final box48 = Rect.fromCenter(center: rRect.center, width: 48, height: 48);
      final pts = [
        for (final p in boxPts(rRect, 1)) ('receiver ${p.$1}', p.$2),
        for (final p in boxPts(box48, 0.5).skip(1)) ('48상자 ${p.$1}', p.$2),
      ];
      bool hits(Offset p) => t.hitTestOnBinding(p).path.any((e) => e.target == ro);
      final hitMap = {for (final p in pts) p.$1: hits(p.$2)};
      log('[$tag $stage] off=${pos.pixels.toStringAsFixed(1)} receiver=${fr(rRect)} behavior=${gd.behavior ?? 'null(deferToChild)'}'
          ' · leading=${fr(lead)} · toolbar=${fr(bar)} · icon=${fr(icon)} · box48=${fr(box48)}');
      if (!strict) {
        await vqCapture(t, key, pinned ? 'S041-BACK_2_pinned' : 'S041-BACK_1_first', conditions: {
          'screen': 'MaterialApp(home: dummy) → push JobPostingScreen(to: _to(), slotDate: s1, reads: _jobReads([s1, s2 FULL, s3])) — 사진 없음, USER',
          'theme': 'RoleTheme.workerTheme', 'viewport': '390x844', 'dpr': 1.0, 'textScaler': 1.0, 'inset': '0',
          'fonts': _fontsNote, 'baseDate(DU1_VQ_DATE)': Platform.environment['DU1_VQ_DATE'] ?? 'now',
          'clock': '주입 없음 — JobPostingReads.now 기본값·D 의 DateTime.now (기록용 _clock=${_clock.toIso8601String()} 은 이 case 에 주입하지 않는다)',
          'scene': stage, 'measure': out.last});
      }
      // 실측 hitTest 는 첫 진입 인스턴스에서 — 실제 탭은 점마다 새 route
      var first = true;
      for (final p in pts) {
        if (!first) await open(pinned: pinned);
        first = false;
        final r2 = t.getRect(receiver());
        expect(r2, rRect, reason: '같은 단계 새 진입의 receiver rect 가 같다');
        await t.tapAt(p.$2);
        await settle(10);
        final popped = !onDetail() && prev.evaluate().isNotEmpty;
        if (!popped) {
          nav.currentState!.pop();
          await settle(10);
        }
        expect(onDetail(), isFalse, reason: '다음 점 전 이전 화면으로 돌아와 있다');
        log('[$tag $stage] ${p.$1} ${f(p.$2)} hit=${hitMap[p.$1]! ? 'O' : 'X'} 실제탭복귀=${popped ? 'O' : 'X(하네스 pop)'}');
        if (p.$1 == 'receiver 중심') expect(popped, isTrue, reason: '$stage 중심 실제 탭 → 이전 화면');
        if (strict) {
          expect(hitMap[p.$1], isTrue, reason: '$stage ${p.$1} ${f(p.$2)} hit');
          expect(popped, isTrue, reason: '$stage ${p.$1} ${f(p.$2)} 실제 탭 복귀');
        }
      }
      if (strict) {
        expect(rRect.width >= 48 && rRect.height >= 48, isTrue, reason: '$stage receiver ${fr(rRect)} ≥ 48×48');
      }
    }
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('S041-BACK-MEASURE 390×844 — 사진 없는 분기 뒤로 receiver·leading·툴바 rect, 17점 hit·점마다 새 진입 실제 탭 복귀(관측)', (t) async {
    await s041BackProbe(t, strict: false);
  });

  testWidgets('S041-BACK-ASSERT 390×844 — 사진 없는 분기 뒤로 receiver ≥48×48·17점 hit·17점 실제 탭 복귀(첫 화면·pinned)', (t) async {
    await s041BackProbe(t, strict: true);
  });

  // [DU1 후속113 S041 사진 있는 분기 뒤로 hit] 같은 USER 상세 fixture(_to, s1·s2 FULL·s3, 피킹·상하차, 서류 준비 차단)에
  //   사업장 대표 사진 1장(mainImageUrl 만, imageUrls 없음 → hasMultiple false, expandedHeight 240)을 준 LOCAL 근사.
  //   URL 은 '.invalid'(RFC 2606) 주소다. 시험 바인딩의 HttpClient 는 응답 400 을 돌려주므로 네트워크 성공이 아니다 — 실제 로딩 상태(placeholder·오류)를 기록한다.
  //   dummy route('S041-PBACK 이전 화면') 위에 MaterialPageRoute 로 push. 390×844·DPR1·scaler1·inset0·USER workerTheme·_loadFonts 근사.
  //   receiver = 뒤로 아이콘의 가장 가까운 onTap GestureDetector 의 Listener. 배경 사진 receiver = CachedNetworkImage(runtimeType 이름으로 찾는다 — 이 파일은 그 패키지를 import 하지 않는다)의 가장 가까운 onTap GestureDetector 의 Listener.
  //   단계: 펼친 화면(offset 0) · 본문 실제 dragFrom(−120) 반복으로 AppBar 높이가 툴바(56)까지 접힌 상태(자동 단언). 점 17개는 구현112 와 같은 규칙.
  //   탭 결과는 세 갈래로 기록한다: 복귀(이전 화면) · 미리보기(사진 전체 화면 dialog) · 무반응. 하네스 정리 pop 은 결과 계산 뒤에 한다.
  //   MEASURE 는 관측(중심 복귀·접힘·진입만 단언)·PNG 2장, ASSERT 는 receiver ≥48×48·17점 hit·17점 복귀·미리보기 0, 그리고 펼친 사진 가운데 탭은 여전히 미리보기(보존)를 단언한다.
  Future<void> s041PhotoBackProbe(WidgetTester t, {required bool strict}) async {
    final tag = strict ? 'ASSERT' : 'MEASURE';
    const photoUrl = 'https://du1-s041.invalid/biz1-main.jpg';
    final slots = [_slot('s1', 1), _slot('s2', 2, full: true), _slot('s3', 3)];
    final base = _jobReads(slots);
    final reads = JobPostingReads(
        toOrFailure: base.toOrFailure,
        workDetails: base.workDetails,
        businessById: (id) async => BusinessModel(
            id: 'biz1', name: '강남 물류센터 평택 2공장', ownerId: 'a1', businessNumber: '000-00-00000', address: '경기도 평택시 포승읍 1',
            category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2025), mainImageUrl: photoUrl),
        slots: base.slots,
        myApplications: base.myApplications,
        workTypeCatalog: base.workTypeCatalog,
        applicationOnce: base.applicationOnce);
    final overflows = <String>[];
    // [r2] 이미지 캐시가 부르는 path_provider 를 응답하지 않게 둔다 — placeholder 고정·파일 I/O 와 HTTP 없음(시험 환경 근사, 실기기 로딩 아님)
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final pathCalls = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, (call) {
      pathCalls.add(call.method);
      return Future.any(<Future<Object?>>[]);
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null));
    final otherErrors = <String>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      final m = d.exceptionAsString();
      if (m.contains('overflowed')) {
        overflows.add(m.split('\n').first);
      } else {
        otherErrors.add(m.split('\n').first);
        prevOnError?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prevOnError);
    final key = GlobalKey();
    final nav = GlobalKey<NavigatorState>();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
            navigatorKey: nav,
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)), child: child!),
            home: const Scaffold(body: Center(child: Text('S041-PBACK 이전 화면')))),
      ),
    ));
    await t.pump();
    Future<void> settle(int n) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }
    final prev = find.text('S041-PBACK 이전 화면');
    final preview = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ImagePreviewDialog');
    bool onDetail() => find.byType(JobPostingScreen).evaluate().isNotEmpty;
    Finder receiver() => find
        .ancestor(of: find.byIcon(Icons.arrow_back), matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onTap != null))
        .first;
    Finder photoGd() => find
        .ancestor(of: find.byWidgetPredicate((w) => w.runtimeType.toString() == 'CachedNetworkImage'), matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onTap != null))
        .first;
    double barH() => t.getRect(find.byType(AppBar).first).height;
    Future<int> open({required bool collapsed}) async {
      nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => JobPostingScreen(to: _to(), workDetails: const [], slotDate: slots.first.date, reads: reads)));
      await settle(25);
      expect(onDetail(), isTrue, reason: '상세 진입');
      expect(prev, findsNothing, reason: '이전 화면은 가려진다(offstage)');
      expect(find.byType(FlexibleSpaceBar), findsOneWidget, reason: '사진 있는 분기(갤러리 앱바)');
      var drags = 0;
      if (collapsed) {
        final vp = t.getRect(find.byType(Scrollable).first);
        while (barH() > 56.5 && drags < 10) {
          await t.dragFrom(Offset(vp.center.dx, vp.center.dy + 120), const Offset(0, -120));
          await settle(12);
          drags++;
        }
        expect(barH(), lessThanOrEqualTo(56.5), reason: '실제 drag 로 AppBar 가 툴바 높이까지 접힌다');
      }
      return drags;
    }
    Future<String> cleanup() async {
      final notes = <String>[];
      var guard = 0;
      while (preview.evaluate().isNotEmpty && guard < 3) {
        nav.currentState!.pop();
        await settle(10);
        notes.add('미리보기 닫음');
        guard++;
      }
      if (onDetail()) {
        nav.currentState!.pop();
        await settle(10);
        notes.add('상세 닫음');
      }
      expect(onDetail(), isFalse, reason: '다음 점 전 이전 화면으로 돌아와 있다');
      return notes.isEmpty ? '' : ' (하네스 ${notes.join('·')})';
    }
    String outcome() => (!onDetail() && prev.evaluate().isNotEmpty)
        ? '복귀'
        : preview.evaluate().isNotEmpty
            ? '미리보기'
            : '무반응';
    List<(String, Offset)> boxPts(Rect r, double inset) => [
          ('중심', r.center),
          ('좌변', Offset(r.left + inset, r.center.dy)), ('우변', Offset(r.right - inset, r.center.dy)),
          ('상변', Offset(r.center.dx, r.top + inset)), ('하변', Offset(r.center.dx, r.bottom - inset)),
          ('좌상', Offset(r.left + inset, r.top + inset)), ('우상', Offset(r.right - inset, r.top + inset)),
          ('좌하', Offset(r.left + inset, r.bottom - inset)), ('우하', Offset(r.right - inset, r.bottom - inset)),
        ];
    String f(Offset o) => '(${o.dx.toStringAsFixed(1)},${o.dy.toStringAsFixed(1)})';
    String fr(Rect r) => '(${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)})~(${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)}) ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)}';
    final out = <String>[];
    void log(String l) {
      out.add(l);
      // ignore: avoid_print
      print('S041-PBACK $l');
    }
    for (final collapsed in [false, true]) {
      final stage = collapsed ? '접힘(실제 drag)' : '펼침';
      final drags = await open(collapsed: collapsed);
      final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
      final rv = receiver();
      final rRect = t.getRect(rv);
      final ro = t.renderObject(find.descendant(of: rv, matching: find.byType(Listener)).first);
      final pg = photoGd();
      final pro = t.renderObject(find.descendant(of: pg, matching: find.byType(Listener)).first);
      final lead = t.getRect(find.ancestor(of: rv, matching: find.byWidgetPredicate((w) => w is LayoutId && '${w.id}'.endsWith('.leading'))).first);
      final bar = t.getRect(find.ancestor(of: rv, matching: find.byType(NavigationToolbar)).first);
      final icon = t.getRect(find.byIcon(Icons.arrow_back));
      final gd = t.widget<GestureDetector>(rv);
      final imgState = 'CachedNetworkImage ${find.byWidgetPredicate((w) => w.runtimeType.toString() == 'CachedNetworkImage').evaluate().length}'
          ' · broken_image ${find.byIcon(Icons.broken_image).evaluate().length}'
          ' · Shimmer ${find.byWidgetPredicate((w) => w.runtimeType.toString() == 'Shimmer').evaluate().length}';
      final box48 = Rect.fromCenter(center: rRect.center, width: 48, height: 48);
      final pts = [
        for (final p in boxPts(rRect, 1)) ('receiver ${p.$1}', p.$2),
        for (final p in boxPts(box48, 0.5).skip(1)) ('48상자 ${p.$1}', p.$2),
      ];
      final hitMap = <String, String>{
        for (final p in pts)
          p.$1: () {
            final path = t.hitTestOnBinding(p.$2).path;
            final b = path.any((e) => e.target == ro);
            final ph = path.any((e) => e.target == pro);
            return '${b ? 'O' : 'X'}${ph ? '·배경사진hit' : ''}';
          }()
      };
      log('[$tag $stage] off=${pos.pixels.toStringAsFixed(1)} drag=$drags AppBar높이=${barH().toStringAsFixed(1)} receiver=${fr(rRect)}'
          ' behavior=${gd.behavior ?? 'null(deferToChild)'} · leading=${fr(lead)} · toolbar=${fr(bar)} · icon=${fr(icon)} · box48=${fr(box48)} · 이미지 $imgState');
      if (!strict) {
        await vqCapture(t, key, collapsed ? 'S041-PBACK_2_collapsed' : 'S041-PBACK_1_expanded', conditions: {
          'screen': 'MaterialApp(home: dummy) → push JobPostingScreen(to: _to(), slotDate: s1, reads: 사진 1장 businessById + _jobReads([s1, s2 FULL, s3]) 나머지) — USER',
          'photo': '$photoUrl (mainImageUrl 만 · imageUrls 없음 · 네트워크 성공 아님)',
          'imageState': imgState,
          'theme': 'RoleTheme.workerTheme', 'viewport': '390x844', 'dpr': 1.0, 'textScaler': 1.0, 'inset': '0',
          'fonts': _fontsNote, 'baseDate(DU1_VQ_DATE)': Platform.environment['DU1_VQ_DATE'] ?? 'now',
          'clock': '주입 없음 — JobPostingReads.now 기본값·D 의 DateTime.now (기록용 _clock=${_clock.toIso8601String()} 은 주입하지 않는다)',
          'scene': stage, 'measure': out.last});
      }
      var first = true;
      for (final p in pts) {
        if (!first) await open(collapsed: collapsed);
        first = false;
        expect(t.getRect(receiver()), rRect, reason: '같은 단계 새 진입의 receiver rect 가 같다');
        await t.tapAt(p.$2);
        await settle(10);
        final o = outcome();
        final note = await cleanup();
        log('[$tag $stage] ${p.$1} ${f(p.$2)} hit=${hitMap[p.$1]} 실제탭=$o$note');
        if (p.$1 == 'receiver 중심') expect(o, '복귀', reason: '$stage 중심 실제 탭 → 이전 화면');
        if (strict) {
          expect(hitMap[p.$1], 'O', reason: '$stage ${p.$1} ${f(p.$2)} 뒤로 receiver 만 hit');
          expect(o, '복귀', reason: '$stage ${p.$1} ${f(p.$2)} 실제 탭 복귀');
        }
      }
      // 관측 점: 툴바 가운데(뒤로·배지 밖) — 배경 사진이 툴바 아래에서 탭을 받는지(기존 동작 관측, 이번 보완 대상 아님)
      await open(collapsed: collapsed);
      const mid = Offset(195, 28);
      final midHit = t.hitTestOnBinding(mid).path.any((e) => e.target == t.renderObject(find.descendant(of: photoGd(), matching: find.byType(Listener)).first));
      await t.tapAt(mid);
      await settle(10);
      final midO = outcome();
      log('[$tag $stage] 관측 툴바가운데 ${f(mid)} 배경사진hit=${midHit ? 'O' : 'X'} 실제탭=$midO${await cleanup()}');
      if (!collapsed) {
        // 보존: 펼친 사진 가운데 탭 → 사진 미리보기(기존 갤러리 동작)
        await open(collapsed: false);
        final pr = t.getRect(photoGd());
        final c = Offset(pr.center.dx, (pr.top + 56 + pr.bottom) / 2);
        await t.tapAt(c);
        await settle(10);
        final co = outcome();
        log('[$tag $stage] 보존 사진가운데 ${f(c)} 사진rect=${fr(pr)} 실제탭=$co${await cleanup()}');
        if (strict) expect(co, '미리보기', reason: '펼친 사진 가운데 탭은 사진 미리보기를 연다(보존)');
      }
      if (strict) {
        expect(rRect.width >= 48 && rRect.height >= 48, isTrue, reason: '$stage receiver ${fr(rRect)} ≥ 48×48');
      }
    }
    log('[$tag] path_provider 호출 ${pathCalls.length}(${pathCalls.toSet().join(',')}, 응답 없음) · overflow ${overflows.length} · 기타 FlutterError ${otherErrors.length}${otherErrors.isEmpty ? '' : ': ${otherErrors.toSet().join(' | ')}'}');
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('S041-PBACK-MEASURE 390×844 — 사진 있는 분기 뒤로 receiver·배경 사진 hit, 펼침·접힘 17점 실제 탭 결과(관측)', (t) async {
    await s041PhotoBackProbe(t, strict: false);
  });

  testWidgets('S041-PBACK-ASSERT 390×844 — 사진 있는 분기 뒤로 receiver ≥48×48·17점 hit·17점 복귀·미리보기 0, 사진 가운데 미리보기 보존', (t) async {
    await s041PhotoBackProbe(t, strict: true);
  });

  // [DU1 후속114 S041 접힌 사진 숨은 탭] S041-PBACK 과 같은 LOCAL 근사(USER 상세 + 대표 사진 1장 '.invalid' · Shimmer placeholder ·
  //   path_provider 응답 대기 mock 은 이 probe 안에서만, tearDown 해제) · dummy route push · 390×844·DPR1·scaler1·inset0.
  //   단계: 펼침(offset 0) · 중간(실제 dragFrom −120 한 번, 관측) · 완전 접힘(실제 drag 반복, AppBar ≤56.5 자동 단언).
  //   매 단계 FlexibleSpaceBarSettings(current/min/maxExtent)·배경 사진 GestureDetector rect·그 위 RenderOpacity.opacity 를 **직접** 읽는다(앞 차수는 SDK 도출값).
  //   툴바 대표 4점(뒤로 56 슬롯 밖 왼쪽 80 · 가운데 195 · 오른쪽 370 · 가운데 아래쪽 y54 — USER 모드라 actions 없음)과
  //   펼친 사진 가운데 (195,148)의 결과를 사진 Listener hit · 실제 탭 결과(복귀/미리보기/무반응) · route 상태(상세 남음·이전 화면 가림)로 나눠 기록한다.
  //   MEASURE 는 관측(진입·접힘만 단언)·PNG 3장. ASSERT 는 접힘 4점 사진 hit 없음·미리보기 없음·상세 남음, 펼친 사진 가운데 미리보기(보존)를 단언한다.
  //   점마다 새 상세 진입. 하네스 정리 pop 은 결과 계산 뒤. 지원 제출·writer 는 누르지 않는다.
  Future<void> s041HiddenPhotoTapProbe(WidgetTester t, {required bool strict}) async {
    final tag = strict ? 'ASSERT' : 'MEASURE';
    const photoUrl = 'https://du1-s041.invalid/biz1-main.jpg';
    final slots = [_slot('s1', 1), _slot('s2', 2, full: true), _slot('s3', 3)];
    final base = _jobReads(slots);
    final reads = JobPostingReads(
        toOrFailure: base.toOrFailure,
        workDetails: base.workDetails,
        businessById: (id) async => BusinessModel(
            id: 'biz1', name: '강남 물류센터 평택 2공장', ownerId: 'a1', businessNumber: '000-00-00000', address: '경기도 평택시 포승읍 1',
            category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2025), mainImageUrl: photoUrl),
        slots: base.slots,
        myApplications: base.myApplications,
        workTypeCatalog: base.workTypeCatalog,
        applicationOnce: base.applicationOnce);
    final overflows = <String>[];
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final pathCalls = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, (call) {
      pathCalls.add(call.method);
      return Future.any(<Future<Object?>>[]);
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null));
    final otherErrors = <String>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      final m = d.exceptionAsString();
      if (m.contains('overflowed')) {
        overflows.add(m.split('\n').first);
      } else {
        otherErrors.add(m.split('\n').first);
        prevOnError?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prevOnError);
    final key = GlobalKey();
    final nav = GlobalKey<NavigatorState>();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
            navigatorKey: nav,
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)), child: child!),
            home: const Scaffold(body: Center(child: Text('S041-HPT 이전 화면')))),
      ),
    ));
    await t.pump();
    Future<void> settle(int n) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }
    final prev = find.text('S041-HPT 이전 화면');
    final preview = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ImagePreviewDialog');
    bool onDetail() => find.byType(JobPostingScreen).evaluate().isNotEmpty;
    Finder photoGd() => find
        .ancestor(
            of: find.byWidgetPredicate((w) => w.runtimeType.toString() == 'CachedNetworkImage'),
            matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onTap != null))
        .first;
    double barH() => t.getRect(find.byType(AppBar).first).height;
    // stage: 0 펼침 · 1 중간(drag 1회) · 2 완전 접힘
    Future<int> open(int stage) async {
      nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => JobPostingScreen(to: _to(), workDetails: const [], slotDate: slots.first.date, reads: reads)));
      await settle(25);
      expect(onDetail(), isTrue, reason: '상세 진입');
      expect(prev, findsNothing, reason: '이전 화면은 가려진다(offstage)');
      expect(find.byType(FlexibleSpaceBar), findsOneWidget, reason: '사진 있는 분기(갤러리 앱바)');
      var drags = 0;
      if (stage > 0) {
        final vp = t.getRect(find.byType(Scrollable).first);
        while ((stage == 1 ? drags < 1 : barH() > 56.5) && drags < 10) {
          await t.dragFrom(Offset(vp.center.dx, vp.center.dy + 120), const Offset(0, -120));
          await settle(12);
          drags++;
        }
        if (stage == 2) expect(barH(), lessThanOrEqualTo(56.5), reason: '실제 drag 로 AppBar 가 툴바 높이까지 접힌다');
      }
      return drags;
    }
    Future<String> cleanup() async {
      final notes = <String>[];
      var guard = 0;
      while (preview.evaluate().isNotEmpty && guard < 3) {
        nav.currentState!.pop();
        await settle(10);
        notes.add('미리보기 닫음');
        guard++;
      }
      if (onDetail()) {
        nav.currentState!.pop();
        await settle(10);
        notes.add('상세 닫음');
      }
      expect(onDetail(), isFalse, reason: '다음 점 전 이전 화면으로 돌아와 있다');
      return notes.isEmpty ? '' : ' (하네스 ${notes.join('·')})';
    }
    String outcome() => (!onDetail() && prev.evaluate().isNotEmpty)
        ? '복귀'
        : preview.evaluate().isNotEmpty
            ? '미리보기'
            : '무반응';
    String route() => '상세${onDetail() ? '남음' : '없음'}·이전화면${prev.evaluate().isNotEmpty ? '보임' : '가림'}';
    String f(Offset o) => '(${o.dx.toStringAsFixed(1)},${o.dy.toStringAsFixed(1)})';
    String fr(Rect r) => '(${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)})~(${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)}) ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)}';
    final out = <String>[];
    void log(String l) {
      out.add(l);
      // ignore: avoid_print
      print('S041-HPT $l');
    }
    String measure() {
      final s = t.widget<FlexibleSpaceBarSettings>(find.byType(FlexibleSpaceBarSettings).first);
      final pr = t.getRect(photoGd());
      RenderObject? o = t.renderObject(photoGd());
      double? opacity;
      while (o != null) {
        if (o is RenderOpacity) {
          opacity = o.opacity;
          break;
        }
        o = o.parent;
      }
      final ign = find.ancestor(of: photoGd(), matching: find.byType(IgnorePointer)).evaluate().map((e) => (e.widget as IgnorePointer).ignoring).toList();
      return 'settings current=${s.currentExtent.toStringAsFixed(1)} min=${s.minExtent.toStringAsFixed(1)} max=${s.maxExtent.toStringAsFixed(1)}'
          ' · AppBar=${barH().toStringAsFixed(1)} · 사진GD=${fr(pr)} · RenderOpacity=${opacity?.toStringAsFixed(3) ?? '없음'}'
          ' · 사진 조상 IgnorePointer ignoring=$ign';
    }
    const toolbarPts = [('툴바왼쪽', Offset(80, 28)), ('툴바가운데', Offset(195, 28)), ('툴바오른쪽', Offset(370, 28)), ('툴바가운데아래', Offset(195, 54))];
    for (final stage in [0, 1, 2]) {
      final name = ['펼침', '중간(drag 1회)', '완전 접힘(실제 drag)'][stage];
      final drags = await open(stage);
      final off = t.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
      final pro = t.renderObject(find.descendant(of: photoGd(), matching: find.byType(Listener)).first);
      final pts = [...toolbarPts, if (stage == 0) ('사진가운데', const Offset(195, 148))];
      final hitMap = {for (final p in pts) p.$1: t.hitTestOnBinding(p.$2).path.any((e) => e.target == pro)};
      log('[$tag $name] off=${off.toStringAsFixed(1)} drag=$drags · ${measure()}'
          ' · 이미지 CachedNetworkImage ${find.byWidgetPredicate((w) => w.runtimeType.toString() == 'CachedNetworkImage').evaluate().length}'
          ' · Shimmer ${find.byWidgetPredicate((w) => w.runtimeType.toString() == 'Shimmer').evaluate().length}');
      if (!strict) {
        await vqCapture(t, key, ['S041-HPT_1_expanded', 'S041-HPT_2_mid', 'S041-HPT_3_collapsed'][stage], conditions: {
          'screen': 'MaterialApp(home: dummy) → push JobPostingScreen(to: _to(), slotDate: s1, reads: 사진 1장 businessById + _jobReads([s1, s2 FULL, s3]) 나머지) — USER',
          'photo': '$photoUrl (mainImageUrl 만 · imageUrls 없음 · 네트워크 성공 아님 · path_provider 응답 대기 mock)',
          'theme': 'RoleTheme.workerTheme', 'viewport': '390x844', 'dpr': 1.0, 'textScaler': 1.0, 'inset': '0',
          'fonts': _fontsNote, 'baseDate(DU1_VQ_DATE)': Platform.environment['DU1_VQ_DATE'] ?? 'now',
          'clock': '주입 없음 — JobPostingReads.now 기본값·D 의 DateTime.now (기록용 _clock=${_clock.toIso8601String()} 은 주입하지 않는다)',
          'scene': name, 'measure': out.last});
      }
      var first = true;
      for (final p in pts) {
        if (!first) await open(stage);
        first = false;
        await t.tapAt(p.$2);
        await settle(10);
        final o = outcome();
        final r = route();
        final note = await cleanup();
        log('[$tag $name] ${p.$1} ${f(p.$2)} 사진hit=${hitMap[p.$1]! ? 'O' : 'X'} 실제탭=$o · $r$note');
        if (strict && stage == 2) {
          expect(hitMap[p.$1], isFalse, reason: '$name ${p.$1} ${f(p.$2)} 보이지 않는 사진은 hit 를 받지 않는다');
          expect(o, '무반응', reason: '$name ${p.$1} ${f(p.$2)} 미리보기 없음·상세 남음');
          expect(r, '상세남음·이전화면가림', reason: '$name ${p.$1} route 상태');
        }
        if (strict && p.$1 == '사진가운데') {
          expect(hitMap[p.$1], isTrue, reason: '펼친 사진 가운데는 사진이 hit 를 받는다(보존)');
          expect(o, '미리보기', reason: '펼친 사진 가운데 탭은 사진 미리보기를 연다(보존)');
        }
      }
    }
    log('[$tag] path_provider 호출 ${pathCalls.length}(${pathCalls.toSet().join(',')}, 응답 없음) · overflow ${overflows.length} · 기타 FlutterError ${otherErrors.length}');
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('S041-HPT-MEASURE 390×844 — 사진 갤러리 펼침·중간·완전 접힘의 배경 위치·불투명도·툴바 4점 사진 hit/탭 결과(관측)', (t) async {
    await s041HiddenPhotoTapProbe(t, strict: false);
  });

  testWidgets('S041-HPT-ASSERT 390×844 — 완전 접힘 툴바 4점 사진 hit 없음·미리보기 없음·상세 남음, 펼친 사진 가운데 미리보기 보존', (t) async {
    await s041HiddenPhotoTapProbe(t, strict: true);
  });

  // [DU1 후속116 S041 뒤로 의미 label] 사진 없는/있는 두 custom 뒤로의 semantics 를 실제 tree 에서 관측·단언한다.
  //   MaterialApp 은 앱(main.dart:209~217)과 같은 locale 구성 — locale ko_KR · GlobalMaterial/Widgets/Cupertino delegates · supportedLocales ko_KR/en_US.
  //   단계: 사진 없음(_jobReads) · 사진 1장 펼침 · 사진 1장 실제 drag 완전 접힘(AppBar ≤56.5). 사진 단계는 PBACK/HPT 와 같은 LOCAL 근사
  //   ('.invalid' · Shimmer · path_provider 응답 대기 mock — 이 probe 안, tearDown 해제). dummy route 위 push · 390×844·DPR1·scaler1·inset0.
  //   관측: 뒤로 receiver(가장 가까운 onTap GestureDetector)의 semantics node — label·tooltip·isButton·tap action·전역 rect,
  //   tree 전체에서 같은 label 노드 수 · 뒤로 중심을 덮는 tap 노드 목록 · 화살표 글리프 문자 노드 유무.
  //   행동: ① semantics tap action(node.owner.performAction) → 결과 ② 새 진입 뒤 실제 touch tapAt(receiver 중심) → 결과. 둘을 구별해 기록하고 cleanup 전에 계산한다.
  //   MEASURE 는 관측(진입·접힘만 단언)·PNG 3장, ASSERT 는 label = MaterialLocalizations.backButtonTooltip('뒤로')·isButton·tap·같은 label 1개·
  //   글리프 미노출·semantics tap 복귀·touch 복귀를 단언한다. 지원 제출·writer 는 누르지 않는다.
  Future<void> s041BackSemanticsProbe(WidgetTester t, {required bool strict}) async {
    final tag = strict ? 'ASSERT' : 'MEASURE';
    final sem = t.ensureSemantics();
    try {
      const photoUrl = 'https://du1-s041.invalid/biz1-main.jpg';
      final slots = [_slot('s1', 1), _slot('s2', 2, full: true), _slot('s3', 3)];
      final base = _jobReads(slots);
      final photoReads = JobPostingReads(
          toOrFailure: base.toOrFailure,
          workDetails: base.workDetails,
          businessById: (id) async => BusinessModel(
              id: 'biz1', name: '강남 물류센터 평택 2공장', ownerId: 'a1', businessNumber: '000-00-00000', address: '경기도 평택시 포승읍 1',
              category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2025), mainImageUrl: photoUrl),
          slots: base.slots,
          myApplications: base.myApplications,
          workTypeCatalog: base.workTypeCatalog,
          applicationOnce: base.applicationOnce);
      final overflows = <String>[];
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      final pathCalls = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, (call) {
        pathCalls.add(call.method);
        return Future.any(<Future<Object?>>[]);
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null));
      final otherErrors = <String>[];
      final prevOnError = FlutterError.onError;
      FlutterError.onError = (d) {
        final m = d.exceptionAsString();
        if (m.contains('overflowed')) {
          overflows.add(m.split('\n').first);
        } else {
          otherErrors.add(m.split('\n').first);
          prevOnError?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = prevOnError);
      final key = GlobalKey();
      final nav = GlobalKey<NavigatorState>();
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
        ],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
              navigatorKey: nav,
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.workerTheme,
              locale: const Locale('ko', 'KR'),
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)), child: child!),
              home: const Scaffold(body: Center(child: Text('S041-BSEM 이전 화면')))),
        ),
      ));
      await t.pump();
      Future<void> settle(int n) async {
        for (var i = 0; i < n; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }
      final prev = find.text('S041-BSEM 이전 화면');
      final preview = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ImagePreviewDialog');
      bool onDetail() => find.byType(JobPostingScreen).evaluate().isNotEmpty;
      Finder receiver() => find
          .ancestor(of: find.byIcon(Icons.arrow_back), matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onTap != null))
          .first;
      double barH() => t.getRect(find.byType(AppBar).first).height;
      Future<void> open(JobPostingReads reads, {required bool collapse}) async {
        nav.currentState!.push(MaterialPageRoute<void>(
            builder: (_) => JobPostingScreen(to: _to(), workDetails: const [], slotDate: slots.first.date, reads: reads)));
        await settle(25);
        expect(onDetail(), isTrue, reason: '상세 진입');
        expect(prev, findsNothing, reason: '이전 화면은 가려진다(offstage)');
        if (collapse) {
          final vp = t.getRect(find.byType(Scrollable).first);
          var drags = 0;
          while (barH() > 56.5 && drags < 10) {
            await t.dragFrom(Offset(vp.center.dx, vp.center.dy + 120), const Offset(0, -120));
            await settle(12);
            drags++;
          }
          expect(barH(), lessThanOrEqualTo(56.5), reason: '실제 drag 로 AppBar 가 툴바 높이까지 접힌다');
        }
      }
      Future<String> cleanup() async {
        final notes = <String>[];
        var guard = 0;
        while (preview.evaluate().isNotEmpty && guard < 3) {
          nav.currentState!.pop();
          await settle(10);
          notes.add('미리보기 닫음');
          guard++;
        }
        if (onDetail()) {
          nav.currentState!.pop();
          await settle(10);
          notes.add('상세 닫음');
        }
        expect(onDetail(), isFalse, reason: '다음 단계 전 이전 화면으로 돌아와 있다');
        return notes.isEmpty ? '' : ' (하네스 ${notes.join('·')})';
      }
      String outcome() => (!onDetail() && prev.evaluate().isNotEmpty)
          ? '복귀'
          : preview.evaluate().isNotEmpty
              ? '미리보기'
              : '무반응';
      Rect globalRect(SemanticsNode n) {
        var r = n.rect;
        SemanticsNode? c = n;
        while (c != null) {
          if (c.transform != null) r = MatrixUtils.transformRect(c.transform!, r);
          c = c.parent;
        }
        return r;
      }
      String fr(Rect r) => '(${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)})~(${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)})';
      final glyph = String.fromCharCode(Icons.arrow_back.codePoint);
      final out = <String>[];
      void log(String l) {
        out.add(l);
        // ignore: avoid_print
        print('S041-BSEM $l');
      }
      final stages = [('사진 없음', base, false), ('사진 펼침', photoReads, false), ('사진 완전 접힘(실제 drag)', photoReads, true)];
      for (var i = 0; i < stages.length; i++) {
        final (name, reads, collapse) = stages[i];
        await open(reads, collapse: collapse);
        final backLabel = MaterialLocalizations.of(t.element(find.byType(JobPostingScreen))).backButtonTooltip;
        final rv = receiver();
        final rvRect = t.getRect(rv);
        final node = t.getSemantics(rv);
        final data = node.getSemanticsData();
        var root = node;
        while (root.parent != null) {
          root = root.parent!;
        }
        final all = <SemanticsNode>[];
        void visit(SemanticsNode n) {
          all.add(n);
          n.visitChildren((c) {
            visit(c);
            return true;
          });
        }
        visit(root);
        final sameLabel = all.where((n) => n.label == backLabel).toList();
        final tapOver = all.where((n) => n.getSemanticsData().hasAction(SemanticsAction.tap) && globalRect(n).contains(rvRect.center)).toList();
        final glyphNodes = all.where((n) => n.label.contains(glyph) || n.value.contains(glyph)).length;
        log('[$tag $name] locale backButtonTooltip="$backLabel" · receiver=${fr(rvRect)} · node#${node.id} label="${node.label}" tooltip="${node.tooltip}"'
            ' isButton=${node.flagsCollection.isButton} tap=${data.hasAction(SemanticsAction.tap)} rect=${fr(globalRect(node))}'
            ' · 같은 label 노드 ${sameLabel.length}(${sameLabel.map((n) => '#${n.id}').join(',')})'
            ' · 뒤로 중심을 덮는 tap 노드 ${tapOver.length}(${tapOver.map((n) => '#${n.id}"${n.label}" ${fr(globalRect(n))}').join(' | ')})'
            ' · 글리프 노출 노드 $glyphNodes · 노드 수 ${all.length}');
        if (!strict) {
          await vqCapture(t, key, ['S041-BSEM_1_nophoto', 'S041-BSEM_2_photo_expanded', 'S041-BSEM_3_photo_collapsed'][i], conditions: {
            'screen': 'MaterialApp(locale ko_KR · Global delegates, home: dummy) → push JobPostingScreen(to: _to(), slotDate: s1, reads: ${i == 0 ? '_jobReads([s1, s2 FULL, s3])' : '사진 1장 businessById + _jobReads 나머지'}) — USER',
            'photo': i == 0 ? '없음' : '$photoUrl (mainImageUrl 만 · 네트워크 성공 아님 · path_provider 응답 대기 mock)',
            'theme': 'RoleTheme.workerTheme', 'viewport': '390x844', 'dpr': 1.0, 'textScaler': 1.0, 'inset': '0', 'semantics': 'ensureSemantics 켬',
            'fonts': _fontsNote, 'baseDate(DU1_VQ_DATE)': Platform.environment['DU1_VQ_DATE'] ?? 'now',
            'clock': '주입 없음 — JobPostingReads.now 기본값·D 의 DateTime.now (기록용 _clock=${_clock.toIso8601String()} 은 주입하지 않는다)',
            'scene': name, 'measure': out.last});
        }
        // ① semantics tap action
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await settle(10);
        final so = outcome();
        log('[$tag $name] semantics tap(node#${node.id}) → $so${await cleanup()}');
        // ② 새 진입 뒤 실제 touch
        await open(reads, collapse: collapse);
        final c = t.getRect(receiver()).center;
        await t.tapAt(c);
        await settle(10);
        final to = outcome();
        log('[$tag $name] touch tapAt(${c.dx.toStringAsFixed(1)},${c.dy.toStringAsFixed(1)}) → $to${await cleanup()}');
        if (strict) {
          expect(backLabel, '뒤로', reason: '앱과 같은 ko_KR locale 의 MaterialLocalizations.backButtonTooltip');
          expect(node.label, backLabel, reason: '$name 뒤로 semantics label');
          expect(node.flagsCollection.isButton, isTrue, reason: '$name 뒤로 button role');
          expect(data.hasAction(SemanticsAction.tap), isTrue, reason: '$name 뒤로 tap action');
          expect(sameLabel.length, 1, reason: '$name 같은 label 노드는 하나(중복 없음)');
          expect(sameLabel.single.id, node.id, reason: '$name 그 label 노드가 뒤로 receiver 의 노드다');
          expect(glyphNodes, 0, reason: '$name 화살표 글리프 문자가 semantics 로 노출되지 않는다');
          expect(so, '복귀', reason: '$name semantics tap → 이전 화면');
          expect(to, '복귀', reason: '$name 실제 touch → 이전 화면');
        }
      }
      log('[$tag] path_provider 호출 ${pathCalls.length}(${pathCalls.toSet().join(',')}, 응답 없음) · overflow ${overflows.length} · 기타 FlutterError ${otherErrors.length}');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    } finally {
      sem.dispose();
    }
  }

  testWidgets('S041-BSEM-MEASURE 390×844 — 사진 없음·사진 펼침·완전 접힘 뒤로 semantics(label·role·action·중복)·semantics/touch 복귀(관측)', (t) async {
    await s041BackSemanticsProbe(t, strict: false);
  });

  testWidgets('S041-BSEM-ASSERT 390×844 — 세 단계 뒤로 label "뒤로"·button·tap·중복 없음·글리프 미노출·semantics/touch 복귀', (t) async {
    await s041BackSemanticsProbe(t, strict: true);
  });

  // [DU1 후속117 S041 한국어 시각 하네스] 다음 S041 V8(밀도) before/after 용 하네스 — 구현111 S041-SCR 과 같은 fixture·장면·실제 drag 를
  //   locale 조건만 바꿔 두 벌로 그린다. en(기본): MaterialApp 에 locale/delegates 를 주지 않는다(= S041-SCR 과 같은 위젯 트리, 옛 하네스 연결용).
  //   ko: locale ko_KR + GlobalMaterial/Widgets/Cupertino delegates + supportedLocales [ko_KR, en_US](앱 main.dart:209~217 의 delegates·지원 목록 + LOCAL ko_KR 명시).
  //   두 벌 모두 testWidgets 기본 semanticsEnabled=true 다(구현116 BSEM 과 이 상태는 같음 — 구현118 주석 정정). 사진 없음 · 390×844·DPR1·scaler1·inset0 · USER workerTheme · _loadFonts 근사.
  //   장면: 첫 화면 → 본문 실제 dragFrom −120(상하차 선택 버튼이 CTA 위로 들 때까지) → 상하차 '선택' 실제 탭 → 말단(dragFrom −160 반복).
  //   기록: requested locale · Localizations.localeOf(context)(resolved) · MaterialLocalizations 종류·scriptCategory · semanticsEnabled,
  //   그리고 첫 화면·둘째 업무·말단 세 장면의 화면 안 RenderParagraph 전부의 글(낱말 결합 문자 제거)·max intrinsic 폭·배치 크기·didExceedMaxLines(TextPainter 수준 폭 비교용).
  //   단언은 도달·선택됨·overflow 0·예외 없음만(하네스 기초). 지원 제출·writer 는 누르지 않는다.
  Future<void> s041LocaleProbe(WidgetTester t,
      {required bool ko, Size size = const Size(390, 844), double scale = 1.0, String? tag}) async {
    // [DU1 구현119] size·scale·tag 는 선택 인자 — 기본값이면 구현117 LOC-en/ko 와 같은 조건이다(작은 폭 한국어 관측 S041-LOCS-ko 용)
    tag ??= ko ? 'ko' : 'en';
    final slots = [_slot('s1', 1), _slot('s2', 2, full: true), _slot('s3', 3)];
    final overflows = <String>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      final m = d.exceptionAsString();
      if (m.contains('overflowed')) {
        overflows.add(m.split('\n').first);
      } else {
        prevOnError?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prevOnError);
    final key = GlobalKey();
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final home = JobPostingScreen(to: _to(), workDetails: const [], slotDate: slots.first.date, reads: _jobReads(slots));
    Widget scaler(BuildContext ctx, Widget? child) =>
        MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: ko
            ? MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.workerTheme,
                locale: const Locale('ko', 'KR'),
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
                builder: scaler,
                home: home)
            : MaterialApp(debugShowCheckedModeBanner: false, theme: RoleTheme.workerTheme, builder: scaler, home: home),
      ),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final ctx = t.element(find.byType(JobPostingScreen));
    final ml = MaterialLocalizations.of(ctx);
    final cond = 'requested=${ko ? 'ko_KR' : '없음(기본)'} · resolved=${Localizations.localeOf(ctx)} · MaterialLocalizations=${ml.runtimeType}'
        ' · scriptCategory=${ml.scriptCategory} · semanticsEnabled=${t.binding.semanticsEnabled}';
    final sc = find.byType(Scrollable).first;
    final pos = t.state<ScrollableState>(sc).position;
    final vp = t.getRect(sc);
    final cta = find.ancestor(of: findVisibleText('지원 준비하기'), matching: find.byType(ElevatedButton)).first;
    final out = <String>[];
    void log(String l) {
      out.add(l);
      // ignore: avoid_print
      print('S041-LOC $l');
    }
    void paragraphs(String scene) {
      final ps = t.renderObjectList<RenderParagraph>(find.byType(RichText)).toList();
      var n = 0;
      for (final p in ps) {
        final txt = p.text.toPlainText().replaceAll('⁠', '').replaceAll('\n', '⏎');
        if (txt.trim().isEmpty) continue;
        final g = p.localToGlobal(Offset.zero);
        if (g.dy + p.size.height < vp.top || g.dy > vp.bottom) continue; // 화면 밖 글은 뺀다
        n++;
        log('[$tag $scene] P$n "${txt.length > 40 ? '${txt.substring(0, 40)}…' : txt}" iw=${p.getMaxIntrinsicWidth(double.infinity).toStringAsFixed(2)}'
            ' size=${p.size.width.toStringAsFixed(2)}×${p.size.height.toStringAsFixed(2)} at=(${g.dx.toStringAsFixed(1)},${g.dy.toStringAsFixed(1)})'
            ' exceed=${p.didExceedMaxLines}');
      }
      log('[$tag $scene] 글 문단 $n');
    }
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }
    Map<String, Object?> sidecar(String scene) => {
          'screen': 'JobPostingScreen(to: _to(), slotDate: s1, reads: _jobReads([s1, s2 FULL, s3])) — 사진 없음, USER (S041-SCR 과 같은 fixture)',
          'locale': cond, 'theme': 'RoleTheme.workerTheme', 'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'dpr': 1.0, 'textScaler': scale, 'inset': '0',
          'fonts': _fontsNote, 'baseDate(DU1_VQ_DATE)': Platform.environment['DU1_VQ_DATE'] ?? 'now',
          'clock': '주입 없음 — JobPostingReads.now 기본값·D 의 DateTime.now (기록용 _clock=${_clock.toIso8601String()} 은 주입하지 않는다)',
          'scene': scene, 'offset': pos.pixels.toStringAsFixed(1), 'max': pos.maxScrollExtent.toStringAsFixed(1)};
    log('[$tag] $cond');
    log('[$tag 첫 화면] off=${pos.pixels.toStringAsFixed(1)}/${pos.maxScrollExtent.toStringAsFixed(1)} CTA=${t.getRect(cta)}');
    paragraphs('첫 화면');
    await vqCapture(t, key, 'S041-LOC-${tag}_1_first', conditions: sidecar('첫 화면 offset 0'));
    final btnLabel = s041CardButton('상하차');
    bool btnInside() {
      if (btnLabel.evaluate().isEmpty) return false;
      final b = t.getRect(find.ancestor(of: btnLabel.first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first);
      return b.top >= vp.top && b.bottom <= t.getRect(cta).top - 8;
    }
    var k = 0;
    while (!btnInside() && k < 30) {
      await t.dragFrom(Offset(vp.center.dx, vp.center.dy + 120), const Offset(0, -120));
      await settle();
      k++;
    }
    expect(btnInside(), isTrue, reason: '상하차 선택 버튼이 실제 drag 로 CTA 위 표시 영역에 들어온다');
    log('[$tag 둘째 업무] drag=$k off=${pos.pixels.toStringAsFixed(1)}/${pos.maxScrollExtent.toStringAsFixed(1)}');
    paragraphs('둘째 업무');
    await vqCapture(t, key, 'S041-LOC-${tag}_2_second_work', conditions: sidecar('실제 dragFrom -120 × $k'));
    final b = t.getRect(find.ancestor(of: btnLabel.first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first);
    await t.tapAt(b.center);
    await settle();
    expect(find.descendant(of: s041Card('상하차'), matching: find.text('선택됨')), findsOneWidget, reason: '상하차 선택됨(화면 상태만)');
    log('[$tag 선택 뒤] off=${pos.pixels.toStringAsFixed(1)}/${pos.maxScrollExtent.toStringAsFixed(1)}');
    await vqCapture(t, key, 'S041-LOC-${tag}_3_selected', conditions: sidecar('상하차 선택 실제 탭 뒤(같은 offset)'));
    var e = 0;
    while (pos.pixels < pos.maxScrollExtent - 0.5 && e < 30) {
      await t.dragFrom(Offset(vp.center.dx, vp.center.dy + 120), const Offset(0, -160));
      await settle();
      e++;
    }
    log('[$tag 말단] drag=$e off=${pos.pixels.toStringAsFixed(1)}/${pos.maxScrollExtent.toStringAsFixed(1)}');
    paragraphs('말단');
    await vqCapture(t, key, 'S041-LOC-${tag}_4_end', conditions: sidecar('말단까지 실제 dragFrom -160 × $e'));
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('S041-LOC-en 390×844 — 한국어 시각 하네스 비교용 기본 locale(S041-SCR 과 같은 트리): 첫 화면·둘째 업무·선택·말단', (t) async {
    await s041LocaleProbe(t, ko: false);
  });

  testWidgets('S041-LOC-ko 390×844 — 한국어 시각 하네스(ko_KR·Global delegates): 첫 화면·둘째 업무·선택·말단', (t) async {
    await s041LocaleProbe(t, ko: true);
  });

  // [DU1 후속119 S041 V8] 작은 폭·큰 배율 한국어 관측 — 같은 probe·같은 장면을 360×560 / scaler 1.3 / ko_KR 로(감사118: 작은 폭 ko 는 V8 셀에서).
  //   단언은 하네스 기초(도달·선택됨·overflow 0·예외 없음)뿐, 문단 높이·exceed 는 관측이다.
  testWidgets('S041-LOCS-ko 360×560@1.3 — 작은 폭 한국어 관측(ko_KR·Global delegates): 첫 화면·둘째 업무·선택·말단', (t) async {
    await s041LocaleProbe(t, ko: true, size: const Size(360, 560), scale: 1.3, tag: 'ko-s');
  });

  // [DU1 후속126 C124-2] 공통 AttendanceRuleGuideView 의 '시간 예시 보기/접기' 현 위치 토글 관측 — S041 과 같은 fixture(_to/_slot s1·s2 FULL·s3,
  //   피킹 09:00~18:00·상하차 13:00~22:00)에 사업장 근태 기준만 기본값(const AttendanceRules())으로 넣는다. 공개 공고(내 지원 없음) → '예시 기준 근무'.
  //   ko_KR·Global delegates·390×844·DPR1·scaler1·inset0·workerTheme·_loadFonts 근사. 토글은 화면 안 상태(_showExamples)만 바꾼다 — writer·이동·저장 아님.
  //   장면: 실제 drag 로 토글이 표시 영역에 든 접힘 · 실제 tap 뒤 같은 offset 펼침 · 펼침에서 '접기' 가 표시 영역에 든 프레임.
  //   단언은 도달(토글 표시 영역 안)·tap 뒤 '시간 예시 접기' 1개·overflow 0·예외 없음뿐이다. 색·크기·hit·주변 문단은 관측 줄이다.
  testWidgets('S041-ARG-ko 390×844 — 근태 기준 있는 공고의 시간 예시 토글 접힘·펼침(ko_KR)', (t) async {
    final slots = [_slot('s1', 1), _slot('s2', 2, full: true), _slot('s3', 3)];
    final overflows = <String>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      final m = d.exceptionAsString();
      if (m.contains('overflowed')) {
        overflows.add(m.split('\n').first);
      } else {
        prevOnError?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prevOnError);
    final key = GlobalKey();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final home = JobPostingScreen(
        to: _to(), workDetails: const [], slotDate: slots.first.date, reads: _jobReads(slots, rules: const AttendanceRules()));
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            locale: const Locale('ko', 'KR'),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
            home: home),
      ),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }
    final ctx = t.element(find.byType(JobPostingScreen));
    final ml = MaterialLocalizations.of(ctx);
    final cond = 'requested=ko_KR · resolved=${Localizations.localeOf(ctx)} · MaterialLocalizations=${ml.runtimeType}'
        ' · scriptCategory=${ml.scriptCategory} · semanticsEnabled=${t.binding.semanticsEnabled}';
    final sc = find.byType(Scrollable).first;
    final pos = t.state<ScrollableState>(sc).position;
    final vp = t.getRect(sc);
    void log(String l) {
      // ignore: avoid_print
      print('S041-ARG $l');
    }
    bool hits(Finder f, Offset p) {
      final r = HitTestResult();
      WidgetsBinding.instance.hitTestInView(r, p, t.view.viewId);
      return r.path.any((e) => e.target == t.renderObject(f));
    }
    String hex(Color? c) => c == null ? 'null' : '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    bool inView(Rect r) => r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5;
    void describe(String scene, String label) {
      final txt = find.text(label);
      if (txt.evaluate().isEmpty) {
        log('[$scene] "$label" 없음');
        return;
      }
      final btn = find.ancestor(of: txt, matching: find.byType(TextButton)).first;
      final br = t.getRect(btn);
      final tr = t.getRect(txt);
      final st = (t.renderObject(txt) as RenderParagraph).text.style;
      log('[$scene] "$label" TextButton $br ${br.width.toStringAsFixed(1)}×${br.height.toStringAsFixed(1)} hit=${hits(btn, br.center)}'
          ' · 글 $tr 색 ${hex(st?.color)} 명목 ${st?.fontSize} w${st?.fontWeight?.value} · 표시영역 안=${inView(tr)}');
    }
    void paragraphs(String scene) {
      var n = 0;
      for (final p in t.renderObjectList<RenderParagraph>(find.byType(RichText))) {
        final txt = p.text.toPlainText().replaceAll('⁠', '').replaceAll('\n', '⏎');
        if (txt.trim().isEmpty) continue;
        final g = p.localToGlobal(Offset.zero);
        if (g.dy + p.size.height < vp.top || g.dy > vp.bottom) continue;
        n++;
        final st = p.text.style;
        final head = txt.length > 36 ? '${txt.substring(0, 36)}…' : txt;
        log('[$scene] P$n "$head" at=(${g.dx.toStringAsFixed(1)},${g.dy.toStringAsFixed(1)})'
            ' ${p.size.width.toStringAsFixed(1)}×${p.size.height.toStringAsFixed(1)} 색 ${hex(st?.color)} 명목 ${st?.fontSize} w${st?.fontWeight?.value}');
      }
      log('[$scene] 표시 영역 글 문단 $n');
    }
    Map<String, Object?> sidecar(String scene) => {
          'screen': 'JobPostingScreen(to: _to(), slotDate: s1, reads: _jobReads([s1, s2 FULL, s3], rules: const AttendanceRules())) — 사진 없음, USER, 공개 공고(내 지원 없음)',
          'locale': cond, 'theme': 'RoleTheme.workerTheme', 'viewport': '390x844', 'dpr': 1.0, 'textScaler': 1.0, 'inset': '0',
          'fonts': _fontsNote, 'baseDate(DU1_VQ_DATE)': Platform.environment['DU1_VQ_DATE'] ?? 'now',
          'clock': '주입 없음 — JobPostingReads.now 기본값·D 의 DateTime.now',
          'scene': scene, 'offset': pos.pixels.toStringAsFixed(1), 'max': pos.maxScrollExtent.toStringAsFixed(1)};
    log('[ARG] $cond · 본문 $vp max=${pos.maxScrollExtent.toStringAsFixed(1)}');
    final toggle = find.text('시간 예시 보기');
    expect(toggle, findsOneWidget, reason: '근태 기준·근무 시각이 있으면 접힌 사례 토글이 있다');
    var k = 0;
    while (!inView(t.getRect(toggle)) && k < 40) {
      await t.dragFrom(Offset(vp.center.dx, vp.center.dy + 120), const Offset(0, -160));
      await settle();
      k++;
    }
    expect(inView(t.getRect(toggle)), isTrue, reason: '실제 drag 로 토글이 표시 영역에 든다');
    log('[접힘] drag=$k off=${pos.pixels.toStringAsFixed(1)}/${pos.maxScrollExtent.toStringAsFixed(1)}');
    describe('접힘', '시간 예시 보기');
    paragraphs('접힘');
    await vqCapture(t, key, 'S041-ARG-ko_1_collapsed', conditions: sidecar('실제 dragFrom -160 × $k · 토글 접힘'));
    await t.tap(find.widgetWithText(TextButton, '시간 예시 보기'));
    await settle();
    expect(find.text('시간 예시 접기'), findsOneWidget, reason: '토글 tap 뒤 같은 자리에서 펼침');
    log('[펼침] off=${pos.pixels.toStringAsFixed(1)}/${pos.maxScrollExtent.toStringAsFixed(1)}');
    describe('펼침', '시간 예시 접기');
    paragraphs('펼침');
    await vqCapture(t, key, 'S041-ARG-ko_2_expanded', conditions: sidecar('토글 실제 tap 뒤 같은 offset · 펼침'));
    final fold = find.text('시간 예시 접기');
    var e = 0;
    while (!inView(t.getRect(fold)) && e < 40) {
      await t.dragFrom(Offset(vp.center.dx, vp.center.dy + 120), const Offset(0, -160));
      await settle();
      e++;
    }
    log('[펼침 접기] drag=$e off=${pos.pixels.toStringAsFixed(1)}/${pos.maxScrollExtent.toStringAsFixed(1)}');
    describe('펼침 접기', '시간 예시 접기');
    paragraphs('펼침 접기');
    await vqCapture(t, key, 'S041-ARG-ko_3_expanded_fold', conditions: sidecar('펼침 뒤 실제 dragFrom -160 × $e · 접기 토글 표시 영역'));
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });

  // [DU1 후속118 S041 사진 미리보기 의미 이름] 디코드되어 표시된 LOCAL 사진 한 장에서 사진 미리보기 receiver 의 semantics 를 관측·단언한다.
  //   사진: assets/icons/app_icon.png(기존 저장소 자원, 실제 PNG) bytes 를 _LocalPhotoCacheManager 로 '.invalid' URL 에 연결 — 실DEV·CDN·업로드 아님.
  //   디코드는 엔진 비동기라 runAsync 로 기다리고, 표시 확인 = CachedNetworkImage 안 RawImage.image != null(크기 기록). path_provider 는 세는 mock(응답 없음)만 둔다.
  //   MaterialApp: locale ko_KR + GlobalMaterial/Widgets/Cupertino delegates + supportedLocales [ko_KR, en_US](앱 main 의 delegates·지원 목록 + LOCAL ko_KR 명시).
  //   dummy route('S041-PSEM 이전 화면') 위 push · USER · 사진 1장(imageUrls 없음 → 높이 240) · 390×844·DPR1·scaler1·inset0 · workerTheme · _loadFonts 근사.
  //   단계: 펼침(사진 표시) · 실제 drag 완전 접힘(AppBar ≤56.5). 관측: 사진 receiver(CachedNetworkImage 의 가장 가까운 onTap GestureDetector) 노드의
  //   label·isButton·isImage·tap·rect, 같은 기능명 노드 수(와 그중 tap 있는 수), 사진 가운데를 덮는 tap 노드, 뒤로 노드 label.
  //   행동(펼침): ① semantics tap(node.owner.performAction) → 결과 ② 새 진입 뒤 실제 touch tapAt(사진 가운데) → 결과. 미리보기면 닫은 뒤 상세 남음을 확인한다.
  //   MEASURE 는 관측(진입·표시·접힘만 단언)·PNG 2장. ASSERT 는 펼침 label '사업장 사진 미리보기'·tap·같은 기능명 1개(= 사진 노드)·semantics/touch 미리보기·
  //   닫은 뒤 상세 남음, 완전 접힘 같은 기능명 노드 0(보이지 않는 사진이 이름·동작으로 노출되지 않음)·뒤로 label 보존을 단언한다.
  Future<void> s041PhotoSemanticsProbe(WidgetTester t, {required bool strict}) async {
    final tag = strict ? 'ASSERT' : 'MEASURE';
    const photoName = '사업장 사진 미리보기';
    const photoUrl = 'https://du1-s041.invalid/biz1-photo-local.png';
    final photoBytes = File('assets/icons/app_icon.png').readAsBytesSync();
    final slots = [_slot('s1', 1), _slot('s2', 2, full: true), _slot('s3', 3)];
    final base = _jobReads(slots);
    final reads = JobPostingReads(
        toOrFailure: base.toOrFailure,
        workDetails: base.workDetails,
        businessById: (id) async => BusinessModel(
            id: 'biz1', name: '강남 물류센터 평택 2공장', ownerId: 'a1', businessNumber: '000-00-00000', address: '경기도 평택시 포승읍 1',
            category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2025), mainImageUrl: photoUrl),
        slots: base.slots,
        myApplications: base.myApplications,
        workTypeCatalog: base.workTypeCatalog,
        applicationOnce: base.applicationOnce);
    final overflows = <String>[];
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final pathCalls = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, (call) {
      pathCalls.add(call.method);
      return Future.any(<Future<Object?>>[]);
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null));
    // [r3] cache manager 교체는 path_provider mock 뒤 — 기존 값 읽기가 DefaultCacheManager 정적 초기화(path_provider 호출)를 일으킨다
    final cm = _LocalPhotoCacheManager(photoUrl, photoBytes);
    final prevCm = cni.CachedNetworkImageProvider.defaultCacheManager;
    cni.CachedNetworkImageProvider.defaultCacheManager = cm;
    addTearDown(() => cni.CachedNetworkImageProvider.defaultCacheManager = prevCm);
    final otherErrors = <String>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      final m = d.exceptionAsString();
      if (m.contains('overflowed')) {
        overflows.add(m.split('\n').first);
      } else {
        otherErrors.add(m.split('\n').first);
        prevOnError?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prevOnError);
    final key = GlobalKey();
    final nav = GlobalKey<NavigatorState>();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
            navigatorKey: nav,
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            locale: const Locale('ko', 'KR'),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)), child: child!),
            home: const Scaffold(body: Center(child: Text('S041-PSEM 이전 화면')))),
      ),
    ));
    await t.pump();
    Future<void> settle(int n) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }
    final prev = find.text('S041-PSEM 이전 화면');
    final preview = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ImagePreviewDialog');
    final cachedImg = find.byWidgetPredicate((w) => w.runtimeType.toString() == 'CachedNetworkImage');
    bool onDetail() => find.byType(JobPostingScreen).evaluate().isNotEmpty;
    Finder photoGd() => find.ancestor(of: cachedImg, matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onTap != null)).first;
    Finder backGd() => find
        .ancestor(of: find.byIcon(Icons.arrow_back), matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onTap != null))
        .first;
    RawImage? shownImage() {
      final r = find.descendant(of: cachedImg, matching: find.byWidgetPredicate((w) => w is RawImage && w.image != null));
      return r.evaluate().isEmpty ? null : t.widget<RawImage>(r.first);
    }
    double barH() => t.getRect(find.byType(AppBar).first).height;
    Future<int> waitPhoto() async {
      var k = 0;
      while (shownImage() == null && k < 30) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump(const Duration(milliseconds: 100));
        k++;
      }
      await settle(12); // [r3] 페이드 인(150ms)·placeholder 페이드아웃(OctoImage 기본 1000ms) 끝
      return k;
    }
    Future<String> open({required bool collapse}) async {
      nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => JobPostingScreen(to: _to(), workDetails: const [], slotDate: slots.first.date, reads: reads)));
      await settle(25);
      expect(onDetail(), isTrue, reason: '상세 진입');
      expect(prev, findsNothing, reason: '이전 화면은 가려진다(offstage)');
      expect(find.byType(FlexibleSpaceBar), findsOneWidget, reason: '사진 있는 분기(갤러리 앱바)');
      final waits = await waitPhoto();
      final img = shownImage();
      expect(img, isNotNull, reason: 'LOCAL 사진이 디코드되어 표시된다');
      var drags = 0;
      if (collapse) {
        final vp = t.getRect(find.byType(Scrollable).first);
        while (barH() > 56.5 && drags < 10) {
          await t.dragFrom(Offset(vp.center.dx, vp.center.dy + 120), const Offset(0, -120));
          await settle(12);
          drags++;
        }
        expect(barH(), lessThanOrEqualTo(56.5), reason: '실제 drag 로 AppBar 가 툴바 높이까지 접힌다');
      }
      return 'runAsync 대기 $waits회 · 표시 이미지 ${img!.image!.width}×${img.image!.height} · Shimmer ${find.byWidgetPredicate((w) => w.runtimeType.toString() == 'Shimmer').evaluate().length}'
          ' · drag $drags · AppBar ${barH().toStringAsFixed(1)}';
    }
    Future<String> cleanup() async {
      final notes = <String>[];
      var guard = 0;
      while (preview.evaluate().isNotEmpty && guard < 3) {
        nav.currentState!.pop();
        await settle(10);
        notes.add('미리보기 닫음');
        guard++;
      }
      if (onDetail()) {
        nav.currentState!.pop();
        await settle(10);
        notes.add('상세 닫음');
      }
      expect(onDetail(), isFalse, reason: '다음 단계 전 이전 화면으로 돌아와 있다');
      return notes.isEmpty ? '' : ' (하네스 ${notes.join('·')})';
    }
    String outcome() => (!onDetail() && prev.evaluate().isNotEmpty)
        ? '복귀'
        : preview.evaluate().isNotEmpty
            ? '미리보기'
            : '무반응';
    // 미리보기를 닫은 뒤에도 상세에 남는지(하네스가 상세를 닫기 전에 계산)
    Future<String> closePreviewThenState() async {
      if (preview.evaluate().isEmpty) return '미리보기 없음';
      nav.currentState!.pop();
      await settle(10);
      return preview.evaluate().isEmpty && onDetail() ? '닫은 뒤 상세 남음' : '닫은 뒤 상태 이상(미리보기 ${preview.evaluate().length}·상세 ${onDetail()})';
    }
    Rect globalRect(SemanticsNode n) {
      var r = n.rect;
      SemanticsNode? c = n;
      while (c != null) {
        if (c.transform != null) r = MatrixUtils.transformRect(c.transform!, r);
        c = c.parent;
      }
      return r;
    }
    List<SemanticsNode> allNodes(SemanticsNode any) {
      var root = any;
      while (root.parent != null) {
        root = root.parent!;
      }
      final all = <SemanticsNode>[];
      void visit(SemanticsNode n) {
        all.add(n);
        n.visitChildren((c) {
          visit(c);
          return true;
        });
      }
      visit(root);
      return all;
    }
    String fr(Rect r) => '(${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)})~(${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)})';
    final out = <String>[];
    void log(String l) {
      out.add(l);
      // ignore: avoid_print
      print('S041-PSEM $l');
    }
    final ctx0 = <String>[];
    for (final collapse in [false, true]) {
      final stage = collapse ? '사진 완전 접힘(실제 drag)' : '사진 펼침';
      final load = await open(collapse: collapse);
      if (ctx0.isEmpty) {
        final c = t.element(find.byType(JobPostingScreen));
        final ml = MaterialLocalizations.of(c);
        ctx0.add('requested=ko_KR · resolved=${Localizations.localeOf(c)} · MaterialLocalizations=${ml.runtimeType} · scriptCategory=${ml.scriptCategory}'
            ' · semanticsEnabled=${t.binding.semanticsEnabled} · 사진 bytes ${photoBytes.length}');
        log('[$tag] ${ctx0.first}');
      }
      final pgRect = t.getRect(photoGd());
      final pNode = t.getSemantics(photoGd());
      final pData = pNode.getSemanticsData();
      final bNode = t.getSemantics(backGd());
      final all = allNodes(bNode); // [r4] 살아 있는 뒤로 노드의 root 에서 순회(사진 노드는 제외되면 detached 일 수 있다)
      final named = all.where((n) => n.label == photoName).toList();
      final namedTap = named.where((n) => n.getSemanticsData().hasAction(SemanticsAction.tap)).length;
      final center = Offset(pgRect.center.dx, (56 + 240) / 2);
      final tapOver = all.where((n) => n.getSemanticsData().hasAction(SemanticsAction.tap) && globalRect(n).contains(center)).toList();
      log('[$tag $stage] $load · 사진GD=${fr(pgRect)} · node#${pNode.id} label="${pNode.label}" isButton=${pNode.flagsCollection.isButton}'
          ' isImage=${pNode.flagsCollection.isImage} tap=${pData.hasAction(SemanticsAction.tap)} rect=${fr(globalRect(pNode))} attached=${pNode.attached} 트리포함=${all.contains(pNode)}'
          ' · 같은 기능명 노드 ${named.length}(tap $namedTap)(${named.map((n) => '#${n.id}').join(',')})'
          ' · 사진 가운데${'(${center.dx.toStringAsFixed(0)},${center.dy.toStringAsFixed(0)})'} tap 노드 ${tapOver.length}(${tapOver.map((n) => '#${n.id}"${n.label}"').join(' | ')})'
          ' · 뒤로 node#${bNode.id} label="${bNode.label}" · 노드 수 ${all.length}');
      if (!strict) {
        await vqCapture(t, key, collapse ? 'S041-PSEM_2_collapsed' : 'S041-PSEM_1_expanded', conditions: {
          'screen': 'MaterialApp(locale ko_KR · Global delegates, home: dummy) → push JobPostingScreen(to: _to(), slotDate: s1, reads: 사진 1장 businessById + _jobReads 나머지) — USER',
          'photo': '$photoUrl ← assets/icons/app_icon.png ${photoBytes.length} bytes (_LocalPhotoCacheManager, 메모리 파일) · $load',
          'locale': ctx0.first, 'theme': 'RoleTheme.workerTheme', 'viewport': '390x844', 'dpr': 1.0, 'textScaler': 1.0, 'inset': '0',
          'fonts': _fontsNote, 'baseDate(DU1_VQ_DATE)': Platform.environment['DU1_VQ_DATE'] ?? 'now',
          'clock': '주입 없음 — JobPostingReads.now 기본값·D 의 DateTime.now (기록용 _clock=${_clock.toIso8601String()} 은 주입하지 않는다)',
          'scene': stage, 'measure': out.last});
      }
      if (!collapse) {
        // ① semantics tap
        pNode.owner!.performAction(pNode.id, SemanticsAction.tap);
        await settle(10);
        final so = outcome();
        final sc = await closePreviewThenState();
        log('[$tag $stage] semantics tap(node#${pNode.id}) → $so · $sc${await cleanup()}');
        // ② 새 진입 뒤 실제 touch
        await open(collapse: false);
        await t.tapAt(center);
        await settle(10);
        final to = outcome();
        final tc = await closePreviewThenState();
        log('[$tag $stage] touch tapAt(${center.dx.toStringAsFixed(1)},${center.dy.toStringAsFixed(1)}) → $to · $tc${await cleanup()}');
        if (strict) {
          expect(pNode.label, photoName, reason: '펼친 사진 미리보기 receiver 의 기능명');
          expect(pData.hasAction(SemanticsAction.tap), isTrue, reason: '펼친 사진 tap action');
          expect(named.length, 1, reason: '같은 기능명 노드는 하나');
          expect(named.single.id, pNode.id, reason: '그 기능명 노드가 사진 receiver 의 노드다');
          expect(so, '미리보기', reason: 'semantics tap → 사진 미리보기');
          expect(sc, '닫은 뒤 상세 남음', reason: 'semantics 미리보기를 닫으면 상세에 남는다');
          expect(to, '미리보기', reason: '실제 touch → 사진 미리보기');
          expect(tc, '닫은 뒤 상세 남음', reason: 'touch 미리보기를 닫으면 상세에 남는다');
          expect(bNode.label, '뒤로', reason: '뒤로 label 보존');
        }
      } else {
        log('[$tag $stage] (행동 없음 — 숨은 입력은 구현114 HPT 계약)${await cleanup()}');
        if (strict) {
          expect(named.length, 0, reason: '완전 접힘: 보이지 않는 사진이 기능명 노드로 노출되지 않는다');
          expect(bNode.label, '뒤로', reason: '뒤로 label 보존');
        }
      }
    }
    log('[$tag] LOCAL cache getFileStream ${cm.calls.length} · path_provider 호출 ${pathCalls.length} · overflow ${overflows.length} · 기타 FlutterError ${otherErrors.length}');
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('S041-PSEM-MEASURE 390×844 — LOCAL 사진 표시 펼침·완전 접힘의 사진 미리보기 semantics(이름·역할·action·중복)·semantics/touch 미리보기(관측)', (t) async {
    await s041PhotoSemanticsProbe(t, strict: false);
  });

  testWidgets('S041-PSEM-ASSERT 390×844 — 펼침 사진 기능명 "사업장 사진 미리보기"·tap·중복 없음·미리보기 열고 닫으면 상세, 접힘 노출 0', (t) async {
    await s041PhotoSemanticsProbe(t, strict: true);
  });

  // [DU1 후속17 §4] 짧은 viewport 행동 대표 — 시간 RichText·보조 '업무 자세히 보기'·선택→선택됨·고정 CTA 가 함께 닿는지.
  //   JPD-R(높이 1600) 의 존재 PASS 를 짧은 화면의 행동 도달로 쓰지 않는다.
  testWidgets('VQ-02s 일자리 상세 360×560@1.3 — 선택→선택됨·시간/보조 노출·고정 CTA 와 겹치지 않음·넘침 0', (t) async {
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
    final slots = [_slot('s1', 1), _slot('s2', 2, full: true), _slot('s3', 3)];
    const h = 560.0;
    await _capture(t, JobPostingScreen(to: _to(), workDetails: const [], slotDate: slots.first.date, reads: _jobReads(slots)),
        'VQ-02s_job_detail_short_selected', size: const Size(360, h), scale: 1.3,
        scroll: "scrollUntilVisible(첫 '선택') 뒤 탭 → '선택됨'", beforeShot: () async {
      final cta = findVisibleText('지원 준비하기');
      expect(cta, findsOneWidget, reason: '고정 CTA');
      final ctaTop = t.getRect(cta).top;
      final select = find.text('선택').first;
      await t.scrollUntilVisible(select, 80, scrollable: find.byType(Scrollable).first, maxScrolls: 60);
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(select);
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final selected = find.text('선택됨');
      expect(selected, findsOneWidget, reason: '선택 → 선택됨');
      final sr = t.getRect(selected);
      expect(sr.top >= 0 && sr.bottom <= ctaTop, isTrue, reason: '선택됨이 고정 CTA 위 화면 안 $sr / ctaTop=$ctaTop');
      final detail = findVisibleText('업무 자세히 보기');
      expect(detail, findsWidgets, reason: '보조 행동 존재');
      final time = findVisibleTextContaining('09:00–18:00'); // [DU382] CP05 시간 범위 en dash
      expect(time, findsWidgets, reason: '시간 RichText');
      expect(t.getRect(cta).bottom <= h, isTrue, reason: 'CTA 화면 안');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
    });
  });

  testWidgets('VQ-01c 지원자 홈 320×640@2.0 — 새 확정(미열람) 긴 이름, 날짜·시간 주 줄·확인 행동 도달·넘침 0', (t) async {
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
    final longApp = ApplicationModel(
        id: 'newL', toId: 'to_newL', uid: 'u1', businessId: 'biz1', businessName: '[QA] 아주 긴 이름의 강남 물류센터 평택 2공장',
        toTitle: '단기 공고', status: AppStatus.confirmed, selectedWorkType: '냉장 피킹·검수 보조', startTime: '09:00', endTime: '18:00',
        wage: 12000, wageType: 'hourly', workDate: _day(3), confirmedAt: _clock.subtract(const Duration(hours: 2)), appliedAt: _day(-3));
    await _capture(t, UserHomeScreen(reads: _reads([longApp]), clock: () => _clock), 'VQ-01c_user_home_new_confirm_320x2',
        size: const Size(320, 640), scale: 2.0, scroll: "scrollUntilVisible('근무 확인하기') 뒤 — 날짜·시간·긴 이름은 위로 지나감(VQ-01d 가 첫 화면)",
        beforeShot: () async {
      final d = _day(3);
      final wd = const ['월', '화', '수', '목', '금', '토', '일'][d.weekday - 1];
      // [DU383] CP03 Q4 — 날짜(요일) 보조 줄과 큰 시간 주 줄(두 토큰 · 의미 한 줄)로 나뉘었다
      expect(findVisibleText('${d.month}월 ${d.day}일($wd)'), findsOneWidget, reason: '날짜(요일) 보조 줄');
      expect(_promiseTimeFinder('09:00', '18:00'), findsOneWidget, reason: '시간 주 줄');
      final cta = find.text('근무 확인하기');
      await t.scrollUntilVisible(cta, 150, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
      await t.pump(const Duration(milliseconds: 100));
      final r = t.getRect(cta);
      expect(r.bottom <= 640 && r.top >= 0, isTrue, reason: '확인 행동이 viewport 안에 닿는다 $r');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
    });
  });

  // [DU1 후속16 §4] VQ-01c 는 행동 도달을 보려 스크롤 뒤에 찍어 날짜·시간·긴 이름이 PNG 에 없다 — 같은 조건 첫 화면을 따로 남긴다.
  // [DU383 r2] 소급 19 (a) 비동등 계약 개정 — 원 이름 'VQ-01d 지원자 홈 320×640@2.0 첫 화면 — 날짜(요일)·시간 주 줄 전체·긴 사업장/업무명 노출·넘침 0'.
  //   원 첫 화면 단언 실패(업무 줄 아래 27.3 밖, DU383 TA · TA2)는 보존 기록이다. 이제 첫 화면은 캡처로 남기고 실제 스크롤 도달을 단언한다.
  testWidgets('VQ-01d 지원자 홈 320×640@2.0 — 첫 화면 기록 뒤 날짜(요일)·시간·긴 사업장/업무명 실제 스크롤 도달·넘침 0', (t) async {
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
    final longApp = ApplicationModel(
        id: 'newL', toId: 'to_newL', uid: 'u1', businessId: 'biz1', businessName: '[QA] 아주 긴 이름의 강남 물류센터 평택 2공장',
        toTitle: '단기 공고', status: AppStatus.confirmed, selectedWorkType: '냉장 피킹·검수 보조', startTime: '09:00', endTime: '18:00',
        wage: 12000, wageType: 'hourly', workDate: _day(3), confirmedAt: _clock.subtract(const Duration(hours: 2)), appliedAt: _day(-3));
    await _capture(t, UserHomeScreen(reads: _reads([longApp]), clock: () => _clock), 'VQ-01d_user_home_new_confirm_320x2_reach',
        size: const Size(320, 640), scale: 2.0, topId: 'VQ-01d_user_home_new_confirm_320x2_top',
        scroll: '첫 화면(offset 0) 캡처 뒤 Hero 날짜 · 시간 · 사업장 · 업무 각각 실제 스크롤 도달(마지막 = 업무)', beforeShot: () async {
      final d = _day(3);
      final wd = const ['월', '화', '수', '목', '금', '토', '일'][d.weekday - 1];
      await _heroReach(t, tag: 'VQ-01d', date: '${d.month}월 ${d.day}일($wd)', start: '09:00', end: '18:00',
          biz: '[QA] 아주 긴 이름의 강남 물류센터 평택 2공장', work: '냉장 피킹·검수 보조');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
    });
  });

  // [DU1 후속15 §2.5] 같은 근무일의 UTC 표현(KST 자정 instant 를 DateTime.utc 로 든 slot.date) — 내일 근무가
  //   기기 local 성분으로 읽혀 '오늘'이 되고 '마감임박'(시작 2시간 이내)으로 잘못 판정되던 반례. 고친 뒤에는 보통 모집중.
  // [후속16 §4] KST 22시 이후는 '지금+1시간'이 자정을 넘어 반례 의미가 바뀐다 — 조용히 통과시키지 않고 skipped 로 남긴다
  testWidgets('NS-1 내일 (지금+1시간) 시작 업무는 마감임박이 아니다 — slot.date UTC 표현', skip: _ns1Skip, (t) async {
    final nowKst = DateTime.now().toUtc().add(const Duration(hours: 9));
    final start = '${(nowKst.hour + 1).toString().padLeft(2, '0')}:${nowKst.minute.toString().padLeft(2, '0')}';
    final tomorrowKstMidnightUtc = DateTime.utc(nowKst.year, nowKst.month, nowKst.day + 1).subtract(const Duration(hours: 9));
    final slot = SlotModel(
        id: 'ns1', toId: 'to1', date: tomorrowKstMidnightUtc,
        workDetails: [_wd('wdN', '야간 검수', start, '23:30', 13000, 5)],
        status: SlotStatus.open, confirmedCount: 0, createdAt: DateTime(2026, 10, 1));
    await _capture(t, JobPostingScreen(to: _to(), workDetails: const [], slotDate: slot.date, reads: _jobReads([slot])),
        'NS-1_near_start_tomorrow', beforeShot: () async {
      expect(find.text('마감임박'), findsNothing, reason: '내일 근무 — 2시간 이내 아님');
      expect(find.text('모집중'), findsWidgets);
    });
  });

  // [후속17 §4] 같은 근무일·같은 instant 의 UTC / local 표현 한 쌍 — 실제 local offset 과 각 결과를 run.log 에 남긴다.
  //   skip 이면 testWidgets 결과에 skipped 로 남는다(실행/건너뜀 구별). 전 앱 시계 주입·시간대 행렬은 하지 않는다.
  for (final rep in const ['utc', 'local']) {
    testWidgets('NS-1p 같은 instant $rep 표현 — 마감임박 아님(offset 기록)', skip: _ns1Skip, (t) async {
      final nowKst = DateTime.now().toUtc().add(const Duration(hours: 9));
      final start = '${(nowKst.hour + 1).toString().padLeft(2, '0')}:${nowKst.minute.toString().padLeft(2, '0')}';
      final instant = DateTime.utc(nowKst.year, nowKst.month, nowKst.day + 1).subtract(const Duration(hours: 9));
      final date = rep == 'utc' ? instant : instant.toLocal();
      final slot = SlotModel(
          id: 'ns1$rep', toId: 'to1', date: date,
          workDetails: [_wd('wdN', '야간 검수', start, '23:30', 13000, 5)],
          status: SlotStatus.open, confirmedCount: 0, createdAt: DateTime(2026, 10, 1));
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
        ],
        child: MaterialApp(theme: RoleTheme.workerTheme,
            home: JobPostingScreen(to: _to(), workDetails: const [], slotDate: slot.date, reads: _jobReads([slot]))),
      ));
      for (var i = 0; i < 25; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final nearStart = find.text('마감임박').evaluate().length;
      final recruiting = find.text('모집중').evaluate().length;
      // ignore: avoid_print
      print('NS-1p record rep=$rep isUtc=${date.isUtc} localOffset=${DateTime.now().timeZoneOffset} '
          'instant=${instant.toIso8601String()} date=${date.toIso8601String()} start=$start 마감임박=$nearStart 모집중=$recruiting');
      expect(nearStart, 0, reason: '내일 근무 — 2시간 이내 아님($rep)');
      expect(recruiting, greaterThan(0));
      await t.pumpWidget(const SizedBox.shrink());
    });
  }

  // ── [DU1 후속35 §3] H35 — 지원자 홈 Hero 정보박스·약관/준비/날짜 탐색 밀도. 수정 전후 **같은 셀**(자료·clock·viewport·배율·theme·font·inset) ──
  //   new1: _day(3) 09:00–18:00 피킹·강남 물류센터·시급 12,000·confirmedAt = clock−2h(KST 08시) · next2: _day(5) 13:00–22:00 상하차(새 확정 아님)
  //   약관 reconsentRequired(service_terms) · 지원 준비 0/2(_Worker 신분증·계좌 없음) · 나머지 읽기 빈 목록
  // [DU394] today · clock 을 주면 고정 표본 기준(기본값 = 원래대로 _today · _clock)
  List<ApplicationModel> h35Apps({bool long = false, DateTime? today, DateTime? clock}) => [
        long
            ? ApplicationModel(
                id: 'new1', toId: 'to_new1', uid: 'u1', businessId: 'biz1', businessName: '[QA] 아주 긴 이름의 강남 물류센터 평택 2공장',
                toTitle: '단기 공고', status: AppStatus.confirmed, selectedWorkType: '냉장 피킹·검수 보조', startTime: '09:00', endTime: '18:00',
                wage: 12000, wageType: 'hourly', workDate: today == null ? _day(3) : today.add(const Duration(days: 3)),
                confirmedAt: (clock ?? _clock).subtract(const Duration(hours: 2)),
                appliedAt: today == null ? _day(-3) : today.add(const Duration(days: -3)))
            : _short('new1', 3, confirmedAt: (clock ?? _clock).subtract(const Duration(hours: 2)), today: today),
        _short('next2', 5, type: '상하차', start: '13:00', end: '22:00', today: today),
      ];
  const h35Legal = LegalReadiness(status: LegalReadinessStatus.reconsentRequired, reconsentRequired: ['service_terms']);
  List<String> h35Overflows() {
    final o = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final m = d.exceptionAsString();
      if (m.contains('overflowed')) {
        o.add(m.split('\n').first);
      } else {
        prev?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prev);
    return o;
  }
  String h35Date() {
    final d = _day(3);
    return '${d.month}월 ${d.day}일(${const ['월', '화', '수', '목', '금', '토', '일'][d.weekday - 1]})';
  }
  Finder h35Head() {
    // [DU1 구현69 VQ-01] 확정 카드가 날짜(보조 줄)와 시간(주 줄, 가장 큼)을 나눠 보인다 — 주 줄 = 시간
    // [DU383] CP03 Q4 — 시간은 Semantics('09:00–18:00') 안 두 토큰('09:00' · '–18:00')
    return _promiseTimeFinder('09:00', '18:00');
  }
  // 셀 공통 존재 확인 — 날짜(요일)·시간 / 이름·업무 / 임금 / 확정 의미 / 약관 할 일 / 지원 준비 / 날짜 탐색이 모두 그려진다(숨김으로 공간 확보 금지)
  void h35Present(WidgetTester t, {required bool long}) {
    expect(h35Head(), findsWidgets, reason: '시간 주 줄');
    expect(findVisibleText(h35Date()), findsWidgets, reason: '날짜(요일) 보조 줄');
    expect(findVisibleTextContaining(long ? '[QA] 아주 긴 이름의 강남 물류센터 평택 2공장' : '강남 물류센터'), findsWidgets, reason: '사업장명');
    expect(findVisibleTextContaining('시급'), findsWidgets, reason: '임금 형태');
    expect(findVisibleTextContaining('12,000'), findsWidgets, reason: '임금 금액');
    expect(findVisibleTextContaining('확정'), findsWidgets, reason: '확정 의미');
    expect(find.text('근무 확인하기'), findsOneWidget, reason: '확인 행동');
  }

  testWidgets('H35-A 지원자 홈 390×844@1.0 — 새 확정 + 다가오는 확정 + 약관 재동의 + 준비 0/2', (t) async {
    final overflows = h35Overflows();
    await _capture(t, UserHomeScreen(reads: _reads(h35Apps(), legal: h35Legal), clock: () => _clock), 'H35-A_user_home_390x1',
        beforeShot: () async {
      h35Present(t, long: false);
      final cta = find.text('근무 확인하기');
      final r = t.getRect(cta);
      // ignore: avoid_print
      print('H35-A rect cta=$r head=${t.getRect(h35Head())}');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
    });
  });

  // [DU383 r2] 소급 19 (a) 비동등 계약 개정 — 원 이름 'H35-B 지원자 홈 320×640@2.0 첫 화면 — 긴 이름, 날짜·시간·이름 노출·넘침 0'.
  //   원 첫 화면 단언 실패(큰 시간 y 847.7–981.7, DU383 TA · TA2)는 보존 기록이다. 약관 재동의 · 준비 0/2 상태 그대로 실제 스크롤 도달을 단언한다.
  testWidgets('H35-B 지원자 홈 320×640@2.0 — 첫 화면 기록 뒤 긴 이름, 날짜·시간·이름 실제 스크롤 도달·넘침 0', (t) async {
    final overflows = h35Overflows();
    await _capture(t, UserHomeScreen(reads: _reads(h35Apps(long: true), legal: h35Legal), clock: () => _clock), 'H35-B_user_home_320x2_reach',
        size: const Size(320, 640), scale: 2.0, topId: 'H35-B_user_home_320x2_top',
        scroll: '첫 화면(offset 0) 캡처 뒤 Hero 날짜 · 시간 · 사업장 · 업무 각각 실제 스크롤 도달(마지막 = 업무)', beforeShot: () async {
      h35Present(t, long: true);
      await _heroReach(t, tag: 'H35-B', date: h35Date(), start: '09:00', end: '18:00',
          biz: '[QA] 아주 긴 이름의 강남 물류센터 평택 2공장', work: '냉장 피킹·검수 보조');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
    });
  });

  testWidgets('H35-B2 지원자 홈 320×640@2.0 — 확인 행동까지 실제 스크롤, 전체 터치 영역 viewport 안·넘침 0', (t) async {
    final overflows = h35Overflows();
    await _capture(t, UserHomeScreen(reads: _reads(h35Apps(long: true), legal: h35Legal), clock: () => _clock), 'H35-B2_user_home_320x2_cta',
        size: const Size(320, 640), scale: 2.0, scroll: "scrollUntilVisible('근무 확인하기') 뒤 — 터치 영역(카드 GestureDetector) 하단까지",
        beforeShot: () async {
      h35Present(t, long: true);
      final cta = find.text('근무 확인하기');
      await t.scrollUntilVisible(cta, 120, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
      await t.pump(const Duration(milliseconds: 100));
      // 확인 행동의 실제 터치 대상 = 그 글자를 감싼 가장 가까운 GestureDetector 의 모양(버튼 모양 Container)
      final shape = find.ancestor(of: cta, matching: find.byType(Container)).first;
      final r = t.getRect(shape);
      // ignore: avoid_print
      print('H35-B2 rect ctaShape=$r');
      expect(r.top >= 0 && r.bottom <= 640, isTrue, reason: '확인 행동 전체가 viewport 안 $r');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
    });
  });

  // ── [DU1 후속36 §1] H35-B2 보완 — root(0..640)가 아니라 **실제 스크롤 표시 영역**(Scrollable 의 global rect) 기준.
  //   H35-B2 는 CTA 모양 top 64.6 이 고정 헤더(본문 시작 ≈74) 아래로 가려진 채 통과했다.
  //   표시 CTA = '근무 확인하기' 를 감싼 가장 가까운 Container(버튼 모양). 실제 탭 대상 = 그 위 Hero GestureDetector(카드 전체).
  Future<({Rect viewport, Rect cta, double offset})> h36Position(WidgetTester t) async {
    final cta = find.text('근무 확인하기');
    final sc = find.byType(Scrollable).first;
    await t.scrollUntilVisible(cta, 120, scrollable: sc, maxScrolls: 40);
    await t.pump(const Duration(milliseconds: 100));
    final vp = t.getRect(sc);
    final shape = find.ancestor(of: cta, matching: find.byType(Container)).first;
    var r = t.getRect(shape);
    final pos = t.state<ScrollableState>(sc).position;
    // 표시 영역 위로 걸쳤으면 그만큼(+8) 내용을 내린다 / 아래로 걸쳤으면 올린다 — 실제 스크롤 위치 이동
    if (r.top < vp.top + 8) {
      pos.jumpTo((pos.pixels - (vp.top + 8 - r.top)).clamp(pos.minScrollExtent, pos.maxScrollExtent));
    } else if (r.bottom > vp.bottom - 8) {
      pos.jumpTo((pos.pixels + (r.bottom - (vp.bottom - 8))).clamp(pos.minScrollExtent, pos.maxScrollExtent));
    }
    await t.pump(const Duration(milliseconds: 100));
    r = t.getRect(shape);
    return (viewport: vp, cta: r, offset: pos.pixels);
  }

  bool h36Hits(WidgetTester t, Offset p) {
    final gd = find.ancestor(of: find.text('근무 확인하기'), matching: find.byType(GestureDetector)).first;
    final target = t.renderObject(gd);
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
    return hit.path.any((e) => e.target == target);
  }

  testWidgets('H36-B2 지원자 홈 320×640@2.0 — 확인 행동 표시 CTA 전체가 실제 스크롤 표시 영역 안 · 상/중/하 hit · 넘침 0', (t) async {
    final overflows = h35Overflows();
    await _capture(t, UserHomeScreen(reads: _reads(h35Apps(long: true), legal: h35Legal), clock: () => _clock), 'H36-B2_user_home_320x2_cta_visible',
        size: const Size(320, 640), scale: 2.0,
        scroll: "scrollUntilVisible('근무 확인하기') 뒤 표시 영역(Scrollable global rect) 안으로 정렬 — 고정 헤더 아래",
        beforeShot: () async {
      h35Present(t, long: true);
      final p = await h36Position(t);
      final inside = p.cta.top >= p.viewport.top && p.cta.bottom <= p.viewport.bottom && p.cta.left >= p.viewport.left && p.cta.right <= p.viewport.right;
      final pts = {'top': Offset(p.cta.center.dx, p.cta.top + 3), 'center': p.cta.center, 'bottom': Offset(p.cta.center.dx, p.cta.bottom - 3)};
      final hits = {for (final e in pts.entries) e.key: h36Hits(t, e.value)};
      // ignore: avoid_print
      print('H36-B2 viewport=${p.viewport} ctaShape=${p.cta} offset=${p.offset.toStringAsFixed(1)} inside=$inside hits=$hits');
      expect(inside, isTrue, reason: '표시 CTA 전체가 스크롤 표시 영역 안 ${p.cta} / ${p.viewport}');
      expect(hits.values.every((v) => v), isTrue, reason: 'CTA 상/중/하가 Hero 탭 대상 $hits');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
    });
  });

  testWidgets('H36-B2T 같은 셀에서 표시 CTA 중앙 실제 탭 → 내 지원(initialTabIndex 0)', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(theme: RoleTheme.workerTheme,
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(2.0)), child: child!),
          home: UserHomeScreen(reads: _reads(h35Apps(long: true), legal: h35Legal), clock: () => _clock)),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final p = await h36Position(t);
    expect(p.cta.top >= p.viewport.top && p.cta.bottom <= p.viewport.bottom, isTrue);
    await t.tapAt(p.cta.center);
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final pushed = t.widget<MyApplicationsScreen>(find.byType(MyApplicationsScreen, skipOffstage: false));
    expect(pushed.initialTabIndex, 0);
    // ignore: avoid_print
    print('H36-B2T ok tapAt=${p.cta.center} initialTabIndex=${pushed.initialTabIndex}');
  });

  // 행동: 확인 행동 탭 → 내 지원(initialTabIndex 0) → 뒤로 → 확인 이력(prefs) 반영·새 확정 카드 사라짐·일정은 유지
  testWidgets('H35-ACT 근무 확인하기 → 내 지원 목록 → 복귀 · 확인 이력 반영 · 일정 유지', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(theme: RoleTheme.workerTheme,
          home: UserHomeScreen(reads: _reads(h35Apps(), legal: h35Legal), clock: () => _clock)),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('근무 확인하기'), findsOneWidget);
    await t.tap(find.text('근무 확인하기'));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final pushed = t.widget<MyApplicationsScreen>(find.byType(MyApplicationsScreen, skipOffstage: false));
    expect(pushed.initialTabIndex, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('seen_confirm_ids_v1'), contains('new1'), reason: '확인 이력 기록');
    t.state<NavigatorState>(find.byType(Navigator).first).pop();
    for (var i = 0; i < 15; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(MyApplicationsScreen), findsNothing, reason: '복귀');
    expect(find.text('근무 확인하기'), findsNothing, reason: '확인한 새 확정 카드는 다시 뜨지 않는다');
    final d = _day(5);
    expect(findVisibleTextContaining('13:00'), findsWidgets, reason: '다가오는 일정(${d.month}/${d.day}) 유지');
    // ignore: avoid_print
    print('H35-ACT ok initialTabIndex=${pushed.initialTabIndex} seen=${prefs.getStringList('seen_confirm_ids_v1')}');
    // 목적지가 실제 Firebase 를 부르다 남긴 예외는 홈 행동과 무관 — 기록만
    final ex = t.takeException();
    // ignore: avoid_print
    print('H35-ACT destinationException=${ex == null ? 'none' : ex.runtimeType}');
  });

  // 날짜 영역을 바꿨다 → 빈 상태 영향(같은 날짜 탐색 경로) + 날짜 더보기 열기·취소 한 경로
  testWidgets('H35-E 지원자 홈 빈 상태 390×844@1.0 — 날짜 탐색 영향 확인', (t) async {
    final overflows = h35Overflows();
    await _capture(t, UserHomeScreen(reads: _reads(const []), clock: () => _clock), 'H35-E_user_home_empty_390x1', beforeShot: () async {
      // [DU383] CP03 UH086 질문 시각 삭제 → 날짜 띠 그룹 의미 · UH089 '날짜 더보기' → '날짜 선택'(시트 닫힘 — 홈 행동 하나)
      expect(_dateExplorerGroup(), findsOneWidget);
      expect(find.text('날짜 선택'), findsOneWidget);
      expect(overflows, isEmpty, reason: overflows.join(' | '));
    });
  });

  testWidgets('H35-DATE 날짜 더보기 열기 → 취소 — 시트 열림·닫힘 뒤 스트립·선택 그대로', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(theme: RoleTheme.workerTheme,
          home: UserHomeScreen(reads: _reads(h35Apps(), legal: h35Legal), clock: () => _clock)),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final firstDay = '${_today.day}';
    final lastDay = '${_day(6).day}';
    expect(find.text(firstDay), findsWidgets);
    expect(find.text(lastDay), findsWidgets);
    expect(find.textContaining('일자리 '), findsNothing, reason: '선택 전 날짜 CTA 없음');
    await t.tap(find.text('날짜 선택')); // [DU383] UH089 — 시트 열기 전에는 홈 행동 하나
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(_dateSheetTitle(), findsOneWidget, reason: '시트 열림');
    // 취소 = 시트 바깥(barrier) 탭
    await t.tapAt(const Offset(195, 40));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(_dateSheetTitle(), findsNothing, reason: '시트 닫힘');
    expect(find.text(firstDay), findsWidgets, reason: '스트립 시작일 그대로');
    expect(find.text(lastDay), findsWidgets);
    expect(find.textContaining('일자리 '), findsNothing, reason: '취소 — 선택 날짜 생기지 않음');
    expect(t.takeException(), isNull);
    // ignore: avoid_print
    print('H35-DATE ok strip=$firstDay..$lastDay');
  });

  // [DU1 후속98 S080] 빈 홈(공고 0·지원 0) — H35-E 와 같은 fixture(_reads(const [])·clock·workerTheme·_loadFonts·prefs)를
  //   _capture 와 같은 트리로 직접 띄워 본문 owner·실제 drag 말단·섹션 간격·보이는 링크의 **바깥 receiver**(표시 Text rect 와 따로)를
  //   기록하고 top/mid/end 를 찍는다(_capture 는 한 장만 찍는다). 링크는 누르지 않는다(탐색 제출 없음).
  // [구현99] H98-E 를 크기·배율 인자로 — N 390×844@1.0 과 대표 B 320×640@2.0(C99-2 receiver 48 의 큰 글자 도달)
  Future<void> h98Cell(WidgetTester t, {required String id, required Size size, required double scale, required double dragDy}) async {
    final overflows = h35Overflows();
    final key = GlobalKey();
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
            home: UserHomeScreen(reads: _reads(const []), clock: () => _clock)),
      ),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    bool hits(Finder f, Offset p) {
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
      return hit.path.any((e) => e.target == t.renderObject(f));
    }
    final all = find.byType(Scrollable);
    final cands = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
        .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
        .toList()
      ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
    final body = cands.first;
    final pos = t.state<ScrollableState>(body).position;
    final vp = t.getRect(body);
    final out = <String>['본문 세로 Scrollable ${cands.length}개 중 최대 $vp max=${pos.maxScrollExtent.toStringAsFixed(1)} off=${pos.pixels.toStringAsFixed(1)}'];
    Rect? rectOf(Finder f) => f.evaluate().isEmpty ? null : t.getRect(f.first);
    final marks = <String, Finder>{
      '지원 준비': find.textContaining('지원 준비'),
      // [DU383] CP03 — UH086 질문 시각 삭제(그룹 의미) · UH144 · UH150 · UH151 · UH098 · UH101, 섹션 제목은 낱말 조판
      '날짜 띠 그룹': _dateExplorerGroup(),
      '날짜 숫자(첫 칸)': find.text('${_day(0).day}'),
      '공고 섹션 제목': findVisibleText('둘러볼 일자리'),
      '공고0 제목': find.text('지금 표시할 일자리가 없어요'),
      '공고0 설명': find.text('새 일자리가 등록되면 여기에서 확인할 수 있어요'),
      '지원 현황 제목': findVisibleText('내 지원 현황'),
      '지원0 제목': find.text('아직 지원한 일자리가 없어요'),
      '지원0 설명': find.text('원하는 날짜의 일자리를 찾아보세요'),
    };
    for (final e in marks.entries) {
      out.add('${e.key} ${rectOf(e.value)}');
    }
    final recv = <String, ({Rect text, Rect r, bool hit, bool inVp, String type})>{};
    void receivers(String when) {
      // [DU383] UH102 '일자리 찾기' · UH089 '날짜 선택' · UH099 '전체 보기'. '일자리 찾기'는 약속 0 카드(CP03 Q7)에도 있어
      //   원래 대상(지원 현황 빈 안내의 링크)으로 범위를 좁힌다.
      final links = <String, Finder>{
        '일자리 찾기': find.descendant(
            of: find.ancestor(of: find.text('아직 지원한 일자리가 없어요'), matching: find.byType(Column)).first,
            matching: find.text('일자리 찾기')),
        '날짜 선택': find.text('날짜 선택'),
        '전체 보기': find.text('전체 보기'),
      };
      for (final MapEntry(key: label, value: txt) in links.entries) {
        if (txt.evaluate().isEmpty || recv.containsKey(label)) continue;
        final rf = find.ancestor(of: txt.first, matching: find.byWidgetPredicate((w) =>
            (w is GestureDetector && w.onTap != null) || (w is InkWell && w.onTap != null) || w is ButtonStyleButton)).first;
        final rr = t.getRect(rf);
        // [구현99] viewport 포함은 4방향
        final inVp = rr.top >= vp.top - 0.5 && rr.bottom <= vp.bottom + 0.5 && rr.left >= vp.left - 0.5 && rr.right <= vp.right + 0.5;
        if (!inVp) continue;
        recv[label] = (text: t.getRect(txt.first), r: rr, hit: hits(rf, rr.center), inVp: inVp, type: '${t.widget(rf).runtimeType}@$when');
      }
    }
    receivers('초기');
    await vqCapture(t, key, '${id}_top', conditions: {
      'screen': 'UserHomeScreen(reads: _reads(const []), clock: 2026-11-06T01:00Z) — H35-E 와 같은 빈 fixture',
      'theme': 'RoleTheme.workerTheme', 'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'dpr': 1.0, 'textScaler': scale, 'inset': '0',
      'fonts': '_loadFonts(NotoSansKR·Roboto·FlutterTest·MaterialIcons) 근사', 'scroll': 'off 0', 'measure': out.join(' | ')});
    var k = 0;
    final offs = <double>[pos.pixels];
    while (pos.pixels < pos.maxScrollExtent - 0.5 && k < 20) {
      await t.dragFrom(Offset(vp.left + 4, vp.center.dy), Offset(0, -dragDy));
      // r1: 4×50ms 로는 관성 스크롤이 덜 멈춰 offset 이 max 를 넘은 채 기록됐다 — 정착까지 기다린다
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      k++;
      offs.add(pos.pixels);
      receivers('drag$k');
      if (k == 1) {
        await vqCapture(t, key, '${id}_mid', conditions: {
          'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'textScaler': scale, 'scroll': '본문 실제 dragFrom(left+4,center) -${dragDy.toInt()} × 1 · off ${pos.pixels.toStringAsFixed(1)}'});
      }
    }
    final atEnd = pos.maxScrollExtent < 0.5 || (pos.pixels - pos.maxScrollExtent).abs() < 0.5;
    out.add('정착 offset=${offs.map((o) => o.toStringAsFixed(1)).join('/')} · 최종 max=${pos.maxScrollExtent.toStringAsFixed(1)} · 말단=$atEnd drag=$k · 최대 이동 ${dragDy.toInt()} < viewport ${vp.height.toStringAsFixed(1)}');
    for (final e in recv.entries) {
      final v = e.value;
      out.add('${e.key} 표시 Text ${v.text} · receiver ${v.type} ${v.r} ${v.r.width.toStringAsFixed(1)}×${v.r.height.toStringAsFixed(1)} centerHit=${v.hit} viewport안=${v.inVp}');
    }
    out.add('overflows=${overflows.length}');
    for (final l in out) {
      // ignore: avoid_print
      print('$id $l');
    }
    expect(atEnd, isTrue, reason: '말단');
    expect(find.text('지금 표시할 일자리가 없어요'), findsOneWidget, reason: '공고 0 빈 안내(UH150)');
    // [구현99 C99-2] 세 링크 모두 바깥 receiver 48×48 이상·center hit·viewport 4방향 포함(단언), 서로 겹치지 않음(단언)
    for (final label in const ['일자리 찾기', '날짜 선택', '전체 보기']) {
      final v = recv[label];
      expect(v, isNotNull, reason: '$label 이 본문 viewport 에 4방향으로 들어온 프레임이 있다');
      expect(v!.r.height >= 48 - 0.01 && v.r.width >= 48 - 0.01 && v.hit && v.inVp, isTrue, reason: '$label 바깥 receiver 48×48·hit·4방향 포함');
    }
    final names = recv.keys.toList();
    for (var i = 0; i < names.length; i++) {
      for (var j = i + 1; j < names.length; j++) {
        // 같은 프레임 기준 rect 가 아닐 수 있다(drag 사이 기록) — 같은 프레임에서 기록된 쌍만 겹침을 본다
        final a = recv[names[i]]!, b = recv[names[j]]!;
        if (a.type.split('@').last != b.type.split('@').last) continue;
        final ov = a.r.intersect(b.r);
        // ignore: avoid_print
        print('$id 겹침 ${names[i]} × ${names[j]}: ${ov.width > 0 && ov.height > 0 ? ov : '없음'}');
        expect(ov.width > 0 && ov.height > 0, isFalse, reason: '${names[i]} 와 ${names[j]} receiver 겹침');
      }
    }
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
    await vqCapture(t, key, '${id}_end', conditions: {
      'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'textScaler': scale, 'scroll': '본문 실제 drag → 말단 off ${pos.pixels.toStringAsFixed(1)}', 'measure': out.sublist(out.length - 5).join(' | ')});
    await t.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('H98-E 지원자 홈 빈 상태 390×844@1.0 — 본문 말단·섹션 간격·빈 안내 링크 receiver', (t) async {
    await h98Cell(t, id: 'H98-E_user_home_empty_390x1', size: const Size(390, 844), scale: 1.0, dragDy: 200);
  });

  testWidgets('H99-EB 지원자 홈 빈 상태 320×640@2.0 — 세 링크 receiver 48·말단·overflow 0', (t) async {
    await h98Cell(t, id: 'H99-EB_user_home_empty_320x2', size: const Size(320, 640), scale: 2.0, dragDy: 150);
  });

  // [DU1 구현100 C100-1] 홈 날짜 탐색 줄의 숫자 — 9(한 자리 기준)·10·11·12 의 실제 문단(RenderParagraph) 크기·줄 수·감김,
  //   숫자 상자(AnimatedContainer)·칸(Expanded) 경계 안에 들어오는지. Text rect 는 잘린 상자 크기일 수 있어 문단을 직접 본다.
  //   selectDay 가 있으면 그 날 칸의 바깥 receiver 를 실제 탭해 선택 상태도 같은 항목을 잰다(선택은 화면 상태만 — 쓰기 없음).
  // [DU394] 1부 = 고정 표본 11-08(원 셀 그대로 — 숫자 9~12 한/두 자리 조판, AB/AN 은 표본 +3 = 11 선택). 칸 경계 = 그 칸의 GestureDetector
  //   (행 모드 Expanded · 가로 스크롤 모드 SizedBox 모두 같은 폭 — 원 `Expanded.first` 는 가로 스크롤 모드에서 바깥 Expanded 를 잡을 수 있다).
  //   2부 = 기준일(DU1_VQ_DATE) 실제 7칸: 의미 full date(순서 · 월 경계 · 고유) · 칸 local ≥48 · ensureVisible 뒤 본문/가로 viewport · 화면 안 ·
  //   가운데 hit · 활성 = 확정(_day(3) · _day(5), 공고 0)만 → A 는 _day(3) 실제 탭: 선택 flag(그 칸만) · 정확 CTA 0→1→0. 넘침은 두 부 모두.
  Future<void> stripCell(WidgetTester t,
      {required String id, required String tok, required bool normal, required Size size, required double scale, required double dragDy, String? selectDay}) async {
    final overflows = h35Overflows();
    var taps = 0;
    var moves = 0;
    _d394(_start394(tok));
    _d394('D394 $tok contract=${_contractCheck394(tok)}');
    final sToday = _sampleStrip394;
    final sClock = _kstAt394(sToday);
    final key = GlobalKey();
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
            home: UserHomeScreen(
                reads: normal ? _reads(h35Apps(today: sToday, clock: sClock), legal: h35Legal) : _reads(const []), clock: () => sClock)),
      ),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final all = find.byType(Scrollable);
    final cands = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
        .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
        .toList()
      ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
    final body = cands.first;
    final pos = t.state<ScrollableState>(body).position;
    final vp = t.getRect(body);
    bool fullyIn(Rect r) => r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5 && r.left >= vp.left - 0.5 && r.right <= vp.right + 0.5;
    // 날짜 줄 전체(9~12 숫자 상자)가 viewport 안에 들어올 때까지 실제 drag
    Rect boxOf(String d) => t.getRect(find.ancestor(of: find.text(d), matching: find.byType(AnimatedContainer)).first);
    var k = 0;
    while (!(fullyIn(boxOf('9')) && fullyIn(boxOf('12'))) && k < 30) {
      await t.dragFrom(Offset(vp.left + 4, vp.center.dy), Offset(0, -dragDy));
      moves++;
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      k++;
    }
    final out = <String>['본문 $vp max=${pos.maxScrollExtent.toStringAsFixed(1)} · 날짜 줄 들이기 drag $k회 → off=${pos.pixels.toStringAsFixed(1)}'];
    final bad = <String>[];
    void measure(String when) {
      for (final d in const ['9', '10', '11', '12']) {
        final f = find.text(d);
        if (f.evaluate().length != 1) {
          out.add('$when $d 후보 ${f.evaluate().length}개 — 측정 생략');
          bad.add('$when $d 후보 수');
          continue;
        }
        final para = t.renderObject<RenderParagraph>(f);
        final tp = TextPainter(text: para.text, textScaler: para.textScaler, textDirection: TextDirection.ltr)..layout();
        final lines = (para.size.height / tp.height).round();
        final wrapped = para.size.width + 0.5 < tp.width;
        // 문단이 한 줄 높이보다 낮으면 상자에 눌려 잘린 것이다(줄 수 계산이 1로 보여도)
        final clipped = para.size.height + 0.5 < tp.height;
        final pr = t.getRect(f);
        final br = t.getRect(find.ancestor(of: f, matching: find.byType(AnimatedContainer)).first);
        final cr = t.getRect(find.ancestor(of: f, matching: find.byType(GestureDetector)).first); // [DU394] 칸 = 그 칸의 GestureDetector
        final inBox = pr.left >= br.left - 0.5 && pr.right <= br.right + 0.5 && pr.top >= br.top - 0.5 && pr.bottom <= br.bottom + 0.5;
        final inCell = br.left >= cr.left - 0.5 && br.right <= cr.right + 0.5;
        out.add('$when $d 문단 ${para.size.width.toStringAsFixed(1)}×${para.size.height.toStringAsFixed(1)} · 한 줄 ${tp.width.toStringAsFixed(1)}×${tp.height.toStringAsFixed(1)} · 줄 $lines · 감김=$wrapped · 높이잘림=$clipped · '
            '문단 $pr · 상자 $br(${br.width.toStringAsFixed(1)}×${br.height.toStringAsFixed(1)}) · 칸 ${cr.left.toStringAsFixed(1)}–${cr.right.toStringAsFixed(1)} · 상자안=$inBox 칸안=$inCell 보임=${fullyIn(br)}');
        if (lines != 1 || wrapped || clipped || !inBox || !inCell || !fullyIn(br)) bad.add('$when $d');
      }
    }
    measure('미선택');
    await vqCapture(t, key, '${id}_strip', conditions: {
      'screen': 'UserHomeScreen(reads: ${normal ? 'H35-A 정상 fixture(표본 기준)' : '빈 fixture'}, clock ${sClock.toIso8601String()} — 고정 표본 ${_ymd394(sToday)})',
      'theme': 'RoleTheme.workerTheme', 'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'dpr': 1.0, 'textScaler': scale, 'inset': '0',
      'fonts': '_loadFonts 근사', 'scroll': '본문 실제 dragFrom -${dragDy.toInt()} × $k · off ${pos.pixels.toStringAsFixed(1)} (날짜 줄 9~12 상자 전부 viewport 안)',
      'measure': out.join(' | ')});
    if (selectDay != null) {
      final recv = find.ancestor(of: find.text(selectDay), matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onTap != null)).first;
      final rr = t.getRect(recv);
      taps++;
      await t.tapAt(rr.center);
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final cta = find.textContaining('일자리 0개 보기');
      out.add('선택 탭 $selectDay 칸 receiver $rr → CTA ${cta.evaluate().length}개');
      measure('선택');
      await vqCapture(t, key, '${id}_strip_selected', conditions: {
        'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'textScaler': scale, 'scroll': '같은 off · $selectDay 칸 실제 탭(선택 — 화면 상태만)',
        'measure': out.sublist(out.length - 5).join(' | ')});
    }
    out.add('overflows=${overflows.length} · 실패 항목=$bad');
    for (final l in out) {
      // ignore: avoid_print
      print('$id $l');
    }
    expect(bad, isEmpty, reason: '날짜 숫자 전문이 한 줄로 상자·칸 안에 보인다: $bad');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    // ── [DU394] 2부: 기준일 실제 7칸 ──
    final key2 = GlobalKey();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key2,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
            home: UserHomeScreen(reads: normal ? _reads(h35Apps(), legal: h35Legal) : _reads(const []), clock: () => _clock)),
      ),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final all2 = find.byType(Scrollable);
    final cands2 = [for (var i = 0; i < all2.evaluate().length; i++) all2.at(i)]
        .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
        .toList()
      ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
    final vp2 = t.getRect(cands2.first);
    final screen = Offset.zero & size;
    bool inR(Rect o, Rect r) => r.top >= o.top - 0.5 && r.bottom <= o.bottom + 0.5 && r.left >= o.left - 0.5 && r.right <= o.right + 0.5;
    void rec(String line) {
      // ignore: avoid_print
      print('$id $line');
    }

    const wdn = ['월', '화', '수', '목', '금', '토', '일'];
    final want = _stripDays394(_today);
    final active = normal ? {_day(3), _day(5)} : <DateTime>{};
    final wantLabels = [
      // [DU419 추종 · 판정59 S080 T1] 오늘 칸은 날짜 바로 뒤 '오늘' 한 번
      for (final d in want) ['${d.month}월 ${d.day}일 ${wdn[d.weekday - 1]}요일', if (d == _today) '오늘', if (active.contains(d)) '확정 근무 있음'].join(', ')
    ];
    final labelRe = RegExp(r'^\d{1,2}월 \d{1,2}일 [월화수목금토일]요일(, 오늘)?(, 확정 근무 있음)?(, 일자리 \d+개)?$');
    Finder cellsF() => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.button == true && labelRe.hasMatch(w.properties.label ?? ''),
        skipOffstage: false);
    Semantics semAt(int i) => t.widget<Semantics>(cellsF().at(i));
    Finder gdAt(int i) => find.descendant(of: cellsF().at(i), matching: find.byType(GestureDetector)).first;
    rec('기준일 ${_ymd394(_today)} clock ${_clock.toIso8601String()} 본문 $vp2 칸 ${cellsF().evaluate().length}개');
    expect(cellsF().evaluate().length, 7, reason: '$tok 기준일 날짜 줄 칸 7개');
    final labels = [for (var i = 0; i < 7; i++) semAt(i).properties.label ?? ''];
    final bnd = [for (var i = 1; i < 7; i++) if (want[i].month != want[i - 1].month) i];
    final lefts = [for (var i = 0; i < 7; i++) t.getRect(gdAt(i)).left];
    rec('7칸 ${labels.join(' / ')} · 월 경계 index $bnd · 칸 left $lefts');
    expect(labels, wantLabels, reason: '$tok 7칸 full date(순서 · 월 경계 · 확정 표기)');
    expect(labels.toSet().length, 7, reason: '$tok full date 고유');
    expect([for (var i = 1; i < 7; i++) lefts[i] > lefts[i - 1] + 0.5].every((x) => x), isTrue, reason: '$tok 칸 왼→오 = 날짜 순서');
    for (var i = 0; i < 7; i++) {
      final gd = gdAt(i);
      await t.ensureVisible(gd);
      moves++;
      for (var k = 0; k < 6; k++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final r = t.getRect(gd);
      final z = t.getSize(gd);
      final hs = find.ancestor(of: gd, matching: find.byType(Scrollable));
      final hz = [for (var j = 0; j < hs.evaluate().length; j++) hs.at(j)]
          .where((f) => t.state<ScrollableState>(f).position.axis == Axis.horizontal)
          .toList();
      final hv = hz.isEmpty ? null : t.getRect(hz.first);
      final inV = inR(vp2, r) && inR(screen, r) && (hv == null || inR(hv, r));
      final h = HitTestResult();
      WidgetsBinding.instance.hitTestInView(h, r.center, t.view.viewId);
      final ro = t.renderObject(gd);
      final hit = h.path.any((e) => e.target == ro);
      final gw = t.widget<GestureDetector>(gd);
      final sw = semAt(i);
      final on = active.contains(want[i]);
      rec('칸 $i ${labels[i]} local=${z.width}x${z.height} global=$r 가로=${hv ?? '-'} 안=$inV hit=$hit onTap=${gw.onTap != null} '
          'enabled=${sw.properties.enabled} selected=${sw.properties.selected}');
      expect(z.width >= 48 && z.height >= 48, isTrue, reason: '$tok 칸 $i receiver local ≥48 $z');
      expect(inV, isTrue, reason: '$tok 칸 $i ensureVisible 뒤 본문 · 가로 viewport · 화면 안 $r');
      expect(hit, isTrue, reason: '$tok 칸 $i 가운데 hit');
      expect(gw.onTap != null, on, reason: '$tok 칸 $i 활성 = 확정(공고 0)');
      expect(sw.properties.enabled, on, reason: '$tok 칸 $i 의미 enabled');
      expect(sw.properties.selected, isFalse, reason: '$tok 칸 $i 미선택');
    }
    await vqCapture(t, key2, '${id}_base', conditions: {
      'screen': 'UserHomeScreen(reads: ${normal ? 'H35-A 정상 fixture' : '빈 fixture'}, clock ${_clock.toIso8601String()} — 기준일 ${_ymd394(_today)})',
      'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'textScaler': scale, 'scroll': '칸마다 ensureVisible(마지막 칸 기준)',
      'measure': labels.join(' / ')});
    if (normal) {
      final target = _day(3);
      final row = _contract394[_ymd394(_today)];
      if (row != null) expect(_ymd394(target), row['select'], reason: '$tok 확정 선택일 = 계약표');
      final ix = want.indexOf(target);
      expect(ix, 3, reason: '$tok _day(3) = 7칸 중 4번째');
      final ctaText = '${target.month}월 ${target.day}일 일자리 0개 보기';
      final ctaRe = RegExp(r'^\d{1,2}월 \d{1,2}일 일자리 \d+개 보기$');
      Finder ctaF() => find.byWidgetPredicate((w) => w is Text && w.data != null && visibleText(w.data!) == ctaText, skipOffstage: false);
      Finder anyCta() => find.byWidgetPredicate((w) => w is Text && w.data != null && ctaRe.hasMatch(visibleText(w.data!)), skipOffstage: false);
      Future<void> tapCell(String what) async {
        final gd = gdAt(ix);
        await t.ensureVisible(gd);
        moves++;
        for (var k = 0; k < 6; k++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        final r = t.getRect(gd);
        expect(inR(vp2, r) && inR(screen, r), isTrue, reason: '$tok $what 칸 화면 안 $r');
        taps++;
        await t.tapAt(r.center);
        for (var k = 0; k < 6; k++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }

      final c0 = anyCta().evaluate().length;
      await tapCell('선택');
      final sel1 = [for (var i = 0; i < 7; i++) semAt(i).properties.selected == true];
      final c1 = ctaF().evaluate().length;
      final c1any = anyCta().evaluate().length;
      rec('선택 탭 ${labels[ix]} → selected=$sel1 · 정확 CTA "$ctaText" $c1 · 전체 CTA $c0→$c1any');
      await vqCapture(t, key2, '${id}_base_selected', conditions: {
        'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'textScaler': scale, 'scroll': '${labels[ix]} 칸 실제 탭(선택 — 화면 상태만)',
        'measure': 'selected=$sel1 cta=$c1'});
      await tapCell('해제');
      final sel2 = [for (var i = 0; i < 7; i++) semAt(i).properties.selected == true];
      final c2 = anyCta().evaluate().length;
      rec('해제 탭 → selected=$sel2 · 전체 CTA $c2 (0→1→0)');
      expect(c0, 0, reason: '$tok 탭 전 CTA 0');
      expect(sel1, [for (var i = 0; i < 7; i++) i == ix], reason: '$tok 선택 flag = 탭한 칸만');
      expect(c1, 1, reason: '$tok 정확 CTA "$ctaText" 1');
      expect(c1any, 1, reason: '$tok CTA 전체 1');
      expect(sel2.every((x) => !x), isTrue, reason: '$tok 다시 탭 → 선택 해제');
      expect(c2, 0, reason: '$tok 해제 뒤 CTA 0');
    }
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    _d394('D394 $tok done base=${_ymd394(_today)} taps=$taps moves=$moves');
  }

  testWidgets('H100-EB 빈 홈 320×640@2.0 — 날짜 줄 숫자 9~12 전문·상자/칸 경계 · 고정 표본 11-08 + 기준일 7칸 · D394DATE', (t) async {
    await stripCell(t, id: 'H100-EB_home_strip_empty_320x2', tok: 'H100-EB', normal: false, size: const Size(320, 640), scale: 2.0, dragDy: 150);
  });

  testWidgets('H100-AB 정상 홈 320×640@2.0 — 날짜 줄 숫자·확정 11 선택 · 고정 표본 11-08 + 기준일 7칸 · 확정 +3 선택 0→1→0 · D394DATE', (t) async {
    await stripCell(t, id: 'H100-AB_home_strip_normal_320x2', tok: 'H100-AB', normal: true, size: const Size(320, 640), scale: 2.0, dragDy: 150, selectDay: '11');
  });

  testWidgets('H100-EN 빈 홈 390×844@1.0 — 날짜 줄 숫자(N 기준) · 고정 표본 11-08 + 기준일 7칸 · D394DATE', (t) async {
    await stripCell(t, id: 'H100-EN_home_strip_empty_390x1', tok: 'H100-EN', normal: false, size: const Size(390, 844), scale: 1.0, dragDy: 200);
  });

  testWidgets('H100-AN 정상 홈 390×844@1.0 — 날짜 줄 숫자·확정 11 선택(N 기준) · 고정 표본 11-08 + 기준일 7칸 · 확정 +3 선택 0→1→0 · D394DATE', (t) async {
    await stripCell(t, id: 'H100-AN_home_strip_normal_390x1', tok: 'H100-AN', normal: true, size: const Size(390, 844), scale: 1.0, dragDy: 200, selectDay: '11');
  });

  // [DU1 구현100 셀B] 홈 표식 — 이번 주 안에 확정 근무 1건(_short('wk1', 1) = 11/7, 기존 LOCAL helper)인 홈.
  //   날짜 탐색 줄(확정 점 + `확정 근무` 범례)과 이번 주 일정(확정 점 + 범례 `확정`·`지원중`)을 같은 프레임 단위로 기록한다.
  //   점·범례 글자의 rect 를 따로 남겨 PNG 대비를 문자 / 비문자로 나눠 잰다. 탭·쓰기 없음(본문 drag 만).
  // [DU394] 메타는 실제 값(기준일 · _day(1) · clock)으로 적는다(원 '11/7 · 2026-11-06T01:00Z' 하드코딩 교정 — 원문은 orig 에 보존).
  //   이번 주 확정 +1 표식 = 표시 주 ∩ {_day(1)}: 그 칸의 successDark 점 1개(교집합이 비면 0) · 범례 점 2 — 계약표 h100w 와 대조.
  testWidgets('H100-W 홈 390×844@1.0 — 이번 주 확정 1건: 날짜 줄·이번 주 일정 표식·범례 · 기준일 주 교집합 · D394DATE', (t) async {
    const tok = 'H100-W';
    _d394(_start394(tok));
    _d394('D394 $tok contract=${_contractCheck394(tok)}');
    var moves = 0;
    final overflows = h35Overflows();
    final key = GlobalKey();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)), child: child!),
            home: UserHomeScreen(reads: _reads([_short('wk1', 1)]), clock: () => _clock)),
      ),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final all = find.byType(Scrollable);
    final cands = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
        .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
        .toList()
      ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
    final body = cands.first;
    final pos = t.state<ScrollableState>(body).position;
    final vp = t.getRect(body);
    bool fullyIn(Rect r) => r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5;
    final out = <String>['본문 $vp max=${pos.maxScrollExtent.toStringAsFixed(1)}'];
    // 표식 점: 지름 5~6 의 채운 원(Container circle) — 위치·색을 기록
    void dots(String when) {
      for (final e in find.byType(Container).evaluate()) {
        final c = e.widget as Container;
        final d = c.decoration;
        if (d is! BoxDecoration || d.shape != BoxShape.circle || d.color == null) continue;
        final r = t.getRect(find.byWidget(c));
        if (r.width < 4 || r.width > 8 || !fullyIn(r)) continue;
        out.add('$when 점 ${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)} ${r.width.toStringAsFixed(1)}px #${d.color!.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}');
      }
    }
    Rect? rectOf(Finder f) => f.evaluate().isEmpty ? null : t.getRect(f.first);
    out.add('초기 날짜 줄 `확정 근무` 범례 ${rectOf(find.text('확정 근무'))} · ${_day(1).day} ${rectOf(find.text('${_day(1).day}'))}');
    dots('초기');
    await vqCapture(t, key, 'H100-W_home_markers_390x1_top', conditions: {
      'screen': "UserHomeScreen(reads: _reads([_short('wk1', 1)]) — ${_day(1).month}/${_day(1).day} 확정 1건, clock ${_clock.toIso8601String()} · 기준일 ${_ymd394(_today)})",
      'theme': 'RoleTheme.workerTheme', 'viewport': '390x844', 'dpr': 1.0, 'textScaler': 1.0, 'inset': '0',
      'fonts': '_loadFonts 근사', 'scroll': 'off 0', 'measure': out.join(' | ')});
    // 이번 주 일정 범례(`지원중`)가 viewport 안에 들어올 때까지 실제 drag
    var k = 0;
    while (!(find.text('지원 중').evaluate().isNotEmpty && fullyIn(t.getRect(find.text('지원 중').first))) && k < 20) { // [DU383] UH123
      await t.dragFrom(Offset(vp.left + 4, vp.center.dy), const Offset(0, -200));
      moves++;
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      k++;
    }
    out.add('이번 주 일정 들이기 drag $k회 off=${pos.pixels.toStringAsFixed(1)} · 제목 ${rectOf(findVisibleText('이번 주 일정'))} · 범례 확정 ${rectOf(find.text('확정'))} · 지원 중 ${rectOf(find.text('지원 중'))}');
    dots('이번 주');
    // [DU394] 이번 주 칸별 점 — 확정 +1 표식 = 표시 주 ∩ {_day(1)}
    final week = _weekDays394(_today);
    final wd = _weekDots394(t, week, fullyIn);
    final wantDots = {for (var i = 0; i < 7; i++) if (week[i] == _day(1)) i: 0xFF166534};
    out.add('기준일 ${_ymd394(_today)} 이번 주 ${_ymd394(week.first)}–${_ymd394(week.last)} 칸별 점 ${wd.days} · 기대 $wantDots · 범례 점 ${wd.legend} · ${wd.desc}');
    await vqCapture(t, key, 'H100-W_home_markers_390x1_week', conditions: {
      'viewport': '390x844', 'textScaler': 1.0, 'scroll': '본문 실제 dragFrom -200 × $k · off ${pos.pixels.toStringAsFixed(1)}', 'measure': out.join(' | ')});
    for (final l in out) {
      // ignore: avoid_print
      print('H100-W $l');
    }
    expect(find.text('지원 중'), findsOneWidget, reason: '이번 주 일정 범례(UH123)');
    expect(wd.days, wantDots, reason: '$tok 이번 주 확정 +1 표식 = 표시 주 ∩ {_day(1)}');
    expect(wd.legend, 2, reason: '$tok 범례 점 확정 · 지원 중');
    final row = _contract394[_ymd394(_today)];
    if (row != null) expect([for (final i in wantDots.keys) _ymd394(week[i])], row['h100w'], reason: '$tok 기대 = 계약표 h100w');
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    _d394('D394 $tok done base=${_ymd394(_today)} taps=0 moves=$moves');
  });

  // [DU1 후속101 C101-3] 홈 이번 주 대기 표식 — H100-W 와 같은 조건(clock·workerTheme·_loadFonts 근사·DPR1·inset0)에
  //   기존 LOCAL helper 로 대기 2건을 더한다: 오늘(+0, brand 채운 오늘 상자 아래 점) · +2. 확정 +1 은 H100-W 와 같다.
  //   범례 `확정` 은 지원 현황의 같은 문자열이 아니라 **이번 주 범례 줄(`지원중` 과 같은 높이)** 의 것만 잡는다(감사101 정정).
  //   점 색·rect 는 출력 관찰, 단언은 범례 1쌍·이번 주 점 3개·overflow 0·예외 없음. 탭·쓰기 없음(본문 drag 만).
  // [DU394] 1부 = 고정 평일 표본 11-04(오늘 · +1 · +2 가 같은 주 — 원 3점 조판 단언 그대로 + 칸별 점) · 2부 = 기준일 주(계약표 h101:
  //   11-06 3점 · 11-08 1점 · 11-30 3점)를 칸별 점 색으로 대조한다(확정 #166534 · 대기 #E65100). 범례 점 2 · 넘침 0 · 예외 없음은 두 부 모두.
  testWidgets('H101-W 홈 390×844@1.0 — 이번 주 확정 1·대기 2: 이번 주 표식·범례 · 고정 평일 11-04 + 기준일 주 · D394DATE', (t) async {
    const tok = 'H101-W';
    _d394(_start394(tok));
    _d394('D394 $tok contract=${_contractCheck394(tok)}');
    var moves = 0;
    final overflows = h35Overflows();
    final sToday = _sampleWeek394;
    final sClock = _kstAt394(sToday);
    List<ApplicationModel> appsOf(DateTime? today) => [
          _short('wk1', 1, today: today),
          _short('wp0', 0, today: today).copyWith(status: AppStatus.pending),
          _short('wp2', 2, today: today).copyWith(status: AppStatus.pending),
        ];
    Map<int, int> wantOf(DateTime today) {
      final week = _weekDays394(today);
      final m = <int, int>{};
      for (var i = 0; i < 7; i++) {
        final d = week[i];
        if (d == today.add(const Duration(days: 1))) {
          m[i] = 0xFF166534;
        } else if (d == today || d == today.add(const Duration(days: 2))) {
          m[i] = 0xFFE65100;
        }
      }
      return m;
    }

    final key = GlobalKey();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final apps = appsOf(sToday);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)), child: child!),
            home: UserHomeScreen(reads: _reads(apps), clock: () => sClock)),
      ),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final all = find.byType(Scrollable);
    final cands = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
        .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
        .toList()
      ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
    final body = cands.first;
    final pos = t.state<ScrollableState>(body).position;
    final vp = t.getRect(body);
    bool fullyIn(Rect r) => r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5;
    final out = <String>['본문 $vp max=${pos.maxScrollExtent.toStringAsFixed(1)} · clock ${sClock.toIso8601String()} · today ${_ymd394(sToday)}(고정 평일 표본)'];
    var k = 0;
    while (!(find.text('지원 중').evaluate().isNotEmpty && fullyIn(t.getRect(find.text('지원 중').first))) && k < 20) { // [DU383] UH123
      await t.dragFrom(Offset(vp.left + 4, vp.center.dy), const Offset(0, -200));
      moves++;
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      k++;
    }
    final pend = t.getRect(find.text('지원 중')); // [DU383] UH123
    // 이번 주 범례 `확정` = `지원중` 과 같은 줄(top 차 ≤ 2)에 있는 것
    final legendConfirmed = [
      for (final e in find.text('확정').evaluate()) t.getRect(find.byWidget(e.widget))
    ].where((r) => (r.top - pend.top).abs() <= 2 && r.right <= pend.left).toList();
    final title = t.getRect(findVisibleText('이번 주 일정')); // [DU383] 섹션 제목 낱말 조판
    out.add('drag $k회 off=${pos.pixels.toStringAsFixed(1)} · 제목 $title · 범례 확정 $legendConfirmed · 지원중 $pend · `확정` 전체 ${find.text('확정').evaluate().length}개');
    // 표식 점: 지름 4~8 의 채운 원 Container — 이번 주 7일 줄 점(제목 아래 ~ 범례 위)과 범례 점(범례 줄 높이)을 나눠 적는다
    final weekDots = <String>[];
    final legendDots = <String>[];
    for (final e in find.byType(Container).evaluate()) {
      final c = e.widget as Container;
      final d = c.decoration;
      if (d is! BoxDecoration || d.shape != BoxShape.circle || d.color == null) continue;
      final r = t.getRect(find.byWidget(c));
      if (r.width < 4 || r.width > 8 || !fullyIn(r)) continue;
      final s = '${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)} ${r.width.toStringAsFixed(1)}px #${d.color!.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
      if (r.center.dy > pend.top - 4 && r.center.dy < pend.bottom + 4) {
        legendDots.add(s);
      } else if (r.top > title.bottom && r.bottom < pend.top) {
        if (d.color!.a > 0) weekDots.add(s);
      }
    }
    out.add('이번 주 점(투명 제외) ${weekDots.length}: ${weekDots.join(' ; ')}');
    out.add('범례 점 ${legendDots.length}: ${legendDots.join(' ; ')}');
    final sw = _weekDots394(t, _weekDays394(sToday), fullyIn); // [DU394] 표본 칸별 점
    out.add('표본 칸별 점 ${sw.days} · 기대 ${wantOf(sToday)} · ${sw.desc}');
    await vqCapture(t, key, 'H101-W_home_pending_390x1_week', conditions: {
      'screen': "UserHomeScreen(reads: _reads([_short('wk1',1) 확정, _short('wp0',0)·_short('wp2',2) 대기(copyWith)]) — 고정 평일 표본 ${_ymd394(sToday)}, clock ${sClock.toIso8601String()})",
      'theme': 'RoleTheme.workerTheme', 'viewport': '390x844', 'dpr': 1.0, 'textScaler': 1.0, 'inset': '0',
      'fonts': '_loadFonts 근사', 'scroll': '본문 실제 dragFrom -200 × $k · off ${pos.pixels.toStringAsFixed(1)}', 'measure': out.join(' | ')});
    for (final l in out) {
      // ignore: avoid_print
      print('H101-W $l');
    }
    expect(legendConfirmed.length, 1, reason: '이번 주 범례 `확정` 1개(지원 현황 `확정` 제외)');
    expect(legendDots.length, 2, reason: '범례 점 확정·지원중');
    expect(weekDots.length, 3, reason: '이번 주 점: 오늘 대기 · +1 확정 · +2 대기');
    expect(sw.days, wantOf(sToday), reason: '$tok 표본 칸별 점(수 대기 · 목 확정 · 금 대기)');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    // ── [DU394] 2부: 기준일 주 ──
    final key2 = GlobalKey();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key2,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)), child: child!),
            home: UserHomeScreen(reads: _reads(appsOf(null)), clock: () => _clock)),
      ),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final all2 = find.byType(Scrollable);
    final cands2 = [for (var i = 0; i < all2.evaluate().length; i++) all2.at(i)]
        .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
        .toList()
      ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
    final pos2 = t.state<ScrollableState>(cands2.first).position;
    final vp2 = t.getRect(cands2.first);
    bool fullyIn2(Rect r) => r.top >= vp2.top - 0.5 && r.bottom <= vp2.bottom + 0.5;
    var k2 = 0;
    while (!(find.text('지원 중').evaluate().isNotEmpty && fullyIn2(t.getRect(find.text('지원 중').first))) && k2 < 20) {
      await t.dragFrom(Offset(vp2.left + 4, vp2.center.dy), const Offset(0, -200));
      moves++;
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      k2++;
    }
    final week = _weekDays394(_today);
    final bw = _weekDots394(t, week, fullyIn2);
    final want = wantOf(_today);
    String kind(int c) => c == 0xFF166534 ? 'confirmed' : (c == 0xFFE65100 ? 'pending' : '#${c.toRadixString(16)}');
    final got = [for (final i in (bw.days.keys.toList()..sort())) [_ymd394(week[i]), kind(bw.days[i]!)]];
    // ignore: avoid_print
    print('H101-W 기준일 ${_ymd394(_today)} clock ${_clock.toIso8601String()} drag $k2회 off=${pos2.pixels.toStringAsFixed(1)} · '
        '이번 주 ${_ymd394(week.first)}–${_ymd394(week.last)} 칸별 점 $got · 기대 $want · 범례 점 ${bw.legend} · ${bw.desc}');
    await vqCapture(t, key2, 'H101-W_home_pending_390x1_week_base', conditions: {
      'screen': "UserHomeScreen(reads: 같은 세 지원(기준일 기준), clock ${_clock.toIso8601String()} — 기준일 ${_ymd394(_today)})",
      'theme': 'RoleTheme.workerTheme', 'viewport': '390x844', 'dpr': 1.0, 'textScaler': 1.0, 'inset': '0',
      'fonts': '_loadFonts 근사', 'scroll': '본문 실제 dragFrom -200 × $k2 · off ${pos2.pixels.toStringAsFixed(1)}', 'measure': '칸별 점 $got · 범례 점 ${bw.legend}'});
    expect(bw.days, want, reason: '$tok 기준일 주 칸별 점(확정 +1 · 대기 오늘 · +2 ∩ 표시 주)');
    expect(bw.legend, 2, reason: '$tok 기준일 범례 점 확정 · 지원 중');
    final row = _contract394[_ymd394(_today)];
    if (row != null) expect(got, row['h101'], reason: '$tok 기대 = 계약표 h101');
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    _d394('D394 $tok done base=${_ymd394(_today)} taps=0 moves=$moves');
  });

  testWidgets('VQ-01b 지원자 홈 — 빈 상태(확정·지원 없음)', (t) async {
    await _capture(t, UserHomeScreen(reads: _reads(const []), clock: () => _clock), 'VQ-01b_user_home_empty');
  });

  // ── [DU1 후속199] DU195 — S080 after 8사례(PNG 8 + sidecar 8). 순서 a-B→a-N→b-B→b-N→c-B→c-N→d-B→d-N, 사례별 독립 reset·첫 실패 즉시 종료.
  //   [DU199] 줄 측정 분리: 낱말 검사 = rawSpaceBreaks·insideX·말줄임 0. insideY·원 inside·yOver 는 raw/sidecar 기록(실제 글자·clip 은 PNG 판정).
  //   [DU200] receiver: 같은 Finder 의 local size 엄격 ≥48·local/global 각축 차 ≤1e-10, a 캡처 위치 = CTA 버튼 전체+제목, viewport·화면 안·중심 hit.
  //   [DU203] PHASE before/after 두 단계(같은 T), MaterialApp ko_KR 명시+resolved locale 단언·기록, C201-1 주간숫자·C201-2 월링크·C201-3 0수입제목 측정(성공 단언은 after 만), mask 기하 기록.
  // [DU394] DU195 본문을 함수로 — 원 8사례는 dateView 없이 그대로(본문 · 단언 · helper 동일), 날짜 시험 B/N 은 같은 helper 로
  //   a 선택 · 시트 월 일수 / c 현재 · 다음 달 일수 · 월 복귀 / b 주간 숫자 · 월 링크만 본다(c 범례 · 취소 · d 는 날짜 무관이라 반복 0).
  Future<void> du195Body(WidgetTester t, {String? dateView}) async {
    final phase = Platform.environment['DU1_VQ_PHASE'];
    expect(phase == 'before' || phase == 'after', isTrue, reason: 'DU1_VQ_PHASE 는 before 또는 after ($phase)');
    final isAfter = phase == 'after';
    var curLoc = '-';
    String ymd(DateTime d) => d.toIso8601String().substring(0, 10);
    // [DU394] 날짜 시험은 실제 값만 적는다(원 8사례 문구는 그대로)
    final dts = dateView == null
        ? 'fixture ${ymd(_today)} · 실제 KST ${ymd(FormatHelper.toKstDate(DateTime.now()))} · 탭 ${ymd(_day(1))} · 오늘 표시 8→9일, 8일=과거 일요일'
        : 'fixture ${ymd(_today)} · 실제 KST ${ymd(FormatHelper.toKstDate(DateTime.now()))} · 날짜 시험 $dateView · 선택 ${ymd(_day(1))}';
    // ignore: avoid_print
    print('DU199 dates $dts');
    final nl = String.fromCharCode(10);
    final base = FlutterError.onError;
    final done = <String>[];
    final ovf = <String>[];
    var taps = 0;
    var homeMoves = 0;
    var sheetMoves = 0;
    var curId = '-';
    var curStep = '-';
    void st(String s) {
      curStep = s;
      // ignore: avoid_print
      print('DU195 $curId start $s');
    }
    void check(String where) {
      final e = t.takeException();
      if (e != null) {
        // ignore: avoid_print
        print('DU195 ERROR $curId $where exception: $e');
        fail('$curId $where framework 예외: $e');
      }
      if (ovf.isNotEmpty) {
        // ignore: avoid_print
        print('DU195 ERROR $curId $where overflow: ${ovf.join(' | ')}');
        fail('$curId $where overflow ${ovf.length}');
      }
    }
    void guardTap(String what) {
      expect(taps + 1 <= 16, isTrue, reason: '$curId tap 상한 16 직전: $what');
      taps++;
    }
    void guardMove(String kind, String what) {
      expect(homeMoves + sheetMoves + 1 <= 24, isTrue, reason: '$curId scroll/jump 상한 24 직전: $what');
      if (kind == 'home') {
        homeMoves++;
      } else {
        sheetMoves++;
      }
    }
    Future<void> settle(int n) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }
    bool inRect(Rect outer, Rect r) =>
        r.top >= outer.top - 0.5 && r.bottom <= outer.bottom + 0.5 && r.left >= outer.left - 0.5 && r.right <= outer.right + 0.5;
    bool hitAt(Finder f, Offset p) {
      final h = HitTestResult();
      WidgetsBinding.instance.hitTestInView(h, p, t.view.viewId);
      final ro = t.renderObject(f);
      return h.path.any((e) => e.target == ro);
    }
    void one(Finder f, String what) => expect(f.evaluate().length, 1, reason: '$what — 정확히 1개');
    Finder recv(Finder txt, String what) {
      final r = find.ancestor(of: txt, matching: find.byWidgetPredicate((w) => (w is GestureDetector && w.onTap != null) || (w is InkWell && w.onTap != null)));
      expect(r.evaluate().isNotEmpty, isTrue, reason: '$what — 활성 receiver 있음');
      final f = r.first;
      expect(hitAt(f, t.getCenter(txt)), isTrue, reason: '$what — 글자 가운데가 receiver 에 hit');
      return f;
    }

    double contrast(Color a, Color b) {
      final x = a.computeLuminance();
      final y = b.computeLuminance();
      final hi = x > y ? x : y;
      final lo = x > y ? y : x;
      return (hi + 0.05) / (lo + 0.05);
    }

    Color fg(Finder txt) => t.renderObject<RenderParagraph>(txt).text.style!.color!;
    (Color, String) bg(Finder txt) {
      Color? c;
      var src = 'theme.scaffoldBackgroundColor';
      t.element(txt).visitAncestorElements((el) {
        final w = el.widget;
        Color? k;
        if (w is Material) k = w.color;
        if (w is ColoredBox) k = w.color;
        if (w is DecoratedBox && w.decoration is BoxDecoration) k = (w.decoration as BoxDecoration).color;
        if (w is Container) k = w.color ?? (w.decoration is BoxDecoration ? (w.decoration as BoxDecoration).color : null);
        if (k != null && k.a >= 0.999) {
          c = k;
          src = w.runtimeType.toString();
          return false;
        }
        return true;
      });
      return (c ?? Theme.of(t.element(txt)).scaffoldBackgroundColor, src);
    }

    List<String> homeTexts() => t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').toList();
    DateTime? calFocused(Finder cal) => (t.widget(cal) as dynamic).focusedDay as DateTime?;
    DateTime? calSelected(Finder cal) => (t.widget(cal) as dynamic).selectedDay as DateTime?;
    List<String?> calMonth(Finder cal) => find.descendant(of: cal, matching: find.textContaining('년')).evaluate().map((e) => (e.widget as Text).data).toList();

    Future<({GlobalKey key, ScrollPosition pos, Rect vp})> open(UserHomeReads reads, Size size, double scale) async {
      final key = GlobalKey();
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
        ],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.workerTheme,
              locale: const Locale('ko', 'KR'),
              supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
              localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
              home: UserHomeScreen(reads: reads, clock: () => _clock)),
        ),
      ));
      await settle(25);
      final loc = Localizations.localeOf(t.element(find.byType(UserHomeScreen)));
      curLoc = loc.toString();
      // ignore: avoid_print
      print('DU203 locale $curLoc');
      expect(loc, const Locale('ko', 'KR'), reason: 'resolved locale ko_KR ($curLoc)');
      final all = find.byType(Scrollable);
      final cands = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
          .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
          .toList()
        ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
      expect(cands, isNotEmpty, reason: '본문 세로 Scrollable');
      final body = cands.first;
      return (key: key, pos: t.state<ScrollableState>(body).position, vp: t.getRect(body));
    }

    // 홈 본문 이동만(시트 아님). 화면 안이면 이동 0.
    Future<void> center(ScrollPosition pos, Rect vp, Finder f) async {
      if (inRect(vp, t.getRect(f))) return;
      final r = t.getRect(f);
      var to = pos.pixels + r.center.dy - vp.center.dy;
      if (to < 0) to = 0;
      if (to > pos.maxScrollExtent) to = pos.maxScrollExtent;
      guardMove('home', '홈 본문 jumpTo');
      pos.jumpTo(to);
      await settle(6);
    }

    Future<void> reach(ScrollPosition pos, Rect vp, String text, String what) async {
      var k = 0;
      while (find.text(text, skipOffstage: false).evaluate().isEmpty && k < 3 && pos.pixels < pos.maxScrollExtent - 0.5) {
        var to = pos.pixels + vp.height * 0.9;
        if (to > pos.maxScrollExtent) to = pos.maxScrollExtent;
        guardMove('home', '홈 본문 jumpTo($what)');
        pos.jumpTo(to);
        k++;
        await settle(4);
      }
      final f = find.text(text, skipOffstage: false);
      one(f, what);
      await center(pos, vp, f);
      final g = find.text(text);
      one(g, '$what(화면 안)');
      expect(inRect(vp, t.getRect(g)), isTrue, reason: '$what 전문이 viewport 안');
    }

    // 열린 날짜 시트: 제목→BottomSheet→세로 Scrollable+AppCalendar
    ({Finder sheet, Finder scr, ScrollPosition pos, Finder cal}) sheetOf(String id) {
      final title = _dateSheetTitle(); // [DU383 r2] 홈 행동과 같은 글자 — BottomSheet 안의 것만
      one(title, '$id 시트 제목');
      final sheet = find.ancestor(of: title, matching: find.byType(BottomSheet));
      one(sheet, '$id BottomSheet');
      final sv = find.descendant(of: sheet, matching: find.byType(SingleChildScrollView));
      one(sv, '$id 시트 내용 세로 스크롤');
      final all = find.descendant(of: sv, matching: find.byType(Scrollable));
      final vs = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)].where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical).toList();
      expect(vs, isNotEmpty, reason: '$id 시트 세로 Scrollable');
      final cal = find.descendant(of: sheet, matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == 'AppCalendar'));
      one(cal, '$id AppCalendar');
      return (sheet: sheet, scr: vs.first, pos: t.state<ScrollableState>(vs.first).position, cal: cal);
    }

    Future<void> openSheet(String id, ({GlobalKey key, ScrollPosition pos, Rect vp}) o) async {
      final more = find.text('날짜 선택'); // [DU383 r2] UH089 — 시트 열기 전에는 홈 행동 하나(시트 제목은 열린 뒤)
      one(more, '$id 날짜 선택(홈 행동)');
      await center(o.pos, o.vp, more);
      recv(more, '$id 날짜 선택(홈 행동)');
      st('더보기 탭');
      guardTap('$id 날짜 선택(홈 행동)');
      await t.tapAt(t.getCenter(more));
      await settle(10);
      check('더보기 탭');
    }

    // 달력 안 시트 Scrollable 중앙에서 실제 위로 drag 1회(시트 jumpTo/ensureVisible 0, 제목 시작 대체 0).
    Future<Map<String, Object?>> centerDrag(String id, ({Finder sheet, Finder scr, ScrollPosition pos, Finder cal}) sh) async {
      final start = t.getCenter(sh.scr);
      final rCal = t.getRect(sh.cal);
      expect(rCal.contains(start), isTrue, reason: '$id drag 시작점이 달력 안 start=$start cal=$rCal');
      expect(hitAt(sh.cal, start) && hitAt(sh.scr, start), isTrue, reason: '$id 시작점 hit: 달력·시트 Scrollable');
      final p0 = sh.pos.pixels;
      final max0 = sh.pos.maxScrollExtent;
      final min0 = sh.pos.minScrollExtent;
      final f0 = calFocused(sh.cal);
      final s0 = calSelected(sh.cal);
      final m0 = calMonth(sh.cal);
      st('시트 중앙 drag');
      guardMove('sheet', '$id 시트 중앙 drag');
      await t.dragFrom(start, Offset(0, -(max0 + 200)));
      await settle(6);
      check('시트 중앙 drag');
      final p1 = sh.pos.pixels;
      expect(_dateSheetTitle(), findsOneWidget, reason: '$id drag 뒤 시트 유지');
      if (max0 > 0) expect(p1 > p0, isTrue, reason: '$id 양의 이동 $p0→$p1 (max $max0)');
      expect((p1 - sh.pos.maxScrollExtent).abs() < 0.5, isTrue, reason: '$id 끝 도달 $p1/${sh.pos.maxScrollExtent}');
      expect(calFocused(sh.cal), f0, reason: '$id 표시 기준일 불변');
      expect(calSelected(sh.cal), s0, reason: '$id 선택날짜 불변');
      expect(calMonth(sh.cal), m0, reason: '$id 표시월 불변');
      return {'drag_start': '$start', 'drag_in_calendar': true, 'drag_px': '${p0.toStringAsFixed(2)}->${p1.toStringAsFixed(2)}', 'drag_min_max': '${min0.toStringAsFixed(2)}/${max0.toStringAsFixed(2)}',
              'focused': '$f0', 'selected': '$s0', 'month': m0.join('/')};
    }
    Future<void> runCase(String id, Future<void> Function() body) async {
      expect(identical(FlutterError.onError, base), isTrue, reason: '$id 시작 handler = 시험 시작 handler(중첩 0)');
      final prev = FlutterError.onError;
      if (prev == null) fail('$id 원 FlutterError.onError 가 null');
      curId = id;
      ovf.clear();
      FlutterError.onError = (d) {
        final m = d.exceptionAsString();
        // ignore: avoid_print
        print('DU195 FLUTTER_ERROR id=$curId step=$curStep ${m.split(nl).first}');
        if (m.contains('overflowed')) ovf.add(m.split(nl).first);
        prev(d);
      };
      try {
        await body();
        check('case end');
        // ignore: avoid_print
        print('DU195 $id case done');
      } finally {
        FlutterError.onError = prev;
      }
    }
    // [DU203] mask 기하: 월 링크·0수입 제목·이번 주 일정 제목의 전역 rect(1개가 아니면 개수) — before 에서 mask 를 사전 고정하는 근거
    String geo() {
      String r(String s) {
        final f = find.byWidgetPredicate((w) => w is Text && w.data != null && w.data!.replaceAll(String.fromCharCode(0x2060), '').replaceAll(String.fromCharCode(0xA0), ' ') == s, skipOffstage: false);
        if (f.evaluate().length != 1) return 'n${f.evaluate().length}';
        final x = t.getRect(f);
        return '${x.left},${x.top},${x.right},${x.bottom}';
      }
      return 'link=${r('${_today.year}년 ${_today.month}월')} empty=${r('아직 표시할 수입 금액이 없어요')} week=${r('이번 주 일정')}';
    }
    // [DU383 r4] markDone: 캡처와 사례 완료를 나눈다(기본은 그대로 완료 처리)
    Future<void> shot(String id, GlobalKey key, Map<String, Object?> cond, {bool markDone = true}) async {
      st('캡처');
      check('캡처 전');
      await vqCapture(t, key, id, conditions: {'id': id, 'phase': phase, 'dates': dts, 'locale': curLoc, 'mask_geo': geo(), 'taps': taps, 'home_moves': homeMoves, 'sheet_moves': sheetMoves, ...cond});
      check('캡처 뒤');
      if (markDone) done.add(id);
      // ignore: avoid_print
      print('DU195 shot $id phase=$phase locale=$curLoc geo=${geo()} taps=$taps home=$homeMoves sheet=$sheetMoves ${cond.entries.map((e) => '${e.key}=${e.value}').join(' ')}');
    }
    // [DU200] receiver 원정밀도 기록(local·global·viewport·screen) → raw 출력, 같은 문자열을 sidecar 로
    String rx(String id, String what, Size z, Rect r, Rect vp, Size scr) {
      final s = '$what local=${z.width},${z.height} global=${r.left},${r.top},${r.right},${r.bottom} gw=${r.width} gh=${r.height} vp=${vp.left},${vp.top},${vp.right},${vp.bottom} screen=${scr.width},${scr.height}';
      // ignore: avoid_print
      print('DU200 $id receiver $s');
      return s;
    }
    const views = <(String, Size, double)>[('B', Size(320, 640), 2.0), ('N', Size(390, 844), 1.0)];
    // [DU195] 표시 검사: WJ·NBSP·ZWSP 를 뺀 글자로 찾고 줄·말줄임은 렌더로 잰다
    final wj = String.fromCharCode(0x2060);
    final nbsp = String.fromCharCode(0x00A0);
    final zw = String.fromCharCode(0x200B);
    String plainOf(String s) => s.replaceAll(wj, '').replaceAll(zw, '').replaceAll(nbsp, ' ');
    Finder findPlain(String s, {bool skipOffstage = true}) =>
        find.byWidgetPredicate((w) => w is Text && w.data != null && plainOf(w.data!) == s, skipOffstage: skipOffstage);
    // [DU195/199] 줄 측정: 글자별 첫 box(빈·폭0 skip) top 으로 줄·경계. 원 inside = 첫 box 가 paragraph 안, insideX/insideY 로 분리, yOver = 세로 최대 초과량.
    ({int lines, bool spaceBreaks, bool inside, bool insideX, bool insideY, double yOver}) layoutRp(RenderParagraph rp) {
      final s = rp.text.toPlainText();
      final tops = <double>[];
      var ok = true;
      var inside = true;
      var inX = true;
      var inY = true;
      var yOver = 0.0;
      double? prevTop;
      for (var i = 0; i < s.length; i++) {
        final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
        if (bx.isEmpty || (bx.first.right - bx.first.left).abs() < 0.01) continue;
        final b = bx.first;
        // [DU397r1 측정 수리안] 공백(U+0020 · U+00A0) 글자 상자는 가로 경계 판정에서 뺀다 — 줄 끝에 매달린 공백 상자가 문단 폭을 넘어도
        //   보이는 글자는 안이다(11-16 B CTA: index 17 공백 248.32–257.28 > 256, 보이는 글자 insideX 참). 줄 전환 · 세로 경계는 그대로.
        final blank = s[i] == ' ' || s[i] == String.fromCharCode(0xA0);
        final xOut = !blank && (b.right > rp.size.width + 0.5 || b.left < -0.5);
        final yOut = b.bottom > rp.size.height + 0.5 || b.top < -0.5;
        if (xOut || yOut) inside = false;
        if (xOut) inX = false;
        if (yOut) inY = false;
        if (-b.top > yOver) yOver = -b.top;
        if (b.bottom - rp.size.height > yOver) yOver = b.bottom - rp.size.height;
        if (prevTop == null || (b.top - prevTop).abs() > 1.0) {
          if (prevTop != null && (i == 0 || s[i - 1] != ' ')) ok = false;
          if (!tops.any((x) => (x - b.top).abs() <= 1.0)) tops.add(b.top);
        }
        prevTop = b.top;
      }
      return (lines: tops.length, spaceBreaks: ok, inside: inside, insideX: inX, insideY: inY, yOver: yOver);
    }
    // [DU383 r2 수리 1/3] semanticsLabel 이 붙은 Text(CP03 섹션 제목)는 첫 렌더 객체가 RenderSemanticsAnnotations 다 — 같은 Text 의 RichText 문단을 읽는다
    RenderParagraph paraOf(Finder f) =>
        t.renderObject<RenderParagraph>(find.descendant(of: f, matching: find.byType(RichText), matchRoot: true).first);
    ({int lines, bool spaceBreaks, bool ellipsis, String desc}) layoutOf(Finder f) {
      final rp = paraOf(f);
      final m = layoutRp(rp);
      final e = rp.didExceedMaxLines;
      return (lines: m.lines, spaceBreaks: m.spaceBreaks && m.insideX, ellipsis: e,
          desc: 'raw=${m.spaceBreaks} inX=${m.insideX} inY=${m.insideY} inside=${m.inside} ell=$e lines=${m.lines} yOver=${m.yOver}');
    }
    // [DU203] 측정 시점 본문 viewport(가장 큰 세로 Scrollable)
    Rect vpNow() {
      final all = find.byType(Scrollable);
      final c = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)].where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical).toList()
        ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
      return t.getRect(c.first);
    }
    // [DU203] 줄별 원문·줄 시작 경계 문자(첫 box top, layoutRp 와 같은 skip)
    String linesOf(Finder f) {
      final rp = paraOf(f);
      final s = rp.text.toPlainText();
      final ls = <String>[];
      final br = <String>[];
      var cur = StringBuffer();
      double? top;
      for (var i = 0; i < s.length; i++) {
        final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
        final ok = bx.isNotEmpty && (bx.first.right - bx.first.left).abs() >= 0.01;
        if (ok && top != null && (bx.first.top - top).abs() > 1.0) {
          ls.add(cur.toString());
          cur = StringBuffer();
          br.add('$i[prev ${(i > 0 ? s.codeUnitAt(i - 1) : 0).toRadixString(16)} cur ${s.codeUnitAt(i).toRadixString(16)}]');
        }
        if (ok) top = bx.first.top;
        cur.write(s[i]);
      }
      ls.add(cur.toString());
      return 'text=${plainOf(s)} lines=${ls.map(plainOf).join(' / ')} breaks=${br.join(',')}';
    }
    // [DU203 C201-1] 홈 주간 숫자 7개(시트와 별도): 한 줄·말줄임·가로/세로, 요구 높이·paragraph·상자 치수, 상자 안, 선택면, viewport
    // [DU394] days/fillDay 기본 = 원 11-08 주(2–8 · 오늘 8). 날짜 시험은 기준 주 월–일 · 오늘을 넘긴다. ordered = 칸 왼→오가 days 순서.
    ({String desc, bool ok, bool ordered}) weekDigits(Finder wk, {List<int> days = const [2, 3, 4, 5, 6, 7, 8], int fillDay = 8}) {
      final sec = find.ancestor(of: wk, matching: find.byWidgetPredicate((w) => w is Container && w.color == Colors.white && w.padding != null && w.child is Column)).first;
      final vp = vpNow();
      final parts = <String>[];
      final cells = <String>{};
      final fills = <int>[];
      var ok = true;
      final lefts = <double>[];
      for (final d in days) {
        final df = find.descendant(of: sec, matching: findVisibleText('$d')); // [DU397] 묶음 표시 → 보이는 글자 정확 원문
        one(df, '주간 숫자 $d');
        final rp = paraOf(df); // [DU397] semanticsLabel wrapper → 같은 Text 의 RichText 문단
        final m = layoutOf(df);
        final need = rp.getMinIntrinsicHeight(rp.size.width);
        final box = find.ancestor(of: df, matching: find.byType(Container)).first;
        final br = t.getRect(box);
        final bz = t.getSize(box);
        final tr = t.getRect(df);
        final dec = (t.widget(box) as Container).decoration;
        final fill = dec is BoxDecoration && dec.color != null && dec.color!.a > 0;
        final cr = t.getRect(find.ancestor(of: box, matching: find.byType(Column)).first); // [DU397] 칸 = 직접 cell Column
        cells.add('${cr.left},${cr.right}');
        lefts.add(cr.left);
        final inCell = br.left >= cr.left - 0.5 && br.right <= cr.right + 0.5;
        final txtIn = tr.left >= br.left - 0.5 && tr.right <= br.right + 0.5 && tr.top >= br.top - 0.5 && tr.bottom <= br.bottom + 0.5;
        final inVp = inRect(vp, br);
        if (fill) fills.add(d);
        final good = m.lines == 1 && !m.ellipsis && m.spaceBreaks && need <= rp.size.height + 0.5 && txtIn && inCell && inVp;
        if (!good) ok = false;
        parts.add('$d:${m.desc} need=$need ph=${rp.size.height} pw=${rp.size.width} box=${bz.width}x${bz.height}@${br.left},${br.top},${br.right},${br.bottom} txt=${tr.left},${tr.top},${tr.right},${tr.bottom} cell=${cr.left},${cr.right} inCell=$inCell txtIn=$txtIn fill=$fill inVp=$inVp good=$good');
      }
      if (cells.length != 7 || fills.length != 1 || fills.first != fillDay) ok = false;
      final ordered = lefts.length == 7 && [for (var i = 1; i < lefts.length; i++) lefts[i] > lefts[i - 1] + 0.5].every((x) => x);
      return (desc: 'vp=${vp.top},${vp.bottom} secTop=${t.getRect(sec).top} cells=${cells.length} fillDays=$fills ${parts.join(' ; ')}', ok: ok, ordered: ordered);
    }
    int clippedDays(Finder cal) {
      var bad = 0;
      for (var d = 1; d <= 30; d++) {
        final f = find.descendant(of: cal, matching: find.text('$d'));
        final n = f.evaluate().length;
        if (n == 0) {
          bad++;
          continue;
        }
        for (var i = 0; i < n; i++) {
          final rp = t.renderObject<RenderParagraph>(f.at(i));
          final m = layoutRp(rp);
          if (m.lines != 1 || !m.inside || rp.didExceedMaxLines) bad++;
        }
      }
      return bad;
    }
    Future<Finder> reachPlain(ScrollPosition pos, Rect vp, String text, String what) async {
      var k = 0;
      while (findPlain(text, skipOffstage: false).evaluate().isEmpty && k < 3 && pos.pixels < pos.maxScrollExtent - 0.5) {
        var to = pos.pixels + vp.height * 0.9;
        if (to > pos.maxScrollExtent) to = pos.maxScrollExtent;
        guardMove('home', '홈 본문 jumpTo($what)');
        pos.jumpTo(to);
        k++;
        await settle(4);
      }
      final f = findPlain(text, skipOffstage: false);
      one(f, what);
      await center(pos, vp, f);
      final g = findPlain(text);
      one(g, '$what(화면 안)');
      expect(inRect(vp, t.getRect(g)), isTrue, reason: '$what 전문이 viewport 안');
      return g;
    }
    // [DU195] 두 대상을 한 화면에 넣는 홈 이동 1회(필요할 때만)
    Future<void> fitBoth(ScrollPosition pos, Rect vp, Finder a, Finder b, String what) async {
      final ra = t.getRect(a);
      final rb = t.getRect(b);
      final top = (ra.top < rb.top ? ra.top : rb.top) + pos.pixels - vp.top - 8;
      final bottom = (ra.bottom > rb.bottom ? ra.bottom : rb.bottom) + pos.pixels - vp.top + 8;
      expect(bottom - top <= vp.height, isTrue, reason: '$what 한 화면에 함께 들어갈 높이 ${bottom - top} ≤ ${vp.height}');
      var to = top;
      if (to < 0) to = 0;
      if (to > pos.maxScrollExtent) to = pos.maxScrollExtent;
      if ((to - pos.pixels).abs() > 0.5) {
        guardMove('home', '$what 캡처 위치 jumpTo');
        pos.jumpTo(to);
        await settle(6);
      }
      expect(inRect(vp, t.getRect(a)) && inRect(vp, t.getRect(b)), isTrue, reason: '$what 둘 다 화면 안');
    }
    // [DU196] 근무 요약 전문·강조 span(3회·0시간 #21242D, 100% #166534, w800)
    ({bool ok, String desc}) summarySpans(RenderParagraph rp) {
      final root = rp.text;
      final kids = root is TextSpan ? root.children : null;
      final top = (kids != null && kids.isNotEmpty) ? kids.first : null;
      if (top is! TextSpan || top.children == null) return (ok: false, desc: 'span 구조 없음');
      const want = <String, Color>{'3회': Color(0xFF21242D), '100%': Color(0xFF166534), '0시간': Color(0xFF21242D)};
      final parts = <String>[];
      final seen = <String>{};
      var ok = true;
      for (final c in top.children!) {
        if (c is! TextSpan) continue;
        final txt = c.text ?? '';
        final st = c.style;
        parts.add('$txt|${st?.fontWeight}|${st?.color}');
        if (want.containsKey(txt)) {
          seen.add(txt);
          if (st == null || st.fontWeight != FontWeight.w800 || st.color != want[txt]) ok = false;
        }
      }
      final plain = rp.text.toPlainText();
      final exact = plain == '근무 완료 3회  ·  출근율 100%  ·  총 0시간';
      return (ok: ok && exact && seen.length == 3, desc: 'exact=$exact seen=${seen.length} ${parts.join(' / ')}');
    }
    // ── [DU394] 날짜 (b) 두 시험(B/N) — 원 8사례 helper(open · openSheet · sheetOf · centerDrag · recv · one · layoutRp · layoutOf · linesOf ·
    //   weekDigits · reachPlain · fitBoth · center · shot · runCase · guard*)를 그대로 쓴다. c 범례 · 취소 · d 는 날짜와 무관해 반복하지 않는다.
    if (dateView != null) {
      final tok = 'DU195-DATE-$dateView';
      _d394(_start394(tok));
      _d394('D394 $tok contract=${_contractCheck394(tok)}');
      expect(isAfter, isTrue, reason: '$tok 는 after 단계에서만(C201 단언 활성)');
      final (v, size, scale) = views.firstWhere((x) => x.$1 == dateView);
      final months = <String>[];
      String monthTitle(DateTime m) => '${m.year}년 ${m.month}월';
      int monthLen(DateTime m) => DateTime.utc(m.year, m.month + 1, 0).day;
      // 시트 달력 한 달: 표시 기준월 · 머리(보이는 글자) · 1..말일 각 정확히 1개 · 한 줄 · 문단 안 · 말일+1..31 없음
      void monthOk(Finder cal, DateTime m, String what) {
        final f = calFocused(cal);
        expect(f != null && f.year == m.year && f.month == m.month, isTrue, reason: '$tok $what 표시 기준월 $f = ${monthTitle(m)}');
        final hd = calMonth(cal).map((x) => plainOf(x ?? '')).toList();
        expect(hd, [monthTitle(m)], reason: '$tok $what 달력 머리');
        final n = monthLen(m);
        final badDays = <int>[];
        for (var d = 1; d <= 31; d++) {
          final df = find.descendant(of: cal, matching: find.text('$d'));
          final c = df.evaluate().length;
          if (d > n) {
            if (c != 0) badDays.add(d);
            continue;
          }
          if (c != 1) {
            badDays.add(d);
            continue;
          }
          final rp = t.renderObject<RenderParagraph>(df);
          final mm = layoutRp(rp);
          if (mm.lines != 1 || !mm.inside || rp.didExceedMaxLines) badDays.add(d);
        }
        expect(badDays, isEmpty, reason: '$tok $what ${monthTitle(m)} 날짜 1–$n 각 1개 · 한 줄 · 문단 안, ${n + 1}–31 없음');
        months.add('$what=${monthTitle(m)}/$n일');
      }

      // a + c — 빈 fixture: 시트 현재 달 → (B: 달력 안 중앙 drag) → 다음 달 → 원래 달(선택 불변) → (선택일이 다음 달이면 그 달로) →
      //   _day(1) 실제 탭 → 닫힘 → 정확 CTA → 재열기: 선택값 · 표시월 → 닫기 → 캡처
      await runCase('$tok-a', () async {
        st('open');
        final o = await open(_reads(const []), size, scale);
        check('open');
        await openSheet(tok, o);
        final sh = sheetOf(tok);
        monthOk(sh.cal, _today, '현재 달');
        final cond = <String, Object?>{'dates': '기준일 ${_ymd394(_today)} · 선택 ${_ymd394(_day(1))}', 'sheet_extent': sh.pos.maxScrollExtent.toStringAsFixed(2)};
        if (v == 'B') cond.addAll(await centerDrag(tok, sh));
        final s0 = calSelected(sh.cal);
        Future<void> swipe(String what, double dir) async {
          final rCal = t.getRect(sh.cal);
          final vis = rCal.intersect(t.getRect(sh.scr)).intersect(Offset.zero & size);
          final from = vis.center;
          expect(hitAt(sh.cal, from) && hitAt(sh.scr, from), isTrue, reason: '$tok $what swipe 시작점 달력 · 시트 hit $from');
          st('수평 swipe $what');
          guardMove('sheet', '$tok 달력 수평 swipe $what');
          await t.dragFrom(from, Offset(dir * rCal.width * 0.6, 0));
          await settle(10);
          check('수평 swipe $what');
          expect(_dateSheetTitle(), findsOneWidget, reason: '$tok swipe $what 뒤 시트 유지');
          expect(calSelected(sh.cal), s0, reason: '$tok swipe $what 선택날짜 불변');
        }

        await swipe('다음 달', -1);
        monthOk(sh.cal, DateTime.utc(_today.year, _today.month + 1, 1), '다음 달');
        await swipe('원래 달', 1);
        monthOk(sh.cal, _today, '원래 달 복귀');
        final target = _day(1);
        if (target.month != _today.month) {
          await swipe('선택일 달', -1);
          monthOk(sh.cal, target, '선택일 달');
        }
        final d1 = '${target.day}';
        final day = find.descendant(of: sh.sheet, matching: find.text(d1));
        one(day, '$tok 시트 달력 날짜 $d1');
        expect(inRect(t.getRect(sh.scr), t.getRect(day)) && inRect(Offset.zero & size, t.getRect(day)), isTrue, reason: '$tok 날짜 칸이 시트 보이는 영역 안');
        recv(day, '$tok 시트 달력 날짜 $d1');
        st('날짜 탭');
        guardTap('$tok 날짜 $d1');
        await t.tapAt(t.getCenter(day));
        await settle(10);
        check('날짜 탭');
        expect(_dateSheetTitle(), findsNothing, reason: '$tok 날짜 선택 뒤 시트 닫힘');
        final ctaText = '${target.month}월 ${target.day}일 일자리 0개 보기';
        final cta = findPlain(ctaText, skipOffstage: false);
        one(cta, '$tok CTA $ctaText');
        final cl = layoutOf(cta);
        expect(cl.spaceBreaks && !cl.ellipsis, isTrue, reason: '$tok CTA 낱말 사이에서만 줄바꿈 · 말줄임 0 lines=${cl.lines}');
        st('선택 결과 확인(시트 재열기)');
        await openSheet(tok, o);
        final sh2 = sheetOf(tok);
        final sel = calSelected(sh2.cal);
        expect(sel != null && sel.year == target.year && sel.month == target.month && sel.day == target.day, isTrue, reason: '$tok 실제 선택 결과 $sel = $target');
        monthOk(sh2.cal, target, '재열기 표시월');
        await Navigator.of(t.element(_dateSheetTitle())).maybePop();
        await settle(10);
        check('선택 확인 시트 닫기');
        expect(_dateSheetTitle(), findsNothing, reason: '$tok 선택 확인 시트 닫힘');
        cond.addAll({'months': months.join(' · '), 'selected_after': '$sel', 'cta': ctaText, 'cta_m': cl.desc});
        await shot('${tok}_a', o.key, cond, markDone: false);
        await t.pumpWidget(const SizedBox.shrink());
        check('정리');
      });
      // b — h35Apps: 이번 주 제목 · 범례를 한 화면에 → 주간 숫자 = 기준 주 월–일(순서 · 채움 1 = 오늘) → 월 링크 도달 · receiver 1 · hit · C201-2
      await runCase('$tok-b', () async {
        st('open');
        final o = await open(_reads(h35Apps()), size, scale);
        check('open');
        final wk = await reachPlain(o.pos, o.vp, '이번 주 일정', '$tok 이번 주 일정 제목');
        check('제목 도달');
        final sec = find
            .ancestor(of: wk, matching: find.byWidgetPredicate((w) => w is Container && w.color == Colors.white && w.padding != null && w.child is Column))
            .first;
        final legend = find.descendant(of: sec, matching: find.text('지원 중'));
        one(legend, '$tok 이번 주 범례 지원 중');
        expect(find.descendant(of: sec, matching: find.byType(Scrollable)), findsNothing, reason: '$tok [DU397] 기본 B/N 이번 주 7칸 균등(가로 스크롤 0)');
        await fitBoth(o.pos, o.vp, findPlain('이번 주 일정', skipOffstage: false), legend, '$tok 이번 주 제목 · 범례');
        check('주간 위치');
        final week = _weekDays394(_today);
        final wd = weekDigits(findPlain('이번 주 일정', skipOffstage: false), days: [for (final d in week) d.day], fillDay: _today.day);
        // ignore: avoid_print
        print('DU394 $tok week ${_ymd394(week.first)}–${_ymd394(week.last)} ordered=${wd.ordered} ${wd.desc}');
        expect(wd.ok, isTrue, reason: '$tok 주간 숫자 = 기준 주 월–일 · 한 줄 · 상자 안 · 채움 1개 = 오늘 ${wd.desc}');
        expect(wd.ordered, isTrue, reason: '$tok 주간 숫자 왼→오 = 월–일 순서');
        final wl = layoutOf(findPlain('이번 주 일정', skipOffstage: false));
        expect(wl.spaceBreaks && !wl.ellipsis, isTrue, reason: '$tok 이번 주 일정 제목 낱말 사이에서만 줄바꿈 lines=${wl.lines}');
        await shot('${tok}_b_week', o.key, {
          'dates': '기준일 ${_ymd394(_today)} · 주 ${_ymd394(week.first)}–${_ymd394(week.last)}', 'week_digits': wd.desc, 'ordered': wd.ordered
        }, markDone: false);
        final mlv = findPlain(monthTitle(_today), skipOffstage: false);
        one(mlv, '$tok 수입 현황 월 링크');
        final mt = findPlain('수입 현황', skipOffstage: false);
        one(mt, '$tok 수입 현황 제목');
        st('월 링크 도달');
        await center(o.pos, o.vp, mlv);
        final mlr = t.getRect(mlv);
        final recvs = find.ancestor(of: mlv, matching: find.byWidgetPredicate((w) => (w is GestureDetector && w.onTap != null) || (w is InkWell && w.onTap != null)));
        final rcvR = recvs.evaluate().isEmpty ? Rect.zero : t.getRect(recvs.first);
        // ignore: avoid_print
        print('DU394 $tok 월 링크 위치 offset=${o.pos.pixels.toStringAsFixed(1)} text=$mlr receiver=$rcvR receivers=${recvs.evaluate().length} vp=${o.vp} screen=$size');
        expect(recvs.evaluate().length, 1, reason: '$tok 월 링크 활성 receiver 1개');
        expect(inRect(o.vp, mlr) && inRect(Offset.zero & size, mlr) && inRect(o.vp, rcvR) && inRect(Offset.zero & size, rcvR), isTrue,
            reason: '$tok 월 링크 글자 · receiver 가 본문 표시 영역 · 화면 안 $mlr $rcvR');
        recv(mlv, '$tok 월 링크');
        final mlm = layoutOf(mlv);
        final mlx = linesOf(mlv);
        final mo = t.getRect(mlv).intersect(t.getRect(mt));
        final mOver = mo.width > 0.5 && mo.height > 0.5;
        expect(mlm.spaceBreaks && !mlm.ellipsis && !mOver, isTrue, reason: '$tok [C201-2] 월 링크 숫자 · 월 단위 보존 · 말줄임 0 · 제목 비겹침 $mlx');
        await shot('${tok}_b_month', o.key, {'month_text': '$mlr', 'month_receiver': '$rcvR', 'month_m': '${mlm.desc} $mlx overlapTitle=$mOver'}, markDone: false);
        await t.pumpWidget(const SizedBox.shrink());
        check('정리');
      });
      expect(identical(FlutterError.onError, base), isTrue, reason: '$tok 끝 handler = 시험 시작 handler');
      _d394('D394 $tok done base=${_ymd394(_today)} taps=$taps moves=${homeMoves + sheetMoves}');
      return;
    }
    // a — 빈 fixture. 더보기 탭 → 시트 날짜 1–30 → (B: 달력 안 중앙 drag) → _day(1) 탭 → 닫힘 → 공고0·CTA·제목 줄바꿈 → 재열기로 선택값 확인 → 캡처
    for (final (v, size, scale) in views) {
      final id = 'DU195-a-$v';
      await runCase(id, () async {
        st('open');
        final o = await open(_reads(const []), size, scale);
        check('open');
        await openSheet(id, o);
        final sh = sheetOf(id);
        final ext0 = sh.pos.maxScrollExtent;
        final cd = clippedDays(sh.cal);
        expect(cd, 0, reason: '$id 시트 날짜 1–30 전문(한 줄) 잘림 $cd');
        final cond = <String, Object?>{'sheet_extent': ext0.toStringAsFixed(2), 'clipped_days': cd};
        if (v == 'B') cond.addAll(await centerDrag(id, sh));
        final d1 = '${_day(1).day}';
        final day = find.descendant(of: sh.sheet, matching: find.text(d1));
        one(day, '$id 시트 달력 날짜 $d1');
        expect(inRect(t.getRect(sh.scr), t.getRect(day)) && inRect(Offset.zero & size, t.getRect(day)), isTrue, reason: '$id 날짜 칸이 시트 보이는 영역 안(보조 이동 0)');
        recv(day, '$id 시트 달력 날짜 $d1');
        st('날짜 탭');
        guardTap('$id 날짜 $d1');
        await t.tapAt(t.getCenter(day));
        await settle(10);
        check('날짜 탭');
        expect(_dateSheetTitle(), findsNothing, reason: '$id 날짜 선택 뒤 시트 닫힘');
        await reach(o.pos, o.vp, '이 날짜에 표시할 일자리가 없어요', '$id 날짜0 문구'); // [DU383 r2] UH149
        check('날짜0 문구 도달');
        final msg = find.text('이 날짜에 표시할 일자리가 없어요');
        final (b0, bs) = bg(msg);
        final cr = contrast(fg(msg), b0);
        expect(cr >= 4.5, isTrue, reason: '$id 날짜0 문구 대비 ${cr.toStringAsFixed(2)} ≥ 4.5');
        final ctaText = '${_day(1).month}월 ${_day(1).day}일 일자리 0개 보기';
        final cta = findPlain(ctaText, skipOffstage: false);
        one(cta, '$id CTA $ctaText');
        final cl = layoutOf(cta);
        expect(cl.spaceBreaks && !cl.ellipsis, isTrue, reason: '$id CTA 낱말 사이에서만 줄바꿈·말줄임 0 lines=${cl.lines}');
        final ttl = findPlain('내 지원 현황', skipOffstage: false);
        one(ttl, '$id 지원 현황 제목');
        final tl = layoutOf(ttl);
        expect(tl.spaceBreaks && !tl.ellipsis, isTrue, reason: '$id 지원 현황 제목 낱말 사이에서만 줄바꿈 lines=${tl.lines}');
        st('선택 결과 확인(시트 재열기)');
        await openSheet(id, o);
        final sh2 = sheetOf(id);
        final sel = calSelected(sh2.cal);
        final want = _day(1);
        expect(sel != null && sel.year == want.year && sel.month == want.month && sel.day == want.day, isTrue, reason: '$id 실제 선택 결과 $sel = $want');
        await Navigator.of(t.element(_dateSheetTitle())).maybePop();
        await settle(10);
        check('선택 확인 시트 닫기');
        expect(_dateSheetTitle(), findsNothing, reason: '$id 선택 확인 시트 닫힘');
        final btn = find.ancestor(of: findPlain(ctaText, skipOffstage: false), matching: find.byType(ElevatedButton)).first;
        // [DU383 r3] (a′) CTA 위치 — 버튼 전체를 홈 본문 표시 영역에(실제 스크롤, 화면 안이면 이동 0)
        await center(o.pos, o.vp, btn);
        // ignore: avoid_print
        print('DU383r3 $id CTA 위치 offset=${o.pos.pixels.toStringAsFixed(1)} btn=${t.getRect(btn)} vp=${o.vp}');
        final br = t.getRect(btn);
        final bz = t.getSize(btn);
        final rcv = rx(id, 'CTA', bz, br, vpNow(), size);
        expect(inRect(o.vp, br) && inRect(Offset.zero & size, br), isTrue, reason: '$id CTA receiver 본문 viewport·화면 안 $rcv');
        recv(findPlain(ctaText), '$id CTA');
        expect(bz.width >= 48 && bz.height >= 48, isTrue, reason: '$id CTA receiver local ≥ 48 $rcv');
        expect((bz.width - br.width).abs() <= 1e-10 && (bz.height - br.height).abs() <= 1e-10, isTrue, reason: '$id CTA local/global 차 ≤ 1e-10 $rcv');
        final inBtn = find.descendant(of: btn, matching: find.byType(Text)).evaluate().toSet();
        final allTa = find.byType(Text);
        var cov = 0;
        for (var i = 0; i < allTa.evaluate().length; i++) {
          if (inBtn.contains(allTa.at(i).evaluate().first)) continue;
          final x = br.intersect(t.getRect(allTa.at(i)));
          if (x.width > 0.5 && x.height > 0.5) cov++;
        }
        expect(cov, 0, reason: '$id CTA 와 이웃 글자 겹침 0');
        cond.addAll({'cta_receiver': rcv, 'cta_neighbor_overlap': cov});
        // [DU383 r3] (a′) CTA 위치 캡처(사례 완료 목록 done 에는 넣지 않는다) → 제목 위치로 실제 스크롤
        check('CTA 위치 캡처 전');
        await vqCapture(t, o.key, '${id}_cta', conditions: {'id': '${id}_cta', 'phase': phase, 'dates': dts, 'locale': curLoc,
            'offset': o.pos.pixels.toStringAsFixed(1), 'cta_rect': '$br', 'cta_receiver': rcv, 'cta_neighbor_overlap': cov});
        check('CTA 위치 캡처 뒤');
        final ttlAt = findPlain('내 지원 현황', skipOffstage: false);
        await center(o.pos, o.vp, ttlAt);
        final ttr = t.getRect(ttlAt);
        // ignore: avoid_print
        print('DU383r3 $id 제목 위치 offset=${o.pos.pixels.toStringAsFixed(1)} title=$ttr vp=${o.vp}');
        expect(inRect(o.vp, ttr) && inRect(Offset.zero & size, ttr), isTrue, reason: '$id 지원 현황 제목 전문이 본문 표시 영역 안 $ttr');
        cond.addAll({'title_rect': '$ttr', 'title_offset': o.pos.pixels.toStringAsFixed(1)});
        cond.addAll({'day_target': d1, 'selected_after': '$sel', 'cta': ctaText, 'cta_lines': cl.lines, 'title_lines': tl.lines, 'cta_m': cl.desc, 'title_m': tl.desc, 'msg_fg': fg(msg).toString(), 'msg_bg': '$b0 ($bs)', 'msg_contrast': cr.toStringAsFixed(2)});
        await shot(id, o.key, cond);
        await t.pumpWidget(const SizedBox.shrink());
        check('정리');
      });
    }
    // b — h35Apps 지원 행 전문·배지·겹침·대비, '이번 주 일정' 줄바꿈(행동 0)
    for (final (v, size, scale) in views) {
      final id = 'DU195-b-$v';
      await runCase(id, () async {
        st('open');
        final o = await open(_reads(h35Apps()), size, scale);
        check('open');
        final rows = ['${FormatHelper.formatDateCompact(_day(3))}  09:00 – 18:00', '${FormatHelper.formatDateCompact(_day(5))}  13:00 – 22:00'];
        String? pick;
        var k = 0;
        while (pick == null) {
          for (final s in rows) {
            if (findPlain(s, skipOffstage: false).evaluate().length == 1) {
              pick = s;
              break;
            }
          }
          if (pick != null || k >= 3 || o.pos.pixels >= o.pos.maxScrollExtent - 0.5) break;
          var to = o.pos.pixels + o.vp.height * 0.9;
          if (to > o.pos.maxScrollExtent) to = o.pos.maxScrollExtent;
          guardMove('home', '$id 행 찾기 jumpTo');
          o.pos.jumpTo(to);
          k++;
          await settle(4);
        }
        check('행 찾기');
        expect(pick, isNotNull, reason: '$id 지원 행 날짜·시간 Text');
        final rf = await reachPlain(o.pos, o.vp, pick!, '$id 지원 행');
        check('행 도달');
        final rl = layoutOf(rf);
        expect(!rl.ellipsis && rl.spaceBreaks, isTrue, reason: '$id 지원 행 날짜·시간 전문(말줄임 0·낱말 사이 줄바꿈) lines=${rl.lines}');
        final rr = t.getRect(rf);
        final (b0, bs) = bg(rf);
        final cr = contrast(fg(rf), b0);
        expect(cr >= 4.5, isTrue, reason: '$id 지원 행 대비 ${cr.toStringAsFixed(2)} ≥ 4.5');
        final me = t.element(rf);
        final allT = find.byType(Text);
        var overl = 0;
        for (var i = 0; i < allT.evaluate().length; i++) {
          final f = allT.at(i);
          if (t.element(f) == me) continue;
          final x = rr.intersect(t.getRect(f));
          if (x.width > 0.5 && x.height > 0.5) overl++;
        }
        expect(overl, 0, reason: '$id 지원 행 글자와 다른 글자 겹침 0');
        final rowBox = find.ancestor(of: rf, matching: find.byType(Row)).first;
        final badge = find.descendant(of: rowBox, matching: find.text('확정'));
        one(badge, '$id 확정 배지');
        expect(inRect(o.vp, t.getRect(badge)), isTrue, reason: '$id 확정 배지 화면 안');
        final wk = findPlain('이번 주 일정', skipOffstage: false);
        one(wk, '$id 이번 주 일정 제목');
        final wl = layoutOf(wk);
        expect(wl.spaceBreaks && !wl.ellipsis, isTrue, reason: '$id 이번 주 일정 제목 낱말 사이에서만 줄바꿈 lines=${wl.lines}');
        await fitBoth(o.pos, o.vp, findPlain(pick, skipOffstage: false), findPlain('이번 주 일정', skipOffstage: false), '$id 지원 행·이번 주 일정 제목');
        expect(inRect(o.vp, t.getRect(badge)), isTrue, reason: '$id 확정 배지 캡처 위치 화면 안');
        final wd = weekDigits(wk);
        final ml = findPlain('${_today.year}년 ${_today.month}월', skipOffstage: false);
        one(ml, '$id 수입 현황 월 링크');
        final mlm = layoutOf(ml);
        final mlx = linesOf(ml);
        final mt = findPlain('수입 현황', skipOffstage: false);
        one(mt, '$id 수입 현황 제목');
        final mo = t.getRect(ml).intersect(t.getRect(mt));
        final mOver = mo.width > 0.5 && mo.height > 0.5;
        // ignore: avoid_print
        print('DU203 $id week ${wd.desc}');
        // ignore: avoid_print
        print('DU203 $id monthlink ${mlm.desc} $mlx overlapTitle=$mOver');
        if (isAfter) {
          expect(wd.ok, isTrue, reason: '$id [C201-1] 주간 숫자 7개 한 줄·말줄임 0·요구높이 수용·상자 안 ${wd.desc}');
          expect(mlm.spaceBreaks && !mlm.ellipsis && !mOver, isTrue, reason: '$id [C201-2] 월 링크 숫자·월 단위 보존·말줄임 0·제목 비겹침 $mlx');
        }
        // [DU383 r4] (a″) b 원 위치 캡처 — 완료 처리는 월 링크 확인 뒤 한 번
        await shot(id, o.key, {'row': pick, 'row_lines': rl.lines, 'row_rect': rr.toString(), 'badge': '확정 ${t.getRect(badge)}', 'row_contrast': cr.toStringAsFixed(2), 'overlap': overl, 'week_title_lines': wl.lines, 'row_m': rl.desc, 'week_m': wl.desc, 'week_digits': wd.desc, 'month_link': '${mlm.desc} $mlx overlapTitle=$mOver'}, markDone: false);
        if (isAfter) {
          // 월 링크 위치 — 같은 본문에서 실제 스크롤로 도달
          final mlv = findPlain('${_today.year}년 ${_today.month}월', skipOffstage: false);
          st('월 링크 도달');
          await center(o.pos, o.vp, mlv);
          final mlr = t.getRect(mlv);
          final recvs = find.ancestor(of: mlv, matching: find.byWidgetPredicate((w) => (w is GestureDetector && w.onTap != null) || (w is InkWell && w.onTap != null)));
          final rcvR = recvs.evaluate().isEmpty ? Rect.zero : t.getRect(recvs.first);
          // ignore: avoid_print
          print('DU383r4 $id 월 링크 위치 offset=${o.pos.pixels.toStringAsFixed(1)} text=$mlr receiver=$rcvR receivers=${recvs.evaluate().length} vp=${o.vp} screen=$size');
          expect(recvs.evaluate().length, 1, reason: '$id 월 링크 활성 receiver 1개');
          expect(inRect(o.vp, mlr) && inRect(Offset.zero & size, mlr) && inRect(o.vp, rcvR) && inRect(Offset.zero & size, rcvR), isTrue,
              reason: '$id 월 링크 글자 · receiver 가 본문 표시 영역 · 화면 안 $mlr $rcvR');
          recv(mlv, '$id 월 링크');
          final mlm2 = layoutOf(mlv);
          final mlx2 = linesOf(mlv);
          final mo2 = t.getRect(mlv).intersect(t.getRect(findPlain('수입 현황', skipOffstage: false)));
          final mOver2 = mo2.width > 0.5 && mo2.height > 0.5;
          // ignore: avoid_print
          print('DU383r4 $id monthlink@link ${mlm2.desc} $mlx2 overlapTitle=$mOver2');
          expect(mlm2.spaceBreaks && !mlm2.ellipsis && !mOver2, isTrue, reason: '$id [C201-2] 월 링크 위치에서 재확인 $mlx2');
          check('월 링크 위치 캡처 전');
          await vqCapture(t, o.key, '${id}_month', conditions: {'id': '${id}_month', 'phase': phase, 'dates': dts, 'locale': curLoc,
              'offset': o.pos.pixels.toStringAsFixed(1), 'month_text': '$mlr', 'month_receiver': '$rcvR', 'month_m': '${mlm2.desc} $mlx2 overlapTitle=$mOver2'});
          check('월 링크 위치 캡처 뒤');
        }
        done.add(id);
        // ignore: avoid_print
        print('DU383r4 $id 완료(원 위치 캡처 + 월 링크 확인)');
        await t.pumpWidget(const SizedBox.shrink());
        check('정리');
      });
    }
    // c — H35-DATE fixture. 더보기 실제 탭 → 시트 날짜 1–30 전문 → B: 달력 안 중앙 drag 끝 도달 / N: 시트 스크롤 0 + 달력 안 수평 swipe 다음 달 → 원래 달(날짜 전문 재확인)
    //   → 범례 전체·날짜 칸 hit·대비 → 취소, 홈 글자 그대로
    for (final (v, size, scale) in views) {
      final id = 'DU195-c-$v';
      await runCase(id, () async {
        st('open');
        final o = await open(_reads(h35Apps(), legal: h35Legal), size, scale);
        check('open');
        final before = homeTexts();
        await openSheet(id, o);
        final sh = sheetOf(id);
        final ext0 = sh.pos.maxScrollExtent;
        final cd = clippedDays(sh.cal);
        expect(cd, 0, reason: '$id 시트 날짜 1–30 전문(한 줄) 잘림 $cd');
        final cond = <String, Object?>{'sheet_extent': ext0.toStringAsFixed(2), 'clipped_days': cd};
        if (v == 'B') {
          expect(ext0 >= 0, isTrue, reason: '$id extent $ext0');
          cond.addAll(await centerDrag(id, sh));
        }
        if (v == 'N') {
          expect(ext0 <= 0.01, isTrue, reason: '$id N 시트 불필요한 스크롤 없음 extent=$ext0');
          final rCal = t.getRect(sh.cal);
          final f0 = calFocused(sh.cal);
          final s0 = calSelected(sh.cal);
          final m0 = calMonth(sh.cal);
          st('수평 swipe 다음 달');
          guardMove('sheet', '$id 달력 수평 swipe 1');
          await t.dragFrom(rCal.center, Offset(-rCal.width * 0.6, 0));
          await settle(10);
          check('수평 swipe 1');
          final f1 = calFocused(sh.cal);
          final m1 = calMonth(sh.cal);
          expect(_dateSheetTitle(), findsOneWidget, reason: '$id swipe 1 뒤 시트 유지');
          expect(f0 != null && f1 != null && f1.year * 12 + f1.month == f0.year * 12 + f0.month + 1, isTrue, reason: '$id 다음 달 $f0 → $f1');
          expect(m1, isNot(equals(m0)), reason: '$id 표시월 바뀜 $m0 → $m1');
          expect(calSelected(sh.cal), s0, reason: '$id swipe 1 선택날짜 불변');
          st('수평 swipe 원래 달');
          guardMove('sheet', '$id 달력 수평 swipe 2');
          await t.dragFrom(t.getRect(sh.cal).center, Offset(rCal.width * 0.6, 0));
          await settle(10);
          check('수평 swipe 2');
          final f2 = calFocused(sh.cal);
          final m2 = calMonth(sh.cal);
          expect(_dateSheetTitle(), findsOneWidget, reason: '$id swipe 2 뒤 시트 유지');
          expect(f0 != null && f2 != null && f2.year * 12 + f2.month == f0.year * 12 + f0.month, isTrue, reason: '$id 원래 달 복귀 $f0 → $f2');
          expect(m2, m0, reason: '$id 표시월 복귀');
          expect(calSelected(sh.cal), s0, reason: '$id swipe 2 선택날짜 불변');
          final cd2 = clippedDays(sh.cal);
          expect(cd2, 0, reason: '$id 복귀 뒤 날짜 1–30 전문 잘림 $cd2');
          cond.addAll({'focused': '$f0 -> $f1 -> $f2', 'month': '${m0.join('/')} -> ${m1.join('/')} -> ${m2.join('/')}', 'selected': '$s0', 'clipped_days_after_return': cd2});
        }
        final vpS = t.getRect(sh.scr);
        final leg = find.text('공고 있음');
        one(leg, '$id 범례 공고 있음');
        final legRow = find.ancestor(of: leg, matching: find.byType(Row)).first;
        expect(inRect(vpS, t.getRect(leg)) && inRect(vpS, t.getRect(legRow)) && inRect(Offset.zero & size, t.getRect(legRow)), isTrue, reason: '$id 범례 행 전체가 시트 보이는 영역 안');
        final d1 = '${_day(1).day}';
        final day = find.descendant(of: sh.sheet, matching: find.text(d1));
        one(day, '$id 시트 달력 날짜 $d1');
        expect(inRect(vpS, t.getRect(day)), isTrue, reason: '$id 날짜 칸 보이는 영역 안(보조 이동 0)');
        recv(day, '$id 시트 달력 날짜 $d1(선택 가능)');
        final (b0, bs) = bg(leg);
        final cr = contrast(fg(leg), b0);
        expect(cr >= 4.5, isTrue, reason: '$id 범례 대비 ${cr.toStringAsFixed(2)} ≥ 4.5');
        cond.addAll({'legend_row': t.getRect(legRow).toString(), 'sheet_view': vpS.toString(), 'legend_contrast': cr.toStringAsFixed(2)});
        await shot(id, o.key, cond);
        st('취소');
        expect(find.byType(ModalBarrier).evaluate().isNotEmpty, isTrue, reason: '$id 시트 바깥 barrier');
        guardTap('$id 시트 바깥 취소');
        await t.tapAt(Offset(size.width / 2, 8));
        await settle(10);
        var how = 'barrier';
        if (_dateSheetTitle().evaluate().isNotEmpty) {
          how = 'maybePop';
          await Navigator.of(t.element(_dateSheetTitle())).maybePop();
          await settle(10);
        }
        check('취소');
        expect(_dateSheetTitle(), findsNothing, reason: '$id 시트 닫힘(취소 $how)');
        expect(homeTexts(), before, reason: '$id 취소 뒤 홈 글자(선택 상태) 그대로');
        // ignore: avoid_print
        print('DU195 $id cancel=$how');
        await t.pumpWidget(const SizedBox.shrink());
        check('정리');
      });
    }
    // d — 경력 말단: 요약 문자열·글꼴·배율, 근무 기록 보기 receiver ≥48·hit·겹침 0(목적지 탭 0)
    for (final (v, size, scale) in views) {
      final id = 'DU195-d-$v';
      await runCase(id, () async {
        st('open');
        final o = await open(_reads(const []), size, scale);
        check('open');
        guardMove('home', '$id 말단 jumpTo');
        o.pos.jumpTo(o.pos.maxScrollExtent);
        await settle(6);
        check('말단 이동');
        final sumF = find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().startsWith('근무 완료 '));
        one(sumF, '$id 근무 요약');
        final srp = t.renderObject<RenderParagraph>(sumF);
        final plain = srp.text.toPlainText();
        final fam = srp.text.style?.fontFamily;
        final sc = srp.textScaler.scale(10);
        expect(plain.contains('근무 완료 3회'), isTrue, reason: '$id 근무 요약 문자열 "$plain"');
        expect(fam != null, isTrue, reason: '$id 근무 요약 글꼴 경로(테마 상속) — 글리프 자체는 PNG 관찰로 판정');
        final sp = summarySpans(srp);
        expect(sp.ok, isTrue, reason: '$id 근무 요약 전문·강조 span ${sp.desc}');
        expect((sc - 10 * scale).abs() < 0.01, isTrue, reason: '$id 근무 요약 배율 $sc / ${10 * scale}');
        expect(inRect(o.vp, t.getRect(sumF)), isTrue, reason: '$id 근무 요약 화면 안');
        final lf = find.text('근무 기록 보기');
        one(lf, '$id 근무 기록 보기');
        final rf = recv(lf, '$id 근무 기록 보기');
        final rr = t.getRect(rf);
        final rz = t.getSize(rf);
        final rcv = rx(id, '근무 기록 보기', rz, rr, vpNow(), size);
        final above = find.text('업무 유형 기록이 없어요');
        one(above, '$id 위 안내(업무 유형 기록 없음)');
        final ov = rr.intersect(t.getRect(above));
        final atEnd = (o.pos.pixels - o.pos.maxScrollExtent).abs() < 0.5;
        expect(atEnd, isTrue, reason: '$id 말단');
        expect(inRect(o.vp, rr), isTrue, reason: '$id receiver viewport 안');
        expect(rz.width >= 48 && rz.height >= 48, isTrue, reason: '$id receiver local ≥ 48 $rcv');
        expect((rz.width - rr.width).abs() <= 1e-10 && (rz.height - rr.height).abs() <= 1e-10, isTrue, reason: '$id receiver local/global 차 ≤ 1e-10 $rcv');
        expect(hitAt(rf, rr.topLeft + const Offset(2, 2)) && hitAt(rf, rr.bottomRight - const Offset(2, 2)), isTrue, reason: '$id receiver 가장자리 빈 곳 hit');
        expect(ov.width > 0 && ov.height > 0, isFalse, reason: '$id 위 안내와 겹침 0');
        final et = findPlain('아직 표시할 수입 금액이 없어요', skipOffstage: false);
        one(et, '$id 0수입 제목');
        final etm = layoutOf(et);
        final etx = linesOf(et);
        final ed = findPlain('확정 금액과 근무 예정 수입이 여기에 표시돼요', skipOffstage: false);
        one(ed, '$id 0수입 안내');
        final eo = t.getRect(et).intersect(t.getRect(ed));
        final eOver = eo.width > 0.5 && eo.height > 0.5;
        // ignore: avoid_print
        print('DU203 $id emptytitle ${etm.desc} $etx overlapDesc=$eOver');
        if (isAfter) expect(etm.spaceBreaks && !etm.ellipsis && !eOver, isTrue, reason: '$id [C201-3] 0수입 제목 낱말 보존·말줄임 0·안내 비겹침 $etx');
        await shot(id, o.key, {'summary': plain, 'summary_spans': sp.desc, 'summary_font': '$fam', 'summary_scale10': sc.toStringAsFixed(2), 'receiver': rcv, 'above': t.getRect(above).toString(), 'overlap': ov.width > 0 && ov.height > 0, 'at_end': atEnd, 'empty_title': '${etm.desc} $etx overlapDesc=$eOver'});
        await t.pumpWidget(const SizedBox.shrink());
        check('정리');
      });
    }
    expect(done, ['DU195-a-B', 'DU195-a-N', 'DU195-b-B', 'DU195-b-N', 'DU195-c-B', 'DU195-c-N', 'DU195-d-B', 'DU195-d-N'], reason: '8사례 순서·각1회 완료');
    expect(identical(FlutterError.onError, base), isTrue, reason: '끝 handler = 시험 시작 handler');
    // ignore: avoid_print
    print('DU195 done taps=$taps home_moves=$homeMoves sheet_moves=$sheetMoves cases=${done.length}');
  }

  testWidgets('DU195 S080 8사례 before/after — a 날짜선택 공고0 · b 지원 행 · c 날짜 시트 drag·월 이동 · d 근무 기록 보기', (t) async {
    await du195Body(t);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('DU195-DATE-B 날짜 시트 현재·다음 달 일수·선택 · 주간 숫자 · 월 링크 320×640@2.0 · D394DATE', (t) async {
    await du195Body(t, dateView: 'B');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('DU195-DATE-N 날짜 시트 현재·다음 달 일수·선택 · 주간 숫자 · 월 링크 390×844@1.0 · D394DATE', (t) async {
    await du195Body(t, dateView: 'N');
  }, timeout: const Timeout(Duration(minutes: 3)));

  // [DU397] 이번 주 일정 가로 스크롤 분기 — 320×640@3.0, 기준일 = DU1_VQ_DATE(배정 11-16). 분기 발생(필요 칸 폭 × 7 > 가용 · 가로 최대 이동 > 0)부터
  //   단언해 빈 통과를 막는다. 일곱 칸을 실제 가로 스크롤로 하나씩 들여 full date(요일 · 숫자) · 순서 · 고유 · 오늘 채움 정확 1 · 점 귀속/색 ·
  //   숫자 한 줄 · 말줄임 0 · 상자/칸/가로 viewport/화면/본문 안 · 이웃 칸 비겹침. 첫/끝 위치 PNG. 탭 · 쓰기 없음.
  testWidgets('DU397-WEEK-OVERFLOW-B 이번 주 일정 숫자 폭 가로 스크롤 320×640@3.0 · 기준일 11-16 · D397FB', (t) async {
    const tok = 'DU397-WEEK-OVERFLOW-B';
    _d394(_start394(tok));
    _d394('D394 $tok contract=${_contractCheck394(tok)}');
    var moves = 0;
    final overflows = h35Overflows();
    final key = GlobalKey();
    const size = Size(320, 640);
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final apps = [
      _short('wk1', 1),
      _short('wp0', 0).copyWith(status: AppStatus.pending),
      _short('wp2', 2).copyWith(status: AppStatus.pending),
    ];
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(3.0)), child: child!),
            home: UserHomeScreen(reads: _reads(apps), clock: () => _clock)),
      ),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    void rec(String line) {
      // ignore: avoid_print
      print('DU397 $tok $line');
    }

    bool inR(Rect o, Rect r) => r.top >= o.top - 0.5 && r.bottom <= o.bottom + 0.5 && r.left >= o.left - 0.5 && r.right <= o.right + 0.5;
    final all = find.byType(Scrollable);
    final cands = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
        .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
        .toList()
      ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
    final vp = t.getRect(cands.first);
    final title = findVisibleText('이번 주 일정');
    var k = 0;
    while (title.evaluate().isEmpty && k < 30) {
      await t.dragFrom(Offset(vp.left + 4, vp.center.dy), const Offset(0, -300));
      moves++;
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      k++;
    }
    expect(title, findsOneWidget, reason: '$tok 이번 주 일정 제목 1');
    final sec = find
        .ancestor(of: title, matching: find.byWidgetPredicate((w) => w is Container && w.color == Colors.white && w.padding != null && w.child is Column))
        .first;
    final hs = find.descendant(of: sec, matching: find.byType(Scrollable));
    expect(hs, findsOneWidget, reason: '$tok 가로 스크롤 분기 발생(필요 칸 폭 × 7 > 가용)');
    await t.ensureVisible(hs);
    moves++;
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final hpos = t.state<ScrollableState>(hs).position;
    final hvp0 = t.getRect(hs);
    expect(hpos.axis, Axis.horizontal, reason: '$tok 가로 축');
    expect(hpos.maxScrollExtent > 0, isTrue, reason: '$tok 가로 최대 이동량 > 0 (${hpos.maxScrollExtent})');
    const wdn = ['월', '화', '수', '목', '금', '토', '일'];
    final week = _weekDays394(_today);
    Finder digitF(DateTime d) => find.descendant(of: sec, matching: findVisibleText('${d.day}'));
    Finder cellF(DateTime d) => find.ancestor(of: digitF(d), matching: find.byType(Column)).first;
    for (final d in week) {
      expect(digitF(d), findsOneWidget, reason: '$tok 숫자 ${_ymd394(d)} 정확 1');
    }
    final cellW = t.getSize(cellF(week.first)).width;
    rec('기준일 ${_ymd394(_today)} 본문 $vp drag $k회 · 가로 viewport $hvp0 · 칸 폭 $cellW × 7 = ${cellW * 7} · 가로 max ${hpos.maxScrollExtent} · 처음 offset ${hpos.pixels}');
    expect(cellW * 7 > hvp0.width + 0.5, isTrue, reason: '$tok 필요 칸 폭 × 7 > 가용(${hvp0.width})');
    final todayIx = week.indexWhere((d) => d == _today);
    expect(todayIx >= 0 && inR(hvp0, t.getRect(cellF(week[todayIx]))), isTrue, reason: '$tok 오늘 칸이 첫 화면(처음 가로 위치)에 보임');
    await vqCapture(t, key, '${tok}_first', conditions: {
      'screen': 'UserHomeScreen(reads: 확정 +1 · 대기 오늘/+2, clock ${_clock.toIso8601String()} — 기준일 ${_ymd394(_today)})',
      'theme': 'RoleTheme.workerTheme', 'viewport': '320x640', 'dpr': 1.0, 'textScaler': 3.0, 'inset': '0', 'fixture_base': _ymd394(_today),
      'scroll': '본문 dragFrom -300 × $k + ensureVisible(주간 행) · 가로 offset ${hpos.pixels}'});
    int wantDot(DateTime d) => d == _day(1) ? 0xFF166534 : ((d == _today || d == _day(2)) ? 0xFFE65100 : 0x00000000);
    final contentLefts = <double>[];
    var fills = 0;
    for (var i = 0; i < 7; i++) {
      final d = week[i];
      final cf = cellF(d);
      await t.ensureVisible(cf);
      moves++;
      for (var j = 0; j < 6; j++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final cr = t.getRect(cf);
      final hvp = t.getRect(hs);
      final reach = inR(hvp, cr) && inR(Offset.zero & size, cr) && inR(vp, cr);
      contentLefts.add(cr.left + hpos.pixels);
      final texts = [for (final e in find.descendant(of: cf, matching: find.byType(Text)).evaluate()) visibleText((e.widget as Text).data ?? '')];
      final dp = t.renderObject<RenderParagraph>(find.descendant(of: digitF(d), matching: find.byType(RichText), matchRoot: true).first);
      final tp = TextPainter(text: dp.text, textScaler: dp.textScaler, textDirection: TextDirection.ltr)..layout();
      final lines = (dp.size.height / tp.height).round();
      final wrapped = dp.size.width + 0.5 < tp.width;
      final clipped = dp.size.height + 0.5 < tp.height;
      tp.dispose();
      final box = find.ancestor(of: digitF(d), matching: find.byType(Container)).first;
      final br = t.getRect(box);
      final tr = t.getRect(digitF(d));
      final dec = t.widget<Container>(box).decoration;
      final fill = dec is BoxDecoration && dec.color != null && dec.color!.a > 0;
      if (fill) fills++;
      final dots = [
        for (final e in find.descendant(of: cf, matching: find.byType(Container)).evaluate())
          if ((e.widget as Container).decoration is BoxDecoration && ((e.widget as Container).decoration! as BoxDecoration).shape == BoxShape.circle)
            ((e.widget as Container).decoration! as BoxDecoration).color?.toARGB32() ?? 0
      ];
      var overlapN = 0;
      for (var j = 0; j < 7; j++) {
        if (j == i) continue;
        final x = cr.intersect(t.getRect(cellF(week[j])));
        if (x.width > 0.5 && x.height > 0.5) overlapN++;
      }
      rec('칸 $i ${_ymd394(d)} 글 $texts 칸 $cr 상자 $br 숫자 $tr 가로 ${hpos.pixels.toStringAsFixed(1)} 도달=$reach 줄 $lines 감김=$wrapped 잘림=$clipped '
          '말줄임=${dp.didExceedMaxLines} 채움=$fill 점 ${dots.map((c) => c.toRadixString(16)).toList()} 겹침 $overlapN');
      expect(reach, isTrue, reason: '$tok 칸 $i 실제 가로 스크롤 도달(가로 viewport · 화면 · 본문 안) $cr');
      expect(texts, [wdn[d.weekday - 1], '${d.day}'], reason: '$tok 칸 $i full date(요일 · 숫자) ${_ymd394(d)}');
      expect(lines == 1 && !wrapped && !clipped && !dp.didExceedMaxLines, isTrue, reason: '$tok 칸 $i 숫자 한 줄 · 말줄임 0');
      expect(inR(br, tr) && inR(cr, br), isTrue, reason: '$tok 칸 $i 숫자 ⊂ 상자 ⊂ 칸');
      expect(fill, d == _today, reason: '$tok 칸 $i 오늘 채움');
      expect(dots, [wantDot(d)], reason: '$tok 칸 $i 점 귀속 · 색');
      expect(overlapN, 0, reason: '$tok 칸 $i 이웃 칸 비겹침');
    }
    expect(fills, 1, reason: '$tok 오늘 채움 정확 1');
    expect([for (var i = 1; i < 7; i++) contentLefts[i] > contentLefts[i - 1] + 0.5].every((x) => x), isTrue, reason: '$tok 칸 왼→오 = 월–일 $contentLefts');
    await vqCapture(t, key, '${tok}_last', conditions: {
      'viewport': '320x640', 'textScaler': 3.0, 'fixture_base': _ymd394(_today), 'scroll': '마지막 칸 ensureVisible · 가로 offset ${hpos.pixels}'});
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    _d394('D394 $tok done base=${_ymd394(_today)} taps=0 moves=$moves');
  });
}
