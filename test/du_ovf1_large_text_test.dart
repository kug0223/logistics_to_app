// [OVF1 r2 · 판정268/269] ovf1(F267-OVF-TEMPLATE · AVAILABLE · WORK-DETAIL) 회귀 — 6 조건만 · strict runner(관측/before/A18 분기 0) · 캡처 0.
//   조건 = 갤러리 suite 와 같은 보기: 320×640 논리 픽셀 · devicePixelRatio 1.0 · textScaler B 2.0 / N 1.0 · RoleTheme.businessAdminTheme · ko_KR.
//   글꼴 = A 의 assets/fonts 상대 경로(NotoSansKR Regular/Bold → NotoSansKR · Roboto · FlutterTest) — SDK 절대경로 0(MaterialIcons 미등록 · 아이콘 칸 크기는 같음).
//   안전 = 플랫폼 채널은 'flutter/' 시스템 채널만 통과 · 그 밖 메시지 1 개라도 오면 실패 · HTTP 시도 0 · FlutterError 전부 실패(넘침 포함).
//   대역(새 제품 코드 0 · 제품의 기존 시험 훅만): ContractTemplateSelectorDialog.debugReads · AvailableWorkersBottomSheet(service:) · WorkDetailManagementDialog(workDetailStats 직접).
//   fixture 값 = 갤러리 suite r4 의 _to4 · _wd4/_wd4b/_wd4c 와 같은 값 · FakeCore = test/pilot_invite_fence_sheet_message_test.dart 의 _FakeApp/_FakeCore 와 같은 꼴.
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/screens/business_admin/dialogs/available_workers_bottom_sheet.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_detail_management_dialog.dart';
import 'package:ALfit/services/available_workers_service.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/widgets/common/app_checkbox.dart';
import 'package:ALfit/widgets/dialogs/contract_template_selector_dialog.dart';
import 'package:ALfit/widgets/dialogs/styled_dialog.dart';
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
class _ZeroWorkers implements AvailableWorkersService {
  int reads = 0;
  int invites = 0;
  @override
  Future<AvailableWorkersResult> getAvailableWorkers({required String toId, required String slotId, String? workDetailId, int pageSize = 20, String? cursor}) async {
    reads++;
    return const AvailableWorkersResult(candidates: [], hasMore: false, nextCursor: null, poolComplete: true, weeklyContextAvailable: false);
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
    throw StateError('OVF1 시험은 초대 쓰기 0');
  }
}

// ── fixture(갤러리 suite r4 와 같은 값) ──
const _wd4 = WorkDetailData(wdId: 'wd-700', workType: '상하차', workTypeIcon: 'box', workTypeColor: '#3859E8', workTypeBackgroundColor: '#EEF2FF',
    wage: 12000, wageType: 'hourly', requiredCount: 4, startTime: '09:00', endTime: '18:00', order: 0);
const _wd4b = WorkDetailData(wdId: 'wd-701', workType: '분류', workTypeIcon: 'box', workTypeColor: '#3859E8', workTypeBackgroundColor: '#EEF2FF',
    wage: 12500, wageType: 'hourly', requiredCount: 1, startTime: '13:00', endTime: '22:00', order: 1);
const _wd4c = WorkDetailData(wdId: 'wd-702', workType: '검수', workTypeIcon: 'box', workTypeColor: '#3859E8', workTypeBackgroundColor: '#EEF2FF',
    wage: 13000, wageType: 'hourly', requiredCount: 2, startTime: '06:00', endTime: '15:00', order: 2, isManualClosed: true);
TOModel _to4() => TOModel(
    id: 'to-700', businessId: 'biz-700', businessName: '강남 물류센터', type: TOType.flex, title: '물류센터 상하차 단기 모집', workDetails: const [_wd4],
    totalSlots: 2, totalRequired: 4, editRevision: 0, publishMode: 'immediate', isPublished: true, creatorUID: 'owner-700', createdAt: DateTime(2026, 11, 1));

// ── strict runner ──
typedef _View = ({String id, double scale});
const _vB = (id: 'B', scale: 2.0);
const _vN = (id: 'N', scale: 1.0);
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

// ── 장면 ──
Future<void> _cts(_Ctx c, String arg) async {
  var reads = 0;
  ContractTemplateSelectorDialog.debugReads = (
    uid: () => 'owner-700',
    myBusinesses: (_) async => [],
    templates: (_) async {
      reads++;
      if (arg == 'R') throw StateError('양식 읽기 실패(시험 대역)');
      return [];
    },
  );
  addTearDown(() => ContractTemplateSelectorDialog.debugReads = null);
  Object? result;
  var done = false;
  void open() => ContractTemplateSelectorDialog.show(c.host!, businessId: 'biz-700').then((v) {
        result = v;
        done = true;
      });
  final sheet = find.byType(BottomSheet);
  open();
  await c.frames(12);
  expect(sheet, findsOneWidget, reason: '계약 양식 시트 열림');
  expect(reads, 1, reason: '양식 읽기 1 회');
  await c.visible(find.text('계약서 템플릿 선택'), '제목', hit: false);
  if (arg == 'E') {
    await c.visible(findVisibleText('등록된 템플릿이 없습니다'), '빈 상태 제목', hit: false);
    for (final b in const ['기존 계약서로 시작', 'ALfit 기본 조항', '빈 계약서로 진행']) {
      // [r3] '빈 계약서로 진행' 은 빈 안내 안 글 단추 + 아래 고정 단추 2 개 — 모두 보임·hit 확인(개수 1 이상)
      final n = find.text(b).evaluate().length;
      expect(n, greaterThanOrEqualTo(1), reason: '단추 $b 존재');
      for (var i = 0; i < n; i++) {
        await c.visible(find.text(b).at(i), '단추 $b #${i + 1}/$n');
      }
    }
    await c.tap(find.descendant(of: sheet, matching: find.byIcon(Icons.close)), '닫기(X)');
    expect(sheet, findsNothing, reason: '닫기 → 시트 닫힘');
    expect(done && result == null, isTrue, reason: '닫기 결과 null');
    done = false;
    open();
    await c.frames(12);
    expect(reads, 2, reason: '다시 열면 양식 읽기 2 회');
    await c.tap(find.text('빈 계약서로 진행').first, '빈 계약서로 진행(빈 안내 안 단추)');
    expect(sheet, findsNothing, reason: '빈 계약서로 진행 → 시트 닫힘');
    expect(done && result is List && (result as List).isEmpty, isTrue, reason: '결과 = 빈 조항 목록 · $result');
  } else {
    await c.visible(find.text('템플릿 불러오기 실패'), '오류 제목', hit: false);
    await c.tap(findVisibleText('다시 시도'), '다시 시도');
    await c.frames(10);
    expect(reads, 2, reason: '다시 시도 → 양식 읽기 1 → 2 회');
    await c.visible(find.text('템플릿 불러오기 실패'), '다시 시도 뒤 같은 오류', hit: false);
    await c.tap(find.descendant(of: sheet, matching: find.byIcon(Icons.close)), '닫기(X)');
    expect(sheet, findsNothing, reason: '닫기 → 시트 닫힘');
    expect(done && result == null, isTrue, reason: '닫기 결과 null');
  }
}

Future<void> _avw(_Ctx c) async {
  final svc = _ZeroWorkers();
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
  await c.visible(find.textContaining('근무 초대를 받도록'), '0 명 안내 글', hit: false);
  // 0 명 상태 본문에는 단추 없음 → 닫기 = 시트 위 장벽(시트 최대 높이 0.75 → 위 160px)
  await c.t.tapAt(const Offset(160, 16));
  await c.frames(10);
  expect(sheet, findsNothing, reason: '장벽 → 시트 닫힘');
  expect(closed, isTrue);
  expect(svc.invites, 0, reason: '초대 쓰기 0');
}

Future<void> _wdm(_Ctx c, String arg) async {
  final works = arg == 'X' ? const [_wd4, _wd4b, _wd4c] : const [_wd4];
  final stats = <String, Map<String, int>>{
    _wd4.id: {'confirmed': 1, 'pending': 2},
    _wd4b.id: {'confirmed': 1, 'pending': 0},
    _wd4c.id: {'confirmed': 0, 'pending': 0},
  };
  final item = TOItem(to: _to4(), workDetails: works, confirmedCount: 1, pendingCount: 2, totalRequired: 4, workDetailStats: stats,
      isWorkDetailLoaded: true, workDetailStatsFailed: false);
  var completes = 0;
  WorkDetailManagementDialog(context: c.host!, toItem: item, firestoreService: FirestoreService(), onComplete: () => completes++).show();
  final dlg = find.byType(StyledDialog);
  await c.frames(12);
  expect(dlg, findsOneWidget, reason: '업무별 마감 관리 창 열림');
  await c.visible(find.text('업무별 마감 관리'), '제목', hit: false);
  final types = arg == 'X' ? const ['상하차', '분류', '검수'] : const ['상하차'];
  for (final ty in types) {
    expect(find.descendant(of: dlg, matching: find.text(ty)), findsOneWidget, reason: '카드 $ty');
  }
  expect(find.descendant(of: dlg, matching: find.byType(AppCheckbox)), findsNWidgets(types.length + 1), reason: '카드 ${types.length} + 전체 선택 1');
  await c.visible(find.descendant(of: dlg, matching: find.text('(대기 2명)')), "'(대기 2명)'", hit: false);
  await c.tap(find.descendant(of: dlg, matching: find.text('상하차')), '상하차 카드 선택');
  // 동작 단추 = 정확 '1개 마감' · 도달/hit 만(누르기 0 — 쓰기 경로)
  await c.visible(find.descendant(of: dlg, matching: find.text('1개 마감')), "동작 단추 '1개 마감'");
  await c.tap(find.descendant(of: dlg, matching: findVisibleText('취소')), '취소');
  expect(dlg, findsNothing, reason: '취소 → 창 닫힘');
  expect(completes, 0, reason: '취소 → onComplete 0(쓰기 0)');
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await _loadFonts();
  });
  testWidgets('OVF1-B-CTSE 계약 양식 시트 빈 상태(320×640 · 글자 2.0) — 넘침 0 · 단추 3 보임·hit · 닫기 · 빈 계약서로 진행', (t) async {
    await _strict(t, _vB, (c) => _cts(c, 'E'));
  });
  testWidgets('OVF1-N-CTSE 계약 양식 시트 빈 상태(320×640 · 글자 1.0) — 넘침 0 · 단추 3 보임·hit · 닫기 · 빈 계약서로 진행', (t) async {
    await _strict(t, _vN, (c) => _cts(c, 'E'));
  });
  testWidgets('OVF1-B-CTSR 계약 양식 시트 읽기 실패(320×640 · 글자 2.0) — 넘침 0 · 다시 시도 1→2 호출 · 닫기', (t) async {
    await _strict(t, _vB, (c) => _cts(c, 'R'));
  });
  testWidgets('OVF1-B-AVWE 근무 가능 인력 0 명(320×640 · 글자 2.0) — 넘침 0 · 안내 글 보임 · 장벽 닫힘', (t) async {
    await _strict(t, _vB, _avw);
  });
  testWidgets('OVF1-B-WDMO 업무별 마감 관리 진행중 1(320×640 · 글자 2.0) — 넘침 0 · 카드 1 · (대기 2명) · 1개 마감 보임·hit · 취소', (t) async {
    await _strict(t, _vB, (c) => _wdm(c, 'O'));
  });
  testWidgets('OVF1-B-WDMX 업무별 마감 관리 3 업무(320×640 · 글자 2.0) — 넘침 0 · 카드 3 · (대기 2명) · 1개 마감 보임·hit · 취소', (t) async {
    await _strict(t, _vB, (c) => _wdm(c, 'X'));
  });
}
