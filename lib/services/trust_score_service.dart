// lib/services/trust_score_service.dart

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/settings/trust_settings_model.dart';
import '../utils/trust_score_helper.dart';

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
///
/// ⚠️ [SEC-01] 아키텍처 이슈:
/// trustScore 필드를 클라이언트(관리자 세션)에서 직접 Firestore에 write한다.
/// 악의적인 관리자가 규칙을 우회하거나, 보안 규칙 미비 시 근무자가 자신의 점수를 조작할 수 있다.
/// 이상적인 구조: Cloud Functions에서 이벤트 기반으로 자동 갱신.
/// 현재 규모에서는 Firestore 보안 규칙으로 auth.uid == userId 이외의 write를
/// 관리자 권한으로만 허용하여 완화. 규모 확장 시 Cloud Functions 이관 권장.
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
        return (userData['trustScore'] as num).toInt();
      }
      
      // trustScore 미설정 구 계정 — 계산 후 Firestore에 저장해 이후 incremental 경로 단일화
      final computed = _computeScore(userData, settings);
      _firestore.collection('users').doc(userId).update({'trustScore': computed}).catchError((e) {
        debugPrint('⚠️ [TrustScore] 구 계정 trustScore 저장 실패 ($userId): $e');
      });
      return computed;
    } catch (e) {
      debugPrint('❌ 신뢰도 계산 실패: $e');
      return 50; // 기본값
    }
  }

  /// 점수 계산 로직 — 단일 공식 원칙
  ///
  /// [TrustScoreHelper.calculateFromData]에 위임해 폴백(오프라인) 경로와
  /// 저장 경로의 공식이 항상 일치하도록 보장한다.
  /// [settings]는 시그니처 호환을 위해 유지하되 공식에는 사용하지 않는다.
  int _computeScore(Map<String, dynamic> userData, TrustSettingsModel settings) {
    return TrustScoreHelper.calculateFromData(
      totalWorkDays: ((userData['totalWorkDays'] ?? 0) as num).toInt(),
      averageRating: ((userData['averageRating'] ?? 0) as num).toDouble(),
      reviewCount: ((userData['reviewCount'] ?? 0) as num).toInt(),
      rehireRate: ((userData['rehireRate'] ?? 0) as num).toDouble(),
      noShowCount: ((userData['noShowCount'] ?? 0) as num).toInt(),
      lateCount: ((userData['lateCount'] ?? 0) as num).toInt(),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 점수 이벤트 처리
  // ═══════════════════════════════════════════════════════════

  /// 근무 완료 시 점수 업데이트
  Future<void> onWorkComplete(String userId, String businessId) async {
    await _updateScore(userId, 'work_complete', isIncrease: true, businessId: businessId);
  }

  /// 마감 취소 시 근무완료 점수 롤백
  Future<void> onWorkCanceled(String userId, String businessId) async {
    final settings = await _getSettings();
    final rule = settings.increaseRules.firstWhere(
      (r) => r.type == 'work_complete',
      orElse: () => TrustRule(type: '', points: 1, description: ''),
    );
    if (rule.points != 0) {
      await _applyScoreChange(userId, -rule.points, '마감 취소', businessId: businessId);
    }
  }

  /// 지각 시 점수 업데이트
  ///
  /// ⚠️ 설계 방침: lateCount 증가와 _updateScore()가 별도 Firestore 작업으로 분리되어 있다.
  /// onNoShow()와 달리 트랜잭션으로 원자화하지 않은 이유:
  ///   - 지각은 노쇼와 달리 "현재 noShowCount 값을 읽어 누진 감점을 결정"하는 로직이 없다.
  ///   - 따라서 increment + read 사이의 TOCTOU 문제가 발생하지 않는다.
  ///   - 단, lateCount 증가 직후 _updateScore()가 실패하면 카운트만 올라가고 점수는 변경되지
  ///     않는 불일치가 발생할 수 있다. _updateScore()는 트랜잭션 내부에서 lateCount가 아닌
  ///     설정 기반 고정 감점을 적용하므로 재시도로 복구 가능하다.
  ///   - 허용된 트레이드오프: 지각 감점 누락(과소 처리)이 실제 발생 확률이 낮고,
  ///     트랜잭션 추가 시 복잡도·비용이 높아 현재 규모에서는 분리 처리가 적절하다.
  Future<void> onLate(String userId, String businessId) async {
    await _firestore.collection('users').doc(userId).update({
      'lateCount': FieldValue.increment(1),
    });
    await _updateScore(userId, 'late', isIncrease: false, businessId: businessId);
  }

  /// 노쇼 시 점수 업데이트
  Future<void> onNoShow(String userId, String businessId) async {
    // [E-001] increment 후 즉시 get하면 Firestore 반영 전 old 값을 읽을 수 있음
    // 트랜잭션으로 increment + read를 원자적으로 처리
    int newNoShowCount = 1;
    final userRef = _firestore.collection('users').doc(userId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final current = ((snap.data()?['noShowCount'] ?? 0) as num).toInt();
      newNoShowCount = current + 1;
      tx.update(userRef, {'noShowCount': newNoShowCount});
    });

    final settings = await _getSettings();
    final penalty = settings.getNoshowPenalty(newNoShowCount);

    await _applyScoreChange(userId, penalty, '노쇼 $newNoShowCount회', businessId: businessId);
  }

  /// 노쇼 해제 시 카운트 감소 + 감점 복원
  Future<void> onNoShowCanceled(String userId, String businessId) async {
    // [I-001] onNoShow()와 동일하게 트랜잭션으로 원자화 (TOCTOU 방지)
    int currentNoShowCount = 1;
    final userRef = _firestore.collection('users').doc(userId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      currentNoShowCount = ((snap.data()?['noShowCount'] ?? 0) as num).toInt();
      final newCount = (currentNoShowCount - 1).clamp(0, 9999);
      tx.update(userRef, {
        'noShowCount': newCount,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    final settings = await _getSettings();
    final penalty = settings.getNoshowPenalty(currentNoShowCount);
    if (penalty < 0) {
      await _applyScoreChange(userId, -penalty, '노쇼 해제', businessId: businessId);
    }
  }

  /// 리뷰 받음 시 점수 업데이트
  Future<void> onReviewReceived(String userId, double rating, bool wouldRehire, String businessId) async {
    final settings = await _getSettings();

    if (rating >= 4.5) {
      final rule = settings.increaseRules
          .firstWhere((r) => r.type == 'good_review',
              orElse: () => TrustRule(type: '', points: 2, description: ''));
      await _applyScoreChange(userId, rule.points, '좋은 평가', businessId: businessId);
    }

    if (rating <= 2.0) {
      final rule = settings.decreaseRules
          .firstWhere((r) => r.type == 'bad_review',
              orElse: () => TrustRule(type: '', points: -2, description: ''));
      await _applyScoreChange(userId, rule.points, '낮은 평가', businessId: businessId);
    }

    if (wouldRehire) {
      final rule = settings.increaseRules
          .firstWhere((r) => r.type == 'rehire_yes',
              orElse: () => TrustRule(type: '', points: 1, description: ''));
      await _applyScoreChange(userId, rule.points, '재고용 희망', businessId: businessId);
    }
  }

  /// 점수 변경 적용
  Future<void> _applyScoreChange(String userId, int change, String reason, {required String businessId}) async {
    try {
      final settings = await _getSettings();

      await _firestore.runTransaction((transaction) async {
        final userRef = _firestore.collection('users').doc(userId);
        final userDoc = await transaction.get(userRef);

        if (!userDoc.exists) return;

        final currentScore = userDoc.data()?['trustScore'] ?? settings.startScore;
        final newScore = (currentScore + change).clamp(0, settings.maxScore);

        transaction.update(userRef, {'trustScore': newScore});

        final historyRef = _firestore.collection('trust_score_history').doc();
        transaction.set(historyRef, {
          'userId': userId,
          'businessId': businessId,
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
  Future<void> _updateScore(String userId, String ruleType, {required bool isIncrease, required String businessId}) async {
    final settings = await _getSettings();

    final rules = isIncrease ? settings.increaseRules : settings.decreaseRules;
    final rule = rules.firstWhere(
      (r) => r.type == ruleType,
      orElse: () => TrustRule(type: '', points: 0, description: ''),
    );

    if (rule.points != 0) {
      await _applyScoreChange(userId, rule.points, rule.description, businessId: businessId);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 재시작 프로그램
  // ═══════════════════════════════════════════════════════════

  /// 재시작 프로그램 신청 가능 여부 (쿨타임 체크 — 클라이언트 표시용)
  Future<({bool canRestart, String? reason, int? daysRemaining})> canApplyRestart(String userId) async {
    try {
      final settings = await _getSettings();
      final userDoc = await _firestore.collection('users').doc(userId).get();
      
      if (!userDoc.exists) {
        return (canRestart: false, reason: '사용자 정보를 찾을 수 없습니다.', daysRemaining: null);
      }
      
      final userData = userDoc.data()!;
      final lastRestartAt = (userData['lastRestartAt'] as Timestamp?)?.toDate().toLocal();
      
      if (lastRestartAt != null) {
        final cooldownEnd = lastRestartAt.add(Duration(days: settings.restartProgram.cooldownDays));
        if (DateTime.now().isBefore(cooldownEnd)) {
          final daysRemaining = cooldownEnd.difference(DateTime.now()).inDays;
          return (
            canRestart: false, 
            reason: '쿨타임 중입니다. $daysRemaining일 후 신청 가능합니다.',
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
  ///
  /// [businessId] 관리자 컨텍스트에서 필수 — 보안 규칙상 소속 사업장 businessId 필터 필요.
  /// isSuperAdmin이 아닌 한 businessId 없이 호출 시 Firestore 권한 오류 발생.
  ///
  /// ⚠️ 미완성 기능 (B03): 서비스 메서드는 구현됐으나 UI 진입점이 없음.
  /// 향후 설정 화면 → "신뢰도 변동 내역 보기"로 연결 예정.
  Future<List<Map<String, dynamic>>> getScoreHistory(
    String userId, {
    String? businessId,
    int limit = 20,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _firestore
          .collection('trust_score_history')
          .where('userId', isEqualTo: userId);
      if (businessId != null && businessId.isNotEmpty) {
        q = q.where('businessId', isEqualTo: businessId);
      }
      final snapshot = await q
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
          'createdAt': (data['createdAt'] as Timestamp?)?.toDate().toLocal(),
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