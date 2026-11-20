// [INVITE-PREACCEPT] 관리자가 **초대받은 사람의 서류를 확인할 입구**가 있다.
//
//   2026-10-15 이전: 날짜별 지원자 화면의 초대 행은 누를 수 없었다. 근로자
//   상세의 `서류 확인` 영역(서버 판정·권한·버전 검사)은 이미 확정 전
//   지원서라면 INVITED 에도 열리도록 만들어져 있었지만, 거기로 가는 길이
//   없었다. 근로자가 동의해도 관리자가 확인할 수 없어 수락이 막혔다.
//
//   이 파일은 **소스 계약**이다(CODE 수준). 관리자 상세 다이얼로그를 띄우는
//   렌더 검증은 하지 않았다 — 판정·권한·버전은 서버 테스트
//   (functions/test/invite_preaccept_consent.test.js)가 실행으로 본다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();
const _day = 'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';
const _detail = 'lib/widgets/dialogs/worker_detail_dialog.dart';

String _bodyOf(String src, String header) {
  final i = src.indexOf(header);
  expect(i, greaterThan(0), reason: header);
  // 매개변수 목록 안의 `{...}`(이름 있는 인자)를 건너뛰고 본문 `{` 부터 자른다.
  var p = 0;
  // header 는 매개변수 여는 괄호로 끝난다 — 반환형 `(A, B)` 의 괄호를 잡지 않는다.
  var k0 = i + header.length - 1;
  for (; k0 < src.length; k0++) {
    if (src[k0] == '(') p++;
    if (src[k0] == ')') {
      p--;
      if (p == 0) break;
    }
  }
  final open = src.indexOf('{', k0);
  var d = 0;
  for (var k = open; k < src.length; k++) {
    if (src[k] == '{') d++;
    if (src[k] == '}') {
      d--;
      if (d == 0) return src.substring(i, k + 1);
    }
  }
  fail('닫히지 않음: $header');
}

void main() {
  final day = _read(_day);

  test('PAA-01 대기 중 초대 행만 눌러서 상세를 연다', () {
    final row = _bodyOf(day, 'Widget _buildInviteRow(');
    expect(row.contains('final canOpen = app.status == AppStatus.invited && user != null;'),
        isTrue);
    expect(row.contains('onTap: canOpen ? () => _showInvitedWorkerDetail(app, user) : null'),
        isTrue, reason: '끝난 초대(거절·만료·철회)는 열지 않는다');
  });

  test('PAA-02 초대 상세는 승인 버튼 없이 연다 — 초대는 근로자가 수락한다', () {
    final open = _bodyOf(day, 'Future<void> _showInvitedWorkerDetail(');
    expect(open.contains('showApprovalButtons: false'), isTrue);
    expect(open.contains('isConfirmed: false'), isTrue,
        reason: '확정 전이어야 상세가 서류 확인 영역을 불러온다');
  });

  test('PAA-03 상세는 확정 전 지원서의 서류 검토를 **부가 조회와 무관하게 먼저** 불러온다', () {
    final d = _read(_detail);
    final load = _bodyOf(d, 'Future<void> _loadAdditionalData(');
    final first = load.indexOf('unawaited(_loadApplicantDocumentReview());');
    final wait = load.indexOf('await Future.wait([');
    expect(first, greaterThan(0));
    expect(first, lessThan(wait), reason: '부가 조회 실패가 서류 검토를 막으면 안 된다');
  });

  test('PAA-03b 확정 전 지원서에만 서류 검토를 부른다(조건은 그대로)', () {
    final d = _read(_detail);
    expect(
        RegExp(r'if \(!widget\.isConfirmed\) \{\s*unawaited\(_loadApplicantDocumentReview\(\)\);')
            .hasMatch(d),
        isTrue);
  });

  test('PAA-04 상태 라벨이 관리자의 할 일을 말한다(동의 전 / 확인 가능)', () {
    // [E2-INVITED-SEAT] 라벨 본문은 공용 함수(inviteStateLabelOf)로 옮겼다.
    expect(day.contains('inviteStateLabelOf(app, capacity: capacity)'), isTrue);
    final label = File('lib/widgets/admin/invite_state_label.dart').readAsStringSync();
    expect(label.contains("'초대 중 · 서류 동의 전'"), isTrue);
    expect(label.contains("'초대 중 · 서류 확인 가능'"), isTrue);
    expect(label.contains('app.hasReviewPurposeConsent'), isTrue,
        reason: '동의 판정은 공식 버전 하나를 본다');
  });
}
