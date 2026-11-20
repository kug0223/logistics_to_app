import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [SA-AUDIT.49] 슈퍼관리자 쓰기의 안내가 실제 서버 결과와 맞는가.
///   근거(LOCAL, DEV 배포 원본 직접 실행): c49/sa49-biz.json · c49/sa49-blacklist.json
///     - 사업장 비활성: 연쇄가 돌면 진행 공고 마감·대기 반려·확정 21건 취소, 안 돌면 공고가 근로자 목록에 그대로.
///       어느 쪽이든 재활성으로 복구되지 않는다.
///     - 블랙리스트 사유: 지원 거절·로그인 안내에 그대로 보인다.
String _src(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final biz = _src('lib/screens/super_admin/all_businesses_screen.dart');
  final users = _src('lib/screens/super_admin/all_users_screen.dart');

  test('SA49-1 사업장 비활성 확인 창이 사실과 다른 말을 하지 않는다', () {
    expect(biz.contains('활성 TO는 수동으로 마감 처리해 주세요'), isFalse, reason: '연쇄가 돌면 자동으로 마감된다');
    expect(biz.contains('공고는 지원자에게 노출되지 않습니다'), isFalse, reason: '연쇄가 안 돌면 목록에 그대로 보인다');
    expect(biz.contains("'• 새 지원이 바로 막힙니다.\\n'"), isTrue);
    // [.50] 취소 기준을 '시작 전'에서 실제 기준(출근 기록·정산)으로 고쳤다 — sa_deact_50_test SA50-2.
    expect(biz.contains('출근 기록이 없는 확정 근무(지난 날짜 포함)가 취소되고'), isTrue);
    expect(biz.contains('재활성화해도 되살아나지 않습니다'), isTrue);
    expect(biz.contains('비활성화 때 마감·취소된 공고와 근무는 되살아나지 않습니다'), isTrue, reason: '재활성 확인 창');
  });

  test('SA49-2 블랙리스트 사유가 당사자에게 보인다는 사실을 입력 전에 말한다', () {
    expect(users.contains("visibilityNote: '입력한 사유는 이 사용자에게 그대로 보입니다"), isTrue);
    expect(users.contains('사기 피해 신고'), isFalse, reason: '신고자 관련 내용을 쓰도록 유도하는 예시');
    expect(users.contains('if (widget.visibilityNote != null) ...['), isTrue);
  });

  test('SA49-3 실패 안내에 예외 원문을 보이지 않고, 실패 뒤 목록을 다시 읽는다', () {
    expect(users.contains("'처리 실패: \$e'"), isFalse);
    expect(biz.contains("'처리 실패: \$e'"), isFalse);
    // [.58] 수동·영구 제한 해제 실패도 목록을 다시 읽는다 — 블랙리스트 해제·등록·노쇼 리셋 3곳 + 수동 해제 1곳.
    expect('unawaited(_loadAllUsers());'.allMatches(users).length, 4);
    // [.53] 승인 실패(서버 거절)도 목록을 다시 읽는다 — 3곳(비활성·승인 예외·재활성) + 승인 서버 거절 1곳.
    expect('unawaited(_loadAllBusinesses());'.allMatches(biz).length, 4);
    expect(users.contains("return '처리 결과를 확인하지 못했습니다. 목록에서 현재 상태를 확인해 주세요.';"), isTrue);
  });

  test('SA49-4 홈 통계가 읽기 실패를 0명·0개로 말하지 않는다', () {
    final home = _src('lib/screens/super_admin/super_admin_home_screen.dart');
    expect(home.contains('totalUsers: 0, totalBusinesses: 0'), isFalse);
    expect("_stats == null ? '확인 못함'".allMatches(home).length, 2);
  });

  test('SA49-6 SA 가 운영을 중지한 사업장에 관리자 준비 단계를 권하지 않는다(기기: 승인 진행 중 · 2가지 준비)', () {
    final home = _src('lib/screens/business_admin/business_admin_home_screen.dart');
    final jobs = _src('lib/screens/business_admin/jobs_root_screen.dart');
    final card = home.substring(home.indexOf('Widget _buildPostingSetupCard('));
    expect(card.indexOf('if (_allBusinessesClosed) return const SizedBox.shrink();'),
        lessThan(card.indexOf('final r = _firstPosting;')));
    expect(jobs.contains('businesses.every((b) => b.isDeactivated)'), isTrue);
    expect(jobs.contains("'운영이 중지된 사업장이에요'"), isTrue);
    expect(jobs.contains('? (_closedTitle != null'), isTrue);
  });

  test('SA49-5 사용자 목록이 서버 상한(500명)에 닿으면 전체 수처럼 말하지 않는다', () {
    expect(users.contains('static const int _serverListCap = 500;'), isTrue);
    expect(users.contains("'전체 사용자 관리 (최근 \${_users.length}명까지)'"), isTrue);
  });
}
