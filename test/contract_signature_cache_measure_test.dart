// [CONTRACT-PDF-REMEDIATION.3 §3] `CachedNetworkImage` 가 **짧은 Signed URL** 과
// 함께 쓰일 때 실제로 문제가 되는지 **측정**한다.
//
//   §3: "CachedNetworkImage 의 캐시 키 변경 문제는 실제 렌더·조회 문제가
//        재현되는지 확인한다. **측정 없이 새로운 바이트 캐시 시스템을
//        구축하지 않는다.**"
//
//   그래서 이 파일은 **고치지 않는다.** 재는 것이 전부다:
//     ① 캐시 키가 URL 인가 — 같은 이미지라도 서명이 바뀌면 다시 받는가
//     ② 그 문제를 라이브러리가 이미 해결할 수단을 주는가 (`cacheKey`)
//     ③ 서명 PNG 가 계약 1건 화면에서 몇 번 쓰이는가 (전환 비용의 크기)
//
//   네트워크를 쓰지 않는다. 위젯 속성과 소스만 본다.
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  // ══════════════════════════════════════════════════════════════════
  // ① 캐시 키가 URL 이라는 사실
  // ══════════════════════════════════════════════════════════════════
  test('SIGC-01 cacheKey 를 주지 않으면 URL 이 캐시 키가 된다', () {
    // 같은 파일을 가리키지만 서명 파라미터가 다른 두 URL.
    final a = CachedNetworkImage(
        imageUrl: 'https://x/o/sig.png?X-Goog-Signature=AAA&Expires=1');
    final b = CachedNetworkImage(
        imageUrl: 'https://x/o/sig.png?X-Goog-Signature=BBB&Expires=2');
    expect(a.cacheKey, isNull,
        reason: 'cacheKey 가 null 이면 라이브러리는 imageUrl 을 키로 쓴다');
    expect(b.cacheKey, isNull);
    expect(a.imageUrl == b.imageUrl, isFalse,
        reason: '서명이 바뀌면 URL 이 달라진다 = 키가 달라진다');
  });

  // ══════════════════════════════════════════════════════════════════
  // ② 라이브러리가 이미 해결 수단을 준다
  // ══════════════════════════════════════════════════════════════════
  test('SIGC-02 cacheKey 를 주면 URL 이 달라도 같은 키가 된다', () {
    const key = 'contract_c1_employer';
    final a = CachedNetworkImage(
        imageUrl: 'https://x/o/sig.png?sig=AAA', cacheKey: key);
    final b = CachedNetworkImage(
        imageUrl: 'https://x/o/sig.png?sig=BBB', cacheKey: key);
    expect(a.cacheKey, b.cacheKey);
    expect(a.cacheKey, key);
  });

  // ══════════════════════════════════════════════════════════════════
  // ③ 전환 비용의 크기 — 계약 1건 화면의 서명 이미지 수
  // ══════════════════════════════════════════════════════════════════
  test('SIGC-03 계약 미리보기의 서명 이미지는 둘이고, 로드 지점은 하나다', () {
    final sign = _read('lib/screens/contract/contract_sign_screen.dart');
    // 서명란은 사업주(갑)·근로자(을) 두 블록이다.
    //   `const _SignBlock({` 은 생성자 선언이므로 **사용처만** 센다.
    final blocks = RegExp(r'child: _SignBlock\(').allMatches(sign).length;
    expect(blocks, 2, reason: '서명 블록 수가 바뀌면 전환 비용도 바뀐다');
    // [R8P6-SIG-CUTOVER] 전환 뒤: 두 블록이 **계약 id + 역할**을 받는다.
    //   예전에는 `imageUrl: employerSignatureUrl`(영구 토큰)이었다.
    expect(sign, contains("role: 'employer'"));
    expect(sign, contains("role: 'worker'"));
    expect(sign.contains('imageUrl: employerSignatureUrl'), isFalse);
    expect(sign.contains('imageUrl: workerSignatureUrl'), isFalse);
    // 실제 로드는 CachedNetworkImage 하나를 지난다 — 전환도 한 곳이었다.
    expect(RegExp(r'CachedNetworkImage\(').allMatches(sign).length, 1,
        reason: '로드 지점이 하나여야 전환도 한 곳이다');
  });

  test('SIGC-04 PDF 생성기는 네트워크를 쓰지 않는다 (바이트를 받는다)', () {
    final pdf = _read('lib/screens/contract/contract_pdf_builder.dart');
    // [R8P6-SIG-CUTOVER] 측정 당시엔 `http.get` 1회였다. 전환 뒤엔 0이다 —
    //   빌더는 순수 렌더러가 되고, 권한·만료·재시도는 서비스 한 곳이 가진다.
    expect(RegExp(r'http\.get\(').allMatches(pdf).length, 0,
        reason: '빌더가 다시 직접 가져오면 권한·재시도가 두 곳으로 흩어진다');
    // 사업주·근로자 서명이 **같은 모양**이 됐다 — 둘 다 바이트다.
    expect(pdf, contains('Uint8List? employerSignatureBytes'));
    expect(pdf, contains('Uint8List? workerSignatureBytes'));
  });

  // ══════════════════════════════════════════════════════════════════
  // ④ 측정 결론 — 짓지 않는다
  // ══════════════════════════════════════════════════════════════════
  test('SIGC-05 측정 결론 — 새 바이트 캐시 시스템은 필요하지 않았다', () {
    // 재현된 문제: URL 이 캐시 키이므로 15분 Signed URL 을 매번 새로 받으면
    //   같은 서명 이미지를 매번 다시 내려받는다(캐시 무효화).
    //
    // 그런데 `CachedNetworkImage` 가 **이미** `cacheKey` 를 받는다(SIGC-02).
    //   → 새 시스템을 만들 이유가 없다. **인자 하나를 넘기는 문제다.**
    //   전환은 실제로 그 한 가지로 끝났다(SIGC-03·04).
    //
    // [정정 — SIG-CUTOVER §5] 측정 당시의 결론은 키를 `contractId + role` 로
    //   하자는 것이었다. **그것만으로는 틀렸다.** 서버의
    //   `_newContractAttemptPrefix` 가 요청마다 무작위 16바이트를 쓰므로,
    //   같은 계약을 재서명하면 **새 경로에 새 파일**이 저장된다. 계약·역할만으로
    //   키를 만들면 옛 키가 옛 서명 이미지를 계속 돌려준다.
    //   그래서 서버가 `signatureVersion`(그 attempt)을 함께 돌려주고,
    //   키는 `계약 + 역할 + 판` 세 조각이 된다.
    final sign = _read('lib/screens/contract/contract_sign_screen.dart');
    expect(sign, contains("cacheKey: 'contract_sig_"));
    expect(sign, contains(r'${link.version}'),
        reason: '판이 키에 없으면 재서명 후 옛 이미지가 남는다');
    final svc = _read('lib/services/contract_service.dart');
    expect(svc, contains("data?['signatureVersion']"));
  });
}
