import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/employment_contract_model.dart';
import '../../services/contract_service.dart';
import '../../services/device_integrity_service.dart';
import '../../services/firestore_service.dart';

/// [R7-P2-1 잔여] 출퇴근 화면이 **목록을 만들 때** 나가는 읽기 경계.
///
/// 홈 쪽 `UserHomeReads` 와 같은 형태다 — 화면이 실제로 나가서 읽는 호출만
/// 들고 있고, 날짜 필터·제외 술어·정렬·문구는 전부 화면에 남는다.
/// production 은 `reads: null` 이라 기존 `FirestoreService` 인스턴스를 그대로 쓴다.
///
/// 체크인·체크아웃 mutation 은 **이 경계에 넣지 않는다** — 읽기만 갈아끼운다.
class AttendanceCheckReads {
  const AttendanceCheckReads({
    required this.myApplications,
    required this.todayAttendance,
    required this.myContracts,
    this.businessById,
    this.serverTimeMs,
    this.myApplicationsLiveComplete,
  });

  final Future<List<ApplicationModel>> Function(String uid) myApplications;

  final Future<AttendanceModel?> Function({
    required String userId,
    required String applicationId,
  }) todayAttendance;

  /// [CONTRACT-BEFORE-CHECKIN] 내 계약 목록 — 출근 버튼 gate 의 근거.
  ///   화면을 읽을 때마다 새로 받는다(UserProvider 의 서명 대기 캐시를 쓰지 않는다).
  ///   실패는 throw 로 올린다 — 빈 목록으로 바꾸면 "계약 없음"과 구별되지 않는다.
  final Future<List<EmploymentContractModel>> Function(String uid) myContracts;

  /// [PERF-L39 · 2026-11-26] 오늘 근무의 사업장 문서 — 목록을 읽을 때 **기다리지 않고** 미리 받아 둔다.
  ///   출근·퇴근을 누른 뒤 같은 문서를 처음부터 다시 읽던 왕복 하나를 없앤다.
  ///   null(시험 대역 등)이면 미리 받지 않고, 누를 때 기존처럼 읽는다. 판정 권위는 그대로 서버다.
  final Future<BusinessModel?> Function(String businessId)? businessById;

  /// [PERF-L38 · 판정291 B1] 서버 시각 표본(ms) — 오늘 출근할 근무가 있으면 화면을 읽을 때 **미리** 받아 둔다.
  ///   null(시험 대역 등)이면 미리 받지 않고 누를 때 기존 확인을 한다. 확인 실패는 null 이다(정상 근거 아님).
  final Future<int?> Function()? serverTimeMs;

  /// [서버296 H3 · impl_60] 지원서 상한에 닿았어도 진행 중 근무가 모두 들어왔는가(새 서버 `activeIncluded` 표식).
  ///   null(시험 대역 · 구서버 모름) 이면 false 로 본다 — 상한 방어('오늘 근무를 모두 확인하지 못했어요')를 유지한다.
  final bool Function(String uid)? myApplicationsLiveComplete;

  factory AttendanceCheckReads.of([FirestoreService? service]) {
    final svc = service ?? FirestoreService();
    return AttendanceCheckReads(
      myApplications: svc.getMyApplications,
      todayAttendance: ({required String userId, required String applicationId}) =>
          svc.getTodayAttendance(userId: userId, applicationId: applicationId),
      myContracts: (uid) => ContractService().getByWorker(uid),
      businessById: svc.getBusinessById,
      serverTimeMs: DeviceIntegrityService().fetchServerTimeMs,
      myApplicationsLiveComplete: svc.myApplicationsLiveComplete,
    );
  }
}
