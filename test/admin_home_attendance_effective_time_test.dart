import 'dart:io';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/utils/attendance_review_helper.dart';
import 'package:ALfit/utils/work_detail_helper.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// AH-V2-04A.1 ATTENDANCE-EFFECTIVE-TIME-ALIGNMENT
//
// actionability predicate는 04A에서 공유됐지만 시간 source가 달랐다.
//   Home   : application.startTime / endTime
//   Dialog : WorkDetailHelper.effectiveStart / effectiveEnd
//
// effectiveStart/End는 급여 확정(wage_confirm_dialog)도 쓰는
// "실제 적용 근무시간"이므로 이쪽이 canonical이다. Home을 여기에 맞춘다.
//
// 이 테스트는 두 호출부와 동일한 resolution을 거쳐
//   HOME_ATTENTION_COUNT == DIALOG_REVIEW_COUNT
// 를 검증한다. (§15 — 값 복사가 아니라 실제 source 경로)
// ═══════════════════════════════════════════════════════════════

final _workDate = DateTime(2026, 9, 13);
DateTime _t(int h, int m) => DateTime(2026, 9, 13, h, m);
DateTime _tomorrow(int h, int m) => DateTime(2026, 9, 14, h, m);

ApplicationModel _app({
  String id = 'app1',
  String workType = '피킹',
  String start = '09:00',
  String end = '18:00',
}) {
  return ApplicationModel(
    id: id,
    businessId: 'b1',
    businessName: '테스트사업장',
    toTitle: '테스트공고',
    workDate: _workDate,
    startTime: start,
    endTime: end,
    uid: 'u1',
    selectedWorkType: workType,
    wage: 12000,
    status: 'CONFIRMED',
    appliedAt: _workDate,
  );
}

AttendanceModel _att({
  String applicationId = 'app1',
  String status = 'scheduled',
  String wageStatus = AttendanceModel.wagePending,
  bool adminConfirmed = false,
  DateTime? checkInAt,
  DateTime? checkOutAt,
}) {
  return AttendanceModel(
    id: 'att_$applicationId',
    applicationId: applicationId,
    userId: 'u1',
    businessId: 'b1',
    businessName: '테스트사업장',
    workDate: _workDate,
    workType: '피킹',
    status: status,
    wageStatus: wageStatus,
    adminConfirmed: adminConfirmed,
    checkInAt: checkInAt,
    checkOutAt: checkOutAt,
    createdAt: _workDate,
  );
}

/// workType 단독 키만 가진 timeMap — composite 키가 없어 override가 적용된다.
/// (WorkDetailHelper.resolve 3순위 경로)
Map<String, dynamic> _overrideMap(String workType, String start, String end) => {
      workType: {'startTime': start, 'endTime': end},
    };

/// composite 키를 가진 timeMap — 지원서 시각과 정확히 일치하는 정상 경로
/// (WorkDetailHelper.resolve 1순위 경로)
Map<String, dynamic> _compositeMap(String workType, String start, String end) => {
      '${workType}_${start}_$end': {'startTime': start, 'endTime': end},
    };

// ── production과 동일한 resolution을 거치는 판정 ──────────────
bool _reviewVia(
  ApplicationModel app,
  Map<String, dynamic> timeMap,
  AttendanceModel? att,
  DateTime now,
) {
  return AttendanceReviewHelper.requiresReviewNow(
    now: now,
    workDate: _workDate,
    scheduledStart: WorkDetailHelper.effectiveStart(app, timeMap),
    scheduledEnd: WorkDetailHelper.effectiveEnd(app, timeMap),
    attendance: att,
  );
}

/// Home의 집계 형태 (확정 로스터 → 지원서 단위 Set)
int _homeCount(
  List<ApplicationModel> roster,
  Map<String, dynamic> timeMap,
  Map<String, AttendanceModel> attMap,
  DateTime now,
) {
  final ids = <String>{};
  for (final app in roster) {
    if (_reviewVia(app, timeMap, attMap[app.id], now)) ids.add(app.id);
  }
  return ids.length;
}

/// Dialog 검토 탭의 집계 형태 (_workersByTab case 0)
int _dialogReviewCount(
  List<ApplicationModel> roster,
  Map<String, dynamic> timeMap,
  Map<String, AttendanceModel> attMap,
  DateTime now,
) {
  return roster
      .where((app) => _reviewVia(app, timeMap, attMap[app.id], now))
      .length;
}

// ── 소스 배선 ──────────────────────────────────────────────────
const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _dialogPath =
    'lib/screens/business_admin/dialogs/attendance_status_dialog.dart';
const _servicePath = 'lib/services/work_detail_time_service.dart';

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
  late String home;
  late String dialog;

  setUpAll(() {
    home = _codeOf(_src(_homePath));
    dialog = _codeOf(_src(_dialogPath));
  });

  // ───────────────────────────────────────────────────────────
  // §12 start override
  // ───────────────────────────────────────────────────────────
  group('TIME-01/02 출근 시각 override', () {
    final app = _app(start: '09:00', end: '18:00');
    final map = _overrideMap('피킹', '10:00', '18:00');
    final roster = [app];
    final attMap = <String, AttendanceModel>{};

    test('override가 실제로 적용된다', () {
      expect(WorkDetailHelper.effectiveStart(app, map), '10:00');
    });

    test('TIME-01 now=09:30 → 양쪽 0 (아직 시작 전)', () {
      final now = _t(9, 30);
      expect(_homeCount(roster, map, attMap, now), 0);
      expect(_dialogReviewCount(roster, map, attMap, now), 0);
    });

    test('TIME-01 대조 — override 없으면 09:30에 대상이 된다', () {
      final now = _t(9, 30);
      expect(_homeCount(roster, const {}, attMap, now), 1,
          reason: 'override 유무가 실제로 경계를 바꾼다는 확인');
    });

    test('TIME-02 now=10:01 → 양쪽 1', () {
      final now = _t(10, 1);
      expect(_homeCount(roster, map, attMap, now), 1);
      expect(_dialogReviewCount(roster, map, attMap, now), 1);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §13 end override
  // ───────────────────────────────────────────────────────────
  group('TIME-03/04 퇴근 시각 override', () {
    final app = _app(start: '09:00', end: '17:00');
    final map = _overrideMap('피킹', '09:00', '18:00');
    final roster = [app];
    final attMap = {'app1': _att(checkInAt: _t(9, 0))};

    test('override가 실제로 적용된다', () {
      expect(WorkDetailHelper.effectiveEnd(app, map), '18:00');
    });

    test('TIME-03 now=17:30 → 양쪽 0 (아직 근무 중)', () {
      final now = _t(17, 30);
      expect(_homeCount(roster, map, attMap, now), 0);
      expect(_dialogReviewCount(roster, map, attMap, now), 0);
    });

    test('TIME-03 대조 — override 없으면 17:30에 퇴근미체크', () {
      expect(_homeCount(roster, const {}, attMap, _t(17, 30)), 1);
    });

    test('TIME-04 now=18:01 → 양쪽 1', () {
      final now = _t(18, 1);
      expect(_homeCount(roster, map, attMap, now), 1);
      expect(_dialogReviewCount(roster, map, attMap, now), 1);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §14 overnight
  // ───────────────────────────────────────────────────────────
  group('TIME-05/06 야간 시프트', () {
    final app = _app(start: '21:00', end: '05:00');
    final map = _overrideMap('피킹', '22:00', '06:00');
    final roster = [app];
    final attMap = {'app1': _att(checkInAt: _t(22, 0))};

    test('override 적용 확인', () {
      expect(WorkDetailHelper.effectiveStart(app, map), '22:00');
      expect(WorkDetailHelper.effectiveEnd(app, map), '06:00');
    });

    test('TIME-05 익일 05:00 → review NO (익일 종료 보정 유지)', () {
      final now = _tomorrow(5, 0);
      expect(_homeCount(roster, map, attMap, now), 0);
      expect(_dialogReviewCount(roster, map, attMap, now), 0);
    });

    test('TIME-06 익일 06:01 → review YES', () {
      final now = _tomorrow(6, 1);
      expect(_homeCount(roster, map, attMap, now), 1);
      expect(_dialogReviewCount(roster, map, attMap, now), 1);
    });

    test('야간 출근 미체크도 override 시작 시각을 따른다', () {
      final empty = <String, AttendanceModel>{};
      expect(_homeCount(roster, map, empty, _t(21, 30)), 0,
          reason: 'override 시작 22:00 전');
      expect(_homeCount(roster, map, empty, _t(22, 1)), 1);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §10 legacy fallback
  // ───────────────────────────────────────────────────────────
  group('legacy / fallback', () {
    test('timeMap이 비어도 지원서 시각으로 정상 동작', () {
      final app = _app(start: '09:00', end: '18:00');
      expect(WorkDetailHelper.effectiveStart(app, const {}), '09:00');
      expect(_homeCount([app], const {}, {}, _t(9, 1)), 1);
      expect(_homeCount([app], const {}, {}, _t(8, 59)), 0);
    });

    test('composite 키가 맞으면 override 경로를 타지 않는다', () {
      final app = _app(start: '09:00', end: '18:00');
      final map = {
        ..._compositeMap('피킹', '09:00', '18:00'),
        ..._overrideMap('피킹', '13:00', '22:00'), // 단독 키가 있어도
      };
      expect(WorkDetailHelper.effectiveStart(app, map), '09:00',
          reason: 'composite exact match가 1순위');
      expect(_homeCount([app], map, {}, _t(9, 1)), 1);
    });

    test('HH:mm:ss 레거시 포맷 fallback', () {
      final app = _app(start: '09:00:00', end: '18:00:00');
      expect(_homeCount([app], const {}, {}, _t(9, 1)), 1);
      expect(_homeCount([app], const {}, {}, _t(8, 59)), 0);
    });

    test('시각을 해석할 수 없으면 대상으로 올리지 않는다', () {
      final app = _app(start: '', end: '');
      // effectiveStart는 마지막 수단으로 09:00을 주지만,
      // 그건 helper의 기존 계약이며 여기서 바꾸지 않는다.
      expect(WorkDetailHelper.effectiveStart(app, const {}), '09:00');
      // timeMap에 빈 문자열이 명시돼 있으면 파싱 실패 → 판정 보류
      expect(
        AttendanceReviewHelper.requiresReviewNow(
          now: _t(23, 0),
          workDate: _workDate,
          scheduledStart: '',
          scheduledEnd: '',
        ),
        isFalse,
      );
    });
  });

  // ───────────────────────────────────────────────────────────
  // §11 actionability 계약 불변
  // ───────────────────────────────────────────────────────────
  group('actionability 상태 계약 불변', () {
    final app = _app(start: '09:00', end: '18:00');
    final map = _overrideMap('피킹', '10:00', '19:00');
    final roster = [app];

    test('종결 상태는 override와 무관하게 제외', () {
      final now = _tomorrow(0, 0);
      for (final att in [
        _att(status: AttendanceModel.statusNoShow),
        _att(status: AttendanceModel.statusAbsent),
        _att(wageStatus: AttendanceModel.wageConfirmed),
        _att(adminConfirmed: true, checkInAt: _t(10, 30), checkOutAt: _t(19, 0)),
      ]) {
        expect(_homeCount(roster, map, {'app1': att}, now), 0);
      }
    });

    test('지각 판정도 override 시각 기준', () {
      final now = _t(20, 0);
      // 10:00 시작 기준 → 09:30 출근은 지각 아님
      final early = {'app1': _att(checkInAt: _t(9, 30), checkOutAt: _t(19, 0))};
      expect(_homeCount(roster, map, early, now), 0);
      // 10:30 출근은 지각
      final late = {'app1': _att(checkInAt: _t(10, 30), checkOutAt: _t(19, 0))};
      expect(_homeCount(roster, map, late, now), 1);
    });

    test('조퇴 판정도 override 시각 기준', () {
      final now = _t(20, 0);
      // override end 19:00 → 18:00 퇴근은 조퇴
      final a = {'app1': _att(checkInAt: _t(10, 0), checkOutAt: _t(18, 0))};
      expect(_homeCount(roster, map, a, now), 1);
      final b = {'app1': _att(checkInAt: _t(10, 0), checkOutAt: _t(19, 0))};
      expect(_homeCount(roster, map, b, now), 0);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §15 alignment invariant
  // ───────────────────────────────────────────────────────────
  group('REAL_SOURCE_ALIGNMENT — Home == Dialog', () {
    test('혼합 로스터에서 두 집계가 일치한다', () {
      final roster = [
        _app(id: 'a1', start: '09:00', end: '18:00'),
        _app(id: 'a2', start: '09:00', end: '18:00'),
        _app(id: 'a3', start: '09:00', end: '18:00'),
        _app(id: 'a4', start: '09:00', end: '18:00'),
      ];
      final map = _overrideMap('피킹', '10:00', '19:00');
      final attMap = <String, AttendanceModel>{
        'a2': _att(applicationId: 'a2', checkInAt: _t(10, 30), checkOutAt: _t(19, 0)),
        'a3': _att(applicationId: 'a3', checkInAt: _t(10, 0)),
        'a4': _att(applicationId: 'a4', status: AttendanceModel.statusNoShow),
      };

      for (final now in [
        _t(9, 30), _t(10, 1), _t(14, 0), _t(19, 1), _tomorrow(1, 0),
      ]) {
        expect(
          _homeCount(roster, map, attMap, now),
          _dialogReviewCount(roster, map, attMap, now),
          reason: 'now=$now 에서 Home과 Dialog가 달라졌다',
        );
      }
    });

    test('override 없는 로스터에서도 일치', () {
      final roster = [_app(id: 'a1'), _app(id: 'a2')];
      final attMap = {'a1': _att(applicationId: 'a1', checkInAt: _t(9, 0))};
      for (final now in [_t(8, 0), _t(9, 1), _t(18, 1)]) {
        expect(_homeCount(roster, const {}, attMap, now),
            _dialogReviewCount(roster, const {}, attMap, now));
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  // 배선
  // ───────────────────────────────────────────────────────────
  group('TIME_SOURCE_CONTRACT 배선', () {
    test('Home이 effectiveStart/End를 쓴다', () {
      final l = _bodyOf(home, 'Future<void> _loadTodayAttendance(');
      expect(l.contains('WorkDetailHelper.effectiveStart(app, timeMap)'), isTrue);
      expect(l.contains('WorkDetailHelper.effectiveEnd(app, timeMap)'), isTrue);
      expect(l.contains('scheduledStart: app.startTime'), isFalse,
          reason: '지원서 원본 시각 직접 사용은 제거돼야 한다');
    });

    test('Home과 Dialog가 같은 로더를 쓴다', () {
      expect(home.contains('WorkDetailTimeService.load(allConfirmed)'), isTrue);
      expect(dialog.contains('WorkDetailTimeService.load('), isTrue);
    });

    test('로더가 dialog 밖 단일 소스로 존재한다', () {
      final svc = _codeOf(_src(_servicePath));
      expect(svc.contains('static Future<Map<String, dynamic>> load('), isTrue);
      expect(svc.contains('workDetails'), isTrue);
      // dialog에 중복 구현이 남아 있지 않다
      expect(dialog.contains('void extractFromWorkDetails('), isFalse);
    });

    test('쿼리는 근로자 단위가 아니라 슬롯 단위다 (N+1 금지)', () {
      final svc = _codeOf(_src(_servicePath));
      expect(svc.contains('final slotPairs = <String, Set<String>>{}'), isTrue,
          reason: '고유 (toId, slotId) Set으로 dedupe');
      expect(svc.contains('Future.wait(slotFutures)'), isTrue,
          reason: '병렬 배치 조회');
    });

    test('Dialog 검토 탭도 같은 predicate + 같은 시간 소스', () {
      final t = _bodyOf(dialog, 'List<ApplicationModel> _workersByTab(');
      expect(t.contains('AttendanceReviewHelper.requiresReviewNow('), isTrue);
      expect(t.contains('WorkDetailHelper.effectiveStart(app, _workDetailTimeMap)'),
          isTrue);
      expect(t.contains('WorkDetailHelper.effectiveEnd(app, _workDetailTimeMap)'),
          isTrue);
    });

    test('lateGrace 정책을 건드리지 않았다', () {
      // 주석에는 "적용하지 않는다"고 적혀 있으나 코드에서는 참조하지 않아야 한다.
      final helper = _codeOf(_src('lib/utils/attendance_review_helper.dart'));
      expect(helper.contains('lateGrace'), isFalse,
          reason: 'BACKLOG-ATTENDANCE-LATE-GRACE-CLASSIFICATION — 이번 Phase 범위 밖');
      expect(_src('lib/utils/attendance_status_helper.dart').contains('graceMinutes'),
          isTrue, reason: '기존 helper는 그대로');
    });

    test('write semantics 미변경 — 서비스는 읽기 전용', () {
      final svc = _src(_servicePath);
      expect(svc.contains('.set('), isFalse);
      expect(svc.contains('.update('), isFalse);
      expect(svc.contains('.delete('), isFalse);
      expect(svc.contains('httpsCallable'), isFalse);
    });

    test('AH-V2-04A 계약이 유지된다', () {
      expect(home.contains("label: '근태 확인'"), isTrue);
      expect(home.contains('reviewAppIds'), isTrue);
      final t = _bodyOf(dialog, 'List<ApplicationModel> _workersByTab(');
      expect(t.contains('case 0: return needsReview;'), isTrue);
      expect(t.contains('attendance?.status == AttendanceModel.statusAbsent'),
          isTrue);
    });
  });
}
