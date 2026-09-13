import 'dart:io';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/utils/attendance_review_helper.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// AH-V2-04A TODAY-ATTENDANCE-ACTIONABILITY
//
//   ACTION_REQUIRED != ABNORMAL_HISTORY
//   ACTION_REQUIRED != FUTURE_NOT_STARTED
//
// 처리하면 줄어드는 숫자여야 한다.
// Home `근태 확인`과 AttendanceStatusDialog 검토 탭이 같은 계약을 쓴다.
// ═══════════════════════════════════════════════════════════════

final _workDate = DateTime(2026, 9, 13);
DateTime _t(int h, int m) => DateTime(2026, 9, 13, h, m);

const _start = '09:00';
const _end = '18:00';

AttendanceModel _att({
  String id = 'att1',
  String applicationId = 'app1',
  String status = 'scheduled',
  String wageStatus = AttendanceModel.wagePending,
  bool adminConfirmed = false,
  DateTime? checkInAt,
  DateTime? checkOutAt,
}) {
  return AttendanceModel(
    id: id,
    applicationId: applicationId,
    userId: 'u1',
    businessId: 'b1',
    businessName: '테스트사업장',
    workDate: _workDate,
    workType: '일반',
    status: status,
    wageStatus: wageStatus,
    adminConfirmed: adminConfirmed,
    checkInAt: checkInAt,
    checkOutAt: checkOutAt,
    createdAt: _workDate,
  );
}

bool _review({
  required DateTime now,
  AttendanceModel? attendance,
  String start = _start,
  String end = _end,
}) =>
    AttendanceReviewHelper.requiresReviewNow(
      now: now,
      workDate: _workDate,
      scheduledStart: start,
      scheduledEnd: end,
      attendance: attendance,
    );

// ── 소스 배선 검증용 ──────────────────────────────────────────
const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _dialogPath =
    'lib/screens/business_admin/dialogs/attendance_status_dialog.dart';

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
  // lifecycle
  // ───────────────────────────────────────────────────────────
  group('AHV2-04A-01 근무 시작 전 + 근태 없음 → 처리 대상 아님', () {
    test('attendance 문서 자체가 없음', () {
      expect(_review(now: _t(8, 0)), isFalse);
    });

    test('scheduled 문서만 있고 출근 기록 없음', () {
      expect(_review(now: _t(8, 59), attendance: _att()), isFalse);
    });

    test('시작 1분 전까지는 아님', () {
      expect(_review(now: _t(8, 59)), isFalse);
    });
  });

  group('AHV2-04A-02 시작 시각 경과 + 근태 없음 → 처리 대상', () {
    test('정각부터 포함된다', () {
      expect(_review(now: _t(9, 0)), isTrue);
    });

    test('경과 후에도 유지', () {
      expect(_review(now: _t(11, 30)), isTrue);
      expect(_review(now: _t(11, 30), attendance: _att()), isTrue);
    });

    test('지각 유예(lateGrace)를 적용하지 않는다', () {
      // 사업장 lateGrace는 체크인 지각 분류 규칙이며 미출근 판정에 쓰인 적 없다.
      // 새 정책을 임의로 만들지 않는다 (§8).
      expect(_review(now: _t(9, 3)), isTrue);
    });
  });

  group('AHV2-04A-03 노쇼 처리하면 목록에서 빠진다', () {
    test('처리 전 → 대상', () {
      expect(_review(now: _t(10, 0)), isTrue);
    });

    test('처리 후 → 제외', () {
      final after = _att(
        status: AttendanceModel.statusNoShow,
        wageStatus: AttendanceModel.wageConfirmed,
      );
      expect(_review(now: _t(10, 0), attendance: after), isFalse);
    });

    test('완료 표면에서는 여전히 종결 상태로 식별된다', () {
      expect(
        AttendanceReviewHelper.isSettled(
            _att(status: AttendanceModel.statusNoShow)),
        isTrue,
      );
    });
  });

  // ───────────────────────────────────────────────────────────
  // 처리 완료 상태
  // ───────────────────────────────────────────────────────────
  group('AHV2-04A-04 adminConfirmed → 제외', () {
    test('이상 근태여도 관리자 확인 완료면 빠진다', () {
      final late = _att(
        adminConfirmed: true,
        checkInAt: _t(9, 30),
        checkOutAt: _t(18, 0),
      );
      expect(_review(now: _t(19, 0), attendance: late), isFalse);
    });

    test('확인 해제하면 다시 대상이 된다', () {
      final late = _att(checkInAt: _t(9, 30), checkOutAt: _t(18, 0));
      expect(_review(now: _t(19, 0), attendance: late), isTrue);
    });
  });

  group('AHV2-04A-05 NO_SHOW → 제외', () {
    test('wageStatus 유무와 무관하게 제외', () {
      expect(
        _review(
            now: _t(20, 0), attendance: _att(status: AttendanceModel.statusNoShow)),
        isFalse,
      );
    });
  });

  group('AHV2-04A-06 absent lifecycle', () {
    // absent는 네 경로 모두 시스템 확정이다:
    //   자동결근 스케줄러(wageStatus=confirmed) / 퇴사 D+1 / 사업장 삭제 / 계정 삭제
    // 뒤 세 경로는 wageStatus를 쓰지 않으므로 status로 직접 판정해야 한다.
    test('wageStatus confirmed 인 자동결근 → 제외', () {
      expect(
        _review(
          now: _t(20, 0),
          attendance: _att(
            status: AttendanceModel.statusAbsent,
            wageStatus: AttendanceModel.wageConfirmed,
          ),
        ),
        isFalse,
      );
    });

    test('wageStatus 없는 퇴사·삭제 경로 absent도 제외', () {
      expect(
        _review(
            now: _t(20, 0),
            attendance: _att(status: AttendanceModel.statusAbsent)),
        isFalse,
        reason: 'wageStatus가 없어 isDone에 안 걸리던 구멍',
      );
    });

    test('정산 진입 상태는 모두 제외', () {
      for (final w in [
        AttendanceModel.wageCalculated,
        AttendanceModel.wageConfirmed,
        AttendanceModel.wageTransferred,
      ]) {
        expect(
          _review(
            now: _t(20, 0),
            attendance: _att(
                wageStatus: w, checkInAt: _t(9, 30), checkOutAt: _t(18, 0)),
          ),
          isFalse,
          reason: w,
        );
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  // 이상 상태
  // ───────────────────────────────────────────────────────────
  group('AHV2-04A-07 지각 — 관리자 조치 있음 → 포함', () {
    test('출퇴근 완료 + 지각 → 대상', () {
      final a = _att(checkInAt: _t(9, 30), checkOutAt: _t(18, 0));
      expect(_review(now: _t(19, 0), attendance: a), isTrue);
    });

    test('정시 출퇴근 → 대상 아님 (마감은 별도 행이 담당)', () {
      final a = _att(checkInAt: _t(9, 0), checkOutAt: _t(18, 0));
      expect(_review(now: _t(19, 0), attendance: a), isFalse);
    });
  });

  group('AHV2-04A-08 퇴근 미체크', () {
    test('근무 중(종료 전)은 정상 — 대상 아님', () {
      final a = _att(checkInAt: _t(9, 0));
      expect(_review(now: _t(14, 0), attendance: a), isFalse);
    });

    test('종료 시각 경과 후 퇴근 기록 없음 → 대상', () {
      final a = _att(checkInAt: _t(9, 0));
      expect(_review(now: _t(18, 0), attendance: a), isTrue);
      expect(_review(now: _t(21, 0), attendance: a), isTrue);
    });

    test('야간 시프트는 자정 보정 — 익일 종료 전까지 정상', () {
      final a = _att(checkInAt: _t(22, 0));
      expect(
        _review(now: _t(23, 30), attendance: a, start: '22:00', end: '06:00'),
        isFalse,
      );
      expect(
        _review(
            now: DateTime(2026, 9, 14, 6, 30),
            attendance: a,
            start: '22:00',
            end: '06:00'),
        isTrue,
      );
    });
  });

  group('AHV2-04A-09 조퇴 → 포함', () {
    test('예정보다 이른 퇴근 → 대상', () {
      final a = _att(checkInAt: _t(9, 0), checkOutAt: _t(15, 0));
      expect(_review(now: _t(16, 0), attendance: a), isTrue);
    });

    test('조퇴여도 관리자 확인 완료면 제외', () {
      final a = _att(
          checkInAt: _t(9, 0), checkOutAt: _t(15, 0), adminConfirmed: true);
      expect(_review(now: _t(16, 0), attendance: a), isFalse);
    });
  });

  group('AHV2-04A-10 시각 해석 불가 → 임의 판정하지 않음', () {
    test('startTime이 비정상이면 미출근을 대상으로 올리지 않는다', () {
      expect(_review(now: _t(23, 0), start: '', end: ''), isFalse);
    });

    test('HH:mm:ss 레거시 포맷은 정상 처리', () {
      expect(_review(now: _t(9, 0), start: '09:00:00', end: '18:00:00'), isTrue);
      expect(_review(now: _t(8, 0), start: '09:00:00', end: '18:00:00'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §25 핵심 회귀 — 처리하면 줄어든다
  // ───────────────────────────────────────────────────────────
  group('AHV2-04A-11 COUNT_DECREASE_AFTER_ACTION', () {
    /// Home과 dialog가 공유하는 집계 규칙 재현 (지원서 단위 Set)
    int countFor(Map<String, AttendanceModel?> roster, DateTime now) {
      final ids = <String>{};
      roster.forEach((appId, att) {
        if (_review(now: now, attendance: att)) ids.add(appId);
      });
      return ids.length;
    }

    test('미출근 1명 → 노쇼 처리 → 0명', () {
      final now = _t(10, 0);
      final before = <String, AttendanceModel?>{'app1': null};
      expect(countFor(before, now), 1);

      final after = <String, AttendanceModel?>{
        'app1': _att(
          status: AttendanceModel.statusNoShow,
          wageStatus: AttendanceModel.wageConfirmed,
        ),
      };
      expect(countFor(after, now), 0, reason: '처리했는데 줄지 않으면 Phase 미완료');
    });

    test('지각 1명 → 관리자 확인 → 0명', () {
      final now = _t(19, 0);
      final att = _att(checkInAt: _t(9, 30), checkOutAt: _t(18, 0));
      expect(countFor({'app1': att}, now), 1);
      expect(
        countFor({'app1': att.copyWith(adminConfirmed: true)}, now),
        0,
      );
    });

    test('여러 건을 순차 처리하면 순차적으로 줄어든다', () {
      final now = _t(19, 0);
      final roster = <String, AttendanceModel?>{
        'app1': null, // 미출근
        'app2': _att(id: 'a2', applicationId: 'app2', checkInAt: _t(9, 30), checkOutAt: _t(18, 0)), // 지각
        'app3': _att(id: 'a3', applicationId: 'app3', checkInAt: _t(9, 0)), // 퇴근미체크
        'app4': _att(id: 'a4', applicationId: 'app4', checkInAt: _t(9, 0), checkOutAt: _t(18, 0)), // 정상
      };
      expect(countFor(roster, now), 3);

      roster['app1'] = _att(status: AttendanceModel.statusNoShow);
      expect(countFor(roster, now), 2);

      roster['app2'] = roster['app2']!.copyWith(adminConfirmed: true);
      expect(countFor(roster, now), 1);

      roster['app3'] = roster['app3']!.copyWith(checkOutAt: _t(18, 0));
      expect(countFor(roster, now), 0, reason: '정시 퇴근으로 보정 완료');
    });

    test('DUPLICATE_WORKER_COUNT_RISK — 지원서 단위라 1명은 1로 센다', () {
      final now = _t(10, 0);
      // 같은 사람이 여러 이상을 갖더라도 지원서 1건 = 1명
      final roster = <String, AttendanceModel?>{'app1': null};
      expect(countFor(roster, now), 1);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §24 Home ↔ dialog 배선
  // ───────────────────────────────────────────────────────────
  group('AHV2-04A-12 공유 predicate 배선', () {
    test('Home이 canonical helper를 쓴다', () {
      final l = _bodyOf(home, 'Future<void> _loadTodayAttendance(');
      expect(l.contains('AttendanceReviewHelper.requiresReviewNow('), isTrue);
      expect(l.contains('reviewAppIds'), isTrue, reason: 'unique 지원서 Set');
    });

    test('Home에 옛 조건이 남아 있지 않다', () {
      final l = _bodyOf(home, 'Future<void> _loadTodayAttendance(');
      expect(l.contains('a.isNoShow || a.isAbsent'), isFalse,
          reason: '처리 완료 이력을 세던 조건');
      expect(l.contains('needsAttention++'), isFalse);
    });

    test('dialog 검토 탭이 같은 helper를 쓴다', () {
      final t = _bodyOf(dialog, 'List<ApplicationModel> _workersByTab(');
      expect(t.contains('AttendanceReviewHelper.requiresReviewNow('), isTrue);
      expect(t.contains('case 0: return needsReview;'), isTrue);
      expect(t.contains("reviewStatuses"), isFalse,
          reason: '옛 상태 문자열 집합은 제거돼야 한다');
    });

    test('dialog가 workDetail 해석 시각을 넘긴다', () {
      final t = _bodyOf(dialog, 'List<ApplicationModel> _workersByTab(');
      expect(t.contains('WorkDetailHelper.effectiveStart(app, _workDetailTimeMap)'),
          isTrue);
      expect(t.contains('WorkDetailHelper.effectiveEnd(app, _workDetailTimeMap)'),
          isTrue);
    });

    test('결근은 완료 탭으로 간다 (검토·정상 아님)', () {
      final t = _bodyOf(dialog, 'List<ApplicationModel> _workersByTab(');
      expect(t.contains('attendance?.status == AttendanceModel.statusAbsent'),
          isTrue);
    });

    test('나머지 탭 역할이 유지된다', () {
      final t = _bodyOf(dialog, 'List<ApplicationModel> _workersByTab(');
      expect(t.contains('case 2: return isAdminConfirmed && !isDone;'), isTrue);
      expect(t.contains('case 3: return isDone;'), isTrue);
      expect(t.contains('case 1: return !needsReview && !isDone && !isAdminConfirmed;'),
          isTrue);
    });

    test('노쇼 칩은 검토 탭 모집단에서만 나온다 → 시작 전 인원 제외', () {
      // noShowTargets는 _tabWorkers[0](= needsReview)에서만 뽑는다.
      // 검토 탭이 좁아지면 노쇼 대상도 함께 좁아진다.
      final flat = dialog.replaceAll(RegExp(r'\s+'), ' ');
      expect(flat.contains('final noShowTargets = _currentTabIndex == 0'), isTrue);
      expect(
        flat.contains(
            "? tabWorkers.where((a) => _getAttendanceStatus(a)['status'] == 'pending').toList()"),
        isTrue,
      );
      final t = _bodyOf(dialog, 'List<ApplicationModel> _workersByTab(');
      expect(t.contains('case 0: return needsReview;'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // 범위 제한
  // ───────────────────────────────────────────────────────────
  group('AH-V2-04A 범위 제한', () {
    test('카피만 정렬됐다', () {
      expect(home.contains("label: '근태 확인'"), isTrue);
      expect(home.contains("label: '확인 필요'"), isFalse);
    });

    // [AH-V2-06 갱신] 04A는 출근 지표를 건드리지 않았고, 06에서 분자 모집단이
    // attendance 문서 → 오늘 확정 로스터로 교정되고 라벨이 '현재 출근'이 됐다.
    // 04A가 만든 '근태 확인'과 같은 모집단을 쓰게 된 것이 핵심이다.
    test('필요·확정·부족은 그대로, 출근은 같은 로스터를 쓴다', () {
      expect(home.contains("label: '필요'"), isTrue);
      expect(home.contains("label: '확정'"), isTrue);
      expect(home.contains("label: '부족'"), isTrue);
      expect(home.contains("label: '현재 출근'"), isTrue);
      final l = _bodyOf(home, 'Future<void> _loadTodayAttendance(');
      expect(l.contains('allAttendance.where((a) => a.hasCheckedIn).length'),
          isFalse, reason: '로스터 밖 문서까지 세던 경로');
      expect(l.contains('final hasCheckedIn = attMap[app.id]?.checkInAt != null;'),
          isTrue);
      // 근태 확인과 같은 루프·같은 모집단
      expect(l.contains('for (final app in allConfirmed) {'), isTrue);
      expect(l.contains('AttendanceReviewHelper.requiresReviewNow('), isTrue);
    });

    test('상태별 Home row를 추가하지 않았다', () {
      final m = _bodyOf(home, 'Widget _buildAttendanceMetrics(');
      expect("_opsMetric(".allMatches(m).length, 2, reason: '출근 + 근태 확인 2개만');
    });

    test('permission 게이트 유지', () {
      final m = _bodyOf(home, 'Widget _buildAttendanceMetrics(');
      expect(m.contains('canManageWorkers'), isTrue);
    });

    test('ERROR != ZERO 유지', () {
      final l = _bodyOf(home, 'Future<void> _loadTodayAttendance(');
      expect(l.contains('_todayCheckedIn      = null'), isTrue);
      expect(l.contains('_todayNeedsAttention = null'), isTrue);
      final m = _bodyOf(home, 'Widget _buildAttendanceMetrics(');
      expect(m.contains('출근 현황을 불러오지 못했습니다'), isTrue);
    });

    test('empty 표현을 바꾸지 않았다 (별도 카드 없음)', () {
      final m = _bodyOf(home, 'Widget _buildAttendanceMetrics(');
      expect(m.contains('근태 확인이 필요 없어요'), isFalse);
    });

    test('AH-V2-03 staffing 계약 유지', () {
      expect(home.contains('hasUsableData'), isTrue);
      expect(home.contains('향후 7일 예정된 인력 운영이 없어요'), isTrue);
    });

    test('write 정책을 바꾸지 않았다', () {
      // helper는 순수 판정만 한다 — Firestore 접근 없음
      final src = File('lib/utils/attendance_review_helper.dart').readAsStringSync();
      expect(src.contains('FirebaseFirestore'), isFalse);
      expect(src.contains('httpsCallable'), isFalse);
      expect(src.contains('.set(') || src.contains('.update('), isFalse);
    });
  });
}
