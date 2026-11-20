import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// [POSTING-AUTH-43] 수정은 커밋되고 공개만 실패했을 때(한도 등)의 다음 저장
//
// Pixel_5 .42 관찰: 한도로 공개만 실패한 저장 뒤 같은 화면·목록에서 다시 저장하면
// '수정 내용 충돌'. 원인은 updateTO 가 이미 editRevision 을 올렸는데 화면은
// widget.to.editRevision(열 때 값)을 계속 보냈고, 목록도 새로고침 신호를 받지 못한 것.
//
//   ER-1 저장 경로 3곳이 같은 기준값(_expectedEditRevision)을 쓴다.
//   ER-2 수정 커밋 뒤 실패(두 경로)에서 서버 현재값을 다시 읽는다 — 추정 +1 아님, 재전송 아님.
//   ER-3 나갈 때 서버가 바뀌었으면 true 로 pop → 목록 onReturn 이 새로고침한다.
//   ER-4 충돌 검사 자체는 그대로다(서버 expectedEditRevision 계약 유지).
// ═══════════════════════════════════════════════════════════════

const _editPath = 'lib/screens/business_admin/to_management/edit_to_screen.dart';

String _code() => File(_editPath)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  final code = _code();

  test('ER-1 updateTO 3곳이 열 때 값이 아니라 같은 기준값을 보낸다', () {
    // 초안 저장·예약 전환은 _expectedEditRevision, 본 저장은 그 값을 담은 sentEditRevision.
    expect('expectedEditRevision: _expectedEditRevision'.allMatches(code).length, 2);
    expect(code.contains('sentEditRevision = _expectedEditRevision;\n      await _firestoreService.updateTO(widget.to.id, updates,\n          expectedEditRevision: sentEditRevision);'), true);
    expect(code.contains('expectedEditRevision: widget.to.editRevision'), false);
    expect(code.contains('int get _expectedEditRevision => _serverEditRevision ?? widget.to.editRevision;'), true);
  });

  // [POSTING-AUTH-44] .43 은 공개 실패 뒤 서버 **최신** editRevision 을 읽었다. 그 사이 다른 관리자가
  //   고쳤으면 그 번호를 받아 이 화면의 오래된 입력이 그 변경을 조용히 덮었다(서버 SDK 하네스 재현:
  //   perf-20261028/c44 C44-B_before_read-read). 기준은 **내 수정이 승인된 버전(보낸 값 + 1)** 이어야 한다.
  test('ER-2 수정 커밋 뒤 실패에서는 내 수정이 승인된 버전(보낸 값 + 1)을 기준으로 둔다 — 서버 최신값을 읽지 않는다', () {
    final upd = code.indexOf('expectedEditRevision: sentEditRevision);\n      updateCommitted = true;');
    expect(upd, greaterThan(0), reason: 'updateTO 직후에 커밋 표시');
    // 공개 실패(CF 예외) 분기
    final pubCatch = code.indexOf('on FirebaseFunctionsException catch (e) {', upd);
    final pubReturn = code.indexOf('return;', pubCatch);
    expect(code.substring(pubCatch, pubReturn).contains('_adoptCommittedRevision(sentEditRevision);'), true);
    // 바깥 catch(서비스가 바꾼 Exception(MAX_ACTIVE_TO_LIMIT) 포함)
    expect(code.contains('if (updateCommitted) _adoptCommittedRevision(sentEditRevision);'), true);
    final i = code.indexOf('void _adoptCommittedRevision(int sentEditRevision) {');
    expect(i, greaterThan(0));
    final body = code.substring(i, code.indexOf('\n  }\n', i));
    expect(body.contains('_serverEditRevision = sentEditRevision + 1;'), true);
    expect(body.contains('.get('), false, reason: '서버 최신값을 읽으면 다른 관리자 변경을 덮는다');
    expect(body.contains('updateTO'), false, reason: '쓰기를 다시 보내지 않는다');
    expect(code.contains('_resyncAfterPartialSave'), false);
  });

  test('ER-3 나갈 때 서버가 바뀌었으면 true 로 pop 한다', () {
    expect(code.contains('nav.pop(_serverChanged ? true : null);'), true);
    expect(code.contains('_serverChanged = true;'), true);
  });

  test('ER-4 충돌 안내(다른 관리자) 처리는 그대로다', () {
    expect(code.contains('if (_isStaleEditConflict(e)) {'), true);
    expect(code.contains("return msg.contains('다른 관리자');"), true);
  });
}
