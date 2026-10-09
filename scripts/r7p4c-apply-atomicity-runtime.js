/**
 * [R7-PAYROLL-POLICY.4C §52] DEV 런타임 — 직접 지원 고지 atomicity.
 *
 *   A. unchanged : 기준 A 를 보고 A 로 지원 → 성공 · snapshot A
 *   B. race      : A 를 보고 → 사업장이 B 로 변경 → A 로 지원
 *                  → ATTENDANCE_POLICY_CHANGED · 지원서 **없음**
 *                  (카운터·알림도 변화 0 — 직접 확인)
 *   C. refresh   : 최신 B 를 다시 읽고 B 로 지원 → 성공 · snapshot B
 *   D. 미고지    : 토큰 없이 지원 → ATTENDANCE_POLICY_NOT_DISCLOSED
 *   E. metadata  : 7개 숫자 그대로 두고 확인 기록만 새로 → A 로 지원 성공
 *                  (§46 false mismatch 없음)
 *   F. 멱등      : 성공 뒤 사업장 기준 변경 → **같은 요청 재시도**
 *                  → 기존 성공이 already-exists 로 수렴 (§48)
 *
 *   사업장 기준 값 변경만 Admin SDK 직접 쓰기다(테스트 설정). 지원·확인은
 *   모두 canonical callable 이고, 확인 기록은 이 스크립트가 쓰지 않는다.
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;
const CONSENT = '2026-09-18-v3';
const KST = 9 * 3600000;
const pad = (n) => String(n).padStart(2, '0');
const DAY = 2; // 모레 — 오늘·내일은 앞 Phase 런타임이 채워 뒀다

const G = JSON.parse(fs.readFileSync('.goldenpath.json', 'utf8'));
const businessId = G.businessId;
const adminUid = G.adminUid;
const bizRef = db.collection('businesses').doc(businessId);

const F = ['earlyWindow', 'earlyArrivalUnit', 'lateGrace', 'lateUnit',
  'lateWindow', 'overtimeUnit', 'earlyLeaveUnit'];
const DEFAULTS = {earlyWindow: 30, earlyArrivalUnit: 30, lateGrace: 5,
  lateUnit: 30, lateWindow: 30, overtimeUnit: 10, earlyLeaveUnit: 30};

/** 서버 `srvAttendancePolicyFingerprint` 와 같은 형식. */
function fingerprint(rules) {
  if (rules == null || typeof rules !== 'object') return 'absent';
  return F.map((k) =>
    `${k}=${typeof rules[k] === 'number' ? rules[k] : DEFAULTS[k]}`).join('|');
}
const brief = (o) => o == null ? '(없음)' :
  `grace ${o.lateGrace}/unit ${o.lateUnit}/early ${o.earlyLeaveUnit}/ot ${o.overtimeUnit}`;
const same7 = (a, b) => a != null && b != null && F.every((k) => a[k] === b[k]);
const reasonOf = (e) => {
  const d = e && e.details;
  if (d && d.reason) return d.reason;
  return String((e && e.code) || '') + ' ' +
    String((e && e.message) || e).slice(0, 90);
};

const A = {lateGrace: 5, lateUnit: 30, earlyLeaveUnit: 30, overtimeUnit: 30};
const B = {lateGrace: 10, lateUnit: 10, earlyLeaveUnit: 10, overtimeUnit: 10};

async function setRules(p) {
  const upd = {};
  for (const k of Object.keys(p)) upd[`attendanceRules.${k}`] = p[k];
  await bizRef.update(upd);
}
const confirmPolicy = () =>
  lib.callAs(adminUid, 'callableConfirmAttendancePolicy', {businessId});
const appDoc = (id) =>
  db.collection('applications').doc(id).get().then((d) => d.data());

async function makeTO(label, nWd) {
  const nowKst = new Date(Date.now() + KST);
  const dateStr = lib.kstDateKey(DAY);
  const workDateMs = lib.kstMidnightMs(DAY);
  const sM = nowKst.getUTCHours() * 60 + nowKst.getUTCMinutes() + 40;
  const START = `${pad(Math.floor(sM / 60))}:${pad(sM % 60)}`;
  const END = `${pad(Math.floor((sM + 1) / 60))}:${pad((sM + 1) % 60)}`;
  const biz = (await bizRef.get()).data();
  const wts = (await bizRef.collection('workTypes').limit(3).get()).docs;
  // 업무 유형이 2개뿐인 사업장에서도 (유형·시작·종료) 조합이 겹치지 않게
  //   업무마다 시작 시각을 2분씩 민다 — 서버가 조합 고유성을 요구한다.
  const mk = (i) => {
    const s2 = sM + i * 2;
    const e2 = s2 + 1;
    return {
      wdId: `p4c-${label}-${i}`,
      workType: (wts[i % wts.length].data()).name,
      workTypeIcon: 'box', workTypeColor: '#1565C0',
      workTypeBackgroundColor: '#E3F2FD',
      wage: 12000 + i * 1000, wageType: 'hourly', requiredCount: 2,
      startTime: `${pad(Math.floor(s2 / 60))}:${pad(s2 % 60)}`,
      endTime: `${pad(Math.floor(e2 / 60))}:${pad(e2 % 60)}`,
      order: i, payScheduleType: 'next_day',
    };
  };
  const wds = Array.from({length: nWd}, (_, i) => mk(i));
  const created = unwrap(await lib.callAs(adminUid, 'callableCreateTO', {
    toData: {
      businessId, businessName: biz.name, title: `[P4C-${label}] 고지 atomicity`,
      description: 'R7-PAYROLL-POLICY.4C 전용. 실제 모집 아님.',
      type: 'flex', workDetails: wds, creatorUID: adminUid,
      totalRequired: nWd * 2, totalConfirmed: 0, totalPending: 0,
      status: 'active', deadlineType: 'FIXED_TIME', hoursBeforeStart: 1,
      isPublished: false, publishMode: 'deferred',
    },
  }));
  const toId = created.toId;
  await lib.callAs(adminUid, 'callableCreateFlexSlots', {
    toId, businessId, dates: [dateStr], workDetails: wds,
    deadlineType: 'FIXED_TIME', hoursBeforeStart: 1,
    fixedDeadlineMs: Date.now() + 600000, publishMode: 'immediate',
  });
  await lib.callAs(adminUid, 'callablePublishTO', {toId});
  const slots = await db.collection('tos').doc(toId).collection('slots').get();
  const to = (await db.collection('tos').doc(toId).get()).data();
  return {
    toId, slotId: slots.docs[0].id,
    slotWds: slots.docs[0].data().workDetails || [],
    to, workDateMs, START, END,
  };
}

/** 지원 — `expected` 가 undefined 면 토큰을 아예 보내지 않는다. */
function applyAs(uid, T, i, expected) {
  const wd = T.slotWds[i];
  const payload = {
    toId: T.toId, slotId: T.slotId, businessId,
    businessName: T.to.businessName, toTitle: T.to.title,
    workDateMs: T.workDateMs, selectedWorkType: wd.workType,
    workDetailId: wd.wdId, startTime: wd.startTime, endTime: wd.endTime,
    wage: wd.wage, wageType: 'hourly',
    idCardConsentGiven: true, documentAccessConsentGiven: true,
    documentAccessConsentVersion: CONSENT,
  };
  if (expected !== undefined) payload.expectedAttendancePolicy = expected;
  return lib.callAs(uid, 'callableApplyToTO', payload);
}

const relationDocs = (uid, toId) =>
  db.collection('applications').where('uid', '==', uid)
    .where('toId', '==', toId).get();

const notifCount = async () => {
  const s = await db.collection('users').doc(adminUid)
    .collection('notifications').where('type', '==', 'newApplication').get();
  return s.size;
};

(async () => {
  const biz0 = (await bizRef.get()).data();
  const originalRules = biz0.attendanceRules;
  const originalCfm = biz0.attendancePolicyConfirmation ?? null;
  let toId = null;

  try {
    const users = await db.collection('users').where('role', '==', 'USER').get();
    const workDateMs = lib.kstMidnightMs(DAY);
    const free = [];
    for (const u of users.docs) {
      const busy = await db.collection('applications')
        .where('uid', '==', u.id)
        .where('status', 'in', ['CONFIRMED', 'CONTRACT_PENDING']).get();
      if (!busy.docs.some((d) => d.data().workDate?.toMillis() === workDateMs)) {
        free.push(u.id);
      }
    }
    if (free.length < 3) throw new Error('모레 비어 있는 근로자가 3명 필요하다');
    const [u1, u2, u3] = free;

    await setRules(A);
    await confirmPolicy();
    const bizA = (await bizRef.get()).data();
    const fpA = fingerprint(bizA.attendanceRules);
    console.log('기준 A:', brief(bizA.attendanceRules));
    console.log('토큰 A:', fpA);

    const T = await makeTO('race', 3);
    toId = T.toId;

    // ── A. unchanged ─────────────────────────────────────────
    console.log('\n═══ A. 보던 기준 그대로 지원 ═══');
    const r1 = unwrap(await applyAs(u1, T, 0, fpA));
    const a1 = await appDoc(r1.applicationId);
    console.log('  성공 · snapshot:', brief(a1.attendancePolicySnapshot));
    console.log('  A 와 동일 =',
      same7(a1.attendancePolicySnapshot, bizA.attendanceRules) ?
        '예' : '**아니오**');

    // ── B. race ──────────────────────────────────────────────
    console.log('\n═══ B. 보는 동안 기준이 B 로 바뀜 ═══');
    await setRules(B);
    await confirmPolicy();
    const bizB = (await bizRef.get()).data();
    console.log('  사업장 현재:', brief(bizB.attendanceRules));
    const beforeDocs = (await relationDocs(u2, T.toId)).size;
    const beforeNotif = await notifCount();
    const toBefore = (await db.collection('tos').doc(T.toId).get()).data();
    try {
      await applyAs(u2, T, 1, fpA); // 여전히 A 를 들고 있다
      console.log('  **통과했다 — race 가 열려 있다**');
    } catch (e) {
      console.log('  차단 reason =', reasonOf(e));
    }
    const afterDocs = (await relationDocs(u2, T.toId)).size;
    const afterNotif = await notifCount();
    const toAfter = (await db.collection('tos').doc(T.toId).get()).data();
    console.log('  지원서 생성 =', afterDocs - beforeDocs, '(0이어야 한다)');
    console.log('  totalPending 변화 =',
      (toAfter.totalPending ?? 0) - (toBefore.totalPending ?? 0),
      '(0이어야 한다)');
    console.log('  관리자 알림 변화 =', afterNotif - beforeNotif,
      '(0이어야 한다)');

    // ── C. refresh 후 재지원 ─────────────────────────────────
    console.log('\n═══ C. 최신 기준 B 를 다시 읽고 재지원 ═══');
    const fpB = fingerprint(bizB.attendanceRules);
    const r2 = unwrap(await applyAs(u2, T, 1, fpB));
    const a2 = await appDoc(r2.applicationId);
    console.log('  성공 · snapshot:', brief(a2.attendancePolicySnapshot));
    console.log('  B 와 동일 =',
      same7(a2.attendancePolicySnapshot, bizB.attendanceRules) ?
        '예' : '**아니오**');

    // ── D. 토큰 없이 지원 ────────────────────────────────────
    console.log('\n═══ D. 기준을 보여주지 않은 경로 ═══');
    try {
      await applyAs(u3, T, 2, undefined);
      console.log('  **통과했다 — 미고지 지원이 가능하다**');
    } catch (e) {
      console.log('  차단 reason =', reasonOf(e));
    }
    console.log('  지원서 =', (await relationDocs(u3, T.toId)).size,
      '(0이어야 한다)');

    // ── E. metadata 만 바뀐 경우 ─────────────────────────────
    console.log('\n═══ E. 7개 숫자 그대로 · 확인 기록만 새로 ═══');
    await confirmPolicy(); // 같은 값으로 다시 확인 → confirmedAt 만 바뀐다
    const bizE = (await bizRef.get()).data();
    console.log('  토큰 변화 =',
      fingerprint(bizE.attendanceRules) === fpB ? '없음 (정상)' : '**있다**');
    const r3 = unwrap(await applyAs(u3, T, 2, fpB));
    console.log('  지원 성공 =', r3.applicationId ? '예 (false mismatch 없음)' :
      '**실패**');

    // ── F. 멱등 — 성공 뒤 기준 변경 후 같은 요청 재시도 ──────
    console.log('\n═══ F. 성공 뒤 기준 변경 · 같은 요청 재시도 ═══');
    await setRules({lateUnit: 15});
    await confirmPolicy();
    console.log('  사업장 현재 lateUnit =',
      (await bizRef.get()).data().attendanceRules.lateUnit);
    try {
      await applyAs(u1, T, 0, fpA); // 첫 성공과 **같은** 요청
      console.log('  **성공으로 돌아왔다 — 예상 밖**');
    } catch (e) {
      const why = reasonOf(e);
      console.log('  결과 =', why);
      console.log('  판정 =',
        /ALREADY_EXISTS|already/i.test(why) ?
          '기존 성공이 보존됐다 (기준 변경이 과거 성공을 덮지 않았다)' :
          '**기준 변경이 과거 성공을 덮었다**');
    }
    const a1b = await appDoc(r1.applicationId);
    console.log('  첫 지원서 snapshot 불변 =',
      same7(a1b.attendancePolicySnapshot, a1.attendancePolicySnapshot) ?
        '예' : '**아니오**');
  } finally {
    await bizRef.update({attendanceRules: originalRules});
    if (originalCfm != null) {
      await bizRef.update({attendancePolicyConfirmation: originalCfm});
    } else {
      await bizRef.update({
        attendancePolicyConfirmation: lib.admin.firestore.FieldValue.delete(),
      });
    }
    if (toId) {
      try {
        await lib.callAs(adminUid, 'callableCloseTOManually', {toId, businessId});
      } catch (e) { console.log('공고 정리 실패:', reasonOf(e)); }
    }
    const back = (await bizRef.get()).data();
    console.log('\n기준 원복:', brief(back.attendanceRules),
      same7(back.attendanceRules, originalRules) ? '(확인)' : '(**불일치**)');
    console.log('확인 원복:',
      back.attendancePolicyConfirmation == null ? '(없음 — 원래 상태)' : '있음');
  }
  process.exit(0);
})().catch((e) => { console.error('실패:', reasonOf(e)); process.exit(1); });
