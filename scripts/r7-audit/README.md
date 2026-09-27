# R7 Staffing 감사 — 격리 실행환경 재현 절차

이 디렉터리는 **감사 실행을 새 환경에서 다시 만들기 위한 산출물**이다.
지금 떠 있는 프로세스에 기대지 않는다.

- shared DEV(`alfit-89567`) 와 PROD 는 건드리지 않는다. 모든 write 는 `demo-alfit-r7` 안에서만 일어난다.
- 전역 firebase CLI, `functions/package.json`, lockfile, `engines`, `firebase.json` 은 바꾸지 않는다.

---

## 1. 확인된 버전 (이 결과가 나온 환경)

| 구성 | 값 |
|---|---|
| node | v22.20.0 (`/c/Program Files/nodejs/node`) |
| npm | 10.9.3 |
| java | 25 (2025-09-16 LTS) — Firestore/Storage 에뮬레이터용 |
| firebase-tools (감사용, 격리) | **15.31.0** (exact) |
| firebase-tools (전역, 미사용) | 14.20.0 — Functions 에뮬레이터가 이 조합에서 동작하지 않는다(§4) |
| firebase-functions | 7.3.2 (`functions/node_modules`) |
| firebase-admin | 12.7.0 (`functions/node_modules`) |

`@latest` 를 재현 가능한 결과로 쓰지 않는다. 항상 exact version 을 지정한다.

## 2. 격리 CLI 설치

```bash
D=<임시 도구 디렉터리>            # 저장소 밖. 예: 세션 스크래치패드
mkdir -p "$D" && cd "$D"
echo '{"name":"r7-audit-cli","private":true,"version":"0.0.0"}' > package.json
npm install --no-audit --no-fund firebase-tools@15.31.0
```

## 3. CLI 수선 적용 (§4 참조 — 왜 필요한지 먼저 읽을 것)

```bash
cd "$D"
cp node_modules/firebase-tools/lib/emulator/functionsEmulatorRuntime.js \
   node_modules/firebase-tools/lib/emulator/functionsEmulatorRuntime.js.r7bak
patch -p1 < <저장소>/scripts/r7-audit/firebase-tools-15.31.0-preserve-fn-statics.patch
```

| 파일 | sha256 (앞부분) |
|---|---|
| 원본 `functionsEmulatorRuntime.js` (15.31.0) | `5bef9577eaa8e6ed…` |
| 수선 후 | `5a9c32221d51d42f…` |

부작용 확인:

```bash
node <저장소>/scripts/r7-audit/smoke-admin-surface.js
# → firestore 29 / auth 1 / database 8 / storage 1 / messaging 1 개 own property 복원,
#   원본과 **같은 객체**, 추가된 것 없음, binding this 유지
```

`.r7bak` 과 `node_modules` 는 커밋하지 않는다.

## 4. 왜 수선하는가 — 두 BLOCKER

### 4-1. `functions.config()` — 14.20.0 에서 모든 function 로드 실패

- 호출자: `firebase-tools@14.20.0` → `lib/emulator/functionsEmulatorRuntime.js:455,458`
  (`initializeFunctionsConfigHelper`, **가드 없음**)
- 피호출자: `firebase-functions@7.3.2` → `lib/v1/config.js:10` 이 무조건 throw
- 즉 **제품 코드가 아니라 CLI** 가 제거된 API 를 부른다.
- 15.31.0 에는 그 helper 자체가 없다 → 버전 교체로 해소. 수선 불필요.

### 4-2. `admin.firestore.Timestamp` 소실 — 15.31.0 에서 모든 callable `INTERNAL`

- 스택: `TypeError: Cannot read properties of undefined (reading 'fromMillis')`
  at `functions/lib/index.js:30069`
- 원인: CLI `Proxied.getOriginal` 이 `value.bind(target)` 을 반환한다.
  `bind` 는 함수의 own property 를 버린다. `admin.firestore` 는 prototype 이 없어
  `isConstructor` 분기를 타지 못하고 bind 로 떨어진다.
- 같은 표현이 에뮬레이터 **밖** 에서는 정상이다 → CODE 아님, INFRA 다.
- 수선은 bind 후 own descriptor 를 되돌린다. **원본 동작의 복원**이지
  `config()` 처럼 없는 기능을 있는 척 통과시키는 것이 아니다.

> 공식 수정 버전이 확인되면 그쪽을 선호한다. 현재는 **제한된 local compatibility
> patch** 상태이며, 이 조합이 보편적으로 동작한다고 주장하지 않는다.

## 5. 감사용 설정과 env 격리

- `firebase.r7audit.json` (저장소 루트) — 별도 config. `predeploy` 없음.
  포트: functions 5011 / firestore 6070 / storage 6071 / auth 6072 / hub 4410.
- `functions/.env.demo-alfit-r7` — **커밋하지 않는다.** `functions/.env` 의 모든 키를
  감사 전용 dummy 로 덮는다. 없으면 실자격증명이 로드되므로 **실행 금지**.

```bash
node <저장소>/scripts/r7-audit/verify-env-isolation.js demo-alfit-r7
# 값은 출력하지 않는다 — 키별 덮임/다름 여부만 본다. 하나라도 미격리면 exit 1.
```

외부 부작용이 나가지 않는 근거(이번 실행에서 관측):

1. demo 프로젝트 — CLI 가 직접 말한다:
   *"Detected demo project ID … attempts to access non-emulated services for this project will fail."*
2. `GOOGLE_APPLICATION_CREDENTIALS` 미설정, gcloud ADC 파일 없음, `defineSecret` 0건,
   `src/index.ts` 에 하드코딩 bucket 없음.
3. 알림 경로는 fixture 사용자에게 FCM 토큰이 없어 제품 코드가
   `⚠️ [알림 트리거] FCM 토큰 없음` 에서 멈췄다 — `sendEachForMulticast` 에 도달하지 않았다.
4. FCM 전송은 callable 이 아니라 `onNotificationCreated` **트리거**에서 일어난다.
   별도 실행이므로 전송 실패가 callable 의 commit 을 되돌릴 수 없다.

> 한계: 전송 경로 자체를 실패시켜 끝까지 관측하지는 못했다(**NOT TESTED**).
> 3·4 는 "전달되지 않았다"의 근거이고, "모든 outbound 가 차단됐다"의 증명은 아니다.

## 6. 기동

```bash
cd <저장소>
npm --prefix functions run build          # 에뮬레이터는 predeploy 를 돌리지 않는다
unset GOOGLE_APPLICATION_CREDENTIALS
"$D/node_modules/.bin/firebase" emulators:start \
  --config firebase.r7audit.json --project demo-alfit-r7 \
  --only functions,firestore,storage,auth
```

기대: `All emulators ready` + **241 functions initialized**, `Failed to load function` 0건.

종료: 이 세션이 띄운 프로세스만 정리한다(에뮬레이터 프로세스와 그 java 자식).
다른 프로젝트의 에뮬레이터를 일괄 종료하지 않는다.

## 7. 실행

```bash
node scripts/r7-emu-transition-matrix.js   # T1~T4 지원·중복·확정·확정취소
node scripts/r7-emu-matrix2.js             # T5~T7 지원취소·재지원·비동기 수렴
node scripts/r7-writer-inventory.js        # §3B writer 인벤토리 (에뮬레이터 불필요)
```

두 harness 는 실행 전후로 자기 fixture 만 지운다
(`r7biz*/r7to*/r7worker*/r7owner*`). 다른 데이터를 건드리지 않는다.

**정착 판정은 고정 sleep 이 아니다.** `settle()` 이 값이 연속 동일해질 때까지
관측하고, 끝내 흔들리면 `settled: false` 로 남긴다.

## 8. 이 환경으로 확인되지 않는 것

- Firestore **rules** — harness 는 Admin SDK 를 쓰므로 rules 를 통과하지 않는다.
  클라이언트 write 경로를 재현할 때도 **write set 만** 같고 권한 판정은 받지 않는다.
- 실제 기기·실제 네트워크·실제 FCM 전달.
- shared DEV 의 실제 데이터 분포.
