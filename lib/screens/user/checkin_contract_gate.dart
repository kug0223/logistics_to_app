import '../../models/core/application_model.dart';
import '../../models/core/employment_contract_model.dart';

/// [CONTRACT-BEFORE-CHECKIN] 이 근무의 근로계약 동의 상태 — 출근 버튼을 열지 정한다.
///
///   2026-10-25 사용자 지시: "관리자가 확정 시 바로 지원자에게 계약서를 보내고,
///   지원자가 그 계약서에 동의하지 않으면 출근 버튼을 비활성화한다."
///   서버 callableCheckIn 도 같은 식으로 거절한다 — 화면은 서버가 받을지를 미리
///   말할 뿐이고 최종 판정은 서버다.
///
///   지원서 status 는 근거가 아니다 — 초대 수락은 계약서가 생기기 전에 CONFIRMED 다.
///   **그 지원서·그 근로자·그 사업장**에 묶인 계약 문서가 양측 서명 완료인지 본다.
///   무효(voided)·다른 지원서·다른 사람·다른 사업장의 계약은 동의가 아니다.
///   계약을 읽지 못했으면(`contracts == null`) 동의로 치지 않는다(unknown).
enum CheckInContractState {
  /// 양측 서명 완료 — 출근 가능
  completed,

  /// 사업주 서명은 끝났고 근로자 동의(서명) 대기 — 화면에서 바로 동의할 수 있다
  workerPending,

  /// 사업주 서명 대기
  employerPending,

  /// 이 근무의 계약서가 없다(미발송·무효만 있음)
  missing,

  /// 계약 목록을 읽지 못했다 — 모름은 동의가 아니다
  unknown,
}

class CheckInContractGate {
  const CheckInContractGate._(this.state, this.signable);

  final CheckInContractState state;

  /// 근로자가 지금 서명할 수 있는 계약(pending_worker). 그 외 상태에서는 null.
  final EmploymentContractModel? signable;

  bool get allowsCheckIn => state == CheckInContractState.completed;

  static CheckInContractGate evaluate({
    required ApplicationModel work,
    required String uid,
    required List<EmploymentContractModel>? contracts,
  }) {
    if (contracts == null) {
      return const CheckInContractGate._(CheckInContractState.unknown, null);
    }
    EmploymentContractModel? workerPending;
    var employerPending = false;
    for (final c in contracts) {
      if (c.workerId != uid || c.businessId != work.businessId) continue;
      if (c.applicationId != work.id && !c.applicationIds.contains(work.id)) {
        continue;
      }
      switch (c.status) {
        case ContractStatus.completed:
          if (c.employerSignedAt != null && c.workerSignedAt != null) {
            return const CheckInContractGate._(
                CheckInContractState.completed, null);
          }
          break;
        case ContractStatus.pendingWorker:
          workerPending ??= c;
          break;
        case ContractStatus.pendingEmployer:
          employerPending = true;
          break;
        case ContractStatus.voided:
          break;
      }
    }
    if (workerPending != null) {
      return CheckInContractGate._(
          CheckInContractState.workerPending, workerPending);
    }
    if (employerPending) {
      return const CheckInContractGate._(
          CheckInContractState.employerPending, null);
    }
    return const CheckInContractGate._(CheckInContractState.missing, null);
  }
}
