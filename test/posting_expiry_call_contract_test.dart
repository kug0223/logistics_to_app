// [.11 POSTING-EXPIRY-CALL 2026-10-27] 장기 공고 게시 만료가 신청 마감 쪽 결과에 끌려 빠지지 않는다.
//
//   예전 processTOExpiry 는 한 함수였고 신청 마감 대상이 0 이면 앞에서 return 해 게시 만료 구간이 그 시간에
//   아예 돌지 않았다(LOCAL 재현 — 신청 마감 0 / 게시 만료 1 에서 장기 공고가 ACTIVE 로 남음).
//   행동 검증은 retry11/run11.sh(에뮬레이터)가 하고, 여기서는 그 호출 경계가 되돌아가지 않게 고정한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _fn(String src, String head) {
  final a = src.indexOf(head);
  if (a < 0) throw StateError('찾지 못함: $head');
  return src.substring(a, src.indexOf('\n}\n', a));
}

void main() {
  final src = File('functions/src/index.ts').readAsStringSync();

  test('PEC-01 processTOExpiry 는 두 부분을 순서대로 부르고, 게시 만료는 앞 부분 결과와 무관하게 돈다', () {
    final f = _fn(src, 'async function processTOExpiry(');
    final a = f.indexOf('await srvTOApplicationDeadlineExpiry(now);');
    final b = f.indexOf('await srvContractPostingExpiry(now);');
    expect(a, greaterThan(0));
    expect(b, greaterThan(a), reason: '순서(신청 마감 → 게시 만료)를 유지한다');
    // 앞 부분은 try 안이고, 게시 만료 호출은 try/catch 바깥이다(앞 부분 실패가 게시 만료를 건너뛰지 않음)
    expect(f.substring(0, a), contains('try {'));
    expect(f.substring(a, b), contains('catch (e)'));
    // 앞 부분의 실패는 삼키지 않고 다시 던진다 — 핸들러의 '[TO 마감] 실패' 집계 유지
    expect(f.substring(b), contains('if (deadlineError) throw deadlineError;'));
    // 이 함수 자체에는 조기 return 이 없다
    expect(f.contains('return;'), isFalse);
  });

  test('PEC-02 게시 만료 구간은 자기 함수에 있고, 신청 마감 함수에는 없다', () {
    final dl = _fn(src, 'async function srvTOApplicationDeadlineExpiry(');
    final pe = _fn(src, 'async function srvContractPostingExpiry(');
    expect(dl.contains('postingExpiryDate'), isFalse);
    expect(pe, contains('.where("postingExpiryDate", "<=", now)'));
    expect(pe, contains('closedReason: "POSTING_EXPIRED"'));
    // 부정 대조: 예전처럼 신청 마감 함수 안에서 게시 만료를 다시 부르지 않는다
    expect(dl.contains('srvContractPostingExpiry('), isFalse);
  });
}
