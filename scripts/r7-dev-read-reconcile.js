/**
 * R7 7차 §6 — 실DEV **읽기 전용** 대조.
 *
 *   원장(applications)에서 계산한 기대값과, 저장된 파생 집계
 *   (`slot.pendingCount` / `slot.confirmedCount` /
 *    `slot.workDetailCounts[wdId]` / `to.totalPending` / `to.totalConfirmed`)를
 *   비교한다.
 *
 *   **쓰기는 하지 않는다.** `.get()` 만 쓴다. 보정도 하지 않는다.
 *   개인정보는 읽지도 출력하지도 않는다 — 상태·시간·식별자만 본다.
 *
 *   사용:
 *     node scripts/r7-dev-read-reconcile.js --probe        규모만 센다
 *     node scripts/r7-dev-read-reconcile.js --limit 50     공고 50개 대조
 */
const path = require('path');
const fs = require('fs');

const KEY = path.join(__dirname, '..', 'functions',
  'alfit-89567-firebase-adminsdk-fbsvc-4174a2458f.json');
if (!fs.existsSync(KEY)) {
  console.error('서비스 계정 키를 찾지 못했습니다. 대조를 중단합니다.');
  process.exit(2);
}
// 에뮬레이터 환경변수가 남아 있으면 실DEV 가 아니라 로컬을 읽게 된다 — 지운다.
delete process.env.FIRESTORE_EMULATOR_HOST;
delete process.env.FIREBASE_AUTH_EMULATOR_HOST;
delete process.env.FIREBASE_STORAGE_EMULATOR_HOST;

const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));
const cred = JSON.parse(fs.readFileSync(KEY, 'utf8'));
admin.initializeApp({
  credential: admin.credential.cert(cred),
  projectId: cred.project_id,
});
const db = admin.firestore();

const args = process.argv.slice(2);
const PROBE = args.includes('--probe');
const LIMIT = (() => {
  const i = args.indexOf('--limit');
  return i >= 0 ? parseInt(args[i + 1], 10) : 40;
})();

// [O07] `--repair-plan` : 보정 command 가 쓸 필드를 **투영만** 한다(쓰기 없음).
const PLAN = args.includes('--repair-plan');
const plan = [];

const PENDING = ['PENDING', 'INVITED'];
const SEATED = ['CONFIRMED', 'CONTRACT_PENDING'];
const KST = 9 * 3600 * 1000;
const kstDateNum = (d) => {
  const k = new Date(d.getTime() + KST);
  return k.getUTCFullYear() * 10000 + (k.getUTCMonth() + 1) * 100 + k.getUTCDate();
};
/** 트리거와 같은 좌석 규칙. */
function occupiesSeatToday(a) {
  if (a.type !== 'long_term') return true;
  const end = a.actualResignDate ?? a.workEndDate;
  if (!end || typeof end.toDate !== 'function') return true;
  return kstDateNum(end.toDate()) >= kstDateNum(new Date());
}
/** 서버 `srvResolveAppWdId` 와 같은 우선순위. */
function resolveWdId(a, wds, isNewSchema) {
  if (a.wdId) return {wdId: a.wdId, via: 'wdId'};
  if (!isNewSchema) return {via: 'legacySlot'};
  if (a.workDetailId && String(a.workDetailId).split('_').length >= 3) {
    const m = wds.find((w) => `${w.workType}_${w.startTime}_${w.endTime}` === a.workDetailId);
    if (m?.wdId) return {wdId: m.wdId, via: 'composite'};
  }
  if (a.selectedWorkType && a.startTime && a.endTime) {
    const m = wds.find((w) => w.workType === a.selectedWorkType &&
      w.startTime === a.startTime && w.endTime === a.endTime);
    if (m?.wdId) return {wdId: m.wdId, via: 'timeTriple'};
  }
  if (a.selectedWorkType) {
    const same = wds.filter((w) => w.workType === a.selectedWorkType);
    if (same.length === 1 && same[0].wdId) return {wdId: same[0].wdId, via: 'uniqueWorkType'};
    if (same.length > 1) return {via: 'ambiguous'};
  }
  return {via: 'unresolved'};
}

(async () => {
  const startedAt = new Date().toISOString();
  console.log(`# R7 DEV READ 대조 (읽기 전용)`);
  console.log(`- 프로젝트: ${cred.project_id}`);
  console.log(`- 기준시점(UTC): ${startedAt}`);

  if (PROBE) {
    const [tos, apps] = await Promise.all([
      db.collection('tos').count().get(),
      db.collection('applications').count().get(),
    ]);
    console.log(`- tos: ${tos.data().count}`);
    console.log(`- applications: ${apps.data().count}`);
    const flex = await db.collection('tos').where('type', '==', 'flex')
      .count().get();
    console.log(`- flex tos: ${flex.data().count}`);
    process.exit(0);
  }

  // 대조 대상: flex 공고(슬롯 축이 있는 것). 최근 생성 순으로 제한한다.
  // 복합 인덱스를 새로 만들지 않는다(실DEV 변경 금지). 문서 수가 작으므로
  // 전량을 읽고 클라이언트에서 거른다.
  const allTos = await db.collection('tos').get();
  const flexDocs = allTos.docs
    .filter((d) => (d.data().type ?? '') === 'flex')
    .sort((a, b) => {
      const ta = a.data().createdAt?.toMillis?.() ?? 0;
      const tb = b.data().createdAt?.toMillis?.() ?? 0;
      return tb - ta;
    })
    .slice(0, LIMIT);
  const toSnap = {docs: flexDocs, size: flexDocs.length};
  console.log(`- 전체 공고 ${allTos.size} 중 flex ${toSnap.size} 대조 ` +
    `(최근 생성순 ${LIMIT} 제한)\n`);

  const findings = [];
  let slotsChecked = 0, wdKeysChecked = 0;
  const viaTally = {};

  for (const toDoc of toSnap.docs) {
    const toId = toDoc.id;
    const to = toDoc.data();
    const [slots, apps] = await Promise.all([
      db.collection(`tos/${toId}/slots`).get(),
      db.collection('applications').where('toId', '==', toId).get(),
    ]);

    // 공고 단위 기대값
    let toPending = 0, toSeated = 0;
    const bySlot = {};
    apps.forEach((d) => {
      const a = d.data();
      const isP = PENDING.includes(a.status);
      const isS = SEATED.includes(a.status) && a.staffingReleasedAt == null &&
        occupiesSeatToday(a);
      if (isP) toPending++;
      if (isS) toSeated++;
      const sid = a.slotId;
      if (!sid) return;
      bySlot[sid] ??= [];
      bySlot[sid].push({a, isP, isS});
    });

    if ((to.totalPending ?? 0) !== toPending) {
      findings.push({kind: 'to.totalPending', toId,
        stored: to.totalPending ?? null, expected: toPending});
    }
    if ((to.totalConfirmed ?? 0) !== toSeated) {
      findings.push({kind: 'to.totalConfirmed', toId,
        stored: to.totalConfirmed ?? null, expected: toSeated});
    }

    // [O07] 보정 계획 — **재집계 command 가 실제로 쓸 필드 전부**를 투영한다.
    //   `callableRecalculateTOStats(toId)` 가 쓰는 것:
    //     tos: totalPending · totalConfirmed · status(CLOSED/EXPIRED 아닐 때) ·
    //          statsSourceReadAt(fence, 값과 함께 항상)
    //     slots: pendingCount · confirmedCount · workDetailCounts.{현재 wdId}
    //   원장(applications)·계약·근태·급여는 건드리지 않는다.
    if (PLAN) {
      const rows = [];
      const push = (o) => rows.push(o);
      const notClosed = to.status !== 'CLOSED' && to.status !== 'EXPIRED';
      const req = to.totalRequired ?? 0;
      push({scope: `to=${toId}`, field: 'totalPending',
        stored: to.totalPending ?? null, expected: toPending,
        why: '원장 PENDING/INVITED 수', ledger: `applications(toId=${toId})`});
      push({scope: `to=${toId}`, field: 'totalConfirmed',
        stored: to.totalConfirmed ?? null, expected: toSeated,
        why: '확정 중 좌석 점유만(반납·기간종료 제외)',
        ledger: `applications(toId=${toId})`});
      if (notClosed) {
        push({scope: `to=${toId}`, field: 'status',
          stored: to.status ?? null,
          expected: (req > 0 && toSeated >= req) ? 'FULL' : 'ACTIVE',
          why: `totalRequired=${req} 와 좌석 수 비교`, ledger: '위 값에서 파생'});
      } else {
        push({scope: `to=${toId}`, field: 'status',
          stored: to.status ?? null, expected: to.status ?? null,
          why: 'CLOSED/EXPIRED 는 재계산이 손대지 않는다', ledger: '-'});
      }
      push({scope: `to=${toId}`, field: 'statsSourceReadAt',
        stored: to.statsSourceReadAt ? 'set' : null, expected: '(이번 읽기 시각)',
        why: 'fence — 값과 함께 항상 기록', ledger: '-'});
      for (const slotDoc of slots.docs) {
        const s = slotDoc.data();
        const r = bySlot[slotDoc.id] ?? [];
        const wds = Array.isArray(s.workDetails) ? s.workDetails : [];
        const isNew = wds.some((w) => typeof w?.wdId === 'string' && w.wdId.length > 0);
        let sp = 0, sc = 0; const tally = {}; let fc = false;
        for (const {a, isP, isS} of r) {
          if (isP) sp++;
          if (isS) sc++;
          if (!isP && !isS) continue;
          const rr = resolveWdId(a, wds, isNew);
          if (rr.via === 'ambiguous' || rr.via === 'unresolved') { fc = true; continue; }
          if (!rr.wdId) continue;
          tally[rr.wdId] ??= {pending: 0, confirmed: 0};
          if (isP) tally[rr.wdId].pending++;
          if (isS) tally[rr.wdId].confirmed++;
        }
        const sk = `to=${toId} slot=${slotDoc.id}`;
        push({scope: sk, field: 'pendingCount', stored: s.pendingCount ?? null,
          expected: sp, why: '슬롯 범위 원장 재계산',
          ledger: `applications(slotId=${slotDoc.id})`});
        push({scope: sk, field: 'confirmedCount', stored: s.confirmedCount ?? null,
          expected: sc, why: '좌석 점유만', ledger: `applications(slotId=${slotDoc.id})`});
        const stored = s.workDetailCounts ?? {};
        const cur = wds.map((w) => w?.wdId).filter(Boolean);
        for (const k of cur) {
          const e = tally[k] ?? {pending: 0, confirmed: 0};
          const st = stored[k] ?? {};
          push({scope: `${sk} wd=${k}`, field: 'workDetailCounts.pendingCount',
            stored: st.pendingCount ?? null, expected: fc ? '(fail-closed 미갱신)' : e.pending,
            why: fc ? 'identity 미확정 슬롯 — 서버도 건드리지 않는다' : '현재 wdId 전량 0 시드 후 집계',
            ledger: `applications(slotId=${slotDoc.id})`});
          push({scope: `${sk} wd=${k}`, field: 'workDetailCounts.confirmedCount',
            stored: st.confirmedCount ?? null, expected: fc ? '(fail-closed 미갱신)' : e.confirmed,
            why: fc ? 'identity 미확정 슬롯' : '같음',
            ledger: `applications(slotId=${slotDoc.id})`});
        }
        for (const k of Object.keys(stored)) {
          if (cur.includes(k)) continue;
          push({scope: `${sk} wd=${k}`, field: 'workDetailCounts(사라진 키)',
            stored: JSON.stringify({p: stored[k]?.pendingCount ?? null,
              c: stored[k]?.confirmedCount ?? null}),
            expected: '(그대로)',
            why: '현재 업무 정의에 없는 키 — 보존 계약(읽는 곳 없음)', ledger: '-'});
        }
      }
      plan.push({toId, rows});
    }

    for (const slotDoc of slots.docs) {
      slotsChecked++;
      const s = slotDoc.data();
      const rows = bySlot[slotDoc.id] ?? [];
      const wds = Array.isArray(s.workDetails) ? s.workDetails : [];
      const isNewSchema = wds.some((w) => typeof w?.wdId === 'string' && w.wdId.length > 0);

      let sp = 0, sc = 0;
      const tally = {};
      let failClosed = false;
      for (const {a, isP, isS} of rows) {
        if (isP) sp++;
        if (isS) sc++;
        if (!isP && !isS) continue;
        const r = resolveWdId(a, wds, isNewSchema);
        viaTally[r.via] = (viaTally[r.via] || 0) + 1;
        if (r.via === 'ambiguous' || r.via === 'unresolved') { failClosed = true; continue; }
        if (!r.wdId) continue;
        tally[r.wdId] ??= {pending: 0, confirmed: 0};
        if (isP) tally[r.wdId].pending++;
        if (isS) tally[r.wdId].confirmed++;
      }

      if ((s.pendingCount ?? 0) !== sp) {
        findings.push({kind: 'slot.pendingCount', toId, slotId: slotDoc.id,
          stored: s.pendingCount ?? null, expected: sp});
      }
      if ((s.confirmedCount ?? 0) !== sc) {
        findings.push({kind: 'slot.confirmedCount', toId, slotId: slotDoc.id,
          stored: s.confirmedCount ?? null, expected: sc});
      }

      if (failClosed) {
        findings.push({kind: 'wd.failClosed(대조 불가)', toId, slotId: slotDoc.id,
          stored: null, expected: null});
        continue; // 서버도 이 슬롯은 건드리지 않는다
      }
      const stored = s.workDetailCounts ?? {};
      const keys = new Set([...Object.keys(stored),
        ...wds.map((w) => w?.wdId).filter(Boolean)]);
      for (const k of keys) {
        wdKeysChecked++;
        const e = tally[k] ?? {pending: 0, confirmed: 0};
        const st = stored[k] ?? {};
        if ((st.pendingCount ?? 0) !== e.pending) {
          findings.push({kind: 'wd.pendingCount', toId, slotId: slotDoc.id, wdId: k,
            stored: st.pendingCount ?? null, expected: e.pending});
        }
        if ((st.confirmedCount ?? 0) !== e.confirmed) {
          findings.push({kind: 'wd.confirmedCount', toId, slotId: slotDoc.id, wdId: k,
            stored: st.confirmedCount ?? null, expected: e.confirmed});
        }
      }
    }
  }

  console.log(`## 대조 범위`);
  console.log(`- 공고 ${toSnap.size} · 슬롯 ${slotsChecked} · 업무키 ${wdKeysChecked}`);
  console.log(`- identity 해석: ${JSON.stringify(viaTally)}\n`);

  console.log(`## 결과`);
  if (findings.length === 0) {
    console.log('- mismatch 0건 (이 범위·이 시점 기준)');
  } else {
    const byKind = {};
    for (const f of findings) byKind[f.kind] = (byKind[f.kind] || 0) + 1;
    console.log(`- mismatch ${findings.length}건: ${JSON.stringify(byKind)}`);
    console.log('\n### 상위 30건');
    for (const f of findings.slice(0, 30)) {
      console.log(`- ${f.kind} to=${f.toId}` +
        (f.slotId ? ` slot=${f.slotId}` : '') + (f.wdId ? ` wd=${f.wdId}` : '') +
        ` 저장=${f.stored} 기대=${f.expected}`);
    }
  }

  if (PLAN) {
    // mismatch 가 있는 공고만 보정 대상이다 — 나머지는 부를 이유가 없다.
    const targets = new Set(findings.map((f) => f.toId));
    console.log(`\n## 보정 계획 (읽기 전용 투영 · ${startedAt})`);
    console.log(`- 보정 대상 공고 ${targets.size}개 (mismatch 가 있는 flex 공고)`);
    console.log('- 명령 단위: callableRecalculateTOStats(toId) — TO 1건씩, 멱등');
    console.log('\n| TO/slot/wdId | 필드 | 현재값 | 예상값 | 차이 이유 | 근거 원장 | 변경 |');
    console.log('|---|---|---|---|---|---|---|');
    let changed = 0, same = 0;
    for (const p of plan) {
      if (!targets.has(p.toId)) continue;
      for (const r of p.rows) {
        const isSame = String(r.stored) === String(r.expected);
        if (r.field === 'statsSourceReadAt') { changed++; } else if (isSame) { same++; } else { changed++; }
        console.log(`| ${r.scope} | ${r.field} | ${r.stored} | ${r.expected} | ` +
          `${r.why} | ${r.ledger} | ${r.field === 'statsSourceReadAt' ? '변경(기록)' :
            (isSame ? '변경없음' : '변경')} |`);
      }
    }
    console.log(`\n- 변경 ${changed}행 · 변경없음 ${same}행`);
    console.log('- 원장(applications)·계약·근태·급여: **미변경**');
  }
  process.exit(0);
})().catch((e) => {
  console.error('READ 대조 실패:', e && e.message ? e.message : e);
  process.exit(1);
});
