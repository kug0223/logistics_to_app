// [.4C-RUNTIME] 시나리오 본문.
//
//   각 시나리오는 BEFORE → ACTION → WRITE → READBACK → EXPECTED 순으로
//   증거를 남긴다. "callable 성공"만으로 통과시키지 않는다.
'use strict';

const H = require('./lt-4c-consolidated-runtime');
const {
  db, callAs, check, log, head, sub, st, remember,
  makeRelation, signContract, completeDay, loadApp, loadProposal,
  homeContract, bizProposals, myProposals, notificationsFor,
  inventory, reliability, effectiveStatus, eligibleOn, iso, Ts,
  BIZ, OTHER_BIZ, ADMIN, WORKER, OTHER_WORKER,
} = H;
const {kstMidnightMs, kstDateKey} = require('./r7-fixture-lib');

const err = (e) => (e && e.message ? e.message : String(e));
const fail = (p) => p.then(() => null).catch(err);

/** 제안 생성 — 관리자. */
const propose = (oldId, startOffset, endOffset, supersede) =>
  callAs(ADMIN, 'callableCreateRenewalProposal', {
    oldApplicationId: oldId,
    effectiveStartMs: kstMidnightMs(startOffset),
    effectiveEndMs: kstMidnightMs(endOffset),
    ...(supersede ? {supersedeProposalId: supersede} : {}),
  });

module.exports = async function run() {
  const T = kstDateKey(0);
  head(`.4C CONSOLIDATED RUNTIME   T(KST) = ${T}`);
  const invBefore = await inventory('BEFORE');
  const relBefore = await reliability('BEFORE');
  const homeBefore = await homeContract();
  log(`  Home 계약 섹션 ${JSON.stringify(homeBefore)}`);
  if (!H.EXECUTE) { log('\ndry-run 종료.'); return; }
  if (st.aApp) {
    head('이미 실행된 runtime — --cleanup --execute 후 재실행');
    throw new Error('runtime residue');
  }

  // ══════════════════════════════════════════════════════════════
  // SCENARIO A — 만료 전 연속 연장
  // ══════════════════════════════════════════════════════════════
  head('A. 만료 전 연속 연장 (D > T)');
  //   어제가 근무일이 되지 않도록 오늘 시작으로 만든다 — scheduler 가
  //   없는 결근을 만들면 그 자체가 FAIL 이다(§80).
  const aOld = await makeRelation('a', {
    from: 0, to: 5, startTime: '02:10', endTime: '03:10',
  });
  await signContract('a', aOld);
  let a = await loadApp(aOld);
  log(`  OLD ${aOld}`);
  log(`  기간 ${iso(a.workDate)} ~ ${iso(a.workEndDate)} · status ${a.status}`);
  check('A fixture — CONFIRMED · D > T', a.status === 'CONFIRMED' &&
      iso(a.workEndDate) === kstDateKey(5), `${a.status} / ${iso(a.workEndDate)}`);
  check('A 어제는 근무일이 아니다 — 결근 위험 없음',
      eligibleOn(a, -1) === 'BEFORE_START', eligibleOn(a, -1));

  sub('A-1. 제안 전 Home/Task');
  const aHome0 = await homeContract();
  const aMine0 = await myProposals(WORKER);
  log(`  Home ${JSON.stringify(aHome0)} · 근로자 제안 ${aMine0.length}건`);

  sub('A-2. 관리자 제안 (E = D+1)');
  const aP = await propose(aOld, 6, 36);
  remember('aProposal', aP.proposalId);
  const p = await loadProposal(aP.proposalId);
  a = await loadApp(aOld);
  log(`  proposal ${aP.proposalId} status=${p.status} E=${iso(p.effectiveStart)}`);
  check('A 제안은 PENDING', p.status === 'PENDING');
  check('A E = D+1', iso(p.effectiveStart) === kstDateKey(6), iso(p.effectiveStart));
  check('A OLD renewalDecision 은 여전히 null',
      a.renewalDecision == null, String(a.renewalDecision));
  const aNew0 = await db.collection('applications')
      .where('renewedFromApplicationId', '==', aOld).get();
  check('A 제안만으로 새 계약이 생기지 않는다', aNew0.size === 0, `${aNew0.size}건`);
  check('A 연장 기간에 좌석 없음 — 새 지원서가 없으므로', aNew0.size === 0);
  check('A 계약서도 생기지 않는다',
      (await db.collection('employment_contracts')
          .where('applicationId', '==', aOld).get()).docs
          .filter((d) => d.data().status !== 'completed').length === 0);

  sub('A-3. 제안 후 Task 이동');
  const aHome1 = await homeContract();
  const aMine1 = await myProposals(WORKER);
  const aBiz1 = await bizProposals();
  log(`  Home ${JSON.stringify(aHome1)}`);
  log(`  근로자 제안 ${aMine1.length}건 · 관리자 제안 ${aBiz1.length}건`);
  check('A 제안 전에는 관리자 할 일이었다',
      aHome0.count === homeBefore.count + 1,
      `${homeBefore.count} → ${aHome0.count}`);
  check('A 제안 후 관리자 할 일에서 빠진다 (응답 대기)',
      aHome1.count === aHome0.count - 1, `${aHome0.count} → ${aHome1.count}`);
  check('A 근로자에게 할 일이 생긴다',
      aMine1.some((x) => x.id === aP.proposalId), `${aMine1.length}건`);
  check('A 관리자 화면은 응답 대기로 본다',
      aBiz1.some((x) => x.id === aP.proposalId &&
        x.effectiveStatus === 'PENDING'));
  const aNotif = await notificationsFor(WORKER, aOld);
  log(`  근로자 알림 ${JSON.stringify(aNotif.map((n) => n.type))}`);

  sub('A-4. 근로자 수락 — 여기서 약속이 성립한다');
  const aAcc = await callAs(WORKER, 'callableAcceptRenewalProposal',
      {proposalId: aP.proposalId});
  remember('aNewApp', aAcc.newApplicationId);
  const aP2 = await loadProposal(aP.proposalId);
  const aOld2 = await loadApp(aOld);
  const aNew = await loadApp(aAcc.newApplicationId);
  log(`  NEW ${aAcc.newApplicationId} status=${aNew.status}`);
  check('A 제안 ACCEPTED', aP2.status === 'ACCEPTED');
  check('A 제안이 NEW 를 가리킨다', aP2.newApplicationId === aAcc.newApplicationId);
  check('A OLD renewalDecision = EXTEND', aOld2.renewalDecision === 'EXTEND');
  check('A 양방향 링크',
      aOld2.renewedToApplicationId === aAcc.newApplicationId &&
      aNew.renewedFromApplicationId === aOld);
  check('A NEW = CONTRACT_PENDING', aNew.status === 'CONTRACT_PENDING');

  sub('A-5. 약속 snapshot parity');
  const fields = ['selectedWorkType', 'startTime', 'endTime', 'wage',
    'wageType', 'taxDeductionType', 'payScheduleType'];
  const diffs = fields.filter((f) =>
    JSON.stringify(aNew[f]) !== JSON.stringify(p[f] ?? aOld2[f]));
  log(`  비교 ${fields.map((f) => `${f}=${aNew[f]}`).join(' · ')}`);
  check('A 제안 snapshot == NEW 약속', diffs.length === 0, diffs.join(','));
  check('A workDays 도 같다',
      JSON.stringify(aNew.workDays) === JSON.stringify(p.workDays));

  sub('A-6. 효력일 parity');
  check('A proposal.E == NEW.workDate == NEW.desiredStartDate',
      iso(p.effectiveStart) === iso(aNew.workDate) &&
      iso(aNew.workDate) === iso(aNew.desiredStartDate),
      `${iso(p.effectiveStart)} / ${iso(aNew.workDate)} / ${iso(aNew.desiredStartDate)}`);

  sub('A-7. D / E 좌석 경계');
  const eD = eligibleOn(aOld2, 5); const eD1 = eligibleOn(aOld2, 6);
  const nD = eligibleOn(aNew, 5); const nD1 = eligibleOn(aNew, 6);
  log(`  D(${kstDateKey(5)})   OLD=${eD} NEW=${nD}`);
  log(`  E(${kstDateKey(6)}) OLD=${eD1} NEW=${nD1}`);
  check('A D 는 OLD 만 근무일', eD === 'ELIGIBLE' && nD !== 'ELIGIBLE');
  check('A E 는 NEW 만 근무일', nD1 === 'ELIGIBLE' && eD1 !== 'ELIGIBLE');

  sub('A-8. 계약서 발행 → 서명 → CONFIRMED');
  const aC = await signContract('aNew', aAcc.newApplicationId);
  const aCdoc = (await db.collection('employment_contracts').doc(aC).get()).data();
  const aNew2 = await loadApp(aAcc.newApplicationId);
  log(`  contract ${aC} status=${aCdoc.status} start=${aCdoc.snapshot.contractStart}`);
  check('A 계약서 completed', aCdoc.status === 'completed');
  check('A 서명 후 NEW CONFIRMED', aNew2.status === 'CONFIRMED', aNew2.status);
  check('A Contract 시작일 == E',
      aCdoc.snapshot.contractStart === kstDateKey(6),
      aCdoc.snapshot.contractStart);
  check('A OLD 계약기간 불변',
      iso(aNew2.workEndDate) === kstDateKey(36) &&
      iso((await loadApp(aOld)).workEndDate) === kstDateKey(5));

  // ══════════════════════════════════════════════════════════════
  // SCENARIO B — 만료 후 늦은 연장
  // ══════════════════════════════════════════════════════════════
  head('B. 만료 후 늦은 연장 (D < T)');
  const bOld = await makeRelation('b', {
    from: -20, to: -5, startTime: '03:20', endTime: '04:20',
    confirmedAtOffset: -19,
  });
  await signContract('b', bOld);
  const b = await loadApp(bOld);
  log(`  OLD ${bOld} 기간 ${iso(b.workDate)} ~ ${iso(b.workEndDate)}`);
  check('B fixture — 이미 만료', iso(b.workEndDate) === kstDateKey(-5));
  check('B 어제는 근무일이 아니다 — 계약이 이미 끝났다',
      eligibleOn(b, -1) === 'AFTER_END', eligibleOn(b, -1));

  sub('B-1. 과거 시작일 요청 — 거절되어야 한다');
  const bPast = await fail(propose(bOld, -1, 30));
  log(`  응답 ${bPast}`);
  check('B 과거 E 는 서버가 거절한다',
      !!bPast && bPast.includes('오늘 이후 날짜부터'), bPast || '통과해버림');
  check('B 거절 후 제안 0건',
      (await db.collection('renewal_proposals')
          .where('oldApplicationId', '==', bOld).get()).size === 0);

  sub('B-2. 명시적 E = T+2 로 제안');
  const bP = await propose(bOld, 2, 32);
  remember('bProposal', bP.proposalId);
  const bp = await loadProposal(bP.proposalId);
  log(`  E=${iso(bp.effectiveStart)} (D+1 이었다면 ${kstDateKey(-4)})`);
  check('B 조용한 D+1 소급이 없다',
      iso(bp.effectiveStart) === kstDateKey(2) &&
      iso(bp.effectiveStart) !== kstDateKey(-4), iso(bp.effectiveStart));

  sub('B-3. 근로자 수락 후 공백 확인');
  const bAcc = await callAs(WORKER, 'callableAcceptRenewalProposal',
      {proposalId: bP.proposalId});
  remember('bNewApp', bAcc.newApplicationId);
  const bNew = await loadApp(bAcc.newApplicationId);
  check('B NEW 시작일 = E',
      iso(bNew.workDate) === kstDateKey(2) &&
      iso(bNew.desiredStartDate) === kstDateKey(2));
  const gap = [];
  for (let o = -4; o <= 1; o++) {
    const oldV = eligibleOn(b, o); const newV = eligibleOn(bNew, o);
    gap.push(`${kstDateKey(o)}:OLD=${oldV}/NEW=${newV}`);
  }
  log(`  공백 ${gap.join('  ')}`);
  check('B 공백 전 구간 근무 의무 0',
      gap.every((g) => !g.includes('=ELIGIBLE')));
  const bAtt = await db.collection('attendance')
      .where('applicationId', '==', bAcc.newApplicationId).get();
  check('B 공백에 근태가 만들어지지 않았다', bAtt.size === 0, `${bAtt.size}건`);

  // ══════════════════════════════════════════════════════════════
  // SCENARIO C — 근로자 거절
  // ══════════════════════════════════════════════════════════════
  head('C. 근로자 거절');
  const cOld = await makeRelation('c', {
    from: 0, to: 5, startTime: '04:30', endTime: '05:30',
  });
  await signContract('c', cOld);
  const cHome0 = await homeContract();
  const cP = await propose(cOld, 6, 36);
  remember('cProposal', cP.proposalId);
  const cHome1 = await homeContract();
  check('C 제안 후 관리자 할 일에서 빠진다',
      cHome1.count === cHome0.count - 1, `${cHome0.count} → ${cHome1.count}`);

  const relC0 = await reliability('  거절 전');
  await callAs(WORKER, 'callableDeclineRenewalProposal',
      {proposalId: cP.proposalId});
  const cp = await loadProposal(cP.proposalId);
  const c = await loadApp(cOld);
  const relC1 = await reliability('  거절 후');
  check('C 제안 DECLINED', cp.status === 'DECLINED');
  check('C 새 계약 0건',
      (await db.collection('applications')
          .where('renewedFromApplicationId', '==', cOld).get()).size === 0);
  check('C OLD renewalDecision 은 null — 거절은 관리자 결정이 아니다',
      c.renewalDecision == null, String(c.renewalDecision));
  check('C 신뢰도 변화 없음',
      relC1.noShowCount === relC0.noShowCount &&
      relC1.recentNoShowCount === relC0.recentNoShowCount &&
      relC1.restricted === relC0.restricted);
  const cHome2 = await homeContract();
  check('C 거절 후 관리자 할 일이 돌아온다',
      cHome2.count === cHome0.count, `${cHome1.count} → ${cHome2.count}` +
      ' (제안 전과 같은 수)');
  const cMine = await myProposals(WORKER);
  check('C 근로자 할 일에서 사라진다',
      !cMine.some((x) => x.id === cP.proposalId));
  const cAdminNotif = await notificationsFor(ADMIN, cOld);
  log(`  관리자 알림 ${JSON.stringify(cAdminNotif.map((n) => n.type))}`);
  check('C 관리자에게 거절 알림',
      cAdminNotif.some((n) => n.type === 'renewalDeclined'));
  check('C 해지·퇴사·결근 알림 없음',
      !cAdminNotif.some((n) => ['contractTerminating', 'resignApproved',
        'terminationApproved'].includes(n.type)));

  // ══════════════════════════════════════════════════════════════
  // SCENARIO D — derived STALE → 재제안
  // ══════════════════════════════════════════════════════════════
  head('D. derived STALE → 재제안');
  //   오늘 시작 + 이미 지난 근무 시작시각 → 저장은 PENDING, 유효는 STALE.
  const dOld = await makeRelation('d', {
    from: -20, to: -3, startTime: '00:05', endTime: '01:05',
    confirmedAtOffset: -19,
  });
  await signContract('d', dOld);
  const dP = await propose(dOld, 0, 30);
  remember('dProposal', dP.proposalId);
  const dp = await loadProposal(dP.proposalId);
  const eff = effectiveStatus(dp, new Date());
  log(`  proposal ${dP.proposalId} persisted=${dp.status} effective=${eff}`);
  log(`  E=${iso(dp.effectiveStart)} startTime=${dp.startTime} now=${new Date(Date.now() + 9 * 3600e3).toISOString().slice(11, 16)} KST`);
  check('D 저장은 PENDING · 유효는 STALE',
      dp.status === 'PENDING' && eff === 'STALE', `${dp.status}/${eff}`);

  sub('D-1. 근로자 행동이 사라진다');
  const dMine = await myProposals(WORKER);
  check('D 근로자 할 일에 없다', !dMine.some((x) => x.id === dP.proposalId));
  const dAcc = await fail(callAs(WORKER, 'callableAcceptRenewalProposal',
      {proposalId: dP.proposalId}));
  const dDec = await fail(callAs(WORKER, 'callableDeclineRenewalProposal',
      {proposalId: dP.proposalId}));
  log(`  accept  → ${dAcc}`);
  log(`  decline → ${dDec}`);
  check('D 수락 거절됨', !!dAcc && dAcc.includes('시작일이 지났'), dAcc || '통과');
  check('D 거절도 거절됨', !!dDec && dDec.includes('더 이상 응답할 수 없'),
      dDec || '통과');

  sub('D-2. 관리자 할 일로 돌아온다');
  const dBiz = await bizProposals();
  const dEntry = dBiz.find((x) => x.id === dP.proposalId);
  check('D 관리자 reader 도 STALE 로 본다',
      dEntry && dEntry.effectiveStatus === 'STALE',
      dEntry ? dEntry.effectiveStatus : '없음');

  sub('D-3. 새 E 로 재제안');
  const dP2 = await propose(dOld, 1, 31);
  remember('dProposal2', dP2.proposalId);
  const dp1 = await loadProposal(dP.proposalId);
  const dp2 = await loadProposal(dP2.proposalId);
  const dOldApp = await loadApp(dOld);
  log(`  옛 제안 ${dp1.status} staledAt=${dp1.staledAt ? '있음' : '없음'}`);
  log(`  새 제안 ${dp2.status} E=${iso(dp2.effectiveStart)}`);
  check('D 옛 제안이 저장 수준에서도 STALE', dp1.status === 'STALE');
  check('D staledAt 기록', !!dp1.staledAt);
  check('D 응답하지 않은 제안에 respondedAt 없음', !dp1.respondedAt);
  check('D SUPERSEDED 로 섞지 않았다', !dp1.supersededByProposalId);
  check('D 새 제안 PENDING', dp2.status === 'PENDING');
  check('D OLD renewalDecision 여전히 null', dOldApp.renewalDecision == null);
  check('D 포인터가 새 제안을 가리킨다',
      dOldApp.renewalProposalId === dP2.proposalId);
  const dActive = (await db.collection('renewal_proposals')
      .where('oldApplicationId', '==', dOld)
      .where('status', '==', 'PENDING').get()).size;
  check('D 유효한 제안은 정확히 하나', dActive === 1, `${dActive}건`);

  sub('D-4. 옛 stale 제안으로는 수락할 수 없다');
  const dOldAcc = await fail(callAs(WORKER, 'callableAcceptRenewalProposal',
      {proposalId: dP.proposalId}));
  log(`  → ${dOldAcc}`);
  check('D 옛 제안 수락 거절', !!dOldAcc, dOldAcc || '통과해버림');
  check('D 옛 제안에서 만들어진 계약 0건',
      (await db.collection('applications')
          .where('renewedFromApplicationId', '==', dOld).get()).size === 0);

  sub('D-5. 중복 수락');
  const dAcc2 = await callAs(WORKER, 'callableAcceptRenewalProposal',
      {proposalId: dP2.proposalId});
  remember('dNewApp', dAcc2.newApplicationId);
  const dDup = await fail(callAs(WORKER, 'callableAcceptRenewalProposal',
      {proposalId: dP2.proposalId}));
  const dNewCount = (await db.collection('applications')
      .where('renewedFromApplicationId', '==', dOld).get()).size;
  log(`  두 번째 수락 → ${dDup}`);
  check('D 중복 수락해도 새 계약은 하나', dNewCount === 1, `${dNewCount}건`);

  // ══════════════════════════════════════════════════════════════
  // 옛 우회로 · 권한
  // ══════════════════════════════════════════════════════════════
  head('LEGACY BYPASS · 권한');
  const legacy = await fail(callAs(ADMIN, 'callableCreateContractRenewal', {
    originalApplicationId: cOld,
    newStartDateMs: kstMidnightMs(6), newEndDateMs: kstMidnightMs(36),
  }));
  log(`  callableCreateContractRenewal → ${legacy}`);
  check('옛 writer 는 막혀 있다',
      !!legacy && legacy.includes('근무자의 수락이 필요'), legacy || '통과해버림');
  check('옛 writer 로 새 계약 0건',
      (await db.collection('applications')
          .where('renewedFromApplicationId', '==', cOld).get()).size === 0);

  sub('권한');
  const wrongWorker = await fail(callAs(OTHER_WORKER,
      'callableAcceptRenewalProposal', {proposalId: bP.proposalId}));
  log(`  다른 근로자 수락 → ${wrongWorker}`);
  check('다른 근로자는 수락할 수 없다',
      !!wrongWorker && wrongWorker.includes('본인의 제안만'),
      wrongWorker || '통과해버림');
  const crossBiz = await fail(callAs(ADMIN, 'callableGetRenewalProposalsByBiz',
      {businessId: OTHER_BIZ}));
  log(`  타 사업장 조회 → ${crossBiz}`);
  check('타 사업장 제안은 볼 수 없다', !!crossBiz, crossBiz || '통과해버림');
  const workerReads = await fail(callAs(OTHER_WORKER,
      'callableGetRenewalProposalsByBiz', {businessId: BIZ}));
  check('근로자는 사업장 제안 목록을 볼 수 없다',
      !!workerReads, workerReads || '통과해버림');
  // rules — 클라이언트 직접 쓰기 차단은 Admin SDK 로 증명할 수 없다.
  log('  rules 직접 쓰기 차단: Admin SDK 는 rules 를 지나지 않는다 → NOT SEEN');
  log('  SubAdmin canManageContract 경로: DEV 계정 하나뿐 → NOT SEEN');

  // ══════════════════════════════════════════════════════════════
  // SCENARIO H — 수락 전후 근태 경계 · 실제 출근
  // ══════════════════════════════════════════════════════════════
  head('H. 수락 전후 근태 경계 · 실제 출근');
  //   E = 오늘. 지금(KST)보다 뒤의 근무 시작시각을 써야 제안이 STALE 이
  //   되지 않는다 — 시각은 실행 시점에서 정한다.
  //   동시에 출근 창(시작 30분 전부터)이 이미 열려 있어야 실제 출근까지
  //   볼 수 있다. 그래서 시작 시각을 **지금 + 15분**으로 잡는다 —
  //   제안 시점에는 아직 오지 않았고(PENDING), 출근 시점에는 창이 열려
  //   있다. device clock 이 아니라 KST 로 계산한다.
  const kstNow = new Date(Date.now() + 9 * 3600e3);
  const hh = (d) => `${String(d.getUTCHours()).padStart(2, '0')}:` +
    `${String(d.getUTCMinutes()).padStart(2, '0')}`;
  const startAt = new Date(kstNow.getTime() + 15 * 60e3);
  const hStart = hh(startAt);
  const hEnd = hh(new Date(startAt.getTime() + 60 * 60e3));
  log(`  지금 ${hh(kstNow)} KST · 근무시간 ${hStart}~${hEnd}` +
      ' (출근 창은 시작 30분 전부터)');
  if (startAt.getUTCDate() !== kstNow.getUTCDate()) {
    throw new Error('자정을 넘는 시각 — 다른 시간대에 실행해야 한다.');
  }
  //   기간을 짧게 잡는다 — DEV 근로자에게는 과거 날짜에 확정된 근무가
  //   이미 있어서, 긴 기간을 잡으면 시간 겹침으로 지원이 거절된다.
  const hOld = await makeRelation('h', {
    from: -3, to: -1, startTime: hStart, endTime: hEnd,
    confirmedAtOffset: -3,
  });
  await signContract('h', hOld);
  //   마지막 근무일을 완결시킨다 — 없는 결근이 만들어지면 FAIL 이다.
  await completeDay(hOld, -1);
  const hOldApp = await loadApp(hOld);
  check('H fixture — 어제 종료 · 마지막 날 근무 완결',
      iso(hOldApp.workEndDate) === kstDateKey(-1));

  sub('H-1. 수락 전 — 아무 의무도 없다');
  const hP = await propose(hOld, 0, 30);
  remember('hProposal', hP.proposalId);
  const hp = await loadProposal(hP.proposalId);
  const hEff = effectiveStatus(hp, new Date());
  log(`  proposal ${hP.proposalId} E=${iso(hp.effectiveStart)} effective=${hEff}`);
  check('H 제안이 아직 유효하다', hEff === 'PENDING', hEff);
  const hNewBefore = await db.collection('applications')
      .where('renewedFromApplicationId', '==', hOld).get();
  check('H 수락 전 새 계약 0건 — 출근할 대상 자체가 없다',
      hNewBefore.size === 0, `${hNewBefore.size}건`);
  //   scheduler 의 장기 결근 population 을 그대로 흉내낸다.
  const nsPop = await db.collection('applications')
      .where('status', 'in', ['CONFIRMED', 'CONTRACT_PENDING'])
      .where('workEndDate', '>=', Ts(kstMidnightMs(-1))).limit(499).get();
  const nsMine = nsPop.docs.filter(
      (d) => d.data().renewedFromApplicationId === hOld);
  check('H 제안만으로는 결근 후보도 되지 않는다', nsMine.length === 0);

  sub('H-2. 근로자 수락 → 오늘부터 유효');
  const hAcc = await callAs(WORKER, 'callableAcceptRenewalProposal',
      {proposalId: hP.proposalId});
  remember('hNewApp', hAcc.newApplicationId);
  const hNew = await loadApp(hAcc.newApplicationId);
  log(`  NEW ${hAcc.newApplicationId} status=${hNew.status} ` +
      `start=${iso(hNew.workDate)}`);
  check('H NEW CONTRACT_PENDING · 시작 오늘',
      hNew.status === 'CONTRACT_PENDING' &&
      iso(hNew.workDate) === kstDateKey(0));
  check('H 오늘이 근무일이 된다 — 수락 이후에만',
      eligibleOn(hNew, 0) === 'ELIGIBLE', eligibleOn(hNew, 0));
  check('H 어제는 여전히 근무일이 아니다',
      eligibleOn(hNew, -1) === 'BEFORE_START', eligibleOn(hNew, -1));

  sub('H-3. 실제 출근 — 계약서 서명 전이어도 약속은 이미 있다');
  //   출근은 GPS 또는 비콘만 허용된다 — 사업장 좌표를 그대로 쓴다.
  const bizDoc = (await db.collection('businesses').doc(BIZ).get()).data();
  const hIn = await fail(callAs(WORKER, 'callableCheckIn', {
    applicationId: hAcc.newApplicationId, businessId: BIZ,
    businessName: '위워커', workType: '사무업무',
    workDateMs: kstMidnightMs(0),
    method: 'gps',
    latitude: bizDoc.latitude, longitude: bizDoc.longitude,
  }));
  const hAttId =
    `${hAcc.newApplicationId}_${kstDateKey(0).replace(/-/g, '')}`;
  const hAtt = await db.collection('attendance').doc(hAttId).get();
  if (hIn) {
    log(`  callableCheckIn → ${hIn}`);
    check('H 실제 출근 — 서버가 거절했다', false, hIn);
  } else {
    const v = hAtt.data();
    log(`  attendance ${hAttId.slice(-30)} status=${v && v.status}`);
    check('H 출근 기록이 만들어진다', hAtt.exists);
    check('H 기록의 주인이 일치한다',
        hAtt.exists && v.userId === WORKER &&
        v.applicationId === hAcc.newApplicationId);
    check('H 계약서 서명 전에도 허용된다 — Policy C',
        hNew.status === 'CONTRACT_PENDING');
  }

  // ══════════════════════════════════════════════════════════════
  // scheduler 의존 시나리오 — 이번 실행에서 볼 수 없다
  // ══════════════════════════════════════════════════════════════
  head('E / F / G / D-15 — NOT SEEN');
  log('  processContractRenewalChecks 는 masterScheduler 안에서');
  log('  hour === 0 && minute < 10 (KST 자정) 에만 실행된다.');
  log(`  지금은 ${new Date(Date.now() + 9 * 3600e3).toISOString().slice(11, 16)}` +
      ' KST 이고, 이 환경에는 gcloud 가 없어 강제 실행할 수 없다.');
  log('  제품에 test-only 우회로를 추가하는 것은 금지되어 있다(§56).');
  log('');
  log('  → 계약 종료 예정(D-15) · 계약 종료(D+1) · 연속 연장 억제 ·');
  log('    미래 시작 문구 · 알림 dedupe 는 NOT SEEN 으로 남긴다.');
  log('    VERIFIED 로 올리지 않는다(§94).');

  head('요약');
  const invAfter = await inventory('AFTER ');
  const relAfter = await reliability('AFTER ');
  log(`  기준선 ${JSON.stringify(invBefore)}`);
  check('runtime 중 신뢰도 오염 없음',
      relAfter.noShowCount === relBefore.noShowCount &&
      relAfter.recentNoShowCount === relBefore.recentNoShowCount &&
      relAfter.restricted === relBefore.restricted,
      `${JSON.stringify(relBefore)} → ${JSON.stringify(relAfter)}`);
  void invAfter;
  log('\n  정리: --cleanup --execute');
};
