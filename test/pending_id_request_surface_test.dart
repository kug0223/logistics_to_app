import 'dart:io';

import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/ui/pending_id_request_surface.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// DS-03 APPLICANT-PENDING-REQUEST-SURFACE
//
// 감사 결론: 요청은 idCardAccessRequests에 정상 저장되지만
// MyRequestsDialog 진입 경로가 알림 항목 탭 하나뿐이라
// 알림을 지우면 pending 요청이 도달 불가능해진다.
//
// 이 테스트는 두 가지를 지킨다.
//   ① 홈 진입점의 상태 계약 (표시 / 문구 / 자동 소멸)
//   ② 표시 판단이 알림과 무관하다는 배선 사실
// ═══════════════════════════════════════════════════════════════

IdCardAccessRequestModel _req({
  String id = 'r1',
  String businessName = 'ALfit 강남점',
}) {
  return IdCardAccessRequestModel(
    id: id,
    requesterId: 'admin1',
    requesterName: '김관리',
    requesterBusinessId: 'biz1',
    requesterBusinessName: businessName,
    targetUserId: 'user1',
    targetUserName: '박근무',
    reason: IdCardAccessReason.laborContract,
    status: IdCardAccessStatus.pending,
    requestedAt: DateTime(2026, 9, 12, 10),
  );
}

String _src(String path) => File(path).readAsStringSync();

/// 주석 줄을 제거한 사본.
/// 설명 주석에 등장하는 단어가 배선 스캔에 잡히는 것을 막는다.
String _codeOf(String source) => source
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// 시그니처에서 시작해 중괄호 짝을 맞춰 메서드 본문만 잘라낸다.
///
/// 파라미터 목록의 named 중괄호를 본문 시작으로 오인하지 않도록
/// 괄호 짝을 먼저 닫은 뒤의 첫 '{'를 본문 시작으로 잡는다.
String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: '$signature 를 찾지 못함');
  var paren = 0;
  var afterParams = start;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    if (source[i] == '(') paren++;
    if (source[i] == ')') {
      paren--;
      if (paren == 0) {
        afterParams = i;
        break;
      }
    }
  }
  final open = source.indexOf('{', afterParams);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  fail('$signature 본문의 끝을 찾지 못함');
}

void main() {
  const homePath = 'lib/screens/user/user_home_screen.dart';
  const dialogPath = 'lib/screens/user/dialogs/my_requests_dialog.dart';
  const notificationPath = 'lib/screens/common/notification_screen.dart';

  // ───────────────────────────────────────────────────────────
  // 상태 계약
  // ───────────────────────────────────────────────────────────
  group('DS03-01 pending 0 — 진입점 없음', () {
    test('빈 목록이면 표시하지 않는다', () {
      final surface = PendingIdRequestSurface.from([]);
      expect(surface.count, 0);
      expect(surface.isVisible, isFalse);
    });

    test('empty 상수도 동일하다', () {
      expect(PendingIdRequestSurface.empty.isVisible, isFalse);
      expect(PendingIdRequestSurface.empty.count, 0);
    });
  });

  group('DS03-02 pending 1 — 진입점 표시', () {
    test('1건이면 표시한다', () {
      final surface = PendingIdRequestSurface.from([_req()]);
      expect(surface.isVisible, isTrue);
      expect(surface.count, 1);
    });

    test('1건이면 사업장명을 문구에 쓴다', () {
      final surface = PendingIdRequestSurface.from([_req()]);
      expect(surface.businessName, 'ALfit 강남점');
      expect(surface.title, contains('ALfit 강남점'));
      expect(surface.title, contains('신분증'));
    });

    test('사업장명이 비어 있으면 일반 문구로 떨어진다', () {
      final surface = PendingIdRequestSurface.from([_req(businessName: '   ')]);
      expect(surface.businessName, isNull);
      expect(surface.title, '신분증 열람 요청이 있어요');
    });

    test('1건 보조문구는 승인·거절 행동을 안내한다', () {
      final surface = PendingIdRequestSurface.from([_req()]);
      expect(surface.subtitle, contains('승인'));
      expect(surface.subtitle, contains('거절'));
    });
  });

  group('DS03-03 pending 여러 건 — 건수 표시', () {
    test('건수를 문구에 담는다', () {
      final surface = PendingIdRequestSurface.from([
        _req(id: 'r1'),
        _req(id: 'r2', businessName: '두번째 사업장'),
        _req(id: 'r3', businessName: '세번째 사업장'),
      ]);
      expect(surface.count, 3);
      expect(surface.title, contains('3건'));
    });

    test('여러 건이면 사업장명을 고르지 않는다', () {
      final surface = PendingIdRequestSurface.from([
        _req(id: 'r1'),
        _req(id: 'r2', businessName: '두번째 사업장'),
      ]);
      expect(surface.businessName, isNull);
      expect(surface.title, isNot(contains('ALfit 강남점')));
      expect(surface.title, isNot(contains('두번째 사업장')));
    });

    test('건수가 늘어도 홈은 row를 만들지 않는다 — 문구 하나만 파생', () {
      final surface = PendingIdRequestSurface.from(
        List.generate(5, (i) => _req(id: 'r$i')),
      );
      expect(surface.title, '처리할 신분증 열람 요청 5건');
      expect(surface.subtitle, '요청 내용을 확인해 주세요');
    });
  });

  group('DS03-06 마지막 요청 처리 후 자동 소멸', () {
    test('1건 → 0건이 되면 진입점이 사라진다', () {
      var surface = PendingIdRequestSurface.from([_req()]);
      expect(surface.isVisible, isTrue);
      surface = PendingIdRequestSurface.from([]);
      expect(surface.isVisible, isFalse);
    });

    test('2건 → 1건이면 진입점은 남고 건수만 줄어든다', () {
      var surface = PendingIdRequestSurface.from([
        _req(id: 'r1'),
        _req(id: 'r2'),
      ]);
      expect(surface.count, 2);
      surface = PendingIdRequestSurface.from([_req(id: 'r2')]);
      expect(surface.isVisible, isTrue);
      expect(surface.count, 1);
    });
  });

  // ───────────────────────────────────────────────────────────
  // 배선
  // ───────────────────────────────────────────────────────────
  group('DS03-04 알림 비의존', () {
    test('진입점 노출 판단에 알림을 참조하지 않는다', () {
      final code = _codeOf(_src(homePath));
      final card = _bodyOf(code, 'Widget _buildIdRequestCard(');
      expect(card.contains('otification'), isFalse,
          reason: '노출 판단은 요청 상태만 사용해야 한다');
    });

    test('요청 재조회에도 알림을 참조하지 않는다', () {
      final code = _codeOf(_src(homePath));
      final reload = _bodyOf(code, 'Future<void> _reloadPendingIdRequests(');
      expect(reload.contains('otification'), isFalse);
      expect(reload.contains('getPendingIdCardRequestsForUser'), isTrue);
    });

    test('노출 조건은 요청 건수다', () {
      final code = _codeOf(_src(homePath));
      final card = _bodyOf(code, 'Widget _buildIdRequestCard(');
      expect(card.contains('_idRequestSurface.isVisible'), isTrue);
    });
  });

  group('DS03-05 진입점 → 기존 다이얼로그', () {
    test('탭하면 요청 열기 경로를 호출한다', () {
      final code = _codeOf(_src(homePath));
      final card = _bodyOf(code, 'Widget _buildIdRequestCard(');
      expect(card.contains('_openMyRequests(uid)'), isTrue);
    });

    test('새 처리 화면이 아니라 기존 다이얼로그를 연다', () {
      final code = _codeOf(_src(homePath));
      final open = _bodyOf(code, 'Future<void> _openMyRequests(');
      expect(open.contains('MyRequestsDialog.show('), isTrue);
    });

    test('홈은 승인·거절 버튼을 직접 만들지 않는다', () {
      final code = _codeOf(_src(homePath));
      final card = _bodyOf(code, 'Widget _buildIdRequestCard(');
      expect(card.contains('approveIdCardAccessRequest'), isFalse);
      expect(card.contains('rejectIdCardAccessRequest'), isFalse);
    });

    test('알림 화면도 같은 공용 helper를 쓴다 — 중복 launch 로직 없음', () {
      final code = _codeOf(_src(notificationPath));
      expect(code.contains('MyRequestsDialog.show('), isTrue);
      expect(code.contains('builder: (_) => MyRequestsDialog('), isFalse);
    });

    test('공용 helper는 기존 launch 파라미터를 유지한다', () {
      final code = _codeOf(_src(dialogPath));
      final show = _bodyOf(code, 'static Future<void> show(');
      expect(show.contains('barrierDismissible: false'), isTrue);
    });
  });

  group('DS03-06 배선 — 다이얼로그 복귀 후 재조회', () {
    test('다이얼로그를 닫으면 남은 건수를 다시 읽는다', () {
      final code = _codeOf(_src(homePath));
      final open = _bodyOf(code, 'Future<void> _openMyRequests(');
      expect(open.contains('await MyRequestsDialog.show('), isTrue);
      expect(open.indexOf('_reloadPendingIdRequests'),
          greaterThan(open.indexOf('MyRequestsDialog.show(')));
    });

    test('재조회 전에 mounted를 확인한다', () {
      final code = _codeOf(_src(homePath));
      final open = _bodyOf(code, 'Future<void> _openMyRequests(');
      expect(open.contains('if (!mounted) return;'), isTrue);
    });
  });

  group('DS03-07 홈 로드·새로고침 경로', () {
    test('홈 로드에 요청 조회가 포함된다', () {
      final code = _codeOf(_src(homePath));
      final load = _bodyOf(code, 'Future<void> _loadHomeData(');
      expect(load.contains('getPendingIdCardRequestsForUser(uid)'), isTrue);
      expect(load.contains('PendingIdRequestSurface.from('), isTrue);
    });

    test('pull-to-refresh는 같은 홈 로드를 탄다', () {
      final code = _codeOf(_src(homePath));
      expect(code.contains('onRefresh:'), isTrue);
      final refreshIdx = code.indexOf('onRefresh:');
      final tail = code.substring(refreshIdx, refreshIdx + 240);
      expect(tail.contains('_loadHomeData()'), isTrue);
    });

    test('요청 조회는 홈 로드에서 한 번만 호출된다', () {
      final code = _codeOf(_src(homePath));
      final load = _bodyOf(code, 'Future<void> _loadHomeData(');
      final hits = 'getPendingIdCardRequestsForUser'.allMatches(load).length;
      expect(hits, 1, reason: '중복 조회 금지');
    });

    test('로그인 정보가 없으면 조회하지 않는다', () {
      final code = _codeOf(_src(homePath));
      final load = _bodyOf(code, 'Future<void> _loadHomeData(');
      expect(load.contains('if (uid == null'), isTrue);
      final reload = _bodyOf(code, 'Future<void> _reloadPendingIdRequests(');
      expect(reload.contains('if (uid == null) return;'), isTrue);
    });
  });

  group('DS03 범위 제한', () {
    test('새 저장 필드를 만들지 않는다', () {
      final code = _codeOf(_src(homePath));
      expect(code.contains('hasPendingIdCardRequest'), isFalse);
      expect(code.contains('showRequestCard'), isFalse);
      expect(code.contains("'pendingRequestCount'"), isFalse);
    });

    test('관리자가 보낸 요청 목록은 건드리지 않는다', () {
      final code = _codeOf(_src(homePath));
      expect(code.contains('getMyIdCardRequests('), isFalse);
      expect(code.contains('AsAdmin'), isFalse);
    });

    test('기존 Hero·지원 준비 카드가 그대로 남아 있다', () {
      final code = _codeOf(_src(homePath));
      final body = _bodyOf(code, 'Widget _buildUserBody(');
      expect(body.contains('_buildPriorityCard(context, s, theme)'), isTrue);
      expect(body.contains('_buildReadinessCard(context, s, up)'), isTrue);
      expect(body.contains('_buildIdRequestCard(context, s, up)'), isTrue);
    });

    test('Hero 우선순위 계산은 요청을 참조하지 않는다', () {
      final code = _codeOf(_src(homePath));
      final priority = _bodyOf(code, 'Widget _buildPriorityCard(');
      expect(priority.contains('_idRequestSurface'), isFalse);
      final caches = _bodyOf(code, 'void _rebuildCaches(');
      expect(caches.contains('_idRequestSurface'), isFalse);
    });

    test('진입점은 지원 준비 카드보다 위에 놓인다', () {
      final code = _codeOf(_src(homePath));
      final body = _bodyOf(code, 'Widget _buildUserBody(');
      expect(body.indexOf('_buildIdRequestCard'),
          lessThan(body.indexOf('_buildReadinessCard')));
    });
  });
}
