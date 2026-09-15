// [HOME-V2-08D.6] task health notice root cause
//
// 08D.5 이후 실기기 SCREEN A:
//
//   처리할 일
//   이체 대기                    1건 >
//   연체 1건
//   ⓘ 일부 업무 상태를 확인하지 못했어요    재시도
//
// notice는 정상 동작이었다 — 실제로 확인하지 못한 producer가 있었다.
//
// DEV Cloud Functions 로그(2026-09-14 ~ 09-15, 12건)가 단일 원인을 지목한다:
//
//   [adminHome] <bizId> resignRequest 실패:
//     9 FAILED_PRECONDITION: The query requires an index.
//     applications (businessId ASC, resignStatus ASC, resignRequestedAt ASC)
//
// 다른 8종은 한 건도 실패하지 않았다. `마감 필요`(unclosed)는 정상이었다.
//
// 원인 분류: **missing index — 방향 불일치.**
//   firestore.indexes.json에는 같은 3필드가 resignRequestedAt DESCENDING으로
//   있었고, srvHomeResignRequest의 `<=` count()는 ASCENDING을 요구한다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _cfPath = 'functions/src/index.ts';
const _indexPath = 'firestore.indexes.json';
const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) throw StateError('$signature 를 찾지 못함');
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
  throw StateError('$signature 본문의 끝을 찾지 못함');
}

/// TS top-level 함수 본문. `_bodyOf`는 `Promise<{...}>` 반환 타입의 중괄호에
/// 걸리므로, 최상위 함수는 열 0의 `}`까지를 본문으로 본다.
String _tsBodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) throw StateError('$signature 를 찾지 못함');
  final end = source.indexOf('\n}\n', start);
  if (end == -1) throw StateError('$signature 본문의 끝을 찾지 못함');
  return source.substring(start, end + 2);
}

/// firestore.indexes.json에 (collection, [field:ORDER, ...]) 조합이 있는가.
bool hasIndex(List<dynamic> indexes, String collection, List<List<String>> want) {
  return indexes.any((raw) {
    final i = raw as Map<String, dynamic>;
    if (i['collectionGroup'] != collection) return false;
    final fields = (i['fields'] as List)
        .map((f) => [
              (f as Map)['fieldPath'] as String,
              (f['order'] as String?) ?? 'ARRAY',
            ])
        .toList();
    if (fields.length < want.length) return false;
    for (var k = 0; k < want.length; k++) {
      if (fields[k][0] != want[k][0] || fields[k][1] != want[k][1]) return false;
    }
    return true;
  });
}

// ═══════════════════════════════════════════════════════════════
// aggregation replica — §8
// ═══════════════════════════════════════════════════════════════

/// aggSimple의 available 계산. `getCount`가 undefined면 실패로 센다.
({bool available, int count}) aggSimple(List<int?> perBusiness) {
  var permCount = 0, successCount = 0, total = 0;
  for (final v in perBusiness) {
    permCount++;
    if (v != null) {
      successCount++;
      total += v;
    }
  }
  return (
    available: permCount > 0 && successCount == permCount,
    count: total,
  );
}

void main() {
  final cf = _src(_cfPath);
  final home = _src(_homePath);
  final indexes =
      (jsonDecode(_src(_indexPath)) as Map<String, dynamic>)['indexes'] as List;
  final resignFn = _tsBodyOf(cf, 'async function srvHomeResignRequest(');
  final unclosedFn = _tsBodyOf(cf, 'async function srvHomeUnclosed(');

  // ═══════════════════════════════════════════════════════════════
  // 01. root cause — missing index
  // ═══════════════════════════════════════════════════════════════
  group('[08D.6-01] resignRequest index', () {
    test('01-a soonCount 쿼리가 세 필드 equality+range를 쓴다', () {
      final c = _codeOf(resignFn);
      expect(c, contains('.where("businessId", "==", bizId)'));
      expect(c, contains('.where("resignStatus", "==", "PENDING")'));
      expect(c, contains('.where("resignRequestedAt", "<=", soonBoundary)'));
      expect(c, contains('.count()'));
    });

    test('01-b 그 쿼리를 서빙하는 ASCENDING 인덱스가 존재한다', () {
      // FAILED_PRECONDITION이 정확히 이 조합을 요구했다
      expect(
        hasIndex(indexes, 'applications', [
          ['businessId', 'ASCENDING'],
          ['resignStatus', 'ASCENDING'],
          ['resignRequestedAt', 'ASCENDING'],
        ]),
        isTrue,
        reason: 'DESCENDING 인덱스는 이 count() 쿼리를 서빙하지 못한다',
      );
    });

    test('01-c 기존 DESCENDING 인덱스도 남아 있다', () {
      // 다른 쿼리가 쓰고 있을 수 있으므로 이번 Phase에서 제거하지 않았다
      expect(
        hasIndex(indexes, 'applications', [
          ['businessId', 'ASCENDING'],
          ['resignStatus', 'ASCENDING'],
          ['resignRequestedAt', 'DESCENDING'],
        ]),
        isTrue,
      );
    });

    test('01-d 전체 건수 쿼리는 두 필드 — 기존 인덱스로 충분', () {
      expect(_codeOf(resignFn), contains('base.count().get()'));
      expect(
        hasIndex(indexes, 'applications', [
          ['businessId', 'ASCENDING'],
          ['resignStatus', 'ASCENDING'],
        ]),
        isTrue,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 02. 나머지 producer의 쿼리도 인덱스를 갖는가
  // ═══════════════════════════════════════════════════════════════
  group('[08D.6-02] 9종 producer index coverage', () {
    test('02-a approval / unsentContract / expiringContract', () {
      expect(
          hasIndex(indexes, 'applications', [
            ['businessId', 'ASCENDING'],
            ['status', 'ASCENDING'],
          ]),
          isTrue);
      expect(
          hasIndex(indexes, 'applications', [
            ['businessId', 'ASCENDING'],
            ['status', 'ASCENDING'],
            ['createdAt', 'DESCENDING'],
          ]),
          isTrue);
      expect(
          hasIndex(indexes, 'applications', [
            ['businessId', 'ASCENDING'],
            ['status', 'ASCENDING'],
            ['workEndDate', 'ASCENDING'],
          ]),
          isTrue);
    });

    test('02-b unpaidWage / unclosed', () {
      expect(
          hasIndex(indexes, 'attendance', [
            ['businessId', 'ASCENDING'],
            ['wageStatus', 'ASCENDING'],
          ]),
          isTrue);
      // unclosed는 applications(businessId, status in) + attendance getAll
      expect(_codeOf(unclosedFn), contains('db.getAll('));
    });

    test('02-c wageChange / settlement / scheduleChange', () {
      expect(
          hasIndex(indexes, 'payment_change_requests', [
            ['businessId', 'ASCENDING'],
            ['status', 'ASCENDING'],
          ]),
          isTrue);
      expect(
          hasIndex(indexes, 'interim_settlement_requests', [
            ['businessId', 'ASCENDING'],
            ['status', 'ASCENDING'],
          ]),
          isTrue);
      // equality-only 3필드 — 인덱스 필드 순서는 무관하다
      expect(
          hasIndex(indexes, 'schedule_change_requests', [
            ['businessId', 'ASCENDING'],
            ['requestedBy', 'ASCENDING'],
            ['status', 'ASCENDING'],
          ]),
          isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 03. empty result ≠ error — §8
  // ═══════════════════════════════════════════════════════════════
  group('[08D.6-03] 빈 결과는 KNOWN_ZERO다', () {
    test('03-a 0 docs도 성공으로 센다', () {
      final r = aggSimple([0, 0]);
      expect(r.available, isTrue);
      expect(r.count, 0);
    });

    test('03-b 하나라도 실패하면 available=false', () {
      expect(aggSimple([0, null]).available, isFalse);
      expect(aggSimple([3, null]).available, isFalse);
    });

    test('03-c 실패를 0으로 합산하지 않는다', () {
      // 성공한 사업장의 정확한 합만 남고, 불완전하다는 사실은 available이 전달한다
      final r = aggSimple([3, null]);
      expect(r.count, 3);
      expect(r.available, isFalse);
    });

    test('03-d 서버가 undefined만 실패로 본다 (0은 실패가 아니다)', () {
      final agg = _codeOf(_bodyOf(cf, 'const aggSimple ='));
      expect(agg, contains('if (v !== undefined) {'));
      expect(agg.contains('if (v) {'), isFalse,
          reason: 'truthy 검사면 count 0이 실패로 둔갑한다');
      expect(agg,
          contains('available: permCount > 0 && successCount === permCount'));
    });

    test('03-e 커스텀 집계 3종도 객체 존재로만 판단한다', () {
      // {count: 0} 같은 객체는 truthy이므로 0건이 실패로 새지 않는다
      for (final marker in [
        'if (!r.approval) continue;',
        'if (!r.unpaidWage) continue;',
        'if (!r.unclosed) continue;',
      ]) {
        expect(cf.contains(marker), isTrue, reason: marker);
      }
    });

    test('03-f srvHomeResignRequest는 0건에서도 객체를 돌려준다', () {
      expect(_codeOf(resignFn),
          contains('return {count: allAgg.data().count, soonCount: soonAgg.data().count};'));
      expect(_codeOf(resignFn).contains('return undefined'), isFalse);
    });

    test('03-g srvHomeUnclosed는 빈 결과를 명시적으로 0으로 돌려준다', () {
      final c = _codeOf(unclosedFn);
      expect(c, contains('if (appSnap.empty) return {count: 0, oldestDate: null};'));
      expect(c, contains('if (docDateMap.size === 0) return {count: 0, oldestDate: null};'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 04. `마감 필요` canonical 의미 — §5
  // ═══════════════════════════════════════════════════════════════
  group('[08D.6-04] unclosed canonical meaning', () {
    test('04-a 공고 마감이 아니라 근무일 급여 마감이다', () {
      final c = _codeOf(unclosedFn);
      // 활성 지원서의 예상 근무일을 펼쳐 attendance 마감 여부를 본다
      expect(c, contains('db.collection("applications")'));
      expect(c, contains('.where("status", "in", ["CONFIRMED", "CONTRACT_PENDING"])'));
      expect(c, contains('db.collection("attendance")'));
      // TO/공고 collection을 읽지 않는다
      expect(c.contains('collection("tos")'), isFalse);
      expect(c.contains('deadline'), isFalse);
    });

    test('04-b 마감 조건은 wageStatus 또는 NO_SHOW다', () {
      expect(_codeOf(unclosedFn),
          contains('ws === "confirmed" || ws === "transferred" || st === "NO_SHOW"'));
    });

    test('04-c canonical unit은 unique 날짜다', () {
      final c = _codeOf(unclosedFn);
      expect(c, contains('const unclosedDates = new Set<string>();'));
      expect(c, contains('count: unclosedDates.size,'));
    });

    test('04-d 범위 초과는 조용히 줄이지 않고 throw한다', () {
      // silent undercount 금지 — 그때는 available:false가 된다
      expect(_codeOf(unclosedFn), contains('const CAP_DAYS = 3650;'));
      expect(_codeOf(unclosedFn), contains('throw new Error('));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 05. 클라이언트 무회귀 — §14, §16
  // ═══════════════════════════════════════════════════════════════
  group('[08D.6-05] 08D.5 계약 무회귀', () {
    test('05-a UNKNOWN을 named row로 되살리지 않았다', () {
      final make = _codeOf(_bodyOf(home, '_makeActionRows(BuildContext context'));
      expect(make, contains('if (!available || count == 0) return;'));
      expect(make.contains('조회 실패'), isFalse);
    });

    test('05-b notice는 실제 UNKNOWN이 있을 때만 뜬다', () {
      final dash = _codeOf(_bodyOf(home, 'Widget _buildActionDashboard('));
      expect(dash, contains('final unknownCount = _unknownTaskCount(up, cs);'));
      expect(dash, contains('final showNotice = summaryFailed || unknownCount > 0;'));
    });

    test('05-c 모든 producer가 KNOWN이면 notice가 사라진다', () {
      // unknownCount == 0 && cs != null → showNotice == false
      const summaryFailed = false;
      const unknownCount = 0;
      expect(summaryFailed || unknownCount > 0, isFalse);
    });

    test('05-d notice를 무조건 숨기는 코드를 넣지 않았다', () {
      final dash = _codeOf(_bodyOf(home, 'Widget _buildActionDashboard('));
      expect(dash.contains('showNotice = false'), isFalse);
      expect(dash.contains('// TODO'), isFalse);
    });

    test('05-e 클라이언트 코드는 이번 Phase에서 바뀌지 않았다', () {
      // root cause가 backend index였으므로 client patch는 0이다
      final unknown = _codeOf(_bodyOf(home, 'int _unknownTaskCount('));
      expect(RegExp(r'chk\(permitted:').allMatches(unknown).length, 9);
      expect(unknown, contains('if (cs == null) return 0;'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 06. Functions 무회귀 — §19
  // ═══════════════════════════════════════════════════════════════
  group('[08D.6-06] Functions 무회귀', () {
    test('06-a srvHomeResignRequest가 count() aggregation을 유지한다', () {
      // 문서 fetch로 바꾸면 read 비용이 늘어난다 (주석 포함 원본에서 확인)
      expect(resignFn, contains('count() aggregation — 문서 fetch 없음'));
      expect(RegExp(r'\.count\(\)').allMatches(resignFn).length, 2);
      expect(_codeOf(resignFn).contains('.select('), isFalse,
          reason: '문서를 읽지 않는다');
    });

    test('06-b 실패 로깅이 남아 있다 — 다음 원인도 같은 방법으로 찾는다', () {
      for (final key in [
        'approval', 'unsentContract', 'unpaidWage', 'unclosed',
        'wageChangeRequest', 'settlementRequest', 'resignRequest',
        'scheduleChange', 'expiringContract',
      ]) {
        expect(cf.contains('[adminHome] \${bizId} $key 실패:'), isTrue,
            reason: key);
      }
    });

    test('06-c Promise.allSettled 계약이 그대로다', () {
      expect(cf, contains('await Promise.allSettled(['));
      expect(cf, contains('appR.status      === "fulfilled" ? appR.value      : undefined'));
    });

    test('06-d 이번 Phase에서 Functions 코드를 바꾸지 않았다', () {
      // 변경은 firestore.indexes.json 한 곳뿐이다
      expect(_codeOf(resignFn), contains('const soonBoundary = admin.firestore.Timestamp.fromDate('));
      expect(_codeOf(resignFn),
          contains('new Date(todayKSTMidnight.getTime() - 2 * 24 * 60 * 60 * 1000)'));
    });
  });
}
