// ignore_for_file: depend_on_referenced_packages
// [DU533 · 표시만] DU-O003 '업무별 지원자' 창 좁은 조건(320×640 · 2.0)의 통계 구역 — 항목(점 + 라벨 + 값)을 내용 폭으로 줄여 이미 있는 Wrap 이 가로로 흘리게 한다.
//   판정은 머리 밀도 셀의 narrow 그대로(새 판정 0). 글 · 색 · 크기 · 순서 · 표시 조건 불변. 넓은 창(390×844 · 1.0) · 묶음 창은 이전처럼 항목마다 한 줄.
//   before = 현재 A(work_applicants_dialog b2da8d1e · 색 잔여 셀 채택판) 기록 전용 · strict = 후보(6bd74f5a).
//   상태 = 씨앗 시험(199638a6)의 7상태(ROWS · BULK · EMPTY · FAIL · LOADING · BANDS · GROUP — 관측 · 단언 그대로) × W/B + 통계 구역 관측(att stats · 모든 상태 첫 화면).
//   att stats = 구역 수 · 글을 그려진 순서로 이은 것 · 글마다 한 줄 · 항목 안 줄바꿈 0 · 글이 구역 안 · 항목이 놓인 줄 수(runs) · 구역 높이(sh). 첫 카드 가시 높이는 att dense 의 card1.
//   GROUP 의 통계 값은 기록만(묶음 창은 narrow 가 아니다 — TB = TA 대조). BANDS · GROUP 의 넘침 · framework 오류 수도 씨앗과 같이 기록만.
//   하네스 = offer_workdetail_roster_test · noshow_contract_dialog_gate_test 의 WorkApplicantsReads.debugOverride(창을 Scaffold body 로 직접 세운다)
//   + 대기(PENDING) 3 · 확정 2 대역. 쓰기 동작(확정 · 거절 · 계약 · 요청하기)은 누르지 않는다 — 일괄선택 켜기 · 전체 선택 · 다시 시도(읽기) · '신분증 요청'(선택 모드 켜기)만.
//   기본 skip — TB before/du533-tb/DU_BEFORE_OBSERVE=533 · TA after/du533-ta/없음.
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
const _authFake = 'du533.fake.auth.';
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
    throw const SocketException('DU533 관측 — 외부 HTTP 차단');
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

/// 후보(6bd74f5a)에서 행 버튼이 그려지는 줄 범위 — 카드 버튼 호출부(:2900) ~ _buildActionButton 끝(:3139).
///   넘침 오류의 '오류를 낸 위젯' 위치(work_applicants_dialog.dart:줄)가 이 안이면 행 버튼 발 넘침으로 센다. before 는 기록만(줄이 3 어긋난다).
const _ownLo = 2900;
const _ownHi = 3139;
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

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
const _cases = <({String id, int shots})>[(id: 'ROWS', shots: 2), (id: 'BULK', shots: 1), (id: 'EMPTY', shots: 2), (id: 'FAIL', shots: 3), (id: 'LOADING', shots: 1), (id: 'BANDS', shots: 2), (id: 'GROUP', shots: 1)];

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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '533';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du533-tb' && _env['DU_BEFORE_OBSERVE'] == '533') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du533-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

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
    _out('R533 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });
  tearDown(() => WorkApplicantsReads.debugOverride = null);

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S903BS-${v.id}-${c.id} 업무별 지원자 좁은 창 통계 — 항목을 가로로 흘린다', (t) async {
        final tok = 'S903BS-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');

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
        _out('D533 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
            _out('D533 $tok att body stat=$nStat msg=$nMsg close=$nClose inscroll=$inScroll msgin=$msgIn msghit=$msgHit closein=$closeIn closehit=$closeHit '
                'bodyh=${bodyH.toStringAsFixed(1)}');
            _out('R533 $tok lay ${v.id} ${c.id} $lay');
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
            _out('D533 $tok att dense nsub=$dnSub nstat=$dnStat hin=$hin sscroll=$sscroll svis=$svis order=$order x48=$x48 xhit=$xhit '
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
            _out('D533 $tok att stats nbar=$gN set=$gSet oneline=$oneline intact=$intact inbar=$inbar runs=$runs sh=${sh.toStringAsFixed(1)}');
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
            _out('D533 $tok shot $id ovf=${seen.overflows.length}');
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
            // ⓪ 배치 — 통계 줄이 명단 스크롤 안인가 · 명단 스크롤 칸 가시 높이 · 창 기준 자리(W 는 TB = TA 여야 한다 — R533 lay 줄 대조).
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
            _out('R533 $tok lay ${v.id} ${c.id} ${(sr.top - dr.top).toStringAsFixed(1)},${(vp.top - dr.top).toStringAsFixed(1)},${vp.height.toStringAsFixed(1)},'
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
            _out('D533 $tok att head tshown=${ho.shown} tname=${ho.name} tfull=${ho.full} tell0=${ho.ell0} tbrk=${ho.brk} sshown=${so.shown} sname=${so.name} '
                'sfull=${so.full} sbrk=${so.brk}');
            _out('D533 $tok att inv shown=${io.shown} name=${io.name} full=${io.full} brk=${io.brk}');
            _out('R533 $tok txt ${v.id} ${c.id} ${ho.size.width.toStringAsFixed(1)},${ho.size.height.toStringAsFixed(1)},${so.size.width.toStringAsFixed(1)},'
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
            _out('D533 $tok att lay inlist=$inList vph=${vpH.toStringAsFixed(1)} first=$reachFirst last=$reachLast');
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
            _out('D533 $tok att btns n=$n set=${_enc(setText)} offs=$offs face0=${faces == 0} brand1=${maxBrand <= 1} cr45=${lowCr == 0} '
                'min48=${small == 0} hit=${miss == 0} own0=${nOwn == 0 && nUnk == 0}');
            _out('R533 $tok geo ${v.id} ${c.id} ${_enc(geo.join(';'))}');
            await shot('2end', 'rows-end');
            if (!_before) {
              chk('strict 행 버튼 문구 집합 불변', setText == _rowLabels.join('|'), 'set $setText');
              chk('strict 행 버튼 14개를 모두 화면에 넣어 잼(두 보기)', offs == 0 && n == 14, 'offs $offs n $n');
              chk('strict 행 버튼 분류색 면 0', faces == 0, raw);
              chk('strict brand 채움 버튼 행당 ≤1', maxBrand <= 1, 'max $maxBrand');
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
            _out('D533 $tok att retry n=$nRetry rin=$retryIn rhit=$retryHit calls=$callsAfter rows=$rowsAfter stat=$statAfter');
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
            // ⑥ 띠 2종 — 신분증 요청(요청 가능 2명) · 계약서 미작성(확정 2명 모두 계약 없음 대역). 아이콘 · 글 · 버튼의 색과 대비를 잰 뒤
            //   '신분증 요청'을 한 번 눌러 선택 모드(화면 상태만 · 쓰기 0)의 '요청하기' · '취소' 색을 잰다. '요청하기' · '계약서 일괄작성'은 누르지 않는다.
            //   개수가 맞지 않으면 재지 않고 '-' 로 적는다(strict 는 개수 1 을 단언한다).
            stats();
            final idTxt = find.text('요청 가능 2명');
            final ctTxt = find.text('계약서 미작성 2명');
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
            var bandCr = false;
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
              final idUnder = Color.alphaBlend(idBandFace, Colors.white);
              final ctUnder = Color.alphaBlend(ctBandFace, Colors.white);
              bandCr = _contrast(idTextC, idUnder) >= 4.5 &&
                  _contrast(ctTextC, ctUnder) >= 4.5 &&
                  _contrast(idBtnFgC, Color.alphaBlend(idBtnFaceC, idUnder)) >= 4.5 &&
                  _contrast(ctBtnFgC, Color.alphaBlend(ctBtnFaceC, ctUnder)) >= 4.5;
            }
            final bandBrand = _brandFills(dlg);
            _out('D533 $tok att band idn=$nId ctn=$nCt idbtnn=$nIdBtn ctbtnn=$nCtBtn idicon=$idIcon idtext=$idText idbtn=$idBtnFace idbtnfg=$idBtnFg idface=$idFace '
                'cticon=$ctIcon cttext=$ctText ctbtn=$ctBtnFace ctbtnfg=$ctBtnFg cr45=$bandCr brandn=$bandBrand');
            await shot('1bands', 'bands');
            if (nIdBtn == 1) {
              await t.ensureVisible(idBtn);
              for (var m = 0; m < 4; m++) {
                await t.pump(const Duration(milliseconds: 50));
              }
              await t.tap(idBtn);
              for (var m = 0; m < 8; m++) {
                await t.pump(const Duration(milliseconds: 50));
              }
            }
            final reqF = find.text('요청하기');
            final selF = find.text('2명 선택됨');
            final nReq = reqF.evaluate().length;
            final nSel = selF.evaluate().length;
            var nTog = 0;
            var reqFace = '-';
            var reqFg = '-';
            var togFace = '-';
            var togFg = '-';
            var selFace = '-';
            var selCr = false;
            if (nReq == 1 && nSel == 1) {
              final selBand = find.ancestor(of: selF, matching: find.byType(Container)).first;
              final togF = find.descendant(of: selBand, matching: findVisibleText('취소'), skipOffstage: true);
              nTog = togF.evaluate().length;
              final reqFaceC = _faceOf(t, reqF);
              final reqFgC = _fgOf(t, reqF);
              final selFaceC = _faceOf(t, selF);
              reqFace = _hex(reqFaceC);
              reqFg = _hex(reqFgC);
              selFace = _hex(selFaceC);
              final selUnder = Color.alphaBlend(selFaceC, Colors.white);
              selCr = _contrast(reqFgC, Color.alphaBlend(reqFaceC, selUnder)) >= 4.5;
              if (nTog == 1) {
                final togFaceC = _faceOf(t, togF);
                final togFgC = _fgOf(t, togF);
                togFace = _hex(togFaceC);
                togFg = _hex(togFgC);
                selCr = selCr && _contrast(togFgC, Color.alphaBlend(togFaceC, selUnder)) >= 4.5;
              }
            }
            final selBrand = _brandFills(dlg);
            _out('D533 $tok att sel reqn=$nReq seln=$nSel togn=$nTog reqbtn=$reqFace reqfg=$reqFg togbtn=$togFace togfg=$togFg face=$selFace cr45=$selCr brandn=$selBrand');
            await shot('2select', 'idcard-select');
            if (!_before) {
              chk('strict 띠 글 · 버튼 각 1', nId == 1 && nCt == 1 && nIdBtn == 1 && nCtBtn == 1, '개수 $nId/$nCt/$nIdBtn/$nCtBtn');
              chk('strict 신분증 띠 = O002 색(아이콘 grey600 · 글 textPrimary · 신분증 요청 = 면 없음 + brand 글)',
                  idIcon == _hex(AppColors.grey600) && idText == _hex(AppColors.textPrimary) && idBtnFace == _hex(Colors.transparent) && idBtnFg == _hex(AppColors.brand),
                  'icon $idIcon text $idText btn $idBtnFace/$idBtnFg');
              chk('strict 계약 미작성 띠 = O002 색(아이콘 grey600 · 글 textPrimary · 계약서 일괄작성 = brand 채움 + 흰 글)',
                  ctIcon == _hex(AppColors.grey600) && ctText == _hex(AppColors.textPrimary) && ctBtnFace == _hex(AppColors.brand) && ctBtnFg == _hex(Colors.white),
                  'icon $ctIcon text $ctText btn $ctBtnFace/$ctBtnFg');
              chk('strict 띠 글/면 · 버튼 글/면 대비 ≥4.5', bandCr, 'id $idText/$idFace $idBtnFg/$idBtnFace ct $ctText $ctBtnFg/$ctBtnFace');
              chk('strict 선택 모드 — 요청하기 1 · 선택 글 1 · 취소 1', nReq == 1 && nSel == 1 && nTog == 1, '개수 $nReq/$nSel/$nTog');
              chk('strict 요청하기 = O002 색(brand 채움 + 흰 글) · 취소 = grey100 + grey700(불변)',
                  reqFace == _hex(AppColors.brand) && reqFg == _hex(Colors.white) && togFace == _hex(AppColors.grey100) && togFg == _hex(AppColors.grey700),
                  'req $reqFace/$reqFg tog $togFace/$togFg');
              chk('strict 선택 모드 버튼 글/면 대비 ≥4.5', selCr, 'req $reqFg/$reqFace tog $togFg/$togFace face $selFace');
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
            _out('D533 $tok att chips pn=$nP cn=$nC pface=$pFace pfg=$pFg cface=$cFace cfg=$cFg cr45=$chipCr rows=$nGroupRows');
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
            _out('D533 $tok att bulk n=$nBar set=${_enc(setText)} face0=${faces == 0} brand1=${brands == 1} textrej=${!rejectFace} cr45=${lowCr == 0} '
                'min48=${small == 0} hit=${miss == 0}');
            _out('R533 $tok geo ${v.id} ${c.id} ${_enc(geo.join(';'))}');
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
        _out('D533 $tok att wire apps=$nApps cf=$nCf unexpected=$nUnexp http=$nHttp');

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
        _out('R533 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D533 $tok att fw n=$nFw');
        _out('D533 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        final recOnly = c.id == 'BANDS' || c.id == 'GROUP';
        if (!_before && !recOnly) chk('strict 화면 전체 넘침 0(두 보기)', nOvf == 0, ovfRaw);
        if (!_before && !recOnly) chk('strict 미처리 framework 예외 0(BANDS · GROUP 은 기록만)', nFw == 0, fwRaw);
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
