// [R8-PERFORMANCE.1] 혼자 라운드를 차지하던 읽기를 앞 phase 로 옮겼다
//
// 측정 근거: DEV warm 에서 `callableGetDayStaffingDetail` 이 920ms 로 이번
// 감사의 최장 읽기였는데, 두 화면 모두 그 호출을 **앞 결과가 다 온 뒤에야**
// 시작했다. 입력은 사업장·날짜뿐이라 기다릴 이유가 없었다.
//
// 라운드를 합치면서 가장 위험한 것은 **실패를 합치는 것**이다.
// `Future.wait` 는 하나가 던지면 나머지 성공분까지 버린다. 그래서 각 독립
// 호출은 자기 try/catch 를 가진 클로저 안에 들어가고, 실패하면 자기 칸만
// 모름(UNKNOWN)으로 내린다.
//
// 고정하는 것
//   RC-1   DayApplicants — 전부 성공
//   RC-2   DayApplicants — 충원 실패는 명단을 지우지 않는다
//   RC-3   DayApplicants — 초대 실패는 '초대 0명'이 아니다
//   RC-4   DayApplicants — 지원자(기반) 실패는 지금처럼 화면 전체 ERROR
//   RC-5   DayApplicants — 충원·초대가 **둘 다** 실패해도 명단은 남는다
//   RC-6   DayApplicants — 충원·초대가 지원자 응답을 기다리지 않는다 (라운드)
//   RC-7   Attendance — 전부 성공
//   RC-8   Attendance — 충원 실패는 근태 명단을 지우지 않는다
//   RC-9   Attendance — 사업장 읽기 실패는 명단을 비우지 않고, 표식도 남기지 않는다
//   RC-10  Attendance — 근무자(기반) 실패는 화면 전체 ERROR
//   RC-11  Attendance — 충원·사업장이 근무자 응답을 기다리지 않는다 (라운드)
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/attendance_status_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/attendance_reads.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_reads.dart';
import 'package:ALfit/utils/format_helper.dart';

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

/// 초대 조회는 `canManageTo` 가 있어야 **호출 자체가 일어난다**
/// (NO_PERMISSION != ERROR). 테스트에서 그 분기를 타려면 권한이 필요한데
/// `UserProvider` 에 사용자를 주입하는 seam 이 없다 — 권한 판정만 연다.
class _PermissiveProvider extends UserProvider {
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      true;
}

/// `canManageTo` 만 없는 관리자 — 초대 게이트가 닫힌 상태.
class _NoInviteProvider extends UserProvider {
  @override
  bool can(bool Function(MemberPermissions p) check) =>
      check(MemberPermissions.fromMap(const {'canManageWorkers': true}));
  @override
  bool canForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      check(MemberPermissions.fromMap(const {'canManageWorkers': true}));
}

const _biz = 'biz1';
final _day = () {
  final t = DateTime.now().add(const Duration(days: 1));
  return DateTime(t.year, t.month, t.day);
}();
final _dayKey = FormatHelper.kstDayKeyOfCivil(_day);

Map<String, dynamic> _ts(DateTime d) =>
    {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

BusinessModel _business() => BusinessModel(
      id: _biz,
      name: '테스트 사업장',
      businessNumber: '000-00-00000',
      category: '음식점',
      subCategory: '한식',
      address: '서울특별시 강남구 테헤란로 1',
      ownerId: 'owner1',
      createdAt: DateTime(2026, 1, 1),
    );

UserModel _user(String uid, String name) => UserModel(
      uid: uid,
      username: name,
      name: name,
      email: '$uid@example.com',
      role: UserRole.USER,
      createdAt: DateTime(2026, 1, 1),
    );

DayStaffingRow _row() => DayStaffingRow(
      toId: 'to1',
      toTitle: '공고',
      slotId: 'slot1',
      wdId: 'wd1',
      workType: '홀서빙',
      startTime: '09:00',
      endTime: '18:00',
      requiredCount: 2,
      confirmedCount: 1,
      pendingCount: 0,
    );

String _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .where((s) => s.isNotEmpty)
    .join(' | ');

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// ══════════════════════════════════════════════════════════════
// DayApplicantsDialog
// ══════════════════════════════════════════════════════════════

ApplicationModel _app({
  required String id,
  required String uid,
  required String status,
}) =>
    ApplicationModel(
      id: id,
      toId: 'to1',
      slotId: 'slot1',
      wdId: 'wd1',
      businessId: _biz,
      businessName: '테스트 사업장',
      toTitle: '공고',
      uid: uid,
      applicantName: '근로자 $uid',
      status: status,
      appliedAt: _day,
      workDate: _day,
      selectedWorkType: '홀서빙',
      startTime: '09:00',
      endTime: '18:00',
      wage: 12000,
      wageType: 'hourly',
    );

class _DayReads {
  final List<String> calls = [];
  Completer<void>? baseGate;
  bool failStaffing = false;
  bool failInvites = false;
  bool failPending = false;

  DayApplicantsReads build() => DayApplicantsReads(
        pendingApplications:
            ({required date, required businessId, purpose}) async {
          calls.add('pending');
          if (baseGate != null) await baseGate!.future;
          if (failPending) throw StateError('pending read failed');
          return [_app(id: 'a1', uid: 'u1', status: 'PENDING')];
        },
        confirmedWorkers: ({required date, required businessId}) async {
          calls.add('confirmed');
          if (baseGate != null) await baseGate!.future;
          return [_app(id: 'a2', uid: 'u2', status: 'CONFIRMED')];
        },
        dayStaffing: ({required businessId, required dayStartMs}) async {
          calls.add('staffing');
          if (failStaffing) throw StateError('staffing read failed');
          return [_row()];
        },
        dayInvitations: ({required date, required businessId}) async {
          calls.add('invitations');
          if (failInvites) throw StateError('invitations read failed');
          return const <ApplicationModel>[];
        },
        hasWorkedMap: ({required businessId, required date}) async => const {},
        noShowApplicationIds: ({required businessId, required date}) async =>
            <String>{},
        usersBatch: (uids, {required businessId, purpose}) async =>
            {for (final u in uids) u: _user(u, '근로자 $u')},
        weeklyAttendance: ({required businessId, required weekStart,
                required weekEnd}) async =>
            <String, List<AttendanceModel>>{},
        slotWorkDetailCapacities: (toId, slotId) async => const {'wd1': 2},
        slotWorkDetails: (toId, slotId) async => <WorkDetailData>[],
        to: (toId) async => null,
        contractStatusBatch: (ids, {required businessId}) async =>
            <String, String?>{},
      );
}

Future<void> _openDay(WidgetTester tester, _DayReads r) async {
  await tester.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _PermissiveProvider(),
    child: MaterialApp(
      home: Scaffold(
        body: DayApplicantsDialog(
          date: _day,
          businessIds: const [_biz],
          businesses: [_business()],
          reads: r.build(),
        ),
      ),
    ),
  ));
  await _settle(tester);
}

// ══════════════════════════════════════════════════════════════
// AttendanceStatusDialog
// ══════════════════════════════════════════════════════════════

Map<String, dynamic> _appMap({required String id, required String uid}) => {
      'id': id,
      'uid': uid,
      'toId': 'to1',
      'slotId': 'slot1',
      'businessId': _biz,
      'wdId': 'wd1',
      'workDetailId': 'wd-a',
      'status': 'CONFIRMED',
      'type': 'short_term',
      'selectedWorkType': '홀서빙',
      'startTime': '09:00',
      'endTime': '18:00',
      'workDate': _ts(_dayKey),
      'createdAt': _ts(_dayKey),
      'appliedAt': _ts(_dayKey),
    };

class _AttReads {
  final List<String> calls = [];
  Completer<void>? baseGate;
  bool failStaffing = false;
  bool failBusiness = false;
  bool failApplications = false;

  AttendanceReads build() => AttendanceReads(
        applicationsPaged: (payload) async {
          calls.add('apps');
          if (baseGate != null) await baseGate!.future;
          if (failApplications) throw StateError('applications read failed');
          if (payload['type'] != null) return const [];
          return [_appMap(id: 'a1', uid: 'u1')];
        },
        workTypeDocs: (_) async {
          calls.add('workTypes');
          return const {};
        },
        adminAttendances:
            ({required businessId, required startMs, required endMs}) async =>
                const [],
        workDetailTimes: (_) async => const {},
        usersBatch: ({required uids, required businessId}) async =>
            {for (final u in uids) u: _user(u, '근로자 $u')},
        contractStatus: ({required appIds, required businessId}) async =>
            {for (final id in appIds) id: 'signed'},
        dayStaffing: ({required businessId, required dayStartMs}) async {
          calls.add('staffing');
          if (failStaffing) throw StateError('staffing read failed');
          return [_row()];
        },
        businessById: (_) async {
          calls.add('business');
          if (failBusiness) throw StateError('business read failed');
          return _business();
        },
        businessNames: (ids) async => {for (final i in ids) i: '테스트 사업장'},
      );
}

Future<void> _openAtt(WidgetTester tester, _AttReads r) async {
  await tester.pumpWidget(MaterialApp(
    home: ChangeNotifierProvider<UserProvider>(
      create: (_) => _PermissiveProvider(),
      child: Scaffold(
        body: AttendanceStatusDialog(
          date: _day,
          businessIds: const [_biz],
          initialBusinessId: _biz,
          reads: r.build(),
        ),
      ),
    ),
  ));
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  group('DayApplicants — 라운드 합치기', () {
    testWidgets('RC-1 전부 성공', (tester) async {
      final r = _DayReads();
      await _openDay(tester, r);
      expect(r.calls, containsAll(<String>['pending', 'confirmed',
        'staffing', 'invitations']));
      final t = _texts(tester);
      expect(t.contains('근로자 u1') || t.contains('근로자 u2'), isTrue,
          reason: '명단이 그려져야 한다');
      expect(t.contains('인력 현황을 확인하지 못해'), isFalse);
      expect(t.contains('초대 현황을 확인하지 못했어요'), isFalse);
    });

    testWidgets('RC-2 충원 실패는 명단을 지우지 않는다', (tester) async {
      final r = _DayReads()..failStaffing = true;
      await _openDay(tester, r);
      final t = _texts(tester);
      expect(t.contains('근로자 u1') || t.contains('근로자 u2'), isTrue,
          reason: '충원만 모르는 것이지 명단이 사라질 이유가 없다');
      expect(t.contains('인력 현황을 확인하지 못해'), isTrue,
          reason: '모름을 0으로 바꾸지 않는다');
    });

    testWidgets('RC-3 초대 실패는 초대 0명이 아니다', (tester) async {
      final r = _DayReads()..failInvites = true;
      await _openDay(tester, r);
      final t = _texts(tester);
      expect(t.contains('근로자 u1') || t.contains('근로자 u2'), isTrue);
      expect(t.contains('초대 현황을 확인하지 못했어요'), isTrue);
    });

    testWidgets('RC-4 지원자 실패는 화면 전체 ERROR', (tester) async {
      final r = _DayReads()..failPending = true;
      await _openDay(tester, r);
      final t = _texts(tester);
      expect(t.contains('근로자 u1'), isFalse,
          reason: '기반 데이터 실패는 기존처럼 전체 ERROR 다');
      expect(t.contains('근로자 u2'), isFalse);
    });

    testWidgets('RC-5 충원·초대가 둘 다 실패해도 명단은 남는다', (tester) async {
      final r = _DayReads()
        ..failStaffing = true
        ..failInvites = true;
      await _openDay(tester, r);
      final t = _texts(tester);
      expect(t.contains('근로자 u1') || t.contains('근로자 u2'), isTrue);
      expect(t.contains('인력 현황을 확인하지 못해'), isTrue);
      expect(t.contains('초대 현황을 확인하지 못했어요'), isTrue);
    });

    testWidgets('RC-13 canManageTo 가 없으면 초대 조회 자체가 없다 (NO_PERMISSION != ERROR)',
        (tester) async {
      final r = _DayReads();
      await tester.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => _NoInviteProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: DayApplicantsDialog(
              date: _day,
              businessIds: const [_biz],
              businesses: [_business()],
              reads: r.build(),
            ),
          ),
        ),
      ));
      await _settle(tester);
      expect(r.calls, isNot(contains('invitations')),
          reason: '권한이 없으면 서버도 거부한다 — 묻지 않는 것이 맞다');
      expect(r.calls, contains('staffing'),
          reason: '초대 게이트가 닫혀도 충원은 읽는다');
      final t = _texts(tester);
      expect(t.contains('초대 현황을 확인하지 못했어요'), isFalse,
          reason: '권한 없음을 조회 실패로 표시하지 않는다');
    });

    testWidgets('RC-6 충원·초대는 지원자 응답을 기다리지 않는다', (tester) async {
      final r = _DayReads()..baseGate = Completer<void>();
      await tester.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => _PermissiveProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: DayApplicantsDialog(
              date: _day,
              businessIds: const [_biz],
              businesses: [_business()],
              reads: r.build(),
            ),
          ),
        ),
      ));
      // 지원자/확정자는 아직 막혀 있다.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(r.calls, contains('staffing'),
          reason: '같은 라운드라면 지원자 응답 전에 이미 출발해 있어야 한다');
      expect(r.calls, contains('invitations'));
      r.baseGate!.complete();
      await _settle(tester);
      expect(_texts(tester).contains('근로자 u1') ||
          _texts(tester).contains('근로자 u2'), isTrue);
    });
  });

  group('Attendance — 라운드 합치기', () {
    testWidgets('RC-7 전부 성공', (tester) async {
      final r = _AttReads();
      await _openAtt(tester, r);
      expect(r.calls, containsAll(<String>['apps', 'staffing', 'business']));
      expect(_texts(tester).contains('정상 | 1'), isTrue);
    });

    testWidgets('RC-8 충원 실패는 근태 명단을 지우지 않는다', (tester) async {
      final r = _AttReads()..failStaffing = true;
      await _openAtt(tester, r);
      expect(_texts(tester).contains('정상 | 1'), isTrue,
          reason: '종료 여부만 모르는 것이다');
    });

    testWidgets('RC-9 사업장 실패는 명단을 비우지 않는다', (tester) async {
      final r = _AttReads()..failBusiness = true;
      await _openAtt(tester, r);
      expect(_texts(tester).contains('정상 | 1'), isTrue,
          reason: '반올림 정책을 못 읽은 것이 명단 0명이 되면 안 된다');
      // 표식을 남기지 않았으므로 다음 회차가 다시 읽는다 —
      // 같은 화면에서 새로고침하면 business 호출이 또 일어난다.
      final before = r.calls.where((c) => c == 'business').length;
      expect(before, 1);
    });

    testWidgets('RC-10 근무자 실패는 화면 전체 ERROR', (tester) async {
      final r = _AttReads()..failApplications = true;
      await _openAtt(tester, r);
      expect(_texts(tester).contains('정상 | 1'), isFalse);
    });

    testWidgets('RC-12 사업장 읽기 실패는 표식을 남기지 않는다 — 다음 회차가 다시 읽는다',
        (tester) async {
      // 반올림 정책은 사업장이 바뀐 회차에만 읽는다. 실패한 회차가 "읽었다"는
      // 표식을 남기면 그 사업장은 화면이 닫힐 때까지 영영 정책 없이 돈다.
      final r = _AttReads()
        ..failBusiness = true
        ..failApplications = true;
      await _openAtt(tester, r);
      expect(r.calls.where((c) => c == 'business').length, 1);
      // 기반 데이터 실패 → ERROR 상태의 '다시 시도' 로 두 번째 회차를 돈다.
      r.failApplications = false;
      await tester.tap(find.text('다시 시도'));
      await _settle(tester);
      expect(r.calls.where((c) => c == 'business').length, 2,
          reason: '실패한 회차가 표식을 남겼다면 두 번째 회차가 건너뛴다');
      expect(_texts(tester).contains('정상 | 1'), isTrue,
          reason: '재시도는 명단을 복구해야 한다');
    });

    testWidgets('RC-11 충원·사업장은 근무자 응답을 기다리지 않는다', (tester) async {
      final r = _AttReads()..baseGate = Completer<void>();
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<UserProvider>(
          create: (_) => _PermissiveProvider(),
          child: Scaffold(
            body: AttendanceStatusDialog(
              date: _day,
              businessIds: const [_biz],
              initialBusinessId: _biz,
              reads: r.build(),
            ),
          ),
        ),
      ));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(r.calls, contains('staffing'),
          reason: '같은 라운드라면 근무자 응답 전에 이미 출발해 있어야 한다');
      expect(r.calls, contains('business'));
      r.baseGate!.complete();
      await _settle(tester);
      expect(_texts(tester).contains('정상 | 1'), isTrue);
    });
  });
}
