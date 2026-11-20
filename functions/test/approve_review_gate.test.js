/**
 * [APPROVE-REVIEW-GATE] 지원 검토 승인(callableApproveApplicationForReview)도 확정과 같은 서류 문턱을 지난다.
 *
 *   DEV 10-23: 홈 "지원 검토" 의 승인 버튼은 이 함수를 부르고(PENDING → CONTRACT_PENDING, 좌석 확보),
 *   같은 일을 하는 callableConfirmApplication 의 hard gate(srvResolveMatchingReadiness)를 건너뛰었다.
 *   판정 함수 자체는 invite_preaccept_consent.test.js 가 실행으로 검증한다 — 여기서는 연결만 고정한다.
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const SRC = fs.readFileSync(path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');
function body(name) {
  const i = SRC.indexOf(`export const ${name} = onCall(`);
  assert.ok(i >= 0, `${name} 없음`);
  const j = SRC.indexOf('\nexport const ', i + 10);
  return SRC.slice(i, j < 0 ? SRC.length : j);
}

let pass = 0; let fail = 0;
function t(name, fn) { try { fn(); pass++; console.log('  ok   ' + name); } catch (e) { fail++; console.log('  FAIL ' + name + '\n       ' + e.message); } }

const approve = body('callableApproveApplicationForReview');
const confirm = body('callableConfirmApplication');

t('AG-1 승인도 같은 판정 함수를 부른다', () => {
  assert.ok(approve.includes('srvResolveMatchingReadiness('));
  assert.ok(confirm.includes('srvResolveMatchingReadiness('), '대조: 확정 경로');
});
t('AG-2 판정은 PENDING 일 때만, 트랜잭션(좌석 쓰기) 전에', () => {
  const g = approve.indexOf('srvResolveMatchingReadiness(');
  const tx = approve.indexOf('db.runTransaction(');
  assert.ok(g > 0 && tx > 0 && g < tx, '문턱이 좌석 쓰기보다 뒤에 있다');
  assert.ok(/\(appData\.status as string \| undefined\) === "PENDING"/.test(approve), 'CONTRACT_PENDING 재시도는 막지 않는다');
});
t('AG-3 준비되지 않으면 failed-precondition 으로 거절(서버 사유 그대로)', () => {
  assert.ok(/if \(!readiness\.ready\) \{\s*throw new HttpsError\("failed-precondition", readiness\.reason/.test(approve));
});
t('AG-4 통과 근거를 확정과 같은 함수로 남긴다', () => {
  assert.ok(approve.includes('srvBuildMatchingProvenance('));
  assert.ok(approve.includes('...(approveReviewProvenance ?? {})'));
});

// [GATE-IN-TX] 밖의 문턱만으로는 원자적이지 않다 — 승인·확정 모두 좌석 트랜잭션 안에서 다시 본다.
//   실행 반례·후보 대조: AlFit-release-candidates/doc-closeout-20261023/race/*_gate_toctou.test.js
const inTxHelper = SRC.slice(SRC.indexOf('async function srvReassertMatchingReadinessInTx('));
t('AG-5 재판정 helper 는 users·검토 문서를 tx 로 읽고 같은 판정·근거 함수를 쓴다', () => {
  const h = inTxHelper.slice(0, inTxHelper.indexOf('\n}\n'));
  assert.ok(h.includes('await tx.get(db.collection("users").doc(workerUid))'));
  assert.ok(h.includes('await tx.get(\n    db.collection(BIZ_DOC_REVIEW_COL).doc(srvBizReviewId(businessId, workerUid)))'));
  // [DOC-LATE-DELETE.7] 예전 단언: srvResolveMatchingReadiness(workerSnap.data(), reviewSnap.data()).
  //   같은 판정 함수 — 입력이 '상태 필드 없는 예전 문서는 지금 객체 확인을 덧씌운' 사본이 됐다.
  assert.ok(h.includes('srvResolveMatchingReadiness(\n    srvWithLegacyIdCardObject(workerSnap.data(), legacy), reviewSnap.data())'));
  assert.ok(h.includes('await srvProbeLegacyIdCardObject(workerSnap.data(), workerUid)'));
  assert.ok(h.includes('return srvBuildMatchingProvenance('));
});
t('AG-6 승인·확정 트랜잭션이 멱등 분기 뒤·쓰기 전에 재판정한다', () => {
  for (const [name, fn, uid, biz] of [['승인', approve, 'approveApplicantUid', 'targetBusinessId'], ['확정', confirm, 'applicantUid', 'businessId']]) {
    const call = fn.indexOf(`await srvReassertMatchingReadinessInTx(tx, ${biz}, ${uid})`);
    const tx = fn.indexOf('db.runTransaction(');
    const firstWrite = fn.indexOf('tx.update(', call);
    assert.ok(call > tx, `${name}: 재판정이 트랜잭션 안에 없다`);
    assert.ok(firstWrite > call, `${name}: 재판정이 첫 쓰기보다 뒤다`);
    assert.ok(fn.slice(tx, call).includes('"CONTRACT_PENDING"'), `${name}: 멱등(CONTRACT_PENDING) 분기보다 앞이다`);
  }
});

console.log(`\n통과 ${pass} / 실패 ${fail}`);
process.exit(fail ? 1 : 0);
