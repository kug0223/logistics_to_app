// [DOC-DEV-ROLLOUT.9] 외국인 가입 확정의 재가입 제한 안내 — 서버 문장으로 기간 제한/재가입 불가만 가르고,
//   날짜·기간은 만들지 않는다. 서버 문장은 functions/src/index.ts callableFinalizeForeignIdentity 의 것.
import 'dart:io';

import 'package:ALfit/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final m = AuthService.signupRestrictionMessage;

  test('SR-1 서버가 영구 제한이라고 말하면 재가입 불가', () {
    expect(m('이용 정책 위반으로 재가입이 영구 제한된 계정입니다.'), '현재 이 계정은 재가입할 수 없어요.');
  });

  test('SR-2 탈퇴 후 기간 제한 — 날짜·일수를 만들지 않는다', () {
    final t = m('탈퇴 후 1개월이 지난 후 재가입 가능합니다.');
    expect(t, contains('재가입 제한 기간'));
    expect(RegExp(r'\d').hasMatch(t), isFalse, reason: '종료 시각을 받지 않았으므로 숫자(날짜·일수)가 없다');
    expect(t.contains('재가입할 수 없어요'), isFalse, reason: '기한 있는 제한을 영구처럼 말하지 않는다');
  });

  test('SR-3 그 밖·문장 없음 → 사실만 말하는 일반 문구(영구·기간 추정 없음 · 원문 노출 없음)', () {
    for (final s in [null, '', 'permission-denied', '내부 오류 at srvX: uid=abc']) {
      final t = m(s);
      expect(t, '가입이 제한된 계정이에요.');
      expect(t.contains('uid'), isFalse);
    }
  });

  test('SR-4 서버 문장이 바뀌면 이 시험이 알려 준다 — 두 문장은 지금 서버 원문에 있다', () {
    final src = File('functions/src/index.ts').readAsStringSync();
    expect(src, contains('"이용 정책 위반으로 재가입이 영구 제한된 계정입니다."'));
    expect(src, contains('"탈퇴 후 1개월이 지난 후 재가입 가능합니다."'));
  });

  // [DOC-APP-CLOSEOUT.10] failed-precondition — 같은 코드의 두 사유를 나눈다.
  final p = AuthService.finalizePreconditionMessage;
  test('FP-1 나이 미달은 기존 나이 안내 그대로', () {
    expect(p('만 19세 이상만 가입할 수 있습니다.'), '만 19세 이상만 가입할 수 있습니다.');
  });
  test('FP-2 탈퇴 동결은 실제 상태 — 나이·시각·재가입 시점 없음', () {
    final t = p('탈퇴 처리 중인 계정입니다.');
    expect(t, '탈퇴 처리 중에는 가입을 완료할 수 없어요.');
    expect(t.contains('19세'), isFalse);
    expect(RegExp(r'\d').hasMatch(t), isFalse);
  });
  test('FP-3 구 서버·알 수 없는 사유 → 중립(나이·영구 단정 없음 · 원문 미노출)', () {
    for (final s in [null, '', 'FAILED_PRECONDITION', 'srvX failed uid=abc 9001015000001']) {
      final t = p(s);
      expect(t, '현재 계정 상태로 가입을 완료할 수 없어요.');
      expect(t.contains('19세') || t.contains('영구') || t.contains('uid'), isFalse);
    }
  });
  test('FP-4 두 문장은 서버 원문에 있고, 매핑이 이 함수를 쓴다', () {
    final src = File('functions/src/index.ts').readAsStringSync();
    expect(src, contains('"만 19세 이상만 가입할 수 있습니다."'));
    expect(src, contains('"탈퇴 처리 중인 계정입니다."'));
    final a = File('lib/services/auth_service.dart').readAsStringSync();
    expect(a, contains("'failed-precondition'=> finalizePreconditionMessage(e.message),"));
  });

  test('SR-5 권한 거절 매핑이 이 함수를 쓴다', () {
    final src = File('lib/services/auth_service.dart').readAsStringSync();
    expect(src, contains("'permission-denied'  => signupRestrictionMessage(e.message),"));
    expect(src.contains("'가입이 제한된 계정입니다. 고객센터에 문의해주세요.'"), isFalse);
  });
}
