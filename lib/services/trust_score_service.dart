// lib/services/trust_score_service.dart

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/settings/trust_settings_model.dart';

/// 신뢰도 점수 서비스
/// 
/// 정책:
/// - 시작 점수: 50점
/// - 상한선: 100점
/// - 근무 완료: +1점
/// - 좋은 평가 (4.5↑): +2점
/// - 재고용 희망: +1점
/// - 지각: -1점
/// - 노쇼: -3~10점 (누적)
/// - 낮은 평가 (2.0↓): -2점
class TrustScoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // 캐시된 설정
  TrustSettingsModel? _cachedSettings;
  DateTime? _settingsCacheTime;
  static const _cacheDuration = Duration(minutes: 30);

  // ═══════════════════════════════════════════════════════════
  // 신뢰도 점수 계산
  // ═══════════════════════════════════════════════════════════

  /// 사용자 신뢰도 점수 계산 (실시간)
  Future<int> calculateTrustScore(String userId) async {
    try {
      final settings = await _getSettings();
      final userDoc = await _firestore.collection('users').doc(userId).get();
      
      if (!userDoc.exists) return settings.startScore;
      
      final userData = userDoc.data()!;
      
      // 저장된 신뢰도가 있으면 반환
      if (userData['trustScore'] != null) {
        return userData['trustScore'] as int;
      }
      
      // 없으면 계산
      return _computeScore(userData, settings);
    } catch (e) {
      debugPrint('❌ 신뢰도 계산 실패: $e');
      return 50; // 기본값
    }
  }

  /// 점수 계산 로직
  int _computeScore(Map<String, dynamic> userData, TrustSettingsModel settings) {
    int score = settings.startScore;
    
    // 1. 근무 완료 가산 (+1점/일)
    final int totalWorkDays = (userData['totalWorkDays'] ?? 0) as int;
    final workCompleteRule = settings.increaseRules
        .firstWhere((r) => r.type == 'work_complete', 
            orElse: () => TrustRule(type: '', points: 1, description: ''));
    score += totalWorkDays * workCompleteRule.points;
    
    // 2. 평균 평점 기반 가감
    final avgRating = (userData['averageRating'] ?? 0.0) as double;
    final reviewCount = userData['reviewCount'] ?? 0;
    
    if (reviewCount > 0) {
      // 좋은 평가 가산
      final goodReviewRule = settings.increaseRules
          .firstWhere((r) => r.type == 'good_review',
              orElse: () => TrustRule(type: '', points: 2, description: '', condition: 4.5));
      if (avgRating >= (goodReviewRule.condition ?? 4.5)) {
        score += goodReviewRule.points;
      }
      
      // 낮은 평가 감점
      final badReviewRule = settings.decreaseRules
          .firstWhere((r) => r.type == 'bad_review',
              orElse: () => TrustRule(type: '', points: -2, description: '', condition: 2.0));
      if (avgRating <= (badReviewRule.condition ?? 2.0)) {
        score += badReviewRule.points; // 음수
      }
    }
    
    // 3. 재고용 희망률 가산
    final rehireRate = (userData['rehireRate'] ?? 0.0) as double;
    if (rehireRate >= 0.8 && reviewCount >= 3) {
      final rehireRule = settings.increaseRules
          .firstWhere((r) => r.type == 'rehire_yes',
              orElse: () => TrustRule(type: '', points: 1, description: ''));
      score += rehireRule.points;
    }
    
    // 4. 지각 감점
    final int lateCount = (userData['lateCount'] ?? 0) as int;
    final lateRule = settings.decreaseRules
        .firstWhere((r) => r.type == 'late',
            orElse: () => TrustRule(type: '', points: -1, description: ''));
    score += lateCount * lateRule.points; // 음수
    
    // 5. 노쇼 감점 (누적 기반)
    final noShowCount = userData['noShowCount'] ?? 0;
    if (noShowCount > 0) {
      score += settings.getNoshowPenalty(noShowCount);
    }
    
    // 범위 제한
    return score.clamp(0, settings.maxScore);
  }

  // ═══════════════════════════════════════════════════════════
  // 점수 이벤트 처리
  // ═══════════════════════════════════════════════════════════

  /// 근무 완료 시 점수 업데이트
  Future<void> onWorkComplete(String userId) async {
    await _updateScore(userId, 'work_complete', isIncrease: true);
  }

  /// 지각 시 점수 업데이트
  Future<void> onLate(String userId) async {
    // 지각 횟수 증가
    await _firestore.collection('users').doc(userId).update({
      'lateCount': FieldValue.increment(1),
    });
    await _updateScore(userId, 'late', isIncrease: false);
  }

  /// 노쇼 시 점수 업데이트
  Future<void> onNoShow(String userId) async {
    // 노쇼 횟수 증가
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final currentNoShowCount = (userDoc.data()?['noShowCount'] ?? 0) as int;
    final newNoShowCount = currentNoShowCount + 1;
    
    await _firestore.collection('users').doc(userId).update({
      'noShowCount': newNoShowCount,
    });
    
    // 노쇼 횟수에 따른 감점
    final settings = await _getSettings();
    final penalty = settings.getNoshowPenalty(newNoShowCount);
    
    await _applyScoreChange(userId, penalty, '노쇼 $newNoShowCount회');
  }

  /// 리뷰 받음 시 점수 업데이트
  Future<void> onReviewReceived(String userId, int rating, bool wouldRehire) async {
    final settings = await _getSettings();
    
    // 좋은 평가
    if (rating >= 4.5) {
      final rule = settings.increaseRules
          .firstWhere((r) => r.type == 'good_review',
              orElse: () => TrustRule(type: '', points: 2, description: ''));
      await _applyScoreChange(userId, rule.points, '좋은 평가');
    }
    
    // 낮은 평가
    if (rating <= 2.0) {
      final rule = settings.decreaseRules
          .firstWhere((r) => r.type == 'bad_review',
              orElse: () => TrustRule(type: '', points: -2, description: ''));
      await _applyScoreChange(userId, rule.points, '낮은 평가');
    }
    
    // 재고용 희망
    if (wouldRehire) {
      final rule = settings.increaseRules
          .firstWhere((r) => r.type == 'rehire_yes',
              orElse: () => TrustRule(type: '', points: 1, description: ''));
      await _applyScoreChange(userId, rule.points, '재고용 희망');
    }
  }

  /// 점수 변경 적용
  Future<void> _applyScoreChange(String userId, int change, String reason) async {
    try {
      final settings = await _getSettings();
      
      await _firestore.runTransaction((transaction) async {
        final userRef = _firestore.collection('users').doc(userId);
        final userDoc = await transaction.get(userRef);
        
        if (!userDoc.exists) return;
        
        final currentScore = userDoc.data()?['trustScore'] ?? settings.startScore;
        final newScore = (currentScore + change).clamp(0, settings.maxScore);
        
        transaction.update(userRef, {'trustScore': newScore});
        
        // 점수 변동 기록
        final historyRef = _firestore.collection('trust_score_history').doc();
        transaction.set(historyRef, {
          'userId': userId,
          'previousScore': currentScore,
          'newScore': newScore,
          'change': change,
          'reason': reason,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
      
      debugPrint('✅ 신뢰도 변경: $userId, $change점 ($reason)');
    } catch (e) {
      debugPrint('❌ 신뢰도 변경 실패: $e');
    }
  }

  /// 설정 기반 점수 업데이트
  Future<void> _updateScore(String userId, String ruleType, {required bool isIncrease}) async {
    final settings = await _getSettings();
    
    final rules = isIncrease ? settings.increaseRules : settings.decreaseRules;
    final rule = rules.firstWhere(
      (r) => r.type == ruleType,
      orElse: () => TrustRule(type: '', points: 0, description: ''),
    );
    
    if (rule.points != 0) {
      await _applyScoreChange(userId, rule.points, rule.description);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 재시작 프로그램
  // ═══════════════════════════════════════════════════════════

  /// 재시작 프로그램 신청 가능 여부
  Future<({bool canRestart, String? reason, int? daysRemaining})> canApplyRestart(String userId) async {
    try {
      final settings = await _getSettings();
      final userDoc = await _firestore.collection('users').doc(userId).get();
      
      if (!userDoc.exists) {
        return (canRestart: false, reason: '사용자 정보를 찾을 수 없습니다.', daysRemaining: null);
      }
      
      final userData = userDoc.data()!;
      final lastRestartAt = (userData['lastRestartAt'] as Timestamp?)?.toDate();
      
      if (lastRestartAt != null) {
        final cooldownEnd = lastRestartAt.add(Duration(days: settings.restartProgram.cooldownDays));
        if (DateTime.now().isBefore(cooldownEnd)) {
          final daysRemaining = cooldownEnd.difference(DateTime.now()).inDays;
          return (
            canRestart: false, 
            reason: '쿨타임 중입니다. ${daysRemaining}일 후 신청 가능합니다.',
            daysRemaining: daysRemaining,
          );
        }
      }
      
      return (canRestart: true, reason: null, daysRemaining: null);
    } catch (e) {
      debugPrint('❌ 재시작 가능 여부 확인 실패: $e');
      return (canRestart: false, reason: '확인 중 오류가 발생했습니다.', daysRemaining: null);
    }
  }

  /// 재시작 프로그램 적용
  Future<bool> applyRestartProgram(String userId) async {
    try {
      final canRestart = await canApplyRestart(userId);
      if (!canRestart.canRestart) {
        debugPrint('⚠️ 재시작 불가: ${canRestart.reason}');
        return false;
      }
      
      final settings = await _getSettings();
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data()!;
      
      final currentNoShow = userData['noShowCount'] ?? 0;
      final currentLate = userData['lateCount'] ?? 0;
      
      await _firestore.collection('users').doc(userId).update({
        'trustScore': settings.restartProgram.resetScore,
        'noShowCount': (currentNoShow - settings.restartProgram.noshowReduction).clamp(0, 999),
        'lateCount': (currentLate - settings.restartProgram.lateReduction).clamp(0, 999),
        'lastRestartAt': FieldValue.serverTimestamp(),
      });
      
      // 재시작 기록
      await _firestore.collection('restart_program_history').add({
        'userId': userId,
        'previousScore': userData['trustScore'] ?? settings.startScore,
        'newScore': settings.restartProgram.resetScore,
        'noshowReduced': settings.restartProgram.noshowReduction,
        'lateReduced': settings.restartProgram.lateReduction,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      debugPrint('✅ 재시작 프로그램 적용 완료: $userId');
      return true;
    } catch (e) {
      debugPrint('❌ 재시작 프로그램 적용 실패: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 신뢰도 등급
  // ═══════════════════════════════════════════════════════════

  /// 점수 기반 등급 반환
  TrustGrade getGrade(int score) {
    if (score >= 90) return TrustGrade.excellent;
    if (score >= 70) return TrustGrade.good;
    if (score >= 50) return TrustGrade.normal;
    if (score >= 30) return TrustGrade.warning;
    return TrustGrade.danger;
  }

  /// 점수 변동 내역 조회
  Future<List<Map<String, dynamic>>> getScoreHistory(String userId, {int limit = 20}) async {
    try {
      final snapshot = await _firestore
          .collection('trust_score_history')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'previousScore': data['previousScore'],
          'newScore': data['newScore'],
          'change': data['change'],
          'reason': data['reason'],
          'createdAt': (data['createdAt'] as Timestamp?)?.toDate(),
        };
      }).toList();
    } catch (e) {
      debugPrint('❌ 점수 변동 내역 조회 실패: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 설정 조회
  // ═══════════════════════════════════════════════════════════

  Future<TrustSettingsModel> _getSettings() async {
    // 캐시 확인
    if (_cachedSettings != null && 
        _settingsCacheTime != null &&
        DateTime.now().difference(_settingsCacheTime!) < _cacheDuration) {
      return _cachedSettings!;
    }
    
    try {
      final doc = await _firestore.collection('settings').doc('trust_rules').get();
      
      if (!doc.exists) {
        final defaults = TrustSettingsModel.defaults();
        await _firestore.collection('settings').doc('trust_rules').set(defaults.toMap());
        _cachedSettings = defaults;
      } else {
        _cachedSettings = TrustSettingsModel.fromFirestore(doc);
      }
      
      _settingsCacheTime = DateTime.now();
      return _cachedSettings!;
    } catch (e) {
      debugPrint('❌ 신뢰도 설정 조회 실패: $e');
      return TrustSettingsModel.defaults();
    }
  }

  /// 신뢰도 설정 새로고침
  void clearCache() {
    _cachedSettings = null;
    _settingsCacheTime = null;
  }
}

/// 신뢰도 등급
enum TrustGrade {
  excellent,  // 90~100: 🌟 최우수
  good,       // 70~89: ✅ 우수
  normal,     // 50~69: 😐 보통
  warning,    // 30~49: ⚠️ 주의
  danger,     // 0~29: 🚨 경고
}

extension TrustGradeExtension on TrustGrade {
  String get label {
    switch (this) {
      case TrustGrade.excellent: return '최우수';
      case TrustGrade.good: return '우수';
      case TrustGrade.normal: return '보통';
      case TrustGrade.warning: return '주의';
      case TrustGrade.danger: return '경고';
    }
  }
  
  String get emoji {
    switch (this) {
      case TrustGrade.excellent: return '🌟';
      case TrustGrade.good: return '✅';
      case TrustGrade.normal: return '😐';
      case TrustGrade.warning: return '⚠️';
      case TrustGrade.danger: return '🚨';
    }
  }
  
  String get colorHex {
    switch (this) {
      case TrustGrade.excellent: return '#FFD700'; // 금색
      case TrustGrade.good: return '#4CAF50';      // 초록
      case TrustGrade.normal: return '#9E9E9E';    // 회색
      case TrustGrade.warning: return '#FF9800';   // 주황
      case TrustGrade.danger: return '#F44336';    // 빨강
    }
  }
}