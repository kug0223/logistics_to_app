import 'package:cloud_firestore/cloud_firestore.dart';

/// 근로자 근무 가능일 모델
///
/// Firestore 경로: worker_availability/{uid}
///
/// 설계 원칙 (Phase 8.0 D-02/D-03/D-04):
///   · 날짜(full day) 단위 — "YYYY-MM-DD" KST 기준
///   · 최대 60개, today~today+90일 이내만
///   · 시간대/BOOKED/status 필드 없음 — availability와 application은 독립 domain
///   · admin direct read 없음 — CF callableGetAvailableWorkers 경유
class WorkerAvailabilityModel {
  final String uid;

  /// "YYYY-MM-DD" 형식 날짜 배열 (KST 기준).
  /// 최대 60개, today~today+90일 이내. 정렬 순서 보장하지 않음.
  final List<String> dates;

  /// homeRegion.city 복사값 (쿼리 인덱스용).
  /// Firestore에서 city 기반 candidate 조회 시 사용.
  final String city;

  /// homeRegion.district 복사값 (선택). 2차 필터용.
  final String? district;

  final DateTime? updatedAt;

  const WorkerAvailabilityModel({
    required this.uid,
    required this.dates,
    required this.city,
    this.district,
    this.updatedAt,
  });

  // ─── 날짜 키 헬퍼 ────────────────────────────────────────────
  // CalendarHelper._dateKey()와 동일 포맷: 'YYYY-MM-DD'
  // KST = UTC+9 수동 오프셋 (FormatHelper._toKst 패턴 재사용)

  /// DateTime → "YYYY-MM-DD" dateKey (KST 기준)
  static String dateKeyFrom(DateTime d) {
    final kst = d.toUtc().add(const Duration(hours: 9));
    return '${kst.year}-'
        '${kst.month.toString().padLeft(2, '0')}-'
        '${kst.day.toString().padLeft(2, '0')}';
  }

  /// 오늘(KST) dateKey
  static String todayKey() => dateKeyFrom(DateTime.now());

  /// 오늘 + 90일(KST) dateKey (inclusive upper bound)
  static String maxKey() =>
      dateKeyFrom(DateTime.now().add(const Duration(days: 90)));

  /// 저장/표시 유효 날짜 필터:
  ///   today 이상 && today+90 이하 만 허용.
  ///   결과 오름차순 정렬.
  static List<String> filterValidDates(List<String> dates) {
    final today = todayKey();
    final limit = maxKey();
    final valid = dates
        .where((d) => d.compareTo(today) >= 0 && d.compareTo(limit) <= 0)
        .toList()
      ..sort();
    // 60개 초과 시 가장 최근 60개만 (FIFO: 앞부분 제거)
    return valid.length > 60 ? valid.sublist(valid.length - 60) : valid;
  }

  // ─── 역직렬화 ─────────────────────────────────────────────────

  static WorkerAvailabilityModel? tryFromMap(
    Object? raw, {
    required String uid,
  }) {
    if (raw is! Map) return null;
    try {
      final datesRaw = raw['dates'];
      final dates = datesRaw is List
          ? datesRaw.whereType<String>().toList()
          : <String>[];
      final city = raw['city'] as String?;
      if (city == null || city.isEmpty) return null;

      DateTime? updatedAt;
      final ts = raw['updatedAt'];
      if (ts is Timestamp) updatedAt = ts.toDate();

      return WorkerAvailabilityModel(
        uid: (raw['uid'] as String?) ?? uid,
        dates: dates,
        city: city,
        district: raw['district'] as String?,
        updatedAt: updatedAt,
      );
    } catch (_) {
      return null;
    }
  }

  static WorkerAvailabilityModel? tryFromFirestore(DocumentSnapshot doc) {
    if (!doc.exists) return null;
    return tryFromMap(doc.data(), uid: doc.id);
  }

  // ─── 직렬화 (AvailabilityService.saveAvailability에서 직접 쓰기) ──
  // toMap은 서비스에서 필드를 직접 구성하므로 참고용 제공

  Map<String, dynamic> toSaveMap() => {
    'uid': uid,
    'dates': dates,
    'city': city,
    if (district != null && district!.isNotEmpty) 'district': district,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  // ─── 편의 게터 ────────────────────────────────────────────────

  bool get isEmpty => dates.isEmpty;
  int get count => dates.length;

  /// O(1) 날짜 조회용 Set
  Set<String> get dateSet => Set<String>.from(dates);

  @override
  String toString() =>
      'WorkerAvailabilityModel(uid=$uid, city=$city, dates=${dates.length}개)';
}
