// ignore_for_file: depend_on_referenced_packages
// [N352-1 · DU352 디자인 재검토 후속(2026-11-18) · 표시만] S020 계약 확인 필요(ExpiringContractsScreen) — 기한 묶음 카드.
//   후보: 행 앞 이니셜 원 · 왼쪽 4px 급함색 막대 제거(개별 기한색은 D-day 칩 한 곳) · 이미 정해진 `_items` 를 순서대로 나눈 네 묶음
//   (만료 · 결정 필요 / 3일 이내 종료 / 4–7일 후 종료 / 8–15일 후 종료)의 제목 + `(n)` + 흰 카드 한 장 · 카드 안 중립 구분선 · 빈 묶음 0.
//   before = 현재 A(expiring_contracts_screen 15b8383e) · strict = 후보. 판정 · 정렬 · 조회 · 행 탭 목적지는 두 판이 같다(정적 diff).
//   상태: LIST(기존 10행 + 제외 2 — 만료/0/1/3 로컬/3 UTC/4/7/8/9 이름 없음/15 · D16 · 응답 대기) · EMPTY · ERROR(실패 → 다시 시도 → 목록) ·
//     COMBO(빈 묶음 조합 3) · MUT(제외 검사 변이 — 대기 제안 없음 · 16 → 15 → 12행) · NAMES(긴 이름 · 라틴 이름 · 동명이인 · 이름 없음 · 긴 사업장).
//   행 식별 = 행 InkWell 의 ObjectKey(ApplicationModel) — 기대 이름 선필터 없이, 실제 끌기로 방문한 모든 행을 모은다.
//     기준판은 행 키가 없어 이름 글자(semanticsLabel)로 대신 적는다(기록만).
//   '보인다' = 가장 가까운 Scrollable 의 viewport ∩ 화면 **안**(겹침 아님). 실제 끌기(t.drag · 슬롭 보정) 뒤 다시 찾아 잰다 — ensureVisible 0.
//   대비 = 글자 RenderParagraph 의 실제 조상 render 면(RenderDecoratedBox · RenderPhysicalModel/Shape)을 바깥 → 안쪽으로 합성한 바탕 위 ·
//     원색 값을 N352 줄로 남긴다(옛 6.03 재사용 0). 칩 바탕은 손 계산 8비트 기대(12% · 흰 카드)와 채널별로 대조한다(sample).
//   행 탭 → FixedWorkerManagementDialog 는 실제로 열지 않는다(그 창을 여는 기존 시험 대역 0 · 창이 FirestoreService() 를 직접 쓴다) —
//     행동 RUNTIME 미확인 · 목적지 인자/닫힘 뒤 재조회는 정적 diff 보존만. 받는 자리(≥ 48 · 중심 hit · 글자 전부 같은 수신자 · onTap 있음)는 잰다.
//   before 는 화면 값을 기록만 한다 — 단언은 시험 배선(조회 호출 수) · 존재(need) · framework 예외 0 · 끝 예외 0 뿐이다.
//   기본 skip — TB before/du352n1-tb/DU_BEFORE_OBSERVE=352 · TA after/du352n1-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/screens/business_admin/expiring_contracts_reads.dart';
import 'package:ALfit/screens/business_admin/expiring_contracts_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/responsive_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/common/common_widgets.dart';

import 'support/du1_vq_capture.dart';
import 'support/du_word_break.dart';

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

final String _phase = Platform.environment['DU1_VQ_PHASE'] ?? '(unset)';
final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '352';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du352n1-tb' && _env['DU_BEFORE_OBSERVE'] == '352') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du352n1-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

// ── 고정 자료 ─────────────────────────────────────────────────────────────

/// 오늘(KST 달력 날짜 키 — y/m/d 가 KST 오늘인 UTC 자정). 화면 `_loadData` 도 실제 지금으로 잰다(시계 seam 0 · DU347 시험과 같다).
final DateTime _today = FormatHelper.toKstDate(DateTime.now());

/// 모델 파서는 Timestamp 를 `.toLocal()` 로 준다 — 기본은 로컬 표현. utc=true 면 같은 KST 자정 instant 의 UTC 표현.
DateTime _kstMidnight(DateTime kstDate, {bool utc = false}) {
  final i = DateTime.utc(kstDate.year, kstDate.month, kstDate.day).subtract(const Duration(hours: 9));
  return utc ? i : i.toLocal();
}

const _bizLong = '[QA] 아주 긴 이름의 골든패스 테스트 물류센터 사업장';
const _bizShort = '강남 물류센터';

ApplicationModel _app(String id, String biz, String uid, int endInDays, {bool utc = false}) => ApplicationModel(
    id: id, businessId: biz, businessName: biz == 'b1' ? _bizLong : _bizShort,
    toTitle: 'QA 장기', workDate: _kstMidnight(_today.subtract(const Duration(days: 60))), startTime: '09:00', endTime: '18:00',
    uid: uid, selectedWorkType: 'QA 분류', wage: 12000, wageType: 'hourly', status: AppStatus.confirmed,
    appliedAt: _kstMidnight(_today.subtract(const Duration(days: 70))), applicationType: AppType.longTerm,
    workEndDate: _kstMidnight(_today.add(Duration(days: endInDays)), utc: utc));

BusinessModel _biz(String id, String name) => BusinessModel(
    id: id, name: name, ownerId: 'admin1', businessNumber: '000-00-00000',
    address: '서울시 어딘가', category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1));

UserModel _user(String uid, String name) =>
    UserModel(uid: uid, username: uid, name: name, email: '$uid@test.local', role: UserRole.USER);

/// 한 행 자료 — 지원서 id · 사업장 · 이름(null = 이름 조회 결과 없음) · 남은 날 · UTC 표현?
typedef _Row = ({String id, String biz, String? name, int d, bool utc});

/// 기존 DU347/352 고정 자료(두 사업장 교차) — 보이는 10행 + 창 밖 D-16 · 응답 대기 제안 D-5(둘 다 빠져야 한다).
const List<_Row> _listRows = [
  (id: 'a-만료둘', biz: 'b1', name: '만료둘', d: -2, utc: false),
  (id: 'a-디데이', biz: 'b2', name: '디데이', d: 0, utc: false),
  (id: 'a-내일', biz: 'b1', name: '내일', d: 1, utc: false),
  (id: 'a-셋로컬', biz: 'b2', name: '셋로컬', d: 3, utc: false),
  (id: 'a-셋유티시', biz: 'b1', name: '셋유티시', d: 3, utc: true),
  (id: 'a-넷', biz: 'b2', name: '넷', d: 4, utc: false),
  (id: 'a-일곱', biz: 'b1', name: '일곱', d: 7, utc: false),
  (id: 'a-여덟', biz: 'b2', name: '여덟', d: 8, utc: false),
  (id: 'a-열다섯', biz: 'b1', name: '열다섯', d: 15, utc: false),
  (id: 'a-열여섯', biz: 'b2', name: '열여섯', d: 16, utc: false),
  (id: 'a-대기제안', biz: 'b1', name: '대기제안', d: 5, utc: false),
  (id: 'a-noname', biz: 'b2', name: null, d: 9, utc: false),
];

/// 기존 `_items` 순서(사업장별 compareRenewalUrgency → 합친 뒤 남은 날 오름차순 · 같은 날은 b1 먼저 — 짧은 목록의 안정 정렬).
const List<String> _listOrder = ['a-만료둘', 'a-디데이', 'a-내일', 'a-셋유티시', 'a-셋로컬', 'a-넷', 'a-일곱', 'a-여덟', 'a-noname', 'a-열다섯'];

/// [DU352] 제외 검사 변이 — 대기 제안 없음(_Reads.withProposal false) · 16일 행을 15일로. 두 행이 **보여야** 수집기가 유효하다.
const List<_Row> _mutRows = [
  (id: 'a-만료둘', biz: 'b1', name: '만료둘', d: -2, utc: false),
  (id: 'a-디데이', biz: 'b2', name: '디데이', d: 0, utc: false),
  (id: 'a-내일', biz: 'b1', name: '내일', d: 1, utc: false),
  (id: 'a-셋로컬', biz: 'b2', name: '셋로컬', d: 3, utc: false),
  (id: 'a-셋유티시', biz: 'b1', name: '셋유티시', d: 3, utc: true),
  (id: 'a-넷', biz: 'b2', name: '넷', d: 4, utc: false),
  (id: 'a-일곱', biz: 'b1', name: '일곱', d: 7, utc: false),
  (id: 'a-여덟', biz: 'b2', name: '여덟', d: 8, utc: false),
  (id: 'a-열다섯', biz: 'b1', name: '열다섯', d: 15, utc: false),
  (id: 'a-열여섯', biz: 'b2', name: '열여섯', d: 15, utc: false),
  (id: 'a-대기제안', biz: 'b1', name: '대기제안', d: 5, utc: false),
  (id: 'a-noname', biz: 'b2', name: null, d: 9, utc: false),
];

const List<String> _mutOrder = [
  'a-만료둘', 'a-디데이', 'a-내일', 'a-셋유티시', 'a-셋로컬', 'a-넷', 'a-대기제안', 'a-일곱', 'a-여덟', 'a-noname', 'a-열다섯', 'a-열여섯',
];

/// 읽기 — 같은 이름 다른 지원서(동명이인) · 띄어쓰기 없는 긴 이름 · 라틴 이름 · 이름 없음 · 긴 사업장(b1).
const List<_Row> _nameRows = [
  (id: 'a-dup1', biz: 'b2', name: '김민수', d: 1, utc: false),
  (id: 'a-dup2', biz: 'b2', name: '김민수', d: 2, utc: false),
  (id: 'a-long', biz: 'b1', name: '황보가나다라마바사아자차카', d: 5, utc: false),
  (id: 'a-latin', biz: 'b1', name: 'NGUYEN THI MINH KHAI', d: 10, utc: false),
  (id: 'a-none', biz: 'b2', name: null, d: -3, utc: false),
];

const List<String> _nameOrder = ['a-none', 'a-dup1', 'a-dup2', 'a-long', 'a-latin'];

/// 빈 묶음 조합 — 묶음이 빠진 자리에 제목 · 빈 카드 · 여백이 남지 않는다.
typedef _Combo = ({String shot, String state, List<_Row> rows, List<String> order, String head});
const List<_Combo> _combos = [
  (
    shot: '1cone',
    state: 'combo-expired-and-8to15',
    rows: [
      (id: 'a-c1x', biz: 'b2', name: '가만료', d: -5, utc: false),
      (id: 'a-c1y', biz: 'b1', name: '나여유', d: 10, utc: false),
      (id: 'a-c1z', biz: 'b2', name: '다여유', d: 12, utc: false),
    ],
    order: ['a-c1x', 'a-c1y', 'a-c1z'],
    head: '만료 · 결정 필요 1명 · 곧 종료 2명',
  ),
  (
    shot: '2ctwo',
    state: 'combo-0to3-and-4to7',
    rows: [
      (id: 'a-c2x', biz: 'b1', name: '라임박', d: 2, utc: false),
      (id: 'a-c2y', biz: 'b2', name: '마중간', d: 6, utc: false),
    ],
    order: ['a-c2x', 'a-c2y'],
    head: '곧 종료 2명',
  ),
  (
    shot: '3cthree',
    state: 'combo-expired-only',
    rows: [
      (id: 'a-c3x', biz: 'b1', name: '바지남', d: -1, utc: false),
      (id: 'a-c3y', biz: 'b2', name: '사오래', d: -30, utc: false),
    ],
    order: ['a-c3y', 'a-c3x'],
    head: '만료 · 결정 필요 2명',
  ),
];

final _cases = <({String id})>[(id: 'LIST'), (id: 'EMPTY'), (id: 'ERROR'), (id: 'COMBO'), (id: 'MUT'), (id: 'NAMES')];

RenewalProposalModel? _proposal() => RenewalProposalModel.tryFromMap({
      'oldApplicationId': 'a-대기제안', 'businessId': 'b1', 'workerUid': 'u-대기제안', 'status': 'PENDING',
      'effectiveStart': {'_seconds': _kstMidnight(_today.add(const Duration(days: 6))).millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0},
      'effectiveEnd': {'_seconds': _kstMidnight(_today.add(const Duration(days: 96))).millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0},
    }, 'p1');

({Map<String, List<ApplicationModel>> apps, Map<String, UserModel> users}) _fixture(List<_Row> rows) {
  final apps = <String, List<ApplicationModel>>{'b1': <ApplicationModel>[], 'b2': <ApplicationModel>[]};
  final users = <String, UserModel>{};
  for (final r in rows) {
    final uid = 'u-${r.id.substring(2)}';
    apps[r.biz]!.add(_app(r.id, r.biz, uid, r.d, utc: r.utc));
    final nm = r.name;
    if (nm != null) users[uid] = _user(uid, nm);
  }
  return (apps: apps, users: users);
}

/// 세 조회의 시험 대역(DU347 reads seam) — 호출 수를 센다. 판정 · 정렬 · 표시는 실제 화면이다.
class _Reads {
  _Reads(this.apps, this.users, {required this.withProposal, this.failFirst = 0, this.empty = false});
  final Map<String, List<ApplicationModel>> apps;
  final Map<String, UserModel> users;
  final bool withProposal;
  final bool empty;
  int failFirst;
  int calls = 0;
  int prop = 0;
  int user = 0;

  ExpiringContractsReads get seam => ExpiringContractsReads(
        expiringApplications: ({required businessId, required fromDate}) async {
          calls++;
          if (failFirst > 0) {
            failFirst--;
            throw StateError('expiring cf down');
          }
          return empty ? <ApplicationModel>[] : apps[businessId] ?? <ApplicationModel>[];
        },
        pendingRenewalProposals: (businessId) async {
          prop++;
          final p = withProposal ? _proposal() : null;
          return (businessId == 'b1' && p != null) ? [p] : <RenewalProposalModel>[];
        },
        usersBatch: (uids, {required businessId}) async {
          user++;
          return {for (final u in uids) if (users[u] != null) u: users[u]!};
        },
      );
}

// ── 기대(시험이 따로 적는 계약) ────────────────────────────────────────────

/// 묶음 제목 — 표시 순서. 경계는 기존 칩 색 구간(≤3 · ≤7 · 그 밖) + 만료 분리. 갱신 결정 기한이 아니다.
const List<String> _groupTitles = ['만료 · 결정 필요', '3일 이내 종료', '4–7일 후 종료', '8–15일 후 종료'];
final RegExp _titleRe = RegExp(r'^(.+) \((\d+)\)$');

int _grp(int d) => d < 0 ? 0 : (d <= 3 ? 1 : (d <= 7 ? 2 : 3));
String _label(int d) => d < 0 ? '만료 ${-d}일' : (d == 0 ? 'D-Day' : 'D-$d');
Color _bandOf(int d) => d <= 3 ? AppColors.error : (d <= 7 ? AppColors.warning : AppColors.brand);
Color _darkOf(int d) => d <= 3 ? AppColors.errorDark : (d <= 7 ? AppColors.warningInk : AppColors.brandDark);

class _Exp {
  const _Exp(this.name, this.biz, this.date, this.label, this.d);
  final String name;
  final String biz;
  final String date;
  final String label;
  final int d;
}

Map<String, _Exp> _expOf(List<_Row> rows) {
  final fmt = DateFormat('M/d(E)', 'ko_KR');
  return {
    for (final r in rows)
      r.id: _Exp(r.name ?? '알 수 없음', r.biz == 'b1' ? _bizLong : _bizShort,
          fmt.format(DateTime.utc(_today.year, _today.month, _today.day + r.d)), _label(r.d), r.d),
  };
}

/// before(기준판 — 행 키 없음) 대체 식별: 보이는 이름 → 지원서 id. 이 상태 자료 안에서 유일한 이름만 쓴다(동명이인은 위치로 남긴다).
Map<String, String> _nameMap(List<_Row> rows) {
  final n = <String, int>{};
  for (final r in rows) {
    final k = r.name ?? '알 수 없음';
    n[k] = (n[k] ?? 0) + 1;
  }
  return {for (final r in rows) if (n[r.name ?? '알 수 없음'] == 1) r.name ?? '알 수 없음': r.id};
}

final BoxDecoration _cardDeco = CommonWidgets.compactCardDecoration();

// ── 측정 도우미 ───────────────────────────────────────────────────────────

String _f(double v) => v.toStringAsFixed(1);
String _w(String s) => s.isEmpty ? '-' : s;
String _hex(Color c) => '0x${c.toARGB32().toRadixString(16).padLeft(8, '0')}';
int _ch8(double v) => (v * 255).round();

/// [a] 가 [b] **안**에 있는가(겹침이 아니라 포함 · 0.5px 허용).
bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

Rect _rectOf(Element e) {
  final ro = e.renderObject;
  if (ro is! RenderBox || !ro.attached || !ro.hasSize) return Rect.zero;
  return ro.localToGlobal(Offset.zero) & ro.size;
}

List<Element> _below(Element root, bool Function(Widget w) test) {
  final out = <Element>[];
  void walk(Element x) {
    if (test(x.widget)) out.add(x);
    x.visitChildren(walk);
  }

  root.visitChildren(walk);
  return out;
}

List<String> _tail2(List<String> a) => a.length < 2 ? a : a.sublist(a.length - 2);

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _plainOf(RichText w) => TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false));

Finder _rich(bool Function(String text) test) =>
    find.byWidgetPredicate((w) => w is RichText && test(_plainOf(w)), skipOffstage: false);

bool _isTitle(String text) {
  final m = _titleRe.firstMatch(text);
  return m != null && _groupTitles.contains(m.group(1));
}

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// 글자 조각(span)마다 실제 색 — 부모 span 색을 물려받는다(묶음 제목 = 제목 textPrimary + 건수 textSecondary).
void _spanColors(InlineSpan s, Color? inherited, List<Color> out) {
  final c = s.style?.color ?? inherited;
  if (s is TextSpan) {
    if ((s.text ?? '').trim().isNotEmpty && c != null) out.add(c);
    for (final k in s.children ?? const <InlineSpan>[]) {
      _spanColors(k, c, out);
    }
  }
}

/// [N352 · 판정기 재작성] 실제 조상 render 면 합성 — 글자에서 위로 올라가며 칠한 면(RenderDecoratedBox 바탕 ·
///   RenderPhysicalModel/Shape = Material 면)을 모으고, 처음 만나는 불투명 면을 밑에 깐 뒤 바깥 → 안쪽으로 합성한다.
///   render 객체 하나가 면 하나라서 옛 위젯 기준 판정기의 '같은 색 4단계 중첩 한 번만 세기' 휴리스틱이 필요 없다(감사10:68).
///   투명(알파 0) 면 · 투명 Material(MaterialType.transparency — 면 render 객체 없음)은 건너뛴다.
({Color bg, String raw}) _bgOf(RenderObject ro) {
  final layers = <Color>[];
  Color? base;
  RenderObject? p = ro.parent;
  while (p != null) {
    Color? c;
    if (p is RenderDecoratedBox) {
      final d = p.decoration;
      if (p.position == DecorationPosition.background && d is BoxDecoration) c = d.color;
    } else if (p is RenderPhysicalModel) {
      c = p.color;
    } else if (p is RenderPhysicalShape) {
      c = p.color;
    }
    if (c != null && c.a > 0) {
      if (c.a >= 1.0) {
        base = c;
        break;
      }
      layers.add(c);
    }
    p = p.parent;
  }
  var bg = base ?? AppColors.background;
  for (final l in layers.reversed) {
    bg = Color.alphaBlend(l, bg);
  }
  final raw = 'layers=${layers.isEmpty ? '-' : layers.map(_hex).join(',')} base=${base == null ? '-' : _hex(base)} bg=${_hex(bg)}';
  return (bg: bg, raw: raw);
}

/// 가장 가까운 칠한 Container 의 면 색(칩 바탕).
Color? _decoColorAbove(Element e) {
  Color? out;
  e.visitAncestorElements((a) {
    final w = a.widget;
    final d = w is Container ? w.decoration : null;
    if (d is BoxDecoration && d.color != null) {
      out = d.color;
      return false;
    }
    return true;
  });
  return out;
}

// ── 방문 기록 ─────────────────────────────────────────────────────────────

/// 한 행(지원서)의 방문 기록 — 보이는 칸 안에 처음 다 들어온 위치에서 한 번 잰다.
class _Seen {
  _Seen(this.id, this.keyed);
  final String id;
  final bool keyed;
  final List<double> tops = <double>[];
  bool full = false;
  bool measured = false;
  double h = 0;
  bool en = false;
  bool hit = false;
  bool whole = false;
  int cards = 0;
  double cardTop = 0;
  bool inCard = false;
  bool textsIn = false;
  List<String> texts = const <String>[];
  int brk = 0;
  int ell = 0;
  Color? nameFg;
  Color? bizFg;
  Color? dateFg;
  Color? chipFg;
  Color? chipBg;
  double minCr = 99;
  double chipCr = 99;
  int g = -1;
}

/// 묶음 제목 하나의 방문 기록.
class _TitleSeen {
  _TitleSeen(this.g, this.n, this.plain);
  final int g;
  final int n;
  final String plain;
  Rect abs = Rect.zero;
  bool full = false;
  int brk = 0;
  List<Color> colors = const <Color>[];
  double minCr = 99;
}

/// 한 상태의 정리값.
class _Sum {
  int n = 0;
  int keyed = 0;
  int dup = 0;
  int full = 0;
  String ids = '-';
  bool exact = false;
  bool order = false;
  String last = '-';
  int titles = 0;
  String seq = '-';
  String counts = '-';
  int sum = 0;
  int cards = 0;
  bool one = false;
  bool match = false;
  bool concat = false;
  bool empty = false;
  bool gap = false;
  bool top = false;
  String tc = '-';
  String cg = '-';
  bool textFull = false;
  bool labels = false;
  bool dates = false;
  bool chipc = false;
  bool neutral = false;
  bool inrow = false;
  bool incard = false;
  int brk = 0;
  int ell = 0;
  double minh = 0;
  bool hit = false;
  bool whole = false;
  bool en = false;
  double minCr = 99;
  double chipCr = 99;
  double titleCr = 99;
  bool gtFull = false;
  int gtBrk = 0;
  bool gtVis = false;
  bool gtNeutral = false;
  final Map<String, int> groupOf = <String, int>{};

  String gOf(String id) {
    final g = groupOf[id];
    return g == null || g < 0 ? '-' : g.toString();
  }
}

/// 한 화면 상태의 실제 방문 — 행(InkWell) · 묶음 제목 · 카드를 **실제 끌기 뒤 다시 찾아** 모은다.
class _Probe {
  _Probe(this.t, this.screen, this.tok, this.names, this.exp);
  final WidgetTester t;
  final Rect screen;
  final String tok;
  final Map<String, String> names;
  final Map<String, _Exp> exp;
  final Map<String, _Seen> rows = <String, _Seen>{};
  final Map<int, _TitleSeen> titles = <int, _TitleSeen>{};
  final Map<double, Rect> cards = <double, Rect>{};
  final List<String> colorLines = <String>[];
  final Map<int, String> bandHex = <int, String>{};
  final Map<int, bool> bandOk = <int, bool>{};
  int dupFrames = 0;
  int low = 0;
  int steps = 0;
  double step = 0;
  double vh = 0;
  double maxPx = 0;
  bool endReached = false;

  Finder get scroller =>
      find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable), skipOffstage: false).first;
  ScrollPosition get pos => t.state<ScrollableState>(scroller).position;
  Rect get vis => t.getRect(scroller).intersect(screen);

  String _fallbackId(Element e, double absTop) {
    final named = _below(e, (w) => w is Text && w.semanticsLabel != null);
    final label = named.isEmpty ? null : (named.first.widget as Text).semanticsLabel;
    return (label == null ? null : names[label]) ?? 'x${absTop.round()}';
  }

  String _idOf(Element e, double absTop) {
    final k = e.widget.key;
    final app = k is ObjectKey ? k.value : null;
    return app is ApplicationModel ? app.id : _fallbackId(e, absTop);
  }

  /// 지금 위치에서 다시 찾아 모은다(행 · 제목 · 카드). 행 · 제목은 보이는 칸 안에 처음 다 들어왔을 때 한 번 잰다.
  void observe() {
    final vpR = t.getRect(scroller);
    final visR = vpR.intersect(screen);
    final px = pos.pixels;
    final perFrame = <String, int>{};
    for (final e in find.descendant(of: find.byType(ListView), matching: find.byType(InkWell), skipOffstage: false).evaluate()) {
      final r = _rectOf(e);
      if (r.width <= 0 || r.height <= 0) continue;
      final k = e.widget.key;
      final keyed = k is ObjectKey && k.value is ApplicationModel;
      final id = _idOf(e, r.top - vpR.top + px);
      perFrame[id] = (perFrame[id] ?? 0) + 1;
      final s = rows.putIfAbsent(id, () => _Seen(id, keyed));
      s.tops.add(r.top - vpR.top + px);
      if (_inside(r, visR)) {
        s.full = true;
        if (!s.measured) _measure(s, e, r, visR, vpR.top, px);
      }
    }
    if (perFrame.values.any((v) => v > 1)) dupFrames++;
    for (final pe in find.descendant(of: find.byType(ListView), matching: find.byType(RichText), skipOffstage: false).evaluate()) {
      final rp = pe.renderObject;
      if (rp is! RenderParagraph) continue;
      final plain = TextLayout.plain(rp.text.toPlainText(includeSemanticsLabels: false));
      final m = _titleRe.firstMatch(plain);
      if (m == null) continue;
      final g = _groupTitles.indexOf(m.group(1) ?? '');
      if (g < 0) continue;
      final n = int.tryParse(m.group(2) ?? '') ?? -1;
      final r = _rectOf(pe);
      final x = titles.putIfAbsent(g, () => _TitleSeen(g, n, plain));
      x.abs = r.shift(Offset(0, px - vpR.top));
      if (!x.full && _inside(r, visR)) {
        x.full = true;
        x.brk = wordBreaks(rp).where((b) => !b.forced).length;
        final fg = <Color>[];
        _spanColors(rp.text, null, fg);
        x.colors = fg;
        final bg = _bgOf(rp);
        for (final f in fg) {
          final c = _contrast(Color.alphaBlend(f, bg.bg), bg.bg);
          x.minCr = math.min(x.minCr, c);
          if (c < 4.5) low++;
          colorLines.add('N352 $tok color title=$g t=$plain fg=${_hex(f)} ${bg.raw} cr=${c.toStringAsFixed(2)}');
        }
      }
    }
    for (final ce in find.descendant(
        of: find.byType(ListView), matching: find.byWidgetPredicate((w) => w is Container && w.decoration == _cardDeco), skipOffstage: false).evaluate()) {
      final r = _rectOf(ce);
      if (r.height <= 0) continue;
      final a = r.shift(Offset(0, px - vpR.top));
      double? same;
      for (final k in cards.keys) {
        if ((k - a.top).abs() < 1.0) same = k;
      }
      cards[same ?? a.top] = a;
    }
  }

  void _measure(_Seen s, Element e, Rect r, Rect visR, double vpTop, double px) {
    s.measured = true;
    s.h = r.height;
    s.en = (e.widget as InkWell).onTap != null;
    final inkRo = e.renderObject;
    s.hit = t.hitTestOnBinding(r.center).path.any((x) => x.target == inkRo);
    var nCards = 0;
    Rect? cardR;
    e.visitAncestorElements((a) {
      final w = a.widget;
      if (w is Container && w.decoration == _cardDeco) {
        nCards++;
        cardR ??= _rectOf(a);
      }
      return true;
    });
    final cr = cardR;
    s.cards = nCards;
    s.cardTop = cr == null ? 0.0 : cr.top - vpTop + px;
    s.inCard = cr != null && _inside(r, cr);
    final want = exp[s.id];
    final texts = <String>[];
    var allIn = true;
    var allHit = true;
    for (final pe in _below(e, (w) => w is RichText)) {
      final rp = pe.renderObject;
      if (rp is! RenderParagraph) continue;
      final pr = _rectOf(pe);
      final plain = TextLayout.plain(rp.text.toPlainText(includeSemanticsLabels: false));
      texts.add(plain);
      allIn = allIn && _inside(pr, r) && _inside(pr, visR) && (cr == null || _inside(pr, cr));
      allHit = allHit && t.hitTestOnBinding(pr.center).path.any((x) => x.target == inkRo);
      s.brk += wordBreaks(rp).where((b) => !b.forced).length;
      if (rp.didExceedMaxLines) s.ell++;
      final fg = <Color>[];
      _spanColors(rp.text, null, fg);
      final bg = _bgOf(rp);
      for (final f in fg) {
        final c = _contrast(Color.alphaBlend(f, bg.bg), bg.bg);
        s.minCr = math.min(s.minCr, c);
        if (c < 4.5) low++;
        colorLines.add('N352 $tok color id=${s.id} t=$plain fg=${_hex(f)} ${bg.raw} cr=${c.toStringAsFixed(2)}');
      }
      if (want == null || fg.isEmpty) continue;
      if (plain == want.name) s.nameFg = fg.first;
      if (plain == want.biz) s.bizFg = fg.first;
      if (plain == want.date) s.dateFg = fg.first;
      if (plain == want.label) {
        final comp = bg.bg;
        final band = _bandOf(want.d);
        final b = want.d <= 3 ? 0 : (want.d <= 7 ? 1 : 2);
        final ok = [(band.r, comp.r), (band.g, comp.g), (band.b, comp.b)]
            .every((q) => ((0.12 * _ch8(q.$1) + 0.88 * 255).round() - _ch8(q.$2)).abs() <= 1);
        s.chipFg = fg.first;
        s.chipBg = _decoColorAbove(pe);
        s.chipCr = _contrast(Color.alphaBlend(fg.first, comp), comp);
        bandHex.putIfAbsent(b, () => _hex(comp));
        bandOk[b] = (bandOk[b] ?? true) && ok;
      }
    }
    s.texts = texts;
    s.textsIn = allIn;
    s.whole = allHit;
  }

  /// 묶음 제목 g 의 화면 top(지금 만들어져 있지 않으면 null).
  double? titleTop(int g) {
    for (final pe in find.descendant(of: find.byType(ListView), matching: find.byType(RichText), skipOffstage: false).evaluate()) {
      final w = pe.widget;
      if (w is! RichText) continue;
      final m = _titleRe.firstMatch(_plainOf(w));
      if (m != null && m.group(1) == _groupTitles[g]) return _rectOf(pe).top;
    }
    return null;
  }

  /// 행 id 의 화면 top(기준판 경계 캡처 앵커 — 지금 만들어져 있지 않으면 null).
  double? rowTop(String id) {
    final vpTop = t.getRect(scroller).top;
    final px = pos.pixels;
    for (final e in find.descendant(of: find.byType(ListView), matching: find.byType(InkWell), skipOffstage: false).evaluate()) {
      final r = _rectOf(e);
      if (_idOf(e, r.top - vpTop + px) == id) return r.top;
    }
    return null;
  }

  /// 실제 끌기 한 번 — Scrollable 은 DragStartBehavior.start 라 첫 터치 슬롭(kDragSlopDefault)을 버리므로 그만큼 더 끈다.
  Future<double> dragBy(double d) async {
    final p0 = pos.pixels;
    await t.drag(scroller, Offset(0, d > 0 ? -(d + kDragSlopDefault) : -d + kDragSlopDefault));
    for (var j = 0; j < 8; j++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    return pos.pixels - p0;
  }

  /// 처음부터 끝까지 실제 끌기 — 걸음(보이는 칸 높이 × 0.2)마다 다시 찾아 잰다(행 높이 ≤ 보이는 칸 − 걸음 이면 어느 위치에선가 행 전체가
  ///   보이는 칸 안에 든다 · B 추정 칸 ≈ 407 · 걸음 ≈ 81 · 가장 큰 행 ≈ 267). 앵커 k 가 보이는 칸 위 + 8 에서 한 걸음 안으로 오면
  ///   그 거리만큼만 끌어 맞추고 onAnchor(k) 를 부른다(건너뛰는 행 0). 끝까지 못 맞춘 앵커는 끝 위치에서 al=false 로 부른다.
  Future<void> walk({
    required int anchors,
    required double? Function(int k) anchorTop,
    required Future<void> Function(int k, bool al, bool end) onAnchor,
  }) async {
    observe();
    vh = vis.height;
    step = math.max(48.0, vh * 0.2);
    var k = 0;
    for (var guard = 0; guard < 200; guard++) {
      final atEnd = pos.pixels >= pos.maxScrollExtent - 0.5;
      if (k < anchors) {
        final top = anchorTop(k);
        final want = vis.top + 8;
        if (top != null && top - want <= step + 0.5) {
          if (top - want > 0.5 && !atEnd) {
            await dragBy(top - want);
            observe();
          }
          final top2 = anchorTop(k);
          final vt = vis.top;
          final al = top2 != null && top2 >= vt - 0.5 && top2 <= vt + 16.5;
          await onAnchor(k, al, pos.pixels >= pos.maxScrollExtent - 0.5);
          k++;
          continue;
        }
        if (atEnd) {
          await onAnchor(k, false, true);
          k++;
          continue;
        }
      }
      if (atEnd) break;
      final moved = await dragBy(step);
      steps++;
      observe();
      if (moved.abs() < 0.5) break;
    }
    while (k < anchors) {
      await onAnchor(k, false, pos.pixels >= pos.maxScrollExtent - 0.5);
      k++;
    }
    endReached = pos.pixels >= pos.maxScrollExtent - 0.5;
    maxPx = pos.maxScrollExtent;
  }

  /// 방문 기록 정리 — [order] = 기존 `_items` 순서(기대). sp12/sp16/sp24 = 화면과 같은 ResponsiveHelper 간격.
  _Sum sum(List<String> order, double sp12, double sp16, double sp24) {
    final o = _Sum();
    final list = rows.values.toList()..sort((a, b) => a.tops.first.compareTo(b.tops.first));
    o.n = list.length;
    o.keyed = list.where((s) => s.keyed).length;
    o.dup = dupFrames + list.where((s) => s.tops.reduce(math.max) - s.tops.reduce(math.min) > 1.0).length;
    o.full = list.where((s) => s.full).length;
    o.ids = _w(list.map((s) => s.id).join(','));
    o.exact = o.ids == order.join(',');
    o.last = list.isEmpty ? '-' : list.last.id;
    var sorted = list.isNotEmpty;
    for (var i = 1; i < list.length; i++) {
      final a = exp[list[i - 1].id];
      final b = exp[list[i].id];
      if (a == null || b == null || b.d < a.d) sorted = false;
    }
    o.order = sorted;
    final tl = titles.values.toList()..sort((a, b) => a.abs.top.compareTo(b.abs.top));
    o.titles = tl.length;
    o.seq = _w(tl.map((x) => x.g.toString()).join(','));
    o.counts = _w(tl.map((x) => x.n.toString()).join(','));
    o.sum = tl.fold<int>(0, (a, x) => a + x.n);
    final cl = cards.values.toList()..sort((a, b) => a.top.compareTo(b.top));
    o.cards = cl.length;
    final byGroup = <int, List<String>>{};
    var one = list.isNotEmpty;
    var match = list.isNotEmpty;
    for (final s in list) {
      var g = -1;
      if (s.cards == 1) {
        for (final x in tl) {
          if (x.abs.top < s.cardTop) g = x.g;
        }
      } else {
        one = false;
      }
      s.g = g;
      o.groupOf[s.id] = g;
      final e = exp[s.id];
      if (e == null || _grp(e.d) != g) match = false;
      byGroup.putIfAbsent(g, () => <String>[]).add(s.id);
    }
    o.one = one;
    o.match = match;
    final concat = <String>[for (final x in tl) ...?byGroup[x.g]];
    o.concat = list.isNotEmpty && concat.length == list.length && concat.join(',') == order.join(',');
    var counted = tl.isNotEmpty;
    for (final x in tl) {
      if ((byGroup[x.g]?.length ?? 0) != x.n) counted = false;
    }
    o.empty = counted && cl.length == tl.length;
    final tcs = <double>[];
    final cgs = <double>[];
    for (var i = 0; i < tl.length; i++) {
      final tb = tl[i].abs.bottom;
      Rect? card;
      for (final r in cl) {
        if (card == null && r.top >= tb - 0.5) card = r;
      }
      if (card == null) continue;
      tcs.add(card.top - tb);
      if (i + 1 < tl.length) cgs.add(tl[i + 1].abs.top - card.bottom);
    }
    o.tc = tcs.isEmpty ? '-' : tcs.map(_f).join(',');
    o.cg = cgs.isEmpty ? '-' : cgs.map(_f).join(',');
    o.gap = tl.isNotEmpty && tcs.length == tl.length && tcs.every((v) => (v - sp12).abs() <= 0.5) &&
        cgs.every((v) => (v - sp24).abs() <= 0.5);
    o.top = tl.isNotEmpty && (tl.first.abs.top - sp16).abs() <= 0.5;
    var textFull = list.isNotEmpty;
    var labels = list.isNotEmpty;
    var dates = list.isNotEmpty;
    var chipc = list.isNotEmpty;
    var neutral = list.isNotEmpty;
    var inrow = list.isNotEmpty;
    var incard = list.isNotEmpty;
    var hitAll = list.isNotEmpty;
    var whole = list.isNotEmpty;
    var en = list.isNotEmpty;
    var minh = double.infinity;
    for (final s in list) {
      final e = exp[s.id];
      if (e == null || !s.measured) {
        textFull = false;
        labels = false;
        dates = false;
        chipc = false;
        neutral = false;
        inrow = false;
        incard = false;
        hitAll = false;
        whole = false;
        en = false;
        continue;
      }
      textFull = textFull && _sameList(s.texts, [e.name, e.biz, e.date, e.label]);
      labels = labels && s.texts.contains(e.label);
      dates = dates && s.texts.contains(e.date);
      chipc = chipc && s.chipBg == _bandOf(e.d).withValues(alpha: 0.12) && s.chipFg == _darkOf(e.d);
      neutral = neutral && s.nameFg == AppColors.grey700 && s.bizFg == AppColors.textSecondary && s.dateFg == AppColors.textSecondary;
      inrow = inrow && s.textsIn;
      incard = incard && s.inCard;
      hitAll = hitAll && s.hit;
      whole = whole && s.whole;
      en = en && s.en;
      minh = math.min(minh, s.h);
      o.brk += s.brk;
      o.ell += s.ell;
      o.minCr = math.min(o.minCr, s.minCr);
      o.chipCr = math.min(o.chipCr, s.chipCr);
    }
    o.textFull = textFull;
    o.labels = labels;
    o.dates = dates;
    o.chipc = chipc;
    o.neutral = neutral;
    o.inrow = inrow;
    o.incard = incard;
    o.hit = hitAll;
    o.whole = whole;
    o.en = en;
    o.minh = minh.isFinite ? minh : 0.0;
    o.gtFull = tl.isNotEmpty && tl.every((x) => x.plain == '${_groupTitles[x.g]} (${x.n})' && x.n == (byGroup[x.g]?.length ?? -1));
    o.gtBrk = tl.fold<int>(0, (a, x) => a + x.brk);
    o.gtVis = tl.isNotEmpty && tl.every((x) => x.full);
    o.gtNeutral = tl.isNotEmpty &&
        tl.every((x) => x.colors.length == 2 && x.colors[0] == AppColors.textPrimary && x.colors[1] == AppColors.textSecondary);
    o.titleCr = tl.fold<double>(99, (a, x) => math.min(a, x.minCr));
    return o;
  }

  /// 사람 대조용 상세(N352 줄 — gate 의 선언 줄이 아니다): 행 · 제목 · 원색 값.
  void dump() {
    final list = rows.values.toList()..sort((a, b) => a.tops.first.compareTo(b.tops.first));
    for (final s in list) {
      final chip = s.chipBg == null ? '-' : _hex(s.chipBg!);
      _out('N352 $tok row id=${s.id} keyed=${s.keyed} g=${s.g} top=${_f(s.tops.first)} h=${_f(s.h)} cards=${s.cards} full=${s.full} '
          'hit=${s.hit} whole=${s.whole} texts=${s.texts.join('|')} brk=${s.brk} cr=${s.minCr.toStringAsFixed(2)} chip=$chip');
    }
    for (final x in titles.values) {
      _out('N352 $tok title g=${x.g} n=${x.n} top=${_f(x.abs.top)} text=${x.plain} full=${x.full} brk=${x.brk}');
    }
    for (final l in colorLines) {
      _out(l);
    }
  }
}

/// 한 시험(보기 × 상태)의 공통 손잡이 — need(시험 배선 · 존재 즉시 단언) · chk(화면 판정 — 측정값만 모았다가 마지막에) · shot(캡처).
class _Ctx {
  _Ctx(this.t, this.tok, this.key, this.w, this.h, this.s, this.need, this.chk, this.shot);
  final WidgetTester t;
  final String tok;
  final GlobalKey key;
  final double w;
  final double h;
  final double s;
  final void Function(String k, bool ok, String why) need;
  final void Function(String k, bool ok, String why) chk;
  final Future<void> Function(String id, String state, bool al, bool end, bool same) shot;
  Rect get screen => Offset.zero & Size(w, h);
}

Future<void> _pumpScreen(_Ctx x, ExpiringContractsReads reads) async {
  await x.t.pumpWidget(RepaintBoundary(
    key: x.key,
    child: ChangeNotifierProvider<NotificationProvider>(
      create: (_) => NotificationProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RoleTheme.businessAdminTheme,
        builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(x.s)), child: child!),
        home: ExpiringContractsScreen(
          businessIds: const ['b1', 'b2'],
          businesses: [_biz('b1', _bizLong), _biz('b2', _bizShort)],
          reads: reads,
        ),
      ),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await x.t.pump(const Duration(milliseconds: 50));
  }
}

/// 화면과 같은 ResponsiveHelper 간격(12 · 16 · 24).
({double sp12, double sp16, double sp24}) _spacing(WidgetTester t) {
  final ctx = t.element(find.byType(ExpiringContractsScreen));
  return (sp12: ResponsiveHelper.spacing(ctx, 12), sp16: ResponsiveHelper.spacing(ctx, 16), sp24: ResponsiveHelper.spacing(ctx, 24));
}

// ── 상태별 ────────────────────────────────────────────────────────────────

/// LIST — 기존 10행 + 제외 2. 시작 · 각 묶음 경계(2 · 3 · 4번째 제목을 보이는 칸 위로) · 끝 캡처.
Future<void> _runList(_Ctx x) async {
  final t = x.t;
  final tok = x.tok;
  final fx = _fixture(_listRows);
  final reads = _Reads(fx.apps, fx.users, withProposal: true);
  await _pumpScreen(x, reads.seam);
  final nList = find.byType(ListView).evaluate().length;
  x.need('목록 1(기준판 · 후보 모두 ListView)', nList == 1, '목록 $nList');
  final headOk = _rich((p) => p == '만료 · 결정 필요 1명 · 곧 종료 9명').evaluate().length == 1;
  final sp = _spacing(t);
  final probe = _Probe(t, x.screen, tok, _nameMap(_listRows), _expOf(_listRows));
  probe.observe();
  await x.shot('1top', 'list-top', true, false, false);
  const shotIds = ['2gtwo', '3gthree', '4gfour'];
  const firstOf = ['a-디데이', 'a-넷', 'a-여덟'];
  final anchorOk = <bool>[];
  var lastPx = probe.pos.pixels;
  await probe.walk(
    anchors: 3,
    anchorTop: (k) => _before ? probe.rowTop(firstOf[k]) : probe.titleTop(k + 1),
    onAnchor: (k, al, end) async {
      final px = probe.pos.pixels;
      final same = (px - lastPx).abs() < 0.5;
      lastPx = px;
      anchorOk.add(al || end);
      await x.shot(shotIds[k], 'group-${k + 2}-boundary', al, end, same);
    },
  );
  final pxEnd = probe.pos.pixels;
  await x.shot('5end', 'list-end', true, probe.endReached, (pxEnd - lastPx).abs() < 0.5);
  final s = probe.sum(_listOrder, sp.sp12, sp.sp16, sp.sp24);
  probe.dump();
  final excl = !probe.rows.containsKey('a-열여섯') && !probe.rows.containsKey('a-대기제안');
  final d16 = probe.rows.containsKey('a-열여섯');
  final pend = probe.rows.containsKey('a-대기제안');
  final l3 = probe.rows['a-셋로컬'];
  final u3 = probe.rows['a-셋유티시'];
  // local · UTC 같은 KST 자정 instant — 날짜 글자 · 칩 라벨(행 글자 끝 둘) · 묶음이 같아야 한다.
  final utc = l3 != null && u3 != null && l3.texts.length >= 2 && _sameList(_tail2(l3.texts), _tail2(u3.texts)) && l3.g == u3.g;
  final invis = s.n > 0 && s.full == s.n;
  final rx = s.minh >= 48 - 0.01;
  final sample = probe.bandOk.length == 3 && probe.bandOk.values.every((v) => v);
  final bgE = probe.bandHex[0] ?? '-';
  final bgW = probe.bandHex[1] ?? '-';
  final bgB = probe.bandHex[2] ?? '-';
  final calls = reads.calls;
  final prop = reads.prop;
  final users = reads.user;
  final dm = s.gOf('a-만료둘');
  final d0 = s.gOf('a-디데이');
  final d3 = s.gOf('a-셋로컬');
  final d4 = s.gOf('a-넷');
  final d7 = s.gOf('a-일곱');
  final d8 = s.gOf('a-여덟');
  final d15 = s.gOf('a-열다섯');
  final allAnchors = anchorOk.length == 3 && anchorOk.every((v) => v);
  _out('D352 $tok att load calls=$calls prop=$prop users=$users');
  _out('D352 $tok att head ok=$headOk');
  _out('D352 $tok att walk steps=${probe.steps} max=${_f(probe.maxPx)} vh=${_f(probe.vh)} step=${_f(probe.step)} end=${probe.endReached} last=${s.last}');
  _out('D352 $tok att rows n=${s.n} keyed=${s.keyed} dup=${s.dup} ids=${s.ids} full=${s.full} excl=$excl order=${s.order}');
  _out('D352 $tok att groups titles=${s.titles} seq=${s.seq} counts=${s.counts} sum=${s.sum} cards=${s.cards} one=${s.one} concat=${s.concat} '
      'match=${s.match} empty=${s.empty} gap=${s.gap} top=${s.top} tc=${s.tc} cg=${s.cg}');
  _out('D352 $tok att bounds dm=$dm d0=$d0 d3=$d3 d4=$d4 d7=$d7 d8=$d8 d15=$d15 utc=$utc d16=$d16 pend=$pend');
  _out('D352 $tok att text full=${s.textFull} labels=${s.labels} dates=${s.dates} chipc=${s.chipc} neutral=${s.neutral} inrow=${s.inrow} '
      'incard=${s.incard} invis=$invis brk=${s.brk} ell=${s.ell}');
  _out('D352 $tok att tap minh=${_f(s.minh)} rx=$rx hit=${s.hit} whole=${s.whole} en=${s.en}');
  _out('D352 $tok att contrast min=${s.minCr.toStringAsFixed(2)} chip=${s.chipCr.toStringAsFixed(2)} title=${s.titleCr.toStringAsFixed(2)} '
      'low=${probe.low} sample=$sample bgE=$bgE bgW=$bgW bgB=$bgB');
  _out('D352 $tok att gtitle n=${s.titles} full=${s.gtFull} brk=${s.gtBrk} invis=${s.gtVis} neutral=${s.gtNeutral}');
  x.chk('배선 — 조회 2 · 대기 제안 2 · 이름 2(끌기 중 재조회 0)', calls == 2 && prop == 2 && users == 2, 'calls $calls prop $prop users $users');
  if (!_before) {
    final ids = s.ids;
    final seq = s.seq;
    final counts = s.counts;
    x.chk('strict 요약 줄 그대로', headOk, '');
    x.chk('strict 실제 끌기로 끝 도달 · 마지막 행 = a-열다섯', probe.endReached && s.last == 'a-열다섯', 'end ${probe.endReached} last ${s.last}');
    x.chk('strict 행 정확 10 · 키 10 · 중복 0 · 전부 보임 · 순서 = 기존 _items · 제외 2', s.n == 10 && s.keyed == 10 && s.dup == 0 && s.full == 10 && s.exact && s.order && excl,
        'n ${s.n} keyed ${s.keyed} dup ${s.dup} full ${s.full} ids $ids excl $excl');
    x.chk('strict 묶음 0,1,2,3 · 1/4/2/3 · 합 10 · 카드 4 · 행마다 카드 1 · 위치 묶음 = 남은 날 묶음 · 이어 붙이면 원래 순서 · 빈 묶음 0',
        seq == '0,1,2,3' && counts == '1,4,2,3' && s.sum == 10 && s.cards == 4 && s.one && s.match && s.concat && s.empty,
        'seq $seq counts $counts sum ${s.sum} cards ${s.cards} one ${s.one} match ${s.match} concat ${s.concat} empty ${s.empty}');
    x.chk('strict 간격 — 제목→카드 · 카드→다음 제목 · 첫 제목 위', s.gap && s.top, 'tc ${s.tc} cg ${s.cg} top ${s.top}');
    x.chk('strict 경계 0/3/4/7/8/15 · 만료 · local/UTC 같은 날 · D16 · 응답 대기 부재',
        dm == '0' && d0 == '1' && d3 == '1' && d4 == '2' && d7 == '2' && d8 == '3' && d15 == '3' && utc && !d16 && !pend,
        'dm $dm d0 $d0 d3 $d3 d4 $d4 d7 $d7 d8 $d8 d15 $d15 utc $utc d16 $d16 pend $pend');
    x.chk('strict 행 글자 전문(이름 · 사업장 · 날짜 · 칩) · 칩 색 · 중립 읽기색 · 행/카드/보이는 칸 안 · 낱말 경계 · 말줄임 0',
        s.textFull && s.labels && s.dates && s.chipc && s.neutral && s.inrow && s.incard && invis && s.brk == 0 && s.ell == 0,
        'full ${s.textFull} chipc ${s.chipc} neutral ${s.neutral} inrow ${s.inrow} incard ${s.incard} invis $invis brk ${s.brk} ell ${s.ell}');
    x.chk('strict 행 받는 자리 ≥ 48 · 중심 hit · 글자 전부 같은 수신자 · onTap', rx && s.hit && s.whole && s.en,
        'minh ${_f(s.minh)} hit ${s.hit} whole ${s.whole} en ${s.en}');
    x.chk('strict 실바탕 대비 ≥ 4.5(글자 · 칩 · 제목) · 칩 바탕 채널 대조', probe.low == 0 && sample && s.minCr >= 4.5 && s.chipCr >= 4.5 && s.titleCr >= 4.5,
        'low ${probe.low} sample $sample min ${s.minCr} chip ${s.chipCr} title ${s.titleCr} $bgE $bgW $bgB');
    x.chk('strict 묶음 제목 전문 · (n) = 행 수 · 보임 · 중립색 · 낱말 경계', s.titles == 4 && s.gtFull && s.gtVis && s.gtNeutral && s.gtBrk == 0,
        'titles ${s.titles} full ${s.gtFull} vis ${s.gtVis} neutral ${s.gtNeutral} brk ${s.gtBrk}');
    x.chk('strict 경계 캡처 — 제목을 보이는 칸 위로 맞춤(al) 또는 끝(end)', allAnchors, anchorOk.join(','));
  }
}

/// EMPTY — 전체 0건은 기존 빈 상태(묶음 제목 · 카드 0).
Future<void> _runEmpty(_Ctx x) async {
  final tok = x.tok;
  final fx = _fixture(_listRows);
  final reads = _Reads(fx.apps, fx.users, withProposal: true, empty: true);
  await _pumpScreen(x, reads.seam);
  final titleN = _rich((p) => p == '결정이 필요한 계약이 없어요').evaluate().length;
  x.need('빈 상태 제목 1', titleN == 1, '개수 $titleN');
  final rowsN = find.descendant(of: find.byType(ListView), matching: find.byType(InkWell), skipOffstage: false).evaluate().length;
  final cardsN = find.byWidgetPredicate((w) => w is Container && w.decoration == _cardDeco, skipOffstage: false).evaluate().length;
  final noGroups = _rich(_isTitle).evaluate().isEmpty;
  final noErr = _rich((p) => p == '계약 종료 예정 정보를 불러오지 못했어요').evaluate().isEmpty;
  final calls = reads.calls;
  final prop = reads.prop;
  final users = reads.user;
  _out('D352 $tok att load calls=$calls prop=$prop users=$users');
  _out('D352 $tok att empty rows=$rowsN cards=$cardsN nogroups=$noGroups noerr=$noErr');
  await x.shot('1empty', 'empty-state', true, false, false);
  x.chk('배선 — 조회 2 · 대기 제안 2 · 이름 0', calls == 2 && prop == 2 && users == 0, 'calls $calls prop $prop users $users');
  if (!_before) {
    x.chk('strict 전체 빈 상태 — 행 0 · 카드 0 · 묶음 제목 0 · 오류 문구 0', rowsN == 0 && cardsN == 0 && noGroups && noErr,
        'rows $rowsN cards $cardsN nogroups $noGroups noerr $noErr');
  }
}

/// ERROR — 실패는 성공 0건과 다르다(오류 본문 · 다시 시도). 다시 시도 → 같은 자료로 묶음 · 요약이 새로 만들어진다.
Future<void> _runError(_Ctx x) async {
  final t = x.t;
  final tok = x.tok;
  final fx = _fixture(_listRows);
  final reads = _Reads(fx.apps, fx.users, withProposal: true, failFirst: 2);
  await _pumpScreen(x, reads.seam);
  final errN = _rich((p) => p == '계약 종료 예정 정보를 불러오지 못했어요').evaluate().length;
  x.need('실패 본문 1', errN == 1, '개수 $errN');
  final retryF = _rich((p) => p == '다시 시도');
  final retryN = retryF.evaluate().length;
  x.need('다시 시도 1', retryN == 1, '개수 $retryN');
  final btnF = find.ancestor(of: retryF, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
  final outlined = t.widget(btnF) is OutlinedButton;
  final h = t.getRect(btnF).height;
  final rx = h >= 48 - 0.01;
  final noEmpty = _rich((p) => p == '결정이 필요한 계약이 없어요').evaluate().isEmpty;
  final noGroups = _rich(_isTitle).evaluate().isEmpty &&
      find.descendant(of: find.byType(ListView), matching: find.byType(InkWell), skipOffstage: false).evaluate().isEmpty;
  final calls1 = reads.calls;
  final prop1 = reads.prop;
  final users1 = reads.user;
  _out('D352 $tok att load calls=$calls1 prop=$prop1 users=$users1');
  _out('D352 $tok att error h=${_f(h)} outlined=$outlined rx=$rx noempty=$noEmpty nogroups=$noGroups');
  await x.shot('1error', 'error-body', true, false, false);
  await t.tap(btnF);
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final headOk = _rich((p) => p == '만료 · 결정 필요 1명 · 곧 종료 9명').evaluate().length == 1;
  var firstTop = double.infinity;
  var firstText = '-';
  for (final pe in _rich(_isTitle).evaluate()) {
    final r = _rectOf(pe);
    final w = pe.widget;
    if (w is RichText && r.top < firstTop) {
      firstTop = r.top;
      firstText = _plainOf(w);
    }
  }
  final first = firstText == '만료 · 결정 필요 (1)';
  final noErr = _rich((p) => p == '계약 종료 예정 정보를 불러오지 못했어요').evaluate().isEmpty;
  final calls2 = reads.calls;
  final prop2 = reads.prop;
  final users2 = reads.user;
  _out('D352 $tok att retry calls=$calls2 prop=$prop2 users=$users2 head=$headOk first=$first noerr=$noErr');
  await x.shot('2retry', 'after-retry-list', true, false, false);
  x.chk('배선 — 실패 조회 2(대기 제안 · 이름 0) · 다시 시도 뒤 누적 조회 4 · 대기 제안 2 · 이름 2',
      calls1 == 2 && prop1 == 0 && users1 == 0 && calls2 == 4 && prop2 == 2 && users2 == 2, 'first $calls1/$prop1/$users1 retry $calls2/$prop2/$users2');
  if (!_before) {
    x.chk('strict 오류 본문 — outlined 다시 시도 ≥ 48 · 빈 상태 문구 0 · 묶음/행 0', outlined && rx && noEmpty && noGroups,
        'outlined $outlined h ${_f(h)} noempty $noEmpty nogroups $noGroups');
    x.chk('strict 다시 시도 뒤 — 요약 · 첫 묶음 만료 (1) · 오류 문구 사라짐', headOk && first && noErr, 'head $headOk first $firstText noerr $noErr');
  }
}

/// COMBO — 빈 묶음 조합 셋(만료 + 8–15 / 0–3 + 4–7 / 만료만). 빠진 묶음의 제목 · 빈 카드 · 여백 0 · 요약 문구 3형.
Future<void> _runCombo(_Ctx x) async {
  final t = x.t;
  final tok = x.tok;
  final res = <({_Sum s, bool head})>[];
  for (final cb in _combos) {
    await t.pumpWidget(const SizedBox.shrink());
    final fx = _fixture(cb.rows);
    final reads = _Reads(fx.apps, fx.users, withProposal: false);
    await _pumpScreen(x, reads.seam);
    final nList = find.byType(ListView).evaluate().length;
    x.need('조합 목록 1 ${cb.shot}', nList == 1, '목록 $nList');
    final headOk = _rich((p) => p == cb.head).evaluate().length == 1;
    final sp = _spacing(t);
    final probe = _Probe(t, x.screen, tok, _nameMap(cb.rows), _expOf(cb.rows));
    probe.observe();
    await x.shot(cb.shot, cb.state, true, false, false);
    await probe.walk(anchors: 0, anchorTop: (k) => null, onAnchor: (k, al, end) async {});
    final s = probe.sum(cb.order, sp.sp12, sp.sp16, sp.sp24);
    probe.dump();
    res.add((s: s, head: headOk));
  }
  final r1 = res[0];
  final r2 = res[1];
  final r3 = res[2];
  _out('D352 $tok att cone seq=${r1.s.seq} counts=${r1.s.counts} cards=${r1.s.cards} rows=${r1.s.n} ids=${r1.s.ids} head=${r1.head} '
      'gap=${r1.s.gap} top=${r1.s.top} one=${r1.s.one} concat=${r1.s.concat}');
  _out('D352 $tok att ctwo seq=${r2.s.seq} counts=${r2.s.counts} cards=${r2.s.cards} rows=${r2.s.n} ids=${r2.s.ids} head=${r2.head} '
      'gap=${r2.s.gap} top=${r2.s.top} one=${r2.s.one} concat=${r2.s.concat}');
  _out('D352 $tok att cthree seq=${r3.s.seq} counts=${r3.s.counts} cards=${r3.s.cards} rows=${r3.s.n} ids=${r3.s.ids} head=${r3.head} '
      'gap=${r3.s.gap} top=${r3.s.top} one=${r3.s.one} concat=${r3.s.concat}');
  if (!_before) {
    final seqs = '${r1.s.seq}/${r2.s.seq}/${r3.s.seq}';
    final counts = '${r1.s.counts}/${r2.s.counts}/${r3.s.counts}';
    final cards = '${r1.s.cards}/${r2.s.cards}/${r3.s.cards}';
    final rowsN = '${r1.s.n}/${r2.s.n}/${r3.s.n}';
    final heads = r1.head && r2.head && r3.head;
    final gaps = r1.s.gap && r2.s.gap && r3.s.gap && r1.s.top && r2.s.top && r3.s.top;
    final shape = r1.s.one && r2.s.one && r3.s.one && r1.s.concat && r2.s.concat && r3.s.concat;
    x.chk('strict 빈 묶음 조합 — 있는 묶음만 제목 · 카드(0,3 / 1,2 / 0) · 건수 · 행 · 순서',
        seqs == '0,3/1,2/0' && counts == '1,2/1,1/2' && cards == '2/2/1' && rowsN == '3/2/2' && shape,
        'seq $seqs counts $counts cards $cards rows $rowsN shape $shape');
    x.chk('strict 빈 묶음 자리 여백 0(제목→카드 · 카드→다음 제목 · 첫 제목 위 간격 그대로) · 요약 3형', gaps && heads,
        'gap ${r1.s.tc}|${r1.s.cg} ${r2.s.tc}|${r2.s.cg} ${r3.s.tc}|${r3.s.cg} heads $heads');
  }
}

/// MUT — 제외 검사가 자명한 참이 아님(대기 제안 없음 · 16 → 15 이면 두 행이 나타난다 · 12행).
Future<void> _runMut(_Ctx x) async {
  final t = x.t;
  final tok = x.tok;
  final fx = _fixture(_mutRows);
  final reads = _Reads(fx.apps, fx.users, withProposal: false);
  await _pumpScreen(x, reads.seam);
  final nList = find.byType(ListView).evaluate().length;
  x.need('목록 1', nList == 1, '목록 $nList');
  final sp = _spacing(t);
  final probe = _Probe(t, x.screen, tok, _nameMap(_mutRows), _expOf(_mutRows));
  probe.observe();
  await x.shot('1top', 'mutation-top', true, false, false);
  await probe.walk(anchors: 0, anchorTop: (k) => null, onAnchor: (k, al, end) async {});
  final s = probe.sum(_mutOrder, sp.sp12, sp.sp16, sp.sp24);
  probe.dump();
  final has16 = probe.rows.containsKey('a-열여섯');
  final hasPend = probe.rows.containsKey('a-대기제안');
  final allFull = s.n > 0 && s.full == s.n;
  final calls = reads.calls;
  final prop = reads.prop;
  final users = reads.user;
  _out('D352 $tok att load calls=$calls prop=$prop users=$users');
  _out('D352 $tok att mut n=${s.n} ids=${s.ids} counts=${s.counts} has16=$has16 haspend=$hasPend full=$allFull');
  x.chk('배선 — 조회 2 · 대기 제안 2 · 이름 2', calls == 2 && prop == 2 && users == 2, 'calls $calls prop $prop users $users');
  if (!_before) {
    final counts = s.counts;
    x.chk('strict 변이 12행 — 두 행이 나타나고 순서 · 묶음 1/4/3/4', s.n == 12 && s.exact && counts == '1,4,3,4' && has16 && hasPend && allFull,
        'n ${s.n} ids ${s.ids} counts $counts has16 $has16 haspend $hasPend full $allFull');
  }
}

/// NAMES — 긴 이름 · 라틴 이름 · 동명이인(다른 지원서) · 이름 없음 · 긴 사업장의 전문 · 낱말 경계 · 카드 안 · 받는 자리.
Future<void> _runNames(_Ctx x) async {
  final t = x.t;
  final tok = x.tok;
  final fx = _fixture(_nameRows);
  final reads = _Reads(fx.apps, fx.users, withProposal: false);
  await _pumpScreen(x, reads.seam);
  final nList = find.byType(ListView).evaluate().length;
  x.need('목록 1', nList == 1, '목록 $nList');
  final sp = _spacing(t);
  final probe = _Probe(t, x.screen, tok, _nameMap(_nameRows), _expOf(_nameRows));
  probe.observe();
  final px1 = probe.pos.pixels;
  await x.shot('1top', 'names-top', true, false, false);
  await probe.walk(anchors: 0, anchorTop: (k) => null, onAnchor: (k, al, end) async {});
  final px2 = probe.pos.pixels;
  // 내용이 한 화면에 들어가면(스크롤 0) 끝 캡처는 시작과 같은 프레임이다 — same=true 로 분리해 적는다.
  await x.shot('2end', 'names-end', true, probe.endReached, (px2 - px1).abs() < 0.5);
  final s = probe.sum(_nameOrder, sp.sp12, sp.sp16, sp.sp24);
  probe.dump();
  final dupIds = probe.rows.values.where((r) => r.texts.contains('김민수')).map((r) => r.id).toSet();
  final dupName = dupIds.length == 2;
  final invis = s.n > 0 && s.full == s.n;
  final rx = s.minh >= 48 - 0.01;
  final calls = reads.calls;
  final prop = reads.prop;
  final users = reads.user;
  _out('D352 $tok att load calls=$calls prop=$prop users=$users');
  _out('D352 $tok att names n=${s.n} ids=${s.ids} counts=${s.counts} dupname=$dupName full=${s.textFull} brk=${s.brk} ell=${s.ell} '
      'invis=$invis incard=${s.incard} minh=${_f(s.minh)} rx=$rx hit=${s.hit}');
  x.chk('배선 — 조회 2 · 대기 제안 2 · 이름 2', calls == 2 && prop == 2 && users == 2, 'calls $calls prop $prop users $users');
  if (!_before) {
    final counts = s.counts;
    x.chk('strict 이름 5행 — 순서 · 묶음 1/2/1/1 · 동명이인 2행 보존', s.n == 5 && s.exact && counts == '1,2,1,1' && dupName,
        'n ${s.n} ids ${s.ids} counts $counts dupname $dupName');
    x.chk('strict 긴 이름 · 라틴 이름 · 이름 없음 · 긴 사업장 전문 · 낱말 경계 · 말줄임 0 · 카드/보이는 칸 안 · 받는 자리',
        s.textFull && s.brk == 0 && s.ell == 0 && invis && s.incard && rx && s.hit,
        'full ${s.textFull} brk ${s.brk} ell ${s.ell} invis $invis incard ${s.incard} minh ${_f(s.minh)} hit ${s.hit}');
  }
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    for (final c in _cases) {
      testWidgets('S020G-${v.id}-${c.id} 계약 확인 필요 — 기한 묶음 카드 · 행 식별 · 전문 · 실제 끌기 · 실바탕 대비', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        try {
          final tok = 'S020G-${v.id}-${c.id}';
          final mode = _before ? 'before' : 'strict';
          _out('D352 $tok begin mode=$mode phase=$_phase env=$_envLine manifest=$_manifest');
          await t.runAsync(vqLoadFonts);
          final overflows = <String>[];
          final fwErrors = <String>[];
          final prev = FlutterError.onError;
          FlutterError.onError = (d) {
            final m = d.exceptionAsString();
            if (m.contains('overflowed')) {
              final all = d.toString();
              final k = all.indexOf('The relevant error-causing widget was');
              final loc = k < 0 ? '' : all.substring(k).split('\n').skip(1).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
              overflows.add('${m.split('\n').first} @ $loc');
            } else {
              fwErrors.add(m.split('\n').first);
              prev?.call(d);
            }
          };
          addTearDown(() => FlutterError.onError = prev);
          t.view.physicalSize = Size(v.w, v.h);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          // 시험 배선 · 존재(뒤 측정이 기대는 것)는 바로 단언한다. 화면 판정은 모아 두었다가 넘침 수집기를 되돌린 뒤 한꺼번에(v34).
          void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
          final checks = <(String, bool, String)>[];
          void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));
          final key = GlobalKey();
          var nCap = 0;
          Future<void> shot(String id, String state, bool al, bool end, bool same) async {
            final sc = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable), skipOffstage: false);
            final px = sc.evaluate().isEmpty ? 0.0 : t.state<ScrollableState>(sc.first).position.pixels;
            nCap++;
            _out('D352 $tok shot $id px=${_f(px)} al=$al end=$end same=$same ovf=${overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': c.id,
              'state': state,
            });
          }

          final x = _Ctx(t, tok, key, v.w, v.h, v.s, need, chk, shot);
          switch (c.id) {
            case 'LIST':
              await _runList(x);
            case 'EMPTY':
              await _runEmpty(x);
            case 'ERROR':
              await _runError(x);
            case 'COMBO':
              await _runCombo(x);
            case 'MUT':
              await _runMut(x);
            case 'NAMES':
              await _runNames(x);
          }

          // 측정 끝 — 값은 모두 위에서 변수로 잡았다. 넘침 수집기를 되돌린 뒤 모은 단언을 던진다(v34 · 이 뒤 화면 읽기 0).
          final nOvf = overflows.length;
          final ovfRaw = overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '');
          final ovfText = overflows.join(' | ');
          final nFwErr = fwErrors.length;
          final fwText = fwErrors.join(' | ');
          if (!_before) {
            chk('strict 넘침 0', nOvf == 0, ovfText);
          }
          chk('미처리 framework 예외 0', nFwErr == 0, fwText);
          FlutterError.onError = prev;
          for (final c in checks) {
            expect(c.$2, isTrue, reason: '$tok ${c.$1} ${c.$3}');
          }
          final exc = t.takeException();
          _out('D352 $tok done state=${c.id} mode=$mode captures=$nCap overflows=$nOvf exc=${exc != null} ovfRaw=$ovfRaw');
          expect(exc, isNull, reason: '$tok 끝 예외 $exc');
        } catch (e) {
          _anyFail = true;
          rethrow;
        }
      }, skip: !_optIn);
    }
  }
}
