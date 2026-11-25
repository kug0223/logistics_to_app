// [DU576 · 색만 · 결정 미이행 장부 BL-01] 판정139 §3 PP-STATUS-PAIR-20261120 을 근로자 일정 카드(ScheduleCard) · 일정 상세(ScheduleDetailDialog) 상태 배지에 이행.
//   카드: 계약 진행 중 brandSurface/brand · 거절 grey100/textSecondary · 결근 errorBg/errorDark · 정산 완료/송금 완료 successBg/successDark ·
//     정산 중 grey100/textSecondary · 근무 중 successBg/successDark. 상세: 계약 진행 중 brandSurface/brand. 문구 · 분기 · 아이콘 모양 · 크기 변경 0.
//   상세 '거절' error 짝은 바꾸지 않는다(판단 필요 · README §0) — 이 시험은 재지 않는다.
//   before = 지금 A(schedule_card d97c2899 = DU545 후보 · schedule_detail_dialog 23e9e625) 기록 · strict = 후보(prep/mk_cand.py) — 칩 면/글/아이콘 = 결정 짝 · 대비 ≥4.5 ·
//     글 전문 · 낱말 안 끊김 0 · 보임 · 넘침 0 · framework 예외 0 은 cell lines(lgate)가 판정한다.
//   하네스 = DU545 시험(du1_schedulecard_color_545_test · e91e9894 · 정규 1회 DONE 5/5)의 대역 그대로(채널 관찰 · HTTP 차단 · AuthService Fake ·
//     UserProvider 하위 클래스 · ScheduleCard 직접 pump · 일정 화면 바깥 여백) — 일정 상세는 실제 진입처럼 DialogHelper.showSheet(isScrollControlled ·
//     useRootNavigator)로 연다(du1_o024_schedule_detail_256_test 와 같은 열기 · 읽기 대역 = ScheduleDetailReads · 서버 호출 0).
//   측정 블록 = DU571 r2 시험(fad52117 · 정규 1회 DONE 5/5)의 max 판 _fullShown · _midBreaks · _area · _lineCount · _inside · _seeText 그대로(판정169a §5) ·
//     지연 목록 대비 = DU581 r3 시험(3f4a404a · DONE 5/5)의 _bringBuilt · _plainOf 그대로(점검표 A4) · 색 = DU309 시험의 _lum · _contrast · _hex · bgOf 그대로
//     (DU575 시험과 같이 bgOf 만 최상위 _bgOf 로 옮김) · 채움 기록 = DU575 시험의 _fills 그대로(점검표 A8).
//   누르는 것: 상세 사례의 시험 하네스 '열기' 단추 1회뿐(제품 단추 누르기 0). 쓰기 0 · HTTP 요청 0.
//   기본 skip — TB before/du576sp-tb/DU_BEFORE_OBSERVE=576 · TA after/du576sp-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui show BoxHeightStyle;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/services/auth_service.dart';
import 'package:ALfit/services/work_type_guide_resolver.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/utils/responsive_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/calendar/schedule_card.dart';
import 'package:ALfit/widgets/dialogs/schedule_detail_dialog.dart';
import 'package:ALfit/widgets/dialogs/schedule_detail_reads.dart';

import 'support/du1_vq_capture.dart';

/// 원래 경로로 보내는 Flutter 기반 채널과 이유(DU536 · DU540 · DU542 와 같은 표).
const _frameworkAllow = <String, String>{
  'flutter/assets': 'AssetBundle(아이콘 글꼴 · 이미지 매니페스트) 읽기',
  'flutter/platform': 'MaterialApp Title · SystemSound/Haptic(InkWell 탭 피드백)',
  'flutter/navigation': '루트 Navigator 경로 보고',
  'flutter/mousecursor': 'MouseRegion 커서 갱신(시험 포인터)',
  'flutter/restoration': 'RootRestorationScope 상태 복원 조회',
  'flutter/keyboard': 'HardwareKeyboard 상태 동기화',
  'flutter/accessibility': '의미 트리/알림 전달',
};

/// 모든 플랫폼 메시지 관찰 — 기반 채널은 원래 경로, 나머지(CF · Firestore · Auth · 그 밖)는 이름을 기록하고 응답 null.
class _Wire {
  final unexpected = <String>[];

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
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
    throw const SocketException('DU576 관측 — 외부 HTTP 차단');
  }
}

/// 인증 대역 — 카드는 인증을 읽지 않는다(UserProvider 생성자가 기본 AuthService 로 FirebaseAuth 를 만들지 않게 할 뿐).
class _NoAuth extends Fake implements AuthService {}

/// worker_display_truth_fix_test.dart:99 의 _P 와 같은 자리 — 서명 대기 계약 0(pendingContractForTo = null).
class _P extends UserProvider {
  _P() : super(authService: _NoAuth());
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

/// 시각 오류 수집 — 넘침은 원문 + 위치, 그 밖 framework 오류는 원문.
class _Seen {
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
      overflows.add('${m.split('\n').first} @ $loc');
    } else {
      other.add(m);
    }
  }
}

// ── 고정값 — DU545 시험(:154–220)의 _kst · _future · _past · _biz · _wt · _app · _att · _Fx 그대로.
//   [DU576] _app 의 선택 인자 5개(icon · iconColor · iconBg · workDays · workEndDate)는 이 셀 사례가 넘기지 않아 뺐다(unused_element_parameter 예방 · 값 동일).

DateTime _kst(int y, int mo, int d, [int h = 0, int mi = 0]) => DateTime.utc(y, mo, d, h, mi).subtract(const Duration(hours: 9));

final DateTime _future = _kst(2099, 1, 5);
final DateTime _past = _kst(2026, 10, 12);

const _biz = '골든패스 사업장';
const _wt = 'QA 분류';

ApplicationModel _app(
  String id, {
  required DateTime workDate,
  String status = AppStatus.confirmed,
}) =>
    ApplicationModel(
      id: id,
      toId: 'to_$id',
      uid: 'u1',
      businessId: 'biz1',
      businessName: _biz,
      toTitle: 'QA',
      status: status,
      selectedWorkType: _wt,
      startTime: '10:00',
      endTime: '11:00',
      wage: 12000,
      wageType: 'hourly',
      workDate: workDate,
      appliedAt: workDate.subtract(const Duration(days: 3)),
    );

AttendanceModel _att(
  String appId, {
  required DateTime workDate,
  String status = AttendanceModel.statusPresent,
  bool checkIn = false,
  bool checkOut = false,
  String wageStatus = 'pending',
  bool wage = false,
}) =>
    AttendanceModel(
      id: 'att-$appId',
      applicationId: appId,
      userId: 'u1',
      businessId: 'biz1',
      businessName: _biz,
      workDate: workDate,
      workType: _wt,
      checkInAt: checkIn ? workDate.add(const Duration(hours: 10)) : null,
      checkOutAt: checkOut ? workDate.add(const Duration(hours: 11)) : null,
      status: status,
      wageStatus: wageStatus,
      finalWage: wage ? 12000 : null,
      wageDetail: wage ? WageDetailModel(wageType: 'hourly', baseWage: 12000) : null,
      createdAt: workDate,
    );

typedef _Fx = ({ApplicationModel app, AttendanceModel? att});

// ── [DU576] 사례 — 판정139 §3 표의 바뀌는 상태만(필요 상태만). fg/bg = 결정 짝(후보 mk_cand 와 같은 토큰) · sheet = 일정 상세 시트에서 잰다.
typedef _Case = ({String id, int shots, String lab, bool sheet, Color fg, Color bg});
const _cases = <_Case>[
  (id: 'CONTRACT', shots: 1, lab: '계약 진행 중', sheet: false, fg: AppColors.brand, bg: AppColors.brandSurface),
  (id: 'REJECTED', shots: 1, lab: '거절', sheet: false, fg: AppColors.textSecondary, bg: AppColors.grey100),
  (id: 'ABSENT', shots: 1, lab: '결근', sheet: false, fg: AppColors.errorDark, bg: AppColors.errorBg),
  (id: 'PAID', shots: 1, lab: '정산 완료', sheet: false, fg: AppColors.successDark, bg: AppColors.successBg),
  (id: 'SENT', shots: 1, lab: '송금 완료', sheet: false, fg: AppColors.successDark, bg: AppColors.successBg),
  (id: 'SETTLING', shots: 1, lab: '정산 중', sheet: false, fg: AppColors.textSecondary, bg: AppColors.grey100),
  (id: 'WORKING', shots: 1, lab: '근무 중', sheet: false, fg: AppColors.successDark, bg: AppColors.successBg),
  (id: 'DCONTRACT', shots: 1, lab: '계약 진행 중', sheet: true, fg: AppColors.brand, bg: AppColors.brandSurface),
];

/// 상태 칩 갈래마다 한 장 — schedule_card.dart _getDisplayStatus · _getStatusInfo 의 분기 순서를 그대로 밟는 입력(DU545 _fixOf 의 같은 이름 사례와 같은 값).
///   DCONTRACT = 일정 상세 시트의 계약 진행 중(지원 상태만 본다 · 근무일 = KST 2026-11-23 월 → 날짜 배지 '11/23(월)').
_Fx _fixOf(String id) {
  switch (id) {
    case 'CONTRACT':
      return (app: _app('contract', workDate: _future, status: AppStatus.contractPending), att: null);
    case 'REJECTED':
      return (app: _app('rej', workDate: _future, status: AppStatus.rejected), att: null);
    case 'ABSENT': // 확정 + 결근
      return (app: _app('absent', workDate: _past), att: _att('absent', workDate: _past, status: AttendanceModel.statusAbsent));
    case 'PAID': // 급여 confirmed — 급여 명세서 아이콘 버튼 있음
      return (app: _app('paid', workDate: _past), att: _att('paid', workDate: _past, checkIn: true, checkOut: true, wageStatus: 'confirmed', wage: true));
    case 'SENT': // 급여 transferred
      return (app: _app('sent', workDate: _past), att: _att('sent', workDate: _past, checkIn: true, checkOut: true, wageStatus: 'transferred', wage: true));
    case 'SETTLING': // 퇴근 · 급여 pending
      return (app: _app('settle', workDate: _past), att: _att('settle', workDate: _past, checkIn: true, checkOut: true));
    case 'WORKING': // 출근만
      return (app: _app('work', workDate: _past), att: _att('work', workDate: _past, checkIn: true));
    default: // DCONTRACT
      return (app: _app('dcontract', workDate: _kst(2026, 11, 23), status: AppStatus.contractPending), att: null);
  }
}

/// [DU576] 일정 상세 읽기 대역 — schedule_detail_guidance_fallback_test 의 _business() 꼴(필수 칸만 · 전화 없음) · 공고 못 읽음(null → 정산 · 공제 줄 0) ·
///   업무 목록 = 빈 완료본(업무 안내 0). 서버 · 저장소 호출 0.
BusinessModel _business() => BusinessModel(
      id: 'biz1',
      name: _biz,
      ownerId: 'admin1',
      businessNumber: '000-00-00000',
      address: '경기도 평택시 진위면 마산8로 10',
      category: '물류',
      subCategory: '창고',
      isApproved: true,
      createdAt: DateTime(2025),
    );

ScheduleDetailReads _reads() => ScheduleDetailReads(
      businessById: (_) async => _business(),
      toByApplication: (_) async => null,
      workTypeCatalog: (_) async => const WorkTypeCatalog(businessId: 'biz1', byId: {}, nameCounts: {}, complete: true),
    );

/// 시험 하네스의 상세 여는 단추 글(제품 글 아님).
const _openLabel = '일정 상세 열기(시험)';

// ── 측정 블록(DU571 r2 바이트 그대로 · 출처 표시는 verify_test) ──

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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '576';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du576sp-tb' && _env['DU_BEFORE_OBSERVE'] == '576') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du576sp-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  setUpAll(() async {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final wire = _Wire();
    final net = _NoHttp();
    final prevAll = m.allMessagesHandler;
    final prevHttp = HttpOverrides.current;
    m.allMessagesHandler = (channel, handler, message) => wire.route(m, channel, handler, message);
    HttpOverrides.global = net;
    try {
      await initializeDateFormatting('ko_KR');
      await _loadFonts();
    } finally {
      m.allMessagesHandler = prevAll;
      HttpOverrides.global = prevHttp;
    }
    final nUnexp = wire.unexpected.length;
    final nHttp = net.tries.length;
    _out('R576 setup init unexpected=$nUnexp http=$nHttp un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S576SP-${v.id}-${c.id} 일정 상태 배지 색 짝(판정139 §3)', (t) async {
        final tok = 'S576SP-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');

        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final wire = _Wire();
        final net = _NoHttp();
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
        final screen = Offset.zero & Size(v.w, v.h);
        final mode = _before ? 'before' : 'strict';
        _out('D576 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final fx = _fixOf(c.id);
        Object? failure;
        StackTrace? failureSt;
        var nShot = 0;
        var raw = '';
        try {
          FlutterError.onError = seen.add;
          final key = GlobalKey();
          Future<void> shot(String id, String state) async {
            _out('D576 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            nShot++;
          }

          // 카드 = DU545 와 같은 앱(ScheduleCard 직접 · 일정 화면 바깥 여백) · 상세 = 같은 앱에서 하네스 단추로 DialogHelper.showSheet(실제 진입과 같은 인자).
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: ChangeNotifierProvider<UserProvider>(
              create: (_) => _P(),
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
                home: Scaffold(
                  body: Builder(
                    builder: (ctx) => c.sheet
                        ? Center(
                            child: TextButton(
                              onPressed: () => DialogHelper.showSheet<void>(ctx,
                                  isScrollControlled: true,
                                  useRootNavigator: true,
                                  builder: (_) => ScheduleDetailDialog(application: fx.app, reads: _reads())),
                              child: const Text(_openLabel),
                            ),
                          )
                        : SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(ResponsiveHelper.spacing(ctx, 16), ResponsiveHelper.spacing(ctx, 4), ResponsiveHelper.spacing(ctx, 16),
                                ResponsiveHelper.spacing(ctx, 4)),
                            child: ScheduleCard(application: fx.app, attendance: fx.att),
                          ),
                  ),
                ),
              ),
            ),
          ));
          for (var i = 0; i < 10; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          if (c.sheet) {
            final openF = find.text(_openLabel);
            final nOpen = openF.evaluate().length;
            need('하네스 여는 단추 1', nOpen == 1, '개수 $nOpen');
            await t.tap(openF);
            for (var i = 0; i < 20; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
          }
          final hostF = c.sheet ? find.byType(ScheduleDetailDialog) : find.byType(ScheduleCard);
          final nHost = hostF.evaluate().length;
          _out('D576 $tok att host n=$nHost');
          need('그릇 1(카드 또는 상세 시트)', nHost == 1, '개수 $nHost');
          // [점검표 A4] 같은 host 의 찾기/측정 앞 — 배지 글이 안 지어졌으면 그 host 의 세로 목록을 끌어 짓는다(DU581 r3 _bringBuilt · 누르기 아님).
          //   카드는 바깥 SingleChildScrollView 가 카드 밖이라 Scaffold 를, 상세는 시트 자신의 스크롤을 host 로 넘긴다.
          await _bringBuilt(t, c.sheet ? hostF : find.byType(Scaffold), c.lab);
          // 배지 글 — 전문 · 낱말 안 끊김 · 줄 수 · 보임(DU571 _seeText 그대로 · 대상 = 그 host 안 그 글 하나).
          final label = await _seeText(t, hostF, (s) => s == c.lab, screen);
          _out('D576 $tok att label n=${label.n} name=${label.name} full=${label.full} brk=${label.brk} lines=${label.lines} vis=${label.vis}');
          need('배지 글 1', label.n == 1, '개수 ${label.n}');
          final chip = _chipOf(t, hostF, c);
          _out('D576 $tok att chip n=${chip.n} face=${chip.face} fg=${chip.fg} icon=${chip.icon} cr=${chip.cr} ok45=${chip.ok45} pair=${chip.pair}');
          final fills = _fills(t);
          _out('D576 $tok att fills n=${fills.n} brand=${fills.brand} err=${fills.err} none=${fills.none} other=${fills.other} list=${fills.list}');
          await shot(c.sheet ? '1sheet' : '1card', c.sheet ? 'detail-sheet-status-badge' : 'card-status-badge');
          raw = 'label $label chip $chip fills $fills';
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // 성공 · 실패 공통 정리 — 화면을 내리고(UserProvider dispose) 남은 timer 가 끝날 시간을 준다.
        var cleanupErr = '';
        try {
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump(const Duration(milliseconds: 500));
        } catch (e, st) {
          cleanupErr = e.toString();
          if (failure == null) {
            failure = e;
            failureSt = st;
          }
        }

        // 집계 — 예상 밖 플랫폼 채널(서버 · 저장소 · 인증 포함) · HTTP.
        final nUnexp = wire.unexpected.length;
        final nHttp = net.tries.length;
        _out('D576 $tok att wire unexpected=$nUnexp http=$nHttp');

        messenger.allMessagesHandler = prevAll;
        HttpOverrides.global = prevHttp;
        final exc = t.takeException();
        if (exc != null && failure == null) {
          failure = exc;
          failureSt = StackTrace.current;
        }
        final nOvf = seen.overflows.length;
        final nFw = seen.other.length;
        final ovfRaw = seen.overflows.take(8).join('\n----\n');
        final fwRaw = seen.other.take(4).map((m) => m.length > 400 ? m.substring(0, 400) : m).join('\n----\n');
        _out('R576 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(wire.unexpected.join(' | '))} '
            'cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
        _out('D576 $tok att fw n=$nFw');
        _out('D576 $tok done state=${c.id} mode=$mode captures=$nShot overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        expect(nShot == c.shots, isTrue, reason: '$tok 캡처 수 = 선언 shots $nShot want ${c.shots}');
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

// [DU575] 색 도우미 — DU309 시험(du1_confirm_color_split_309_test :84–95 · :162–183)과 같은 식(bgOf 는 main 안 지역 함수를 최상위 _bgOf 로만 옮김).

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

/// [DU576] 상태 배지 하나 — 글 [c.lab] 이 그려진 RichText 가 host 안에 정확히 하나일 때 그 글자색 · 그 글 뒤 실제 바탕(_bgOf = 칩 Container 의 BoxDecoration 면) ·
///   칩 상자(가장 가까운 Container 조상) 안 Icon 색 · 대비를 잰다. pair = 글 = c.fg · 면 = c.bg · (카드) 칩 아이콘 하나 = c.fg / (상세) 칩 안 아이콘 0.
typedef _ChipObs = ({int n, String face, String fg, String icon, String cr, bool ok45, bool pair});

_ChipObs _chipOf(WidgetTester t, Finder host, _Case c) {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == c.lab)
      .toList();
  if (es.length != 1) return (n: es.length, face: '-', fg: '-', icon: '-', cr: '0.00', ok45: false, pair: false);
  final el = es.first;
  final Color fg = (el.widget as RichText).text.style?.color ?? Colors.transparent;
  final face = _bgOf(el);
  final box = find.ancestor(of: find.byElementPredicate((x) => identical(x, el), skipOffstage: false), matching: find.byType(Container)).first;
  final ics = find.descendant(of: box, matching: find.byType(Icon), skipOffstage: false).evaluate().toList();
  final Color? ic = ics.length == 1 ? (ics.first.widget as Icon).color : null;
  final cr = _contrast(fg, face);
  final iconOk = c.sheet ? ics.isEmpty : (ic != null && ic.toARGB32() == c.fg.toARGB32());
  return (
    n: 1,
    face: _hex(face),
    fg: _hex(fg),
    icon: ic == null ? '-' : _hex(ic),
    cr: cr.toStringAsFixed(2),
    ok45: cr >= 4.5,
    pair: fg.toARGB32() == c.fg.toARGB32() && face.toARGB32() == c.bg.toARGB32() && iconOk,
  );
}
