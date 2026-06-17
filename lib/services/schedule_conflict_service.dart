// lib/services/schedule_conflict_service.dart

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/core/application_model.dart';
import '../models/core/work_detail_model.dart';

/// 시간 충돌 레벨
enum ConflictLevel {
  /// 충돌 없음 - 선택 가능
  ok,
  
  /// 시간이 딱 붙음 (이전 종료 = 현재 시작) - 경고 표시, 선택 가능
  warning,
  
  /// 시간 겹침 + 확정됨 - 선택 불가
  blocked,
}

/// 충돌 정보 모델
class ConflictInfo {
  final ConflictLevel level;
  final String? businessName;      // 충돌하는 사업장명
  final String? conflictTime;      // 충돌 시간대 (예: "09:00~14:00")
  final String? message;           // 표시할 메시지

  const ConflictInfo({
    required this.level,
    this.businessName,
    this.conflictTime,
    this.message,
  });

  /// 충돌 없음
  static const ConflictInfo ok = ConflictInfo(level: ConflictLevel.ok);

  /// 충돌 여부
  bool get hasConflict => level != ConflictLevel.ok;
  
  /// 선택 가능 여부
  bool get canSelect => level != ConflictLevel.blocked;
}

/// 시간 충돌 체크 서비스
class ScheduleConflictService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ═══════════════════════════════════════════════════════════
  // 메인 충돌 체크
  // ═══════════════════════════════════════════════════════════

  /// 특정 날짜/시간대에 대해 충돌 체크
  /// 
  /// [uid] 사용자 UID
  /// [workDate] 근무 날짜
  /// [startTime] 시작 시간 (예: "09:00")
  /// [endTime] 종료 시간 (예: "14:00")
  /// 
  /// 반환: ConflictInfo (충돌 레벨 + 상세 정보)
  Future<ConflictInfo> checkConflict({
    required String uid,
    required DateTime workDate,
    required String startTime,
    required String endTime,
  }) async {
    try {
      // 1. 해당 날짜의 확정된 근무 조회
      final confirmedSchedules = await _getConfirmedSchedules(
        uid: uid,
        workDate: workDate,
      );

      if (confirmedSchedules.isEmpty) {
        return ConflictInfo.ok;
      }

      // 2. 각 확정된 근무와 비교
      for (final schedule in confirmedSchedules) {
        final conflictLevel = _checkTimeConflict(
          existingStart: schedule.startTime,
          existingEnd: schedule.endTime,
          newStart: startTime,
          newEnd: endTime,
        );

        if (conflictLevel == ConflictLevel.blocked) {
          return ConflictInfo(
            level: ConflictLevel.blocked,
            businessName: schedule.businessName,
            conflictTime: '${schedule.startTime}~${schedule.endTime}',
            message: '${schedule.startTime}~${schedule.endTime} 확정 근무 (${schedule.businessName})와 시간 충돌',
          );
        }

        if (conflictLevel == ConflictLevel.warning) {
          return ConflictInfo(
            level: ConflictLevel.warning,
            businessName: schedule.businessName,
            conflictTime: '${schedule.startTime}~${schedule.endTime}',
            message: '이전 근무(~${schedule.endTime}) 종료 직후입니다. 이동 시간을 고려하세요.',
          );
        }
      }

      return ConflictInfo.ok;
    } catch (e) {
      debugPrint('❌ 충돌 체크 실패: $e');
      // 에러 시 경고 반환 (ok 반환 시 실제 충돌을 묵인할 수 있음)
      return ConflictInfo(
        level: ConflictLevel.warning,
        message: '충돌 여부를 확인할 수 없습니다. 관리자에게 문의하세요.',
      );
    }
  }

  /// 여러 업무에 대해 한번에 충돌 체크
  /// 
  /// 반환: `Map<workDetailId, ConflictInfo>`
  Future<Map<String, ConflictInfo>> checkConflictsForWorkDetails({
    required String uid,
    required DateTime workDate,
    required List<WorkDetailModel> workDetails,
  }) async {
    final results = <String, ConflictInfo>{};

    try {
      // 해당 날짜의 확정된 근무 한번만 조회
      final confirmedSchedules = await _getConfirmedSchedules(
        uid: uid,
        workDate: workDate,
      );

      for (final work in workDetails) {
        if (confirmedSchedules.isEmpty) {
          results[work.id] = ConflictInfo.ok;
          continue;
        }

        ConflictInfo? worstConflict;

        for (final schedule in confirmedSchedules) {
          final conflictLevel = _checkTimeConflict(
            existingStart: schedule.startTime,
            existingEnd: schedule.endTime,
            newStart: work.startTime,
            newEnd: work.endTime,
          );

          if (conflictLevel == ConflictLevel.blocked) {
            worstConflict = ConflictInfo(
              level: ConflictLevel.blocked,
              businessName: schedule.businessName,
              conflictTime: '${schedule.startTime}~${schedule.endTime}',
              message: '${schedule.startTime}~${schedule.endTime} 확정 근무 (${schedule.businessName})와 시간 충돌',
            );
            break; // BLOCKED면 더 이상 확인 불필요
          }

          if (conflictLevel == ConflictLevel.warning && worstConflict == null) {
            worstConflict = ConflictInfo(
              level: ConflictLevel.warning,
              businessName: schedule.businessName,
              conflictTime: '${schedule.startTime}~${schedule.endTime}',
              message: '이전 근무(~${schedule.endTime}) 종료 직후입니다. 이동 시간을 고려하세요.',
            );
          }
        }

        results[work.id] = worstConflict ?? ConflictInfo.ok;
      }
    } catch (e) {
      debugPrint('❌ 충돌 체크 실패 (벌크): $e');
      const fallback = ConflictInfo(
        level: ConflictLevel.warning,
        message: '충돌 여부를 확인할 수 없습니다. 관리자에게 문의하세요.',
      );
      for (final work in workDetails) {
        results[work.id] = fallback;
      }
    }

    return results;
  }

  // ═══════════════════════════════════════════════════════════
  // 내부 헬퍼 메서드
  // ═══════════════════════════════════════════════════════════

  /// 해당 날짜의 확정된 근무 조회 (장기공고 포함)
  Future<List<ApplicationModel>> _getConfirmedSchedules({
    required String uid,
    required DateTime workDate,
  }) async {
    try {
      // 만료된 지원서 제외 — workEndDate >= 검사일 (장기공고도 정상 포함)
      final queryDate = Timestamp.fromDate(workDate);
      final snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          // [특이사항] confirmedStatuses 항목 수가 30개를 초과하면 whereIn 분할 처리 필요
          .where('status', whereIn: AppStatus.confirmedStatuses)
          .where('workEndDate', isGreaterThanOrEqualTo: queryDate)
          .get();

      final allConfirmed = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();

      // ✅ 해당 날짜에 근무하는 지원서만 필터링 (장기공고 포함)
      final workingOnDate = allConfirmed.where((app) => app.isWorkingOnDate(workDate)).toList();

      debugPrint('📅 [충돌체크] ${workDate.month}/${workDate.day} 확정 근무: ${workingOnDate.length}건');
      return workingOnDate;
    } catch (e) {
      debugPrint('❌ 확정 스케줄 조회 실패: $e');
      rethrow;
    }
  }

/// 시간 충돌 레벨 판정
  /// 
  /// - BLOCKED: 시간이 겹침
  /// - WARNING: 시간이 딱 붙음 (기존 종료 = 새 시작)
  /// - OK: 충돌 없음
  ConflictLevel _checkTimeConflict({
    required String existingStart,
    required String existingEnd,
    required String newStart,
    required String newEnd,
  }) {
    int existStartMin = _timeToMinutes(existingStart);
    int existEndMin = _timeToMinutes(existingEnd);
    int newStartMin = _timeToMinutes(newStart);
    int newEndMin = _timeToMinutes(newEnd);

    // 자정 넘김 정규화: 종료시간 <= 시작시간이면 +1440(다음날)으로 보정
    if (existEndMin <= existStartMin) existEndMin += 1440;
    if (newEndMin <= newStartMin) newEndMin += 1440;

    // 비교 기준 통일: 두 근무를 공통 기준점으로 정렬
    // 기존 근무가 새 근무 시작보다 12시간 이상 늦으면 전날 기준으로 이동
    // ※ existEndMin은 이미 +1440이 적용됐을 수 있으므로 shift는 existStartMin에만 적용
    if (existStartMin > newStartMin + 720) {
      existStartMin -= 1440;
      existEndMin -= 1440; // start와 end를 함께 이동해야 상대 간격 유지
    }

    // 겹치지 않는 조건: 새 종료 <= 기존 시작 OR 기존 종료 <= 새 시작
    final noOverlap = newEndMin <= existStartMin || existEndMin <= newStartMin;

    if (!noOverlap) {
      return ConflictLevel.blocked;
    }

    // 시간이 딱 붙는지 확인
    if (existEndMin == newStartMin || newEndMin == existStartMin) {
      return ConflictLevel.warning;
    }

    return ConflictLevel.ok;
  }

  /// 시간 문자열을 분 단위로 변환 (예: "09:30" → 570)
  int _timeToMinutes(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return 0;

    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;

    return hours * 60 + minutes;
  }

  // ═══════════════════════════════════════════════════════════
  // 사용자 이용 제한 체크
  // ═══════════════════════════════════════════════════════════

  /// 노쇼 횟수로 이용 제한 여부 확인
  /// 
  /// 반환: null이면 제한 없음, DateTime이면 제한 해제일
  Future<DateTime?> checkUserRestriction(String uid) async {
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      
      if (!userDoc.exists) return null;
      final data = userDoc.data();
      if (data == null) return null;
      final restrictedUntil = data['restrictedUntil'] as Timestamp?;

      // 이미 제한 중인지 확인
      if (restrictedUntil != null) {
        final restrictDate = restrictedUntil.toDate().toLocal();
        if (DateTime.now().isBefore(restrictDate)) {
          return restrictDate;
        }
      }

      // 노쇼 3회 이상이면 제한 필요 (실제 제한 적용은 다른 곳에서)
      // 여기서는 체크만
      return null;
    } catch (e) {
      debugPrint('❌ 사용자 제한 체크 실패: $e');
      return null;
    }
  }

  /// 확정 취소 시 패널티 여부 확인
  /// 
  /// [workDate] 근무 날짜
  /// 반환: true면 패널티 적용 (당일 취소)
  bool shouldApplyPenalty(DateTime workDate) {
    final now = DateTime.now();
    final workDay = DateTime(workDate.year, workDate.month, workDate.day);
    final today = DateTime(now.year, now.month, now.day);

    // 당일이면 패널티
    return workDay.isAtSameMomentAs(today) || workDay.isBefore(today);
  }

  /// 취소 가능 여부 + 메시지
  /// 
  /// 반환: (canCancel, penaltyMessage)
  (bool, String) getCancelInfo(DateTime workDate) {
    final hasPenalty = shouldApplyPenalty(workDate);

    if (hasPenalty) {
      return (true, '당일 취소는 노쇼 1회로 기록됩니다.\n노쇼 3회 누적 시 3일간 이용이 제한됩니다.');
    } else {
      return (true, '근무 1일 전까지 취소는 패널티가 없습니다.');
    }
  }
}