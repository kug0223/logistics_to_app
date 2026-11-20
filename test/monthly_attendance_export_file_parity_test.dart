// [PREDEVICE-LIFECYCLE-EXPORT-PARITY §4·§6] **월간 근태 XLSX 를 실제로 만들어 되읽는다.**
//
//   `AdminMonthDetailScreen` 은 reader 주입점(`service`)을 갖고 있다. 그 한 칸만
//   갈아끼우고 화면을 띄워 **production 다운로드 버튼을 실제로 누른다.**
//   시트 분할·정렬·열 구성·파일명은 production 코드가 만든 그대로를 본다.
//
//   `Share` 경계에서 바이트를 가로챈다 — production 이 공유 직후 파일을 지우므로
//   거기서 읽지 않으면 검증 대상이 사라진다.
//
//   실제 개인정보는 쓰지 않는다. 합성값이다.
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/screens/business_admin/admin_month_detail_screen.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/services/admin_stats_service.dart';
import 'package:ALfit/utils/person_label.dart';

// `AdminStatsService` 는 생성자에서 `FirebaseFirestore.instance` 를 잡는다.
// 그래서 subclass 를 만들려면 Firebase 앱이 먼저 있어야 한다 — 조회는 하지 않는다.
class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k',
      appId: 'a',
      messagingSenderId: 's',
      projectId: 'p',
      storageBucket: 'p.appspot.com');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp(
          {String? name, FirebaseOptions? options}) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}

class _CapturingShare extends SharePlatform with MockPlatformInterfaceMixin {
  final List<({String name, Uint8List bytes})> captured = [];
  @override
  Future<ShareResult> shareXFiles(
    List<XFile> files, {
    String? subject,
    String? text,
    Rect? sharePositionOrigin,
    List<String>? fileNameOverrides,
  }) async {
    for (final f in files) {
      captured.add((
        name: f.path.split(RegExp(r'[\\/]')).last,
        bytes: await File(f.path).readAsBytes(),
      ));
    }
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

/// reader 한 칸만 갈아끼운다. 집계·화면·파일 생성은 production 이다.
/// [ADMIN-STATS-CLOSEOUT] 월 상세는 내보내기 직전 급여 권한을 본다 — 사업주는 허용.
class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'o1', username: 'o1', name: '사업주', email: 'o@alfit.local', role: UserRole.BUSINESS_ADMIN);
  @override
  bool get isBusinessAdmin => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
}

class _FakeStats extends AdminStatsService {
  _FakeStats(this.data);
  final MonthDetailData data;
  @override
  Future<MonthDetailData> getMonthDetail({
    required List<String> businessIds,
    String? filterBusinessId,
    required int year,
    required int month,
  }) async =>
      data;
}

final _kDay = DateTime.utc(2026, 10, 1, 15); // KST 2026-10-02 00:00

/// KST 'HH:mm' 를 instant 로 바꾼다.
///
///   `AttendanceModel.checkIn` 은 저장 필드가 아니라 `checkInAt` 을 KST 로
///   포맷하는 getter 다. 그래서 fixture 도 **instant** 로 줘야 production
///   경로(instant → KST 포맷 → 셀)를 그대로 지난다.
///   [day] 는 그 날 KST 자정의 instant 이므로 시·분을 그대로 더하면 된다.
DateTime? _kstAt(DateTime day, String? hhmm) {
  if (hhmm == null) return null;
  final p = hhmm.split(':');
  return day.add(
      Duration(hours: int.parse(p[0]), minutes: int.parse(p[1])));
}

AttendanceModel _att({
  required String id,
  required String uid,
  String businessName = '가 물류센터',
  String workType = '상하차',
  DateTime? workDate,
  String status = 'present',
  /// KST 'HH:mm'. null 이면 미기록.
  String? checkIn = '09:00',
  String? checkOut = '18:00',
  String? modifyReason,
}) =>
    AttendanceModel(
      id: id,
      applicationId: 'app_$id',
      userId: uid,
      businessId: 'bizA',
      businessName: businessName,
      workDate: workDate ?? _kDay,
      workType: workType,
      status: status,
      createdAt: _kDay,
      checkInAt: _kstAt(workDate ?? _kDay, checkIn),
      checkOutAt: _kstAt(workDate ?? _kDay, checkOut),
      modifyReason: modifyReason,
    );

MonthDetailData _data(
  List<AttendanceModel> recs,
  Map<String, UserInfo> info, {
  AttendanceStatsState state = AttendanceStatsState.available,
}) =>
    MonthDetailData(
      year: 2026,
      month: 10,
      presentCount: recs.length,
      lateCount: 0,
      absentCount: 0,
      totalWage: 0,
      workers: const [],
      avgRating: 0,
      rehireCount: 0,
      noRehireCount: 0,
      posTagFreq: const {},
      impTagFreq: const {},
      rawAttendance: recs,
      userInfoMap: info,
      attendanceStatsState: state,
    );

late Directory _tmp;
late _CapturingShare _share;

Future<void> _pumpScreen(WidgetTester t, MonthDetailData data,
    {List<String> businessIds = const ['bizA']}) async {
  t.view.physicalSize = const Size(411, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ChangeNotifierProvider<UserProvider>(create: (_) => _Owner()),
    ],
    child: MaterialApp(
    home: AdminMonthDetailScreen(
      businessIds: businessIds,
      filterBusinessId: null,
      year: 2026,
      month: 10,
      businesses: const [BusinessOption(id: 'bizA', name: '가 물류센터')],
      service: _FakeStats(data),
    ),
  )));
  await t.pumpAndSettle();
}

/// production 다운로드 버튼을 실제로 눌러 XLSX 를 받는다.
Future<({Excel book, String fileName})> _tapDownload(WidgetTester t) async {
  _share.captured.clear();
  final btn = find.byIcon(Icons.download_outlined);
  expect(btn, findsOneWidget, reason: '다운로드 버튼이 없다');
  // 실제 파일 I/O 를 타므로 가짜 시계 밖에서 돌려야 한다.
  await t.runAsync(() async {
    await t.tap(btn);
    await t.pump();
    // 생성·쓰기·공유가 끝날 시간을 준다.
    for (var i = 0; i < 40 && _share.captured.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await t.pump();
    }
  });
  expect(_share.captured, hasLength(1), reason: '파일이 공유 경계까지 오지 않았다');
  final cap = _share.captured.single;
  return (book: Excel.decodeBytes(cap.bytes), fileName: cap.name);
}

/// excel 패키지는 production 이 지운 Sheet1 을 디코드 결과에 남긴다.
/// 그래서 `values.first` 는 빈 시트일 수 있다 — 머리글이 채워진 시트를 고른다.
Sheet _dataSheet(Excel book) {
  for (final s in book.tables.values) {
    if (_text(s, 0, 0).isNotEmpty) return s;
  }
  throw StateError('머리글이 있는 시트가 없다 — 파일이 비었다');
}

String _text(Sheet s, int row, int col) {
  final v = s.rows.length > row && s.rows[row].length > col
      ? s.rows[row][col]?.value
      : null;
  if (v == null) return '';
  return v is TextCellValue ? v.value.toString() : v.toString();
}

List<String> _row(Sheet s, int r) => [for (var c = 0; c < 8; c++) _text(s, r, c)];

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    _tmp = await Directory.systemTemp.createTemp('alfit_month_');
    PathProviderPlatform.instance = _FakePathProvider(_tmp.path);
    _share = _CapturingShare();
    SharePlatform.instance = _share;
  });
  tearDownAll(() async {
    try {
      await _tmp.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('MX-01 열 구성 — 근태 파일에 급여·성별·연락처가 없다', (t) async {
    await _pumpScreen(
        t,
        _data([_att(id: 'a1', uid: 'u1')], {
          // 조회는 성별·연락처를 들고 있다. 파일에 나가는지가 문제다.
          'u1': const UserInfo(
              name: '김하나', gender: '남성', phone: '01000000000', personNo: 'W-001')
        }));
    final r = await _tapDownload(t);
    final sheet = _dataSheet(r.book);

    expect(_row(sheet, 0), [
      PersonLabel.fieldLabel, '사업장명', '근무일자', '파트', '근로자명',
      '출근시간', '퇴근시간', '비고',
    ]);
    final all = [
      for (var i = 0; i < sheet.rows.length; i++) _row(sheet, i)
    ].expand((x) => x).join('|');
    // 근태 파일은 근태를 말한다 — 급여·성별·연락처를 끌고 다니지 않는다.
    expect(all.contains('남성'), isFalse, reason: '성별이 파일에 있다');
    expect(all.contains('01000000000'), isFalse, reason: '연락처가 파일에 있다');
    expect(all.contains('u1'), isFalse, reason: 'uid 가 파일에 있다');
    expect(t.takeException(), isNull);
  });

  testWidgets('MX-02 날짜가 KST 로 적힌다', (t) async {
    // workDate 는 UTC 2026-10-01 15:00 = KST 2026-10-02 00:00 이다.
    // 기기 시간대에 따라 10-01 로 적히면 하루 틀린 파일이 나간다.
    await _pumpScreen(
        t,
        _data([_att(id: 'a1', uid: 'u1')],
            {'u1': const UserInfo(name: '김하나', personNo: 'W-001')}));
    final r = await _tapDownload(t);
    final sheet = _dataSheet(r.book);
    expect(_text(sheet, 1, 2), '2026-10-02');
    expect(t.takeException(), isNull);
  });

  testWidgets('MX-03 같은 사람 같은 날 두 업무가 두 행으로 구별된다', (t) async {
    await _pumpScreen(
        t,
        _data([
          _att(id: 'a1', uid: 'u1', workType: '상하차', checkIn: '09:00', checkOut: '13:00'),
          _att(id: 'a2', uid: 'u1', workType: '사무업무', checkIn: '14:00', checkOut: '18:00'),
        ], {'u1': const UserInfo(name: '김하나', personNo: 'W-001')}));
    final r = await _tapDownload(t);
    final sheet = _dataSheet(r.book);

    final rows = [_row(sheet, 1), _row(sheet, 2)];
    // 파트·출퇴근이 행을 가른다 — 둘이 같아 보이면 받는 쪽은 중복으로 읽는다.
    expect(rows.map((x) => x[3]).toList()..sort(), ['사무업무', '상하차']);
    expect(rows.map((x) => x[5]).toSet(), {'09:00', '14:00'});
    expect(t.takeException(), isNull);
  });

  testWidgets('MX-04 동명이인이 인력번호로 구별된다', (t) async {
    await _pumpScreen(
        t,
        _data([
          _att(id: 'a1', uid: 'u1'),
          _att(id: 'a2', uid: 'u2', checkIn: '10:00'),
        ], {
          'u1': const UserInfo(name: '김동명', personNo: 'W-001'),
          'u2': const UserInfo(name: '김동명', personNo: 'W-014'),
        }));
    final r = await _tapDownload(t);
    final sheet = _dataSheet(r.book);
    final nos = [_text(sheet, 1, 0), _text(sheet, 2, 0)]..sort();
    expect(nos, ['W-001', 'W-014']);
    expect([_text(sheet, 1, 4), _text(sheet, 2, 4)].toSet(), {'김동명'});
    expect(t.takeException(), isNull);
  });

  testWidgets('MX-05 출퇴근 미기록은 빈칸이 아니라 - 로 적힌다', (t) async {
    // 빈칸이면 "0시 출근"이나 누락으로 읽힌다. 모른다는 표시가 있어야 한다.
    await _pumpScreen(
        t,
        _data([_att(id: 'a1', uid: 'u1', checkIn: null, checkOut: null,
            status: 'absent')],
            {'u1': const UserInfo(name: '김하나', personNo: 'W-001')}));
    final r = await _tapDownload(t);
    final sheet = _dataSheet(r.book);
    expect(_text(sheet, 1, 5), '-');
    expect(_text(sheet, 1, 6), '-');
    expect(_text(sheet, 1, 7), contains('결근'));
    expect(t.takeException(), isNull);
  });

  testWidgets('MX-06 관리자 보정은 비고에 사유로 드러난다', (t) async {
    await _pumpScreen(
        t,
        _data([
          _att(id: 'a1', uid: 'u1', status: 'late',
              modifyReason: '지하철 지연 확인')
        ], {'u1': const UserInfo(name: '김하나', personNo: 'W-001')}));
    final r = await _tapDownload(t);
    final sheet = _dataSheet(r.book);
    final note = _text(sheet, 1, 7);
    expect(note, contains('지각'));
    expect(note, contains('지하철 지연 확인'),
        reason: '보정한 사실이 파일에 남지 않으면 원본과 대조할 수 없다');
    expect(t.takeException(), isNull);
  });

  testWidgets('MX-07 재다운로드가 같은 순서를 낸다', (t) async {
    final data = _data([
      _att(id: 'a3', uid: 'u1'),
      _att(id: 'a1', uid: 'u2'),
      _att(id: 'a2', uid: 'u1'),
    ], {
      'u1': const UserInfo(name: '김동명', personNo: 'W-001'),
      'u2': const UserInfo(name: '김동명', personNo: 'W-002'),
    });
    await _pumpScreen(t, data);
    final a = await _tapDownload(t);
    final rowsA = [
      for (var i = 1; i <= 3; i++) _row(_dataSheet(a.book), i)
    ];
    final b = await _tapDownload(t);
    final rowsB = [
      for (var i = 1; i <= 3; i++) _row(_dataSheet(b.book), i)
    ];
    expect(rowsB, rowsA, reason: '순서가 흔들리면 두 파일을 대조할 수 없다');
    expect(b.fileName, a.fileName);
    expect(t.takeException(), isNull);
  });

  testWidgets('MX-08 사업장이 여러 곳이면 시트가 갈리고 전체 시트가 있다', (t) async {
    await _pumpScreen(
        t,
        _data([
          _att(id: 'a1', uid: 'u1', businessName: '가 물류센터'),
          _att(id: 'a2', uid: 'u2', businessName: '나 센터'),
        ], {
          'u1': const UserInfo(name: '김하나', personNo: 'W-001'),
          'u2': const UserInfo(name: '이둘', personNo: 'W-002'),
        }),
        businessIds: ['bizA', 'bizB']);
    final r = await _tapDownload(t);
    final names = r.book.tables.keys.toList();
    expect(names.length, greaterThanOrEqualTo(3),
        reason: '사업장별 시트 + 전체 시트');
    expect(names.any((n) => n.contains('전체')), isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('MX-09 조회 실패면 다운로드 자체가 막힌다 (ERROR ≠ ZERO)', (t) async {
    // 조회가 실패한 상태로 파일을 만들면 "근무가 없었다"는 파일이 나간다.
    await _pumpScreen(
        t,
        _data(const [], const {},
            state: AttendanceStatsState.unavailable));
    // `byIcon` 은 `Icon` 을 찾는다 — 눌림 여부는 조상 `IconButton` 이 갖고 있다.
    final btn = find.ancestor(
        of: find.byIcon(Icons.download_outlined),
        matching: find.byType(IconButton));
    expect(btn, findsOneWidget);
    expect(t.widget<IconButton>(btn).onPressed, isNull,
        reason: '조회 실패 상태에서 버튼이 눌리면 빈 파일이 나간다');
    expect(t.takeException(), isNull);
  });

  testWidgets('MX-10 파일명에 사업장과 연월이 들어간다', (t) async {
    await _pumpScreen(
        t,
        _data([_att(id: 'a1', uid: 'u1')],
            {'u1': const UserInfo(name: '김하나', personNo: 'W-001')}));
    final r = await _tapDownload(t);
    // 여러 사업장을 차례로 내보낼 때 같은 이름이면 받는 쪽에서 덮인다.
    expect(r.fileName, contains('2026년10월'));
    expect(r.fileName, endsWith('.xlsx'));
    expect(r.fileName, contains('근태현황'));
    expect(t.takeException(), isNull);
  });

  // [ADMIN-STATS-CLOSEOUT] 생성된 파일을 되읽는다 — 화면과 같은 의미
  testWidgets('MX-11 퇴근 미확인은 비고에 "퇴근 미확인"(미출근·결근 아님) · 노쇼는 "노쇼" · 번호 열로 동명이인 구분', (t) async {
    final recs = [
      _att(id: 'a1', uid: 'u1', status: 'missed_checkout', checkOut: null),
      _att(id: 'a2', uid: 'u2', status: 'NO_SHOW', checkIn: null, checkOut: null),
      _att(id: 'a3', uid: 'u3', status: 'present'),
    ];
    final info = {
      'u1': const UserInfo(name: '합성 정미퇴근', personNo: 'P-005'),
      'u2': const UserInfo(name: '합성 김동명', personNo: 'P-002'),
      'u3': const UserInfo(name: '합성 김동명', personNo: 'P-003'),
    };
    await _pumpScreen(t, _data(recs, info));
    final f = await _tapDownload(t);
    final sh = _dataSheet(f.book);
    final rows = <String, List<String>>{};
    for (var r = 1; r < sh.rows.length; r++) {
      rows[_text(sh, r, 0)] = List.generate(8, (c) => _text(sh, r, c));
    }
    expect(rows.length, 3, reason: '파일 행 수 = 화면 집합(rawAttendance)');
    expect(rows['P-005']![7], '퇴근 미확인');
    expect(rows['P-005']![6], '-', reason: '퇴근 시각 없음');
    expect(rows['P-002']![7], '노쇼');
    expect(rows['P-003']![7], '출근');
    expect(rows['P-002']![4], rows['P-003']![4], reason: '같은 이름 — 번호 열이 가른다');
  });
}
