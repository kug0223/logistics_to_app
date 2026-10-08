// [R7-PAYROLL-POLICY.5A] 발행 ≠ 시행 ≠ 재동의 — **행동** 테스트.
//
//   실행:  cd functions && npm run build && node test/legal_effective_date.test.js
//
//   왜 이 파일이 있나
//
//     `.5A` 이전에는 발행하는 순간 모든 reader 가 새 판을 현재 약관으로
//     말하고 전원 재동의가 걸렸다. 그런데 service_terms 제3조 ② 는
//     "유리·중립 7일 전 / 불리 30일 전 공지" 를 약속한다. 약속과 동작이
//     어긋나 있었고, 약속을 지우는 쪽으로 맞추는 것은 금지다.
//
//   고정하는 것
//     E-1  고지기간 — 자기약속(7/30일)보다 짧은 시행일은 거절
//     E-2  시행일은 생략할 수 없고 KST 자정이어야 한다
//     E-3  발행된 판의 시행일은 바꿀 수 없다
//     E-4  첫 발행만 즉시 시행이고, 그 판단은 서버가 한다
//     E-5  경계 — effectiveAt-1ms / effectiveAt / +1ms
//     E-6  승격은 포인터가 아니라 한 벌 전체를 옮긴다
//     E-7  readiness·동의 writer 는 **시행 중인 판**을 기준으로 한다
//     E-8  공개 웹과 CF 가 같은 규칙으로 시행 판을 고른다
//     E-9  서버 시각을 모르면 승격하지 않는다 (기기 시계 금지)
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const M = require('../lib/legal_publication');
const ROOT = path.join(__dirname, '..', '..');
const WEB = require(path.join(ROOT, 'public', 'legal-reader.js'));

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

const indexSrc = () => fs
  .readFileSync(path.join(__dirname, '..', 'src', 'index.ts'), 'utf8')
  .split('\n').filter((l) => !l.trimStart().startsWith('//')).join('\n');

const DAY = 24 * 60 * 60 * 1000;
/** 2026-10-08 10:00 KST = 01:00Z */
const NOW = Date.UTC(2026, 9, 8, 1, 0, 0);
/** 2026-10-08 00:00 KST */
const TODAY_KST = Date.UTC(2026, 9, 7, 15, 0, 0);

// ══════════════════════════════════════════════════════════════════
// E-2 / E-4  시행일 자체의 모양
// ══════════════════════════════════════════════════════════════════

t('E2-1 KST 자정으로 내린다 — UTC 자정이 아니다', () => {
  assert.strictEqual(M.kstMidnightMs(NOW), TODAY_KST);
  // 09:00 KST 어긋남이 생기면 사용자가 보는 날짜가 하루 달라진다.
  assert.notStrictEqual(M.kstMidnightMs(NOW), Date.UTC(2026, 9, 8, 0, 0, 0));
  // 자정 정각은 그대로 남는다 (idempotent).
  assert.strictEqual(M.kstMidnightMs(TODAY_KST), TODAY_KST);
  // 자정 1ms 전은 전날이다.
  assert.strictEqual(M.kstMidnightMs(TODAY_KST - 1), TODAY_KST - DAY);
});

t('E2-2 시행일을 생략하면 거절한다 — 기본값 "즉시" 를 두지 않는다', () => {
  const v = M.evaluateNoticePeriod({
    changeType: 'adverse', publishedAtMs: NOW,
    effectiveAtMs: null, hasExistingEffective: true,
  });
  assert.strictEqual(v.ok, false);
  assert.strictEqual(v.reason, 'EFFECTIVE_AT_REQUIRED');
  assert.ok(v.earliestEffectiveAtMs > NOW, '가장 이른 시행일을 알려 준다');
});

t('E2-3 KST 자정이 아닌 시행일은 거절한다', () => {
  const v = M.evaluateNoticePeriod({
    changeType: 'adverse', publishedAtMs: NOW,
    effectiveAtMs: TODAY_KST + 31 * DAY + 60000,
    hasExistingEffective: true,
  });
  assert.strictEqual(v.reason, 'EFFECTIVE_AT_NOT_KST_MIDNIGHT');
});

t('E2-4 모르는 changeType 은 거절한다 — 조용히 한쪽으로 가지 않는다', () => {
  for (const ct of [undefined, null, '', 'typo', 'clerical', 'URGENT', 7]) {
    const v = M.evaluateNoticePeriod({
      changeType: ct, publishedAtMs: NOW,
      effectiveAtMs: TODAY_KST + 31 * DAY, hasExistingEffective: true,
    });
    assert.strictEqual(v.reason, 'INVALID_CHANGE_TYPE', String(ct));
  }
});

// ══════════════════════════════════════════════════════════════════
// E-1  고지기간은 ALfit 자기약속에서 온다
// ══════════════════════════════════════════════════════════════════

t('E1-1 약속한 기간이 표에 그대로 있다 (7일 / 30일)', () => {
  // service_terms 제3조 ② — 줄이려면 약관을 먼저 고쳐야 한다.
  assert.strictEqual(M.LEGAL_NOTICE_DAYS.neutral, 7);
  assert.strictEqual(M.LEGAL_NOTICE_DAYS.adverse, 30);
  assert.strictEqual(M.LEGAL_NOTICE_DAYS.initial, 0);
});

t('E1-2 불리한 변경은 30일을 온전히 채워야 한다', () => {
  const earliest = M.earliestEffectiveAtMs('adverse', NOW);
  assert.ok(earliest - NOW >= 30 * DAY, '30일이 모자란다');
  assert.ok(earliest - NOW < 31 * DAY, '필요 이상으로 밀지 않는다');
  assert.strictEqual(earliest, M.kstMidnightMs(earliest), 'KST 자정이어야 한다');

  // 하루 모자란 날짜는 거절.
  const short = M.evaluateNoticePeriod({
    changeType: 'adverse', publishedAtMs: NOW,
    effectiveAtMs: earliest - DAY, hasExistingEffective: true,
  });
  assert.strictEqual(short.reason, 'NOTICE_PERIOD_TOO_SHORT');
  assert.strictEqual(short.earliestEffectiveAtMs, earliest);

  // 딱 맞는 날짜는 통과.
  const ok = M.evaluateNoticePeriod({
    changeType: 'adverse', publishedAtMs: NOW,
    effectiveAtMs: earliest, hasExistingEffective: true,
  });
  assert.strictEqual(ok.ok, true);
  assert.strictEqual(ok.effectiveAtMs, earliest);
});

t('E1-3 중립적 변경은 7일', () => {
  const e = M.earliestEffectiveAtMs('neutral', NOW);
  assert.ok(e - NOW >= 7 * DAY && e - NOW < 8 * DAY);
  assert.strictEqual(M.evaluateNoticePeriod({
    changeType: 'neutral', publishedAtMs: NOW,
    effectiveAtMs: e - DAY, hasExistingEffective: true,
  }).reason, 'NOTICE_PERIOD_TOO_SHORT');
});

t('E1-4 불리한 변경을 중립으로 적어 기간을 줄일 수는 있다 — 분류가 기록된다', () => {
  // 코드가 분류를 대신 판단하지는 않는다. 다만 분류는 발행본에 남아야
  // 하고(아래 E4-3), 7일보다 짧게는 어느 분류로도 갈 수 없다.
  const e7 = M.earliestEffectiveAtMs('neutral', NOW);
  for (const ct of ['neutral', 'adverse']) {
    const v = M.evaluateNoticePeriod({
      changeType: ct, publishedAtMs: NOW,
      effectiveAtMs: e7 - DAY, hasExistingEffective: true,
    });
    assert.strictEqual(v.ok, false, ct + ' 가 7일 미만을 통과시켰다');
  }
});

// ══════════════════════════════════════════════════════════════════
// E-4  첫 발행
// ══════════════════════════════════════════════════════════════════

t('E4-1 시행 중인 판이 없으면 initial 이어야 한다', () => {
  const v = M.evaluateNoticePeriod({
    changeType: 'adverse', publishedAtMs: NOW,
    effectiveAtMs: TODAY_KST + 31 * DAY, hasExistingEffective: false,
  });
  assert.strictEqual(v.reason, 'INITIAL_REQUIRED');
});

t('E4-2 이미 시행 중인 판이 있으면 initial 을 쓸 수 없다', () => {
  // caller 가 initial 이라고 주장해도 서버가 거절한다 — 즉시 시행 구멍 차단.
  const v = M.evaluateNoticePeriod({
    changeType: 'initial', publishedAtMs: NOW,
    effectiveAtMs: TODAY_KST, hasExistingEffective: true,
  });
  assert.strictEqual(v.reason, 'INITIAL_NOT_ALLOWED');
});

t('E4-3 첫 발행은 미래로 미룰 수 없다', () => {
  // 미루면 그 항목은 시행 중인 판 없이 공개 목록에 들어간다.
  const v = M.evaluateNoticePeriod({
    changeType: 'initial', publishedAtMs: NOW,
    effectiveAtMs: TODAY_KST + DAY, hasExistingEffective: false,
  });
  assert.strictEqual(v.reason, 'INITIAL_MUST_BE_IMMEDIATE');

  const ok = M.evaluateNoticePeriod({
    changeType: 'initial', publishedAtMs: NOW,
    effectiveAtMs: TODAY_KST, hasExistingEffective: false,
  });
  assert.strictEqual(ok.ok, true);
  assert.strictEqual(ok.effectiveAtMs, TODAY_KST);
});

// ══════════════════════════════════════════════════════════════════
// E-3  발행된 판의 시행일은 바꿀 수 없다
// ══════════════════════════════════════════════════════════════════

t('E3-1 이미 발행된 판에 다른 시행일을 밀어 넣으면 거절한다', () => {
  const stored = TODAY_KST + 31 * DAY;
  const v = M.evaluateNoticePeriod({
    changeType: 'adverse', publishedAtMs: NOW,
    effectiveAtMs: stored + 10 * DAY,
    hasExistingEffective: true, storedEffectiveAtMs: stored,
  });
  assert.strictEqual(v.reason, 'EFFECTIVE_AT_IMMUTABLE');
  assert.strictEqual(v.storedEffectiveAtMs, stored);
});

t('E3-2 같은 시행일로 다시 발행하는 것은 무해하다', () => {
  const stored = M.earliestEffectiveAtMs('adverse', NOW);
  const v = M.evaluateNoticePeriod({
    changeType: 'adverse', publishedAtMs: NOW,
    effectiveAtMs: stored,
    hasExistingEffective: true, storedEffectiveAtMs: stored,
  });
  assert.strictEqual(v.ok, true);
});

t('E3-3 시행일을 앞으로 당겨 고지기간을 줄이는 것도 거절한다', () => {
  const stored = TODAY_KST + 31 * DAY;
  const v = M.evaluateNoticePeriod({
    changeType: 'adverse', publishedAtMs: NOW,
    effectiveAtMs: TODAY_KST + DAY,
    hasExistingEffective: true, storedEffectiveAtMs: stored,
  });
  assert.strictEqual(v.reason, 'EFFECTIVE_AT_IMMUTABLE',
    '불변성 검사가 자정·기간 검사보다 먼저 와야 한다');
});

// ══════════════════════════════════════════════════════════════════
// E-5  경계 — 시행 시각 전후
// ══════════════════════════════════════════════════════════════════

const EFF = TODAY_KST + 31 * DAY;
const baseItem = () => ({
  id: 'service_terms',
  version: '2026.08',
  revisionId: 'service_terms__2026.08',
  contentHash: 'hashA',
  isRequired: true,
  isActive: true,
  effectiveAtMs: TODAY_KST - 60 * DAY,
  upcoming: {
    version: '2026-10-08',
    revisionId: 'service_terms__2026-10-08',
    effectiveAtMs: EFF,
    title: '서비스 이용약관',
    content: 'B 본문',
    contentHash: 'hashB',
  },
});

t('E5-1 시행 1ms 전 — 현재는 A, 예정은 B', () => {
  const r = M.resolveEffectiveItem(baseItem(), EFF - 1);
  assert.strictEqual(r.item.version, '2026.08');
  assert.strictEqual(r.item.revisionId, 'service_terms__2026.08');
  assert.strictEqual(r.promoted, false);
  assert.ok(r.pendingUpcoming, '예정 판을 알려 줘야 한다');
  assert.strictEqual(r.pendingUpcoming.version, '2026-10-08');
});

t('E5-2 시행 정각 — 현재가 B 가 된다', () => {
  const r = M.resolveEffectiveItem(baseItem(), EFF);
  assert.strictEqual(r.item.version, '2026-10-08');
  assert.strictEqual(r.item.revisionId, 'service_terms__2026-10-08');
  assert.strictEqual(r.promoted, true);
  assert.strictEqual(r.pendingUpcoming, null);
});

t('E5-3 시행 1ms 후 — 여전히 B', () => {
  const r = M.resolveEffectiveItem(baseItem(), EFF + 1);
  assert.strictEqual(r.item.version, '2026-10-08');
  assert.strictEqual(r.promoted, true);
});

t('E5-4 예정 판이 없으면 그대로 base 다', () => {
  const it = baseItem();
  it.upcoming = null;
  const r = M.resolveEffectiveItem(it, EFF + 10 * DAY);
  assert.strictEqual(r.item.version, '2026.08');
  assert.strictEqual(r.pendingUpcoming, null);
  assert.strictEqual(r.promoted, false);
});

t('E5-5 시각을 읽을 수 없는 예정 판은 승격하지 않는다', () => {
  for (const bad of [null, undefined, NaN, Infinity, 'soon']) {
    const it = baseItem();
    it.upcoming = {version: 'x', revisionId: 'y', effectiveAtMs: bad};
    const r = M.resolveEffectiveItem(it, EFF + 999 * DAY);
    assert.strictEqual(r.item.version, '2026.08', String(bad));
    assert.strictEqual(r.promoted, false, String(bad));
  }
});

// ══════════════════════════════════════════════════════════════════
// E-6  승격은 한 벌 전체를 옮긴다
// ══════════════════════════════════════════════════════════════════

t('E6-1 버전·포인터·제목·본문·해시·시행일이 함께 옮겨진다', () => {
  const raw = {
    id: 'service_terms', title: 'A 제목', content: 'A 본문',
    version: '2026.08', revisionId: 'service_terms__2026.08',
    contentHash: 'hashA', effectiveAt: 'TS_A', order: 1,
    isRequired: true, isActive: true,
    upcoming: {
      version: '2026-10-08', revisionId: 'service_terms__2026-10-08',
      title: 'B 제목', content: 'B 본문', contentHash: 'hashB',
      effectiveAt: 'TS_B',
    },
  };
  const r = M.promoteDueUpcoming({raw, upcomingEffectiveAtMs: EFF, nowMs: EFF});
  assert.strictEqual(r.promoted, true);
  assert.strictEqual(r.raw.version, '2026-10-08');
  assert.strictEqual(r.raw.revisionId, 'service_terms__2026-10-08');
  assert.strictEqual(r.raw.title, 'B 제목');
  assert.strictEqual(r.raw.content, 'B 본문',
    '본문이 남으면 새 버전 번호에 옛 글이 붙는다 — 어느 글도 아니다');
  assert.strictEqual(r.raw.contentHash, 'hashB');
  assert.strictEqual(r.raw.effectiveAt, 'TS_B');
  assert.strictEqual(r.raw.upcoming, null);
  // 항목 자체의 속성은 보존된다.
  assert.strictEqual(r.raw.id, 'service_terms');
  assert.strictEqual(r.raw.order, 1);
  assert.strictEqual(r.raw.isRequired, true);
  // 원본을 고치지 않는다.
  assert.strictEqual(raw.version, '2026.08');
});

t('E6-2 아직 시행 전이면 아무것도 옮기지 않는다', () => {
  const raw = {id: 'x', version: 'A', upcoming: {version: 'B'}};
  const r = M.promoteDueUpcoming({
    raw, upcomingEffectiveAtMs: EFF, nowMs: EFF - 1,
  });
  assert.strictEqual(r.promoted, false);
  assert.strictEqual(r.raw.version, 'A');
  assert.strictEqual(r.raw, raw, '바뀌지 않으면 같은 객체를 돌려준다');
});

t('E6-3 예정 판이 없으면 멱등하다', () => {
  for (const up of [undefined, null, 'x', 42, []]) {
    const raw = {id: 'x', version: 'A', upcoming: up};
    const r = M.promoteDueUpcoming({
      raw, upcomingEffectiveAtMs: EFF, nowMs: EFF + DAY,
    });
    assert.strictEqual(r.promoted, false, String(up));
  }
});

// ══════════════════════════════════════════════════════════════════
// E-7  readiness·동의 writer 는 시행 중인 판을 기준으로 한다
// ══════════════════════════════════════════════════════════════════

t('E7-1 projection 해석기가 하나다 — 각자 계산하지 않는다', () => {
  const s = indexSrc();
  const uses = (s.match(/srvResolveLegalProjection\(/g) || []).length;
  // 정의 1 + readiness 1 + 동의 writer 1
  assert.strictEqual(uses, 3,
    `해석기 사용처가 ${uses}곳이다 — 새 reader 가 자기 규칙을 만들었는지 확인`);
  const i = s.indexOf('async function srvLegalReadiness');
  const body = s.slice(i, i + 1600);
  assert.ok(body.includes('srvResolveLegalProjection'),
    'readiness 가 해석기를 쓰지 않는다');
  assert.ok(body.includes('Timestamp.now().toMillis()'),
    'readiness 가 서버 시각을 쓰지 않는다');
});

t('E7-2 동의 writer 도 시행 중인 판만 받는다', () => {
  const s = indexSrc();
  const i = s.indexOf('export const callableRecordTermsConsent');
  const j = s.indexOf('\nexport const ', i + 10);
  const body = s.slice(i, j > 0 ? j : s.length);
  assert.ok(body.includes('srvResolveLegalProjection'),
    '동의 writer 가 raw projection 을 직접 읽는다');
  assert.ok(body.includes('Timestamp.now().toMillis()'),
    '동의 writer 가 서버 시각을 쓰지 않는다');
  // 예정 판 버전을 보내면 기존 stale 규칙으로 거절된다.
  assert.ok(body.includes('TERMS_VERSION_STALE'));
});

t('E7-3 readiness 는 예정 판을 status 에 섞지 않는다', () => {
  const s = indexSrc();
  const i = s.indexOf('export const callableGetLegalReadiness');
  const j = s.indexOf('\nexport const ', i + 10);
  const body = s.slice(i, j > 0 ? j : s.length);
  assert.ok(body.includes('upcoming: r.upcoming'), '예정 안내를 안 내려 준다');
  // status 는 네 값 그대로다 — NOTICE_PENDING 류를 추가하지 않았다.
  for (const bad of ['NOTICE_PENDING', 'UPCOMING_REQUIRED']) {
    assert.ok(!s.includes(bad), bad + ' 가 생겼다');
  }
});

t('E7-4 발행이 base 를 바로 교체하지 않는다', () => {
  const s = indexSrc();
  const i = s.indexOf('export const callablePublishLegalRevision');
  const j = s.indexOf('\nexport const ', i + 10);
  const body = s.slice(i, j > 0 ? j : s.length);
  assert.ok(body.includes('lpEvaluateNoticePeriod'), '고지기간 검사가 없다');
  assert.ok(body.includes('lpPromoteDueUpcoming'), '승격을 공용 함수로 하지 않는다');
  assert.ok(body.includes('upcomingFields: {'), '예정 자리 값을 만들지 않는다');
  assert.ok(body.includes('effectiveAtMs: notice.effectiveAtMs'), '시행 시각을 넘기지 않는다');
  assert.ok(body.includes('Timestamp.now().toMillis()'), '서버 시각을 쓰지 않는다');
});

t('E7-5 시행 전환은 reconciliation 이고, 스케줄러에 걸려 있다', () => {
  const s = indexSrc();
  assert.ok(s.includes('processDueLegalRevisions(timestamp)'),
    '스케줄러에 등록되지 않았다 — base 가 영구히 낡는다');
  const i = s.indexOf('async function processDueLegalRevisions');
  const body = s.slice(i, i + 2000);
  assert.ok(body.includes('lpPromoteDueUpcoming'), '공용 승격 함수를 쓰지 않는다');
  assert.ok(body.includes('if (!changed) return;'), '멱등하지 않다');
});

// ══════════════════════════════════════════════════════════════════
// E-8 / E-9  공개 웹과 CF 가 같은 규칙
// ══════════════════════════════════════════════════════════════════

/** 공개 웹이 받는 모양(REST parse 결과)으로 같은 상황을 만든다. */
const webItem = () => ({
  id: 'service_terms', title: 'A 제목', content: 'A 본문',
  version: '2026.08', revisionId: 'service_terms__2026.08',
  isActive: true, isRequired: true,
  effectiveAt: new Date(TODAY_KST - 60 * DAY).toISOString(),
  upcoming: {
    version: '2026-10-08', revisionId: 'service_terms__2026-10-08',
    title: 'B 제목', content: 'B 본문', contentHash: 'hashB',
    effectiveAt: new Date(EFF).toISOString(),
  },
});

t('E8-1 같은 시각에 같은 판을 고른다 (경계 3점)', () => {
  for (const [nowMs, want] of [
    [EFF - 1, '2026.08'], [EFF, '2026-10-08'], [EFF + 1, '2026-10-08'],
  ]) {
    const cf = M.resolveEffectiveItem(baseItem(), nowMs).item.version;
    const web = WEB.resolveEffective(webItem(), nowMs).effective.version;
    assert.strictEqual(cf, want, 'CF @' + nowMs);
    assert.strictEqual(web, want, 'WEB @' + nowMs);
    assert.strictEqual(cf, web, '두 reader 가 다른 판을 말한다 @' + nowMs);
  }
});

t('E8-2 공개 웹도 승격 때 본문을 함께 옮긴다', () => {
  const r = WEB.resolveEffective(webItem(), EFF);
  assert.strictEqual(r.effective.version, '2026-10-08');
  assert.strictEqual(r.effective.content, 'B 본문');
  assert.strictEqual(r.effective.title, 'B 제목');
  assert.strictEqual(r.upcoming, null);
});

t('E9-1 서버 시각을 모르면 승격하지 않는다', () => {
  for (const bad of [null, undefined, NaN]) {
    const r = WEB.resolveEffective(webItem(), bad);
    assert.strictEqual(r.effective.version, '2026.08', String(bad));
    assert.ok(r.upcoming, '예정 판은 그대로 남는다');
  }
});

t('E9-2 공개 웹은 기기 시계를 쓰지 않는다', () => {
  const src = fs.readFileSync(
    path.join(ROOT, 'public', 'legal-reader.js'), 'utf8')
    .split('\n').filter((l) => !l.trimStart().startsWith('//')).join('\n');
  assert.ok(!/Date\.now\(\)/.test(src),
    '기기 시계로 시행을 판정하면 시계를 돌린 방문자에게 예정 약관이 보인다');
  assert.ok(src.includes("headers.get('date')"),
    '서버 시각(Date 헤더)을 읽지 않는다');
});

t('E9-3 발행본은 시행 중인 판의 것을 읽는다', () => {
  const src = fs.readFileSync(
    path.join(ROOT, 'public', 'legal-reader.js'), 'utf8');
  const i = src.indexOf('async function loadAndRender');
  const body = src.slice(i);
  // 승격 판정을 먼저 하고, 그 결과의 revisionId 로 발행본을 읽어야 한다.
  const r = body.indexOf('resolveEffective(picked, nowMs)');
  const f = body.indexOf('/legal_revisions/');
  assert.ok(r > 0 && f > r,
    '시행 판을 정하기 전에 발행본을 읽으면 옛 판 본문이 나온다');
});

t('E9-4 시행 예정 안내는 현재 약관과 구분된다', () => {
  const view = WEB.buildLegalView({
    termsDoc: {fields: {items: {arrayValue: {values: [{mapValue: {fields: {
      id: {stringValue: 'service_terms'},
      title: {stringValue: 'A 제목'},
      content: {stringValue: 'A 본문'},
      version: {stringValue: '2026.08'},
      isActive: {booleanValue: true},
      upcoming: {mapValue: {fields: {
        version: {stringValue: '2026-10-08'},
        revisionId: {stringValue: 'service_terms__2026-10-08'},
        effectiveAt: {timestampValue: new Date(EFF).toISOString()},
      }}},
    }}}]}}}},
    itemId: 'service_terms',
    nowMs: EFF - DAY,
  });
  assert.strictEqual(view.state, 'SUCCESS_CURRENT');
  assert.strictEqual(view.version, '2026.08', '현재 약관은 A 다');
  assert.ok(view.upcoming, '예정 안내가 없다');
  assert.strictEqual(view.upcoming.version, '2026-10-08');
  const label = WEB.upcomingLabel(view);
  assert.ok(label.includes('시행 예정'), label);
  assert.ok(!label.includes('현재'), '예정을 현재로 말하지 않는다');
});

// ══════════════════════════════════════════════════════════════════
// E-11  발행된 판을 어느 자리에 두는가
//
//   `.5A` 변이 M12 가 여기서 빠져나갔다 — 배치 판단이 writer 안에
//   인라인이라 소스 모양만 보고 있었고, `isEffectiveNow = true` 로 바꿔도
//   아무 테스트가 깨지지 않았다. 그래서 순수 함수로 꺼냈다.
// ══════════════════════════════════════════════════════════════════

const BASE = () => ({
  id: 'service_terms', title: 'A 제목', content: 'A 본문',
  version: '2026.08', revisionId: 'service_terms__2026.08',
  contentHash: 'hashA', effectiveAt: 'TS_A', order: 1,
  isRequired: true, isActive: true, upcoming: null,
});
const NEWBASE = () => ({
  id: 'service_terms', title: 'B 제목', content: 'B 본문',
  version: '2026-11-07', revisionId: 'service_terms__2026-11-07',
  contentHash: 'hashB', effectiveAt: 'TS_B', order: 1,
  isRequired: true, isActive: true,
});
const NEWUP = () => ({
  version: '2026-11-07', revisionId: 'service_terms__2026-11-07',
  title: 'B 제목', content: 'B 본문', contentHash: 'hashB',
  effectiveAt: 'TS_B',
});

t('E11-1 시행 예정이면 base 를 건드리지 않고 대기 자리에만 쓴다', () => {
  const r = M.placePublishedRevision({
    items: [BASE()],
    itemId: 'service_terms',
    revisionId: 'service_terms__2026-11-07',
    baseFields: NEWBASE(),
    upcomingFields: NEWUP(),
    effectiveAtMs: 2000, nowMs: 1000,
  });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.placed, 'upcoming');
  const it = r.items[0];
  // 현재 약관은 그대로 A 다 — 이것이 `.5A` 의 핵심이다.
  assert.strictEqual(it.version, '2026.08');
  assert.strictEqual(it.revisionId, 'service_terms__2026.08');
  assert.strictEqual(it.content, 'A 본문');
  assert.strictEqual(it.effectiveAt, 'TS_A');
  // 예정 판은 대기 자리에 한 벌로 들어간다.
  assert.strictEqual(it.upcoming.version, '2026-11-07');
  assert.strictEqual(it.upcoming.content, 'B 본문');
  assert.strictEqual(it.upcoming.effectiveAt, 'TS_B');
});

t('E11-2 첫 발행은 base 에 들어가고 대기 자리는 비어 있다', () => {
  const r = M.placePublishedRevision({
    items: [],
    itemId: 'service_terms',
    revisionId: 'service_terms__2026.08',
    baseFields: BASE(),
    upcomingFields: NEWUP(),
    effectiveAtMs: 1000, nowMs: 2000,
  });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.placed, 'base');
  assert.strictEqual(r.items.length, 1);
  assert.strictEqual(r.items[0].version, '2026.08');
  assert.strictEqual(r.items[0].upcoming, null);
});

t('E11-3 노출 토글이 대기 중인 고지를 지우지 않는다', () => {
  const items = [{...BASE(), upcoming: NEWUP()}];
  const r = M.placePublishedRevision({
    items,
    itemId: 'service_terms',
    revisionId: 'service_terms__2026.08',   // base 와 같은 판
    baseFields: {...BASE(), isActive: false},
    upcomingFields: NEWUP(),
    effectiveAtMs: 1000, nowMs: 2000,
  });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.items[0].isActive, false, '토글이 반영돼야 한다');
  assert.ok(r.items[0].upcoming, '예고된 변경이 사라졌다 — 고지가 없어진다');
  assert.strictEqual(r.items[0].upcoming.version, '2026-11-07');
});

t('E11-4 지난 시행일로 현재 약관을 되돌릴 수 없다', () => {
  // base 가 B 인데 과거에 시행됐던 A 를 다시 밀어 넣는 경우.
  const items = [NEWBASE()];
  const r = M.placePublishedRevision({
    items,
    itemId: 'service_terms',
    revisionId: 'service_terms__2026.08',
    baseFields: BASE(),
    upcomingFields: NEWUP(),
    effectiveAtMs: 1000, nowMs: 2000,
  });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, 'EFFECTIVE_AT_IN_PAST');
});

t('E11-5 항목이 없는데 시행 예정으로 두려 하면 거절한다', () => {
  // 그러면 시행 중인 판이 없는 채로 공개 목록에 들어간다.
  const r = M.placePublishedRevision({
    items: [],
    itemId: 'service_terms',
    revisionId: 'service_terms__2026-11-07',
    baseFields: NEWBASE(),
    upcomingFields: NEWUP(),
    effectiveAtMs: 2000, nowMs: 1000,
  });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, 'EFFECTIVE_AT_IN_PAST');
});

t('E11-6 다른 항목은 건드리지 않고, 원본 배열도 고치지 않는다', () => {
  const other = {id: 'marketing_consent', version: '2026.08', upcoming: null};
  const items = [BASE(), other];
  const r = M.placePublishedRevision({
    items,
    itemId: 'service_terms',
    revisionId: 'service_terms__2026-11-07',
    baseFields: NEWBASE(),
    upcomingFields: NEWUP(),
    effectiveAtMs: 2000, nowMs: 1000,
  });
  assert.strictEqual(r.items.length, 2);
  assert.strictEqual(r.items[1].id, 'marketing_consent');
  assert.strictEqual(r.items[1].version, '2026.08');
  // 원본 불변.
  assert.strictEqual(items[0].upcoming, null);
});

t('E11-7 대기 중이던 판은 새 예정 판으로 교체된다', () => {
  const stale = {
    version: '2026-10-20', revisionId: 'service_terms__2026-10-20',
    title: '옛 예정', content: '옛 예정 본문', effectiveAt: 'TS_OLD',
  };
  const r = M.placePublishedRevision({
    items: [{...BASE(), upcoming: stale}],
    itemId: 'service_terms',
    revisionId: 'service_terms__2026-11-07',
    baseFields: NEWBASE(),
    upcomingFields: NEWUP(),
    effectiveAtMs: 2000, nowMs: 1000,
  });
  assert.strictEqual(r.items[0].upcoming.version, '2026-11-07');
  assert.strictEqual(r.items[0].upcoming.effectiveAt, 'TS_B');
  // 교체된 쪽은 한 번도 시행된 적이 없다 — base 는 그대로 A.
  assert.strictEqual(r.items[0].version, '2026.08');
});

t('E11-9 시행 여부는 두 시각의 비교로 정해진다 (경계 3점)', () => {
  // `.5A` 변이 M12b 는 이 한 줄이 index.ts 안에 불리언으로 있어서
  //   빠져나갔다. 지금은 여기서 판단하므로 경계를 직접 볼 수 있다.
  const call = (effectiveAtMs, nowMs) => M.placePublishedRevision({
    items: [BASE()],
    itemId: 'service_terms',
    revisionId: 'service_terms__2026-11-07',
    baseFields: NEWBASE(),
    upcomingFields: NEWUP(),
    effectiveAtMs, nowMs,
  });
  const EFF2 = 1700000000000;
  assert.strictEqual(call(EFF2, EFF2 - 1).placed, 'upcoming', '1ms 전');
  // 정각·1ms 후는 base 자리로 가지만, base 와 다른 판이므로 거절된다 —
  // 즉 "시행 시각이 지난 새 판" 은 발행 시점에 올 수 없다는 뜻이고,
  // 고지기간 검사가 그것을 먼저 막는다.
  assert.strictEqual(call(EFF2, EFF2).reason, 'EFFECTIVE_AT_IN_PAST', '정각');
  assert.strictEqual(call(EFF2, EFF2 + 1).reason, 'EFFECTIVE_AT_IN_PAST',
    '1ms 후');
  // 같은 판을 다시 보내면(토글) 정각·이후에 base 자리로 간다.
  const same = (nowMs) => M.placePublishedRevision({
    items: [BASE()],
    itemId: 'service_terms',
    revisionId: 'service_terms__2026.08',
    baseFields: BASE(),
    upcomingFields: NEWUP(),
    effectiveAtMs: EFF2, nowMs,
  });
  assert.strictEqual(same(EFF2).placed, 'base');
  assert.strictEqual(same(EFF2 + 1).placed, 'base');
  assert.strictEqual(same(EFF2 - 1).placed, 'upcoming',
    '아직 시행 전이면 base 를 건드리지 않는다');
});

t('E11-8 writer 가 그 함수를 쓴다 — 인라인 분기를 다시 만들지 않았다', () => {
  const s = indexSrc();
  const i = s.indexOf('export const callablePublishLegalRevision');
  const j = s.indexOf('\nexport const ', i + 10);
  const body = s.slice(i, j > 0 ? j : s.length);
  assert.ok(body.includes('lpPlacePublishedRevision('), '배치 함수를 쓰지 않는다');
  assert.ok(!/items\[at\]\s*=\s*\{/.test(body),
    'writer 안에 자리 배치가 다시 들어왔다');
});

// ══════════════════════════════════════════════════════════════════
// E-10  Dart 쪽 변환이 서버 정의와 같은 값을 낸다
// ══════════════════════════════════════════════════════════════════

t('E10-1 Dart kstMidnightOfDate 가 서버가 요구하는 KST 자정을 만든다', () => {
  // Dart: DateTime.utc(y, m, d).subtract(Duration(hours: 9))
  //   그 식이 실제로 그 모양인지는 Dart 테스트(L-1/03)가 고정한다. 여기서는
  //   그 식의 **결과**가 서버 정의(kstMidnightMs)를 통과하는지 본다.
  //   한쪽만 고치면 발행이 EFFECTIVE_AT_NOT_KST_MIDNIGHT 로 막힌다.
  const dart = (y, m, d) => Date.UTC(y, m - 1, d) - 9 * 60 * 60 * 1000;
  const cases = [
    [2026, 1, 1], [2026, 3, 1], [2026, 10, 8], [2026, 11, 7],
    [2026, 12, 31], [2027, 2, 28], [2028, 2, 29],
  ];
  for (const [y, m, d] of cases) {
    const v = dart(y, m, d);
    assert.strictEqual(M.kstMidnightMs(v), v,
      `${y}-${m}-${d} 가 서버 기준 KST 자정이 아니다`);
  }
  // UTC 자정은 통과하지 못한다 — 두 정의가 다르다는 증거.
  assert.notStrictEqual(M.kstMidnightMs(Date.UTC(2026, 10, 7)),
    Date.UTC(2026, 10, 7));
});

t('E10-2 Dart 소스가 그 식을 그대로 들고 있다', () => {
  const src = fs.readFileSync(
    path.join(ROOT, 'lib', 'models', 'core', 'legal_terms_model.dart'),
    'utf8');
  assert.ok(
    src.includes(
      'DateTime.utc(year, month, day).subtract(const Duration(hours: 9))'),
    'canonical 변환 식이 바뀌었다 — E10-1 의 가정이 깨진다');
});

t('E10-3 분류에 "오탈자" 류가 없다 — 우회 구멍을 만들지 않는다', () => {
  // `.5` 는 서비스 역할·책임·근태 기준 신설·제3자 제공 보완을 담았다.
  // 그것을 "오탈자" 로 분류해 고지기간을 건너뛰는 경로가 있으면 안 된다.
  const keys = Object.keys(M.LEGAL_NOTICE_DAYS).sort();
  assert.deepStrictEqual(keys, ['adverse', 'initial', 'neutral']);
  const dart = fs.readFileSync(
    path.join(ROOT, 'lib', 'models', 'core', 'legal_terms_model.dart'),
    'utf8');
  for (const bad of ['clerical', 'typo', 'urgent', 'legalCorrection']) {
    assert.ok(!dart.includes(bad), `클라이언트에 ${bad} 분류가 생겼다`);
  }
  // initial 을 뺀 나머지는 모두 7일 이상이다.
  for (const k of ['neutral', 'adverse']) {
    assert.ok(M.LEGAL_NOTICE_DAYS[k] >= 7, k);
  }
});

console.log(`\n${pass} passed, ${fails.length} failed`);
if (fails.length) {
  for (const f of fails) console.log('  - ' + f);
  process.exit(1);
}
