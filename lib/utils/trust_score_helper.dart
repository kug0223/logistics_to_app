import '../models/core/user_model.dart';

class TrustScoreHelper {
  TrustScoreHelper._();

  /// 신뢰도 점수 계산 (0~100)
  /// 기준: 평점(40점) + 근무일수(15점) + 기본(60점) - 노쇼(5점) - 지각(2점)
  static int calculate(UserModel? user) {
    if (user == null) return 60;
    int score = 60;
    score += (user.averageRating * 4).round();
    score += (user.totalWorkDays / 10).clamp(0, 15).round();
    score -= user.noShowCount * 5;
    score -= user.lateCount * 2;
    return score.clamp(0, 100);
  }
}
