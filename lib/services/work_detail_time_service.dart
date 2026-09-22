// lib/services/work_detail_time_service.dart
//
// [AH-V2-04A.1] workDetail 실제 근무시간(timeMap) 로더 — 단일 소스.
//
// 이 map은 WorkDetailHelper.effectiveStart/effectiveEnd 의 입력이며,
// 급여 확정(wage_confirm_dialog)과 근태 판정(attendance_status_dialog,
// 관리자 Home)이 같은 "실제 적용 근무시간"을 보도록 보장한다.
//
// 이전에는 AttendanceStatusDialog 안의 private 메서드였다. Home은 이 map을
// 갖지 못해 지원서 원본 시각으로 근태를 판정했고, workDetail override가
// 걸린 근무에서 Home과 Dialog의 시간 경계가 갈릴 수 있었다.
//
// [쿼리 비용] 근로자 수가 아니라 고유 (toId, slotId) 쌍 수에 비례한다.
//   slotPairs → 슬롯 문서 병렬 get
//   slotId 없는 toId → TO 문서 get
//   slotPairs의 toId → TO 마스터 get (workType 단독 폴백 키 보정, ??= 이므로 슬롯값 우선)
//
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/core/application_model.dart';
import '../utils/work_detail_helper.dart';

class WorkDetailTimeService {
  const WorkDetailTimeService._();

  /// [targetWorkers] 기준 workDetail 시간 맵을 로드한다.
  static Future<Map<String, dynamic>> load(List<ApplicationModel> targetWorkers) async {
    final Map<String, dynamic> timeInfoMap = {};


    if (targetWorkers.isEmpty) return timeInfoMap;

    // 고유한 (toId, slotId) 쌍 수집 — 동일 toId에 여러 슬롯 가능하므로 Set으로 보관
    final slotPairs = <String, Set<String>>{}; // toId → Set<slotId>
    final toIds = <String>{};                  // slotId 없는 경우 TO 폴백용
    for (final app in targetWorkers) {
      if (app.toId == null || app.toId!.isEmpty) continue;
      if (app.slotId != null && app.slotId!.isNotEmpty) {
        slotPairs.putIfAbsent(app.toId!, () => {}).add(app.slotId!);
      } else {
        toIds.add(app.toId!);
      }
    }

    void extractFromWorkDetails(List<dynamic> raw) {
      for (var wd in raw) {
        final data = Map<String, dynamic>.from(wd as Map);
        final workType = data['workType'] as String? ?? '';
        // 'HH:mm:ss' → 'HH:mm' 정규화 (레거시 데이터 대응)
        final rawStart = data['startTime'] as String? ?? '';
        final rawEnd = data['endTime'] as String? ?? '';
        final startTime = rawStart.length >= 5 ? rawStart.substring(0, 5) : rawStart;
        final endTime = rawEnd.length >= 5 ? rawEnd.substring(0, 5) : rawEnd;
        if (workType.isEmpty) continue;
        final compositeKey = '${workType}_${startTime}_$endTime';
        final entry = {
          'startTime': startTime,
          'endTime': endTime,
          'wage': data['wage'] ?? 0,
          'wageType': data['wageType'] ?? 'hourly',
          'breakMinutes': data['breakMinutes'] ?? 0,
          'nightAllowanceApplied': data['nightAllowanceApplied'] ?? true,
          'nightIncluded': data['nightIncluded'] ?? false,
          'shiftType': data['shiftType'],
          'baseHourlyWage': (data['baseHourlyWage'] as num?)?.toInt(),
          'weeklyHolidayIncluded': data['weeklyHolidayIncluded'] as bool? ?? false,
          'scheduledDaysPerWeek': (data['scheduledDaysPerWeek'] as num?)?.toInt(),
          'taxDeductionType': data['taxDeductionType'] as String?,
          'payScheduleType': data['payScheduleType'] as String?,
          'payScheduleDay': (data['payScheduleDay'] as num?)?.toInt(),
        };
        timeInfoMap[compositeKey] = entry;
        timeInfoMap[workType] ??= entry; // 레거시 폴백 키 (마지막 값 덮어씀)
      }
    }

    try {
      // 슬롯 문서 병렬 조회 (toId당 여러 슬롯 가능)
      final slotFutures = slotPairs.entries.expand((e) =>
          e.value.map((slotId) => FirebaseFirestore.instance
              .collection('tos').doc(e.key)
              .collection('slots').doc(slotId)
              .get()));
      final slotDocs = await Future.wait(slotFutures);
      for (final doc in slotDocs) {
        if (!doc.exists) continue;
        final raw = doc.data()?['workDetails'] as List<dynamic>?;
        if (raw != null && raw.isNotEmpty) extractFromWorkDetails(raw);
      }

      // slotId 없는 경우 TO 문서 폴백
      if (toIds.isNotEmpty) {
        final toFutures = toIds.map((id) =>
            FirebaseFirestore.instance.collection('tos').doc(id).get());
        final toDocs = await Future.wait(toFutures);
        for (final doc in toDocs) {
          if (!doc.exists) continue;
          final raw = doc.data()?['workDetails'] as List<dynamic>?;
          if (raw != null) extractFromWorkDetails(raw);
        }
      }

      // TO 마스터로 workType 단독 폴백키를 보정한다.
      // 슬롯 문서가 이미 데이터를 채웠으면 덮어쓰지 않음 (??=)
      // → 슬롯 수정 시 TO 마스터(구시간)가 최신 슬롯값을 되돌리는 버그 방지
      //
      // [R8-P10] **아직 풀리지 않은 지원서가 있을 때만** 읽는다.
      //
      //   이전에는 슬롯을 가진 모든 toId 의 마스터를 무조건 한 번 더 읽었다.
      //   DEV 실측에서 그 10회가 맵에 더한 키는 0개였다 — 전체 읽기 25회 중
      //   10회(40%)가 아무것도 바꾸지 않고 왕복만 했다.
      //
      //   이 라운드가 채우는 것은 `timeMap[workType]` 하나뿐이고,
      //   그 키는 WorkDetailHelper._resolveLive 의 **마지막** 폴백이다.
      //   앞의 두 키(복합키·workDetailId)로 이미 풀린 지원서에게는 쓰이지 않는다.
      //   그러니 풀린 지원서만 있으면 읽을 이유가 없다.
      //
      //   슬롯이 없는 지원서는 여기 대상이 아니다 — 그쪽 TO 는 위에서 이미 읽었고,
      //   거기서도 못 찾았다면 이 라운드가 읽을 문서가 같아서 달라지지 않는다.
      final masterIds = <String>{};
      for (final app in targetWorkers) {
        final toId = app.toId;
        if (toId == null || toId.isEmpty) continue;
        if (app.slotId == null || app.slotId!.isEmpty) continue;
        if (!slotPairs.containsKey(toId)) continue;
        if (WorkDetailHelper.resolveLive(app, timeInfoMap) != null) continue;
        masterIds.add(toId);
      }
      if (masterIds.isNotEmpty) {
        final masterFutures = masterIds.map((id) =>
            FirebaseFirestore.instance.collection('tos').doc(id).get());
        final masterDocs = await Future.wait(masterFutures);
        for (final doc in masterDocs) {
          if (!doc.exists) continue;
          final raw = doc.data()?['workDetails'] as List<dynamic>?;
          if (raw == null) continue;
          for (var wd in raw) {
            final data = Map<String, dynamic>.from(wd as Map);
            final workType = data['workType'] as String? ?? '';
            if (workType.isEmpty) continue;
            timeInfoMap[workType] ??= {
              'startTime': data['startTime'] ?? '',
              'endTime': data['endTime'] ?? '',
              'wage': data['wage'] ?? 0,
              'wageType': data['wageType'] ?? 'hourly',
              'breakMinutes': data['breakMinutes'] ?? 0,
              'nightAllowanceApplied': data['nightAllowanceApplied'] ?? true,
              'nightIncluded': data['nightIncluded'] ?? false,
              'shiftType': data['shiftType'],
              'baseHourlyWage': (data['baseHourlyWage'] as num?)?.toInt(),
              'weeklyHolidayIncluded': data['weeklyHolidayIncluded'] as bool? ?? false,
              'scheduledDaysPerWeek': (data['scheduledDaysPerWeek'] as num?)?.toInt(),
              'taxDeductionType': data['taxDeductionType'] as String?,
              'payScheduleType': data['payScheduleType'] as String?,
              'payScheduleDay': (data['payScheduleDay'] as num?)?.toInt(),
            };
          }
        }
      }
    } catch (e) {
      debugPrint('❌ WorkDetail 시간 조회 실패: $e');
    }

    return timeInfoMap;
  }
}
