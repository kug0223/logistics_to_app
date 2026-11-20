/// [DU401 S024] 팀원 관리(MemberManagementScreen) 화면의 **읽기 경계** — 관측 seam.
///
///   production 은 `reads: null` 이다. 화면은 기존 서비스 메서드를 같은 인자 · 같은 순서로 그대로 부른다.
///   읽기 세 개만 둔다.
///     • 사업장 이름 — 기존 관대한 조회(`getBusinessesByIds`, 실패 시 빈 목록)의 계약을 바꾸지 않는다.
///       BusinessListReads 의 `*OrThrow` 연결은 복사하지 않는다(오류 정책 변경이 된다).
///     • 멤버 · 보낸 대기 초대(CF 읽기) — 실패는 그대로 던진다(기존과 같음).
///   쓰기 · 검색 · 중복 확인 · 초대/권한/제거 · 알림 경로는 이 경계에 넣지 않는다.
library;

import '../../models/core/business_member_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/member_invitation_model.dart';

class MemberManagementReads {
  const MemberManagementReads({
    required this.businessesByIds,
    required this.members,
    required this.sentPendingInvitations,
  });

  /// 관리 중인 사업장 이름 조회(화면은 이름이 없으면 id 로 대신 쓴다).
  final Future<List<BusinessModel>> Function(List<String> ids) businessesByIds;

  /// 사업장의 멤버 목록. 실패는 throw.
  final Future<List<BusinessMemberModel>> Function(String businessId) members;

  /// 사업장이 보낸 대기 초대(CF 읽기). 실패는 throw.
  final Future<List<MemberInvitationModel>> Function(String businessId) sentPendingInvitations;
}
