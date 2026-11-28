// ignore_for_file: depend_on_referenced_packages
// [DU1 후속102 C102-1] 장기 근무별 대표 — 오늘·선택·가능일과 겹치는 장기 확정 근무일 별, 같은 근무의 휴무일 별.
//   출발·조건은 S101 과 같다: production MyScheduleScreen(reads: LOCAL MyScheduleReads) 단독 화면 · USER · workerTheme ·
//     W360×780@1.0(DU1_S101_DPR=3 이면 같은 논리 크기 DPR3) · inset0 · prefs {} · vqLoadFonts. UserRoot 자연 진입이 아니다.
//   시계 미주입(DateTime.now) — 실행 KST 날짜·호스트 시간대를 conditions 에 기록한다.
//   fixture(LOCAL 주입, 새 DEV fixture 아님 — 기존 ApplicationModel 생성자):
//     장기 확정 1건(매일 근무) 기간 T=오늘 ~ E=+3, 휴무일 V=+2 · 가능일 {A=+1}
//     → T 장기별+오늘 · A 장기별+가능일 윤곽 · V 휴무별 · E 장기별만.
//   장면: ① 첫 화면(초기 선택=오늘 T) ② A 실제 탭(T 는 오늘 연한 채움) ③ E 탭(A 는 미선택 윤곽+별).
//   날짜 탭은 화면 상태(선택일)만 바꾼다. 쓰기 채널 차단·계수 0. 표식 색·rect·그림자 유무는 출력 관찰이고,
//   단언은 개수·IgnorePointer·선택 이동·윤곽 개수·overflow 0 처럼 before/after 공통 계약만 둔다.
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

const kUid = 'worker-local-c102';
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
  final dT = kDay(0), dA = kDay(1), dV = kDay(2), dE = kDay(3);
  String keyOf(int plus) => WorkerAvailabilityModel.dateKeyFrom(kstMidnight(plus));
  final apps = [
    ApplicationModel(
      id: 'app-c102-l', toId: 'to-c102-l', uid: kUid, applicantName: 'QA 근로자', businessId: 'biz-c102', businessName: kBizName,
      toTitle: 'QA 장기', status: AppStatus.confirmed, selectedWorkType: '상하차', startTime: '09:00', endTime: '18:00',
      wage: 12000, wageType: 'hourly', applicationType: AppType.longTerm,
      workDays: const ['월', '화', '수', '목', '금', '토', '일'],
      workDate: localDay(0), workEndDate: localDay(3), leaveDates: [localDay(2)], appliedAt: localDay(-10),
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

  testWidgets('S102-N 일정 장기 근무별 360×780@1.0 — 오늘·선택·가능일 × 장기별 · 휴무별', (t) async {
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
    // [impl_63 · 날짜 의존] 오늘(T)~E(오늘+3)가 한 달 안에 있어야 같은 표시월 달력에서 표식을 잰다. 오늘은 화면이 기기 시계로 정하므로
    //   (제품 시계 주입 없음 · 제품 코드 0) 월말 3일 구간에서는 이 조건을 만들 수 없다 — 실패가 아니라 생략으로 기록한다
    //   (같은 꼴 선례: du1_c1_create_failure_toast_test '그 달 마지막 날').  11-28 전체 대사에서 이 단언이 날짜로만 실패했다(impl_62).
    if (dE.month != dT.month) {
      markTestSkipped('월말 — 오늘~오늘+3 이 같은 표시 월이 아니다(T=${dT.day}일 · E=${dE.month}/${dE.day})');
      return;
    }
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
    final days = <String, DateTime>{'T': dT, 'A': dA, 'V': dV, 'E': dE};
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
        'fixture': '장기 확정 1건(매일) T=${keyOf(0)}~E=${keyOf(3)} · 휴무 V=${keyOf(2)} · 가능일 {A=${keyOf(1)}} · 초대 ON 송파구 · 월근태 []',
        'calendar': _r(calRect), 'scene': scene, 'markers': line.join(' | '), 'outlines': outlines().join(' ; '),
        'calls': calls.toString(), 'overflows': overflows.length,
      };
    }

    void contracts(String scene) {
      final mk = markers();
      // 표식 개수·종류 계약(before/after 공통): T·A·V·E 별 1개씩(점 0), 모두 IgnorePointer(ignoring) 안
      for (final k in ['T', 'A', 'V', 'E']) {
        expect(mk[k]!.where((s) => s.startsWith('별')).length, 1, reason: '$scene $k 별 1개: ${mk[k]}');
        expect(mk[k]!.where((s) => s.startsWith('점')).length, 0, reason: '$scene $k 점 0개: ${mk[k]}');
      }
      for (final v in mk.values.expand((x) => x)) {
        expect(v.endsWith('ignore=true'), isTrue, reason: '$scene 표식은 IgnorePointer 안: $v');
      }
      // 가능일 윤곽 1개(A)
      expect(outlines().length, 1, reason: '$scene 가능일 윤곽 A: ${outlines()}');
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
    await cap('S102-N_1_first', cond('첫 화면 · 초기 선택일 KST 오늘 T(장기별)'));
    var n = 2;
    for (final k in ['A', 'E']) {
      await tapDay(k);
      contracts('tap $k');
      final label = {'A': '장기별+가능일', 'E': '장기별'}[k];
      await cap('S102-N_${n}_${k}_selected', cond('$k($label) 실제 탭 뒤 · T 는 오늘(미선택)'));
      n++;
    }
    for (final l in log) {
      // ignore: avoid_print
      print('S102 $l');
    }
    expect(overflows, isEmpty);
    expect(calls.keys.where((k) => k.startsWith('BLOCKED')), isEmpty, reason: '쓰기·원격 채널 0');
    expect(t.takeException(), isNull);
  });
}
