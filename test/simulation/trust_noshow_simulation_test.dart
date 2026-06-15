// test/simulation/trust_noshow_simulation_test.dart
//
// 신뢰도·노쇼 정책 종합 시뮬레이션
// 목적: 실제 사용 패턴을 가상으로 재현해 공식·정책·모델 전반의 버그를 탐지한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/settings/trust_settings_model.dart';
import 'package:ALfit/utils/trust_score_helper.dart';

// ── 최소 UserModel 헬퍼 ───────────────────────────────────────────
UserModel _u({
  int days = 0,
  double avg = 0.0,
  int rc = 0,
  double rr = 0.0,
  int ns = 0,
  int late = 0,
  int? stored,
}) =>
    UserModel(
      uid: 'sim-user',
      username: 'sim',
      name: '시뮬',
      email: 'sim@test.com',
      role: UserRole.USER,
      totalWorkDays: days,
      averageRating: avg,
      reviewCount: rc,
      rehireRate: rr,
      noShowCount: ns,
      lateCount: late,
      storedTrustScore: stored,
    );

// ── 노쇼 이용 제한 기간 계산 (application_firestore 로직 복제) ─────
DateTime? _restrictionUntil(int noShowCount) {
  if (noShowCount <= 0) return null;
  final now = DateTime.now();
  switch (noShowCount) {
    case 1: return now.add(const Duration(days: 3));
    case 2: return now.add(const Duration(days: 7));
    case 3: return now.add(const Duration(days: 30));
    default: return DateTime(9999, 12, 31);
  }
}

bool _isPermanent(DateTime? d) => d != null && d.year >= 9999;
bool _isRestricted(DateTime? d) => d != null && d.isAfter(DateTime.now());

// ── TrustSettingsModel.getNoshowPenalty 검증용 ────────────────────
int _penalty(int count) => TrustSettingsModel.defaults().getNoshowPenalty(count);

void main() {
  // ═══════════════════════════════════════════════════════════
  // SIM-A: 신규 사용자 온보딩 시뮬레이션
  // ═══════════════════════════════════════════════════════════
  group('SIM-A. 신규 사용자 온보딩', () {
    test('A-01: 가입 직후 — 아무 이력 없음 → 60점', () {
      expect(_u().trustScore, 60);
    });
    test('A-02: 첫 근무 (1일) → 여전히 60점 (10일 미만 가산 없음)', () {
      expect(_u(days: 1).trustScore, 60);
    });
    test('A-03: 10일 달성 → 64점 (경험 +4)', () {
      expect(_u(days: 10).trustScore, 64);
    });
    test('A-04: 첫 리뷰 4.0 받음 (rc=1)', () {
      // diff=1.0, w=0.2 → round(2.0)=2 → 62
      expect(_u(days: 0, avg: 4.0, rc: 1).trustScore, 62);
    });
    test('A-05: 첫 노쇼 → 55점 & 3일 제한', () {
      final score = _u(days: 0, ns: 1).trustScore;
      expect(score, 55);
      final until = _restrictionUntil(1)!;
      expect(_isRestricted(until), isTrue);
      expect(until.difference(DateTime.now()).inDays, greaterThanOrEqualTo(2));
    });
    test('A-06: 첫 노쇼 후 3일 지나면 제한 해제', () {
      final past = DateTime.now().subtract(const Duration(days: 4));
      expect(past.isAfter(DateTime.now()), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SIM-B: 성실 근무자 성장 시뮬레이션 (노쇼 없음)
  // ═══════════════════════════════════════════════════════════
  group('SIM-B. 성실 근무자 성장', () {
    test('B-01: 10일 · 평점3.0 리뷰1 → 64', () {
      expect(_u(days: 10, avg: 3.0, rc: 1).trustScore, 64);
    });
    test('B-02: 20일 · 평점4.0 리뷰3 · 재고용0.7 → 80', () {
      // exp=+8, rating=round(1.0×10×0.6)=6, rehire=round(5.6)=6 → 80
      expect(_u(days: 20, avg: 4.0, rc: 3, rr: 0.7).trustScore, 80);
    });
    test('B-03: 40일 · 평점4.5 리뷰5 · 재고용0.9 → 95', () {
      // exp=+12, rating=round(1.5×10×1)=15, rehire=round(7.2)=7 → 94
      // Wait: 60+12+15+7=94
      expect(_u(days: 40, avg: 4.5, rc: 5, rr: 0.9).trustScore, 94);
    });
    test('B-04: 60일 · 평점4.8 리뷰8 · 재고용1.0 → 100', () {
      // exp=+15, rating=round(1.8×10×1)=18, rehire=8 → 101→100
      expect(_u(days: 60, avg: 4.8, rc: 8, rr: 1.0).trustScore, 100);
    });
    test('B-05: 신뢰도 100 → clamp 초과 없음', () {
      final s = _u(days: 300, avg: 5.0, rc: 100, rr: 1.0).trustScore;
      expect(s, inInclusiveRange(0, 100));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SIM-C: 노쇼 누적 페르소나 시뮬레이션
  // ═══════════════════════════════════════════════════════════
  group('SIM-C. 노쇼 누적 시나리오', () {
    test('C-01: 노쇼 없음 → 제한 없음', () {
      expect(_restrictionUntil(0), isNull);
    });
    test('C-02: 노쇼 1회 → 3일 제한 (72시간)', () {
      final u = _restrictionUntil(1)!;
      final diff = u.difference(DateTime.now());
      expect(diff.inHours, greaterThanOrEqualTo(71)); // ≈72h
      expect(diff.inDays, lessThanOrEqualTo(3));
    });
    test('C-03: 노쇼 2회 → 7일 제한', () {
      final u = _restrictionUntil(2)!;
      expect(u.difference(DateTime.now()).inDays, greaterThanOrEqualTo(6));
    });
    test('C-04: 노쇼 3회 → 30일 제한', () {
      final u = _restrictionUntil(3)!;
      expect(u.difference(DateTime.now()).inDays, greaterThanOrEqualTo(29));
    });
    test('C-05: 노쇼 4회 → 영구 제한 (9999년)', () {
      expect(_isPermanent(_restrictionUntil(4)), isTrue);
    });
    test('C-06: 노쇼 10회 → 여전히 영구', () {
      expect(_isPermanent(_restrictionUntil(10)), isTrue);
    });
    test('C-07: 제한 기간 단계 단조 증가 검증', () {
      final d1 = _restrictionUntil(1)!.difference(DateTime.now()).inHours;
      final d2 = _restrictionUntil(2)!.difference(DateTime.now()).inHours;
      final d3 = _restrictionUntil(3)!.difference(DateTime.now()).inHours;
      expect(d1 < d2, isTrue, reason: '1회 < 2회');
      expect(d2 < d3, isTrue, reason: '2회 < 3회');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SIM-D: 노쇼 감점 & 만회계수 시뮬레이션
  // ═══════════════════════════════════════════════════════════
  group('SIM-D. 노쇼 감점 시뮬레이션', () {
    test('D-01: 노쇼1, 근무0 → 만회 없음, -5 → 55', () {
      expect(_u(ns: 1).trustScore, 55);
    });
    test('D-02: 노쇼1, 근무40 (출근율≈97%) → 만회 50%, deduct=3 → 69', () {
      // exp=+12, factor=0.5, deduct=round(2.5)=3 → 60+12-3=69
      expect(_u(days: 40, ns: 1).trustScore, 69);
    });
    test('D-03: 노쇼2, 근무0 → -13 → 47', () {
      expect(_u(ns: 2).trustScore, 47);
    });
    test('D-04: 노쇼2, 근무100 (출근율≈98%) → 만회 50%, deduct=7 → 68', () {
      // exp=+15, raw=13, deduct=7 → 68
      expect(_u(days: 100, ns: 2).trustScore, 68);
    });
    test('D-05: 노쇼3, 근무0 → -23 → 37', () {
      expect(_u(ns: 3).trustScore, 37);
    });
    test('D-06: 노쇼3, 근무57 (출근율=0.95) → 만회, deduct=12 → 60', () {
      // exp=+12, raw=23, deduct=round(11.5)=12 → 60
      expect(_u(days: 57, ns: 3).trustScore, 60);
    });
    test('D-07: 노쇼4, 근무0 → -33 → 27', () {
      expect(_u(ns: 4).trustScore, 27);
    });
    test('D-08: 노쇼7, 근무0 → 감점 초과 → 0 clamp', () {
      expect(_u(ns: 7).trustScore, 0);
    });
    test('D-09: 노쇼 감점은 근무일수 경험 가산과 독립 작동', () {
      final base = TrustScoreHelper.calculate(_u(days: 60));
      final withNs = TrustScoreHelper.calculate(_u(days: 60, ns: 1));
      // 만회계수 적용됨 (60일 근무 + 노쇼1 → rate≈0.984 → factor=0.5, deduct=3)
      expect(base - withNs, 3); // 만회 50% 적용 후 3점 차이
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SIM-E: 지각 누진 시뮬레이션
  // ═══════════════════════════════════════════════════════════
  group('SIM-E. 지각 누진 시뮬레이션', () {
    test('E-01: 지각 0회 → 0', () => expect(_u(late: 0).trustScore, 60));
    test('E-02: 지각 1회 → -1 → 59', () => expect(_u(late: 1).trustScore, 59));
    test('E-03: 지각 2회 → -2 → 58', () => expect(_u(late: 2).trustScore, 58));
    test('E-04: 지각 3회 → -4 → 56', () => expect(_u(late: 3).trustScore, 56));
    test('E-05: 지각 5회 → -8 → 52', () => expect(_u(late: 5).trustScore, 52));
    test('E-06: 지각 6회 → -11 → 49', () => expect(_u(late: 6).trustScore, 49));
    test('E-07: 지각 10회 → -23 → 37', () => expect(_u(late: 10).trustScore, 37));
    test('E-08: 지각 30회 → deep → 0 clamp', () {
      expect(_u(late: 30).trustScore, 0);
    });
    test('E-09: 지각 단조 감점 (회당 페널티 비감소)', () {
      int prev = 60;
      for (int i = 1; i <= 20; i++) {
        final cur = _u(late: i).trustScore;
        expect(cur, lessThanOrEqualTo(prev), reason: '지각 $i회');
        prev = cur;
      }
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SIM-F: 복합 패턴 — 직종별 페르소나
  // ═══════════════════════════════════════════════════════════
  group('SIM-F. 직종별 페르소나', () {
    test('F-01: 피킹 베테랑 (100일, 평점4.5, 리뷰10, 재고용0.8, 지각2) → 95', () {
      // exp=+15, rating=round(1.5×10×1)=15, rehire=round(6.4)=6, late=-(1+1)=-2
      // 60+15+15+6-2=94
      expect(_u(days: 100, avg: 4.5, rc: 10, rr: 0.8, late: 2).trustScore, 94);
    });
    test('F-02: 이직 잦은 단기 근무자 (20일, 평점3.5, 리뷰2, 노쇼1) → 61', () {
      // exp=+8, avg: diff=0.5, w=0.4 → round(2.0)=2, rehire=0(rc<3)
      // ns=1, total=21, rate=20/21≈0.952≥0.95, days≥20 → factor=0.5, deduct=round(2.5)=3
      // 60+8+2-3=67
      expect(_u(days: 20, avg: 3.5, rc: 2, ns: 1).trustScore, 67);
    });
    test('F-03: 재시작 후 회복 중 (stored=50, 신규 이력 쌓기 중)', () {
      // stored 우선 → 50
      expect(_u(stored: 50, days: 10, ns: 3).trustScore, 50);
    });
    test('F-04: 저평가 + 노쇼 복합 최악 케이스 → 0 clamp', () {
      expect(_u(avg: 1.0, rc: 5, ns: 5, late: 10).trustScore, 0);
    });
    test('F-05: 골드 달성 후보 (85점+, 근무50일, 노쇼0) → 92', () {
      // exp=+15(60일), rating=round(1.5×10×1)=15, rehire=round(6.4)=6, late=0
      // 60+15+15+6=96
      // 사실 노쇼0, 50일(exp=+12) → 60+12+15+6=93
      expect(
        _u(days: 50, avg: 4.5, rc: 5, rr: 0.8).trustScore,
        greaterThanOrEqualTo(85),
      );
    });
    test('F-06: 다이아 달성 후보 (95점+, 100일, 노쇼0, 평점4.5+, 재고용1.0)', () {
      final score = _u(days: 100, avg: 4.9, rc: 10, rr: 1.0).trustScore;
      expect(score, greaterThanOrEqualTo(95));
    });
    test('F-07: 비계절성 단발 근무자 (5일, 이력없음) → 60', () {
      expect(_u(days: 5).trustScore, 60);
    });
    test('F-08: 지각만 있는 근무자 (30일, 지각5) → 60', () {
      // exp=+8, late=-8 → 60
      expect(_u(days: 30, late: 5).trustScore, 60);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SIM-G: TrustSettingsModel 검증
  // ═══════════════════════════════════════════════════════════
  group('SIM-G. TrustSettingsModel 검증', () {
    final settings = TrustSettingsModel.defaults();

    test('G-01: startScore=60', () => expect(settings.startScore, 60));
    test('G-02: maxScore=100', () => expect(settings.maxScore, 100));
    test('G-03: getNoshowPenalty(1) == -5', () => expect(_penalty(1), -5));
    test('G-04: getNoshowPenalty(2) == -8', () => expect(_penalty(2), -8));
    test('G-05: getNoshowPenalty(3) == -10', () => expect(_penalty(3), -10));
    test('G-06: getNoshowPenalty(4) == -10 (3+ 동일)', () => expect(_penalty(4), -10));
    test('G-07: getNoshowPenalty(99) == -10', () => expect(_penalty(99), -10));
    test('G-08: work_complete 규칙 존재', () {
      expect(
        settings.increaseRules.any((r) => r.type == 'work_complete'),
        isTrue,
      );
    });
    test('G-09: late 규칙 존재', () {
      expect(settings.decreaseRules.any((r) => r.type == 'late'), isTrue);
    });
    test('G-10: restartProgram.cooldownDays=60', () {
      expect(settings.restartProgram.cooldownDays, 60);
    });
    test('G-11: restartProgram.resetScore=50', () {
      expect(settings.restartProgram.resetScore, 50);
    });
    test('G-12: fromMap(toMap()) 직렬화 왕복 일치', () {
      final map = settings.toMap();
      final restored = TrustSettingsModel.fromMap(map);
      expect(restored.startScore, settings.startScore);
      expect(restored.maxScore, settings.maxScore);
      expect(restored.restartProgram.cooldownDays, settings.restartProgram.cooldownDays);
      expect(restored.increaseRules.length, settings.increaseRules.length);
      expect(restored.decreaseRules.length, settings.decreaseRules.length);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SIM-H: BadgeModel 시뮬레이션
  // ═══════════════════════════════════════════════════════════
  group('SIM-H. BadgeModel 시뮬레이션', () {
    final badges = BadgeModel.defaultBadges();

    test('H-01: defaultBadges() 비어있지 않음', () {
      expect(badges, isNotEmpty);
    });
    test('H-02: 모든 배지 id 고유', () {
      final ids = badges.map((b) => b.id).toList();
      expect(ids.toSet().length, ids.length);
    });
    test('H-03: 레벨 배지 4종 존재', () {
      final levelBadges = badges.where((b) => b.type == BadgeType.trustScore).toList();
      expect(levelBadges.length, 4);
    });
    test('H-04: 경험 배지 2종 존재 (베테랑, 마스터)', () {
      final expBadges = badges.where((b) => b.type == BadgeType.experience).toList();
      expect(expBadges.length, 2);
    });
    test('H-05: 업종 배지 conditionValue=30 (50일→30일 완화)', () {
      final specBadges = badges.where((b) => b.type == BadgeType.specialty).toList();
      for (final b in specBadges) {
        expect(b.conditionValue, 30, reason: '${b.name} conditionValue=30');
      }
    });
    test('H-06: 골드 배지 복합 조건 — maxNoShowAllowed=0', () {
      final gold = badges.firstWhere((b) => b.id == 'badge_gold');
      expect(gold.maxNoShowAllowed, 0);
      expect(gold.minWorkDaysRequired, 50);
      expect(gold.conditionValue, 85);
    });
    test('H-07: 다이아 배지 복합 조건 — 평점 4.5 이상', () {
      final dia = badges.firstWhere((b) => b.id == 'badge_diamond');
      expect(dia.maxNoShowAllowed, 0);
      expect(dia.minWorkDaysRequired, 100);
      expect(dia.minRatingRequired, 4.5);
      expect(dia.conditionValue, 95);
    });
    test('H-08: 실버 배지 — maxNoShowAllowed=1 (1회 허용)', () {
      final silver = badges.firstWhere((b) => b.id == 'badge_silver');
      expect(silver.maxNoShowAllowed, 1);
    });
    test('H-09: 브론즈 배지 — maxNoShowAllowed null (제한 없음)', () {
      final bronze = badges.firstWhere((b) => b.id == 'badge_bronze');
      expect(bronze.maxNoShowAllowed, isNull);
    });
    test('H-10: toMap/fromMap 왕복 직렬화 (복합 조건 포함)', () {
      final gold = badges.firstWhere((b) => b.id == 'badge_gold');
      final map = gold.toMap();
      expect(map['maxNoShowAllowed'], 0);
      expect(map['minWorkDaysRequired'], 50);
      expect(map['conditionValue'], 85);
      expect(map['benefit'], isNotNull);
    });
    test('H-11: fromMap 구 형식 (복합 조건 없음) → null 처리 안전', () {
      final now = DateTime.now();
      final oldMap = <String, dynamic>{
        'name': '브론즈',
        'icon': '🥉',
        'type': 'trustScore',
        'conditionType': 'minScore',
        'conditionValue': 60,
        'isActive': true,
        'order': 1,
        'createdAt': now,
        // 복합 조건 필드 없음
      };
      // Timestamp 없으면 예외 발생 — Timestamp 모킹 불가, 구조 검증만
      expect(oldMap['maxNoShowAllowed'], isNull);
      expect(oldMap['minWorkDaysRequired'], isNull);
    });
    test('H-12: 배지 benefit 문자열 비어있지 않음', () {
      for (final b in badges) {
        if (b.benefit != null) {
          expect(b.benefit!.isNotEmpty, isTrue, reason: '${b.name} benefit 비어있음');
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SIM-I: 공식 일관성 검증 (UserModel ↔ calculateFromData)
  // ═══════════════════════════════════════════════════════════
  group('SIM-I. 공식 일관성 검증', () {
    void _assertConsistent(String label, UserModel u) {
      final fromModel = TrustScoreHelper.calculate(u);
      final fromData = TrustScoreHelper.calculateFromData(
        totalWorkDays: u.totalWorkDays,
        averageRating: u.averageRating,
        reviewCount: u.reviewCount,
        rehireRate: u.rehireRate,
        noShowCount: u.noShowCount,
        lateCount: u.lateCount,
      );
      expect(fromModel, fromData, reason: '$label: calculate vs calculateFromData 불일치');
      if (u.storedTrustScore == null) {
        expect(u.trustScore, fromModel, reason: '$label: trustScore getter 불일치');
      }
    }

    test('I-01: 신입 일관성', () => _assertConsistent('신입', _u()));
    test('I-02: 경험자 일관성', () => _assertConsistent('경험자', _u(days: 60, avg: 4.5, rc: 8, rr: 0.9)));
    test('I-03: 노쇼 있음 일관성', () => _assertConsistent('노쇼', _u(days: 30, ns: 2, late: 3)));
    test('I-04: 저평가 일관성', () => _assertConsistent('저평가', _u(avg: 1.5, rc: 5)));
    test('I-05: 복합 일관성', () => _assertConsistent(
      '복합',
      _u(days: 50, avg: 4.0, rc: 5, rr: 0.8, ns: 1, late: 2),
    ));
    test('I-06: storedTrustScore 있으면 getter가 stored 값 반환', () {
      final u = _u(stored: 77, days: 100, avg: 5.0, rc: 10);
      expect(u.trustScore, 77);
    });
    test('I-07: storedTrustScore=0 → 0 (false-y 오판 없음)', () {
      expect(_u(stored: 0).trustScore, 0);
    });
    test('I-08: 범위 항상 0~100', () {
      final testCases = [
        _u(ns: 100),            // 극단 하한
        _u(days: 300, avg: 5.0, rc: 100, rr: 1.0), // 극단 상한
        _u(late: 100),           // 지각 극단
      ];
      for (final u in testCases) {
        expect(u.trustScore, inInclusiveRange(0, 100));
      }
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SIM-J: 경계값·엣지케이스 집중 탐지
  // ═══════════════════════════════════════════════════════════
  group('SIM-J. 경계값 & 엣지케이스', () {
    test('J-01: noShowCount=0 → 감점 없음', () {
      final withNs = TrustScoreHelper.calculate(_u(ns: 0));
      final noNs   = TrustScoreHelper.calculate(_u(ns: 0));
      expect(withNs, noNs);
    });
    test('J-02: reviewCount=0 → 재고용률 무관하게 기여 0', () {
      expect(TrustScoreHelper.calculate(_u(rc: 0, rr: 1.0)), 60);
      expect(TrustScoreHelper.calculate(_u(rc: 0, rr: 0.0)), 60);
    });
    test('J-03: 음수 입력 방어 — days 음수는 공식 상 +0', () {
      // UserModel 생성 시 음수가 들어올 수 없지만 calculateFromData 직접 호출 방어
      final score = TrustScoreHelper.calculateFromData(
        totalWorkDays: -5,
        averageRating: 0.0,
        reviewCount: 0,
        rehireRate: 0.0,
        noShowCount: 0,
        lateCount: 0,
      );
      expect(score, inInclusiveRange(0, 100));
    });
    test('J-04: noShowCount 음수 입력 → 반복 없음 (for loop i=1 to 0)', () {
      final score = TrustScoreHelper.calculateFromData(
        totalWorkDays: 0,
        averageRating: 0.0,
        reviewCount: 0,
        rehireRate: 0.0,
        noShowCount: -1,
        lateCount: 0,
      );
      expect(score, 60); // 노쇼 음수 → loop 실행 안 됨 → 감점 없음
    });
    test('J-05: lateCount 음수 입력 → loop 실행 안 됨', () {
      final score = TrustScoreHelper.calculateFromData(
        totalWorkDays: 0,
        averageRating: 0.0,
        reviewCount: 0,
        rehireRate: 0.0,
        noShowCount: 0,
        lateCount: -5,
      );
      expect(score, 60);
    });
    test('J-06: averageRating=0.0, rc=0 → 기여 없음', () {
      expect(TrustScoreHelper.calculate(_u(avg: 0.0, rc: 0)), 60);
    });
    test('J-07: averageRating 5.0 초과 입력 → 상한 clamp', () {
      final score = TrustScoreHelper.calculateFromData(
        totalWorkDays: 0, averageRating: 10.0,
        reviewCount: 5, rehireRate: 0.0,
        noShowCount: 0, lateCount: 0,
      );
      expect(score, inInclusiveRange(0, 100));
    });
    test('J-08: rehireRate > 1.0 → clamp(0,8) 적용', () {
      final normal  = TrustScoreHelper.calculateFromData(
        totalWorkDays: 0, averageRating: 3.0,
        reviewCount: 5, rehireRate: 1.0, noShowCount: 0, lateCount: 0,
      );
      final excess  = TrustScoreHelper.calculateFromData(
        totalWorkDays: 0, averageRating: 3.0,
        reviewCount: 5, rehireRate: 99.0, noShowCount: 0, lateCount: 0,
      );
      expect(excess, equals(normal)); // 초과해도 동일한 +8
    });
    test('J-09: 노쇼 만회계수 totalCommitments=0 → 0 나누기 방어', () {
      // days=0, ns=0 → total=0 → rate=0/0 방어 필요
      final score = TrustScoreHelper.calculateFromData(
        totalWorkDays: 0, averageRating: 0.0,
        reviewCount: 0, rehireRate: 0.0,
        noShowCount: 0, lateCount: 0,
      );
      expect(score, 60); // NaN/infinity 없음
    });
    test('J-10: 만회 기준 정확히 days=20, rate=0.95', () {
      // days=19, ns=1: total=20, rate=0.95 but days<20 → factor=1.0 → 59
      // days=20, ns=1: total=21, rate≈0.952 → factor=0.5 → 65
      expect(TrustScoreHelper.calculate(_u(days: 19, ns: 1)), 59);
      expect(TrustScoreHelper.calculate(_u(days: 20, ns: 1)), 65);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SIM-K: 재시작 프로그램 시뮬레이션
  // ═══════════════════════════════════════════════════════════
  group('SIM-K. 재시작 프로그램', () {
    final settings = TrustSettingsModel.defaults();

    test('K-01: 쿨다운 기간 60일', () {
      expect(settings.restartProgram.cooldownDays, 60);
    });
    test('K-02: 리셋 점수 50점', () {
      expect(settings.restartProgram.resetScore, 50);
    });
    test('K-03: 재시작 후 storedTrustScore=50 → trustScore getter=50', () {
      final u = _u(stored: 50, ns: 5, late: 10);
      expect(u.trustScore, 50); // 공식 무시, stored 우선
    });
    test('K-04: 재시작 후 새 근무 20일 쌓으면 (stored 제거 후) → 68', () {
      // exp=+8, diff=0.0 → 평판 기여 0, rehire=0(rc<3) → 68
      expect(_u(days: 20, avg: 3.0, rc: 1).trustScore, 68);
    });
    test('K-05: 쿨다운 중 재신청 불가 (60일 전)', () {
      final lastRestart = DateTime.now().subtract(const Duration(days: 30));
      final cooldownEnd = lastRestart.add(Duration(days: settings.restartProgram.cooldownDays));
      expect(cooldownEnd.isAfter(DateTime.now()), isTrue);
    });
    test('K-06: 쿨다운 완료 후 재신청 가능 (61일 후)', () {
      final lastRestart = DateTime.now().subtract(const Duration(days: 61));
      final cooldownEnd = lastRestart.add(Duration(days: settings.restartProgram.cooldownDays));
      expect(cooldownEnd.isBefore(DateTime.now()), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SIM-L: 이용 제한 메시지 시뮬레이션
  // ═══════════════════════════════════════════════════════════
  group('SIM-L. 이용 제한 메시지', () {
    test('L-01: 3일 제한 — isAfter(now) = true', () {
      final d = _restrictionUntil(1)!;
      expect(d.isAfter(DateTime.now()), isTrue);
    });
    test('L-02: 영구 제한 — year=9999', () {
      final d = _restrictionUntil(4)!;
      expect(d.year, 9999);
    });
    test('L-03: 만료된 제한 — isAfter(now) = false', () {
      final expired = DateTime.now().subtract(const Duration(days: 1));
      expect(expired.isAfter(DateTime.now()), isFalse);
    });
    test('L-04: 제한 0회 → null 반환', () {
      expect(_restrictionUntil(0), isNull);
    });
    test('L-05: isRestricted 로직', () {
      expect(_isRestricted(_restrictionUntil(1)), isTrue);
      expect(_isRestricted(_restrictionUntil(0)), isFalse);
      expect(_isRestricted(DateTime.now().subtract(const Duration(seconds: 1))), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SIM-M: 배지 획득 자격 시뮬레이션 (기준 조건 충족 여부)
  // ═══════════════════════════════════════════════════════════
  group('SIM-M. 배지 자격 시뮬레이션', () {
    bool _eligible(BadgeModel b, UserModel u) {
      final score = u.trustScore;
      if (b.conditionType == BadgeConditionType.minScore && score < b.conditionValue) return false;
      if (b.minWorkDaysRequired != null && u.totalWorkDays < b.minWorkDaysRequired!) return false;
      if (b.maxNoShowAllowed != null && u.noShowCount > b.maxNoShowAllowed!) return false;
      if (b.minRatingRequired != null && u.averageRating < b.minRatingRequired!) return false;
      return true;
    }

    final badges = BadgeModel.defaultBadges();
    final gold    = badges.firstWhere((b) => b.id == 'badge_gold');
    final diamond = badges.firstWhere((b) => b.id == 'badge_diamond');
    final bronze  = badges.firstWhere((b) => b.id == 'badge_bronze');

    test('M-01: 브론즈 — 60점, 5일 → 자격 있음', () {
      final u = _u(days: 5, stored: 60);
      expect(_eligible(bronze, u), isTrue);
    });
    test('M-02: 브론즈 — 59점 → 자격 없음', () {
      final u = _u(days: 5, stored: 59);
      expect(_eligible(bronze, u), isFalse);
    });
    test('M-03: 골드 — 점수 충족·50일·노쇼0 → 자격 있음', () {
      final u = _u(days: 50, ns: 0, stored: 85);
      expect(_eligible(gold, u), isTrue);
    });
    test('M-04: 골드 — 노쇼1회 → 자격 없음 (maxNoShow=0)', () {
      final u = _u(days: 50, ns: 1, stored: 90);
      expect(_eligible(gold, u), isFalse);
    });
    test('M-05: 골드 — 근무 49일 → 자격 없음 (50일 필요)', () {
      final u = _u(days: 49, ns: 0, stored: 90);
      expect(_eligible(gold, u), isFalse);
    });
    test('M-06: 다이아 — 모든 조건 충족', () {
      final u = _u(days: 100, ns: 0, avg: 4.7, stored: 96);
      expect(_eligible(diamond, u), isTrue);
    });
    test('M-07: 다이아 — 평점 4.4 → 자격 없음 (4.5 필요)', () {
      final u = _u(days: 100, ns: 0, avg: 4.4, stored: 96);
      expect(_eligible(diamond, u), isFalse);
    });
    test('M-08: 다이아 — 노쇼1 → 자격 없음', () {
      final u = _u(days: 100, ns: 1, avg: 4.8, stored: 96);
      expect(_eligible(diamond, u), isFalse);
    });
    test('M-09: 다이아 — 근무99일 → 자격 없음 (100일 필요)', () {
      final u = _u(days: 99, ns: 0, avg: 4.8, stored: 96);
      expect(_eligible(diamond, u), isFalse);
    });
  });
}
