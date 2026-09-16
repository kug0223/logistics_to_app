// [PREDEVICE-RUNTIME-CLOSURE.1 PART B] 한 칸이 실패해도 화면 전체를 비우지 않는다
//
// READ에서 확인된 것:
//   · 홈은 네 도메인(지원 내역 · 근태 · 공고 · 신분증 요청)을 Future.wait로
//     함께 불렀다. Future.wait는 하나가 실패하면 나머지가 성공했어도 결과를
//     통째로 버린다. 지원 내역만 못 불러왔을 뿐인데 오늘 근무도, 추천 공고도,
//     신분증 요청 카드도 같이 사라져 화면 전체가 빈 것처럼 보였다.
//   · 그리고 지원 내역이 비면 "아직 지원한 일자리가 없어요 / 일자리 찾아보기"
//     라는 empty CTA가 나온다. 조회에 실패했을 뿐인데 지원이 없다고 말하는 것은
//     거짓이고, 그 사람을 다시 지원하러 보내는 유도가 된다.
//
// DEV runtime:
//   callableGetMyApplications는 실패를 HTTP 401 + error로 돌려준다.
//   {"error":{"status":"UNAUTHENTICATED"}} — applications 키 자체가 없다.
//   즉 빈 목록으로 위장한 성공이 서버에서 올라오지 않는다.
//
// 계약:
//   도메인별로 실패를 따로 받고, 실패한 칸만 모른다고 둔다.
//   지원 내역 실패는 0이 아니라 ERROR로 말하고, empty CTA를 만들지 않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _homePath = 'lib/screens/user/user_home_screen.dart';
const _appFsPath = 'lib/services/firestore/application_firestore.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  final home = _src(_homePath);
  final homeCode = _codeOf(home);
  final homeFlat = _flat(homeCode);

  group('도메인별로 실패를 따로 받는다', () {
    test('네 조회 모두 개별 catchError를 갖는다', () {
      expect('.catchError((Object e)'.allMatches(homeFlat).length >= 4, true,
          reason: 'Future.wait 하나가 실패하면 나머지 성공분이 버려진다');
      for (final v in ['appsErr', 'attsErr', 'tosErr', 'idErr']) {
        expect(homeFlat.contains('Object? $v;'), true,
            reason: '$v 가 없으면 어느 칸이 실패했는지 구분할 수 없다');
      }
    });

    test('성공한 칸만 반영한다', () {
      for (final pair in [
        ['attsErr == null', '_attendances = results[1]'],
        ['tosErr == null', '_publishedTos = results[2]'],
        ['idErr == null', '_idRequestSurface ='],
      ]) {
        final i = homeFlat.indexOf('if (${pair[0]})');
        expect(i > 0, true, reason: '${pair[0]} 분기가 없다');
        expect(homeFlat.substring(i, i + 160).contains(pair[1]), true,
            reason: '${pair[1]} 가 실패해도 덮어써진다');
      }
    });

    test('지원 내역 실패 시 이전 값을 0으로 덮지 않는다', () {
      final i = homeFlat.indexOf('if (appsErr == null) { _applications =');
      expect(i > 0, true,
          reason: '실패했는데 _applications를 빈 목록으로 대입하면 0이 진실처럼 보인다');
    });
  });

  group('지원 내역 실패는 ERROR로 말한다', () {
    test('실패가 화면 상태로 올라간다', () {
      final i = homeFlat.indexOf('if (appsErr != null)');
      expect(i > 0, true);
      final block = homeFlat.substring(i, i + 260);
      expect(block.contains('_homeLoadFailed = true;'), true);
      expect(block.contains('_isLoadingData = false;'), true,
          reason: '로딩 상태가 남으면 영영 스켈레톤이다');
    });

    test('ERROR가 SUCCESS_ZERO보다 먼저 갈린다 — empty CTA 금지', () {
      final guard =
          'if (_homeLoadFailed && _applications.isEmpty && !_isLoadingData)';
      final guardAt = homeFlat.indexOf(guard);
      final emptyAt = homeFlat.indexOf('아직 지원한 일자리가 없어요');
      expect(guardAt > 0, true, reason: 'ERROR 분기가 없다');
      expect(emptyAt > guardAt, true,
          reason: '빈 상태 문구가 먼저 걸리면 실패를 "지원 없음"이라고 말하게 된다');
    });

    test('ERROR 화면에 원인과 재시도가 함께 있다', () {
      expect(homeCode.contains('지원 현황을 불러오지 못했어요'), true);
      expect(homeCode.contains('다시 시도'), true);
      expect(homeFlat.contains('onTap: _loadHomeData'), true,
          reason: '앱 재시작을 요구하면 안 된다');
    });

    test('성공하면 오류 상태가 풀린다', () {
      expect(homeFlat.contains('_homeLoadFailed = false;'), true,
          reason: '복구 경로가 없으면 한 번 실패한 화면이 영영 오류로 남는다');
    });
  });

  group('서비스가 실패를 빈 목록으로 바꾸지 않는다', () {
    test('캐시가 없으면 rethrow — 있으면 stale', () {
      final fs = _flat(_codeOf(_src(_appFsPath)));
      final i = fs.indexOf('Future<List<ApplicationModel>> getMyApplications(');
      final body = fs.substring(i, i + 1600);
      expect(body.contains('return cached ?? [];'), false);
      expect(body.contains('if (cached != null) return cached;'), true,
          reason: 'stale 데이터가 빈 화면보다 낫다 — 다만 0으로 덮지 않는다');
      expect(body.contains('rethrow;'), true);
    });
  });
}
