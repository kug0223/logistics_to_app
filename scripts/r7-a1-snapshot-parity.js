/**
 * [R7-GOLDEN-PATH-DEV-E2E.1 §4] ContractService._buildSnapshot parity.
 *
 *   §4 는 "Dart 가 만든 payload 와 직전 CF 에서 성공한 canonical payload 를
 *   비교" 하라고 한다. Dart 를 실행할 Flutter 런타임이 이 기기에 없으므로
 *   (Visual Studio 없음 / web 타깃 없음 / APK 는 사용자 몫) 대신
 *   **_buildSnapshot 의 매핑 규칙을 그대로 적용해 DEV 원본 문서에서
 *   기대값을 다시 계산**하고, DEV 에 저장된 snapshot 과 필드별로 비교한다.
 *
 *   이것은 "Dart 가 실행됐다" 는 증거가 아니다. "직전 Phase 가 보낸 payload 가
 *   Dart 가 보낼 값과 같았는가" 를 재는 것이고, 다르면 그 필드를 정확히
 *   드러낸다. 보고에 그 등급 그대로 적는다.
 */
'use strict';
const lib = require('./r7-fixture-lib');
const {db} = lib;

const iso = (ms) => new Date(ms + 9 * 3600000).toISOString().slice(0, 10);

(async () => {
  const G = require('../.goldenpath.json');
  const c = (await db.collection('employment_contracts').doc(G.contractId)
    .get()).data();
  const app = (await db.collection('applications').doc(G.applicationId).get())
    .data();
  const biz = (await db.collection('businesses').doc(G.businessId).get()).data();
  const worker = (await db.collection('users').doc(G.applicantUid).get()).data();
  const slot = (await db.collection('tos').doc(G.toId)
    .collection('slots').doc(G.slotId).get()).data();
  const wdRaw = (slot.workDetails || []).find((w) => w.wdId === G.wdId) || {};

  // _withPromisedWage — 약속 snapshot 이 있으면 임금 조건 전체를 약속 버전으로.
  const hasSnap = app.baseHourlyWage !== undefined ||
    app.breakMinutes !== undefined || app.taxDeductionType !== undefined;
  const wd = {
    ...wdRaw,
    wage: app.wage,
    wageType: app.wageType ?? wdRaw.wageType,
    ...(hasSnap ? {
      baseHourlyWage: app.baseHourlyWage ?? null,
      breakMinutes: app.breakMinutes ?? wdRaw.breakMinutes ?? 0,
      taxDeductionType: app.taxDeductionType ?? wdRaw.taxDeductionType,
    } : {}),
  };
  console.log('지원서 약속 snapshot 존재:', hasSnap);

  // worker.officialName — 외국인이면 legalName, 아니면 name
  const officialName = (worker.isForeign === true && worker.legalName)
    ? worker.legalName : worker.name;
  const joinAddr = (a, b) => [a, b].filter((x) => typeof x === 'string' && x)
    .join(' ').trim();

  // _buildSnapshot 의 매핑을 그대로 적용한 기대값
  const expected = {
    businessName: biz.name,
    businessAddress: joinAddr(biz.address, biz.detailAddress),
    businessPhone: biz.phone ?? null,
    ownerName: biz.ownerName ?? '',
    workerName: officialName,
    workerBirthDate: worker.birthDate ?
      iso(worker.birthDate.toMillis()) : null,
    workerPhone: worker.phone ?? null,
    workerAddress: joinAddr(worker.address, worker.detailAddress) || null,
    workType: wd.workType,
    workPlace: biz.address,
    isLongTerm: false,
    contractStart: null, contractEnd: null,
    startTime: wd.startTime, endTime: wd.endTime,
    breakMinutes: wd.breakMinutes ?? 0,
    wage: wd.wage, wageType: wd.wageType,
    wagePaymentDay: biz.wagePaymentDay ?? null,
    baseHourlyWage: wd.baseHourlyWage ?? null,
  };

  const stored = c.snapshot;
  console.log('\n=== snapshot 필드별 대조 (기대 = _buildSnapshot 매핑) ===');
  const diffs = [];
  for (const [k, v] of Object.entries(expected)) {
    const s = stored[k];
    const same = JSON.stringify(s ?? null) === JSON.stringify(v ?? null);
    if (!same) diffs.push(k);
    const show = (x) => x === null || x === undefined ? '(없음)' :
      (typeof x === 'string' && /^0?1[0-9-]{7,}$/.test(x) ? '(연락처 마스킹)' :
        JSON.stringify(x));
    console.log(' ', same ? 'OK  ' : 'DIFF', k.padEnd(18),
      same ? show(v) : `저장=${show(s)}  기대=${show(v)}`);
  }

  console.log('\n=== 서버 권위 필드 ===');
  for (const k of ['payScheduleType', 'payScheduleDay', 'payScheduleTime']) {
    console.log(' ', k.padEnd(18), JSON.stringify(stored[k] ?? null),
      '(CF 가 지원서 약속에서 주입)');
  }
  console.log('  paymentMethod     ', JSON.stringify(stored.paymentMethod),
    '(모델 기본값)');

  console.log('\n=== 그 밖의 identity ===');
  const checks = {
    applicationId: [c.applicationId, G.applicationId],
    businessId: [c.businessId, G.businessId],
    workerId: [c.workerId, G.applicantUid],
    toId: [c.toId, G.toId],
    workDetailId: [c.workDetailId, G.wdId],
    templateId: [c.templateId, c.templateId],
    'slots[0].workDate': [c.slots[0].workDate, G.dateStr],
    'slots[0].wage': [c.slots[0].wage, app.wage],
  };
  for (const [k, [a, b]] of Object.entries(checks)) {
    console.log(' ', JSON.stringify(a) === JSON.stringify(b) ? 'OK  ' : 'DIFF',
      k.padEnd(18), JSON.stringify(a) === JSON.stringify(b) ? '' :
        `저장=${a} 기대=${b}`);
  }

  console.log('\n차이 난 snapshot 필드:', diffs.length ? diffs.join(', ') : '없음');
  process.exit(0);
})().catch((e) => { console.error('실패:', e.message); process.exit(1); });
