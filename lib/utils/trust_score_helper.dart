import '../models/core/user_model.dart';

/// 신뢰도 점수 정적 계산 유틸
///
/// 오프라인/폴백용 공식. [UserModel.storedTrustScore]가 없을 때 디스플레이 시점에 사용.
/// [TrustScoreService._computeScore()]도 이 공식을 위임받아 사용하므로
/// 저장 경로와 폴백 경로의 점수가 항상 일치한다.
class TrustScoreHelper {
  TrustScoreHelper._();

  // ── 공식 상수 ────────────────────────────────────────────────
  static const int _base = 60;             // 신규·이력 없음 기준점
  static const double _ratingPivot = 3.0;  // 평판 중립 기준점
  static const int _ratingWeightAt = 5;    // 풀가중치 최소 리뷰 수
  static const int _rehireWeightAt = 3;    // 재고용률 집계 최소 리뷰 수
  static const double _mitigateThreshold = 0.95; // 만회계수 출근율 기준
  static const int _mitigateMinDays = 20;  // 만회계수 최소 근무일수

  // ─────────────────────────────────────────────────────────────
  // 공개 API
  // ─────────────────────────────────────────────────────────────

  /// [UserModel] 기반 신뢰도 점수 (0~100).
  ///
  /// null이면 기준점 60 반환.
  static int calculate(UserModel? user) {
    if (user == null) return _base;
    return calculateFromData(
      totalWorkDays: user.totalWorkDays,
      averageRating: user.averageRating,
      reviewCount: user.reviewCount,
      rehireRate: user.rehireRate,
      noShowCount: user.noShowCount,
      lateCount: user.lateCount,
    );
  }

  /// 필드값 기반 신뢰도 점수 (0~100).
  ///
  /// Firestore Map에서 추출한 값을 직접 넘길 때 사용 ([TrustScoreService] 위임).
  /// [calculate]와 동일한 공식 — 단일 공식 원칙.
  static int calculateFromData({
    required int totalWorkDays,
    required double averageRating,
    required int reviewCount,
    required double rehireRate,
    required int noShowCount,
    required int lateCount,
  }) {
    int score = _base;

    // ── [1] 경험 가산 +0~+15 (단계형) ──────────────────────────
    // 장기 근무자일수록 신뢰도 가점. 60일에 상한.
    score += _experienceBonus(totalWorkDays);

    // ── [2] 평판 기여 -10~+20 (연속형) ─────────────────────────
    // 리뷰가 없으면 기여 없음(0). 리뷰 5개 미만이면 비례 축소(과적합 방지).
    // 기준점 3.0 초과 시 상방(×10), 미만 시 하방(×5) — 하방 방어 설계.
    if (reviewCount > 0) {
      final weight = (reviewCount / _ratingWeightAt).clamp(0.0, 1.0);
      final diff = averageRating - _ratingPivot;
      if (diff >= 0) {
        score += (diff * 10.0 * weight).round().clamp(0, 20);
      } else {
        score += (diff * 5.0 * weight).round().clamp(-10, 0);
      }

      // ── [3] 재고용률 가산 +0~+8 ─────────────────────────────
      // 리뷰 3개 미만은 통계 신뢰 불충분.
      if (reviewCount >= _rehireWeightAt) {
        score += (rehireRate * 8.0).round().clamp(0, 8);
      }
    }

    // ── [4] 노쇼 감점 -5/-8/-10 누진 + 만회계수 ────────────────
    // 출근율 ≥95% && 근무 20일+ 이면 감점 50% 감면.
    // → 장기 성실 근로자의 돌발 노쇼 1회가 신입 노쇼와 같은 무게를 갖지 않도록.
    if (noShowCount > 0) {
      final total = totalWorkDays + noShowCount;
      final rate = total > 0 ? totalWorkDays / total : 0.0;
      final factor = (rate >= _mitigateThreshold && totalWorkDays >= _mitigateMinDays)
          ? 0.5
          : 1.0;

      int raw = 0;
      for (int i = 1; i <= noShowCount; i++) {
        raw += i == 1 ? 5 : i == 2 ? 8 : 10;
      }
      score -= (raw * factor).round();
    }

    // ── [5] 지각 감점 -1/-2/-3 누진 ─────────────────────────────
    // 지각이 잦을수록 회당 페널티 증가.
    for (int i = 1; i <= lateCount; i++) {
      score -= i <= 2 ? 1 : i <= 5 ? 2 : 3;
    }

    return score.clamp(0, 100);
  }

  // ─────────────────────────────────────────────────────────────
  // private
  // ─────────────────────────────────────────────────────────────

  static int _experienceBonus(int days) {
    if (days >= 60) return 15;
    if (days >= 40) return 12;
    if (days >= 20) return 8;
    if (days >= 10) return 4;
    return 0;
  }
}
