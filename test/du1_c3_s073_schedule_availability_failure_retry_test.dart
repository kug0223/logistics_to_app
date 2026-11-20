// ignore_for_file: depend_on_referenced_packages
// [DU1 후속68 · 감사68 §4 F67-2] 카드 식별·근무 정보 실제 가시성(RenderParagraph 말줄임·rect·viewport) 측정 추가 — 같은 사건·fixture 유지.
// [DU1 구현67 · 감사67 §5] S073-SCHEDULE-CONFIRMED-AVAILABILITY-FAILURE-RETRY-B/W — 근로자 일정 탭: 확정 일정 유지 + 가능일만 실패 → 실제 재시도 → 복구.
//   출발(감사67 §5.1): production MyScheduleScreen(reads: 명시 LOCAL MyScheduleReads) 단독 화면 · USER · 초기 선택일 KST 오늘 · 스크롤 0.
//     UserRoot 자연 shell(IndexedStack 타 탭·PendingContractBar)은 쓰지 않는다 — 이 시험은 UserRoot 탐색 성공이 아니다.
//     원래 탭 매핑: user_root_screen.dart IndexedStack index 2 = const MyScheduleScreen() (소스 확인만).
//   read seam 4종만 치환(myApplications · myMonthlyAttendances · myAvailability · invitePreference). 쓰기(가능일 저장)는 seam 밖 —
//     Functions/Firestore 채널은 전부 차단·계수해 0 을 단언한다.
//   fixture(§5.2): Q = 실행 KST 오늘+1 · U = +2 (같은 표시 월이어야 함 — 아니면 실패). Q 에 확정 단기 근무 1건(긴 사업장명), U 근무 0.
//     월 근태 정상 empty · 초대 지역 정상 ON(서울특별시 송파구) · 가능일 정상 응답 = 유효 {Q,U}.
//   사건: applications#1·availability#1 gate 보류(invitePreference 정상) → applications 정상 → 월 근태 empty → 실제 Q 탭 →
//     availability#1 명시 실패 → 가능일 전용 실패/다시 시도 → 실제 중심 tap 1회 → availability#2 gate 보류 → {Q,U} 정상 → U 탭 → Q 복귀.
//   논리 seam 사전(실행 전 고정): applications-held 3 → +monthlyAttendances 4 → retry +availability 5. 실패/정상 해제·같은 월 날짜 탭 추가 0.
//     5 는 논리 seam 호출 수이며 네트워크 호출 수 선언이 아니다.
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/invite_region_preference.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/worker_availability_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_schedule_reads.dart';
import 'package:ALfit/screens/user/my_schedule_screen.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/widgets/calendar/schedule_calendar.dart';
import 'package:ALfit/widgets/calendar/schedule_card.dart';

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

const kUid = 'worker-local-c67';
const kBizName = 'QA 송파 물류센터 제2캠퍼스 상하차동';

class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: kUid, username: 'worker', name: 'QA 근로자', email: 'w@test.local', role: UserRole.USER,
        homeRegion: const UserRegion(province: '서울특별시', city: '송파구'), accountStatus: 'active',
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

String _kst(DateTime d) {
  final k = d.toUtc().add(const Duration(hours: 9));
  String p(int x) => x.toString().padLeft(2, '0');
  return '${k.year}-${p(k.month)}-${p(k.day)} ${p(k.hour)}:${p(k.minute)} KST(ms=${d.millisecondsSinceEpoch})';
}

int _lines(RenderParagraph p) {
  final len = p.text.toPlainText().length;
  final boxes = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len));
  return boxes.map((b) => b.top.round()).toSet().length;
}

void main() {
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  const fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // ── KST 날짜 고정 ──
  final now = DateTime.now();
  final kNow = now.toUtc().add(const Duration(hours: 9));
  DateTime kstMidnight(int plus) => DateTime.utc(kNow.year, kNow.month, kNow.day + plus).subtract(const Duration(hours: 9));
  final qDate = kstMidnight(1);
  final uDate = kstMidnight(2);
  final qKey = WorkerAvailabilityModel.dateKeyFrom(qDate);
  final uKey = WorkerAvailabilityModel.dateKeyFrom(uDate);
  final kQ = qDate.toUtc().add(const Duration(hours: 9));
  final kU = uDate.toUtc().add(const Duration(hours: 9));

  final appQ = ApplicationModel(
    id: 'app-c67-q', toId: 'to-c67-q', slotId: 'slot-c67-q', workDetailId: 'wd-c67-q', uid: kUid, applicantName: 'QA 근로자',
    businessId: 'biz-c67', businessName: kBizName, toTitle: 'QA 상하차 단기', status: AppStatus.confirmed,
    selectedWorkType: '상하차', startTime: '09:00', endTime: '13:00', wage: 12000, wageType: 'hourly',
    workDate: qDate, appliedAt: qDate.subtract(const Duration(days: 3)),
  );

  // ── 논리 seam 계수 ──
  final calls = <String, int>{};
  void inc(String k) => calls[k] = (calls[k] ?? 0) + 1;
  final appGates = <Completer<void>>[];
  final availGates = <Completer<void>>[];
  final seamLog = <String>[];
  MyScheduleReads reads() => MyScheduleReads(
        myApplications: (uid) async {
          inc('myApplications');
          seamLog.add('myApplications(uid=$uid)');
          final g = Completer<void>();
          appGates.add(g);
          await g.future;
          return [appQ];
        },
        myMonthlyAttendances: ({required String userId, required int year, required int month}) async {
          inc('myMonthlyAttendances');
          seamLog.add('myMonthlyAttendances(userId=$userId, $year-$month)');
          return const <AttendanceModel>[];
        },
        myAvailability: (uid) async {
          inc('myAvailability');
          seamLog.add('myAvailability(uid=$uid)');
          final n = calls['myAvailability']!;
          final g = Completer<void>();
          availGates.add(g);
          await g.future;
          if (n == 1) throw Exception('LOCAL-S073-AVAILABILITY-FAILURE');
          return WorkerAvailabilityModel(uid: uid, dates: [qKey, uKey], city: '송파구');
        },
        invitePreference: (uid) async {
          inc('invitePreference');
          seamLog.add('invitePreference(uid=$uid)');
          return const InviteRegionPreference(enabled: true, regions: [UserRegion(province: '서울특별시', city: '송파구')]);
        },
      );
  void stubChannels() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMessageHandler(fnChannel, (msg) async {
      final args = (const StandardMessageCodec().decodeMessage(msg) as List).first as Map;
      inc('BLOCKED functions ${args['functionName']}');
      return const StandardMessageCodec().encodeMessage(<Object?>['not-found', 'du67-blocked', <String, Object?>{'code': 'not-found'}]);
    });
    for (final op in const ['documentReferenceGet', 'queryGet', 'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete',
      'writeBatchCommit', 'transactionCreate', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$fsBase.$op', (msg) async {
        inc('BLOCKED firestore $op');
        return null;
      });
    }
  }

  // 실행 전 고정 사전(소스 근거: didChangeDependencies → _loadApplications · initState postFrame → _loadAvailability + _loadInvitePref ·
  //   applications 성공 뒤 Phase2 myMonthlyAttendances · 재시도 = TextButton(onRetry: _loadAvailability) · 같은 월 날짜 탭 = setState 캐시 계산)
  const expectedHeld = {'myApplications': 1, 'myAvailability': 1, 'invitePreference': 1};
  const expectedApps = {...expectedHeld, 'myMonthlyAttendances': 1};
  const expectedFinal = {'myApplications': 1, 'myAvailability': 2, 'invitePreference': 1, 'myMonthlyAttendances': 1};

  for (final c in const [
    (id: 'S073-SCHEDULE-CONFIRMED-AVAILABILITY-FAILURE-RETRY-B', w: 320.0, h: 640.0, s: 2.0),
    (id: 'S073-SCHEDULE-CONFIRMED-AVAILABILITY-FAILURE-RETRY-W', w: 360.0, h: 780.0, s: 1.0),
  ]) {
    testWidgets('${c.id} 일정 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 확정 유지·가능일만 실패→실제 재시도→복구', (t) async {
      await t.runAsync(vqLoadFonts);
      calls.clear();
      appGates.clear();
      availGates.clear();
      seamLog.clear();
      stubChannels();
      final overflows = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        final m = d.exceptionAsString();
        if (m.contains('overflowed')) {
          overflows.add(m.split('\n').first);
          // ignore: avoid_print
          print('OVERFLOW-DETAIL ${d.toString().split('\n').where((l) => l.contains('file:///') || l.contains('overflowed')).take(4).join(' / ')}');
        } else {
          prev?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = prev);
      t.view.physicalSize = Size(c.w, c.h);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      void out(String l) {
        // ignore: avoid_print
        print(l);
      }
      final kStart = DateTime.now().toUtc().add(const Duration(hours: 9));
      out('${c.id} 실행 local=${DateTime.now().toIso8601String()} utc=${DateTime.now().toUtc().toIso8601String()} tz=${now.timeZoneName}(${now.timeZoneOffset}) · KST now=${_kst(DateTime.now())}');
      out('   Q=$qKey(${_kst(qDate)}) U=$uKey(${_kst(uDate)}) · Q 근무 ${appQ.id}/${appQ.toId}/${appQ.workDetailId} 상하차 09:00~13:00 "$kBizName"');
      expect(kQ.month == kNow.month && kU.month == kNow.month, isTrue, reason: 'Q/U 가 같은 표시 월(월 경계면 사전 재고정 필요)');
      expect(DateTime(kStart.year, kStart.month, kStart.day), DateTime(kNow.year, kNow.month, kNow.day));
      final deferred = <String>[];
      final observations = <String>[];
      final key = GlobalKey();
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>(create: (_) => _Worker()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
        ],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: MyScheduleScreen(reads: reads()),
          ),
        ),
      ));
      Future<void> frames([int n = 8]) async {
        for (var i = 0; i < n; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
      }
      bool hits(Finder f, Offset p) {
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
        return hit.path.any((e) => e.target == t.renderObject(f));
      }
      String topHit(Offset p) {
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
        return hit.path.take(4).map((e) => e.target.runtimeType.toString()).join('>');
      }
      String rr(Finder f) {
        final r = t.getRect(f);
        final ok48 = r.width >= 48 && r.height >= 48;
        return '$r(${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} 48=${ok48 ? 'OK' : 'NG'}) centerHit=${hits(f, r.center)} path=${topHit(r.center)}';
      }
      Map<String, int> snap() => Map<String, int>.from(calls);
      Map<String, int> delta(Map<String, int> a) => {
            for (final k in {...a.keys, ...calls.keys})
              if ((calls[k] ?? 0) != (a[k] ?? 0)) k: (calls[k] ?? 0) - (a[k] ?? 0)};
      final screen = find.byType(MyScheduleScreen);
      final cal = find.byType(ScheduleCalendar);
      List<String> texts() => t.widgetList<Text>(find.descendant(of: screen, matching: find.byType(Text)))
          .map((w) => visibleText(w.data ?? w.textSpan?.toPlainText() ?? '')).where((s) => s.trim().isNotEmpty).toList();
      final checking = find.text('근무 가능일을 확인하고 있어요');
      final availFail = find.text('등록한 근무 가능일을 불러오지 못했어요');
      final retryText = find.text('다시 시도');
      final schedLoading = find.text('일정을 불러오고 있어요');
      // 확정 단기 dot(7px 원, 채움) · 가능일 윤곽선(원 테두리, 채움 없음) — schedule_calendar.dart markerBuilder
      final confirmedDot = find.descendant(of: cal, matching: find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        return d is BoxDecoration && d.shape == BoxShape.circle && d.color != null && d.border == null &&
            w.constraints?.maxWidth == 7 && w.constraints?.maxHeight == 7;
      }));
      final availOutline = find.descendant(of: cal, matching: find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        return d is BoxDecoration && d.shape == BoxShape.circle && d.color == null && d.border != null;
      }));
      final card = find.byType(ScheduleCard);
      String cardText() => card.evaluate().isEmpty
          ? '(없음)'
          : t.widgetList<Text>(find.descendant(of: card.first, matching: find.byType(Text)))
              .map((w) => visibleText(w.data ?? w.textSpan?.toPlainText() ?? '')).where((s) => s.trim().isNotEmpty).join(' | ');
      bool hasText(String s) => texts().any((x) => x.contains(s));
      String rendered() => '일정로딩=${schedLoading.evaluate().length} 가능일확인중=${checking.evaluate().length} 가능일실패=${availFail.evaluate().length} 다시시도=${retryText.evaluate().length}'
          ' · 확정dot=${confirmedDot.evaluate().length} 가능일윤곽=${availOutline.evaluate().length} · 카드=${card.evaluate().length}'
          ' · 등록문구=${texts().where((s) => s.contains('일 등록됨')).toList()} · 0일=${hasText('0일')} · 일정없음=${hasText('일정이 없어요')}';
      // 날짜 셀 — 달력 안에서 그 날 숫자 Text(현재 월 행이 먼저 나온다)
      Finder dayCell(DateTime k) => find.descendant(of: cal, matching: find.text('${k.day}')).first;
      Finder scroll() => find.descendant(of: find.descendant(of: screen, matching: find.byType(CustomScrollView)), matching: find.byType(Scrollable)).first;
      bool hasScroll() => find.descendant(of: screen, matching: find.byType(CustomScrollView)).evaluate().isNotEmpty;
      double offset() => hasScroll() ? t.state<ScrollableState>(scroll()).position.pixels : 0;
      Rect vp() => t.getRect(scroll());
      bool inVp(Rect r) => r.top >= vp().top - 0.5 && r.bottom <= vp().bottom + 0.5;
      // [r3] 끌기 시작점은 달력(세로 스와이프로 월 형식을 바꾸는 제스처) 밖이어야 한다 — r2 B 는 viewport 가운데가 달력이라 스크롤 0 에 머물렀다.
      Offset dragPoint() {
        final v = vp();
        final calR = cal.evaluate().isEmpty ? Rect.zero : t.getRect(cal);
        for (final y in [v.bottom - 30, v.top + 30, v.center.dy]) {
          final p = Offset(v.left + 8, y);
          if (!calR.contains(p)) return p;
        }
        return Offset(v.left + 8, v.bottom - 30);
      }
      Future<String> bring(Finder f, String when) async {
        final a = offset();
        for (var k = 0; k < 40 && f.evaluate().isEmpty; k++) {
          final pos = t.state<ScrollableState>(scroll()).position;
          if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
          await t.dragFrom(dragPoint(), const Offset(0, -60));
          await frames(2);
        }
        if (f.evaluate().isEmpty) {
          final pos = t.state<ScrollableState>(scroll()).position;
          final s = '$when 직후 offset=${a.toStringAsFixed(1)} → 끝까지 끌어도 대상 없음(offset=${pos.pixels} max=${pos.maxScrollExtent} viewport=${pos.viewportDimension} vp=${vp()} 선택일카드=${card.evaluate().length})';
          out('   $s');
          return s;
        }
        final r0 = t.getRect(f.first);
        for (var k = 0; k < 60; k++) {
          final r = t.getRect(f.first);
          if (inVp(r)) break;
          final dy = r.top < vp().top ? 60.0 : -60.0;
          await t.dragFrom(dragPoint(), Offset(0, dy));
          await frames(2);
        }
        await frames(2);
        final s = '$when 직후 offset=${a.toStringAsFixed(1)} 대상 $r0 inVp=${inVp(r0)} → 끌기 뒤 offset=${offset().toStringAsFixed(1)} 대상 ${t.getRect(f.first)} inVp=${inVp(t.getRect(f.first))}';
        out('   $s');
        return s;
      }
      // 맨 위로 — 남은 offset 이하로만 끌어 RefreshIndicator(onRefresh=_loadApplications)를 깨우지 않는다(추가 read 금지)
      Future<void> toTop() async {
        for (var k = 0; k < 60; k++) {
          final o = offset();
          if (o <= 0.5) break;
          await t.dragFrom(dragPoint(), Offset(0, o < 80 ? o : 80));
          await frames(2);
        }
        await frames(2);
      }
      Map<String, Object?> cond(String state) {
        final m = MediaQuery.of(t.element(screen));
        return {
          'entry': 'LOCAL MaterialApp(home: MyScheduleScreen(reads: LOCAL MyScheduleReads)) 단독 화면 · USER · UserRoot shell 미사용',
          'theme': 'RoleTheme.workerTheme', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
          'mqNow': 'size=${m.size} padding=${m.padding} viewPadding=${m.viewPadding} viewInsets=${m.viewInsets}',
          'physicalInsetBottomNow': t.view.viewInsets.bottom,
          'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · initializeDateFormatting(ko_KR)', 'prefs': 'setMockInitialValues({})',
          'clock': '미주입(KST ${_kst(DateTime.now())})',
          'fixture': 'uid $kUid · Q=$qKey 확정 단기 ${appQ.id}/${appQ.toId}/${appQ.slotId}/${appQ.workDetailId} 상하차 09:00~13:00 "$kBizName" · U=$uKey 근무 0',
          'seam': 'myApplications#1 gate→[Q] · myMonthlyAttendances 즉시 [] · myAvailability#1 gate→throw LOCAL-S073-AVAILABILITY-FAILURE · #2 gate→{$qKey,$uKey} · invitePreference 즉시 ON(서울특별시 송파구)',
          'gates': 'applications=${appGates.map((g) => g.isCompleted).toList()} availability=${availGates.map((g) => g.isCompleted).toList()}',
          'state': state, 'calls': calls.toString()};
      }

      // [후속68] 카드 식별·근무 정보의 **실제 가시성** — 원문 Text 존재만으로 통과시키지 않는다.
      //   사업장·업무·예정시간·상태·임금 각 RenderParagraph 의 didExceedMaxLines(말줄임)와 rect 가 카드·viewport 안인지 잰다.
      String cardVis(String when) {
        final parts = <String>[];
        final cr = t.getRect(card.first);
        for (final e in [
          (label: '사업장', text: kBizName),
          (label: '업무', text: '상하차'),
          (label: '예정시간', text: '09:00~13:00'),
          (label: '상태', text: '확정'),
          (label: '임금', text: '12,000원 (시급)'),
        ]) {
          final f = find.descendant(of: card.first, matching: find.byWidgetPredicate((w) => w is Text && visibleText(w.data ?? w.textSpan?.toPlainText() ?? '') == e.text));
          if (f.evaluate().isEmpty) {
            deferred.add('$when 카드 ${e.label} "${e.text}" Text 없음');
            parts.add('${e.label}=없음');
            continue;
          }
          final p = t.renderObject<RenderParagraph>(f.first);
          final r = t.getRect(f.first);
          final inCard = r.left >= cr.left - 0.5 && r.right <= cr.right + 0.5 && r.top >= cr.top - 0.5 && r.bottom <= cr.bottom + 0.5;
          parts.add('${e.label}: lines=${_lines(p)} didExceedMaxLines=${p.didExceedMaxLines} rect=$r inCard=$inCard inVp=${inVp(r)}');
          if (p.didExceedMaxLines) deferred.add('$when 카드 ${e.label} "${e.text}" 말줄임(didExceedMaxLines=true)');
          if (!inCard || !inVp(r)) deferred.add('$when 카드 ${e.label} 가 카드/viewport 밖(rect=$r card=$cr)');
        }
        final s = '카드 rect=$cr inVp=${inVp(cr)} · ${parts.join(' · ')}';
        out('   $when 카드 가시성 $s');
        if (!inVp(cr)) deferred.add('$when 카드 전체가 viewport 밖');
        return s;
      }
      // ── ① 최초: applications·availability 보류 ──
      await frames(6);
      out('① 최초 calls=$calls · 그림 ${rendered()}');
      expect(calls, expectedHeld, reason: 'applications-held 3');
      expect(schedLoading, findsOneWidget, reason: '일정 로딩(body 전체)');
      await vqCapture(t, key, '${c.id}_1_held', conditions: cond('applications·availability 보류 · ${rendered()}'));

      // ── ② applications 정상 → 월 근태 empty · 가능일 아직 보류 ──
      appGates[0].complete();
      await frames(10);
      out('② applications 해제 · calls=$calls · 그림 ${rendered()}');
      expect(calls, expectedApps, reason: '+monthlyAttendances = 4');
      expect(checking, findsOneWidget, reason: '가능일 확인 중');
      expect(hasText('일 등록됨'), isFalse, reason: '보류 중 등록 n일(0일 포함) 주장 없음');
      expect(confirmedDot, findsOneWidget, reason: 'Q 확정 dot');
      expect(availOutline, findsNothing, reason: '가능일 모름 — 윤곽 없음');
      // 실제 Q 탭
      final qCell = dayCell(kQ);
      out('   Q 셀 ${rr(qCell)}');
      final qr = t.getRect(qCell);
      if (qr.width < 48 || qr.height < 48) observations.add('날짜 셀 Q ${qr.width.toStringAsFixed(1)}×${qr.height.toStringAsFixed(1)} < 48(달력 셀 — 이번 판정 대상 아님·기록)');
      final b0 = snap();
      await t.tapAt(qr.center);
      await frames(6);
      expect(delta(b0), isEmpty, reason: '같은 월 날짜 탭 추가 read 0');
      final cb = await bring(card, '② Q 카드');
      out('   Q 카드="${cardText()}"');
      final v2 = cardVis('② Q');
      expect(cardText(), contains(kBizName));
      expect(cardText(), contains('상하차'));
      expect(cardText(), contains('09:00'));
      await vqCapture(t, key, '${c.id}_2_q_card', conditions: cond('applications 정상 · 가능일 보류 · Q 탭 · $cb · 카드="${cardText()}" · $v2 · ${rendered()}'));
      await toTop(); // 맨 위로 실제 끌기(당겨서 새로고침이 걸리지 않게 남은 offset 만큼만)
      await frames(4);
      final ch = await bring(checking, '② 가능일 확인중');
      await vqCapture(t, key, '${c.id}_2_checking', conditions: cond('가능일 보류 · $ch · ${rendered()}'));

      // ── ③ availability#1 명시 실패 ──
      final b1 = snap();
      availGates[0].complete();
      await frames(10);
      out('③ availability#1 실패 · delta=${delta(b1)} · 그림 ${rendered()}');
      expect(delta(b1), isEmpty);
      expect(confirmedDot, findsOneWidget, reason: '확정 dot 유지');
      expect(availOutline, findsNothing, reason: '실패 — 윤곽 없음(0일 확정 아님)');
      expect(hasText('일 등록됨'), isFalse, reason: '실패를 0일/미등록으로 확정하지 않는다');
      final fb = await bring(availFail, '③ 가능일 실패');
      expect(availFail, findsOneWidget);
      final failP = t.renderObject<RenderParagraph>(availFail);
      final retryBtn = find.ancestor(of: retryText, matching: find.byType(TextButton)).first;
      final rb = await bring(retryBtn, '③ 다시 시도');
      final retryR = t.getRect(retryBtn);
      out('   실패 문구 lines=${_lines(failP)} didExceedMaxLines=${failP.didExceedMaxLines} rect=${t.getRect(availFail)} inVp=${inVp(t.getRect(availFail))}');
      out('   다시 시도 TextButton ${rr(retryBtn)} · 글 ${t.getRect(retryText)} · inVp=${inVp(retryR)}');
      if (retryR.width < 48 || retryR.height < 48) deferred.add('가능일 다시 시도 터치 ${retryR.width.toStringAsFixed(1)}×${retryR.height.toStringAsFixed(1)} < 48');
      if (!hits(retryBtn, retryR.center)) deferred.add('가능일 다시 시도 중심 hit 실패');
      if (failP.didExceedMaxLines) deferred.add('가능일 실패 문구 말줄임');
      expect(inVp(retryR), isTrue);
      await vqCapture(t, key, '${c.id}_3_failure', conditions: cond('availability#1 실패 · $fb · $rb · 다시시도 ${rr(retryBtn)} · ${rendered()}'));
      final cq = await bring(card, '③ Q 카드 유지');
      expect(cardText(), contains(kBizName), reason: '가능일 실패에 확정 카드 영향 없음');
      final v3 = cardVis('③ Q');
      await vqCapture(t, key, '${c.id}_3_q_card', conditions: cond('availability#1 실패 · Q 카드 유지 · $cq · $v3'));

      // ── ④ 다시 시도 실제 중심 1회 → availability#2 보류 ──
      await toTop(); // 맨 위로 실제 끌기(당겨서 새로고침이 걸리지 않게 남은 offset 만큼만)
      await frames(4);
      await bring(retryBtn, '④ 재시도 직전');
      final tapR = t.getRect(retryBtn);
      final b2 = snap();
      await t.tapAt(tapR.center);
      await frames(6);
      out('④ 다시 시도 · delta=${delta(b2)} · 그림 ${rendered()}');
      expect(delta(b2), {'myAvailability': 1}, reason: '재시도 = availability 1');
      expect(availGates.length, 2);
      // 현재 소스: hadValue=false → loading 으로 돌아간다(감사67 §5.5 소스상 기대)
      if (checking.evaluate().isEmpty) deferred.add('재시도 보류 중 확인 중 표시 없음');
      if (availFail.evaluate().isNotEmpty) observations.add('재시도 보류 중 실패 안내 유지');
      expect(hasText('일 등록됨'), isFalse);
      expect(confirmedDot, findsOneWidget);
      final hh = await bring(checking.evaluate().isNotEmpty ? checking : availFail, '④ 재시도 보류');
      await vqCapture(t, key, '${c.id}_4_retry_held', conditions: cond('availability#2 보류 · $hh · ${rendered()}'));

      // ── ⑤ availability#2 정상 {Q,U} ──
      final b3 = snap();
      availGates[1].complete();
      await frames(10);
      out('⑤ availability#2 정상 · delta=${delta(b3)} · 그림 ${rendered()}');
      expect(delta(b3), isEmpty);
      expect(availFail, findsNothing, reason: '실패 안내 제거');
      expect(checking, findsNothing);
      expect(hasText('근무 가능일 2일 등록됨'), isTrue, reason: '가능일 2일');
      expect(availOutline, findsNWidgets(2), reason: 'Q·U 윤곽선');
      expect(confirmedDot, findsOneWidget, reason: 'Q 확정 dot 유지');
      expect(hasText('근무 가능일'), isTrue, reason: '범례');
      final okb = await bring(find.text('근무 가능일 2일 등록됨'), '⑤ 가능일 2일');
      await vqCapture(t, key, '${c.id}_5_recovered', conditions: cond('availability#2 정상 · $okb · ${rendered()}'));
      final cq2 = await bring(card, '⑤ Q 카드');
      expect(cardText(), contains(kBizName));
      await vqCapture(t, key, '${c.id}_5_q_card', conditions: cond('복구 · Q 카드 · $cq2 · ${cardVis('⑤ Q')}'));

      // ── ⑥ U 실제 탭 → 윤곽 있음·근무 없음 · Q 복귀 ──
      await toTop(); // 맨 위로 실제 끌기(당겨서 새로고침이 걸리지 않게 남은 offset 만큼만)
      await frames(4);
      final uCell = dayCell(kU);
      await bring(uCell, '⑥ U 셀');
      out('   U 셀 ${rr(uCell)}');
      final ur = t.getRect(uCell);
      if (ur.width < 48 || ur.height < 48) observations.add('날짜 셀 U ${ur.width.toStringAsFixed(1)}×${ur.height.toStringAsFixed(1)} < 48(달력 셀 — 이번 판정 대상 아님·기록)');
      final b4 = snap();
      await t.tapAt(ur.center);
      await frames(6);
      expect(delta(b4), isEmpty, reason: '같은 월 날짜 탭 추가 read 0');
      out('⑥ U 탭 · 그림 ${rendered()}');
      expect(card, findsNothing, reason: 'U 근무 카드 없음');
      expect(availOutline, findsNWidgets(2));
      expect(confirmedDot, findsOneWidget, reason: '확정 dot 은 Q 에만');
      final ue = find.descendant(of: screen, matching: findVisibleTextContaining('일정이 없어요')); // [r2] 제목에 줄바꿈 제어 문자(TextLayout) — 보이는 글자로 비교
      final ub = await bring(ue, '⑥ U 일정 없음');
      expect(ue, findsOneWidget, reason: 'U 정상 일정 없음');
      await vqCapture(t, key, '${c.id}_6_u_selected', conditions: cond('U 선택 · $ub · ${rendered()}'));
      await toTop(); // 맨 위로 실제 끌기(당겨서 새로고침이 걸리지 않게 남은 offset 만큼만)
      await frames(4);
      final qCell2 = dayCell(kQ);
      await bring(qCell2, '⑥ Q 셀 복귀');
      final b5 = snap();
      await t.tapAt(t.getRect(qCell2).center);
      await frames(6);
      expect(delta(b5), isEmpty);
      final cq3 = await bring(card, '⑥ Q 복귀 카드');
      expect(cardText(), contains(kBizName));
      await vqCapture(t, key, '${c.id}_6_q_back', conditions: cond('Q 복귀 · $cq3 · ${cardVis('⑥ Q 복귀')} · ${rendered()}'));

      // ── 종료선 ──
      await frames(10);
      final kEnd = DateTime.now().toUtc().add(const Duration(hours: 9));
      expect(DateTime(kEnd.year, kEnd.month, kEnd.day), DateTime(kNow.year, kNow.month, kNow.day), reason: '종료까지 같은 KST 일자');
      out('최종 calls=$calls · seam=$seamLog · KST 종료=${_kst(DateTime.now())}');
      expect(calls, expectedFinal, reason: '최종 논리 seam 5 · 채널 차단 0');
      expect(appGates.every((g) => g.isCompleted) && availGates.every((g) => g.isCompleted), isTrue);
      FlutterError.onError = prev;
      out('observations(${observations.length})=${observations.join(' | ')}');
      out('overflows(${overflows.length})=${overflows.join(' | ')}');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
      expect(t.takeException(), isNull);
      out('deferred(${deferred.length})=${deferred.join(' | ')}');
      expect(deferred, isEmpty, reason: deferred.join(' | '));
    });
  }
}
