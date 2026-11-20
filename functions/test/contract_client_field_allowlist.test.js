/**
 * [SERVER-INTEGRITY] 신규 계약 생성 입력의 **허용 목록**이 모델과 어긋나지 않는다.
 *
 *   허용 목록은 거부 목록보다 안전하다 — 새 서버 필드의 기본값이 "차단"이다.
 *   대신 **새 업무 필드가 조용히 사라지는** 반대 위험이 생긴다. 그 위험을
 *   여기서 막는다: Dart 모델 `EmploymentContractModel.toMap()` 의 키를 읽어
 *   서버 소유 키를 뺀 나머지가 허용 목록과 **정확히 같아야** 한다.
 *
 *   모델에 업무 필드가 늘면 이 테스트가 먼저 깨진다 — 그때 허용 목록에
 *   넣을지(업무 데이터) 서버가 정할지(서버 소유)를 사람이 결정한다.
 */
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const TS = fs.readFileSync(
    path.join(ROOT, 'functions', 'src', 'index.ts'), 'utf8');
// [함정] Dart 파일은 CRLF 다 — `\n` 표지가 그대로는 맞지 않는다.
const DART = fs.readFileSync(
    path.join(ROOT, 'lib', 'models', 'core', 'employment_contract_model.dart'),
    'utf8').replace(/\r\n/g, '\n');

/** 서버가 정하는 것 — 클라이언트 입력에서 승격되지 않는다. */
const SERVER_OWNED = new Set([
  'status',
  'employerSignatureUrl', 'employerSignatureHash', 'employerSignedAt',
  'workerSignatureUrl', 'workerSignatureHash', 'workerSignedAt',
  'pdfUrl', 'pdfStoragePath',
  'employerSignatureStoragePath', 'workerSignatureStoragePath',
  'createdAt', 'updatedAt',
]);

function serverAllowlist() {
  const m = /const CONTRACT_CLIENT_OWNED_FIELDS = \[([\s\S]*?)\] as const;/
      .exec(TS);
  assert.ok(m, 'CONTRACT_CLIENT_OWNED_FIELDS 를 찾지 못했다');
  return m[1].split(',')
      .map((s) => s.trim().replace(/^"|"$/g, ''))
      .filter((s) => s.length > 0 && !s.startsWith('//'));
}

/** `EmploymentContractModel.toMap()` 의 **최상위** 키. */
function modelToMapKeys() {
  // 모델 파일에는 toMap 이 여러 개다(ContractSlot·Snapshot·Article).
  //   최상위 계약의 것은 `'applicationId'` 로 시작하고 `'updatedAt'` 로 끝난다.
  const i = DART.indexOf("  Map<String, dynamic> toMap() => {\n    'applicationId': applicationId,\n    'businessId'");
  assert.ok(i > -1, '계약 최상위 toMap 을 찾지 못했다');
  const end = DART.indexOf('\n  };', i);
  assert.ok(end > i, 'toMap 끝을 찾지 못했다');
  const body = DART.slice(i, end);
  return [...body.matchAll(/^\s*'([A-Za-z0-9_]+)':/gm)].map((m) => m[1]);
}

test('CFA-01 허용 목록 = 모델 업무 필드 (서버 소유 제외)', () => {
  const allow = new Set(serverAllowlist());
  const business = modelToMapKeys().filter((k) => !SERVER_OWNED.has(k));

  const missing = business.filter((k) => !allow.has(k));
  assert.deepStrictEqual(missing, [],
      `모델의 업무 필드가 허용 목록에 없다 — 저장되지 않고 사라진다: ${missing}`);

  const extra = [...allow].filter((k) => !business.includes(k));
  assert.deepStrictEqual(extra, [],
      `허용 목록에만 있는 키 — 모델이 보내지 않는다: ${extra}`);
});

test('CFA-02 서버 소유 필드는 허용 목록에 하나도 없다', () => {
  const allow = serverAllowlist();
  const leaked = allow.filter((k) => SERVER_OWNED.has(k));
  assert.deepStrictEqual(leaked, [],
      `클라이언트 입력이 서버 소유 필드로 승격된다: ${leaked}`);
});

test('CFA-03 생성 경로가 허용 목록으로 입력을 구성한다 (거부 목록 아님)', () => {
  const i = TS.indexOf('const cleanData: Record<string, unknown> = {};');
  assert.ok(i > -1, 'cleanData 를 허용 목록으로 만들지 않는다');
  const near = TS.slice(i, i + 400);
  assert.ok(near.includes('for (const f of CONTRACT_CLIENT_OWNED_FIELDS)'),
      '허용 목록을 돌지 않는다');
  assert.ok(near.includes('if (contractData[f] !== undefined)'),
      '없는 키를 undefined 로 쓰면 Firestore 가 거부한다');
  // 예전 거부 목록(spread + delete)이 남아 있지 않다.
  assert.ok(!TS.includes('const cleanData: Record<string, unknown> = {...contractData};'),
      '거부 목록 방식이 남아 있다 — 새 서버 필드가 생기면 구멍이 난다');
});

test('CFA-04 서버가 쓰는 필드는 cleanData **뒤에** 온다', () => {
  // spread 순서가 뒤집히면 클라이언트 값이 서버 값을 덮는다.
  const i = TS.indexOf('const data: Record<string, unknown> = {\n            ...cleanData,');
  assert.ok(i > -1, '서버 필드가 cleanData 뒤에 오지 않는다');
  const block = TS.slice(i, TS.indexOf('tx.set(contractRef, data);', i));
  for (const f of ['status: "pending_worker"', 'employerSignatureStoragePath: storagePath',
    'employerSignatureHash: employerHash', 'createdAt: admin.firestore.FieldValue.serverTimestamp()']) {
    assert.ok(block.includes(f), `서버가 정하는 ${f} 가 없다`);
  }
});

test('CFA-05 발행 자격 술어가 한 벌이다 (서버·클라이언트)', () => {
  // 서버: 순수 helper 하나를 목록·발행이 함께 쓴다.
  assert.ok(TS.includes('function srvAppEligibleForContractIssue('),
      '자격 판정 helper 가 없다');
  assert.ok(/srvNeedsContractIssue[\s\S]{0,200}srvAppEligibleForContractIssue\(appData\)/
      .test(TS), '미발송 목록이 같은 helper 를 쓰지 않는다');
  const preauth = TS.slice(
      TS.indexOf('export const callableFinalizeEmployerSignature'),
      TS.indexOf('// ── voidContractAtomicLifecycle'));
  assert.ok(preauth.includes('srvAppEligibleForContractIssue(appData)'),
      'PREAUTH 가 자격을 보지 않는다');
  assert.ok(preauth.includes('srvAppEligibleForContractIssue(txAppSnap.data()!)'),
      '트랜잭션이 자격을 다시 보지 않는다');

  // 클라이언트: 같은 네 조건.
  const APP = fs.readFileSync(
      path.join(ROOT, 'lib', 'models', 'core', 'application_model.dart'), 'utf8');
  assert.ok(APP.includes('bool get isContractIssuable'),
      '클라이언트 술어가 없다');
});

test('CFA-06 트랜잭션은 **읽기를 모두 마친 뒤** 쓴다', () => {
  const tx = TS.slice(
      TS.indexOf('await db.runTransaction(async (tx) => {',
          TS.indexOf('export const callableFinalizeEmployerSignature')),
      TS.indexOf('tx.set(contractRef, data);'));
  const contractRead = tx.indexOf('await tx.get(contractRef)');
  const dupRead = tx.indexOf('srvIssuedContractExists(dupAppId, dupBizId, tx)');
  const appRead = tx.indexOf('await tx.get(db.collection("applications").doc(dupAppId))');
  assert.ok(contractRead > -1 && dupRead > contractRead && appRead > dupRead,
      'Firestore 트랜잭션은 모든 읽기가 쓰기보다 앞서야 한다');
});
