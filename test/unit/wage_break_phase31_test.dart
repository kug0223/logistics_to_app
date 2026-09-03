// test/unit/wage_break_phase31_test.dart
// [Phase 3.1] 휴게 breakdown — WageDetailModel 신규 필드 단위 테스트
//
// 실행: flutter test test/unit/wage_break_phase31_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';

// ─── 픽스처 헬퍼 ─────────────────────────────────────────────────────────────

Map<String, dynamic> _legacyMap({
  int breakMinutes = 60,
  int scheduledBreakMinutes = 60,
  int scheduledMinutes = 480,
  int actualMinutes = 480,
  int workMinutes = 420,
}) =>
    {
      'wageType': 'hourly',
      'baseWage': 10030,
      'scheduledMinutes': scheduledMinutes,
      'scheduledBreakMinutes': scheduledBreakMinutes,
      'actualMinutes': actualMinutes,
      'breakMinutes': breakMinutes,
      'workMinutes': workMinutes,
      'overtimeMinutes': 0,
      'earlyArrivalMinutes': 0,
      'nightMinutes': 0,
      'baseAmount': 70210,
      'overtimeAmount': 0,
      'earlyArrivalAmount': 0,
      'nightAmount': 0,
      'additionalAmount': 0,
      'deductionAmount': 0,
      'weeklyHolidayAmount': 0,
      'totalAmount': 70210,
      'nightAllowanceApplied': false,
      'appliedMinimumWage': 10030,
      'appliedSupplementWage': 10030,
      'taxDeductionType': 'none',
      'employmentInsuranceDeduction': 0,
      'nationalPensionDeduction': 0,
      'healthInsuranceDeduction': 0,
      'ltcInsuranceDeduction': 0,
      'incomeTaxDeduction': 0,
      'retroactiveDeduction': 0,
      'netWage': 70210,
    };

Map<String, dynamic> _breakdownMap({
  int scheduledBreak = 60,
  int appliedScheduled = 30,
  int additional = 30,
  int totalBreak = 60,
}) =>
    {
      ..._legacyMap(
          breakMinutes: totalBreak, scheduledBreakMinutes: scheduledBreak),
      'appliedScheduledBreakMinutes': appliedScheduled,
      'additionalBreakMinutes': additional,
    };

// ─── 테스트 ──────────────────────────────────────────────────────────────────

void main() {
  // 1. breakReviewRequired 검출 로직
  group('[Phase 3.1] breakReviewRequired 검출', () {
    test('actualPresence < scheduledPresence → 검토 필요', () {
      final m = WageDetailModel.fromMap(
        _legacyMap(
          scheduledMinutes: 480,
          scheduledBreakMinutes: 60,
          actualMinutes: 450,
          breakMinutes: 60,
          workMinutes: 390,
        ),
      );
      final scheduledPresence = m.scheduledMinutes - m.scheduledBreakMinutes;
      final actualPresence = m.actualMinutes - m.breakMinutes;
      expect(actualPresence < scheduledPresence, isTrue);
      expect(m.scheduledBreakMinutes > 0, isTrue);
    });

    test('actualPresence == scheduledPresence → 검토 불필요', () {
      final m = WageDetailModel.fromMap(
        _legacyMap(
          scheduledMinutes: 480,
          scheduledBreakMinutes: 60,
          actualMinutes: 480,
          breakMinutes: 60,
          workMinutes: 420,
        ),
      );
      final scheduledPresence = m.scheduledMinutes - m.scheduledBreakMinutes;
      final actualPresence = m.actualMinutes - m.breakMinutes;
      expect(actualPresence < scheduledPresence, isFalse);
    });

    test('scheduledBreakMinutes=0이면 검토 불필요', () {
      final m = WageDetailModel.fromMap(
        _legacyMap(
          scheduledBreakMinutes: 0,
          actualMinutes: 450,
          breakMinutes: 0,
          workMinutes: 450,
        ),
      );
      expect(m.scheduledBreakMinutes > 0, isFalse);
    });
  });

  // 2. 신규 레코드 — fromMap / hasBreakBreakdown
  group('[Phase 3.1] 신규 레코드 파싱 (hasBreakBreakdown)', () {
    test('appliedScheduledBreakMinutes 포함 → hasBreakBreakdown true', () {
      final m = WageDetailModel.fromMap(_breakdownMap());
      expect(m.hasBreakBreakdown, isTrue);
      expect(m.appliedScheduledBreakMinutes, 30);
      expect(m.additionalBreakMinutes, 30);
    });

    test('effectiveAppliedScheduledBreak = appliedScheduledBreakMinutes', () {
      final m = WageDetailModel.fromMap(_breakdownMap(appliedScheduled: 30));
      expect(m.effectiveAppliedScheduledBreak, 30);
    });

    test('effectiveAdditionalBreak = additionalBreakMinutes', () {
      final m = WageDetailModel.fromMap(_breakdownMap(additional: 30));
      expect(m.effectiveAdditionalBreak, 30);
    });

    test('hasReducedScheduledBreak: applied(30) < scheduled(60) → true', () {
      final m = WageDetailModel.fromMap(
          _breakdownMap(scheduledBreak: 60, appliedScheduled: 30));
      expect(m.hasReducedScheduledBreak, isTrue);
    });

    test('hasReducedScheduledBreak: applied == scheduled → false', () {
      final m = WageDetailModel.fromMap(
          _breakdownMap(
              scheduledBreak: 60,
              appliedScheduled: 60,
              additional: 0,
              totalBreak: 60));
      expect(m.hasReducedScheduledBreak, isFalse);
    });

    test('추가 휴게만 있을 때 (applied=60, additional=30, total=90)', () {
      final m = WageDetailModel.fromMap(_breakdownMap(
          scheduledBreak: 60,
          appliedScheduled: 60,
          additional: 30,
          totalBreak: 90));
      expect(m.effectiveAppliedScheduledBreak, 60);
      expect(m.effectiveAdditionalBreak, 30);
      expect(m.hasAdditionalBreak, isTrue);
      expect(m.hasReducedScheduledBreak, isFalse);
    });
  });

  // 3. legacy 레코드 — null 게터 폴백
  group('[Phase 3.1] legacy 레코드 fallback getters', () {
    test('breakdown 없으면 hasBreakBreakdown false', () {
      final m = WageDetailModel.fromMap(_legacyMap());
      expect(m.hasBreakBreakdown, isFalse);
      expect(m.appliedScheduledBreakMinutes, isNull);
      expect(m.additionalBreakMinutes, isNull);
    });

    test('effectiveAppliedScheduledBreak = min(scheduled, total) 폴백', () {
      // scheduled=60, break=60 → min(60,60)=60
      final m1 = WageDetailModel.fromMap(
          _legacyMap(scheduledBreakMinutes: 60, breakMinutes: 60));
      expect(m1.effectiveAppliedScheduledBreak, 60);

      // scheduled=60, break=30 (조기 퇴근) → min(60,30)=30
      final m2 = WageDetailModel.fromMap(
          _legacyMap(scheduledBreakMinutes: 60, breakMinutes: 30));
      expect(m2.effectiveAppliedScheduledBreak, 30);

      // scheduled=0 (TO에 휴게 없음), break=30 → min(0,30)=0
      final m3 = WageDetailModel.fromMap(
          _legacyMap(scheduledBreakMinutes: 0, breakMinutes: 30));
      expect(m3.effectiveAppliedScheduledBreak, 0);
    });

    test('effectiveAdditionalBreak = max(0, total - applied) 폴백', () {
      // scheduled=60, break=90 → applied폴백=60, additional폴백=30
      final m = WageDetailModel.fromMap(
          _legacyMap(scheduledBreakMinutes: 60, breakMinutes: 90));
      expect(m.effectiveAdditionalBreak, 30);

      // scheduled=60, break=60 → additional=0
      final m2 = WageDetailModel.fromMap(
          _legacyMap(scheduledBreakMinutes: 60, breakMinutes: 60));
      expect(m2.effectiveAdditionalBreak, 0);
    });

    test('breakMinutes=0 → effectiveApplied=0, effectiveAdditional=0', () {
      final m = WageDetailModel.fromMap(
          _legacyMap(breakMinutes: 0, scheduledBreakMinutes: 60));
      expect(m.effectiveAppliedScheduledBreak, 0);
      expect(m.effectiveAdditionalBreak, 0);
      expect(m.hasAdditionalBreak, isFalse);
    });
  });

  // 4. EDIT 테스트 — _applyBreakComponents 동작 (breakdown 보존 / legacy upgrade)
  group('[Phase 3.1] EDIT: _applyBreakComponents 동작', () {
    // EDIT-01: breakdown이 있는 레코드를 편집해도 breakdown이 유지된다
    test('EDIT-01: copyWith applied+additional → hasBreakBreakdown 유지', () {
      final original = WageDetailModel.fromMap(
        _breakdownMap(scheduledBreak: 60, appliedScheduled: 30, additional: 30, totalBreak: 60),
      );
      expect(original.hasBreakBreakdown, isTrue);

      // _applyBreakComponents 로직 시뮬레이션: 새 applied/additional로 copyWith
      final edited = original.copyWith(
        breakMinutes: 45 + 15,
        appliedScheduledBreakMinutes: 45,
        additionalBreakMinutes: 15,
      );

      expect(edited.hasBreakBreakdown, isTrue,
          reason: 'breakdown은 편집 후에도 유지되어야 한다');
      expect(edited.appliedScheduledBreakMinutes, 45);
      expect(edited.additionalBreakMinutes, 15);
      expect(edited.breakMinutes, 60);
    });

    // EDIT-02: legacy 레코드를 편집하면 breakdown이 생성된다 (upgrade)
    test('EDIT-02: legacy 레코드 편집 시 breakdown 신규 생성', () {
      final legacy = WageDetailModel.fromMap(_legacyMap(breakMinutes: 60));
      expect(legacy.hasBreakBreakdown, isFalse, reason: 'legacy 레코드는 breakdown 없음');

      // _applyBreakComponents로 edited 저장 시 copyWith(applied:..., additional:...) 호출됨
      final upgraded = legacy.copyWith(
        appliedScheduledBreakMinutes: 60,
        additionalBreakMinutes: 0,
      );

      expect(upgraded.hasBreakBreakdown, isTrue,
          reason: 'copyWith로 applied+additional 주입 후 breakdown 존재해야 한다');
      expect(upgraded.appliedScheduledBreakMinutes, 60);
      expect(upgraded.additionalBreakMinutes, 0);
    });
  });

  // 5. GATE 테스트 — _breakReviewGatePassed 순수 로직
  group('[Phase 3.1] GATE: breakReviewGatePassed 순수 로직', () {
    // 공통 헬퍼 — 다이얼로그 인스턴스 없이 순수 gate 논리만 테스트
    bool gatePass({required bool required, required bool reviewed}) =>
        !(required && !reviewed);

    // GATE-01: required=false → 항상 통과
    test('GATE-01: reviewRequired=false → 게이트 통과', () {
      expect(gatePass(required: false, reviewed: false), isTrue);
      expect(gatePass(required: false, reviewed: true), isTrue);
    });

    // GATE-02: required=true, reviewed=false → 차단
    test('GATE-02: reviewRequired=true, reviewed=false → 게이트 차단', () {
      expect(gatePass(required: true, reviewed: false), isFalse);
    });

    // GATE-03: required=true, reviewed=true → 통과
    test('GATE-03: reviewRequired=true, reviewed=true → 게이트 통과', () {
      expect(gatePass(required: true, reviewed: true), isTrue);
    });

    // GATE-04: Map lookup 시뮬레이션 — null을 false로 취급
    test('GATE-04: Map에 키 없음(null) → reviewed=false로 취급, required=true면 차단', () {
      final reviewRequired = <String, bool>{'appA': true};
      final reviewCompleted = <String, bool>{};
      final appId = 'appA';

      final pass = !(reviewRequired[appId] == true && reviewCompleted[appId] != true);
      expect(pass, isFalse, reason: 'reviewed 키 없음 = 미검토 → 차단');
    });
  });

  // 6. GROUP 테스트 — 그룹 칩 override 로직 (Set<String> 보호)
  group('[Phase 3.1] GROUP: override marker 보호', () {
    // GROUP-01: override 없는 근무자는 그룹 칩 변경에 영향 받음
    test('GROUP-01: override 없는 근무자는 그룹 변경 반영', () {
      final overridden = <String>{};
      final workerIds = ['w1', 'w2', 'w3'];
      final extraBreak = <String, int>{};

      // 그룹 칩 30분 적용
      final toUpdate = workerIds.where((id) => !overridden.contains(id)).toList();
      for (final id in toUpdate) {
        extraBreak[id] = 30;
      }

      expect(extraBreak['w1'], 30);
      expect(extraBreak['w2'], 30);
      expect(extraBreak['w3'], 30);
    });

    // GROUP-02: override된 근무자는 그룹 칩 변경에서 제외됨
    test('GROUP-02: override 근무자는 그룹 변경에서 보호', () {
      final overridden = <String>{'w2'}; // w2는 개별 설정
      final workerIds = ['w1', 'w2', 'w3'];
      final extraBreak = <String, int>{'w2': 60}; // w2 개별값

      final toUpdate = workerIds.where((id) => !overridden.contains(id)).toList();
      for (final id in toUpdate) {
        extraBreak[id] = 30;
      }

      expect(extraBreak['w1'], 30, reason: 'override 없는 w1은 변경됨');
      expect(extraBreak['w2'], 60, reason: 'override된 w2는 보호되어 기존값 유지');
      expect(extraBreak['w3'], 30, reason: 'override 없는 w3은 변경됨');
    });

    // GROUP-03: 개별 설정 후 override marker 추가 확인
    test('GROUP-03: _setWorkerBreakComponents 호출 시 overridden에 추가', () {
      final overridden = <String>{};
      // _setWorkerBreakComponents 로직 시뮬레이션
      void setComponents(String id) {
        overridden.add(id);
      }
      setComponents('w2');
      expect(overridden.contains('w2'), isTrue);
    });

    // GROUP-04: 모든 근무자가 override되면 그룹 칩은 아무것도 변경하지 않음
    test('GROUP-04: 전원 override 시 그룹 칩 변경 없음', () {
      final overridden = <String>{'w1', 'w2', 'w3'};
      final workerIds = ['w1', 'w2', 'w3'];
      final extraBreak = <String, int>{'w1': 60, 'w2': 90, 'w3': 0};

      final toUpdate = workerIds.where((id) => !overridden.contains(id)).toList();
      for (final id in toUpdate) {
        extraBreak[id] = 30;
      }

      expect(toUpdate, isEmpty, reason: '모든 근무자가 override → toUpdate 비어있음');
      expect(extraBreak['w1'], 60);
      expect(extraBreak['w2'], 90);
      expect(extraBreak['w3'], 0);
    });
  });

  // 7. MEMO — toMap에 memo 필드 보존
  group('[Phase 3.1] MEMO: toMap() memo 필드 보존', () {
    test('MEMO: memo 필드가 toMap()에 포함된다', () {
      final raw = {
        ..._legacyMap(),
        'memo': '관리자 메모: 조기 퇴근 확인',
      };
      final m = WageDetailModel.fromMap(raw);
      final map = m.toMap();
      expect(map.containsKey('memo'), isTrue,
          reason: 'memo는 toMap()에 반드시 포함되어야 한다 — CF ALLOW_FIELDS에 추가됨');
      expect(map['memo'], '관리자 메모: 조기 퇴근 확인');
    });

    test('MEMO: memo null 시 toMap()에서 생략 또는 null', () {
      final m = WageDetailModel.fromMap(_legacyMap());
      final map = m.toMap();
      // memo가 없거나 null이어야 한다
      final memoVal = map['memo'];
      expect(memoVal == null || !map.containsKey('memo'), isTrue,
          reason: 'memo 없으면 null 또는 키 미포함이 맞음');
    });
  });

  // 9. fromMap 파싱 엣지 케이스
  group('[Phase 3.1] fromMap 파싱', () {
    test('null 필드는 fromMap에서 null로 파싱', () {
      final m = WageDetailModel.fromMap(_legacyMap());
      expect(m.appliedScheduledBreakMinutes, isNull);
      expect(m.additionalBreakMinutes, isNull);
    });

    test('double 값 (30.0) → int로 파싱', () {
      final raw = {
        ..._legacyMap(),
        'appliedScheduledBreakMinutes': 30.0,
        'additionalBreakMinutes': 30.0,
      };
      final m = WageDetailModel.fromMap(raw);
      expect(m.appliedScheduledBreakMinutes, 30);
      expect(m.additionalBreakMinutes, 30);
      expect(m.appliedScheduledBreakMinutes, isA<int>());
    });

    test('breakdown=0 (휴게 전혀 안 씀)', () {
      final raw = {
        ..._legacyMap(breakMinutes: 0, workMinutes: 480),
        'appliedScheduledBreakMinutes': 0,
        'additionalBreakMinutes': 0,
      };
      final m = WageDetailModel.fromMap(raw);
      expect(m.hasBreakBreakdown, isTrue);
      expect(m.effectiveAppliedScheduledBreak, 0);
      expect(m.effectiveAdditionalBreak, 0);
    });
  });

  // 10. copyWith — nullable 필드
  group('[Phase 3.1] copyWith nullable 동작', () {
    test('copyWith에 breakdown 값 전달 → 업데이트', () {
      final base = WageDetailModel.fromMap(_legacyMap());
      expect(base.appliedScheduledBreakMinutes, isNull);

      final updated = base.copyWith(
        appliedScheduledBreakMinutes: 45,
        additionalBreakMinutes: 15,
      );
      expect(updated.appliedScheduledBreakMinutes, 45);
      expect(updated.additionalBreakMinutes, 15);
      expect(updated.hasBreakBreakdown, isTrue);
    });

    test('copyWith(breakdown 미전달) → 기존 값 유지', () {
      final base = WageDetailModel.fromMap(_breakdownMap());
      final updated = base.copyWith(baseAmount: 99999);
      expect(updated.appliedScheduledBreakMinutes, base.appliedScheduledBreakMinutes);
      expect(updated.additionalBreakMinutes, base.additionalBreakMinutes);
    });
  });
}
