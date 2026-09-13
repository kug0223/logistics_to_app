import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// AH-V2-05A HOME-DEAD-LOADER-REMOVAL
//
// Home은 진입·새로고침마다 사업장 수만큼 callableGetTOsByBiz를 호출하고
// 결과를 전량 버리고 있었다. 화면·navigation·정책 어디에도 consumer가 없었다.
//
// 순수 제거다. 대체 쿼리를 넣지 않고, 보이는 것은 하나도 바뀌지 않는다.
// ═══════════════════════════════════════════════════════════════

const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';

String _src(String p) => File(p).readAsStringSync();
String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

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
  late String raw;
  late String home;

  setUpAll(() {
    raw = _src(_homePath);
    home = _codeOf(raw);
  });

  // ───────────────────────────────────────────────────────────
  // PERF-01 / 02 죽은 심볼 제거
  // ───────────────────────────────────────────────────────────
  group('PERF-01/02 dead symbols', () {
    test('PERF-01 _loadSummaryCounts가 없다', () {
      expect(home.contains('_loadSummaryCounts'), isFalse);
    });

    test('PERF-02 죽은 상태 필드가 없다', () {
      for (final sym in [
        '_summaryActiveTO',
        '_summaryLoading',
        '_summaryRequestGeneration',
      ]) {
        expect(home.contains(sym), isFalse, reason: sym);
      }
    });

    test('이 값만 갱신하던 revision listener도 함께 사라졌다', () {
      for (final sym in [
        '_lastSeenPostingRevision',
        '_onPostingRevisionChanged',
        'WorkforceController.dataRevision',
      ]) {
        expect(home.contains(sym), isFalse, reason: sym);
      }
    });

    test('연쇄 미사용 import가 정리됐다', () {
      expect(raw.contains("import '../../controllers/workforce_controller.dart';"),
          isFalse);
    });

    test('ignore: unused_field 우회가 남아 있지 않다', () {
      expect(raw.contains('// ignore: unused_field'), isFalse,
          reason: '죽은 필드를 숨기던 pragma가 제거돼야 한다');
    });
  });

  // ───────────────────────────────────────────────────────────
  // PERF-03 Home callable inventory
  // ───────────────────────────────────────────────────────────
  group('PERF-03 Home callable 인벤토리', () {
    test('Home에서 TO 목록 조회가 0건', () {
      // 프로젝트 전체가 아니라 Home 화면에서만 0건을 요구한다.
      expect(home.contains('getTOsByBusiness'), isFalse);
      expect(home.contains('callableGetTOsByBiz'), isFalse);
    });

    test('Home이 직접 호출하는 callable이 없다 (서비스 경유만)', () {
      expect(home.contains('httpsCallable'), isFalse);
    });

    test('남은 고정 callable 2종은 서비스로 유지된다', () {
      expect(home.contains('AdminHomeSummaryService()'), isTrue);
      expect(home.contains('StaffingReadinessService.fetchReadiness('), isTrue);
    });

    test('§16 대체 쿼리를 추가하지 않았다', () {
      // TO를 다시 세는 어떤 경로도 생기지 않아야 한다
      expect(home.contains('activeTO'), isFalse);
      expect(home.contains("status == 'ACTIVE'"), isFalse);
      expect(home.contains('TOStatus.openStates'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────
  // PERF-04 로더·refresh 계약
  // ───────────────────────────────────────────────────────────
  group('PERF-04 남은 로더', () {
    test('로더 정의 집합이 정확히 5종', () {
      final loaders = RegExp(r'Future<void> (_load[A-Za-z]*)\(')
          .allMatches(raw)
          .map((m) => m.group(1))
          .toSet();
      expect(loaders, {
        '_loadApprovedBusinessStatus',
        '_loadCanonicalSummary',
        '_loadPostingReadiness',
        '_loadStaffingReadiness',
        '_loadTodayAttendance',
      });
    });

    test('refresh가 실제 loader만 호출한다', () {
      final r = _bodyOf(home, 'Future<void> _refresh(');
      for (final l in [
        '_loadCanonicalSummary()',
        '_loadStaffingReadiness()',
        '_loadTodayAttendance()',
        '_reloadReadiness()',
      ]) {
        expect(r.contains(l), isTrue, reason: l);
      }
      expect(r.contains('_loadSummaryCounts'), isFalse);
      expect(r.contains('_isRefreshing'), isTrue);
      expect(r.contains('await Future.wait(['), isTrue);
    });

    test('AH-V2-03 readiness refresh 계약 유지', () {
      final rr = _bodyOf(home, 'Future<void> _reloadReadiness(');
      expect(rr.indexOf('_loadApprovedBusinessStatus()'),
          lessThan(rr.indexOf('_loadPostingReadiness()')));
    });

    test('사업장 전환 시 재조회 목록에서도 빠졌다', () {
      final s = _bodyOf(home, 'void _onBusinessSwitchCheck(');
      expect(s.contains('_loadSummaryCounts'), isFalse);
      for (final l in [
        '_loadApprovedBusinessStatus()',
        '_loadStaffingReadiness()',
        '_loadTodayAttendance()',
        '_loadPostingReadiness()',
        '_loadCanonicalSummary()',
      ]) {
        expect(s.contains(l), isTrue, reason: l);
      }
    });

    test('FCM·앱 복귀 신선도 경로는 유지된다', () {
      expect(home.contains('addAdminRefreshListener(_onFcmRefresh)'), isTrue);
      expect(home.contains('if (state == AppLifecycleState.resumed) _autoRefresh();'),
          isTrue);
      expect(home.contains('onRefresh: _refresh'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §4 _getBusinesses 보존
  // ───────────────────────────────────────────────────────────
  group('§4 _getBusinesses 의미 불변', () {
    test('strict fetch semantics 유지', () {
      final g = _bodyOf(home, 'Future<List<BusinessModel>> _getBusinesses(');
      expect(g.contains('if (_businesses.isNotEmpty) return _businesses;'), isTrue);
      expect(g.contains('getBusinessesByIdsOrThrow('), isTrue);
      expect(g.contains('up.effectiveBusinessId'), isTrue);
      expect(g.contains('managedBusinessIds'), isTrue);
    });

    test('AH-V2-01 ERROR != ZERO 유지', () {
      expect(home.contains('getBusinessesByIdsOrThrow('), isTrue);
      final att = _bodyOf(home, 'Future<void> _loadTodayAttendance(');
      expect(att.contains('_todayCheckedIn      = null'), isTrue);
      final st = _bodyOf(home, 'Future<void> _loadStaffingReadiness(');
      expect(st.contains('_staffingReadiness = null'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // PERF-05 / §12~15 표시 불변
  // ───────────────────────────────────────────────────────────
  group('PERF-05 화면 계약 불변', () {
    test('§13 Home section 집합·순서 그대로', () {
      final titles = RegExp(r"_sectionHeader\(context, s, '([^']+)'\)")
          .allMatches(home)
          .map((m) => m.group(1))
          .toSet();
      expect(titles, {'오늘 운영', '다가오는 인력 부족', '처리할 일'});

      final b = _bodyOf(home, 'Widget build(');
      var prev = -1;
      for (final m in [
        '_buildHeader(', '_buildStateBanner(', '_buildPostingSetupCard(',
        // [AH-V2-05B] TODAY → TASK → NEXT
        '_buildTodayOps(', '_buildActionDashboard(', '_buildFutureStaffing(',
      ]) {
        final at = b.indexOf(m);
        expect(at, greaterThan(prev), reason: m);
        prev = at;
      }
    });

    // [AH-V2-05B 갱신] 05A는 순서를 건드리지 않았고, 05B에서 운영
    // urgency 기준으로 재정렬됐다. 9종 집합은 그대로다.
    test('§14 처리할 일 9종이 우선순위 순서를 따른다', () {
      final rows = _bodyOf(home, '_makeActionRows(BuildContext context');
      const order = [
        '퇴사 요청', '지원 검토', '스케줄 변경 요청', '계약 미발송', '마감 필요',
        '중간정산 요청', '급여 변경 요청', '이체 대기', '계약 종료 예정',
      ];
      var prev = -1;
      for (final label in order) {
        final at = rows.indexOf("label: '$label'");
        expect(at, greaterThan(prev), reason: label);
        prev = at;
      }
    });

    // [AH-V2-05C 갱신] Home의 elevation은 05C에서 전부 제거됐다.
    test('visual 미변경 — Home은 flat surface', () {
      expect('BoxShadow'.allMatches(home).length, 0);
    });

    test('AH-V2-03 staffing 상태 문구 유지', () {
      expect(home.contains('hasUsableData'), isTrue);
      expect(home.contains('오늘 예정된 인력 운영이 없어요'), isTrue);
      expect(home.contains('향후 7일 예정된 인력 운영이 없어요'), isTrue);
      expect(home.contains('향후 7일 인원이 모두 충원됐어요'), isTrue);
      expect(home.contains('_partialStaffingNotice(s)'), isTrue);
    });

    test('AH-V2-04A/B/C 계약 유지', () {
      expect(home.contains("label: '근태 확인'"), isTrue);
      expect(home.contains('AttendanceReviewHelper.requiresReviewNow('), isTrue);
      expect(home.contains('WorkDetailTimeService.load(allConfirmed)'), isTrue);
      expect(home.contains('_isMultiBusinessScope'), isTrue);
      expect(home.contains('shortageScopeLabel()'), isTrue);
      expect(home.contains('initialFilter: (approval?.overdueCount ?? 0) > 0'),
          isTrue);
    });

    test('§11 WorkDetailTimeService를 건드리지 않았다', () {
      final svc = _src('lib/services/work_detail_time_service.dart');
      expect(svc.contains('static Future<Map<String, dynamic>> load('), isTrue);
      expect(svc.contains('final slotPairs = <String, Set<String>>{}'), isTrue);
      // cache/preload를 추가하지 않았다
      expect(svc.contains('_cache'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §8 Functions 불변
  // ───────────────────────────────────────────────────────────
  group('§8 서버 함수 불변', () {
    test('callableGetTOsByBiz는 서버에 그대로 있다', () {
      final cf = _src('functions/src/index.ts');
      expect(cf.contains('callableGetTOsByBiz'), isTrue,
          reason: 'Home이 안 쓸 뿐, 다른 화면이 쓸 수 있으므로 삭제 금지');
    });

    test('다른 화면의 TO 조회 경로는 살아 있다', () {
      final toFs = _src('lib/services/firestore/to_firestore.dart');
      expect(toFs.contains('getTOsByBusiness('), isTrue);
      expect(toFs.contains("httpsCallable('callableGetTOsByBiz'"), isTrue);
    });

    test('다른 화면의 revision listener는 그대로', () {
      expect(_src('lib/screens/business_admin/jobs_root_screen.dart')
          .contains('WorkforceController.dataRevision.addListener'), isTrue);
      expect(_src(
              'lib/screens/business_admin/workforce_management/workforce_root_screen.dart')
          .contains('WorkforceController.dataRevision.addListener'), isTrue);
    });
  });
}
