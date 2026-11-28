// [OVF2 · 판정272 다음 순서 1] ovf2(F272-OVF-INVITE-METHOD · RECOVERY · AVAILABLE-ERROR · AVAILABLE-FILTER0) 회귀 — 4 조건 · strict runner · 캡처 0.
//   하니스 = v1g/ovf1/test_cand_r4/du_ovf1_large_text_test.dart(1dad34bc0c8e1688) 의 글꼴·FakeCore·_NoHttp·_Ctx·_strict 줄 그대로(문자열 목록 단언 · exceptionAsString).
//   조건 = 320×640 · dpr 1.0 · 글자 2.0(B) · RoleTheme.businessAdminTheme · ko_KR. 대역 = 제품의 기존 시험 훅(service: · RegistrationRecoveryReads) · 새 제품 코드 0.
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/available_worker_model.dart';
import 'package:ALfit/screens/auth/registration_recovery_reads.dart';
import 'package:ALfit/screens/auth/registration_recovery_screen.dart';
import 'package:ALfit/screens/business_admin/dialogs/available_workers_bottom_sheet.dart';
import 'package:ALfit/screens/business_admin/dialogs/invite_method_sheet.dart';
import 'package:ALfit/services/available_workers_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'support/visible_text.dart'; // [impl_21] TextLayout 문구는 보이는 글자로 찾는다

// ── 글꼴(상대 경로) ──
Future<void> _loadFonts() async {
  Future<ByteData> b(String p) => File(p).readAsBytes().then((x) => ByteData.view(x.buffer));
  for (final fam in const ['NotoSansKR', 'Roboto', 'FlutterTest']) {
    await (FontLoader(fam)
          ..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))
          ..addFont(b('assets/fonts/NotoSansKR-Bold.ttf')))
        .load();
  }
}

// ── Firebase 코어 대역(pilot_invite_fence_sheet_message_test.dart 와 같은 꼴) ──
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

// ── 안전 대역 ──
class _NoHttp extends HttpOverrides {
  final tries = <String>[];
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    throw StateError('OVF1 시험은 HTTP 0');
  }
}

/// 근무 가능 인력 0 명 대역 — 후보 조회 호출 수를 센다 · 초대 호출 = 즉시 실패(쓰기 0).
// [ovf2] _ZeroWorkers(ovf1 전용) · fixture 는 옮기지 않음 — 아래 _Workers

// ── strict runner ──
typedef _View = ({String id, double scale});
const _vB = (id: 'B', scale: 2.0);
const _screen = Size(320, 640);

class _Ctx {
  _Ctx(this.t);
  final WidgetTester t;
  BuildContext? host;
  final errors = <FlutterErrorDetails>[];
  final unexpected = <String>[];
  late _NoHttp net;

  Rect get screen => Offset.zero & _screen;

  Future<void> frames([int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  /// 대상 1 · 사각형 전부 화면 안 · 중심 hit 가 대상(또는 그 자손)에 닿음. 감싼 Scrollable 이 있으면 먼저 그쪽으로 끌어온다(구현 형식 단언 0).
  Future<void> visible(Finder f, String what, {bool hit = true}) async {
    expect(f, findsOneWidget, reason: '$what 1 개');
    final sc = find.ancestor(of: f, matching: find.byType(Scrollable));
    if (sc.evaluate().isNotEmpty) {
      await t.scrollUntilVisible(f, 80, scrollable: sc.first, maxScrolls: 60);
      await frames(4);
    }
    final rc = t.getRect(f);
    final inside = rc.left >= -0.5 && rc.top >= -0.5 && rc.right <= _screen.width + 0.5 && rc.bottom <= _screen.height + 0.5;
    expect(inside, isTrue, reason: '$what 화면 안 보임 · rect $rc');
    if (hit) expect(f.hitTestable(), findsOneWidget, reason: '$what 중심 hit(가림 0) · rect $rc');
  }

  Future<void> tap(Finder f, String what) async {
    await visible(f, what);
    await t.tap(f);
    await frames(10);
  }
}

Future<void> _strict(WidgetTester t, _View v, Future<void> Function(_Ctx c) body) async {
  final c = _Ctx(t);
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final prevAll = m.allMessagesHandler;
  final prevHttp = HttpOverrides.current;
  final prevOnError = FlutterError.onError;
  c.net = _NoHttp();
  m.allMessagesHandler = (channel, handler, message) {
    if (channel.startsWith('flutter/')) return handler == null ? null : handler(message);
    c.unexpected.add(channel);
    return null;
  };
  HttpOverrides.global = c.net;
  t.view.physicalSize = _screen;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  try {
    FlutterError.onError = c.errors.add;
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: RoleTheme.businessAdminTheme,
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.scale)), child: child!),
      home: Scaffold(body: Builder(builder: (bc) {
        c.host = bc;
        return const SizedBox.expand();
      })),
    ));
    await body(c);
    await t.pumpWidget(const SizedBox.shrink());
    await c.frames(10);
  } finally {
    FlutterError.onError = prevOnError;
    m.allMessagesHandler = prevAll;
    HttpOverrides.global = prevHttp;
  }
  // [r3] 위젯 해제 뒤 FlutterErrorDetails.toString() 은 조상 탐색으로 assert — 예외 문자열만 사용
  final ovf = c.errors.where((e) => e.exceptionAsString().contains('overflowed')).toList();
  // [r4] matcher 의 불일치 설명도 FlutterErrorDetails.toString() 을 부름 → 문자열 목록으로 단언
  final ovfText = ovf.map((e) => e.exceptionAsString().split('\n').first).toList();
  final errText = c.errors.map((e) => e.exceptionAsString().split('\n').first).toList();
  expect(ovfText, isEmpty, reason: 'RenderFlex 넘침 0');
  expect(errText, isEmpty, reason: 'FlutterError 0');
  expect(c.unexpected, isEmpty, reason: '플랫폼 채널(CF·Firestore·Auth 포함) 0 — ${c.unexpected.join(' | ')}');
  expect(c.net.tries, isEmpty, reason: 'HTTP 0');
  expect(t.takeException(), isNull);
}

// ── 대역: 근무 가능 인력 조회(결과/실패 선택 · 호출 수) · 초대 = 즉시 실패(쓰기 0) ──
class _Workers implements AvailableWorkersService {
  _Workers({this.fail = false, this.withOne = false});
  final bool fail;
  final bool withOne;
  int reads = 0;
  int invites = 0;
  @override
  Future<AvailableWorkersResult> getAvailableWorkers({required String toId, required String slotId, String? workDetailId, int pageSize = 20, String? cursor}) async {
    reads++;
    if (fail) throw StateError('OVF2 시험 대역 — 조회 실패');
    return AvailableWorkersResult(
        candidates: withOne ? const [AvailableWorkerModel(uid: 'w1', maskedName: '김*로', city: '서울')] : const [],
        hasMore: false,
        nextCursor: null,
        poolComplete: true,
        weeklyContextAvailable: false);
  }

  @override
  Future<String> inviteWorker(
      {required String toId,
      required String businessId,
      required String targetUid,
      required DateTime workDate,
      String? slotId,
      String? selectedWorkType,
      String? workDetailStartTime,
      String? workDetailEndTime}) async {
    invites++;
    throw StateError('OVF2 시험은 초대 쓰기 0');
  }
}

/// TextLayout.keepWords/phrases 의 낱말 결합자(U+2060)·끊음 자리(U+200B)를 뺀 글이 [s] 와 같은 Text.
Finder _plain(String s) => find.byWidgetPredicate((w) => w is Text && (w.data ?? '').replaceAll('⁠', '').replaceAll('​', '') == s, description: 'plain "$s"');

// ── 장면 ──
/// B-INVM — 근무 초대 방법 시트(갤러리 suite r4 _invmBody 와 같은 인자 · _kInit = 2026-11-24).
Future<void> _invm(_Ctx c) async {
  final sheet = find.byType(InviteMethodSheet);
  Object? result = 'unset';
  var done = false;
  void open() {
    done = false;
    result = 'unset';
    DialogHelper.showSheet<String>(c.host!,
            builder: (_) => InviteMethodSheet(workType: '상하차', date: DateTime(2026, 11, 24), startTime: '09:00', endTime: '18:00', shortage: 2))
        .then((v) {
      result = v;
      done = true;
    });
  }

  open();
  await c.frames(12);
  expect(sheet, findsOneWidget, reason: '초대 방법 시트 열림');
  await c.visible(findVisibleText('근무 초대'), '제목', hit: false);
  for (final b in const ['근무 가능 인력', '직접 초대']) {
    await c.visible(find.text(b), '선택지 $b');
  }
  await c.tap(find.text('근무 가능 인력'), '근무 가능 인력');
  expect(sheet, findsNothing, reason: '선택 → 시트 닫힘');
  expect(done && result == 'availability', isTrue, reason: "결과 'availability' · $result");
  open();
  await c.frames(12);
  await c.tap(find.text('직접 초대'), '직접 초대');
  expect(done && result == 'direct', isTrue, reason: "결과 'direct' · $result");
  open();
  await c.frames(12);
  await c.t.tapAt(const Offset(160, 16));   // 시트 위 장벽(시트 최대 높이 9/16 → 위 280px)
  await c.frames(10);
  expect(sheet, findsNothing, reason: '장벽 → 시트 닫힘');
  expect(done && result == null, isTrue, reason: '장벽 결과 null · $result');
}

/// B-RRCF — 가입 복구(외국인등록증 재입력 단계 · 갤러리 suite r4 _rrcCase('F') 와 같은 대역 · 약관 읽기 0 · 동의 기록 0).
Future<void> _rrcf(_Ctx c) async {
  var consents = 0;
  Navigator.of(c.host!).push(MaterialPageRoute<void>(
      builder: (_) => RegistrationRecoveryScreen(
          reads: RegistrationRecoveryReads(
              currentUid: () => 'owner-700',
              userDoc: (_) async => <String, dynamic>{'role': 'USER'},
              terms: () async => throw StateError('OVF2 시험 대역 — 약관 읽기 0'),
              recordConsent: (_) async => consents++))));
  await c.frames(12);
  expect(find.byType(RegistrationRecoveryScreen), findsOneWidget, reason: '가입 복구 화면 열림');
  await c.visible(_plain('외국인등록증 정보 등록 필요'), '제목', hit: false);
  // 아래 단추 2 — 둘 다 보임·hit(누르기 0: 이어서 완료 = 외국인 가입 화면(쓰기 경로) · 돌아가기 = 로그아웃(Auth))
  await c.visible(_plain('외국인 가입 이어서 완료'), '단추 외국인 가입 이어서 완료'); // [ovf3] keepWords 뒤 정확 글 = _plain
  await c.visible(_plain('로그인 화면으로 돌아가기'), '단추 로그인 화면으로 돌아가기');
  expect(consents, 0, reason: '동의 기록 0');
}

/// B-AVW 오류(:794) — 조회 실패 → 오류 안내 · '다시 시도' 1→2 호출 · 장벽 닫힘.
Future<void> _avwErr(_Ctx c) async {
  final svc = _Workers(fail: true);
  var closed = false;
  unawaited(DialogHelper.showSheet<void>(c.host!,
      isScrollControlled: true,
      builder: (_) => AvailableWorkersBottomSheet(
          toId: 'to-700', slotId: 'slot-700', workDetailId: 'wd-700', businessId: 'biz-700', date: DateTime(2026, 12, 3), workType: '상하차',
          startTime: '09:00', endTime: '18:00', requiredCount: 4, confirmedCount: 1, service: svc)).then((_) => closed = true));
  final sheet = find.byType(AvailableWorkersBottomSheet);
  await c.frames(12);
  expect(sheet, findsOneWidget, reason: '근무 가능 인력 시트 열림');
  expect(svc.reads, 1, reason: '후보 조회 1 회');
  await c.visible(find.text('인력 조회에 실패했습니다. 다시 시도해주세요.'), '오류 안내 글', hit: false);
  await c.tap(findVisibleText('다시 시도'), '다시 시도');
  await c.frames(10);
  expect(svc.reads, 2, reason: '다시 시도 → 조회 1 → 2 회');
  await c.visible(find.text('인력 조회에 실패했습니다. 다시 시도해주세요.'), '다시 시도 뒤 같은 오류', hit: false);
  await c.t.tapAt(const Offset(160, 16));
  await c.frames(10);
  expect(sheet, findsNothing, reason: '장벽 → 시트 닫힘');
  expect(closed, isTrue);
  expect(svc.invites, 0, reason: '초대 쓰기 0');
}

/// B-AVW 필터 0(:845) — 후보 1(업무 경험 0) → 필터 '이 업무 경험 있음' 적용 → 필터 0 안내 · '필터 초기화' → 후보 다시 보임 · 장벽 닫힘.
Future<void> _avwFilter0(_Ctx c) async {
  final svc = _Workers(withOne: true);
  var closed = false;
  unawaited(DialogHelper.showSheet<void>(c.host!,
      isScrollControlled: true,
      builder: (_) => AvailableWorkersBottomSheet(
          toId: 'to-700', slotId: 'slot-700', workDetailId: 'wd-700', businessId: 'biz-700', date: DateTime(2026, 12, 3), workType: '상하차',
          startTime: '09:00', endTime: '18:00', requiredCount: 4, confirmedCount: 1, service: svc)).then((_) => closed = true));
  final sheet = find.byType(AvailableWorkersBottomSheet);
  await c.frames(12);
  expect(sheet, findsOneWidget, reason: '근무 가능 인력 시트 열림');
  expect(find.textContaining('김*로'), findsWidgets, reason: '후보 1 보임');
  await c.tap(find.text('필터'), '필터 열기');
  await c.tap(find.text('이 업무 경험 있음'), '이 업무 경험 있음');
  await c.tap(find.text('적용'), '적용');
  await c.visible(find.text('조건에 맞는 초대 가능 인력이 없습니다.'), '필터 0 안내 글', hit: false);
  await c.tap(find.text('필터 초기화'), '필터 초기화');
  expect(find.textContaining('김*로'), findsWidgets, reason: '필터 초기화 → 후보 다시 보임');
  expect(svc.reads, 1, reason: '필터는 다시 조회하지 않음(조회 1 회)');
  await c.t.tapAt(const Offset(160, 16));
  await c.frames(10);
  expect(sheet, findsNothing, reason: '장벽 → 시트 닫힘');
  expect(closed, isTrue);
  expect(svc.invites, 0, reason: '초대 쓰기 0');
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await _loadFonts();
  });
  testWidgets('OVF2-B-INVM 근무 초대 방법 시트(320×640 · 글자 2.0) — 넘침 0 · 선택지 2 보임·hit · 선택 결과 · 장벽 닫힘', (t) async {
    await _strict(t, _vB, _invm);
  });
  testWidgets('OVF2-B-RRCF 가입 복구 외국인등록증 단계(320×640 · 글자 2.0) — 넘침 0 · 제목 · 아래 단추 2 보임·hit', (t) async {
    await _strict(t, _vB, _rrcf);
  });
  testWidgets('OVF2-B-AVWR 근무 가능 인력 조회 실패(320×640 · 글자 2.0) — 넘침 0 · 오류 안내 · 다시 시도 1→2 · 장벽 닫힘', (t) async {
    await _strict(t, _vB, _avwErr);
  });
  testWidgets('OVF2-B-AVWF 근무 가능 인력 필터 결과 0(320×640 · 글자 2.0) — 넘침 0 · 필터 0 안내 · 필터 초기화 · 장벽 닫힘', (t) async {
    await _strict(t, _vB, _avwFilter0);
  });
}
