/**
 * [ALFIT-AUTH-KAKAO-ONBOARDING.1 §3] 외부 호출 경계 — 카카오 토큰 정보 · PortOne 인증 조회.
 *
 *   이 모듈만 네트워크에 닿는다. 시험은 이 모듈 대신 가짜 어댑터를 주입한다
 *   (auth_kakao.ts 는 어댑터를 인자로 받는다). 모듈 평가 시점 네트워크 0.
 *
 *   실 연동은 PENDING VERIFICATION(X1–X4): 카카오 앱 id 허용 목록·PortOne V1
 *   응답 필드(merchant_uid·certified_at·pg_provider)의 실제 존재는 대표 외부
 *   준비 뒤 확인한다. 응답 해석 규칙은 signup_core.parsePortOneCertification.
 */

/** 카카오 토큰 검증 결과 — subject·appId 는 **서버가** 응답에서 꺼낸 값. */
export type KakaoTokenInfo =
  | {ok: true; subject: string; appId: string; expiresInSec: number}
  | {ok: false; reason: "KAKAO_TOKEN_INVALID" | "KAKAO_UNAVAILABLE"};

export interface KakaoTokenVerifier {
  verify(accessToken: string): Promise<KakaoTokenInfo>;
}

/** PortOne 조회 결과 — 원 응답 JSON 을 그대로 돌려주고 해석은 순수 모듈이 한다. */
export type PortOneRead =
  | {ok: true; raw: unknown}
  | {ok: false; reason: "PORTONE_UNAVAILABLE" | "PORTONE_TOKEN_FAILED"};

export interface PortOneCertReader {
  read(args: {impKey: string; impSecret: string; impUid: string}): Promise<PortOneRead>;
}

const KAKAO_TOKEN_INFO_URL = "https://kapi.kakao.com/v1/user/access_token_info";
const PORTONE_TOKEN_URL = "https://api.iamport.kr/users/getToken";
const PORTONE_CERT_URL = "https://api.iamport.kr/certifications/";

/**
 * 카카오 `GET /v1/user/access_token_info` (Bearer). 응답 `id`·`app_id`·`expires_in`.
 *   별도 Admin/Client Secret 불필요(판정277 X4 정정). 401 = 무효 토큰.
 */
export const kakaoTokenVerifierHttp: KakaoTokenVerifier = {
  async verify(accessToken: string): Promise<KakaoTokenInfo> {
    let res: Response;
    try {
      res = await fetch(KAKAO_TOKEN_INFO_URL, {
        method: "GET",
        headers: {Authorization: `Bearer ${accessToken}`},
      });
    } catch (_e) {
      return {ok: false, reason: "KAKAO_UNAVAILABLE"};
    }
    if (res.status === 401 || res.status === 400) return {ok: false, reason: "KAKAO_TOKEN_INVALID"};
    if (!res.ok) return {ok: false, reason: "KAKAO_UNAVAILABLE"};
    let body: Record<string, unknown>;
    try {
      body = await res.json() as Record<string, unknown>;
    } catch (_e) {
      return {ok: false, reason: "KAKAO_UNAVAILABLE"};
    }
    const id = body["id"];
    const appId = body["app_id"];
    const exp = body["expires_in"];
    if ((typeof id !== "number" && typeof id !== "string") ||
        (typeof appId !== "number" && typeof appId !== "string") ||
        typeof exp !== "number") {
      return {ok: false, reason: "KAKAO_TOKEN_INVALID"};
    }
    return {ok: true, subject: String(id), appId: String(appId), expiresInSec: exp};
  },
};

/** PortOne V1 — 토큰 발급 후 `/certifications/{imp_uid}` 조회. 키는 호출자(핸들러)가 넘긴다. */
export const portOneCertReaderHttp: PortOneCertReader = {
  async read({impKey, impSecret, impUid}): Promise<PortOneRead> {
    try {
      const tokenRes = await fetch(PORTONE_TOKEN_URL, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({imp_key: impKey, imp_secret: impSecret}),
      });
      const tokenData = await tokenRes.json() as {response?: {access_token?: string}};
      const accessToken = tokenData.response?.access_token;
      if (!accessToken) return {ok: false, reason: "PORTONE_TOKEN_FAILED"};
      const certRes = await fetch(PORTONE_CERT_URL + encodeURIComponent(impUid), {
        headers: {Authorization: accessToken},
      });
      return {ok: true, raw: await certRes.json()};
    } catch (_e) {
      return {ok: false, reason: "PORTONE_UNAVAILABLE"};
    }
  },
};

/**
 * DEV 모의(AUTH_MOCK_MODE, 비 prod 전용). 실 연동 결과와 섞이지 않게 호출자가
 * `evidence:'mock'` 으로 표시한다.
 *   · 카카오: `mock-kakao:{subject}` → subject, appId 는 설정값.
 *   · PortOne: `mock-imp:{seed}` → seed 별 고정 CI(같은 사람 시나리오 재현).
 */
export function mockKakaoVerifier(appId: string): KakaoTokenVerifier {
  return {
    async verify(t: string): Promise<KakaoTokenInfo> {
      const m = /^mock-kakao:([0-9]{1,20})$/.exec(t);
      if (!m) return {ok: false, reason: "KAKAO_TOKEN_INVALID"};
      return {ok: true, subject: m[1], appId, expiresInSec: 3600};
    },
  };
}

/**
 * @param {function(): {requestId: string, nowMs: number}} ctx 세션 cert 정보
 * @return {PortOneCertReader} 모의 리더
 */
export function mockPortOneReader(
  ctx: () => {requestId: string; nowMs: number}): PortOneCertReader {
  return {
    async read({impUid}): Promise<PortOneRead> {
      const m = /^mock-imp:([A-Za-z0-9]{1,32})(?:-[A-Za-z0-9]{1,32})?$/.exec(impUid);
      if (!m) return {ok: true, raw: {code: -1, response: null}};
      const {requestId, nowMs} = ctx();
      return {ok: true, raw: {code: 0, response: {
        certified: true,
        unique_key: `MOCK-CI-${m[1]}`,
        name: "홍길동",
        birthday: "1990-01-15",
        phone: "01012345678",
        gender: "male",
        merchant_uid: requestId,
        certified_at: Math.floor(nowMs / 1000),
        pg_provider: "inicis_unified",
      }}};
    },
  };
}
