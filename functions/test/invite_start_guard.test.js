/**
 * [INVITE-START-GUARD] 초대 수락 마감 계약.
 *
 *   계약: 수락 가능 시각 = **초대+24시간과 근무 시작 중 더 이른 쪽**.
 *         근무 시작 시각부터는 수락을 거절한다.
 *
 *   실행: cd functions && node test/invite_start_guard.test.js
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const SRC = fs.readFileSync(path.join(__dirname, '..', 'src', 'index.ts'), 'utf8');
const CODE = SRC.split(/\r?\n/)
    .filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l))
    .join('\n');

let pass = 0; const fails = [];
function t(id, fn) {
  try { fn(); pass++; console.log('  ok   ' + id); } catch (e) {
    fails.push(id + ': ' + e.message.split('\n')[0]);
    console.log('  FAIL ' + id + ' — ' + e.message.split('\n')[0]);
  }
}

// ── 계약 계산식 — 서버와 같은 식을 여기서 재현해 경계를 센다 ──────────
const KST = 9 * 3600000;
const DAY = 86400000;
/** 서버 `srvShiftStartMsFrom` 과 같은 식. */
function shiftStartMs(workDateMs, startTime) {
  if (typeof startTime !== 'string' || !/^\d{1,2}:\d{2}$/.test(startTime)) return null;
  const [hh, mm] = startTime.split(':').map(Number);
  if (!Number.isFinite(hh) || !Number.isFinite(mm)) return null;
  return workDateMs + (hh * 60 + mm) * 60000;
}
/** 서버 초대 생성의 만료 결정과 같은 식. */
function inviteExpiry(invitedAtMs, workDateMs, startTime, isLong) {
  const plus24 = invitedAtMs + 24 * 3600000;
  const start = isLong ? null : shiftStartMs(workDateMs, startTime);
  return (start != null && start < plus24) ? start : plus24;
}
/** 서버 수락 guard 와 같은 판정. */
function acceptAllowed(nowMs, workDateMs, startTime, isLong) {
  if (isLong) return true;
  const start = shiftStartMs(workDateMs, startTime);
  if (start == null) return true; // 알 수 없으면 막지 않는다
  return nowMs < start;
}

const kstMidnight = (y, m, d) => Date.UTC(y, m - 1, d) - KST;

console.log('[ISG-A] 만료 = min(초대+24h, 근무 시작)');

t('ISG-1 근무가 24시간 안이면 근무 시작이 만료다', () => {
  const wd = kstMidnight(2026, 10, 15);
  const invitedAt = wd + 10 * 3600000 + 9 * 60000; // 10-15 10:09 KST
  const exp = inviteExpiry(invitedAt, wd, '20:00', false);
  assert.strictEqual(exp, shiftStartMs(wd, '20:00'));
  assert.ok(exp < invitedAt + DAY);
});

t('ISG-2 근무가 24시간 뒤면 +24시간이 만료다', () => {
  const wd = kstMidnight(2026, 10, 20);
  const invitedAt = kstMidnight(2026, 10, 15) + 10 * 3600000;
  const exp = inviteExpiry(invitedAt, wd, '10:00', false);
  assert.strictEqual(exp, invitedAt + DAY);
});

t('ISG-3 DEV 실측 사례가 12.2시간 → 0시간으로 좁혀진다', () => {
  const wd = kstMidnight(2026, 10, 15);
  const invitedAt = wd + 10 * 3600000 + 9 * 60000 + 20000; // 10:09:20
  const before = invitedAt + DAY; // 기존 계약
  const after = inviteExpiry(invitedAt, wd, '20:00', false);
  const shiftEnd = shiftStartMs(wd, '22:00');
  assert.ok((before - shiftEnd) / 3600000 > 12, '기존은 근무 종료 후 12시간 초과');
  assert.ok(after <= shiftEnd, '새 계약은 근무 종료 전에 닫힌다');
  assert.strictEqual(after, shiftStartMs(wd, '20:00'));
});

t('ISG-4 장기 근무는 좁히지 않는다', () => {
  const wd = kstMidnight(2026, 10, 15);
  const invitedAt = wd + 10 * 3600000;
  assert.strictEqual(inviteExpiry(invitedAt, wd, '20:00', true), invitedAt + DAY);
});

console.log('\n[ISG-B] 수락 guard — 시작 직전/정각/직후');

t('ISG-5 시작 1분 전은 수락된다', () => {
  const wd = kstMidnight(2026, 10, 15);
  const start = shiftStartMs(wd, '20:00');
  assert.strictEqual(acceptAllowed(start - 60000, wd, '20:00', false), true);
});

t('ISG-6 시작 정각은 거절된다', () => {
  const wd = kstMidnight(2026, 10, 15);
  const start = shiftStartMs(wd, '20:00');
  assert.strictEqual(acceptAllowed(start, wd, '20:00', false), false);
});

t('ISG-7 시작 1분 후는 거절된다', () => {
  const wd = kstMidnight(2026, 10, 15);
  const start = shiftStartMs(wd, '20:00');
  assert.strictEqual(acceptAllowed(start + 60000, wd, '20:00', false), false);
});

t('ISG-8 근무 종료 후(기존 B 초대 창)도 거절된다', () => {
  const wd = kstMidnight(2026, 10, 15);
  const afterShift = shiftStartMs(wd, '22:00') + 3600000; // 10-15 23:00
  assert.strictEqual(acceptAllowed(afterShift, wd, '20:00', false), false);
});

t('ISG-9 startTime 을 알 수 없으면 막지 않는다', () => {
  const wd = kstMidnight(2026, 10, 15);
  assert.strictEqual(acceptAllowed(wd + DAY, wd, undefined, false), true);
  assert.strictEqual(acceptAllowed(wd + DAY, wd, '', false), true);
  assert.strictEqual(acceptAllowed(wd + DAY, wd, '25:xx', false), true);
});

t('ISG-10 장기 근무는 시작 이후에도 막지 않는다', () => {
  const wd = kstMidnight(2026, 10, 15);
  const start = shiftStartMs(wd, '20:00');
  assert.strictEqual(acceptAllowed(start + 3600000, wd, '20:00', true), true);
});

console.log('\n[ISG-C] 소스 계약 — 구현이 그 자리에 있는가');

t('ISG-11 초대 생성이 min(+24h, 시작) 을 저장한다', () => {
  assert.ok(CODE.includes('const inviteShiftStartMs = isLong ?'),
      '만료 좁히기 계산이 없다');
  assert.ok(/inviteExpiresAt:\s*inviteExpiresAtTs/.test(CODE),
      '문서에 좁힌 값을 저장하지 않는다');
  assert.ok(!/inviteExpiresAt:\s*expiresAt\b/.test(CODE),
      '아직 24시간 고정값을 저장하는 자리가 남아 있다');
});

t('ISG-12 수락 트랜잭션 안에 시작 guard 가 있다', () => {
  const i = CODE.indexOf('export const callableAcceptTOInvitation');
  assert.ok(i > 0);
  const body = CODE.slice(i, i + 20000);
  const tx = body.indexOf('db.runTransaction');
  assert.ok(tx > 0, '트랜잭션이 없다');
  const guard = body.indexOf('근무가 이미 시작되어 수락할 수 없습니다');
  assert.ok(guard > tx, 'guard 가 트랜잭션 **안**에 있어야 한다');
});

t('ISG-13 guard 는 slot 을 트랜잭션으로 읽는다(저장값만 믿지 않음)', () => {
  const i = CODE.indexOf('export const callableAcceptTOInvitation');
  const body = CODE.slice(i, i + 20000);
  assert.ok(/guardSlotSnap\s*=\s*await tx\.get\(/.test(body),
      'slot 을 tx.get 으로 읽지 않는다');
  // [ISG2] guard 는 fail-closed 리졸버로 바뀌었다 — 이유를 돌려받아
  //   모르면 거절한다. 계산식은 여전히 한 곳(srvShiftStartMsFrom)이다.
  assert.ok(body.includes('srvResolveGuardShiftStart'),
      'canonical 계산식을 쓰지 않는다');
});

t('ISG-14 계산식을 복제하지 않았다 — 순수 함수 1벌', () => {
  const defs = (CODE.match(/function srvShiftStartMsFrom\(/g) || []).length;
  assert.strictEqual(defs, 1, 'srvShiftStartMsFrom 정의가 ' + defs + '개');
  const pure = (CODE.match(/function srvShiftStartFromSlotData\(/g) || []).length;
  assert.strictEqual(pure, 1, 'srvShiftStartFromSlotData 정의가 ' + pure + '개');
  // 기존 비동기 헬퍼는 순수 함수를 호출만 한다
  assert.ok(/async function srvResolveShiftStartMs[\s\S]{0,600}srvShiftStartFromSlotData/
      .test(CODE), 'srvResolveShiftStartMs 가 순수 함수를 쓰지 않는다');
});

t('ISG-15 만료 스케줄러는 저장값을 본다 — 쿼리는 그대로', () => {
  assert.ok(CODE.includes('.where("status", "==", "INVITED")'));
  assert.ok(CODE.includes('.where("inviteExpiresAt", "<=", now)'),
      '만료 스케줄러 쿼리가 바뀌었다');
});

t('ISG-16 이미 EXPIRED·REJECTED·CONFIRMED 는 기존 분기가 먼저 막는다', () => {
  const i = CODE.indexOf('export const callableAcceptTOInvitation');
  const body = CODE.slice(i, i + 20000);
  const confirmed = body.indexOf('alreadyConfirmed');
  const expired = body.indexOf('만료된 초대는 수락할 수 없습니다');
  const rejected = body.indexOf('이미 거절한 초대입니다');
  const guard = body.indexOf('근무가 이미 시작되어 수락할 수 없습니다');
  assert.ok(confirmed > 0 && expired > 0 && rejected > 0);
  assert.ok(confirmed < guard && expired < guard && rejected < guard,
      '상태 분기가 시작 guard 보다 먼저 와야 한다');
});

console.log('\n[ISG-D] 화면 갱신 — 초대가 변경으로 기록되는가');

t('ISG-17 시트가 성공 시에만 콜백을 부른다', () => {
  const f = fs.readFileSync(path.join(__dirname, '..', '..', 'lib', 'screens',
      'business_admin', 'dialogs', 'available_workers_bottom_sheet.dart'), 'utf8');
  assert.ok(f.includes('final VoidCallback? onInviteSucceeded;'), '콜백 선언이 없다');
  const call = f.indexOf('widget.onInviteSucceeded?.call()');
  assert.ok(call > 0, '성공 시 호출하지 않는다');
  const added = f.indexOf('_invitedUids.add(worker.uid)');
  const catchAt = f.indexOf('} catch (e) {', added);
  assert.ok(added > 0 && added < call, '성공 경로 뒤에 있어야 한다');
  assert.ok(call < catchAt, '콜백이 catch 블록 앞(=성공 경로)에 있어야 한다');
});

t('ISG-18 호출자가 초대를 _hasChanges 로 기록한다', () => {
  const f = fs.readFileSync(path.join(__dirname, '..', '..', 'lib', 'screens',
      'business_admin', 'dialogs', 'day_applicants_dialog.dart'), 'utf8');
  // [ISG2] 판단은 공용 식(inviteSheetOutcome / inviteDialogOutcome)이 한다.
  assert.ok(
      /onInviteSucceeded:\s*\(\)\s*\{[\s\S]{0,300}outcome\.propagate\) _hasChanges = true;/
          .test(f),
      '가능인력 경로가 변경을 기록하지 않는다');
  // [E1-AMBIGUOUS-INVITE] bool → InviteDialogResult(sent/canceled/unconfirmed),
  //   불명확하게 닫히면 대상 지원서를 다시 읽어 확인한 뒤에만 전파한다.
  assert.ok(f.includes('final invited = await showDialog<InviteDialogResult>('),
      '직접 초대 결과를 InviteDialogResult 로 받지 않는다');
  assert.ok(
      /InviteSaveVerifier\.resolve\(\s*inviteDialogOutcome\(invited\),[\s\S]{0,300}outcome\.propagate\) _hasChanges = true;/
          .test(f),
      '직접 초대 성공(또는 확인된 저장)만 반영하지 않는다');
  assert.ok(!/await showDialog<void>\([\s\S]{0,200}InviteWorkerDialog\.contextual/.test(f),
      '아직 <void> 로 버리는 자리가 남아 있다');
});

t('ISG-19 카드→Home 전파 체인은 그대로 쓴다(새 경로 없음)', () => {
  const f = fs.readFileSync(path.join(__dirname, '..', '..', 'lib', 'widgets',
      'admin', 'cards', 'admin_to_group_card.dart'), 'utf8');
  assert.ok(/final hasChanges = await showDialog<bool>\(/.test(f));
  assert.ok(/if \(hasChanges == true && mounted\)\s*\{[\s\S]{0,200}widget\.onChanged\(\)/
      .test(f), '카드가 변경을 받아 재조회하는 기존 체인이 사라졌다');
  assert.ok(f.includes('WorkforceController.notifyDataChanged'),
      'Home 알림 체인이 사라졌다');
});

t('ISG-20 지원(Apply) 직후 갱신 동작은 건드리지 않았다', () => {
  const f = fs.readFileSync(path.join(__dirname, '..', '..', 'lib', 'screens',
      'business_admin', 'dialogs', 'work_applicants_dialog.dart'), 'utf8');
  assert.ok(f.includes('await _loadApplicants();'),
      'work_applicants_dialog 의 기존 재조회가 사라졌다');
});

console.log('\n[ISG-E] 지원자 문구');

t('ISG-21 홈 배너가 24시간 고정이라고 말하지 않는다', () => {
  const f = fs.readFileSync(path.join(__dirname, '..', '..', 'lib', 'screens',
      'user', 'user_home_screen.dart'), 'utf8');
  assert.ok(!f.includes('24시간 내 수락하지 않으면 자동 만료됩니다'),
      '옛 문구가 남아 있다');
  // [ISG2] 한쪽 경계만 말하는 것도 숨기는 것이다 — 둘을 함께 말한다.
  assert.ok(!f.includes('근무 시작 전까지 수락하지 않으면 자동 만료됩니다'),
      '한쪽 경계만 말하는 문구가 남아 있다');
  assert.ok(f.includes('초대 후 24시간과 근무 시작 중 빠른 때까지 수락할 수 있어요'));
});

t('ISG-22 만료 시각 표시는 실효 마감을 쓴다(저장값이 근무 뒤여도 맞는다)', () => {
  const f = fs.readFileSync(path.join(__dirname, '..', '..', 'lib', 'screens',
      'user', 'my_applications_screen.dart'), 'utf8');
  // [ISG2] 저장값만 읽으면 이 계약 이전 기록에서 근무 **다음 날**이 보인다.
  //   실효 마감(min(저장값, 근무 시작))을 읽고, 표기는 KST 로 고정한다.
  assert.ok(f.includes('app.effectiveInviteDeadline'),
      '만료 표시가 실효 마감을 읽지 않는다');
  assert.ok(!f.includes('_mdhmFmt.format('),
      '기기 시간대 성분을 찍는 포맷터가 남아 있다');
  assert.ok(f.includes('FormatHelper.formatKstMonthDayTime('),
      'KST 고정 표기를 쓰지 않는다');
});

console.log('\n통과 ' + pass + ' / 실패 ' + fails.length);
if (fails.length) { for (const f of fails) console.log('  - ' + f); process.exit(1); }
