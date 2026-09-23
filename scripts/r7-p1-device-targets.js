#!/usr/bin/env node
/**
 * [R7-P1-PRODUCT] 실기기 검증 대상 찾기.
 *
 * 검증할 상태 목록을 주는 것으로는 부족하다. 실기기 앞에 앉은 사람이
 * 알아야 하는 것은 "FULL 상태를 보라"가 아니라 **"어느 공고의 어느 날짜를
 * 열면 FULL이 보이는가"**다. 그것을 DEV 실데이터에서 찾아 준다.
 *
 * fixture를 만들지 않는다. 있는 것을 가리킬 뿐이고, 없는 상태는
 * NOT SEEN으로 남긴다.
 *
 *   node scripts/r7-p1-device-targets.js --project alfit-89567
 *
 * 읽기 전용이다.
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

const {db} = require('./r7-fixture-lib');

const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const ADMIN = 'BErRdiWP1xbgyoTovxwAPNEsuD72';
const KST = 9 * 3600e3;
const DAY = 24 * 3600e3;

const log = (...a) => console.log(...a);
const head = (s) => console.log(`\n${'─'.repeat(72)}\n${s}\n`);
const toMs = (v) => {
  if (!v) return null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (typeof v._seconds === 'number') return v._seconds * 1000;
  return null;
};
const dayKey = (ms) => new Date(ms + KST).toISOString().slice(0, 10);

function capacityStateOf(confirmed, required, isClosed) {
  if (confirmed === null || confirmed === undefined) return 'UNKNOWN';
  if (isClosed) return 'CLOSED';
  if (required > 0 && confirmed >= required) return 'FULL';
  return 'AVAILABLE';
}

(async () => {
  log('');
  log(`R7-P1 DEVICE TARGETS — project=${projectId} (읽기 전용)`);

  const toSnap = await db.collection('tos')
      .where('businessId', '==', BIZ).limit(200).get();

  /** 공고별 요약 */
  const postings = [];
  for (const toDoc of toSnap.docs) {
    const to = toDoc.data();
    const isLongTerm = to.type === 'contract';
    const slots = await db.collection('tos').doc(toDoc.id)
        .collection('slots').limit(60).get();

    const units = slots.empty
        ? [{id: null, date: null, data: to}]
        : slots.docs.map((d) => ({
          id: d.id, date: toMs(d.data().date), data: d.data(),
        }));

    const perDate = [];
    for (const u of units) {
      const counts = u.data.workDetailCounts || {};
      const details = (u.data.workDetails && u.data.workDetails.length)
          ? u.data.workDetails : (to.workDetails || []);
      const states = [];
      for (const wd of details) {
        const wdId = wd.wdId || wd.id;
        const row = wdId ? counts[wdId] : undefined;
        const confirmed = row && typeof row.confirmedCount === 'number'
            ? row.confirmedCount : null;
        const required = typeof wd.requiredCount === 'number'
            ? wd.requiredCount : 0;
        const closed = u.data.isManualClosed === true ||
            u.data.status === 'closed' || to.isManualClosed === true;
        states.push({
          workType: wd.workType, required, confirmed,
          cap: capacityStateOf(confirmed, required, closed),
          shortage: confirmed === null ? null
              : Math.max(0, required - confirmed),
        });
      }
      perDate.push({slotId: u.id, date: u.date, states});
    }

    postings.push({
      id: toDoc.id,
      title: to.groupTitle || to.title || '(제목 없음)',
      rawTitle: to.title || '',
      groupTitle: to.groupTitle || null,
      isLongTerm,
      slotCount: slots.size,
      perDate,
    });
  }

  // ── 1. 제목 == 업무명인 공고 (R7-P1-2의 핵심 회귀 대상) ──────────────
  head('1. 제목이 업무명과 같은 공고 — 이전에는 제목 줄이 통째로 사라지던 경우');
  const sameAsWork = postings.filter((p) => {
    const types = new Set();
    for (const d of p.perDate) for (const s of d.states) types.add(s.workType);
    return types.size === 1 && p.title === [...types][0];
  });
  if (sameAsWork.length === 0) {
    log('   NOT SEEN — 제목과 업무명이 같은 공고가 없다.');
    log('   (이 회귀는 계약 테스트 06-f가 고정하고 있다)');
  } else {
    for (const p of sameAsWork.slice(0, 5)) {
      log(`   "${p.title}"  to=${p.id}  ${p.isLongTerm ? '고정' : '단기'}`);
    }
  }

  // ── 2. mixed FLEX — 한 공고 안에 FULL 날짜와 shortage 날짜가 함께 ──
  head('2. MIXED FLEX — FULL 날짜와 부족 날짜가 한 공고에 같이 있는 것');
  const mixed = [];
  for (const p of postings) {
    if (p.isLongTerm) continue;
    const dated = p.perDate.filter((d) => d.date);
    const hasFull = dated.some((d) => d.states.some((s) => s.cap === 'FULL'));
    const hasShort = dated.some((d) =>
      d.states.some((s) => s.cap === 'AVAILABLE' && s.shortage > 0));
    if (hasFull && hasShort) mixed.push(p);
  }
  if (mixed.length === 0) {
    log('   NOT SEEN — FULL과 부족이 공존하는 FLEX 공고가 없다.');
    const multi = postings.filter((p) => !p.isLongTerm && p.slotCount > 1);
    log(`   (다중 날짜 FLEX 자체는 ${multi.length}건 있다 — §4의 나머지는 확인 가능)`);
    for (const p of multi.slice(0, 3)) {
      const days = p.perDate.filter((d) => d.date)
          .map((d) => dayKey(d.date)).sort();
      log(`     "${p.title}" to=${p.id}  ${days[0]}~${days[days.length - 1]} (${days.length}일)`);
    }
  } else {
    for (const p of mixed.slice(0, 5)) {
      log(`   "${p.title}"  to=${p.id}`);
      for (const d of p.perDate.filter((x) => x.date).slice(0, 8)) {
        const tags = d.states.map((s) =>
          `${s.workType}:${s.cap}${s.shortage ? `(부족${s.shortage})` : ''}`);
        log(`     ${dayKey(d.date)}  ${tags.join('  ')}`);
      }
    }
  }

  // ── 3. 각 capacity 상태의 구체적 진입 지점 ──────────────────────────
  head('3. capacity 상태별 진입 지점');
  const byCap = {AVAILABLE: [], FULL: [], CLOSED: [], UNKNOWN: []};
  for (const p of postings) {
    for (const d of p.perDate) {
      for (const s of d.states) {
        if (byCap[s.cap].length >= 3) continue;
        byCap[s.cap].push({
          title: p.title, toId: p.id, isLongTerm: p.isLongTerm,
          date: d.date ? dayKey(d.date) : '(고정 공고 — 날짜 없음)',
          workType: s.workType, required: s.required,
          confirmed: s.confirmed, shortage: s.shortage,
        });
      }
    }
  }
  for (const [cap, rows] of Object.entries(byCap)) {
    log(`   ${cap}`);
    if (rows.length === 0) {
      log('     NOT SEEN');
      continue;
    }
    for (const r of rows) {
      log(`     "${r.title}" ${r.isLongTerm ? '[고정]' : '[단기]'} ${r.date}`);
      log(`       ${r.workType} — 확정 ${r.confirmed ?? '?'} / 필요 ${r.required}` +
          `${r.shortage ? ` · 부족 ${r.shortage}` : ''}`);
    }
  }

  // ── 4. 인력 현황 first-view 대상 — 지원자 수별 ─────────────────────
  head('4. 「인력 현황」 진입 대상 — 지원자 수별');
  const apps = await db.collection('applications')
      .where('businessId', '==', BIZ).limit(500).get();
  const byUnit = new Map();
  for (const d of apps.docs) {
    const a = d.data();
    const key = `${a.toId}|${a.slotId || '-'}|${a.wdId || a.workDetailId || '-'}`;
    if (!byUnit.has(key)) byUnit.set(key, {pending: 0, confirmed: 0, raw: a});
    const e = byUnit.get(key);
    if (a.status === 'PENDING') e.pending++;
    if (a.status === 'CONFIRMED' || a.status === 'CONTRACT_PENDING') e.confirmed++;
  }
  const units = [...byUnit.entries()].map(([k, v]) => ({k, ...v}));
  const pick = (f, label) => {
    const hit = units.filter(f).slice(0, 2);
    log(`   ${label}`);
    if (hit.length === 0) {
      log('     NOT SEEN');
      return;
    }
    for (const h of hit) {
      const [toId, slotId] = h.k.split('|');
      const wd = h.raw.workDate ? dayKey(toMs(h.raw.workDate)) : '?';
      log(`     to=${toId} slot=${slotId} ${wd} — 지원 ${h.pending} / 확정 ${h.confirmed}`);
    }
  };
  pick((u) => u.pending === 0 && u.confirmed === 0, '지원자 0');
  pick((u) => u.pending + u.confirmed === 1, '지원자 1');
  pick((u) => u.pending + u.confirmed >= 3, '지원자 여러 명 (3+)');
  pick((u) => u.confirmed >= 2, '확정자 2명 이상 (bulk 대상)');

  // ── 5. 알림 상태 ────────────────────────────────────────────────────
  head('5. 알림 — 그룹·읽음 분포');
  const notifs = await db.collection('users').doc(ADMIN)
      .collection('notifications').orderBy('createdAt', 'desc')
      .limit(200).get();
  const now = Date.now();
  const today = dayKey(now);
  const yesterday = dayKey(now - DAY);
  const g = {오늘: 0, 어제: 0, '이번 주': 0, 이전: 0};
  let unread = 0;
  for (const d of notifs.docs) {
    const n = d.data();
    if (!n.isRead) unread++;
    const ms = toMs(n.createdAt);
    if (ms === null) continue;
    const k = dayKey(ms);
    if (k === today) g['오늘']++;
    else if (k === yesterday) g['어제']++;
    else if (ms > now - 7 * DAY) g['이번 주']++;
    else g['이전']++;
  }
  log(`   최근 ${notifs.size}건 기준`);
  for (const [k, v] of Object.entries(g)) {
    log(`     ${k.padEnd(8)} ${v}${v === 0 ? '   ← NOT SEEN' : ''}`);
  }
  log(`     미읽음   ${unread}`);
  log('');
  log('   swipe 검증: 미읽음 알림 → [읽음 | 삭제] / 읽은 알림 → [삭제]');
  log(`   미읽음이 ${unread}건이므로 두 경우 모두 확인 가능` +
      `${unread === notifs.size ? ' — 단, 읽은 알림이 없으면 하나를 먼저 읽어야 한다' : ''}`);

  log('');
  log('─'.repeat(72));
  log('NOT SEEN으로 적힌 것은 억지로 만들지 않는다. 그대로 보고에 남긴다.');
  log('');
  process.exit(0);
})();
