// [R8-P7.4] 공고·리뷰 경계에서 "못 읽음"이 "없음"으로 붕괴하지 않는다.
//
//   P7.2/P7.3 에서 같은 모양을 두 번 봤다 — 쿼리가 실패하고, 서비스가 빈 값으로
//   삼키고, 화면이 "없음"이라고 말한다. 공고와 리뷰는 그 문장이 특히 비싸다.
//   구직자에게 "지원 가능한 일자리가 없어요"는 오늘 지원을 포기하라는 말이고,
//   관리자에게 "업무 유형 미등록"은 이미 등록한 것을 또 등록하라는 말이다.
//
//   이 파일은 그 세 층 중 삼키는 층과 단정하는 층을 함께 고정한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('파일을 찾지 못했다: $p');
  return f.readAsStringSync();
}

/// 주석을 지운 코드만 남긴다 — 표지를 주석에 두지 않기 위해.
String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 함수의 catch 블록만 잘라 낸다.
/// 조기 반환(`if (ids.isEmpty) return [];`)은 정당한 빈 결과이므로 건드리지 않는다.
String _catchBodyOf(String file, String fnStart) {
  final code = _codeOf(_read(file));
  final s = code.indexOf(fnStart);
  if (s < 0) throw StateError('함수를 찾지 못했다: $fnStart');
  final c = code.indexOf('} catch (', s);
  if (c < 0) throw StateError('catch 블록을 찾지 못했다: $fnStart');
  final open = code.indexOf('{', c + 2);
  var depth = 0;
  var end = open;
  for (var k = open; k < code.length; k++) {
    if (code[k] == '{') depth++;
    if (code[k] == '}') {
      depth--;
      if (depth == 0) {
        end = k;
        break;
      }
    }
  }
  return _flat(code.substring(open, end + 1));
}

void _propagates(String file, String fnStart, String reason) {
  final body = _catchBodyOf(file, fnStart);
  expect(body.contains('rethrow'), isTrue, reason: reason);
  expect(
      RegExp(r'return\s*(const\s*)?(<[^>]*>)?\s*\[\s*\]\s*;').hasMatch(body),
      isFalse,
      reason: '$reason — catch 안에서 빈 목록을 돌려준다');
  expect(
      RegExp(r'return\s*(const\s*)?(<[^>]*>)?\s*\{\s*\}\s*;').hasMatch(body),
      isFalse,
      reason: '$reason — catch 안에서 빈 맵을 돌려준다');
}

void main() {
  const toSvc = 'lib/services/firestore/to_firestore.dart';
  const bizSvc = 'lib/services/firestore/business_firestore.dart';
  const revSvc = 'lib/services/monthly_review_service.dart';
  const readiness = 'lib/services/business_posting_readiness.dart';
  const home = 'lib/screens/user/user_home_screen.dart';
  const jobTab = 'lib/screens/user/tabs/user_job_tab.dart';
  const adminHome = 'lib/screens/business_admin/business_admin_home_screen.dart';
  const picker = 'lib/utils/business_picker_helper.dart';

  group('[R8P7.4] 공고 — 못 읽은 것을 "공고 없음"으로 말하지 않는다', () {
    test('PR-1 공개 공고 목록', () {
      _propagates(toSvc, 'Future<List<TOModel>> getPublishedTOs(',
          '구직자 홈이 "지원 가능한 일자리가 없어요"로 말하게 된다');
    });

    test('PR-2 공개 공고 페이지네이션', () {
      _propagates(toSvc, 'Future<Map<String, dynamic>> getPublishedTOsPaged(',
          '일자리 탭이 "등록된 공고가 없습니다"로 말하게 된다');
    });

    test('PR-3 페이지네이션 실패를 "끝까지 읽었다"로 바꾸지 않는다', () {
      final body = _catchBodyOf(
          toSvc, 'Future<Map<String, dynamic>> getPublishedTOsPaged(');
      expect(body.contains("'hasMore': false"), isFalse,
          reason: 'hasMore:false 는 더 없다는 단정이라 재시도 경로까지 닫는다');
    });

    test('PR-4 사업장 공고 목록 (관리자)', () {
      _propagates(toSvc, 'Future<List<TOModel>> getTOsByBusiness(',
          '"기존 공고 불러오기"가 빈 목록으로 열린다');
    });

    test('PR-5 실패한 조회를 캐시에 남기지 않는다', () {
      final body =
          _catchBodyOf(toSvc, 'Future<List<TOModel>> getPublishedTOs(');
      expect(body.contains('_cachedPublishedTOs ='), isFalse,
          reason: '실패 결과를 캐시하면 TTL 동안 빈 목록이 고착된다');
    });
  });

  group('[R8P7.4] 업무 유형 — 못 읽은 것은 "미등록"이 아니다', () {
    test('PR-6 업무 유형 조회', () {
      _propagates(bizSvc,
          'Future<List<BusinessWorkTypeModel>> getBusinessWorkTypes(',
          '공고 준비 gate가 "업무 유형 미등록"으로 굳는다');
    });

    test('PR-7 readiness 는 실패를 UNKNOWN 으로 들고 간다', () {
      final code = _flat(_codeOf(_read(readiness)));
      expect(code.contains('final bool workTypesUnknown;'), isTrue);
      expect(code.contains('workTypesUnknown = true;'), isTrue,
          reason: '조회 실패를 "업무 0개"로 접으면 안 된다');
      expect(
          code.contains(
              'bool get isMissingWorkTypes => !workTypesUnknown && !hasActiveWorkTypes;'),
          isTrue,
          reason: '"업무가 없다"고 말할 수 있는 조건을 따로 둬야 한다');
    });

    test('PR-8 UNKNOWN 을 준비 완료로 올리지 않는다 (fail-closed 유지)', () {
      final code = _flat(_codeOf(_read(readiness)));
      expect(
          code.contains(
              'bool get isReady => isApproved && hasLicense && hasActiveWorkTypes;'),
          isTrue,
          reason: '모를 때 gate 를 열면 서버가 거절하는 공고를 만들게 된다');
    });

    test('PR-9 UNKNOWN 을 Home Task 로 만들지 않는다', () {
      final code = _flat(_codeOf(_read(adminHome)));
      expect(code.contains('r.workTypesUnknown ?'), isTrue,
          reason: '못 읽은 상태에서 "업무를 등록하세요"라고 단정하면 안 된다');
      expect(code.contains('상태를 확인하지 못했어요'), isTrue);
      expect(code.contains('r.isMissingWorkTypes'), isTrue,
          reason: 'CTA 가 업무를 이미 가진 사업장으로 가면 안 된다');
      expect(code.contains('!r.hasActiveWorkTypes'), isFalse,
          reason: 'CTA 판정이 UNKNOWN 을 "없음"으로 읽는 경로가 남아 있다');
    });
  });

  group('[R8P7.4] 리뷰 — 못 읽은 것을 "리뷰 없음"으로 말하지 않는다', () {
    test('PR-10 미공개 리뷰 요청', () {
      _propagates(revSvc,
          'Future<List<ReviewRequestModel>> getAllNonPublishedRequestsForBusiness(',
          '마감일 맵이 통째로 비어 "마감 없음"이 된다');
    });

    test('PR-11 공개 리뷰 조회', () {
      _propagates(revSvc,
          'Future<List<MonthlyReviewModel>> getPublishedReviewsForUser(',
          '근무자 상세가 "받은 리뷰 없음"으로 말하게 된다');
    });
  });

  group('[R8P7.4] 소비부 — 빈 화면의 문장이 이유를 구분한다', () {
    test('PR-12 구직자 홈', () {
      final code = _flat(_codeOf(_read(home)));
      expect(code.contains('bool _postingsFailed'), isTrue);
      expect(code.contains('공고를 불러오지 못했어요'), isTrue);
      // 정상 빈 상태 문구까지 지우면 안 된다 — 둘은 다른 문장이다.
      expect(code.contains('해당 날짜에 지원 가능한 공고가 없어요'), isTrue,
          reason: '실제 empty 문구를 없애는 것은 이 Phase 의 목적이 아니다');
      expect(code.contains('else if (_postingsFailed)'), isTrue,
          reason: '실패 분기가 "없음" 분기보다 먼저 와야 한다');
    });

    test('PR-13 일자리 탭', () {
      final code = _flat(_codeOf(_read(jobTab)));
      expect(code.contains('bool _loadFailed'), isTrue);
      expect(code.contains('if (_loadFailed) {'), isTrue,
          reason: '실패 분기가 즐겨찾기·필터 "없음"보다 먼저 와야 한다');
      expect(code.contains('공고를 불러오지 못했습니다'), isTrue);
      expect(code.contains('등록된 공고가 없습니다'), isTrue,
          reason: '실제 empty 문구는 유지된다');
      expect(code.contains('_loadFailed = _displayList.isEmpty;'), isTrue,
          reason: '이미 받아 둔 목록이 있으면 실패 화면으로 덮지 않는다');
    });

    test('PR-14 사업장 선택 — 조회 실패는 "사업장 0개"가 아니다', () {
      final code = _flat(_codeOf(_read(picker)));
      expect(code.contains('getBusinessesByIdsOrThrow'), isTrue,
          reason: '실패와 0개를 구분하는 변형이 이미 있다 (AH-V2-01)');
      expect(code.contains('사업장 목록을 불러오지 못했습니다'), isTrue);
      expect(code.contains('등록된 사업장이 없습니다'), isTrue,
          reason: '실제 0개 문구는 유지된다');
    });
  });
}
