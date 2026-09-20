// [R8-P1C] 출근 한 번에 7개 쿼리가 나가던 것을 1개로 줄인다.
//
//   출퇴근·시간수정·노쇼·리셋·마감취소는 서버에서 attendance 문서만 바꾼다.
//   그런데 그 뒤에 _loadData()를 통째로 다시 돌려 지원서·업무유형·프로필·
//   계약 상태·모집단위 종료 여부까지 전부 다시 읽었다. 그중 여섯은 바뀐 것이
//   없는 데이터였다.
//
//   대신 서버가 실제로 자리·지원서까지 바꾸는 mutation은 전체 로드를 유지한다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _src() => File(
    'lib/screens/business_admin/dialogs/attendance_status_dialog.dart')
    .readAsStringSync();
String _fn() => File('functions/src/index.ts').readAsStringSync();

/// 주석으로 시작하는 줄만 제거한다 (문서 주석은 남는다).
String _codeOf(String raw) => raw
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 그룹 수집 시점에도 불리므로 expect 대신 예외로 실패시킨다.
String _sliceOf(String raw, String from, String to) {
  final i = raw.indexOf(from);
  if (i < 0) throw StateError('시작 표지를 찾지 못함: $from');
  final j = raw.indexOf(to, i + from.length);
  if (j < 0) throw StateError('끝 표지를 찾지 못함: $to');
  return raw.substring(i, j);
}

void main() {
  final raw = _src();
  final code = _codeOf(raw);
  final f = _flat(code);
  final scoped = _sliceOf(code, 'Future<void> _refreshAttendanceOnly() async {',
      'Future<void> _loadData() async {');
  final sf = _flat(scoped);

  group('AS-1 — 근태만 바꾸는 mutation은 근태만 다시 읽는다', () {
    test('AS-10 부분 갱신 경로가 존재하고 근태 조회 하나만 쓴다', () {
      expect(sf, contains('final map = await _getAttendanceRecords(appIds)'));
      // 지원서·업무유형·프로필·계약·모집단위를 다시 읽지 않는다
      for (final forbidden in [
        '_getConfirmedWorkersForDate(', '_getWorkTypeInfo(',
        'getUsersBatch(', 'getContractStatusBatch(', 'getDayStaffingDetail(',
      ]) {
        expect(scoped.contains(forbidden), false, reason: forbidden);
      }
    });

    test('AS-11 갱신하는 상태는 근태 맵과 파생 캐시뿐이다', () {
      expect(sf, contains('_attendanceMap = map'));
      expect(sf, contains('_rebuildStatusCache()'));
      expect(sf, contains('_rebuildTabWorkers()'));
      expect(scoped.contains('_confirmedWorkers ='), false);
      expect(scoped.contains('_userMap ='), false);
      expect(scoped.contains('_contractStatusMap ='), false);
    });

    test('AS-12 여덟 곳이 부분 갱신을 쓴다', () {
      // 정의 1 + 호출 8
      expect('_refreshAttendanceOnly()'.allMatches(code).length, 9);
    });
  });

  group('AS-2 — 서버가 더 넓게 쓰는 mutation은 전체 로드를 유지한다', () {
    final fn = _fn();

    test('AS-20 노쇼 취소는 지원서·슬롯까지 바꾼다 — 전체 로드 유지', () {
      final cancel = _sliceOf(fn, 'export const callableBatchCancelNoShow =',
          'export const callableBatchResetAttendance');
      expect(_flat(_codeOf(cancel)), contains('collection("applications").doc(restore.appId)'));
      // 클라이언트도 전체 로드를 유지한다
      final handler = _sliceOf(code, "httpsCallable('callableBatchCancelNoShow')",
          'Future<void> _showBatchResetDialog() async {');
      expect(_flat(handler), contains('await _loadData();'));
    });

    test('AS-21 자리 반납(대체 모집)은 전체 로드 유지', () {
      expect(f, contains('releaseNoshowSeat('));
      final rel = _sliceOf(code, 'releaseNoshowSeat(', 'DayApplicantsDialog');
      expect(_flat(rel), contains('unawaited(_loadData())'));
    });

    test('AS-22 사업장 전환은 전체 로드 유지', () {
      expect(f, contains('if (value != null && value != _selectedBusinessId)'));
    });
  });

  group('AS-3 — 서버 권위를 추측으로 대체하지 않는다', () {
    test('AS-30 응답값으로 status를 지어내지 않는다', () {
      expect(scoped.contains("status = 'present'"), false);
      expect(scoped.contains('copyWith(status:'), false);
      expect(scoped.contains('checkInAt:'), false);
    });

    test('AS-31 성공 id만 골라 패치하지 않고 그 날 근태를 다시 읽는다', () {
      expect(sf, contains('final appIds = _confirmedWorkers.map((a) => a.id).toList()'));
    });

    test('AS-32 근태 조회는 여전히 서버 CF다', () {
      final rec = _sliceOf(code, 'Future<Map<String, AttendanceModel>> _getAttendanceRecords',
          'Future<Map<String, BusinessWorkTypeModel>> _getWorkTypeInfo');
      expect(_flat(rec), contains("httpsCallable('callableGetAdminAttendances'"));
    });
  });

  group('AS-4 — 늦은 응답이 최신 화면을 덮지 않는다', () {
    test('AS-40 세대 번호로 stale 응답을 버린다', () {
      expect(sf, contains('final seq = ++_attRefreshSeq'));
      expect(sf, contains('if (!mounted || seq != _attRefreshSeq) return'));
    });

    test('AS-41 전체 로드가 진행 중인 부분 갱신을 무효화한다', () {
      final load = _sliceOf(code, 'Future<void> _loadData() async {',
          'Future<List<ApplicationModel>> _getConfirmedWorkersForDate');
      expect(_flat(load), contains('_attRefreshSeq++'));
    });
  });

  group('AS-5 — 처리와 갱신을 구분해서 말한다', () {
    test('AS-50 갱신 실패를 처리 실패라고 하지 않는다', () {
      expect(sf, contains('처리는 완료됐어요. 최신 상태를 불러오지 못해 다시 불러옵니다.'));
    });

    test('AS-51 갱신 실패 시 낡은 화면을 그대로 두지 않는다', () {
      expect(sf, contains('await _loadData();'));
    });
  });

  group('AS-6 — 부분 실패 의미가 그대로다', () {
    test('AS-60 출근 partial 경고가 유지된다', () {
      expect(f, contains("'\$processed명 출근 처리 · \$failed명 처리하지 못했습니다'"));
    });

    test('AS-61 퇴근 partial 경고가 유지된다', () {
      expect(f, contains("'\$processed명 퇴근 처리 · \$failed명 처리하지 못했습니다'"));
    });

    test('AS-62 실패한 행을 성공처럼 덮어쓰지 않는다 — 서버 값을 그대로 읽는다', () {
      // 성공 id 목록 기반 부분 패치가 아니라 전체 재조회이므로
      // 실패 행은 서버의 기존 값 그대로 들어온다
      expect(sf, isNot(contains('processed')));
      expect(sf, isNot(contains('failures')));
    });
  });
}
