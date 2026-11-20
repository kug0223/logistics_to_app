import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/posting_partial_revoke.dart';

/// [POSTING-AUTH-45] 권한 회수로 앞 단계만 반영된 거절을 일반 권한 거절과 가른다.
void main() {
  FirebaseFunctionsException fx(String code, [Object? details]) =>
      FirebaseFunctionsException(code: code, message: 'TO 관리 권한이 없습니다.', details: details);

  test('PR-1 details.code 가 PERMISSION_REVOKED_MIDWAY 인 permission-denied 만 부분 반영이다', () {
    expect(isPostingPartialRevoke(fx('permission-denied', {'code': 'PERMISSION_REVOKED_MIDWAY', 'slotsClosed': 2})), isTrue);
    expect(isPostingPartialRevoke(fx('permission-denied')), isFalse);
    expect(isPostingPartialRevoke(fx('permission-denied', {'code': 'OTHER'})), isFalse);
    expect(isPostingPartialRevoke(fx('failed-precondition', {'code': 'PERMISSION_REVOKED_MIDWAY'})), isFalse);
    expect(isPostingPartialRevoke(Exception('x')), isFalse);
  });

  test('PR-2 호출부 3곳이 부분 반영이면 목록을 새로 읽는다', () {
    final card = File('lib/widgets/admin/cards/admin_to_group_card.dart').readAsStringSync();
    expect(RegExp(r'isPostingPartialRevoke\(e\)\) \{\s*// \[POSTING-AUTH-45\][^\n]*\n\s*widget\.firestoreService\.clearCache\(toId: masterTO\.id\);\s*widget\.onChanged\(\);')
        .allMatches(card).length, 2);
    final svc = File('lib/services/firestore/to_firestore.dart').readAsStringSync();
    expect(RegExp(r'if \(isPostingPartialRevoke\(e\)\) \{\s*clearCache\(toId: toId\);\s*ToastHelper\.showWarning\(postingPartialRevokeMessage\);\s*return true;')
        .hasMatch(svc), isTrue);
  });

  test('PR-4 [.46] 실제 writer 응답 두 갈래 — 첫 보호 쓰기 전 거절은 일반 권한 거절, 닫기 커밋 뒤 거절은 부분 반영', () {
    // c46/b44-race.txt B-deleteSlots-3 · B-closeSlots-5 (현재 DEV P2/P3 와 같은 코드 + 경합 후보)의 응답을
    //   서버 SDK 직렬화(HttpsError.toJSON) 그대로 옮겼다:
    //   {"error":{"details":{"code":"PERMISSION_REVOKED_MIDWAY","slotsClosed":1,"applicationsRejected":0},"status":"PERMISSION_DENIED"}}
    //   {"error":{"status":"PERMISSION_DENIED"}}  — details 없음
    final before = FirebaseFunctionsException(code: 'permission-denied', message: 'TO 관리 권한이 없습니다.');
    final after = FirebaseFunctionsException(code: 'permission-denied', message: 'TO 관리 권한이 없습니다.',
        details: <String, Object?>{'code': 'PERMISSION_REVOKED_MIDWAY', 'slotsClosed': 1, 'applicationsRejected': 0});
    expect(isPostingPartialRevoke(before), isFalse);
    expect(isPostingPartialRevoke(after), isTrue);
  });

  test('PR-5 [.46] 안내는 목록 갱신 결과를 단정하지 않는다(갱신 실패는 목록 화면이 따로 알린다)', () {
    expect(postingPartialRevokeMessage.contains('불러왔어요'), isFalse);
    final list = File('lib/screens/business_admin/workforce_management/workforce_list_view.dart').readAsStringSync();
    expect(list.contains("ToastHelper.showError('공고 목록을 새로고침하지 못했습니다');"), isTrue);
  });

  test('PR-3 안내는 재시도를 권하지 않고 개발 용어가 없다', () {
    expect(postingPartialRevokeMessage.contains('다시 시도'), isFalse);
    expect(RegExp(r'[A-Z_]{4,}').hasMatch(postingPartialRevokeMessage), isFalse);
  });
}
