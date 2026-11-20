/**
 * [WORKTYPE-IDENTITY] 업무유형 문서 Rules 후보 — 이름·아이콘(색 포함) 고정 + 단건 hard delete 금지.
 *
 *   업무유형 이름·아이콘은 등록 후 바꾸지 않는다(공고·지원·계약이 그것을 저장본으로 들고 있다).
 *   설명·사진·순서·활성 여부는 그대로 고칠 수 있다. 삭제는 isActive:false 뿐이다.
 *   --with-containment: 사업장·멤버 delete 도 막는다(BUSINESS-DELETE-CONTAINMENT 와 같은 세 줄 —
 *   업무유형 delete 는 이 후보가 이미 막는다). applications 블록 등 다른 곳은 건드리지 않는다.
 *
 *   node scripts/build-worktype-identity-rules.js <원문> <출력> [--with-containment]
 *   증명: 바뀐 블록 밖은 원문과 줄 단위로 동일.
 */
'use strict';
const fs = require('fs');
const [src, out, flag] = process.argv.slice(2);
if (!src || !out) throw new Error('사용: <원문> <출력> [--with-containment]');
const raw = fs.readFileSync(src, 'utf8');
const EOL = raw.includes('\r\n') ? '\r\n' : '\n';
let s = raw.split(EOL).join('\n');
function rep(a, b) {
  const n = s.split(a).length - 1; if (n !== 1) throw new Error(`앵커 ${n}회: ${a.slice(0, 90)}`);
  s = s.replace(a, b);
}
const LOCKED = "['businessId', 'name', 'icon', 'color', 'backgroundColor']";
rep(`        allow update: if (isAdminOf(businessId) || (isSubAdminOf(businessId) && subAdminCanManageTo(businessId)) || isSuperAdmin()) &&
                        !request.resource.data.diff(resource.data).affectedKeys().hasAny(['businessId']);
        allow delete: if isAdminOf(businessId) || (isSubAdminOf(businessId) && subAdminCanManageTo(businessId)) || isSuperAdmin();
      }`,
`        // [WORKTYPE-IDENTITY] 이름·아이콘·색은 등록 후 고정(슈퍼관리자 포함) — 공고·지원·계약이 이 값을
        //   저장본으로 들고 있어, 바꾸면 같은 업무가 다른 업무처럼 보인다. 다른 업무는 새 문서로 만든다.
        //   설명·사진·순서·isActive 는 고칠 수 있다. 같은 값을 다시 쓰는 것은 바뀐 키가 아니므로 통과한다.
        allow update: if (isAdminOf(businessId) || (isSubAdminOf(businessId) && subAdminCanManageTo(businessId)) || isSuperAdmin()) &&
                        !request.resource.data.diff(resource.data).affectedKeys().hasAny(${LOCKED});
        // [WORKTYPE-IDENTITY] 단건 hard delete 금지(슈퍼관리자 포함) — 삭제는 isActive:false 뿐이다. 기존 공고는
        //   이 문서의 최신 안내를 읽는다. (구 앱의 사업장 삭제 일괄 batch 도 이 줄에서 통째로 거절된다.)
        allow delete: if false;
      }`);
if (flag === '--with-containment') {
  const note = (what) => [
    `      // [BUSINESS-DELETE-CONTAINMENT] ${what} 클라이언트 직접 삭제 금지(슈퍼관리자 포함).`,
    '      //   구 앱의 사업장 삭제가 이것을 사업장 삭제 직전에 일괄로 지운다 — 막지 않으면 사업장 삭제만',
    '      //   거절돼도 이것만 사라진다. 정상 운영은 소프트 삭제·Admin SDK callable 을 쓴다.',
  ].join('\n');
  rep('      allow delete: if (isAdminOf(businessId) && resource.data.ownerId == request.auth.uid) || isSuperAdmin();',
    `${note('사업장 문서')}\n      allow delete: if false;`);
  rep(`      allow delete: if isLoggedIn() && (
                      isAdminOf(businessId) ||
                      (request.auth.uid == uid && !isSubAdminOf(businessId)) ||
                      isSuperAdmin()
                    );
    }`, `${note('멤버 문서(제외는 callableRemoveMember·callableLeaveAsSubAdmin)')}\n      allow delete: if false;\n    }`);
}
fs.writeFileSync(out, s.split('\n').join(EOL));
// 증명: 줄 단위 diff — 후보에만 있는 줄은 주석 또는 바뀐 allow 줄, 원문에만 있는 줄은 바뀐 allow 줄뿐
const A = raw.split(EOL).join('\n').split('\n'); const B = s.split('\n');
const setA = new Map(); for (const l of A) setA.set(l, (setA.get(l) || 0) + 1);
const setB = new Map(); for (const l of B) setB.set(l, (setB.get(l) || 0) + 1);
const onlyB = B.filter((l) => (setA.get(l) || 0) < (setB.get(l) || 0));
const onlyA = A.filter((l) => (setB.get(l) || 0) < (setA.get(l) || 0));
const okB = onlyB.every((l) => /^\s*\/\/|allow (update|delete):|affectedKeys\(\)\.hasAny\(\['businessId', 'name'/.test(l));
const okA = onlyA.every((l) => /allow delete:|affectedKeys\(\)\.hasAny\(\['businessId'\]\)|isAdminOf\(businessId\) \|\||request\.auth\.uid == uid && !isSubAdminOf|isSuperAdmin\(\)$|^\s+\);$/.test(l));
console.log(`후보 ${B.length}줄 · 원문에만 ${onlyA.length}줄 · 후보에만 ${onlyB.length}줄 · 바뀐 블록 밖 동일 ${okA && okB} → ${out}`);
if (!(okA && okB)) { console.log(onlyA.slice(0, 5), onlyB.slice(0, 5)); process.exit(1); }
