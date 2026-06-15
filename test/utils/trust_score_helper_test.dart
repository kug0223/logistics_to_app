import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/utils/trust_score_helper.dart';

// ── 최소 UserModel 생성 헬퍼 ──────────────────────────────────────
UserModel _user({
  double averageRating = 0.0,
  int totalWorkDays = 0,
  int reviewCount = 0,
  double rehireRate = 0.0,
  int noShowCount = 0,
  int lateCount = 0,
  int? storedTrustScore,
}) =>
    UserModel(
      uid: 'u1',
      username: 'tester',
      name: '테스터',
      email: 'test@example.com',
      role: UserRole.USER,
      averageRating: averageRating,
      totalWorkDays: totalWorkDays,
      reviewCount: reviewCount,
      rehireRate: rehireRate,
      noShowCount: noShowCount,
      lateCount: lateCount,
      storedTrustScore: storedTrustScore,
    );

// ── calculateFromData 검증 헬퍼 ───────────────────────────────────
int _calc({
  int days = 0,
  double avg = 0.0,
  int rc = 0,
  double rr = 0.0,
  int ns = 0,
  int late = 0,
}) =>
    TrustScoreHelper.calculateFromData(
      totalWorkDays: days,
      averageRating: avg,
      reviewCount: rc,
      rehireRate: rr,
      noShowCount: ns,
      lateCount: late,
    );

// ═══════════════════════════════════════════════════════════════════
// 공식 요약:
//   base=60
//   경험: days<10→+0 / 10→+4 / 20→+8 / 40→+12 / 60→+15
//   평판: reviewCount=0이면 0. weight=min(rc/5,1). diff=avg-3.0.
//         양: (diff×10×w).round().clamp(0,20)
//         음: (diff×5×w).round().clamp(-10,0)
//   재고용: rc≥3일 때 round(rr×8).clamp(0,8)
//   노쇼: raw=sum(1회:-5, 2회:-8, 3회+:-10).
//         만회: 출근율≥0.95 && days≥20 이면 ×0.5
//   지각: i≤2:-1/i, 3≤i≤5:-2/i, i≥6:-3/i
// ═══════════════════════════════════════════════════════════════════

void main() {
  // ═══════════════════════════════════════════════════════════
  // A. 기본 기준점
  // ═══════════════════════════════════════════════════════════
  group('A. 기본 기준점', () {
    test('A-01: null user → 60', () => expect(TrustScoreHelper.calculate(null), 60));
    test('A-02: 모든 지표 0 → 60', () => expect(_calc(), 60));
    test('A-03: rc=0이면 평점 기여 없음 (avg=5.0, rc=0 → 60)',
        () => expect(_calc(avg: 5.0, rc: 0), 60));
    test('A-04: storedTrustScore 있으면 계산 무시',
        () => expect(_user(storedTrustScore: 42, totalWorkDays: 100).trustScore, 42));
    test('A-05: storedTrustScore=0 → 0 (falsy 오판 없음)',
        () => expect(_user(storedTrustScore: 0).trustScore, 0));
    test('A-06: storedTrustScore 없으면 calculate(user)와 동일', () {
      final u = _user(totalWorkDays: 30, averageRating: 4.0, reviewCount: 5);
      expect(u.trustScore, TrustScoreHelper.calculate(u));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // B. 경험 가산 +0~+15 (단계형)
  // ═══════════════════════════════════════════════════════════
  group('B. 경험 가산', () {
    test('B-01: days=0 → +0 → 60',   () => expect(_calc(days: 0),   60));
    test('B-02: days=5 → +0 → 60',   () => expect(_calc(days: 5),   60));
    test('B-03: days=9 → +0 → 60',   () => expect(_calc(days: 9),   60));
    test('B-04: days=10 → +4 → 64',  () => expect(_calc(days: 10),  64));
    test('B-05: days=15 → +4 → 64',  () => expect(_calc(days: 15),  64));
    test('B-06: days=19 → +4 → 64',  () => expect(_calc(days: 19),  64));
    test('B-07: days=20 → +8 → 68',  () => expect(_calc(days: 20),  68));
    test('B-08: days=30 → +8 → 68',  () => expect(_calc(days: 30),  68));
    test('B-09: days=39 → +8 → 68',  () => expect(_calc(days: 39),  68));
    test('B-10: days=40 → +12 → 72', () => expect(_calc(days: 40),  72));
    test('B-11: days=59 → +12 → 72', () => expect(_calc(days: 59),  72));
    test('B-12: days=60 → +15 → 75', () => expect(_calc(days: 60),  75));
    test('B-13: days=100 → 상한 +15 → 75', () => expect(_calc(days: 100), 75));
    test('B-14: days=300 → clamp 상한 → 75', () => expect(_calc(days: 300), 75));
  });

  // ═══════════════════════════════════════════════════════════
  // C. 평판 기여 (연속형, 리뷰 수 가중치)
  // ═══════════════════════════════════════════════════════════
  group('C. 평판 기여', () {
    // 풀가중치 (rc=5, weight=1.0)
    test('C-01: avg=5.0, rc=5 → diff=2.0, bonus=20 → 80',
        () => expect(_calc(avg: 5.0, rc: 5), 80));
    test('C-02: avg=4.0, rc=5 → diff=1.0, bonus=10 → 70',
        () => expect(_calc(avg: 4.0, rc: 5), 70));
    test('C-03: avg=3.5, rc=5 → diff=0.5, bonus=5 → 65',
        () => expect(_calc(avg: 3.5, rc: 5), 65));
    test('C-04: avg=3.0, rc=5 → diff=0, bonus=0 → 60',
        () => expect(_calc(avg: 3.0, rc: 5), 60));
    // 음수 diff: ×5 (하방 완화)
    test('C-05: avg=2.5, rc=5 → diff=-0.5, (-2.5).round()=-3 → 57',
        () => expect(_calc(avg: 2.5, rc: 5), 57));
    test('C-06: avg=2.0, rc=5 → diff=-1.0, penalty=-5 → 55',
        () => expect(_calc(avg: 2.0, rc: 5), 55));
    test('C-07: avg=1.0, rc=5 → diff=-2.0, penalty=-10 → 50',
        () => expect(_calc(avg: 1.0, rc: 5), 50));
    test('C-08: avg=0.0, rc=5 → (-15).clamp(-10,0)=-10 → 50',
        () => expect(_calc(avg: 0.0, rc: 5), 50));

    // 부분 가중치 (rc=1, weight=0.2)
    test('C-09: avg=5.0, rc=1 → round(2.0×10×0.2)=4 → 64',
        () => expect(_calc(avg: 5.0, rc: 1), 64));
    test('C-10: avg=1.0, rc=1 → round(-2.0×5×0.2)=-2 → 58',
        () => expect(_calc(avg: 1.0, rc: 1), 58));

    // 부분 가중치 (rc=3, weight=0.6)
    test('C-11: avg=5.0, rc=3 → round(2.0×10×0.6)=12 → 72',
        () => expect(_calc(avg: 5.0, rc: 3), 72));
    test('C-12: avg=4.5, rc=3 → round(1.5×10×0.6)=9 → 69',
        () => expect(_calc(avg: 4.5, rc: 3), 69));

    // rc=0 → 평점 무시
    test('C-13: avg=5.0, rc=0 → 60', () => expect(_calc(avg: 5.0, rc: 0), 60));

    // 부분 가중치 경계 (rc=4, weight=0.8)
    test('C-14: avg=5.0, rc=4 → round(2.0×10×0.8)=16 → 76',
        () => expect(_calc(avg: 5.0, rc: 4), 76));
  });

  // ═══════════════════════════════════════════════════════════
  // D. 재고용률 가산 +0~+8
  // ═══════════════════════════════════════════════════════════
  group('D. 재고용률', () {
    // avg=3.0(중립점)으로 평판 기여=0 고정, 재고용률만 격리 테스트
    test('D-01: rr=1.0, rc=3, avg=3.0 → +8 → 68',
        () => expect(_calc(avg: 3.0, rr: 1.0, rc: 3), 68));
    test('D-02: rr=0.5, rc=3, avg=3.0 → +4 → 64',
        () => expect(_calc(avg: 3.0, rr: 0.5, rc: 3), 64));
    test('D-03: rr=0.75, rc=3, avg=3.0 → round(6.0)=6 → 66',
        () => expect(_calc(avg: 3.0, rr: 0.75, rc: 3), 66));
    test('D-04: rr=0.0, rc=3, avg=3.0 → 0 → 60',
        () => expect(_calc(avg: 3.0, rr: 0.0, rc: 3), 60));
    test('D-05: rr=1.0, rc=2, avg=3.0 → rc<3 재고용 없음 → 60',
        () => expect(_calc(avg: 3.0, rr: 1.0, rc: 2), 60));
    test('D-06: rr=1.0, rc=1, avg=3.0 → rc<3 재고용 없음 → 60',
        () => expect(_calc(avg: 3.0, rr: 1.0, rc: 1), 60));
    test('D-07: rr=1.0, rc=10, avg=3.0 → clamp=8 → 68',
        () => expect(_calc(avg: 3.0, rr: 1.0, rc: 10), 68));
    // 복합: avg=4.0, rc=3(w=0.6), rr=1.0
    // rating=round(1.0×10×0.6)=6, rehire=8 → 60+6+8=74
    test('D-08: avg=4.0, rc=3, rr=1.0 → 60+6+8=74',
        () => expect(_calc(avg: 4.0, rc: 3, rr: 1.0), 74));
    // rr=1.2 clamp 테스트 (avg=3.0 중립)
    test('D-09: rr=1.2, rc=5, avg=3.0 → round(9.6)=10→clamp=8 → 68',
        () => expect(_calc(avg: 3.0, rr: 1.2, rc: 5), 68));
  });

  // ═══════════════════════════════════════════════════════════
  // E. 노쇼 감점 누진 (만회계수 없음 — days=0)
  // ═══════════════════════════════════════════════════════════
  group('E. 노쇼 감점 누진', () {
    test('E-01: ns=1 → -5 → 55',     () => expect(_calc(ns: 1), 55));
    test('E-02: ns=2 → -(5+8)=-13 → 47',   () => expect(_calc(ns: 2), 47));
    test('E-03: ns=3 → -(5+8+10)=-23 → 37', () => expect(_calc(ns: 3), 37));
    test('E-04: ns=4 → -33 → 27',    () => expect(_calc(ns: 4), 27));
    test('E-05: ns=5 → -43 → 17',    () => expect(_calc(ns: 5), 17));
    test('E-06: ns=6 → -53 → 7',     () => expect(_calc(ns: 6), 7));
    test('E-07: ns=7 → -63 → 0 (clamp)', () => expect(_calc(ns: 7), 0));
    test('E-08: ns=10 → 0 (clamp)',  () => expect(_calc(ns: 10), 0));
    test('E-09: ns=20 → 0 (clamp)',  () => expect(_calc(ns: 20), 0));
  });

  // ═══════════════════════════════════════════════════════════
  // F. 노쇼 만회계수 (출근율≥0.95 && days≥20 → ×0.5)
  // ═══════════════════════════════════════════════════════════
  group('F. 노쇼 만회계수', () {
    // days=20, ns=1: total=21, rate=20/21≈0.952≥0.95, days≥20 → factor=0.5
    //   raw=5, deduct=round(2.5)=3 → 60+8-3=65
    test('F-01: ns=1, days=20 → factor=0.5, deduct=3 → 65',
        () => expect(_calc(ns: 1, days: 20), 65));

    // days=100, ns=2: total=102, rate≈0.980 → factor=0.5
    //   raw=13, deduct=round(6.5)=7 → 60+15-7=68
    test('F-02: ns=2, days=100 → factor=0.5, deduct=7 → 68',
        () => expect(_calc(ns: 2, days: 100), 68));

    // days=19, ns=1: rate=0.95 충족하지만 days<20 → factor=1.0
    //   raw=5, exp=+4 → 60+4-5=59
    test('F-03: ns=1, days=19 → days<20으로 만회 미적용 → 59',
        () => expect(_calc(ns: 1, days: 19), 59));

    // days=5, ns=1: rate=5/6≈0.833 < 0.95 → factor=1.0
    test('F-04: ns=1, days=5 → rate<0.95 → 55',
        () => expect(_calc(ns: 1, days: 5), 55));

    // days=38, ns=2: total=40, rate=0.95 경계 → factor=0.5
    //   raw=13, deduct=round(6.5)=7, exp=+8 → 60+8-7=61
    test('F-05: ns=2, days=38 → 출근율=0.95 경계 만회 적용 → 61',
        () => expect(_calc(ns: 2, days: 38), 61));

    // days=57, ns=3: total=60, rate=0.95 → factor=0.5
    //   raw=23, deduct=round(11.5)=12, exp=+12 → 60+12-12=60
    test('F-06: ns=3, days=57 → factor=0.5, deduct=12 → 60',
        () => expect(_calc(ns: 3, days: 57), 60));

    // 만회 경계 비교: days=19 vs days=20
    test('F-07: 만회계수 days=19→미적용, days=20→적용 비교', () {
      expect(_calc(ns: 1, days: 19), 59); // factor=1.0 → -5
      expect(_calc(ns: 1, days: 20), 65); // factor=0.5 → -3
    });
  });

  // ═══════════════════════════════════════════════════════════
  // G. 지각 감점 누진
  // ═══════════════════════════════════════════════════════════
  group('G. 지각 감점 누진', () {
    test('G-01: late=0 → 0 → 60',    () => expect(_calc(late: 0),  60));
    test('G-02: late=1 → -1 → 59',   () => expect(_calc(late: 1),  59));
    test('G-03: late=2 → -2 → 58',   () => expect(_calc(late: 2),  58));
    // 3회부터 -2/회
    test('G-04: late=3 → -(1+1+2)=-4 → 56', () => expect(_calc(late: 3), 56));
    test('G-05: late=4 → -(1+1+2+2)=-6 → 54', () => expect(_calc(late: 4), 54));
    test('G-06: late=5 → -(1+1+2+2+2)=-8 → 52', () => expect(_calc(late: 5), 52));
    // 6회부터 -3/회
    test('G-07: late=6 → -(8+3)=-11 → 49', () => expect(_calc(late: 6), 49));
    test('G-08: late=7 → -(8+3+3)=-14 → 46', () => expect(_calc(late: 7), 46));
    // late=10: -(1+1+2+2+2+3+3+3+3+3)=-23 → 37
    test('G-09: late=10 → -(2+6+15)=-23 → 37', () => expect(_calc(late: 10), 37));
    // late=20: -(1+1+2+2+2 + 3×15)=-(8+45)=-53 → 60-53=7
    test('G-10: late=20 → -53 → 7',
        () => expect(_calc(late: 20), 7));
  });

  // ═══════════════════════════════════════════════════════════
  // H. 복합 시나리오
  // ═══════════════════════════════════════════════════════════
  group('H. 복합 시나리오', () {
    // 성실 신입 (20일, avg4.5 rc5, rr0.8)
    // exp=+8, rating=round(1.5×10×1)=15, rehire=round(6.4)=6 → 89
    test('H-01: 성실신입(20일,avg4.5,rc5,rr0.8) → 89', () {
      expect(_calc(days: 20, avg: 4.5, rc: 5, rr: 0.8), 89);
    });

    // 장기 우수 (100일, avg4.8 rc10, rr1.0)
    // exp=+15, rating=round(1.8×10×1)=18, rehire=8 → 101→100
    test('H-02: 장기우수(100일,avg4.8,rc10,rr1.0) → 100', () {
      expect(_calc(days: 100, avg: 4.8, rc: 10, rr: 1.0), 100);
    });

    // 경험자 노쇼 만회 (60일, ns=1)
    // exp=+15, total=61, rate≈0.984 → factor=0.5, deduct=3 → 72
    test('H-03: 경험자(60일,ns=1,만회) → 72', () {
      expect(_calc(days: 60, ns: 1), 72);
    });

    // 지각+노쇼 동시 (30일, ns=1, late=3)
    // exp=+8, factor=0.5 deduct=3, late=-4 → 61
    test('H-04: 지각+노쇼(30일,ns=1,late=3) → 61', () {
      expect(_calc(days: 30, ns: 1, late: 3), 61);
    });

    // 불성실 (ns=2, late=5)
    // raw=13, factor=1.0, deduct=13; late=-8 → 39
    test('H-05: 불성실(ns=2,late=5) → 39', () {
      expect(_calc(ns: 2, late: 5), 39);
    });

    // 저평점+지각 (avg=1.5 rc=5, late=4)
    // diff=-1.5, w=1.0, penalty=round(-7.5)=-8; late=-6 → 46
    test('H-06: 저평점+지각(avg=1.5,rc=5,late=4) → 46', () {
      expect(_calc(avg: 1.5, rc: 5, late: 4), 46);
    });

    // 이론 최고점 → 100 clamp
    test('H-07: 최고점(60일+,avg5.0,rc5,rr1.0) → 100', () {
      expect(_calc(days: 60, avg: 5.0, rc: 5, rr: 1.0), 100);
    });

    // 극단 감점 → 0 clamp
    test('H-08: 극단 감점(ns=20,late=20) → 0', () {
      expect(_calc(ns: 20, late: 20), 0);
    });

    // 이력 없음
    test('H-09: 신규(days=5) → 60', () {
      expect(_calc(days: 5), 60);
    });

    // 재고용 rc 경계 (rc=2면 없음) — avg=3.0으로 평판 기여 제거
    test('H-10: rr=1.0, rc=2, avg=3.0 → 재고용 없음 → 60', () {
      expect(_calc(avg: 3.0, rr: 1.0, rc: 2), 60);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // I. 경계값 & clamp
  // ═══════════════════════════════════════════════════════════
  group('I. 경계값 & clamp', () {
    test('I-01: 점수 최소 0 clamp (ns=50)', () {
      expect(_calc(ns: 50), 0);
    });
    test('I-02: 점수 최대 100 clamp', () {
      expect(_calc(days: 300, avg: 5.0, rc: 100, rr: 1.0), 100);
    });
    test('I-03: 경험 10일 경계 (9→60, 10→64)', () {
      expect(_calc(days: 9),  60);
      expect(_calc(days: 10), 64);
    });
    test('I-04: 경험 20일 경계 (19→64, 20→68)', () {
      expect(_calc(days: 19), 64);
      expect(_calc(days: 20), 68);
    });
    test('I-05: 경험 40일 경계 (39→68, 40→72)', () {
      expect(_calc(days: 39), 68);
      expect(_calc(days: 40), 72);
    });
    test('I-06: 경험 60일 경계 (59→72, 60→75)', () {
      expect(_calc(days: 59), 72);
      expect(_calc(days: 60), 75);
    });
    test('I-07: 리뷰 가중치 rc=4 (weight=0.8) → bonus=16 → 76', () {
      expect(_calc(avg: 5.0, rc: 4), 76);
    });
    test('I-08: 리뷰 가중치 rc=5 (풀가중치) → bonus=20 → 80', () {
      expect(_calc(avg: 5.0, rc: 5), 80);
    });
    test('I-09: rc>5 도 풀가중치 동일 (rc=10 → 80)', () {
      expect(_calc(avg: 5.0, rc: 10), 80);
    });
    // avg=3.0 중립으로 평판 기여 제거하고 재고용률만 검증
    test('I-10: rr=0.0, rc=5, avg=3.0 → 보너스 없음 → 60', () {
      expect(_calc(avg: 3.0, rr: 0.0, rc: 5), 60);
    });
    test('I-11: rr=1.2, rc=5, avg=3.0 → clamp=8 → 68', () {
      expect(_calc(avg: 3.0, rr: 1.2, rc: 5), 68);
    });
    test('I-12: 만회계수 days=19 vs 20 경계', () {
      expect(_calc(ns: 1, days: 19), 59); // days<20 → factor=1.0
      expect(_calc(ns: 1, days: 20), 65); // days≥20 → factor=0.5
    });
    test('I-13: 만회계수 출근율 0.95 경계 (days=38, ns=2 → 61)', () {
      expect(_calc(ns: 2, days: 38), 61); // rate=38/40=0.95 → 적용
    });
    test('I-14: 평판 음수 clamp (avg=0.0, rc=5 → -15→clamp=-10 → 50)', () {
      expect(_calc(avg: 0.0, rc: 5), 50);
    });
    test('I-15: 노쇼 days=0 이면 만회 미적용', () {
      // days=0, ns=1: total=1, rate=0/1=0 → factor=1.0 → 55
      expect(_calc(days: 0, ns: 1), 55);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // J. UserModel.trustScore getter 위임 검증
  // ═══════════════════════════════════════════════════════════
  group('J. UserModel.trustScore 위임', () {
    test('J-01: storedTrustScore 있으면 calculate() 무시', () {
      expect(_user(storedTrustScore: 77, totalWorkDays: 100).trustScore, 77);
    });
    test('J-02: storedTrustScore 없으면 calculate(user)와 동일', () {
      final u = _user(totalWorkDays: 30, averageRating: 4.0, reviewCount: 5);
      expect(u.trustScore, TrustScoreHelper.calculate(u));
    });
    test('J-03: storedTrustScore=0 도 0 반환 (falsy 오판 없음)', () {
      expect(_user(storedTrustScore: 0).trustScore, 0);
    });
    test('J-04: calculate(user) == calculateFromData(동일 필드)', () {
      final u = _user(
        totalWorkDays: 45,
        averageRating: 3.8,
        reviewCount: 4,
        rehireRate: 0.6,
        noShowCount: 1,
        lateCount: 2,
      );
      expect(
        TrustScoreHelper.calculate(u),
        TrustScoreHelper.calculateFromData(
          totalWorkDays: u.totalWorkDays,
          averageRating: u.averageRating,
          reviewCount: u.reviewCount,
          rehireRate: u.rehireRate,
          noShowCount: u.noShowCount,
          lateCount: u.lateCount,
        ),
      );
    });
    test('J-05: 모든 지표 최대 → 100', () {
      final u = _user(
        totalWorkDays: 100,
        averageRating: 5.0,
        reviewCount: 10,
        rehireRate: 1.0,
        noShowCount: 0,
        lateCount: 0,
      );
      expect(u.trustScore, 100);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // K. 실제 페르소나 시나리오
  // ═══════════════════════════════════════════════════════════
  group('K. 실제 페르소나', () {
    test('K-01: 신입 (이력없음) → 60', () {
      expect(_calc(), 60);
    });

    // days=10, avg=3.0, rc=1 → exp=+4, diff=0 → bonus=0 → 64
    test('K-02: 첫 근무 완료 (10일, avg3.0, rc1) → 64', () {
      expect(_calc(days: 10, avg: 3.0, rc: 1), 64);
    });

    // days=25, avg=4.0, rc=3(w=0.6), rr=0.7
    // exp=+8, rating=round(6.0)=6, rehire=round(5.6)=6 → 80
    test('K-03: 한 달 성실 (25일, avg4.0, rc3, rr0.7) → 80', () {
      expect(_calc(days: 25, avg: 4.0, rc: 3, rr: 0.7), 80);
    });

    // days=60, avg=4.5, rc=8(w=1.0), rr=0.9
    // exp=+15, rating=round(15.0)=15, rehire=round(7.2)=7 → 97
    test('K-04: 3개월 성실 (60일, avg4.5, rc8, rr0.9) → 97', () {
      expect(_calc(days: 60, avg: 4.5, rc: 8, rr: 0.9), 97);
    });

    test('K-05: 불성실 신입 (5일, ns=1) → 55', () {
      expect(_calc(days: 5, ns: 1), 55);
    });

    // days=40, late=6: exp=+12, late=-(1+1+2+2+2+3)=-11 → 61
    test('K-06: 지각 잦음 (40일, late=6) → 61', () {
      expect(_calc(days: 40, late: 6), 61);
    });

    // days=100, ns=2: exp=+15, total=102, rate≈0.980 → factor=0.5
    //   raw=13, deduct=7 → 68
    test('K-07: 오랜 노쇼 만회 (100일, ns=2) → 68', () {
      expect(_calc(days: 100, ns: 2), 68);
    });

    // days=100, avg=4.9, rc=12(w=1), rr=1.0
    // exp=+15, rating=round(1.9×10)=19, rehire=8 → 102→100
    test('K-08: 다이아 후보 (100일, avg4.9, rc12, rr1.0) → 100', () {
      expect(_calc(days: 100, avg: 4.9, rc: 12, rr: 1.0), 100);
    });

    // ns=3, late=2: raw=23, deduct=23, late=-2 → 35
    test('K-09: 제재 직전 (ns=3, late=2) → 35', () {
      expect(_calc(ns: 3, late: 2), 35);
    });

    // 재시작 프로그램 후 → storedTrustScore=50 우선 사용
    test('K-10: 재시작 후 (storedTrustScore=50, ns=3) → 50', () {
      expect(_user(storedTrustScore: 50, noShowCount: 3).trustScore, 50);
    });

    // days=40, avg=3.0, rc=5, rr=0.5, ns=1, late=2
    // exp=+12, rating=round(0)=0, rehire=round(4)=4
    // ns=1, total=41, rate=40/41≈0.976≥0.95, days≥20 → factor=0.5, deduct=round(2.5)=3
    // late=-(1+1)=-2 → 60+12+0+4-3-2=71
    test('K-11: 균형 잡힌 근무자 (40일, avg3.0, rc5, rr0.5, ns1, late2) → 71', () {
      expect(_calc(days: 40, avg: 3.0, rc: 5, rr: 0.5, ns: 1, late: 2), 71);
    });

    // days=20, avg=4.5, rc=5, ns=2
    // exp=+8, rating=round(15)=15
    // ns=2, total=22, rate=20/22≈0.909 < 0.95 → factor=1.0, deduct=13 → 70
    test('K-12: 노쇼2 만회 미적용 (20일, avg4.5, rc5, ns=2) → 70', () {
      expect(_calc(days: 20, avg: 4.5, rc: 5, ns: 2), 70);
    });
  });
}
