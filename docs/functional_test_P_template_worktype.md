# Category P — 계약서 템플릿 + 업무유형 관리 검증 (100개 시나리오)

> 대상 파일:
> - `lib/screens/business_admin/contract_template_list_screen.dart`
> - `lib/screens/business_admin/contract_template_edit_screen.dart`
> - `lib/screens/business_admin/contract_template_preview_screen.dart`
> - `lib/screens/business_admin/work_type_management_screen.dart`
> - `lib/screens/business_admin/work_type_detail_screen.dart`
>
> 버그 수정: 없음
> 경고: ⚠️ P-01 (업무유형 활성 TO 체크 whereIn 대량 시 지연)

---

## 수정된 버그

없음 — 분석 결과 실제 런타임 버그 없음. 에이전트가 제기한 `_scrollCtrl` 미선언은 줄 140에 `final _scrollCtrl = ScrollController();` 정상 선언되어 있어 오탐.

---

## 경고

### ⚠️ P-01 — `work_type_management_screen.dart` 활성 TO 체크 whereIn 성능
- 업무유형 삭제 전 활성 TO 존재 여부를 `whereIn` 조건으로 조회
- 업무유형 수가 많은 경우 쿼리 지연 가능
- 현재 규모에서 수용

---

## 테스트 시나리오

### [ContractTemplateListScreen — 계약서 템플릿 목록]

**P-001** 화면 진입 → businessId로 getTemplates() 조회, 템플릿 목록 표시

**P-002** 템플릿 없음 → AppEmptyState "등록된 템플릿이 없습니다" 표시

**P-003** 로딩 중 → CircularProgressIndicator 표시

**P-004** '+ 새 템플릿' 버튼 탭 → 유형 선택 바텀시트 표시 (단기/기간제/업무위탁)

**P-005** 유형 선택 → ContractTemplateEditScreen(isNew, type) 이동

**P-006** ContractTemplateEditScreen 복귀 result=true → _load() 재호출

**P-007** 기존 템플릿 카드 탭 → ContractTemplateEditScreen(template) 수정 모드 이동

**P-008** 템플릿 카드 복사 버튼 탭 → _isDuplicating=true → 복사 완료 후 편집 화면 자동 오픈

**P-009** 복사 중 추가 복사 버튼 탭 → _isDuplicating 플래그로 중복 방지

**P-010** 복사 완료 → '복사된 {이름}' 이름으로 새 템플릿 편집 화면 진입

**P-011** 템플릿 삭제 버튼 → 확인 다이얼로그 표시

**P-012** 삭제 확인 → 목록에서 즉시 제거 + 성공 토스트

**P-013** 삭제 취소 → 목록 유지

**P-014** 삭제 실패 → 에러 토스트

**P-015** 미리보기 버튼 → ContractTemplatePreviewScreen 이동

**P-016** 템플릿 유형별 색상 배지 표시 (단기/기간제/업무위탁 각각 다른 색상)

**P-017** RefreshIndicator pull → _load() 재호출

**P-018** 네트워크 오류 → 에러 토스트 + 빈 목록 또는 이전 목록 유지

---

### [ContractTemplateEditScreen — 계약서 템플릿 편집]

**P-019** 신규 생성 — 선택된 유형의 기본 조항 자동 로드 (defaultArticlesFor())

**P-020** 수정 모드 — 기존 템플릿 이름 + 조항 그대로 표시

**P-021** 템플릿 이름 빈 값 → '템플릿 이름을 입력해주세요' 토스트, 저장 차단

**P-022** 조항 추가 버튼 탭 → 새 빈 조항 Entry 추가 + 리스트 맨 아래로 자동 스크롤

**P-023** 자동 스크롤 — `_scrollCtrl.animateTo(maxScrollExtent)` 정상 동작 확인

**P-024** 조항 삭제 버튼 탭 → 해당 조항 TextEditingController dispose + 목록에서 제거

**P-025** ReorderableListView — 드래그로 조항 순서 변경 가능

**P-026** 제목+내용 모두 빈 조항 → 저장 시 자동 제외 (where 필터)

**P-027** 제목만 있거나 내용만 있는 조항 → 저장 포함

**P-028** 저장 중 → 버튼 로딩 스피너 표시, 재탭 차단 (_saving=true)

**P-029** 신규 저장 성공 → '템플릿이 저장되었습니다' 토스트 + Navigator.pop(true)

**P-030** 수정 저장 성공 → '템플릿이 수정되었습니다' 토스트 + Navigator.pop(true)

**P-031** 저장 실패 → '저장에 실패했습니다' 에러 토스트

**P-032** 백버튼 → 현재 데이터 손실 없이 복귀 (별도 확인 다이얼로그 없음)

**P-033** 템플릿 유형 — 수정 모드에서 유형 변경 불가 (읽기 전용)

**P-034** dispose 시 _nameCtrl + _scrollCtrl + 모든 조항 컨트롤러 정상 해제

---

### [ContractTemplatePreviewScreen — 템플릿 미리보기]

**P-035** 화면 진입 → _dummySnapshot 기반 예시 데이터로 계약서 렌더링

**P-036** 제1조(당사자), 제2조(근무조건), 제3조(임금) — 자동 채워짐 안내 배너 표시

**P-037** 편집 가능 조항들 → 템플릿에 저장된 순서대로 표시

**P-038** 스크롤 → 긴 계약서도 전체 스크롤 가능

**P-039** 단기/기간제/업무위탁 각 유형별 미리보기 — 조항 구성 차이 반영

**P-040** StatelessWidget → 비동기 작업 없음, 로딩 없음, 에러 없음

---

### [WorkTypeManagementScreen — 업무유형 관리]

**P-041** 일반 관리자 → getMyBusiness(uid)로 사업장 목록 로드, 첫 사업장 자동 선택

**P-042** SubAdmin → effectiveBusinessId 기반 단일 사업장만 표시, 드롭다운 없음

**P-043** 사업장 변경 드롭다운 선택 → _loadWorkTypes() 재호출

**P-044** 업무유형 없음 → AppEmptyState "등록된 업무 유형이 없습니다" 표시

**P-045** '+ 업무유형 추가' 버튼 → AddWorkTypeSheet.show() 바텀시트 표시

**P-046** 추가 완료 → 완료 다이얼로그 표시 → '상세 정보 입력' 선택 시 WorkTypeDetailScreen(initialEditMode=true)

**P-047** '상세 정보 입력' 취소 → 목록으로 복귀, 추가된 항목 반영

**P-048** 업무유형 카드 탭 → WorkTypeDetailScreen 이동

**P-049** 업무유형 더보기 메뉴 — '수정' → AddWorkTypeSheet.show(editTarget) 수정 모드

**P-050** 업무유형 더보기 메뉴 — '상세 정보' → WorkTypeDetailScreen 이동

**P-051** 업무유형 더보기 메뉴 — '삭제' — 활성 TO 있음 → "활성 공고가 있어 삭제 불가" 경고

**P-052** 업무유형 더보기 메뉴 — '삭제' — 활성 TO 없음 → 확인 다이얼로그 → 삭제 후 목록 갱신

**P-053** 업무유형 '위로' 버튼 — 첫 번째 항목 → 비활성화

**P-054** 업무유형 '아래로' 버튼 — 마지막 항목 → 비활성화

**P-055** 순서 변경 → batch로 displayOrder 교환, 즉시 UI 반영

**P-056** RefreshIndicator pull → _loadWorkTypes() 재호출

**P-057** 사업장 없는 상태 → AppEmptyState 표시 (사업장 등록 유도)

---

### [WorkTypeDetailScreen — 업무유형 상세]

**P-058** 조회 모드 (initialEditMode=false) → 모든 필드 읽기 전용 표시

**P-059** initialEditMode=true → 즉시 편집 모드 진입 (AddWorkTypeSheet에서 상세 입력 바로 진행)

**P-060** 편집 모드 전환 → 텍스트 필드 활성화, 편집 버튼 → 저장/취소 버튼으로 변경

**P-061** 한 줄 소개 입력 (최대 100자) → 저장 후 반영

**P-062** 상세 설명 입력 (다중 행) → 저장 후 반영

**P-063** 대표 이미지 추가 → _newThumbnail 설정, 편집 모드에서 미리보기

**P-064** 추가 이미지 추가 → _newImages에 File 추가

**P-065** 이미지 썸네일 탭 → 해당 이미지가 메인 표시 영역에 확대 표시

**P-066** 이미지 삭제 — URL 이미지 → _imagesToDelete에 추가

**P-067** 이미지 삭제 — 마지막 이미지 삭제 → _currentImageIndex=0 유지 (UI에서 빈 이미지 영역 처리)

**P-068** 근무환경 ChoiceChip — '실내'/'냉장'/'냉동'/'실외'/'혼합' 중 선택 가능

**P-069** 자격요건 입력 → 저장 후 requirements 필드 업데이트

**P-070** 주요업무 입력 → 저장 후 duties 필드 업데이트

**P-071** 준비사항 입력 → 저장 후 precautions 필드 업데이트

**P-072** 빈 텍스트 필드 → null로 저장 (Firestore에 null 기록)

**P-073** 저장 중 → _isLoading=true, 버튼 비활성화

**P-074** 저장 성공:
- Storage 이미지 삭제 → 새 이미지 업로드 → Firestore update → 로컬 상태 업데이트
- '업무유형이 수정되었습니다' 토스트

**P-075** 저장 실패 → '저장에 실패했습니다' 에러 토스트, _isLoading=false

**P-076** '취소' 버튼 → _isEditing=false, _initControllers()로 원래 값 복원

**P-077** 뒤로가기 — 저장 후 (_hasChanges=true) → PopScope에서 Navigator.pop(context, true) 자동 호출

**P-078** 뒤로가기 — 저장 전 (_hasChanges=false) → 시스템 기본 pop (변경사항 확인 없음)

**P-079** 저장 중 뒤로가기 → _isLoading=true 상태에서 PopScope 동작 확인

---

### [통합 시나리오]

**P-080** 계약서 템플릿 신규 생성 → 저장 → 목록 표시 확인

**P-081** 템플릿 복사 → 이름 '복사본' → 편집 화면 → 수정 저장 → 목록에 2개 표시

**P-082** 업무유형 추가 → 상세 정보 입력 → 저장 → 목록 표시 확인

**P-083** 업무유형 순서 변경 → 사업장 변경 후 돌아와도 순서 유지 확인

**P-084** 업무유형 삭제 전 활성 TO 체크 → 활성 TO 3개 있을 때 삭제 차단 확인

**P-085** 계약서 템플릿 — 조항 10개 작성 → 저장 → 다시 열기 → 동일 순서 확인

**P-086** 계약서 템플릿 — 유형별 기본 조항 내용이 실제 법적 필수 항목인지 육안 확인 (수동 검토)

**P-087** 업무유형 이미지 5장 → 썸네일 선택 → 편집 모드 이미지 삭제 → 저장 → 4장 반영 확인

**P-088** 계약서 템플릿 미리보기 → 더미 데이터 예시가 실제 계약서 형식과 유사한지 육안 확인

**P-089** 오프라인 상태 → 템플릿 목록 조회 실패 → 에러 처리 확인

**P-090** 사업장 변경 → 이전 사업장의 업무유형 목록이 새 사업장 목록으로 교체 확인

**P-091** WorkTypeDetailScreen — 편집 모드에서 앱 최소화 후 복귀 → 편집 상태 유지 확인

**P-092** 업무유형 조회 모드 → 편집 버튼 탭 → 수정 → '취소' → 원래 데이터 복원 확인

**P-093** 계약서 템플릿 삭제 → 연결된 계약서에는 영향 없음 확인 (별개 저장)

**P-094** SubAdmin → 업무유형 목록 조회 가능, 드롭다운 사업장 선택 없음 확인

**P-095** 업무유형 더보기 메뉴에서 각 옵션 탭 → 메뉴 시트 자동 닫힘 확인

**P-096** 계약서 템플릿 편집 — 조항 추가 후 스크롤 → 새 조항이 하단에 표시 확인

**P-097** 빈 내용의 조항만 있는 템플릿 저장 → 조항 없이 저장 (빈 조항 자동 제외)

**P-098** 업무유형 추가 후 바로 상세 정보 입력 선택 → initialEditMode=true로 DetailScreen 진입

**P-099** 업무유형 상세 — 모든 선택적 필드 비워두고 저장 → null 값으로 정상 저장

**P-100** 계약서 템플릿 → 동일 이름 2개 생성 가능 여부 확인 (중복 방지 없음, 허용됨)

---

## 체크리스트

| 구분 | 항목 | 상태 |
|------|------|------|
| 수정 버그 | 없음 | - |
| ⚠️ P-01 | 업무유형 활성 TO 체크 whereIn 대량 시 지연 | 수용 |
