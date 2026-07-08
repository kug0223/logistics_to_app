// test/simulation/super_admin_settings_simulation_test.dart
//
// SUPER_ADMIN 전용 시스템 설정 시뮬레이션 테스트
// 목적: TrustSettingsModel, BadgeModel, InsuranceRateModel, 최저임금,
//       ReviewTagsModel 직렬화 및 비즈니스 로직 검증 (P4/P5)
//
// Firebase 의존 메서드(fromFirestore, BadgeModel.fromMap)는 생략:
//   - BadgeModel.fromMap : createdAt 필드를 Timestamp 로 강제 — 생성자 직접 사용
//   - TrustSettingsModel.fromFirestore : DocumentSnapshot 필요
//   - LegalTerms.fromFirestore : DocumentSnapshot 필요
// 나머지 fromMap / 생성자 / 비즈니스 로직을 집중 검증.
//
// 실행: flutter test test/simulation/super_admin_settings_simulation_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/settings/trust_settings_model.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';
import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:ALfit/utils/wage_calculator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 공통 헬퍼
// ─────────────────────────────────────────────────────────────────────────────

/// 점수 적용 헬퍼 — TrustRule 적용 후 [0, maxScore] clamp
int _applyRule(int currentScore, TrustRule rule, int maxScore) =>
    (currentScore + rule.points).clamp(0, maxScore);

/// 배지 수여 조건 판정 헬퍼 (BadgeModel 에 메서드 없음 → 테스트 내 구현)
bool _wouldAward(
  BadgeModel badge, {
  required int trustScore,
  required int workDays,
  required int noShowCount,
  required double rating,
}) {
  bool mainMet;
  switch (badge.conditionType) {
    case BadgeConditionType.minScore:
      mainMet = trustScore >= badge.conditionValue;
      break;
    case BadgeConditionType.workDays:
    case BadgeConditionType.consecutive:
    case BadgeConditionType.monthlyPerfect:
      mainMet = workDays >= badge.conditionValue;
      break;
  }
  if (!mainMet) return false;
  if (badge.minWorkDaysRequired != null && workDays < badge.minWorkDaysRequired!) return false;
  if (badge.maxNoShowAllowed != null && noShowCount > badge.maxNoShowAllowed!) return false;
  if (badge.minRatingRequired != null && rating < badge.minRatingRequired!) return false;
  return true;
}

/// BadgeModel 생성 헬퍼 (Timestamp 없이 생성자 직접 사용)
BadgeModel _badge({
  String id = 'badge-test',
  String name = '테스트 배지',
  String icon = '⭐',
  BadgeType type = BadgeType.trustScore,
  BadgeConditionType conditionType = BadgeConditionType.minScore,
  int conditionValue = 60,
  String? workType,
  bool isActive = true,
  int order = 0,
  int? minWorkDaysRequired,
  int? maxNoShowAllowed,
  double? minRatingRequired,
  String? benefit,
}) =>
    BadgeModel(
      id: id,
      name: name,
      icon: icon,
      type: type,
      conditionType: conditionType,
      conditionValue: conditionValue,
      workType: workType,
      isActive: isActive,
      order: order,
      createdAt: DateTime(2026, 1, 1),
      minWorkDaysRequired: minWorkDaysRequired,
      maxNoShowAllowed: maxNoShowAllowed,
      minRatingRequired: minRatingRequired,
      benefit: benefit,
    );

// ─────────────────────────────────────────────────────────────────────────────
void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO-SA-01: TrustSettingsModel 직렬화 왕복
  // ═══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SA-01: TrustSettingsModel 직렬화 왕복', () {
    test('SA-01-01: fromMap 빈 맵 → startScore=60, maxScore=100 기본값', () {
      final m = TrustSettingsModel.fromMap({});
      expect(m.startScore, 60);
      expect(m.maxScore, 100);
    });

    test('SA-01-02: fromMap 빈 맵 → increaseRules 빈 리스트', () {
      final m = TrustSettingsModel.fromMap({});
      expect(m.increaseRules, isEmpty);
    });

    test('SA-01-03: fromMap 빈 맵 → decreaseRules 빈 리스트', () {
      final m = TrustSettingsModel.fromMap({});
      expect(m.decreaseRules, isEmpty);
    });

    test('SA-01-04: fromMap 명시 값 → startScore, maxScore 올바르게 파싱', () {
      final m = TrustSettingsModel.fromMap({'startScore': 70, 'maxScore': 120});
      expect(m.startScore, 70);
      expect(m.maxScore, 120);
    });

    test('SA-01-05: fromMap 빈 리스트 → increaseRules/decreaseRules 빈 리스트', () {
      final m = TrustSettingsModel.fromMap({
        'increaseRules': <dynamic>[],
        'decreaseRules': <dynamic>[],
      });
      expect(m.increaseRules, isEmpty);
      expect(m.decreaseRules, isEmpty);
    });

    test('SA-01-06: toMap → fromMap 왕복 후 startScore/maxScore 동일', () {
      final original = TrustSettingsModel(startScore: 55, maxScore: 90);
      final map = original.toMap();
      final restored = TrustSettingsModel.fromMap(map);
      expect(restored.startScore, original.startScore);
      expect(restored.maxScore, original.maxScore);
    });

    test('SA-01-07: toMap → fromMap 왕복 후 increaseRules 개수 동일', () {
      final original = TrustSettingsModel(
        increaseRules: [
          TrustRule(type: 'work_complete', points: 1, description: '근무 완료'),
          TrustRule(type: 'good_review', points: 2, description: '좋은 평가'),
        ],
      );
      final map = original.toMap();
      final restored = TrustSettingsModel.fromMap(map);
      expect(restored.increaseRules.length, 2);
    });

    test('SA-01-08: toMap → fromMap 왕복 후 decreaseRules points 순서 유지', () {
      final original = TrustSettingsModel(
        decreaseRules: [
          TrustRule(type: 'late', points: -1, description: '지각'),
          TrustRule(type: 'noshow_1', points: -5, description: '노쇼'),
        ],
      );
      final map = original.toMap();
      final restored = TrustSettingsModel.fromMap(map);
      expect(restored.decreaseRules[0].points, -1);
      expect(restored.decreaseRules[1].points, -5);
    });

    test('SA-01-09: defaults() → startScore=60, maxScore=100', () {
      final d = TrustSettingsModel.defaults();
      expect(d.startScore, 60);
      expect(d.maxScore, 100);
    });

    test('SA-01-10: defaults() → increaseRules 비어있지 않음', () {
      final d = TrustSettingsModel.defaults();
      expect(d.increaseRules, isNotEmpty);
    });

    test('SA-01-11: defaults() → decreaseRules 비어있지 않음', () {
      final d = TrustSettingsModel.defaults();
      expect(d.decreaseRules, isNotEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO-SA-02: TrustRule 직렬화
  // ═══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SA-02: TrustRule 직렬화', () {
    test('SA-02-01: fromMap 가점 규칙 → type, points, description 올바르게 파싱', () {
      final r = TrustRule.fromMap({
        'type': 'work_complete',
        'points': 1,
        'description': '근무 완료',
      });
      expect(r.type, 'work_complete');
      expect(r.points, 1);
      expect(r.description, '근무 완료');
    });

    test('SA-02-02: fromMap 감점 규칙 → points 음수 파싱', () {
      final r = TrustRule.fromMap({
        'type': 'noshow_1',
        'points': -5,
        'description': '노쇼 1회',
      });
      expect(r.points, -5);
      expect(r.points.isNegative, isTrue);
    });

    test('SA-02-03: fromMap condition 포함 → 파싱 정확', () {
      final r = TrustRule.fromMap({
        'type': 'good_review',
        'points': 2,
        'description': '좋은 평가',
        'condition': 4.5,
      });
      expect(r.condition, 4.5);
    });

    test('SA-02-04: fromMap condition 없음 → null', () {
      final r = TrustRule.fromMap({'type': 'work_complete', 'points': 1, 'description': '근무 완료'});
      expect(r.condition, isNull);
    });

    test('SA-02-05: toMap → fromMap 왕복 일치', () {
      final original = TrustRule(type: 'late', points: -1, description: '지각', condition: null);
      final restored = TrustRule.fromMap(original.toMap());
      expect(restored.type, original.type);
      expect(restored.points, original.points);
      expect(restored.description, original.description);
    });

    test('SA-02-06: tryFromMap null-safe — 빈 맵 → type/points 기본값', () {
      final r = TrustRule.tryFromMap({});
      expect(r, isNotNull);
      expect(r!.type, '');
      expect(r.points, 0);
    });

    test('SA-02-07: 가점(양수)과 감점(음수) 구분 — 부호 유지', () {
      final inc = TrustRule(type: 'inc', points: 3, description: '+3');
      final dec = TrustRule(type: 'dec', points: -3, description: '-3');
      expect(inc.points > 0, isTrue);
      expect(dec.points < 0, isTrue);
    });

    test('SA-02-08: 리스트 순서 유지 — defaults() decreaseRules 첫 번째 = late', () {
      final rules = TrustSettingsModel.defaults().decreaseRules;
      expect(rules.first.type, 'late');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO-SA-03: RestartProgramSettings 직렬화
  // ═══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SA-03: RestartProgramSettings 직렬화', () {
    test('SA-03-01: 기본값 — resetScore=50', () {
      expect(RestartProgramSettings().resetScore, 50);
    });

    test('SA-03-02: 기본값 — noshowReduction=1', () {
      expect(RestartProgramSettings().noshowReduction, 1);
    });

    test('SA-03-03: 기본값 — lateReduction=1', () {
      expect(RestartProgramSettings().lateReduction, 1);
    });

    test('SA-03-04: 기본값 — cooldownDays=60', () {
      expect(RestartProgramSettings().cooldownDays, 60);
    });

    test('SA-03-05: fromMap 값 파싱', () {
      final rp = RestartProgramSettings.fromMap({
        'resetScore': 40,
        'noshowReduction': 2,
        'lateReduction': 1,
        'cooldownDays': 90,
      });
      expect(rp.resetScore, 40);
      expect(rp.noshowReduction, 2);
      expect(rp.cooldownDays, 90);
    });

    test('SA-03-06: fromMap 빈 맵 → 기본값 폴백', () {
      final rp = RestartProgramSettings.fromMap({});
      expect(rp.resetScore, 50);
      expect(rp.cooldownDays, 60);
    });

    test('SA-03-07: toMap → fromMap 왕복 일치', () {
      final original = RestartProgramSettings(
        resetScore: 45,
        noshowReduction: 3,
        lateReduction: 2,
        cooldownDays: 30,
      );
      final restored = RestartProgramSettings.fromMap(original.toMap());
      expect(restored.resetScore, 45);
      expect(restored.noshowReduction, 3);
      expect(restored.lateReduction, 2);
      expect(restored.cooldownDays, 30);
    });

    test('SA-03-08: TrustSettingsModel.defaults() 의 restartProgram 기본값', () {
      final rp = TrustSettingsModel.defaults().restartProgram;
      expect(rp.resetScore, 50);
      expect(rp.cooldownDays, 60);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO-SA-04: TrustSettingsModel 비즈니스 로직
  // ═══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SA-04: TrustSettingsModel 비즈니스 로직', () {
    late TrustSettingsModel settings;
    setUpAll(() => settings = TrustSettingsModel.defaults());

    test('SA-04-01: getNoshowPenalty(1) → -5', () {
      expect(settings.getNoshowPenalty(1), -5);
    });

    test('SA-04-02: getNoshowPenalty(2) → -8 (누진)', () {
      expect(settings.getNoshowPenalty(2), -8);
    });

    test('SA-04-03: getNoshowPenalty(3) → -10 (3회+ 누진)', () {
      expect(settings.getNoshowPenalty(3), -10);
    });

    test('SA-04-04: getNoshowPenalty(10) → -10 (3회+ 동일)', () {
      expect(settings.getNoshowPenalty(10), -10);
    });

    test('SA-04-05: 노쇼 패널티 누진 — 1회 < 2회 < 3회+ 절댓값', () {
      final p1 = settings.getNoshowPenalty(1).abs();
      final p2 = settings.getNoshowPenalty(2).abs();
      final p3 = settings.getNoshowPenalty(3).abs();
      expect(p1 < p2, isTrue);
      expect(p2 < p3, isTrue);
    });

    test('SA-04-06: 가점 적용 후 maxScore clamp — 95점에서 +2 → 97 (100 이하)', () {
      final rule = settings.increaseRules.firstWhere((r) => r.type == 'good_review');
      final result = _applyRule(95, rule, settings.maxScore);
      expect(result, lessThanOrEqualTo(settings.maxScore));
      expect(result, 97);
    });

    test('SA-04-07: 가점 적용 maxScore 초과 방지 — 99점에서 +2 → 100', () {
      final rule = TrustRule(type: 'inc', points: 2, description: '+2');
      final result = _applyRule(99, rule, 100);
      expect(result, 100);
    });

    test('SA-04-08: 감점 적용 후 0 clamp — 2점에서 -5 → 0', () {
      final rule = TrustRule(type: 'noshow_1', points: -5, description: '노쇼');
      final result = _applyRule(2, rule, 100);
      expect(result, 0);
    });

    test('SA-04-09: startScore == maxScore 설정 생성 가능 (경고 조건)', () {
      final m = TrustSettingsModel(startScore: 100, maxScore: 100);
      expect(m.startScore, m.maxScore);
    });

    test('SA-04-10: startScore > maxScore 설정 생성 가능 (유효성 검사는 UI 레이어)', () {
      final m = TrustSettingsModel(startScore: 110, maxScore: 100);
      expect(m.startScore > m.maxScore, isTrue);
    });

    test('SA-04-11: 룰 없는 settings → getNoshowPenalty 기본값 반환', () {
      final empty = TrustSettingsModel(decreaseRules: []);
      expect(empty.getNoshowPenalty(1), -5);  // orElse 기본값
      expect(empty.getNoshowPenalty(2), -8);
      expect(empty.getNoshowPenalty(3), -10);
    });

    test('SA-04-12: 커스텀 noshow_1 패널티 → getNoshowPenalty 반영', () {
      final custom = TrustSettingsModel(
        decreaseRules: [
          TrustRule(type: 'noshow_1', points: -3, description: '커스텀 노쇼'),
        ],
      );
      expect(custom.getNoshowPenalty(1), -3);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO-SA-05: ReviewTagsModel 직렬화
  // ═══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SA-05: ReviewTagsModel 직렬화', () {
    test('SA-05-01: 빈 맵 → 모든 리스트 빈 리스트', () {
      final m = ReviewTagsModel.fromMap({});
      expect(m.positiveTags, isEmpty);
      expect(m.improvementTags, isEmpty);
      expect(m.businessPositiveTags, isEmpty);
      expect(m.businessImprovementTags, isEmpty);
    });

    test('SA-05-02: positiveTags 파싱', () {
      final m = ReviewTagsModel.fromMap({
        'positiveTags': ['시간 준수', '성실함'],
      });
      expect(m.positiveTags, ['시간 준수', '성실함']);
    });

    test('SA-05-03: businessImprovementTags 파싱', () {
      final m = ReviewTagsModel.fromMap({
        'businessImprovementTags': ['업무 과중', '소통 부족'],
      });
      expect(m.businessImprovementTags.length, 2);
    });

    test('SA-05-04: toMap → fromMap 왕복 — positiveTags 일치', () {
      final original = ReviewTagsModel(positiveTags: ['태그1', '태그2']);
      final restored = ReviewTagsModel.fromMap(original.toMap());
      expect(restored.positiveTags, ['태그1', '태그2']);
    });

    test('SA-05-05: toMap 키 확인 — 4종 키 모두 포함', () {
      final m = ReviewTagsModel();
      final map = m.toMap();
      expect(map.containsKey('positiveTags'), isTrue);
      expect(map.containsKey('improvementTags'), isTrue);
      expect(map.containsKey('businessPositiveTags'), isTrue);
      expect(map.containsKey('businessImprovementTags'), isTrue);
    });

    test('SA-05-06: defaults() — positiveTags 8개', () {
      final d = ReviewTagsModel.defaults();
      expect(d.positiveTags.length, 8);
    });

    test('SA-05-07: defaults() — improvementTags 6개', () {
      final d = ReviewTagsModel.defaults();
      expect(d.improvementTags.length, 6);
    });

    test('SA-05-08: defaults() — businessPositiveTags 6개', () {
      final d = ReviewTagsModel.defaults();
      expect(d.businessPositiveTags.length, 6);
    });

    test('SA-05-09: defaults() — businessImprovementTags 5개', () {
      final d = ReviewTagsModel.defaults();
      expect(d.businessImprovementTags.length, 5);
    });

    test('SA-05-10: defaults() — positiveTags에 "시간 준수" 포함', () {
      final d = ReviewTagsModel.defaults();
      expect(d.positiveTags, contains('시간 준수'));
    });

    test('SA-05-11: defaults() — businessImprovementTags에 "안전 문제" 포함', () {
      final d = ReviewTagsModel.defaults();
      expect(d.businessImprovementTags, contains('안전 문제'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO-SA-06: BadgeModel 구조 및 defaultBadges
  // ═══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SA-06: BadgeModel 구조 및 defaultBadges', () {
    test('SA-06-01: BadgeType 4종 존재', () {
      expect(BadgeType.values.length, 4);
      expect(BadgeType.values, containsAll([
        BadgeType.trustScore,
        BadgeType.attendance,
        BadgeType.experience,
        BadgeType.specialty,
      ]));
    });

    test('SA-06-02: BadgeConditionType 4종 존재', () {
      expect(BadgeConditionType.values.length, 4);
      expect(BadgeConditionType.values, containsAll([
        BadgeConditionType.minScore,
        BadgeConditionType.workDays,
        BadgeConditionType.consecutive,
        BadgeConditionType.monthlyPerfect,
      ]));
    });

    test('SA-06-03: BadgeModel 생성자 — 필드 정확', () {
      final b = _badge(
        id: 'badge_bronze',
        name: '브론즈',
        conditionType: BadgeConditionType.minScore,
        conditionValue: 60,
        minWorkDaysRequired: 5,
      );
      expect(b.id, 'badge_bronze');
      expect(b.conditionValue, 60);
      expect(b.minWorkDaysRequired, 5);
    });

    test('SA-06-04: conditionValue=0 허용 (경계값)', () {
      final b = _badge(conditionValue: 0);
      expect(b.conditionValue, 0);
    });

    test('SA-06-05: maxNoShowAllowed=0 허용 (노쇼 0회 제한)', () {
      final b = _badge(maxNoShowAllowed: 0);
      expect(b.maxNoShowAllowed, 0);
    });

    test('SA-06-06: defaultBadges() — 비어있지 않음', () {
      expect(BadgeModel.defaultBadges(), isNotEmpty);
    });

    test('SA-06-07: defaultBadges() — badge_bronze 포함', () {
      final ids = BadgeModel.defaultBadges().map((b) => b.id).toList();
      expect(ids, contains('badge_bronze'));
    });

    test('SA-06-08: defaultBadges() — badge_diamond conditionValue=95', () {
      final diamond = BadgeModel.defaultBadges()
          .firstWhere((b) => b.id == 'badge_diamond');
      expect(diamond.conditionValue, 95);
    });

    test('SA-06-09: defaultBadges() — badge_diamond minRatingRequired=4.5', () {
      final diamond = BadgeModel.defaultBadges()
          .firstWhere((b) => b.id == 'badge_diamond');
      expect(diamond.minRatingRequired, 4.5);
    });

    test('SA-06-10: defaultBadges() — badge_gold maxNoShowAllowed=0', () {
      final gold = BadgeModel.defaultBadges()
          .firstWhere((b) => b.id == 'badge_gold');
      expect(gold.maxNoShowAllowed, 0);
    });

    test('SA-06-11: defaultBadges() — specialty 배지 workType 있음', () {
      final specialty = BadgeModel.defaultBadges()
          .where((b) => b.type == BadgeType.specialty)
          .toList();
      expect(specialty, isNotEmpty);
      expect(specialty.every((b) => b.workType != null), isTrue);
    });

    test('SA-06-12: defaultBadges() — 모든 배지 isActive=true', () {
      final badges = BadgeModel.defaultBadges();
      expect(badges.every((b) => b.isActive), isTrue);
    });

    test('SA-06-13: defaultBadges() — order 오름차순 (레벨 배지 1~4)', () {
      final level = BadgeModel.defaultBadges()
          .where((b) => b.type == BadgeType.trustScore)
          .toList();
      final orders = level.map((b) => b.order).toList();
      final sorted = [...orders]..sort();
      expect(orders, sorted);
    });

    test('SA-06-14: specialty 배지 workType 코드 — PICK/LOAD/INSPECT', () {
      final workTypes = BadgeModel.defaultBadges()
          .where((b) => b.type == BadgeType.specialty)
          .map((b) => b.workType)
          .toList();
      expect(workTypes, containsAll(['PICK', 'LOAD', 'INSPECT']));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO-SA-07: BadgeModel 수여 조건 로직
  // ═══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SA-07: BadgeModel 수여 조건 로직', () {
    test('SA-07-01: conditionType=minScore, conditionValue=60 — 점수 60 → 수여', () {
      final b = _badge(conditionType: BadgeConditionType.minScore, conditionValue: 60);
      expect(_wouldAward(b, trustScore: 60, workDays: 0, noShowCount: 0, rating: 0.0), isTrue);
    });

    test('SA-07-02: conditionType=minScore — 점수 59 → 미수여', () {
      final b = _badge(conditionType: BadgeConditionType.minScore, conditionValue: 60);
      expect(_wouldAward(b, trustScore: 59, workDays: 0, noShowCount: 0, rating: 0.0), isFalse);
    });

    test('SA-07-03: conditionType=workDays — workDays=100 이상 → 수여', () {
      final b = _badge(conditionType: BadgeConditionType.workDays, conditionValue: 100);
      expect(_wouldAward(b, trustScore: 0, workDays: 100, noShowCount: 0, rating: 0.0), isTrue);
    });

    test('SA-07-04: conditionType=workDays — workDays=99 → 미수여', () {
      final b = _badge(conditionType: BadgeConditionType.workDays, conditionValue: 100);
      expect(_wouldAward(b, trustScore: 0, workDays: 99, noShowCount: 0, rating: 0.0), isFalse);
    });

    test('SA-07-05: conditionValue=0 → 항상 수여 (경계값)', () {
      final b = _badge(conditionType: BadgeConditionType.minScore, conditionValue: 0);
      expect(_wouldAward(b, trustScore: 0, workDays: 0, noShowCount: 0, rating: 0.0), isTrue);
    });

    test('SA-07-06: 복합 조건 — minScore + minWorkDays 모두 충족 → 수여', () {
      final b = _badge(
        conditionType: BadgeConditionType.minScore,
        conditionValue: 70,
        minWorkDaysRequired: 20,
      );
      expect(_wouldAward(b, trustScore: 75, workDays: 25, noShowCount: 0, rating: 0.0), isTrue);
    });

    test('SA-07-07: 복합 조건 — minScore 충족, minWorkDays 미충족 → 미수여', () {
      final b = _badge(
        conditionType: BadgeConditionType.minScore,
        conditionValue: 70,
        minWorkDaysRequired: 20,
      );
      expect(_wouldAward(b, trustScore: 75, workDays: 15, noShowCount: 0, rating: 0.0), isFalse);
    });

    test('SA-07-08: 복합 조건 — maxNoShowAllowed=0, noShow=1 → 미수여', () {
      final b = _badge(
        conditionType: BadgeConditionType.minScore,
        conditionValue: 85,
        maxNoShowAllowed: 0,
      );
      expect(_wouldAward(b, trustScore: 90, workDays: 50, noShowCount: 1, rating: 0.0), isFalse);
    });

    test('SA-07-09: 복합 조건 — maxNoShowAllowed=0, noShow=0 → 수여', () {
      final b = _badge(
        conditionType: BadgeConditionType.minScore,
        conditionValue: 85,
        maxNoShowAllowed: 0,
      );
      expect(_wouldAward(b, trustScore: 90, workDays: 50, noShowCount: 0, rating: 0.0), isTrue);
    });

    test('SA-07-10: 복합 조건 — minRatingRequired=4.5, rating=4.4 → 미수여', () {
      final b = _badge(
        conditionType: BadgeConditionType.minScore,
        conditionValue: 95,
        minWorkDaysRequired: 100,
        maxNoShowAllowed: 0,
        minRatingRequired: 4.5,
      );
      expect(_wouldAward(b, trustScore: 98, workDays: 120, noShowCount: 0, rating: 4.4), isFalse);
    });

    test('SA-07-11: 복합 조건 — 모두 충족 → 수여 (다이아 조건)', () {
      final b = _badge(
        conditionType: BadgeConditionType.minScore,
        conditionValue: 95,
        minWorkDaysRequired: 100,
        maxNoShowAllowed: 0,
        minRatingRequired: 4.5,
      );
      expect(_wouldAward(b, trustScore: 98, workDays: 120, noShowCount: 0, rating: 4.7), isTrue);
    });

    test('SA-07-12: defaultBadges() 브론즈 실제 조건 검증 — score=60, days=5 → 수여', () {
      final bronze = BadgeModel.defaultBadges().firstWhere((b) => b.id == 'badge_bronze');
      expect(
        _wouldAward(bronze, trustScore: 60, workDays: 5, noShowCount: 0, rating: 0.0),
        isTrue,
      );
    });

    test('SA-07-13: defaultBadges() 실버 — score=70, days=20, noShow=1 → 수여', () {
      final silver = BadgeModel.defaultBadges().firstWhere((b) => b.id == 'badge_silver');
      expect(
        _wouldAward(silver, trustScore: 70, workDays: 20, noShowCount: 1, rating: 0.0),
        isTrue,
      );
    });

    test('SA-07-14: defaultBadges() 실버 — noShow=2 → 미수여 (최대 1회 허용)', () {
      final silver = BadgeModel.defaultBadges().firstWhere((b) => b.id == 'badge_silver');
      expect(
        _wouldAward(silver, trustScore: 80, workDays: 30, noShowCount: 2, rating: 0.0),
        isFalse,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO-SA-08: InsuranceRateModel 연도별 관리 (단위 테스트와 중복 최소화)
  // ═══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SA-08: InsuranceRateModel 연도별 관리', () {
    test('SA-08-01: toMap에 year 필드 포함', () {
      final m = InsuranceRateModel.defaults2026();
      expect(m.toMap().containsKey('year'), isTrue);
      expect(m.toMap()['year'], 2026);
    });

    test('SA-08-02: 복수 레코드 — 연도별 리스트 관리 가능', () {
      final rates = [
        InsuranceRateModel.fromMap({'year': 2024, 'nationalPensionRate': 4.5}),
        InsuranceRateModel.fromMap({'year': 2025, 'nationalPensionRate': 4.5}),
        InsuranceRateModel.defaults2026(),
      ];
      expect(rates.length, 3);
      expect(rates.map((r) => r.year).toList(), containsAll([2024, 2025, 2026]));
    });

    test('SA-08-03: 최신 연도 우선 조회 — 2026이 가장 큰 연도', () {
      final rates = [
        InsuranceRateModel.fromMap({'year': 2024}),
        InsuranceRateModel.fromMap({'year': 2025}),
        InsuranceRateModel.defaults2026(),
      ];
      final latest = rates.reduce((a, b) => a.year > b.year ? a : b);
      expect(latest.year, 2026);
    });

    test('SA-08-04: 2026년 건강보험 3.595% — 2025년 3.545%와 다름', () {
      final r2025 = InsuranceRateModel.fromMap({'year': 2025, 'healthInsuranceRate': 3.545});
      final r2026 = InsuranceRateModel.defaults2026();
      expect(r2026.healthInsuranceRate, isNot(r2025.healthInsuranceRate));
      expect(r2026.healthInsuranceRate, greaterThan(r2025.healthInsuranceRate));
    });

    test('SA-08-05: fromMap 연도 누락 → 2026 기본값', () {
      final m = InsuranceRateModel.fromMap({});
      expect(m.year, 2026);
    });

    test('SA-08-06: copyWith 연도 변경 후 다른 필드 유지', () {
      final base = InsuranceRateModel.defaults2026();
      final next = base.copyWith(year: 2027);
      expect(next.year, 2027);
      expect(next.nationalPensionRate, base.nationalPensionRate);
      expect(next.healthInsuranceRate, base.healthInsuranceRate);
    });

    test('SA-08-07: 공제 타입 5종 상수 all distinct', () {
      final types = InsuranceRateModel.allTypes;
      expect(types.toSet().length, types.length); // 중복 없음
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO-SA-09: WageCalculator 최저임금 상수 및 폴백 로직
  // ═══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SA-09: WageCalculator 최저임금 상수 및 폴백', () {
    test('SA-09-01: 2024년 최저시급 = 9,860원', () {
      expect(WageCalculator.getMinimumWage(2024), 9860);
    });

    test('SA-09-02: 2025년 최저시급 = 10,030원', () {
      expect(WageCalculator.getMinimumWage(2025), 10030);
    });

    test('SA-09-03: 2026년 최저시급 = 10,320원', () {
      expect(WageCalculator.getMinimumWage(2026), 10320);
    });

    test('SA-09-04: 연도별 인상 추세 — 2024 < 2025 < 2026', () {
      expect(WageCalculator.getMinimumWage(2024), lessThan(WageCalculator.getMinimumWage(2025)));
      expect(WageCalculator.getMinimumWage(2025), lessThan(WageCalculator.getMinimumWage(2026)));
    });

    test('SA-09-05: 알 수 없는 연도(9999) → 최신 연도(2026) 폴백', () {
      // 로컬 백업 맵에 없는 연도 → 가장 최근 연도 값 반환
      final fallback = WageCalculator.getMinimumWage(9999);
      expect(fallback, WageCalculator.getMinimumWage(2026));
    });

    test('SA-09-06: 과거 연도(2020) = 8,590원', () {
      expect(WageCalculator.getMinimumWage(2020), 8590);
    });

    test('SA-09-07: 최저시급은 모두 양수', () {
      for (final year in [2020, 2021, 2022, 2023, 2024, 2025, 2026]) {
        expect(WageCalculator.getMinimumWage(year), greaterThan(0));
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO-SA-10: LegalTermsItem.fromMap (Timestamp 미사용 필드만 검증)
  // ═══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SA-10: LegalTermsItem.fromMap (Timestamp 미사용)', () {
    test('SA-10-01: fromMap 기본 필드 파싱', () {
      final item = LegalTermsItem.fromMap({
        'id': 'service_terms',
        'title': '서비스 이용약관',
        'content': '내용',
        'isRequired': true,
        'isActive': true,
        'version': '2025.01',
        'order': 1,
      });
      expect(item.id, 'service_terms');
      expect(item.title, '서비스 이용약관');
      expect(item.isRequired, isTrue);
      expect(item.version, '2025.01');
      expect(item.order, 1);
    });

    test('SA-10-02: fromMap updatedAt 누락 → updatedAt = null (Timestamp 생략)', () {
      final item = LegalTermsItem.fromMap({
        'id': 'test',
        'title': '테스트',
        'content': '내용',
        'isRequired': false,
      });
      expect(item.updatedAt, isNull);
    });

    test('SA-10-03: fromMap isRequired=false → 선택 동의', () {
      final item = LegalTermsItem.fromMap({
        'id': 'marketing',
        'title': '마케팅',
        'content': '내용',
        'isRequired': false,
      });
      expect(item.isRequired, isFalse);
    });

    test('SA-10-04: fromMap 빈 맵 → 기본값 적용', () {
      final item = LegalTermsItem.fromMap({});
      expect(item.id, '');
      expect(item.isRequired, isTrue);   // 기본값 true
      expect(item.isActive, isTrue);      // 기본값 true
      expect(item.version, '1.0');        // 기본값
      expect(item.order, 0);             // 기본값
    });

    test('SA-10-05: toMap → fromMap 왕복 (updatedAt 제외)', () {
      final original = LegalTermsItem(
        id: 'privacy_policy',
        title: '개인정보 처리방침',
        content: '처리방침 내용',
        isRequired: true,
        version: '2025.01',
        order: 2,
      );
      final map = original.toMap();
      // updatedAt=null이면 map에 null로 들어가므로 fromMap에서 null 처리
      final restored = LegalTermsItem.fromMap(map);
      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.version, original.version);
      expect(restored.order, original.order);
    });

    test('SA-10-06: LegalTerms.defaultTerms() 5개 약관 항목', () {
      final terms = LegalTerms.defaultTerms();
      expect(terms.items.length, 5);
    });

    test('SA-10-07: LegalTerms.defaultTerms() 마케팅 동의는 isRequired=false', () {
      final terms = LegalTerms.defaultTerms();
      final marketing = terms.items.firstWhere((t) => t.id == 'marketing_consent');
      expect(marketing.isRequired, isFalse);
    });

    test('SA-10-08: LegalTerms.defaultTerms() 나머지 4개는 isRequired=true', () {
      final terms = LegalTerms.defaultTerms();
      final required = terms.items.where((t) => t.id != 'marketing_consent').toList();
      expect(required.every((t) => t.isRequired), isTrue);
    });

    test('SA-10-09: LegalTerms.activeItems order 정렬 검증', () {
      final terms = LegalTerms.defaultTerms();
      final orders = terms.activeItems.map((t) => t.order).toList();
      expect(orders, equals([1, 2, 3, 4, 5]));
    });

    test('SA-10-10: LegalTermsItem.copyWith — version 업데이트', () {
      final original = LegalTermsItem(
        id: 'service_terms',
        title: '서비스 이용약관',
        content: '내용',
        isRequired: true,
        version: '2025.01',
      );
      final updated = original.copyWith(version: '2026.01');
      expect(updated.version, '2026.01');
      expect(updated.id, original.id); // id 불변
    });
  });
}
