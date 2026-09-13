import 'dart:io';

import 'package:ALfit/models/ui/staffing_readiness_model.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// AH-V2-03 HOME-STATE-SEMANTICS-REFRESH
//
// 관리자 Home은 숫자보다 먼저 상태를 믿을 수 있어야 한다.
//
//   공고 없음        != 인원 충원 완료
//   일부 사업장 실패  != 전체 실패
//   조회 실패        != 0명
//
// P2-A 부분 실패 / P2-B empty 의미 / P2-C refresh completeness
//
// 서버 실행은 emulator 없이 불가하므로
//   DTO·상태 파생은 값으로, 배선은 소스 단정으로 고정한다.
// ═══════════════════════════════════════════════════════════════

const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _indexPath = 'functions/src/index.ts';

String _src(String path) => File(path).readAsStringSync();

String _codeOf(String body) => body
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

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

/// CF 응답 형태를 흉내낸 map → 모델 파싱 검증용
Map<String, Object?> _day(String date, {int req = 0, int conf = 0, int short = 0}) => {
      'date': date,
      'requiredCount': req,
      'confirmedCount': conf,
      'shortageCount': short,
      'pendingCount': 0,
      'byBusiness': <Object?>[],
    };

StaffingReadinessModel _model({
  required bool available,
  bool partial = false,
  int failed = 0,
  List<Map<String, Object?>> days = const [],
}) {
  return StaffingReadinessModel(
    available: available,
    partial: partial,
    failedBusinessCount: failed,
    days: days.map((m) => StaffingDayData.fromMap(m)).toList(),
  );
}

void main() {
  late String home;
  late String cf;

  setUpAll(() {
    home = _codeOf(_src(_homePath));
    cf = _codeOf(_src(_indexPath));
  });

  // ───────────────────────────────────────────────────────────
  // P2-A 부분 실패
  // ───────────────────────────────────────────────────────────
  group('AHV2-03-01 일부 사업장 실패 → 전체 실패 아님', () {
    // [AH-V2-03.1 갱신] 부분 실패의 wire 표현은 available=false + partial=true다.
    // (구 앱이 부분합을 전체값으로 오인하지 않게 하려는 rollout 제약)
    // "Home 전체를 ERROR로 만들지 않는다"는 hasUsableData가 담보한다.
    test('부분 실패는 ERROR가 아니라 부분합으로 표시된다', () {
      final m = _model(available: false, partial: true, failed: 1, days: [
        _day('2026-09-13', req: 5, conf: 4, short: 1),
      ]);
      expect(m.hasUsableData, isTrue, reason: 'Home 전체를 ERROR로 만들면 안 된다');
      expect(m.partial, isTrue);
      expect(m.failedBusinessCount, 1);
      expect(m.days.first.shortageCount, 1, reason: '정상 사업장 데이터는 유지');
    });

    test('서버가 실패 사업장을 합산에서 제외한다', () {
      final fn = cf.substring(cf.indexOf('let okBusinessCount'));
      expect(fn.contains('failedBusinessCount++'), isTrue);
      // rejected / success=false 둘 다 continue 로 합산에서 빠진다
      expect('continue;'.allMatches(fn.substring(0, fn.indexOf('okBusinessCount++'))).length,
          2,
          reason: 'rejected + success=false 두 경로 모두 제외되어야 한다');
    });

    test('실패 사실을 UI가 숨기지 않는다', () {
      final w = _bodyOf(home, 'Widget _partialStaffingNotice(');
      expect(w.contains('sr.partial'), isTrue);
      expect(w.contains('불러오지 못해'), isTrue);
      expect(w.contains('재시도'), isTrue);
      expect(w.contains('_loadStaffingReadiness()'), isTrue);
    });

    test('오늘 운영·향후 부족 양쪽에 고지가 붙는다', () {
      expect('_partialStaffingNotice(s)'.allMatches(home).length, 3,
          reason: '오늘 운영 1 + 향후 부족(있음/없음) 2');
    });
  });

  group('AHV2-03-02 모든 사업장 실패 → ERROR', () {
    test('available=false', () {
      final m = _model(available: false);
      expect(m.available, isFalse);
      expect(m.hasTodayTarget, isFalse);
    });

    // [AH-V2-03.1 갱신] available은 rollout 안전을 위해 "전부 성공"이라는
    // 기존 의미로 되돌렸다. 쓸 수 있는 부분합의 신호는 partial이다.
    test('서버 available은 실패 0건일 때만 true', () {
      expect(cf.contains('available: failedBusinessCount === 0,'), isTrue);
      expect(
        cf.contains('partial: okBusinessCount > 0 && failedBusinessCount > 0'),
        isTrue,
      );
    });

    test('UI가 에러 표면을 유지한다', () {
      final t = _bodyOf(home, 'Widget _buildStaffingMetrics(');
      expect(t.contains('인력 정보를 불러오지 못했습니다'), isTrue);
      final f = _bodyOf(home, 'Widget _buildFutureStaffing(');
      expect(f.contains('향후 인력 현황을 불러오지 못했습니다'), isTrue);
    });
  });

  group('AHV2-03-03 전부 성공 → 기존 집계 유지', () {
    test('partial=false, failed=0', () {
      final m = _model(available: true, days: [
        _day('2026-09-13', req: 10, conf: 8, short: 2),
      ]);
      expect(m.partial, isFalse);
      expect(m.failedBusinessCount, 0);
      expect(m.days.first.requiredCount, 10);
    });

    test('빈 scope 응답도 새 필드를 갖는다', () {
      expect(
        'return {available: true, partial: false, failedBusinessCount: 0, days: []};'
            .allMatches(cf)
            .length,
        2,
        reason: '사업장 0개 / SubAdmin 권한 0개 두 경로',
      );
    });
  });

  // ───────────────────────────────────────────────────────────
  // P2-B empty 의미
  // ───────────────────────────────────────────────────────────
  group('AHV2-03-04 향후 운영 대상 없음 → 충원 완료 금지', () {
    test('requiredCount가 모두 0이면 target 없음', () {
      final m = _model(available: true, days: [
        _day('2026-09-13'),
        _day('2026-09-14'),
        _day('2026-09-15'),
      ]);
      expect(m.hasFutureTarget, isFalse);
    });

    test('days가 비어도 target 없음', () {
      expect(_model(available: true).hasFutureTarget, isFalse);
    });

    test('UI가 두 문구를 구분한다', () {
      final f = _bodyOf(home, 'Widget _buildFutureStaffing(');
      expect(f.contains('hasFutureTarget'), isTrue);
      expect(f.contains('향후 7일 예정된 인력 운영이 없어요'), isTrue);
      expect(f.contains('향후 7일 인원이 모두 충원됐어요'), isTrue);
      expect(f.contains('향후 7일 인원 충원 완료'), isFalse,
          reason: '두 상태를 뭉뚱그리던 구 문구는 남으면 안 된다');
    });
  });

  group('AHV2-03-05 대상 있음 + 부족 0 → 충원 완료', () {
    test('required > 0 이면 target 있음', () {
      final m = _model(available: true, days: [
        _day('2026-09-13', req: 3, conf: 3),
        _day('2026-09-14', req: 2, conf: 2),
      ]);
      expect(m.hasFutureTarget, isTrue);
      expect(m.days.skip(1).every((d) => d.shortageCount == 0), isTrue);
    });
  });

  group('AHV2-03-06 부족 있음 → 기존 UI 유지', () {
    test('shortage > 0 인 날만 행으로 남는다', () {
      final f = _bodyOf(home, 'Widget _buildFutureStaffing(');
      expect(f.contains('.skip(1)'), isTrue);
      expect(f.contains('.where((d) => d.shortageCount > 0)'), isTrue);
      expect(f.contains('_buildFutureShortageRow('), isTrue);
    });

    test('CTA destination을 바꾸지 않았다', () {
      expect(home.contains('_navigateToDayApplicantsForDate(context, day)'), isTrue);
      expect(
        home.contains('_navigateToDayApplicantsForDate(context, onShortageDay)'),
        isTrue,
      );
    });
  });

  group('AHV2-03-07 오늘 운영 대상 없음', () {
    test('days[0].requiredCount == 0 이면 today target 없음', () {
      final m = _model(available: true, days: [_day('2026-09-13')]);
      expect(m.hasTodayTarget, isFalse);
    });

    test('required > 0 이면 today target 있음', () {
      final m = _model(available: true, days: [_day('2026-09-13', req: 4)]);
      expect(m.hasTodayTarget, isTrue);
    });

    test('UI가 0/0/0 대신 상태 문구를 쓴다', () {
      final t = _bodyOf(home, 'Widget _buildStaffingMetrics(');
      expect(t.contains('hasTodayTarget'), isTrue);
      expect(t.contains('오늘 예정된 인력 운영이 없어요'), isTrue);
      final noTargetAt = t.indexOf('hasTodayTarget');
      final metricAt = t.indexOf("label: '필요'");
      expect(noTargetAt, lessThan(metricAt),
          reason: '대상 없음 분기가 수치 표시보다 먼저 와야 한다');
    });

    test('대상 없음은 에러가 아니다', () {
      final t = _bodyOf(home, 'Widget _buildStaffingMetrics(');
      final noTargetAt = t.indexOf('hasTodayTarget');
      final errAt = t.indexOf('인력 정보를 불러오지 못했습니다');
      expect(errAt, lessThan(noTargetAt),
          reason: '에러 분기가 먼저 처리되고, 그 뒤가 정상 대상 없음이다');
    });
  });

  // ───────────────────────────────────────────────────────────
  // ERROR != ZERO
  // ───────────────────────────────────────────────────────────
  group('AHV2-03 ERROR != ZERO 유지', () {
    test('실패 사업장을 0으로 합산하지 않는다', () {
      final fn = cf.substring(cf.indexOf('let okBusinessCount'));
      final beforeOk = fn.substring(0, fn.indexOf('okBusinessCount++'));
      expect(beforeOk.contains('aggDays'), isFalse,
          reason: '실패 경로에서 집계에 더하면 안 된다');
    });

    test('출근 로더의 ERROR != ZERO 배선이 유지된다', () {
      final att = _bodyOf(home, 'Future<void> _loadTodayAttendance(');
      expect(att.contains('_todayCheckedIn      = null'), isTrue);
      expect(home.contains('getBusinessesByIdsOrThrow('), isTrue);
    });

    test('staffing 로더 실패는 여전히 null이다', () {
      final l = _bodyOf(home, 'Future<void> _loadStaffingReadiness(');
      expect(l.contains('_staffingReadiness = null'), isTrue);
    });

    test('pendingCount null 의미가 유지된다', () {
      expect(cf.contains('overallPendingAvailable'), isTrue);
      final m = _model(available: true, days: [
        {
          'date': '2026-09-13',
          'requiredCount': 1,
          'confirmedCount': 0,
          'shortageCount': 1,
          'pendingCount': null,
          'byBusiness': <Object?>[],
        }
      ]);
      expect(m.days.first.pendingCount, isNull);
    });
  });

  // ───────────────────────────────────────────────────────────
  // P2-C refresh
  // ───────────────────────────────────────────────────────────
  group('AHV2-03-08~10 pull-to-refresh completeness', () {
    test('refresh가 승인 사업장 상태를 재조회한다', () {
      final r = _bodyOf(home, 'Future<void> _refresh(');
      expect(r.contains('_reloadReadiness()'), isTrue);
      final rr = _bodyOf(home, 'Future<void> _reloadReadiness(');
      expect(rr.contains('_loadApprovedBusinessStatus()'), isTrue);
    });

    test('refresh가 첫 공고 준비를 재조회한다', () {
      final rr = _bodyOf(home, 'Future<void> _reloadReadiness(');
      expect(rr.contains('_loadPostingReadiness()'), isTrue);
      // 사업장 조회가 먼저 await 되어야 readiness가 최신 _businesses를 본다
      expect(rr.indexOf('_loadApprovedBusinessStatus()'),
          lessThan(rr.indexOf('_loadPostingReadiness()')));
    });

    // [AH-V2-05A 갱신] _loadSummaryCounts는 dead loader라 제거됐다.
    // refresh가 커버해야 할 실제 로더 집합을 고정한다.
    test('refresh가 실제 로더를 모두 호출한다', () {
      final r = _bodyOf(home, 'Future<void> _refresh(');
      for (final loader in [
        '_loadCanonicalSummary()',
        '_loadStaffingReadiness()',
        '_loadTodayAttendance()',
        '_reloadReadiness()',
      ]) {
        expect(r.contains(loader), isTrue, reason: loader);
      }
      expect(r.contains('_loadSummaryCounts'), isFalse);
    });

    test('pull-to-refresh가 그 경로에 연결돼 있다', () {
      expect(home.contains('onRefresh: _refresh'), isTrue);
    });

    test('동시 실행만 방어하고 직렬화하지 않는다', () {
      final r = _bodyOf(home, 'Future<void> _refresh(');
      expect(r.contains('_isRefreshing'), isTrue);
      expect(r.contains('await Future.wait(['), isTrue,
          reason: 'Home refresh를 느리게 만들지 않는다');
    });
  });

  group('AHV2-03-11 섹션 독립 실패', () {
    test('로더가 각자 catch로 자기 상태만 바꾼다', () {
      for (final sig in [
        'Future<void> _loadCanonicalSummary(',
        'Future<void> _loadStaffingReadiness(',
        'Future<void> _loadTodayAttendance(',
      ]) {
        expect(_bodyOf(home, sig).contains('} catch (e) {'), isTrue);
      }
    });

    test('초기 로드는 독립 실행된다', () {
      expect(home.contains('unawaited(_loadCanonicalSummary())'), isTrue);
      expect(home.contains('unawaited(_loadStaffingReadiness())'), isTrue);
      expect(home.contains('unawaited(_loadTodayAttendance())'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('AH-V2-03 범위 제한', () {
    test('capacity 계산 정책을 바꾸지 않았다', () {
      // 확정 취급 상태 = CONFIRMED + CONTRACT_PENDING
      expect(cf.contains('const CONFIRMED_STATUSES = ["CONFIRMED", "CONTRACT_PENDING"];'),
          isTrue);
      expect(cf.contains('.where("status", "in", CONFIRMED_STATUSES)'), isTrue);
      // flex: per-wdId 부족분 합산 (초과확정이 다른 wdId를 상쇄하지 않음)
      expect(cf.contains('const shortage  = Math.max(0, wd.required - confirmed);'),
          isTrue);
      expect(cf.contains('wdc[wd.id]?.confirmedCount'), isTrue,
          reason: 'workDetailCounts가 canonical source로 유지돼야 한다');
      // contract: per-TO per-day 부족분 합산
      expect(
        cf.contains('dayAcc[i].shortage  += Math.max(0, to.totalRequired - confirmedOnDay);'),
        isTrue,
      );
      // LEGACY_WORKDETAIL은 여전히 임의 fallback 없이 skip
      expect(cf.contains('LEGACY_WORKDETAIL'), isTrue);
    });

    test('permission 게이트가 그대로다', () {
      final t = _bodyOf(home, 'Widget _buildTodayOps(');
      expect(t.contains('canManageTo'), isTrue);
      expect(t.contains('canManageWorkers'), isTrue);
      final f = _bodyOf(home, 'Widget _buildFutureStaffing(');
      expect(f.contains('canManageTo'), isTrue);
    });

    test('Home 섹션 구성·순서가 그대로다', () {
      final titles = RegExp(r"_sectionHeader\(context, s, '([^']+)'\)")
          .allMatches(home)
          .map((m) => m.group(1))
          .toSet();
      expect(titles, {'오늘 운영', '다가오는 인력 부족', '처리할 일'});
      final b = _bodyOf(home, 'Widget build(');
      var prev = -1;
      for (final m in [
        '_buildHeader(', '_buildStateBanner(', '_buildPostingSetupCard(',
        '_buildTodayOps(', '_buildFutureStaffing(', '_buildActionDashboard(',
      ]) {
        final at = b.indexOf(m);
        expect(at, greaterThan(prev));
        prev = at;
      }
    });

    test('처리할 일 9종이 그대로다', () {
      final rows = _bodyOf(home, '_makeActionRows(BuildContext context');
      for (final label in [
        '퇴사 요청', '지원 검토', '마감 필요', '급여 변경 요청', '중간정산 요청',
        '스케줄 변경 요청', '계약 미발송', '계약 종료 예정', '이체 대기',
      ]) {
        expect(rows.contains("label: '$label'"), isTrue);
      }
    });

    test('다사업장 scope 표시·destination은 건드리지 않았다 (AH-V2-04)', () {
      final f = _bodyOf(home, 'Widget _buildFutureStaffing(');
      expect(f.contains('businessName'), isFalse);
      final t = _bodyOf(home, 'Widget _buildStaffingMetrics(');
      expect(t.contains('businessName'), isFalse);
    });
  });
}
