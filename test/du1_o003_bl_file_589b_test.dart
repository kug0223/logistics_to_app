// ignore_for_file: depend_on_referenced_packages
// [DU589b · 파일 단위 장부 셀] 관리자 '업무별 지원자' 창(WorkApplicantsDialog · DU-O003)의 결정 미이행 장부 행 이행 —
//   039 계약 '무효' 칩 글 error → errorDark(면 errorBg 그대로 · 판정138 R3 :46) ·
//   129 확정 막힘 이유 FULL '정원이 모두 차서 추가로 확정할 수 없어요.'(판정162 :60) · 비FULL = 원인을 단정하지 않는 표시 fallback(J129) ·
//   127 장기 희망/근무 기간 줄 = 판단 16/1.5/400 textPrimary(말줄임 0 · 판정157 :81) ·
//   128 채움 단추(확정 · 계약서 작성) 좌우 여백 16 → 12 · 높이(상하 15.5 · 주 버튼 최소 52) 그대로(판정162 :59 · J128).
//   before = 지금 A(work_applicants_dialog 96050cbd = DU562 후보) 기록 · strict = 후보(21bab304).
//   하네스 = DU559 r1 수리판(du1_o003_typo_t3_559_test 16906839 · TA12/RG18 성공)의 업무별 창 대역 · 읽기 경계 · 플랫폼 채널 관찰 · HTTP 차단 · 넘침 수집 그대로 +
//     DU562(b4029f2a · DONE 5/5) 글 측정 도우미(max 판 _fullShown · _textObs · _area · _hitWithin · _lineCount · _txt · _bringBuilt · _semOf · _textLine) 그대로.
//     값 = DU559 ROWS 대역에서 같은 모델 칸의 값만 바꾼다(계약 상태 voided · 공고 상태 FULL/CLOSED · 장기 공고 type contract + 장기 지원서 희망 시작일/종료일).
//     실패/지연 주입 0 · 응답 모양 변경 0.
//   누르는 것 0 — 확정 · 거절 · 계약서 작성 · 확정취소 · 제안 · 별표 · 카드 탭을 누르지 않는다(ensureVisible · 끌기 대비만).
//   기본 skip — TB before/du589bwa-tb/DU_BEFORE_OBSERVE=589 · TA after/du589bwa-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui show BoxHeightStyle;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/slot_model.dart' show SlotModel, SlotStatus;
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_applicants_reads.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/admin/applicant_row_surface.dart';

import 'support/du1_vq_capture.dart';
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

const _biz1 = 'biz1';
const _bizName = '강남 물류센터';

/// 소유자(BUSINESS_ADMIN) — DU526 _Owner 와 같은 override(창은 `checkForBusiness` · `watchBusinessPermissions` 를 부른다).
class _Owner extends UserProvider {
  final watched = <String>[];
  @override
  UserModel? get currentUser => UserModel(
      uid: 'admin1', username: 'admin1', name: '김관리', email: 'admin1@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const [_biz1], sealBase64: 'seal');
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
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  VoidCallback watchBusinessPermissions(String businessId) {
    watched.add(businessId);
    return () {};
  }
}

/// 근무일 = 3일 뒤 KST 자정(noshow_contract_dialog_gate_test 의 kDay 와 같은 식 — 증명된 대역).
final DateTime _day = () {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day + 3).subtract(const Duration(hours: 9));
}();
final DateTime _applied = DateTime.now().subtract(const Duration(hours: 3));
final DateTime _made = DateTime.now().subtract(const Duration(days: 3));

WorkDetailData _wd1() => WorkDetailData(
    wdId: 'wd1', workType: '홀서빙', startTime: '09:00', endTime: '18:00', requiredCount: 5, wage: 12000, wageType: 'hourly',
    applicationDeadline: DateTime.now().add(const Duration(days: 2)));

/// 둘째 업무 — '다른 업무 제안' · '근무 변경 제안' 이 서려면 제안할 다른 업무가 있어야 한다(:3256 offerableFrom).
WorkDetailData _wd2() => WorkDetailData(
    wdId: 'wd2', workType: '주방 보조', startTime: '13:00', endTime: '22:00', requiredCount: 3, wage: 12000, wageType: 'hourly',
    applicationDeadline: DateTime.now().add(const Duration(days: 2)));

/// [DU589b] 사례 — DU559 ROWS 대역(대기 3 · 확정 2 · 같은 읽기 경계 9 함수 · 같은 응답 모양)에서 같은 모델 칸의 **값만** 바꾼다.
///   VOID = 확정 c1 계약 상태 'voided'(무효 칩 · 장부 039) · FULL = 공고 상태 FULL(막힘 이유 FULL 원문 · 129) ·
///   CLSD = 공고 상태 CLOSED · 수동 마감 아님(막힘 이유 fallback · 129 J) ·
///   LTRM = 장기 공고(type contract · 슬롯 없음) + 장기 지원서(희망 시작일 · 종료일 — p2 만 희망 시작일 없음 → '장기:' 분기 · 127).
///   128(채움 단추 받는 자리)은 네 사례 모두에서 잰다.
const _cases = <({String id, int shots})>[(id: 'VOID', shots: 2), (id: 'FULL', shots: 2), (id: 'CLSD', shots: 2), (id: 'LTRM', shots: 2)];
const _names = <String, String>{'p1': '김별표', 'p2': '이선택', 'p3': '박대기', 'c1': '최확정', 'c2': '정미작성'};

TOModel _to(String kind) => kind == 'LTRM'
    ? TOModel(
        id: 'to1', businessId: _biz1, businessName: _bizName, type: 'contract', title: '장기 모집', creatorUID: 'admin1', status: TOStatus.active,
        workDetails: [_wd1(), _wd2()], rangeStart: _day, rangeEnd: _day.add(const Duration(days: 90)), workDays: const ['월', '수', '금'],
        totalRequired: 5, totalConfirmed: 2, totalPending: 3, isPublished: true, publishMode: 'immediate', createdAt: _made, statusUpdatedAt: _made)
    : TOModel(
        id: 'to1', businessId: _biz1, businessName: _bizName, type: 'flex', title: '단기 모집', creatorUID: 'admin1',
        status: switch (kind) { 'FULL' => TOStatus.full, 'CLSD' => TOStatus.closed, _ => TOStatus.active },
        workDetails: [_wd1(), _wd2()], totalRequired: 8, totalConfirmed: 2, totalPending: 3, isPublished: true, publishMode: 'immediate',
        createdAt: _made, statusUpdatedAt: _made);

TOItem _item(String kind) => TOItem(
    to: _to(kind),
    slot: kind == 'LTRM'
        ? null
        : SlotModel(id: 'slot1', toId: 'to1', date: _day, status: SlotStatus.open, workDetails: [_wd1(), _wd2()], createdAt: _made),
    workDetails: [_wd1(), _wd2()], confirmedCount: 2, pendingCount: 3, totalRequired: kind == 'LTRM' ? 5 : 8);

ApplicationModel _app(String kind, String id, String status) {
  final lt = kind == 'LTRM';
  return ApplicationModel(
      id: id, uid: 'u_$id', toId: 'to1', slotId: lt ? null : 'slot1', businessId: _biz1, businessName: _bizName, toTitle: lt ? '장기 모집' : '단기 모집',
      selectedWorkType: '홀서빙', wdId: 'wd1', startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly', status: status,
      workDate: _day, appliedAt: _applied, isStarred: id == 'p1',
      applicationType: lt ? AppType.longTerm : null, workDays: lt ? const ['월', '수', '금'] : null,
      desiredStartDate: lt && id != 'p2' ? _day : null, workEndDate: lt ? _day.add(const Duration(days: 60)) : null);
}

/// 대역 — 대기 3(p1 별표) · 확정 2(c1 계약 완료 또는 무효 · c2 계약 미작성). 사례마다 새로 만든다(공유 상태 0).
List<ApplicationModel> _apps(String kind) => [
      _app(kind, 'p1', AppStatus.pending), _app(kind, 'p2', AppStatus.pending), _app(kind, 'p3', AppStatus.pending),
      _app(kind, 'c1', AppStatus.confirmed), _app(kind, 'c2', AppStatus.confirmed),
    ];

/// 창의 읽기 경계(주입) — DU559 `_Reads` 와 같은 9 함수 · 같은 응답 모양. 실패/지연/빈 응답 분기 0. 쓰기는 여기 없다.
class _Reads {
  _Reads(this.kind);

  final String kind;
  final calls = <String, int>{};
  void _hit(String k) => calls[k] = (calls[k] ?? 0) + 1;

  WorkApplicantsReads reads() => WorkApplicantsReads(
        applications: (to, {slotId, required purpose}) {
          _hit('applications');
          return Future<List<ApplicationModel>>.value(_apps(kind));
        },
        usersBatch: (uids, {required businessId, purpose}) async {
          _hit('users');
          return {
            for (final u in uids)
              u: UserModel(uid: u, username: u, name: _names[u.replaceFirst('u_', '')] ?? '근로자 $u', email: '$u@alfit.local', role: UserRole.USER),
          };
        },
        weeklyAttendance: ({required businessId, required weekStart, required weekEnd}) async {
          _hit('weekly');
          return <String, List<AttendanceModel>>{};
        },
        contractStatusBatch: (ids, {required businessId}) async {
          _hit('contracts');
          return ContractStatusBatch(statuses: <String, String?>{for (final x in ids) if (x == 'c1') x: kind == 'VOID' ? 'voided' : 'completed'});
        },
        hasWorkedMap: ({required businessId, required date}) async {
          _hit('hasWorked');
          return const <String, bool>{};
        },
        idCardStatusBatch: ({required requesterId, required targetUserIds}) async {
          _hit('idCard');
          return const <String, String>{};
        },
        capacity: (to, {slotId, slotWorkDetails}) async {
          _hit('capacity');
          return <String, dynamic>{
            'workDetails': [_wd1(), _wd2()],
            'workStats': {
              'wd1': {'confirmed': 2, 'pending': 3},
              'wd2': {'confirmed': 0, 'pending': 0},
            },
            'statsFailed': false,
          };
        },
        reassignProposals: (bizId) async {
          _hit('reassign');
          return const [];
        },
        contractAttendances: ({required businessId, required first, required last}) async {
          _hit('contractAtt');
          return const <AttendanceModel>[];
        },
      );
}

/// CF Pigeon 채널 — RG 시험(offer_workdetail_roster · noshow_contract_dialog_gate)과 같은 'unavailable' 응답을 주고 센다.
const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// [DU526 과 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널.
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du589b.fake.auth.';
const _authListeners = ['registerIdTokenListener', 'registerAuthStateListener'];

/// 원래 경로로 보내는 Flutter 기반 채널과 이유.
const _frameworkAllow = <String, String>{
  'flutter/assets': 'AssetBundle(아이콘 글꼴 · 이미지 매니페스트) 읽기',
  'flutter/platform': 'MaterialApp Title · SystemSound/Haptic(InkWell 탭 피드백)',
  'flutter/navigation': '루트 Navigator 경로 보고',
  'flutter/mousecursor': 'MouseRegion 커서 갱신(시험 포인터)',
  'flutter/restoration': 'RootRestorationScope 상태 복원 조회',
  'flutter/keyboard': 'HardwareKeyboard 상태 동기화',
  'flutter/accessibility': '의미 트리/알림 전달',
};

/// 모든 플랫폼 메시지 관찰 — 기반 채널은 원래 경로 · Auth 두 리스너는 setUpAll 모의 · CF 는 'unavailable' 응답 ·
///   그 밖은 이름을 기록하고 응답 null(플러그인 없음과 같은 결과). 예외를 삼키지 않는다 — 수는 줄로 남긴다.
class _Wire {
  final unexpected = <String>[];
  final cf = <String>[];
  final auth = <String>[];

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
    if (channel == _cfChannel) {
      cf.add(channel);
      return Future<ByteData?>.value(const StandardMessageCodec().encodeMessage(<Object?>['unavailable', 'test harness', null]));
    }
    for (final name in _authListeners) {
      if (channel == '$_authBase$name' || channel == '$_authFake$name') {
        auth.add(name);
        return handler?.call(message);
      }
    }
    if (_frameworkAllow.containsKey(channel)) {
      return handler != null ? handler(message) : m.delegate.send(channel, message);
    }
    unexpected.add(channel);
    return null;
  }
}

/// 외부 HTTP 차단 — 만들려는 시도를 기록하고 실패시킨다.
class _NoHttp extends HttpOverrides {
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    throw const SocketException('DU589b 관측 — 외부 HTTP 차단');
  }
}

Future<void> _loadFonts() async {
  Future<ByteData> b(String p) => File(p).readAsBytes().then((x) => ByteData.view(x.buffer));
  for (final fam in const ['NotoSansKR', 'Roboto']) {
    await (FontLoader(fam)
          ..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))
          ..addFont(b('assets/fonts/NotoSansKR-Bold.ttf')))
        .load();
  }
  await (FontLoader('FlutterTest')..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))).load();
  await (FontLoader('MaterialIcons')
        ..addFont(b('C:/Users/kug02/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')))
      .load();
}

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _enc(String s) => s.isEmpty ? '-' : base64Url.encode(utf8.encode(s)).replaceAll('=', '');

/// [a] 가 [b] **안**에 있는가(0.5px 허용).
bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

String _hex(Color c) {
  String h(double x) => (x * 255).round().toRadixString(16).padLeft(2, '0');
  return '${h(c.a)}${h(c.r)}${h(c.g)}${h(c.b)}';
}

/// WCAG 대비 — [fg] 글자 · [bg] 불투명 바탕.
double _contrast(Color fg, Color bg) {
  final a = Color.alphaBlend(fg, bg).computeLuminance();
  final b = bg.computeLuminance();
  final hi = a > b ? a : b;
  final lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

typedef _Probe = ({String label, Rect r, Color fill, Color fg, double cr, bool big, bool hit});

/// 버튼 하나의 관측값 — DU535 `_probe` 와 같은 식. 글 찾기만 `w is Text`(KeepWordsText 는 Text 하위 형 — find.byType(Text) 는 정확 형이라 못 찾는다).
_Probe _probe(WidgetTester t, Finder one, Color under) {
  final textF = find.descendant(of: one, matching: find.byWidgetPredicate((w) => w is Text), skipOffstage: true);
  final tw = t.widget<Text>(textF.first);
  final label = tw.data ?? '';
  final fg = tw.style?.color ?? Colors.black;
  final fill = t.widget<Material>(find.ancestor(of: one, matching: find.byType(Material)).first).color ?? Colors.transparent;
  final bg = fill.a == 0 ? under : Color.alphaBlend(fill, under);
  final r = t.getRect(one);
  final big = r.width >= 48 - 0.01 && r.height >= 48 - 0.01;
  final hit = t.hitTestOnBinding(r.center).path.any((x) => identical(x.target, t.renderObject(one)));
  return (label: label, r: r, fill: fill, fg: fg, cr: _contrast(fg, bg), big: big, hit: hit);
}

/// [DU589b] 카드(_buildApplicantCard ~ 주N회 배지 끝) 줄 범위 — 넘침 위치가 이 안이면 '카드 발 넘침'(raw 기록 · 판정은 화면 전체 넘침 0).
///   base 96050cbd :2554–3345 · 후보 21bab304 :2554–3345(편집 +12 −12 · 모두 이 범위 안 · 줄 수 같음) — 두 모드 같은 범위.
const int _ownLo = 2554;
const int _ownHi = 3345;
final RegExp _locRe = RegExp(r'work_applicants_dialog\.dart:(\d+)');

/// 시각 오류 수집 — 넘침은 원문 + 위치, 그 밖 framework 오류는 원문.
class _Seen {
  final overflows = <String>[];
  final other = <String>[];
  var own = 0;
  var unk = 0;

  void add(FlutterErrorDetails d) {
    final m = d.exceptionAsString();
    if (m.contains('overflowed')) {
      final full = d.toString();
      final k = full.indexOf('The relevant error-causing widget was');
      final loc = k < 0
          ? ''
          : full.substring(k).split('\n').skip(1).where((l) => l.trim().isNotEmpty).take(2).map((l) => l.trim()).join(' ');
      // 위치 줄이 아예 없으면 '모름'(어느 위젯인지 가릴 수 없다) · 이 창의 행 버튼 줄 범위면 '행 버튼 발'.
      final lines = [for (final x in _locRe.allMatches(loc)) int.parse(x.group(1)!)];
      if (loc.isEmpty) {
        unk++;
      } else if (lines.any((n) => n >= _ownLo && n <= _ownHi)) {
        own++;
      }
      overflows.add('${m.split('\n').first} @ $loc');
    } else {
      other.add(m);
    }
  }
}

final String _wj = String.fromCharCode(0x2060);
final String _zw = String.fromCharCode(0x200B);

bool _gap(String ch) => ch == ' ' || ch == '\n' || ch == '\t' || ch == _zw;

/// 그려진 글(표시 제어 문자 포함) 기준 — 낱말(공백 · 개행 · ZWSP 사이) 안에서 줄이 바뀐 횟수. NBSP · WORD JOINER 로 묶은 덩어리는 한 낱말이다.
int _midBreaks(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  var n = 0;
  double? lastTop;
  var lastIdx = -1;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == '\n') {
      lastTop = null;
      lastIdx = i;
      continue;
    }
    if (ch == _wj || ch == _zw) continue;
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final top = bx.first.top;
    final half = (bx.first.bottom - bx.first.top) / 2;
    final wrapped = lastTop != null && top > lastTop + half;
    if (wrapped) {
      var gap = _gap(ch) || (lastIdx >= 0 && _gap(s[lastIdx]));
      for (var k = lastIdx + 1; k < i; k++) {
        if (_gap(s[k])) gap = true;
      }
      if (!gap) n++;
    }
    if (lastTop == null || wrapped) lastTop = top;
    lastIdx = i;
  }
  return n;
}

/// 글 전문이 그려졌는가 — 마지막 글자까지 자리(box)가 문단 크기 안에 있다(말줄임으로 잘린 글자는 자리가 없다).
bool _fullShown(RenderParagraph rp, Size size) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  for (var i = s.length - 1; i >= 0; i--) {
    final ch = s[i];
    if (ch == _wj || _gap(ch)) continue;
    // [DU560 repair 3 proposed / decision168] Vertical max selection box; horizontal tight right; tolerance unchanged.
    // This measures selection-box placement, not ink bounds or ancestor clipping.
    final sel = TextSelection(baseOffset: i, extentOffset: i + 1);
    final tight = rp.getBoxesForSelection(sel);
    final mx = rp.getBoxesForSelection(sel, boxHeightStyle: ui.BoxHeightStyle.max);
    return tight.isNotEmpty && mx.isNotEmpty && mx.first.bottom <= size.height + 0.5 && tight.first.right <= size.width + 0.5;
  }
  return false;
}

typedef _TextObs = ({bool shown, bool name, bool full, bool ell0, int brk, Size size});

/// Text 하나의 관측값(잰 즉시 값으로 굳힌다) — 그려진 글(표시 제어 문자를 뺀 것) · 읽는 이름이 각각 [want] 원문과 같은가 · 전문 · 말줄임 설정 · 낱말 안 끊김 수.
_TextObs _textObs(WidgetTester t, Finder textF, String want) {
  final rp = t.renderObject<RenderParagraph>(find.descendant(of: textF, matching: find.byType(RichText), skipOffstage: true).first);
  final size = rp.size;
  final shown = TextLayout.plain(rp.text.toPlainText(includeSemanticsLabels: false));
  final name = rp.text.toPlainText();
  return (shown: shown == want, name: name == want, full: _fullShown(rp, size), ell0: rp.overflow != TextOverflow.ellipsis, brk: _midBreaks(rp), size: size);
}

/// [f] 가 실제로 보일 수 있는 칸 — 화면 ∩ 조상 스크롤 칸 전부.
Rect _area(Finder f, Rect screen) {
  var a = screen;
  for (final e in find.ancestor(of: f, matching: find.byType(Scrollable)).evaluate()) {
    final ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize) a = a.intersect(ro.localToGlobal(Offset.zero) & ro.size);
  }
  return a;
}

/// [pos] 를 눌렀을 때 맞는 대상 중에 [f] 의 위젯(자손 포함)이 만든 render object 가 있는가.
bool _hitWithin(WidgetTester t, Finder f, Offset pos) {
  final own = <Object>{};
  void walk(Element e) {
    final ro = e.renderObject;
    if (ro != null) own.add(ro);
    e.visitChildren(walk);
  }

  walk(f.evaluate().first);
  return t.hitTestOnBinding(pos).path.any((x) => own.contains(x.target));
}

/// 그려진 문단의 줄 수 — 글자 자리(box)의 서로 다른 top 개수.
int _lineCount(RenderParagraph rp) {
  final n = rp.text.toPlainText(includeSemanticsLabels: false).length;
  final tops = <int>{};
  for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: n))) {
    tops.add(b.top.round());
  }
  return tops.length;
}

/// [f] 의 Text 위젯마다 그 안 RichText 문단 — Text 하나에 문단이 정확히 1 이 아니면 그 Text 는 뺀다(개수는 raw 에 남는다).
List<RenderParagraph> _parasOf(Finder f) {
  final out = <RenderParagraph>[];
  for (final e in f.evaluate()) {
    final rps = <RenderParagraph>[];
    void visit(Element x) {
      final ro = x.renderObject;
      if (x.widget is RichText && ro is RenderParagraph) rps.add(ro);
      x.visitChildren(visit);
    }
    e.visitChildren(visit);
    if (rps.length == 1) out.add(rps.first);
  }
  return out;
}

/// 글 조각별 실제 스타일 — 조상 스타일부터 차례로 merge. 빈 조각은 뺀다.
List<(String, TextStyle)> _spansOf(RenderParagraph rp) {
  final out = <(String, TextStyle)>[];
  void walk(InlineSpan s, TextStyle eff) {
    final e = s.style == null ? eff : eff.merge(s.style);
    if (s is TextSpan) {
      final tx = s.text;
      if (tx != null && tx.isNotEmpty) out.add((tx, e));
      for (final ch in s.children ?? const <InlineSpan>[]) {
        walk(ch, e);
      }
    }
  }
  walk(rp.text, const TextStyle());
  return out;
}

/// 스타일 서명 '크기/줄 높이/굵기/자간/색' — 크기 · 자간 소수 1 · 줄 높이 소수 2 · 굵기 값 · ARGB 8자리(없으면 n).
String _sig(TextStyle s) {
  String n(double? x, int d) => x == null ? 'n' : x.toStringAsFixed(d);
  final c = s.color;
  return [
    n(s.fontSize, 1),
    n(s.height, 2),
    s.fontWeight == null ? 'n' : s.fontWeight!.value.toString(),
    n(s.letterSpacing, 1),
    c == null ? 'n' : c.toARGB32().toRadixString(16).padLeft(8, '0'),
  ].join('/');
}

/// 칸 하나의 서명 집합 — 글 조각 서명을 모아 정렬 · '|'. 없으면 '-'.
String _sigsOf(List<(RenderParagraph, String)> ps) {
  final out = <String>{};
  for (final (p, _) in ps) {
    for (final (_, st) in _spansOf(p)) {
      out.add(_sig(st));
    }
  }
  final l = out.toList()..sort();
  return l.isEmpty ? '-' : l.join('|');
}

/// 그려진 글(묶음 문자를 뺀 것) · 위젯 글이 [want] 인 Text(Text.rich 포함) — DU523 의 찾기 술어와 같다.
///   [onstage] true = 화면에 그려지는 것만(머리 — O003 은 좁은 창 판정용 머리 사본을 Offstage 로 한 번 더 짓는다 · work_applicants_dialog:2038).
///   false = 지어진 것 전부(본문 — O002 본문은 지연 생성 목록 CustomScrollView/SliverList · ListView.separated · day_applicants_dialog:1457/:1476 —
///   B 에서 머리가 커지면 첫 묶음이 칸 밖(캐시 안)에 지어져 onstage 개수 0 이 될 수 있다 · DU573/DU581 TB STOP 교훈).
Finder _txt(Finder scope, String want, {bool onstage = true}) => find.descendant(
    of: scope,
    matching: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? w.textSpan?.toPlainText() ?? '') == want),
    skipOffstage: onstage);

/// [DU581 r3 _bringBuilt 와 같은 대비 · 판정167 교훈] [want] 글이 [host] 안에 아직 안 지어졌을 때만 그 host 의 세로 Scrollable 을 끌어 짓는다
///   (누르기 아님 · 찾는 식 = _txt 와 같은 정규화 · 단언 없음 — 개수 판정은 뒤 _textLine/_btnReach 출력과 cell 선언). 지어져 있으면 아무것도 하지 않는다.
Future<void> _bringBuilt(WidgetTester t, Finder host, String? want) async {
  final tf = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? w.textSpan?.toPlainText() ?? '') == want), skipOffstage: false);
  if (tf.evaluate().isNotEmpty) return;
  final sc = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down), skipOffstage: false);
  await t.scrollUntilVisible(tf, 120, scrollable: sc.first, maxScrolls: 40);
  await t.pump(const Duration(milliseconds: 50));
}

/// 읽는 이름 — Text.semanticsLabel(있으면) · 없으면 span 의 읽는 이름을 포함한 평문 · 그다음 data.
String _semOf(Text w) => w.semanticsLabel ?? w.textSpan?.toPlainText() ?? w.data ?? '';

typedef _TO = ({int n, bool shown, bool sem, bool full, bool ell0, int brk, int lines, bool vis});

/// 글 하나 — [tf] 를 ensureVisible 로 화면 안에 넣고 **같은 [tf]** 를 잰다(점검표 A1 · 판정169a §5).
///   shown · full · ell0 · brk = DU560 r3 _textObs(max 판 _fullShown 그대로) · lines = _lineCount · vis = 화면 ∩ 조상 스크롤 칸 안 · n ≠ 1 이면 재지 않는다.
Future<_TO> _textLine(WidgetTester t, Finder tf, String want, Rect screen) async {
  final n = tf.evaluate().length;
  _TextObs o = (shown: false, name: false, full: false, ell0: false, brk: 0, size: Size.zero);
  var sem = false;
  var lines = 0;
  var vis = false;
  if (n == 1) {
    await t.ensureVisible(tf);
    for (var m = 0; m < 4; m++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    o = _textObs(t, tf, want);
    sem = _semOf(t.widget<Text>(tf)) == want;
    lines = _lineCount(t.renderObject<RenderParagraph>(find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: true).first));
    vis = _inside(t.getRect(tf), _area(tf, screen));
  }
  return (n: n, shown: o.shown, sem: sem, full: o.full, ell0: o.ell0, brk: o.brk, lines: lines, vis: vis);
}

// ───────────── [DU589b] 측정 — 위 재사용 도우미(_textLine · _txt · _bringBuilt · _area · _hitWithin · _inside · _probe · _parasOf · _spansOf · _sigsOf)만 부른다 ─────────────

/// 바뀐 문구(mk_cand.py 상수와 같은 값 — mkcell 이 base/후보 소스와 대조한다).
const _kFullOld = '정원이 충족된 공고입니다. 추가 확정이 제한됩니다.';
const _kFullNew = '정원이 모두 차서 추가로 확정할 수 없어요.';
const _kElseOld = '기간이 만료된 공고입니다. 추가 확정이 제한됩니다.';
const _kElseNew = '지금은 추가로 확정할 수 없어요.';
const _kVoid = '무효';
const _kHopePre = '희망: ';
const _kLongPre = '장기: ';

/// 채움 주 행동(판정162 ① 대상) 글.
const _mainLabels = <String>{'확정', '계약서 작성'};

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '589';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du589bwa-tb' && _env['DU_BEFORE_OBSERVE'] == '589') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du589bwa-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

/// 글자색 '#RRGGBB'(대문자).
String _hx(Color c) => '#${_hex(c).substring(2).toUpperCase()}';

/// [f] 의 실제 글자 서명(크기/줄 높이/굵기/자간/ARGB) — 문단 조각 서명 집합(DU559 _sigsOf).
String _sigOfText(Finder f) {
  final ps = _parasOf(f);
  return _sigsOf([for (final p in ps) (p, '')]);
}

/// 접두로 찾는 글(장기 희망/근무 기간 — 날짜가 대역 시각을 따라 바뀌어 원문 전체를 상수로 두지 않는다) · 지어진 것 전부.
///   찾는 식 = _txt 와 같은 정규화(TextLayout.plain · Text.rich 평문). O003 본문은 SingleChildScrollView(지연 생성 목록 아님 · :997) — 개수 0 이면 need 로 멈춘다.
Finder _txtPre(Finder scope, String pre) => find.descendant(
    of: scope,
    matching: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? w.textSpan?.toPlainText() ?? '').startsWith(pre)),
    skipOffstage: false);

typedef _VO = ({int n, String sig, String fg, String bg, double cr, bool vis});

/// [039] 상태 칩 하나 — 안 지어졌으면 짓고(_bringBuilt) ensureVisible 로 화면 안에 넣은 뒤 **같은 Text** 의 글자 서명 · 글자색 · 칩 면(가장 가까운 Container
///   decoration) · 대비 · 화면 ∩ 스크롤 칸 안(점검표 A1). 칩 면은 흰 카드 위 불투명 면이다(errorBg).
Future<_VO> _chipLine(WidgetTester t, Finder scope, String want, Rect screen) async {
  await _bringBuilt(t, scope, want);
  final tf = _txt(scope, want, onstage: false);
  final n = tf.evaluate().length;
  if (n != 1) return (n: n, sig: '-', fg: '-', bg: '-', cr: 0.0, vis: false);
  await t.ensureVisible(tf);
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final ps = _parasOf(tf);
  final sp = ps.isEmpty ? const <(String, TextStyle)>[] : _spansOf(ps.first);
  final fc = sp.isEmpty ? null : sp.first.$2.color;
  final box = t.widget<Container>(find.ancestor(of: tf, matching: find.byType(Container)).first);
  final deco = box.decoration;
  final dc = deco is BoxDecoration ? deco.color : null;
  final cr = fc == null || dc == null ? 0.0 : _contrast(fc, Color.alphaBlend(dc, Colors.white));
  return (n: n, sig: _sigOfText(tf), fg: fc == null ? '-' : _hx(fc), bg: dc == null ? '-' : _hx(dc), cr: cr, vis: _inside(t.getRect(tf), _area(tf, screen)));
}

typedef _MO = ({int n, bool allb, String pad, bool min48, bool vis, bool hit, bool m48, bool cr45, double hmax, String raw});

/// [128] 카드 행동 단추 중 채움 주 행동(확정 · 계약서 작성) 전부 — 하나씩 **그 InkWell** 을 ensureVisible 하고 같은 InkWell 을 잰다(점검표 A1):
///   면 = brand · 받는 자리 여백(InkWell › Container.padding '좌x상') · 최소 높이 제약(Container.constraints ≥48 이면 true — 채움은 원래 없음) ·
///   화면 ∩ 스크롤 칸 안 · 중심 hit · 48 · 흰 글/면 대비 ≥4.5 · 최대 높이(주 버튼 52 기준 — 기록).
///   찾기 = DU559 행 버튼 식(카드 안 InkWell › Container) · 지어진 것 전부(본문 SingleChildScrollView).
Future<_MO> _mainBtns(WidgetTester t, Rect screen) async {
  final btnF = find.descendant(
      of: find.byType(ApplicantRowSurface), matching: find.byWidgetPredicate((w) => w is InkWell && w.child is Container), skipOffstage: false);
  final idx = <int>[];
  final all = btnF.evaluate().length;
  for (var i = 0; i < all; i++) {
    final tw = find.descendant(of: btnF.at(i), matching: find.byWidgetPredicate((w) => w is Text), skipOffstage: false);
    if (tw.evaluate().isNotEmpty && _mainLabels.contains(t.widget<Text>(tw.first).data)) idx.add(i);
  }
  var allb = idx.isNotEmpty;
  var min48 = idx.isNotEmpty;
  var vis = idx.isNotEmpty;
  var hit = idx.isNotEmpty;
  var m48 = idx.isNotEmpty;
  var cr45 = idx.isNotEmpty;
  var hmax = 0.0;
  final pads = <String>{};
  final raw = <String>[];
  for (final i in idx) {
    final one = btnF.at(i);
    await t.ensureVisible(one);
    for (var m = 0; m < 4; m++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final p = _probe(t, one, Colors.white);
    final box = t.widget<InkWell>(one).child as Container;
    final pd = box.padding;
    pads.add(pd is EdgeInsets ? '${pd.left}x${pd.top}' : '-');
    if ((box.constraints?.minHeight ?? 0) < 48) min48 = false;
    if (p.fill != AppColors.brand) allb = false;
    final v = _inside(p.r, _area(one, screen));
    final h = _hitWithin(t, one, p.r.center);
    if (!v) vis = false;
    if (!h) hit = false;
    if (!p.big) m48 = false;
    if (p.cr < 4.5) cr45 = false;
    if (p.r.height > hmax) hmax = p.r.height;
    raw.add('${p.label}:${p.r.width.toStringAsFixed(1)}x${p.r.height.toStringAsFixed(1)},${_hex(p.fill)},${_hex(p.fg)},${p.cr.toStringAsFixed(2)},v$v,h$h');
  }
  final pad = pads.isEmpty ? '-' : (pads.length == 1 ? pads.first : 'mixed');
  return (n: idx.length, allb: allb, pad: pad, min48: min48, vis: vis, hit: hit, m48: m48, cr45: cr45, hmax: hmax, raw: raw.join(';'));
}

/// [A8] 캡처에 보이는 카드 행동 단추의 채움 색 — 면이 있는 단추(Material 색 불투명)를 brand · errorDark · 그 밖으로 센다(누르지 않는다 · 읽기만).
({int n, int brand, int err, int other, String list}) _fillsOf(WidgetTester t) {
  final btnF = find.descendant(
      of: find.byType(ApplicantRowSurface), matching: find.byWidgetPredicate((w) => w is InkWell && w.child is Container), skipOffstage: false);
  var n = 0;
  var b = 0;
  var e = 0;
  var o = 0;
  final ls = <String>[];
  for (var i = 0; i < btnF.evaluate().length; i++) {
    final one = btnF.at(i);
    final fill = t.widget<Material>(find.ancestor(of: one, matching: find.byType(Material)).first).color ?? Colors.transparent;
    if (fill.a == 0) continue;
    n++;
    if (fill == AppColors.brand) {
      b++;
    } else if (fill == AppColors.errorDark) {
      e++;
    } else {
      o++;
    }
    final tw = find.descendant(of: one, matching: find.byWidgetPredicate((w) => w is Text), skipOffstage: false);
    ls.add('${tw.evaluate().isEmpty ? '?' : t.widget<Text>(tw.first).data}:${_hex(fill)}');
  }
  return (n: n, brand: b, err: e, other: o, list: ls.join(';'));
}

Future<void> _case(WidgetTester t, _V v, ({String id, int shots}) c, String tok) async {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final wire = _Wire();
  final net = _NoHttp();
  final prevAll = messenger.allMessagesHandler;
  final prevHttp = HttpOverrides.current;
  final prevOnError = FlutterError.onError;
  final prevOverride = WorkApplicantsReads.debugOverride;
  messenger.allMessagesHandler = (channel, handler, message) => wire.route(messenger, channel, handler, message);
  HttpOverrides.global = net;
  addTearDown(() {
    messenger.allMessagesHandler = prevAll;
    HttpOverrides.global = prevHttp;
    FlutterError.onError = prevOnError;
    WorkApplicantsReads.debugOverride = prevOverride;
  });
  t.view.physicalSize = Size(v.w, v.h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final screen = Offset.zero & Size(v.w, v.h);
  final mode = _before ? 'before' : 'strict';
  _out('D589 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
  final seen = _Seen();
  void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
  final checks = <(String, bool, String)>[];
  void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

  final owner = _Owner();
  final reads = _Reads(c.id);
  Object? failure;
  StackTrace? failureSt;
  var shots = 0;
  var raw = '';
  try {
    FlutterError.onError = seen.add;
    WorkApplicantsReads.debugOverride = reads.reads();
    final key = GlobalKey();
    await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
      value: owner,
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.businessAdminTheme,
          locale: const Locale('ko', 'KR'),
          supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
          home: Scaffold(body: WorkApplicantsDialog(key: UniqueKey(), toItem: _item(c.id), work: _wd1(), onChanged: () {})),
        ),
      ),
    ));
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final dlg = find.byType(WorkApplicantsDialog);
    final nDlg = dlg.evaluate().length;
    need('창 1', nDlg == 1, '개수 $nDlg');
    final nRow = find.byType(ApplicantRowSurface, skipOffstage: false).evaluate().length;
    need('명단 행 5', nRow == 5, '개수 $nRow');

    Future<void> shot(String id, String state) async {
      _out('D589 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    await shot('1top', 'open');

    // ① 사례별 바뀐 글 — 찾기 전부 앞 _bringBuilt(정확 글) · 접두 글은 지어진 개수 need · 재는 대상 = ensureVisible 대상(_textLine · _chipLine).
    if (c.id == 'VOID') {
      final vo = await _chipLine(t, dlg, _kVoid, screen);
      _out('D589 $tok att vd n=${vo.n} sig=${vo.sig} fg=${vo.fg} bg=${vo.bg} cr=${vo.cr.toStringAsFixed(2)} ok45=${vo.cr >= 4.5} vis=${vo.vis}');
      raw = '$raw vd $vo';
      need('무효 칩 1', vo.n == 1, 'n ${vo.n}');
      if (!_before) {
        chk('strict 무효 칩 = 14/1.3/700 errorDark 글 · errorBg 면 · 대비 ≥4.5 · 보임',
            vo.sig == '14.0/1.30/700/0.0/ffb42318' && vo.fg == '#B42318' && vo.bg == '#FEEDEA' && vo.cr >= 4.5 && vo.vis, vo.toString());
      }
      await shot('2void', 'void-chip');
    } else if (c.id == 'FULL' || c.id == 'CLSD') {
      final want = c.id == 'FULL' ? (_before ? _kFullOld : _kFullNew) : (_before ? _kElseOld : _kElseNew);
      await _bringBuilt(t, dlg, want);
      final rf = _txt(dlg, want, onstage: false);
      final cnt = rf.evaluate().length;
      need('막힘 이유 있음', cnt >= 1, '개수 $cnt');
      final ro = await _textLine(t, rf.first, want, screen);
      final sig = _sigOfText(rf.first);
      _out('D589 $tok att hn cnt=$cnt n=${ro.n} shown=${ro.shown} sem=${ro.sem} full=${ro.full} ell0=${ro.ell0} brk=${ro.brk} lines=${ro.lines} vis=${ro.vis} sig=$sig');
      raw = '$raw hn $ro';
      if (!_before) {
        chk('strict 막힘 이유 전문 · 읽는 이름 · 말줄임 0 · 낱말 안 끊김 0 · 보임 · 판단 16',
            ro.shown && ro.sem && ro.full && ro.ell0 && ro.brk == 0 && ro.vis && sig == '16.0/1.50/400/0.0/ff21242d', '$ro $sig');
      }
      await shot('2hint', 'approve-blocked');
    } else {
      final qf = _txtPre(dlg, _kLongPre);
      final qn = qf.evaluate().length;
      need('장기 근무 기간 글 있음', qn >= 1, '개수 $qn');
      final qwant = TextLayout.plain(t.widget<Text>(qf.first).data ?? '');
      final qo = await _textLine(t, qf.first, qwant, screen);
      final qsig = _sigOfText(qf.first);
      _out('D589 $tok att hq cnt=$qn n=${qo.n} shown=${qo.shown} sem=${qo.sem} full=${qo.full} ell0=${qo.ell0} brk=${qo.brk} lines=${qo.lines} vis=${qo.vis} sig=$qsig');
      final hf = _txtPre(dlg, _kHopePre);
      final hn = hf.evaluate().length;
      need('희망 기간 글 있음', hn >= 1, '개수 $hn');
      final hwant = TextLayout.plain(t.widget<Text>(hf.first).data ?? '');
      final ho = await _textLine(t, hf.first, hwant, screen);
      final hsig = _sigOfText(hf.first);
      _out('D589 $tok att hp cnt=$hn n=${ho.n} shown=${ho.shown} sem=${ho.sem} full=${ho.full} ell0=${ho.ell0} brk=${ho.brk} lines=${ho.lines} vis=${ho.vis} sig=$hsig');
      raw = '$raw hq $qwant $qo hp $hwant $ho';
      if (!_before) {
        for (final (k, o, s) in [('장기', qo, qsig), ('희망', ho, hsig)]) {
          chk('strict $k 기간 전문 · 읽는 이름 · 말줄임 0 · 낱말 안 끊김 0 · 보임 · 판단 16',
              o.shown && o.sem && o.full && o.ell0 && o.brk == 0 && o.vis && s == '16.0/1.50/400/0.0/ff21242d', '$o $s');
        }
      }
      await shot('2long', 'longterm-period');
    }

    // ② 채움 주 행동 단추(128) — 모든 사례. brand 채움 유지 · 최소 높이 제약 없음(높이는 상하 여백 15.5 그대로)은 두 모드 · 좌우 여백 12 는 strict.
    final mo = await _mainBtns(t, screen);
    _out('D589 $tok att mb n=${mo.n} allb=${mo.allb} pad=${mo.pad} min48=${mo.min48} vis=${mo.vis} hit=${mo.hit} m48=${mo.m48} cr45=${mo.cr45} hmax=${mo.hmax.toStringAsFixed(1)}');
    raw = '$raw mb ${mo.raw}';
    chk('채움 주 행동 ≥1 · 모두 brand 채움(두 모드)', mo.n >= 1 && mo.allb, '${mo.n} ${mo.raw}');
    if (!_before) {
      chk('strict 채움 좌우 여백 12 · 상하 15.5 그대로 · 보임 · 중심 hit · 48 · 대비 ≥4.5',
          mo.pad == '12.0x15.5' && mo.vis && mo.hit && mo.m48 && mo.cr45, mo.raw);
    }

    // ③ A8 채움 색 기록(읽기만).
    final fl = _fillsOf(t);
    _out('D589 $tok att fills n=${fl.n} brand=${fl.brand} err=${fl.err} other=${fl.other} list=${_enc(fl.list)}');
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // ④ 성공 · 실패 공통 정리 — 창을 내리고 남은 timer · 지연 응답이 끝날 시간을 준다(DU535 와 같다).
  var cleanupErr = '';
  try {
    await t.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(seconds: 1));
    }
  } catch (e, st) {
    cleanupErr = e.toString();
    if (failure == null) {
      failure = e;
      failureSt = st;
    }
  }

  // ⑤ 집계 — 지원서 읽기 수 · CF · 예상 밖 채널 · HTTP. 쓰기 동작은 누르지 않았다.
  final nApps = reads.calls['applications'] ?? 0;
  final nUnexp = wire.unexpected.length;
  final nCf = wire.cf.length;
  final nHttp = net.tries.length;
  final unText = wire.unexpected.join(' | ');
  _out('D589 $tok att wire apps=$nApps cf=$nCf unexpected=$nUnexp http=$nHttp');

  messenger.allMessagesHandler = prevAll;
  HttpOverrides.global = prevHttp;
  WorkApplicantsReads.debugOverride = prevOverride;
  final exc = t.takeException();
  if (exc != null && failure == null) {
    failure = exc;
    failureSt = StackTrace.current;
  }
  final nOvf = seen.overflows.length;
  final nFw = seen.other.length;
  final ovfRaw = seen.overflows.take(8).join('\n----\n');
  final fwRaw = seen.other.take(4).map((m) => m.length > 400 ? m.substring(0, 400) : m).join('\n----\n');
  _out('R589 $tok raw m64=${_enc(raw)} own=${seen.own} unk=${seen.unk} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} '
      'cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D589 $tok att fw n=$nFw');
  _out('D589 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

  final f0 = failure;
  if (f0 != null) {
    _halt ??= '$tok ${f0.toString().split('\n').first}';
    Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
  }
  chk('지원서 읽기 1 · CF 0 · 예상 밖 채널 0 · HTTP 0(두 모드)', nApps == 1 && nCf == 0 && nUnexp == 0 && nHttp == 0, 'apps $nApps cf $nCf 예상 밖 [$unText] http $nHttp');
  if (!_before) chk('strict 화면 전체 넘침 0(W · B · N)', nOvf == 0, ovfRaw);
  if (!_before) chk('strict 미처리 framework 예외 0', nFw == 0, fwRaw);
  chk('캡처 수 = 선언', shots == c.shots, 'shots $shots want ${c.shots}');
  final bad = checks.where((x) => !x.$2).toList();
  if (bad.isNotEmpty) _halt ??= '$tok ${bad.first.$1}';
  for (final x in checks) {
    expect(x.$2, isTrue, reason: '$tok ${x.$1} ${x.$3}');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final wire = _Wire();
    final net = _NoHttp();
    final prevAll = m.allMessagesHandler;
    final prevHttp = HttpOverrides.current;
    m.allMessagesHandler = (channel, handler, message) => wire.route(m, channel, handler, message);
    HttpOverrides.global = net;
    try {
      FirebasePlatform.instance = _FakeCore();
      await Firebase.initializeApp();
      await initializeDateFormatting('ko_KR');
      await _loadFonts();
      // FirebaseAuth 생성 때의 두 listener 등록 채널 모의(이벤트 0 · 로그인 상태 불변) — 창이 읽지 않으면 쓰이지 않는다.
      const codec = StandardMessageCodec();
      for (final name in _authListeners) {
        m.setMockMessageHandler('$_authBase$name', (_) async => codec.encodeMessage(<Object?>['$_authFake$name']));
        m.setMockMethodCallHandler(MethodChannel('$_authFake$name'), (_) async => null);
      }
    } finally {
      m.allMessagesHandler = prevAll;
      HttpOverrides.global = prevHttp;
    }
    final nCf = wire.cf.length;
    final nUnexp = wire.unexpected.length;
    final nHttp = net.tries.length;
    _out('R589 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });
  tearDown(() {
    WorkApplicantsReads.debugOverride = null;
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S589WA-${v.id}-${c.id} O003 결정 이행 — 무효 칩 errorDark · 막힘 이유 문구 · 장기 기간 판단 16 · 채움 단추 받는 자리', (t) async {
        final tok = 'S589WA-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _case(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0), (id: 'N', w: 320.0, h: 640.0, s: 1.0)];
