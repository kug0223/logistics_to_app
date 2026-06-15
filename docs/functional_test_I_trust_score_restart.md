# Category I — 신뢰도(Trust Score) · 재시작 프로그램 기능 테스트 시나리오

> 대상 파일:
> - `lib/services/trust_score_service.dart`
> - `lib/widgets/dialogs/trust_score_info_dialog.dart`
> - `lib/widgets/dialogs/restart_program_dialog.dart`
> - `lib/screens/super_admin/trust_rules_settings_screen.dart`
> - `functions/src/index.ts` (applyRestartProgram CF)
>
> 버그 수정: BUG-I-01, BUG-I-02, BUG-I-03 (3건)
> 경고: ⚠️ I-01 (설정 캐시 stale 시나리오)

---

## 수정된 버그

### BUG-I-01 (Critical) — `onNoShowCanceled()` TOCTOU 취약점
- **파일**: `lib/services/trust_score_service.dart`
- **증상**: noShowCount를 읽은 후(`get()`) 별도의 `update()` 호출 — 두 호출 사이에 다른 프로세스가 카운트를 변경하면 잘못된 감면 점수 적용
- **수정**: `onNoShow()`와 동일하게 `runTransaction`으로 read+decrement 원자화

### BUG-I-02 (Medium) — `_validateInputs()` 재시작 프로그램 필드 검증 누락
- **파일**: `lib/screens/super_admin/trust_rules_settings_screen.dart`
- **증상**: resetScore, cooldownDays, noshowReduction, lateReduction에 음수/0/범위 초과 값 입력 후 저장 가능
- **수정**: 4개 필드 검증 추가 (resetScore 0~100, cooldownDays ≥ 1, 감면횟수 ≥ 0)

### BUG-I-03 (Medium) — 감소 규칙 저장 시 음수 입력 이중 부호 오류
- **파일**: `lib/screens/super_admin/trust_rules_settings_screen.dart`
- **증상**: 사용자가 "-3" 입력 시 `points: -(-3) = +3` 으로 저장 → 감소 규칙이 증가 규칙으로 역전
- **수정**: `(int.tryParse(...)).abs()` 추가로 음수 입력 방어

---

## 경고 (버그 수준 아님)

### ⚠️ I-01 — 설정 30분 캐시 stale 시나리오
- `TrustScoreService._getSettings()`는 30분 캐시를 사용
- SuperAdmin이 설정 변경 후 30분 이내에는 다른 서비스 인스턴스(CF 포함)가 구 설정으로 점수 계산 가능
- CF는 별도로 설정을 조회하므로 클라이언트 캐시 영향 없음; 클라이언트 캐시는 UI 표시용이므로 수용 가능

### ⚠️ I-02 — `TrustScoreInfoDialog` 하드코딩 등급 임계값
- 다이얼로그가 Firestore 설정값이 아닌 하드코딩 점수(60, 75, 90, 95)로 등급 기준 표시
- SuperAdmin이 설정 변경 시 UI 설명과 실제 로직 불일치 가능
- 현재 설계상 수용 가능 (정보성 UI); 향후 설정값 연동 고려 대상

---

## 테스트 시나리오 (I-001 ~ I-100)

### [신뢰도 점수 계산 — calculateTrustScore]

**I-001** `trustScore` 필드가 있는 사용자 → 저장된 값 그대로 반환 (재계산 없음)
- 조건: user.trustScore = 75
- 결과: 75 반환

**I-002** `trustScore` 필드가 없는 구 계정 → `_computeScore()` 실행 후 Firestore에 저장
- 조건: user.trustScore 필드 없음, totalWorkDays=10
- 결과: 계산된 점수 반환 + users/{uid}.trustScore 업데이트

**I-003** 사용자 문서 없음 → `settings.startScore` 반환 (기본 50)
- 결과: 50

**I-004** Firestore 오류 → 기본값 50 반환 (에러 전파 없음)

**I-005** `_computeScore` — 시작 점수 50 + 근무 10일(+10) = 60
- 조건: startScore=50, totalWorkDays=10, 리뷰 없음
- 결과: 60

**I-006** 평균 평점 4.8, 리뷰 5개 → 좋은평가 +10점 추가
- 조건: avgRating=4.8, reviewCount=5, goodReview.points=2
- 결과: startScore + workDays×1 + 5×2 = 50+0+10=60

**I-007** 평균 평점 1.5, 리뷰 3개 → 낮은평가 -6점 추가
- 조건: avgRating=1.5, reviewCount=3, badReview.points=-2
- 결과: 50 + 3×(-2) = 44

**I-008** 재고용률 0.8, 리뷰 5개 → 재고용 4회 +4점
- 조건: rehireRate=0.8, reviewCount=5, rehire.points=1
- 결과: 50 + (0.8×5).round()×1 = 54

**I-009** 재고용률 존재하지만 리뷰 2개(reviewCount < 3) → 재고용 점수 미적용
- 결과: 재고용 0점 추가

**I-010** 지각 5회 → -5점
- 조건: lateCount=5, lateRule.points=-1
- 결과: 50 - 5 = 45

**I-011** 노쇼 3회 — 누적 페널티 합산 (-3 + -4 + -5 = -12)
- 조건: noShowCount=3, 1회=-3, 2회=-4, 3회=-5
- 결과: 50 - 12 = 38

**I-012** 점수 계산 결과가 0 미만 → 0으로 clamp
- 조건: 노쇼 20회 누적
- 결과: 0

**I-013** 점수 계산 결과가 maxScore 초과 → maxScore로 clamp
- 조건: 근무 100일, 좋은평가 50개
- 결과: 100 (상한선)

---

### [점수 이벤트 — onWorkComplete / onWorkCanceled]

**I-014** `onWorkComplete(userId, businessId)` → trustScore +1 + history 기록
- 결과: users.trustScore += 1, trust_score_history 문서 추가

**I-015** `onWorkComplete` 후 점수가 maxScore(100)이면 → 100에서 고정
- 조건: 현재 점수 100
- 결과: 100 유지

**I-016** `onWorkCanceled(userId, businessId)` → 근무완료 점수 롤백 (-1)
- 결과: trustScore -= 1, history 기록 ('마감 취소')

**I-017** `onWorkCanceled` 후 점수가 0 미만이면 → 0으로 clamp
- 조건: 현재 점수 0
- 결과: 0 유지

---

### [점수 이벤트 — onLate / onNoShow / onNoShowCanceled]

**I-018** `onLate(userId, businessId)` → lateCount +1 + trustScore -1
- 결과: users.lateCount += 1, trustScore -= 1

**I-019** `onNoShow(userId, businessId)` 최초 1회 → noShowCount=1, penalty=-3
- 결과: users.noShowCount = 1, trustScore -= 3

**I-020** `onNoShow` 2회째 → noShowCount=2, penalty=-4
- 결과: trustScore -= 4 (누적 가중 페널티)

**I-021** `onNoShow` 트랜잭션 원자성 — 동시 2개 호출 시 noShowCount 최종=2 (not 1)
- 결과: runTransaction으로 race condition 방지 확인

**I-022** `onNoShowCanceled(userId, businessId)` — noShowCount 3→2, penalty(3회)=-5 → +5 복원 (BUG-I-01 수정)
- 결과: users.noShowCount = 2, trustScore += 5

**I-023** `onNoShowCanceled` 트랜잭션 원자성 — noShowCount read+decrement 원자화 확인 (BUG-I-01 수정)
- 조건: 동시에 noShow + noShowCanceled 호출
- 결과: noShowCount 최종값 일관성 보장

**I-024** `onNoShowCanceled` noShowCount=0인 상태에서 호출 → clamp(0, 9999) 로 noShowCount=0 유지, 점수 복원 없음 (penalty=0)
- 결과: 음수 카운트 방지

**I-025** `onNoShow` → `onNoShowCanceled` → 점수 net 변화 = 0 (대칭)
- 결과: 원래 점수와 동일

---

### [점수 이벤트 — onReviewReceived]

**I-026** rating=4.8, wouldRehire=true → +2(좋은평가) +1(재고용) = +3
- 결과: trustScore += 3

**I-027** rating=3.0, wouldRehire=false → 변화 없음 (4.5 미만, 2.0 초과)
- 결과: trustScore 변화 없음

**I-028** rating=1.5, wouldRehire=false → -2(낮은평가)
- 결과: trustScore -= 2

**I-029** rating=4.5 경계값 → 좋은평가 조건 충족 (+2)
- 결과: trustScore += 2

**I-030** rating=2.0 경계값 → 낮은평가 조건 충족 (-2)
- 결과: trustScore -= 2

**I-031** rating=4.8, wouldRehire=true, 현재 점수 99 → 101.clamp(0,100) = 100
- 결과: trustScore = 100 (상한선)

---

### [점수 변동 내역 — getScoreHistory]

**I-032** businessId 없이 호출 → userId 기준 최근 20건 조회 (슈퍼어드민 컨텍스트)
- 결과: trust_score_history 컬렉션에서 최신순 20개

**I-033** businessId 있는 경우 → userId + businessId 필터로 조회 (관리자 컨텍스트)
- 결과: 해당 사업장 관련 기록만 반환

**I-034** limit 파라미터 → `{int limit = 20}` 기본값, 커스텀 값 동작 확인
- 조건: limit=5
- 결과: 최대 5건 반환

**I-035** 내역 없는 사용자 → 빈 리스트 반환 (에러 없음)

**I-036** Firestore 오류 → 빈 리스트 반환 (에러 전파 없음)

**I-037** 반환 데이터 형식 확인 — id, previousScore, newScore, change, reason, createdAt(DateTime?) 포함

---

### [설정 캐시 — _getSettings / clearCache]

**I-038** 최초 호출 → Firestore에서 trust_rules 문서 조회, 캐시에 저장
- 결과: 설정 반환, _cachedSettings != null

**I-039** 30분 이내 재호출 → Firestore 호출 없이 캐시 반환
- 결과: 동일 설정 객체 반환

**I-040** 30분 초과 후 호출 → Firestore 재조회
- 결과: 최신 설정 반환

**I-041** trust_rules 문서 없음 → defaults 생성 후 Firestore에 저장
- 결과: TrustSettingsModel.defaults() 반환

**I-042** `clearCache()` 호출 → 캐시 무효화, 다음 호출 시 Firestore 재조회
- 결과: _cachedSettings=null, _settingsCacheTime=null

**I-043** Firestore 오류 → TrustSettingsModel.defaults() 반환 (에러 전파 없음)

---

### [재시작 프로그램 가능 여부 — canApplyRestart]

**I-044** 최초 신청 (lastRestartAt 없음) → canRestart=true
- 결과: {canRestart: true, reason: null, daysRemaining: null}

**I-045** lastRestartAt이 60일 이전 (cooldownDays=60) → canRestart=true
- 조건: lastRestartAt = 61일 전
- 결과: {canRestart: true}

**I-046** lastRestartAt이 30일 이전 (cooldownDays=60) → canRestart=false, daysRemaining=30
- 조건: lastRestartAt = 30일 전, cooldownDays=60
- 결과: {canRestart: false, daysRemaining: 30}

**I-047** cooldownEnd 당일 (daysRemaining=0) → canRestart=false, daysRemaining=0
- 결과: {canRestart: false, daysRemaining: 0}

**I-048** 사용자 문서 없음 → canRestart=false, reason='사용자 정보를 찾을 수 없습니다.'

**I-049** Firestore 오류 → canRestart=false, reason='확인 중 오류가 발생했습니다.'

---

### [RestartProgramDialog — UI]

**I-050** 다이얼로그 열기 → `_checkCanRestart()` 자동 호출, 로딩 표시
- 결과: LoadingWidget 표시 후 결과 화면으로 전환

**I-051** canRestart=true → 안내 메시지 + 비교 카드 + 준수사항 + 신청 버튼 표시

**I-052** canRestart=false, daysRemaining=15 → 쿨타임 메시지 "15일 후 다시 신청할 수 있습니다." 표시

**I-053** canRestart=false, daysRemaining=null → 쿨타임 메시지 (날짜 미표시)
- 결과: if (_daysRemaining != null) 블록 미표시

**I-054** 비교 카드 — currentScore=30, noShowCount=2, lateCount=3 → 50점, 1회, 2회로 표시

**I-055** noShowCount=0인 경우 비교 카드 → 0회 → max(0-1, 0)=0회로 표시 (음수 방지 clamp)

**I-056** 준수사항 체크박스 미체크 후 신청 → "준수사항에 동의해주세요." 토스트

**I-057** 준수사항 체크박스 체크 후 신청 → `applyRestartProgram` CF 호출

**I-058** CF 호출 성공 → 성공 토스트 + onSuccess 콜백 + Navigator.pop(context, true)

**I-059** FirebaseFunctionsException 발생 → e.message 에러 토스트, _isSubmitting=false, 다이얼로그 유지

**I-060** 일반 Exception 발생 → '재시작 프로그램 적용에 실패했습니다.' 에러 토스트

**I-061** 신청 중 (_isSubmitting=true) → 버튼 비활성화(null onPressed), CircularProgressIndicator 표시

**I-062** 취소 버튼 → Navigator.pop(context) (bool? 반환 없음)

**I-063** 점수 색상 — 90↑ 금색, 70↑ 초록, 50↑ 회색, 30↑ 주황, 30↓ 빨강

---

### [TrustScoreInfoDialog — UI]

**I-064** `TrustScoreInfoDialog.show(context)` → 다이얼로그 표시

**I-065** 다이얼로그 내용 — 설명, 올라가는 경우, 내려가는 경우, 등급 배지, 팁 섹션 모두 표시

**I-066** 올라가는 경우 — +1(정상 출퇴근), +2(좋은 평가 4.5 이상), +1(재고용 희망) 표시

**I-067** 내려가는 경우 — -1(지각), -3~10(노쇼), -2(낮은 평가 2.0 이하) 표시

**I-068** 등급 배지 — 브론즈(60↑), 실버(75↑), 골드(90↑), 다이아(95↑ + 100일) 표시

**I-069** '알겠어요!' 버튼 → Navigator.pop(context)

**I-070** SingleChildScrollView 적용 → 내용이 길어져도 스크롤 가능

---

### [TrustRulesSettingsScreen — 설정 화면]

**I-071** 화면 진입 → `_loadSettings()` 호출, Firestore trust_rules 조회

**I-072** trust_rules 문서 없음 → defaults 생성 후 Firestore 저장, 컨트롤러 초기화

**I-073** 기본 설정 섹션 — 시작 점수, 최대 점수 필드 표시

**I-074** 점수 증가 규칙 섹션 — 규칙별 필드 표시 (+prefix, 녹색)

**I-075** 점수 감소 규칙 섹션 — 규칙별 필드 표시 (-prefix, 빨강)

**I-076** 재시작 프로그램 섹션 — 리셋점수, 쿨다운, 노쇼감면, 지각감면 필드 표시

**I-077** 저장 전 확인 다이얼로그 → '저장하시겠습니까?' 확인 후 저장

**I-078** 유효성 검사 — startScore=-1 입력 → '시작 점수는 0~100 사이여야 합니다' 토스트 (BUG-I-02 수정)

**I-079** 유효성 검사 — maxScore=90, startScore=95 → '최대 점수는 시작 점수 이상' 오류 (BUG-I-02 수정)

**I-080** 유효성 검사 — resetScore=-5 → '재시작 리셋 점수는 0~100 사이여야 합니다' 오류 (BUG-I-02 수정)

**I-081** 유효성 검사 — cooldownDays=0 → '쿨다운 기간은 1일 이상이어야 합니다' 오류 (BUG-I-02 수정)

**I-082** 유효성 검사 — noshowReduction=-1 → '감면 횟수는 0 이상이어야 합니다' 오류 (BUG-I-02 수정)

**I-083** 유효성 검사 — 정수 아닌 값 입력 → '숫자만 입력해주세요' 오류

**I-084** 감소 규칙 필드에 "-3" 입력 → `.abs()` 처리로 3으로 저장, points=-3 (BUG-I-03 수정)
- 저장 전: "-3" 표시
- 저장 후: Firestore에 points=-3 (올바름)

**I-085** 저장 성공 → 'settings/trust_rules' 문서 갱신 + '설정이 저장되었습니다' 토스트

**I-086** 저장 실패 → '설정 저장에 실패했습니다' 에러 토스트

**I-087** 저장 중 (_isSaving=true) → 저장 버튼 비활성화, CircularProgressIndicator 표시

**I-088** 초기화 버튼 → 위험 확인 다이얼로그, 확인 시 defaults로 복원

**I-089** 초기화 성공 → 기존 컨트롤러 dispose + 새 컨트롤러 초기화 + '기본값으로 복원되었습니다' 토스트

**I-090** 초기화 실패 → '복원에 실패했습니다' 에러 토스트

---

### [신뢰도 등급 — TrustGrade]

**I-091** 점수 100 → TrustGrade.excellent ('최우수', '🌟', '#FFD700')

**I-092** 점수 90 → TrustGrade.excellent (경계값)

**I-093** 점수 89 → TrustGrade.good ('우수', '✅', '#4CAF50')

**I-094** 점수 70 → TrustGrade.good (경계값)

**I-095** 점수 69 → TrustGrade.normal ('보통', '😐', '#9E9E9E')

**I-096** 점수 50 → TrustGrade.normal (경계값)

**I-097** 점수 49 → TrustGrade.warning ('주의', '⚠️', '#FF9800')

**I-098** 점수 30 → TrustGrade.warning (경계값)

**I-099** 점수 29 → TrustGrade.danger ('경고', '🚨', '#F44336')

**I-100** 점수 0 → TrustGrade.danger (최저)

---

## 체크리스트

| 구분 | 항목 | 상태 |
|------|------|------|
| BUG-I-01 | onNoShowCanceled TOCTOU 트랜잭션화 | ✅ 수정 완료 |
| BUG-I-02 | _validateInputs 재시작 프로그램 필드 검증 추가 | ✅ 수정 완료 |
| BUG-I-03 | 감소 규칙 음수 입력 .abs() 방어 | ✅ 수정 완료 |
| ⚠️ I-01 | 설정 30분 캐시 stale 가능성 | 수용 (CF는 독립 조회) |
| ⚠️ I-02 | TrustScoreInfoDialog 하드코딩 등급 임계값 | 수용 (정보성 UI) |
