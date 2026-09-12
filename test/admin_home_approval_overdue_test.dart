import 'dart:io';

import 'package:ALfit/utils/format_helper.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// AH-V2-04C.1 APPROVAL-OVERDUE-CANONICAL-ALIGNMENT
//
//   APPROVAL_OVERDUE_CANONICAL =
//     status == "PENDING" AND workDate < TODAY_KST_MIDNIGHT
//
// type 조건 없음 — 장기(long_term)도 계약 시작일이 지났는데 PENDING이면
// 단기와 똑같이 방치된 요청이다.
//
// Home 배지와 SupportReviewQueue '기한 지남'이 같은 수를 말해야 한다.
// ═══════════════════════════════════════════════════════════════

const _cfPath = 'functions/src/index.ts';
const _queuePath = 'lib/screens/business_admin/support_review_queue_screen.dart';

String _src(String p) => File(p).readAsStringSync();
String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _fnBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: '$signature 를 찾지 못함');
  final end = source.indexOf('\n}', start);
  expect(end, isNot(-1));
  return source.substring(start, end + 2);
}

String _dartBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: '$signature 를 찾지 못함');
  final open = source.indexOf('{', start);
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

// ── KST 시각 조립 (기기 timezone 무관) ─────────────────────────
/// KST 달력일 [y]-[m]-[d]의 자정에 해당하는 UTC instant.
/// 서버가 workDate를 이 형태로 보관한다.
DateTime _kstDay(int y, int m, int d) =>
    DateTime.utc(y, m, d).subtract(const Duration(hours: 9));

/// KST 벽시계 시각에 해당하는 UTC instant.
DateTime _kstAt(int y, int m, int d, int h, int min) =>
    DateTime.utc(y, m, d, h, min).subtract(const Duration(hours: 9));

// ── 양쪽 predicate 재현 ────────────────────────────────────────

/// 서버 srvHomeApproval의 overdue 판정.
///   status == PENDING && workDate.toMillis() < todayKSTMidnight
bool _homeOverdue({
  required String status,
  required DateTime workDate,
  required DateTime nowKstMidnight,
}) {
  if (status != 'PENDING') return false;
  return workDate.millisecondsSinceEpoch <
      nowKstMidnight.millisecondsSinceEpoch;
}

/// SupportReviewQueueScreen._priorityOf의 overdue 분기.
///   (private이므로 동일 식을 재현하고, 소스가 이 식을 쓰는지 별도 단정)
bool _queueOverdue({required DateTime workDate, required DateTime now}) {
  final today = FormatHelper.toKstDate(now);
  final dateOnly = FormatHelper.toKstDate(workDate);
  return dateOnly.isBefore(today);
}

String _queuePriority({required DateTime workDate, required DateTime now}) {
  final today = FormatHelper.toKstDate(now);
  final dateOnly = FormatHelper.toKstDate(workDate);
  if (dateOnly.isBefore(today)) return 'overdue';
  if (dateOnly.isAtSameMomentAs(today)) return 'today';
  return 'upcoming';
}

class _App {
  final String type;
  final String status;
  final DateTime workDate;
  final String businessId;
  const _App(this.type, this.status, this.workDate, {this.businessId = 'b1'});
}

void main() {
  late String cf;
  late String queue;

  setUpAll(() {
    cf = _src(_cfPath);
    queue = _codeOf(_src(_queuePath));
  });

  // 기준: KST 2026-09-13
  final todayKst = _kstDay(2026, 9, 13);
  final nowKst = _kstAt(2026, 9, 13, 10, 0);
  final yesterday = _kstDay(2026, 9, 12);
  final tomorrow = _kstDay(2026, 9, 14);

  // ───────────────────────────────────────────────────────────
  // §7 핵심 — 장기 포함
  // ───────────────────────────────────────────────────────────
  group('OVERDUE-01/02 단기·장기 모두 overdue', () {
    test('OVERDUE-01 short + 어제 → 양쪽 overdue', () {
      expect(
          _homeOverdue(
              status: 'PENDING',
              workDate: yesterday,
              nowKstMidnight: todayKst),
          isTrue);
      expect(_queueOverdue(workDate: yesterday, now: nowKst), isTrue);
    });

    test('OVERDUE-02 long_term + 어제 → 양쪽 overdue (이번 Phase의 핵심)', () {
      // 서버 predicate에 type이 없으므로 short와 결과가 같아야 한다
      expect(
          _homeOverdue(
              status: 'PENDING',
              workDate: yesterday,
              nowKstMidnight: todayKst),
          isTrue);
      expect(_queueOverdue(workDate: yesterday, now: nowKst), isTrue);
    });

    test('서버 코드에서 type === "short" 조건이 사라졌다', () {
      // 주석에는 type을 설명하므로 코드 라인만 본다
      final fn = _codeOf(_fnBody(cf, 'async function srvHomeApproval('));
      expect(fn.contains('d["type"]'), isFalse);
      expect(fn.contains('"short"'), isFalse);
      expect(fn.contains('.select("workDate", "type")'), isFalse,
          reason: 'select 투영에서도 더 이상 필요 없다');
    });

    test('서버 overdue는 workDate만 본다', () {
      final fn = _fnBody(cf, 'async function srvHomeApproval(');
      expect(fn.contains('if (wdTs && wdTs.toMillis() < todayMs) overdue++;'),
          isTrue);
      expect(fn.contains('.where("status", "==", "PENDING")'), isTrue);
    });

    test('Queue에 type 제한을 추가하지 않았다', () {
      final f = _dartBody(queue, '_Priority _priorityOf(');
      expect(f.contains('type'), isFalse);
      expect(f.contains('short'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §8 / §9 경계
  // ───────────────────────────────────────────────────────────
  group('OVERDUE-03/04/05 경계 조건', () {
    test('OVERDUE-03 오늘 → overdue 아님', () {
      expect(
          _homeOverdue(
              status: 'PENDING', workDate: todayKst, nowKstMidnight: todayKst),
          isFalse);
      expect(_queueOverdue(workDate: todayKst, now: nowKst), isFalse);
      expect(_queuePriority(workDate: todayKst, now: nowKst), 'today');
    });

    test('OVERDUE-04 미래 → overdue 아님', () {
      expect(
          _homeOverdue(
              status: 'PENDING', workDate: tomorrow, nowKstMidnight: todayKst),
          isFalse);
      expect(_queueOverdue(workDate: tomorrow, now: nowKst), isFalse);
      expect(_queuePriority(workDate: tomorrow, now: nowKst), 'upcoming');
    });

    test('OVERDUE-05 PENDING 아니면 과거여도 overdue 아님', () {
      for (final st in ['CONFIRMED', 'REJECTED', 'CANCELED', 'CONTRACT_PENDING']) {
        expect(
            _homeOverdue(
                status: st, workDate: yesterday, nowKstMidnight: todayKst),
            isFalse,
            reason: st);
      }
      // Queue는 CF가 PENDING만 실어 보내므로 모집단 자체가 PENDING이다
      final loader = _src('lib/services/support_review_queue_service.dart');
      expect(loader.contains('callableGetPendingApplicationsForReview'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §10 KST 경계 — 기기 timezone 무관
  // ───────────────────────────────────────────────────────────
  group('KST day boundary', () {
    test('KST 00:30에 전날 근무는 overdue', () {
      final justAfterMidnight = _kstAt(2026, 9, 13, 0, 30);
      expect(_queueOverdue(workDate: yesterday, now: justAfterMidnight), isTrue);
      expect(
          _homeOverdue(
              status: 'PENDING',
              workDate: yesterday,
              nowKstMidnight: todayKst),
          isTrue);
    });

    test('KST 23:30에 당일 근무는 아직 overdue 아님', () {
      final lateNight = _kstAt(2026, 9, 13, 23, 30);
      expect(_queueOverdue(workDate: todayKst, now: lateNight), isFalse);
    });

    test('같은 instant면 기기 timezone 표현이 달라도 결과가 같다', () {
      final instant = _kstAt(2026, 9, 13, 0, 30);
      // 동일 시점을 UTC / local 로 표현해도 분류가 흔들리면 안 된다
      expect(_queuePriority(workDate: yesterday, now: instant.toUtc()),
          _queuePriority(workDate: yesterday, now: instant.toLocal()));
      expect(_queuePriority(workDate: todayKst.toUtc(), now: instant),
          _queuePriority(workDate: todayKst.toLocal(), now: instant));
    });

    test('UTC 자정 근처에서도 KST 날짜로 분류된다', () {
      // UTC 2026-09-12 16:00 = KST 2026-09-13 01:00
      final now = DateTime.utc(2026, 9, 12, 16, 0);
      expect(_queuePriority(workDate: todayKst, now: now), 'today');
      expect(_queuePriority(workDate: yesterday, now: now), 'overdue');
    });

    test('Queue가 device local 자정을 쓰지 않는다', () {
      final f = _dartBody(queue, '_Priority _priorityOf(');
      expect(f.contains('FormatHelper.toKstDate(DateTime.now())'), isTrue);
      expect(f.contains('FormatHelper.toKstDate(app.workDate)'), isTrue);
      expect(f.contains('DateTime(now.year, now.month, now.day)'), isFalse,
          reason: 'local 자정 계산은 제거돼야 한다');
    });

    test('§13 — overdue/today/upcoming이 같은 classifier를 공유한다', () {
      final f = _dartBody(queue, '_Priority _priorityOf(');
      expect('FormatHelper.toKstDate'.allMatches(f).length, 2,
          reason: 'today/dateOnly 두 번만 — 분기마다 다른 기준을 쓰지 않는다');
      expect(f.contains('_Priority.overdue'), isTrue);
      expect(f.contains('_Priority.today'), isTrue);
      expect(f.contains('_Priority.upcoming'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §20 Home == Queue 개수 일치
  // ───────────────────────────────────────────────────────────
  group('HOME_QUEUE_COUNT_ALIGNMENT', () {
    int homeOverdueCount(List<_App> apps) => apps
        .where((a) => _homeOverdue(
            status: a.status,
            workDate: a.workDate,
            nowKstMidnight: todayKst))
        .length;

    int queueOverdueCount(List<_App> apps) => apps
        .where((a) => a.status == 'PENDING') // Queue 모집단 = PENDING 전체
        .where((a) => _queueOverdue(workDate: a.workDate, now: nowKst))
        .length;

    test('단기 3 + 장기 2 → 양쪽 5', () {
      final apps = [
        _App('short', 'PENDING', yesterday),
        _App('short', 'PENDING', _kstDay(2026, 9, 11)),
        _App('short', 'PENDING', _kstDay(2026, 9, 10)),
        _App('long_term', 'PENDING', yesterday),
        _App('long_term', 'PENDING', _kstDay(2026, 9, 1)),
      ];
      expect(homeOverdueCount(apps), 5);
      expect(queueOverdueCount(apps), 5);
    });

    test('장기만 기한 지남 → 양쪽 2 (이전에는 Home 0)', () {
      final apps = [
        _App('long_term', 'PENDING', yesterday),
        _App('long_term', 'PENDING', _kstDay(2026, 9, 5)),
        _App('short', 'PENDING', tomorrow),
      ];
      expect(homeOverdueCount(apps), 2);
      expect(queueOverdueCount(apps), 2);
    });

    test('혼합 — 오늘·미래·비PENDING 섞여도 일치', () {
      final apps = [
        _App('short', 'PENDING', yesterday),        // overdue
        _App('long_term', 'PENDING', yesterday),    // overdue
        _App('short', 'PENDING', todayKst),         // today
        _App('long_term', 'PENDING', tomorrow),     // upcoming
        _App('short', 'CONFIRMED', yesterday),      // 모집단 밖
      ];
      expect(homeOverdueCount(apps), 2);
      expect(queueOverdueCount(apps), 2);
    });

    test('overdue 0건에서도 일치', () {
      final apps = [
        _App('short', 'PENDING', todayKst),
        _App('long_term', 'PENDING', tomorrow),
      ];
      expect(homeOverdueCount(apps), 0);
      expect(queueOverdueCount(apps), 0);
    });

    test('BY_BUSINESS — 사업장별도 같은 predicate', () {
      final apps = [
        _App('short', 'PENDING', yesterday, businessId: 'A'),
        _App('short', 'PENDING', yesterday, businessId: 'A'),
        _App('long_term', 'PENDING', yesterday, businessId: 'A'),
        _App('short', 'PENDING', yesterday, businessId: 'B'),
        _App('long_term', 'PENDING', tomorrow, businessId: 'B'),
      ];
      final a = apps.where((x) => x.businessId == 'A').toList();
      final b = apps.where((x) => x.businessId == 'B').toList();
      expect(homeOverdueCount(a), 3, reason: 'short 2 + long 1');
      expect(homeOverdueCount(b), 1);
      expect(homeOverdueCount(apps), 4);
      expect(queueOverdueCount(apps), 4);
    });

    test('byBusiness가 같은 함수 결과를 쓴다', () {
      expect(
        cf.contains(
            'approvalByBiz.push({businessId: r.bizId, count: r.approval.total, overdueCount: r.approval.overdue});'),
        isTrue,
        reason: 'aggregate와 byBusiness가 srvHomeApproval 한 소스에서 나온다',
      );
    });
  });

  // ───────────────────────────────────────────────────────────
  // 범위 제한
  // ───────────────────────────────────────────────────────────
  group('AH-V2-04C.1 범위 제한', () {
    test('§12 total(count) 의미 불변 — PENDING 전체', () {
      final fn = _fnBody(cf, 'async function srvHomeApproval(');
      expect(fn.contains('total++;'), isTrue);
      // total은 조건 없이 증가한다
      final idx = fn.indexOf('total++;');
      final before = fn.substring(fn.indexOf('for (const doc'), idx);
      expect(before.contains('if ('), isFalse, reason: 'total에 새 조건이 붙으면 안 된다');
    });

    // [AH-V2-04C 갱신] initialFilter는 이 Phase에서는 금지였고, 후속 04C에서
    // canonical overdueCount를 근거로 연결됐다. 그 연결이 overdue 계약을
    // 그대로 쓰는지만 여기서 고정한다.
    test('§14 후속 initialFilter가 canonical overdueCount를 근거로 한다', () {
      final home = _codeOf(
          _src('lib/screens/business_admin/business_admin_home_screen.dart'));
      expect(home.contains('SupportReviewQueueScreen.route('), isTrue);
      expect(home.contains('initialFilter: (approval?.overdueCount ?? 0) > 0'),
          isTrue);
      expect(home.contains('? SupportReviewFilter.overdue'), isTrue);
      expect(home.contains(': SupportReviewFilter.all,'), isTrue);
    });

    test('§16 새 query·index 없음', () {
      final fn = _fnBody(cf, 'async function srvHomeApproval(');
      expect('db.collection('.allMatches(fn).length, 1,
          reason: '쿼리 1개 유지 — 추가 조회 없음');
      expect(fn.contains('.select("workDate")'), isTrue,
          reason: '투영은 오히려 줄었다');
    });

    // [AH-V2-04C 갱신] _Filter는 route 파라미터로 쓰기 위해
    // SupportReviewFilter로 공개 승격됐다. 값 4종은 그대로다.
    test('Queue 필터 4종 유지', () {
      for (final l in ['전체', '기한 지남', '오늘', '예정']) {
        expect(queue.contains("return '$l';"), isTrue, reason: l);
      }
      for (final v in ['all', 'overdue', 'today', 'upcoming']) {
        expect(queue.contains('SupportReviewFilter.$v'), isTrue, reason: v);
      }
      expect(queue.contains('enum SupportReviewFilter { all, overdue, today, upcoming }'),
          isTrue);
    });

    // [AH-V2-04C 갱신] 기본값은 상수 초기화에서 route/생성자 기본 파라미터로
    // 옮겨갔다. 지정하지 않으면 여전히 all이다.
    test('Queue 기본 필터는 여전히 all', () {
      expect(
        queue.contains('this.initialFilter = SupportReviewFilter.all,'),
        isTrue,
        reason: '생성자 기본값',
      );
      expect(
        queue.contains('SupportReviewFilter initialFilter = SupportReviewFilter.all,'),
        isTrue,
        reason: 'route 기본값',
      );
      expect(queue.contains('_filter = widget.initialFilter;'), isTrue);
    });

    test('날짜 grouping·정렬 유지', () {
      expect(queue.contains('_buildGroups()'), isTrue);
      final loader = _src('lib/services/support_review_queue_service.dart');
      expect(loader.contains('all.sort((a, b) => a.workDate.compareTo(b.workDate));'),
          isTrue);
    });

    test('permission 불변 — approval = canManageTo', () {
      final home = _codeOf(
          _src('lib/screens/business_admin/business_admin_home_screen.dart'));
      expect(home.contains('canManageTo'), isTrue);
      expect(cf.contains('const canTo    = !isSubAdmin || perms["canManageTo"]       === true;'),
          isTrue);
    });

    test('staffing·attendance를 건드리지 않았다', () {
      expect(cf.contains('available: failedBusinessCount === 0,'), isTrue);
      final home = _codeOf(
          _src('lib/screens/business_admin/business_admin_home_screen.dart'));
      expect(home.contains("label: '근태 확인'"), isTrue);
      expect(home.contains('AttendanceReviewHelper.requiresReviewNow('), isTrue);
      expect(home.contains('WorkDetailTimeService.load(allConfirmed)'), isTrue);
    });

    test('04B scope 표시 유지', () {
      final home = _codeOf(
          _src('lib/screens/business_admin/business_admin_home_screen.dart'));
      expect(home.contains('_isMultiBusinessScope'), isTrue);
      expect(home.contains('shortageScopeLabel()'), isTrue);
    });
  });
}
