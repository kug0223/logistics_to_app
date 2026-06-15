# Category Q — 급여 화면 검증 (100개 시나리오)

> 대상 파일:
> - `lib/screens/business_admin/payroll/payroll_overview_screen.dart`
> - `lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart`
> - `lib/screens/business_admin/payroll/payroll_worker_detail_screen.dart`
> - `lib/screens/business_admin/payroll/today_payment_screen.dart`
> - `lib/screens/business_admin/admin_month_detail_screen.dart`
>
> 버그 수정: 없음
> 경고: ⚠️ Q-01 (워커 상세 limit 500), ⚠️ Q-02 (netWage 0 처리 일관성), ⚠️ Q-03 (임시 파일 미정리)

---

## 수정된 버그

없음 — 분석된 의심 패턴들을 코드 검증한 결과:
- `DateTime(year, month+1, 0)` 패턴: Dart 정상 동작 (month 경계 처리 의도적)
- `payroll_worker_detail_screen.dart:472` mounted 체크: `if (app == null || !context.mounted) return;` 존재 확인
- netWage 계산 불일치: 화면별 컨텍스트 차이 (설계 의도)

---

## 경고

### ⚠️ Q-01 — `payroll_worker_detail_screen.dart` limit(500) 하드코딩
- 한 달 근무 레코드 500건 초과 시 일부 미표시
- 현재 규모에서 발생 불가 — 수용

### ⚠️ Q-02 — 금액 계산 로직 화면별 미세 차이
- `today_payment_screen.dart`: `netWage > 0 ? netWage : totalAmount`
- `payroll_payment_dashboard_screen.dart`: `netWage > 0 ? netWage : (totalAmount - totalInsuranceDeduction)`
- 보험료 차감 방식 차이 → 대시보드 표시 금액과 오늘 지급 표시 금액 미세 불일치 가능
- 실제 이체 금액은 `markTransferred()` 내에서 재계산 — 수용

### ⚠️ Q-03 — `admin_month_detail_screen.dart` 임시 파일 미정리
- Excel 내보내기 시 `getTemporaryDirectory()`에 파일 생성 후 cleanup 없음
- 공유 후 파일 잔류 (시스템이 주기적으로 정리)
- 수용

---

## 테스트 시나리오

### [PayrollOverviewScreen — 급여 개요]

**Q-001** 화면 진입 → 현재 연도 자동 선택, 사업장 조회 후 _loadYear() + _loadTodayCount() 병렬 로드

**Q-002** 연도 왼쪽 화살표 탭 → 이전 연도 데이터 로드

**Q-003** 연도 오른쪽 화살표 탭 — 현재 연도인 경우 → 다음 연도 이동 불가

**Q-004** 연도 왼쪽 화살표 탭 — 2015년 이하 → 로드 방지

**Q-005** 12개월 그리드 카드 표시 → 현재 월 이후 카드 비활성화 (isFuture=true)

**Q-006** 과거 월 카드 클릭 → PayrollMonthDetailScreen(또는 AdminMonthDetailScreen) 이동

**Q-007** 오늘 지급 건수 > 0 → 상단 배너 표시 (배너 클릭 → TodayPaymentScreen)

**Q-008** TodayPaymentScreen 복귀 후 → _loadTodayCount() 재실행, 배너 업데이트

**Q-009** 오늘 지급 건수 = 0 → 배너 미표시

**Q-010** 월별 카드 — 근무자 수 + 확정 건수 표시

**Q-011** 월별 카드 — 총 지급액 한글 단위 포맷팅 (만/천원 단위)

**Q-012** 사업장 조회 실패 → 에러 상태 처리

**Q-013** 로딩 중 → LoadingWidget 표시

**Q-014** mounted 체크로 화면 전환 중 setState 오류 방지

**Q-015** 가로 모드 → 레이아웃 유지 확인

---

### [PayrollPaymentDashboardScreen — 급여 지급 대시보드]

**Q-016** 화면 진입 → 4개 탭 (미이체/이체완료/변경요청/중간정산) 동시 로드

**Q-017** 미이체 탭 — (근무자+지급일) 기준 그룹화된 카드 표시

**Q-018** 검색 입력 → 이름 기반 필터링 + 근무자 수 업데이트

**Q-019** 퀵필터 '전체' → 모든 그룹 표시

**Q-020** 퀵필터 '연체' → 지급 기한 경과 건만 표시

**Q-021** 퀵필터 '오늘마감' → 오늘 지급일 건만 표시

**Q-022** 탭 전환 → 배치모드 자동 해제 (TabController listener)

**Q-023** 일괄선택 버튼 탭 → 배치모드 활성화 + 체크박스 표시

**Q-024** 배치모드 — 개별 카드 탭 → 선택 상태 토글

**Q-025** 배치모드 — '모두선택' → _selectedIds 전체 추가

**Q-026** 배치모드 — '모두해제' → _selectedIds 전부 제거

**Q-027** 단건 '송금' 버튼 → 확인 다이얼로그 + 메모 입력 다이얼로그

**Q-028** 메모 '건너뛰기' → note=null로 markTransferred() 호출

**Q-029** 송금 처리 완료 → _load() 재실행 + 성공 토스트

**Q-030** 일괄 송금 → markTransferredBatch() 호출 + _load() 재실행

**Q-031** 이체완료 탭 → 이체일 표시 + '이체완료' 배지

**Q-032** 변경요청 탭 → '승인' / '거절' 버튼 표시

**Q-033** 중간정산 탭 → pending 상태만 버튼 활성화

**Q-034** 미이체 탭 — '더 불러오기' 탭 → 다음 페이지 추가 로드 (_hasMorePending)

**Q-035** 이체완료 탭 — '더 불러오기' 탭 → 다음 페이지 추가 로드 (_hasMoreTransferred)

**Q-036** 계좌 정보 마스킹 → 뒤 4자리만 표시 (예: ****1234)

**Q-037** CSV 내보내기 버튼 → 파일 생성 + 공유 화면 표시

**Q-038** 요약 헤더 → 연체 건수 > 0 시 경고 배지 표시

**Q-039** 네트워크 오류 → 에러 토스트 + UI 유지

**Q-040** mounted 체크 — 다이얼로그 후 화면 전환 시 stale context 방지 확인

---

### [PayrollWorkerDetailScreen — 근무자 급여 상세]

**Q-041** 화면 진입 → 해당 월의 확정/이체완료 레코드 최대 500건 로드 (⚠️ Q-01)

**Q-042** 요약 헤더 → 실수령합계 / 송금완료액 / 미송금액 / 근무일수 / 총근무시간 표시

**Q-043** 레코드 리스트 → 날짜 오름차순 정렬, 날짜 + 금액 + 송금상태 배지 표시

**Q-044** 레코드 클릭 — wageDetail 있음 → ApplicationModel + UserModel 조회 후 WageDetailDialog 표시

**Q-045** 레코드 클릭 — wageDetail null → 클릭 무시 (return early)

**Q-046** WageDetailDialog 표시 전 mounted 체크 → `if (app == null || !context.mounted) return;` 확인

**Q-047** 빈 레코드 → "확정된 급여 내역이 없습니다" 메시지 표시

**Q-048** '명세서' 버튼 탭 → 바텀시트 (월간/주간 선택)

**Q-049** '월간 명세서' 선택 → 해당 월 전체 레코드 기반 PDF 생성 + 공유

**Q-050** '주간 명세서' 선택 → 주차 칩 표시, 해당 주차에 레코드 없으면 칩 비활성화

**Q-051** 주간 명세서 — 주차 선택 → 해당 주간 레코드만 필터링 후 PDF 생성

**Q-052** '중간정산 처리' 메뉴 탭 → 확정 미이체 레코드만 선택하여 다이얼로그 표시

**Q-053** 중간정산 다이얼로그 → 대상 건수 + 합계 금액 표시

**Q-054** 중간정산 확인 → InterimSettlementRequest 생성 + 즉시 approveInterimSettlement() 호출

**Q-055** 중간정산 완료 후 → _loadRecords() 재호출 + 레코드 상태 '이체완료'로 갱신

**Q-056** 중간정산 가능한 레코드 없음 → "확정 급여가 없습니다" 경고 토스트

**Q-057** 네트워크 오류 → 에러 메시지 + 화면 유지

---

### [TodayPaymentScreen — 오늘 지급]

**Q-058** 화면 진입 → 지급 예정일 ≤ 오늘인 확정 레코드 조회 + uid별 이름 캐시 병렬 로드

**Q-059** 레코드 없음 → "오늘 처리할 송금이 없습니다" empty state

**Q-060** 레코드 있음 → payScheduleType별 그룹 섹션 표시 (당일/익일/주급/월급 순)

**Q-061** 요약 헤더 → 총 송금액 + 연체 건수 표시

**Q-062** 퀵필터 '전체' → 모든 레코드 표시

**Q-063** 퀵필터 '연체' → 연체 건만 필터링

**Q-064** 퀵필터 '오늘마감' → 오늘 지급일 건만 필터링

**Q-065** 퀵필터 변경 시 → _selectedIds 초기화 (배치 선택 리셋)

**Q-066** 일괄선택 버튼 → 배치모드 활성화

**Q-067** '모두선택' → 현재 필터된 레코드 전체 선택

**Q-068** 단건 '송금' → 확인 다이얼로그 + 메모 입력 (선택)

**Q-069** 메모 '건너뛰기' → note=null 처리 후 markTransferred()

**Q-070** 일괄 송금 처리 → "N건 송금 처리되었습니다" 토스트

**Q-071** 처리 완료 후 → _load() 재실행 + 처리된 레코드 목록에서 제거

**Q-072** CSV 내보내기 → 현재 레코드 기준 파일 생성 + 공유

**Q-073** 네트워크 오류 → 에러 토스트 + 목록 유지

---

### [AdminMonthDetailScreen — 관리자 월별 상세]

**Q-074** 화면 진입 → AdminStatsService.getMonthDetail()으로 MonthDetailData 로드

**Q-075** 로딩 중 → LoadingWidget 표시

**Q-076** 데이터 없음 → "근무 데이터가 없습니다" empty state

**Q-077** 네트워크 오류 → 에러 메시지 + '다시 시도' 버튼

**Q-078** 근태 현황 요약 → 정상(초록)/지각(주황)/결근(빨강) 비율 바 표시

**Q-079** 비율 바 → presRatio 0.0 → flex=0 처리 (Row 렌더링 오류 없음 확인)

**Q-080** 리뷰 요약 → 데이터 있을 때만 평균 별점 + 재고용율 표시

**Q-081** 상위 리뷰 태그 2개 → 색상 칩으로 표시

**Q-082** 근무자 테이블 → 이름 / 근무일 / 출결현황 / 임금 컬럼 표시

**Q-083** 정렬 칩 '근무일' → 근무일 많은 순 정렬

**Q-084** 정렬 칩 '임금' → 임금 많은 순 정렬

**Q-085** 정렬 칩 '이름' → 이름 사전순 정렬

**Q-086** 정렬 칩 재탭 → 캐시 초기화 후 재정렬 확인

**Q-087** 근무일 컬럼 → 숫자 + 'n일' 표시

**Q-088** 출결현황 → 지각/결근 배지 또는 초록 점(정상) 표시

**Q-089** 임금 컬럼 — 확정 전 → '미확정' 텍스트, 확정 후 → 금액 (만/천 단위 축약)

**Q-090** 엑셀 내보내기 버튼 탭 → 파일 생성 시작

**Q-091** 단일 사업장 → 시트 1개 생성

**Q-092** 복수 사업장 → 사업장별 시트 + '전체' 통합 시트 생성

**Q-093** 엑셀 컬럼 → 사업장명/근무일자/파트/이름/성별/연락처/출근시간/퇴근시간/비고 (9개) 확인

**Q-094** 엑셀 정렬 → 사업장별 → 근무일자순 → 이름순

**Q-095** 엑셀 내보내기 완료 → 공유 시트 표시 (⚠️ Q-03: 임시 파일 미정리 수용)

---

### [통합 시나리오]

**Q-096** 급여 개요 → 이번 달 카드 탭 → 근무자 상세 → 레코드 확인 → 명세서 발행 플로우

**Q-097** 오늘 지급 배너 탭 → TodayPaymentScreen → 일괄 선택 → 일괄 송금 처리 → 배너 업데이트

**Q-098** 급여 대시보드 → 미이체 탭 → 개별 송금 → 이체완료 탭으로 이동 확인

**Q-099** 중간정산 처리 → 레코드 상태 갱신 → 대시보드 중간정산 탭에 표시 확인

**Q-100** 월별 상세 → 엑셀 내보내기 → 파일 내용 정합성 (이름/날짜/금액) 육안 확인

---

## 체크리스트

| 구분 | 항목 | 상태 |
|------|------|------|
| 수정 버그 | 없음 | - |
| ⚠️ Q-01 | 워커 상세 limit(500) 하드코딩 | 수용 |
| ⚠️ Q-02 | netWage 0 처리 화면별 차이 | 수용 |
| ⚠️ Q-03 | 임시 파일 미정리 | 수용 |
