// [R7-BANKBOOK-EVIDENCE-AUTHORITY.2] 지급 계좌 동일성 — **설계 계약** 테스트.
//
//   실행:  cd functions && node test/bankbook_payment_account_identity.test.js
//
//   왜 이 테스트가 필요한가
//
//     앞 Phase 의 C-minimal 권고는 "클라이언트가 평문 계좌번호를 **추가로**
//     보내면 서버가 그 값으로 HMAC 지문을 만든다" 였다. 그런데 지급에 쓰이는
//     값은 같은 요청의 **다른 필드**(AES 암호문)다. 서버는 그 암호문을
//     복호화할 수 없으므로(클라이언트 키 미보유) 두 값이 같은 계좌인지
//     확인할 방법이 없다.
//
//       입력:  accountNumber = AES(계좌 A)   ← 지급에 쓰인다
//              plaintext     = 계좌 B        ← 지문·OCR 대조에 쓰인다
//       결과:  문서(계좌 B)로 MATCHED → 자동 지급 준비 → 돈은 **계좌 A** 로
//
//     즉 "확인한 계좌"와 "입금되는 계좌"가 갈라진다. 이 파일은 그 발산을
//     합성 데이터로 **재현**하고, 발산이 구조적으로 불가능한 계약을 고정한다.
//
//   무엇을 고정하는가
//     D1  평문을 별도 입력으로 받는 설계는 발산을 허용한다            (취약)
//     D2  지급에 쓰이는 **그 암호문에서** 판정 입력을 끌어내면 불가능 (권고)
//     그리고 §3 판정 시나리오 7개 · §4 버전·동시성 계약.
//
//   이 테스트는 production 코드를 호출하지 않는다. 아직 구현이 없기 때문이다.
//   참조 구현(_refEvaluate)은 **설계 계약 그 자체**이며, 구현 시 이 계약을
//   그대로 옮기면 된다.
'use strict';

const crypto = require('crypto');
const assert = require('assert');

let pass = 0;
let fail = 0;
function check(label, fn) {
  try {
    fn();
    pass++;
    console.log('  [PASS] ' + label);
  } catch (e) {
    fail++;
    console.log('  [FAIL] ' + label + ' — ' + e.message);
  }
}

// ── 합성 암호화 (클라이언트 AES-CBC·랜덤 IV 를 모사) ─────────────
//   실제 계좌번호는 쓰지 않는다. 전부 합성 자리표시자다.
const CLIENT_KEY = crypto.createHash('sha256').update('synthetic-client-key').digest();
function aesEncrypt(plain) {
  const iv = crypto.randomBytes(16);
  const c = crypto.createCipheriv('aes-256-cbc', CLIENT_KEY, iv);
  const enc = Buffer.concat([c.update(String(plain), 'utf8'), c.final()]);
  return iv.toString('base64') + ':' + enc.toString('base64');
}
function aesDecrypt(stored, key) {
  try {
    const i = String(stored).indexOf(':');
    if (i < 0) return null;
    const iv = Buffer.from(String(stored).slice(0, i), 'base64');
    const d = crypto.createDecipheriv('aes-256-cbc', key, iv);
    return Buffer.concat([
      d.update(Buffer.from(String(stored).slice(i + 1), 'base64')), d.final(),
    ]).toString('utf8');
  } catch (e) {
    return null;
  }
}
// 이 테스트가 필요한 것은 **일관된** HMAC 키 하나뿐이다 — 비밀이 아니다.
//   `..._SECRET` 이라는 이름은 사실과 다르고, 저장소 비밀 탐지기
//   (`scripts/check_secrets.js` SEC-SECRET)를 울려 신호를 흐린다.
//   이름과 값이 둘 다 "테스트용"이라고 말하게 둔다.
const TEST_HMAC_KEY = 'r8-test-hmac-key-not-a-secret';
const fingerprint = (plain) =>
  crypto.createHmac('sha256', TEST_HMAC_KEY).update(String(plain)).digest('hex');

// 합성 계좌 (실데이터 아님)
const ACC_A = '110000000001'; // 실제 지급될 계좌
const ACC_B = '220000000002'; // 공격자가 검증시키려는 계좌

// ── 판정 상수 ────────────────────────────────────────────────────
const MATCHED = 'MATCHED';
const MISMATCH = 'MISMATCH';
const UNREADABLE = 'UNREADABLE';
const UNASSESSED = 'UNASSESSED';
// 근거의 **출처**만 말한다. 금융기관 실명조회가 아니므로
//   SERVER_VERIFIED·은행 인증 완료 같은 이름은 쓰지 않는다.
const ASSURANCE_SERVER = 'SERVER_OCR_EVIDENCE';
const ASSURANCE_CLIENT = 'CLIENT_EVIDENCE';

/**
 * 권고 계약(D2)의 참조 구현.
 *
 *   판정 입력은 **지급에 쓰이는 암호문에서만** 나온다. 클라이언트가 보낸
 *   outcome·평문·후보는 판정에 쓰지 않는다(안내용으로만 보존).
 */
function _refEvaluate(input) {
  const {
    storedCiphertext,      // users.accountNumber — 지급 snapshot 의 원천
    serverKey,             // 서버가 복호화에 쓰는 키(승인 항목)
    serverOcrCandidates,   // 서버가 Vision 결과에서 뽑은 숫자 후보
    serverOcrFailed,
    versionsAtRead,        // {acc, doc} — OCR 시작 시점
    versionsAtCommit,      // {acc, doc} — 저장 트랜잭션 시점
    clientClaim,           // 클라이언트 주장(무시되어야 한다)
  } = input;

  // [§4] 외부 OCR 은 트랜잭션 밖에서 돈다. 저장 시점에 상태가 달라졌으면
  //   낡은 결과를 새 계좌·새 통장에 붙이지 않는다 — 저장을 포기한다.
  if (versionsAtRead.acc !== versionsAtCommit.acc ||
      versionsAtRead.doc !== versionsAtCommit.doc) {
    return {verdict: null, stored: false, reason: 'STALE_RETRY'};
  }
  // OCR 이 실패했으면 아무것도 주장하지 않는다.
  if (serverOcrFailed) {
    return {verdict: UNREADABLE, assurance: ASSURANCE_SERVER, stored: true,
      reason: 'OCR_FAILED'};
  }
  // 지급에 쓰이는 값을 서버가 읽지 못하면 **비교 자체가 불가능**하다.
  //   이때 MATCHED 로 올리지 않는다. 사람 검토 경로로 보낸다.
  const payPlain = aesDecrypt(storedCiphertext, serverKey);
  if (payPlain === null) {
    return {verdict: UNASSESSED, assurance: ASSURANCE_SERVER, stored: true,
      reason: 'PAY_VALUE_UNREADABLE'};
  }
  const cands = (serverOcrCandidates || []).map((c) => String(c).replace(/\D/g, ''));
  const usable = cands.filter((c) => c.length >= 9 && c.length <= 20);
  if (usable.length === 0) {
    return {verdict: UNREADABLE, assurance: ASSURANCE_SERVER, stored: true,
      reason: 'NO_CANDIDATE'};
  }
  // 지문 비교 — 평문을 저장하지 않고도 동일성을 판정한다.
  const payFp = fingerprint(payPlain);
  const hit = usable.some((c) => fingerprint(c) === payFp);
  return {
    verdict: hit ? MATCHED : MISMATCH,
    assurance: ASSURANCE_SERVER,
    stored: true,
    clientClaimIgnored: clientClaim !== undefined,
    reason: null,
  };
}

/** READY_AUTO 승격 계약 — 서버 근거의 MATCHED 만 자동이다. */
function _refReadyAuto({verdict, assurance, manualOk}) {
  if (verdict === MATCHED && assurance === ASSURANCE_SERVER) return 'READY_AUTO';
  if (manualOk) return 'READY_MANUAL';
  return 'BLOCKED';
}

const V = {acc: 3, doc: 7};
const base = (over) => Object.assign({
  storedCiphertext: aesEncrypt(ACC_A),
  serverKey: CLIENT_KEY,
  serverOcrCandidates: [ACC_A],
  serverOcrFailed: false,
  versionsAtRead: V,
  versionsAtCommit: V,
}, over);

console.log('\n════ §2 지급 계좌와 검증 계좌의 동일성 ════');

check('D1(평문 별도 입력) — 암호문 A / 지문 입력 B 가 발산한다 [취약 재현]', () => {
  // 앞 Phase 권고를 그대로 모사한다: 서버가 클라이언트의 평문을 신뢰.
  const stored = {
    accountNumber: aesEncrypt(ACC_A),          // 지급될 계좌
    bankAccountFingerprint: fingerprint(ACC_B), // 클라이언트가 보낸 평문 B 기준
  };
  // 문서에는 계좌 B 가 적혀 있다(공격자가 가진 다른 통장).
  const docCandidate = ACC_B;
  const matched = fingerprint(docCandidate) === stored.bankAccountFingerprint;
  assert.strictEqual(matched, true, 'D1 에서는 문서 B 가 지문 B 와 일치한다');
  // 그런데 지급에 쓰이는 값은 A 다 — 확인한 계좌와 입금 계좌가 다르다.
  const payPlain = aesDecrypt(stored.accountNumber, CLIENT_KEY);
  assert.strictEqual(payPlain, ACC_A);
  assert.notStrictEqual(payPlain, docCandidate);
});

check('D2(암호문에서 파생) — 같은 입력으로는 MATCHED 가 되지 않는다', () => {
  const r = _refEvaluate(base({serverOcrCandidates: [ACC_B]}));
  assert.strictEqual(r.verdict, MISMATCH);
});

check('D2 — 발산 자체가 표현 불가능하다 (판정 입력이 하나뿐)', () => {
  // 클라이언트가 평문·지문·outcome 을 무엇으로 보내도 판정에 들어가지 않는다.
  const r = _refEvaluate(base({
    clientClaim: {identifier: 'MATCHED', plaintext: ACC_B, fingerprint: fingerprint(ACC_B)},
    serverOcrCandidates: [ACC_B],
  }));
  assert.strictEqual(r.verdict, MISMATCH);
  assert.strictEqual(r.clientClaimIgnored, true);
});

console.log('\n════ §3 서버 소유 판정 시나리오 ════');

check('1 정상 — 문서 후보가 지급 계좌와 같다 → MATCHED · 자동', () => {
  const r = _refEvaluate(base());
  assert.strictEqual(r.verdict, MATCHED);
  assert.strictEqual(r.assurance, ASSURANCE_SERVER);
  assert.strictEqual(_refReadyAuto({...r, manualOk: false}), 'READY_AUTO');
});

check('2 다른 계좌 문서 → MISMATCH · 자동 아님', () => {
  const r = _refEvaluate(base({serverOcrCandidates: [ACC_B]}));
  assert.strictEqual(r.verdict, MISMATCH);
  assert.strictEqual(_refReadyAuto({...r, manualOk: false}), 'BLOCKED');
});

check('3 계좌 일부만 인식 → UNREADABLE (불일치라고 말하지 않는다)', () => {
  const r = _refEvaluate(base({serverOcrCandidates: ['1100-0000']}));
  assert.strictEqual(r.verdict, UNREADABLE);
});

check('4 전화·날짜만 인식 → UNREADABLE', () => {
  const r = _refEvaluate(base({serverOcrCandidates: ['15778000', '2024-03-15']}));
  assert.strictEqual(r.verdict, UNREADABLE);
});

check('5 1×1 이미지 + 클라이언트 MATCHED 주장 → UNREADABLE', () => {
  // 서버 OCR 은 아무 후보도 못 뽑는다. 클라이언트 주장은 판정에 없다.
  const r = _refEvaluate(base({
    serverOcrCandidates: [],
    clientClaim: {identifier: 'MATCHED'},
  }));
  assert.strictEqual(r.verdict, UNREADABLE);
  assert.strictEqual(_refReadyAuto({...r, manualOk: false}), 'BLOCKED');
});

check('6 OCR 실패·타임아웃 → UNREADABLE · 자동 승격 없음', () => {
  const r = _refEvaluate(base({serverOcrFailed: true}));
  assert.strictEqual(r.verdict, UNREADABLE);
  assert.strictEqual(_refReadyAuto({...r, manualOk: false}), 'BLOCKED');
});

check('7 다른 은행 문서 — 계좌가 같으면 통과 (은행은 판정 축이 아니다)', () => {
  // 기존 계약 유지: isDocumentConsistent 는 계좌·예금주만 본다.
  const r = _refEvaluate(base({serverOcrCandidates: [ACC_A]}));
  assert.strictEqual(r.verdict, MATCHED);
});

check('서버가 지급 값을 못 읽으면 UNASSESSED — MATCHED 로 올리지 않는다', () => {
  const r = _refEvaluate(base({serverKey: crypto.randomBytes(32)}));
  assert.strictEqual(r.verdict, UNASSESSED);
  assert.strictEqual(_refReadyAuto({...r, manualOk: false}), 'BLOCKED');
});

console.log('\n════ §4 동시성 · 버전 계약 ════');

check('OCR 중 계좌가 바뀌면 저장하지 않는다 (낡은 결과 금지)', () => {
  const r = _refEvaluate(base({versionsAtCommit: {acc: 4, doc: 7}}));
  assert.strictEqual(r.stored, false);
  assert.strictEqual(r.reason, 'STALE_RETRY');
});

check('OCR 중 새 통장이 올라오면 저장하지 않는다', () => {
  const r = _refEvaluate(base({versionsAtCommit: {acc: 3, doc: 8}}));
  assert.strictEqual(r.stored, false);
});

check('버전이 그대로면 저장한다', () => {
  const r = _refEvaluate(base());
  assert.strictEqual(r.stored, true);
});

check('동일 문서 중복 제출 — 같은 입력이면 같은 판정(멱등)', () => {
  const ct = aesEncrypt(ACC_A);
  const a = _refEvaluate(base({storedCiphertext: ct}));
  const b = _refEvaluate(base({storedCiphertext: ct}));
  assert.strictEqual(a.verdict, b.verdict);
});

console.log('\n════ §5 기존 사용자 전환 계약 ════');

check('기존 CLIENT_EVIDENCE MATCHED 는 자동 근거가 아니다', () => {
  const state = {verdict: MATCHED, assurance: ASSURANCE_CLIENT};
  assert.strictEqual(_refReadyAuto({...state, manualOk: false}), 'BLOCKED');
});

check('기존 사용자라도 관리자 검토가 있으면 통과한다 (일괄 차단 아님)', () => {
  const state = {verdict: MATCHED, assurance: ASSURANCE_CLIENT};
  assert.strictEqual(_refReadyAuto({...state, manualOk: true}), 'READY_MANUAL');
});

check('구버전 주장을 SERVER_OCR_EVIDENCE 로 승격하지 않는다', () => {
  // 승격은 서버가 실제로 판정했을 때만 assurance 가 바뀐다.
  const r = _refEvaluate(base({clientClaim: {identifier: 'MATCHED'}}));
  assert.strictEqual(r.assurance, ASSURANCE_SERVER);
  const legacy = {verdict: MATCHED, assurance: ASSURANCE_CLIENT};
  assert.notStrictEqual(legacy.assurance, ASSURANCE_SERVER);
});

check('이름에 은행 인증·SERVER_VERIFIED 를 쓰지 않는다', () => {
  assert.strictEqual(/VERIFIED/.test(ASSURANCE_SERVER), false);
  assert.strictEqual(ASSURANCE_SERVER, 'SERVER_OCR_EVIDENCE');
});

console.log('\n──────────────────────────────');
console.log('총 ' + (pass + fail) + '건 · 실패 ' + fail + '건');
process.exit(fail === 0 ? 0 : 1);
