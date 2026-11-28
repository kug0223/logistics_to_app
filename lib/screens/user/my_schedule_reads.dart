import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../models/core/invite_region_preference.dart';
import '../../models/core/worker_availability_model.dart';
import '../../services/availability_service.dart';
import '../../services/firestore_service.dart';
import '../../services/invite_region_service.dart';

/// [R7-P2-3 READ] 일정 탭이 **화면을 만들 때** 나가는 읽기 경계.
///
/// 근무 가능일은 **초대의 절반**이다 — 나머지 절반(초대 받을 지역·수신 여부)은
/// 같은 문서의 다른 필드가 정한다. 화면이 무엇을 약속하는지 확인하려면 두 값을
/// 함께 줄 수 있어야 한다. production 은 `reads: null` 이라 기존 서비스를 쓴다.
///
/// 가능일 저장(쓰기)은 이 경계에 넣지 않는다 — 읽기만 갈아끼운다.
class MyScheduleReads {
  const MyScheduleReads({
    required this.myApplications,
    required this.myMonthlyAttendances,
    required this.myAvailability,
    required this.invitePreference,
    this.invalidateCaches,
    this.dataRevision,
  });

  /// [PERF-P9 · 판정291 §8] 이 사용자의 지원·근태 캐시가 무효화된 세대(출퇴근·지원·취소 등 뒤 바뀜).
  ///   탭이 다시 보일 때 읽은 때와 다르면 표시월을 조용히 다시 읽는다. null(시험 대역)이면 시간 기준만 쓴다.
  final Object Function(String uid)? dataRevision;

  /// [PERF-L20] 새로고침 전에 이 사용자의 지원·근태 TTL 캐시를 비운다. null 이면 아무 일도 없다(시험 대역).
  final void Function(String uid)? invalidateCaches;

  final Future<List<ApplicationModel>> Function(String uid) myApplications;

  final Future<List<AttendanceModel>> Function({
    required String userId,
    required int year,
    required int month,
  }) myMonthlyAttendances;

  final Future<WorkerAvailabilityModel?> Function(String uid) myAvailability;

  /// 실패해도 OFF 로 단정하지 않는다 — `unknown` 이 따로 있다.
  final Future<InviteRegionPreference> Function(String uid) invitePreference;

  factory MyScheduleReads.of([
    FirestoreService? service,
    AvailabilityService? availabilityService,
    InviteRegionService? inviteRegionService,
  ]) {
    final svc = service ?? FirestoreService();
    final av = availabilityService ?? AvailabilityService();
    // [PERF-L20] 초대 지역은 공유 읽기 + `InviteRegionService.parseOrUnknown`(loadMine 과 같은 규칙)로 읽는다 —
    //   `inviteRegionService` 인자는 호출부 호환으로 남는다(그 인스턴스의 읽기 경로는 쓰지 않는다).
    // [PERF-L20] 근무 가능일과 초대 지역은 **같은 문서**(worker_availability/{uid})다. 화면이 두 값을 같은 순간에
    //   읽으므로 진행 중인 읽기 하나를 함께 쓴다(같은 uid 만 · 끝나면 놓는다 · 결과 보관 0 — 저장 뒤 재조회는 새로 읽는다).
    //   해석은 각 서비스의 기존 규칙 그대로(가능일: 실패는 던짐 · 초대 지역: 실패는 unknown).
    final shared = _InFlightDoc(av.availabilityDoc);
    return MyScheduleReads(
      myApplications: svc.getMyApplications,
      myMonthlyAttendances: (
              {required String userId,
              required int year,
              required int month}) =>
          svc.getMyMonthlyAttendances(userId: userId, year: year, month: month),
      myAvailability: (uid) async => AvailabilityService.parseAvailability(await shared.get(uid)),
      invitePreference: (uid) => InviteRegionService.parseOrUnknown(() => shared.get(uid)),
      invalidateCaches: (uid) {
        svc.invalidateMyApplicationsCache(uid);
        svc.invalidateMyAttendanceCache(uid);
      },
      dataRevision: (uid) =>
          '${svc.myApplicationsGenerationOf(uid)}|${svc.myAttendanceGenerationOf(uid)}',
    );
  }
}

/// [PERF-L20] 같은 uid 의 진행 중 문서 읽기 하나를 공유한다 — 끝나면(성공·실패) 놓는다. 결과를 보관하지 않는다.
class _InFlightDoc {
  _InFlightDoc(this._read);
  final Future<DocumentSnapshot<Map<String, dynamic>>> Function(String uid) _read;
  final Map<String, Future<DocumentSnapshot<Map<String, dynamic>>>> _inFlight = {};

  Future<DocumentSnapshot<Map<String, dynamic>>> get(String uid) {
    final existing = _inFlight[uid];
    if (existing != null) return existing;
    final f = _read(uid);
    _inFlight[uid] = f;
    f.whenComplete(() {
      if (identical(_inFlight[uid], f)) _inFlight.remove(uid);
    }).ignore();
    return f;
  }
}
