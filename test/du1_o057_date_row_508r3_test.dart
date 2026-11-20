// ignore_for_file: depend_on_referenced_packages
// [DU508 r3 · 후속120 §2 · 표시만] DU-O057 지원 확인 시트 — 날짜 행 **실노출**(보이는 칸 = viewport ∩ 시트 ∩ 화면 안에 행 전체) ·
//   날짜/업무명 조판(공백 · NBSP · ZWSP 뒤에서만 줄바꿈) · 상태 표시가 날짜 아래 줄 · 하단 '지원하기'(받는 자리 ≥ 48 · 중심 hit · 활성) ·
//   실제 '취소' 탭 → 시트 닫힘 · null 반환(지원 탭 0 · writer 0) · 읽기 경계(F120-3 — 실제 Pigeon 채널 모의 · 정확 호출 · 예상 밖 0).
//   before = 현재 A(multi_apply_confirm_sheet 836b8cee) · strict = 후보(머리 본문 스크롤 안 · 상태 표시 아래 줄 · 날짜 조판).
//   상태 ONE · BLOCK(0번 근무 PENDING 이미 지원 — 확정 충돌 대역 아님) · LONG(긴 업무명). r2 의 shown(화면 경계만)은 쓰지 않는다.
//   before 는 화면 값을 기록만 한다 — 단언은 시험 배선(읽기 경계 · fixture 상태)과 framework 예외 0 · 끝 예외 0 뿐이다.
//   기본 skip — TB before/du508-tb/DU_BEFORE_OBSERVE=508 · TA after/du508-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';
import 'package:ALfit/widgets/dialogs/apply/multi_apply_confirm_sheet.dart';

import 'support/du1_vq_capture.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p', storageBucket: 'b');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

/// 서류 요건을 갖춘 **시험용** 사용자(원 시험과 같다 · 실제 검증 아님).
class _Applicant extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER, accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 2, 1), isIdVerified: true, idCardImagePath: 'users/u1/id.png', bankName: '국민은행',
        accountNumber: '1234', accountHolder: '김근로', bankbookImagePath: 'users/u1/bb.png', createdAt: DateTime(2026, 1, 1),
      );
}

/// [F120-3] 지원 시트가 열릴 때 충돌 확인이 타는 **실제** 플랫폼 채널(cloud_functions_platform_interface 5.8.2 Pigeon).
const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// [F120-3] Cloud Functions 채널 뒤의 시험 모의 서버 — 앱 코드는 실제 ScheduleConflictService → HttpsCallable → Pigeon 을 탄다.
///   요청 = Pigeon `[인자 Map]`(StandardMessageCodec · int 는 int64) · 성공 응답 = `[결과]` · 오류 응답 = `[code, message, details]`.
///   시트가 여는 읽기는 `callableGetMyApplications`(statuses = CONFIRMED · CONTRACT_PENDING · limit 200 · 서울 · 20초) 하나다.
///   세 상태 모두 내 확정 약속 0건을 돌려준다 — BLOCK 의 막힘은 myApplications(0번 근무 PENDING) 관계 판정이지 확정 충돌이 아니다.
///   그 밖의 함수(지원 writer 등)는 기록하고 오류로 막는다(성공 응답 0 · 끝에 0 단언).
class _CfMock {
  final calls = <({String fn, String region, String timeout, String statuses, String limit})>[];

  Future<ByteData?> handle(ByteData? message) async {
    final args = (const StandardMessageCodec().decodeMessage(message) as List).first as Map;
    final fn = (args['functionName'] ?? '-').toString();
    final params = (args['parameters'] as Map?) ?? const {};
    calls.add((
      fn: fn,
      region: (args['region'] ?? '-').toString(),
      timeout: (args['timeout'] ?? '-').toString(),
      statuses: ((params['statuses'] as List?) ?? const []).join(','),
      limit: (params['limit'] ?? '-').toString(),
    ));
    if (fn == 'callableGetMyApplications') {
      return const StandardMessageCodec().encodeMessage(<Object?>[<String, Object?>{'applications': <Object?>[]}]);
    }
    return const StandardMessageCodec().encodeMessage(<Object?>['blocked', 'DU508 r3 시험 — 예상 밖 함수 $fn', null]);
  }
}

/// [F120-3] 모든 플랫폼 메시지 관찰 — CF 채널은 위 모의 서버로, 'flutter/' 프레임워크 채널은 원래 경로 그대로 넘긴다(센다).
///   그 밖의 채널(Firestore · Auth · 저장소 등)은 이름을 기록하고 막는다(응답 null) — 끝에 0 을 단언한다.
class _Wire {
  final unexpected = <String>[];
  var framework = 0;

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
    if (channel == _cfChannel) return handler?.call(message);
    if (channel.startsWith('flutter/')) {
      framework++;
      return handler != null ? handler(message) : m.delegate.send(channel, message);
    }
    unexpected.add(channel);
    return null;
  }
}

/// [F120-3] 외부 HTTP 차단 — 만들려는 시도를 기록하고 실패시킨다(끝에 0 단언).
class _NoHttp extends HttpOverrides {
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    throw const SocketException('DU508 r3 시험 — 외부 HTTP 차단');
  }
}

/// 캡처 기준일(DU1_VQ_DATE)에서 5일 뒤 KST 자정 — 실행 날마다 날짜 글자 폭이 바뀌지 않게 고정한다.
final kFuture = vqNow().add(const Duration(days: 5));
const _biz = '강남 물류센터 주식회사';

TOModel _to() => TOModel(
      id: 'to1', businessId: 'biz1', businessName: _biz, type: 'flex', title: '단기 모집', creatorUID: 'a',
      status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0, workDetails: const [], totalRequired: 50, totalConfirmed: 0,
      totalPending: 0, isPublished: true, publishMode: 'immediate', rangeStart: kFuture, createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

WorkDetailData _wd(int i) => WorkDetailData(
      wdId: 'wd$i', workType: '냉장분류', workTypeIcon: 'box', workTypeColor: '#000000', workTypeBackgroundColor: '#FFFFFF',
      wage: 12000, wageType: 'hourly', requiredCount: 10, startTime: '18:00', endTime: '22:30', breakMinutes: 30,
    );

const _longName = '물류센터상하차보조';
WorkDetailData _wdLong(int i) => WorkDetailData(
      wdId: 'wd$i', workType: _longName, workTypeIcon: 'box', workTypeColor: '#000000', workTypeBackgroundColor: '#FFFFFF',
      wage: 12000, wageType: 'hourly', requiredCount: 10, startTime: '18:00', endTime: '22:30', breakMinutes: 30,
    );

SlotModel _slot(int i) => SlotModel(id: 'slot$i', toId: 'to1', date: kFuture.add(Duration(days: i)), workDetails: [_wd(i)], status: SlotStatus.open);

/// 0번 근무에 이미 낸 지원(PENDING) — 관계 판정으로 제출 대상에서 빠진다(MAC-61 과 같은 축 · 확정 충돌 대역 아님).
ApplicationModel _applied0() => ApplicationModel(
      id: 'a_pending_wd0', uid: 'u1', toId: 'to1', slotId: 'slot0', businessId: 'biz1', businessName: _biz,
      toTitle: '단기 모집', selectedWorkType: '냉장분류', wdId: 'wd0', startTime: '18:00', endTime: '22:30', wage: 12000,
      wageType: 'hourly', status: AppStatus.pending, workDate: kFuture, appliedAt: DateTime(2026, 10, 1),
    );

final _cases = <({String id, int count, List<ApplicationModel> myApps})>[
  (id: 'ONE', count: 1, myApps: const <ApplicationModel>[]),
  (id: 'BLOCK', count: 2, myApps: [_applied0()]),
  (id: 'LONG', count: 1, myApps: const <ApplicationModel>[]),
];

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

String _f(double v) => v.toStringAsFixed(1);
String _rs(Rect r) => '${_f(r.left)},${_f(r.top)},${_f(r.right)},${_f(r.bottom)}';
String _rd(Rect r) => r.width > 0 && r.height > 0 ? _rs(r) : '-';

/// [a] 가 [b] **안**에 있는가(겹침이 아니라 포함 · 0.5px 허용).
bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

/// 글자 상자 top 으로 줄을 가른다 — 줄바꿈이 공백 · NBSP · ZWSP 뒤에서만 일어났는가(r446 · DU475 r2 · 508 r2 와 같다).
({int lines, bool ok}) _breaks(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final tops = <double>[];
  double? prevTop;
  var ok = true;
  for (var i = 0; i < s.length; i++) {
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final tp = bx.first.top;
    if (!tops.any((x) => (x - tp).abs() < 0.5)) tops.add(tp);
    if (prevTop != null && (tp - prevTop).abs() >= 0.5) {
      final raw = s.substring(0, i);
      if (!(raw.endsWith(' ') || raw.endsWith(String.fromCharCode(0x00A0)) || raw.endsWith(String.fromCharCode(0x200B)))) ok = false;
    }
    prevTop = tp;
  }
  return (lines: tops.length, ok: ok);
}

typedef _Seen = ({bool pre, Rect row, Rect vp, Rect vis, double dw, int lines, bool ok, bool inside, bool hit, bool foot, double px, double mx});

/// [r3 · F120-2] 글 상자들([paras] — 날짜 · 업무명 또는 동의 끝 문단)을 **실제 끌기**로 보이는 칸에 넣고, finder 를 **다시 찾아** 잰다.
///   보이는 칸 = 가장 가까운 Scrollable(viewport) ∩ 시트(BottomSheet) ∩ 화면. inside = 행 전체 rect 가 그 칸 **안**(겹침 아님).
///   hit = 글 상자 중심의 hit 경로에 그 글 상자가 있다(하단 · 조상 clip · 덮개에 가리지 않음). foot = 행 아래가 고정 하단 위쪽 이하.
///   끌기: Scrollable 은 DragStartBehavior.start 라 터치 슬롭(kDragSlopDefault)만큼을 버리므로 그만큼 더 끈다. 움직일 수 없는 쪽
///   (W 처럼 내용이 다 들어감 · 이미 끝)으로는 끌지 않는다 — 시트의 끌어 닫기 제스처가 받지 않게. ensureVisible 은 쓰지 않는다.
Future<_Seen> _bring(WidgetTester t, List<Finder> paras, Rect screen, double footTop) async {
  Finder scroller() => find.ancestor(of: paras.first, matching: find.byType(Scrollable)).first;
  Rect rowRect() => paras.map(t.getRect).reduce((a, b) => a.expandToInclude(b));
  Rect visRect() => t.getRect(scroller()).intersect(t.getRect(find.byType(BottomSheet))).intersect(screen);
  final pre = _inside(rowRect(), visRect());
  for (var k = 0; k < 3; k++) {
    final r0 = rowRect();
    final v0 = visRect();
    final p0 = t.state<ScrollableState>(scroller()).position;
    final m = math.max(0.0, math.min(8.0, v0.height - r0.height));
    final u = r0.top - (v0.top + m);
    final canUp = p0.pixels < p0.maxScrollExtent - 0.5;
    final canDown = p0.pixels > p0.minScrollExtent + 0.5;
    if (u.abs() <= 0.5 || (u > 0 && !canUp) || (u < 0 && !canDown)) break;
    final px0 = p0.pixels;
    await t.drag(scroller(), Offset(0, u > 0 ? -(u + kDragSlopDefault) : -u + kDragSlopDefault));
    for (var j = 0; j < 8; j++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    if ((t.state<ScrollableState>(scroller()).position.pixels - px0).abs() < 0.5) break;
  }
  final sc = scroller();
  final pos = t.state<ScrollableState>(sc).position;
  final vp = t.getRect(sc);
  final vis = visRect();
  final row = rowRect();
  var lines = 0;
  var ok = true;
  var hit = true;
  for (final f in paras) {
    final para = t.renderObject(f) as RenderParagraph;
    final b = _breaks(para);
    lines += b.lines;
    ok = ok && b.ok;
    final ctr = t.getRect(f).center;
    hit = hit && t.hitTestOnBinding(ctr).path.any((e) => e.target == para);
  }
  final dw = (t.renderObject(paras.first) as RenderParagraph).constraints.maxWidth;
  return (
    pre: pre, row: row, vp: vp, vis: vis, dw: dw, lines: lines, ok: ok,
    inside: vis.width > 0 && vis.height > 0 && _inside(row, vis), hit: hit, foot: row.bottom <= footTop + 0.5,
    px: pos.pixels, mx: pos.maxScrollExtent,
  );
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '508';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du508-tb' && _env['DU_BEFORE_OBSERVE'] == '508') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du508-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async => FirebasePlatform.instance = _FakeCore());

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    for (final c in _cases) {
      testWidgets('S957SW-${v.id}-${c.id} 지원 확인 시트 — 날짜 행 실노출 · 조판 · 상태 표시 아래 줄 · 취소 닫힘 · 읽기 경계', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        try {
          final tok = 'S957SW-${v.id}-${c.id}';
          final mode = _before ? 'before' : 'strict';
          _out('D508 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
          await t.runAsync(vqLoadFonts);
          final overflows = <String>[];
          final fwErrors = <String>[];
          final prev = FlutterError.onError;
          FlutterError.onError = (d) {
            final m = d.exceptionAsString();
            if (m.contains('overflowed')) {
              final full = d.toString();
              final k = full.indexOf('The relevant error-causing widget was');
              final loc = k < 0 ? '' : full.substring(k).split('\n').skip(1).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
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

          // [F120-3] 읽기 경계 — 실제 Pigeon 채널에 모의 서버를 붙이고, 모든 플랫폼 메시지와 HTTP 를 관찰 · 차단한다.
          final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          final cf = _CfMock();
          final wire = _Wire();
          messenger.setMockMessageHandler(_cfChannel, cf.handle);
          messenger.allMessagesHandler = (channel, handler, message) => wire.route(messenger, channel, handler, message);
          addTearDown(() {
            messenger.allMessagesHandler = null;
            messenger.setMockMessageHandler(_cfChannel, null);
          });
          final net = _NoHttp();
          final prevHttp = HttpOverrides.current;
          HttpOverrides.global = net;
          addTearDown(() => HttpOverrides.global = prevHttp);

          final items = <({SlotModel? slot, WorkDetailData work})>[for (var i = 0; i < c.count; i++) (slot: _slot(i), work: c.id == 'LONG' ? _wdLong(i) : _wd(i))];
          final key = GlobalKey();
          var popped = false;
          MultiApplyResult? got;
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: ChangeNotifierProvider<UserProvider>(
              create: (_) => _Applicant(),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.workerTheme,
                builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (inner) => ElevatedButton(
                        onPressed: () async {
                          got = await DialogHelper.showSheet<MultiApplyResult>(
                            inner,
                            useRootNavigator: true,
                            isScrollControlled: true,
                            builder: (_) => MultiApplyConfirmSheet(items: items, to: _to(), myApplications: c.myApps),
                          );
                          popped = true;
                        },
                        child: const Text('열기'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ));
          await t.pump();
          await t.tap(find.text('열기'));
          // 충돌 확인 응답(모의)과 시트 올라옴을 끝까지 흘린다(r1 · r2 와 같은 틱).
          for (var k = 0; k < 2; k++) {
            await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
            for (var i = 0; i < 20; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
          }
          Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
          final sheetN = find.byType(MultiApplyConfirmSheet).evaluate().length;
          need('시트 열림', sheetN == 1, '시트 $sheetN');
          final screen = Offset.zero & Size(v.w, v.h);
          final sheetR = t.getRect(find.byType(BottomSheet));
          final onSheet = sheetR.intersect(screen);

          // ① fixture 상태 — 모의 읽기 성공(확정 약속 0)이라 '확인 실패 경고(주의)' 대역이 아니다. BLOCK 만 0번이 '이미 지원중'.
          final name = c.id == 'LONG' ? _longName : '냉장분류';
          final title = c.id == 'BLOCK' ? '2개 중 1개 업무에 지원할 수 있어요' : '1개 업무에 지원합니다';
          final headOk = rt((p) => p == title).evaluate().length == 1;
          final nAlready = rt((p) => p == '이미 지원중').evaluate().length;
          final nWarn = rt((p) => p == '주의').evaluate().length;
          final nBlocked = rt((p) => p == '지원 불가').evaluate().length;
          final nSpin = find.byType(CircularProgressIndicator).evaluate().length;
          final nCta = rt((p) => p == '지원하기').evaluate().length;
          final wantAlready = c.id == 'BLOCK' ? 1 : 0;
          _out('D508 $tok att state head=$headOk already=$nAlready warn=$nWarn blocked=$nBlocked spin=$nSpin cta=$nCta');
          chk('fixture 머리 · 상태(모의 읽기 성공 — 경고 대역 아님)', headOk && nAlready == wantAlready && nWarn == 0 && nBlocked == 0 && nSpin == 0 && nCta == 1,
              'head $headOk already $nAlready warn $nWarn blocked $nBlocked spin $nSpin cta $nCta');

          // ② 고정 하단 위쪽(지원 안내 상자) · 하단 안내 낱말 경계.
          final infoF = rt((p) => p.startsWith('지원 후 관리자의 근무 확정을'));
          final infoN = infoF.evaluate().length;
          need('하단 안내 1', infoN == 1, '개수 $infoN');
          final footTop = t.getRect(find.ancestor(of: infoF, matching: find.byType(Container)).first).top;
          final infoOk = _breaks(t.renderObject(infoF) as RenderParagraph).ok;
          _out('D508 $tok att info ok=$infoOk');

          // ③ 나머지 안내(BLOCK) — 처음 연 그대로(스크롤 0)에서 보이는 칸 안 · 중심 hit · 낱말 경계.
          //   보이는 칸 = 가장 가까운 Scrollable 이 있으면(후보 — 머리가 본문 스크롤 안) 그 viewport ∩ 시트 ∩ 화면, 없으면(기준 — 고정 머리) 시트 ∩ 화면.
          if (c.id == 'BLOCK') {
            final restF = rt((p) => p == '나머지 1개는 이미 지원 중이거나 확정된 근무와 겹쳐요.');
            final restN = restF.evaluate().length;
            need('나머지 안내 1', restN == 1, '개수 $restN');
            final restSc = find.ancestor(of: restF, matching: find.byType(Scrollable));
            final restInScroll = restSc.evaluate().isNotEmpty;
            final restVis = restInScroll ? t.getRect(restSc.first).intersect(onSheet) : onSheet;
            final restR = t.getRect(restF);
            final restRo = t.renderObject(restF);
            final restHit = t.hitTestOnBinding(restR.center).path.any((e) => e.target == restRo);
            final restIn = _inside(restR, restVis) && restHit;
            final restOk = _breaks(restRo as RenderParagraph).ok;
            _out('D508 $tok att rest ok=$restOk in=$restIn sc=$restInScroll');
            if (!_before) {
              chk('strict 나머지 안내 — 처음 화면에 보임 · 낱말 경계', restIn && restOk, 'in $restIn ok $restOk');
            }
          }

          // ④ 첫 업무 날짜 행 — 날짜 문단(+ 따로 놓인 업무명 문단)을 실제로 끌어 보이는 칸에 넣고 다시 찾아 잰다.
          final dateRe = RegExp(r'^\d{1,2}월 \d{1,2}일\(.\) · ');
          final dateF = rt((p) => dateRe.hasMatch(p));
          final nameF = rt((p) => p == name);
          final dN = dateF.evaluate().length;
          final sepN = nameF.evaluate().length;
          need('날짜 행 = 업무 수', dN == c.count, '날짜 $dN 업무 ${c.count}');
          need('업무명 문단 = 0(날짜와 한 문단) 또는 업무 수(따로)', sepN == 0 || sepN == c.count, '업무명 $sepN');
          final sep = sepN == c.count;
          final d0 = await _bring(t, [dateF.at(0), if (sep) nameF.at(0)], screen, footTop);
          final nameOk = sep || _plainOf(t.widget(dateF.at(0))).endsWith(name);
          final nr = sep ? _rd(t.getRect(nameF.at(0))) : '-';
          _out('D508 $tok att date n=$dN pre=${d0.pre} dr=${_rs(d0.row)} nr=$nr dw=${_f(d0.dw)} vp=${_rs(d0.vp)} vw=${_f(d0.vp.width)} vis=${_rd(d0.vis)} '
              'vh=${_f(d0.vis.height)} px=${_f(d0.px)} max=${_f(d0.mx)} lines=${d0.lines} ok=${d0.ok} in=${d0.inside} foot=${d0.foot} hit=${d0.hit} name=$nameOk sep=$sep');
          if (!_before) {
            chk('strict 첫 날짜 행 — 보이는 칸 안 · 하단 위 · 중심 hit · 낱말 경계 · 업무명 전문', d0.inside && d0.foot && d0.hit && d0.ok && nameOk,
                'in ${d0.inside} foot ${d0.foot} hit ${d0.hit} ok ${d0.ok} 줄 ${d0.lines} name $nameOk');
          }
          // 상태 표시 — BLOCK 0번 '이미 지원중' 배지가 날짜 행 **아래** 줄인가(날짜 칸 폭을 차지하지 않는다).
          final badgeF = rt((p) => p == '이미 지원중');
          final bN = badgeF.evaluate().length;
          if (c.id == 'BLOCK') {
            need('BLOCK 배지 1', bN == 1, '배지 $bN');
            final br = t.getRect(find.ancestor(of: badgeF, matching: find.byType(Container)).first);
            final below = br.top >= d0.row.bottom - 0.5;
            _out('D508 $tok att badge n=$bN br=${_rs(br)} bw=${_f(br.width)} below=$below');
            if (!_before) {
              chk('strict 상태 표시가 날짜 행 아래 줄', below, '배지 top ${_f(br.top)} 행 bottom ${_f(d0.row.bottom)}');
            }
          } else {
            _out('D508 $tok att badge n=$bN');
          }
          _out('D508 $tok shot 1date ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_1date', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': c.id,
            'state': 'date-row-dragged-into-view',
          });

          // ⑤ 마지막 업무 날짜 행 — 실제로 끈 뒤 다시 찾아 잰다(ONE · LONG 은 첫 업무와 같다).
          final li = c.count - 1;
          final dl = await _bring(t, [dateF.at(li), if (sep) nameF.at(li)], screen, footTop);
          _out('D508 $tok att last idx=$li dr=${_rs(dl.row)} lines=${dl.lines} px=${_f(dl.px)} in=${dl.inside} hit=${dl.hit} ok=${dl.ok}');
          if (!_before) {
            chk('strict 마지막 날짜 행 — 실제 끈 뒤 보이는 칸 안 · 중심 hit · 낱말 경계', dl.inside && dl.hit && dl.ok, 'in ${dl.inside} hit ${dl.hit} ok ${dl.ok}');
          }

          // ⑥ 동의 끝 문단 — 실제로 끌어 보이는 칸 안 · 중심 hit(끝 도달).
          final tailF = rt((p) => p == DocumentAccessConsent.partsFor(_biz).last);
          final tailN = tailF.evaluate().length;
          need('동의 끝 문단 1', tailN == 1, '개수 $tailN');
          final cs = await _bring(t, [tailF], screen, footTop);
          _out('D508 $tok att consent cr=${_rs(cs.row)} lines=${cs.lines} in=${cs.inside} hit=${cs.hit}');
          if (!_before) {
            chk('strict 동의 끝 문단 — 보이는 칸 안 · 중심 hit', cs.inside && cs.hit, 'in ${cs.inside} hit ${cs.hit}');
          }

          // ⑦ '지원하기' — 받는 자리(InkWell) ≥ 48 · 시트 · 화면 안(잘림 0) · 중심 hit · 활성. 누르지 않는다(지원 writer 0).
          final ctaF = rt((p) => p == '지원하기');
          need('지원하기 1', ctaF.evaluate().length == 1, '개수 $nCta');
          final inkF = find.ancestor(of: ctaF, matching: find.byType(InkWell)).first;
          final ctaR = t.getRect(inkF);
          final inkRo = t.renderObject(inkF);
          final ctaHit = t.hitTestOnBinding(ctaR.center).path.any((e) => e.target == inkRo);
          final ctaEn = t.widget<InkWell>(inkF).onTap != null;
          final ctaIn = _inside(ctaR, onSheet);
          final ctaRx = ctaR.height >= 48 - 0.01 && ctaR.width >= 48 - 0.01;
          _out('D508 $tok att cta r=${_rs(ctaR)} h=${_f(ctaR.height)} w=${_f(ctaR.width)} rx=$ctaRx in=$ctaIn hit=$ctaHit en=$ctaEn');
          if (!_before) {
            chk('strict 지원하기 — 받는 자리 ≥ 48 · 시트 · 화면 안 · 중심 hit · 활성', ctaRx && ctaIn && ctaHit && ctaEn, 'rx $ctaRx in $ctaIn hit $ctaHit en $ctaEn');
          }
          _out('D508 $tok shot 2end ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_2end', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': c.id,
            'state': 'consent-end-and-cta',
          });

          // ⑧ 실제 '취소' 탭 → 시트 닫힘 · 반환 null(지원 탭 0).
          final xF = find.widgetWithText(TextButton, '취소');
          final xN = xF.evaluate().length;
          need('취소 1', xN == 1, '개수 $xN');
          final xR = t.getRect(xF);
          final xRo = t.renderObject(xF);
          final xHit = t.hitTestOnBinding(xR.center).path.any((e) => e.target == xRo);
          final xIn = _inside(xR, onSheet);
          await t.tap(xF);
          for (var i = 0; i < 12; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          final sheetsAfter = find.byType(MultiApplyConfirmSheet).evaluate().length;
          final resS = got == null ? 'null' : 'set';
          _out('D508 $tok att cancel hit=$xHit in=$xIn sheets=$sheetsAfter popped=$popped result=$resS');
          if (!_before) {
            chk('strict 취소 — 중심 hit · 시트 안 · 실제 탭 뒤 닫힘 · null 반환', xHit && xIn && sheetsAfter == 0 && popped && resS == 'null',
                'hit $xHit in $xIn sheets $sheetsAfter popped $popped result $resS');
          }
          await t.pump(const Duration(seconds: 1));

          // ⑨ 읽기 경계 — 연 뒤 · 취소 뒤까지 CF 호출 정확 1(callableGetMyApplications · 입력 고정) · 쓰기 0 · 예상 밖 채널 0 · HTTP 0.
          final nCalls = cf.calls.length;
          final fns = nCalls == 0 ? '-' : cf.calls.map((x) => x.fn).join(',');
          final region = nCalls == 0 ? '-' : cf.calls.first.region;
          final timeout = nCalls == 0 ? '-' : cf.calls.first.timeout;
          final statuses = nCalls == 0 ? '-' : cf.calls.first.statuses;
          final limit = nCalls == 0 ? '-' : cf.calls.first.limit;
          final nWriter = cf.calls.where((x) => x.fn != 'callableGetMyApplications').length;
          final nUnexp = wire.unexpected.length;
          final unexpNames = wire.unexpected.join(' | ');
          final nHttp = net.tries.length;
          final nFrame = wire.framework;
          _out('D508 $tok att reader calls=$nCalls fn=$fns region=$region timeout=$timeout statuses=$statuses limit=$limit writer=$nWriter unexpected=$nUnexp http=$nHttp fw=$nFrame');
          chk('읽기 경계 — callableGetMyApplications 정확 1 · 입력 · 쓰기 0 · 예상 밖 채널 0 · HTTP 0',
              nCalls == 1 && fns == 'callableGetMyApplications' && region == 'asia-northeast3' && timeout == '20000' &&
                  statuses == 'CONFIRMED,CONTRACT_PENDING' && limit == '200' && nWriter == 0 && nUnexp == 0 && nHttp == 0,
              'calls $nCalls fn $fns region $region timeout $timeout statuses $statuses limit $limit writer $nWriter 예상 밖 [$unexpNames] http $nHttp');

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
          _out('D508 $tok done state=${c.id} mode=$mode captures=2 overflows=$nOvf exc=${exc != null} ovfRaw=$ovfRaw');
          expect(exc, isNull, reason: '$tok 끝 예외 $exc');
        } catch (e) {
          _anyFail = true;
          rethrow;
        }
      }, skip: !_optIn);
    }
  }
}
