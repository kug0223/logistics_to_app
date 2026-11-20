// [CONTRACT-BEFORE-CHECKIN] 출근 화면 시험용 계약 문서.
//
//   2026-10-25부터 출근 버튼은 그 지원서·근로자·사업장의 계약이 양측 서명 완료일 때만 열린다
//   (사용자 지시: "확정 시 계약서 발송 → 지원자 미동의면 출근 버튼 비활성").
//   출근 버튼이 열린다고 기대하던 기존 시험은 이제 그 전제를 명시해야 한다 — 이 파일이 그 계약을 만든다.
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';

EmploymentContractModel checkInContractFor(
  ApplicationModel app, {
  ContractStatus status = ContractStatus.completed,
  String? workerId,
  String? businessId,
  String? applicationId,
  bool bundled = false,
  bool employerSigned = true,
  bool workerSigned = true,
}) {
  final appId = applicationId ?? app.id;
  final signedAt = DateTime.utc(2026, 1, 1);
  return EmploymentContractModel(
    id: 'contract_$appId${status.value}',
    // bundled: 최초 지원서는 다른 것이고 이 지원서는 applicationIds 로만 묶인 경우(단기 번들)
    applicationId: bundled ? 'first_app_of_bundle' : appId,
    applicationIds: [if (bundled) 'first_app_of_bundle', appId],
    businessId: businessId ?? app.businessId,
    workerId: workerId ?? app.uid,
    isLongTerm: app.isLongTermApplication,
    toId: app.toId ?? '',
    workDetailId: '',
    status: status,
    employerSignedAt: (status == ContractStatus.pendingEmployer || !employerSigned)
        ? null
        : signedAt,
    workerSignedAt: (status == ContractStatus.completed && workerSigned) ? signedAt : null,
    snapshot: const ContractSnapshot(
      businessName: '합성 사업장',
      businessNumber: '000-00-00000',
      businessAddress: '합성 주소',
      ownerName: '합성 대표',
      workerName: '합성 근로자',
      workType: '분류',
      workPlace: '합성 주소',
      isLongTerm: false,
      startTime: '09:00',
      endTime: '18:00',
      breakMinutes: 0,
      wage: 10320,
      wageType: 'hourly',
    ),
    createdAt: signedAt,
  );
}

/// 각 근무마다 양측 서명 완료 계약 — "출근할 수 있는 상태"의 전제
List<EmploymentContractModel> completedContractsFor(
        Iterable<ApplicationModel> apps) =>
    [for (final a in apps) checkInContractFor(a)];
