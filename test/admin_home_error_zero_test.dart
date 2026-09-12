import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// AH-V2-01 ADMIN-HOME-ERROR-ZERO-RECOVERY
//
// invariant: ERROR != ZERO
//   관리자 Home의 '0명'은 "조회에 성공했고 실제 값이 0"만 의미해야 한다.
//   조회하지 못한 상태를 0으로 표현하면 관리자가
//   "오늘 아무 문제 없음"으로 오판한다.
//
// 이전 상태:
//   getBusinessesByIds  catch → []      (서비스가 실패를 0개로 변환)
//   _getBusinesses      catch → []      (화면이 한 번 더 변환)
//   _loadTodayAttendance isEmpty → 0/0  (실패가 정상 수치로 표시)
//
// 서버·Firestore를 붙이지 않고 실행할 수 없으므로 구조 수준 고정이다.
// ═══════════════════════════════════════════════════════════════

const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _bizServicePath = 'lib/services/firestore/business_firestore.dart';

String _src(String path) => File(path).readAsStringSync();

/// 주석 줄을 제거한 사본. 설명 주석이 배선 스캔에 잡히는 것을 막는다.
String _codeOf(String body) => body
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// 시그니처에서 시작해 중괄호 짝을 맞춰 메서드 본문만 잘라낸다.
/// 파라미터 목록의 중괄호를 본문 시작으로 오인하지 않는다.
String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: '$signature 를 찾지 못함');
  var paren = 0;
  var afterParams = start;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    if (source[i] == '(') paren++;
    if (source[i] == ')') {
      paren--;
      if (paren == 0) {
        afterParams = i;
        break;
      }
    }
  }
  final open = source.indexOf('{', afterParams);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  fail('$signature 본문의 끝을 찾지 못함');
}

void main() {
  late String home;
  late String homeCode;
  late String bizService;

  setUpAll(() {
    home = _src(_homePath);
    homeCode = _codeOf(home);
    bizService = _codeOf(_src(_bizServicePath));
  });

  // ───────────────────────────────────────────────────────────
  group('AHV2-01-01 실제 0 — SUCCESS_ZERO', () {
    test('사업장이 실제로 0개면 0/0을 표시한다', () {
      final body = _bodyOf(homeCode, 'Future<void> _loadTodayAttendance(');
      expect(body.contains('if (businesses.isEmpty)'), isTrue);
      expect(body.contains('_todayCheckedIn      = 0'), isTrue);
      expect(body.contains('_todayNeedsAttention = 0'), isTrue);
    });

    test('그 분기는 조회 성공 이후에만 도달한다', () {
      final body = _bodyOf(homeCode, 'Future<void> _loadTodayAttendance(');
      final fetchAt = body.indexOf('await _getBusinesses()');
      final emptyAt = body.indexOf('if (businesses.isEmpty)');
      expect(fetchAt, isNot(-1));
      expect(emptyAt, greaterThan(fetchAt));
    });
  });

  group('AHV2-01-02 사업장 조회 실패 → ERROR', () {
    test('서비스가 실패를 빈 목록으로 바꾸지 않는 변형을 제공한다', () {
      expect(
        bizService.contains(
            'Future<List<BusinessModel>> getBusinessesByIdsOrThrow('),
        isTrue,
      );
      final strict =
          _bodyOf(bizService, 'Future<List<BusinessModel>> getBusinessesByIdsOrThrow(');
      expect(strict.contains('사업장 일괄 조회 실패'), isFalse,
          reason: '조회 실패를 삼키는 catch가 남아 있으면 안 된다');
      expect(strict.contains('return null;'), isTrue,
          reason: '개별 문서 파싱 실패만 건너뛴다 (의도된 격리)');
      expect(strict.contains('if (ids.isEmpty) return [];'), isTrue,
          reason: 'ids가 비면 0개 반환은 유지 (실패 아님)');
    });

    test('화면 헬퍼가 strict 변형을 쓰고 실패를 삼키지 않는다', () {
      final body = _bodyOf(homeCode, 'Future<List<BusinessModel>> _getBusinesses(');
      expect(body.contains('getBusinessesByIdsOrThrow('), isTrue);
      expect(body.contains('catch'), isFalse,
          reason: '실패를 []로 변환하던 계약이 제거되어야 한다');
      expect(body.contains('return [];'), isFalse);
    });

    test('실패는 출근 로더의 ERROR 상태로 수렴한다', () {
      final body = _bodyOf(homeCode, 'Future<void> _loadTodayAttendance(');
      expect(body.contains('_todayCheckedIn      = null'), isTrue);
      expect(body.contains('_todayNeedsAttention = null'), isTrue);
    });

    test('상태 배너 입력도 실패를 0개로 받지 않는다', () {
      final body =
          _bodyOf(homeCode, 'Future<void> _loadApprovedBusinessStatus(');
      expect(body.contains('getBusinessesByIdsOrThrow('), isTrue,
          reason: '실패 시 사업장 있는 관리자에게 등록 배너가 뜨면 안 된다');
    });
  });

  group('AHV2-01-03 attendance 조회 실패 → ERROR', () {
    test('핵심 조회 실패 시 수치를 null로 둔다', () {
      final body = _bodyOf(homeCode, 'Future<void> _loadTodayAttendance(');
      final catchAt = body.lastIndexOf('} catch (e) {');
      expect(catchAt, isNot(-1));
      final tail = body.substring(catchAt);
      expect(tail.contains('_todayCheckedIn      = null'), isTrue);
      expect(tail.contains('= 0'), isFalse,
          reason: '실패 경로에서 0으로 되돌리면 안 된다');
    });

    test('UI가 null을 에러 표면으로 그린다', () {
      final body = _bodyOf(homeCode, 'Widget _buildAttendanceMetrics(');
      expect(body.contains('if (_todayCheckedIn == null)'), isTrue);
      expect(body.contains('출근 현황을 불러오지 못했습니다'), isTrue);
    });
  });

  group('AHV2-01-04 권한상 0개는 ERROR 아님', () {
    test('SubAdmin scope 계산이 그대로다', () {
      final body = _bodyOf(homeCode, 'Future<List<BusinessModel>> _getBusinesses(');
      expect(body.contains('isSubAdmin == true'), isTrue);
      expect(body.contains('up.effectiveBusinessId'), isTrue);
      expect(body.contains('managedBusinessIds'), isTrue);
    });

    test('ids가 비면 strict 변형도 정상 0개를 반환한다', () {
      final strict =
          _bodyOf(bizService, 'Future<List<BusinessModel>> getBusinessesByIdsOrThrow(');
      expect(strict.contains('if (ids.isEmpty) return [];'), isTrue);
    });

    test('권한 게이트는 변경되지 않았다', () {
      final body = _bodyOf(homeCode, 'Widget _buildAttendanceMetrics(');
      expect(body.contains('canManageWorkers'), isTrue);
    });
  });

  group('AHV2-01-05 재시도 복구', () {
    test('에러 표면의 재시도가 출근 로더를 다시 부른다', () {
      final body = _bodyOf(homeCode, 'Widget _buildAttendanceMetrics(');
      expect(body.contains('onRetry: () => unawaited(_loadTodayAttendance())'),
          isTrue);
    });

    test('실패 후 캐시가 남아 재시도를 막지 않는다', () {
      final body = _bodyOf(homeCode, 'Future<List<BusinessModel>> _getBusinesses(');
      // 캐시는 성공 경로에서만 채워진다 — 실패 시 _businesses는 비어 있어 재조회된다
      final assignAt = body.indexOf('_businesses = businesses');
      final awaitAt = body.indexOf('await _firestoreService.getBusinessesByIdsOrThrow');
      expect(assignAt, greaterThan(awaitAt));
    });

    test('로더 시작 시 로딩 상태로 전환된다', () {
      final body = _bodyOf(homeCode, 'Future<void> _loadTodayAttendance(');
      expect(body.contains('setState(() => _attendanceLoading = true)'), isTrue);
    });
  });

  group('AHV2-01-06 pull-to-refresh 복구', () {
    test('refresh가 출근 로더를 포함한다', () {
      final body = _bodyOf(homeCode, 'Future<void> _refresh(');
      expect(body.contains('_loadTodayAttendance()'), isTrue);
    });

    test('Home이 pull-to-refresh를 그 경로에 연결한다', () {
      expect(homeCode.contains('onRefresh: _refresh'), isTrue);
    });
  });

  group('AHV2-01-07 다른 caller 회귀', () {
    test('기존 관대한 계약이 남아 있어 외부 호출부가 영향받지 않는다', () {
      expect(
        bizService.contains('Future<List<BusinessModel>> getBusinessesByIds('),
        isTrue,
      );
      final lenient =
          _bodyOf(bizService, 'Future<List<BusinessModel>> getBusinessesByIds(');
      expect(lenient.contains('getBusinessesByIdsOrThrow('), isTrue,
          reason: '로직 중복 없이 위임해야 한다');
      expect(lenient.contains('return [];'), isTrue);
    });

    test('Home 밖 호출부는 계약 변경 대상이 아니다', () {
      for (final path in [
        'lib/screens/business_admin/business_list_screen.dart',
        'lib/screens/business_admin/member_management_screen.dart',
        'lib/screens/business_admin/payroll/payroll_overview_screen.dart',
        'lib/screens/business_admin/to_management/create_to_screen.dart',
        'lib/utils/business_picker_helper.dart',
      ]) {
        final src = _src(path);
        expect(src.contains('getBusinessesByIdsOrThrow'), isFalse,
            reason: '$path 는 이번 범위가 아니다');
      }
    });

    test('unawaited 로더가 throw를 밖으로 흘리지 않는다', () {
      final body = _bodyOf(homeCode, 'Future<void> _loadSummaryCounts(');
      final fetchAt = body.indexOf('await _getBusinesses()');
      final tryAt = body.indexOf('try {');
      expect(tryAt, isNot(-1));
      expect(tryAt, lessThan(fetchAt),
          reason: '_getBusinesses 호출이 try 안에 있어야 한다');
      expect(body.contains('_summaryLoading = false'), isTrue,
          reason: '실패해도 영구 로딩이 남으면 안 된다');
    });

    test('네비게이션 경로는 _safeNavigate가 감싼다', () {
      // _getBusinesses를 쓰는 탐색 진입점은 전부 오류 토스트로 수렴한다
      final safe = _bodyOf(homeCode, 'Future<void> _safeNavigate(');
      expect(safe.contains('catch'), isTrue);
      expect(safe.contains('처리 중 오류가 발생했습니다'), isTrue);
      for (final marker in [
        '_navigateToDayApplicantsForDate(context',
        '_openTodayAttendanceDialog(context)',
      ]) {
        expect(homeCode.contains(marker), isTrue);
      }
      final tapSites = '_safeNavigate('.allMatches(homeCode).length;
      expect(tapSites, greaterThanOrEqualTo(8));
    });
  });

  group('AHV2-01 stale 값 방지', () {
    test('실패 시 이전 성공 수치를 유지하지 않는다', () {
      final body = _bodyOf(homeCode, 'Future<void> _loadTodayAttendance(');
      final catchAt = body.lastIndexOf('} catch (e) {');
      final tail = body.substring(catchAt);
      // null 대입이 곧 stale 제거 — 이전 값이 그대로 남는 경로가 없어야 한다
      expect(tail.contains('_todayCheckedIn      = null'), isTrue);
      expect(tail.contains('_attendanceLoading   = false'), isTrue);
    });

    test('staffing 로더도 동일 원칙을 유지한다', () {
      final body = _bodyOf(homeCode, 'Future<void> _loadStaffingReadiness(');
      expect(body.contains('_staffingReadiness = null'), isTrue);
    });
  });

  group('AH-V2-01 범위 제한', () {
    test('다른 Home 섹션을 건드리지 않았다', () {
      for (final marker in [
        'Widget _buildStaffingMetrics(',
        'Widget _buildFutureStaffing(',
        'Widget _buildActionDashboard(',
        'Widget _buildPostingSetupCard(',
        'Widget _buildStateBanner(',
      ]) {
        expect(home.contains(marker), isTrue);
      }
    });

    test('섹션 순서가 그대로다', () {
      final body = _bodyOf(homeCode, 'Widget build(');
      final order = [
        '_buildHeader(',
        '_buildStateBanner(',
        '_buildPostingSetupCard(',
        '_buildTodayOps(',
        '_buildFutureStaffing(',
        '_buildActionDashboard(',
      ];
      var prev = -1;
      for (final m in order) {
        final at = body.indexOf(m);
        expect(at, greaterThan(prev), reason: '$m 순서가 바뀌었다');
        prev = at;
      }
    });

    // [AH-V2-03 갱신] 향후 7일 empty copy는 "대상 없음"/"충원 완료" 두 상태로
    // 분리됐다. AH-V2-01이 건드리지 않았다는 사실은 그대로이며,
    // 여기서는 분리된 새 계약을 고정한다.
    test('empty copy는 AH-V2-03 두 상태 계약을 따른다', () {
      expect(homeCode.contains('향후 7일 예정된 인력 운영이 없어요'), isTrue);
      expect(homeCode.contains('향후 7일 인원이 모두 충원됐어요'), isTrue);
      expect(homeCode.contains('처리할 업무가 없어요'), isTrue);
    });

    test('dead query를 제거하지 않았다 (AH-V2-05 범위)', () {
      expect(homeCode.contains('_summaryActiveTO'), isTrue);
    });
  });
}
