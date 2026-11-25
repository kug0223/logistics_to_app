// ignore_for_file: depend_on_referenced_packages
// [DU559 · PP-TYPOGRAPHY T3 첫 셀] 관리자 '업무별 지원자' 창(WorkApplicantsDialog · DU-O003)의 **지원자 반복 카드** 글자 역할 —
//   이름 = 카드 제목 17/1.3/700 textPrimary(TextLayout.identity · 읽는 이름 원문) · 부가 식별(인력번호 · 성별) · 지원 시각 · 전화 · 평점 · 자기소개 · 순번 = 보조 14/1.45/400 textSecondary ·
//   확정 제한 이유 = 판단 16/1.5/400 textPrimary · 상태 배지(주N회 · 계약 · 노쇼 · 관계) = 14/1.3/700(색 그대로) · 행동 버튼 글 = 16/1.3/700(색 그대로) · KeepWordsText(낱말 사이 줄바꿈).
//   before = 현재 A(work_applicants_dialog 4a39de53 = DU535 후보) 기록 전용 · strict = 후보(T3 · 20ba812d).
//   하네스 = DU535(du1_o002_o003_check_sheet_535_test 7894ebcf · DONE 5/5)의 업무별 창 대역 · 읽기 경계 · 플랫폼 채널 관찰 · HTTP 차단 · 넘침 수집 그대로 +
//     DU558(d92408e3) 글자 역할 측정 도우미 그대로. 값 = DU535 ROWS 대역 + 같은 모델 칸의 값(이름 · 인력번호 · 성별 · 전화 · 평점 · 노쇼 수 · 자기소개 · 공고 상태 FULL).
//     실패/지연 주입 0 · 응답 모양 변경 0.
//   측정(읽기만): 역할별 실제 TextStyle 서명 · 전문 · 말줄임/줄 제한 · 낱말 안 끊김(KeepWordsText 칸 = 공용 du_word_break wb/wf · 이름 = DU535 _midBreaks — 강제 포함) ·
//     첫 카드 읽기 순서 · 명단 첫/끝 도달(끌기 — DU535 과 같다) · 바뀐 글 순차 도달(ensureVisible) · 행 버튼 문구 집합 · 면/대비/48/중심 hit/카드 발 넘침 · 넘침 · framework.
//   누르는 것 0 — 확정 · 거절 · 계약서 작성 · 확정취소 · 제안 · 별표 · 카드 탭을 누르지 않는다.
//   [DU364] find.byType(Text) 는 KeepWordsText 를 세지 않는다 — 이 시험은 `w is Text` 술어로 찾는다.
//   기본 skip — TB before/du559-tb/DU_BEFORE_OBSERVE=559 · TA after/du559-ta/없음.
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
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/widgets/admin/applicant_row_surface.dart';

import 'support/du1_vq_capture.dart';
import 'support/du_word_break.dart';
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

/// [DU559] 사례 — DU535 ROWS 대역(대기 3 · 확정 2 · 같은 읽기 경계 · 같은 응답 모양)에서 같은 모델 칸의 **값만** 바꾼다.
///   ROWS = DU535 그대로 · IDENT = 동명이인 2(인력번호 · 성별) + 전화 · 평점 · 자기소개 · 노쇼 사실 · LONG = 긴 이름(띄어쓰기 있음 — CP01/CP04 인계 값) + 부가 식별 ·
///   FULL = 공고 상태 FULL(TOModel 값 — 대기 카드에 확정 버튼 대신 확정 제한 이유).
const _cases = <({String id})>[(id: 'ROWS'), (id: 'IDENT'), (id: 'LONG'), (id: 'FULL')];
const _ids = <String>['p1', 'p2', 'p3', 'c1', 'c2'];
const _baseNames = <String, String>{'p1': '김별표', 'p2': '이선택', 'p3': '박대기', 'c1': '최확정', 'c2': '정미작성'};
const _kSameName = '김민준';
const _kLongName = '응우옌 티 프엉 타오 쩐';
const _kPhoneRaw = '01012345678';
const _kMessage = '주말 오전 근무도 가능합니다';
const _kApplied = '지원 3시간 전';
const _kFullHint = '정원이 충족된 공고입니다. 추가 확정이 제한됩니다.';

String _nameOf(String kind, String id) => switch ((kind, id)) {
      ('IDENT', 'p1' || 'p2') => _kSameName,
      ('LONG', 'p1') => _kLongName,
      _ => _baseNames[id]!,
    };

int? _noOf(String kind, String id) => switch ((kind, id)) {
      ('IDENT', 'p1') => 14,
      ('IDENT', 'p2') => 15,
      ('LONG', 'p1') => 1234,
      _ => null,
    };

String? _genderOf(String kind, String id) => switch ((kind, id)) {
      ('IDENT', 'p1' || 'p2') => '남성',
      ('LONG', 'p1') => '여성',
      _ => null,
    };

/// 부가 식별 원문 — 화면의 '(${PersonLabel.secondary(번호, 성별 + 나이)})' 와 같은 값(생년월일 없음 → 나이 없음).
String? _idOf(String kind, String id) => switch ((kind, id)) {
      ('IDENT', 'p1') => '(P-014 · 남성)',
      ('IDENT', 'p2') => '(P-015 · 남성)',
      ('LONG', 'p1') => '(P-1234 · 여성)',
      _ => null,
    };

TOModel _to(String kind) => TOModel(
    id: 'to1', businessId: _biz1, businessName: _bizName, type: 'flex', title: '단기 모집', creatorUID: 'admin1',
    status: kind == 'FULL' ? TOStatus.full : 'ACTIVE',
    workDetails: [_wd1(), _wd2()], totalRequired: 8, totalConfirmed: 2, totalPending: 3, isPublished: true, publishMode: 'immediate',
    createdAt: _made, statusUpdatedAt: _made);

TOItem _item(String kind) => TOItem(
    to: _to(kind),
    slot: SlotModel(id: 'slot1', toId: 'to1', date: _day, status: SlotStatus.open, workDetails: [_wd1(), _wd2()], createdAt: _made),
    workDetails: [_wd1(), _wd2()], confirmedCount: 2, pendingCount: 3, totalRequired: 8);

ApplicationModel _app(String kind, String id, String status) => ApplicationModel(
    id: id, uid: 'u_$id', toId: 'to1', slotId: 'slot1', businessId: _biz1, businessName: _bizName, toTitle: '단기 모집',
    selectedWorkType: '홀서빙', wdId: 'wd1', startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly', status: status,
    workDate: _day, appliedAt: _applied, isStarred: id == 'p1' && (kind == 'ROWS' || kind == 'FULL'),
    applicationMessage: kind == 'IDENT' && id == 'p1' ? _kMessage : null);

/// 대역 — 대기 3 · 확정 2(c1 계약 완료 · c2 계약 미작성). 사례마다 새로 만든다(공유 상태 0).
List<ApplicationModel> _apps(String kind) => [
      _app(kind, 'p1', AppStatus.pending), _app(kind, 'p2', AppStatus.pending), _app(kind, 'p3', AppStatus.pending),
      _app(kind, 'c1', AppStatus.confirmed), _app(kind, 'c2', AppStatus.confirmed),
    ];

UserModel _user(String kind, String uid) {
  final id = uid.replaceFirst('u_', '');
  return UserModel(
      uid: uid, username: uid, name: _nameOf(kind, id), email: '$uid@alfit.local', role: UserRole.USER,
      personNo: _noOf(kind, id), gender: _genderOf(kind, id),
      phone: kind == 'IDENT' && id == 'p1' ? _kPhoneRaw : null,
      averageRating: kind == 'IDENT' && id == 'p1' ? 4.5 : 0.0,
      recentNoShowCount: kind == 'IDENT' && id == 'p2' ? 2 : 0);
}

/// 창의 읽기 경계(주입) — DU535 `_Reads` 와 같은 9 함수 · 같은 응답 모양. 실패/지연/빈 응답 분기 0(이 셀 사례는 모두 성공). 쓰기는 여기 없다.
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
          return {for (final u in uids) u: _user(kind, u)};
        },
        weeklyAttendance: ({required businessId, required weekStart, required weekEnd}) async {
          _hit('weekly');
          return <String, List<AttendanceModel>>{};
        },
        contractStatusBatch: (ids, {required businessId}) async {
          _hit('contracts');
          return ContractStatusBatch(statuses: <String, String?>{for (final x in ids) if (x == 'c1') x: 'completed'});
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
const _authFake = 'du559.fake.auth.';
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
    throw const SocketException('DU559 관측 — 외부 HTTP 차단');
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

/// 버튼 면이 '분류색 면'인가 — 면 없음(투명) · brand 채움 · 비활성 회색(grey100)이 아니면 분류색 면이다.
bool _classFace(Color fill) => fill.a != 0 && fill != AppColors.brand && fill != AppColors.grey100;

/// [DU559] 카드(_buildApplicantCard ~ 카드 전용 도우미 · 배지 끝) 줄 범위 — 넘침 위치가 이 안이면 '카드 발 넘침'(DU535 의 행 버튼 범위를 카드 전체로 넓혔다).
///   base 4a39de53 :2552–3344 · 후보 20ba812d :2554–3345 — 모드별(before 도 바른 범위로 센다).
final int _ownLo = _before ? 2552 : 2554;
final int _ownHi = _before ? 3344 : 3345;
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

/// [DU559 수리 r1 · 판정159 §4-1·2] 이름 전문 — 마지막 글자(WORD JOINER · 공백 · 개행 · ZWSP 제외)의 selection box 를 높이 방식 둘로 받는다(읽기만).
///   ok(판정) = tight · max 상자 둘 다 있음 · 가로 tight right ≤ 문단 폭 + 0.5(종전 그대로) · 세로 = 그 글자가 놓인 실제 줄의 max 상자 bottom ≤ 문단 높이 + 0.5.
///   old(raw 전용) = 종전 식(tight bottom · tight right). tight 세로는 run 글꼴 높이라 줄 높이(height)가 글꼴 고유 높이보다 작으면 줄 상자 밖으로 나올 수 있다.
///   이것은 줄 배치 검사다 — 실제 잉크 · 조상 clip 을 증명하지 않는다(캡처의 이름 끝 직접 대조는 따로).
typedef _LastGlyph = ({bool ok, bool old, int at, int len, int unit, List<TextBox> tight, List<TextBox> mx});

_LastGlyph _lastGlyph(RenderParagraph rp, Size size) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  for (var i = s.length - 1; i >= 0; i--) {
    final ch = s[i];
    if (ch == _wj || _gap(ch)) continue;
    final sel = TextSelection(baseOffset: i, extentOffset: i + 1);
    final tight = rp.getBoxesForSelection(sel);
    final mx = rp.getBoxesForSelection(sel, boxHeightStyle: ui.BoxHeightStyle.max);
    final right = tight.isNotEmpty && tight.first.right <= size.width + 0.5;
    final old = right && tight.first.bottom <= size.height + 0.5;
    final ok = right && mx.isNotEmpty && mx.first.bottom <= size.height + 0.5;
    return (ok: ok, old: old, at: i, len: s.length, unit: s.codeUnitAt(i), tight: tight, mx: mx);
  }
  return (ok: false, old: false, at: -1, len: s.length, unit: -1, tight: const <TextBox>[], mx: const <TextBox>[]);
}

/// [DU559 수리 r1] 상자 목록 raw — 반올림 없는 좌표(Dart double 기본 표기) · 방향.
String _boxesRaw(List<TextBox> bs) => '${bs.length}:[${bs.map((b) => '${b.left},${b.top},${b.right},${b.bottom},${b.direction.name}').join(';')}]';

/// 요소 하나가 끌기 없이 보이고 눌리는가 — 창 상자 ∩ 화면(∩ 가까운 Scrollable 이 있으면 그 칸) 안 + 중심 hit(DU537 · DU538 r2 · DU540 · DU543 r3 · DU548 · DU551 · DU552 · DU555 `_tapNow` 와 같은 식).
({bool vis, bool hit, bool min48, Rect r}) _tapNow(WidgetTester t, Finder f, Finder dlg, Rect screen) {
  final boxF = find.descendant(of: dlg, matching: find.byType(Dialog), skipOffstage: true);
  var area = boxF.evaluate().isEmpty ? screen : t.getRect(boxF.first).intersect(screen);
  final scF = find.ancestor(of: f, matching: find.byType(Scrollable));
  final nSc = scF.evaluate().length;
  if (nSc > 0) area = area.intersect(t.getRect(scF.first));
  final r = t.getRect(f);
  final vis = _inside(r, area);
  final hit = t.hitTestOnBinding(r.center).path.any((x) => identical(x.target, t.renderObject(f)));
  final min48 = r.width >= 48 - 0.01 && r.height >= 48 - 0.01;
  return (vis: vis, hit: hit, min48: min48, r: r);
}

// ── 글자 역할 측정(읽기만 · DU558 도우미 그대로 — _textOf 만 Text.rich 이름을 찾도록 고쳤다) ──

/// 창 안 글(Text 위젯 — KeepWordsText 같은 하위 형 · Text.rich 포함) — 보이는 글(표시 제어 문자 제거 · Text.rich 는 span 읽는 이름 포함 평문)이 [s] 인 것. 화면 밖 포함.
///   find.text 는 EditableText 도 센다 — Text 위젯만 본다. (DU558 `_textOf` 에서 `w.data ?? w.textSpan?.toPlainText()` 로 바꿨다 — support/visible_text 의 findVisibleText 와 같은 식.)
Finder _textOf(Finder home, String s) => find.descendant(of: home, skipOffstage: false,
    matching: find.byWidgetPredicate((w) => w is Text && visibleText(w.data ?? w.textSpan?.toPlainText() ?? '') == s, skipOffstage: false));

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

/// 문단의 줄 수 — 전체 선택 상자의 윗변이 1px 넘게 달라지는 횟수.
int _linesOf(RenderParagraph rp) {
  final n = rp.text.toPlainText().length;
  if (n == 0) return 0;
  final tops = <double>[];
  for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: n))) {
    if (tops.every((x) => (x - b.top).abs() > 1)) tops.add(b.top);
  }
  return tops.length;
}

typedef _Fit = ({int ex, int cut, int wb, int full, int lines});

/// 문단 하나 — 줄 제한 넘음 · 줄 제한/말줄임 설정 · 피할 수 있는 낱말 안 끊김(공용 판정기) · 전문 불일치 · 줄 수.
_Fit _fitOf(RenderParagraph rp, String show) => (
      ex: rp.didExceedMaxLines ? 1 : 0,
      cut: rp.maxLines != null || rp.overflow == TextOverflow.ellipsis ? 1 : 0,
      wb: wordBreaks(rp).where((x) => !x.forced).length,
      full: visibleText(rp.text.toPlainText()) == show ? 0 : 1,
      lines: _linesOf(rp),
    );

Rect _rectOf(RenderParagraph rp) => MatrixUtils.transformRect(rp.getTransformTo(null), Offset.zero & rp.size);

/// [b] 가 [a] 다음 읽기 자리인가 — 같은 줄 오른쪽(세로로 겹치고 왼쪽 ≥ a 오른쪽) 또는 아래(위 ≥ a 아래).
bool _after(Rect a, Rect b) => (b.left >= a.right - 0.5 && b.top < a.bottom && b.bottom > a.top) || b.top >= a.bottom - 0.5;

/// 문단 하나의 **강제** 낱말 안 끊김 수(공용 판정기 forced — 낱말 하나가 문단 폭보다 길어 불가피한 분절). `_fitOf` 의 wb 는 forced 를 세지 않는다(판정149 :49).
int _wfOf(RenderParagraph rp) => wordBreaks(rp).where((x) => x.forced).length;

/// 상태별 기대 — 선언(cell lines)과 같은 값(mkcell 이 대조한다).
const _btnN = <String, int>{'ROWS': 14, 'IDENT': 14, 'LONG': 14, 'FULL': 11};
const _mainN = <String, int>{'ROWS': 4, 'IDENT': 4, 'LONG': 4, 'FULL': 1};

/// 행 버튼 문구 — 문구 불변 기준(정렬 순 · FULL 은 대기 카드 '확정' 없음).
List<String> _rowLabelsOf(String kind) => ['거절', '계약서 작성', '근무 변경 제안', '다른 업무 제안', if (kind != 'FULL') '확정', '확정취소'];

/// 칸별 글 원문 — nm 이름 · ix 순번 · id 부가 식별 · tm 지원 시각 · sp 전화/평점 · ms 자기소개 · bd 상태 배지 · hn 확정 제한 이유 · ct 행동 버튼 글(이 셀이 바꾼 글) ·
///   hd 구획 머리 · ib 신분증 배지(이 셀이 바꾸지 않은 글 — 기록).
Map<String, List<String>> _slotsOf(String kind) => {
      'nm': [for (final i in _ids) _nameOf(kind, i)],
      'ix': const ['1.', '2.', '3.'],
      'id': [for (final i in _ids) if (_idOf(kind, i) != null) _idOf(kind, i)!],
      'tm': const [_kApplied],
      'sp': [if (kind == 'IDENT') ...[FormatHelper.formatPhone(_kPhoneRaw), '4.5']],
      'ms': [if (kind == 'IDENT') _kMessage],
      'bd': ['주0회', '계약완료', '계약서 작성 필요', if (kind == 'IDENT') '최근 90일 노쇼 2회'],
      'hn': [if (kind == 'FULL') _kFullHint],
      'ct': _rowLabelsOf(kind),
      'hd': const ['지원 (3명)', '확정 (2명)'],
      'ib': const ['신분증미요청'],
    };

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '559';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du559-tb' && _env['DU_BEFORE_OBSERVE'] == '559') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du559-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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
    _out('R559 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });
  tearDown(() {
    WorkApplicantsReads.debugOverride = null;
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S959TO-${v.id}-${c.id} O003 지원자 카드 글자 역할 T3 — 이름 17 · 보조 14 · 판단 16 · 배지 14 · 행동 16 · 전문 · 음절 끊김 · 읽기 순서 · 순차/끝 도달 · 행동 48', (t) async {
        final tok = 'S959TO-${v.id}-${c.id}';
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
        final screen = Offset.zero & Size(v.w, v.h);
        final mode = _before ? 'before' : 'strict';
        _out('D559 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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

          Future<void> shot(String id, String state) async {
            _out('D559 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          await shot('1top', 'rows-top');

          // ① 역할 글 — 칸마다 글을 찾아 문단을 모은다(화면 밖 포함). 선언한 글은 모두 있어야 한다(두 모드 — 문구 불변).
          final slots = _slotsOf(c.id);
          final found = <String, List<(RenderParagraph, String)>>{};
          for (final e in slots.entries) {
            final ps = <(RenderParagraph, String)>[];
            for (final q in e.value.toSet()) {
              final got = _parasOf(_textOf(dlg, q));
              need('역할 글 있음 ${e.key}', got.isNotEmpty, q);
              for (final p in got) {
                ps.add((p, q));
              }
            }
            found[e.key] = ps;
          }
          List<(RenderParagraph, String)> at(String k) => found[k] ?? const [];
          _out('D559 $tok att role nm=${_sigsOf(at('nm'))} ix=${_sigsOf(at('ix'))} id=${_sigsOf(at('id'))} tm=${_sigsOf(at('tm'))} sp=${_sigsOf(at('sp'))} ms=${_sigsOf(at('ms'))} bd=${_sigsOf(at('bd'))} hn=${_sigsOf(at('hn'))} ct=${_sigsOf(at('ct'))}');
          _out('D559 $tok att ru hd=${_sigsOf(at('hd'))} ib=${_sigsOf(at('ib'))}');

          // ② 전문 · 말줄임/줄 제한 · 낱말 안 끊김 — KeepWordsText/Text 칸(공용 du_word_break · 피할 수 있는 wb · 강제 wf) / 이름(Text.rich 읽는 이름 — DU535 _midBreaks · 강제 포함).
          //   자기소개(ms)는 한 줄 말줄임을 그대로 둔 글이라 fit 에서 뺀다(역할 서명 · 순차 도달만).
          final fa = [0, 0, 0, 0, 0, 0];
          final badF = <String>[];
          final slotF = <String>[];
          for (final k in const ['ix', 'id', 'tm', 'sp', 'bd', 'hn', 'ct']) {
            final ls = <int>[];
            for (final (p, show) in at(k)) {
              final f = _fitOf(p, show);
              final wf = _wfOf(p);
              fa[0]++;
              fa[1] += f.ex;
              fa[2] += f.cut;
              fa[3] += f.wb;
              fa[4] += wf;
              fa[5] += f.full;
              ls.add(f.lines);
              if (f.ex + f.cut + f.wb + wf + f.full > 0) {
                badF.add('$k ex${f.ex} cut${f.cut} wb${f.wb} wf$wf full${f.full} "${visibleText(p.text.toPlainText())}" ${wordBreaks(p).map((x) => x.toString()).join(';')}');
              }
            }
            slotF.add('$k:${at(k).length}:${ls.join('.')}');
          }
          final fitRaw = 'slots ${slotF.join(' ')} bad ${badF.join(' | ')}';
          _out('D559 $tok att fit n=${fa[0]} ex=${fa[1]} cut=${fa[2]} wb=${fa[3]} wf=${fa[4]} full=${fa[5]}');
          final fn = [0, 0, 0, 0, 0];
          final badN = <String>[];
          final nameRaw = <String>[];
          final nmRaw = <String>[];
          for (final (p, show) in at('nm')) {
            final ex = p.didExceedMaxLines ? 1 : 0;
            final cutN = p.maxLines != null || p.overflow == TextOverflow.ellipsis ? 1 : 0;
            final brk = _midBreaks(p);
            final shown = visibleText(p.text.toPlainText(includeSemanticsLabels: false)) == show;
            final lg = _lastGlyph(p, p.size);
            final full = shown && lg.ok ? 0 : 1;
            fn[0]++;
            fn[1] += ex;
            fn[2] += cutN;
            fn[3] += brk;
            fn[4] += full;
            nameRaw.add('$show:${p.size.width.toStringAsFixed(1)}x${p.size.height.toStringAsFixed(1)}');
            // [DU559 수리 r1 · 판정159 §4-2] 이름별 raw(읽기만 · 판정에 쓰지 않음) — shown · 마지막 글자 UTF-16 offset/길이/코드 · 문단 크기 무반올림 · textScaler ·
            //   첫 조각 실제 크기/줄 높이 · tight/max 상자 전체 좌표 · 선택 기준 · 종전(old)/새(new) 판정.
            final nsp = _spansOf(p);
            nmRaw.add('$show shown=$shown at=${lg.at}/${lg.len} u=${lg.unit.toRadixString(16)} size=${p.size.width},${p.size.height} ts=${p.textScaler} '
                'st=${nsp.isEmpty ? '-' : '${nsp.first.$2.fontSize},${nsp.first.$2.height}'} tight=${_boxesRaw(lg.tight)} max=${_boxesRaw(lg.mx)} '
                'crit=max.bottom<=h+0.5&tight.right<=w+0.5 old=${lg.old} new=${lg.ok} full=$full');
            if (ex + cutN + brk + full > 0) badN.add('$show ex$ex cut$cutN brk$brk full$full');
          }
          _out('D559 $tok att fitn n=${fn[0]} ex=${fn[1]} cut=${fn[2]} brk=${fn[3]} full=${fn[4]}');
          _out('R559 $tok nmraw n=${nmRaw.length} nm64=${_enc(nmRaw.join(' | '))}');
          raw = '$raw fit $fitRaw fitn ${nameRaw.join(' ')} bad ${badN.join(' | ')}';
          if (!_before) {
            chk('strict 바뀐 카드 글 전문 · 줄 제한/말줄임 0 · 낱말 안 끊김 0(피할 수 있는 것 · 강제 모두)',
                fa[1] == 0 && fa[2] == 0 && fa[3] == 0 && fa[4] == 0 && fa[5] == 0, fitRaw);
            chk('strict 이름 전문 · 줄 제한/말줄임 0 · 낱말 안 끊김 0(강제 포함)', fn[1] == 0 && fn[2] == 0 && fn[3] == 0 && fn[4] == 0, badN.join(' | '));
          }

          // ③ 첫 카드 읽기 순서 — 이름 → (부가 식별: 같은 줄 오른쪽 또는 아래) → 지원 시각 → 첫 행동 버튼 글.
          final rowF = find.byType(ApplicantRowSurface);
          final nRow = rowF.evaluate().length;
          need('명단 행 5', nRow == 5, '개수 $nRow');
          Rect? rectIn(Finder card, bool Function(String s) want) {
            Rect? best;
            for (final e in find.descendant(of: card, matching: find.byWidgetPredicate((w) => w is Text), skipOffstage: false).evaluate()) {
              final w = e.widget as Text;
              if (!want(visibleText(w.data ?? w.textSpan?.toPlainText() ?? ''))) continue;
              final ps = _parasOf(find.byElementPredicate((x) => identical(x, e)));
              if (ps.isEmpty) continue;
              final r = _rectOf(ps.first);
              if (best == null || r.top < best.top) best = r;
            }
            return best;
          }

          final card0 = rowF.first;
          final nmSet = slots['nm']!.toSet();
          final ctSet = slots['ct']!.toSet();
          final rN = rectIn(card0, nmSet.contains);
          final rI = rectIn(card0, (s) => s.startsWith('(P-'));
          final rT = rectIn(card0, (s) => s == _kApplied);
          final rB = rectIn(card0, ctSet.contains);
          var ord = false;
          if (rN != null && rT != null && rB != null) {
            ord = (rI == null ? _after(rN, rT) : _after(rN, rI) && _after(rI, rT)) && _after(rT, rB);
          }
          String fr(Rect? r) => r == null ? '-' : '${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)}-${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)}';
          _out('D559 $tok att order ord=$ord');
          raw = '$raw order nm ${fr(rN)} id ${fr(rI)} tm ${fr(rT)} ct ${fr(rB)}';
          if (!_before) chk('strict 첫 카드 읽기 순서(이름 → 부가 식별 → 지원 시각 → 행동)', ord, 'nm ${fr(rN)} id ${fr(rI)} tm ${fr(rT)} ct ${fr(rB)}');

          // ④ 명단 끝 도달 — DU535 와 같은 끌기(마지막 행 → 맨 위 → 첫 행 · 끌기 뒤 개수 가드).
          final listF = find.ancestor(of: rowF.first, matching: find.byType(Scrollable));
          final nList = listF.evaluate().length;
          need('명단 스크롤 칸 ≥1', nList >= 1, '개수 $nList');
          final vp = t.getRect(listF.first);
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
              final fr0 = t.getRect(rowF.first);
              reachFirst = fr0.top >= vp.top - 0.5 && fr0.top < vp.bottom;
            }
          }
          _out('D559 $tok att lay rows=$nRow first=$reachFirst last=$reachLast');
          raw = '$raw lay vp ${fr(vp)}';
          if (!_before) chk('strict 스크롤로 첫 행 · 마지막 행 도달', reachFirst && reachLast, 'first $reachFirst last $reachLast vp $vp');

          // ⑤ 순차 도달 — 바뀐 글(이름 · 부가 식별 · 지원 시각 · 전화/평점 · 자기소개 · 배지 · 확정 제한 이유)의 서로 다른 원문마다 첫 글을 ensureVisible 해서
          //   창 ∩ 화면 ∩ 명단 칸 안에 들어오는가(DU558 seq 와 같은 식 · 대상마다 한 번 · 4 × 50ms). 행동 버튼은 ⑥ 에서 하나씩 잰다.
          final seqQ = <String>{
            for (final k in const ['nm', 'id', 'tm', 'sp', 'ms', 'bd', 'hn']) ...(slots[k] ?? const <String>[]),
          }.toList();
          var sVis = 0;
          final seqRaw = <String>[];
          for (final q in seqQ) {
            final f = _textOf(dlg, q).first;
            await t.ensureVisible(f);
            for (var k = 0; k < 4; k++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final p = _tapNow(t, f, dlg, screen);
            if (p.vis) sVis++;
            seqRaw.add(p.vis.toString());
          }
          final sAll = sVis == seqQ.length;
          _out('D559 $tok att seq n=${seqQ.length} all=$sAll');
          raw = '$raw seq ${seqRaw.join(',')}';
          if (!_before) chk('strict 바뀐 카드 글 순차 도달(전부 창 · 화면 · 명단 칸 안)', sAll, seqRaw.join(','));

          // ⑥ 행 버튼 — DU535 와 같은 식(카드 안 InkWell › Container · 하나씩 ensureVisible · 칸 안만 잰다). 글 찾기만 `w is Text`.
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
            labels.add(t.widget<Text>(find.descendant(of: one, matching: find.byWidgetPredicate((w) => w is Text), skipOffstage: true).first).data ?? '');
            await t.ensureVisible(one);
            for (var m = 0; m < 4; m++) {
              await t.pump(const Duration(milliseconds: 50));
            }
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
          raw = '$raw btns ${rowsRaw.join(' | ')}';
          _out('D559 $tok att btns n=$n set=${_enc(setText)} main=$mainBrand offs=$offs face0=${faces == 0} brand1=${maxBrand <= 1} cr45=${lowCr == 0} min48=${small == 0} hit=${miss == 0} own0=${nOwn == 0 && nUnk == 0}');
          _out('R559 $tok geo ${v.id} ${c.id} ${_enc(geo.join(';'))}');
          await shot('2end', 'rows-end');
          chk('행 버튼 문구 집합 불변 · 개수 = 선언(두 모드)', setText == _rowLabelsOf(c.id).join('|') && n == _btnN[c.id], 'set $setText n $n');
          chk('확정 · 계약서 작성 = brand 채움 유지(두 모드)', mainN == _mainN[c.id] && mainBrand == _mainN[c.id], 'n $mainN brand $mainBrand');
          if (!_before) {
            chk('strict 행 버튼을 모두 칸 안에 넣어 잼', offs == 0, 'offs $offs');
            chk('strict 행 버튼 분류색 면 0 · brand 채움 행당 ≤1', faces == 0 && maxBrand <= 1, 'faces $faces max $maxBrand');
            chk('strict 행 버튼 글자/면 대비 ≥4.5 · 받는 자리 ≥48 · 중심 hit', lowCr == 0 && small == 0 && miss == 0, rowsRaw.join(' | '));
            chk('strict 카드 줄(:$_ownLo–$_ownHi) 발 넘침 0 · 위치 모르는 넘침 0', nOwn == 0 && nUnk == 0, 'own $nOwn unk $nUnk');
          }
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ⑦ 성공 · 실패 공통 정리 — 창을 내리고 남은 timer · 지연 응답이 끝날 시간을 준다(DU535 와 같다).
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

        // ⑧ 집계 — 지원서 읽기 수 · CF · 예상 밖 채널 · HTTP. 쓰기 동작은 누르지 않았다.
        final nApps = reads.calls['applications'] ?? 0;
        final nUnexp = wire.unexpected.length;
        final nCf = wire.cf.length;
        final nHttp = net.tries.length;
        final unText = wire.unexpected.join(' | ');
        _out('D559 $tok att wire apps=$nApps cf=$nCf unexpected=$nUnexp http=$nHttp');

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
        _out('R559 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D559 $tok att fw n=$nFw');
        _out('D559 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        chk('지원서 읽기 1 · CF 0 · 예상 밖 채널 0 · HTTP 0(두 모드)', nApps == 1 && nCf == 0 && nUnexp == 0 && nHttp == 0, 'apps $nApps cf $nCf 예상 밖 [$unText] http $nHttp');
        if (!_before) chk('strict 화면 전체 넘침 0(W · B · N)', nOvf == 0, ovfRaw);
        if (!_before) chk('strict 미처리 framework 예외 0', nFw == 0, fwRaw);
        chk('캡처 수 = 선언', shots == 2, 'shots $shots want 2');
        final bad = checks.where((x) => !x.$2).toList();
        if (bad.isNotEmpty) _halt ??= '$tok ${bad.first.$1}';
        for (final x in checks) {
          expect(x.$2, isTrue, reason: '$tok ${x.$1} ${x.$3}');
        }
      }, skip: !_optIn);
    }
  }
}

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0), (id: 'N', w: 320.0, h: 640.0, s: 1.0)];
