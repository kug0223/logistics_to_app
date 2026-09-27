/**
 * R7 6차 §4 — C7: `callableGetAvailableWorkers` 의 workDetailId 매칭과 폴백.
 *
 *   서버는 `workDetailId` 를 composite(`workType_start_end`) 또는 workType 으로
 *   맞추고, **못 맞추면 첫 번째 workDetail 로 떨어진다.** 그 폴백이 실제로
 *   다른 업무의 후보 목록을 돌려주는지 본다.
 *
 *   후보 pool 이 비면 비교가 공허하므로, 업무별로 **후보가 달라지게** 만든다:
 *     · wd1 09:00–12:00 / wd2 18:00–22:00
 *     · BUSY  — 같은 날 18:00–22:00 에 다른 곳에서 확정 → wd2 와만 겹친다
 *     · FREE  — 겹치는 일정 없음
 *   그러면 wd1 의 후보와 wd2 의 후보가 다르고, 잘못된 입력의 결과가 어느
 *   쪽과 같은지로 폴백을 관측할 수 있다.
 *
 * 격리 에뮬레이터(demo-alfit-r7) 전용. id 는 실행마다 유일하다.
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

const results = [];
let failures = 0;
function check(label, actual, expected, note) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  results.push({label, ok, actual, expected, ...(note ? {note} : {})});
}
const observe = (label, actual, note) =>
  results.push({label, ok: true, actual, expected: '관측', ...(note ? {note} : {})});

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const kstDayStart = (ms) => {
  const off = 9 * 3600 * 1000;
  const d = new Date(ms + off); d.setUTCHours(0, 0, 0, 0);
  return d.getTime() - off;
};
const ymd = (ms) => {
  const d = new Date(ms + 9 * 3600 * 1000);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-` +
    `${String(d.getUTCDate()).padStart(2, '0')}`;
};

async function idToken(uid) {
  const custom = await admin.auth().createCustomToken(uid);
  const r = await fetch(
    'http://127.0.0.1:6072/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake',
    {method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({token: custom, returnSecureToken: true})});
  return (await r.json()).idToken;
}
async function call(name, data, token, timeoutMs = 60000) {
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), timeoutMs);
  try {
    const r = await fetch(`${FN}/${name}`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json',
        ...(token ? {Authorization: `Bearer ${token}`} : {}),
        'X-Firebase-AppCheck': 'r7-audit-emulator-token'},
      body: JSON.stringify({data}),
      signal: ac.signal,
    });
    const t = await r.text();
    let body; try { body = JSON.parse(t); } catch { body = t; }
    return {status: r.status, body};
  } catch (e) {
    return {status: -1, body: {error: String(e && e.name === 'AbortError'
      ? `TIMEOUT ${timeoutMs}ms` : e)}};
  } finally { clearTimeout(timer); }
}

const RUN = `r7c7${Date.now().toString(36)}`;
const BIZ = `${RUN}biz`, TO = `${RUN}to`, SLOT = `${RUN}slot`;
const OTHER_TO = `${RUN}oto`, OTHER_SLOT = `${RUN}oslot`;
const WD1 = `${RUN}wd1`, WD2 = `${RUN}wd2`, WDX = `${RUN}wdx`;
const OWNER = `${RUN}own`, BUSY = `${RUN}busy`, FREE = `${RUN}free`;
const REGION_KEY = '서울특별시|강남구';

const wd = (id, wt, st, et) => ({wdId: id, workType: wt, startTime: st, endTime: et,
  wage: 12000, wageType: 'hourly', requiredCount: 3});

async function seedWorker(uid, name, workDate) {
  await db.doc(`users/${uid}`).set({uid, name, role: 'USER', accountStatus: 'active',
    passVerifiedAt: admin.firestore.Timestamp.now(), isIdVerified: true,
    idCardImagePath: `id_cards/${uid}/id.jpg`,
    bankName: '국민', accountNumber: 'enc', accountHolder: name,
    bankbookImagePath: `bankbooks/${uid}/b.jpg`,
    termsConsentAt: admin.firestore.Timestamp.now(),
    isBlacklisted: false, isForeign: false,
    idDocumentVersion: 1, bankbookDocumentVersion: 1, bankAccountVersion: 1});
  // 후보 조회는 `inviteKeys`(= `지역키#날짜`) array-contains 로 pool 을 만든다.
  //   초대 발송 CF 가 보는 `inviteEnabled`/`inviteRegionKeys`/`dates` 와는
  //   **다른 인덱스**다. 실제 앱은 `callableSyncInviteKeys` 가 둘을 맞춘다.
  await db.doc(`worker_availability/${uid}`).set({
    uid, inviteEnabled: true, inviteRegionKeys: [REGION_KEY], dates: [ymd(workDate)],
    inviteKeys: [`${REGION_KEY}#${ymd(workDate)}`]});
}

async function seed() {
  const workDate = kstDayStart(Date.now()) + 3 * 86400000;
  for (const uid of [OWNER, BUSY, FREE]) {
    try { await admin.auth().createUser({uid}); } catch (e) {
      if (e.code !== 'auth/uid-already-exists') throw e;
    }
  }
  await db.doc(`businesses/${BIZ}`).set({name: 'C7', ownerId: OWNER,
    status: 'approved', isActive: true, adminIds: [OWNER],
    city: '강남구', address: '서울특별시 강남구 테헤란로 1'});
  await db.doc(`users/${OWNER}`).set({uid: OWNER, name: 'C7 관리자',
    role: 'BUSINESS_ADMIN', businessId: BIZ, accountStatus: 'active'});
  await seedWorker(BUSY, 'C7 바쁜사람', workDate);
  await seedWorker(FREE, 'C7 한가한사람', workDate);

  const wds = [wd(WD1, '홀서빙', '09:00', '12:00'), wd(WD2, '주방', '18:00', '22:00')];
  const base = kstDayStart(Date.now()) - 86400000;
  await db.doc(`tos/${TO}`).set({id: TO, businessId: BIZ, title: 'C7 공고',
    status: 'published', isPublic: true, isPublished: true, isDeleted: false,
    type: 'flex', createdBy: OWNER, workDetails: wds,
    totalRequired: 6, totalConfirmed: 0, totalPending: 0,
    publishedAt: admin.firestore.Timestamp.fromMillis(base),
    createdAt: admin.firestore.Timestamp.fromMillis(base)});
  const counts = {};
  for (const d of wds) counts[d.wdId] = {confirmedCount: 0, pendingCount: 0};
  await db.doc(`tos/${TO}/slots/${SLOT}`).set({id: SLOT, toId: TO, businessId: BIZ,
    status: 'open', isManualClosed: false,
    date: admin.firestore.Timestamp.fromMillis(workDate),
    workDetails: wds, workDetailCounts: counts,
    requiredCount: 6, confirmedCount: 0, pendingCount: 0});

  // BUSY 는 같은 날 18:00~22:00 에 **다른 사업장**에서 확정 — wd2 와만 겹친다.
  await db.doc(`applications/${RUN}busyapp`).set({
    uid: BUSY, toId: OTHER_TO, slotId: OTHER_SLOT, businessId: `${RUN}otherbiz`,
    status: 'CONFIRMED', selectedWorkType: '홀서빙',
    startTime: '09:00', endTime: '12:00',
    workDate: admin.firestore.Timestamp.fromMillis(workDate),
    createdAt: admin.firestore.Timestamp.now()});
  return {workDate};
}

async function cleanup() {
  await db.doc(`applications/${RUN}busyapp`).delete().catch(() => {});
  const apps = await db.collection('applications').where('toId', '==', TO).get();
  for (const d of apps.docs) await d.ref.delete();
  await db.doc(`tos/${TO}/slots/${SLOT}`).delete().catch(() => {});
  await db.doc(`tos/${TO}`).delete().catch(() => {});
  // 사업장을 먼저 지우고 cascade 가 끝난 뒤 사용자를 지운다(onBusinessDeleted).
  await db.doc(`businesses/${BIZ}`).delete().catch(() => {});
  await sleep(1800);
  for (const p of [`users/${OWNER}`, `users/${BUSY}`, `users/${FREE}`,
    `worker_availability/${BUSY}`, `worker_availability/${FREE}`]) {
    await db.doc(p).delete().catch(() => {});
  }
}

(async () => {
  await seed();
  const otok = await idToken(OWNER);
  const ask = (wdIdArg) => call('callableGetAvailableWorkers',
    {toId: TO, slotId: SLOT, workDetailId: wdIdArg}, otok);
  const uidsOf = (r) => (r.body?.result?.candidates ?? [])
    .map((c) => c.uid ?? c.id).sort();

  // 진단 — CF 의 충돌 검사가 볼 문서가 실제로 있는지 먼저 확인한다.
  const conflDocs = await db.collection('applications')
    .where('status', 'in', ['CONFIRMED', 'CONTRACT_PENDING']).get();
  observe('C7-pre 충돌 검사 대상 문서',
    JSON.stringify(conflDocs.docs.map((d) => ({
      uid: String(d.data().uid).slice(-12), st: d.data().startTime,
      et: d.data().endTime,
      wd: d.data().workDate && d.data().workDate.toDate().toISOString()}))));

  const forWd1 = await ask('홀서빙_09:00_12:00');
  const forWd2 = await ask('주방_18:00_22:00');
  observe('C7-0 wd1 응답', `${forWd1.status} ${JSON.stringify(uidsOf(forWd1))}`);
  observe('C7-0 wd2 응답', `${forWd2.status} ${JSON.stringify(uidsOf(forWd2))}`);

  if (forWd1.status !== 200 || forWd2.status !== 200) {
    observe('C7 판정 보류 — 호출이 200 이 아니다',
      `${forWd1.status}/${forWd2.status}`,
      `${JSON.stringify(forWd1.body).slice(0, 200)}`);
  } else {
    const a = uidsOf(forWd1), b = uidsOf(forWd2);
    const poolNonEmpty = a.length > 0 || b.length > 0;
    check('C7-1 후보 pool 이 비어 있지 않다', poolNonEmpty, true,
      `wd1=${JSON.stringify(a)} wd2=${JSON.stringify(b)}`);
    check('C7-2 업무별 후보가 다르다 — 비교가 성립한다',
      JSON.stringify(a) !== JSON.stringify(b), true,
      `wd1=${JSON.stringify(a)} wd2=${JSON.stringify(b)}`);
    observe('C7-2 BUSY 포함 여부',
      `wd1=${a.includes(BUSY)} wd2=${b.includes(BUSY)}`,
      '겹치는 시간의 업무에서 제외되어야 한다');

    if (poolNonEmpty && JSON.stringify(a) !== JSON.stringify(b)) {
      // (a) 잘못된 식별자
      const invalid = await ask('없는-업무-식별자');
      const inv = uidsOf(invalid);
      observe('C7-3 잘못된 식별자 응답', `${invalid.status} ${JSON.stringify(inv)}`);
      const sameAsFirst = JSON.stringify(inv) === JSON.stringify(a);
      const sameAsAsked = JSON.stringify(inv) === JSON.stringify(b);
      observe('C7-3 첫 업무와 같은가', String(sameAsFirst));
      check('C7-3 잘못된 식별자를 조용히 다른 업무로 바꾸지 않는다',
        !(sameAsFirst && !sameAsAsked), true,
        `wd1=${JSON.stringify(a)} wd2=${JSON.stringify(b)} invalid=${JSON.stringify(inv)}`);

      // (b) legacy — workType 단독
      const legacy = await ask('주방');
      const leg = uidsOf(legacy);
      check('C7-4 workType 단독(legacy)은 그 업무로 맞는다',
        JSON.stringify(leg), JSON.stringify(b),
        `legacy=${JSON.stringify(leg)} wd2=${JSON.stringify(b)}`);

      // (c) 미전달
      const none = await ask(undefined);
      observe('C7-5 workDetailId 미전달 응답',
        `${none.status} ${JSON.stringify(uidsOf(none))}`,
        '업무가 2개이므로 시간 충돌 검사를 할 수 없는 경로');

      // (d) business isolation — 다른 사업장 공고로 물어보면 거부되어야 한다
      const foreign = await call('callableGetAvailableWorkers',
        {toId: OTHER_TO, slotId: OTHER_SLOT, workDetailId: '주방_18:00_22:00'}, otok);
      check('C7-6 다른 사업장 공고 후보 조회 거부', foreign.status >= 400, true,
        `status=${foreign.status} ${JSON.stringify(foreign.body).slice(0, 160)}`);
    }
  }

  // 충돌 창이 하루 밀렸는지 본다.
  //   CF 는 KST 성분으로 `new Date(연,월,일)` 을 만든다 — 런타임 TZ 해석이다.
  //   런타임이 UTC 면 창이 +9h 밀려 **다음 날** 확정을 보게 된다.
  //   그래서 하루 뒤 확정을 넣고 오늘 날짜로 물어본다. 그때 제외되면
  //   창이 밀렸다는 뜻이다.
  const nextDay = kstDayStart(Date.now()) + 4 * 86400000;
  await db.doc(`applications/${RUN}nextday`).set({
    uid: FREE, toId: OTHER_TO, slotId: OTHER_SLOT, businessId: `${RUN}otherbiz`,
    status: 'CONFIRMED', selectedWorkType: '홀서빙',
    startTime: '09:00', endTime: '12:00',
    workDate: admin.firestore.Timestamp.fromMillis(nextDay),
    createdAt: admin.firestore.Timestamp.now()});
  const shifted = await call('callableGetAvailableWorkers',
    {toId: TO, slotId: SLOT, workDetailId: '홀서빙_09:00_12:00'}, otok);
  const shiftedUids = (shifted.body?.result?.candidates ?? []).map((c) => c.uid);
  observe('C7-9 하루 뒤 확정자가 오늘 후보에서 제외되는가',
    `${shifted.status} free포함=${shiftedUids.includes(FREE)} ` +
    `busy포함=${shiftedUids.includes(BUSY)}`,
    'free 가 제외되면 충돌 창이 +1일 밀렸다는 증거다');
  await db.doc(`applications/${RUN}nextday`).delete().catch(() => {});

  // 업무가 **하나뿐인** 슬롯에서도 충돌이 걸러지지 않는지 본다.
  //   걸러지면 문제는 "업무가 여럿일 때의 매칭"이고,
  //   여전히 안 걸러지면 문제는 "충돌 배제 자체"다.
  const SOLO = `${RUN}solo`;
  await db.doc(`tos/${TO}/slots/${SOLO}`).set({
    id: SOLO, toId: TO, businessId: BIZ, status: 'open', isManualClosed: false,
    date: admin.firestore.Timestamp.fromMillis(
      kstDayStart(Date.now()) + 3 * 86400000),
    workDetails: [wd(WD1, '홀서빙', '09:00', '12:00')],
    workDetailCounts: {[WD1]: {confirmedCount: 0, pendingCount: 0}},
    requiredCount: 3, confirmedCount: 0, pendingCount: 0});
  const solo = await call('callableGetAvailableWorkers',
    {toId: TO, slotId: SOLO, workDetailId: '홀서빙_09:00_12:00'}, otok);
  observe('C7-8a 업무 1개 슬롯 — 겹치는 근로자 포함 여부',
    `${solo.status} busy=${((solo.body?.result?.candidates ?? [])
      .map((c) => c.uid)).includes(BUSY)}`,
    JSON.stringify((solo.body?.result?.candidates ?? []).map((c) => c.uid)));
  await db.doc(`tos/${TO}/slots/${SOLO}`).delete().catch(() => {});

  // 후보 목록이 충돌을 걸러내지 않았다면, 초대 자체는 막히는지 본다.
  //   막힌다면 영향은 "목록이 과하게 포함된다"에 한정된다.
  const inviteBusy = await call('callableInviteWorker', {
    toId: TO, businessId: BIZ, targetUid: BUSY, slotId: SLOT,
    workDate: ymd(kstDayStart(Date.now()) + 3 * 86400000),
    selectedWorkType: '홀서빙',
    workDetailStartTime: '09:00', workDetailEndTime: '12:00',
  }, otok);
  observe('C7-8 겹치는 근로자 초대 시도',
    `${inviteBusy.status}`, JSON.stringify(inviteBusy.body).slice(0, 220));

  // (e) 같은 workType 이 둘 — ambiguous 입력
  await db.doc(`tos/${TO}/slots/${SLOT}`).update({
    workDetails: [wd(WD1, '홀서빙', '09:00', '12:00'),
      wd(WDX, '홀서빙', '13:00', '17:00')],
    [`workDetailCounts.${WDX}`]: {confirmedCount: 0, pendingCount: 0},
  });
  const ambiguous = await call('callableGetAvailableWorkers',
    {toId: TO, slotId: SLOT, workDetailId: '홀서빙'}, otok);
  check('C7-7 같은 workType 두 개 + workType 단독 입력 → 거부',
    ambiguous.status >= 400, true,
    String(ambiguous.status) + ' ' + JSON.stringify(ambiguous.body).slice(0,160));
  observe('C7-7 관측',
    `${ambiguous.status} ${JSON.stringify((ambiguous.body?.result?.candidates ?? [])
      .map((c) => c.uid ?? c.id))}`,
    '어느 시간대로 판정됐는지는 응답만으로 알 수 없다 — 후보 구성으로 추론');

  console.log(JSON.stringify({run: RUN, failures, results}, null, 2));
  await cleanup();
  process.exit(failures > 0 ? 1 : 0);
})().catch((e) => { console.error('HARNESS ERROR:', e); process.exit(2); });
