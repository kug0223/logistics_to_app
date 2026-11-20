// [ADMIN-MONTHLY-SUMMARY.1] 관리자 통계(연간 → 월 상세)가 실제 근무 사건을 같은 대상으로 세는가.
//
//   입력: test/fixtures/admin_monthly_reads.json — LOCAL 에뮬레이터에서 실제 writer 로 만든 한 달치 사건
//   (core-invite-wd-20261026/run-M3, 시계를 옮겨 9/30·10/31·11/1 근무를 실행) 에 live reader
//   (callableGetAdminAttendances 00099 · callableGetUsersBatch 00101 · callableGetMonthlyReviewStatsByBiz 00002)
//   를 부른 실제 응답. 앱 AdminStatsService 를 그대로 돌리고, 기대값은 writer 원장(ledger-P3.json)에서
//   손으로 센 값이다(같은 집계 함수를 다시 불러 만들지 않는다).
//
//   원장(사업장 M, 10월 근무일 7건 · 9월 1건 · 11월 1건; 다른 사업장 X 1건은 섞이면 안 된다)
//     m1 A 10/31 present/transferred 41,280 · m1 B 10/31 present(관리자 정정, 원래 late)/calculated
//     m2 B 10/31 present/pending(다른 업무 제안 수락 — m1 과 동명이인) · m7 B 10/31 present/pending(퇴근 안 함 = 출근 중)
//     m4 A 10/31 NO_SHOW/confirmed 0 · m5 A 10/31 missed_checkout/pending(스케줄러 미퇴근 처리)
//     m3 야간 10/31 23:00 → 11/01 00:30 출근 late/confirmed 85,140 (근무일 기준 10월)
//     m3 야간 9/30 → 10/01 00:30 출근 late/confirmed 85,140 (9월) · m4 A 11/01 present/pending (11월)
//     m6 은 확정 뒤 관리자 취소 → 근태 없음
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/services/admin_stats_service.dart';

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

const _ch = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
final _fx = (jsonDecode(File('test/fixtures/admin_monthly_reads.json').readAsStringSync()) as Map).cast<String, dynamic>();
final _reads = (_fx['reads'] as Map).cast<String, dynamic>();
final String _biz = _fx['biz'] as String;

/// 앱이 보내는 KST 경계(UTC 자정 - 9h)를 여기서 따로 계산해 녹화 키로 바꾼다.
int _kb(int y, int m) => DateTime.utc(y, m, 1).subtract(const Duration(hours: 9)).millisecondsSinceEpoch;
String? _rangeKey(int s, int e) {
  final m = <String, List<int>>{
    '2026-09': [_kb(2026, 9), _kb(2026, 10)], '2026-10': [_kb(2026, 10), _kb(2026, 11)], '2026-11': [_kb(2026, 11), _kb(2026, 12)],
    '2026-12': [_kb(2026, 12), _kb(2027, 1)], 'Y2026': [_kb(2026, 1), _kb(2027, 1)], 'Y2025': [_kb(2025, 1), _kb(2026, 1)],
  };
  for (final x in m.entries) {
    if (x.value[0] == s && x.value[1] == e) return x.key;
  }
  return null;
}

String who = 'owner';
final calls = <String>[];
Object? Function(String fn, Map p)? respond;

void _install() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_ch, (msg) async {
    final args = (const StandardMessageCodec().decodeMessage(msg) as List).first as Map;
    final fn = args['functionName'] as String; final p = (args['parameters'] as Map?) ?? {};
    calls.add(fn);
    final o = respond?.call(fn, p);
    if (o != null) return const StandardMessageCodec().encodeMessage(o);
    Map<String, dynamic>? rec;
    if (fn == 'callableGetAdminAttendances') {
      final k = _rangeKey((p['startMs'] as num).toInt(), (p['endMs'] as num).toInt());
      rec = (_reads['att|$who|$k'] as Map?)?.cast<String, dynamic>();
    } else if (fn == 'callableGetUsersBatch') {
      rec = (_reads['users|${who == 'saWorkers' ? 'saWorkers' : 'owner'}'] as Map?)?.cast<String, dynamic>();
    } else if (fn == 'callableGetMonthlyReviewStatsByBiz') {
      final k = p['reviewMonth'] == null ? 'Y${p['reviewYear']}' : '${p['reviewYear']}-${p['reviewMonth'].toString().padLeft(2, '0')}';
      rec = (_reads['review|owner|$k'] as Map?)?.cast<String, dynamic>();
    }
    if (rec == null) return const StandardMessageCodec().encodeMessage(<Object?>['not-found', 'no recording for $fn ${jsonEncode(p)}', null]);
    if (rec['ok'] != true) return const StandardMessageCodec().encodeMessage(<Object?>[rec['code'], rec['message'], null]);
    return const StandardMessageCodec().encodeMessage(<Object?>[rec['data']]);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  setUp(() {
    who = 'owner';
    respond = null;
    calls.clear();
    _install();
  });

  group('M1·M2 10월 월 상세 = writer 원장', () {
    test('MS-1 같은 사업장 문서 7건만 센다(다른 사업장 X 제외) · 금액은 확정·이체만', () async {
      final d = await AdminStatsService().getMonthDetail(businessIds: [_biz], year: 2026, month: 10);
      expect(d.attendanceStatsState, AttendanceStatsState.available);
      expect(d.rawAttendance.length, 7);
      expect(d.rawAttendance.every((a) => a.businessId == _biz), isTrue);
      expect(d.totalWage, 41280 + 85140 + 0, reason: 'm1 A 이체 + m3 야간 확정 + m4 노쇼 확정 0 — m1 B(calculated)·대기 제외');
    });

    test('MS-2 출결 구분: 정상 4 · 지각 1 · 결근 1(노쇼) · 퇴근 미확인 1(missed_checkout 은 결근이 아니다)', () async {
      final d = await AdminStatsService().getMonthDetail(businessIds: [_biz], year: 2026, month: 10);
      expect(d.presentCount, 4, reason: 'm1 A·m1 B(정정 present)·m2 B·m7 B(출근 중)');
      expect(d.lateCount, 1, reason: 'm3 야간(11/01 00:30 출근, 근무일 10/31)');
      expect(d.absentCount, 1, reason: '노쇼 m4 만 — 출근 기록이 있는 미퇴근 m5 는 결근이 아니다');
      expect(d.missedCheckoutCount, 1);
      expect(d.totalAttendanceCount, 7);
    });

    test('MS-3 직원별: 6명 · 같은 날 두 근무는 1일·금액 합 · 동명이인은 인력번호로 구분', () async {
      final d = await AdminStatsService().getMonthDetail(businessIds: [_biz], year: 2026, month: 10);
      expect(d.workers.length, 6);
      final kims = d.workers.where((w) => w.userName == '합성 김동명').toList();
      expect(kims.length, 2);
      expect(kims.map((w) => w.personNo).toSet().length, 2, reason: '같은 이름 두 사람 — 화면이 구분할 수단');
      final m1 = kims.firstWhere((w) => w.records.length == 2);
      expect(m1.totalDays, 1);
      expect(m1.presentDays, 2);
      expect(m1.totalWage, 41280, reason: 'A 이체 41,280 + B calculated 제외');
      final m5 = d.workers.firstWhere((w) => w.userName == '합성 정미퇴근');
      expect(m5.absentDays, 0);
      expect(m5.missedCheckoutDays, 1);
    });
  });

  group('M3 기간 경계', () {
    test('MS-4 야간 근무는 근무일 월: 9/30 근무(10/01 00:30 출근)는 9월, 10/31 근무(11/01 출근)는 10월 · 11월은 11/01 근무 1건', () async {
      final s = AdminStatsService();
      final sep = await s.getMonthDetail(businessIds: [_biz], year: 2026, month: 9);
      final nov = await s.getMonthDetail(businessIds: [_biz], year: 2026, month: 11);
      final dec = await s.getMonthDetail(businessIds: [_biz], year: 2026, month: 12);
      expect((sep.rawAttendance.length, sep.lateCount, sep.totalWage), (1, 1, 85140));
      expect((nov.rawAttendance.length, nov.presentCount, nov.totalWage), (1, 1, 0));
      expect((dec.attendanceStatsState, dec.rawAttendance.length), (AttendanceStatsState.available, 0), reason: '빈 달은 실패가 아니다');
    });

    test('MS-5 연간 월별 막대 = 월 상세(같은 문서 집합) · 연간 합계', () async {
      final a = await AdminStatsService().getAnnualStats(businessIds: [_biz], year: 2026);
      expect(a.attendanceStatsState, AttendanceStatsState.available);
      final t = {for (final m in a.monthlyTrends) m.month: m};
      expect((t[9]!.workCount, t[9]!.totalWage), (1, 85140));
      expect((t[10]!.workCount, t[10]!.totalWage, t[10]!.workerCount), (7, 126420, 6));
      expect((t[11]!.workCount, t[11]!.totalWage), (1, 0));
      expect(a.totalWage, 211560);
      expect(a.totalWorkerCount, 6);
      expect(a.noShowCount, 1);
    });
  });

  group('M4 단위', () {
    test('MS-6 연간 "근무 건수"는 급여 확정·이체 건(4)이고 월 막대 건수(전체 9)와 단위가 다르다 — 라벨로 구분돼야 한다', () async {
      final a = await AdminStatsService().getAnnualStats(businessIds: [_biz], year: 2026);
      expect(a.totalWorkCount, 4, reason: 'm1 A·m4 노쇼·m3 야간 2건 — MED-STAT 계약(인건비와 같은 기준)');
      expect(a.monthlyTrends.fold<int>(0, (s, m) => s + m.workCount), 9);
    });

    test('MS-7 출근율: 미퇴근(출근 기록 있음)은 출근으로 센다 — 8/9', () async {
      final a = await AdminStatsService().getAnnualStats(businessIds: [_biz], year: 2026);
      expect(a.attendanceRate, closeTo(8 / 9 * 100, 0.01));
    });
  });

  group('M5·M6 실패·잘림은 0 이 아니다', () {
    test('MS-8 근태 조회 실패 → 확인 불가(0 아님) · 이름 조회 실패는 집계를 지우지 않는다', () async {
      respond = (fn, p) => fn == 'callableGetAdminAttendances' ? <Object?>['unavailable', 'x', null] : null;
      final d = await AdminStatsService().getMonthDetail(businessIds: [_biz], year: 2026, month: 10);
      expect(d.attendanceStatsState, AttendanceStatsState.unavailable);
      respond = (fn, p) => fn == 'callableGetUsersBatch' ? <Object?>['permission-denied', 'x', null] : null;
      final d2 = await AdminStatsService().getMonthDetail(businessIds: ['other_cache_key_$_biz', _biz], filterBusinessId: _biz, year: 2026, month: 10);
      expect(d2.attendanceStatsState, AttendanceStatsState.available);
      expect(d2.rawAttendance.length, 7);
    });

    test('MS-9 상한 도달(limitReached) → 확인 불가', () async {
      respond = (fn, p) => fn == 'callableGetAdminAttendances' ? <Object?>[<String, Object?>{'items': <Object?>[], 'limitReached': true}] : null;
      final d = await AdminStatsService().getMonthDetail(businessIds: [_biz], year: 2026, month: 10);
      expect(d.attendanceStatsState, AttendanceStatsState.unavailable);
    });
  });

  group('M7 권한', () {
    test('MS-10 근로자 관리만 가진 SubAdmin 응답은 금액 필드가 빠진다 — 서비스로는 0 과 구별할 수 없다(그래서 입구가 막아야 한다)', () async {
      who = 'saWorkers';
      final d = await AdminStatsService().getMonthDetail(businessIds: [_biz], year: 2026, month: 10);
      expect(d.rawAttendance.length, 7);
      expect(d.totalWage, 0, reason: '실제 126,420원이지만 응답에 finalWage·netWage 가 없다');
      who = 'saWage';
      final d2 = await AdminStatsService().getMonthDetail(businessIds: [_biz], year: 2026, month: 10);
      expect(d2.totalWage, 126420);
    });

    test('MS-11 다른 사업장 관리자·소속 없는 사업장 조회는 거절 → 확인 불가', () async {
      who = 'other';
      final d = await AdminStatsService().getMonthDetail(businessIds: [_biz], year: 2026, month: 10);
      expect(d.attendanceStatsState, AttendanceStatsState.unavailable);
      expect((_reads['att|owner|BZX'] as Map)['ok'], isFalse);
    });
  });
}
