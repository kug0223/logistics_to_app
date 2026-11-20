// [WD-CANON] Application `workDate` 는 **그 날 KST 자정 instant** 다.
//
//   실행:  cd functions && node test/workdate_kst_canonical.test.js
//
// ── 재현된 오염 (DEV READ) ────────────────────────────────────────────
//   `applications` 36건 중 **4건**의 workDate 가 `KST 09:00` = **UTC 자정**
//   이었다. 4건 모두 같은 근로자의 **초대 경로**(invitedAt == appliedAt ==
//   confirmedAt) 산물이고, 같은 slot 의 `date` 는 전부 정상 KST 자정이었다.
//
// ── root cause ────────────────────────────────────────────────────────
//   `callableInviteWorker` 가 문자열 날짜를 이렇게 바꿨다:
//
//       Timestamp.fromDate(new Date(workDate))
//
//   JS 는 `'2026-10-15'` 같은 날짜-only ISO 를 **UTC 자정**으로 파싱한다.
//   그대로 저장되면 KST 09:00 이고, `srvShiftStartMsFrom(workDateMs + 벽시계)`
//   를 쓰는 **취소 5분 cutoff·노쇼 확정 guard 가 9시간 늦게** 열린다.
//
// ── 고친 것 ───────────────────────────────────────────────────────────
//   두 writer(`callableInviteWorker`, `callableApplyToTO`)가 저장 전에
//   `srvKstDayStartMs` 로 정규화한다. 이 함수는 **idempotent** 라 이미
//   정상인 값은 그대로 두고, 날짜를 다른 날로 바꾸지 않는다.
//
// ── 이 테스트의 한계(정직하게) ────────────────────────────────────────
//   `srvKstDayStartMs` 는 `index.ts` 안의 non-exported 함수라 직접 호출할
//   수 없다. 그래서 ① 소스에서 두 writer 가 그 정규화를 거치는지 확인하고
//   ② 정규화 **식 자체의 성질**을 같은 구현으로 고정한다. 실제 배포본의
//   런타임 동작은 DEV 배포 후 별도 검증 대상이다(이번 Phase 범위 밖).
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const SRC = fs.readFileSync(
    path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');

/** 주석을 뺀 코드 — 설명문이 자기 자신을 잡지 않도록. */
const CODE = SRC.split('\n')
    .filter((l) => !l.trimStart().startsWith('//') &&
                   !l.trimStart().startsWith('*') &&
                   !l.trimStart().startsWith('/*'))
    .join('\n');

const KST_MS = 9 * 3600 * 1000;

/**
 * [GATE0] **빌드 산출물의 실제 함수**를 꺼내 쓴다 — 계산식을 복제하지 않는다.
 *
 *   `srvKstDayStartMs` 는 `index.ts` 안의 non-exported 함수라 require 로는
 *   닿지 않는다. 그래서 컴파일된 `lib/index.js` 에서 그 함수 선언과 상수를
 *   **원문 그대로** 떼어 평가한다. 손으로 옮겨 적은 식이 아니라 배포될
 *   코드 자체다.
 */
function loadProductionHelper() {
  const lib = fs.readFileSync(
      path.join(__dirname, '..', 'lib', 'index.js'), 'utf8');
  const konst = lib.match(/const SRV_KST_MS = [^;]+;/);
  const fn = lib.match(/function srvKstDayStartMs\(ms\) \{[\s\S]*?\n\}/);
  assert.ok(konst, 'lib/index.js 에서 SRV_KST_MS 를 찾지 못했다');
  assert.ok(fn, 'lib/index.js 에서 srvKstDayStartMs 를 찾지 못했다');
  // eslint-disable-next-line no-new-func
  return new Function(
      konst[0] + '\n' + fn[0] + '\nreturn srvKstDayStartMs;')();
}

const kstDayStartMs = loadProductionHelper();

const kst = (ms) => new Date(ms + KST_MS).toISOString().slice(0, 16);

let pass = 0;
const fails = [];
function t(id, fn) {
  try {
    fn();
    pass++;
    console.log(`  ok   ${id}`);
  } catch (e) {
    fails.push(`${id}: ${e.message.split('\n')[0]}`);
    console.log(`  FAIL ${id} — ${e.message.split('\n')[0]}`);
  }
}

console.log('[WD-A] 정규화 식의 성질');

t('WD-1 UTC 자정 입력을 그 날 KST 자정으로 보낸다 (오염 교정)', () => {
  // 오염 실측값: 2026-10-15T00:00:00Z (= KST 09:00)
  const contaminated = Date.UTC(2026, 9, 15, 0, 0, 0);
  assert.strictEqual(kst(contaminated), '2026-10-15T09:00',
      '오염 입력이 KST 09:00 이어야 재현이 맞다');
  const fixed = kstDayStartMs(contaminated);
  assert.strictEqual(kst(fixed), '2026-10-15T00:00');
});

t('WD-2 idempotent — 이미 KST 자정이면 그대로', () => {
  const ok = Date.UTC(2026, 9, 14, 15, 0, 0); // = KST 10-15 00:00
  assert.strictEqual(kst(ok), '2026-10-15T00:00');
  assert.strictEqual(kstDayStartMs(ok), ok);
  assert.strictEqual(kstDayStartMs(kstDayStartMs(ok)), ok);
});

t('WD-3 날짜를 다른 날로 바꾸지 않는다', () => {
  // 그 날 안의 어떤 시각이든 같은 날 자정으로만 간다.
  const base = Date.UTC(2026, 9, 14, 15, 0, 0); // KST 10-15 00:00
  for (const h of [0, 1, 9, 12, 23]) {
    const probe = base + h * 3600 * 1000;
    assert.strictEqual(kst(kstDayStartMs(probe)).slice(0, 10), '2026-10-15',
        `KST ${h}시 입력`);
  }
});

t('WD-4 KST 자정 직전은 전날이다', () => {
  const justBefore = Date.UTC(2026, 9, 14, 14, 59, 59); // KST 10-14 23:59:59
  assert.strictEqual(kst(kstDayStartMs(justBefore)).slice(0, 10), '2026-10-14');
});

t('WD-5 서버 로컬 TZ 에 기대지 않는다 (UTC 산술만)', () => {
  // 같은 입력이면 어떤 TZ 에서 돌려도 같은 결과여야 한다.
  const ms = Date.UTC(2026, 9, 15, 0, 0, 0);
  const got = kstDayStartMs(ms);
  assert.strictEqual(got, Date.UTC(2026, 9, 14, 15, 0, 0));
});

t('WD-6 근무 시작 instant 가 서버 식과 맞는다', () => {
  // srvShiftStartMsFrom(workDateMs, '16:00') = workDateMs + 16h
  const canonical = kstDayStartMs(Date.UTC(2026, 9, 15, 0, 0, 0));
  const start = canonical + 16 * 3600 * 1000;
  assert.strictEqual(kst(start), '2026-10-15T16:00');
  // 오염된 값이었다면 9시간 늦은 익일 01:00 이 된다.
  const contaminatedStart = Date.UTC(2026, 9, 15, 0, 0, 0) + 16 * 3600 * 1000;
  assert.strictEqual(kst(contaminatedStart), '2026-10-16T01:00');
});

console.log('[WD-B] 두 writer 가 정규화를 거친다 (소스 계약)');

t('WD-7 초대 경로가 srvKstDayStartMs 로 정규화한다', () => {
  assert.ok(
      CODE.includes('srvKstDayStartMs(invWorkDateMs)'),
      'callableInviteWorker 의 workDateTs 가 정규화를 거쳐야 한다');
  assert.ok(
      !CODE.includes('Timestamp.fromDate(new Date(workDate))'),
      '날짜-only ISO 를 그대로 Date 로 파싱하던 식이 남아 있다');
});

t('WD-8 초대 경로가 잘못된 날짜 형식을 명시적으로 거부한다', () => {
  assert.ok(CODE.includes('workDate 형식이 올바르지 않습니다'));
  assert.ok(CODE.includes('Number.isFinite(invWorkDateMs)'));
});

t('WD-9 초대 종료일도 같은 자를 쓴다', () => {
  assert.ok(CODE.includes('srvKstDayStartMs(invEndMs)'));
  assert.ok(!CODE.includes('Timestamp.fromDate(new Date(workEndDate))'));
});

t('WD-10 지원 경로도 정규화한다', () => {
  assert.ok(CODE.includes('srvKstDayStartMs(workDateMs)'),
      'callableApplyToTO 도 서버에서 정규화해야 구버전 앱을 막는다');
  assert.ok(!CODE.includes(
      'const workDate = admin.firestore.Timestamp.fromMillis(workDateMs);'),
  '정규화 없이 그대로 저장하던 식이 남아 있다');
});

t('WD-11 지원 경로의 종료일·희망시작일도 같은 자', () => {
  assert.ok(CODE.includes('srvKstDayStartMs(workEndDateMs)'));
  assert.ok(CODE.includes('srvKstDayStartMs(\n        desiredStartDateMs)') ||
            CODE.includes('srvKstDayStartMs(desiredStartDateMs)'));
});

console.log('[WD-D] slot 날짜 일치 — 정규화가 못 잡는 오류');

t('WD-15 정규화해도 잘못 고른 날은 그대로 남는다', () => {
  // 10-16 을 보내면 정규화 결과도 10-16 이다. 형식은 정상이지만
  //   사용자가 고른 slot(10-15)과 다른 근무가 된다.
  const wrong = kstDayStartMs(Date.UTC(2026, 9, 15, 20, 0, 0)); // KST 10-16 05:00
  assert.strictEqual(kst(wrong).slice(0, 10), '2026-10-16');
  const slotDay = kstDayStartMs(Date.UTC(2026, 9, 14, 15, 0, 0)); // KST 10-15
  assert.notStrictEqual(wrong, slotDay, '정규화만으로는 못 거른다');
});

t('WD-16 지원 경로가 slot 날짜와 대조한다', () => {
  assert.ok(CODE.includes('srvKstDayStartMs(slotWorkDateTs.toMillis()) !==\n            workDate.toMillis()'),
      'applyToTO 가 slot.date 와 입력 날짜를 비교해야 한다');
  assert.ok(CODE.includes('선택한 근무일이 공고 일정과 일치하지 않습니다'));
});

t('WD-17 초대 경로가 slot 날짜와 대조한다', () => {
  assert.ok(CODE.includes('invSlotDayMs !== null && invSlotDayMs !== workDateTs.toMillis()'),
      'callableInviteWorker 가 slot.date 와 입력 날짜를 비교해야 한다');
  assert.ok(CODE.includes('초대 날짜가 공고 일정과 일치하지 않습니다'));
});

t('WD-18 slot 이 없으면(장기공고) 이 검증을 건너뛴다', () => {
  // 장기공고는 slotId 가 없다 — null 가드로 통과시킨다.
  assert.ok(CODE.includes('let invSlotDayMs: number | null = null;'));
  assert.ok(CODE.includes('if (invSlotDayMs !== null'),
      'slot 이 없을 때 막으면 장기공고 초대가 통째로 끊긴다');
});

t('WD-19 slot 이 같은 날이면 통과한다 (기존 36건 전부 해당)', () => {
  const slotMs = kstDayStartMs(Date.UTC(2026, 9, 14, 15, 0, 0)); // KST 10-15 00:00
  // 오염된 입력(UTC 자정)도 정규화하면 같은 날이 된다 — 차단되지 않는다.
  const contaminated = kstDayStartMs(Date.UTC(2026, 9, 15, 0, 0, 0));
  assert.strictEqual(contaminated, slotMs);
  // 정상 입력도 당연히 같다.
  assert.strictEqual(kstDayStartMs(slotMs), slotMs);
});

console.log('[WD-E] 단기 slot 누락은 장기공고 예외가 아니다 (fail-closed)');

t('WD-20 지원 경로: 없는 slotId 는 not-found', () => {
  assert.ok(CODE.includes(
      'if (!slotSnap.exists) throw new HttpsError("not-found", "해당 날짜 정보를 찾을 수 없습니다.");'),
  'applyToTO 는 slotId 가 가리키는 슬롯이 없으면 거부해야 한다');
});

t('WD-21 초대 경로: 없는 slotId 는 not-found', () => {
  // 예전에는 `if (slotSnap.exists)` 로 감싸 조용히 통과했다.
  assert.ok(CODE.includes('선택한 근무 일정을 찾을 수 없습니다'),
      'callableInviteWorker 도 거부해야 한다');
  assert.ok(!CODE.includes('      if (slotSnap.exists) {\n        startTime ='),
      'exists 분기로 감싸던 구조가 남아 있다');
});

t('WD-22 다른 TO 의 slotId 도 같은 경로로 막힌다', () => {
  // 조회가 `tos/{toId}/slots/{slotId}` 하위 경로라 다른 TO 의 slot 은
  //   애초에 not-exists 가 된다 — 위 두 거부가 그대로 적용된다.
  assert.ok(CODE.includes(
      'db.collection("tos").doc(toId).collection("slots").doc(slotId).get()'),
  '초대 경로의 slot 조회가 toId 하위여야 한다');
});

t('WD-23 슬롯에 날짜가 없으면 양쪽 모두 거부', () => {
  const n = (CODE.match(/근무 일정의 날짜 정보를 확인할 수 없습니다/g) || []).length;
  assert.strictEqual(n, 2, '지원·초대 두 경로 모두에 있어야 한다 (실제: ' + n + ')');
});

t('WD-24 slotless 장기공고 경로는 그대로 열려 있다', () => {
  // 두 경로 모두 slot 검증 전체가 `if (slotId)` 안에 있다.
  assert.ok(CODE.includes('let invSlotDayMs: number | null = null;'));
  assert.ok(CODE.includes('if (invSlotDayMs !== null'),
      'slot 이 없는 장기 초대를 막으면 안 된다');
});

console.log('[WD-C] 바꾸지 않은 것');

t('WD-12 판정식(srvShiftStartMsFrom)은 그대로다', () => {
  assert.ok(CODE.includes(
      'return workDateMs + (hh * 60 + mm) * 60000;'),
  '근무 시작 계산은 canonical 그대로 둔다');
});

t('WD-13 기존 데이터 보정·migration 코드를 넣지 않았다', () => {
  // 'backfill' 자체는 리뷰·통장사본 쪽 기존 기능 이름이라 쓰지 않는다.
  for (const banned of [
    'backfillWorkDate', 'migrateWorkDate', 'fixWorkDate',
    'workDate: admin.firestore.Timestamp.fromMillis(srvKstDayStartMs(existing',
  ]) {
    assert.ok(!CODE.includes(banned), banned);
  }
});

t('WD-14 srvKstDayStartMs 구현은 건드리지 않았다', () => {
  assert.ok(CODE.includes('function srvKstDayStartMs(ms: number): number {'));
  assert.ok(CODE.includes('d.setUTCHours(0, 0, 0, 0);'));
});

console.log('');
console.log(`통과 ${pass} / 실패 ${fails.length}`);
if (fails.length) {
  for (const f of fails) console.log('  - ' + f);
  process.exit(1);
}
