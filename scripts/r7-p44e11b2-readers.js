/**
 * [R7-P4.4E.11B.2 §13~§17·RT-10·RT-11·RT-12] 세 bankbook byte-reader runtime.
 *
 *   positive : 정상 통장사본 → 인가된 호출자에게 Signed URL 발급
 *   negative : 같은 사용자의 신분증/사업자등록증/프로필/타인/중첩/malformed
 *              포인터 → 거부 + ID bytes 노출 0 + 성공 감사 0
 *
 *   인가·목적·동의 gate 는 소스에서 읽어 최소 fixture 로 충족시킨다.
 *   모든 fixture 는 rt11b2_ 접두. synthetic 1px 이미지만 쓴다.
 */
'use strict';

const {
  admin, db, callAs, PREFIX, putObject, delObject, makeChecker, mask,
} = require('./r7-p44e11b2-lib');

const RUN = PREFIX + 'rd' + Date.now().toString(36);
const MGR = RUN + '_mgr';
const W = RUN + '_w';
const W2 = RUN + '_w2';
const BIZ = RUN + '_biz';
const APP_CONFIRMED = RUN + '_appC';
const APP_PENDING = RUN + '_appP';
const ATT = RUN + '_att';

const ts = 1790000100000;
const A = `users/${W}/bankbook_${ts}.jpg`;          // 정상 통장사본
const IDC = `users/${W}/idCard_${ts + 1}.jpg`;       // 같은 사용자 신분증
const LIC = `users/${W}/businessLicense_${ts + 2}.jpg`;
const PROF = `users/${W}/profile_${ts + 3}.jpg`;
const NESTED = `users/${W}/sub/bankbook_${ts + 4}.jpg`;
const OTHER = `users/${W2}/bankbook_${ts + 5}.jpg`;   // 타인 통장사본
const MALFORMED = `users/${W}/bankbook_abc.jpg`;
const BIZNS = `businesses/${BIZ}/license/x_${ts}.jpg`;

/** wire 코드만 꺼낸다 — 메시지 문구에 의존하지 않는다. */
async function expectReject(c, label, fn) {
  try {
    await fn();
    c.check(label, 'ALLOWED', 'REJECTED');
    return null;
  } catch (e) {
    c.check(label, 'REJECTED', 'REJECTED', e.wireCode || e.httpStatus);
    return e;
  }
}

async function countLogs(col, extra) {
  let q = db.collection(col).where('targetUserId', '==', W);
  const s = await q.get();
  return s.docs.filter((d) => !extra || extra(d.data())).length;
}

(async () => {
  const c = makeChecker();
  console.log('fixture run =', RUN);

  // ── fixture ─────────────────────────────────────────────────
  for (const uid of [MGR, W, W2]) {
    try { await admin.auth().createUser({uid}); } catch (e) {
      if (e.code !== 'auth/uid-already-exists') throw e;
    }
  }
  await db.doc(`businesses/${BIZ}`).set({
    name: 'RT11B2 사업장', ownerId: MGR, adminIds: [MGR],
    status: 'approved', isActive: true,
    createdAt: admin.firestore.Timestamp.now(),
  });
  await db.doc(`users/${MGR}`).set({
    uid: MGR, name: 'RT11B2 관리자', role: 'BUSINESS_ADMIN',
    businessId: BIZ, accountStatus: 'active',
    createdAt: admin.firestore.Timestamp.now(),
  });
  for (const uid of [W, W2]) {
    await db.doc(`users/${uid}`).set({
      uid, name: 'RT11B2 근로자', role: 'USER', accountStatus: 'active',
      createdAt: admin.firestore.Timestamp.now(),
      passVerifiedAt: admin.firestore.Timestamp.now(), isIdVerified: true,
      bankName: '테스트은행', accountNumber: 'enc:rt11b2',
      accountHolder: 'RT11B2 근로자',
      bankbookImagePath: uid === W ? A : OTHER,
      bankbookDocumentVersion: 1, bankAccountVersion: 1,
    });
  }
  // GetBankbookSignedUrl: CONFIRMED + 동의
  await db.doc(`applications/${APP_CONFIRMED}`).set({
    uid: W, businessId: BIZ, status: 'CONFIRMED',
    documentAccessConsentGiven: true,
    documentAccessConsentVersion: '2026-09-18-v3',
    createdAt: admin.firestore.Timestamp.now(),
  });
  // GetApplicantDocumentUrl: PENDING + 동의
  await db.doc(`applications/${APP_PENDING}`).set({
    uid: W, businessId: BIZ, status: 'PENDING',
    documentAccessConsentGiven: true,
    documentAccessConsentVersion: '2026-09-18-v3',
    createdAt: admin.firestore.Timestamp.now(),
  });
  // GetPayrollBankbookUrl: 확정 급여
  await db.doc(`attendance/${ATT}`).set({
    businessId: BIZ, userId: W, wageStatus: 'confirmed',
    status: 'present', finalWage: 90000,
    createdAt: admin.firestore.Timestamp.now(),
  });

  for (const p of [A, IDC, LIC, PROF, NESTED, OTHER, MALFORMED, BIZNS]) {
    await putObject(p);
  }

  const calls = {
    bb: () => callAs(MGR, 'callableGetBankbookSignedUrl',
        {applicationId: APP_CONFIRMED, businessId: BIZ}),
    pay: () => callAs(MGR, 'callableGetPayrollBankbookUrl',
        {businessId: BIZ, targetUid: W, attendanceId: ATT}),
    app: () => callAs(MGR, 'callableGetApplicantDocumentUrl',
        {applicationId: APP_PENDING, businessId: BIZ, targetUid: W,
          documentType: 'BANKBOOK'}),
    appId: () => callAs(MGR, 'callableGetApplicantDocumentUrl',
        {applicationId: APP_PENDING, businessId: BIZ, targetUid: W,
          documentType: 'ID'}),
  };

  const setPointer = (p) => db.doc(`users/${W}`).update({bankbookImagePath: p});

  // ── §13 / RT-12 positive ────────────────────────────────────
  console.log('\n=== RT-12 positive — 정상 통장사본 (A) ===');
  await setPointer(A);
  for (const [k, label] of [['bb', 'GetBankbookSignedUrl'],
    ['pay', 'GetPayrollBankbookUrl'], ['app', 'GetApplicantDocumentUrl(BANKBOOK)']]) {
    const r = await calls[k]();
    const url = r.signedUrl || r.url;
    c.check(`${label} → 발급 성공`, typeof url === 'string' && url.length > 0, true);
    // 발급 대상이 실제로 A 인지 (URL 에 경로가 담긴다)
    c.check(`${label} → 서명 대상이 A`,
        typeof url === 'string' && url.includes(encodeURIComponent(A).replace(/%2F/g, '%2F')) ||
        (typeof url === 'string' && url.includes(A)), true);
  }
  // ID 분기는 이번 patch 로 깨지지 않았다 (§18 basic regression)
  await db.doc(`users/${W}`).update({idCardImagePath: IDC});
  const idr = await calls.appId();
  c.check('GetApplicantDocumentUrl(ID) → 정상 유지',
      typeof (idr.signedUrl || idr.url) === 'string', true);

  // ── §14 / RT-10 negative: same-user ID ──────────────────────
  console.log('\n=== RT-10 negative — bankbookImagePath = 같은 사용자 신분증 ===');
  const bbBefore = await countLogs('bankbook_access_logs');
  const appBefore = await countLogs('applicant_document_access_logs',
      (d) => d.documentType === 'BANKBOOK');
  await setPointer(IDC);
  const e1 = await expectReject(c, 'GetBankbookSignedUrl → 거부', calls.bb);
  const e2 = await expectReject(c, 'GetPayrollBankbookUrl → 거부', calls.pay);
  const e3 = await expectReject(c, 'GetApplicantDocumentUrl(BANKBOOK) → 거부', calls.app);
  for (const [n, e] of [['bb', e1], ['pay', e2], ['app', e3]]) {
    c.check(`${n} 응답에 signedUrl 없음`,
        !!(e && /signedUrl|https:\/\/storage/.test(e.message)), false);
  }

  console.log('\n=== §16·§17 감사 무결성 — 거부에 성공 로그 0 ===');
  c.check('bankbook_access_logs 증가 0',
      (await countLogs('bankbook_access_logs')) - bbBefore, 0);
  c.check('applicant_document_access_logs(BANKBOOK) 증가 0',
      (await countLogs('applicant_document_access_logs',
          (d) => d.documentType === 'BANKBOOK')) - appBefore, 0);

  // ── §15 negative: 다른 artifact class ───────────────────────
  console.log('\n=== §15 negative — 다른 artifact / 타인 / 중첩 / malformed ===');
  const cases = [
    ['businessLicense 유사 경로', LIC],
    ['profile 유사 경로', PROF],
    ['타인 통장사본', OTHER],
    ['중첩 경로', NESTED],
    ['malformed (timestamp 아님)', MALFORMED],
    ['business 네임스페이스', BIZNS],
  ];
  for (const [label, p] of cases) {
    await setPointer(p);
    await expectReject(c, `GetPayrollBankbookUrl ← ${label}`, calls.pay);
  }
  // 대표 reader 외 나머지 둘은 핵심 1건씩만 live 확인 (§15 비용 고려)
  await setPointer(OTHER);
  await expectReject(c, 'GetBankbookSignedUrl ← 타인 통장사본', calls.bb);
  await expectReject(c, 'GetApplicantDocumentUrl(BANKBOOK) ← 타인 통장사본', calls.app);

  // ── positive 복구 확인 ──────────────────────────────────────
  console.log('\n=== 복구 — 다시 정상 A 면 발급된다 ===');
  await setPointer(A);
  const again = await calls.pay();
  c.check('GetPayrollBankbookUrl → 재발급 성공',
      typeof (again.signedUrl || again.url) === 'string', true);
  c.check('정상 접근에서는 감사 로그가 증가한다',
      (await countLogs('bankbook_access_logs')) > bbBefore, true);

  // ── teardown ────────────────────────────────────────────────
  console.log('\n=== teardown ===');
  for (const p of [A, IDC, LIC, PROF, NESTED, OTHER, MALFORMED, BIZNS]) {
    await delObject(p);
  }
  for (const d of [`applications/${APP_CONFIRMED}`, `applications/${APP_PENDING}`,
    `attendance/${ATT}`, `businesses/${BIZ}`,
    `users/${MGR}`, `users/${W}`, `users/${W2}`]) {
    await db.doc(d).delete().catch(() => {});
  }
  for (const uid of [MGR, W, W2]) await admin.auth().deleteUser(uid).catch(() => {});
  // 감사 로그는 보존 정책상 남긴다 (§54) — fixture 임을 명시 기록.
  const bbLogs = await db.collection('bankbook_access_logs')
      .where('targetUserId', '==', W).get();
  const apLogs = await db.collection('applicant_document_access_logs')
      .where('targetUserId', '==', W).get();
  c.note('의도적으로 남긴 fixture 감사 로그 (bankbook)', bbLogs.size);
  c.note('의도적으로 남긴 fixture 감사 로그 (applicant)', apLogs.size);
  console.log('  fixture uid =', mask(MGR), mask(W), mask(W2), '→ 삭제');

  const {fail} = c.summary();
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error('실패:', e.message, e.stack); process.exit(1); });
