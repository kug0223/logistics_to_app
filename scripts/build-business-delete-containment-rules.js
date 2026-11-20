/**
 * [BUSINESS-DELETE-CONTAINMENT] 사업장 하드 삭제와 그 **선행 일괄 삭제**를 함께 막는 Rules 후보.
 *
 *   구 앱(HEAD 1.0.20 business_list_screen._deleteBusiness)은 workTypes 전부 + members 전부를 **같은 batch**
 *   (499건 단위)로 지운 뒤 사업장 문서를 따로 지운다. 사업장 delete 만 막으면 앞의 batch 는 이미 커밋돼
 *   업무유형·멤버만 사라진다. 세 delete 를 모두 막으면 그 batch 가 통째로 거절되고(원자적) 앱은 사업장 삭제
 *   전에 멈춘다 — 아무것도 지워지지 않는다.
 *   정상 운영은 이 delete 를 쓰지 않는다(전수 확인, 1.0.1+5 이후 배포본 전부):
 *     업무유형 삭제 = update {isActive:false}(소프트 삭제) · 멤버 제외 = callableRemoveMember / callableLeaveAsSubAdmin(Admin SDK)
 *
 *   node scripts/build-business-delete-containment-rules.js <원문> <출력>
 *   증명: 원문과 다른 곳이 세 delete 문뿐이고 나머지는 바이트 동일.
 */
'use strict';
const fs = require('fs');
const [src, out] = process.argv.slice(2);
if (!src || !out) throw new Error('사용: <원문> <출력>');
const raw = fs.readFileSync(src, 'utf8');
const EOL = raw.includes('\r\n') ? '\r\n' : '\n';
let s = raw.split(EOL).join('\n');
const spans = [];
function rep(a, b) {
  const n = s.split(a).length - 1; if (n !== 1) throw new Error(`앵커 ${n}회: ${a.slice(0, 70)}`);
  const at = s.indexOf(a); spans.push([at, at + b.length]); s = s.replace(a, b);
}
const note = (what) => [
  `      // [BUSINESS-DELETE-CONTAINMENT] ${what} 클라이언트 직접 삭제 금지(슈퍼관리자 포함).`,
  '      //   구 앱의 사업장 삭제가 이것을 사업장 삭제 직전에 일괄로 지운다 — 막지 않으면 사업장 삭제만',
  '      //   거절돼도 이것만 사라진다. 정상 운영은 소프트 삭제·Admin SDK callable 을 쓴다.',
].join('\n');
// ① businesses
rep('      allow delete: if (isAdminOf(businessId) && resource.data.ownerId == request.auth.uid) || isSuperAdmin();',
  `${note('사업장 문서')}\n      allow delete: if false;`);
// ② workTypes (businesses/{id}/workTypes)
rep('        allow delete: if isAdminOf(businessId) || (isSubAdminOf(businessId) && subAdminCanManageTo(businessId)) || isSuperAdmin();\n      }\n\n      match /contract_templates/{templateId} {',
  `  ${note('업무유형(삭제는 isActive:false 소프트 삭제로만)').split('\n').join('\n  ')}\n        allow delete: if false;\n      }\n\n      match /contract_templates/{templateId} {`);
// ③ members (businesses/{id}/members)
rep(`      allow delete: if isLoggedIn() && (
                      isAdminOf(businessId) ||
                      (request.auth.uid == uid && !isSubAdminOf(businessId)) ||
                      isSuperAdmin()
                    );
    }`, `${note('멤버 문서(제외는 callableRemoveMember·callableLeaveAsSubAdmin)')}\n      allow delete: if false;\n    }`);
fs.writeFileSync(out, s.split('\n').join(EOL));
// 증명: 바뀐 세 구간 밖은 원문과 바이트 동일
const orig = raw.split(EOL).join('\n');
let i = 0; let ok = true; let cursor = 0;
for (const [a, b] of spans.sort((x, y) => x[0] - y[0])) {
  void a; void b;
}
// 줄 단위 대조: 원문과 후보의 공통 앞부분·뒷부분 사이만 달라야 하고, 다른 줄은 모두 delete 문/주석이어야 한다
const A = orig.split('\n'); const B = s.split('\n');
const diffLines = [];
{
  // 간단한 LCS 없이: 순차 정렬 — 후보의 추가 줄은 '[BUSINESS-DELETE-CONTAINMENT]' 주석 또는 'allow delete: if false;'
  let ai = 0;
  for (let bi = 0; bi < B.length; bi++) {
    if (ai < A.length && A[ai] === B[bi]) { ai++; continue; }
    const added = /BUSINESS-DELETE-CONTAINMENT|구 앱의 사업장 삭제가 이것을|거절돼도 이것만 사라진다|allow delete: if false;/.test(B[bi]);
    if (!added) { ok = false; diffLines.push(`+${bi + 1}: ${B[bi]}`); }
    // 원문의 바뀐 delete 문(들)은 건너뛴다
    while (ai < A.length && A[ai] !== B[bi + 1] && /allow delete:|isAdminOf\(businessId\) \|\||request\.auth\.uid == uid && !isSubAdminOf|isSuperAdmin\(\)$|^\s+\);$/.test(A[ai]) && !/allow delete: if false;/.test(B[bi])) ai++;
  }
  if (ai !== A.length) { ok = false; diffLines.push(`원문 남은 줄 ${A.length - ai}`); }
}
void i; void cursor;
console.log(`치환 ${spans.length}곳 · 바뀐 곳 밖 동일 ${ok}${diffLines.length ? ' · ' + diffLines.slice(0, 3).join(' | ') : ''} · 후보 ${B.length}줄 → ${out}`);
if (!ok) process.exit(1);
