/**
 * [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 판정281] 공통 진입 판정(탈퇴 freeze fence)의 읽기를 **분리 관측**한다.
 *
 *   index.ts 의 모든 callable 은 이제 handler 앞에서 호출자 `account_deletion_tombstones/{uid}` 를 1회 읽는다.
 *   기존 계약 시험들의 "읽기 0/정확한 읽기 목록" 은 handler 의 **업무 읽기**(지원서·제안·사업장 등)에 대한
 *   보장이다. 그 보장을 완화하지 않으려고 fence 읽기를 지우는 대신 여기서 **정확히 검증한 뒤** 별도 목록으로 옮긴다:
 *     · 인증된 호출이면 첫 읽기가 반드시 그 호출자의 tombstone 문서(거래 밖)여야 한다 — 아니면 시험 실패.
 *     · 그 한 건만 W.reads 에서 빼 FENCE_READS 에 남긴다. 나머지 읽기 계약은 원래 단언 그대로 적용된다.
 *
 * @param {object} R 폐포 exports
 * @param {string[]} names callable 이름
 * @param {object} W 가짜 저장소 계측
 * @return {Array<object>} FENCE_READS(관측 목록)
 */
'use strict';
function separateFenceReads(R, names, W) {
  const FENCE_READS = [];
  for (const n of names) {
    const orig = R[n];
    if (typeof orig !== 'function') continue;
    R[n] = (req) => {
      const i0 = W.reads.length;
      const p = orig(req);
      const uid = req && req.auth && req.auth.uid;
      if (uid) {
        const r = W.reads[i0];
        const want = 'account_deletion_tombstones/' + uid;
        if (!r || r.path !== want || r.tx !== null || r.kind !== 'doc') {
          throw new Error(`[fence] ${n}: 첫 읽기가 호출자 탈퇴 상태(${want})가 아니다: ${r && r.path}`);
        }
        W.reads.splice(i0, 1);
        FENCE_READS.push(r);
      }
      return p;
    };
  }
  return FENCE_READS;
}
module.exports = {separateFenceReads};
