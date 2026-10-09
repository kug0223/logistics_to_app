/**
 * [R7-P4.4E.11B.2 §54·§55·§56] fixture 잔류 / 공유 DEV baseline 최종 확인.
 *
 *   READ ONLY + fixture 전용 정리만. 공유 데이터는 건드리지 않는다.
 */
'use strict';

const {admin, db, devBucket, PREFIX, makeChecker} = require('./r7-p44e11b2-lib');

const COLLECTIONS = ['users', 'businesses', 'applications', 'attendance',
  'notifications', 'members', 'document_corrections'];

(async () => {
  const c = makeChecker();
  console.log('프로젝트:', admin.app().options.projectId);

  // ── §54 Firestore fixture 잔류 ──────────────────────────────
  console.log('\n=== §54 Firestore fixture 잔류 ===');
  for (const col of COLLECTIONS) {
    try {
      const s = await db.collection(col).get();
      const n = s.docs.filter((d) => d.id.startsWith(PREFIX) ||
          JSON.stringify(d.data()).includes(PREFIX)).length;
      c.check(`${col} 잔류 0`, n, 0);
    } catch (e) {
      c.note(`${col} 조회 불가`, e.message.slice(0, 60));
    }
  }

  // ── §54 Storage fixture 잔류 + hold 잔류 ────────────────────
  console.log('\n=== §54 Storage fixture 잔류 / temporaryHold ===');
  const [all] = await devBucket().getFiles();
  const fx = all.filter((f) => f.name.includes(PREFIX));
  c.check('rt11b2_* object 잔류 0', fx.length, 0);
  let held = 0;
  for (const f of all) {
    if (f.metadata && f.metadata.temporaryHold === true) held++;
  }
  c.check('temporaryHold 걸린 object 0', held, 0);

  // ── §54 Auth fixture 잔류 ───────────────────────────────────
  console.log('\n=== §54 Auth fixture 잔류 ===');
  let authFx = 0; let token;
  do {
    const page = await admin.auth().listUsers(1000, token);
    authFx += page.users.filter((u) => u.uid.startsWith(PREFIX)).length;
    token = page.pageToken;
  } while (token);
  c.check('rt11b2_* Auth 계정 잔류 0', authFx, 0);

  // ── §54 test-only cleanup 필드 잔류 ────────────────────────
  console.log('\n=== §54 test-only cleanup 필드 잔류 ===');
  const us = await db.collection('users').get();
  const withQ = us.docs.filter((d) => {
    const q = d.data().bankbookCleanupPendingPaths;
    return Array.isArray(q) && q.length > 0;
  });
  c.check('cleanup 대기 보유 사용자 0', withQ.length, 0);

  // ── §54 fixture 감사 로그 — 의도적 보존, shared 와 구분 ────
  console.log('\n=== §54 fixture 감사 로그 (의도적 보존) ===');
  for (const col of ['bankbook_access_logs', 'applicant_document_access_logs']) {
    try {
      const s = await db.collection(col).get();
      const fxLogs = s.docs.filter((d) =>
        JSON.stringify(d.data()).includes(PREFIX));
      c.note(`${col}: 전체 ${s.size}건 중 fixture ${fxLogs.length}건 (보존)`,
          fxLogs.length);
    } catch (e) {
      c.note(`${col} 조회 불가`, e.message.slice(0, 60));
    }
  }

  // ── §56 공유 DEV baseline ───────────────────────────────────
  console.log('\n=== §56 공유 DEV baseline ===');
  c.check('users 문서 수 = 8 (baseline)', us.size, 8);
  const ptr = us.docs.filter((d) => typeof d.data().bankbookImagePath === 'string' &&
      d.data().bankbookImagePath).length;
  c.check('bankbookImagePath 보유 = 7 (baseline)', ptr, 7);
  const bbObjs = all.filter((f) =>
    /^users\/[^/]+\/bankbook_\d{10,}\.(jpg|jpeg|png|gif|webp|heic|heif)$/i.test(f.name));
  c.check('통장사본 object = 10 (baseline)', bbObjs.length, 10);
  c.check('users/ 하위 object = 18 (baseline)',
      all.filter((f) => f.name.startsWith('users/')).length, 18);

  // ── §49 historical residue 3건 generation 동일성 ───────────
  console.log('\n=== §49 historical residue 3건 ===');
  const EXPECTED = {
    '1790675070156872': 269302,
    '1790753696469701': 198006,
    '1790753755759625': 198006,
  };
  const refs = new Set(us.docs.map((d) => d.data().bankbookImagePath).filter(Boolean));
  const unref = bbObjs.filter((f) => !refs.has(f.name));
  c.check('미참조 통장사본 = 3건', unref.length, 3);
  for (const f of unref) {
    const [md] = await f.getMetadata();
    const g = String(md.generation);
    c.check(`generation ${g} 이 baseline 과 동일`, g in EXPECTED, true);
    c.check(`  size ${md.size} 동일`, Number(md.size), EXPECTED[g]);
  }
  c.check('자동 queue 등록 0 (어떤 사용자도 이 경로를 대기에 넣지 않았다)',
      us.docs.some((d) => {
        const q = d.data().bankbookCleanupPendingPaths;
        return Array.isArray(q) && q.some((p) => unref.some((f) => f.name === p));
      }), false);

  const {fail} = c.summary();
  console.log('\n쓰기 0건. READ ONLY 종료.');
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
