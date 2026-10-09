/**
 * [R7-LEGAL.DEPLOY §14~§16] 대표 1명에게만 실제 legacy 재동의를 수행한다.
 *
 *   §25 금지: 8명 일괄 consent mutation. 여기서는 **한 명**만 건드린다.
 *   선택 약관(marketing)은 **거부**로 보낸다 — 자동 true 가 되지 않는지 본다.
 *
 *   PII 를 출력하지 않는다(uid 는 앞 6자만).
 */
'use strict';

const lib = require('./r7-fixture-lib');
const {db} = lib;

const unwrap = (r) => (r && (r.result ?? r.data)) ?? r;

(async () => {
  // ── 대표 1명 고르기: USER 이면서 legacy 인 사람 ────────────────
  const users = await db.collection('users').where('role', '==', 'USER').get();
  let target = null;
  for (const d of users.docs) {
    const r = unwrap(await lib.callAs(d.id, 'callableGetLegalReadiness', {}));
    if (r.status === 'LEGACY_CONSENT_UNKNOWN') { target = {uid: d.id, r}; break; }
  }
  if (!target) throw new Error('legacy USER 를 찾지 못했다');
  const uid = target.uid;
  console.log('대표 사용자:', uid.slice(0, 6) + '…');
  console.log('  이전 상태:', target.r.status,
    '| legacy', target.r.legacyUnknown.length,
    '| optional', target.r.optionalUnanswered.length);

  // ── 이전 증거 상태 ─────────────────────────────────────────────
  const beforeEvents = await db.collection('users').doc(uid)
    .collection('consentEvents').get();
  const beforeDoc = await db.collection('users').doc(uid).get();
  const beforeConsent = beforeDoc.data()?.termsConsent ?? {};
  const beforeConsentAt = beforeDoc.data()?.termsConsentAt ?? null;
  console.log('  이전 consentEvents:', beforeEvents.size);
  console.log('  이전 projection 항목:', Object.keys(beforeConsent).length,
    '| termsConsentAt:', beforeConsentAt ? '있음' : '없음');

  // ── 클라이언트가 보낼 payload 를 그대로 구성 ───────────────────
  //   항목이 발행본을 가리키는데 기록에 발행본 id 가 없으면 "다시 받아야
  //   하는 것" 이다(TermsConsentPlan.recordFor 와 같은 규칙).
  const terms = await db.collection('app_settings').doc('legal_terms').get();
  const items = (terms.data()?.items ?? []).filter((i) => i?.isActive !== false);
  const record = {};
  for (const it of items) {
    const prev = beforeConsent[String(it.id)];
    const same = prev && prev.version === it.version &&
      prev.revisionId === it.revisionId;
    if (same) continue;
    // 필수는 동의, 선택(marketing)은 **거부**.
    record[String(it.id)] = {
      agreed: it.isRequired !== false,
      version: String(it.version),
    };
  }
  console.log('\n보낼 항목:', Object.keys(record).length,
    '| marketing:', record['marketing_consent']?.agreed);

  await lib.callAs(uid, 'callableRecordTermsConsent',
    {consentRecord: record, source: 'reconsent'});

  // ── §15 증거 검증 ──────────────────────────────────────────────
  console.log('\n=== §15 동의 증거 ===');
  const afterEvents = await db.collection('users').doc(uid)
    .collection('consentEvents').get();
  console.log('  consentEvents:', beforeEvents.size, '→', afterEvents.size);
  let okEvents = 0;
  afterEvents.forEach((e) => {
    const d = e.data();
    const ok = typeof d.revisionId === 'string' && d.revisionId.length > 0 &&
      typeof d.version === 'string' && d.agreedAt &&
      typeof d.requiredAtConsentTime === 'boolean' && d.source === 'reconsent';
    if (ok) okEvents++;
    else console.log('    미흡한 event:', JSON.stringify(Object.keys(d)));
  });
  console.log('  필드 완비 event:', okEvents, '/', afterEvents.size);

  const afterDoc = await db.collection('users').doc(uid).get();
  const afterConsent = afterDoc.data()?.termsConsent ?? {};
  let withRev = 0;
  for (const it of items) {
    const c = afterConsent[String(it.id)];
    if (c?.revisionId === it.revisionId) withRev++;
  }
  console.log('  projection 이 발행본을 가리킴:', withRev, '/', items.length);

  // §16 선택 거부 보존
  const mk = afterConsent['marketing_consent'];
  console.log('\n=== §16 선택 거부 ===');
  console.log('  marketing agreed =', mk?.agreed,
    mk?.agreed === false ? '(거부 보존 OK)' : '(**자동 true FAIL**)');
  const mkEvent = afterEvents.docs
    .map((d) => d.data())
    .find((d) => d.itemId === 'marketing_consent');
  console.log('  marketing event agreed =', mkEvent?.agreed);

  // 과거를 꾸며내지 않았는가 — 이전에 없던 "과거 시각" 이 생기지 않았는지.
  const times = afterEvents.docs.map((d) => d.data().agreedAt?.toMillis())
    .filter(Boolean);
  const now = Date.now();
  const anyBackdated = times.some((t) => t < now - 10 * 60 * 1000);
  console.log('  과거로 소급된 event:', anyBackdated ? '**있음 FAIL**' : '없음');

  // ── 상태 재조회 ────────────────────────────────────────────────
  const after = unwrap(await lib.callAs(uid, 'callableGetLegalReadiness', {}));
  console.log('\n=== 재조회 ===');
  console.log('  이후 상태:', after.status,
    '| required', after.reconsentRequired.length,
    '| legacy', after.legacyUnknown.length,
    '| optional', after.optionalUnanswered.length);
  console.log('  홈 할 일 사라짐:',
    (after.status === 'CURRENT' || after.status === 'OPTIONAL_UNANSWERED') ?
      'YES' : 'NO');

  // ── 다른 사용자는 건드리지 않았다 ──────────────────────────────
  let others = 0;
  for (const d of users.docs) {
    if (d.id === uid) continue;
    const r = unwrap(await lib.callAs(d.id, 'callableGetLegalReadiness', {}));
    if (r.status === 'LEGACY_CONSENT_UNKNOWN') others++;
  }
  console.log('\n  나머지 USER 중 여전히 LEGACY:', others, '(일괄 변경 없음 확인)');
  process.exit(0);
})().catch((e) => {
  console.error('실패:', e.message);
  process.exit(1);
});
