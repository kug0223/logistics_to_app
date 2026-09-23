#!/usr/bin/env node
/**
 * [R7-P1] STAFFING + NOTIFICATION PATCH — DEV 런타임 검증.
 *
 * 코드가 맞는 것과 화면이 맞는 것은 다르다. 이 스크립트는 그 사이를 메운다:
 * **실제 DEV 데이터에 이번 PATCH가 판단해야 할 상태들이 실재하는가**, 그리고
 * **그 상태에서 canonical reader가 무엇이라고 말하는가**를 확인한다.
 *
 * 판정식을 여기서 다시 쓰지 않는다. 가능한 곳은 화면이 쓰는 그 CF를 부르고,
 * 클라이언트 안에서만 도는 규칙은 출처를 적고 옮긴다(그 사실도 보고에 남긴다).
 *
 *   node scripts/r7-p1-runtime-verify.js --project alfit-89567
 *
 * 읽기 전용이다. 아무것도 쓰지 않는다.
 */
'use strict';

const EXPECTED_DEV_PROJECT = 'alfit-89567';
const argv = process.argv.slice(2);
const projectId = (() => {
  const i = argv.indexOf('--project');
  return i >= 0 ? argv[i + 1] : null;
})();
if (projectId !== EXPECTED_DEV_PROJECT) {
  console.error(`이 스크립트는 DEV 전용입니다. --project ${EXPECTED_DEV_PROJECT}`);
  process.exit(2);
}

const {db, callAs} = require('./r7-fixture-lib');

const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const ADMIN = 'BErRdiWP1xbgyoTovxwAPNEsuD72';
const WORKER = 'tJ8izfP2nNYN79aPTLb6YARiPqC3';

const KST = 9 * 3600e3;
const DAY = 24 * 3600e3;

const log = (...a) => console.log(...a);
const head = (s) => console.log(`\n${'─'.repeat(72)}\n${s}\n`);

const findings = [];
const record = (level, text) => {
  findings.push({level, text});
  log(`   ${level.padEnd(9)} ${text}`);
};

const toMs = (v) => {
  if (!v) return null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (typeof v._seconds === 'number') return v._seconds * 1000;
  if (typeof v.seconds === 'number') return v.seconds * 1000;
  return null;
};
const dayKey = (ms) => new Date(ms + KST).toISOString().slice(0, 10);

// ══════════════════════════════════════════════════════════════════════
// A. staffing 상태 분포 — §28이 요구하는 상태가 실제로 있는가
//
//    capacity 판정은 클라이언트 `inviteCapacityStateOf`를 옮긴 것이다.
//    (lib/models/ui/invite_capacity_state.dart — CF 등가물 없음)
// ══════════════════════════════════════════════════════════════════════
function capacityStateOf(canonicalConfirmed, requiredCount, isClosed) {
  if (canonicalConfirmed === null || canonicalConfirmed === undefined) {
    return 'UNKNOWN';
  }
  if (isClosed) return 'CLOSED';
  if (requiredCount > 0 && canonicalConfirmed >= requiredCount) return 'FULL';
  return 'AVAILABLE';
}
function shortageOf(capacity, requiredCount, seatedConfirmed) {
  if (capacity === 'UNKNOWN') return null;
  if (capacity === 'CLOSED') return 0;
  const n = requiredCount - seatedConfirmed;
  return n > 0 ? n : 0;
}

async function sectionStaffing() {
  head('A. Staffing 상태 분포 (§28)');

  const toSnap = await db.collection('tos')
      .where('businessId', '==', BIZ).limit(200).get();
  log(`   공고 ${toSnap.size}건 조회`);

  const buckets = {AVAILABLE: 0, FULL: 0, CLOSED: 0, UNKNOWN: 0};
  const byKind = {flex: 0, contract: 0};
  let shortagePostings = 0;
  let longTermShortage = 0;
  let mixedFlex = 0;
  const samples = [];

  for (const toDoc of toSnap.docs) {
    const to = toDoc.data();
    const isLongTerm = to.type === 'contract';
    byKind[isLongTerm ? 'contract' : 'flex']++;

    const slots = await db.collection('tos').doc(toDoc.id)
        .collection('slots').limit(40).get();
    if (!isLongTerm && slots.size > 1) mixedFlex++;

    // 고정 공고는 슬롯이 없다 — 공고 자신이 모집 단위다.
    const units = slots.empty
        ? [{id: null, data: to}]
        : slots.docs.map((d) => ({id: d.id, data: d.data()}));

    let postingShortage = 0;
    for (const u of units) {
      const counts = u.data.workDetailCounts || {};
      // canonical wdId는 **슬롯의** workDetails에 있다.
      //   TO 레벨 workDetails에는 wdId가 없는 레코드가 있고, 슬롯의
      //   workDetailCounts 키는 슬롯 자신의 wdId다. TO 쪽을 읽으면
      //   모든 모집 단위가 UNKNOWN으로 보인다 — 첫 실행에서 실제로 그랬다.
      const details = (u.data.workDetails && u.data.workDetails.length)
          ? u.data.workDetails
          : (to.workDetails || []);
      for (const wd of details) {
        const wdId = wd.wdId || wd.id;
        const row = wdId ? counts[wdId] : undefined;
        // row가 없으면 canonical이 없다 — UNKNOWN이다. 0으로 읽지 않는다.
        const confirmed = row && typeof row.confirmedCount === 'number'
            ? row.confirmedCount : null;
        const required = typeof wd.requiredCount === 'number'
            ? wd.requiredCount : 0;
        const closed = u.data.isManualClosed === true ||
            u.data.status === 'closed' || to.isManualClosed === true;
        const cap = capacityStateOf(confirmed, required, closed);
        buckets[cap]++;
        const sh = shortageOf(cap, required, confirmed ?? 0);
        if (sh && sh > 0) {
          postingShortage += sh;
          if (isLongTerm) longTermShortage++;
        }
        if (samples.length < 8) {
          samples.push({
            to: toDoc.id.slice(0, 6), slot: (u.id || '-').slice(0, 6),
            wd: String(wdId).slice(0, 10),
            cap, required, confirmed, shortage: sh,
          });
        }
      }
    }
    if (postingShortage > 0) shortagePostings++;
  }

  log('');
  log('   capacity 분포 (모집 단위 기준)');
  for (const [k, v] of Object.entries(buckets)) log(`     ${k.padEnd(10)} ${v}`);
  log('');
  log('   샘플');
  for (const s of samples) {
    log(`     to=${s.to} slot=${s.slot} wd=${s.wd.padEnd(10)} ` +
        `${s.cap.padEnd(9)} 필요${s.required} 확정${s.confirmed ?? '?'} ` +
        `부족${s.shortage === null ? 'UNKNOWN' : s.shortage}`);
  }
  log('');

  record(buckets.AVAILABLE > 0 && shortagePostings > 0 ? 'OK' : 'MISSING',
      `shortage posting ${shortagePostings}건`);
  record(buckets.FULL > 0 ? 'OK' : 'MISSING', `FULL target ${buckets.FULL}건`);
  record(buckets.CLOSED > 0 ? 'OK' : 'MISSING',
      `CLOSED target ${buckets.CLOSED}건`);
  record(mixedFlex > 0 ? 'OK' : 'MISSING', `다중 날짜 FLEX ${mixedFlex}건`);
  record(byKind.contract > 0 ? 'OK' : 'MISSING',
      `장기(고정) 공고 ${byKind.contract}건 (부족 ${longTermShortage})`);
  // UNKNOWN이 0인 것은 좋은 일이지만, 그러면 UNKNOWN 경로는 런타임에서
  // 확인되지 않은 채 남는다. 사실대로 적는다.
  record(buckets.UNKNOWN > 0 ? 'OK' : 'NOT_SEEN',
      `capacity UNKNOWN ${buckets.UNKNOWN}건`);

  return {buckets, shortagePostings};
}

// ══════════════════════════════════════════════════════════════════════
// B. Day ↔ WorkApplicants parity
//
//    두 화면은 같은 모집 단위를 다른 문으로 연다. 이번 PATCH 전에는
//    한쪽만 부족을 말했다. 지금은 같은 함수를 쓰므로, 같은 입력에서
//    같은 숫자가 나와야 한다.
// ══════════════════════════════════════════════════════════════════════
async function sectionParity() {
  head('B. Day ↔ WorkApplicants parity');

  const todayMs = Date.now();
  let checked = 0;
  let mismatch = 0;

  for (let d = -3; d <= 10 && checked < 6; d++) {
    const key = dayKey(todayMs + d * DAY);
    let detail;
    try {
      detail = await callAs(ADMIN, 'callableGetDayStaffingDetail',
          {businessId: BIZ, dateMs: todayMs + d * DAY});
    } catch (e) {
      record('ERROR', `${key} detail 조회 실패: ${e.message}`);
      continue;
    }
    const rows = detail.rows || [];
    if (rows.length === 0) continue;

    for (const r of rows) {
      if (checked >= 6) break;
      checked++;
      // Day 화면이 쓰는 값 = 이 row. WorkApplicants가 쓰는 값 = slot 문서의
      // workDetailCounts. 두 출처가 같은 사실을 말해야 한다.
      const slotSnap = r.slotId
          ? await db.collection('tos').doc(r.toId)
              .collection('slots').doc(r.slotId).get()
          : null;
      const counts = slotSnap && slotSnap.exists
          ? (slotSnap.data().workDetailCounts || {}) : {};
      const row = counts[r.wdId];
      const slotConfirmed = row && typeof row.confirmedCount === 'number'
          ? row.confirmedCount : null;

      const same = slotConfirmed === null
          ? r.confirmedCount === undefined || r.confirmedCount === null
          : slotConfirmed === r.confirmedCount;
      if (!same) {
        mismatch++;
        record('MISMATCH',
            `${key} to=${String(r.toId).slice(0, 6)} wd=${String(r.wdId).slice(0, 8)} ` +
            `day=${r.confirmedCount} slot=${slotConfirmed}`);
      }
    }
  }

  log(`   모집 단위 ${checked}건 대조`);
  record(checked === 0 ? 'NOT_SEEN' : (mismatch === 0 ? 'OK' : 'MISMATCH'),
      checked === 0 ? '대조할 모집 단위를 찾지 못함'
          : `확정 수 불일치 ${mismatch}건`);
}

// ══════════════════════════════════════════════════════════════════════
// C. 지원자 상태 분포 — 카드가 말해야 하는 것들
// ══════════════════════════════════════════════════════════════════════
async function sectionApplicants() {
  head('C. 지원자 / 후속 처리 상태 분포');

  const apps = await db.collection('applications')
      .where('businessId', '==', BIZ).limit(400).get();
  const byStatus = {};
  const uids = new Set();
  for (const d of apps.docs) {
    const a = d.data();
    byStatus[a.status] = (byStatus[a.status] || 0) + 1;
    if (a.uid) uids.add(a.uid);
  }
  log('   지원서 상태');
  for (const [k, v] of Object.entries(byStatus).sort()) {
    log(`     ${String(k).padEnd(18)} ${v}`);
  }

  const contracts = await db.collection('employment_contracts')
      .where('businessId', '==', BIZ).limit(400).get();
  const byContract = {};
  for (const d of contracts.docs) {
    const c = d.data();
    byContract[c.status] = (byContract[c.status] || 0) + 1;
  }
  log('');
  log('   계약 상태');
  for (const [k, v] of Object.entries(byContract).sort()) {
    log(`     ${String(k).padEnd(18)} ${v}`);
  }

  // 신분증 요청 가능 — IdCardHelper.isRequestable 을 옮긴 것.
  //   (none | expired | rejected) → `요청 가능`
  const grants = await db.collection('idCardAccessRequests')
      .where('businessId', '==', BIZ).limit(400).get();
  const byGrant = {};
  for (const d of grants.docs) {
    const g = d.data();
    byGrant[g.status] = (byGrant[g.status] || 0) + 1;
  }
  log('');
  log('   신분증 요청 상태');
  for (const [k, v] of Object.entries(byGrant).sort()) {
    log(`     ${String(k).padEnd(18)} ${v}`);
  }
  const requestable = (byGrant.expired || 0) + (byGrant.rejected || 0);
  log('');
  record((byStatus.PENDING || 0) > 0 ? 'OK' : 'NOT_SEEN',
      `PENDING 지원자 ${byStatus.PENDING || 0}명`);
  record((byStatus.CONFIRMED || 0) > 0 ? 'OK' : 'NOT_SEEN',
      `CONFIRMED ${byStatus.CONFIRMED || 0}명`);
  record((byContract.pending_worker || 0) > 0 ? 'OK' : 'NOT_SEEN',
      `서명 대기 계약 ${byContract.pending_worker || 0}건`);
  record((byContract.pending_employer || 0) > 0 ? 'OK' : 'NOT_SEEN',
      `관리자 서명 필요 ${byContract.pending_employer || 0}건`);
  // 기존 grant가 없는 확정자도 `요청 가능`이다(none). 그 수는 화면이 센다.
  record('INFO',
      `grant 문서 기준 재요청 대상(expired+rejected) ${requestable}건`);

  // 최근 90일 노쇼 — red 유지 대상
  const cut = Date.now() - 90 * DAY;
  const att = await db.collection('attendance')
      .where('businessId', '==', BIZ).limit(500).get();
  let noShow = 0;
  let actualFinalized = 0;
  let noShowConfirmedWage = 0;
  for (const d of att.docs) {
    const a = d.data();
    const wd = toMs(a.workDate);
    if (a.status === 'NO_SHOW') {
      if (wd && wd >= cut) noShow++;
      if (a.wageStatus === 'confirmed' || a.wageStatus === 'transferred') {
        noShowConfirmedWage++;
      }
    }
    const worked = ['present', 'late', 'early_leave'].includes(a.status);
    const done = ['confirmed', 'transferred'].includes(a.wageStatus);
    if (worked && done) actualFinalized++;
  }
  log('');
  record(noShow > 0 ? 'OK' : 'NOT_SEEN', `최근 90일 노쇼 ${noShow}건`);
  record('INFO', `실근무+마감(리뷰 자격) ${actualFinalized}건`);
  // 이것이 §11 defect의 실체다 — wageStatus만 보면 이만큼이 실근무로 샌다.
  record(noShowConfirmedWage > 0 ? 'FOUND' : 'NOT_SEEN',
      `NO_SHOW인데 wageStatus가 confirmed/transferred: ${noShowConfirmedWage}건 ` +
      `(wageStatus만 보면 실근무로 집계되던 수)`);
}

// ══════════════════════════════════════════════════════════════════════
// D. Notification — 90일 window · Notification != Task
// ══════════════════════════════════════════════════════════════════════
async function sectionNotifications() {
  head('D. Notification (90일 window / Notification != Task)');

  const VISIBLE_DAYS = 90; // lib/utils/notification_retention.dart
  const now = Date.now();
  const cut = now - VISIBLE_DAYS * DAY;

  for (const [who, uid] of [['관리자', ADMIN], ['근로자', WORKER]]) {
    const snap = await db.collection('users').doc(uid)
        .collection('notifications').limit(500).get();
    let visible = 0; let aged = 0; let unknownTs = 0;
    let unread = 0; let unreadVisible = 0;
    let oldestMs = null;
    for (const d of snap.docs) {
      const n = d.data();
      const ms = toMs(n.createdAt);
      if (ms === null) { unknownTs++; visible++; if (!n.isRead) { unread++; unreadVisible++; } continue; }
      if (oldestMs === null || ms < oldestMs) oldestMs = ms;
      if (ms >= cut) { visible++; if (!n.isRead) unreadVisible++; }
      else aged++;
      if (!n.isRead) unread++;
    }
    log(`   ${who}  전체 ${snap.size} / 창 안 ${visible} / 창 밖 ${aged} / ` +
        `시각없음 ${unknownTs}`);
    log(`         미읽음 ${unread} (창 안 ${unreadVisible})`);
    if (oldestMs !== null) {
      const ageDays = Math.floor((now - oldestMs) / DAY);
      log(`         가장 오래된 알림: ${ageDays}일 전`);
      // 정리 job이 30일이었으므로 DEV에도 30일 넘는 알림이 거의 없을 수 있다.
      record(ageDays > 30 ? 'OK' : 'NOT_SEEN',
          `${who} 30일 초과 알림 존재 여부 (가장 오래된 ${ageDays}일)`);
    }
    record(unknownTs === 0 ? 'OK' : 'FOUND',
        `${who} createdAt 없는 legacy 알림 ${unknownTs}건 ` +
        `(있으면 '이전' 섹션으로 간다 — '오늘' 아님)`);
    record(unread === unreadVisible ? 'OK' : 'INFO',
        `${who} 미읽음 수가 창 적용 전후로 ${unread === unreadVisible ? '같다' : '다르다'} ` +
        `(${unread} → ${unreadVisible})`);
  }

  // Notification != Task — 알림이 없어도 domain task는 남아 있는가
  log('');
  const pendingApps = await db.collection('applications')
      .where('businessId', '==', BIZ).where('status', '==', 'PENDING')
      .limit(50).get();
  const pendingContracts = await db.collection('employment_contracts')
      .where('businessId', '==', BIZ).where('status', '==', 'pending_worker')
      .limit(50).get();

  const adminNotifs = await db.collection('users').doc(ADMIN)
      .collection('notifications').limit(500).get();
  const notifAppIds = new Set();
  const notifContractIds = new Set();
  for (const d of adminNotifs.docs) {
    const data = d.data().data || {};
    if (data.applicationId) notifAppIds.add(data.applicationId);
    if (data.contractId) notifContractIds.add(data.contractId);
  }

  const appsWithoutNotif = pendingApps.docs
      .filter((d) => !notifAppIds.has(d.id)).length;
  const contractsWithoutNotif = pendingContracts.docs
      .filter((d) => !notifContractIds.has(d.id)).length;

  log(`   PENDING 지원서 ${pendingApps.size} (알림 없는 것 ${appsWithoutNotif})`);
  log(`   서명대기 계약 ${pendingContracts.size} (알림 없는 것 ${contractsWithoutNotif})`);
  record('OK',
      `알림 없이 남아 있는 domain task가 ${appsWithoutNotif + contractsWithoutNotif}건 — ` +
      `알림은 task source가 아니다`);

  // 반대 방향: 알림이 가리키는 대상이 이미 사라진 경우(stale deep link)
  let staleApp = 0;
  for (const id of Array.from(notifAppIds).slice(0, 30)) {
    const s = await db.collection('applications').doc(id).get();
    if (!s.exists) staleApp++;
  }
  record(staleApp === 0 ? 'OK' : 'INFO',
      `대상이 사라진 알림 deep link ${staleApp}건 (화면은 안내 후 목록으로 보낸다)`);
}

// ══════════════════════════════════════════════════════════════════════
(async () => {
  log('');
  log(`R7-P1 RUNTIME VERIFY — project=${projectId} (읽기 전용)`);
  log(`biz=${BIZ}`);

  try {
    await sectionStaffing();
    await sectionParity();
    await sectionApplicants();
    await sectionNotifications();
  } catch (e) {
    console.error('\n치명적 오류:', e);
    process.exitCode = 1;
  }

  head('요약');
  const counts = {};
  for (const f of findings) counts[f.level] = (counts[f.level] || 0) + 1;
  for (const [k, v] of Object.entries(counts)) log(`   ${k.padEnd(10)} ${v}`);
  log('');
  for (const f of findings) {
    if (f.level === 'OK' || f.level === 'INFO') continue;
    log(`   ${f.level.padEnd(10)} ${f.text}`);
  }
  log('');
  process.exit(0);
})();
