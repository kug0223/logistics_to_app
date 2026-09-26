// [R7-P1-2.2] staffing 지원자 읽기 — 서버가 먼저 막는다.
//
//   d2f8206 은 권한을 잃은 뒤 화면에서 지원자를 지웠다. 그런데 DEV 런타임이
//   보여준 것은 이랬다.
//
//     canManageTo=false 인 멤버가 callableGetApplicationsByBiz 로
//     지원서 50건을 그대로 받았다.
//
//   화면이 감췄을 뿐 payload 는 이미 기기에 도착해 있었다. 그건 authorization
//   이 아니다 — UI hide 로 닫을 수 있는 구멍이 아니다.
//
//   서버에는 이미 맞는 계약이 있었다: `purpose=applicantReview` 면 canManageTo
//   를 strict 로 본다. staffing caller 가 그 purpose 를 **넘기지 않아서**
//   membership-only 분기로 빠진 것이 root cause 였다.
//
//   그래서 여기서 지키는 두 문장.
//
//     지원자 관리 화면의 읽기는 서버에서 canManageTo 를 요구한다.
//     다른 목적 reader 는 그 때문에 깨지지 않는다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

String _codeOf(String dart) => dart
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  expect(i, greaterThan(-1), reason: '구간 시작을 찾지 못했다: $start');
  final j = src.indexOf(end, i + start.length);
  expect(j, greaterThan(i), reason: '구간 끝을 찾지 못했다: $end');
  return src.substring(i, j);
}

/// 서버 함수 하나를 잘라낸다.
String _callable(String ts, String name) =>
    _slice(ts, 'export const $name = onCall(', '\nexport const ');

void main() {
  late String cf;
  late String getApps;
  late String appService;
  late String workDialog;
  late String dayDialog;

  setUpAll(() {
    cf = _read('functions/src/index.ts');
    getApps = _callable(cf, 'callableGetApplicationsByBiz');
    appService =
        _codeOf(_read('lib/services/firestore/application_firestore.dart'));
    workDialog = _codeOf(
        _read('lib/screens/business_admin/dialogs/work_applicants_dialog.dart'));
    dayDialog = _codeOf(
        _read('lib/screens/business_admin/dialogs/day_applicants_dialog.dart'));
  });

  // ══════════════════════════════════════════════════════════════
  // A~E. 서버 계약
  // ══════════════════════════════════════════════════════════════

  group('SAP-A 서버 권한 계약', () {
    test('SAP-A1 applicantReview 는 canManageTo 를 strict 로 본다', () {
      expect(getApps, contains('const isApplicantReview = purpose === "applicantReview";'));
      final branch =
          _slice(getApps, 'if (isApplicantReview) {', '} else {');
      expect(branch, contains('appsPerms?.canManageTo !== true'));
      expect(branch, contains('"permission-denied"'));
    });

    test('SAP-B payload 를 만들기 전에 막는다', () {
      // 권한 판정이 쿼리·응답 생성보다 앞에 있어야 한다.
      final deny = getApps.indexOf('"TO 관리 권한이 없습니다."');
      final query = getApps.indexOf('db\n      .collection("applications")');
      expect(deny, greaterThan(-1));
      expect(query, greaterThan(-1),
          reason: 'applications 쿼리를 찾지 못했다 — 앵커를 다시 봐야 한다');
      expect(deny, lessThan(query),
          reason: '쿼리를 돌린 뒤 거르면 이미 읽은 것이다');
    });

    test('SAP-C owner / adminIds / SUPER_ADMIN 은 통과한다', () {
      final full = _slice(getApps, 'const appsIsFullAccess =', 'if (!appsIsFullAccess)');
      expect(full, contains('"SUPER_ADMIN"'));
      expect(full, contains('appsAdminIds.includes(callerUid)'));
      expect(full, contains('appsOwnerId === callerUid'));
    });

    test('SAP-D/E membership 을 먼저 확인한다', () {
      final assertIdx = getApps.indexOf('await assertBizAdmin(callerUid, businessId)');
      final permIdx = getApps.indexOf('const appsIsFullAccess =');
      expect(assertIdx, greaterThan(-1));
      expect(assertIdx, lessThan(permIdx),
          reason: '멤버십 확인이 권한 분기보다 먼저여야 한다');
    });

    test('SAP-E2 알 수 없는 purpose 는 거부된다', () {
      expect(getApps, contains('허용되지 않는 purpose 값'));
      expect(getApps, contains('"invalid-argument"'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // F. staffing caller 가 purpose 를 넘긴다
  // ══════════════════════════════════════════════════════════════

  group('SAP-F staffing caller', () {
    test('SAP-F1 서비스가 purpose 를 실어 보낸다', () {
      for (final m in [
        'getApplicationsByTOId',
        'getApplicationsBySlotId',
        'getPendingApplicationsByDateAndBusiness',
      ]) {
        expect(appService, contains(m));
      }
      // 세 메서드 모두 payload 에 purpose 를 조건부로 넣는다.
      final occurrences =
          "if (purpose != null) 'purpose': purpose,".allMatches(appService).length;
      expect(occurrences, 3,
          reason: 'purpose 를 전달하는 자리가 3곳이어야 한다 (실제 $occurrences)');
    });

    test('SAP-F2 인력 현황 다이얼로그가 applicantReview 를 넘긴다', () {
      final loader = _slice(workDialog, 'final List<ApplicationModel> apps;',
          'final uniqueUids');
      expect(loader, contains('getApplicationsBySlotId'));
      expect(loader, contains('getApplicationsByTOId'));
      expect('FirestoreService.purposeApplicantReview'.allMatches(loader).length,
          2,
          reason: '두 조회 경로 모두 purpose 를 넘겨야 한다');
    });

    test('SAP-F3 당일 명단이 대기 지원자 조회에 applicantReview 를 넘긴다', () {
      final phase =
          _slice(dayDialog, 'final phase1 = await Future.wait([', ']);');
      expect(phase, contains('getPendingApplicationsByDateAndBusiness'));
      expect(phase, contains('FirestoreService.purposeApplicantReview'));
    });

    test('SAP-F4 purpose 상수를 새로 만들지 않았다', () {
      final svc = _codeOf(_read('lib/services/firestore_service.dart'));
      expect(svc,
          contains("static const String purposeApplicantReview = 'applicantReview';"));
      for (final invented in ['purposeStaffing', 'purposeApplicantManage']) {
        expect(svc, isNot(contains(invented)), reason: '새 purpose: $invented');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // G·H. 회귀 — 다른 목적 reader 를 깨지 않는다
  // ══════════════════════════════════════════════════════════════

  group('SAP-H 비-staffing 회귀', () {
    test('SAP-H1 네 권한 OR 분기가 그대로다', () {
      final other = _slice(getApps, '} else {', 'const cap =');
      expect(other, contains('APPLICATION_READ_PERMISSIONS'));
      for (final p in [
        '"canManageTo"',
        '"canManageWorkers"',
        '"canManageWage"',
        '"canManageContract"',
      ]) {
        expect(other, contains(p), reason: '정상 reader 를 잃었다: $p');
      }
      expect(other, contains('"지원서 조회 권한이 없습니다."'));
    });

    test('SAP-H2 blanket canManageTo 로 바꾸지 않았다', () {
      // purpose 가 없으면 canManageTo 를 요구하지 않는다.
      final other = _slice(getApps, '} else {', 'const cap =');
      expect(other, contains('.some((p) => appsPerms?.[p] === true)'),
          reason: '넷 중 하나 OR 가 아니라 단일 권한 강제로 바뀌었다');
    });

    test('SAP-H3 확정 근무자 reader 는 purpose 를 넘기지 않는다', () {
      // Home·근무 운영 화면이 같은 reader 를 쓴다 — canManageWorkers 가 정상이다.
      final confirmed = _slice(appService,
          'Future<List<ApplicationModel>> getConfirmedWorkersByDateAndBusinessOrThrow(',
          'Future<Set<DateTime>> getSeatedWorkDatesInRange(');
      expect(confirmed, isNot(contains('purpose')));

      for (final path in [
        'lib/screens/business_admin/business_admin_home_screen.dart',
        'lib/screens/business_admin/workforce_management/workforce_operational_view.dart',
      ]) {
        final s = _codeOf(_read(path));
        final call = s.indexOf('getConfirmedWorkersByDateAndBusinessOrThrow');
        expect(call, greaterThan(-1), reason: '$path — reader 를 잃었다');
        final window = s.substring(call, (call + 260).clamp(0, s.length));
        expect(window, isNot(contains('purposeApplicantReview')),
            reason: '$path — 이 화면까지 canManageTo 로 좁혔다');
      }
    });

    test('SAP-G pagination 계약이 그대로다', () {
      expect(getApps, contains('startAfterDocId'));
      expect(appService, contains('startAfterDocId'));
      final paged = _slice(appService,
          'Future<List<Map<String, dynamic>>> fetchApplicationsByBizPaged(',
          'Future<List<ApplicationModel>> getApplicationsByTOId(');
      expect(paged, contains('startAfterDocId'));
      // purpose 를 넣는다고 paging payload 가 사라지면 안 된다.
      expect(paged, contains('maxPages'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // I·J. 클라이언트 쪽 계약
  // ══════════════════════════════════════════════════════════════

  group('SAP-I 클라이언트 매핑', () {
    test('SAP-I1 서버 DENY 가 NO_PERMISSION 으로 간다', () {
      expect(workDialog, contains('_loadDenied = isPermissionDenial(e);'));
      expect(workDialog, contains('_buildNoPermissionState()'));
      // generic ERROR 로 되돌리지 않는다.
      final handler = _slice(workDialog, 'Future<void> _loadApplicants() async {',
          'Future<void> _runLoadApplicants()');
      final denied = _slice(handler, '} else if (denied) {', '} else if (hadRows) {');
      expect(denied, contains('_loadFailed = false;'));
      expect(denied, contains('_refreshFailed = false;'));
    });

    test('SAP-I2 DENY 뒤에 사람 정보 조회가 이어지지 않는다', () {
      // 명단 조회가 rethrow 하면 그 뒤 getUsersBatch 는 실행되지 않는다.
      final body = _slice(workDialog, 'final List<ApplicationModel> apps;',
          'final userMapFuture');
      expect(body, contains('rethrow;'));
      final appsIdx = workDialog.indexOf('final List<ApplicationModel> apps;');
      final usersIdx = workDialog.indexOf('final userMapFuture');
      expect(appsIdx, lessThan(usersIdx),
          reason: '거부된 뒤에도 사람 정보를 부르면 불필요한 노출 시도다');
    });

    test('SAP-J 이번에 손댄 경로에 문자열 권한 판정이 없다', () {
      for (final s in [workDialog, dayDialog, appService]) {
        for (final banned in [
          "contains('permission-denied')",
          "contains('PERMISSION_DENIED')",
          "message.contains('권한')",
        ]) {
          expect(s, isNot(contains(banned)), reason: '문자열 파싱: $banned');
        }
      }
      expect(workDialog, contains('.code'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 범위 가드
  // ══════════════════════════════════════════════════════════════

  test('SAP-Z rules / indexes 를 건드리지 않았다', () {
    // 이번 변경은 callable 권한 분기와 caller purpose 뿐이다.
    final rules = _read('firestore.rules');
    expect(rules, contains('match /applications/{applicationId}'));
    // getUsersBatch 의 workerDirectory 계약은 그대로다.
    expect(cf, contains('const isWorkerDirectory = purpose === "workerDirectory";'));
  });
}
