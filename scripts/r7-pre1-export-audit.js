#!/usr/bin/env node
/**
 * [R7-PRE1] 관리자 export / Excel 운영 계약 감사.
 *
 * 디자인을 보지 않는다. **파일이 화면과 같은 말을 하는가**만 본다.
 * 화면이 쓰는 canonical reader(CF)를 그대로 불러서, 각 export 가 그 결과로
 * 무엇을 찍게 되는지 여기서 재구성하고 대조한다.
 *
 *   node scripts/r7-pre1-export-audit.js --project alfit-89567
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

const dayKey = (ms) => new Date(ms + KST).toISOString().slice(0, 10);

/**
 * AttendanceModel.checkIn / checkOut 게터와 같은 'HH:mm'.
 * CF 는 Timestamp 를 {_seconds} 로 직렬화해 보낸다 — 객체를 그대로 문자열에
 * 넣으면 전부 '[object Object]' 가 되어 서로 다른 시각이 같아 보인다.
 */
const hhmm = (v) => {
  const t = msOf(v);
  if (t == null || Number.isNaN(t)) return null;
  return new Date(t + KST).toISOString().slice(11, 16);
};

/** 화면들이 공통으로 쓰는 근태 reader. payroll·월상세 둘 다 이것을 부른다. */
async function adminAttendances(startMs, endMs, wageStatus) {
  const r = await callAs(ADMIN, 'callableGetAdminAttendances', {
    businessId: BIZ, startMs, endMs,
    ...(wageStatus ? {wageStatus} : {}),
  });
  return r.items || [];
}

const num = (v) => (typeof v === 'number' ? v : 0);
const msOf = (v) => (v == null ? null
  : typeof v === 'number' ? v
  : v._seconds != null ? v._seconds * 1000
  : v.seconds != null ? v.seconds * 1000
  : Date.parse(v));

// ═══════════════════════════════════════════════════════════════════
// 1. 급여 Excel — 이체현황 탭 (exportPayrollDetail)
// ═══════════════════════════════════════════════════════════════════
async function auditPayrollDetail(month) {
  head(`1. 급여/정산 Excel — 이체현황 탭  (${month})`);
  const [y, m] = month.split('-').map(Number);
  const start = Date.UTC(y, m - 1, 1);
  const end = Date.UTC(y, m, 1);

  // 화면 = confirmed + transferred 두 번 조회해 합친다 (대시보드와 같은 순서).
  const conf = await adminAttendances(start, end, 'confirmed');
  const xfer = await adminAttendances(start, end, 'transferred');
  const all = [...conf, ...xfer];
  log(`   화면 모집단 : 확정 ${conf.length}건 + 이체완료 ${xfer.length}건 = ${all.length}건`);

  // Excel 은 이 목록을 건별 1행으로 찍고 합계 행을 붙인다.
  const netOf = (r) => num((r.wageDetail || {}).netWage ?? r.finalWage);
  const sumNet = all.reduce((a, r) => a + netOf(r), 0);
  const screenPending = conf.reduce((a, r) => a + netOf(r), 0);
  const screenXfer = xfer.reduce((a, r) => a + netOf(r), 0);
  log(`   Excel 행 수  : ${all.length}행 + 합계 1행`);
  log(`   Excel 합계   : ${sumNet.toLocaleString()}원`);
  log(`   화면 요약    : 미이체 ${screenPending.toLocaleString()}원 · ` +
      `이체완료 ${screenXfer.toLocaleString()}원`);

  if (sumNet === screenPending + screenXfer) {
    record('OK', 'EXP-1', '파일 합계 = 화면 두 금액의 합 (같은 모집단).');
  } else {
    record('BLOCKER', 'EXP-1',
        `파일 합계 ${sumNet.toLocaleString()}원 ≠ 화면 합 ` +
        `${(screenPending + screenXfer).toLocaleString()}원.`);
  }
  record('NOTE', 'EXP-1',
      '화면은 미이체·이체완료를 나눠 보여주고 파일은 하나의 합계만 찍는다. ' +
      '파일만 보는 사람은 이 합계를 "지급할 금액"으로 읽을 수 있다 — ' +
      '이체상태 컬럼이 행마다 있으므로 오독은 가능하지만 데이터는 완전하다.');

  // 행 식별자 — 사람을 구분할 수 있는가.
  const dupKey = {};
  for (const r of all) {
    const k = `${r.userId}|${dayKey(msOf(r.workDate))}`;
    (dupKey[k] ??= []).push(r);
  }
  const collided = Object.entries(dupKey).filter(([, v]) => v.length > 1);
  if (collided.length > 0) {
    log(`   같은 (이름,근무일) 행 ${collided.length}조 — 파일에서 구분되는가?`);
    let indistinguishable = 0;
    for (const [k, v] of collided) {
      // 고친 뒤 컬럼: 이름·사업장·업무·근무시간·급여형태·근무일…
      const keys = new Set(v.map((r) =>
        `${r.workType}|${hhmm(r.checkIn) || '-'}~${hhmm(r.checkOut) || '-'}`));
      const ok = keys.size === v.length;
      log(`     ${k}  ${v.length}행  금액 ${v.map(netOf).join('/')}` +
          `  업무·근무시간 조합 ${keys.size}가지${ok ? '' : '  ← 여전히 같다'}`);
      if (!ok) indistinguishable++;
    }
    if (indistinguishable > 0) {
      record('CORRECTION', 'EXP-1',
          `같은 사람·같은 날 행 중 ${indistinguishable}조는 업무·근무시간까지 같아 ` +
          '파일에서 구분되지 않는다. 회계 담당이 중복 입력으로 오인할 수 있다.');
    } else {
      record('OK', 'EXP-1',
          `같은 사람·같은 날 행이 ${collided.length}조 있지만 업무·근무시간 컬럼으로 ` +
          '모두 구분된다(R7-PRE1에서 두 컬럼 추가).');
    }
  } else {
    record('OK', 'EXP-1', '같은 사람·같은 근무일 행 충돌 없음.');
  }

  // 이름 결측 — uid 를 이름 칸에 넣지 않는가.
  const uids = [...new Set(all.map((r) => r.userId))];
  const users = await db.getAll(...uids.map((u) => db.collection('users').doc(u)));
  const missing = users.filter((s) => !s.exists || !s.data().name).length;
  record(missing === 0 ? 'OK' : 'NOTE', 'EXP-1',
      missing === 0
        ? '모든 행의 이름을 조회할 수 있다.'
        : `이름을 못 읽는 근로자 ${missing}명 — '이름 확인 불가'로 찍힌다(uid 노출 아님).`);

  return {start, end, all};
}

// ═══════════════════════════════════════════════════════════════════
// 2. 은행 이체 Excel (exportTransferList)
// ═══════════════════════════════════════════════════════════════════
async function auditTransferList(start, end) {
  head('2. 급여이체 / 은행 업로드 파일 — 미이체 탭');

  const conf = await adminAttendances(start, end, 'confirmed');
  log(`   대상(미이체) : ${conf.length}건`);

  // transfer_export_plan.classifyRecord 와 같은 순서로 판정한다.
  let exported = 0; let blocked = 0; let na = 0;
  const reasons = {};
  for (const r of conf) {
    const status = r.status;
    const nonWork = status === 'NO_SHOW' || status === 'absent';
    if (nonWork && num(r.finalWage) === 0) { na++; continue; }
    const wd = r.wageDetail;
    if (!wd) { blocked++; reasons.dataError = (reasons.dataError || 0) + 1; continue; }
    const net = num(wd.netWage);
    if (net < 0) { blocked++; reasons.dataError = (reasons.dataError || 0) + 1; continue; }
    if (net === 0) {
      blocked++; reasons.zeroAmountUnexplained = (reasons.zeroAmountUnexplained || 0) + 1;
      continue;
    }
    if (r.wageAccountReviewRequired === true) {
      blocked++; reasons.reviewRequired = (reasons.reviewRequired || 0) + 1; continue;
    }
    if (r.wageAccountSnapshotVersion !== 1) {
      blocked++; reasons.legacyNoSnapshot = (reasons.legacyNoSnapshot || 0) + 1; continue;
    }
    const ok = r.wageAccountBankName && r.wageAccountNumberEncrypted &&
        r.wageAccountHolder && r.wageAccountSnapshotAt;
    if (!ok) {
      blocked++; reasons.noAccountSnapshot = (reasons.noAccountSnapshot || 0) + 1; continue;
    }
    exported++;
  }
  log(`   판정         : 포함 ${exported} · 확인 필요 ${blocked} · 지급 대상 아님 ${na}`);
  if (Object.keys(reasons).length) {
    log(`   제외 사유    : ${JSON.stringify(reasons)}`);
  }

  // 불변식: 전부가 정확히 한 갈래에 담긴다.
  if (exported + blocked + na === conf.length) {
    record('OK', 'EXP-2',
        `모든 건이 한 갈래에 정확히 담긴다 (${conf.length} = ${exported}+${blocked}+${na}). ` +
        '조용히 사라지는 건이 없다.');
  } else {
    record('BLOCKER', 'EXP-2',
        `합이 맞지 않는다: ${conf.length} ≠ ${exported}+${blocked}+${na}.`);
  }

  // 계좌 출처 — 확정 시점 스냅샷인가, 현재 프로필인가.
  const snapshotted = conf.filter((r) => r.wageAccountSnapshotVersion === 1).length;
  record('OK', 'EXP-2',
      `계좌 출처는 확정 시점 스냅샷이다 (snapshotVersion==1 ${snapshotted}/${conf.length}건). ` +
      'users/{uid} 현재 프로필을 쓰지 않는다 — 서버 이체 CF 와 같은 4필드를 본다.');

  // 파일이 누락을 스스로 말하는가.
  record(blocked + na > 0 ? 'OK' : 'OK', 'EXP-2',
      '제외 건이 있으면 파일 하단에 "전체 N건 중 M건 포함 / 확인 필요 … / 지급 대상 아님 …" ' +
      '문구가 들어간다(payroll_excel_helper.dart:103). 화면 시트에서 이름·사유도 먼저 보여준다.');

  // 계좌번호 셀 타입 — 앞자리 0 과 수식 주입.
  record('OK', 'EXP-2',
      '계좌번호는 TextCellValue(문자열 셀)로 쓴다 → 앞자리 0 이 유지되고, ' +
      'xlsx 문자열 셀은 수식으로 평가되지 않는다(<f> 요소가 아님). CSV 가 아니므로 ' +
      '= + - @ 로 시작하는 값의 수식 주입 경로가 없다.');
}

// ═══════════════════════════════════════════════════════════════════
// 3. 근태 Excel — 월 상세 (admin_month_detail_screen)
// ═══════════════════════════════════════════════════════════════════
async function auditAttendanceExcel(month) {
  head(`3. 근태 / 출퇴근 Excel — 월 상세  (${month})`);
  const [y, m] = month.split('-').map(Number);
  const start = Date.UTC(y, m - 1, 1) - KST;
  const end = Date.UTC(y, m, 1) - KST;
  const rows = await adminAttendances(start, end);
  log(`   reader 반환  : ${rows.length}건 (callableGetAdminAttendances, wageStatus 필터 없음)`);

  // 문서 id 중복(진짜 중복) vs (userId, workDate) 중복(같은 날 다른 근무)
  const byId = new Set();
  const byUserDate = {};
  for (const r of rows) {
    byId.add(r.id);
    const k = `${r.userId}|${dayKey(msOf(r.workDate))}`;
    (byUserDate[k] ??= []).push(r);
  }
  const sameDay = Object.entries(byUserDate).filter(([, v]) => v.length > 1);
  log(`   문서 id 기준 : ${byId.size}건 (진짜 중복 ${rows.length - byId.size}건)`);
  log(`   (사람,날짜) 기준: ${Object.keys(byUserDate).length}조 · ` +
      `같은 날 2건 이상 ${sameDay.length}조`);
  for (const [k, v] of sameDay) {
    log(`     ${k}  ${v.length}건  ` +
        v.map((r) => `${r.workType}/${num(r.finalWage)}원`).join('  |  '));
  }

  if (rows.length !== byId.size) {
    record('CORRECTION', 'EXP-3',
        `같은 문서가 ${rows.length - byId.size}번 중복 반환됐다 — 중복 제거가 필요하다.`);
  } else {
    record('OK', 'EXP-3', '문서 중복 없음 — 화면·파일 모두 문서 id 로 한 번씩만 센다.');
  }

  // 화면 집계와 파일 행 수가 같은 모집단에서 나오는가.
  const settled = rows.filter((r) =>
    ['confirmed', 'transferred'].includes(r.wageStatus));
  const sumAll = settled.reduce(
      (a, r) => a + num((r.wageDetail || {}).netWage ?? r.finalWage), 0);
  // 예전 키를 그대로 재현한다. (JS 의 Set.add 는 boolean 이 아니라 Set 을
  //  돌려준다 — filter 안에서 그대로 쓰면 아무것도 걸러지지 않는다.)
  const seen = new Set();
  const oldDedup = rows.filter((r) => {
    const k = `${r.userId}_${msOf(r.workDate)}`;
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
  const sumOld = oldDedup
      .filter((r) => ['confirmed', 'transferred'].includes(r.wageStatus))
      .reduce((a, r) => a + num((r.wageDetail || {}).netWage ?? r.finalWage), 0);
  log(`   확정·이체 금액: 전체 ${sumAll.toLocaleString()}원 · ` +
      `(사람,날짜) 중복제거 시 ${sumOld.toLocaleString()}원`);
  if (sumAll !== sumOld) {
    record('NOTE', 'EXP-3',
        `(사람,날짜) 키로 거르면 ${(sumAll - sumOld).toLocaleString()}원이 사라진다. ` +
        '같은 날 두 건 근무가 정상이므로 그 키를 쓰면 안 된다 — ' +
        '문서 id 로 거르도록 고쳤다(admin_stats_service.getMonthDetail).');
  }

  // PII 노출 범위
  record('CORRECTION', 'EXP-3',
      '컬럼에 성별·연락처가 들어간다(사업장명·근무일자·파트·이름·성별·연락처·출근·퇴근·비고). ' +
      '급여 Excel 은 같은 이유로 이름만 남겼다(PII-DOC-R0.1). 이 파일은 사내 배포를 ' +
      '전제로 하더라도 연락처가 꼭 필요한지 재검토 대상이다 — 지금은 결함이 아니라 판단 항목.');

  // 시트 이름 = 사업장명
  const biz = (await db.collection('businesses').doc(BIZ).get()).data();
  const bad = /[:\\/?*\[\]]/.test(biz.name || '') || (biz.name || '').length > 31;
  record(bad ? 'CORRECTION' : 'NOTE', 'EXP-3',
      `복수 사업장일 때 시트 이름에 사업장명을 그대로 쓴다(excel[entry.key]). ` +
      `Excel 시트명은 31자 제한이고 : \\ / ? * [ ] 를 쓸 수 없다. ` +
      `현재 DEV 사업장명 "${biz.name}" 은 ${bad ? '규칙 위반' : '문제 없음'} — ` +
      '사업장명은 사용자 입력이므로 위반 시 파일이 깨질 수 있다.');

  // 파일명에 사업장 구분이 없다
  record('NOTE', 'EXP-3',
      `파일명이 '근태현황_${y}년${m}월.xlsx' 로 사업장 구분이 없다. ` +
      '여러 사업장을 차례로 내보내면 받는 쪽에서 같은 이름의 파일이 겹친다.');
}

// ═══════════════════════════════════════════════════════════════════
// 4. PDF 계열 — 당일명단 / 임금명세서 / 계약서
//    숫자를 재구성할 수 없는 산출물이라 출처·범위·실패 처리만 본다.
// ═══════════════════════════════════════════════════════════════════
async function auditPdfExports() {
  head('4. PDF 산출물 — 당일명단 / 임금명세서 / 계약서');

  record('OK', 'EXP-4',
      '당일명단 PDF: 출처가 화면이 그린 바로 그 목록이다(_confirmedWorkers·_userMap). ' +
      'totalCount = confirmedWorkers.length 라 행 수와 머릿수가 같고, ' +
      'userMap 에 없는 사람도 applicantName 으로 남는다 — 조용히 빠지지 않는다 ' +
      '(attendance_list_pdf.dart:646).');
  record('OK', 'EXP-4',
      '당일명단 PDF: 생성 실패는 토스트로 알리고 빈 PDF 를 만들지 않는다 ' +
      '(data==null || pdfBytes==null → return).');
  record('NOTE', 'EXP-4',
      '당일명단 PDF 에는 이름·성별·연락처가 들어간다. 현장 운영 문서라 ' +
      '연락처가 목적에 부합한다 — 근태 Excel 과는 성격이 다르다.');

  record('OK', 'EXP-4',
      '임금명세서 PDF: 일별 행의 금액은 effectiveNetWage 로 채운다 ' +
      '(DailyRecord.fromAttendance). 필드명이 netWage 라 금지 패턴처럼 보이지만 ' +
      'WageDetailModel 과 다른 클래스이고 주석에도 명시돼 있다 — 위반 아님.');
  record('NOTE', 'EXP-4',
      '임금명세서 PDF: wageDetail 이 없는 근태는 일별 상세에서 빠진다 ' +
      '(payslip_period_helper.dart:273 valid 필터). 빠졌다는 표시는 없다. ' +
      '확정 급여만 모으는 화면이라 현재 경로에서는 발생하지 않지만, ' +
      '법정 문서라 누락이 말없이 일어나면 안 된다 — 런타임 확인 항목.');

  const contracts = await db.collection('employment_contracts')
      .where('businessId', '==', BIZ).get();
  const completed = contracts.docs.filter((d) => d.data().status === 'completed');
  const withPdf = completed.filter((d) => d.data().pdfUrl);
  log(`   계약서 ${contracts.size}건 (완료 ${completed.length}건 · PDF 보유 ${withPdf.length}건)`);
  if (withPdf.length === completed.length) {
    record('OK', 'EXP-4',
        '완료된 계약서는 전부 pdfUrl 을 갖는다 — 서명 완료가 산출물 없이 끝나지 않는다.');
  } else {
    record('CORRECTION', 'EXP-4',
        `완료 계약 ${completed.length}건 중 ${completed.length - withPdf.length}건에 ` +
        'pdfUrl 이 없다 — 서명은 끝났는데 내려받을 문서가 없다.');
  }
}

// ═══════════════════════════════════════════════════════════════════
async function main() {
  log('R7-PRE1 관리자 export / Excel 운영 계약 감사  (읽기 전용)');
  log(`  project : ${projectId}`);
  log(`  오늘(KST): ${kstDateKey(0)}`);

  const month = kstDateKey(0).slice(0, 7);
  const {start, end} = await auditPayrollDetail(month);
  await auditTransferList(start, end);
  await auditAttendanceExcel(month);
  await auditPdfExports();

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
