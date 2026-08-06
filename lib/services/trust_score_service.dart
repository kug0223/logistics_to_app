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
      final results = await Future.wait([
        _getSettings(),
        _firestore.collection('users').doc(userId).get(),
      ]);
      final settings = results[0] as TrustSettingsModel;
      final userDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>;
      
      if (!userDoc.exists) return settings.startScore;
      
      final userData = userDoc.data()!;
      
      // 저장된 신뢰도가 있으면 반환
      if (userData['trustScore'] != null) {
        return (userData['trustScore'] as num).toInt();
      }
      
      // trustScore 미설정 구 계정 — 표시용으로만 계산 (CF Admin SDK 전용 필드, 클라이언트 write 차단)
      return _computeScore(userData, settings);
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

  // ═══════════════════════════════════════════════════════════
  // 재시작 프로그램
  // ═══════════════════════════════════════════════════════════

  /// 재시작 프로그램 신청 가능 여부 (쿨타임 체크 — 클라이언트 표시용)
  Future<({bool canRestart, String? reason, int? daysRemaining})> canApplyRestart(String userId) async {
    try {
      final results = await Future.wait([
        _getSettings(),
        _firestore.collection('users').doc(userId).get(),
      ]);
      final settings = results[0] as TrustSettingsModel;
      final userDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>;
      
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
      
      // 문서 미존재 시 클라이언트 set() 금지 — settings 쓰기는 isSuperAdmin() 전용 (PERMISSION_DENIED 방지)
      if (!doc.exists) {
        _cachedSettings = TrustSettingsModel.defaults();
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