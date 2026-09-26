// [R7-P1-2.3] 지원서 조회 — 목적이 곧 권한 경계다.
//
//   1a61876 까지의 상태는 이랬다.
//
//     purpose 를 생략하면 네 권한 중 하나로 통과했고,
//     통과한 호출은 applicantReview 와 **같은 전체 payload** 를 받았다.
//
//   즉 canManageWorkers 만 가진 SubAdmin 이 purpose 를 빼는 것만으로 지원자
//   명단 전체를 가져갈 수 있었다. 권한이 caller 의 정직함 위에 서 있었다 —
//   그건 경계가 아니다.
//
//   그래서 두 문장을 고정한다.
//
//     목적을 말하지 않은 조회는 받지 않는다.
//     목적마다 그 도메인의 권한을 본다.
//
//   새 권한을 만들지 않았다. 이미 있는 네 개로 나눴을 뿐이다.

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

/// `fetchApplicationsByBizPaged({ ... })` 호출 하나하나를 잘라낸다.
List<({String file, int line, String body})> _callSites() {
  final out = <({String file, int line, String body})>[];
  for (final f in Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {
    final lines = _codeOf(f.readAsStringSync()).split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].contains('fetchApplicationsByBizPaged({')) continue;
      final buf = <String>[];
      for (var j = i; j < lines.length && j < i + 20; j++) {
        buf.add(lines[j]);
        if (RegExp(r'^\s*\}[,)]').hasMatch(lines[j])) break;
      }
      out.add((file: f.path, line: i + 1, body: buf.join('\n')));
    }
  }
  return out;
}

const _validPurposes = {
  'applicantReview',
  'workerOperation',
  'contractReview',
  'capacity',
};

void main() {
  late String cf;
  late String getApps;

  setUpAll(() {
    cf = _read('functions/src/index.ts');
    getApps =
        _slice(cf, 'export const callableGetApplicationsByBiz = onCall(',
            '\nexport const ');
  });

  // ══════════════════════════════════════════════════════════════
  // A·B. 목적 없는 조회는 없다
  // ══════════════════════════════════════════════════════════════

  group('ALP-A 목적 전수', () {
    test('ALP-A1 모든 호출부가 purpose 를 싣는다', () {
      final sites = _callSites();
      expect(sites.length, greaterThanOrEqualTo(20),
          reason: '호출부를 제대로 못 읽었다 (${sites.length}건)');
      final missing = sites
          .where((s) => !s.body.contains('purpose'))
          .map((s) => '${s.file}:${s.line}')
          .toList();
      expect(missing, isEmpty,
          reason: '목적 없이 지원서를 읽는 곳이 남았다:\n${missing.join('\n')}');
    });

    test('ALP-A2 쓰인 purpose 값이 서버 허용 목록 안에 있다', () {
      final used = <String>{};
      for (final s in _callSites()) {
        for (final m
            in RegExp(r"'purpose': '([a-zA-Z]+)'").allMatches(s.body)) {
          used.add(m.group(1)!);
        }
      }
      // 상수로 넘기는 자리는 상수 정의로 확인한다(아래 ALP-A3).
      final unknown = used.difference(_validPurposes);
      expect(unknown, isEmpty, reason: '서버가 모르는 purpose: $unknown');
    });

    test('ALP-A3 purpose 상수가 서버 목록과 일치한다', () {
      final svc = _codeOf(_read('lib/services/firestore_service.dart'));
      const pairs = {
        'purposeApplicantReview': 'applicantReview',
        'purposeWorkerOperation': 'workerOperation',
        'purposeContractReview': 'contractReview',
        'purposeCapacity': 'capacity',
      };
      pairs.forEach((name, value) {
        expect(svc, contains("static const String $name = '$value';"),
            reason: '상수 누락: $name');
        expect(getApps, contains('$value:'),
            reason: '서버 허용 목록에 없다: $value');
      });
    });

    test('ALP-B broad OR fallback 이 사라졌다', () {
      // 옛 분기: purpose 없으면 네 권한 중 하나로 통과.
      expect(getApps, isNot(contains('APPLICATION_READ_PERMISSIONS')),
          reason: '생략 시 통과하던 분기가 남아 있다');
      expect(getApps, contains('지원서 조회 목적(purpose)이 필요합니다.'));
      final guard = _slice(getApps, 'const purposeKnown =', 'const isCapacityRead');
      expect(guard, contains('hasOwnProperty.call(APPLICATION_READ_PURPOSES'));
      expect(guard, contains('"invalid-argument"'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // C~G. 목적 → 권한 매핑
  // ══════════════════════════════════════════════════════════════

  group('ALP-C 목적별 canonical capability', () {
    late String map;
    setUpAll(() {
      map = _slice(getApps,
          'const APPLICATION_READ_PURPOSES: Record<string, string[]> = {',
          '};');
    });

    test('ALP-C applicantReview → canManageTo', () {
      expect(map, contains('applicantReview: ["canManageTo"],'));
    });

    test('ALP-D workerOperation → canManageWorkers', () {
      expect(map, contains('workerOperation: ["canManageWorkers"],'));
    });

    test('ALP-E contractReview → canManageContract', () {
      expect(map, contains('contractReview: ["canManageContract"],'));
    });

    test('ALP-F capacity → 네 권한 중 하나 (projection 축소로 상쇄)', () {
      final cap = _slice(map, 'capacity: [', '],');
      for (final c in [
        'canManageTo',
        'canManageWorkers',
        'canManageWage',
        'canManageContract',
      ]) {
        expect(cap, contains(c));
      }
    });

    test('ALP-G 교차 권한은 거부된다 — 단일 required 배열', () {
      // applicantReview / workerOperation / contractReview 는 각각 하나뿐이다.
      for (final p in ['applicantReview', 'workerOperation', 'contractReview']) {
        final entry = RegExp('$p: \\[([^\\]]*)\\]').firstMatch(map)!.group(1)!;
        expect(entry.split(',').where((s) => s.trim().isNotEmpty).length, 1,
            reason: '$p 가 여러 권한으로 열려 있다');
      }
      expect(getApps, contains('required.some((p) => appsPerms?.[p] === true)'));
    });

    test('ALP-G2 새 permission capability 를 만들지 않았다', () {
      for (final invented in [
        'canReviewApplicants',
        'canReadApplications',
        'canViewStaffing',
      ]) {
        expect(cf, isNot(contains(invented)), reason: '새 capability: $invented');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // H·I. 소속·권한 0
  // ══════════════════════════════════════════════════════════════

  test('ALP-H 소속 확인이 권한 분기보다 먼저다', () {
    final assertIdx = getApps.indexOf('await assertBizAdmin(callerUid, businessId)');
    final permIdx = getApps.indexOf('const appsIsFullAccess =');
    expect(assertIdx, greaterThan(-1));
    expect(assertIdx, lessThan(permIdx));
  });

  test('ALP-I payload 생성 전에 거부한다', () {
    final deny = getApps.indexOf('throw new HttpsError("permission-denied", deny[purpose]);');
    final query = getApps.indexOf('db\n      .collection("applications")');
    expect(deny, greaterThan(-1));
    expect(query, greaterThan(-1));
    expect(deny, lessThan(query), reason: '읽은 뒤 거르면 이미 읽은 것이다');
  });

  // ══════════════════════════════════════════════════════════════
  // L. 정원 조회는 사람을 식별하지 않는다
  // ══════════════════════════════════════════════════════════════

  group('ALP-L projection 격리', () {
    test('ALP-L1 정원 allowlist 에 식별 field 가 없다', () {
      final allow = _slice(getApps,
          'const CAPACITY_ALLOWED_FIELDS = new Set([', ']);');
      for (final banned in [
        '"uid"',
        '"userName"',
        '"name"',
        '"phone"',
        '"wage"',
        '"snapshotWage"',
        '"idCardConsentGiven"',
        '"trustScore"',
      ]) {
        expect(allow, isNot(contains(banned)),
            reason: '정원 계산에 필요 없는 값을 내보낸다: $banned');
      }
    });

    test('ALP-L2 정원 계산에 필요한 field 는 남아 있다', () {
      final allow = _slice(getApps,
          'const CAPACITY_ALLOWED_FIELDS = new Set([', ']);');
      for (final need in [
        '"status"',
        '"workDetailId"',
        '"wdId"',
        '"slotId"',
        '"staffingReleasedAt"',
      ]) {
        expect(allow, contains(need), reason: '정원 계산이 깨진다: $need');
      }
    });

    test('ALP-L3 정원 응답만 축소되고 다른 목적은 그대로다', () {
      final ret = _slice(getApps, 'applications: pageDocs.map(', 'hasMore,');
      expect(ret, contains('if (!isCapacityRead) return {id: d.id, ...data};'));
      expect(ret, contains('CAPACITY_ALLOWED_FIELDS.has(k)'));
    });

    test('ALP-L4 정원 목적을 쓰는 곳이 식별 field 를 읽지 않는다', () {
      // edit_to_screen 이 쓰는 key 는 정원 allowlist 안에 있어야 한다.
      final edit = _codeOf(
          _read('lib/screens/business_admin/to_management/edit_to_screen.dart'));
      expect(edit, contains('purposeCapacity'));
      for (final banned in ["app['uid']", "app['userName']", "app['wage']"]) {
        expect(edit, isNot(contains(banned)),
            reason: '정원 projection 에 없는 값을 읽는다: $banned');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // J·K. 목적이 중간 layer 에서 사라지지 않는다
  // ══════════════════════════════════════════════════════════════

  group('ALP-J 목적 보존', () {
    test('ALP-J1 페이징 헬퍼가 payload 를 그대로 이어 쓴다', () {
      final appService =
          _codeOf(_read('lib/services/firestore/application_firestore.dart'));
      final paged = _slice(appService,
          'Future<List<Map<String, dynamic>>> fetchApplicationsByBizPaged(',
          'Future<List<ApplicationModel>> getApplicationsByTOId(');
      // 2페이지 이후에도 같은 data 에 cursor 만 얹어야 한다.
      expect(paged, contains('startAfterDocId'));
      expect(paged, isNot(contains("data.remove('purpose')")));
      expect(paged, isNot(contains("..remove('purpose')")));
    });

    test('ALP-K 서비스 layer 가 purpose 를 떨어뜨리지 않는다', () {
      final appService =
          _codeOf(_read('lib/services/firestore/application_firestore.dart'));
      // purpose 를 받는 세 메서드는 반드시 payload 에 다시 넣는다.
      final threaded =
          "if (purpose != null) 'purpose': purpose,".allMatches(appService).length;
      expect(threaded, 3, reason: 'purpose 를 받고도 안 쓰는 메서드가 있다');
    });

    test('ALP-K2 staffing 화면이 canonical 상수를 쓴다', () {
      final work = _codeOf(_read(
          'lib/screens/business_admin/dialogs/work_applicants_dialog.dart'));
      final day = _codeOf(_read(
          'lib/screens/business_admin/dialogs/day_applicants_dialog.dart'));
      expect('FirestoreService.purposeApplicantReview'.allMatches(work).length, 2);
      expect(day, contains('FirestoreService.purposeApplicantReview'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 13. worker self 경로 분리
  // ══════════════════════════════════════════════════════════════

  test('ALP-M 본인 조회는 이 callable 을 쓰지 않는다', () {
    final appService =
        _codeOf(_read('lib/services/firestore/application_firestore.dart'));
    final selfBranch = _slice(appService,
        'if (uid != null && uid.isNotEmpty) {', 'return (result.data');
    expect(selfBranch, contains('callableGetMyApplications'),
        reason: '본인 조회에 관리자 권한 계약을 적용하면 안 된다');
    expect(selfBranch, isNot(contains('purpose')));
  });

  // ══════════════════════════════════════════════════════════════
  // 범위 가드
  // ══════════════════════════════════════════════════════════════

  test('ALP-Z 다른 계약을 건드리지 않았다', () {
    // getUsersBatch 의 purpose 계약은 그대로다.
    expect(cf, contains('const isWorkerDirectory = purpose === "workerDirectory";'));
    expect(cf, contains('const isApplicantReview = purpose === "applicantReview";'),
        reason: 'getUsersBatch 쪽 분기까지 지우면 안 된다');
    // 클라이언트 NO_PERMISSION 계약 유지.
    final work = _codeOf(_read(
        'lib/screens/business_admin/dialogs/work_applicants_dialog.dart'));
    expect(work, contains('_buildNoPermissionState()'));
    expect(work, contains('isPermissionDenial'));
  });
}
