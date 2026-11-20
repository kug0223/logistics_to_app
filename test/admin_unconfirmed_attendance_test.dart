// [MISSING-CHECKOUT.3 §6] status 없는 근태는 결근이 아니다 — '근태 확인 필요'로 따로 센다.
//
//   `AttendanceModel.fromMap` 은 status 가 없으면 'absent' 로 채운다. 관리자 통계는 그 값을
//   그대로 결근으로 셌다 — 근태 초기화(callableBatchResetAttendance 00078)는 출근·status 를
//   지운 문서를 남기므로, 초기화한 근무가 한 달 통계에서 '결근'이 됐다.
//
//   입력: test/fixtures/admin_unconfirmed_reads.json — LOCAL 에뮬레이터에서 실제 writer 로 만든 한 달
//   (core-invite-wd-20261026/run-U4) 에 live reader(callableGetAdminAttendances 00099 ·
//   callableGetUsersBatch 00101 · callableGetMonthlyReviewStatsByBiz 00002)를 부른 응답.
//   기대값은 writer 원장(ledger-U4.json)에서 손으로 센 값이다.
//
//   원장(사업장 M, 10/31 근무 4건)
//     m1 정상 출근·퇴근 · 급여 확정 41,280 (present/confirmed)
//     m4 관리자 노쇼 처리 (BatchSetNoShow 00083 → NO_SHOW/confirmed 0원) — 명시 결근
//     m7 출근만 · 자정 스케줄러(후보 a9ed6a22)가 미퇴근 처리 (missed_checkout/pending)
//     m5 출근 뒤 관리자 근태 초기화 (BatchReset 00078 → status·checkIn 없음, pending)
//
//   고정하는 것
//     UA-1  월 상세: 정상 1 · 결근 1(노쇼만) · 퇴근 미확인 1 · 근태 확인 필요 1 · 전체 4(분모에서 빼지 않음)
//     UA-2  직원별: 초기화된 사람은 결근 0 · 확인 필요 1
//     UA-3  연간: 확인 필요 1 · 노쇼 분자에 넣지 않음 · 확정 금액·건수 그대로
//     UA-4  단순 fixture: 정상 근태에서 status 키만 지우면 확인 필요로 옮겨 간다(결근 아님) · 모르는 값도 같다
//     UA-5  화면: 연간 출근율·노쇼율은 숫자 대신 '확인 필요' + 건수 · 전년 대비 없음
//     UA-6  화면: 월 상세 칩·직원 배지 · Excel 비고 '근태 확인 필요'(결근·미출근 아님)
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_month_detail_screen.dart';
import 'package:ALfit/screens/business_admin/admin_stats_screen.dart';
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

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}

class _CapturingShare extends SharePlatform with MockPlatformInterfaceMixin {
  final List<({String name, Uint8List bytes})> captured = [];
  @override
  Future<ShareResult> shareXFiles(List<XFile> files,
      {String? subject, String? text, Rect? sharePositionOrigin, List<String>? fileNameOverrides}) async {
    for (final f in files) {
      captured.add((name: f.path.split(RegExp(r'[\\/]')).last, bytes: await File(f.path).readAsBytes()));
    }
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'o1', username: 'o1', name: '사업주', email: 'o@alfit.local', role: UserRole.BUSINESS_ADMIN);
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
}

/// 화면에는 production 서비스가 만든 값을 그대로 건넨다(집계를 다시 만들지 않는다).
class _Fixed extends AdminStatsService {
  _Fixed({this.annual, this.detail});
  final AnnualStatsData? annual;
  final MonthDetailData? detail;
  @override
  Future<List<BusinessOption>> getBusinessOptions(List<String> ids) async => [BusinessOption(id: _biz, name: '[합성] 월간 사업장')];
  @override
  Future<AnnualStatsData> getAnnualStats({required List<String> businessIds, String? filterBusinessId, required int year}) async => annual!;
  @override
  Future<MonthDetailData> getMonthDetail({required List<String> businessIds, String? filterBusinessId, required int year, required int month}) async =>
      detail!;
}

const _ch = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
final _fx = (jsonDecode(File('test/fixtures/admin_unconfirmed_reads.json').readAsStringSync()) as Map).cast<String, dynamic>();
final _reads = (_fx['reads'] as Map).cast<String, dynamic>();
final String _biz = _fx['biz'] as String;

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

/// 녹화된 근태 응답을 바꿔 끼운다(단순 fixture 용). key → items 변환.
List<Object?> Function(List<Object?> items)? mutateAtt;

void _install() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_ch, (msg) async {
    final args = (const StandardMessageCodec().decodeMessage(msg) as List).first as Map;
    final fn = args['functionName'] as String;
    final p = (args['parameters'] as Map?) ?? {};
    Map<String, dynamic>? rec;
    if (fn == 'callableGetAdminAttendances') {
      final k = _rangeKey((p['startMs'] as num).toInt(), (p['endMs'] as num).toInt());
      rec = (_reads['att|owner|$k'] as Map?)?.cast<String, dynamic>();
      if (rec != null && mutateAtt != null && rec['ok'] == true) {
        final data = Map<String, dynamic>.from(jsonDecode(jsonEncode(rec['data'])) as Map);
        data['items'] = mutateAtt!(List<Object?>.from(data['items'] as List));
        rec = {'ok': true, 'data': data};
      }
    } else if (fn == 'callableGetUsersBatch') {
      rec = (_reads['users|owner'] as Map?)?.cast<String, dynamic>();
    } else if (fn == 'callableGetMonthlyReviewStatsByBiz') {
      final k = p['reviewMonth'] == null ? 'Y${p['reviewYear']}' : '${p['reviewYear']}-${p['reviewMonth'].toString().padLeft(2, '0')}';
      rec = (_reads['review|owner|$k'] as Map?)?.cast<String, dynamic>();
    }
    if (rec == null) return const StandardMessageCodec().encodeMessage(<Object?>['not-found', 'no recording for $fn ${jsonEncode(p)}', null]);
    if (rec['ok'] != true) return const StandardMessageCodec().encodeMessage(<Object?>[rec['code'], rec['message'], null]);
    return const StandardMessageCodec().encodeMessage(<Object?>[rec['data']]);
  });
}

WorkerMonthSummary _w(MonthDetailData d, String name) => d.workers.firstWhere((w) => w.userName == name);

late Directory _tmp;
late _CapturingShare _share;

Future<void> _pump(WidgetTester t, Widget home) async {
  t.view.physicalSize = const Size(360, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _Owner()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(home: KeyedSubtree(key: UniqueKey(), child: home)),
  ));
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

String _text(Sheet s, int row, int col) {
  final v = s.rows.length > row && s.rows[row].length > col ? s.rows[row][col]?.value : null;
  if (v == null) return '';
  return v is TextCellValue ? v.value.toString() : v.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    _tmp = await Directory.systemTemp.createTemp('alfit_unconf_');
    PathProviderPlatform.instance = _FakePathProvider(_tmp.path);
    _share = _CapturingShare();
    SharePlatform.instance = _share;
  });
  tearDownAll(() async {
    try {
      await _tmp.delete(recursive: true);
    } catch (_) {}
  });
  setUp(() {
    mutateAtt = null;
    _install();
  });

  test('UA-0 녹화 응답에서 초기화 문서는 status 키가 없다(fixture 가 실제 writer 출력이라는 확인)', () {
    final items = ((_reads['att|owner|2026-10'] as Map)['data'] as Map)['items'] as List;
    expect(items.length, 4);
    expect(items.where((i) => !(i as Map).containsKey('status')).length, 1);
  });

  test('UA-1 월 상세: 정상 1 · 결근 1(노쇼만) · 퇴근 미확인 1 · 확인 필요 1 · 전체 4', () async {
    final d = await AdminStatsService().getMonthDetail(businessIds: [_biz], year: 2026, month: 10);
    expect(d.attendanceStatsState, AttendanceStatsState.available);
    expect(d.rawAttendance.length, 4);
    expect(d.presentCount, 1, reason: 'm1');
    expect(d.lateCount, 0);
    expect(d.absentCount, 1, reason: '명시 노쇼 m4 만 — 초기화된 m5 는 결근이 아니다(예전엔 2)');
    expect(d.missedCheckoutCount, 1, reason: 'm7');
    expect(d.unconfirmedCount, 1, reason: 'm5 — status 없음');
    expect(d.totalAttendanceCount, 4, reason: '확인 필요도 전체(분모)에 남는다');
    expect(d.totalWage, 41280, reason: '확정 금액은 그대로 — m1 41,280 + m4 노쇼 확정 0');
    expect(d.settledCount, 2);
    final m5 = d.rawAttendance.firstWhere((a) => a.userId.startsWith('gpm_m5_'));
    expect(m5.status, AttendanceModel.statusUnconfirmed);
    expect(m5.statusLabel, '근태 확인 필요');
  });

  test('UA-2 직원별: 초기화된 사람은 결근 0 · 확인 필요 1', () async {
    final d = await AdminStatsService().getMonthDetail(businessIds: [_biz], year: 2026, month: 10);
    final m5 = _w(d, '합성 정미퇴근');
    expect((m5.absentDays, m5.unconfirmedDays, m5.presentDays, m5.totalWage), (0, 1, 0, 0));
    final m4 = _w(d, '합성 최노쇼');
    expect((m4.absentDays, m4.unconfirmedDays, m4.hasSettledWage), (1, 0, true));
    final m7 = _w(d, '합성 오출근중');
    expect((m7.missedCheckoutDays, m7.absentDays, m7.unconfirmedDays), (1, 0, 0));
  });

  test('UA-3 연간: 확인 필요 1 · 노쇼 분자에 넣지 않음 · 확정 금액·건수 그대로', () async {
    final a = await AdminStatsService().getAnnualStats(businessIds: [_biz], year: 2026);
    expect(a.attendanceStatsState, AttendanceStatsState.available);
    expect(a.attendanceRecordCount, 4);
    expect(a.unconfirmedAttendanceCount, 1);
    expect(a.prevUnconfirmedAttendanceCount, 0);
    expect(a.noShowCount, 1, reason: 'm4 만');
    expect((a.totalWage, a.totalWorkCount), (41280, 2));
    expect(a.exceptions.where((e) => e.absentCount > 0).length, 1, reason: '주의 직원 결근도 명시 노쇼만');
  });

  test('UA-4 단순 fixture: status 키만 지우면 확인 필요로 옮겨 간다 · 빈 값·모르는 값도 같다', () async {
    mutateAtt = (items) => [
          for (final i in items)
            if ((i as Map)['userId'].toString().startsWith('gpm_m1_'))
              (Map<String, dynamic>.from(i)..remove('status'))
            else if (i['userId'].toString().startsWith('gpm_m7_'))
              (Map<String, dynamic>.from(i)..['status'] = '')
            else if (i['userId'].toString().startsWith('gpm_m4_'))
              (Map<String, dynamic>.from(i)..['status'] = 'unknown_future_status')
            else
              i,
        ];
    final d = await AdminStatsService().getMonthDetail(businessIds: [_biz], year: 2026, month: 10);
    expect((d.presentCount, d.absentCount, d.missedCheckoutCount, d.unconfirmedCount), (0, 0, 0, 4));
    expect(d.totalWage, 41280, reason: '근태 상태를 모른다고 확정 급여가 사라지지 않는다');
    expect(AdminStatsService.isKnownAttendanceStatus(null), isFalse);
    expect(AdminStatsService.isKnownAttendanceStatus('absent'), isTrue);
    expect(AdminStatsService.isKnownAttendanceStatus('NO_SHOW'), isTrue);
    // 모델 기본값은 그대로다 — 다른 소비자(급여·근태 화면)는 바뀌지 않는다. 통계만 원본으로 따로 판정한다.
    final raw = (((_reads['att|owner|2026-10'] as Map)['data'] as Map)['items'] as List)
        .cast<Map>()
        .firstWhere((i) => !i.containsKey('status'));
    final m = Map<String, dynamic>.from(raw);
    final id = m.remove('id') as String;
    expect(AttendanceModel.tryFromMap(m, id)?.status, AttendanceModel.statusAbsent);
  });

  testWidgets('UA-5 연간 화면: 출근율·노쇼율은 숫자 대신 "확인 필요" + 건수 · 전년 대비 없음', (t) async {
    final a = (await t.runAsync(() => AdminStatsService().getAnnualStats(businessIds: [_biz], year: 2026)))!;
    await _pump(t, AdminStatsScreen(businessIds: [_biz], service: _Fixed(annual: a)));
    expect(find.text('확인 필요'), findsNWidgets(2));
    expect(find.text('미확인 1건 ›'), findsNWidgets(2), reason: "'근태 N건' 은 막대의 '전체 근태 (건)' 와 같은 단위로 읽혔다 — 값 '확인 필요' 아래 '미확인 N건'");
    expect(find.textContaining('50.0%'), findsNothing, reason: '확인 못 한 1건을 뺀 비율도, 넣은 비율도 숫자로 말하지 않는다');
    expect(find.textContaining('25.0%'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('UA-6 월 상세 화면 칩·배지 · Excel 비고 "근태 확인 필요"', (t) async {
    final d = (await t.runAsync(() => AdminStatsService().getMonthDetail(businessIds: [_biz], year: 2026, month: 10)))!;
    await _pump(t, AdminMonthDetailScreen(businessIds: [_biz], filterBusinessId: _biz, year: 2026, month: 10,
        businesses: [BusinessOption(id: _biz, name: '[합성] 월간 사업장')], service: _Fixed(detail: d)));
    expect(find.text('근태 확인 필요 25%'), findsOneWidget);
    expect(find.text('결근 25%'), findsOneWidget, reason: '노쇼 1건만');
    expect(find.text('퇴근 미확인 25%'), findsOneWidget);
    expect(find.text('확인필요 1 ›'), findsOneWidget);
    expect(t.takeException(), isNull);

    _share.captured.clear();
    await t.runAsync(() async {
      await t.tap(find.byIcon(Icons.download_outlined));
      await t.pump();
      for (var i = 0; i < 40 && _share.captured.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await t.pump();
      }
    });
    expect(_share.captured, hasLength(1));
    final book = Excel.decodeBytes(_share.captured.single.bytes);
    final sh = book.tables.values.firstWhere((s) => _text(s, 0, 0).isNotEmpty);
    final notes = <String, String>{for (var r = 1; r < sh.rows.length; r++) _text(sh, r, 4): _text(sh, r, 7)};
    expect(notes.length, 4, reason: '파일 행 = 화면 집합');
    expect(notes['합성 정미퇴근'], '근태 확인 필요');
    expect(notes['합성 최노쇼'], '노쇼');
    expect(notes['합성 오출근중'], '퇴근 미확인');
    expect(notes['합성 김동명'], '출근');
  });
}
