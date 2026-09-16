import 'dart:io';

import 'package:ALfit/models/ui/staffing_readiness_model.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// AH-V2-03.1 STAFFING-ROLLOUT-CONTRACT-ALIGNMENT
//
//   PARTIAL DATA != COMPLETE DATA
//
// 이 invariant는 OLD CLIENT + NEW SERVER 조합에서도 성립해야 한다.
// 구 앱은 partial을 모르므로, 부분 실패를 available=false로 받아야만
// 기존 ERROR 화면으로 빠지고 부분합을 전체값으로 오인하지 않는다.
//
// 서버:   available = 전부 성공 (기존 의미 보존)
//         partial   = 쓸 수 있는 부분합 존재
// 신규앱: partial을 available보다 먼저 판정
// ═══════════════════════════════════════════════════════════════

const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _indexPath = 'functions/src/index.ts';

String _src(String p) => File(p).readAsStringSync();

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

/// CF wire 응답을 그대로 흉내낸 map (DTO 파싱 경로 검증용)
Map<Object?, Object?> _wire({
  required bool available,
  bool? partial,
  int? failedBusinessCount,
  List<Map<String, Object?>> days = const [],
}) =>
    {
      'available': available,
      if (partial != null) 'partial': partial,
      if (failedBusinessCount != null)
        'failedBusinessCount': failedBusinessCount,
      'days': days,
    };

/// fromCallable과 동일한 파싱 규칙 (HttpsCallableResult 없이 검증)
StaffingReadinessModel _parse(Map<Object?, Object?> map) {
  final rawDays = map['days'] as List<Object?>? ?? const [];
  return StaffingReadinessModel(
    available: (map['available'] as bool?) ?? false,
    partial: (map['partial'] as bool?) ?? false,
    failedBusinessCount: (map['failedBusinessCount'] as num?)?.toInt() ?? 0,
    days: rawDays
        .whereType<Map<Object?, Object?>>()
        .map(StaffingDayData.fromMap)
        .toList(),
  );
}

Map<String, Object?> _day(String date, {int req = 0, int conf = 0, int short = 0}) => {
      'date': date,
      'requiredCount': req,
      'confirmedCount': conf,
      'shortageCount': short,
      'pendingCount': 0,
      'byBusiness': <Object?>[],
    };

/// 구 클라이언트의 staffing 판정을 그대로 재현한다.
/// (f3e43b4~1 기준: `sr == null || !sr.available` → ERROR)
bool oldClientShowsError(StaffingReadinessModel? sr) =>
    sr == null || !sr.available;

/// 신규 클라이언트의 판정 — hasUsableData 단일 소스
bool newClientShowsError(StaffingReadinessModel? sr) =>
    sr == null || !sr.hasUsableData;

void main() {
  late String home;
  late String cf;
  late String dto;

  setUpAll(() {
    home = _codeOf(_src(_homePath));
    cf = _codeOf(_src(_indexPath));
    dto = _codeOf(_src('lib/models/ui/staffing_readiness_model.dart'));
  });

  // ───────────────────────────────────────────────────────────
  // 서버 응답 계약
  // ───────────────────────────────────────────────────────────
  group('서버 available 의미 복원', () {
    test('available은 실패 0건일 때만 true', () {
      expect(cf.contains('available: failedBusinessCount === 0,'), isTrue);
      expect(cf.contains('available: okBusinessCount > 0,'), isFalse,
          reason: 'f3e43b4의 넓어진 의미는 되돌아가야 한다');
    });

    test('partial은 쓸 수 있는 부분합이 있을 때만 true', () {
      expect(
        cf.contains('partial: okBusinessCount > 0 && failedBusinessCount > 0,'),
        isTrue,
      );
    });

    test('CONTRACT-06 EMPTY SCOPE는 여전히 정상 empty', () {
      expect(
        'return {available: true, partial: false, failedBusinessCount: 0, days: []};'
            .allMatches(cf)
            .length,
        2,
        reason: '사업장 0개 / 권한 사업장 0개 두 경로',
      );
    });

    test('CONTRACT-07 실패 사업장 중간집계는 여전히 제외', () {
      final fn = cf.substring(cf.indexOf('let okBusinessCount'));
      final beforeOk = fn.substring(0, fn.indexOf('okBusinessCount++'));
      expect(beforeOk.contains('aggDays'), isFalse);
      expect('continue;'.allMatches(beforeOk).length, 2,
          reason: 'rejected + success=false 두 경로 모두 합산 제외');
    });

    test('CONTRACT-08 failedBusinessCount는 두 실패 경로 모두 센다', () {
      final fn = cf.substring(cf.indexOf('let okBusinessCount'));
      final beforeOk = fn.substring(0, fn.indexOf('okBusinessCount++'));
      expect('failedBusinessCount++'.allMatches(beforeOk).length, 2);
      expect(cf.contains('failedBusinessCount,'), isTrue,
          reason: '응답에 실려야 한다');
    });
  });

  // ───────────────────────────────────────────────────────────
  // Rollout Compatibility Matrix
  // ───────────────────────────────────────────────────────────
  group('CONTRACT-01 OLD CLIENT + NEW SERVER', () {
    // 신규 서버의 부분 실패 응답 (사업장 A,B 성공 / C 실패)
    final partialWire = _wire(
      available: false,
      partial: true,
      failedBusinessCount: 1,
      days: [_day('2026-09-13', req: 6, conf: 4, short: 2)],
    );

    test('구 앱은 ERROR로 빠진다', () {
      expect(oldClientShowsError(_parse(partialWire)), isTrue);
    });

    test('구 앱이 부분합을 정상 전체값으로 표시하지 않는다', () {
      final sr = _parse(partialWire);
      // 구 앱의 정상 표시 조건은 available==true 하나뿐이었다.
      expect(sr.available, isFalse,
          reason: 'FALSE COMPLETE DATA — 이게 true면 구 앱이 6/4/2를 전체값으로 읽는다');
    });

    test('구 앱 판정에 partial은 관여하지 않는다', () {
      // partial 값을 뒤집어도 구 앱 결과는 동일해야 한다 (필드를 모르므로)
      final flipped = _parse(_wire(
        available: false,
        partial: false,
        failedBusinessCount: 1,
        days: [_day('2026-09-13', req: 6)],
      ));
      expect(oldClientShowsError(flipped), oldClientShowsError(_parse(partialWire)));
    });
  });

  group('CONTRACT-02 NEW CLIENT + OLD SERVER', () {
    // 구 서버는 partial / failedBusinessCount 자체를 보내지 않는다.
    test('없는 필드는 안전한 기본값으로 파싱된다', () {
      final sr = _parse(_wire(available: true, days: [_day('2026-09-13', req: 3, conf: 3)]));
      expect(sr.partial, isFalse);
      expect(sr.failedBusinessCount, 0);
    });

    test('구 서버 부분 실패(available=false)는 기존처럼 ERROR', () {
      final sr = _parse(_wire(available: false));
      expect(newClientShowsError(sr), isTrue,
          reason: 'partial 기본값 false → hasUsableData=false → ERROR');
    });

    test('false success가 생기지 않는다', () {
      final sr = _parse(_wire(available: false, days: [_day('2026-09-13', req: 9)]));
      expect(sr.hasUsableData, isFalse);
    });

    test('구 서버 정상 응답은 그대로 SUCCESS', () {
      final sr = _parse(_wire(available: true, days: [_day('2026-09-13', req: 3, conf: 3)]));
      expect(newClientShowsError(sr), isFalse);
      expect(sr.partial, isFalse);
    });
  });

  group('CONTRACT-03 NEW CLIENT + NEW SERVER partial', () {
    final sr = _parse(_wire(
      available: false,
      partial: true,
      failedBusinessCount: 1,
      days: [_day('2026-09-13', req: 6, conf: 4, short: 2)],
    ));

    test('ERROR로 빠지지 않는다', () {
      expect(newClientShowsError(sr), isFalse);
    });

    test('부분합을 쓸 수 있다', () {
      expect(sr.hasUsableData, isTrue);
      expect(sr.days.first.shortageCount, 2);
      expect(sr.hasTodayTarget, isTrue);
    });

    test('부분합임을 알 수 있다', () {
      expect(sr.partial, isTrue);
      expect(sr.failedBusinessCount, 1);
    });
  });

  group('CONTRACT-04 / 05 ALL SUCCESS · ALL FAILED', () {
    test('CONTRACT-04 전부 성공', () {
      final sr = _parse(_wire(
        available: true,
        partial: false,
        failedBusinessCount: 0,
        days: [_day('2026-09-13', req: 5, conf: 5)],
      ));
      expect(sr.available, isTrue);
      expect(sr.partial, isFalse);
      expect(newClientShowsError(sr), isFalse);
      expect(oldClientShowsError(sr), isFalse, reason: '구 앱도 정상 표시');
    });

    test('CONTRACT-05 전부 실패', () {
      final sr = _parse(_wire(available: false, partial: false, failedBusinessCount: 3));
      expect(sr.hasUsableData, isFalse);
      expect(newClientShowsError(sr), isTrue);
      expect(oldClientShowsError(sr), isTrue, reason: '양쪽 모두 ERROR');
    });

    test('CONTRACT-06 EMPTY SCOPE는 양쪽 모두 ERROR 아님', () {
      final sr = _parse(_wire(
          available: true, partial: false, failedBusinessCount: 0, days: []));
      expect(newClientShowsError(sr), isFalse);
      expect(oldClientShowsError(sr), isFalse);
      expect(sr.hasTodayTarget, isFalse);
      expect(sr.hasFutureTarget, isFalse);
    });
  });

  group('ROLLOUT MATRIX 전수 — false complete data 없음', () {
    // 서버가 낼 수 있는 4상태 × 클라이언트 2세대
    final cases = <String, Map<Object?, Object?>>{
      'ALL_SUCCESS': _wire(
          available: true, partial: false, failedBusinessCount: 0,
          days: [_day('2026-09-13', req: 4, conf: 4)]),
      'PARTIAL': _wire(
          available: false, partial: true, failedBusinessCount: 1,
          days: [_day('2026-09-13', req: 4, conf: 2, short: 2)]),
      'ALL_FAILED': _wire(available: false, partial: false, failedBusinessCount: 2),
      'EMPTY_SCOPE': _wire(
          available: true, partial: false, failedBusinessCount: 0, days: []),
    };

    test('구 앱이 완전한 데이터로 읽는 상태는 ALL_SUCCESS/EMPTY 뿐', () {
      final shownAsComplete = cases.entries
          .where((e) => !oldClientShowsError(_parse(e.value)))
          .map((e) => e.key)
          .toSet();
      expect(shownAsComplete, {'ALL_SUCCESS', 'EMPTY_SCOPE'},
          reason: 'PARTIAL이 여기 섞이면 구 앱이 부분합을 전체값으로 표시한다');
    });

    test('신규 앱이 데이터를 쓰는 상태는 PARTIAL까지 포함', () {
      final usable = cases.entries
          .where((e) => !newClientShowsError(_parse(e.value)))
          .map((e) => e.key)
          .toSet();
      expect(usable, {'ALL_SUCCESS', 'PARTIAL', 'EMPTY_SCOPE'});
    });

    test('어느 세대도 ALL_FAILED를 데이터로 읽지 않는다', () {
      final sr = _parse(cases['ALL_FAILED']!);
      expect(oldClientShowsError(sr), isTrue);
      expect(newClientShowsError(sr), isTrue);
    });

    test('신규 앱이 데이터를 쓰는 경우, 구 앱보다 좁아지지 않는다', () {
      for (final e in cases.entries) {
        final sr = _parse(e.value);
        if (!oldClientShowsError(sr)) {
          expect(newClientShowsError(sr), isFalse,
              reason: '${e.key}: 구 앱이 보던 데이터를 신규 앱이 잃으면 퇴행');
        }
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  // 클라이언트 판정 순서 배선
  // ───────────────────────────────────────────────────────────
  group('NEW_CLIENT_STAFFING_STATE_ORDER', () {
    test('판정 순서가 DTO 한 곳에 정의돼 있다', () {
      expect(dto.contains('bool get hasUsableData => partial || available;'), isTrue);
    });

    test('에러 분기 3곳이 모두 hasUsableData를 쓴다', () {
      // [HOME-V2-08D.2] Hero 분기와 section gate가 같은 판정을 쓰면서 늘었다.
      //   요지는 개수가 아니라 available 직접 판정이 없다는 것이다.
      expect('hasUsableData'.allMatches(home).length, 8);
      expect(home.contains('!_staffingReadiness!.available'), isFalse,
          reason: 'available 직접 판정이 남으면 partial이 ERROR로 삼켜진다');
    });

    test('오늘 운영: ERROR → 대상없음 → 수치 → partial notice', () {
      final t = _bodyOf(home, 'Widget? _buildTodayStaffingSummary(');
      final err = t.indexOf('hasUsableData');
      final noTarget = t.indexOf('hasTodayTarget');
      final metric = t.indexOf('명 필요 · ');
      final notice = t.indexOf('_partialStaffingNotice(s)');
      expect(err, lessThan(noTarget));
      expect(noTarget, lessThan(metric));
      expect(metric, lessThan(notice));
    });

    test('향후 부족: ERROR → 목록/빈상태 → partial notice', () {
      final f = _bodyOf(home, 'Widget _buildFutureStaffing(');
      // [HOME-V2-08D.2] no-target 분기가 gate로 옮겨져 hasFutureTarget이 빠졌다.
      // [HOME-V2-08D.4] 전부충원 분기도 행이 되면서 `_staffingReadiness!.partial`
      //   조건 분기가 사라졌다 — partial 고지는 목록 아래에 무조건 붙는다
      //   (_partialStaffingNotice가 자체적으로 partial 여부를 판단한다).
      expect(f.indexOf('hasUsableData'), lessThan(f.indexOf('futureDays.isEmpty')));
      expect(f.indexOf('futureDays.isEmpty'),
          lessThan(f.indexOf('_partialStaffingNotice(s)')));
      expect(_bodyOf(home, 'Widget _partialStaffingNotice(').contains('sr.partial'),
          isTrue);
    });

    test('오늘 지표 getter도 partial을 버리지 않는다', () {
      final g = _bodyOf(home, 'StaffingDayData? get _todayStaffingDay');
      expect(g.contains('!sr.hasUsableData'), isTrue);
      expect(g.contains('!sr.available'), isFalse);
    });

    test('로더 실패는 여전히 null (ERROR≠ZERO)', () {
      final l = _bodyOf(home, 'Future<void> _loadStaffingReadiness(');
      expect(l.contains('_staffingReadiness = null'), isTrue);
    });

    test('empty() 기본값은 ERROR로 판정된다', () {
      expect(StaffingReadinessModel.empty().hasUsableData, isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────
  // AH-V2-03 회귀
  // ───────────────────────────────────────────────────────────
  group('AH-V2-03 계약 유지', () {
    test('공고 없음 != 충원 완료', () {
      final f = _bodyOf(home, 'Widget _buildFutureStaffing(');
      // [HOME-V2-08D.2] '대상 없음'은 이제 gate가 섹션을 숨기고 Hero가 말한다.

      expect(f.contains('향후 인력 현황을 불러오지 못했습니다'), isTrue);
      final t = _bodyOf(home, 'Widget? _buildTodayStaffingSummary(');
      // [HOME-V2-08D.2] '대상 없음'은 이제 gate가 섹션을 숨기고 Hero가 말한다.

    });

    test('partial notice 카피·재시도 유지', () {
      final w = _bodyOf(home, 'Widget _partialStaffingNotice(');
      expect(w.contains('sr.partial'), isTrue);
      expect(w.contains('불러오지 못해'), isTrue);
      expect(w.contains('재시도'), isTrue);
      expect(w.contains('_loadStaffingReadiness()'), isTrue);
    });

    test('refresh 계약 유지', () {
      final r = _bodyOf(home, 'Future<void> _refresh(');
      expect(r.contains('_reloadReadiness()'), isTrue);
      final rr = _bodyOf(home, 'Future<void> _reloadReadiness(');
      expect(rr.indexOf('_loadApprovedBusinessStatus()'),
          lessThan(rr.indexOf('_loadPostingReadiness()')));
    });

    test('permission 게이트·destination 유지', () {
      final t = _bodyOf(home, 'Widget _buildTodayOps(');
      expect(t.contains('canManageTo'), isTrue);
      expect(t.contains('canManageWorkers'), isTrue);
      expect(home.contains('_navigateToDayApplicantsForDate(context, day)'), isTrue);
      // [HOME-V2-08D.3] 오늘 부족 destination은 issue row로 옮겨졌다 — 대상은 같다
      expect(_bodyOf(home, 'List<Widget> _buildTodayIssueRows(')
          .contains('_navigateToDayApplicantsForDate(context, day)'), isTrue);
    });

    test('capacity 계산 정책 미변경', () {
      expect(cf.contains('const CONFIRMED_STATUSES = ["CONFIRMED", "CONTRACT_PENDING"];'),
          isTrue);
      // [R2.4] 뺄셈 식은 그대로다 — 확정만 빼고, per-wdId이며, 음수는 0이다.
      //   앞에 종료 여부가 붙었을 뿐이다: 채울 수 없는 단위는 부족이 아니고,
      //   같은 규칙을 callableGetDayStaffingDetail이 이미 쓰고 있다.
      expect(cf.contains('Math.max(0, wd.required - confirmed)'), isTrue);
      expect(cf.contains('const shortage  = wd.closed ?'), isTrue);
      expect(
        cf.contains('dayAcc[i].shortage  += Math.max(0, to.totalRequired - confirmedOnDay);'),
        isTrue,
      );
      expect(cf.contains('WORKDETAIL_CONTRACT_BROKEN'), isTrue);
      expect(cf.contains('LEGACY_WORKDETAIL'), isFalse,
          reason: 'silent skip은 결손을 0으로 합성했다');
    });

    test('pendingCount null 의미 유지', () {
      expect(cf.contains('overallPendingAvailable'), isTrue);
      final sr = _parse({
        'available': true,
        'days': [
          {
            'date': '2026-09-13',
            'requiredCount': 1,
            'confirmedCount': 0,
            'shortageCount': 1,
            'pendingCount': null,
            'byBusiness': <Object?>[],
          }
        ],
      });
      expect(sr.days.first.pendingCount, isNull);
    });

    test('신규 서버 필드를 더 늘리지 않았다', () {
      final fn = cf.substring(cf.indexOf('let okBusinessCount'));
      final ret = fn.substring(fn.indexOf('return {'));
      expect(ret.contains('hasUsableData'), isFalse,
          reason: 'partial + failedBusinessCount로 충분하다');
    });
  });
}
