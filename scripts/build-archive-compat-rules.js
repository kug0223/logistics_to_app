/**
 * [ARCHIVE-RULES-COMPAT] DEV 활성 ruleset 원문에 **운영 종료 경계 세 곳만** 더한 배포 후보를 만든다.
 *   작업 트리 firestore.rules 전체를 복사하지 않는다(그쪽에는 배포 순서가 다른 삭제 차단 등이 있다).
 *
 *   node scripts/build-archive-compat-rules.js <DEV 활성 원문> <출력>
 *
 *   바꾸는 곳
 *     ① businesses update — 종료 표식·연쇄 상태(deactivatedAt·archived*·archiveCascade*)를 클라이언트가
 *        바꾸지 못한다(슈퍼관리자 포함). 단독 관리자 deactivatedAt 예외(SEC-95) 제거.
 *     ② tos update — workDetails 단독 수정(업무 마감·재오픈)은 운영 중 사업장에서만.
 *     ③ slots — 운영 종료 사업장에서 슬롯 생성·closed→open·workDetails 수정 금지(마감·카운터는 허용).
 *   증명: 위 세 치환 밖은 바이트 동일, applications 블록은 원문 그대로.
 */
'use strict';
const fs = require('fs');
const [src, out] = process.argv.slice(2);
if (!src || !out) throw new Error('사용: <DEV 활성 원문> <출력>');
const raw = fs.readFileSync(src, 'utf8');
const EOL = raw.includes('\r\n') ? '\r\n' : '\n';
let s = raw.split(EOL).join('\n');
const edits = [];
function rep(a, b) {
  const n = s.split(a).length - 1;
  if (n !== 1) throw new Error(`앵커 ${n}회: ${a.slice(0, 70)}`);
  const at = s.indexOf(a); edits.push([at, a.length, b.length]); s = s.replace(a, b);
}

// ① businesses
rep(`      // deactivatedAt: 기본적으로 차단 — 단, 단독 관리자 탈퇴 시 예외 허용 (SEC-95)
      //   단독 관리자(adminIds.size() <= 1)가 deactivatedAt 필드만 설정하는 경우 허용.
      //   이중 관리자 이상인 경우 차단 유지 (외부 비활성화 공격 방어).`,
`      // [ARCHIVE-RULES-COMPAT] 운영 종료 표식·연쇄 상태는 서버(Admin SDK) 전용이다 — 슈퍼관리자 포함.
      //   deactivatedAt·archivedAt·archivedBy·archiveReason·archiveCascade·archiveCascadeRuns.
      //   구·현재 앱 모두 이 필드를 쓰지 않는다(사업장 수정은 폼 필드만, 종료는 callableArchiveOwnBusiness,
      //   슈퍼관리자는 callableManageBusiness). 예전의 "단독 관리자 deactivatedAt 단독 변경" 예외(SEC-95)는
      //   쓰는 앱이 없었고, 그 예외로 종료 표식을 지우거나(null) 바꿔 종료 판정을 무력화할 수 있었다.`);
rep(`                    !request.resource.data.diff(resource.data).affectedKeys()
                      .hasAny(['isApproved', 'approvedBy', 'deactivatedBy', 'reactivatedBy',
                               'attendancePolicyConfirmation']) &&`,
`                    !request.resource.data.diff(resource.data).affectedKeys()
                      .hasAny(['isApproved', 'approvedBy', 'deactivatedBy', 'reactivatedBy',
                               'attendancePolicyConfirmation',
                               'deactivatedAt', 'archivedAt', 'archivedBy', 'archiveReason',
                               'archiveCascade', 'archiveCascadeRuns']) &&`);
rep(`                                 'businessNumber']) ||
                       (request.resource.data.diff(resource.data).affectedKeys()
                         .hasOnly(['deactivatedAt']) &&
                        resource.data.get('adminIds', []).size() <= 1)) &&`,
`                                 'businessNumber'])) &&`);

// ② tos — workDetails 단독 수정
rep(`                    || (isLoggedIn() && (isToWriteAdmin(toId) || isSuperAdmin()) &&
                        request.resource.data.diff(resource.data).affectedKeys().hasOnly(['workDetails']));`,
`                    //   [ARCHIVE-RULES-COMPAT] 운영 종료 사업장의 공고는 업무 단위 재오픈·수정을 받지 않는다
                    //   (구·현재 앱 work_detail_management_dialog 의 직접 쓰기). 운영 중이면 그대로.
                    || (isLoggedIn() && (isToWriteAdmin(toId) || isSuperAdmin()) &&
                        request.resource.data.diff(resource.data).affectedKeys().hasOnly(['workDetails']) &&
                        get(/databases/$(database)/documents/businesses/$(resource.data.businessId))
                          .data.get('deactivatedAt', null) == null);`);

// ③ slots
rep(`      match /slots/{slotId} {
        // SEC-83: 미발행 TO의 슬롯(임금정보 등) 노출 차단 — isPublished 상속 적용`,
`      match /slots/{slotId} {
        // [ARCHIVE-RULES-COMPAT] 부모 공고의 사업장이 운영 중인가(문서가 없으면 아님 → 거절).
        function slotBizOpen() {
          let bid = get(/databases/$(database)/documents/tos/$(toId)).data.businessId;
          return get(/databases/$(database)/documents/businesses/$(bid))
                   .data.get('deactivatedAt', null) == null;
        }
        // [ARCHIVE-RULES-COMPAT] 운영 종료 사업장의 슬롯은 다시 열지 않는다. 구·현재 앱의 직접 쓰기 중
        //   다시 여는 것: 공고 저장 시 마감 시각 재계산(workDetails + closed→open), 업무 재오픈(workDetails),
        //   cascade 재오픈(closed→open). 막지 않는 것: 마감(→closed), 확정 취소 뒤 full→open 재계산,
        //   공개 시각(visibleFrom), 카운터. 운영 중 사업장은 전과 같다.
        function slotNoReopenWhenClosed() {
          return slotBizOpen() ||
                 (!request.resource.data.diff(resource.data).affectedKeys().hasAny(['workDetails']) &&
                  !(resource.data.get('status', '') == 'closed' &&
                    request.resource.data.get('status', '') != 'closed'));
        }
        // SEC-83: 미발행 TO의 슬롯(임금정보 등) 노출 차단 — isPublished 상속 적용`);
rep(`        allow create: if isLoggedIn() && (isToWriteAdmin(toId) || isSuperAdmin()) &&
                        (isSuperAdmin() ||`,
`        allow create: if isLoggedIn() && (isToWriteAdmin(toId) || isSuperAdmin()) &&
                        // [ARCHIVE-RULES-COMPAT] 운영 종료 사업장에는 슬롯을 만들지 않는다(슈퍼관리자 포함)
                        slotBizOpen() &&
                        (isSuperAdmin() ||`);
rep(`        allow update: if isLoggedIn() && (isToWriteAdmin(toId) || isSuperAdmin()) &&
                        // confirmedCount ±1 제한`,
`        allow update: if isLoggedIn() && (isToWriteAdmin(toId) || isSuperAdmin()) &&
                        // [ARCHIVE-RULES-COMPAT] 운영 종료 사업장의 슬롯 재오픈·업무 수정 금지
                        slotNoReopenWhenClosed() &&
                        // confirmedCount ±1 제한`);

fs.writeFileSync(out, s.split('\n').join(EOL));

// ── 증명: applications 블록 원문 그대로, 치환 밖 바이트 동일
const block = (t, open) => {
  const L = t.split('\n'); const st = L.findIndex((l) => l.includes(open)); let d = 0;
  for (let i = st; i < L.length; i++) {
    for (const ch of L[i].split('//')[0]) { if (ch === '{') d++; else if (ch === '}') d--; }
    if (i > st && d === 0) return L.slice(st, i + 1).join('\n');
  }
  throw new Error('블록 닫힘 없음 ' + open);
};
const orig = raw.split(EOL).join('\n');
const appSame = block(orig, 'match /applications/{applicationId} {') === block(s, 'match /applications/{applicationId} {');
// 치환을 되돌리면 원문과 같아야 한다(밖은 바이트 동일)
let back = s;
const pairs = [];
{
  // 원문 ↔ 후보의 차이를 줄 단위로 세어 치환 범위 밖 변화가 없는지 확인
  const a = orig.split('\n'); const b = s.split('\n');
  let i = 0; while (i < a.length && a[i] === b[i]) i++;
  let ja = a.length - 1; let jb = b.length - 1; while (ja >= i && jb >= i && a[ja] === b[jb]) { ja--; jb--; }
  pairs.push([i + 1, ja + 1, jb + 1]);
}
void back;
const bizStart = orig.split('\n').findIndex((l) => l.includes('match /businesses/{businessId} {')) + 1;
const tosEnd = (() => { const L = orig.split('\n'); const st = L.findIndex((l) => l.includes('match /tos/{toId} {')); let d = 0;
  for (let i = st; i < L.length; i++) { for (const ch of L[i].split('//')[0]) { if (ch === '{') d++; else if (ch === '}') d--; } if (i > st && d === 0) return i + 1; } })();
const [first, lastOrig] = pairs[0];
console.log(`치환 ${edits.length}곳 · 원문과 다른 줄 범위 ${first}~${lastOrig}행(원문 기준) · businesses~tos 블록 ${bizStart}~${tosEnd}행`);
console.log(`차이가 businesses~tos 블록 안에만: ${first >= bizStart && lastOrig <= tosEnd} · applications 블록 원문 그대로: ${appSame}`);
console.log(`후보 ${s.split('\n').length}줄 → ${out}`);
if (!(first >= bizStart && lastOrig <= tosEnd) || !appSame) { console.log('FAIL'); process.exit(1); }
