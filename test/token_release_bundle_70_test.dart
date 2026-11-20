// [.70] .68(로그아웃 토큰 정리 4초 상한)과 .69(기기 토큰 폐기·폐기 대기 재처리)는 한 출시 단위다.
//   .68만 들어가면 오프라인 로그아웃 뒤 이전 계정 토큰이 남아 다음 계정 기기로 발송된다(.69 재현).
//   이 시험은 최종 소스에 두 변경이 **함께** 들어 있는지를 고정한다(동작은 fcm_token_revoker_69_test 가 본다).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  final provider = _read('lib/providers/user_provider.dart');
  final fcm = _read('lib/services/fcm_service.dart');
  final main = _read('lib/main.dart');

  test('[T70-a] 로그아웃은 상한(.68)과 기기 토큰 폐기(.69)를 함께 쓴다', () {
    expect(provider, contains('clearToken(networkTimeout: const Duration(seconds: 4), revokeDevice: true)'));
    expect(provider.contains('await FCMService().clearToken(networkTimeout: const Duration(seconds: 4));'), isFalse,
        reason: '.68 만의 형태(폐기 없음)가 남아 있으면 안 된다');
  });

  test('[T70-b] 로그인 등록은 남은 폐기를 먼저 끝낸 뒤에만(.69)', () {
    final i = fcm.indexOf('final revokeSettled = await _revoker.settle(');
    final j = fcm.indexOf('if (authorized && revokeSettled && _currentUserId == userId) await _saveToken();');
    expect(i, greaterThan(-1));
    expect(j, greaterThan(i));
  });

  test('[T70-c] 앱 시작에서 폐기 대기를 이어받는다(.69)', () {
    expect(main, contains('unawaited(FCMService().settlePendingRevoke());'));
  });

  test('[T70-d] 상태·구독 정리가 네트워크 대기보다 먼저(.68 순서)', () {
    final reset = fcm.indexOf('_currentUserId = null;\n    _isInitialized = false;');
    final net = fcm.indexOf('currentToken = await bounded(_messaging.getToken());');
    expect(reset, greaterThan(-1), reason: '정리 위치(줄바꿈 LF 기준)');
    expect(net, greaterThan(reset));
  });
}
