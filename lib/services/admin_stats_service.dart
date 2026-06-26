import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/core/attendance_model.dart';
import '../models/core/monthly_review_model.dart';

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
  });

  int get totalAttendanceCount => presentCount + lateCount + absentCount;
  double get attendanceRate => totalAttendanceCount == 0
      ? 0
      : presentCount / totalAttendanceCount * 100;
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

    final results = await Future.wait([
      _queryAttendance(ids, yearStart, yearEnd),
      _queryAttendance(ids, prevYearStart, prevYearEnd),
      _queryReviews(ids, year),
      _queryReviews(ids, year - 1),
    ]);

    final thisYearAtt = results[0] as List<AttendanceModel>;
    final prevYearAtt = results[1] as List<AttendanceModel>;
    final thisYearReviews = results[2] as List<MonthlyReviewModel>;
    // ignore: unused_local_variable
    final prevYearReviews = results[3] as List<MonthlyReviewModel>;

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
              ? (r.finalWage ?? 0) : 0));
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
        thisYearAtt.fold<int>(0, (acc, r) => acc + (isPaid(r) ? (r.finalWage ?? 0) : 0));
    final prevYearWage =
        prevYearAtt.fold<int>(0, (acc, r) => acc + (isPaid(r) ? (r.finalWage ?? 0) : 0));
    final workerIds = thisYearAtt.map((r) => r.userId).toSet().length;

    // 출근율
    final attRate = _calcAttendanceRate(thisYearAtt);
    final prevAttRate = _calcAttendanceRate(prevYearAtt);

    // 재고용률 + 평점
    final reviewsWithRehire =
        thisYearReviews.where((r) => r.wouldRehire != null).toList();
    final rehireRate = reviewsWithRehire.isEmpty
        ? 0.0
        : reviewsWithRehire.where((r) => r.wouldRehire == true).length /
            reviewsWithRehire.length *
            100;
    final avgRating = thisYearReviews.isEmpty
        ? 0.0
        : thisYearReviews.map((r) => r.rating).reduce((a, b) => a + b) /
            thisYearReviews.length;

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
        wageTypeMap[r.workType] = (wageTypeMap[r.workType] ?? 0) + (r.finalWage ?? 0);
      }
    }
    final sortedEntries = wageTypeMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
    final wageByWorkType = Map.fromEntries(sortedEntries.take(5));

    // 예외 알림 — 가장 최근 데이터 있는 달 기준
    final exceptionMonth = _latestActiveMonth(monthlyTrends);
    final exceptionRecords = exceptionMonth > 0 ? trendMap[exceptionMonth]! : <AttendanceModel>[];
    final nameMap = await _fetchUserNames(
        exceptionRecords.map((r) => r.userId).toSet().toList());
    final exceptions =
        _buildExceptions(exceptionRecords, nameMap, exceptionMonth);

    return AnnualStatsData(
      year: year,
      filterBusinessId: filterBusinessId,
      totalWage: totalWage,
      totalWorkCount: thisYearAtt.length,
      totalWorkerCount: workerIds,
      prevYearTotalWage: prevYearWage,
      prevYearTotalWorkCount: prevYearAtt.length,
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

    final results = await Future.wait([
      _queryAttendance(ids, start, end),
      _queryMonthReviews(ids, year, month),
    ]);

    final attendance = results[0] as List<AttendanceModel>;
    final reviews = results[1] as List<MonthlyReviewModel>;

    final userIds = attendance.map((r) => r.userId).toSet().toList();
    final infoMap = await _fetchUserInfo(userIds);

    // 직원별 집계
    final workerMap = <String, List<AttendanceModel>>{};
    for (final a in attendance) {
      workerMap.putIfAbsent(a.userId, () => []).add(a);
    }

    final workers = workerMap.entries.map((e) {
      final records = e.value;
      int present = 0, late = 0, absent = 0, wage = 0;
      for (final r in records) {
        switch (r.status) {
          case AttendanceModel.statusPresent:
            present++;
          case AttendanceModel.statusLate:
            late++;
          default:
            absent++;
        }
        if (r.wageStatus == AttendanceModel.wageConfirmed ||
            r.wageStatus == AttendanceModel.wageTransferred) {
          wage += r.finalWage ?? 0;
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

    // 근태 합계
    int tp = 0, tl = 0, ta = 0, tw = 0;
    for (final a in attendance) {
      switch (a.status) {
        case AttendanceModel.statusPresent:
          tp++;
        case AttendanceModel.statusLate:
          tl++;
        default:
          ta++;
      }
      if (a.wageStatus == AttendanceModel.wageConfirmed ||
          a.wageStatus == AttendanceModel.wageTransferred) {
        tw += a.finalWage ?? 0;
      }
    }

    // 리뷰 집계
    final avgRating = reviews.isEmpty
        ? 0.0
        : reviews.map((r) => r.rating).reduce((a, b) => a + b) /
            reviews.length;
    final rehireCount =
        reviews.where((r) => r.wouldRehire == true).length;
    final noRehireCount =
        reviews.where((r) => r.wouldRehire == false).length;

    final posFreq = <String, int>{};
    final impFreq = <String, int>{};
    for (final r in reviews) {
      for (final t in r.positiveTags) { posFreq[t] = (posFreq[t] ?? 0) + 1; }
      for (final t in r.improvementTags) { impFreq[t] = (impFreq[t] ?? 0) + 1; }
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
      posTagFreq: posFreq,
      impTagFreq: impFreq,
      rawAttendance: attendance,
      userInfoMap: infoMap,
    );
  }

  // ── 내부 쿼리 ────────────────────────────────────────────────

  // [D01 설계] limit() 없이 전체 조회: 관리자 통계 화면에서 연간/월별 집계를 위해
  // 기간 내 모든 출근 기록이 필요하다. 사업장당 연간 최대 수천 건 수준으로 예상되므로
  // 현재 규모에서는 허용된 트레이드오프다. 대규모 사업장(수만 건 이상)이 생기면
  // 서버사이드 집계(Cloud Functions + 집계 문서)로 전환을 고려해야 한다.
  // 20초 타임아웃으로 무한 대기 방지.
  Future<List<AttendanceModel>> _queryAttendance(
      List<String> ids, DateTime start, DateTime end) async {
    final results = await Future.wait(ids.map((id) async {
      try {
        final snap = await _db
            .collection('attendance')
            .where('businessId', isEqualTo: id)
            .where('workDate',
                isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('workDate', isLessThan: Timestamp.fromDate(end))
            .get()
            .timeout(const Duration(seconds: 20));
        return snap.docs.map(AttendanceModel.fromFirestore).toList();
      } catch (e) {
        debugPrint('❌ 근태 조회 실패 ($id): $e');
        return <AttendanceModel>[];
      }
    }));
    return results.expand((list) => list).toList();
  }

  Future<List<MonthlyReviewModel>> _queryReviews(
      List<String> ids, int year) async {
    final results = await Future.wait(ids.map((id) async {
      try {
        final snap = await _db
            .collection('monthly_reviews')
            .where('businessId', isEqualTo: id)
            .where('reviewYear', isEqualTo: year)
            .where('reviewType', isEqualTo: 'ADMIN_TO_USER')
            .get()
            .timeout(const Duration(seconds: 20));
        return snap.docs.map(MonthlyReviewModel.fromFirestore).toList();
      } catch (e) {
        debugPrint('⚠️ 연간 리뷰 조회 실패 ($id): $e');
        return <MonthlyReviewModel>[];
      }
    }));
    return results.expand((list) => list).toList();
  }

  Future<List<MonthlyReviewModel>> _queryMonthReviews(
      List<String> ids, int year, int month) async {
    final results = await Future.wait(ids.map((id) async {
      try {
        final snap = await _db
            .collection('monthly_reviews')
            .where('businessId', isEqualTo: id)
            .where('reviewYear', isEqualTo: year)
            .where('reviewMonth', isEqualTo: month)
            .where('reviewType', isEqualTo: 'ADMIN_TO_USER')
            .get()
            .timeout(const Duration(seconds: 20));
        return snap.docs.map(MonthlyReviewModel.fromFirestore).toList();
      } catch (e) {
        debugPrint('⚠️ 월간 리뷰 조회 실패 ($id): $e');
        return <MonthlyReviewModel>[];
      }
    }));
    return results.expand((list) => list).toList();
  }

  Future<Map<String, String>> _fetchUserNames(List<String> ids) async {
    if (ids.isEmpty) return {};
    final map = <String, String>{};
    // 30개 청크를 순차 await — whereIn 30개 제한(QUERY-01) 준수 설계
    // Future.wait로 병렬화 가능하나, 다수 청크 동시 요청 시 Firestore 부하 우려로 순차 유지
    for (int i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, (i + 30).clamp(0, ids.length));
      try {
        final snap = await _db
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .limit(chunk.length)
            .get()
            .timeout(const Duration(seconds: 15));
        for (final doc in snap.docs) {
          map[doc.id] = doc.data()['name'] as String? ?? '알 수 없음';
        }
      } catch (e) {
        debugPrint('⚠️ 사용자 이름 조회 실패: $e');
      }
    }
    return map;
  }

  Future<Map<String, UserInfo>> _fetchUserInfo(List<String> ids) async {
    if (ids.isEmpty) return {};
    final map = <String, UserInfo>{};
    for (int i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, (i + 30).clamp(0, ids.length));
      try {
        final snap = await _db
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .limit(chunk.length)
            .get()
            .timeout(const Duration(seconds: 15));
        for (final doc in snap.docs) {
          final d = doc.data();
          map[doc.id] = UserInfo(
            name: d['name'] as String? ?? '알 수 없음',
            gender: d['gender'] as String?,
            phone: d['phone'] as String?,
          );
        }
      } catch (e) {
        debugPrint('⚠️ 사용자 정보 조회 실패: $e');
      }
    }
    return map;
  }

  // ── 헬퍼 ─────────────────────────────────────────────────────

  double _calcAttendanceRate(List<AttendanceModel> list) {
    if (list.isEmpty) return 0;
    final present =
        list.where((r) => r.status == AttendanceModel.statusPresent).length;
    return present / list.length * 100;
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
          r.status == AttendanceModel.statusNoShow ||
          r.status == AttendanceModel.statusEarlyLeave) {
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
