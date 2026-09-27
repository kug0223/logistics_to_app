/**
 * R7 §4 — Firestore rules 경로 검증.
 *
 *   harness 의 다른 스크립트는 Admin SDK 를 쓰므로 rules 를 **우회한다**.
 *   여기서는 ID 토큰을 들고 Firestore 에뮬레이터 REST 를 직접 호출한다 —
 *   그 요청은 실제 `firestore.rules` 를 지나간다.
 *
 *   묻는 것:
 *     · 지원자가 자기 지원서의 **원장 상태**를 취소로 바꿀 수 있는가
 *     · 남의 지원서 / 금지된 상태 전이 / 파생 카운터 조작은 막히는가
 *     · **원장 상태 쓰기 권한**과 **파생 카운터 쓰기 권한**이 구분되는가
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

const REST = `http://127.0.0.1:6070/v1/projects/${PROJECT}/databases/(default)/documents`;

const RUN = `r7rul${Date.now().toString(36)}`;
const BIZ = `${RUN}biz`;
const TO = `${RUN}to`;
const SLOT = `${RUN}slot`;
const WD = `${RUN}wd`;
const OWNER = `${RUN}owner`;
const WA = `${RUN}wa`;
const WB = `${RUN}wb`;

const results = [];
let failures = 0;
function check(label, actual, expected, note) {
  const ok = actual === expected;
  if (!ok) failures++;
  results.push({label, ok, actual, expected, ...(note ? {note} : {})});
}

async function idToken(uid) {
  const custom = await admin.auth().createCustomToken(uid);
  const r = await fetch(
    'http://127.0.0.1:6072/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake',
    {method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({token: custom, returnSecureToken: true})});
  const j = await r.json();
  if (!j.idToken) throw new Error('idToken: ' + JSON.stringify(j).slice(0, 200));
  return j.idToken;
}

/** rules 를 지나는 부분 업데이트. 허용되면 200, 막히면 403. */
async function patch(token, docPath, fields) {
  const mask = Object.keys(fields)
    .map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`).join('&');
  const body = {fields: {}};
  for (const [k, v] of Object.entries(fields)) body.fields[k] = v;
  const r = await fetch(`${REST}/${docPath}?${mask}`, {
    method: 'PATCH',
    headers: {'Content-Type': 'application/json', Authorization: `Bearer ${token}`},
    body: JSON.stringify(body),
  });
  const t = await r.text();
  return {status: r.status, body: t.slice(0, 220)};
}

const str = (v) => ({stringValue: v});
const int = (v) => ({integerValue: String(v)});
/** 중첩 맵 한 칸만 바꾸는 요청 — `workDetailCounts.<wd>.pendingCount` */
const mapOf = (obj) => ({mapValue: {fields: obj}});

const appIdOf = (w) => `${TO}_${SLOT}_${WD}_${w}`;

async function seed() {
  for (const uid of [WA, WB, OWNER]) {
    try { await admin.auth().createUser({uid}); } catch (e) {
      if (e.code !== 'auth/uid-already-exists') throw e;
    }
  }
  await db.doc(`businesses/${BIZ}`).set(
    {name: 'R7 rules 사업장', ownerId: OWNER, status: 'approved', isActive: true,
      adminIds: [OWNER]});
  for (const [uid, role] of [[WA, 'USER'], [WB, 'USER'], [OWNER, 'BUSINESS_ADMIN']]) {
    await db.doc(`users/${uid}`).set({
      uid, name: `R7 ${uid}`, role, accountStatus: 'active',
      ...(role === 'BUSINESS_ADMIN' ? {businessId: BIZ} : {}),
      passVerifiedAt: admin.firestore.Timestamp.now(), isIdVerified: true,
    });
  }
  const wd = {wdId: WD, workType: '홀서빙', startTime: '09:00', endTime: '18:00',
    wage: 12000, wageType: 'hourly', requiredCount: 2};
  await db.doc(`tos/${TO}`).set({
    id: TO, businessId: BIZ, title: 'R7 rules 공고', status: 'published',
    isPublic: true, isPublished: true, isDeleted: false, type: 'flex',
    createdBy: OWNER, workDetails: [wd],
    totalRequired: 2, totalConfirmed: 0, totalPending: 2,
    createdAt: admin.firestore.Timestamp.now()});
  await db.doc(`tos/${TO}/slots/${SLOT}`).set({
    id: SLOT, toId: TO, businessId: BIZ, status: 'open', isManualClosed: false,
    date: admin.firestore.Timestamp.now(), workDetails: [wd],
    workDetailCounts: {[WD]: {confirmedCount: 0, pendingCount: 2}},
    requiredCount: 2, confirmedCount: 0, pendingCount: 2});
  for (const w of [WA, WB]) {
    await db.doc(`applications/${appIdOf(w)}`).set({
      uid: w, toId: TO, slotId: SLOT, businessId: BIZ, wdId: WD,
      status: 'PENDING', selectedWorkType: '홀서빙',
      startTime: '09:00', endTime: '18:00',
      workDate: admin.firestore.Timestamp.now(),
      createdAt: admin.firestore.Timestamp.now(),
    });
  }
}

async function cleanup() {
  for (const w of [WA, WB]) await db.doc(`applications/${appIdOf(w)}`).delete().catch(() => {});
  for (const p of [`tos/${TO}/slots/${SLOT}`, `tos/${TO}`, `businesses/${BIZ}`,
    `users/${WA}`, `users/${WB}`, `users/${OWNER}`]) {
    await db.doc(p).delete().catch(() => {});
  }
}

(async () => {
  await seed();
  const ta = await idToken(WA);
  const tb = await idToken(WB);

  // ── R1 원장 상태: 본인 지원서를 취소할 수 있다 ───────────────────────────
  const r1 = await patch(ta, `applications/${appIdOf(WA)}`, {status: str('CANCELED')});
  check('R1 본인 PENDING → CANCELED 허용', r1.status === 200, true,
    `status=${r1.status} ${r1.body}`);

  // ── R2 남의 지원서는 건드릴 수 없다 ─────────────────────────────────────
  const r2 = await patch(tb, `applications/${appIdOf(WA)}`, {status: str('CANCELED')});
  check('R2 타인 지원서 상태 변경 거부', r2.status === 403, true,
    `status=${r2.status} ${r2.body}`);

  // ── R3 본인이라도 확정으로 올릴 수 없다 ─────────────────────────────────
  const r3 = await patch(tb, `applications/${appIdOf(WB)}`, {status: str('CONFIRMED')});
  check('R3 본인 스스로 CONFIRMED 승격 거부', r3.status === 403, true,
    `status=${r3.status} ${r3.body}`);
  const r3b = await patch(tb, `applications/${appIdOf(WB)}`,
    {status: str('CONTRACT_PENDING')});
  check('R3b CONTRACT_PENDING 승격도 거부', r3b.status === 403, true,
    `status=${r3b.status} ${r3b.body}`);

  // ── R4 파생 카운터: 업무 단위는 클라이언트가 쓸 수 없다 ──────────────────
  const r4 = await patch(tb, `tos/${TO}/slots/${SLOT}`, {
    workDetailCounts: mapOf({[WD]: mapOf({pendingCount: int(0), confirmedCount: int(0)})}),
  });
  check('R4 workDetailCounts 직접 쓰기 거부', r4.status === 403, true,
    `status=${r4.status} ${r4.body}`);

  // ── R5 슬롯 합계 ±1 / 임의값 ────────────────────────────────────────────
  //
  //   현재값을 **읽고** ±1 을 만든다. R1 의 취소가 `syncTOStats` 를 깨워
  //   값을 이미 재계산했으므로, 고정 숫자를 넣으면 "변화 없음"이 되어
  //   규칙에 걸린다 — 그것을 거부로 읽으면 잘못된 증거가 된다.
  const curSlot = (await db.doc(`tos/${TO}/slots/${SLOT}`).get()).data() ?? {};
  const slotP = curSlot.pendingCount ?? 0;
  const r5 = await patch(tb, `tos/${TO}/slots/${SLOT}`,
    {pendingCount: int(slotP - 1)});
  check('R5 슬롯 pendingCount −1 허용', r5.status === 200, true,
    `현재=${slotP} → ${slotP - 1}, status=${r5.status} ${r5.body}`);
  const cur2 = (await db.doc(`tos/${TO}/slots/${SLOT}`).get()).data() ?? {};
  const r5b = await patch(tb, `tos/${TO}/slots/${SLOT}`,
    {pendingCount: int((cur2.pendingCount ?? 0) + 50)});
  check('R5b 슬롯 pendingCount 임의값 거부', r5b.status === 403, true,
    `현재=${cur2.pendingCount} → +50, status=${r5b.status} ${r5b.body}`);

  // ── R6 좌석 카운터는 클라이언트가 못 쓴다 ───────────────────────────────
  const r6 = await patch(tb, `tos/${TO}/slots/${SLOT}`, {confirmedCount: int(1)});
  check('R6 슬롯 confirmedCount 직접 쓰기 거부', r6.status === 403, true,
    `status=${r6.status} ${r6.body}`);
  const r6b = await patch(tb, `tos/${TO}`, {totalConfirmed: int(1)});
  check('R6b TO totalConfirmed 직접 쓰기 거부', r6b.status === 403, true,
    `status=${r6b.status} ${r6b.body}`);

  // ── R7 TO totalPending — ±1 만 허용되는지 현재값 기준으로 본다 ───────────
  const curTo = (await db.doc(`tos/${TO}`).get()).data() ?? {};
  const toP = curTo.totalPending ?? 0;
  const r7 = await patch(tb, `tos/${TO}`, {totalPending: int(toP - 1)});
  check('R7 TO totalPending −1 허용', r7.status === 200, true,
    `현재=${toP} → ${toP - 1}, status=${r7.status} ${r7.body}`);
  const curTo2 = (await db.doc(`tos/${TO}`).get()).data() ?? {};
  const r7b = await patch(tb, `tos/${TO}`,
    {totalPending: int((curTo2.totalPending ?? 0) + 50)});
  check('R7b TO totalPending 임의값 거부', r7b.status === 403, true,
    `현재=${curTo2.totalPending} → +50, status=${r7b.status} ${r7b.body}`);

  // ── R8 남의 사업장 문서 ─────────────────────────────────────────────────
  const r8 = await patch(tb, `businesses/${BIZ}`, {name: str('탈취')});
  check('R8 사업장 문서 변경 거부', r8.status === 403, true,
    `status=${r8.status} ${r8.body}`);

  console.log(JSON.stringify({run: RUN, failures, results}, null, 2));
  await cleanup();
  process.exit(failures > 0 ? 1 : 0);
})().catch((e) => { console.error('HARNESS ERROR:', e); process.exit(2); });
