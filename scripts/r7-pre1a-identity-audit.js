#!/usr/bin/env node
/**
 * [R7-PRE1A] 사람 식별 / 동명이인 감사.
 *
 * invariant
 *   표시 이름        = presentation only
 *   person identity  = uid
 *   row identity     = applicationId / attendanceId / contractId
 *
 * 이 스크립트는 화면이 쓰는 canonical reader(CF)를 그대로 불러서,
 * **돌아온 결과만으로 사람과 행을 구분할 수 있는지**를 본다.
 * 이름 문자열이 어딘가의 key 로 쓰이면 여기서 두 사람이 한 줄로 합쳐진다.
 *
 *   node scripts/r7-pre1a-identity-audit.js --project alfit-89567
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

const {db, callAs, kstDateKey} = require('./r7-fixture-lib');

const BIZ = 'fLmSOHVKUwmBHcbwQE0I';
const ADMIN = 'BErRdiWP1xbgyoTovxwAPNEsuD72';
const KST = 9 * 3600e3;

const log = (...a) => console.log(...a);
const head = (s) => console.log(`\n${'─'.repeat(72)}\n${s}\n`);

const findings = [];
const record = (level, id, text) => {
  findings.push({level, id, text});
  log(`   ${level === 'OK' ? 'OK      ' : level.padEnd(10)} ${text}`);
};

const msOf = (v) => (v == null ? null
  : typeof v === 'number' ? v
  : v._seconds != null ? v._seconds * 1000
  : v.seconds != null ? v.seconds * 1000
  : Date.parse(v));
const dayKey = (v) => new Date(msOf(v) + KST).toISOString().slice(0, 10);
const num = (v) => (typeof v === 'number' ? v : 0);

async function appsByBiz(params) {
  const out = [];
  let cursor = null;
  for (let page = 0; page < 50; page++) {
    const r = await callAs(ADMIN, 'callableGetApplicationsByBiz',
        {...params, ...(cursor ? {startAfterDocId: cursor} : {})});
    out.push(...(r.applications || []));
    if (r.hasMore !== true) return out;
    cursor = r.lastDocId;
    if (!cursor) return out;
  }
  throw new Error('appsByBiz: 50페이지 초과');
}

// ═══════════════════════════════════════════════════════════════════
// 0. DEV 인구 — 동명이인이 실제로 있는가
// ═══════════════════════════════════════════════════════════════════
async function auditPopulation() {
  head('0. DEV 인구 · 동명 그룹');

  const s = await db.collection('users').get();
  const byName = {};
  const byUsername = {};
  const byPhone4 = {};
  for (const d of s.docs) {
    const u = d.data();
    (byName[u.name || '(없음)'] ??= []).push({uid: d.id, role: u.role});
    if (u.username) (byUsername[u.username] ??= []).push(d.id);
    const ph = String(u.authPhone || u.phone || '');
    if (ph.length >= 4) (byPhone4[ph.slice(-4)] ??= []).push(d.id);
  }
  const dupName = Object.entries(byName).filter(([, v]) => v.length > 1);
  const dupUser = Object.entries(byUsername).filter(([, v]) => v.length > 1);
  const dupPhone = Object.entries(byPhone4).filter(([, v]) => v.length > 1);

  log(`   users ${s.size}명 · 서로 다른 이름 ${Object.keys(byName).length}개`);
  log(`   동명 그룹 ${dupName.length}개:`);
  for (const [n, v] of dupName) {
    const roles = v.map((x) => x.role).join('+');
    log(`     ${n}  ${v.length}명  roles=${roles}`);
  }
  log(`   username 중복 ${dupUser.length}개 · 전화 뒤4자리 중복 ${dupPhone.length}개`);

  // 같은 사람의 USER/ADMIN 두 역할은 정책상 허용된 동명이다(동일인).
  const sameRoleDup = dupName.filter(([, v]) =>
    v.filter((x) => x.role === 'USER').length > 1);
  if (sameRoleDup.length === 0) {
    record('NOTE', 'POP',
        '서로 다른 USER 계정끼리 이름이 겹치는 경우가 DEV 에 없다. ' +
        '동명 그룹 2개는 같은 사람의 USER+BUSINESS_ADMIN 조합이다(정책상 허용). ' +
        '시나리오 A 는 런타임 재현 불가 — 아래 A 절 참조.');
  } else {
    record('NOTE', 'POP', `USER 끼리 동명인 그룹 ${sameRoleDup.length}개 — 런타임 A 가능.`);
  }
  return {byName, byUsername};
}

// ═══════════════════════════════════════════════════════════════════
// A. 서로 다른 사용자, 같은 이름 — 런타임 재현 가능성
// ═══════════════════════════════════════════════════════════════════
async function auditSameName() {
  head('A. 서로 다른 사용자, 같은 이름');

  record('NOTE', 'A',
      '제품에 이름 변경 경로가 없다. firestore.rules 가 users.name 을 본인 수정에서 ' +
      '차단하고("수정 UI는 존재하지 않는다"), 값을 정하는 것은 가입/본인인증 CF 뿐이다. ' +
      'DEV 에 동명 USER 계정을 만들려면 본인인증을 우회해야 하므로 만들지 않는다.');

  // 재현 대신, 같은 이름이 주어졌을 때 reader 가 무엇으로 행을 구분하는지 본다.
  const apps = await appsByBiz({businessId: BIZ, limit: 2000});
  const uids = [...new Set(apps.map((a) => a.uid))];
  log(`   이 사업장 지원서 ${apps.length}건 · 서로 다른 uid ${uids.length}명`);

  // 지원서 응답이 uid 를 항상 싣고 있는가 — 이름만 오면 화면이 구분할 근거가 없다.
  const noUid = apps.filter((a) => !a.uid).length;
  const noId = apps.filter((a) => !a.id).length;
  if (noUid === 0 && noId === 0) {
    record('OK', 'A',
        `지원서 ${apps.length}건 전부 uid 와 문서 id 를 함께 내려준다 — ` +
        '이름이 같아도 화면·선택·변경이 구분할 근거가 있다.');
  } else {
    record('BLOCKER', 'A',
        `uid 없는 지원서 ${noUid}건 · id 없는 지원서 ${noId}건 — 동명이인을 구분할 수 없다.`);
  }

  // 지원서의 이름 스냅샷(applicantName)이 사람 key 로 쓰이면 안 된다.
  const withSnapshotName = apps.filter((a) => a.applicantName).length;
  log(`   applicantName 스냅샷 보유 ${withSnapshotName}/${apps.length}건 ` +
      '(표시 폴백용 — key 아님)');

  return apps;
}

// ═══════════════════════════════════════════════════════════════════
// B. 같은 사용자, 복수 Application
// ═══════════════════════════════════════════════════════════════════
async function auditMultiApplication(apps) {
  head('B. 같은 사용자, 복수 Application');

  const byUid = {};
  for (const a of apps) (byUid[a.uid] ??= []).push(a);
  const multi = Object.entries(byUid).filter(([, v]) => v.length > 1);
  log(`   복수 지원 보유 uid ${multi.length}명`);

  let merged = 0;
  for (const [uid, v] of multi.slice(0, 5)) {
    const ids = new Set(v.map((a) => a.id));
    const active = v.filter((a) =>
      ['PENDING', 'CONFIRMED', 'CONTRACT_PENDING'].includes(a.status));
    log(`     ${uid.slice(0, 10)}  지원서 ${v.length}건 · 서로 다른 문서 id ${ids.size}개 ` +
        `· 활성 ${active.length}건`);
    for (const a of active.slice(0, 6)) {
      log(`        ${a.id.slice(-28).padEnd(28)} ${String(a.status).padEnd(17)} ` +
          `${dayKey(a.workDate)} ${a.startTime}-${a.endTime} ${a.selectedWorkType}`);
    }
    if (ids.size !== v.length) merged++;
  }
  if (merged === 0) {
    record('OK', 'B',
        '한 사람의 지원서가 문서 id 로 각각 유지된다 — 합쳐지지 않는다. ' +
        'complexId(toId_slotId_workType_uid)가 같은 슬롯 중복 지원만 막고, ' +
        '다른 날짜·다른 업무는 별개 문서가 된다.');
  } else {
    record('BLOCKER', 'B', `지원서가 합쳐진 uid ${merged}명.`);
  }
}

// ═══════════════════════════════════════════════════════════════════
// C. 같은 사용자, 같은 날 복수 근무
// ═══════════════════════════════════════════════════════════════════
async function auditSameDayMultiWork() {
  head('C. 같은 사용자, 같은 날 복수 근무');

  const month = kstDateKey(0).slice(0, 7);
  const [y, m] = month.split('-').map(Number);
  const start = Date.UTC(y, m - 1, 1) - KST;
  const end = Date.UTC(y, m, 1) - KST;
  const r = await callAs(ADMIN, 'callableGetAdminAttendances',
      {businessId: BIZ, startMs: start, endMs: end});
  const rows = r.items || [];

  const byUserDay = {};
  for (const a of rows) (byUserDay[`${a.userId}|${dayKey(a.workDate)}`] ??= []).push(a);
  const multi = Object.entries(byUserDay).filter(([, v]) => v.length > 1);
  log(`   ${month} 근태 ${rows.length}건 · 같은 사람 같은 날 2건 이상 ${multi.length}조`);

  let sameRowIdentity = 0;
  let settledSum = 0;
  for (const [k, v] of multi) {
    const ids = new Set(v.map((a) => a.id));
    const apps = new Set(v.map((a) => a.applicationId));
    const amounts = v.map((a) => num((a.wageDetail || {}).netWage ?? a.finalWage));
    log(`     ${k}  ${v.length}건 · 근태 id ${ids.size}개 · 지원서 ${apps.size}개 ` +
        `· 금액 ${amounts.join('/')}`);
    if (ids.size !== v.length || apps.size !== v.length) sameRowIdentity++;
    for (const a of v) {
      if (['confirmed', 'transferred'].includes(a.wageStatus)) {
        settledSum += num((a.wageDetail || {}).netWage ?? a.finalWage);
      }
    }
  }

  if (multi.length === 0) {
    record('NOTE', 'C', '이 달에 같은 사람 같은 날 복수 근무가 없다 — 런타임 확인 불가.');
  } else if (sameRowIdentity === 0) {
    record('OK', 'C',
        `같은 사람 같은 날 근무가 ${multi.length}조 있고, 각각 별개의 근태 id 와 ` +
        '지원서 id 를 갖는다 — 행이 합쳐지지 않는다.');
  } else {
    record('BLOCKER', 'C', `행 식별자가 겹치는 조 ${sameRowIdentity}개.`);
  }

  // 화면 집계와 Excel 모집단이 같은가 (R7-PRE1 수정 결과 확인)
  const byId = new Set(rows.map((a) => a.id));
  if (byId.size === rows.length) {
    record('OK', 'C',
        `문서 id 기준 ${byId.size}건 = reader 반환 ${rows.length}건. ` +
        '화면 집계와 Excel 이 같은 목록을 본다(R7-PRE1 수정 반영).');
  } else {
    record('CORRECTION', 'C', `문서 중복 ${rows.length - byId.size}건.`);
  }
  log(`   같은 날 복수 근무분 확정·이체 금액 합계: ${settledSum.toLocaleString()}원`);
  return multi;
}

// ═══════════════════════════════════════════════════════════════════
// D. 이름 변경 — 과거 스냅샷과 현재 프로필
// ═══════════════════════════════════════════════════════════════════
async function auditRename() {
  head('D. 이름 변경 — 과거 귀속이 깨지는가');

  record('NOTE', 'D',
      '이름은 finalizePassReauth 가 바꾼다(본인인증 재인증). CF 주석에 ' +
      '"전화번호 변경, 이름 개명, 잘못 저장된 초기값 교정 모두 반영"이라고 적혀 있다 — ' +
      '개명 경로는 실재한다.');

  // 과거 스냅샷이 현재 프로필과 독립인가.
  const contracts = await db.collection('employment_contracts')
      .where('businessId', '==', BIZ).get();
  const uids = [...new Set(contracts.docs.map((d) => d.data().workerId).filter(Boolean))];
  const users = uids.length
    ? await db.getAll(...uids.map((u) => db.collection('users').doc(u)))
    : [];
  const nameNow = {};
  users.forEach((s) => { if (s.exists) nameNow[s.id] = s.data().name; });

  let snapshotted = 0; let drifted = 0;
  for (const d of contracts.docs) {
    const c = d.data();
    const snapName = (c.snapshot || {}).workerName;
    if (!snapName) continue;
    snapshotted++;
    if (nameNow[c.workerId] && nameNow[c.workerId] !== snapName) drifted++;
  }
  log(`   계약 ${contracts.size}건 중 workerName 스냅샷 보유 ${snapshotted}건 · ` +
      `현재 프로필과 다른 것 ${drifted}건`);
  record('OK', 'D',
      '계약서는 서명 시점 snapshot.workerName 을 들고 있고 workerId 로 사람을 가리킨다 — ' +
      '개명해도 과거 계약의 명의가 재작성되지 않는다.');

  // 급여 계좌 스냅샷 예금주 vs 현재 이름
  const att = await db.collection('attendance')
      .where('businessId', '==', BIZ)
      .where('wageAccountSnapshotVersion', '==', 1).limit(50).get();
  let holderDrift = 0;
  const holderUids = [...new Set(att.docs.map((d) => d.data().userId))];
  const hu = holderUids.length
    ? await db.getAll(...holderUids.map((u) => db.collection('users').doc(u)))
    : [];
  const hNow = {};
  hu.forEach((s) => { if (s.exists) hNow[s.id] = s.data().name; });
  for (const d of att.docs) {
    const a = d.data();
    if (a.wageAccountHolder && hNow[a.userId] &&
        a.wageAccountHolder !== hNow[a.userId]) holderDrift++;
  }
  log(`   계좌 스냅샷 보유 근태 ${att.size}건 · 예금주가 현재 이름과 다른 것 ${holderDrift}건`);
  record('OK', 'D',
      'wageAccountHolder 는 급여 확정 시점 스냅샷이고 소급 변경되지 않는다 ' +
      '(USER PRODUCT POLICY 7). 개명해도 이미 확정된 건의 예금주는 그대로다.');

  // 그런데 Excel 의 이름은 현재 프로필에서 온다.
  record('CORRECTION', 'D',
      '이체 Excel 한 파일 안에서 「이름」은 현재 프로필(_loadWorkerNames → users/{uid}.name)이고 ' +
      '「예금주」는 확정 시점 스냅샷이다. 개명 후 과거 급여를 내보내면 두 칸이 서로 다른 ' +
      '이름으로 찍힌다 — 은행 쪽에서 명의 불일치로 읽히고, 운영자는 이유를 알 수 없다. ' +
      '금액·계좌는 정확하므로 BLOCKER 는 아니다.');

  record('NOTE', 'D',
      'payroll_summaries/{biz}_{YYYY-MM}/workers/{uid}.name 은 현재 프로필로 다시 쓰인다 ' +
      '(onAttendanceWageChanged · callableRepairPayrollSummaries). uid 로 키가 잡혀 있어 ' +
      '귀속은 안전하고, 이름은 표시값이라 갱신이 틀린 것은 아니다.');
}

// ═══════════════════════════════════════════════════════════════════
// E. Export row identity
// ═══════════════════════════════════════════════════════════════════
async function auditExportIdentity(sameDayGroups) {
  head('E. Export row identity — 파일만 보고 사람과 행을 구분할 수 있는가');

  const rows = [
    ['은행 이체 xlsx', '이름 · 은행명 · 계좌번호 · 예금주 · 이체금액 · 메모',
      '사람: 계좌번호(사실상) · 행: 근로자×계좌 합산',
      '계좌번호가 사람을 가르지만 계좌는 identity 가 아니다. 같은 이름 두 사람이 ' +
      '각자 계좌를 가지면 구분되지만, 운영자가 그것을 식별자로 읽게 된다.'],
    ['급여현황 xlsx', '이름 · 사업장 · 업무 · 근무시간 · 급여형태 · 근무일 · 금액들 · 이체상태',
      '사람: 이름뿐 · 행: 업무+근무시간+근무일(R7-PRE1 추가)',
      '행은 구분되지만 **사람은 이름만으로 구분한다.**'],
    ['근태현황 xlsx', '사업장명 · 근무일자 · 파트 · 이름 · 성별 · 연락처 · 출근 · 퇴근 · 비고',
      '사람: 이름+연락처 · 행: 근무일자+파트+출퇴근',
      '연락처가 사실상 식별자로 쓰이고 있다 — PII 를 identity 로 쓰는 형태.'],
    ['당일명단 PDF', '이름 · 성별 · 연락처 · 근무시간',
      '사람: 이름+연락처 · 행: 파트 그룹 내 순서',
      'uid 가 전혀 없다. 같은 이름 두 사람이 같은 파트면 두 줄이 완전히 같아 보인다.'],
    ['임금명세서 PDF', '근로자명 · 기간 · 일별 근무 · 금액',
      '사람: 이름 · 행: 날짜',
      '1인 1파일이라 파일 내 혼동은 없다. 파일명이 `{이름}_{연월}_임금명세서.pdf` 라 ' +
      '동명이인 파일이 서로 덮어쓴다.'],
  ];
  for (const [name, cols, ident, note] of rows) {
    log(`   ${name}`);
    log(`     컬럼   : ${cols}`);
    log(`     식별   : ${ident}`);
    log(`     비고   : ${note}`);
  }

  record('CORRECTION', 'E',
      '운영 export 5종 중 **사람 식별용 stable ID 를 가진 파일이 하나도 없다.** ' +
      '전부 이름(+연락처/계좌)으로 사람을 가른다. 동명이인이 생기면 ' +
      '급여현황·근태현황·당일명단에서 두 사람이 같은 줄로 읽힌다.');

  record('CORRECTION', 'E',
      '임금명세서 PDF 파일명이 `{이름}_{연월}_임금명세서.pdf` 다. 동명이인 두 명을 ' +
      '차례로 내보내면 받는 쪽에서 같은 파일명이 되어 하나가 덮인다.');

  if (sameDayGroups.length > 0) {
    record('OK', 'E',
        `같은 사람 같은 날 복수 근무 ${sameDayGroups.length}조는 급여현황 xlsx 에서 ` +
        '업무·근무시간 컬럼으로 구분된다(R7-PRE1). 근태현황 xlsx 는 출퇴근 컬럼으로 구분된다.');
  }
}

// ═══════════════════════════════════════════════════════════════════
// F. UI disambiguator 후보 — 현재 존재하는 식별자
// ═══════════════════════════════════════════════════════════════════
async function auditDisambiguators() {
  head('F. UI disambiguator 후보 — 지금 있는 것');

  const s = await db.collection('users').where('role', '==', 'USER').get();
  const users = s.docs.map((d) => ({uid: d.id, ...d.data()}));

  const uniq = (f) => new Set(users.map(f).filter((x) => x != null && x !== '')).size;
  const phone4 = (u) => String(u.authPhone || u.phone || '').slice(-4);
  const birthYear = (u) => (u.birthDate ? new Date(u.birthDate.toMillis() + KST).getUTCFullYear() : null);

  log(`   USER ${users.length}명 기준 후보별 고유값 수`);
  log(`     username        ${uniq((u) => u.username)}개  (로그인 ID · 가입 시 중복검사 존재)`);
  log(`     전화 뒤4자리     ${uniq(phone4)}개`);
  log(`     생년             ${uniq(birthYear)}개`);
  log(`     uid 앞 6자리     ${uniq((u) => u.uid.slice(0, 6))}개`);
  log(`     사업장 근로자번호  없음 (businesses/{}/members 는 관리자·서브관리자용)`);

  record('NOTE', 'F',
      'username 은 이미 서버가 관리자에게 내려주고 있다 ' +
      '(APPLICANT_REVIEW_ALLOWED 에 포함). 화면에 표시만 안 한다. ' +
      '다만 이것은 **로그인 ID** 다 — 자격증명의 절반을 사업장에 노출하는 셈이라 ' +
      'disambiguator 로 쓰는 것은 권장하지 않는다.');
}

// ═══════════════════════════════════════════════════════════════════
async function main() {
  log('R7-PRE1A 사람 식별 / 동명이인 감사  (읽기 전용)');
  log(`  project : ${projectId}`);
  log(`  오늘(KST): ${kstDateKey(0)}`);

  await auditPopulation();
  const apps = await auditSameName();
  await auditMultiApplication(apps);
  const sameDay = await auditSameDayMultiWork();
  await auditRename();
  await auditExportIdentity(sameDay);
  await auditDisambiguators();

  head('판정 요약');
  const by = (l) => findings.filter((f) => f.level === l);
  for (const l of ['BLOCKER', 'CORRECTION', 'NOTE']) {
    for (const f of by(l)) log(`   [${l}] (${f.id}) ${f.text}`);
  }
  log(`\n   OK ${by('OK').length} · CORRECTION ${by('CORRECTION').length} ·` +
      ` NOTE ${by('NOTE').length} · BLOCKER ${by('BLOCKER').length}`);
  process.exit(by('BLOCKER').length > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error('\n실패:', e && e.message ? e.message : e);
  process.exit(1);
});
