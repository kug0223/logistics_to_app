# AlFit 프로젝트 Claude 작업 지침

## 절대 금지 사항

### Android 패키지 관련 파일 — 절대 수정 금지
다음 파일들은 어떤 이유로도 수정하지 않는다:
- `android/app/build.gradle.kts`
- `android/app/google-services.json`
- `android/app/src/main/kotlin/com/alfit/app/MainActivity.kt`

패키지명 `ALfit`도 변경하지 않는다. (Android 설정과 연동됨)

---

## 응답 언어

항상 **한국어**로 응답한다.

---

## 하단 홈버튼 / 네비게이션바 영역 처리 (SafeArea)

### 필수 규칙: 새 바텀시트/화면을 만들 때 반드시 적용

#### 바텀시트 (`showModalBottomSheet`)
`useSafeArea: true`를 항상 명시한다.

```dart
// ✅ 올바른 패턴
showModalBottomSheet(
  context: context,
  useSafeArea: true,          // 필수 — 하단 홈버튼 영역 자동 처리
  isScrollControlled: true,  // 키보드가 밀어올릴 때 필요 시 추가
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (ctx) => MySheet(),
);

// ❌ 금지 — useSafeArea 누락
showModalBottomSheet(
  context: context,
  builder: (ctx) => MySheet(),  // 하단이 홈버튼과 겹칠 수 있음
);
```

#### 커스텀 하단 바 (Scaffold bottomNavigationBar / 고정 버튼)
`SafeArea(top: false)`로 감싼다.

```dart
// ✅ 올바른 패턴
Scaffold(
  bottomNavigationBar: SafeArea(
    top: false,   // 상단 safe area 제외, 하단만 처리
    child: Container(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton(...),
    ),
  ),
)
```

#### 화면 전체 (`Scaffold body`)
대부분의 Scaffold는 `resizeToAvoidBottomInset: true`(기본값)로 키보드를 처리한다. 추가 SafeArea는 필요 시에만.

### 이중 처리 주의
`useSafeArea: true`와 내부 `SafeArea` 위젯을 동시에 쓰면 Flutter이 자동으로 중복 패딩을 막아주므로 시각적 문제는 없지만, 코드 명확성을 위해 `useSafeArea: true` 하나로 통일을 권장한다.

---

## 모바일 UI 공간 설계 원칙

좁은 화면(360dp 미만)에서 Row 레이아웃이 넘칠 수 있다:
- 2개 이상의 위젯을 Row에 넣을 때는 `Flexible` 또는 `Expanded` 사용
- 텍스트 + 아이콘 조합이 길어질 경우 `Wrap`으로 줄바꿈 허용
- 고정 너비(`width: 200`) 대신 비율 기반(`flex`) 사용

---

## 디자인 시스템 규칙

신규 UI는 반드시 공통 컴포넌트를 사용하고, 인라인 구현 금지:
- 색상: `AppColors.*` 사용 (하드코딩 금지)
- 텍스트 스타일: `ResponsiveHelper.bodyStyle()` 등 사용
- 카드: `CommonWidgets.compactCardDecoration()` 사용
- 아이콘: `WorkTypeIcon.buildWithBackground()` 사용

---

## 임금 구조 설계 원칙

- 주휴수당 자동계산 없음 — 관리자가 수동 입력하거나 0으로 처리
- 시급/일급 TO 레벨에서 고정 (변경 불가)
- `effectiveNetWage` getter를 사용 — `netWage`를 직접 참조하지 않는다

```dart
// ✅ 올바른 참조
final net = wageDetail.effectiveNetWage;

// ❌ 금지 — 미확정 시 0 반환
final net = wageDetail.netWage;
```

---

## 비동기 안전성

async gap 이후 `context` 또는 `setState` 사용 시 반드시 `mounted` 체크:

```dart
// ✅ 올바른 패턴
await someAsyncOperation();
if (!mounted) return;
setState(() { ... });

// ❌ 금지
await someAsyncOperation();
setState(() { ... });  // mounted 체크 없음
```

---

## Firestore 삭제 순서

Storage와 Firestore를 함께 삭제할 때 반드시 **Firestore 먼저**:

```dart
// ✅ 올바른 순서 (Firestore 실패 시 Storage는 건드리지 않음)
// 1. Storage URL 미리 수집
// 2. Firestore 삭제 (실패 시 전체 취소)
// 3. Storage 정리

// ❌ 금지
await storageRef.delete();  // Storage 먼저 삭제하면 Firestore 실패 시 broken URL 남음
await firestoreDoc.delete();
```

---

## 임시 파일 처리

`getTemporaryDirectory()`로 생성한 파일은 공유(`Share.shareXFiles`) 후 반드시 삭제:

```dart
final file = File('${dir.path}/export.xlsx');
await file.writeAsBytes(bytes);
await Share.shareXFiles([XFile(file.path)]);
await file.delete();  // 필수
```

파일을 반환하는 함수(`savePdfLocally` 등)는 호출자가 삭제 책임을 가진다.

---

## 테스트 실행

```bash
flutter test          # 전체 테스트
flutter analyze       # 정적 분석 (No issues found 확인)
```

---

## 안티패턴 탐지 스크립트

```powershell
.\scripts\check_antipatterns.ps1
```

NET-01(보험료 미차감 폴백), TMP-01(임시파일 누수), LOG-01(print 직접사용), QUERY-01(whereIn 30개 제한) 탐지.
