/**
 * [R7-PAYROLL-POLICY.4D §45] DEV 런타임 — 기준 없음에서 신규 지원 차단.
 *
 *   A. absent              : attendanceRules 삭제 → 지원 → UNAVAILABLE · side effect 0
 *   B. present+unconfirmed : 기준 A 있음 · 확인 기록 없음 → 지원 **성공** · snapshot A
 *                            (`.4A` 가 일부러 열어 둔 경로 — positive control)
 *   C. recovery            : absent 차단 → 기준 저장 → 최신 읽고 지원 성공
 *   D. partial             : 7개 중 하나만 지운 상태 → 지원 차단
 *                            (서버가 기본값으로 메워 통과시키지 않는다)
 *   E. existing success    : 성공 뒤 기준 삭제 → 같은 요청 재시도
 *                            → ALREADY_EXISTS (과거 성공을 덮지 않는다)
 *
 *   §46 실제 데이터 보호: 사업장 문서의 `attendanceRules` 를 Admin SDK 로
 *   임시 변경·삭제한다. **변경 전 raw 문서를 통째로 보존**하고 finally 에서
 *   원복한 뒤 7개 값까지 비교해 확인한다. 지원·확인·공고마감은 모두 canonical
 *   callable 이고, 사용자 실제 지원서는 건드리지 않는다.
 */
'use strict';
const fs = require('fs');
const lib = require('./r7-fixture-lib');
const {db} = lib;
const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;
const CONSENT = '2026-09-18-v3';
const KST = 9 * 3600000;
const pad = (n) => String(n).padStart(2, '0');
const DAY = 3; // 3일 뒤 — 앞 Phase 런타임들이 오늘~모레를 채웠다

const G = JSON.parse(fs.readFileSync('.goldenpath.json', 'utf8'));
const businessId = G.businessId;
const adminUid = G.adminUid;
const bizRef = db.collection('businesses').doc(businessId);

const F = ['earlyWindow', 'earlyArrivalUnit', 'lateGrace', 'lateUnit',
  'lateWindow', 'overtimeUnit', 'earlyLeaveUnit'];
const DEF = {earlyWindow: 30, earlyArrivalUnit: 30, lateGrace: 5,
  lateUnit: 30, lateWindow: 30, overtimeUnit: 10, earlyLeaveUnit: 30};
const fingerprint = (r) => r == null || typeof r !== 'object' ? 'absent' :
  F.map((k) => `${k}=${typeof r[k] === 'number' ? r[k] : DEF[k]}`).join('|');
const brief = (o) => o == null ? '(없음)' :
  `grace ${o.lateGrace}/unit ${o.lateUnit}/early ${o.earlyLeaveUnit}/ot ${o.overtimeUnit}`;
const same7 = (a, b) => a != null && b != null && F.every((k) => a[k] === b[k]);
const reasonOf = (e) => {
  const d = e && e.details;
  if (d && d.reason) return d.reason;
  return String((e && e.code) || '') + ' ' +
    String((e && e.message) || e).slice(0, 80);
};
const appDoc = (id) =>
  db.collection('applications').doc(id).get().then((d) => d.data());
const relationDocs = (uid, toId) =>
  db.collection('applications').where('uid', '==', uid)
    .where('toId', '==', toId).get();
const notifCount = async () => (await db.collection('users').doc(adminUid)
  .collection('notifications').where('type', '==', 'newApplication').get()).size;

async function makeTO(label, nWd) {
  const nowKst = new Date(Date.now() + KST);
  const dateStr = lib.kstDateKey(DAY);
  const workDateMs = lib.kstMidnightMs(DAY);
  const sM = nowKst.getUTCHours() * 60 + nowKst.getUTCMinutes() + 50;
  const biz = (await bizRef.get()).data();
  const wts = (await bizRef.collection('workTypes').limit(3).get()).docs;
  const mk = (i) => {
    const s2 = sM + i * 2;
    const e2 = s2 + 1;
    return {
      wdId: `p4d-${label}-${i}`,
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
      businessId, businessName: biz.name, title: `[P4D-${label}] 기준 없음`,
      description: 'R7-PAYROLL-POLICY.4D 전용. 실제 모집 아님.',
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
    fixedDeadlineMs: Date.now() + 900000, publishMode: 'immediate',
  });
  await lib.callAs(adminUid, 'callablePublishTO', {toId});
  const slots = await db.collection('tos').doc(toId).collection('slots').get();
  const to = (await db.collection('tos').doc(toId).get()).data();
  return {
    toId, slotId: slots.docs[0].id,
    slotWds: slots.docs[0].data().workDetails || [],
    to, workDateMs,
  };
}

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

(async () => {
  // §46 변경 전 raw 문서 전체 보존
  const biz0 = (await bizRef.get()).data();
  const originalRules = biz0.attendanceRules;
  const originalCfm = biz0.attendancePolicyConfirmation ?? null;
  console.log('보존한 원본 기준:', brief(originalRules));
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
    if (free.length < 4) throw new Error('비어 있는 근로자가 4명 필요하다');
    const [u1, u2, u3, u4] = free;

    // 공고는 **기준이 있고 확인된 상태**에서만 만들어진다 — 기준 없음·미확인은
    //   이미 `.4` 의 posting readiness 가 막는다(§28). 그래서 먼저 확인한다.
    //   (이 사업장의 원래 상태는 '미확인' 이고 finally 에서 그대로 돌려준다.)
    await lib.callAs(adminUid, 'callableConfirmAttendancePolicy', {businessId});
    console.log('공고 개설용 기준 확인 완료 (readiness gate 통과)');
    const T = await makeTO('absent', 4);
    toId = T.toId;
    console.log('공고 개설 완료 (기준 있는 상태에서)');

    // ── A. absent ────────────────────────────────────────────
    console.log('\n═══ A. attendanceRules 삭제 → 신규 지원 ═══');
    await bizRef.update({
      attendanceRules: lib.admin.firestore.FieldValue.delete(),
      attendancePolicyConfirmation: lib.admin.firestore.FieldValue.delete(),
    });
    const bizAbsent = (await bizRef.get()).data();
    console.log('  사업장 기준:', bizAbsent.attendanceRules == null ?
      'ABSENT' : '**남아 있다**');
    console.log('  클라이언트 토큰:', fingerprint(bizAbsent.attendanceRules));
    const beforeDocs = (await relationDocs(u1, T.toId)).size;
    const beforeNotif = await notifCount();
    const toBefore = (await db.collection('tos').doc(T.toId).get()).data();
    try {
      await applyAs(u1, T, 0, 'absent'); // absent == absent
      console.log('  **통과했다 — absent==absent 가 열려 있다**');
    } catch (e) {
      console.log('  차단 reason =', reasonOf(e));
    }
    const toAfter = (await db.collection('tos').doc(T.toId).get()).data();
    console.log('  지원서 생성 =',
      (await relationDocs(u1, T.toId)).size - beforeDocs, '(0이어야 한다)');
    console.log('  totalPending 변화 =',
      (toAfter.totalPending ?? 0) - (toBefore.totalPending ?? 0), '(0)');
    console.log('  관리자 알림 변화 =', (await notifCount()) - beforeNotif, '(0)');

    // ── D. partial ───────────────────────────────────────────
    console.log('\n═══ D. 7개 중 하나만 지운 부분 정책 ═══');
    const partial = {...originalRules};
    delete partial.lateWindow;
    await bizRef.update({attendanceRules: partial});
    const bizPartial = (await bizRef.get()).data();
    console.log('  저장된 lateWindow =',
      bizPartial.attendanceRules.lateWindow === undefined ?
        '(없음)' : bizPartial.attendanceRules.lateWindow);
    console.log('  메워진 토큰:', fingerprint(bizPartial.attendanceRules));
    try {
      await applyAs(u1, T, 0, fingerprint(bizPartial.attendanceRules));
      console.log('  **통과했다 — 서버가 메운 값으로 지원이 생겼다**');
    } catch (e) {
      console.log('  차단 reason =', reasonOf(e));
    }
    console.log('  지원서 =', (await relationDocs(u1, T.toId)).size - beforeDocs,
      '(0이어야 한다)');

    // ── B. present + unconfirmed (positive control) ──────────
    console.log('\n═══ B. 기준 있음 + 사업장 미확인 → 지원 성공해야 한다 ═══');
    await bizRef.update({attendanceRules: originalRules});
    const bizB = (await bizRef.get()).data();
    console.log('  기준:', brief(bizB.attendanceRules),
      '| 확인 기록:', bizB.attendancePolicyConfirmation == null ?
        '없음 (미확인)' : '**있다**');
    const fpB = fingerprint(bizB.attendanceRules);
    try {
      const r = unwrap(await applyAs(u2, T, 1, fpB));
      const a = await appDoc(r.applicationId);
      console.log('  지원 성공 · snapshot:', brief(a.attendancePolicySnapshot));
      console.log('  판정 =', same7(a.attendancePolicySnapshot, bizB.attendanceRules) ?
        '예 — .4A 정책이 유지됐다' : '**snapshot 불일치**');
    } catch (e) {
      console.log('  **차단됐다 — .4A 가 열어 둔 경로를 깨뜨렸다**:', reasonOf(e));
    }

    // ── C. recovery ──────────────────────────────────────────
    console.log('\n═══ C. 기준 삭제 → 차단 → 저장/확인 → 지원 재개 ═══');
    await bizRef.update({
      attendanceRules: lib.admin.firestore.FieldValue.delete(),
    });
    try {
      await applyAs(u3, T, 2, 'absent');
      console.log('  삭제 후 지원: **통과했다**');
    } catch (e) {
      console.log('  삭제 후 차단 reason =', reasonOf(e));
    }
    await bizRef.update({attendanceRules: originalRules});
    await lib.callAs(adminUid, 'callableConfirmAttendancePolicy', {businessId});
    const bizC = (await bizRef.get()).data();
    const r3 = unwrap(await applyAs(u3, T, 2,
      fingerprint(bizC.attendanceRules)));
    const a3 = await appDoc(r3.applicationId);
    console.log('  저장·확인 후 지원 성공 · snapshot:',
      brief(a3.attendancePolicySnapshot));
    console.log('  판정 =', same7(a3.attendancePolicySnapshot, bizC.attendanceRules) ?
      '예 (복구됨)' : '**불일치**');

    // ── E. existing success 보존 ─────────────────────────────
    console.log('\n═══ E. 성공 뒤 기준 삭제 · 같은 요청 재시도 ═══');
    await bizRef.update({
      attendanceRules: lib.admin.firestore.FieldValue.delete(),
    });
    try {
      await applyAs(u3, T, 2, fingerprint(bizC.attendanceRules));
      console.log('  **성공으로 돌아왔다 — 예상 밖**');
    } catch (e) {
      const why = reasonOf(e);
      console.log('  결과 =', why);
      console.log('  판정 =', /ALREADY_EXISTS|already/i.test(why) ?
        '기존 성공이 보존됐다 (기준 삭제가 과거 성공을 덮지 않았다)' :
        '**기준 삭제가 과거 성공을 덮었다**');
    }
    const a3b = await appDoc(r3.applicationId);
    console.log('  기존 지원서 snapshot 불변 =',
      same7(a3b.attendancePolicySnapshot, a3.attendancePolicySnapshot) ?
        '예' : '**아니오**');
    void u4;
  } finally {
    // §46 원복 + 검증
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
    const okRules = same7(back.attendanceRules, originalRules) &&
      F.every((k) => typeof back.attendanceRules[k] === 'number');
    console.log('\n기준 원복:', brief(back.attendanceRules),
      okRules ? '(7개 전부 확인)' : '(**불일치**)');
    console.log('확인 기록 원복:',
      back.attendancePolicyConfirmation == null ? '(없음 — 원래 상태)' : '있음');
  }
  process.exit(0);
})().catch((e) => { console.error('실패:', reasonOf(e)); process.exit(1); });
