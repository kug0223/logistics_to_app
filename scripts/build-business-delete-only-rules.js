/**
 * [BUSINESS-DELETE-ISOLATION] DEV 활성 ruleset 원문에서 **businesses 문서의 클라이언트 delete 한 줄만** false 로
 *   바꾼 후보를 만든다. archive-compat 후보·작업 트리 firestore.rules 와 별개다.
 *     node scripts/build-business-delete-only-rules.js <DEV 활성 원문> <출력>
 *   증명: 원문과 다른 줄이 그 delete 문(주석 포함) 하나뿐이고, 나머지는 바이트 동일.
 */
'use strict';
const fs = require('fs');
const [src, out] = process.argv.slice(2);
if (!src || !out) throw new Error('사용: <DEV 활성 원문> <출력>');
const raw = fs.readFileSync(src, 'utf8');
const EOL = raw.includes('\r\n') ? '\r\n' : '\n';
const lines = raw.split(EOL);
const target = '      allow delete: if (isAdminOf(businessId) && resource.data.ownerId == request.auth.uid) || isSuperAdmin();';
const idx = lines.findIndex((l) => l === target);
if (idx < 0 || lines.filter((l) => l === target).length !== 1) throw new Error('businesses delete 문을 정확히 하나 찾지 못함');
const repl = [
  '      // [BUSINESS-DELETE-ISOLATION] 사업장 문서 클라이언트 직접 삭제 금지(슈퍼관리자 포함).',
  '      //   하드 삭제는 onBusinessDeleted 가 공고·지원서까지 지운다 — 기록을 남기는 운영 종료는',
  '      //   callableArchiveOwnBusiness / callableManageBusiness(Admin SDK, Rules 무관)가 맡는다.',
  '      allow delete: if false;',
];
const next = [...lines.slice(0, idx), ...repl, ...lines.slice(idx + 1)];
fs.writeFileSync(out, next.join(EOL));
// 증명
const sameBefore = lines.slice(0, idx).join('\n') === next.slice(0, idx).join('\n');
const sameAfter = lines.slice(idx + 1).join('\n') === next.slice(idx + repl.length).join('\n');
console.log(`바꾼 줄 ${idx + 1}행 1줄 → ${repl.length}줄 · 앞 바이트 동일 ${sameBefore} · 뒤 바이트 동일 ${sameAfter} · 후보 ${next.length}줄`);
if (!sameBefore || !sameAfter) { console.log('FAIL'); process.exit(1); }
