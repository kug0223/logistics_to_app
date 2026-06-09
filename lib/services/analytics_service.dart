import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// AlFit Firebase Analytics 서비스
///
/// 이벤트 네이밍: snake_case, 40자 이하 (Firebase 제한)
/// 파라미터 네이밍: snake_case, 40자 이하, 최대 25개/이벤트
class AnalyticsService {
  AnalyticsService._();

  static final _fa = FirebaseAnalytics.instance;

  /// NavigatorObserver — MaterialApp navigatorObservers에 추가
  static FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _fa);

  // ══════════════════════════════════════════════════════
  // 사용자 속성
  // ══════════════════════════════════════════════════════

  /// 로그인 성공 후 사용자 ID·역할 설정
  static Future<void> setUser({
    required String uid,
    required String role, // 'USER' | 'BUSINESS_ADMIN' | 'SUPER_ADMIN'
  }) async {
    if (kDebugMode) return;
    await _fa.setUserId(id: uid);
    await _fa.setUserProperty(name: 'user_role', value: role);
  }

  /// 로그아웃 시 사용자 초기화
  static Future<void> clearUser() async {
    if (kDebugMode) return;
    await _fa.setUserId(id: null);
  }

  // ══════════════════════════════════════════════════════
  // 인증 이벤트
  // ══════════════════════════════════════════════════════

  static Future<void> logLogin(String role) async {
    if (kDebugMode) return;
    await _fa.logLogin(loginMethod: role);
  }

  static Future<void> logSignUp(String role) async {
    if (kDebugMode) return;
    await _fa.logSignUp(signUpMethod: role);
  }

  // ══════════════════════════════════════════════════════
  // 공고(TO) 이벤트
  // ══════════════════════════════════════════════════════

  /// 공고 상세 조회
  static Future<void> logTOView({
    required String toId,
    required String businessName,
    required String toType, // 'flex' | 'contract'
  }) async {
    if (kDebugMode) return;
    await _fa.logViewItem(
      items: [
        AnalyticsEventItem(
          itemId: toId,
          itemName: businessName,
          itemCategory: toType,
        ),
      ],
    );
  }

  /// 공고 등록
  static Future<void> logTOCreate({required String toType}) async {
    if (kDebugMode) return;
    await _fa.logEvent(
      name: 'to_create',
      parameters: {'to_type': toType},
    );
  }

  // ══════════════════════════════════════════════════════
  // 지원 이벤트
  // ══════════════════════════════════════════════════════

  /// 지원 완료
  static Future<void> logApply({
    required String toId,
    required String businessName,
    required String workType,
    required String appType, // 'short' | 'long_term'
  }) async {
    if (kDebugMode) return;
    await _fa.logEvent(
      name: 'application_submit',
      parameters: {
        'to_id': toId,
        'business_name': businessName,
        'work_type': workType,
        'app_type': appType,
      },
    );
  }

  /// 지원 취소
  static Future<void> logCancel({required String reason}) async {
    if (kDebugMode) return;
    await _fa.logEvent(
      name: 'application_cancel',
      parameters: {'reason': reason},
    );
  }

  /// 확정 처리 (관리자)
  static Future<void> logConfirm({required String appType}) async {
    if (kDebugMode) return;
    await _fa.logEvent(
      name: 'application_confirm',
      parameters: {'app_type': appType},
    );
  }

  // ══════════════════════════════════════════════════════
  // 출퇴근 이벤트
  // ══════════════════════════════════════════════════════

  /// 출근 체크
  static Future<void> logCheckIn({required String method}) async {
    if (kDebugMode) return;
    await _fa.logEvent(
      name: 'attendance_check_in',
      parameters: {'method': method}, // 'gps' | 'beacon' | 'both' | 'manual'
    );
  }

  /// 퇴근 체크
  static Future<void> logCheckOut({required String method}) async {
    if (kDebugMode) return;
    await _fa.logEvent(
      name: 'attendance_check_out',
      parameters: {'method': method},
    );
  }

  // ══════════════════════════════════════════════════════
  // 급여 이벤트
  // ══════════════════════════════════════════════════════

  /// 급여 확정
  static Future<void> logWageConfirm({required int workerCount}) async {
    if (kDebugMode) return;
    await _fa.logEvent(
      name: 'wage_confirm',
      parameters: {'worker_count': workerCount},
    );
  }

  // ══════════════════════════════════════════════════════
  // 검색·필터 이벤트
  // ══════════════════════════════════════════════════════

  /// 공고 검색/필터 적용
  static Future<void> logSearch({
    String? city,
    String? toType,
  }) async {
    if (kDebugMode) return;
    await _fa.logSearch(
      searchTerm: [city, toType].whereType<String>().join(','),
    );
  }

  // ══════════════════════════════════════════════════════
  // 오류 이벤트
  // ══════════════════════════════════════════════════════

  /// 기능 오류 (Crashlytics 외 분석용)
  static Future<void> logError({
    required String feature,
    required String errorCode,
  }) async {
    if (kDebugMode) return;
    await _fa.logEvent(
      name: 'feature_error',
      parameters: {
        'feature': feature,
        'error_code': errorCode,
      },
    );
  }
}
