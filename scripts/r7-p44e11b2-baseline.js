/**
 * [R7-P4.4E.11B.2 §22·§23] DEV 통장사본 baseline — READ ONLY. 쓰기 0.
 *
 *   세기만 한다. backfill·repair·cleanup·queue 등록 모두 하지 않는다.
 *   historical residue 3건은 metadata 만 읽는다 — 내용 열람 금지(§23).
 */
'use strict';

const {admin, db, devBucket} = require('./r7-fixture-lib');

/** 서버 술어와 같은 모양. 여기서는 판정만 하고 쓰지 않는다. */
function isBankbookPath(uid, p) {
  if (typeof uid !== 'string' || !uid || uid.includes('/') || uid.includes('..')) return false;
  if (typeof p !== 'string' || !p || p.length > 500) return false;
  const prefix = `users/${uid}/`;
  if (!p.startsWith(prefix)) return false;
  const name = p.slice(prefix.length);
  if (name.includes('/') || name.includes('..')) return false;
  return /^bankbook_\d{10,}\.(jpg|jpeg|png|gif|webp|heic|heif)$/i.test(name);
}

/** URL 이면 경로로 환원한다. 서버 resolver 와 같은 규칙. */
function resolveBankbook(uid, raw) {
  if (typeof raw !== 'string' || !raw) return null;
  let c = raw;
  const m = raw.match(/\/o\/([^?#]+)/);
  if (m) { try { c = decodeURIComponent(m[1]); } catch (_) { return null; } }
  return isBankbookPath(uid, c) ? c : null;
}

const mask = (s) => (typeof s === 'string' && s.length > 10
  ? s.slice(0, 6) + '…' + s.slice(-4) : s);

(async () => {
  console.log('프로젝트:', admin.app().options.projectId);
  console.log('버킷:', devBucket().name);
  console.log('측정 시각:', new Date().toISOString());

  // ── Firestore 쪽 포인터 분포 ────────────────────────────────
  let pathCount = 0, urlCount = 0, poisoned = 0, bothCount = 0;
  let pendingNonEmpty = 0, pendingTotalEntries = 0;
  const referenced = new Set();
  const poisonedUids = [];
  const pendingUids = [];

  const snap = await db.collection('users').get();
  for (const d of snap.docs) {
    const u = d.data();
    const p = u.bankbookImagePath;
    const url = u.bankbookImageUrl;
    if (typeof p === 'string' && p) pathCount++;
    if (typeof url === 'string' && url) urlCount++;
    if (typeof p === 'string' && p && typeof url === 'string' && url) bothCount++;
    // canonical current 포인터가 통장사본 네임스페이스인가
    if (typeof p === 'string' && p) {
      const ok = resolveBankbook(d.id, p);
      if (ok === null) { poisoned++; poisonedUids.push(mask(d.id)); } else referenced.add(ok);
    }
    if (typeof url === 'string' && url) {
      const ok = resolveBankbook(d.id, url);
      if (ok !== null) referenced.add(ok);
    }
    const q = u.bankbookCleanupPendingPaths;
    if (Array.isArray(q) && q.length > 0) {
      pendingNonEmpty++;
      pendingTotalEntries += q.length;
      pendingUids.push(mask(d.id) + ':' + q.length);
    }
  }

  console.log('\n=== §22 Firestore 포인터 ===');
  console.log('  users 문서 수            =', snap.size, '건');
  console.log('  bankbookImagePath 보유   =', pathCount, '건');
  console.log('  bankbookImageUrl 보유    =', urlCount, '건');
  console.log('  path+url 동시 보유       =', bothCount, '건');
  console.log('  poisoned current 포인터  =', poisoned, '건',
      poisoned ? '→ ' + poisonedUids.join(', ') : '');
  console.log('  cleanup 대기 보유 사용자 =', pendingNonEmpty, '건 / 항목 합계', pendingTotalEntries,
      pendingNonEmpty ? '→ ' + pendingUids.join(', ') : '');

  // ── Storage 쪽 object 분포 ──────────────────────────────────
  const [files] = await devBucket().getFiles({prefix: 'users/'});
  const bankbookObjs = files.filter((f) => {
    const m = f.name.match(/^users\/([^/]+)\/(.+)$/);
    return m && isBankbookPath(m[1], f.name);
  });
  const unref = bankbookObjs.filter((f) => !referenced.has(f.name));
  const ref = bankbookObjs.filter((f) => referenced.has(f.name));

  console.log('\n=== §22 Storage ===');
  console.log('  users/ 하위 object 총수       =', files.length, '건');
  console.log('  통장사본 네임스페이스 object  =', bankbookObjs.length, '건');
  console.log('  참조됨(current 포인터)        =', ref.length, '건');
  console.log('  미참조                        =', unref.length, '건');

  // ── §23 historical residue metadata only ────────────────────
  console.log('\n=== §23 미참조 object metadata (내용 열람 0) ===');
  for (const f of unref) {
    const [md] = await f.getMetadata();
    const owner = f.name.split('/')[1];
    console.log('  path=users/' + mask(owner) + '/' + f.name.split('/').slice(2).join('/'),
        '| generation=' + md.generation,
        '| size=' + md.size,
        '| timeCreated=' + md.timeCreated,
        '| updated=' + md.updated);
  }

  // ── fixture prefix 사전 점검 ────────────────────────────────
  const fx = files.filter((f) => f.name.includes('rt11b2_'));
  const fxUsers = snap.docs.filter((d) => d.id.startsWith('rt11b2_'));
  console.log('\n=== fixture prefix 사전 잔류 ===');
  console.log('  rt11b2_* Storage =', fx.length, '건 / Firestore users =', fxUsers.length, '건');

  console.log('\n쓰기 0건. READ ONLY 종료.');
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
