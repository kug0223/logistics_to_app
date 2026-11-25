// ignore_for_file: depend_on_referenced_packages
// [DU577b · BL-04 재준비 · 색 · 표시만] 급여 금액 brand — 판정170 §5(실제 소비 3 파일) · audits/retro170-20261121/backlog_findings.md:5–11.
//   바뀐 것: ① 일자리 탭 compact 공고 카드 금액(textPrimary → brand) ② 공고 상세 '업무 자세히 보기' 시트 급여 값(successDark → brand)
//     ③ 지원 창 업무 카드 일급 · 시급 금액 글과 급여 아이콘(warningDark · successDark → brand · 그 밖 유형 = 보조색 그대로) · 정산 방식 배지(급여 색 getter → 중립 grey100 면 · textSecondary 글).
//   before = 지금 A(user_to_card 9dd0e162 · job_posting_screen 2a7433b0 = DU582b 후보 · work_selection_card 760e3eec) 기록 · strict = 후보 —
//     글자색 brand(그 밖 유형 = textSecondary 정확) · 대비 ≥ 4.5 · 전문 · 보임 · 배지 중립 짝 · 넘침 0. 낱말 안 끊김은 기록(색 셀 · 배치 불변 — README 손 대조).
//   하네스 = DU571 r2 시험(fad52117 · 정규 1회 DONE 5/5 · 공고 상세 JobPostingReads 대역 · max 판 _fullShown · _seeText) 블록 그대로 +
//     DU581 r3 시험(3f4a404a · DONE 5/5)의 _bringBuilt(String?) · _tapBtn + DU575 시험(5cd431b1 · DONE 5/5)의 색 도우미 · A8 _fills +
//     DU465 시험(A test/du1_s077_compact_wage_465_test.dart 77066ad2)의 compact 카드 대역. prep/mk_test.py 가 조립 · prep/verify_test.py 가 바이트 대조.
//   쓰기 0 · CF 0 · HTTP 0 · 누르는 것 = SHEET 사례의 '업무 자세히 보기' 1회(읽기 전용 시트 열기). 기본 skip — TB before/du577bbl04-tb/DU_BEFORE_OBSERVE=577 · TA after/du577bbl04-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/job_posting_reads.dart';
import 'package:ALfit/screens/common/job_posting_screen.dart';
import 'package:ALfit/services/tax_identity_service.dart';
import 'package:ALfit/services/work_type_guide_resolver.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/apply/work_selection_card.dart';
import 'package:ALfit/widgets/user/cards/user_to_card.dart';

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

/// CF Pigeon 채널 — RG 시험(offer_workdetail_roster · noshow_contract_dialog_gate)과 같은 'unavailable' 응답을 주고 센다.
const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// [DU526 과 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널.
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du577b.fake.auth.';
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
    throw const SocketException('UXW1 관측 — 외부 HTTP 차단');
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
    // [DU571 r2 · 판정167 시험 STOP 수리 · 판정159/161/162 방식] 세로는 줄 배치(max 상자) · 가로는 tight right(종전) · 공차 0.5 그대로.
    //   tight 세로는 run 글꼴 높이라 줄 높이 1.3 < 글꼴 원래 1.448em 이면 줄 상자 밖으로 나온다(DU559 nmraw: h+1.258). 잉크/clip 증명 아님.
    final sel = TextSelection(baseOffset: i, extentOffset: i + 1);
    final tight = rp.getBoxesForSelection(sel);
    final mx = rp.getBoxesForSelection(sel, boxHeightStyle: ui.BoxHeightStyle.max);
    return tight.isNotEmpty && mx.isNotEmpty && mx.first.bottom <= size.height + 0.5 && tight.first.right <= size.width + 0.5;
  }
  return false;
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

const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0), (id: 'N', w: 320.0, h: 640.0, s: 1.0)];

/// [DU577b] 서류를 다 갖춘 **시험용** 근로자(DU571 r2 `_P` 와 같은 꼴에서 이용 제한만 뺐다 · 실제 검증 아님).
class _Ready extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER, accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 2, 1), isIdVerified: true, idCardImagePath: 'users/u1/id.png', bankName: '국민은행',
        accountNumber: '1234', accountHolder: '김근로', bankbookImagePath: 'users/u1/bb.png', createdAt: DateTime(2026, 1, 1),
      );
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

// ── 공고 상세 대역(DU571 r2 블록 그대로 · 업무 하나만 이 셀 값 — 시급 12,000 · 익일 17:00 지급) ──

const _kTo = 'to1';
const _kSlot = 'slot1';
final DateTime _kDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).add(const Duration(days: 3));

/// [DU577b] 시트 급여 값 '시급 12,000원  ·  익일'을 만드는 업무(정산 방식이 있어야 값에 '· 익일'이 붙는다).
const _wd = WorkDetailData(wdId: 'wdA', workType: '상하차', workTypeIcon: 'box', workTypeColor: '#000000', workTypeBackgroundColor: '#FFFFFF',
    wage: 12000, wageType: 'hourly', requiredCount: 3, startTime: '09:00', endTime: '13:00', payScheduleType: 'next_day', payScheduleTime: '17:00');

TOModel _to() => TOModel(
      id: _kTo, businessId: 'biz1', businessName: '강남 물류센터', type: 'flex', title: '단기 모집', creatorUID: 'admin1',
      status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0, workDetails: const [], totalRequired: 3, totalConfirmed: 0,
      totalPending: 0, isPublished: true, publishMode: 'immediate', createdAt: DateTime(2026, 9, 1), statusUpdatedAt: DateTime(2026, 9, 1),
    );

BusinessModel _business() => BusinessModel(
      id: 'biz1', name: '강남 물류센터', businessNumber: '000-00-00000', category: '음식점', subCategory: '한식',
      address: '서울특별시 강남구 테헤란로 1', ownerId: 'owner1', createdAt: DateTime(2026, 9, 1),
    );

SlotModel _slot() => SlotModel(id: _kSlot, toId: _kTo, date: _kDate, workDetails: const [_wd], status: SlotStatus.open, confirmedCount: 0,
    createdAt: DateTime(2025));

JobPostingReads _reads() => JobPostingReads(
      toOrFailure: (id) async => (to: _to(), failed: false),
      workDetails: (id) async => const <WorkDetailData>[],
      businessById: (id) async => _business(),
      slots: (id, {bool visibleOnly = true}) async => [_slot()],
      myApplications: (uid) async => const <ApplicationModel>[],
      workTypeCatalog: (id) async => WorkTypeCatalog.empty,
      applicationOnce: (id) async => null,
      taxStatus: () async => const TaxIdentityStatus.unknown(),
    );

// ── compact 카드 대역(DU465 시험 블록 그대로 — 단기 · 업무 2(12,000 · 13,000) → 카드 금액 '12,000원~') ──

DateTime _day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: offset));
}

const _works0 = WorkDetailData(wdId: 'wdA', workType: '분류', wage: 12000, requiredCount: 3, startTime: '09:00', endTime: '13:00');
const _works1 = WorkDetailData(wdId: 'wdB', workType: '상차', wage: 13000, requiredCount: 2, startTime: '14:00', endTime: '18:00');

TOModel _toOf({required String id, required String type, required List<WorkDetailData> works, int required = 0, int confirmed = 0}) => TOModel(
      id: id, businessId: 'biz1', businessName: '골든패스 테스트 사업장', businessCity: '평택시', type: type,
      title: '물류센터 공고 $id', creatorUID: 'admin1', status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0,
      workDetails: works, slotDateKeys: type == 'flex' ? [_key(_day(2)), _key(_day(3))] : const [], totalSlots: type == 'flex' ? 2 : 0,
      totalRequired: required, totalConfirmed: confirmed, totalPending: 0, isPublished: true, publishMode: 'immediate',
      rangeStart: _day(2), rangeEnd: _day(30), createdAt: _day(-3), statusUpdatedAt: _day(-3),
    );

String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

/// [DU577b] 지원 창 업무 카드 — 시급(당일 지급) · 일급(익일 지급) · 월급(월급 정산 · 이 셀의 '그 밖 유형' — 금액 색 보조색 그대로).
WorkDetailData _wsc(String id) => WorkDetailData(
      wdId: 'wd$id', workType: '상하차', workTypeIcon: 'box', workTypeColor: '#000000', workTypeBackgroundColor: '#FFFFFF',
      wage: id == 'DAY' ? 120000 : (id == 'MONTH' ? 2500000 : 12000),
      wageType: id == 'DAY' ? 'daily' : (id == 'MONTH' ? 'monthly' : 'hourly'),
      requiredCount: 4, startTime: '09:00', endTime: '18:00', breakMinutes: 60,
      payScheduleType: id == 'DAY' ? 'next_day' : (id == 'MONTH' ? 'monthly' : 'same_day'),
      payScheduleTime: id == 'MONTH' ? null : '18:00',
    );

/// 사례 — CARD = 일자리 탭 compact 공고 카드 · SHEET = 공고 상세 업무 시트 · HOUR · DAY · MONTH = 지원 창 업무 카드(시급 · 일급 · 월급).
///   amt = 재는 급여 글(손으로 적은 값 — mkcell 이 제품 표기 소스와 대조) · badge = 정산 방식 배지 글(없으면 '').
typedef _Case = ({String id, int shots, String amt, String badge});
const _cases = <_Case>[
  (id: 'CARD', shots: 1, amt: '12,000원~', badge: ''),
  (id: 'SHEET', shots: 1, amt: '시급 12,000원  ·  익일', badge: ''),
  (id: 'HOUR', shots: 1, amt: '12,000원/시급', badge: '당일'),
  (id: 'DAY', shots: 1, amt: '120,000원/일급', badge: '익일'),
  (id: 'MONTH', shots: 1, amt: '2,500,000원/월급', badge: '월급 정산'),
];

/// 시트를 여는 단추 글 · 시트 급여 라벨(바뀌지 않는다 — 보존 확인).
const _opener = '업무 자세히 보기';
const _sheetLab = '급여';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '577';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du577bbl04-tb' && _env['DU_BEFORE_OBSERVE'] == '577') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du577bbl04-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

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

/// [DU514 과 같다] 그린 글(표시 제어 문자 제외).
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

/// [DU581 r2 · 판정167 시험 STOP 수리] 지연 생성 목록(사용자 목록 · 상세 시트 ListView) 안의 글이 아직 안 만들어졌을 때만
///   그 host 의 세로 목록을 끌어 만든다(누르기 아님 · 찾는 식 = _seeText 와 같은 _plainOf · 단언 없음 — 개수 판정은 _seeText 뒤 need).
Future<void> _bringBuilt(WidgetTester t, Finder host, String? want) async {
  final tf = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == want), skipOffstage: false);
  if (tf.evaluate().isNotEmpty) return;
  final sc = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down), skipOffstage: false);
  await t.scrollUntilVisible(tf, 120, scrollable: sc.first, maxScrolls: 40);
  await t.pump(const Duration(milliseconds: 50));
}

/// [DU581] 그 글이 든 버튼 한 요소(_btnLine 과 같은 찾기)를 **버튼 ∩ 보이는 칸 중심**으로 실제로 누른다(DU514 ⑤⑦ 진입 탭과 같은 점 · ensureVisible 0).
Future<bool> _tapBtn(WidgetTester t, Finder host, bool Function(String s) match, Rect screen) async {
  final btn = find.byWidgetPredicate((w) => w is ButtonStyleButton, skipOffstage: false);
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => match(TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false))))
      .where((e) {
        final ef = find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
        return find.ancestor(of: ef, matching: btn).evaluate().isNotEmpty;
      })
      .toList();
  if (es.length != 1) return false;
  final el = es.first;
  final tf = find.byElementPredicate((x) => identical(x, el), skipOffstage: false);
  final bf = find.ancestor(of: tf, matching: btn).first;
  final r = t.getRect(bf).intersect(_area(bf, screen));
  if (r.width <= 0 || r.height <= 0) return false;
  await t.tapAt(r.center);
  return true;
}

/// [DU577b] 급여 사례 — DU571 r2 `_limitCase` 의 틀(guard · 보기 · begin · 캡처 · 정리 · 집계)을 블록 그대로 쓰고 앱 · 재는 것만 바꿨다.
///   재는 글마다 _bringBuilt(같은 host 의 지연 목록 대비 · 점검표 A4) → _seeText(그 RichText 하나를 ensureVisible · 같은 요소로 전문 · 끊김 · 줄 수 · 보임) →
///   _inkOf(같은 찾기 식 · 글자색 · 가장 가까운 칠한 상자 · 뒤 바탕 · 대비 — A1). SHEET 의 여는 단추는 _showBtn(그 단추 ensureVisible) → _tapBtn(같은 단추 ∩ 보이는 칸 중심).
Future<void> _wageCase(WidgetTester t, _V v, _Case c, String tok) async {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final wire = _DWire();
  final net = _DNoHttp(wire);
  final prevAll = messenger.allMessagesHandler;
  final prevHttp = HttpOverrides.current;
  final prevOnError = FlutterError.onError;
  messenger.allMessagesHandler = (channel, handler, message) => wire.route(messenger, channel, handler, message);
  HttpOverrides.global = net;
  addTearDown(() {
    messenger.allMessagesHandler = prevAll;
    HttpOverrides.global = prevHttp;
    FlutterError.onError = prevOnError;
  });
  t.view.physicalSize = Size(v.w, v.h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final mode = _before ? 'before' : 'strict';
  _out('D577 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
  final seen = _DSeen();
  void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
  final screen = Offset.zero & Size(v.w, v.h);

  Object? failure;
  StackTrace? failureSt;
  var shots = 0;
  var raw = '';
  try {
    FlutterError.onError = seen.add;
    final key = GlobalKey();
    final Widget home;
    if (c.id == 'CARD') {
      home = Scaffold(
        backgroundColor: AppColors.background,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: UserTOCard(to: _toOf(id: 'F', type: 'flex', works: const [_works0, _works1]), myApplications: const [], onApplySuccess: () {}, compact: true),
        ),
      );
    } else if (c.id == 'SHEET') {
      home = JobPostingScreen(to: _to(), workDetails: const [], slotDate: _kDate, reads: _reads());
    } else {
      home = Scaffold(
        backgroundColor: AppColors.background,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: WorkSelectionCard(workDetail: _wsc(c.id), status: WorkApplicationStatus.notApplied, onApply: () {}, slotDate: _kDate),
        ),
      );
    }
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _Ready()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.workerTheme,
          locale: const Locale('ko', 'KR'),
          supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
          home: home,
        ),
      ),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final Finder host;
    if (c.id == 'CARD') {
      host = find.byType(UserTOCard);
    } else if (c.id == 'SHEET') {
      host = find.byType(JobPostingScreen);
    } else {
      host = find.byType(WorkSelectionCard);
    }
    final nScr = host.evaluate().length;
    _out('D577 $tok att scr n=$nScr');
    need('화면 1', nScr == 1, '개수 $nScr');
    Future<void> shot(String id, String state) async {
      _out('D577 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    var scope = host;
    if (c.id == 'SHEET') {
      // ⓪ 업무 카드 '업무 자세히 보기' — 같은 host 목록에서 만들고(A4) · 그 단추 한 요소를 넣고 · 같은 단추를 누른다(A1 · 읽기 전용 시트 1회).
      await _bringBuilt(t, host, _opener);
      final nBtn = await _showBtn(t, host, (s) => s == _opener);
      final tapped = await _tapBtn(t, host, (s) => s == _opener, screen);
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      final sheet = find.byType(BottomSheet);
      final nSheet = sheet.evaluate().length;
      _out('D577 $tok att open btn=$nBtn tap=$tapped sheet=$nSheet');
      need('시트 1', nBtn == 1 && tapped && nSheet == 1, '단추 $nBtn 누름 $tapped 시트 $nSheet');
      scope = sheet;
    }

    // ① 급여 금액 글(세 표면 공통) — 그 글 하나를 넣고 같은 요소로 잰다 · 칠(글자 · 뒤 바탕 · 대비). brand = 글자색 brand · sec = 보조색(그 밖 유형 보존).
    await _bringBuilt(t, scope, c.amt);
    final o = await _seeText(t, scope, (s) => s == c.amt, screen);
    final k = _inkOf(scope, (s) => s == c.amt);
    _out('D577 $tok att amt n=${o.n} name=${o.name} full=${o.full} brk=${o.brk} lines=${o.lines} vis=${o.vis} '
        'fg=${k.fg} face=${k.face} cr=${k.cr} ok45=${k.ok45} brand=${k.fg == _hex(AppColors.brand)} sec=${k.fg == _hex(AppColors.textSecondary)}');
    need('급여 글 1', o.n == 1 && k.n == 1, '개수 ${o.n}/${k.n}');
    raw += 'amt $o $k ';

    if (c.id == 'SHEET') {
      // ② 시트 급여 라벨 '급여' — 보조색 그대로(이 셀이 바꾸지 않는다).
      await _bringBuilt(t, scope, _sheetLab);
      final lk = _inkOf(scope, (s) => s == _sheetLab);
      _out('D577 $tok att lab n=${lk.n} fg=${lk.fg} keep=${lk.fg == _hex(AppColors.textSecondary)}');
      need('급여 라벨 1', lk.n == 1, '개수 ${lk.n}');
      raw += 'lab $lk ';
    }

    if (c.badge.isNotEmpty) {
      // ③ 급여 아이콘(payments_outlined 글리프) — 금액과 같은 getter 색. ④ 정산 방식 배지 — 중립 = textSecondary 글 · grey100 면.
      final g = _glyphOf(host, Icons.payments_outlined);
      _out('D577 $tok att ico n=${g.n} fg=${g.fg} face=${g.face} cr=${g.cr} brand=${g.fg == _hex(AppColors.brand)} sec=${g.fg == _hex(AppColors.textSecondary)}');
      need('급여 아이콘 1', g.n == 1, '개수 ${g.n}');
      await _bringBuilt(t, host, c.badge);
      final b = await _seeText(t, host, (s) => s == c.badge, screen);
      final bk = _inkOf(host, (s) => s == c.badge);
      final neutral = bk.fg == _hex(AppColors.textSecondary) && bk.box == _argb(AppColors.grey100);
      _out('D577 $tok att badge n=${b.n} name=${b.name} full=${b.full} brk=${b.brk} lines=${b.lines} vis=${b.vis} '
          'fg=${bk.fg} box=${bk.box} face=${bk.face} cr=${bk.cr} ok45=${bk.ok45} neutral=$neutral');
      need('정산 방식 배지 1', b.n == 1 && bk.n == 1, '개수 ${b.n}/${bk.n}');
      raw += 'ico $g badge $b $bk ';
    }

    // ⑤ [점검표 A8] 화면에 그려진 단추 채움 전부(기록만 · 이 셀이 바꾸지 않는다).
    final fills = _fills(t);
    _out('D577 $tok att fills n=${fills.n} brand=${fills.brand} err=${fills.err} none=${fills.none} other=${fills.other} list=${fills.list}');
    raw += 'fills $fills ';
    if (c.id == 'CARD') {
      await shot('1list', 'compact-card-wage');
    } else if (c.id == 'SHEET') {
      await shot('1sheet', 'work-sheet-wage');
    } else {
      await shot('1work', 'work-card-wage');
    }
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // 성공 · 실패 공통 정리 — DU535 _dayCase ⑤ 와 같다.
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
  final nUnexp = wire.unexpected.length;
  final nCf = wire.cf.length;
  final nHttp = net.tries.length;
  final unText = wire.unexpected.join(' | ');
  _out('D577 $tok att wire cf=$nCf unexpected=$nUnexp http=$nHttp');
  messenger.allMessagesHandler = prevAll;
  HttpOverrides.global = prevHttp;
  final exc = t.takeException();
  if (exc != null && failure == null) {
    failure = exc;
    failureSt = StackTrace.current;
  }
  final nOvf = seen.overflows.length;
  final nFw = seen.other.length;
  _out('R577 $tok raw m64=${_enc(raw)} ovf64=${_enc(seen.overflows.join('\n----\n'))} fw64=${_enc(seen.other.join('\n----\n'))} '
      'un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D577 $tok att fw n=$nFw');
  _out('D577 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');
  final f0 = failure;
  if (f0 != null) {
    _halt ??= '$tok ${f0.toString().split('\n').first}';
    Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
  }
  expect(shots == c.shots, isTrue, reason: '$tok 캡처 수 = 선언 shots $shots want ${c.shots}');
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
    _out('R577 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S577BW-${v.id}-${c.id} 급여 금액 brand · 정산 방식 배지 중립(BL-04 실제 소비)', (t) async {
        final tok = 'S577BW-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _wageCase(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}

// 측정 도우미(DU571 r2 바이트 그대로 · DU575 와 같이 main 뒤에 둔다 — preflight 'renderObject 재사용' 줄 훑기 거짓 양성 회피).

typedef _SeeObs = ({int n, bool name, bool full, int brk, int lines, bool vis});

/// [DU571] 바뀐 글 하나 — 그린 글(표시 제어 문자 제외)이 [match] 에 맞는 RichText 가 정확히 하나일 때 **그 RichText 를** ensureVisible 로 넣고,
///   같은 요소로 읽는 이름(가장 가까운 Semantics 조상 label = 그 글 원문) · 전문 · 낱말 안 끊김(강제 포함) · 줄 수 · 화면 ∩ 스크롤 칸 안을 잰다
///   (DU570 의 같은 이름 도우미와 같은 잣대 · 찾는 조건만 함수 · await 뒤에는 Element 를 직접 읽지 않고 같은 finder 로 다시 잡는다).
Future<_SeeObs> _seeText(WidgetTester t, Finder host, bool Function(String s) match, Rect screen) async {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => match(TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false))))
      .toList();
  if (es.length != 1) return (n: es.length, name: false, full: false, brk: 0, lines: 0, vis: false);
  final el = es.first;
  final want = TextLayout.plain((el.widget as RichText).text.toPlainText(includeSemanticsLabels: false));
  final tf = find.byElementPredicate((x) => identical(x, el), skipOffstage: false);
  await t.ensureVisible(tf);
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final rp = t.renderObject<RenderParagraph>(tf);
  final sem = find.ancestor(of: tf, matching: find.byType(Semantics, skipOffstage: false)).evaluate();
  final label = sem.isEmpty ? null : (sem.first.widget as Semantics).properties.label;
  return (
    n: 1,
    name: label == want,
    full: _fullShown(rp, rp.size),
    brk: _midBreaks(rp),
    lines: _lineCount(rp),
    vis: _inside(t.getRect(tf), _area(tf, screen)),
  );
}

// [DU577b] 색 도우미 · A8 채움 — DU575 시험(:768–802 · :871–903) 바이트 그대로.

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a);
  final y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Color _bgOf(Element e) {
  final layers = <Color>[];
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is ColoredBox) {
      c = w.color;
    } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
      c = (w.decoration as BoxDecoration).color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color ?? Theme.of(a).canvasColor;
    }
    if (c == null || c.a == 0) return true;
    layers.add(c);
    return c.a < 1.0;
  });
  var out = layers.isEmpty ? Colors.white : layers.last;
  for (final c in layers.reversed.skip(1)) {
    out = Color.alphaBlend(c, out);
  }
  return out;
}

/// [DU575 · 점검표 A8] 화면에 그려진(onstage) ButtonStyleButton 전부의 채움 — 단추 자신의 Material 색(투명 · 없음 = none) · 글 = 첫 RichText(Icon 글리프 제외).
///   기록만(브랜드 밖 채움은 보고서 색 조화 표 '후보'). 카드 행 단추(_inviteActionButton = GestureDetector + Container)는 여기 들지 않는다 — README A8 표.
typedef _FillObs = ({int n, int brand, int err, int none, int other, String list});

_FillObs _fills(WidgetTester t) {
  final rows = <String>[];
  var b = 0, er = 0, no = 0, ot = 0;
  for (final e in find.byWidgetPredicate((w) => w is ButtonStyleButton).evaluate()) {
    final bf = find.byElementPredicate((x) => identical(x, e));
    final mats = find.descendant(of: bf, matching: find.byType(Material), skipOffstage: false).evaluate().toList();
    final Color? fc = mats.isEmpty ? null : (mats.first.widget as Material).color;
    final texts = find
        .descendant(of: bf, matching: find.byType(RichText), skipOffstage: false)
        .evaluate()
        .where((r) => find.ancestor(of: find.byElementPredicate((x) => identical(x, r), skipOffstage: false), matching: find.byType(Icon)).evaluate().isEmpty)
        .toList();
    final lab = texts.isEmpty ? '-' : TextLayout.plain((texts.first.widget as RichText).text.toPlainText(includeSemanticsLabels: false));
    if (fc == null || fc.a == 0) {
      no++;
      rows.add('$lab:none');
    } else {
      if (fc.toARGB32() == AppColors.brand.toARGB32()) {
        b++;
      } else if (fc.toARGB32() == AppColors.errorDark.toARGB32()) {
        er++;
      } else {
        ot++;
      }
      rows.add('$lab:${_hex(fc)}');
    }
  }
  return (n: rows.length, brand: b, err: er, none: no, other: ot, list: _enc(rows.join('|')));
}

/// [DU577b] 칠 — 그 글(RichText) 하나의 글자색 · 가장 가까운 칠한 상자(DecoratedBox 의 BoxDecoration 면 · ARGB 8자리) · 글 뒤 실제 바탕(_bgOf) · 대비.
///   '-' = 없음.
typedef _InkObs = ({int n, String fg, String box, String face, String cr, bool ok45});

String _argb(Color? c) => c == null ? '-' : c.toARGB32().toRadixString(16).padLeft(8, '0');

_InkObs _inkOfEl(Element el, int n) {
  final Color? fg = (el.widget as RichText).text.style?.color;
  BoxDecoration? dec;
  el.visitAncestorElements((a) {
    final w = a.widget;
    if (w is DecoratedBox && w.decoration is BoxDecoration) {
      dec = w.decoration as BoxDecoration;
      return false;
    }
    return true;
  });
  final d = dec;
  final face = _bgOf(el);
  final cr = fg == null ? 0.0 : _contrast(fg, face);
  return (
    n: n,
    fg: fg == null ? '-' : _hex(fg),
    box: _argb(d?.color),
    face: _hex(face),
    cr: cr.toStringAsFixed(2),
    ok45: cr >= 4.5,
  );
}

/// [DU577b] [host] 안에서 그린 글(표시 제어 문자 제외)이 [match] 에 맞는 RichText 가 정확히 하나일 때만 그 칠을 잰다(_seeText 와 같은 찾기 식).
_InkObs _inkOf(Finder host, bool Function(String s) match) {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => match(TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false))))
      .toList();
  if (es.length != 1) return (n: es.length, fg: '-', box: '-', face: '-', cr: '0.00', ok45: false);
  return _inkOfEl(es.first, 1);
}

/// [DU577b] 그 글이 든 단추 한 요소(_tapBtn 과 같은 찾기)를 스크롤 칸 **가운데**로 넣는다 — 점검표 A1(넣는 대상 = 누르는 대상). 반환 = 찾은 단추 수.
///   공고 상세는 고정 머리(SliverAppBar pinned: true)를 쓴다 — 기본 ensureVisible(정렬 0.0)은 단추를 칸 맨 위(고정 머리 밑)로 보내 누름이 머리에 맞을 수 있다.
Future<int> _showBtn(WidgetTester t, Finder host, bool Function(String s) match) async {
  final btn = find.byWidgetPredicate((w) => w is ButtonStyleButton, skipOffstage: false);
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => match(TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false))))
      .where((e) => find.ancestor(of: find.byElementPredicate((x) => identical(x, e), skipOffstage: false), matching: btn).evaluate().isNotEmpty)
      .toList();
  if (es.length != 1) return es.length;
  final el = es.first;
  final bf = find.ancestor(of: find.byElementPredicate((x) => identical(x, el), skipOffstage: false), matching: btn).first;
  await Scrollable.ensureVisible(t.element(bf), alignment: 0.5);
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  return 1;
}

/// [DU577b] [host] 안 [icon] 아이콘 하나의 칠 — Icon 위젯이 받은 색(DU575 `_paintOf` 의 아이콘 색 읽기와 같다) · 그 아이콘 뒤 실제 바탕(_bgOf) · 대비.
///   아이콘이 정확히 하나일 때만. 글리프 RichText 는 세지 않는다(preflight v26 Icon 글리프 함정 — 글 측정과 섞지 않는다 · 파일 맨 끝에 둔다).
_InkObs _glyphOf(Finder host, IconData icon) {
  final es = find.descendant(of: host, matching: find.byIcon(icon, skipOffstage: false), skipOffstage: false).evaluate().toList();
  if (es.length != 1) return (n: es.length, fg: '-', box: '-', face: '-', cr: '0.00', ok45: false);
  final el = es.first;
  final Color? fg = (el.widget as Icon).color;
  final face = _bgOf(el);
  final cr = fg == null ? 0.0 : _contrast(fg, face);
  return (n: 1, fg: fg == null ? '-' : _hex(fg), box: '-', face: _hex(face), cr: cr.toStringAsFixed(2), ok45: cr >= 4.5);
}
