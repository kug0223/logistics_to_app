# Category E: 계약서 관리 기능 테스트 시나리오 100개

> 감사 기준일: 2026-06-12  
> 대상 파일: `contract_service.dart`, `employment_contract_model.dart`, `contract_template_service.dart`, `admin_contract_management_screen.dart`, `contract_sign_screen.dart`  
> 발견 버그: **BUG-E-01** (아래 표 내 🔴 표시)

---

## 버그 요약

| ID | 심각도 | 위치 | 설명 | 상태 |
|----|--------|------|------|------|
| BUG-E-01 | LOW | `contract_service.dart:482` | `voidContract()` — 이미 `voided`인 계약서 재호출 시 이미 취소된 지원서를 재취소 시도 → failedIds 발생 + 오해의 소지 있는 에러 토스트 | **수정 완료** |

---

## E-001~020: 계약서 생성

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| E-001 | 정상 | 단기 지원서 최초 확정 → 계약서 신규 생성 | `_createNew()` 호출, `isNewUnsaved=true`, Firestore 미저장 | `findOrCreateContract():59` | ✅ |
| E-002 | 정상 | 동일 (toId + workDetailId + workerId) 단기 지원서 2번째 확정 → 슬롯 추가 | `_findBundle()` → `pendingEmployer` 상태 → `_addSlot()` 호출 | `findOrCreateContract():52-55` | ✅ |
| E-003 | 경계값 | 번들 계약서가 `pendingWorker` 상태일 때 3번째 단기 확정 | 번들 탐색 → status=pendingWorker → 슬롯 추가 불가 → `_createNew()` 신규 생성 | `findOrCreateContract():52-53` K-001 | ✅ |
| E-004 | 경계값 | 번들 계약서가 `completed` 상태일 때 단기 확정 | `_createNew()` 신규 생성 | `findOrCreateContract():52-53` | ✅ |
| E-005 | 경계값 | 번들 계약서가 `voided` 상태일 때 단기 확정 | `_createNew()` 신규 생성 | `findOrCreateContract():52-53` | ✅ |
| E-006 | 정상 | 장기 지원서 확정 → 단일 계약서 생성 (슬롯 없음) | `isLong=true → slots=[]` | `_createNew():649-660` | ✅ |
| E-007 | 경계값 | `toId=null` 지원서 확정 → `toId=''`로 계약서 생성 | `toId = application.toId ?? ''` | `findOrCreateContract():39` | ✅ |
| E-008 | 경계값 | `workDetailId=null` 지원서 확정 → `workDetail.id` 폴백 사용 | `workDetailId = application.workDetailId ?? workDetail.id` | `findOrCreateContract():40` | ✅ |
| E-009 | 경계값 | `ownerName=null` 사업장에서 계약서 생성 → `users/{ownerId}` 조회 | `ceoName` 우선, 없으면 `name` 폴백 | `_createNew():612-625` | ✅ |
| E-010 | 경계값 | `ownerName=''` (빈 문자열) 사업장에서 계약서 생성 | `ownerName.trim().isEmpty → users 조회 경로` | `_createNew():612` | ✅ |
| E-011 | 경계값 | TO type='contract' 레거시 데이터 → `isLongTerm=false` 지원서임에도 TO 조회 후 `isLong=true` 보정 | `_createNew():630-638` | ✅ |
| E-012 | 경계값 | TO 문서 없음 (삭제됨) → `isLong` 폴백 유지 | `catch(e) → debugPrint, isLong 그대로 유지` | `_createNew():636-638` | ✅ |
| E-013 | 정상 | 미리보기 계약서 생성 (`buildPreviewContract`) | `isNewUnsaved=true`, Firestore 저장 없음 | `buildPreviewContract():73-89` | ✅ |
| E-014 | 경계값 | `_addSlot()` 동시 확정 (두 관리자 같은 지원서 동시 확정) | 트랜잭션으로 `current.slots` 재조회 → last-write-wins 방지 | `_addSlot():576-593` 트랜잭션 | ✅ |
| E-015 | 경계값 | `_addSlot()` 대상 계약서 이미 삭제된 경우 | `throw Exception('계약서를 찾을 수 없습니다')` | `_addSlot():578` | ✅ |
| E-016 | 경계값 | `desiredStartDate=null` 장기 지원서 → `workDate`로 `contractStart` 폴백 | `contractStart = _fmtDate(application.desiredStartDate ?? application.workDate)` | `_buildSnapshot():721-722` | ✅ |
| E-017 | 경계값 | `workEndDate=null` 장기 지원서 → `contractEnd=''` | `_fmtDate(null) = ''` | `_buildSnapshot():723` + `_fmtDate():791` | ✅ |
| E-018 | 경계값 | `workerAddress=null`+`detailAddress=null` → `workerAddress=null` | join → trim → isEmpty → null | `_buildSnapshot():706-716` | ✅ |
| E-019 | 경계값 | 단기 동일 지원서 `findOrCreateContract` 재호출 (`applicationId` 중복) | `_addSlot()`에 중복 체크 없음 → 동일 applicationId 슬롯 2개 추가 | `_addSlot():564-596` 중복 체크 없음 | ⚠️ 중복 슬롯 가능 |
| E-020 | 경계값 | `_findBundle()` 복합 인덱스 미생성 에러 | `FAILED_PRECONDITION` → rethrow | `getByApplication():376-380` | ✅ |

---

## E-021~040: 서명 처리

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| E-021 | 정상 | 사업주 서명 — `isNewUnsaved=true` 최초 저장 | 트랜잭션으로 doc 존재 여부 체크 후 `tx.set()` | `saveEmployerSignature():123-134` | ✅ |
| E-022 | 경계값 | 사업주 서명 중복 제출 (`isNewUnsaved=true`, doc 이미 존재) | 트랜잭션에서 `snap.exists → throw Exception('이미 계약서가 생성되었습니다')` | `saveEmployerSignature():129-131` | ✅ |
| E-023 | 정상 | 사업주 서명 — `isNewUnsaved=false` 기존 계약서 업데이트 | 트랜잭션으로 `employerSignatureUrl != null` 체크 후 update | `saveEmployerSignature():136-155` | ✅ |
| E-024 | 경계값 | 사업주 이미 서명된 계약서 재서명 시도 (`employerSignatureUrl != null`) | `throw Exception('이미 사업주 서명이 완료된 계약서입니다')` | `saveEmployerSignature():101-103` 조기 반환 | ✅ |
| E-025 | 경계값 | 완료된 계약서에 사업주 서명 재시도 | `throw Exception('이미 완료된 계약서입니다')` | `saveEmployerSignature():98-100` | ✅ |
| E-026 | 오류복구 | 사업주 서명 — Storage 업로드 성공, Firestore 트랜잭션 실패 | 업로드된 서명 파일 삭제 시도 (K-004), rethrow | `saveEmployerSignature():158-168` | ✅ |
| E-027 | 경계값 | 사업주 서명 파일 삭제 실패 (K-004) | `debugPrint('⚠️ [K-004]...')`, 예외 재발생 | `saveEmployerSignature():163-166` | ✅ |
| E-028 | 정상 | 사업주 서명 완료 → 근무자에게 서명 요청 알림 발송 | `createNotification(ContractSignRequested)` | `saveEmployerSignature():171-183` | ✅ |
| E-029 | 경계값 | 알림 발송 실패 → 서명 완료는 유지 | `catch(e) → debugPrint`, 서명 결과 반환 | `saveEmployerSignature():181-183` | ✅ |
| E-030 | 정상 | 근무자 서명 완료 → status=completed, pdfUrl 저장 | 트랜잭션으로 완료 처리 | `saveWorkerSignature():236-272` | ✅ |
| E-031 | 경계값 | 근무자 서명 중복 제출 (`workerSignatureUrl != null`) | 트랜잭션에서 `throw Exception('이미 근무자 서명이 완료된 계약서입니다')` | `saveWorkerSignature():243-245` | ✅ |
| E-032 | 경계값 | 근무자 서명 — PDF 업로드 실패 → 서명 이미지 롤백 | `catch → signature_worker.png 삭제 → rethrow` | `saveWorkerSignature():212-219` | ✅ |
| E-033 | 오류복구 | 근무자 서명 — Firestore 트랜잭션 실패 → 서명+PDF 삭제 | `catch → signature_worker.png + contract.pdf 삭제 → rethrow` | `saveWorkerSignature():273-281` | ✅ |
| E-034 | 정상 | 근무자 서명 완료 → CONTRACT_PENDING 지원서들 CONFIRMED 원자 갱신 | `tx.update(appRef, status: 'CONFIRMED')` (CONTRACT_PENDING인 경우만) | `saveWorkerSignature():256-271` | ✅ |
| E-035 | 경계값 | 근무자 서명 — 연결 지원서 중 이미 CONFIRMED인 경우 | `CONTRACT_PENDING`이 아니면 update skip | `saveWorkerSignature():260` | ✅ |
| E-036 | 정상 | 근무자 서명 완료 → 계약 완료 알림 발송 | `createNotification(ApplicationConfirmed)` | `saveWorkerSignature():285-301` | ✅ |
| E-037 | 경계값 | `contractStart=null` 장기 계약서 알림 — workDate 폴백 | `contractStart != null ? DateTime.parse(contractStart) : DateTime.now()` | `saveWorkerSignature():292-294` | ✅ |
| E-038 | 경계값 | SHA-256 서명 해시 저장 — 사업주 서명 | `employerSignatureHash = sha256.convert(bytes).toString()` | `saveEmployerSignature():122` | ✅ |
| E-039 | 경계값 | SHA-256 서명 해시 저장 — 근무자 서명 | `workerSignatureHash = sha256.convert(bytes).toString()` | `saveWorkerSignature():235` | ✅ |
| E-040 | 정상 | 서명 없이 서명 화면 동의 체크박스 미체크 후 서명 버튼 클릭 | `if (!_agreed) → ToastHelper.showWarning('내용 확인 동의가 필요합니다')` | `contract_sign_screen.dart:172-174` | ✅ |

---

## E-041~055: 계약서 조회

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| E-041 | 정상 | `getByApplication()` — applicationId 직접 매칭 | 1번 쿼리에서 반환 | `getByApplication():349-360` | ✅ |
| E-042 | 정상 | `getByApplication()` — 번들 슬롯 applicationId (2번째 지원서) | 1번 쿼리 빈 결과 → 2번 `applicationIds arrayContains` 쿼리 반환 | `getByApplication():361-373` | ✅ |
| E-043 | 경계값 | `getByApplication()` — workerId/businessId 둘 다 null | `assert` 실패 (개발 환경) — 릴리스에서는 무시됨 | `getByApplication():345-346` assert | ⚠️ 릴리스 빌드 assert 비활성화 |
| E-044 | 경계값 | `getByApplication()` — 일치 계약서 없음 | `null` 반환 | `getByApplication():374` | ✅ |
| E-045 | 경계값 | `getByApplication()` — 복합 인덱스 누락 | `FAILED_PRECONDITION → rethrow` | `getByApplication():375-380` | ✅ |
| E-046 | 정상 | `getByWorkerPaged()` — 첫 페이지 조회 (pageSize=20) | 최대 20건 반환, `hasMore = snap.docs.length == 20` | `getByWorkerPaged():404-406` | ✅ |
| E-047 | 경계값 | `getByWorkerPaged()` — 정확히 20건인 경우 | `hasMore=true` (20 == 20), 다음 페이지 조회 시 0건 → `hasMore=false` | `getByWorkerPaged():404` `length == pageSize` | ⚠️ off-by-one: 실제 마지막 페이지인지 다음 페이지 조회 전까지 알 수 없음 |
| E-048 | 정상 | `getByWorkerPaged()` — statusFilter 지정 | `where('status', isEqualTo: statusFilter.value)` 필터 적용 | `getByWorkerPaged():401-403` | ✅ |
| E-049 | 정상 | `getByWorkerPaged()` — startAfter 커서 전달 | `startAfterDocument(startAfter)` 적용 | `getByWorkerPaged():405` | ✅ |
| E-050 | 정상 | `getByBusinessPaged()` — 사업장 계약서 첫 페이지 | 최대 20건, hasMore 반환 | `getByBusinessPaged():434-459` | ✅ |
| E-051 | 정상 | `AdminContractManagement` — 스크롤 하단 도달 시 자동 추가 로드 | `_onScroll()` → `_loadMore()` 호출 | `admin_contract_management_screen.dart:94-100` | ✅ |
| E-052 | 정상 | `AdminContractManagement` — 탭 전환 시 목록 새로고침 | `_tabCtrl.addListener → _refresh()` | `admin_contract_management_screen.dart:76-78` | ✅ |
| E-053 | 경계값 | `AdminContractManagement` — 검색어 입력 중 hasMore=true 안내 배너 표시 | `_searchQuery.isNotEmpty && _hasMore → 안내 컨테이너` | `admin_contract_management_screen.dart:210-221` | ✅ |
| E-054 | 경계값 | `getByWorker()` 하위 호환 메서드 — limit 없음 | 전체 계약서 조회. 근무자 계약 1,000건 이상 시 성능 저하 가능 | `contract_service.dart:419-430` | ⚠️ limit 없음 |
| E-055 | 경계값 | `getByBusiness()` 하위 호환 메서드 — limit 없음 | 전체 계약서 조회. 대형 사업장에서 성능 저하 가능 | `contract_service.dart:463-476` | ⚠️ limit 없음 |

---

## E-056~065: 계약서 무효화

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| E-056 | 정상 | 완료된 계약서 무효화 → 연결 지원서 CANCELED + status=voided | `cancelConfirmedApplication` 루프 → contract update | `voidContract():482-522` | ✅ |
| E-057 | 정상 | 무효화 — 연결 지원서 전부 성공 취소 | `failedIds=[] → voidFailedAppIds 미저장 → 예외 없음` | `voidContract():511-515` | ✅ |
| E-058 | 경계값 | 무효화 — 일부 지원서 취소 실패 | `failedIds 있음 → voidFailedAppIds 저장 → throw Exception('N개 실패')` | `voidContract():518-522` | ✅ |
| E-059 | **🔴 BUG-E-01** | 이미 `voided` 상태 계약서 재무효화 시도 | 실제: 이미 취소된 지원서 재취소 시도 → all failedIds → 오해 토스트 / 기대: 조기 반환 | `voidContract():482` 상태 검증 없음 | ❌ BUG-E-01 |
| E-060 | 경계값 | 존재하지 않는 계약서 ID 무효화 | `!contractDoc.exists → return` | `voidContract():484-485` | ✅ |
| E-061 | 경계값 | UI — 이미 voided 계약서 카드에 무효화 버튼 노출 여부 | `onVoid: item.status != ContractStatus.voided ? () => _voidContract(item) : null` → null | `admin_contract_management_screen.dart:243-245` | ✅ |
| E-062 | 경계값 | 무효화 — `isVoidingContract=true` 상태에서 재클릭 | `if (_isVoidingContract) return` | `admin_contract_management_screen.dart:158` | ✅ |
| E-063 | 정상 | 무효화 다이얼로그 취소 → 아무 변경 없음 | `ok != true → return` | `admin_contract_management_screen.dart:170` | ✅ |
| E-064 | 경계값 | 무효화 오류 시 에러 토스트 | `catch(e) → ToastHelper.showError('무효 처리에 실패했습니다')` | `admin_contract_management_screen.dart:178` | ✅ |
| E-065 | 경계값 | `voidContract()` — `applicationIds=[]` 빈 계약서 무효화 | 루프 스킵 → failedIds=[] → contract voided 정상 처리 | `voidContract():492` for loop empty | ✅ |

---

## E-066~075: 템플릿 관리

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| E-066 | 정상 | 계약서 템플릿 생성 | Firestore `businesses/{id}/contract_templates` subcollection에 저장 | `ContractTemplateService.createTemplate()` | ✅ |
| E-067 | 정상 | 템플릿 조회 — `createdAt` 오름차순 | `orderBy('createdAt', descending: false)` | `ContractTemplateService.getTemplates():17` | ✅ |
| E-068 | 정상 | 템플릿 수정 (name, templateType, articles) | `_col(businessId).doc(id).update({...})` | `ContractTemplateService.updateTemplate()` | ✅ |
| E-069 | 정상 | 템플릿 복제 — 이름 뒤 '(복사)' 추가 | `'${source.name} (복사)'`, articles 내용 복사 | `ContractTemplateService.duplicateTemplate()` | ✅ |
| E-070 | 경계값 | 복제 템플릿 — articles ContractArticle 새 인스턴스 생성 | `ContractArticle(title, content)` 새 복사본 | `duplicateTemplate():63-65` | ✅ |
| E-071 | 정상 | 템플릿 삭제 — Firestore subcollection에서 제거 | `_col(businessId).doc(templateId).delete()` | `deleteTemplate()` | ✅ |
| E-072 | 경계값 | 계약서에 참조 중인 템플릿 삭제 | 기존 계약서 articles는 서명 시점 복사본 → 무결성 영향 없음 (templateId만 dangling) | 계약서 생성 시 articles 복사 설계 | ✅ |
| E-073 | 경계값 | `getTemplates()` — limit 없음 (템플릿 수 상한 없음) | 사업장당 템플릿이 100건 미만으로 예상되어 현재 허용 | `getTemplates():17` limit 없음 | ⚠️ 다수 템플릿 시 성능 저하 |
| E-074 | 정상 | `updateArticles()` — 구 계약서에 신규 템플릿 조항 소급 적용 | `articles`, `templateId`, `updatedAt` 업데이트 | `updateArticles():321-331` | ✅ |
| E-075 | 경계값 | `updateArticles()` — 완료(completed) 계약서에 호출 | 상태 검증 없이 articles 덮어씌움 (의도된 레거시 보정 케이스) | `updateArticles()` 상태 체크 없음 | ⚠️ 완료 계약서 수정 가능 |

---

## E-076~085: 서명 화면 동작

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| E-076 | 정상 | 사업주 — 인감 등록됨 → 서명 버튼 클릭 시 인감 날인 | `_hasSeal=true → base64Decode → _performSign` | `contract_sign_screen.dart:209-211` | ✅ |
| E-077 | 경계값 | 사업주 — 인감 미등록 → 안내 다이얼로그 표시 | `!_hasSeal → AlertDialog('인감 미등록')` | `contract_sign_screen.dart:191-208` | ✅ |
| E-078 | 정상 | 근무자 — 사전 등록 서명 있음 → 서명 방법 선택 바텀시트 표시 | `_hasSavedSignature → _showSignatureOptions()` | `contract_sign_screen.dart:179-180` | ✅ |
| E-079 | 정상 | 근무자 — 사전 등록 서명 없음 → 직접 서명 패드 표시 | `!_hasSavedSignature → _signWithPad(askToSave: true)` | `contract_sign_screen.dart:182-183` | ✅ |
| E-080 | 경계값 | 스크롤 불필요 시 `_hasReadAll` 자동 해제 | `maxScrollExtent <= 0 → setState(_hasReadAll = true)` | `contract_sign_screen.dart:81-85` | ✅ |
| E-081 | 경계값 | 스크롤 하단 60px 이내 → `_hasReadAll=true` | `pixels >= maxScrollExtent - 60` | `contract_sign_screen.dart:163-165` | ✅ |
| E-082 | 경계값 | `_isSigning=true` 상태에서 서명 버튼 재클릭 방지 | UI에서 `_isSigning` 동안 버튼 비활성화 | `contract_sign_screen.dart:44` `_isSigning` | ✅ |
| E-083 | 경계값 | TO 타입 'contract' 구 계약서 — `_toIsContract=true` 보정 → isLongTerm 표시 | `_checkTOType() → setState(_toIsContract=true)` | `contract_sign_screen.dart:146-148` | ✅ |
| E-084 | 경계값 | `snapshot.ownerName` 빈 문자열 → business 문서 → users 문서 조회 | `ownerName.isEmpty → sealBase64 로드 + ownerName 폴백 조회` | `contract_sign_screen.dart:100-120` | ✅ |
| E-085 | 경계값 | 인감/대표자 로드 중 네트워크 에러 | `catch → debugPrint('인감/대표자 로드 실패')`, 화면 계속 표시 | `contract_sign_screen.dart:133-135` | ✅ |

---

## E-086~095: 계약서 스냅샷 무결성

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| E-086 | 정상 | 서명 완료 후 근무 조건 변경 → 계약서 스냅샷은 서명 시점 고정 | `ContractSnapshot`은 서명 시점 복사본 → TO 수정 영향 없음 | 설계: snapshot 불변 | ✅ |
| E-087 | 정상 | `payScheduleType='same_day'` 스냅샷 → `payScheduleLabel='당일'` | `case 'same_day': return '당일$timeStr'` | `ContractSnapshot.payScheduleLabel` | ✅ |
| E-088 | 정상 | `payScheduleType='weekly', payScheduleDay=5(금)` → `'매주 금요일'` | `_weekdayLabels[5] = '금'` | `ContractSnapshot.payScheduleLabel` | ✅ |
| E-089 | 경계값 | `payScheduleDay=31` (월말일) → `'매월 말일'` | `d == 31 ? '말일' : '$d일'` | `ContractSnapshot.payScheduleLabel` | ✅ |
| E-090 | 경계값 | `payScheduleType=null` → wagePaymentDay 레거시 폴백 | `wagePaymentDay != null → '매월 N일', else '별도 협의'` | `ContractSnapshot.payScheduleLabel:266-268` | ✅ |
| E-091 | 경계값 | `hourlyWage` 계산 — 일급제, workMins=0 | `workMins <= 0 → null` | `ContractSnapshot.hourlyWage:314-315` | ✅ |
| E-092 | 경계값 | `workTimeText` — 자정 넘어가는 근무 (23:00~07:00) | `if (em < sm) em += 24*60` → 올바른 시간 계산 | `ContractSnapshot._timeDiff():342` | ✅ |
| E-093 | 경계값 | `workTimeText` — 잘못된 시간 형식 ('aa:bb') | `sp.length < 2 → return 0` | `ContractSnapshot._timeDiff():339` | ✅ |
| E-094 | 경계값 | `taxDeductionType` 미저장 레거시 계약서 → `typeNone` 폴백 | `m['taxDeductionType'] as String? ?? InsuranceRateModel.typeNone` | `ContractSnapshot.fromMap():235` | ✅ |
| E-095 | 경계값 | `snapshot` 필드 누락 Firestore 문서 → `ArgumentError` | `d['snapshot'] == null → throw ArgumentError` | `EmploymentContractModel.fromMap():456-457` | ✅ |

---

## E-096~100: 로컬 저장 / 기타

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| E-096 | 정상 | PDF 로컬 임시 파일 저장 (`savePdfLocally`) | `getTemporaryDirectory()` → `file.writeAsBytes(bytes)` | `contract_service.dart:778-786` | ✅ |
| E-097 | 정상 | 사용자 서명 base64 저장 (`saveUserSignature`) | `users/{uid}.signatureBase64 = base64` | `contract_service.dart:308-312` | ✅ |
| E-098 | 정상 | 사용자 서명 삭제 (`clearUserSignature`) | `users/{uid}.signatureBase64 = null` | `contract_service.dart:316-318` | ✅ |
| E-099 | 경계값 | `ContractStatusX.fromString()` 알 수 없는 값 입력 | `default: return ContractStatus.pendingEmployer` | `employment_contract_model.dart:38-39` | ✅ |
| E-100 | 경계값 | `ContractSlot.fromMap()` 필드 누락 → 기본값 폴백 | `applicationId: m['applicationId'] ?? ''`, startTime/endTime 기본값 | `employment_contract_model.dart:72-79` | ✅ |

---

## 발견된 버그 상세

### BUG-E-01 (LOW): voidContract — 이미 voided 상태 검증 없음

**파일**: [contract_service.dart:482](lib/services/contract_service.dart#L482)

**현상**: `voidContract()`가 이미 `voided`인 계약서에 재호출되면, 연결된 지원서들이 이미 `CANCELED` 상태이므로 `cancelConfirmedApplication`이 false를 반환하고 모두 failedIds에 포함됨. 계약서는 다시 voided로 갱신되지만, `throw Exception(...)` 이 발생하여 UI에서 "무효 처리에 실패했습니다" 오해 토스트가 표시됨.

UI에서는 `onVoid: item.status != ContractStatus.voided ? ... : null`로 버튼을 숨기지만, 서비스 레이어 자체에 방어가 없음.

**수정**:
```dart
Future<void> voidContract(String contractId) async {
  final contractDoc = await _db.collection('employment_contracts').doc(contractId).get();
  if (!contractDoc.exists) return;

  final contract = EmploymentContractModel.fromFirestore(contractDoc);

  // 이미 voided 상태면 조기 반환 (재호출 방어)
  if (contract.status == ContractStatus.voided) return;
  // 이하 기존 로직...
```

---

## 추가 검증 필요 (⚠️) 요약

| # | 시나리오 | 내용 |
|---|----------|------|
| E-019 | 중복 슬롯 가능성 | `_addSlot()`에 applicationId 중복 체크 없음 — 동일 지원서 이중 확정 시 슬롯 2개 |
| E-043 | assert 릴리스 비활성화 | `getByApplication()` assert가 릴리스 빌드에서 무시됨 — 권한 오류로만 실패 |
| E-047 | off-by-one hasMore | `pageSize == snap.docs.length`이면 hasMore=true — 실제 마지막 페이지일 수 있음 |
| E-054 | getByWorker limit 없음 | 하위 호환 메서드, 대규모 근무자 데이터 시 성능 저하 |
| E-055 | getByBusiness limit 없음 | 하위 호환 메서드, 대형 사업장 데이터 시 성능 저하 |
| E-073 | getTemplates limit 없음 | 템플릿 다수 생성 시 성능 저하 |
| E-075 | 완료 계약서 articles 수정 가능 | 레거시 보정 목적 의도된 동작이나, 완료 계약서 불변성 원칙과 충돌 |
