/**
 * R7 §5·§8 — 좁은 확인 두 가지.
 *
 *   F1. `callableGetAvailableWorkers` 의 workDetailId 매칭 실패 폴백.
 *       서버는 composite(`workType_start_end`) 또는 workType 으로 맞추고,
 *       못 맞추면 **첫 번째 workDetail** 로 떨어진다. 그 폴백이 실제로
 *       다른 업무의 결과를 돌려주는지 본다. 정상 입력과 잘못된 입력을
 *       나란히 놓고 차이를 관측한다.
 *
 *   F2. `onBusinessDeleted` 의 `NOT_FOUND` 후보.
 *       정상 삭제 순서에서도 터지는지, 사용자 문서가 먼저 없어진
 *       경우에만 터지는지 좁게 가른다.
 *
 * 격리 에뮬레이터(demo-alfit-r7) 전용.
 */
const PROJECT = 'demo-alfit-r7';
process.env.GCLOUD_PROJECT = PROJECT;
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:6070';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:6072';

const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));
admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();
const FN = `http://127.0.0.1:5011/${PROJECT}/asia-northeast3`;

const RUN = `r7f${Date.now().toString(36)}`;
const results = [];
let failures = 0;
function check(label, actual, expected, note) {
  const ok = actual === expected;
  if (!ok) failures++;
  results.push({label, ok, actual, expected, ...(note ? {note} : {})});
}
const observe = (label, actual, note) =>
  results.push({label, ok: true, actual, expected: '관측만', ...(note ? {note} : {})});

async function idToken(uid) {
  const custom = await admin.auth().createCustomToken(uid);
  const r = await fetch(
    'http://127.0.0.1:6072/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake',
    {method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({token: custom, returnSecureToken: true})});
  return (await r.json()).idToken;
}
async function call(name, data, token) {
  const r = await fetch(`${FN}/${name}`, {
    method: 'POST',
    headers: {'Content-Type': 'application/json',
      ...(token ? {Authorization: `Bearer ${token}`} : {}),
      'X-Firebase-AppCheck': 'r7-audit-emulator-token'},
    body: JSON.stringify({data}),
  });
  const t = await r.text();
  let body; try { body = JSON.parse(t); } catch { body = t; }
  return {status: r.status, body};
}
const kstDayStart = (ms) => {
  const off = 9 * 3600 * 1000;
  const d = new Date(ms + off); d.setUTCHours(0, 0, 0, 0);
  return d.getTime() - off;
};

// ── F1 ────────────────────────────────────────────────────────────────────
async function f1() {
  const BIZ = `${RUN}f1biz`, TO = `${RUN}f1to`, SLOT = `${RUN}f1slot`;
  const OWNER = `${RUN}f1owner`, BUSY = `${RUN}f1busy`;
  const WD1 = `${RUN}wd1`, WD2 = `${RUN}wd2`;
  const workDate = kstDayStart(Date.now()) + 3 * 86400000;

  for (const uid of [OWNER, BUSY]) {
    try { await admin.auth().createUser({uid}); } catch (e) {
      if (e.code !== 'auth/uid-already-exists') throw e;
    }
  }
  await db.doc(`businesses/${BIZ}`).set({name: 'F1', ownerId: OWNER, city: '강남구', address: '서울특별시 강남구 테헤란로 1',
    status: 'approved', isActive: true, adminIds: [OWNER]});
  await db.doc(`users/${OWNER}`).set({uid: OWNER, name: 'F1 관리자',
    role: 'BUSINESS_ADMIN', businessId: BIZ, accountStatus: 'active'});
  await db.doc(`users/${BUSY}`).set({uid: BUSY, name: 'F1 바쁜사람', role: 'USER',
    accountStatus: 'active', isIdVerified: true,
    inviteRegions: ['서울특별시 강남구'], isAvailableForInvite: true});

  // 두 업무 — 시간이 겹치지 않는다.
  const wd1 = {wdId: WD1, workType: '홀서빙', startTime: '09:00', endTime: '12:00',
    wage: 12000, wageType: 'hourly', requiredCount: 2};
  const wd2 = {wdId: WD2, workType: '주방', startTime: '18:00', endTime: '22:00',
    wage: 13000, wageType: 'hourly', requiredCount: 2};

  await db.doc(`tos/${TO}`).set({id: TO, businessId: BIZ, title: 'F1 공고',
    status: 'published', isPublic: true, isPublished: true, isDeleted: false,
    type: 'flex', createdBy: OWNER, workDetails: [wd1, wd2],
    totalRequired: 4, totalConfirmed: 0, totalPending: 0,
    createdAt: admin.firestore.Timestamp.now()});
  await db.doc(`tos/${TO}/slots/${SLOT}`).set({id: SLOT, toId: TO, businessId: BIZ,
    status: 'open', isManualClosed: false,
    date: admin.firestore.Timestamp.fromMillis(workDate),
    workDetails: [wd1, wd2],
    workDetailCounts: {[WD1]: {confirmedCount: 0, pendingCount: 0},
      [WD2]: {confirmedCount: 0, pendingCount: 0}},
    requiredCount: 4, confirmedCount: 0, pendingCount: 0});

  // BUSY 는 그 날 **18:00~22:00** 에 다른 곳에서 이미 확정 — wd2 와 겹친다.
  await db.doc(`applications/${RUN}busyapp`).set({
    uid: BUSY, toId: `${RUN}other`, slotId: `${RUN}otherslot`,
    businessId: `${RUN}otherbiz`, status: 'CONFIRMED',
    selectedWorkType: '주방', startTime: '18:00', endTime: '22:00',
    workDate: admin.firestore.Timestamp.fromMillis(workDate),
    createdAt: admin.firestore.Timestamp.now()});

  const otok = await idToken(OWNER);
  const ask = (wdIdArg) => call('callableGetAvailableWorkers',
    {toId: TO, slotId: SLOT, workDetailId: wdIdArg}, otok);

  const validWd2 = await ask('주방_18:00_22:00');
  const invalid = await ask('존재하지않는-업무-식별자');
  const validWd1 = await ask('홀서빙_09:00_12:00');

  const names = (r) => (r.body?.result?.candidates ?? []).map((c) => c.uid ?? c.id);
  const hasBusy = (r) => names(r).includes(BUSY);

  observe('F1-a wd2(정상 composite) 응답', `${validWd2.status} busy포함=${hasBusy(validWd2)}`,
    JSON.stringify(validWd2.body).slice(0, 200));
  observe('F1-b wd1(정상 composite) 응답', `${validWd1.status} busy포함=${hasBusy(validWd1)}`);
  observe('F1-c 잘못된 식별자 응답', `${invalid.status} busy포함=${hasBusy(invalid)}`,
    JSON.stringify(invalid.body).slice(0, 200));

  if (validWd2.status === 200 && invalid.status === 200 && validWd1.status === 200) {
    // 폴백이 첫 업무(wd1)로 떨어지면, 잘못된 입력의 결과가 wd1 과 같아진다.
    // 세 결과가 모두 비어 있으면 비교가 **공허하다** — 같다고 해서
    // 폴백이 안전하다는 뜻이 아니다. 후보 pool 자체가 비었을 뿐이다.
    const anyCandidate = [validWd1, validWd2, invalid].some((r) => names(r).length > 0);
    if (!anyCandidate) {
      observe('F1-f 판정 보류 — 후보 pool 이 비어 비교가 성립하지 않는다',
        `wd1=${validWd1.body?.result?.totalFound} ` +
        `wd2=${validWd2.body?.result?.totalFound} ` +
        `invalid=${invalid.body?.result?.totalFound}`,
        '초대 대상 pool 진입 조건(inviteKeys/availability)을 충족시키지 못했다');
      return;
    }
    const sameAsFirst = JSON.stringify(names(invalid)) === JSON.stringify(names(validWd1));
    const sameAsAsked = JSON.stringify(names(invalid)) === JSON.stringify(names(validWd2));
    observe('F1-d 잘못된 입력이 첫 업무 결과와 같은가', String(sameAsFirst));
    observe('F1-e 잘못된 입력이 물어본 업무 결과와 같은가', String(sameAsAsked));
    check('F1-f 잘못된 식별자를 조용히 다른 업무로 바꾸지 않는다',
      !(sameAsFirst && !sameAsAsked), true,
      `wd1=${JSON.stringify(names(validWd1))} wd2=${JSON.stringify(names(validWd2))} ` +
      `invalid=${JSON.stringify(names(invalid))}`);
  } else {
    observe('F1-f 판정 보류 — 호출이 200 이 아니다',
      `wd2=${validWd2.status} wd1=${validWd1.status} invalid=${invalid.status}`);
  }

  for (const p of [`applications/${RUN}busyapp`, `tos/${TO}/slots/${SLOT}`,
    `tos/${TO}`, `businesses/${BIZ}`, `users/${OWNER}`, `users/${BUSY}`]) {
    await db.doc(p).delete().catch(() => {});
  }
}

// ── F2 ────────────────────────────────────────────────────────────────────
async function f2() {
  const logAt = () => new Date().toISOString();

  // (1) 정상 순서 — 사업장만 지운다. 사용자 문서는 남아 있다.
  const B1 = `${RUN}f2normal`, O1 = `${RUN}f2owner`;
  await db.doc(`users/${O1}`).set({uid: O1, name: 'F2 정상', role: 'BUSINESS_ADMIN',
    businessId: B1, accountStatus: 'active'});
  await db.doc(`businesses/${B1}`).set({name: 'F2 정상', ownerId: O1,
    status: 'approved', isActive: true, adminIds: [O1]});
  await new Promise((r) => setTimeout(r, 1200));
  const t1 = logAt();
  await db.doc(`businesses/${B1}`).delete();
  await new Promise((r) => setTimeout(r, 3000));
  const u1 = (await db.doc(`users/${O1}`).get()).data() ?? {};
  observe('F2-a 정상 삭제(사용자 문서 존재) — cascade 후 사용자 상태',
    `businessId=${u1.businessId ?? '(제거됨)'}`, `t=${t1}`);

  // (2) 비정상 순서 — 사용자 문서를 먼저 지우고 사업장을 지운다.
  const B2 = `${RUN}f2missing`, O2 = `${RUN}f2owner2`;
  await db.doc(`users/${O2}`).set({uid: O2, name: 'F2 결손', role: 'BUSINESS_ADMIN',
    businessId: B2, accountStatus: 'active'});
  await db.doc(`businesses/${B2}`).set({name: 'F2 결손', ownerId: O2,
    status: 'approved', isActive: true, adminIds: [O2]});
  await new Promise((r) => setTimeout(r, 1200));
  await db.doc(`users/${O2}`).delete();
  const t2 = logAt();
  await db.doc(`businesses/${B2}`).delete();
  await new Promise((r) => setTimeout(r, 3000));
  observe('F2-b 사용자 문서 없는 상태로 사업장 삭제 — 로그에서 NOT_FOUND 확인 필요',
    'emulator 로그 대조', `t=${t2}`);

  await db.doc(`users/${O1}`).delete().catch(() => {});
}

(async () => {
  await f1();
  await f2();
  console.log(JSON.stringify({run: RUN, failures, results}, null, 2));
  process.exit(failures > 0 ? 1 : 0);
})().catch((e) => { console.error('HARNESS ERROR:', e); process.exit(2); });
