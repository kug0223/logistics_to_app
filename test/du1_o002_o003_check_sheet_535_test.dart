// ignore_for_file: depend_on_referenced_packages
// [DU535 · 표시만] 지원자 두 창(DU-O003 '업무별 지원자' · DU-O002 '인력 현황') — 감사133 §6-1 · §6-2.
//   (A) 신분증 선택 체크(AppCheckbox 명시 activeColor) info → brand — 선택 모드('신분증 요청'을 누른 뒤)에서 att idchk 로 잰다(위젯 값 · rect 0).
//   (B) 계약 일괄 발송 미리보기 창 안내 띠 info 면/글 → grey100 면 · textPrimary 글 — 이 시험은 그 창을 열지 않는다(여는 길이 서버 호출 · 템플릿 선택 창을 지난다 · 소스 변경만).
//   before = 현재 A(work_applicants_dialog 18910e89 · day_applicants_dialog 506f83b1 = DU534 채택판) 기록 전용 · strict = 후보(4a39de53 · 4618577d).
//   본문 = DU534 시험(4aaad8d7) 그대로: 업무별 창 7상태(ROWS · BULK · EMPTY · FAIL · LOADING · BANDS · GROUP) + 날짜별 창 DBANDS. 기존 단언 · 출력 줄 유지.
//   두 창은 같은 측정 함수(_selLine)와 같은 단언 함수(_bandChecks) · 같은 기대 상수(_wantBrand)를 쓴다 — 체크 기대 색이 서로 같다.
//   쓰기 동작(확정 · 거절 · 계약 · 요청하기 · 계약서 일괄작성 · 별 토글 · 체크 토글)은 누르지 않는다 — 일괄선택 켜기 · 전체 선택 · 다시 시도(읽기) · '신분증 요청'(선택 모드 켜기) · 닫기만.
//   GROUP · DBANDS 의 넘침 수는 기록만(씨앗과 같다). BANDS 는 넘침 0 · framework 오류 0 을 strict 로 단언한다.
//   기본 skip — TB before/du535-tb/DU_BEFORE_OBSERVE=535 · TA after/du535-ta/없음.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/slot_model.dart' show SlotModel, SlotStatus;
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_home_summary_model.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/models/ui/staffing_readiness_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_home_reads.dart';
import 'package:ALfit/screens/business_admin/business_admin_home_screen.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_reads.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_applicants_reads.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/admin/applicant_row_surface.dart';
import 'package:ALfit/widgets/common/app_checkbox.dart';
import 'package:ALfit/widgets/common/app_empty_state.dart';
import 'package:ALfit/widgets/common/loading_widget.dart';
import 'package:ALfit/widgets/dialogs/styled_dialog.dart';

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

TOModel _to() => TOModel(
    id: 'to1', businessId: _biz1, businessName: _bizName, type: 'flex', title: '단기 모집', creatorUID: 'admin1', status: 'ACTIVE',
    workDetails: [_wd1(), _wd2()], totalRequired: 8, totalConfirmed: 2, totalPending: 3, isPublished: true, publishMode: 'immediate',
    createdAt: _made, statusUpdatedAt: _made);

TOItem _item() => TOItem(
    to: _to(),
    slot: SlotModel(id: 'slot1', toId: 'to1', date: _day, status: SlotStatus.open, workDetails: [_wd1(), _wd2()], createdAt: _made),
    workDetails: [_wd1(), _wd2()], confirmedCount: 2, pendingCount: 3, totalRequired: 8);

ApplicationModel _app(String id, String status, {bool starred = false}) => ApplicationModel(
    id: id, uid: 'u_$id', toId: 'to1', slotId: 'slot1', businessId: _biz1, businessName: _bizName, toTitle: '단기 모집',
    selectedWorkType: '홀서빙', wdId: 'wd1', startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly', status: status,
    workDate: _day, appliedAt: _applied, isStarred: starred);

const _names = <String, String>{'p1': '김별표', 'p2': '이선택', 'p3': '박대기', 'c1': '최확정', 'c2': '정미작성'};

/// 대역 — 대기 3(p1 별표) · 확정 2(c1 계약 완료 · c2 계약 미작성). 사례마다 새로 만든다(공유 상태 0).
List<ApplicationModel> _apps() => [
      _app('p1', AppStatus.pending, starred: true), _app('p2', AppStatus.pending), _app('p3', AppStatus.pending),
      _app('c1', AppStatus.confirmed), _app('c2', AppStatus.confirmed),
    ];

/// 창의 읽기 경계(주입) — 호출 수만 센다. 쓰기는 여기 없다.
class _Reads {
  _Reads(this.kind);

  /// 사례 이름 — EMPTY(빈 명단) · FAIL(첫 조회만 실패) · LOADING(응답이 오지 않는다) · BANDS(명단 5 · 확정 2명 모두 계약 없음) · 그 밖(명단 5).
  final String kind;
  final hold = Completer<List<ApplicationModel>>();
  final calls = <String, int>{};
  void _hit(String k) => calls[k] = (calls[k] ?? 0) + 1;

  WorkApplicantsReads reads() => WorkApplicantsReads(
        applications: (to, {slotId, required purpose}) {
          _hit('applications');
          final nth = calls['applications'] ?? 0;
          if (kind == 'LOADING') return hold.future;
          if (kind == 'FAIL' && nth == 1) return Future<List<ApplicationModel>>.error(Exception('unavailable'));
          return Future<List<ApplicationModel>>.value(kind == 'EMPTY' ? <ApplicationModel>[] : _apps());
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
          return ContractStatusBatch(statuses: <String, String?>{for (final x in ids) if (x == 'c1' && kind != 'BANDS') x: 'completed'});
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
              'wd1': {'confirmed': kind == 'EMPTY' ? 0 : 2, 'pending': kind == 'EMPTY' ? 0 : 3},
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
const _authFake = 'du535.fake.auth.';
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
    throw const SocketException('DU535 관측 — 외부 HTTP 차단');
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

/// 버튼 하나의 관측값 — 잰 즉시 값으로 굳힌다(트리 변경 뒤 다시 읽지 않는다).
///   면 = 가장 가까운 Material(버튼 자신) 색 · 글자색 = 버튼 안 Text 의 style 색 · 대비 = 글자 ↔ (채움이면 그 면, 아니면 [under]).
_Probe _probe(WidgetTester t, Finder one, Color under) {
  final textF = find.descendant(of: one, matching: find.byType(Text), skipOffstage: true);
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

/// 버튼 면이 '분류색 면'인가 — 면 없음(투명) · brand 채움 · 비활성 회색(grey100)이 아니면 분류색 면이다.
bool _classFace(Color fill) => fill.a != 0 && fill != AppColors.brand && fill != AppColors.grey100;

/// 후보(18910e89)에서 행 버튼이 그려지는 줄 범위 — 카드 버튼 호출부(:2913) ~ _buildActionButton 끝(:3152).
///   넘침 오류의 '오류를 낸 위젯' 위치(work_applicants_dialog.dart:줄)가 이 안이면 행 버튼 발 넘침으로 센다. before 는 기록만(줄이 13 어긋난다).
const _ownLo = 2913;
const _ownHi = 3152;
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
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    return bx.isNotEmpty && bx.first.bottom <= size.height + 0.5 && bx.first.right <= size.width + 0.5;
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

/// [f](글)에서 가장 가까운 Container 의 면 색(BoxDecoration.color · 없으면 Container.color · 그것도 없으면 투명).
Color _faceOf(WidgetTester t, Finder f) {
  final box = t.widget<Container>(find.ancestor(of: f, matching: find.byType(Container)).first);
  final d = box.decoration;
  if (d is BoxDecoration) return d.color ?? Colors.transparent;
  return box.color ?? Colors.transparent;
}

/// Text 하나의 글자색(style 에 색이 없으면 검정으로 적는다).
Color _fgOf(WidgetTester t, Finder f) => t.widget<Text>(f).style?.color ?? Colors.black;

/// [dlg] 안에서 brand 로 채운 면의 수 — BoxDecoration 면이 brand 인 Container + 색이 brand 인 Material(트리 전체 · 보이는 칸으로 거르지 않는다 · 기록용).
int _brandFills(Finder dlg) {
  bool fill(Widget w) {
    if (w is Material) return w.color == AppColors.brand;
    if (w is Container) {
      final d = w.decoration;
      return d is BoxDecoration && d.color == AppColors.brand;
    }
    return false;
  }

  return find.descendant(of: dlg, matching: find.byWidgetPredicate(fill), skipOffstage: true).evaluate().length;
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

/// [f](글)에서 가장 가까운 Container 의 테두리 색(BoxDecoration.border 가 Border 일 때 윗변 색) — 테두리가 없으면 '-'.
String _edgeOf(WidgetTester t, Finder f) {
  final d = t.widget<Container>(find.ancestor(of: f, matching: find.byType(Container)).first).decoration;
  final b = d is BoxDecoration ? d.border : null;
  return b is Border ? _hex(b.top.color) : '-';
}

/// Text 하나의 낱말 안 줄바꿈 수(그려진 문단 기준 · 잰 즉시 수로 굳힌다).
int _brkOf(WidgetTester t, Finder textF) =>
    _midBreaks(t.renderObject<RenderParagraph>(find.descendant(of: textF, matching: find.byType(RichText), skipOffstage: true).first));

/// 두 창 공통 기대 색(같은 요소 = 같은 값 — 업무별 창 · 날짜별 창이 이 상수 하나를 쓴다).
final String _wantBrand = _hex(AppColors.brand);
final String _wantWhite = _hex(Colors.white);
final String _wantClear = _hex(Colors.transparent);
final String _wantStar = _hex(AppColors.amber);
final String _wantLine = _hex(AppColors.border);

typedef _InvObs = ({int n, String fg, String side});

/// 초대 외곽선 버튼([txtF] = 버튼 글) — 개수 · 글/아이콘 색(foreground) · 테두리 색. 출력 한 줄(키 고정). 누르지 않는다.
_InvObs _invLine(WidgetTester t, Finder txtF, String tok) {
  var n = 0;
  var fg = '-';
  var side = '-';
  if (txtF.evaluate().length == 1) {
    final btnF = find.ancestor(of: txtF, matching: find.byWidgetPredicate((w) => w is OutlinedButton));
    n = btnF.evaluate().length;
    if (n >= 1) {
      final st = t.widget<OutlinedButton>(btnF.first).style;
      final fgC = st?.foregroundColor?.resolve(<WidgetState>{});
      final sideC = st?.side?.resolve(<WidgetState>{})?.color;
      if (fgC != null) fg = _hex(fgC);
      if (sideC != null) side = _hex(sideC);
    }
  }
  _out('D535 $tok att invc n=$n fg=$fg side=$side');
  return (n: n, fg: fg, side: side);
}

typedef _FavObs = ({int rows, int starn, int uniq, String bg, String bd, String star, String raw});

/// 지원자 카드 면 — 카드(ApplicantRowSurface) 수 · 별표 카드 수(켜진 별 아이콘 = star_rounded + amber 가 있는 카드) ·
///   카드들의 (면, 테두리) 조합 수(uniq — 1 이면 별표 카드가 일반 카드와 같은 면 · 선) · 별표 카드의 면 · 테두리 · 별 아이콘 색. 출력 한 줄(키 고정).
_FavObs _favLine(WidgetTester t, Finder dlg, String tok) {
  final rowF = find.descendant(of: dlg, matching: find.byType(ApplicantRowSurface), skipOffstage: true);
  final n = rowF.evaluate().length;
  final pairs = <String>{};
  final all = <String>[];
  var starn = 0;
  var bg = '-';
  var bd = '-';
  var star = '-';
  for (var i = 0; i < n; i++) {
    final one = rowF.at(i);
    final surf = t.widget<ApplicantRowSurface>(one);
    final pair = '${_hex(surf.background)}/${_hex(surf.border)}';
    pairs.add(pair);
    final starF = find.descendant(
        of: one, matching: find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.star_rounded && w.color == AppColors.amber), skipOffstage: true);
    final lit = starF.evaluate().isNotEmpty;
    all.add('$i $pair star=$lit');
    if (lit) {
      starn++;
      bg = _hex(surf.background);
      bd = _hex(surf.border);
      star = _hex(t.widget<Icon>(starF.first).color ?? Colors.black);
    }
  }
  _out('D535 $tok att fav rows=$n starn=$starn uniq=${pairs.length} bg=$bg bd=$bd star=$star');
  return (rows: n, starn: starn, uniq: pairs.length, bg: bg, bd: bd, star: star, raw: all.join(' | '));
}

/// 첫 화면 색 단언(strict · 두 창 공통) — 초대 외곽선 = brand · 별표 카드 = 일반 카드와 같은 면/선 + 별 아이콘 amber.
List<(String, bool, String)> _topChecks(_InvObs io, _FavObs fo) => [
      ('strict 초대 외곽선 버튼 1 · 글/아이콘 = brand · 테두리 = brand(두 창 같은 값)', io.n == 1 && io.fg == _wantBrand && io.side == _wantBrand, 'n ${io.n} fg ${io.fg} side ${io.side}'),
      ('strict 별표 카드 1 · 카드 면/테두리 조합 1가지(별표 = 일반 카드) · 별표 카드 면 = 흰색', fo.starn == 1 && fo.uniq == 1 && fo.bg == _wantWhite, fo.raw),
      ('strict 별 아이콘 amber 유지', fo.star == _wantStar, 'star ${fo.star}'),
    ];

typedef _BandObs = ({
  int nId,
  int nCt,
  int nIdBtn,
  int nCtBtn,
  String idIcon,
  String idText,
  String idBtn,
  String idBtnFg,
  String idFace,
  String ctIcon,
  String ctText,
  String ctBtn,
  String ctBtnFg,
  String ctEdge,
  int idBrk,
  int ctBrk,
  bool cr,
  String raw,
});

/// 띠 2종(평소) — 신분증 요청('요청 가능 2명') · 계약서 미작성('계약서 미작성 2명'). 아이콘 · 글 · 버튼의 색 · 대비, '계약서 일괄작성'의 테두리,
///   안내 글의 낱말 안 줄바꿈 수를 잰다. 개수가 맞지 않으면 재지 않고 '-' · 0 으로 적는다. 버튼은 누르지 않는다. 출력 한 줄(키 고정) + 자리 기록 한 줄.
Future<_BandObs> _bandLine(WidgetTester t, Finder dlg, String tok, bool broken) async {
  final idTxt = findVisibleText('요청 가능 2명');
  final ctTxt = findVisibleText('계약서 미작성 2명');
  final idBtn = find.text('신분증 요청');
  final ctBtn = find.text('계약서 일괄작성');
  final nId = idTxt.evaluate().length;
  final nCt = ctTxt.evaluate().length;
  final nIdBtn = idBtn.evaluate().length;
  final nCtBtn = ctBtn.evaluate().length;
  var idIcon = '-';
  var idText = '-';
  var idBtnFace = '-';
  var idBtnFg = '-';
  var idFace = '-';
  var ctIcon = '-';
  var ctText = '-';
  var ctBtnFace = '-';
  var ctBtnFg = '-';
  var ctEdge = '-';
  var idBrk = 0;
  var ctBrk = 0;
  var bandCr = false;
  var geo = '-';
  if (!broken && nId == 1 && nCt == 1 && nIdBtn == 1 && nCtBtn == 1) {
    await t.ensureVisible(ctBtn);
    for (var m = 0; m < 4; m++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final idBand = find.ancestor(of: idTxt, matching: find.byType(Container)).first;
    final ctBand = find.ancestor(of: ctTxt, matching: find.byType(Container)).first;
    final idIconF = find.descendant(of: idBand, matching: find.byType(Icon), skipOffstage: true);
    final ctIconF = find.descendant(of: ctBand, matching: find.byType(Icon), skipOffstage: true);
    final idBandFace = _faceOf(t, idTxt);
    final ctBandFace = _faceOf(t, ctTxt);
    final idTextC = _fgOf(t, idTxt);
    final ctTextC = _fgOf(t, ctTxt);
    final idBtnFaceC = _faceOf(t, idBtn);
    final idBtnFgC = _fgOf(t, idBtn);
    final ctBtnFaceC = _faceOf(t, ctBtn);
    final ctBtnFgC = _fgOf(t, ctBtn);
    if (idIconF.evaluate().length == 1) idIcon = _hex(t.widget<Icon>(idIconF).color ?? Colors.black);
    if (ctIconF.evaluate().length == 1) ctIcon = _hex(t.widget<Icon>(ctIconF).color ?? Colors.black);
    idText = _hex(idTextC);
    ctText = _hex(ctTextC);
    idBtnFace = _hex(idBtnFaceC);
    idBtnFg = _hex(idBtnFgC);
    idFace = _hex(idBandFace);
    ctBtnFace = _hex(ctBtnFaceC);
    ctBtnFg = _hex(ctBtnFgC);
    ctEdge = _edgeOf(t, ctBtn);
    idBrk = _brkOf(t, idTxt);
    ctBrk = _brkOf(t, ctTxt);
    final idUnder = Color.alphaBlend(idBandFace, Colors.white);
    final ctUnder = Color.alphaBlend(ctBandFace, Colors.white);
    bandCr = _contrast(idTextC, idUnder) >= 4.5 &&
        _contrast(ctTextC, ctUnder) >= 4.5 &&
        _contrast(idBtnFgC, Color.alphaBlend(idBtnFaceC, idUnder)) >= 4.5 &&
        _contrast(ctBtnFgC, Color.alphaBlend(ctBtnFaceC, ctUnder)) >= 4.5;
    final idBandR = t.getRect(idBand);
    final ctBandR = t.getRect(ctBand);
    final ctBtnR = t.getRect(find.ancestor(of: ctBtn, matching: find.byType(Container)).first);
    final idBtnR = t.getRect(find.ancestor(of: idBtn, matching: find.byType(Container)).first);
    geo = '${idBandR.width.toStringAsFixed(1)},${idBandR.height.toStringAsFixed(1)},${ctBandR.width.toStringAsFixed(1)},${ctBandR.height.toStringAsFixed(1)},'
        '${idBtnR.width.toStringAsFixed(1)},${idBtnR.height.toStringAsFixed(1)},${ctBtnR.width.toStringAsFixed(1)},${ctBtnR.height.toStringAsFixed(1)}';
  }
  final bandBrand = _brandFills(dlg);
  _out('D535 $tok att band idn=$nId ctn=$nCt idbtnn=$nIdBtn ctbtnn=$nCtBtn idicon=$idIcon idtext=$idText idbtn=$idBtnFace idbtnfg=$idBtnFg idface=$idFace '
      'cticon=$ctIcon cttext=$ctText ctbtn=$ctBtnFace ctbtnfg=$ctBtnFg ctbd=$ctEdge idbrk=$idBrk ctbrk=$ctBrk cr45=$bandCr brandn=$bandBrand');
  _out('R535 $tok bandgeo $geo');
  return (
    nId: nId, nCt: nCt, nIdBtn: nIdBtn, nCtBtn: nCtBtn, idIcon: idIcon, idText: idText, idBtn: idBtnFace, idBtnFg: idBtnFg, idFace: idFace,
    ctIcon: ctIcon, ctText: ctText, ctBtn: ctBtnFace, ctBtnFg: ctBtnFg, ctEdge: ctEdge, idBrk: idBrk, ctBrk: ctBrk, cr: bandCr,
    raw: 'n $nId/$nCt/$nIdBtn/$nCtBtn id $idIcon $idText/$idFace $idBtnFg/$idBtnFace brk $idBrk ct $ctIcon $ctText $ctBtnFg/$ctBtnFace bd $ctEdge brk $ctBrk geo $geo',
  );
}

typedef _SelObs = ({int nReq, int nSel, int nTog, String reqFace, String reqFg, String togFace, String togFg, String face, String edge, int brk, bool cr, int chkOn, int chkUniq, String chkColor, bool chkCr, String raw});

/// 신분증 띠 선택 모드('신분증 요청'을 누른 뒤 — 화면 상태만) — '요청하기' · '취소' 색, 띠 면 · 테두리, 'n명 선택됨' 글의 낱말 안 줄바꿈 수. 출력 한 줄(키 고정).
///   '요청하기'는 누르지 않는다.
_SelObs _selLine(WidgetTester t, Finder dlg, String tok) {
  final reqF = find.text('요청하기');
  final selF = findVisibleText('2명 선택됨');
  final nReq = reqF.evaluate().length;
  final nSel = selF.evaluate().length;
  var nTog = 0;
  var reqFace = '-';
  var reqFg = '-';
  var togFace = '-';
  var togFg = '-';
  var selFace = '-';
  var selEdge = '-';
  var selBrk = 0;
  var selCr = false;
  if (nReq == 1 && nSel == 1) {
    final selBand = find.ancestor(of: selF, matching: find.byType(Container)).first;
    final togF = find.descendant(of: selBand, matching: findVisibleText('취소'), skipOffstage: true);
    nTog = togF.evaluate().length;
    final reqFaceC = _faceOf(t, reqF);
    final reqFgC = _fgOf(t, reqF);
    final selFaceC = _faceOf(t, selF);
    final selTextC = _fgOf(t, selF);
    reqFace = _hex(reqFaceC);
    reqFg = _hex(reqFgC);
    selFace = _hex(selFaceC);
    selEdge = _edgeOf(t, selF);
    selBrk = _brkOf(t, selF);
    final selUnder = Color.alphaBlend(selFaceC, Colors.white);
    selCr = _contrast(reqFgC, Color.alphaBlend(reqFaceC, selUnder)) >= 4.5 && _contrast(selTextC, selUnder) >= 4.5;
    if (nTog == 1) {
      final togFaceC = _faceOf(t, togF);
      final togFgC = _fgOf(t, togF);
      togFace = _hex(togFaceC);
      togFg = _hex(togFgC);
      selCr = selCr && _contrast(togFgC, Color.alphaBlend(togFaceC, selUnder)) >= 4.5;
    }
  }
  final selBrand = _brandFills(dlg);
  _out('D535 $tok att sel reqn=$nReq seln=$nSel togn=$nTog reqbtn=$reqFace reqfg=$reqFg togbtn=$togFace togfg=$togFg face=$selFace bd=$selEdge brk=$selBrk '
      'cr45=$selCr brandn=$selBrand');
  // [DU535] 신분증 선택 체크 — 선택됨(value) · 누를 수 있는(enabled + onTap) AppCheckbox 가 그린 Icon 의 색. 위젯 값만 읽는다(자리 · rect 0 · 누르지 않는다).
  //   비활성 체크(enabled: false)와 일괄선택 체크(onTap 없음 · 이 모드에서는 서지 않는다)는 세지 않는다. 대비 = 흰 카드 면 기준.
  final chkSeen = <Color>[];
  var chkOdd = 0;
  for (final e in find.descendant(of: dlg, matching: find.byType(AppCheckbox), skipOffstage: true).evaluate()) {
    final w = e.widget as AppCheckbox;
    if (!w.value || !w.enabled || w.onTap == null) continue;
    final icons = find.descendant(of: find.byElementPredicate((x) => identical(x, e)), matching: find.byType(Icon), skipOffstage: true).evaluate().toList();
    final ic = icons.length == 1 ? (icons.first.widget as Icon).color : null;
    if (ic == null) {
      chkOdd++;
    } else {
      chkSeen.add(ic);
    }
  }
  final chkOn = chkSeen.length + chkOdd;
  final chkHex = {for (final col in chkSeen) _hex(col)};
  final chkUniq = chkHex.length + (chkOdd > 0 ? 1 : 0);
  final chkColor = (chkOdd == 0 && chkHex.length == 1) ? chkHex.first : '-';
  final chkCr = chkOdd == 0 && chkSeen.isNotEmpty && chkSeen.every((col) => _contrast(col, Colors.white) >= 4.5);
  _out('D535 $tok att idchk on=$chkOn uniq=$chkUniq color=$chkColor cr45=$chkCr');
  return (
    nReq: nReq, nSel: nSel, nTog: nTog, reqFace: reqFace, reqFg: reqFg, togFace: togFace, togFg: togFg, face: selFace, edge: selEdge, brk: selBrk, cr: selCr,
    chkOn: chkOn, chkUniq: chkUniq, chkColor: chkColor, chkCr: chkCr,
    raw: 'n $nReq/$nSel/$nTog req $reqFace/$reqFg tog $togFace/$togFg face $selFace bd $selEdge brk $selBrk chk $chkOn/$chkUniq/$chkColor/$chkCr',
  );
}

/// 띠 색 단언(strict · 두 창 공통) — 평소 띠 + 선택 모드. 같은 함수 · 같은 상수라 두 창의 기대값이 서로 같다.
List<(String, bool, String)> _bandChecks(_BandObs bo, _SelObs so) => [
      ('strict 띠 글 · 버튼 각 1', bo.nId == 1 && bo.nCt == 1 && bo.nIdBtn == 1 && bo.nCtBtn == 1, bo.raw),
      (
        'strict 신분증 띠(아이콘 grey600 · 글 textPrimary · 신분증 요청 = 면 없음 + brand 글)',
        bo.idIcon == _hex(AppColors.grey600) && bo.idText == _hex(AppColors.textPrimary) && bo.idBtn == _wantClear && bo.idBtnFg == _wantBrand,
        bo.raw
      ),
      (
        'strict 계약서 일괄작성 = brand 외곽선(면 없음 · brand 글 · brand 테두리 — 두 창 같은 값) · 띠 아이콘 grey600 · 글 textPrimary',
        bo.ctIcon == _hex(AppColors.grey600) && bo.ctText == _hex(AppColors.textPrimary) && bo.ctBtn == _wantClear && bo.ctBtnFg == _wantBrand && bo.ctEdge == _wantBrand,
        bo.raw
      ),
      ('strict 띠 글/면 · 버튼 글/면 대비 ≥4.5', bo.cr, bo.raw),
      ('strict 띠 안내 글 낱말 안 줄바꿈 0(요청 가능 · 계약서 미작성)', bo.idBrk == 0 && bo.ctBrk == 0, bo.raw),
      ('strict 선택 모드 — 요청하기 1 · 선택 글 1 · 취소 1', so.nReq == 1 && so.nSel == 1 && so.nTog == 1, so.raw),
      (
        'strict 요청하기 = brand 채움 + 흰 글(유지) · 취소 = grey100 + grey700(유지)',
        so.reqFace == _wantBrand && so.reqFg == _wantWhite && so.togFace == _hex(AppColors.grey100) && so.togFg == _hex(AppColors.grey700),
        so.raw
      ),
      ('strict 선택 모드 띠 = 중립(흰 면 · border 선 — 두 창 같은 값)', so.face == _wantWhite && so.edge == _wantLine, so.raw),
      ('strict 선택 모드 글/면 · 버튼 글/면 대비 ≥4.5 · 선택 글 낱말 안 줄바꿈 0', so.cr && so.brk == 0, so.raw),
      ('strict 신분증 선택 체크 = brand(선택된 체크 ≥1 · 색 1가지 · 흰 면 대비 ≥4.5 — 두 창 같은 값)', so.chkOn >= 1 && so.chkUniq == 1 && so.chkColor == _wantBrand && so.chkCr, so.raw),
    ];

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
const _cases = <({String id, int shots})>[(id: 'ROWS', shots: 2), (id: 'BULK', shots: 1), (id: 'EMPTY', shots: 2), (id: 'FAIL', shots: 3), (id: 'LOADING', shots: 1), (id: 'BANDS', shots: 2), (id: 'GROUP', shots: 1), (id: 'DBANDS', shots: 3)];

/// 행 버튼 문구 — 문구 불변 기준(선언 lines 의 exact 와 같은 값). 순서 = 정렬.
const _rowLabels = ['거절', '계약서 작성', '근무 변경 제안', '다른 업무 제안', '확정', '확정취소'];
const _bulkLabels = ['거절', '확정'];

/// 글 원문 — 문구 불변 기준(대역: 홀서빙 · 09:00~18:00 · 시급 12,000 · 필요 5 · 확정 2).
const _titleText = '홀서빙 · 인력 현황';
const _inviteText = '인력 초대 (3명 부족)';
const _emptyText = '지원자가 없습니다';
const _failText = '인력 현황을 불러오지 못했어요';
/// 통계 구역 글(그려진 순서 · '|' 로 이음) — 명단 5 대역(지원 3 · 확정 2 · 필요 5 → 부족 3). 문구 불변 기준.
const _statWords = '지원: |3명|확정: |2명|부족: |3명|필요 5명';
final String _subText = '${FormatHelper.formatDate(_day)} · 09:00~18:00 | 시급 12,000원';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '535';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du535-tb' && _env['DU_BEFORE_OBSERVE'] == '535') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du535-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

// ───────────── 날짜별 창(DU-O002) 대역 · 읽기 경계 · guard — DU526 시험(3b30a391)에서 가져왔다(private 이름 앞에 d · 값은 그대로) ─────────────
const _dBiz1 = 'biz1';
const _dBiz2 = 'biz2';
const _dBizName = '강남 물류센터';
const _dLongBiz = '강남구 테헤란로 제2물류센터 야간 상하차 전용 창고'; // CP04 · CP01 인계 긴 사업장
const _dLongName = '응우옌 티 프엉 타오 쩐'; // CP01-C1 · CP04 인계 긴 이름(띄어쓰기 있음)
const _dLatinName = 'KHAMPHOUVONGSOUKSAVANH'; // 띄어쓰기 없는 긴 로마자 이름
const _dLongTitle = '수도권 남부 통합 물류센터 야간 상하차 및 분류 보조 단기 모집';
const _dLongWork = '냉장·냉동 식품 분류 및 출고 검수 보조';
const _dNightTitle = '야간 상하차 단기';

/// 소유자(BUSINESS_ADMIN) — 홈(CP04 _DOwner)과 창(ARO _DOwner · PCL _DAdminP)이 실제로 부르는 판정을 허용으로 준다.
///   창은 `canForBusiness`(private _dCurrentUser 를 읽는다) · `watchBusinessPermissions` 를 부르므로 둘 다 대역에서 답한다.
class _DOwner extends UserProvider {
  _DOwner({this.bizIds = const [_dBiz1]});
  final List<String> bizIds;
  final watched = <String>[];
  @override
  UserModel? get currentUser => UserModel(
      uid: 'admin1', username: 'admin1', name: '김관리', email: 'admin1@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: bizIds, sealBase64: 'seal');
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

// ── 고정 시각(KST) — DU1_VQ_DATE 날의 10:00 (CP04 와 같은 산식) ──
final DateTime _dClock = () {
  final k = vqNow().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day, 10).subtract(const Duration(hours: 9));
}();
final DateTime _dToday = FormatHelper.toKstDate(_dClock);
final String _dYmd = '${_dToday.year}-${_dToday.month.toString().padLeft(2, '0')}-${_dToday.day.toString().padLeft(2, '0')}';
// 상대 시각은 창이 실제 DateTime.now() 로 센다(day_applicants_dialog.dart:4415) — 실행 시각 기준 3시간 전으로 둔다.
final DateTime _dApplied = DateTime.now().subtract(const Duration(hours: 3));
final DateTime _dInvAt = DateTime.now().subtract(const Duration(hours: 5));

BusinessModel _dBusiness(String id, String name) => BusinessModel(
    id: id, name: name, ownerId: 'admin1', businessNumber: '000-00-00000', address: '서울시 어딘가',
    category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1));

Map<String, dynamic> _dBiz(String id, String name, int req, int conf, int short) =>
    {'businessId': id, 'businessName': name, 'requiredCount': req, 'confirmedCount': conf, 'shortageCount': short};

Map<String, dynamic> _dDay(int req, int conf, int short, {int? pending, List<Map<String, dynamic>> byBusiness = const []}) => {
      'date': _dYmd, 'requiredCount': req, 'confirmedCount': conf, 'shortageCount': short,
      if (pending != null) 'pendingCount': pending, 'pendingAvailable': pending != null, 'byBusiness': byBusiness,
    };

StaffingReadinessModel _dStaffing(Map<String, dynamic> d) =>
    StaffingReadinessModel(available: true, publishedPostingCount: 1, days: [StaffingDayData.fromMap(d)]);

class _DTemplate extends Fake implements ContractTemplateModel {
  @override
  bool get isSupportedForNewUse => true;
}

Map<String, BusinessPostingReadiness> _dReady(List<BusinessModel> bizs) => {
      for (final b in bizs)
        b.id: BusinessPostingReadiness(
            bizId: b.id, isApproved: true, hasCanonicalLicense: true, hasOwnerLegacyLicense: false,
            hasActiveWorkTypes: true, hasEmployerSeal: true),
    };

/// 할 일 canonical — 전부 0(CP04 _dSummary 와 같은 CF 직렬화 모양 · 파싱은 production).
AdminHomeSummaryModel _dSummary() {
  Map<String, dynamic> s() => {'available': true, 'count': 0, 'byBusiness': [{'businessId': _dBiz1, 'count': 0}]};
  return AdminHomeSummaryModel.fromMap({
    'actions': {
      'resignRequest': {...s(), 'soonCount': 0, 'manualReviewCount': null},
      'approval': {...s(), 'overdueCount': 0},
      'scheduleChangeRequest': s(),
      'unsentContract': s(),
      'unclosed': {...s(), 'oldestDate': null},
      'settlementRequest': s(),
      'wageChangeRequest': s(),
      'unpaidWage': {
        ...s(), 'overdueCount': 0, 'missingDueDateCount': 0,
        'byBusiness': [{'businessId': _dBiz1, 'count': 0, 'missingDueDateCount': 0}],
      },
    },
    'upcoming': {
      'expiringContract': {...s(), 'upcomingCount': 0, 'expiredCount': 0},
    },
  });
}

ApplicationModel _dApp(String id, String status,
        {String bizId = _dBiz1, String bizName = _dBizName, String toId = 'to1', String title = '물류 단기 모집',
        String wd = 'wd1', String work = '상하차', String start = '09:00', String end = '18:00', bool starred = false,
        DateTime? invitedAt}) =>
    ApplicationModel(
      id: id, uid: 'u_$id', toId: toId, slotId: 's_$toId', businessId: bizId, businessName: bizName, toTitle: title,
      selectedWorkType: work, wdId: wd, startTime: start, endTime: end, wage: 12000, wageType: 'hourly', status: status,
      workDate: _dToday, appliedAt: _dApplied, isStarred: starred, invitedAt: invitedAt,
      invitedBy: invitedAt == null ? null : 'admin1',
    );

DayStaffingRow _dRow(
        {String toId = 'to1', String title = '물류 단기 모집', String wd = 'wd1', String work = '상하차',
        String start = '09:00', String end = '18:00', required int req, required int conf, int pend = 0}) =>
    DayStaffingRow(
      toId: toId, toTitle: title, slotId: 's_$toId', wdId: wd, workType: work, startTime: start, endTime: end,
      requiredCount: req, confirmedCount: conf, pendingCount: pend,
    );

UserModel _dPerson(String appId) {
  final uid = 'u_$appId';
  UserModel u(String name, {int? personNo, String? phone, int noShow = 0, double rating = 0}) => UserModel(
      uid: uid, username: uid, name: name, email: '$uid@alfit.local', role: UserRole.USER,
      personNo: personNo, phone: phone, recentNoShowCount: noShow, averageRating: rating);
  switch (appId) {
    case 'p1':
      return u('김별표', phone: '01012345678', rating: 4.5);
    case 'p2':
      return u('이선택');
    case 'p3':
      return u('박노쇼', noShow: 1);
    case 'c1':
      return u('최확정');
    case 'c2':
      return u('정미작성');
    case 'c3':
      return u('한서명');
    case 'c4':
      return u('오관리');
    case 'i9':
      return u('문마감');
    case 'l1':
      return u(_dLongName, personNo: 123);
    case 'l2':
      return u(_dLatinName);
    case 'l3':
      return u('남궁하늘빛나리');
    case 'm1':
      return u('서다사업');
    case 'm2':
      return u('윤확정');
    case 'm3':
      return u('장미작성');
    case 'i1':
      return u('강초대');
    default:
      return u('근로자 $appId');
  }
}

typedef _DFx = ({
  List<String> bizIds,
  List<BusinessModel> businesses,
  StaffingReadinessModel staffing,
  String dialogBiz,
  List<ApplicationModel> pending,
  List<ApplicationModel> confirmed,
  List<ApplicationModel> invites,
  List<DayStaffingRow> rows,
  Map<String, int> caps,
  Map<String, String> contracts,
  Map<String, UserModel> users,
  bool failFirst,
  bool rowsFail,
  bool invitesFail,
  bool capsFail,
});

_DFx _dFx(List<BusinessModel> businesses, StaffingReadinessModel staffing,
    {List<String> bizIds = const [_dBiz1], String dialogBiz = _dBiz1, List<ApplicationModel> pending = const [],
    List<ApplicationModel> confirmed = const [], List<ApplicationModel> invites = const [],
    List<DayStaffingRow> rows = const [], Map<String, int> caps = const {}, Map<String, String> contracts = const {},
    bool failFirst = false, bool rowsFail = false, bool invitesFail = false, bool capsFail = false}) {
  final users = {for (final a in [...pending, ...confirmed, ...invites]) a.uid: _dPerson(a.id)};
  return (
    bizIds: bizIds, businesses: businesses, staffing: staffing, dialogBiz: dialogBiz, pending: pending,
    confirmed: confirmed, invites: invites, rows: rows, caps: caps, contracts: contracts, users: users,
    failFirst: failFirst, rowsFail: rowsFail, invitesFail: invitesFail, capsFail: capsFail,
  );
}

/// 상태별 대역 — 각 사례가 새로 만든다(공유 상태 0). 홈 오늘 부족 > 0 이어야 '인원 현황 보기' 행이 선다(:2882).
_DFx _dFixture(String id) {
  final single = [_dBusiness(_dBiz1, _dBizName)];
  final multi = [_dBusiness(_dBiz1, _dBizName), _dBusiness(_dBiz2, _dLongBiz)];
  ApplicationModel night(String appId, String st, {DateTime? invitedAt, bool starred = false}) => _dApp(appId, st,
      bizId: _dBiz2, bizName: _dLongBiz, toId: 'to2', title: _dNightTitle, wd: 'wdA', start: '18:00', end: '23:00',
      invitedAt: invitedAt, starred: starred);
  switch (id) {
    case 'SHORT':
    case 'FAIL':
      return _dFx(single, _dStaffing(_dDay(5, 2, 3, byBusiness: [_dBiz(_dBiz1, _dBizName, 5, 2, 3)])),
          confirmed: [_dApp('c1', AppStatus.confirmed), _dApp('c2', AppStatus.confirmed)],
          rows: [_dRow(req: 5, conf: 2)], caps: const {'wd1': 5}, contracts: const {'c1': 'completed'},
          failFirst: id == 'FAIL');
    case 'FULL':
      return _dFx(single, _dStaffing(_dDay(5, 4, 1, byBusiness: [_dBiz(_dBiz1, _dBizName, 5, 4, 1)])),
          confirmed: [
            _dApp('c1', AppStatus.confirmed), _dApp('c2', AppStatus.confirmed), _dApp('c3', AppStatus.confirmed),
            _dApp('c4', AppStatus.confirmed, wd: 'wd2', work: '포장', start: '13:00', end: '22:00'),
          ],
          invites: [_dApp('i9', AppStatus.invited, invitedAt: _dInvAt)],
          rows: [_dRow(req: 3, conf: 3), _dRow(wd: 'wd2', work: '포장', start: '13:00', end: '22:00', req: 2, conf: 1)],
          caps: const {'wd1': 3, 'wd2': 2},
          contracts: const {'c1': 'completed', 'c2': 'pending_worker', 'c3': 'pending_employer'});
    case 'PEND':
      return _dFx(single, _dStaffing(_dDay(4, 1, 3, pending: 3, byBusiness: [_dBiz(_dBiz1, _dBizName, 4, 1, 3)])),
          pending: [_dApp('p1', AppStatus.pending, starred: true), _dApp('p2', AppStatus.pending), _dApp('p3', AppStatus.pending)],
          confirmed: [_dApp('c1', AppStatus.confirmed)], rows: [_dRow(req: 4, conf: 1, pend: 3)],
          caps: const {'wd1': 4}, contracts: const {'c1': 'completed'});
    case 'UNK':
      return _dFx(single, _dStaffing(_dDay(5, 2, 3, byBusiness: [_dBiz(_dBiz1, _dBizName, 5, 2, 3)])),
          pending: [_dApp('p2', AppStatus.pending)],
          confirmed: [_dApp('c1', AppStatus.confirmed), _dApp('c2', AppStatus.confirmed)],
          contracts: const {'c1': 'completed'}, rowsFail: true, invitesFail: true, capsFail: true);
    case 'LONG':
      return _dFx(single, _dStaffing(_dDay(3, 1, 2, pending: 2, byBusiness: [_dBiz(_dBiz1, _dBizName, 3, 1, 2)])),
          pending: [
            _dApp('l1', AppStatus.pending, title: _dLongTitle, work: _dLongWork),
            _dApp('l2', AppStatus.pending, title: _dLongTitle, work: _dLongWork),
          ],
          confirmed: [_dApp('l3', AppStatus.confirmed, title: _dLongTitle, work: _dLongWork)],
          rows: [_dRow(title: _dLongTitle, work: _dLongWork, req: 3, conf: 1, pend: 2)], caps: const {'wd1': 3});
    case 'DBANDS': // [DU534] MULTI 와 같은 두 사업장 대역 + 대기 2(m1 별표 · m4) · 확정 2명 모두 계약 없음(계약서 미작성 띠가 선다)
      return _dFx(multi,
          _dStaffing(_dDay(8, 4, 4, byBusiness: [_dBiz(_dBiz1, _dBizName, 3, 2, 1), _dBiz(_dBiz2, _dLongBiz, 5, 2, 3)])),
          bizIds: const [_dBiz1, _dBiz2], dialogBiz: _dBiz2,
          pending: [night('m1', AppStatus.pending, starred: true), night('m4', AppStatus.pending)],
          confirmed: [night('m2', AppStatus.confirmed), night('m3', AppStatus.confirmed)],
          invites: [night('i1', AppStatus.invited, invitedAt: _dInvAt)],
          rows: [_dRow(toId: 'to2', title: _dNightTitle, wd: 'wdA', start: '18:00', end: '23:00', req: 5, conf: 2, pend: 2)],
          caps: const {'wdA': 5});
    default: // MULTI — 부족 큰 순 biz2(3) · biz1(1) → 창 첫 사업장 biz2(:3548–3553 · :479–480)
      return _dFx(multi,
          _dStaffing(_dDay(8, 4, 4, byBusiness: [_dBiz(_dBiz1, _dBizName, 3, 2, 1), _dBiz(_dBiz2, _dLongBiz, 5, 2, 3)])),
          bizIds: const [_dBiz1, _dBiz2], dialogBiz: _dBiz2,
          pending: [night('m1', AppStatus.pending)],
          confirmed: [night('m2', AppStatus.confirmed), night('m3', AppStatus.confirmed)],
          invites: [night('i1', AppStatus.invited, invitedAt: _dInvAt)],
          rows: [_dRow(toId: 'to2', title: _dNightTitle, wd: 'wdA', start: '18:00', end: '23:00', req: 5, conf: 2, pend: 1)],
          caps: const {'wdA': 5}, contracts: const {'m2': 'completed'});
  }
}

AdminHomeReads _dHomeReads(_DFx fx, Map<String, int> calls) {
  void hit(String k) => calls[k] = (calls[k] ?? 0) + 1;
  return AdminHomeReads(
    summary: ({String? selectedBusinessId}) {
      hit('summary');
      return Future.value(_dSummary());
    },
    businessesByIds: (ids) async {
      hit('businesses');
      return fx.businesses;
    },
    staffingReadiness: ({String? selectedBusinessId}) {
      hit('staffing');
      return Future.value(fx.staffing);
    },
    attendanceByDate: ({required String businessId, required DateTime date}) async {
      hit('attendance');
      return <AttendanceModel>[];
    },
    confirmedWorkers: ({required DateTime date, required String businessId}) async {
      hit('roster');
      return <ApplicationModel>[];
    },
    workDetailTimes: (_) async => <String, dynamic>{},
    postingReadiness: (bizs) async => _dReady(bizs),
    contractTemplates: (_) async => <ContractTemplateModel>[_DTemplate()],
    tourCompleted: () => Future<bool>.value(true),
    clock: () => _dClock,
    legalReadiness: () async => const LegalReadiness(status: LegalReadinessStatus.current),
  );
}

/// 창의 읽기 경계 — 호출 수 · 사업장 · 날짜 · KST 자정 · 목적을 기록한다. 실패 대역은 fixture 플래그로만.
class _DDayReads {
  _DDayReads(this.fx);
  final _DFx fx;
  final calls = <String, int>{};
  final biz = <String>{};
  final dates = <String>{};
  final dayStarts = <int>{};
  final purposes = <String>{};

  /// [r1 · 판정 §3-3] 호출별 날짜 · 주간 경계 원값(읽기 이름 → 호출 순서대로). 끝에서 고정 KST 기대와 단언한다.
  final at = <String, List<String>>{};
  var _dPendingTries = 0;

  void _dHit(String k, [String? businessId]) {
    calls[k] = (calls[k] ?? 0) + 1;
    if (businessId != null) biz.add(businessId);
  }

  void _dOn(String k, DateTime d) {
    final v = _dDk(d);
    dates.add(v);
    at.putIfAbsent(k, () => <String>[]).add(v);
  }

  DayApplicantsReads reads() => DayApplicantsReads(
        pendingApplications: ({required date, required businessId, purpose}) async {
          _dHit('pending', businessId);
          _dOn('pending', date);
          purposes.add('p:${purpose ?? '-'}');
          _dPendingTries++;
          if (fx.failFirst && _dPendingTries == 1) throw StateError('NCB-12O 관측 fixture — 첫 조회 실패');
          return fx.pending;
        },
        confirmedWorkers: ({required date, required businessId}) async {
          _dHit('confirmed', businessId);
          _dOn('confirmed', date);
          return fx.confirmed;
        },
        dayStaffing: ({required businessId, required dayStartMs}) async {
          _dHit('dayStaffing', businessId);
          dayStarts.add(dayStartMs);
          if (fx.rowsFail) throw StateError('NCB-12O 관측 fixture — 인력 현황 조회 실패');
          return fx.rows;
        },
        dayInvitations: ({required date, required businessId}) async {
          _dHit('invites', businessId);
          _dOn('invites', date);
          if (fx.invitesFail) throw StateError('NCB-12O 관측 fixture — 초대 현황 조회 실패');
          return fx.invites;
        },
        hasWorkedMap: ({required businessId, required date}) async {
          _dHit('hasWorked', businessId);
          _dOn('hasWorked', date);
          return const <String, bool>{};
        },
        noShowApplicationIds: ({required businessId, required date}) async {
          _dHit('noShow', businessId);
          _dOn('noShow', date);
          return <String>{};
        },
        usersBatch: (uids, {required businessId, purpose}) async {
          _dHit('users', businessId);
          purposes.add('u:${purpose ?? '-'}');
          return {for (final u in uids) if (fx.users.containsKey(u)) u: fx.users[u]!};
        },
        weeklyAttendance: ({required businessId, required weekStart, required weekEnd}) async {
          _dHit('weekly', businessId);
          at.putIfAbsent('weekly', () => <String>[]).add('${_dDk(weekStart)}..${_dDk(weekEnd)}');
          return <String, List<AttendanceModel>>{};
        },
        slotWorkDetailCapacities: (toId, slotId) async {
          _dHit('caps');
          if (fx.capsFail) throw StateError('NCB-12O 관측 fixture — 정원 조회 실패');
          return fx.caps;
        },
        slotWorkDetails: (toId, slotId) async {
          _dHit('slotWds');
          return <WorkDetailData>[];
        },
        to: (toId) async {
          _dHit('to');
          return null;
        },
        contractStatusBatch: (ids, {required businessId}) async {
          _dHit('contracts', businessId);
          return ContractStatusBatch(statuses: {for (final x in ids) if (fx.contracts.containsKey(x)) x: fx.contracts[x]});
        },
        contractAttendances: ({required businessId, required date}) async {
          _dHit('contractAtt', businessId);
          _dOn('contractAtt', date);
          return <AttendanceModel>[];
        },
      );
}

/// 날짜 원값 — 연-월-일T시:분 + 시간대 표시(Z=UTC · L=기기 지역). 창이 넘기는 값을 그대로 적는다.
String _dDk(DateTime d) => '${d.year}-${d.month}-${d.day}T${d.hour}:${d.minute}${d.isUtc ? 'Z' : 'L'}';


/// 모든 플랫폼 메시지 관찰 — 허용 Flutter 기반 채널은 원래 경로(센다) · Auth 정확 허용은 setUpAll 모의로(센다) ·
///   CF · 그 밖(Firestore · 저장소 · 허용 밖 flutter/*)은 이름을 기록하고 막는다(응답 null) · **막는 순간 tripped**(후속 UI 조작 중단).
class _DWire {
  final unexpected = <String>[];
  final cf = <String>[];
  final framework = <String, int>{};
  final auth = <String>[];
  var tripped = false;

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
    if (channel == _cfChannel) {
      cf.add(channel);
      tripped = true;
      return null;
    }
    for (final name in _authListeners) {
      if (channel == '$_authBase$name') {
        auth.add('register:$name');
        return handler?.call(message);
      }
      if (channel == '$_authFake$name') {
        String method;
        try {
          method = const StandardMethodCodec().decodeMethodCall(message).method;
        } catch (_) {
          method = '?';
        }
        if (method == 'listen' || method == 'cancel') {
          auth.add('$method:$name');
          return handler?.call(message);
        }
        unexpected.add('$channel#$method');
        tripped = true;
        return null;
      }
    }
    if (_frameworkAllow.containsKey(channel)) {
      framework.update(channel, (x) => x + 1, ifAbsent: () => 1);
      return handler != null ? handler(message) : m.delegate.send(channel, message);
    }
    unexpected.add(channel);
    tripped = true;
    return null;
  }
}

/// [F120-3] 외부 HTTP 차단 — 만들려는 시도를 기록하고 실패시킨다(끝에 0 단언).
class _DNoHttp extends HttpOverrides {
  _DNoHttp(this.wire);
  final _DWire wire;
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    wire.tripped = true;
    throw const SocketException('NCB-12O 관측 — 외부 HTTP 차단');
  }
}


/// 1단계 읽기 넷 — '다시 시도' 실제 탭으로 각 1 → 2(DU515 r3 에서 실측된 경로).
const _dPhase1 = ['pending', 'confirmed', 'dayStaffing', 'invites'];

/// 시각 오류 수집 — 넘침은 원문 전체 + 위치 두 줄, 그 밖 framework 오류도 원문 전체(DU516 r1 과 같다).
class _DSeen {
  final overflows = <String>[];
  final other = <String>[];

  void add(FlutterErrorDetails d) {
    final m = d.exceptionAsString();
    if (m.contains('overflowed')) {
      final full = d.toString();
      final k = full.indexOf('The relevant error-causing widget was');
      final loc = k < 0
          ? ''
          : full.substring(k).split('\n').skip(1).where((l) => l.trim().isNotEmpty).take(2).map((l) => l.trim()).join(' ');
      overflows.add('${m.split('\n').first} @ $loc\n$m');
    } else {
      other.add(m);
    }
  }
}


/// 상태 대역 — UNK = 인력 현황 · 초대 · 정원 조회 실패(지원 1 · 확정 2 는 유효).
_DFx _dStateFx(String id) => _dFixture(id);

/// 날짜별 창(DU-O002 '인력 현황') 사례 — DU526 하네스(홈 → '인원 현황 보기' → 창) 그대로 + 첫 화면 색(초대 외곽선 · 별표 카드) · 띠 2종 · 신분증 선택 모드.
///   쓰기 동작('요청하기' · '계약서 일괄작성' · '확정' · 별 토글)은 누르지 않는다 — '신분증 요청'(선택 모드 켜기 · 화면 상태만)과 하단 '닫기'만 누른다.
///   넘침 수는 기록만(계약서 미작성 띠 · 선택 모드는 이 창에서 처음 그리는 대역이다).
Future<void> _dayCase(WidgetTester t, _V v, ({String id, int shots}) c, String tok) async {
  // guard 를 이 사례의 어떤 초기화보다 먼저 건다(대역 · provider · 홈 생성 전). 이전 값은 모두 잡아 둔다.
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final wire = _DWire();
  final net = _DNoHttp(wire);
  final prevAll = messenger.allMessagesHandler;
  final prevHttp = HttpOverrides.current;
  final prevOnError = FlutterError.onError;
  final prevOverride = DayApplicantsReads.debugOverride;
  messenger.allMessagesHandler = (channel, handler, message) => wire.route(messenger, channel, handler, message);
  HttpOverrides.global = net;
  addTearDown(() {
    messenger.allMessagesHandler = prevAll;
    HttpOverrides.global = prevHttp;
    FlutterError.onError = prevOnError;
    DayApplicantsReads.debugOverride = prevOverride;
  });
  t.view.physicalSize = Size(v.w, v.h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final mode = _before ? 'before' : 'strict';
  _out('D535 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
  final seen = _DSeen();
  void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
  void safe(String step) => need('안전 대역($step) — 예상 밖 채널 · CF · HTTP 0', !wire.tripped && net.tries.isEmpty,
      'cf ${wire.cf.length} 예상 밖 [${wire.unexpected.join(' | ')}] http ${net.tries.length}');
  final checks = <(String, bool, String)>[];
  void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

  final fx = _dStateFx(c.id);
  final owner = _DOwner(bizIds: fx.bizIds);
  final homeCalls = <String, int>{};
  final dayReads = _DDayReads(fx);
  Object? failure;
  StackTrace? failureSt;
  var shots = 0;
  var closed = false;
  var raw = '';
  try {
    FlutterError.onError = seen.add;
    DayApplicantsReads.debugOverride = dayReads.reads();
    final key = GlobalKey();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: owner),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
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
          home: BusinessAdminHomeScreen(reads: _dHomeReads(fx, homeCalls)),
        ),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    safe('홈 열림');
    final entryF = find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? '') == '인원 현황 보기');
    final nEntry = entryF.evaluate().length;
    need('홈 인원 현황 보기 행 ≥1', nEntry >= 1, '개수 $nEntry');
    await t.ensureVisible(entryF.first);
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.tap(find.ancestor(of: entryF.first, matching: find.byType(InkWell)).first);
    for (var i = 0; i < 24; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final dlg = find.byType(DayApplicantsDialog);
    final nDlg = dlg.evaluate().length;
    need('창 1', nDlg == 1, '개수 $nDlg');
    safe('창 열림');
    Future<void> shot(String id, String state) async {
      _out('D535 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    // ① 첫 화면(끌기 전) — 초대 외곽선 버튼 · 지원자 카드 면(별표 카드 포함)을 위젯 값으로 잰다(자리와 무관).
    await shot('1open', 'list-open');
    safe('첫 캡처');
    final io = _invLine(t, findVisibleText(_inviteText), tok);
    final fo = _favLine(t, dlg, tok);
    // ② 띠 2종 — '계약서 일괄작성'을 화면에 넣고 색 · 테두리 · 낱말 줄바꿈을 잰다(누르지 않는다).
    final bo = await _bandLine(t, dlg, tok, false);
    safe('띠 재기');
    await shot('2dbands', 'bands');
    safe('띠 캡처');
    // ③ '신분증 요청' 한 번(선택 모드 = 화면 상태만 · 쓰기 0) → '요청하기' · '취소' · 띠 면/테두리.
    final idBtn = find.text('신분증 요청');
    if (bo.nIdBtn == 1) {
      await t.ensureVisible(idBtn);
      for (var m = 0; m < 4; m++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.tap(idBtn);
      for (var m = 0; m < 8; m++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }
    safe('신분증 요청(선택 모드)');
    final so = _selLine(t, dlg, tok);
    await shot('3dselect', 'idcard-select');
    safe('선택 캡처');
    raw = 'inv ${io.n} ${io.fg}/${io.side} fav ${fo.raw} band ${bo.raw} sel ${so.raw}';
    if (!_before) {
      for (final x in _topChecks(io, fo)) {
        chk(x.$1, x.$2, x.$3);
      }
      for (final x in _bandChecks(bo, so)) {
        chk(x.$1, x.$2, x.$3);
      }
    }

    // ④ 닫기
    final closeF = find.descendant(of: find.byType(AppModalFooter), matching: find.widgetWithText(TextButton, '닫기'), skipOffstage: true);
    final nClose = closeF.evaluate().length;
    need('하단 닫기 1', nClose == 1, '개수 $nClose');
    await t.tap(closeF);
    for (var i = 0; i < 16; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final nAfter = find.byType(DayApplicantsDialog).evaluate().length;
    closed = nAfter == 0;
    safe('닫기');
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // ⑤ 성공 · 실패 공통 정리 — 홈 · 창을 내리고 남은 timer · 지연 응답이 끝날 시간을 준다. guard 는 아직 걸려 있다.
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

  // ⑥ 최종 안전 집계 — 해제 · 대기 뒤 guard 아래에서 센다(값 측정과 분리).
  final p1ok = _dPhase1.every((k) => (dayReads.calls[k] ?? 0) == 1);
  final p1Text = [for (final k in _dPhase1) '$k*${dayReads.calls[k] ?? 0}'].join(',');
  final nUnexp = wire.unexpected.length;
  final nCf = wire.cf.length;
  final nHttp = net.tries.length;
  final tripped = wire.tripped;
  final unText = wire.unexpected.join(' | ');
  _out('D535 $tok att reader p1=$p1ok closed=$closed cf=$nCf unexpected=$nUnexp http=$nHttp');

  messenger.allMessagesHandler = prevAll;
  HttpOverrides.global = prevHttp;
  DayApplicantsReads.debugOverride = prevOverride;
  final exc = t.takeException();
  if (exc != null && failure == null) {
    failure = exc;
    failureSt = StackTrace.current;
  }
  final nOvf = seen.overflows.length;
  final nFw = seen.other.length;
  final ovfRaw = seen.overflows.join('\n----\n');
  final fwRaw = seen.other.join('\n----\n');
  _out('R535 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
      'fail64=${_enc(failure?.toString() ?? '')}');
  _out('D535 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

  final f0 = failure;
  if (f0 != null) {
    _halt ??= '$tok ${f0.toString().split('\n').first}';
    Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
  }
  if (!_before) chk('strict 미처리 framework 예외 0', nFw == 0, fwRaw);
  chk('캡처 수 = 선언', shots == c.shots, 'shots $shots want ${c.shots}');
  chk('읽기 1단계 호출 수(해제 · 대기 뒤) · 닫힘', p1ok && closed, 'p1 $p1Text want 각 1 closed $closed');
  chk('시험 전체 CF 0 · 예상 밖 채널 0 · HTTP 0(해제 · 대기 뒤)', nCf == 0 && nUnexp == 0 && nHttp == 0 && !tripped,
      'cf $nCf 예상 밖 [$unText] http $nHttp tripped $tripped');
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
    _out('R535 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });
  tearDown(() {
    WorkApplicantsReads.debugOverride = null;
    DayApplicantsReads.debugOverride = null;
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S903CK-${v.id}-${c.id} 지원자 두 창 신분증 선택 체크 brand · 계약 미리보기 안내 띠 중립', (t) async {
        final tok = 'S903CK-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        // 날짜별 창 사례는 자기 하네스(홈 → 창)로 돈다 — 아래 본문은 업무별 창 전용.
        if (c.id == 'DBANDS') {
          await _dayCase(t, v, c, tok);
          return;
        }

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
        final mode = _before ? 'before' : 'strict';
        _out('D535 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
                builder: (ctx, child) =>
                    MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: Scaffold(body: WorkApplicantsDialog(key: UniqueKey(), toItem: _item(), work: c.id == 'GROUP' ? null : _wd1(), onChanged: () {})),
              ),
            ),
          ));
          for (var i = 0; i < 40; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          final dlg = find.byType(WorkApplicantsDialog);
          final nDlg = dlg.evaluate().length;
          need('창 1', nDlg == 1, '개수 $nDlg');
          // 배치 오류(무한 높이 등)가 난 트리는 크기를 읽을 수 없다 — 그때는 재지 않고 수만 남긴다(before 의 B EMPTY · FAIL).
          final broken = seen.other.isNotEmpty;
          final screen = Offset.zero & Size(v.w, v.h);

          /// 상태 본문 관측 — 통계 줄 수 · 안내([msgF])와 '닫기'가 보이는 칸 안 + 중심 hit · 본문([bodyF]) 높이. 출력 한 줄(키 고정).
          Future<({int stat, int msg, int close, bool inScroll, bool msgIn, bool msgHit, bool closeIn, bool closeHit})> obs(Finder msgF, Finder bodyF) async {
            final statF = find.text('지원: ');
            final nStat = statF.evaluate().length;
            final nMsg = msgF.evaluate().length;
            final closeF = find.descendant(of: find.byType(AppModalFooter), matching: findVisibleText('닫기'), skipOffstage: true);
            final nClose = closeF.evaluate().length;
            var inScroll = false;
            var msgIn = false;
            var msgHit = false;
            var closeIn = false;
            var closeHit = false;
            var bodyH = 0.0;
            var lay = '-';
            if (!broken && nStat == 1 && nMsg == 1 && nClose == 1 && bodyF.evaluate().isNotEmpty) {
              final scF = find.ancestor(of: statF, matching: find.byType(Scrollable));
              inScroll = scF.evaluate().isNotEmpty;
              final pre = inScroll ? t.state<ScrollableState>(scF.first).position.pixels : 0.0;
              final dr = t.getRect(find.descendant(of: find.descendant(of: dlg, matching: find.byType(Dialog), skipOffstage: true).first,
                  matching: find.byType(Material), skipOffstage: true).first);
              final sr0 = t.getRect(statF);
              final br0 = t.getRect(bodyF.first);
              await t.ensureVisible(msgF);
              for (var m = 0; m < 4; m++) {
                await t.pump(const Duration(milliseconds: 50));
              }
              final post = inScroll ? t.state<ScrollableState>(scF.first).position.pixels : 0.0;
              final mr = t.getRect(msgF);
              msgIn = _inside(mr, _area(msgF, screen));
              msgHit = t.hitTestOnBinding(mr.center).path.any((x) => identical(x.target, t.renderObject(msgF)));
              final cr = t.getRect(closeF);
              closeIn = _inside(cr, screen);
              closeHit = t.hitTestOnBinding(cr.center).path.any((x) => identical(x.target, t.renderObject(closeF)));
              bodyH = br0.height;
              lay = '${dr.top.toStringAsFixed(1)},${dr.height.toStringAsFixed(1)},${(sr0.top - dr.top).toStringAsFixed(1)},${(br0.top - dr.top).toStringAsFixed(1)},'
                  '${br0.height.toStringAsFixed(1)},${pre.toStringAsFixed(1)},${post.toStringAsFixed(1)}';
            }
            _out('D535 $tok att body stat=$nStat msg=$nMsg close=$nClose inscroll=$inScroll msgin=$msgIn msghit=$msgHit closein=$closeIn closehit=$closeHit '
                'bodyh=${bodyH.toStringAsFixed(1)}');
            _out('R535 $tok lay ${v.id} ${c.id} $lay');
            return (stat: nStat, msg: nMsg, close: nClose, inScroll: inScroll, msgIn: msgIn, msgHit: msgHit, closeIn: closeIn, closeHit: closeHit);
          }

          /// 머리 밀도 관측(첫 화면 · 끌기 전에 부른다) — 보조 줄 · 통계 줄 개수, 보조 줄 자리(고정 머리의 자손인가 · 스크롤 안인가 · 보이는 칸 안인가),
          ///   읽기 순서(세로 위치: 보조 < 통계 < 초대 < 첫 카드 — 있는 것만), 닫기(X) 받는 자리 · 중심 hit, 고정 머리 높이, 첫 카드의 첫 화면 가시 높이.
          ///   고정 머리 = 제목에서 가장 가까운 Container(_buildHeader 의 바깥 상자). 그리지 않는 재기용 사본(Offstage)은 finder 기본값이 뺀다. 출력 한 줄(키 고정).
          void dense() {
            final dSub = findVisibleText(_subText);
            final dStat = find.text('지원: ');
            final dTitle = findVisibleText(_titleText);
            final dInv = findVisibleText(_inviteText);
            final dRow = find.byType(ApplicantRowSurface);
            final dnSub = dSub.evaluate().length;
            final dnStat = dStat.evaluate().length;
            final dnTitle = dTitle.evaluate().length;
            var hin = false;
            var sscroll = false;
            var svis = false;
            var order = false;
            var x48 = false;
            var xhit = false;
            var dnX = 0;
            var hh = 0.0;
            var card1 = 0.0;
            var dRaw = '-';
            if (!broken && dnSub == 1 && dnStat == 1 && dnTitle == 1) {
              final dHead = find.ancestor(of: dTitle, matching: find.byType(Container)).first;
              hin = find.descendant(of: dHead, matching: dSub, skipOffstage: true).evaluate().isNotEmpty;
              sscroll = find.ancestor(of: dSub, matching: find.byType(Scrollable)).evaluate().isNotEmpty;
              final subR = t.getRect(dSub);
              final statR = t.getRect(dStat);
              svis = _inside(subR, _area(dSub, screen));
              order = subR.top < statR.top;
              var lastTop = statR.top;
              if (dInv.evaluate().length == 1) {
                final invR = t.getRect(dInv);
                order = order && lastTop < invR.top;
                lastTop = invR.top;
              }
              if (dRow.evaluate().isNotEmpty) {
                final rowR = t.getRect(dRow.first);
                final rowA = _area(dRow.first, screen);
                order = order && lastTop < rowR.top;
                final lo = rowR.top > rowA.top ? rowR.top : rowA.top;
                final hi = rowR.bottom < rowA.bottom ? rowR.bottom : rowA.bottom;
                card1 = hi > lo ? hi - lo : 0.0;
              }
              final dX = find.descendant(of: dHead, matching: find.byType(IconButton), skipOffstage: true);
              dnX = dX.evaluate().length;
              if (dnX == 1) {
                final xR = t.getRect(dX);
                x48 = xR.width >= 48 - 0.01 && xR.height >= 48 - 0.01;
                xhit = _hitWithin(t, dX, xR.center);
              }
              final headR = t.getRect(dHead);
              hh = headR.height;
              dRaw = 'head=$headR sub=$subR stat=$statR x=$dnX';
            }
            _out('D535 $tok att dense nsub=$dnSub nstat=$dnStat hin=$hin sscroll=$sscroll svis=$svis order=$order x48=$x48 xhit=$xhit '
                'hh=${hh.toStringAsFixed(1)} card1=${card1.toStringAsFixed(1)}');
            if (!_before) {
              chk('strict 보조 줄 1 · 통계 줄 1 · 머리 제목 1(중복 0)', dnSub == 1 && dnStat == 1 && dnTitle == 1, 'sub $dnSub stat $dnStat title $dnTitle');
              if (v.id == 'B') chk('strict B 보조 줄 = 본문 스크롤 안 · 고정 머리 안 0', sscroll && !hin, 'sscroll $sscroll hin $hin $dRaw');
              if (v.id == 'W') chk('strict W 보조 줄 = 고정 머리 안(스크롤 밖 · 이전 배치)', hin && !sscroll, 'sscroll $sscroll hin $hin $dRaw');
              chk('strict 보조 줄이 첫 화면의 보이는 칸 안', svis, dRaw);
              chk('strict 읽기 순서(세로) 보조 < 통계 < 초대 < 첫 카드', order, dRaw);
              chk('strict 닫기(X) 1 · 받는 자리 ≥48 · 중심 hit', dnX == 1 && x48 && xhit, 'n $dnX x48 $x48 hit $xhit $dRaw');
            }
          }

          /// 통계 구역 관측(첫 화면 · 끌기 전에 부른다) — 구역 수('지원: ' 라벨 수) · 구역 안 글을 그려진 순서대로 이은 것(set) · 글마다 한 줄인가 ·
          ///   항목(점 + 라벨 + 값 Row)마다 라벨과 값이 같은 줄인가 · 글이 구역 상자 안인가 · 항목이 놓인 줄 수(runs · '필요 n명' 묶음 포함 · 세로 가운데가 1 넘게 다른 것) · 구역 높이.
          ///   구역 = '지원: ' 라벨에서 가장 가까운 Container(_buildStatsBar 의 바깥 상자). 출력 한 줄(키 고정).
          void stats() {
            final gLab = find.text('지원: ');
            final gN = gLab.evaluate().length;
            var gSet = '-';
            var oneline = false;
            var intact = false;
            var inbar = false;
            var runs = 0;
            var sh = 0.0;
            var gRaw = '-';
            if (!broken && gN == 1) {
              final gBar = find.ancestor(of: gLab, matching: find.byType(Container)).first;
              final barR = t.getRect(gBar);
              final gTexts = find.descendant(of: gBar, matching: find.byType(Text), skipOffstage: true);
              final gItems = find.descendant(of: gBar, matching: find.byType(Row), skipOffstage: true);
              final words = <String>[];
              final mids = <double>[];
              var multi = 0;
              var outside = 0;
              final nText = gTexts.evaluate().length;
              for (var i = 0; i < nText; i++) {
                final one = gTexts.at(i);
                words.add(t.widget<Text>(one).data ?? '');
                final rp = t.renderObject<RenderParagraph>(find.descendant(of: one, matching: find.byType(RichText), skipOffstage: true).first);
                if (_lineCount(rp) != 1) multi++;
                final tr = t.getRect(one);
                if (!_inside(tr, barR)) outside++;
              }
              var split = 0;
              final nItem = gItems.evaluate().length;
              for (var i = 0; i < nItem; i++) {
                final row = gItems.at(i);
                final rowR = t.getRect(row);
                mids.add(rowR.center.dy);
                final inRow = find.descendant(of: row, matching: find.byType(Text), skipOffstage: true);
                if (inRow.evaluate().length != 2) {
                  split++;
                  continue;
                }
                final a = t.getRect(inRow.at(0));
                final b = t.getRect(inRow.at(1));
                if (a.center.dy < b.top || a.center.dy > b.bottom || a.right > b.left + 0.5) split++;
              }
              final need5 = findVisibleTextContaining('필요 ');
              final capF = find.descendant(of: gBar, matching: need5, skipOffstage: true);
              if (capF.evaluate().isNotEmpty) mids.add(t.getRect(capF.first).center.dy);
              mids.sort();
              var lineN = mids.isEmpty ? 0 : 1;
              for (var i = 1; i < mids.length; i++) {
                if (mids[i] - mids[i - 1] > 1.0) lineN++;
              }
              gSet = _enc(words.join('|'));
              oneline = nText > 0 && multi == 0;
              intact = nItem > 0 && split == 0;
              inbar = outside == 0;
              runs = lineN;
              sh = barR.height;
              gRaw = 'bar=$barR texts=$nText items=$nItem multi=$multi split=$split outside=$outside words=${words.join('|')}';
            }
            _out('D535 $tok att stats nbar=$gN set=$gSet oneline=$oneline intact=$intact inbar=$inbar runs=$runs sh=${sh.toStringAsFixed(1)}');
            if (!_before && c.id != 'GROUP') {
              chk('strict 통계 구역 1', gN == 1, '개수 $gN');
              chk('strict 통계 글마다 한 줄 · 항목(라벨 + 값) 안 줄바꿈 0 · 글이 구역 안', oneline && intact && inbar, gRaw);
              if (c.id == 'ROWS' || c.id == 'BULK' || c.id == 'BANDS') {
                chk('strict 통계 글 · 순서 불변(지원 3 · 확정 2 · 부족 3 · 필요 5)', gSet == _enc(_statWords), gRaw);
                if (v.id == 'B') chk('strict B 통계 항목이 가로로 흐른다(4항목 · 줄 3 이하)', runs >= 1 && runs <= 3, gRaw);
                if (v.id == 'W') chk('strict W 통계 배치 불변(항목마다 한 줄 = 4줄)', runs == 4, gRaw);
              }
            }
          }

          Future<void> shot(String id, String state) async {
            _out('D535 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          if (c.id == 'ROWS') {
            // ① 행 버튼 — 카드(ApplicantRowSurface) 안의 InkWell › Container(카드 전체 InkWell 은 child 가 Padding 이라 빠진다).
            await shot('1top', 'rows-top');
            dense();
            stats();
            // [DU534] 첫 화면 색 — 초대 외곽선 버튼 · 지원자 카드 면(별표 카드 포함). 위젯 값으로 잰다(끌기 전 · 누르지 않는다).
            final invObs = _invLine(t, findVisibleText(_inviteText), tok);
            final favObs = _favLine(t, dlg, tok);
            if (!_before) {
              for (final x in _topChecks(invObs, favObs)) {
                chk(x.$1, x.$2, x.$3);
              }
            }
            // ⓪ 배치 — 통계 줄이 명단 스크롤 안인가 · 명단 스크롤 칸 가시 높이 · 창 기준 자리(W 는 TB = TA 여야 한다 — R535 lay 줄 대조).
            final rowF = find.byType(ApplicantRowSurface);
            final nRow = rowF.evaluate().length;
            need('명단 행 5', nRow == 5, '개수 $nRow');
            final statF = find.text('지원: ');
            final nStat = statF.evaluate().length;
            need('통계 지원 칸 1', nStat == 1, '개수 $nStat');
            final inList = find.ancestor(of: statF, matching: find.byType(Scrollable)).evaluate().isNotEmpty;
            final listF = find.ancestor(of: rowF.first, matching: find.byType(Scrollable));
            final nList = listF.evaluate().length;
            need('명단 스크롤 칸 ≥1', nList >= 1, '개수 $nList');
            final vp = t.getRect(listF.first);
            final sr = t.getRect(statF);
            final dr = t.getRect(find.descendant(of: find.descendant(of: dlg, matching: find.byType(Dialog), skipOffstage: true).first,
                matching: find.byType(Material), skipOffstage: true).first);
            final fr0 = t.getRect(rowF.first);
            _out('R535 $tok lay ${v.id} ${c.id} ${(sr.top - dr.top).toStringAsFixed(1)},${(vp.top - dr.top).toStringAsFixed(1)},${vp.height.toStringAsFixed(1)},'
                '${(fr0.top - dr.top).toStringAsFixed(1)},${dr.top.toStringAsFixed(1)},${dr.height.toStringAsFixed(1)}');
            // ⓪-2 머리 제목 · 보조 줄 · 초대 버튼 글 — 그려진 글과 읽는 이름이 각각 원문과 같은가 · 전문 · 낱말 안 끊김(끌기 전에 잰다).
            final titleF = findVisibleText(_titleText);
            final subF = findVisibleText(_subText);
            final invF = findVisibleText(_inviteText);
            final nTitle = titleF.evaluate().length;
            final nSub = subF.evaluate().length;
            final nInv = invF.evaluate().length;
            need('머리 제목 1 · 보조 줄 1 · 초대 버튼 글 1', nTitle == 1 && nSub == 1 && nInv == 1, '개수 $nTitle/$nSub/$nInv');
            final ho = _textObs(t, titleF, _titleText);
            final so = _textObs(t, subF, _subText);
            final io = _textObs(t, invF, _inviteText);
            _out('D535 $tok att head tshown=${ho.shown} tname=${ho.name} tfull=${ho.full} tell0=${ho.ell0} tbrk=${ho.brk} sshown=${so.shown} sname=${so.name} '
                'sfull=${so.full} sbrk=${so.brk}');
            _out('D535 $tok att inv shown=${io.shown} name=${io.name} full=${io.full} brk=${io.brk}');
            _out('R535 $tok txt ${v.id} ${c.id} ${ho.size.width.toStringAsFixed(1)},${ho.size.height.toStringAsFixed(1)},${so.size.width.toStringAsFixed(1)},'
                '${so.size.height.toStringAsFixed(1)},${io.size.width.toStringAsFixed(1)},${io.size.height.toStringAsFixed(1)}');
            if (!_before) {
              chk('strict 머리 제목 — 그려진 글 · 읽는 이름 = 원문 · 전문(말줄임 0) · 낱말 안 끊김 0', ho.shown && ho.name && ho.full && ho.ell0 && ho.brk == 0, ho.toString());
              chk('strict 머리 보조 줄 — 그려진 글 · 읽는 이름 = 원문 · 전문 · 덩어리 안 끊김 0', so.shown && so.name && so.full && so.brk == 0, so.toString());
              chk('strict 초대 버튼 글 — 그려진 글 · 읽는 이름 = 원문 · 전문 · 낱말 안 끊김 0', io.shown && io.name && io.full && io.brk == 0, io.toString());
            }
            // 끌어서 마지막 행 → 다시 맨 위 → 첫 행(끌기 뒤 개수 가드 — 칸 높이가 없으면 끌지 않고 도달 false).
            var reachFirst = false;
            var reachLast = false;
            if (vp.height >= 1) {
              await t.drag(listF.first, const Offset(0, -6000));
              for (var m = 0; m < 6; m++) {
                await t.pump(const Duration(milliseconds: 50));
              }
              final nAfterDown = rowF.evaluate().length;
              if (nAfterDown == 5) {
                final lr = t.getRect(rowF.last);
                reachLast = lr.bottom <= vp.bottom + 0.5 && lr.bottom > vp.top;
              }
              await t.drag(listF.first, const Offset(0, 6000));
              for (var m = 0; m < 6; m++) {
                await t.pump(const Duration(milliseconds: 50));
              }
              await t.ensureVisible(rowF.first);
              for (var m = 0; m < 6; m++) {
                await t.pump(const Duration(milliseconds: 50));
              }
              final nAfterUp = rowF.evaluate().length;
              if (nAfterUp == 5) {
                final fr = t.getRect(rowF.first);
                reachFirst = fr.top >= vp.top - 0.5 && fr.top < vp.bottom;
              }
            }
            final vpH = vp.height;
            _out('D535 $tok att lay inlist=$inList vph=${vpH.toStringAsFixed(1)} first=$reachFirst last=$reachLast');
            if (!_before) {
              chk('strict 스크롤로 첫 행 · 마지막 행 도달', reachFirst && reachLast, 'first $reachFirst last $reachLast vp $vp');
              if (v.id == 'B') chk('strict B 통계 줄이 명단 스크롤 안 · 명단 칸 가시 높이 ≥150', inList && vpH >= 150, 'inList $inList vph $vpH');
              if (v.id == 'W') chk('strict W 통계 줄 고정(스크롤 밖)', !inList, 'inList $inList');
            }
            bool isRowBtn(Widget w) => w is InkWell && w.child is Container;
            final btnF = find.descendant(of: find.byType(ApplicantRowSurface), matching: find.byWidgetPredicate(isRowBtn), skipOffstage: true);
            final n = btnF.evaluate().length;
            need('행 버튼 ≥2', n >= 2, '개수 $n');
            var faces = 0;
            var lowCr = 0;
            var small = 0;
            var miss = 0;
            var offs = 0;
            var maxBrand = 0;
            var mainN = 0;
            var mainBrand = 0;
            final perRow = <int, int>{};
            final labels = <String>{};
            final rowsRaw = <String>[];
            final geo = <String>[];
            for (var i = 0; i < n; i++) {
              final one = btnF.at(i);
              // 문구는 위젯 값으로 먼저 모은다(자리와 무관 — 문구 집합은 두 모드에서 같아야 한다).
              labels.add(t.widget<Text>(find.descendant(of: one, matching: find.byType(Text), skipOffstage: true).first).data ?? '');
              await t.ensureVisible(one);
              for (var m = 0; m < 4; m++) {
                await t.pump(const Duration(milliseconds: 50));
              }
              // 보이는 것만 잰다 — 가장 가까운 스크롤 칸 안에 들어온 버튼만(아니면 세고 건너뛴다).
              final scF = find.ancestor(of: one, matching: find.byType(Scrollable));
              final nSc = scF.evaluate().length;
              final area = nSc == 0 ? (Offset.zero & Size(v.w, v.h)) : t.getRect(scF.first);
              final r0 = t.getRect(one);
              if (!_inside(r0, area)) {
                offs++;
                rowsRaw.add('$i 칸 밖 r=$r0 area=$area');
                continue;
              }
              final surfF = find.ancestor(of: one, matching: find.byType(ApplicantRowSurface));
              final surf = t.widget<ApplicantRowSurface>(surfF.first);
              final rowId = identityHashCode(surfF.evaluate().first);
              final p = _probe(t, one, Color.alphaBlend(surf.background, Colors.white));
              if (_classFace(p.fill)) faces++;
              if (p.cr < 4.5) lowCr++;
              if (!p.big) small++;
              if (!p.hit) miss++;
              if (p.label == '확정' || p.label == '계약서 작성') {
                mainN++;
                if (p.fill == AppColors.brand) mainBrand++;
              }
              if (p.fill == AppColors.brand) {
                final nb = (perRow[rowId] ?? 0) + 1;
                perRow[rowId] = nb;
                if (nb > maxBrand) maxBrand = nb;
              }
              geo.add('${p.label}:${p.r.width.toStringAsFixed(1)},${p.r.height.toStringAsFixed(1)},${_hex(p.fill)},${_hex(p.fg)},${p.cr.toStringAsFixed(2)}');
              rowsRaw.add('$i ${p.label} r=${p.r} fill=${_hex(p.fill)} fg=${_hex(p.fg)} cr=${p.cr.toStringAsFixed(2)} hit=${p.hit}');
            }
            final sorted = labels.toList()..sort();
            final setText = sorted.join('|');
            final nOwn = seen.own;
            final nUnk = seen.unk;
            raw = rowsRaw.join(' | ');
            _out('D535 $tok att btns n=$n set=${_enc(setText)} offs=$offs face0=${faces == 0} brand1=${maxBrand <= 1} cr45=${lowCr == 0} '
                'min48=${small == 0} hit=${miss == 0} own0=${nOwn == 0 && nUnk == 0}');
            _out('R535 $tok geo ${v.id} ${c.id} ${_enc(geo.join(';'))}');
            await shot('2end', 'rows-end');
            if (!_before) {
              chk('strict 행 버튼 문구 집합 불변', setText == _rowLabels.join('|'), 'set $setText');
              chk('strict 행 버튼 14개를 모두 화면에 넣어 잼(두 보기)', offs == 0 && n == 14, 'offs $offs n $n');
              chk('strict 행 버튼 분류색 면 0', faces == 0, raw);
              chk('strict brand 채움 버튼 행당 ≤1', maxBrand <= 1, 'max $maxBrand');
              chk('strict 행의 확정 · 계약서 작성 = brand 채움 유지(4개 모두)', mainN == 4 && mainBrand == 4, 'n $mainN brand $mainBrand');
              chk('strict 행 버튼 글자/면 대비 ≥4.5', lowCr == 0, raw);
              chk('strict 행 버튼 받는 자리 ≥48 · 중심 hit', small == 0 && miss == 0, raw);
              chk('strict 행 버튼 줄(:$_ownLo–$_ownHi) 발 넘침 0 · 위치 모르는 넘침 0', nOwn == 0 && nUnk == 0, 'own $nOwn unk $nUnk');
            }
          } else if (c.id == 'EMPTY') {
            // ③ 빈 상태(조회 성공 · 지원 0) — 안내 글과 '닫기'가 닿는가.
            await shot('1empty', 'empty-top');
            dense();
            stats();
            final o = await obs(findVisibleText(_emptyText), find.byType(AppEmptyState));
            await shot('2msg', 'empty-message');
            if (!_before) {
              chk('strict EMPTY 통계 줄 1 · 안내 글 1 · 닫기 1', o.stat == 1 && o.msg == 1 && o.close == 1, o.toString());
              chk('strict EMPTY 안내 글이 보이는 칸 안 + hit · 닫기 화면 안 + hit', o.msgIn && o.msgHit && o.closeIn && o.closeHit, o.toString());
              chk('strict EMPTY 통계 줄 자리(B = 본문과 한 스크롤 · W = 고정)', o.inScroll == (v.id == 'B'), o.toString());
            }
          } else if (c.id == 'FAIL') {
            // ④ 첫 조회 실패 — 안내 글 · '다시 시도' · '닫기'가 닿는가 → '다시 시도' 한 번 → 재조회 1회 → 명단 5 · 통계 줄 1.
            await shot('1fail', 'fail-top');
            dense();
            stats();
            final o = await obs(findVisibleText(_failText), find.byType(AppEmptyState));
            final retryF = find.descendant(of: find.byType(AppEmptyState), matching: findVisibleText('다시 시도'), skipOffstage: true);
            final nRetry = retryF.evaluate().length;
            var retryIn = false;
            var retryHit = false;
            if (!broken && nRetry == 1) {
              await t.ensureVisible(retryF);
              for (var m = 0; m < 4; m++) {
                await t.pump(const Duration(milliseconds: 50));
              }
              final rr = t.getRect(retryF);
              retryIn = _inside(rr, _area(retryF, screen));
              retryHit = t.hitTestOnBinding(rr.center).path.any((x) => identical(x.target, t.renderObject(retryF)));
            }
            await shot('2btn', 'fail-retry-button');
            if (retryIn && retryHit) {
              await t.tap(retryF);
              for (var i = 0; i < 40; i++) {
                await t.pump(const Duration(milliseconds: 50));
              }
            }
            final callsAfter = reads.calls['applications'] ?? 0;
            final rowsAfter = find.byType(ApplicantRowSurface).evaluate().length;
            final statAfter = find.text('지원: ').evaluate().length;
            _out('D535 $tok att retry n=$nRetry rin=$retryIn rhit=$retryHit calls=$callsAfter rows=$rowsAfter stat=$statAfter');
            await shot('3rows', 'after-retry');
            if (!_before) {
              chk('strict FAIL 통계 줄 1 · 안내 글 1 · 닫기 1', o.stat == 1 && o.msg == 1 && o.close == 1, o.toString());
              chk('strict FAIL 안내 글이 보이는 칸 안 + hit · 닫기 화면 안 + hit', o.msgIn && o.msgHit && o.closeIn && o.closeHit, o.toString());
              chk('strict FAIL 통계 줄 자리(B = 본문과 한 스크롤 · W = 고정)', o.inScroll == (v.id == 'B'), o.toString());
              chk('strict FAIL 다시 시도 1 · 보이는 칸 안 + hit', nRetry == 1 && retryIn && retryHit, 'n $nRetry in $retryIn hit $retryHit');
              chk('strict FAIL 다시 시도 → 재조회 1회(합 2) → 명단 5 · 통계 줄 1(중복 0)', callsAfter == 2 && rowsAfter == 5 && statAfter == 1,
                  'calls $callsAfter rows $rowsAfter stat $statAfter');
            }
          } else if (c.id == 'LOADING') {
            // ⑤ 불러오는 중(응답 지연) — 통계 줄 1 · 진행 표시와 '닫기'가 화면 안.
            await shot('1load', 'loading');
            dense();
            stats();
            final o = await obs(find.byType(LoadingWidget), find.byType(LoadingWidget));
            if (!_before) {
              chk('strict LOADING 통계 줄 1 · 진행 표시 1 · 닫기 1', o.stat == 1 && o.msg == 1 && o.close == 1, o.toString());
              chk('strict LOADING 진행 표시가 보이는 칸 안 · 닫기 화면 안 + hit', o.msgIn && o.closeIn && o.closeHit, o.toString());
            }
          } else if (c.id == 'BANDS') {
            // ⑥ 띠 2종 — 신분증 요청(요청 가능 2명) · 계약서 미작성(확정 2명 모두 계약 없음 대역). 아이콘 · 글 · 버튼의 색 · 대비 · 낱말 줄바꿈을 잰 뒤
            //   '신분증 요청'을 한 번 눌러 선택 모드(화면 상태만 · 쓰기 0)의 '요청하기' · '취소' 색을 잰다. '요청하기' · '계약서 일괄작성'은 누르지 않는다.
            //   개수가 맞지 않으면 재지 않고 '-' 로 적는다(strict 는 개수 1 을 단언한다).
            stats();
            final bo = await _bandLine(t, dlg, tok, broken);
            await shot('1bands', 'bands');
            final idBtn = find.text('신분증 요청');
            if (bo.nIdBtn == 1) {
              await t.ensureVisible(idBtn);
              for (var m = 0; m < 4; m++) {
                await t.pump(const Duration(milliseconds: 50));
              }
              await t.tap(idBtn);
              for (var m = 0; m < 8; m++) {
                await t.pump(const Duration(milliseconds: 50));
              }
            }
            final so = _selLine(t, dlg, tok);
            await shot('2select', 'idcard-select');
            raw = 'band ${bo.raw} sel ${so.raw}';
            if (!_before) {
              for (final x in _bandChecks(bo, so)) {
                chk(x.$1, x.$2, x.$3);
              }
            }
          } else if (c.id == 'GROUP') {
            // ⑦ 묶음 창(work 없음) — 업무 묶음 머리의 합계 칩('지원 3' · '확정 2') 색. 이 상태의 넘침 · framework 오류 수는 기록만 한다(TB = TA 대조 —
            //   묶음 창은 이전에 그려 본 시험이 없어 기존 값이 알려져 있지 않다).
            stats();
            final pChip = find.text('지원 3');
            final cChip = find.text('확정 2');
            final nP = pChip.evaluate().length;
            final nC = cChip.evaluate().length;
            final nGroupRows = find.byType(ApplicantRowSurface).evaluate().length;
            var pFace = '-';
            var pFg = '-';
            var cFace = '-';
            var cFg = '-';
            var chipCr = false;
            if (!broken && nP == 1 && nC == 1) {
              final pFaceC = _faceOf(t, pChip);
              final pFgC = _fgOf(t, pChip);
              final cFaceC = _faceOf(t, cChip);
              final cFgC = _fgOf(t, cChip);
              pFace = _hex(pFaceC);
              pFg = _hex(pFgC);
              cFace = _hex(cFaceC);
              cFg = _hex(cFgC);
              chipCr = _contrast(pFgC, Color.alphaBlend(pFaceC, Colors.white)) >= 4.5 && _contrast(cFgC, Color.alphaBlend(cFaceC, Colors.white)) >= 4.5;
            }
            _out('D535 $tok att chips pn=$nP cn=$nC pface=$pFace pfg=$pFg cface=$cFace cfg=$cFg cr45=$chipCr rows=$nGroupRows');
            await shot('1group', 'group');
            if (!_before) {
              chk('strict 합계 칩 각 1', nP == 1 && nC == 1, '개수 $nP/$nC');
              chk('strict 합계 칩 = O002 색(grey100 면 + textSecondary 글)',
                  pFace == _hex(AppColors.grey100) && pFg == _hex(AppColors.textSecondary) && cFace == _hex(AppColors.grey100) && cFg == _hex(AppColors.textSecondary),
                  'p $pFace/$pFg c $cFace/$cFg');
              chk('strict 합계 칩 글/면 대비 ≥4.5', chipCr, 'p $pFg/$pFace c $cFg/$cFace');
            }
          } else {
            // ② 일괄 띠 — '일괄선택' 켜기 → 전체 선택(화면 상태만 · 쓰기 0) → 하단 띠의 거절 · 확정.
            final togF = find.text('일괄선택');
            final nTog = togF.evaluate().length;
            need('일괄선택 1', nTog == 1, '개수 $nTog');
            dense();
            stats();
            // 좁은 창에서는 전체 선택 줄이 스크롤 안이다 — 화면에 넣고 누른다(스크롤 밖이면 아무 일도 없다).
            await t.ensureVisible(togF);
            for (var m = 0; m < 4; m++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            await t.tap(find.ancestor(of: togF, matching: find.byType(InkWell)).first);
            for (var m = 0; m < 8; m++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final cbF = find.descendant(of: dlg, matching: find.byType(AppCheckbox), skipOffstage: true);
            final nCb = cbF.evaluate().length;
            need('일괄 모드 체크 ≥1', nCb >= 1, '개수 $nCb');
            await t.ensureVisible(cbF.first);
            for (var m = 0; m < 4; m++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            await t.tap(cbF.first);
            for (var m = 0; m < 8; m++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final barF = find.descendant(of: find.byType(AppModalFooter), matching: find.byType(InkWell), skipOffstage: true);
            final nBar = barF.evaluate().length;
            need('일괄 띠 버튼 2', nBar == 2, '개수 $nBar');
            var faces = 0;
            var lowCr = 0;
            var small = 0;
            var miss = 0;
            var brands = 0;
            var rejectFace = false;
            final labels = <String>[];
            final rowsRaw = <String>[];
            final geo = <String>[];
            for (var i = 0; i < nBar; i++) {
              final p = _probe(t, barF.at(i), Colors.white);
              labels.add(p.label);
              if (_classFace(p.fill)) faces++;
              if (p.cr < 4.5) lowCr++;
              if (!p.big) small++;
              if (!p.hit) miss++;
              if (p.fill == AppColors.brand) brands++;
              if (p.label == '거절' && p.fill.a != 0) rejectFace = true;
              geo.add('${p.label}:${p.r.width.toStringAsFixed(1)},${p.r.height.toStringAsFixed(1)},${_hex(p.fill)},${_hex(p.fg)},${p.cr.toStringAsFixed(2)}');
              rowsRaw.add('$i ${p.label} r=${p.r} fill=${_hex(p.fill)} fg=${_hex(p.fg)} cr=${p.cr.toStringAsFixed(2)} hit=${p.hit}');
            }
            labels.sort();
            final setText = labels.join('|');
            raw = rowsRaw.join(' | ');
            _out('D535 $tok att bulk n=$nBar set=${_enc(setText)} face0=${faces == 0} brand1=${brands == 1} textrej=${!rejectFace} cr45=${lowCr == 0} '
                'min48=${small == 0} hit=${miss == 0}');
            _out('R535 $tok geo ${v.id} ${c.id} ${_enc(geo.join(';'))}');
            await shot('1bulk', 'bulk-selected');
            if (!_before) {
              chk('strict 일괄 띠 문구 집합 불변', setText == _bulkLabels.join('|'), 'set $setText');
              chk('strict 일괄 띠 분류색 면 0 · 거절은 면 없는 글자', faces == 0 && !rejectFace, raw);
              chk('strict 일괄 띠 brand 채움 정확히 1(확정)', brands == 1, raw);
              chk('strict 일괄 띠 글자/면 대비 ≥4.5', lowCr == 0, raw);
              chk('strict 일괄 띠 받는 자리 ≥48', small == 0, raw);
              chk('strict 일괄 띠 중심 hit(두 보기)', miss == 0, raw);
            }
          }
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ③ 성공 · 실패 공통 정리 — 창을 내리고 남은 timer · 지연 응답이 끝날 시간을 준다.
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

        // ④ 집계 — 읽기 · 채널 · HTTP 는 기록(수). 쓰기 동작은 누르지 않았다.
        final nApps = reads.calls['applications'] ?? 0;
        final nUnexp = wire.unexpected.length;
        final nCf = wire.cf.length;
        final nHttp = net.tries.length;
        final unText = wire.unexpected.join(' | ');
        _out('D535 $tok att wire apps=$nApps cf=$nCf unexpected=$nUnexp http=$nHttp');

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
        _out('R535 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D535 $tok att fw n=$nFw');
        _out('D535 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        final recOnly = c.id == 'GROUP';
        if (!_before && !recOnly) chk('strict 화면 전체 넘침 0(두 보기)', nOvf == 0, ovfRaw);
        if (!_before && !recOnly) chk('strict 미처리 framework 예외 0(GROUP 은 기록만)', nFw == 0, fwRaw);
        chk('캡처 수 = 선언', shots == c.shots, 'shots $shots want ${c.shots}');
        final bad = checks.where((x) => !x.$2).toList();
        if (bad.isNotEmpty) _halt ??= '$tok ${bad.first.$1}';
        for (final x in checks) {
          expect(x.$2, isTrue, reason: '$tok ${x.$1} ${x.$3}');
        }
      }, skip: !_optIn);
    }
  }
}
