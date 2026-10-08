/// [R7-P2-2 A1-U] 지원 **결과**를 격리에서 볼 수 있게 하는 단 하나의 주입점.
///
/// ## 왜 필요한가 (먼저 적어 둔다)
///
/// 지원 버튼을 누른 뒤 화면이 말하는 네 가지 —
/// 성공 / 이미 지원 / 실패 / 모름(재확인 후 발견·여전히 모름) — 는
/// `FirestoreService.applyToTOWithWorkType` 이 돌려주는 `ApplyResult` 하나로
/// 갈린다. 그 호출은 하드 싱글턴 뒤에 있고 extension 정적 디스패치라
/// 하위 클래스로 바꿔 끼울 수 없다(A1-R 에서 확인한 그 구조다).
///
/// 그래서 **그 호출 한 곳만** 받는다. 범용 Firestore 쓰기 fake 도, 공유 DEV
/// 쓰기도 아니다. `production` 은 `submit: null` 이라 지금과 **똑같이**
/// 서비스를 부르고, 그 앞의 선행 검사(로그인·제출 중 잠금·근무 요일·충돌 날짜·
/// 확인 시트 승인)는 모두 화면에 그대로 남는다 — 이 주입점은 그 검사들을
/// 지나온 뒤에만 불린다.
library;

import '../../../models/core/work_detail_data.dart';
import '../../../models/core/to_model.dart';
import '../../../services/firestore_service.dart';

class ApplyWorkSubmit {
  const ApplyWorkSubmit({required this.apply});

  /// 화면이 모으는 값을 그대로 넘긴다 — 새 payload 모델을 만들지 않는다.
  final Future<ApplyResult> Function({
    required String uid,
    required TOModel to,
    required WorkDetailData work,
    required DateTime workDate,
    required String expectedAttendancePolicy,
    String? slotId,
    DateTime? workEndDate,
    DateTime? desiredStartDate,
  }) apply;

  factory ApplyWorkSubmit.of([FirestoreService? service]) {
    final svc = service ?? FirestoreService();
    return ApplyWorkSubmit(
      apply: ({
        required String uid,
        required TOModel to,
        required WorkDetailData work,
        required DateTime workDate,
        required String expectedAttendancePolicy,
        String? slotId,
        DateTime? workEndDate,
        DateTime? desiredStartDate,
      }) =>
          svc.applyToTOWithWorkType(
            uid: uid,
            expectedAttendancePolicy: expectedAttendancePolicy,
            businessId: to.businessId,
            businessName: to.businessName,
            toTitle: to.title,
            workDate: workDate,
            selectedWorkType: work.workType,
            workDetailId: work.id,
            wage: work.wage,
            wageType: work.wageType,
            workTypeIcon: work.workTypeIcon,
            workTypeColor: work.workTypeColor,
            workTypeBackgroundColor: work.workTypeBackgroundColor,
            startTime: work.startTime,
            endTime: work.endTime,
            workEndDate: workEndDate,
            workDays: to.workDays,
            type: to.type,
            toId: to.id,
            slotId: slotId,
            desiredStartDate: desiredStartDate,
          ),
    );
  }
}
