import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/core/attendance_model.dart';
import 'firestore_service.dart';

// ─── 리뷰 통계 상태 ─────────────────────────────────────────────
// [SECURITY-ADMIN-REVIEW-STATS-AGGREGATE 2026-09-05]
// NO_DATA / SUPPRESSED / UNAVAILABLE 세 가지 상태를 명시적으로 구분.
// nullable bool 2개로 표현하면 불가능한 상태가 생기므로 enum 사용.
enum ReviewStatsState {
  available,    // 쿼리 성공 + reviewCount >= 1 + 미억제
  noData,       // 쿼리 성공 + reviewCount == 0 (또는 초기값)
  suppressed,   // 쿼리 성공 + reviewCount < 3 + wage-only SUB_ADMIN
  unavailable,  // callable 실패 (어느 사업장이라도)
}

// ─── 출근 통계 완전성 상태 ───────────────────────────────────────
// [SECURITY-ADMIN-STATS-ATTENDANCE-COMPLETENESS 2026-09-05]
// AVAILABLE: 모든 사업장 callable 성공 + limitReached=false + 완전한 행 파싱.
// UNAVAILABLE: callable 실패 / limitReached=true / envelope 오류 / 행 파싱 실패.
// 정상 응답 0건도 AVAILABLE — 집계 데이터 없음은 실패가 아님.
enum AttendanceStatsState {
  available,    // 완전하고 신뢰할 수 있는 출근 데이터
  unavailable,  // 부분적이거나 조회 실패한 데이터 — 집계 표시 금지
}

/// 단일 사업장 callableGetMonthlyReviewStatsByBiz 응답 DTO.
/// suppressed=true 시 ratingSum 등 민감 필드는 null.
/// transport 실패와 NO_DATA를 절대 혼동하지 않음 —
/// transport 실패는 throw로 전파, empty()는 reviewCount==0 성공 응답 전용.
class ReviewStatsDto {
  final int reviewCount;
  final bool suppressed;
  final int? ratingSum;
  final int? rehireYesCount;
  final int? rehireNoCount;
  final Map<String, int>? positiveTagCounts;

  const ReviewStatsDto({
    required this.reviewCount,
    required this.suppressed,
    this.ratingSum,
    this.rehireYesCount,
    this.rehireNoCount,
    this.positiveTagCounts,
  });

  /// NO_DATA (reviewCount==0) 성공 응답용 — transport 실패에 사용 금지
  const ReviewStatsDto.empty()
      : reviewCount = 0,
        suppressed = false,
        ratingSum = 0,
        rehireYesCount = 0,
        rehireNoCount = 0,
        positiveTagCounts = const {};

  /// callableGetMonthlyReviewStatsByBiz 응답을 엄격하게 파싱한다.
  /// 필수 키 누락·잘못된 타입·불변식 위반 → FormatException throw.
  /// throw는 호출부의 독립 review try/catch가 ReviewStatsState.unavailable로 매핑.
  /// [SECURITY-MONTHLY-REVIEWS-STATS-DTO-VALIDATION 2026-09-05]
  static ReviewStatsDto fromMap(Map<String, dynamic> m) {
    // ── 공통 필수 키 존재 확인 ──────────────────────────────────────
    if (!m.containsKey('reviewCount')) {
      throw FormatException('ReviewStatsDto: reviewCount 키 누락');
    }
    if (!m.containsKey('suppressed')) {
      throw FormatException('ReviewStatsDto: suppressed 키 누락');
    }

    // ── reviewCount: num, finite, integer, >= 0 ─────────────────────
    final rawCount = m['reviewCount'];
    if (rawCount is! num) {
      throw FormatException(
          'ReviewStatsDto: reviewCount가 num이 아님 (${rawCount.runtimeType})');
    }
    if (!rawCount.isFinite || rawCount != rawCount.toInt()) {
      throw FormatException(
          'ReviewStatsDto: reviewCount 유효하지 않음 ($rawCount)');
    }
    final reviewCount = rawCount.toInt();
    if (reviewCount < 0) {
      throw FormatException('ReviewStatsDto: reviewCount가 음수 ($reviewCount)');
    }

    // ── suppressed: bool only (0/1/null/"true" 등 거부) ────────────
    final rawSuppressed = m['suppressed'];
    if (rawSuppressed is! bool) {
      throw FormatException(
          'ReviewStatsDto: suppressed가 bool이 아님 (${rawSuppressed.runtimeType})');
    }
    final suppressed = rawSuppressed;

    // ── 억제 응답 경로 ──────────────────────────────────────────────
    if (suppressed) {
      // 억제 응답 불변식: reviewCount > 0 (서버 zero-count 수정과 동기)
      if (reviewCount == 0) {
        throw FormatException(
            'ReviewStatsDto: suppressed=true이나 reviewCount=0 (서버 불변식 위반)');
      }
      // 민감 필드는 키 존재 + 명시적 null 필수 (키 누락도 거부)
      for (final key in [
        'ratingSum', 'rehireYesCount', 'rehireNoCount', 'positiveTagCounts',
      ]) {
        if (!m.containsKey(key)) {
          throw FormatException('ReviewStatsDto: suppressed 응답에 $key 키 없음');
        }
        if (m[key] != null) {
          throw FormatException(
              'ReviewStatsDto: suppressed=true이나 $key가 null이 아님');
        }
      }
      return ReviewStatsDto(reviewCount: reviewCount, suppressed: true);
    }

    // ── 미억제 응답 경로 — 로컬 헬퍼로 각 메트릭 검증 ───────────────
    int requireNonNegInt(String key) {
      if (!m.containsKey(key)) {
        throw FormatException('ReviewStatsDto: $key 키 누락');
      }
      final v = m[key];
      if (v is! num) {
        throw FormatException(
            'ReviewStatsDto: $key가 num이 아님 (${v.runtimeType})');
      }
      if (!v.isFinite || v != v.toInt()) {
        throw FormatException('ReviewStatsDto: $key 유효하지 않음 ($v)');
      }
      final i = v.toInt();
      if (i < 0) throw FormatException('ReviewStatsDto: $key가 음수 ($i)');
      return i;
    }

    final ratingSum = requireNonNegInt('ratingSum');
    final rehireYesCount = requireNonNegInt('rehireYesCount');
    final rehireNoCount = requireNonNegInt('rehireNoCount');

    // 재고용 답변 합산 <= 전체 리뷰 수 (wouldRehire=null 허용 설계와 일치)
    if (rehireYesCount + rehireNoCount > reviewCount) {
      throw FormatException(
          'ReviewStatsDto: rehire count 불변식 위반 '
          '(yes=$rehireYesCount + no=$rehireNoCount > count=$reviewCount)');
    }

    // positiveTagCounts: Map, 키=String, 값=non-negative integer
    if (!m.containsKey('positiveTagCounts')) {
      throw FormatException('ReviewStatsDto: positiveTagCounts 키 누락');
    }
    final rawTags = m['positiveTagCounts'];
    if (rawTags is! Map) {
      throw FormatException('ReviewStatsDto: positiveTagCounts가 Map이 아님');
    }
    final positiveTagCounts = <String, int>{};
    for (final entry in rawTags.entries) {
      if (entry.key is! String) {
        throw FormatException(
            'ReviewStatsDto: positiveTagCounts 키가 String이 아님 '
            '(${entry.key.runtimeType})');
      }
      final v = entry.value;
      if (v is! num) {
        throw FormatException(
            'ReviewStatsDto: positiveTagCounts["${entry.key}"] 값이 num이 아님');
      }
      if (!v.isFinite || v != v.toInt()) {
        throw FormatException(
            'ReviewStatsDto: positiveTagCounts["${entry.key}"] 값 유효하지 않음 ($v)');
      }
      final i = v.toInt();
      if (i < 0) {
        throw FormatException(
            'ReviewStatsDto: positiveTagCounts["${entry.key}"] 값이 음수 ($i)');
      }
      positiveTagCounts[entry.key as String] = i;
    }

    // NO_DATA 불변식: reviewCount=0이면 모든 집계는 0/빈맵이어야 함
    if (reviewCount == 0 &&
        (ratingSum != 0 ||
            rehireYesCount != 0 ||
            rehireNoCount != 0 ||
            positiveTagCounts.isNotEmpty)) {
      throw FormatException(
          'ReviewStatsDto: reviewCount=0이나 집계값 존재 (서버 불변식 위반)');
    }

    return ReviewStatsDto(
      reviewCount: reviewCount,
      suppressed: false,
      ratingSum: ratingSum,
      rehireYesCount: rehireYesCount,
      rehireNoCount: rehireNoCount,
      positiveTagCounts: positiveTagCounts,
    );
  }
}

// ─── 데이터 모델 ────────────────────────────────────────────────

class BusinessOption {
  final String id;
  final String name;
  const BusinessOption({required this.id, required this.name});
}

class MonthlyTrend {
  final int year;
  final int month;
  final int workCount;
  final int totalWage;
  final int workerCount;
  const MonthlyTrend({
    required this.year,
    required this.month,
    required this.workCount,
    required this.totalWage,
    required this.workerCount,
  });
}

class WorkerException {
  final String userId;
  final String userName;
  final String businessName;
  final int lateCount;
  final int absentCount;
  const WorkerException({
    required this.userId,
    required this.userName,
    required this.businessName,
    required this.lateCount,
    required this.absentCount,
  });
}

/// Level 1 — 연간 개요
class AnnualStatsData {
  final int year;
  final String? filterBusinessId;

  // 연간 KPI (선택 연도)
  final int totalWage;
  final int totalWorkCount;
  final int totalWorkerCount; // 중복 제거한 인원

  // 전년 대비
  final int prevYearTotalWage;
  final int prevYearTotalWorkCount;

  // 출근율 (연간 누적)
  final double attendanceRate;    // 정시 / 전체 %
  final double prevYearAttendanceRate;

  // 재고용률 (연간 리뷰 기준)
  final double rehireRate;
  final double avgRating;

  // 노쇼율
  final int noShowCount;
  final double noShowRate;       // noShow / 전체 * 100
  final double prevYearNoShowRate;

  // 업무별 인건비 (상위 5개, workType → wage)
  final Map<String, int> wageByWorkType;

  // 월별 추이 (12개월)
  final List<MonthlyTrend> monthlyTrends;

  // 주의 직원 (최근 데이터 있는 달 기준, 지각 2회↑ or 결근 1회↑)
  final List<WorkerException> exceptions;
  final int exceptionMonth; // 예외가 집계된 월

  // 신뢰점수 분포 (userId → trustScore)
  final Map<String, int> workerTrustScores;

  // 리뷰 통계 상태 — NO_DATA / SUPPRESSED / UNAVAILABLE / AVAILABLE
  final ReviewStatsState reviewStatsState;

  // 출근 통계 완전성 상태 — [SECURITY-ADMIN-STATS-ATTENDANCE-COMPLETENESS 2026-09-05]
  final AttendanceStatsState attendanceStatsState;
  final AttendanceStatsState prevAttendanceStatsState;

  const AnnualStatsData({
    required this.year,
    this.filterBusinessId,
    required this.totalWage,
    required this.totalWorkCount,
    required this.totalWorkerCount,
    required this.prevYearTotalWage,
    required this.prevYearTotalWorkCount,
    required this.attendanceRate,
    required this.prevYearAttendanceRate,
    required this.rehireRate,
    required this.avgRating,
    required this.noShowCount,
    required this.noShowRate,
    required this.prevYearNoShowRate,
    required this.wageByWorkType,
    required this.monthlyTrends,
    required this.exceptions,
    required this.exceptionMonth,
    this.workerTrustScores = const {},
    this.reviewStatsState = ReviewStatsState.noData,
    this.attendanceStatsState = AttendanceStatsState.available,
    this.prevAttendanceStatsState = AttendanceStatsState.available,
  });

  double get wageDeltaPct {
    if (prevYearTotalWage == 0) return 0;
    return (totalWage - prevYearTotalWage) / prevYearTotalWage * 100;
  }

  double get workCountDeltaPct {
    if (prevYearTotalWorkCount == 0) return 0;
    return (totalWorkCount - prevYearTotalWorkCount) /
        prevYearTotalWorkCount *
        100;
  }
}

class UserInfo {
  final String name;
  final String? gender;
  final String? phone;
  const UserInfo({required this.name, this.gender, this.phone});
}

/// Level 2 — 월 상세
class WorkerMonthSummary {
  final String userId;
  final String userName;
  final int totalDays;
  final int presentDays;
  final int lateDays;
  final int absentDays;
  final int totalWage;
  final List<AttendanceModel> records;
  const WorkerMonthSummary({
    required this.userId,
    required this.userName,
    required this.totalDays,
    required this.presentDays,
    required this.lateDays,
    required this.absentDays,
    required this.totalWage,
    required this.records,
  });
}

class MonthDetailData {
  final int year;
  final int month;
  final int presentCount;
  final int lateCount;
  final int absentCount;
  final int totalWage;
  final List<WorkerMonthSummary> workers;
  final double avgRating;
  final int rehireCount;
  final int noRehireCount;
  final Map<String, int> posTagFreq;
  final Map<String, int> impTagFreq;
  final List<AttendanceModel> rawAttendance;
  final Map<String, UserInfo> userInfoMap;

  // 리뷰 통계 상태
  final ReviewStatsState reviewStatsState;

  // 출근 통계 완전성 상태 — [SECURITY-ADMIN-STATS-ATTENDANCE-COMPLETENESS 2026-09-05]
  final AttendanceStatsState attendanceStatsState;

  const MonthDetailData({
    required this.year,
    required this.month,
    required this.presentCount,
    required this.lateCount,
    required this.absentCount,
    required this.totalWage,
    required this.workers,
    required this.avgRating,
    required this.rehireCount,
    required this.noRehireCount,
    required this.posTagFreq,
    required this.impTagFreq,
    required this.rawAttendance,
    required this.userInfoMap,
    this.reviewStatsState = ReviewStatsState.noData,
    this.attendanceStatsState = AttendanceStatsState.available,
  });

  int get totalAttendanceCount => presentCount + lateCount + absentCount;
  double get attendanceRate => totalAttendanceCount == 0
      ? 0
      : presentCount / totalAttendanceCount * 100;
}

// ─── 출근 조회 결과 래퍼 ──────────────────────────────────────────
// AdminStatsService 파일 전용 — 외부 노출 금지.
// [SECURITY-ADMIN-STATS-ATTENDANCE-COMPLETENESS 2026-09-05]
class _AttFetchResult {
  final List<AttendanceModel> rows;
  final AttendanceStatsState state;

  const _AttFetchResult({
    required this.rows,
    required this.state,
  });
}

// ─── 서비스 ─────────────────────────────────────────────────────

class AdminStatsService {
  final _db = FirebaseFirestore.instance;

  // ── 사업장 목록 로드 ─────────────────────────────────────────

  Future<List<BusinessOption>> getBusinessOptions(
      List<String> businessIds) async {
    if (businessIds.isEmpty) return [];
    final docs = await Future.wait(
      businessIds.map((id) async {
        try {
          return await _db
              .collection('businesses')
              .doc(id)
              .get()
              .timeout(const Duration(seconds: 15));
        } catch (e) {
          debugPrint('⚠️ 사업장 조회 실패 ($id): $e');
          return null;
        }
      }),
    );
    final options = <BusinessOption>[];
    for (int i = 0; i < businessIds.length; i++) {
      final doc = docs[i];
      if (doc != null && doc.exists) {
        options.add(BusinessOption(
          id: businessIds[i],
          name: doc.data()?['name'] as String? ?? businessIds[i],
        ));
      }
    }
    return options;
  }

  // ── Level 1: 연간 통계 ───────────────────────────────────────

  Future<AnnualStatsData> getAnnualStats({
    required List<String> businessIds,
    String? filterBusinessId,
    required int year,
  }) async {
    try {
      return await _getAnnualStatsInternal(
        businessIds: businessIds,
        filterBusinessId: filterBusinessId,
        year: year,
      ).timeout(const Duration(seconds: 30));
    } catch (e, st) {
      debugPrint('❌ getAnnualStats 실패: $e\n$st');
      return _emptyAnnual(year, filterBusinessId);
    }
  }

  Future<AnnualStatsData> _getAnnualStatsInternal({
    required List<String> businessIds,
    String? filterBusinessId,
    required int year,
  }) async {
    final ids = filterBusinessId != null ? [filterBusinessId] : businessIds;
    if (ids.isEmpty) return _emptyAnnual(year, filterBusinessId);

    final yearStart = DateTime(year, 1, 1);
    final yearEnd = DateTime(year + 1, 1, 1);
    final prevYearStart = DateTime(year - 1, 1, 1);
    final prevYearEnd = DateTime(year, 1, 1);

    // [PERF] 출근 통계 — 병렬 조회 (리뷰 통계와 독립)
    // [SECURITY-ADMIN-STATS-ATTENDANCE-COMPLETENESS 2026-09-05]
    // _fetchAttendanceSafe: 기간 단위 독립 실패 포착 — thisYear 실패 ≠ prevYear 실패
    final attResults = await Future.wait([
      _fetchAttendanceSafe(ids, yearStart, yearEnd),
      _fetchAttendanceSafe(ids, prevYearStart, prevYearEnd),
    ]);

    final thisResult = attResults[0];
    final prevResult = attResults[1];
    final thisYearAtt = thisResult.rows;
    final prevYearAtt = prevResult.rows;
    final attendanceStatsState = thisResult.state;
    final prevAttendanceStatsState = prevResult.state;

    // 월별 집계
    final trendMap = <int, List<AttendanceModel>>{};
    for (int m = 1; m <= 12; m++) { trendMap[m] = []; }
    // Dart DateTime.month는 항상 1~12 — 위 루프에서 전 키 초기화했으므로 !안전
    for (final a in thisYearAtt) { trendMap[a.workDate.month]!.add(a); }

    final monthlyTrends = List.generate(12, (i) {
      final m = i + 1; // 1~12, 위 trendMap 키 범위와 일치 — !안전
      final records = trendMap[m]!;
      final wage = records.fold<int>(0, (acc, r) =>
          acc + ((r.wageStatus == AttendanceModel.wageConfirmed ||
              r.wageStatus == AttendanceModel.wageTransferred)
              ? (r.wageDetail?.effectiveNetWage ?? r.finalWage ?? 0) : 0));
      final workerIds = records.map((r) => r.userId).toSet().length;
      return MonthlyTrend(
        year: year,
        month: m,
        workCount: records.length,
        totalWage: wage,
        workerCount: workerIds,
      );
    });

    // 연간 KPI
    bool isPaid(AttendanceModel r) =>
        r.wageStatus == AttendanceModel.wageConfirmed ||
        r.wageStatus == AttendanceModel.wageTransferred;
    final totalWage =
        thisYearAtt.fold<int>(0, (acc, r) => acc + (isPaid(r) ? (r.wageDetail?.effectiveNetWage ?? r.finalWage ?? 0) : 0));
    final prevYearWage =
        prevYearAtt.fold<int>(0, (acc, r) => acc + (isPaid(r) ? (r.wageDetail?.effectiveNetWage ?? r.finalWage ?? 0) : 0));
    final workerIds = thisYearAtt.map((r) => r.userId).toSet().length;

    // 출근율
    final attRate = _calcAttendanceRate(thisYearAtt);
    final prevAttRate = _calcAttendanceRate(prevYearAtt);

    // 재고용률 + 평점 — 독립 에러 경계 (FAIL-A: 어느 사업장 실패 시 unavailable)
    // 출근/급여 통계는 review 실패에 무관하게 유지됨.
    ReviewStatsState reviewStatsState = ReviewStatsState.noData;
    double rehireRate = 0.0;
    double avgRating = 0.0;
    try {
      final dto = await _queryReviewStatsMerged(ids, year);
      if (dto.suppressed) {
        reviewStatsState = ReviewStatsState.suppressed;
      } else if (dto.reviewCount == 0) {
        reviewStatsState = ReviewStatsState.noData;
      } else {
        reviewStatsState = ReviewStatsState.available;
        avgRating = dto.ratingSum! / dto.reviewCount;
        final denominator = dto.rehireYesCount! + dto.rehireNoCount!;
        rehireRate = denominator == 0
            ? 0.0
            : dto.rehireYesCount! / denominator * 100;
      }
    } catch (e) {
      debugPrint('⚠️ 연간 리뷰 통계 조회 실패: $e');
      reviewStatsState = ReviewStatsState.unavailable;
    }

    // 노쇼율
    final noShowCount = thisYearAtt.where((r) =>
        r.status == AttendanceModel.statusNoShow).length;
    final noShowRate = thisYearAtt.isEmpty ? 0.0 : noShowCount / thisYearAtt.length * 100;
    final prevNoShowCount = prevYearAtt.where((r) =>
        r.status == AttendanceModel.statusNoShow).length;
    final prevNoShowRate = prevYearAtt.isEmpty ? 0.0 : prevNoShowCount / prevYearAtt.length * 100;

    // 업무별 인건비 (workType별 finalWage 합산, 상위 5개)
    // isPaid(confirmed + transferred)만 집계 — totalWage와 동일 기준 적용
    final wageTypeMap = <String, int>{};
    for (final r in thisYearAtt) {
      if (r.workType.isNotEmpty && isPaid(r)) {
        wageTypeMap[r.workType] = (wageTypeMap[r.workType] ?? 0) + (r.wageDetail?.effectiveNetWage ?? r.finalWage ?? 0);
      }
    }
    final sortedEntries = wageTypeMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
    final wageByWorkType = Map.fromEntries(sortedEntries.take(5));

    // 예외 알림 — 가장 최근 데이터 있는 달 기준
    final exceptionMonth = _latestActiveMonth(monthlyTrends);
    final exceptionRecords = exceptionMonth > 0 ? trendMap[exceptionMonth]! : <AttendanceModel>[];

    // 신뢰점수 분포 + 예외 이름 — getUsersBatch를 공유하여 중복 CF 호출 방지
    final workerGrouped = <String, Set<String>>{};
    for (final r in thisYearAtt) {
      if (r.businessId.isNotEmpty) {
        workerGrouped.putIfAbsent(r.businessId, () => {}).add(r.userId);
      }
    }
    final fsService = FirestoreService();
    // [5A.2A] trustScore 시스템 제거 — workerTrustScores는 빈 맵으로 유지 (AnnualStatsData 구조 보존)
    final trustScores = <String, int>{};
    final nameMap = <String, String>{};
    await Future.wait(workerGrouped.entries.map((entry) async {
      try {
        final userMap = await fsService.getUsersBatch(
          entry.value.toList(), businessId: entry.key);
        for (final e in userMap.entries) {
          // trustScore 제거 — trustScores[e.key] = e.value.trustScore 삭제
          nameMap[e.key] = e.value.name.isNotEmpty ? e.value.name : '알 수 없음';
        }
      } catch (e) {
        debugPrint('⚠️ 사용자 조회 실패 (${entry.key}): $e');
      }
    }));

    final exceptions =
        _buildExceptions(exceptionRecords, nameMap, exceptionMonth);

    return AnnualStatsData(
      year: year,
      filterBusinessId: filterBusinessId,
      totalWage: totalWage,
      // [MED-STAT] totalWorkCount: confirmed+transferred만 집계 — totalWage와 동일 기준
      // 이전: thisYearAtt.length (노쇼·pending 포함 → 과대 계상)
      totalWorkCount: thisYearAtt.where(isPaid).length,
      totalWorkerCount: workerIds,
      prevYearTotalWage: prevYearWage,
      prevYearTotalWorkCount: prevYearAtt.where(isPaid).length,
      attendanceRate: attRate,
      prevYearAttendanceRate: prevAttRate,
      rehireRate: rehireRate,
      avgRating: avgRating,
      noShowCount: noShowCount,
      noShowRate: noShowRate,
      prevYearNoShowRate: prevNoShowRate,
      wageByWorkType: wageByWorkType,
      monthlyTrends: monthlyTrends,
      exceptions: exceptions,
      exceptionMonth: exceptionMonth,
      workerTrustScores: trustScores,
      reviewStatsState: reviewStatsState,
      attendanceStatsState: attendanceStatsState,
      prevAttendanceStatsState: prevAttendanceStatsState,
    );
  }

  // ── Level 2: 월 상세 ─────────────────────────────────────────

  Future<MonthDetailData> getMonthDetail({
    required List<String> businessIds,
    String? filterBusinessId,
    required int year,
    required int month,
  }) async {
    final ids = filterBusinessId != null ? [filterBusinessId] : businessIds;
    if (ids.isEmpty) return _emptyDetail(year, month);

    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);

    // 출근 통계 (독립 경로 — review 실패 시에도 유지)
    // [SECURITY-ADMIN-STATS-ATTENDANCE-COMPLETENESS 2026-09-05]
    final attResult = await _fetchAttendanceSafe(ids, start, end);
    final attendance = attResult.rows;
    final attendanceStatsState = attResult.state;

    // 리뷰 통계 독립 에러 경계 (FAIL-A: 어느 사업장 실패 시 unavailable)
    ReviewStatsState reviewStatsState = ReviewStatsState.noData;
    double avgRating = 0.0;
    int rehireCount = 0;
    int noRehireCount = 0;
    Map<String, int> posTagFreq = {};
    try {
      final dto = await _queryMonthReviewStatsMerged(ids, year, month);
      if (dto.suppressed) {
        reviewStatsState = ReviewStatsState.suppressed;
      } else if (dto.reviewCount == 0) {
        reviewStatsState = ReviewStatsState.noData;
      } else {
        reviewStatsState = ReviewStatsState.available;
        avgRating = dto.ratingSum! / dto.reviewCount;
        rehireCount = dto.rehireYesCount ?? 0;
        noRehireCount = dto.rehireNoCount ?? 0;
        posTagFreq = dto.positiveTagCounts ?? {};
      }
    } catch (e) {
      debugPrint('⚠️ 월 리뷰 통계 조회 실패: $e');
      reviewStatsState = ReviewStatsState.unavailable;
    }

    final infoMap = await _fetchUserInfoByRecords(attendance);

    // (userId, workDate) 기준 중복 제거 — 동일 근무자·날짜 문서가 2개 이상이면 이중 계산 방지
    final seen = <String>{};
    final dedupedAttendance = attendance.where((a) {
      final key = '${a.userId}_${a.workDate.millisecondsSinceEpoch}';
      return seen.add(key);
    }).toList();

    // 직원별 집계
    final workerMap = <String, List<AttendanceModel>>{};
    for (final a in dedupedAttendance) {
      workerMap.putIfAbsent(a.userId, () => []).add(a);
    }

    final workers = workerMap.entries.map((e) {
      final records = e.value;
      int present = 0, late = 0, absent = 0, wage = 0;
      for (final r in records) {
        switch (r.status) {
          case AttendanceModel.statusPresent:
          case AttendanceModel.statusEarlyLeave:
            present++;
          case AttendanceModel.statusLate:
            late++;
          default:
            absent++;
        }
        if (r.wageStatus == AttendanceModel.wageConfirmed ||
            r.wageStatus == AttendanceModel.wageTransferred) {
          wage += r.wageDetail?.effectiveNetWage ?? r.finalWage ?? 0;
        }
      }
      return WorkerMonthSummary(
        userId: e.key,
        userName: infoMap[e.key]?.name ?? '알 수 없음',
        totalDays: records.length,
        presentDays: present,
        lateDays: late,
        absentDays: absent,
        totalWage: wage,
        records: records..sort((a, b) => a.workDate.compareTo(b.workDate)),
      );
    }).toList()
      ..sort((a, b) => b.totalDays.compareTo(a.totalDays));

    // 근태 합계 (직원별 집계와 동일 기준: dedupedAttendance + earlyLeave = present)
    int tp = 0, tl = 0, ta = 0, tw = 0;
    for (final a in dedupedAttendance) {
      switch (a.status) {
        case AttendanceModel.statusPresent:
        case AttendanceModel.statusEarlyLeave:
          tp++;
        case AttendanceModel.statusLate:
          tl++;
        default:
          ta++;
      }
      if (a.wageStatus == AttendanceModel.wageConfirmed ||
          a.wageStatus == AttendanceModel.wageTransferred) {
        tw += a.wageDetail?.effectiveNetWage ?? a.finalWage ?? 0;
      }
    }

    return MonthDetailData(
      year: year,
      month: month,
      presentCount: tp,
      lateCount: tl,
      absentCount: ta,
      totalWage: tw,
      workers: workers,
      avgRating: avgRating,
      rehireCount: rehireCount,
      noRehireCount: noRehireCount,
      posTagFreq: posTagFreq,
      // [SECURITY-ADMIN-REVIEW-STATS-AGGREGATE] impTagFreq: active consumer 없음
      // 신규 aggregate 엔드포인트에서 미반환. 기존 모델 필드는 유지 (구조 변경 최소화).
      impTagFreq: const {},
      rawAttendance: attendance,
      userInfoMap: infoMap,
      reviewStatsState: reviewStatsState,
      attendanceStatsState: attendanceStatsState,
    );
  }

  // ── 내부 쿼리 ────────────────────────────────────────────────

  // [D01 → CF 이전] 관리자 통계용 출근 기록 조회 — callableGetAdminAttendances CF 경유.
  // attendance allow list: if false 이후 Admin SDK 서버사이드 처리로 전환.
  // 사업장별 병렬 CF 호출 (기존 병렬 Firestore 쿼리 패턴 유지).
  // [SECURITY-ADMIN-STATS-ATTENDANCE-COMPLETENESS 2026-09-05]
  // fail-closed: per-business catch 제거 — 어느 사업장이라도 실패하면 throw 전파.
  // 엄격한 envelope 검증 + limitReached fail-closed + 행 파싱 fail-closed.
  Future<List<AttendanceModel>> _queryAttendance(
      List<String> ids, DateTime start, DateTime end) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableGetAdminAttendances',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
    final results = await Future.wait(ids.map((id) async {
      // per-business catch 없음 — 실패 시 Future.wait가 throw, 기간 전체 UNAVAILABLE
      final result = await callable.call<Map<String, dynamic>>({
        'businessId': id,
        'startMs': start.millisecondsSinceEpoch,
        'endMs': end.millisecondsSinceEpoch,
      });

      // ── 엄격한 응답 envelope 검증 (기본값 ?? [] / ?? false 금지) ──────
      final data = result.data;
      if (!data.containsKey('items')) {
        throw StateError(
            'callableGetAdminAttendances: items 키 누락 (bizId=$id)');
      }
      final rawItems = data['items'];
      if (rawItems is! List) {
        throw StateError(
            'callableGetAdminAttendances: items가 List가 아님 (bizId=$id)');
      }
      if (!data.containsKey('limitReached')) {
        throw StateError(
            'callableGetAdminAttendances: limitReached 키 누락 (bizId=$id)');
      }
      final rawLimitReached = data['limitReached'];
      if (rawLimitReached is! bool) {
        throw StateError(
            'callableGetAdminAttendances: limitReached가 bool이 아님 (bizId=$id)');
      }

      // ── limitReached fail-closed (LIMIT-A) ────────────────────────
      if (rawLimitReached) {
        throw StateError(
            '출근 기록 한계(10,000건) 초과 — 완전한 집계 불가 (bizId=$id)');
      }

      // ── 행 파싱 fail-closed (ROW-A) ──────────────────────────────
      final parsed = <AttendanceModel>[];
      for (final e in rawItems) {
        final m = Map<String, dynamic>.from(e as Map);
        final docId = m.remove('id') as String? ?? '';
        final model = AttendanceModel.tryFromMap(m, docId);
        if (model == null) {
          throw StateError(
              '출근 기록 파싱 실패 (bizId=$id, docId=$docId)');
        }
        parsed.add(model);
      }
      return parsed;
    }));
    return results.expand((list) => list).toList();
  }

  /// 기간 단위 출근 조회 — throw를 AttendanceStatsState.unavailable 로 변환.
  /// annual: Future.wait([_fetchAttendanceSafe, _fetchAttendanceSafe])로 양 기간 독립 실패 지원.
  /// [SECURITY-ADMIN-STATS-ATTENDANCE-COMPLETENESS 2026-09-05]
  Future<_AttFetchResult> _fetchAttendanceSafe(
      List<String> ids, DateTime start, DateTime end) async {
    try {
      final rows = await _queryAttendance(ids, start, end);
      return _AttFetchResult(
          rows: rows, state: AttendanceStatsState.available);
    } catch (e) {
      debugPrint('⚠️ 출근 조회 실패 ($start~$end): $e');
      return const _AttFetchResult(
          rows: [], state: AttendanceStatsState.unavailable);
    }
  }

  // [SECURITY-ADMIN-REVIEW-STATS-AGGREGATE 2026-09-05]
  // aggregate 전용 — 개별 리뷰 행 미반환.
  // FAIL-A: per-business catch 없음 — 어느 사업장이라도 실패하면 전파.
  // 호출부는 독립 try/catch로 감싸 출근 통계를 보존함.
  Future<ReviewStatsDto> _queryReviewStatsMerged(
      List<String> ids, int year) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableGetMonthlyReviewStatsByBiz',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)));
    final dtos = await Future.wait(ids.map((id) async {
      // per-business catch 없음 (FAIL-A)
      final result = await callable.call({
        'businessId': id,
        'reviewYear': year,
      });
      return ReviewStatsDto.fromMap(
          Map<String, dynamic>.from(result.data as Map));
    }));
    return _mergeReviewStats(dtos);
  }

  Future<ReviewStatsDto> _queryMonthReviewStatsMerged(
      List<String> ids, int year, int month) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableGetMonthlyReviewStatsByBiz',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)));
    final dtos = await Future.wait(ids.map((id) async {
      // per-business catch 없음 (FAIL-A)
      final result = await callable.call({
        'businessId': id,
        'reviewYear': year,
        'reviewMonth': month,
      });
      return ReviewStatsDto.fromMap(
          Map<String, dynamic>.from(result.data as Map));
    }));
    return _mergeReviewStats(dtos);
  }

  /// 다중 사업장 집계 merge.
  /// suppression-aware: 어느 하나라도 suppressed → 전체 suppressed.
  /// 빈 list → ReviewStatsDto.empty() (idempotent).
  ReviewStatsDto _mergeReviewStats(List<ReviewStatsDto> dtos) {
    if (dtos.isEmpty) return const ReviewStatsDto.empty();
    // suppression-aware: any suppressed → merged suppressed
    // (현재 SUB_ADMIN=단일 사업장이므로 list는 항상 1개.
    //  [FUTURE-PRIV-NOTE] 다중 SUB_ADMIN 도입 시 suppression 재검토 필요)
    if (dtos.any((d) => d.suppressed)) {
      return ReviewStatsDto(
        reviewCount: dtos.fold(0, (s, d) => s + d.reviewCount),
        suppressed: true,
      );
    }
    final totalCount = dtos.fold(0, (s, d) => s + d.reviewCount);
    final totalRatingSum = dtos.fold(0, (s, d) => s + (d.ratingSum ?? 0));
    final totalYes = dtos.fold(0, (s, d) => s + (d.rehireYesCount ?? 0));
    final totalNo = dtos.fold(0, (s, d) => s + (d.rehireNoCount ?? 0));
    final mergedTags = <String, int>{};
    for (final d in dtos) {
      for (final e in (d.positiveTagCounts ?? {}).entries) {
        mergedTags[e.key] = (mergedTags[e.key] ?? 0) + e.value;
      }
    }
    return ReviewStatsDto(
      reviewCount: totalCount,
      suppressed: false,
      ratingSum: totalRatingSum,
      rehireYesCount: totalYes,
      rehireNoCount: totalNo,
      positiveTagCounts: mergedTags,
    );
  }

  /// FirestoreService.getUsersBatch를 통해 이름·성별·전화번호 조회 (캐시 공유)
  /// attendance 레코드로부터 (businessId → userIds) 그룹핑 후 각 사업장별 조회
  Future<Map<String, UserInfo>> _fetchUserInfoByRecords(
      List<AttendanceModel> records) async {
    if (records.isEmpty) return {};
    final map = <String, UserInfo>{};

    final grouped = <String, Set<String>>{};
    for (final r in records) {
      if (r.businessId.isNotEmpty) {
        grouped.putIfAbsent(r.businessId, () => {}).add(r.userId);
      }
    }

    final fsService = FirestoreService();
    await Future.wait(grouped.entries.map((entry) async {
      try {
        final userMap = await fsService.getUsersBatch(
          entry.value.toList(),
          businessId: entry.key,
        );
        for (final e in userMap.entries) {
          map[e.key] = UserInfo(
            name: e.value.name.isNotEmpty ? e.value.name : '알 수 없음',
            gender: e.value.gender,
            phone: e.value.effectivePhone,
          );
        }
      } catch (e) {
        debugPrint('⚠️ 사용자 정보 조회 실패 (${entry.key}): $e');
      }
    }));
    return map;
  }

  // ── 헬퍼 ─────────────────────────────────────────────────────

  double _calcAttendanceRate(List<AttendanceModel> list) {
    if (list.isEmpty) return 0;
    // [MED-STAT] 출근율 = (정시출근 + 지각 + 조퇴) / 전체 — 지각·조퇴도 "출근"으로 집계
    // 이전: statusPresent만 분자 → 지각이 많은 사업장에서 출근율 과소 집계
    // [STAT-FIX] earlyLeave도 출근 인정 — badge_service/work_applicants_dialog와 동일 기준
    final attended = list.where((r) =>
        r.status == AttendanceModel.statusPresent ||
        r.status == AttendanceModel.statusLate ||
        r.status == AttendanceModel.statusEarlyLeave).length;
    return attended / list.length * 100;
  }

  int _latestActiveMonth(List<MonthlyTrend> trends) {
    for (int m = trends.length; m >= 1; m--) {
      if (trends[m - 1].workCount > 0) return m;
    }
    return 0;
  }

  List<WorkerException> _buildExceptions(List<AttendanceModel> records,
      Map<String, String> nameMap, int month) {
    if (records.isEmpty) return [];
    final lateMap = <String, int>{};
    final absentMap = <String, int>{};
    final bizMap = <String, String>{};
    for (final r in records) {
      bizMap[r.userId] = r.businessName;
      if (r.status == AttendanceModel.statusLate) {
        lateMap[r.userId] = (lateMap[r.userId] ?? 0) + 1;
      } else if (r.status == AttendanceModel.statusAbsent ||
          r.status == AttendanceModel.statusNoShow) {
        // [STAT-FIX] earlyLeave 제거 — 조퇴는 출근으로 인정, absent/noShow만 결근 집계
        absentMap[r.userId] = (absentMap[r.userId] ?? 0) + 1;
      }
    }
    final allIds = {...lateMap.keys, ...absentMap.keys};
    return allIds
        .where((id) => (lateMap[id] ?? 0) >= 2 || (absentMap[id] ?? 0) >= 1)
        .map((id) => WorkerException(
              userId: id,
              userName: nameMap[id] ?? '알 수 없음',
              businessName: bizMap[id] ?? '',
              lateCount: lateMap[id] ?? 0,
              absentCount: absentMap[id] ?? 0,
            ))
        .toList()
      ..sort((a, b) =>
          (b.lateCount + b.absentCount * 2)
              .compareTo(a.lateCount + a.absentCount * 2));
  }

  AnnualStatsData _emptyAnnual(int year, String? bizId) => AnnualStatsData(
        year: year,
        filterBusinessId: bizId,
        totalWage: 0,
        totalWorkCount: 0,
        totalWorkerCount: 0,
        prevYearTotalWage: 0,
        prevYearTotalWorkCount: 0,
        attendanceRate: 0,
        prevYearAttendanceRate: 0,
        rehireRate: 0,
        avgRating: 0,
        noShowCount: 0,
        noShowRate: 0,
        prevYearNoShowRate: 0,
        wageByWorkType: {},
        monthlyTrends: List.generate(
            12,
            (i) => MonthlyTrend(
                year: year,
                month: i + 1,
                workCount: 0,
                totalWage: 0,
                workerCount: 0)),
        exceptions: [],
        exceptionMonth: 0,
        attendanceStatsState: AttendanceStatsState.unavailable,
        prevAttendanceStatsState: AttendanceStatsState.unavailable,
      );

  MonthDetailData _emptyDetail(int year, int month) => MonthDetailData(
        year: year,
        month: month,
        presentCount: 0,
        lateCount: 0,
        absentCount: 0,
        totalWage: 0,
        workers: [],
        avgRating: 0,
        rehireCount: 0,
        noRehireCount: 0,
        posTagFreq: {},
        impTagFreq: {},
        rawAttendance: [],
        userInfoMap: {},
      );
}
