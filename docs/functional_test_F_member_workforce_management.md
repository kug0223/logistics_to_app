# Category F: 멤버/인력 관리 기능 시나리오 (100개)

> 대상 파일
> - `lib/services/member_service.dart`
> - `lib/models/core/business_member_model.dart`
> - `lib/models/core/member_invitation_model.dart`
> - `lib/controllers/workforce_controller.dart`
> - `lib/screens/business_admin/member_management_screen.dart`
> - `lib/screens/business_admin/workforce_management/integrated_workforce_screen.dart`
> - `lib/screens/business_admin/workforce_management/workforce_list_view.dart`

---

## F-001 ~ F-010: 전화번호 검색 (findUserByPhone)

### F-001 정상 — 하이픈 없는 입력으로 근무자 검색 성공
- **입력**: `01012345678`
- **기댓값**: DB에 `01012345678`로 저장된 USER 역할 문서 반환

### F-002 정상 — 하이픈 있는 입력으로 근무자 검색 성공
- **입력**: `010-1234-5678`
- **기댓값**: 정규화(하이픈 제거) 후 DB 조회 → USER 문서 반환

### F-003 정상 — DB에 하이픈 형식(`010-1234-5678`)으로 저장된 경우에도 검색 성공
- **입력**: `01012345678`
- **기댓값**: 첫 번째 쿼리(숫자형) 실패 → 두 번째 쿼리(하이픈형) 성공 → 문서 반환

### F-004 정상 — 검색 결과 없음
- **입력**: 가입되지 않은 전화번호
- **기댓값**: `null` 반환

### F-005 정상 — role=ADMIN인 사용자는 검색 제외
- **환경**: 동일 전화번호가 ADMIN 역할로만 등록
- **기댓값**: `null` 반환 (`where('role', isEqualTo: 'USER')` 필터)

### F-006 엣지 — 빈 문자열 입력
- **입력**: `''`
- **기댓값**: 빈 `digits` → 두 쿼리 모두 빈 문자열로 실행 → `null` 반환

### F-007 엣지 — 특수문자 포함 입력 (`010.1234.5678`)
- **기댓값**: 숫자 추출 후 `01012345678` → 정상 조회

### F-008 엣지 — 네트워크 오류 발생
- **기댓값**: catch 블록에서 `debugPrint` 후 다음 쿼리로 진행, 최종 `null` 반환

### F-009 엣지 — 동일 전화번호가 여러 문서에 존재
- **기댓값**: `limit(1)` 보장으로 첫 번째 문서만 반환

### F-010 엣지 — 9자리 전화번호 입력
- **기댓값**: 쿼리 실행(DB에 없으므로) `null` 반환, 별도 유효성 검사 없음

---

## F-011 ~ F-025: 초대 발송

### F-011 정상 — 신규 근무자 초대 발송 성공
- **흐름**: 전화번호 검색 → 권한 1개 이상 선택 → 발송
- **기댓값**: `member_invitations` 문서 생성 + 알림 발송

### F-012 정상 — 권한 4개 모두 선택 후 발송
- **기댓값**: `canManageTo/Workers/Wage/Contract` 모두 `true`로 저장

### F-013 정상 — 이미 멤버인 경우 발송 차단
- **기댓값**: `isAlreadyMember() = true` → 에러 토스트 "이미 멤버로 등록된 사용자입니다" → 발송 안 됨

### F-014 정상 — 30일 이내 pending 초대가 이미 있는 경우 발송 차단
- **기댓값**: `hasPendingInvitation() = true` → 에러 토스트 "이미 초대가 발송된 사용자입니다" → 발송 안 됨

### F-015 정상 — 31일 전 pending 초대는 만료 간주 → 재발송 허용
- **기댓값**: `hasPendingInvitation()` 30일 기준으로 31일 전 초대 제외 → `false` → 재발송 성공

### F-016 정상 — 알림 발송 실패해도 초대 자체는 성공
- **환경**: `createNotification()` throw
- **기댓값**: catch 후 `debugPrint` → `sendInvitation` 정상 반환

### F-017 엣지 — `_send()` 호출 시 `currentUser == null`
- **기댓값**: 에러 토스트 "로그인 정보를 찾을 수 없습니다" → 발송 중단

### F-018 엣지 — 권한 미선택(전체 false) 상태에서 초대 발송 시도
- **기댓값**: `canSend = _found != null && _permissions.hasAnyPermission` → false → 버튼 비활성화, 발송 없음

### F-019 엣지 — `_found == null` 상태에서 발송 버튼 접근
- **기댓값**: 버튼 `onPressed: canSend ? _send : null` → null → 탭 불가

### F-020 경쟁조건 ⚠️ — `isAlreadyMember` + `hasPendingInvitation` 체크 후 두 클라이언트가 동시 초대 발송
- **증상**: TOCTOU — 두 번의 확인 후 두 초대 모두 `sendInvitation` 호출 가능
- **현황**: 별도 트랜잭션 없음 → 동일 사용자에게 중복 초대 2건 생성 가능
- **의사결정**: 실제 사용 환경(관리자 1명 운영)에서는 발생 확률 극히 낮음 → 주석 처리

### F-021 정상 — `hasPendingInvitation` 쿼리 구조 검증
- **기댓값**: `businessId + targetUid + status=pending + createdAt > 30일 전` 복합 조건으로 중복 최소화

### F-022 정상 — 거절된 초대 이후 재초대 가능
- **환경**: 이전 초대 `status=rejected`
- **기댓값**: `hasPendingInvitation()` pending만 체크 → `false` → 재초대 가능

### F-023 정상 — 수락된 초대 이후 이미 멤버 → 재초대 차단
- **기댓값**: `isAlreadyMember() = true` → 재초대 불가

### F-024 엣지 — `sendInvitation` Firestore 오류
- **기댓값**: `_send()` catch 블록 → 에러 토스트 "초대 발송 중 오류가 발생했습니다"

### F-025 엣지 — 발송 중 다이얼로그 닫기 시도
- **기댓값**: `PopScope(canPop: !_sending)` → 발송 중 뒤로가기 차단

---

## F-026 ~ F-035: 초대 수락 / 거절

### F-026 정상 — 초대 수락 성공
- **흐름**: `acceptInvitation()` 호출
- **기댓값**: 배치 — invitation.status=accepted + members/{uid} 생성
- **부수효과**: CF trigger `onMemberInvitationAccepted` → user.subAdminOf = businessId

### F-027 정상 — 수락 후 수락한 관리자에게 알림 발송
- **기댓값**: `createMemberInvitationAccepted` 알림 생성

### F-028 정상 — 수락 알림 실패해도 배치 커밋은 성공
- **환경**: `createNotification()` throw
- **기댓값**: catch → `debugPrint` → 정상 반환

### F-029 정상 — 초대 거절 성공
- **기댓값**: invitation.status=rejected, respondedAt 기록

### F-030 정상 — 거절 후 관리자에게 알림 발송
- **기댓값**: `createMemberInvitationRejected` 알림 생성

### F-031 엣지 — 수락 시 `_members(businessId)` set은 멱등적
- **기댓값**: 이미 members/{uid} 존재해도 `batch.set()` → 덮어씀, 오류 없음

### F-032 경쟁조건 ⚠️ — 동일 초대를 두 번 수락 (빠른 더블탭)
- **증상**: 배치에 상태 체크 없음 → 두 배치 모두 성공 가능
- **현황**: 결과는 동일(idempotent) — status=accepted, member 동일, 알림 2건
- **의사결정**: 알림 중복 발생 가능하지만 데이터 무결성 문제 없음 → 주석 처리

### F-033 엣지 — 수락 시 `addedBy` 필드 = invitation.invitedBy
- **기댓값**: 초대한 관리자 uid가 `addedBy`로 저장됨

### F-034 엣지 — `acceptInvitation()` 배치 커밋 실패
- **기댓값**: 오류 전파 → 호출자에서 에러 처리

### F-035 엣지 — 이미 거절/취소된 초대를 다시 수락 시도
- **현황**: status 체크 없음 → members에 추가 가능
- **의사결정**: UI에서 pending 초대만 노출하므로 실제 발생 가능성 낮음 → 주석 처리

---

## F-036 ~ F-050: 멤버 조회 / 권한 관리

### F-036 정상 — 멤버 목록 조회
- **기댓값**: `addedAt` 오름차순 정렬, `BusinessMemberModel` 리스트 반환

### F-037 정상 — 빈 멤버 목록
- **기댓값**: 빈 리스트 반환, `AppEmptyState` 위젯 표시

### F-038 ⚠️ `getMembers()` limit 없음
- **현황**: 멤버 수가 많아질 경우 전량 읽기 — 사업장당 수십 명 이하로 현실적 위험 낮음
- **의사결정**: 주석 처리

### F-039 정상 — `getMemberPermissions()` 성공
- **기댓값**: `MemberPermissions.fromMap()` 반환

### F-040 정상 — `getMemberPermissions()` 문서 없음
- **기댓값**: `null` 반환

### F-041 정상 — 권한 업데이트 성공
- **기댓값**: members/{uid}.permissions 필드 갱신

### F-042 엣지 ⚠️ — `updatePermissions()` 멤버 문서 미존재 시 Firestore update 오류
- **현황**: 존재 체크 없음 → Firestore `update()` on non-existent doc → throws
- **현황**: UI 호출부(`_editPermissions`)에서 try/catch → 에러 토스트 처리됨
- **의사결정**: UI 보호 있으므로 주석 처리

### F-043 정상 — 권한 수정 다이얼로그 — 1개 이상 선택해야 저장 활성화
- **기댓값**: `_permissions.hasAnyPermission == false` → 저장 버튼 비활성화

### F-044 정상 — `_PermissionDialog` 취소 → null 반환 → 업데이트 없음
- **기댓값**: `result == null` → 조기 반환

### F-045 정상 — 권한 업데이트 후 멤버 목록 새로고침
- **기댓값**: `ToastHelper.showSuccess` → `_load()` 재호출

---

## F-046 ~ F-060: 멤버 제거

### F-046 정상 — 멤버 제거 성공
- **기댓값**: members/{uid} 삭제 + user.subAdminOf 삭제 (배치)

### F-047 **BUG-F-01** — `removeMember()` 타 사업장 subAdminOf 오삭제
- **현상**: users/{uid}.subAdminOf가 **다른** businessId를 가리키는 상황에서 BusinessA가 `removeMember` 호출
- **원인**: `FieldValue.delete()` 조건 없이 무조건 실행
- **영향**: 사용자가 BusinessB의 하위 관리자 권한을 잃음
- **수정**: 트랜잭션으로 `subAdminOf` 현재 값 확인 후 일치 시에만 삭제 → **수정 완료**

### F-048 정상 — 자기 자신(오너)은 멤버 목록에 없으므로 제거 대상 아님
- **기댓값**: 오너 uid는 members 서브컬렉션에 없음

### F-049 엣지 — 존재하지 않는 uid 제거 시도
- **기댓값**: `batch.delete()` on non-existent doc → 오류 없음(Firestore delete idempotent)
- `batch.update()` on users → subAdminOf 없으면 FieldValue.delete() → 무시됨

### F-050 정상 — 제거 확인 다이얼로그 취소
- **기댓값**: `ok != true` → 조기 반환, 제거 없음

### F-051 정상 — 제거 성공 후 멤버 목록 새로고침
- **기댓값**: 토스트 "멤버가 제거되었습니다" → `_load()` 재호출

### F-052 엣지 — 제거 중 Firestore 오류
- **기댓값**: catch → 에러 토스트 "멤버 제거에 실패했습니다"

---

## F-053 ~ F-060: 초대 조회

### F-053 정상 — 특정 사용자의 pending 초대 목록 조회
- **기댓값**: `status=pending` 필터 + `createdAt` 최신순

### F-054 ⚠️ `getPendingInvitations()` limit 없음
- **현황**: 다수 pending 초대 누적 가능 — 실제 사용환경에서는 최대 수십 건 이하
- **의사결정**: 주석 처리

### F-055 정상 — invitationId로 단건 초대 조회 성공
- **기댓값**: `MemberInvitationModel` 반환

### F-056 정상 — 존재하지 않는 초대 조회
- **기댓값**: `null` 반환

### F-057 정상 — 알림에서 초대 ID로 진입 → `getInvitation()` 호출 정상
- **기댓값**: 알림 클릭 → invitationId 파싱 → 초대 모델 반환

### F-058 엣지 — `MemberInvitationModel.fromFirestore` createdAt 누락 시 throw
- **기댓값**: `ArgumentError('Document ${doc.id} missing required field: createdAt')`

### F-059 정상 — `InvitationStatus._statusFromString` 알 수 없는 문자열
- **기댓값**: default → `InvitationStatus.pending` 반환

### F-060 엣지 — `getPendingInvitations` Firestore 오류
- **기댓값**: catch → `debugPrint` → 빈 리스트 반환

---

## F-061 ~ F-075: WorkforceController

### F-061 정상 — `load()` SuperAdmin 컨텍스트
- **기댓값**: `businessIds = null` → 모든 사업장 TO 조회

### F-062 정상 — `load()` 일반 관리자 컨텍스트
- **기댓값**: `businessIds = user.managedBusinessIds` → 해당 사업장 TO만 조회

### F-063 정상 — `load()` SubAdmin 컨텍스트
- **기댓값**: `businessIds = [user.subAdminOf]` → 단일 사업장 TO 조회

### F-064 정상 — `load()` 사업장 없는 관리자
- **기댓값**: `businessIds = []` → `_items = []` → early 반환 없이 finally/postload 실행

### F-065 정상 — `load()` 재진입 보호
- **기댓값**: `_isLoading = true` 중 재호출 → 즉시 `return`

### F-066 정상 — flex TO 슬롯 날짜 30개 초과 시 청크 분할
- **환경**: 31개 flex TO
- **기댓값**: [30개 chunk, 1개 chunk] → 병렬 `Future.wait` → 결과 merge

### F-067 정상 — `dispose()` 후 `notifyListeners()` 안전 차단
- **기댓값**: `_disposed = true` → `if (!_disposed) notifyListeners()` → 호출 안 됨

### F-068 정상 — `loadGroupDetails()` 중복 로드 방지
- **기댓값**: `isGroupDetailLoaded` 또는 `_loadingGroupIds.contains(group.id)` → 즉시 반환

### F-069 정상 — `loadWorkDetails()` needsWorkDetailLoad=false 시 스킵
- **기댓값**: `!slot.needsWorkDetailLoad` → 즉시 반환

### F-070 정상 — `_preloadFlexTOSlots()` 사전 로드 → 캘린더 날짜 필터링 즉시 가능
- **기댓값**: 조용히 백그라운드 실행, UI 갱신

### F-071 정상 — `_maybeCascadeCloseExpiredTO()` — 모든 슬롯 만료 시 TO CLOSED 동기화
- **기댓값**: `_service.markTOAsExpired(to.id)` 비동기 호출

### F-072 정상 — `_maybeCascadeCloseExpiredTO()` — TO가 이미 closed → 스킵
- **기댓값**: `to.isClosed` → 즉시 반환

### F-073 정상 — `_maybeCascadeCloseExpiredTO()` — TO가 scheduled → 스킵
- **기댓값**: `status == TOStatus.scheduled` → 반환 (미공개 TO 보호)

### F-074 ⚠️ `_maybeCascadeCloseExpiredTO()` / `_maybeCascadeCloseExpiredContractTOs()` — fire-and-forget
- **현황**: `markTOAsExpired` 실패 시 Firestore 미갱신 → 다음 reload 때 재시도 가능
- **현황**: UI는 로컬 `isClosed` 기준으로 이미 닫힘 처리 → 사용자 체감 영향 없음
- **의사결정**: 의도된 낙관적 갱신 → 주석 처리

### F-075 정상 — `reload()` = `load()` 위임 확인
- **기댓값**: `reload(context)` → `load(context)` 동일 플로우

---

## F-076 ~ F-090: WorkforceListView 필터 / 탭 / 페이지네이션

### F-076 정상 — 진행중 탭: `!isClosed` 아이템만 표시
- **기댓값**: 마감된 TO 제외

### F-077 정상 — 마감됨 탭: `isClosed` 아이템 + closedAt 최신순 정렬
- **기댓값**: `closedAt ?? statusUpdatedAt ?? date` 기준 정렬

### F-078 정상 — 마감됨 탭 페이지네이션 (스크롤 트리거)
- **기댓값**: `_closedDisplayCount` 5씩 증가, `_scrollController` 콜백

### F-079 정상 — 탭 전환 시 `_closedDisplayCount` 초기화
- **기댓값**: `_selectedTab != tab` → `_closedDisplayCount = _closedPageSize`

### F-080 정상 — 사업장 필터 적용
- **기댓값**: `groupItem.businessName != _selectedBusiness` → 제외

### F-081 정상 — TO 타입 필터 (flex/contract)
- **기댓값**: `masterTO.type != _selectedTOType` → 제외

### F-082 정상 — 공개 상태 필터 (published/unpublished/pending)
- **기댓값**: 각 case별 `isPublished`/`isPendingPublish` 조건 적용

### F-083 정상 — 날짜 필터 — 단기 TO
- **기댓값**: TO date가 filterStart~filterEnd 범위 내 → 포함

### F-084 정상 — 날짜 필터 — 장기 TO (startDate-endDate overlap)
- **기댓값**: 필터 범위와 겹치면 포함 (filterEnd < toStart || filterStart > toEnd 시 제외)

### F-085 정상 — 날짜 필터 — flex TO 슬롯 날짜 기준
- **기댓값**: `groupTOs`가 로드된 경우 slot.date 기준, 미로드 시 `slotDates` → `masterTO.date` 폴백 순

### F-086 정상 — 필터 활성화 카운트 배지 표시
- **기댓값**: 4개 필터 중 적용된 수 → `_getActiveFilterCount()` → 배지 숫자

### F-087 정상 — 그룹 카드 펼침 — flex TO lazy load
- **기댓값**: `isGroupDetailLoaded=false` → `loadGroupDetails()` 호출 → 로딩 스피너 → 완료 시 슬롯 표시

### F-088 정상 — 그룹 카드 펼침 — 단건 TO workDetails lazy load
- **기댓값**: `isWorkDetailLoaded=false` → `loadTOWorkDetails()` → 통계 설정

### F-089 정상 — 그룹 카드 재닫기 (같은 카드 다시 탭)
- **기댓값**: `_expandedGroups.contains(key)` → remove → 접힘

### F-090 정상 — 그룹 펼침 시 기존 펼쳐진 그룹 자동 닫힘
- **기댓값**: `_expandedGroups.clear()` 후 새 키 add → 한 번에 하나만 열림

---

## F-091 ~ F-100: IntegratedWorkforceScreen / 통합

### F-091 정상 — SubAdmin 로그인 시 effectiveBusinessId로 즉시 로드
- **기댓값**: `getMyBusiness()` 호출 없이 `[effectiveBizId]` 사용

### F-092 정상 — 일반 관리자 로그인 시 `getMyBusiness()` 로 사업장 목록 조회
- **기댓값**: 첫 번째 사업장 선택 → `_controller.load(context)`

### F-093 정상 — 사업장 없음
- **기댓값**: 경고 토스트 → GradientScaffold with AppEmptyState

### F-094 정상 — 앱 포그라운드 복귀 시 자동 reload
- **기댓값**: `didChangeAppLifecycleState(resumed)` → `_controller.reload(context)`

### F-095 정상 — FCM 관리자 갱신 신호 → reload
- **기댓값**: `_fcmRefreshCallback` → `_controller.reload(context)`

### F-096 정상 — FCM 리스너 dispose 시 제거
- **기댓값**: `FCMService().removeAdminRefreshListener(_fcmRefreshCallback)` → 메모리 누수 없음

### F-097 정상 — 목록 ↔ 캘린더 뷰 전환
- **기댓값**: `_isCalendarView` 토글 → 해당 뷰 렌더링

### F-098 정상 — 상단 새로고침(pull-to-refresh)
- **기댓값**: `onRefresh: _loadBusinessIds` → 사업장 재조회 + 컨트롤러 reload

### F-099 정상 — `MemberManagementScreen._load()` mounted 체크
- **기댓값**: async gap 후 `if (!mounted) return` → setState 안전 호출

### F-100 정상 — `PhoneNumberFormatter` 입력 포맷터 작동
- **기댓값**: 숫자 입력 시 자동 `010-XXXX-XXXX` 형식 변환

---

## 버그 수정 요약

| ID       | 위치                   | 내용                                                    | 상태     |
|----------|----------------------|-------------------------------------------------------|--------|
| BUG-F-01 | member_service.dart:258 | `removeMember()` subAdminOf 무조건 삭제 → 타 사업장 권한 오삭제 | ✅ 수정 |

## 추가검증 대상 (⚠️)

| ID    | 위치                               | 내용                                              | 결정 |
|-------|----------------------------------|---------------------------------------------------|------|
| F-020 | member_service.dart sendInvitation | 초대 발송 TOCTOU 경쟁조건                         | 주석  |
| F-032 | member_service.dart acceptInvitation | 초대 이중 수락 → 알림 중복                      | 주석  |
| F-035 | member_service.dart acceptInvitation | 거절/취소 초대 재수락 가능                      | 주석  |
| F-038 | member_service.dart getMembers   | limit 없음 (현실적 위험 낮음)                    | 주석  |
| F-042 | member_management_screen.dart    | updatePermissions 멤버 미존재 시 throw (UI 보호됨) | 주석  |
| F-054 | member_service.dart getPendingInvitations | limit 없음                               | 주석  |
| F-074 | workforce_controller.dart        | cascade close fire-and-forget (낙관적 갱신)      | 주석  |
