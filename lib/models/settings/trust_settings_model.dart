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
  ///
  /// 노쇼 패널티는 TrustScoreHelper 공식(누진: 1회=-5, 2회=-8, 3회+=-10)과 일치시킨다.
  factory TrustSettingsModel.defaults() {
    return TrustSettingsModel(
      startScore: 60,
      maxScore: 100,
      increaseRules: [
        TrustRule(type: 'work_complete', points: 1, description: '근무 완료 (1일)'),
        TrustRule(type: 'good_review',   points: 2, description: '좋은 평가', condition: 4.5),
        TrustRule(type: 'rehire_yes',    points: 1, description: '재고용 희망'),
      ],
      decreaseRules: [
        TrustRule(type: 'late',          points: -1,  description: '지각 (1~2회)'),
        TrustRule(type: 'late_repeat',   points: -2,  description: '지각 (3~5회)'),
        TrustRule(type: 'late_chronic',  points: -3,  description: '지각 (6회+)'),
        TrustRule(type: 'noshow_1',      points: -5,  description: '노쇼 1회'),
        TrustRule(type: 'noshow_2',      points: -8,  description: '노쇼 2회 누진'),
        TrustRule(type: 'noshow_3plus',  points: -10, description: '노쇼 3회+ 누진'),
        TrustRule(type: 'bad_review',    points: -2,  description: '낮은 평가', condition: 2.0),
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
    final raw = doc.data();
    if (raw == null) throw ArgumentError('TrustSettingsModel.fromFirestore: doc.data() is null (id: ${doc.id})');
    return TrustSettingsModel.fromMap(raw as Map<String, dynamic>);
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

  /// 노쇼 누적 횟수별 증분 감점 조회 (1회=-5, 2회=-8, 3회+=-10).
  ///
  /// TrustScoreHelper 공식의 누진 계산과 동일한 값을 반환한다.
  int getNoshowPenalty(int noshowCount) {
    switch (noshowCount) {
      case 1:
        return decreaseRules
            .firstWhere((r) => r.type == 'noshow_1',
                orElse: () => TrustRule(type: '', points: -5, description: ''))
            .points;
      case 2:
        return decreaseRules
            .firstWhere((r) => r.type == 'noshow_2',
                orElse: () => TrustRule(type: '', points: -8, description: ''))
            .points;
      default:
        return decreaseRules
            .firstWhere((r) => r.type == 'noshow_3plus',
                orElse: () => TrustRule(type: '', points: -10, description: ''))
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
    final raw = doc.data();
    if (raw == null) throw ArgumentError('ReviewTagsModel.fromFirestore: doc.data() is null (id: ${doc.id})');
    return ReviewTagsModel.fromMap(raw as Map<String, dynamic>);
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
  trustScore,   // 신뢰도 기반 (레벨 배지)
  attendance,   // 근태 기반
  experience,   // 경험 기반 (총 근무량)
  specialty,    // 업종 전문
}

/// 배지 모델
///
/// [conditionValue] : 주 조건값 (점수·일수·횟수 등 conditionType에 따라 해석).
/// [minWorkDaysRequired] : 추가 최소 근무일수 조건 (null = 없음).
/// [maxNoShowAllowed] : 최대 허용 노쇼 횟수 (null = 무제한).
/// [minRatingRequired] : 최소 평균 평점 조건 (null = 없음).
/// [benefit] : 배지 보유 시 혜택 설명 (앱 내 표시용).
class BadgeModel {
  final String id;
  final String name;
  final String icon;
  final BadgeType type;
  final BadgeConditionType conditionType;
  final int conditionValue;
  final String? workType;            // specialty 배지 업종 코드
  final bool isActive;
  final int order;
  final DateTime createdAt;

  // 복합 조건 (선택적 — null이면 해당 조건 미적용)
  final int? minWorkDaysRequired;    // 추가 최소 근무일수
  final int? maxNoShowAllowed;       // 최대 허용 노쇼 횟수
  final double? minRatingRequired;  // 최소 평균 평점
  final String? benefit;             // 혜택 설명

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
    this.minWorkDaysRequired,
    this.maxNoShowAllowed,
    this.minRatingRequired,
    this.benefit,
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
      createdAt: (map['createdAt'] as Timestamp?)?.toDate().toLocal() ??
          (throw ArgumentError('BadgeModel: createdAt is required')),
      minWorkDaysRequired: map['minWorkDaysRequired'],
      maxNoShowAllowed: map['maxNoShowAllowed'],
      minRatingRequired: (map['minRatingRequired'] as num?)?.toDouble(),
      benefit: map['benefit'],
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
      if (minWorkDaysRequired != null) 'minWorkDaysRequired': minWorkDaysRequired,
      if (maxNoShowAllowed != null)    'maxNoShowAllowed': maxNoShowAllowed,
      if (minRatingRequired != null)   'minRatingRequired': minRatingRequired,
      if (benefit != null)             'benefit': benefit,
    };
  }

  /// 기본 배지 목록 (Firestore 비어 있을 때 초기화용)
  static List<BadgeModel> defaultBadges() {
    final now = DateTime.now();
    return [
      // ── 레벨 배지 (신뢰도 + 복합 조건) ───────────────────────
      BadgeModel(
        id: 'badge_bronze',
        name: '브론즈',
        icon: '🥉',
        type: BadgeType.trustScore,
        conditionType: BadgeConditionType.minScore,
        conditionValue: 60,
        minWorkDaysRequired: 5,
        benefit: '신뢰도 인증 근무자로 관리자 목록에 브론즈 배지 표시 · 성실한 입문자 증명',
        order: 1,
        createdAt: now,
      ),
      BadgeModel(
        id: 'badge_silver',
        name: '실버',
        icon: '🥈',
        type: BadgeType.trustScore,
        conditionType: BadgeConditionType.minScore,
        conditionValue: 70,
        minWorkDaysRequired: 20,
        maxNoShowAllowed: 1,
        benefit: '관리자 지원자 목록 실버 강조 표시 · 신뢰도 검증 근무자로 우선 노출 · 노쇼 이력 1회 이하 인증',
        order: 2,
        createdAt: now,
      ),
      BadgeModel(
        id: 'badge_gold',
        name: '골드',
        icon: '🥇',
        type: BadgeType.trustScore,
        conditionType: BadgeConditionType.minScore,
        conditionValue: 85,
        minWorkDaysRequired: 50,
        maxNoShowAllowed: 0,
        benefit: '골드 강조 표시 · 자동확정 공고 지원 가능 · 노쇼 이력 없음 인증 · 재고용 시 우선 채팅 알림',
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
        minWorkDaysRequired: 100,
        maxNoShowAllowed: 0,
        minRatingRequired: 4.5,
        benefit: '최우선 강조 표시 · 자동확정 공고 우선 배정 · 단골 사업장 빠른 매칭 · 평점 4.5+ 및 노쇼 0 최고 등급 인증',
        order: 4,
        createdAt: now,
      ),

      // ── 경험 배지 (총 근무량) ───────────────────────────────────
      BadgeModel(
        id: 'badge_veteran',
        name: '베테랑',
        icon: '⭐',
        type: BadgeType.experience,
        conditionType: BadgeConditionType.workDays,
        conditionValue: 100,
        benefit: '100일 이상 근무 경력 공식 인증 · 이력서에 경험 배지 표시 · 신뢰할 수 있는 장기 근무자 증명',
        order: 8,
        createdAt: now,
      ),
      BadgeModel(
        id: 'badge_master',
        name: '마스터',
        icon: '👑',
        type: BadgeType.experience,
        conditionType: BadgeConditionType.workDays,
        conditionValue: 200,
        benefit: '200일 장기 근무 최고 경험 배지 · 마스터 전용 강조 표시 · 플랫폼 최우수 근무 경력자 인증',
        order: 9,
        createdAt: now,
      ),

      // ── 근태 배지 ────────────────────────────────────────────────
      BadgeModel(
        id: 'badge_streak',
        name: '연속 출근',
        icon: '🔥',
        type: BadgeType.attendance,
        conditionType: BadgeConditionType.consecutive,
        conditionValue: 15,        // 지각 없이 15회 연속
        benefit: '15회 연속 지각 없는 성실 근태 인증 · 꾸준한 근무 습관 보유자 표시',
        order: 10,
        createdAt: now,
      ),
      BadgeModel(
        id: 'badge_time_master',
        name: '시간의 달인',
        icon: '⏰',
        type: BadgeType.attendance,
        conditionType: BadgeConditionType.consecutive,
        conditionValue: 30,        // 지각 없이 30회 연속
        benefit: '30회 연속 정시 출근 전문가 공식 인증 · 지각 이력 무결 증명 · 관리자 선호 근무자 표시',
        order: 11,
        createdAt: now,
      ),
      BadgeModel(
        id: 'badge_perfect_attendance',
        name: '퍼펙트 출근',
        icon: '🎯',
        type: BadgeType.attendance,
        conditionType: BadgeConditionType.monthlyPerfect,
        conditionValue: 1,         // 한 달 등록 TO 전부 출근
        benefit: '한 달 신청 공고 100% 출근 달성 · 성실 근무자 상징 배지 · 월간 만근 인증',
        order: 12,
        createdAt: now,
      ),

      // ── 업종 전문 배지 ──────────────────────────────────────────
      BadgeModel(
        id: 'badge_picking_expert',
        name: '피킹 전문가',
        icon: '📦',
        type: BadgeType.specialty,
        conditionType: BadgeConditionType.workDays,
        conditionValue: 30,
        workType: 'PICK',
        benefit: '피킹 업무 30일 이상 실력 공식 인증 · 동종 공고 검색 시 우선 표시 · 업무 숙련도 보유자 증명',
        order: 20,
        createdAt: now,
      ),
      BadgeModel(
        id: 'badge_loading_expert',
        name: '상하차 전문가',
        icon: '🏋️',
        type: BadgeType.specialty,
        conditionType: BadgeConditionType.workDays,
        conditionValue: 30,
        workType: 'LOAD',
        benefit: '상하차 업무 30일 이상 실력 공식 인증 · 동종 공고 검색 시 우선 표시 · 체력 및 숙련도 보유자 증명',
        order: 21,
        createdAt: now,
      ),
      BadgeModel(
        id: 'badge_inspection_expert',
        name: '검수 전문가',
        icon: '🔍',
        type: BadgeType.specialty,
        conditionType: BadgeConditionType.workDays,
        conditionValue: 30,
        workType: 'INSPECT',
        benefit: '검수 업무 30일 이상 실력 공식 인증 · 동종 공고 검색 시 우선 표시 · 꼼꼼한 품질 관리 역량 증명',
        order: 22,
        createdAt: now,
      ),
    ];
  }
}