# Category N — 계약서·급여명세서 PDF 테스트 시나리오

> 대상 파일:
> - `lib/screens/contract/contract_sign_screen.dart`
> - `lib/screens/contract/contract_pdf_builder.dart`
> - `lib/screens/payroll/payslip_view_screen.dart`
> - `lib/screens/payroll/payslip_pdf_builder.dart`
>
> 버그 수정: 없음
> 경고: ⚠️ N-01 (서명 저장 실패 시 서명 계속 진행 — UX 의도적), ⚠️ N-02 (PDF 폰트 번들 로딩 실패 시 에러만 표시)

---

## 수정된 버그

없음 — 계약서·급여명세서 화면 현재 상태에서 심각한 로직 버그 없음.

---

## 경고 (버그 수준 아님)

### ⚠️ N-01 — 서명 저장 실패 시 계약 서명 계속 진행
- `_signWithPad()`: 서명 저장(Firestore) 실패 → '서명 저장에 실패했습니다. 계약 서명은 계속 진행합니다.' 경고 토스트
- 서명 저장은 선택 편의 기능이므로 실패해도 계약 서명을 차단하지 않는 의도적 설계
- 현재 동작 정상

### ⚠️ N-02 — PDF 폰트 번들 로딩 실패 시 에러 화면만 표시
- `PayslipViewScreen`: `rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf')` 실패 시 Exception
- 에러 화면에 안내 텍스트 표시, fallback 폰트 없음
- assets 번들 포함 확인 필요 (현재 pubspec.yaml에 정상 포함되어 있다면 실 운영에서는 미발생)

---

## 테스트 시나리오 (N-001 ~ N-100)

---

### [ContractSignScreen — 계약서 확인 및 서명 공용]

**N-001** 화면 진입 → 계약서 본문 스크롤 + 하단 동의 체크박스 + 서명 버튼 표시

**N-002** 계약서 본문 끝까지 스크롤 (maxScrollExtent - 60px) → `_hasReadAll=true` 전환

**N-003** `_hasReadAll=false` 상태 → 동의 체크박스 탭 불가 (GestureDetector null onTap)

**N-004** `_hasReadAll=true` → 동의 체크박스 탭 가능

**N-005** 스크롤 불필요한 짧은 계약서 → initState에서 `_hasReadAll=true` 자동 설정

**N-006** 동의 미체크 상태에서 서명 버튼 → '내용 확인 동의가 필요합니다' 경고 토스트

**N-007** `_isSigning=true` 상태 → 서명 버튼 비활성화 (중복 서명 방지)

**N-008** `_effectiveIsLongTerm` — `_toIsContract=true` OR `contract.snapshot.isLongTerm=true` → 장기 근무 계약서 레이아웃

**N-009** `_checkTOType()` — TO 타입 'contract' → `_toIsContract=true` (구 계약서 isLongTerm 오류 보정)

**N-010** `_checkTOType()` — TO 타입 그 외 → `_toIsContract` 미변경

**N-011** `_checkTOType()` — toId 빈 문자열 → Firestore 조회 생략

**N-012** 대표자 이름 조회 순서: `snapshot.ownerName` → `business.ownerName` → `user.ceoName` → `user.name`

**N-013** 대표자 이름 모두 null/빈 → `_resolvedOwnerName=null` (빈 문자열 표시)

**N-014** `_loadBusinessSeal()` 실패 → debugPrint, UI는 인감 없이 표시 (에러 토스트 없음)

---

### [ContractSignScreen — 사업주 서명 (role: 'employer')]

**N-015** 사업주 화면 → `_loadBusinessSeal()` 호출, 인감 + TO 타입 확인

**N-016** 인감 미등록 (_hasSeal=false) → 동의 후 서명 버튼 탭 → '인감 미등록' 안내 다이얼로그

**N-017** 인감 미등록 다이얼로그 — '확인' 탭 → 다이얼로그 닫기, 서명 미진행

**N-018** 인감 등록됨 (_hasSeal=true) → 동의 후 서명 버튼 탭 → `base64Decode(sealBase64)` + `_performSign()` 직접 진행

**N-019** `_performSign()` 성공 (employer) → `service.saveEmployerSignature()` 호출

**N-020** 저장 성공 → '서명이 완료되었습니다. 근무자에게 계약서가 발송됩니다.' 토스트 + `Navigator.pop(updated)`

**N-021** 저장 실패 → 에러 토스트 (e.message), `_isSigning=false` 복원

**N-022** 사업주 배너 → '내용을 검토 후 서명하면 근무자에게 발송됩니다.' 표시

---

### [ContractSignScreen — 근무자 서명 (role: 'worker')]

**N-023** 근무자 화면 → `user.signatureBase64` 로드, 사업주 인감도 로드 (계약서에 표시용)

**N-024** 사전 등록 서명 있음 (_hasSavedSignature=true) → 동의 후 서명 버튼 탭 → 서명 방법 선택 BottomSheet 표시

**N-025** BottomSheet — 저장된 서명 미리보기 표시 (base64 이미지, maxHeight 80)

**N-026** BottomSheet — '저장된 서명으로 서명' 탭 → BottomSheet 닫기 + `_signWithSaved()` 호출

**N-027** BottomSheet — '새 서명 그리기' 탭 → BottomSheet 닫기 + `_signWithPad(askToSave: true)` 호출

**N-028** 사전 등록 서명 없음 (_hasSavedSignature=false) → 동의 후 서명 버튼 → `_signWithPad(askToSave: true)` 직접 호출

**N-029** 서명 패드 → `showSignaturePad()` 다이얼로그 표시

**N-030** 서명 패드 취소 → `bytes=null` 반환, 서명 미진행

**N-031** 서명 완료 후 저장 여부 다이얼로그 → '저장' 선택 → `service.saveUserSignature()` + `userProvider.refreshCurrentUser()`

**N-032** 서명 저장 성공 → `_savedSignatureBase64` 갱신, 이후 서명 시 저장된 서명 표시

**N-033** 서명 저장 실패 → '서명 저장에 실패했습니다. 계약 서명은 계속 진행합니다.' 경고 토스트 + `_performSign()` 계속 (⚠️ N-01)

**N-034** '저장 안 함' 선택 → 서명 저장 생략, `_performSign()` 바로 진행

**N-035** `_performSign()` (worker) → `ContractPdfBuilder.build()` + `service.saveWorkerSignature()`

**N-036** 저장 성공 → '계약서 서명이 완료되었습니다!' 토스트 + `Navigator.pop(updated)`

**N-037** 저장 실패 → 에러 토스트, `_isSigning=false` 복원

**N-038** `ContractPdfBuilder.build()` — employerSignatureUrl + workerSignatureBytes 모두 포함된 PDF 생성

**N-039** 근무자 배너 → '내용을 끝까지 확인하신 후 서명해주세요.' 표시

---

### [ContractPdfBuilder — 계약서 PDF 빌더]

**N-040** `build()` — ContractSnapshotModel + slots + articles → PDF 바이트 반환

**N-041** 단기 근무 계약서 (isLongTerm=false) → 날짜/시간 슬롯 목록 포함 레이아웃

**N-042** 장기 근무 계약서 (isLongTerm=true or _effectiveIsLongTerm) → 계약 기간 표시 레이아웃

**N-043** 사업주 서명 URL 있음 → PDF에 사업주 서명 이미지 포함

**N-044** 사업주 서명 URL 없음 → 사업주 서명 영역 빈 칸

**N-045** 근무자 서명 bytes 있음 → PDF에 근무자 서명 이미지 포함

**N-046** 근무자 서명 bytes 없음 → 근무자 서명 영역 빈 칸

**N-047** ownerNameOverride 있음 → PDF 대표자명에 override 값 사용

**N-048** ownerNameOverride null → snapshot.ownerName 사용

**N-049** isLongTermOverride 있음 → 레이아웃 분기에 override 적용

---

### [PayslipViewScreen — 임금명세서 미리보기]

**N-050** 화면 진입 → `_buildData()` FutureBuilder로 비동기 빌드

**N-051** worker/workerNameOverride 모두 null → assert 실패, 런타임 에러

**N-052** worker.name 우선, null이면 workerNameOverride 사용, 둘 다 null이면 '근무자'

**N-053** `wageDetail=null` → `Exception('급여 정보가 없습니다. 관리자에게 문의해주세요.')` + 에러 화면

**N-054** NotoSansKR-Regular.ttf 로딩 실패 → `Exception('PDF 생성에 필요한 폰트를 로드할 수 없습니다')` + 에러 화면

**N-055** 데이터 로딩 중 → LoadingWidget '임금명세서 생성 중...' 표시

**N-056** 로딩 성공 → 상단 `_InfoBanner` + `_PdfZoomViewer` 표시

**N-057** `_InfoBanner` — workerName · businessName + 근무일 + 실수령액 표시

**N-058** 실수령액 계산 — `wageDetail.netWage > 0` → netWage, 그렇지 않으면 `totalAmount - totalInsuranceDeduction`

**N-059** `_PdfZoomViewer` — InteractiveViewer 핀치줌 지원

**N-060** `_pdfBytesFuture` — `??=` 패턴으로 한 번만 `PayslipPdfBuilder.build(data)` 호출 (재사용)

**N-061** 공유 아이콘 탭 → `Printing.sharePdf(bytes, filename)` 호출

**N-062** 공유 파일명 — `${businessName}_임금명세서_${workerName}_${date}.pdf`

**N-063** 인쇄 아이콘 탭 → `Printing.layoutPdf(onLayout, name)` 호출

**N-064** 공유 실패 → '공유에 실패했습니다' 에러 토스트

**N-065** 인쇄 실패 → '인쇄에 실패했습니다' 에러 토스트

**N-066** 에러 화면 → '임금명세서를 생성할 수 없습니다' + Exception 메시지 표시 ('Exception: ' 접두사 제거)

---

### [PayslipPdfBuilder — 급여명세서 PDF 생성]

**N-067** `build(PayslipData)` → Uint8List PDF 반환

**N-068** `buildAggregated()` → 여러 AttendanceModel 집계 후 PDF 반환 (MyScheduleScreen에서 호출)

**N-069** 근무 기간 표시 — 단일 일자 또는 시작~종료 날짜 범위

**N-070** 급여 내역 — 기본급, 식대, 각종 공제 항목 (국민연금, 건강보험, 고용보험, 소득세) 명세

**N-071** 총 지급액 = 기본급 + 각종 수당 합산

**N-072** 총 공제액 = 국민연금 + 건강보험 + 고용보험 + 소득세 합산

**N-073** 실수령액 = 총 지급액 - 총 공제액

**N-074** 사업장 정보 — businessNumber, businessAddress, ownerName 포함

**N-075** 근무자 정보 — workerName, workerBirthDate 포함

**N-076** 공제 항목 미해당 시 (InsuranceRate 값 0) → 해당 항목 0원 표시

---

### [계약서 서명 통합 플로우]

**N-077** 사업주 계약서 생성 → 사업주 서명 → ContractStatus.pendingWorker로 업데이트

**N-078** 근무자 계약서 수신 → 근무자 서명 → ContractStatus.completed로 업데이트

**N-079** 근무자 서명 완료 → ContractPdfBuilder.build() → Storage에 PDF 업로드 → downloadUrl 저장

**N-080** 계약서 상태 pendingEmployer → 사업주 서명 대기 (근무자 화면에서 '사업주 서명 대기 중' 표시)

**N-081** 계약서 상태 voided → 무효 배지 표시 (서명 불가)

**N-082** 기존 서명 있을 때 계약서 재접근 → 동의+서명 버튼 정상 표시 (상태 재검토 가능)

---

### [공통 — PDF 화면]

**N-083** 오프라인 상태 — 인감/대표자 로드 실패 → 인감 없이 계약서 표시 (에러 토스트 없음)

**N-084** ContractSignScreen dispose → ScrollController 리스너 제거 + dispose

**N-085** PayslipViewScreen → PDF bytes FutureBuilder 완료 전 화면 닫기 → mounted 체크로 setState 차단

**N-086** 가로 모드에서 서명 방법 선택 BottomSheet → `isScrollControlled=true`로 콘텐츠 잘림 방지

**N-087** 사업주 서명 후 MyApplicationsScreen 복귀 → `_loadApplications()` 재호출로 상태 갱신

**N-088** 근무자 서명 후 UserContractsScreen 복귀 → `_refresh()` 재호출로 상태 갱신

**N-089** ContractSignScreen 스크롤 완료 전 서명 버튼 → 동의 체크박스 비활성, 클릭 시 반응 없음

**N-090** 계약서 ContractTemplateWidget — employerSealBase64 있음 → 인감 이미지 표시

**N-091** 계약서 ContractTemplateWidget — employerSealBase64 null → 인감 영역 빈 칸

---

### [통합 시나리오]

**N-092** 사업주 서명 → 근무자 알림 수신 → 근무자 서명 → 계약서 완료 (완전한 서명 플로우)

**N-093** 근무자가 서명 패드에 서명 → 저장 선택 → 다음 계약서에서 저장된 서명 자동 제안

**N-094** 여러 근무자의 임금명세서 개별 PDF 생성 → 각각 고유 파일명으로 공유

**N-095** 사업주 인감 변경 → 이후 서명된 계약서부터 새 인감 적용

**N-096** 계약서 서명 완료 → Firestore status=completed + pdfUrl 저장 확인

**N-097** 구 계약서 (isLongTerm=false지만 TO type='contract') → _effectiveIsLongTerm=true 보정 적용

**N-098** 임금명세서 공유 → 수신자가 PDF 파일명으로 날짜+근무자명 식별 가능

**N-099** 계약서 서명 중 네트워크 끊김 → 에러 토스트 + _isSigning=false 복원 (재시도 가능)

**N-100** 임금명세서 인쇄 — 기기 프린터 연결 없음 → 인쇄 플러그인 UI에서 처리 (앱 수준 에러 없음)

---

## 체크리스트

| 구분 | 항목 | 상태 |
|------|------|------|
| 수정 버그 | 없음 | - |
| ⚠️ N-01 | 서명 저장 실패 시 계약 서명 계속 진행 (의도적) | 수용 |
| ⚠️ N-02 | PDF 폰트 번들 로딩 실패 시 에러 화면만 표시 | 수용 (assets 번들 정상 포함 확인) |
