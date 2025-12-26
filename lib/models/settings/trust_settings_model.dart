// lib/models/settings/trust_settings_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// 신뢰도 증감 규칙
class TrustRule {
  final String type;
  final int points;
  final String description;
  final double? condition;  // 예: 평점 4.5 이상

  TrustRule({
    required this.type,
    required this.points,
    required this.description,
    this.condition,
  });

  factory TrustRule.fromMap(Map<String, dynamic> map) {
    return TrustRule(
      type: map['type'] ?? '',
      points: map['points'] ?? 0,
      description: map['description'] ?? '',
      condition: map['condition']?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'points': points,
      'description': description,
      'condition': condition,
    };
  }
}

/// 재시작 프로그램 설정
class RestartProgramSettings {
  final int resetScore;
  final int noshowReduction;
  final int lateReduction;
  final int cooldownDays;

  RestartProgramSettings({
    this.resetScore = 50,
    this.noshowReduction = 1,
    this.lateReduction = 1,
    this.cooldownDays = 60,
  });

  factory RestartProgramSettings.fromMap(Map<String, dynamic> map) {
    return RestartProgramSettings(
      resetScore: map['resetScore'] ?? 50,
      noshowReduction: map['noshowReduction'] ?? 1,
      lateReduction: map['lateReduction'] ?? 1,
      cooldownDays: map['cooldownDays'] ?? 60,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'resetScore': resetScore,
      'noshowReduction': noshowReduction,
      'lateReduction': lateReduction,
      'cooldownDays': cooldownDays,
    };
  }
}

/// 신뢰도 설정 모델
/// Firestore: /settings/trust_rules
class TrustSettingsModel {
  final int startScore;
  final int maxScore;
  final List<TrustRule> increaseRules;
  final List<TrustRule> decreaseRules;
  final RestartProgramSettings restartProgram;

  TrustSettingsModel({
    this.startScore = 50,
    this.maxScore = 100,
    this.increaseRules = const [],
    this.decreaseRules = const [],
    RestartProgramSettings? restartProgram,
  }) : restartProgram = restartProgram ?? RestartProgramSettings();

  /// 기본 설정
  factory TrustSettingsModel.defaults() {
    return TrustSettingsModel(
      startScore: 50,
      maxScore: 100,
      increaseRules: [
        TrustRule(type: 'work_complete', points: 1, description: '근무 완료 (1일)'),
        TrustRule(type: 'good_review', points: 2, description: '좋은 평가', condition: 4.5),
        TrustRule(type: 'rehire_yes', points: 1, description: '재고용 희망'),
      ],
      decreaseRules: [
        TrustRule(type: 'late', points: -1, description: '지각'),
        TrustRule(type: 'noshow_1', points: -3, description: '노쇼 1회'),
        TrustRule(type: 'noshow_2', points: -5, description: '노쇼 2회'),
        TrustRule(type: 'noshow_3', points: -7, description: '노쇼 3회'),
        TrustRule(type: 'noshow_4plus', points: -10, description: '노쇼 4회+'),
        TrustRule(type: 'bad_review', points: -2, description: '낮은 평가', condition: 2.0),
      ],
      restartProgram: RestartProgramSettings(),
    );
  }

  factory TrustSettingsModel.fromMap(Map<String, dynamic> map) {
    return TrustSettingsModel(
      startScore: map['startScore'] ?? 50,
      maxScore: map['maxScore'] ?? 100,
      increaseRules: (map['increaseRules'] as List<dynamic>?)
          ?.map((e) => TrustRule.fromMap(e as Map<String, dynamic>))
          .toList() ?? [],
      decreaseRules: (map['decreaseRules'] as List<dynamic>?)
          ?.map((e) => TrustRule.fromMap(e as Map<String, dynamic>))
          .toList() ?? [],
      restartProgram: map['restartProgram'] != null
          ? RestartProgramSettings.fromMap(map['restartProgram'])
          : RestartProgramSettings(),
    );
  }

  factory TrustSettingsModel.fromFirestore(DocumentSnapshot doc) {
    return TrustSettingsModel.fromMap(doc.data() as Map<String, dynamic>);
  }

  Map<String, dynamic> toMap() {
    return {
      'startScore': startScore,
      'maxScore': maxScore,
      'increaseRules': increaseRules.map((r) => r.toMap()).toList(),
      'decreaseRules': decreaseRules.map((r) => r.toMap()).toList(),
      'restartProgram': restartProgram.toMap(),
    };
  }

  /// 노쇼 횟수별 감점 조회
  int getNoshowPenalty(int noshowCount) {
    switch (noshowCount) {
      case 1:
        return decreaseRules
            .firstWhere((r) => r.type == 'noshow_1', orElse: () => TrustRule(type: '', points: -3, description: ''))
            .points;
      case 2:
        return decreaseRules
            .firstWhere((r) => r.type == 'noshow_2', orElse: () => TrustRule(type: '', points: -5, description: ''))
            .points;
      case 3:
        return decreaseRules
            .firstWhere((r) => r.type == 'noshow_3', orElse: () => TrustRule(type: '', points: -7, description: ''))
            .points;
      default:
        return decreaseRules
            .firstWhere((r) => r.type == 'noshow_4plus', orElse: () => TrustRule(type: '', points: -10, description: ''))
            .points;
    }
  }
}

/// 리뷰 태그 설정 모델
/// Firestore: /settings/review_tags
class ReviewTagsModel {
  /// 지원자 긍정 태그 (관리자 → 지원자)
  final List<String> positiveTags;
  
  /// 지원자 개선 태그 (관리자 → 지원자)
  final List<String> improvementTags;
  
  /// 사업장 긍정 태그 (지원자 → 사업장)
  final List<String> businessPositiveTags;
  
  /// 사업장 개선 태그 (지원자 → 사업장)
  final List<String> businessImprovementTags;

  ReviewTagsModel({
    this.positiveTags = const [],
    this.improvementTags = const [],
    this.businessPositiveTags = const [],
    this.businessImprovementTags = const [],
  });

  /// 기본 태그
  factory ReviewTagsModel.defaults() {
    return ReviewTagsModel(
      positiveTags: [
        '시간 준수',
        '성실함',
        '작업 속도',
        '소통 원활',
        '꼼꼼함',
        '체력 좋음',
        '협조적',
        '빠른 습득',
      ],
      improvementTags: [
        '지각/조퇴',
        '무단 이탈',
        '작업 미숙',
        '소통 부족',
        '태도 불량',
        '집중력',
      ],
      businessPositiveTags: [
        '급여 정확',
        '친절한 관리자',
        '시설 청결',
        '업무 설명 명확',
        '휴게시간 준수',
        '교통 편리',
      ],
      businessImprovementTags: [
        '업무 과중',
        '소통 부족',
        '시설 불편',
        '대기 시간 김',
        '안전 문제',
      ],
    );
  }

  factory ReviewTagsModel.fromMap(Map<String, dynamic> map) {
    return ReviewTagsModel(
      positiveTags: List<String>.from(map['positiveTags'] ?? []),
      improvementTags: List<String>.from(map['improvementTags'] ?? []),
      businessPositiveTags: List<String>.from(map['businessPositiveTags'] ?? []),
      businessImprovementTags: List<String>.from(map['businessImprovementTags'] ?? []),
    );
  }

  factory ReviewTagsModel.fromFirestore(DocumentSnapshot doc) {
    return ReviewTagsModel.fromMap(doc.data() as Map<String, dynamic>);
  }

  Map<String, dynamic> toMap() {
    return {
      'positiveTags': positiveTags,
      'improvementTags': improvementTags,
      'businessPositiveTags': businessPositiveTags,
      'businessImprovementTags': businessImprovementTags,
    };
  }
}

/// 배지 조건 타입
enum BadgeConditionType {
  minScore,     // 최소 신뢰도 점수
  workDays,     // 근무 일수
  consecutive,  // 연속 근무/무지각
  monthlyPerfect, // 월간 100% 출근
}

/// 배지 유형
enum BadgeType {
  trustScore,   // 신뢰도 기반
  attendance,   // 근태 기반
  specialty,    // 업종 전문
}

/// 배지 모델
class BadgeModel {
  final String id;
  final String name;
  final String icon;
  final BadgeType type;
  final BadgeConditionType conditionType;
  final int conditionValue;
  final String? workType;  // specialty 배지인 경우
  final bool isActive;
  final int order;
  final DateTime createdAt;

  BadgeModel({
    required this.id,
    required this.name,
    required this.icon,
    required this.type,
    required this.conditionType,
    required this.conditionValue,
    this.workType,
    this.isActive = true,
    this.order = 0,
    required this.createdAt,
  });

  factory BadgeModel.fromMap(Map<String, dynamic> map, String id) {
    return BadgeModel(
      id: id,
      name: map['name'] ?? '',
      icon: map['icon'] ?? '',
      type: BadgeType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => BadgeType.trustScore,
      ),
      conditionType: BadgeConditionType.values.firstWhere(
        (e) => e.name == map['conditionType'],
        orElse: () => BadgeConditionType.minScore,
      ),
      conditionValue: map['conditionValue'] ?? 0,
      workType: map['workType'],
      isActive: map['isActive'] ?? true,
      order: map['order'] ?? 0,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'icon': icon,
      'type': type.name,
      'conditionType': conditionType.name,
      'conditionValue': conditionValue,
      'workType': workType,
      'isActive': isActive,
      'order': order,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// 기본 배지 목록
  static List<BadgeModel> defaultBadges() {
    final now = DateTime.now();
    return [
      // 신뢰도 배지
      BadgeModel(
        id: 'badge_bronze',
        name: '브론즈',
        icon: '🥉',
        type: BadgeType.trustScore,
        conditionType: BadgeConditionType.minScore,
        conditionValue: 60,
        order: 1,
        createdAt: now,
      ),
      BadgeModel(
        id: 'badge_silver',
        name: '실버',
        icon: '🥈',
        type: BadgeType.trustScore,
        conditionType: BadgeConditionType.minScore,
        conditionValue: 75,
        order: 2,
        createdAt: now,
      ),
      BadgeModel(
        id: 'badge_gold',
        name: '골드',
        icon: '🥇',
        type: BadgeType.trustScore,
        conditionType: BadgeConditionType.minScore,
        conditionValue: 90,
        order: 3,
        createdAt: now,
      ),
      BadgeModel(
        id: 'badge_diamond',
        name: '다이아',
        icon: '💎',
        type: BadgeType.trustScore,
        conditionType: BadgeConditionType.minScore,
        conditionValue: 95,
        order: 4,
        createdAt: now,
      ),
      // 근태 배지
      BadgeModel(
        id: 'badge_time_master',
        name: '시간의 달인',
        icon: '⏰',
        type: BadgeType.attendance,
        conditionType: BadgeConditionType.consecutive,
        conditionValue: 50,
        order: 10,
        createdAt: now,
      ),
      BadgeModel(
        id: 'badge_perfect_attendance',
        name: '퍼펙트 출근',
        icon: '🎯',
        type: BadgeType.attendance,
        conditionType: BadgeConditionType.monthlyPerfect,
        conditionValue: 3,
        order: 11,
        createdAt: now,
      ),
      BadgeModel(
        id: 'badge_streak',
        name: '연속 출근',
        icon: '🔥',
        type: BadgeType.attendance,
        conditionType: BadgeConditionType.consecutive,
        conditionValue: 30,
        order: 12,
        createdAt: now,
      ),
      // 업종 전문 배지
      BadgeModel(
        id: 'badge_picking_expert',
        name: '피킹 전문가',
        icon: '📦',
        type: BadgeType.specialty,
        conditionType: BadgeConditionType.workDays,
        conditionValue: 50,
        workType: 'PICK',
        order: 20,
        createdAt: now,
      ),
      BadgeModel(
        id: 'badge_loading_expert',
        name: '상하차 전문가',
        icon: '🏋️',
        type: BadgeType.specialty,
        conditionType: BadgeConditionType.workDays,
        conditionValue: 50,
        workType: 'LOAD',
        order: 21,
        createdAt: now,
      ),
      BadgeModel(
        id: 'badge_inspection_expert',
        name: '검수 전문가',
        icon: '🔍',
        type: BadgeType.specialty,
        conditionType: BadgeConditionType.workDays,
        conditionValue: 50,
        workType: 'INSPECT',
        order: 22,
        createdAt: now,
      ),
    ];
  }
}