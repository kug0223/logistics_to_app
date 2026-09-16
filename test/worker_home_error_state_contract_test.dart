// [PREDEVICE] 근로자 홈에서 ERROR는 0이 아니다
//
// READ에서 확인된 것:
//   · getMyApplications는 실패하면 `cached ?? []`를 돌려줬다. 캐시가 없으면
//     빈 목록이므로 홈의 Future.wait는 성공으로 끝나고, catch는 아예 도달하지
//     않았다. 화면은 "검토중 0 · 확정 0 · 계약 대기 0"과 "아직 지원한
//     일자리가 없어요"를 자신 있게 그렸다.
//   · getPendingIdCardRequestsForUser도 같은 방식이라, 신분증 열람 요청 카드가
//     조용히 사라졌다 — 근로자가 승인/거절할 기회를 잃는다.
//   · 관리자 홈은 ERROR ≠ ZERO를 강제하는데 근로자 홈만 반대였다.
//
// 계약:
//   LOADING / SUCCESS_ZERO / SUCCESS_NONZERO / ERROR 를 구분하고,
//   직전 데이터가 있으면 PARTIAL(stale)로 표현한다.
//   호출자 전원이 try/catch를 갖고 있으므로 판단은 화면이 한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _appFsPath = 'lib/services/firestore/application_firestore.dart';
const _idFsPath = 'lib/services/firestore/id_card_firestore.dart';
const _homePath = 'lib/screens/user/user_home_screen.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

/// 메서드 선언부터 다음 최상위 멤버 직전까지.
String _memberOf(String source, String decl) {
  final start = source.indexOf(decl);
  if (start < 0) throw StateError('$decl 을 찾지 못함');
  final next = source.indexOf('\n  ///', start + decl.length);
  return source.substring(start, next == -1 ? source.length : next);
}

void main() {
  group('서비스가 실패를 빈 목록으로 바꾸지 않는다', () {
    test('getMyApplications는 캐시가 없으면 rethrow한다', () {
      final body = _flat(_codeOf(
          _memberOf(_src(_appFsPath), 'Future<List<ApplicationModel>> getMyApplications(')));
      expect(body.contains('return cached ?? [];'), false,
          reason: '빈 목록은 "지원 0건"과 구분되지 않는다');
      expect(body.contains('if (cached != null) return cached;'), true,
          reason: '캐시가 있으면 stale을 주는 편이 빈 화면보다 낫다');
      expect(body.contains('rethrow;'), true);
    });

    test('getPendingIdCardRequestsForUser는 rethrow한다', () {
      final body = _flat(_codeOf(_memberOf(_src(_idFsPath),
          'Future<List<IdCardAccessRequestModel>> getPendingIdCardRequestsForUser(')));
      expect(body.contains('return [];'), false,
          reason: '빈 목록이면 요청 카드가 조용히 사라진다');
      expect(body.contains('rethrow;'), true);
    });
  });

  group('홈이 네 상태를 구분한다', () {
    final home = _src(_homePath);
    final code = _codeOf(home);
    final flat = _flat(code);

    test('실패가 화면 상태로 남는다 — 토스트만으로 끝내지 않는다', () {
      expect(flat.contains('bool _homeLoadFailed = false;'), true);
      expect(flat.contains('_homeLoadFailed = true;'), true,
          reason: 'catch에서 실패를 기록해야 한다');
      expect(flat.contains('_homeLoadFailed = false;'), true,
          reason: '성공 시 복구되지 않으면 오류 상태가 남는다');
    });

    test('ERROR와 SUCCESS_ZERO가 다른 화면을 낸다', () {
      expect(
        flat.contains(
          'if (_homeLoadFailed && _applications.isEmpty && !_isLoadingData)',
        ),
        true,
        reason: 'ERROR를 empty state보다 먼저 갈라야 한다',
      );
      expect(flat.contains('_applicationStatusErrorCard(s)'), true);
      // 빈 상태 문구는 남아 있어야 한다 — 진짜 0건일 때 쓰는 말이다.
      expect(code.contains('아직 지원한 일자리가 없어요'), true);
      expect(code.contains('지원 현황을 불러오지 못했어요'), true,
          reason: '모르는 상태를 0건으로 말하지 않는다');
    });

    test('PARTIAL(stale)은 숫자를 지우지 않고 사실을 덧붙인다', () {
      expect(flat.contains('if (_homeLoadFailed) ...[ _staleNotice(s),'), true,
          reason: '직전 데이터가 있으면 지우지 말고 stale임을 알린다');
      expect(code.contains('이전에 받은 내용을 보여주는 중이에요'), true);
    });

    test('두 오류 표면 모두 다시 시도 경로를 준다', () {
      expect('onTap: _loadHomeData'.allMatches(flat).length >= 2, true,
          reason: 'ERROR 카드와 stale 배너 모두 재시도가 있어야 한다');
    });

    test('요청 목록 갱신 실패가 카드를 지우지 않는다', () {
      final body = _flat(_codeOf(
          _memberOf(home, 'Future<void> _reloadPendingIdRequests() async {')));
      expect(body.contains('catch'), true,
          reason: 'rethrow로 바뀐 서비스를 감싸지 않으면 갱신이 화면을 깬다');
      expect(
        body.indexOf('setState') < body.indexOf('catch'),
        true,
        reason: '실패 시 _idRequestSurface를 덮어쓰지 않아야 한다',
      );
    });
  });
}
