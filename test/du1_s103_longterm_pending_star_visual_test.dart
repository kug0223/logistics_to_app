// ignore_for_file: depend_on_referenced_packages
// [DU1 후속103 C103-1] 장기 대기별 실제 관측 — 장기 pending 은 희망 시작일(desiredStartDate ?? workDate) 하루에만 별로 보인다.
//   출발·조건은 S101/S102 와 같다: production MyScheduleScreen(reads: LOCAL MyScheduleReads) 단독 화면 · USER · workerTheme ·
//     W360×780@1.0(DU1_S101_DPR=3 이면 같은 논리 크기 DPR3) · inset0 · prefs {} · vqLoadFonts. UserRoot 자연 진입이 아니다.
//   시계 미주입(DateTime.now) — 실행 KST 날짜·호스트 시간대를 conditions 에 기록한다.
//   fixture(LOCAL 주입, 새 DEV fixture 아님 — 기존 ApplicationModel 생성자):
//     X=+1 장기 대기(희망 시작일 X, 기간 X~+20 매일) + 가능일 X · C=+2 장기 확정 근무일 · V=+3 같은 장기 확정의 휴무일 · P=+4 단기 대기
//   장면: ① 첫 화면(초기 선택=오늘, 표식 없음) ② C 실제 탭 ③ X 실제 탭 ④ 실제 drag 로 X 날짜 카드 ⑤ 실제 drag 로 맨 위 → `대기` 필터 칩 실제 탭.
//   날짜·칩 탭은 화면 상태만 바꾼다. 쓰기 채널 차단·계수 0. 표식 색·rect·그림자 유무는 출력 관찰이고,
//   단언은 필터별 표식 개수·IgnorePointer·선택 이동·윤곽 개수·overflow 0 처럼 before/after 공통 계약만 둔다.
import 'dart:io';
import 'dart:ui' as ui;

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

const kUid = 'worker-local-c103';
const kBizName = 'QA 송파 물류센터';

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

String _hex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
String _r(Rect r) => '${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)} ${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)}';

void main() {
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  const fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  final kNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  // 단기 workDate = KST 자정 instant(S073 과 같은 방식)
  DateTime kstMidnight(int plus) => DateTime.utc(kNow.year, kNow.month, kNow.day + plus).subtract(const Duration(hours: 9));
  // 장기 기간 = 기기 local 날짜(Firestore Timestamp 가 local DateTime 으로 오는 production 과 같은 형). 호스트 시간대를 기록한다.
  DateTime localDay(int plus) => DateTime(kNow.year, kNow.month, kNow.day + plus);
  DateTime kDay(int plus) => DateTime.utc(kNow.year, kNow.month, kNow.day + plus);
  final dT = kDay(0), dX = kDay(1), dC = kDay(2), dV = kDay(3), dP = kDay(4);
  String keyOf(int plus) => WorkerAvailabilityModel.dateKeyFrom(kstMidnight(plus));
  final apps = [
    ApplicationModel(
      id: 'app-c103-lp', toId: 'to-c103-lp', uid: kUid, applicantName: 'QA 근로자', businessId: 'biz-c103', businessName: kBizName,
      toTitle: 'QA 장기 대기', status: AppStatus.pending, selectedWorkType: '피킹', startTime: '09:00', endTime: '18:00',
      wage: 12000, wageType: 'hourly', applicationType: AppType.longTerm,
      workDays: const ['월', '화', '수', '목', '금', '토', '일'],
      workDate: localDay(1), desiredStartDate: localDay(1), workEndDate: localDay(20), appliedAt: localDay(-2),
    ),
    ApplicationModel(
      id: 'app-c103-lc', toId: 'to-c103-lc', uid: kUid, applicantName: 'QA 근로자', businessId: 'biz-c103', businessName: kBizName,
      toTitle: 'QA 장기 확정', status: AppStatus.confirmed, selectedWorkType: '상하차', startTime: '09:00', endTime: '18:00',
      wage: 12000, wageType: 'hourly', applicationType: AppType.longTerm,
      workDays: const ['월', '화', '수', '목', '금', '토', '일'],
      workDate: localDay(2), workEndDate: localDay(3), leaveDates: [localDay(3)], appliedAt: localDay(-10),
    ),
    ApplicationModel(
      id: 'app-c103-sp', toId: 'to-c103-sp', slotId: 'slot-c103-sp', workDetailId: 'wd-c103-sp', uid: kUid,
      applicantName: 'QA 근로자', businessId: 'biz-c103', businessName: kBizName, toTitle: 'QA 단기 대기', status: AppStatus.pending,
      selectedWorkType: '상하차', startTime: '09:00', endTime: '13:00', wage: 12000, wageType: 'hourly',
      workDate: kstMidnight(4), appliedAt: kstMidnight(4).subtract(const Duration(days: 3)),
    ),
  ];
  final calls = <String, int>{};
  void inc(String k) => calls[k] = (calls[k] ?? 0) + 1;
  MyScheduleReads reads() => MyScheduleReads(
        myApplications: (uid) async {
          inc('myApplications');
          return apps;
        },
        myMonthlyAttendances: ({required String userId, required int year, required int month}) async {
          inc('myMonthlyAttendances');
          return const <AttendanceModel>[];
        },
        myAvailability: (uid) async {
          inc('myAvailability');
          return WorkerAvailabilityModel(uid: uid, dates: [keyOf(1)], city: '송파구');
        },
        invitePreference: (uid) async {
          inc('invitePreference');
          return const InviteRegionPreference(enabled: true, regions: [UserRegion(province: '서울특별시', city: '송파구')]);
        },
      );

  testWidgets('S103-N 일정 장기 대기별 360×780@1.0 — 미선택·선택·카드·대기 필터 × 장기 확정/휴무/단기 대기/가능일', (t) async {
    await t.runAsync(vqLoadFonts);
    calls.clear();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMessageHandler(fnChannel, (msg) async {
      inc('BLOCKED functions');
      return const StandardMessageCodec().encodeMessage(<Object?>['not-found', 'blocked', <String, Object?>{'code': 'not-found'}]);
    });
    for (final op in const ['documentReferenceGet', 'queryGet', 'documentReferenceSet', 'documentReferenceUpdate',
      'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$fsBase.$op', (msg) async {
        inc('BLOCKED firestore $op');
        return null;
      });
    }
    final overflows = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final s = d.exceptionAsString();
      if (s.contains('overflowed')) {
        overflows.add(s.split('\n').first);
      } else {
        prev?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prev);
    final key0 = GlobalKey();
    // 기본 DPR1(S073 과 같은 V 조건). DU1_S101_DPR=3 이면 같은 논리 크기 360×780 을 DPR3 로 그려 3배 PNG 로 남긴다
    //   (얇은 테두리·숫자 간격의 기하 측정 보조 — 실기기 아님).
    final dpr = double.tryParse(Platform.environment['DU1_S101_DPR'] ?? '') ?? 1.0;
    t.view.physicalSize = Size(360 * dpr, 780 * dpr);
    t.view.devicePixelRatio = dpr;
    addTearDown(t.view.reset);
    Future<void> cap(String id, Map<String, Object?> c) async {
      if (dpr == 1.0) return vqCapture(t, key0, id, conditions: c);
      if (!vqEnabled) return;
      final dir = vqOutDir..createSync(recursive: true);
      final out = File('${dir.path}/${id}_dpr${dpr.toStringAsFixed(0)}.png');
      final rj = File('${dir.path}/${id}_dpr${dpr.toStringAsFixed(0)}.run.txt');
      if (out.existsSync() || rj.existsSync()) throw StateError('이미 있는 캡처를 덮지 않는다: ${out.path}');
      final b = key0.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final img = await b.toImage(pixelRatio: dpr);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        out.writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      rj.writeAsStringSync({...c, 'dpr': dpr, 'capturePixelRatio': dpr}.entries.map((e) => '${e.key}=${e.value}').join('\n'));
    }
    expect(dP.month == dT.month, isTrue, reason: 'T~P 같은 표시 월');
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key0,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: RoleTheme.workerTheme,
          builder: (ctx, child) =>
              MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)), child: child!),
          home: MyScheduleScreen(reads: reads()),
        ),
      ),
    ));
    Future<void> frames([int n = 8]) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await frames(12);
    final cal = find.byType(ScheduleCalendar);
    expect(cal, findsOneWidget);
    final days = <String, DateTime>{'T': dT, 'X': dX, 'C': dC, 'V': dV, 'P': dP};
    Finder digit(DateTime d) => find.descendant(of: cal, matching: find.text('${d.day}')).first;
    final calRect = t.getRect(cal);

    // 표식: 달력 안 지름 6~8 의 채운 원 Container(점) + Icons.star(별). 각 표식을 가장 가까운 날짜 열에 붙인다.
    Map<String, List<String>> markers() {
      final byDay = <String, List<String>>{for (final k in days.keys) k: []};
      final cols = {for (final e in days.entries) e.key: t.getRect(digit(e.value))};
      String? owner(Rect r) {
        for (final e in cols.entries) {
          final c = e.value;
          if ((r.center.dx - c.center.dx).abs() < 24 && r.top > c.top - 4 && r.top < c.bottom + 20) return e.key;
        }
        return null;
      }

      for (final e in find.descendant(of: cal, matching: find.byType(Container)).evaluate()) {
        final c = e.widget as Container;
        final d = c.decoration;
        if (d is! BoxDecoration || d.shape != BoxShape.circle || d.color == null) continue;
        // Container rect 는 margin 을 포함한다 — 칠해지는 원(decoration) 크기로 줄여 잰다
        final outer = t.getRect(find.byWidget(c));
        final r = c.margin == null ? outer : c.margin!.resolve(TextDirection.ltr).deflateRect(outer);
        if (r.width < 6 || r.width > 8) continue;
        final o = owner(r);
        if (o == null) continue;
        final ig = e.findAncestorWidgetOfExactType<IgnorePointer>();
        final sh = d.boxShadow == null || d.boxShadow!.isEmpty
            ? 'shadow 0'
            : 'shadow ${d.boxShadow!.map((b) => '${_hex(b.color)} spread ${b.spreadRadius} blur ${b.blurRadius}').join('/')}';
        byDay[o]!.add('점 ${_r(r)} ${_hex(d.color!)} $sh ignore=${ig?.ignoring}');
      }
      for (final e in find.descendant(of: cal, matching: find.byIcon(Icons.star)).evaluate()) {
        final ic = e.widget as Icon;
        final r = t.getRect(find.byWidget(ic));
        final o = owner(r);
        if (o == null) continue;
        final ig = e.findAncestorWidgetOfExactType<IgnorePointer>();
        byDay[o]!.add('별 ${_r(r)} ${_hex(ic.color!)} shadows ${ic.shadows?.length ?? 0}${ic.shadows == null || ic.shadows!.isEmpty ? '' : ' ${_hex(ic.shadows!.first.color)}'} ignore=${ig?.ignoring}');
      }
      return byDay;
    }

    // 가능일 윤곽: 달력 안 border 있는 원 Container
    List<String> outlines() {
      final out = <String>[];
      for (final e in find.descendant(of: cal, matching: find.byType(Container)).evaluate()) {
        final c = e.widget as Container;
        final d = c.decoration;
        if (d is! BoxDecoration || d.shape != BoxShape.circle || d.border == null) continue;
        final b = d.border as Border;
        out.add('윤곽 ${_r(t.getRect(find.byWidget(c)))} ${_hex(b.top.color)} w${b.top.width}');
      }
      return out;
    }

    final log = <String>[];
    Map<String, Object?> cond(String scene) {
      final mk = markers();
      final line = [for (final e in mk.entries) '${e.key}(${days[e.key]!.month}/${days[e.key]!.day} 숫자 ${_r(t.getRect(digit(days[e.key]!)))}): ${e.value.join(' ; ')}'];
      log.add('[$scene] ${line.join(' | ')} | ${outlines().join(' ; ')}');
      return {
        'entry': 'LOCAL MaterialApp(home: MyScheduleScreen(reads: LOCAL MyScheduleReads)) 단독 · USER · UserRoot 미사용',
        'theme': 'RoleTheme.workerTheme', 'viewport': '360x780', 'dpr': 1.0, 'textScaler': 1.0, 'inset': 0,
        'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) — 기기 글꼴 아님', 'prefs': '{}',
        'clock': '미주입 — 실행 KST ${kNow.toIso8601String().substring(0, 16)} · host tz ${DateTime.now().timeZoneName} ${DateTime.now().timeZoneOffset}',
        'fixture': '장기 대기 X=${keyOf(1)}(희망 시작일·기간 ~+20 매일) · 장기 확정 C=${keyOf(2)}~V=${keyOf(3)}(V 휴무) · 단기 대기 P=${keyOf(4)} · 가능일 {X=${keyOf(1)}} · 초대 ON 송파구 · 월근태 []',
        'calendar': _r(calRect), 'scene': scene, 'markers': line.join(' | '), 'outlines': outlines().join(' ; '),
        'calls': calls.toString(), 'overflows': overflows.length,
      };
    }

    // 필터별 표식 계약(before/after 공통). 전체: X 별1 · C 별1 · V 별1 · P 점1 · T 0. 대기: X 별1 · P 점1 · C/V/T 0.
    void contracts(String scene, {bool pendingOnly = false}) {
      final mk = markers();
      int stars(String k) => mk[k]!.where((s) => s.startsWith('별')).length;
      int dots(String k) => mk[k]!.where((s) => s.startsWith('점')).length;
      expect(stars('X'), 1, reason: '$scene X 장기 대기 별 1: ${mk['X']}');
      expect(dots('X'), 0, reason: '$scene X 점 0: ${mk['X']}');
      expect(dots('P'), 1, reason: '$scene P 단기 대기 점 1: ${mk['P']}');
      expect(stars('C'), pendingOnly ? 0 : 1, reason: '$scene C 장기 확정 별: ${mk['C']}');
      expect(stars('V'), pendingOnly ? 0 : 1, reason: '$scene V 휴무 별: ${mk['V']}');
      expect(mk['T']!, isEmpty, reason: '$scene T 표식 없음: ${mk['T']}');
      for (final v in mk.values.expand((x) => x)) {
        expect(v.endsWith('ignore=true'), isTrue, reason: '$scene 표식은 IgnorePointer 안: $v');
      }
      // 가능일 윤곽 1개(X) — 필터와 무관
      expect(outlines().length, 1, reason: '$scene 가능일 윤곽 X: ${outlines()}');
    }

    Color? digitColor(String k) => t.widget<Text>(digit(days[k]!)).style?.color;
    Future<void> tapDay(String k) async {
      final c = t.getRect(digit(days[k]!)).center;
      await t.tapAt(c);
      await frames(6);
      // 선택 계약: 숫자 중심 실제 탭 → 그 날이 선택(selectedTextStyle 흰 글자), 오늘 T 는 today 글자색(primary)으로 남는다
      expect(digitColor(k), Colors.white, reason: '$k 선택');
      expect(digitColor('T'), isNot(Colors.white), reason: '$k 탭 뒤 T 는 미선택 오늘');
    }

    // ① 첫 화면 — 초기 선택=오늘 T
    expect(calls, {'myApplications': 1, 'myMonthlyAttendances': 1, 'myAvailability': 1, 'invitePreference': 1});
    contracts('first');
    expect(digitColor('T'), Colors.white, reason: '초기 선택 = 오늘 T');
    await cap('S103-N_1_first', cond('첫 화면 · 초기 선택일 KST 오늘 T(표식 없음) · 필터 전체'));
    await tapDay('C');
    contracts('tap C');
    await cap('S103-N_2_C_selected', cond('C(장기 확정 근무일) 실제 탭 뒤 · X 는 미선택(장기 대기별+가능일)'));
    await tapDay('X');
    contracts('tap X');
    await cap('S103-N_3_X_selected', cond('X(장기 대기별+가능일) 실제 탭 뒤'));
    // ④ 실제 drag(달력 밖 왼쪽 여백)로 X 날짜 카드까지
    final screen = find.byType(MyScheduleScreen);
    final cardF = find.byType(ScheduleCard);
    Finder scroll() => find
        .descendant(of: find.descendant(of: screen, matching: find.byType(CustomScrollView)), matching: find.byType(Scrollable))
        .first;
    final vp = t.getRect(scroll());
    var k = 0;
    for (; k < 40; k++) {
      if (cardF.evaluate().isNotEmpty && t.getRect(cardF.first).bottom <= vp.bottom - 8) break;
      final pos = t.state<ScrollableState>(scroll()).position;
      if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
      await t.dragFrom(Offset(vp.left + 8, vp.bottom - 30), const Offset(0, -60));
      await frames(2);
    }
    await frames(4);
    expect(cardF, findsWidgets, reason: 'X 카드');
    final cardTexts = find.descendant(of: cardF.first, matching: find.byType(Text)).evaluate()
        .map((e) => (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText() ?? '').where((s) => s.isNotEmpty).join(' / ');
    log.add('[X 카드] drag $k회 off ${t.state<ScrollableState>(scroll()).position.pixels.toStringAsFixed(1)} · 카드 ${t.getRect(cardF.first)} · 글자: $cardTexts');
    await cap('S103-N_4_X_card', {...cond('X 탭 뒤 실제 drag $k회로 X 날짜 카드'), 'card': cardTexts});
    // ⑤ 실제 drag 로 맨 위 → `대기` 필터 칩 실제 탭(화면 상태만)
    for (var j = 0; j < 40 && t.state<ScrollableState>(scroll()).position.pixels > 0.5; j++) {
      await t.dragFrom(Offset(vp.left + 8, vp.bottom - 150), const Offset(0, 120)); // 달력(세로 제스처) 밖 아래쪽에서 시작
      await frames(2);
    }
    await frames(4);
    expect(t.state<ScrollableState>(scroll()).position.pixels, lessThan(0.5), reason: '맨 위로 되돌림');
    final allTop = t.getRect(find.text('전체').first).top;
    final chip = find.text('대기').evaluate().map((e) => find.byWidget(e.widget)).firstWhere((f) => (t.getRect(f).top - allTop).abs() <= 2);
    await t.tapAt(t.getRect(chip).center);
    await frames(6);
    contracts('filter 대기', pendingOnly: true);
    await cap('S103-N_5_filter_pending', cond('맨 위로 실제 drag 뒤 `대기` 필터 칩 실제 탭 · 선택일 X 유지'));
    for (final l in log) {
      // ignore: avoid_print
      print('S103 $l');
    }
    expect(overflows, isEmpty);
    expect(calls.keys.where((k) => k.startsWith('BLOCKED')), isEmpty, reason: '쓰기·원격 채널 0');
    expect(t.takeException(), isNull);
  });
}
