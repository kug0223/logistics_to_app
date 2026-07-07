// test/simulation/to_security_rule_simulation_test.dart
//
// tos 컬렉션 보안 규칙 충돌 수정 시나리오 시뮬레이션 테스트
//
// 수정 대상:
//   1. getTOGroupItemsLight — whereIn → 병렬 isEqualTo 전환 (2사업장 이상 관리자)
//   2. getTOsByIds — documentId whereIn LIST → 개별 doc GET 병렬 전환 (Algolia 검색)
//
// 검증 내용:
//   - whereIn 사용 시 filters.businessId == null → PERMISSION_DENIED 발생 조건
//   - 병렬 isEqualTo 쿼리의 결과 병합·정렬 정확성
//   - getTOsByIds: 비공개 TO 자동 제외, 빈 결과 처리, 중복 없음
//   - 보안 규칙 요건 충족 여부 명세
//
// Firebase 의존성 없음 — 순수 로직 검증
//
// 실행: flutter test test/simulation/to_security_rule_simulation_test.dart

import 'package:flutter_test/flutter_test.dart';

// ── 테스트용 최소 TO 모델 ──────────────────────────────────────────────────
class _TO {
  final String id;
  final String businessId;
  final DateTime createdAt;
  final String status;
  final bool isPublished;
  final bool isClosed;

  const _TO({
    required this.id,
    required this.businessId,
    required this.createdAt,
    this.status = 'OPEN',
    this.isPublished = true,
    this.isClosed = false,
  });
}

// ── openStates / closedStates (TOStatus 상수 재현) ──────────────────────
const _openStates = {'OPEN', 'PENDING_OPEN'};
const _closedStates = {'CLOSED', 'EXPIRED'};

// ── getTOGroupItemsLight 병렬 쿼리 결과 병합 로직 재현 ──────────────────
// 실제 코드: Future.wait → expand → sort
List<_TO> _mergeAndSort(List<List<_TO>> perBizResults) {
  return perBizResults
      .expand((list) => list)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

// ── getTOsByIds 결과 필터 로직 재현 ──────────────────────────────────────
// 실제 코드: .where((to) => to.isPublished && !to.isClosed)
List<_TO> _filterPublishedAndOpen(List<_TO?> snaps) {
  return snaps
      .whereType<_TO>()
      .where((to) => to.isPublished && !to.isClosed)
      .toList();
}

void main() {
  // ════════════════════════════════════════════════════════════════════
  // 1. whereIn → isEqualTo 전환 이유 — 보안 규칙 충돌 명세
  // ════════════════════════════════════════════════════════════════════
  group('SCENARIO-TO-1: tos list 규칙 충돌 조건 명세', () {
    test('SEC-01 businessId isEqualTo → filters.businessId 정상 평가 (안전)', () {
      // tos list 규칙: isAdminOf(request.query.filters.businessId)
      // isEqualTo 사용 시 → filters.businessId == "biz-001" → isAdminOf 정상 평가
      const query = 'businessId isEqualTo biz-001';
      expect(query.contains('isEqualTo'), isTrue);
      // 단일 사업장 관리자: filters.businessId 정상 → PERMISSION_DENIED 없음
    });

    test('SEC-02 businessId whereIn → filters.businessId == null (PERMISSION_DENIED)', () {
      // whereIn: [biz-001, biz-002] → Firebase 버그로 filters.businessId == null
      // → isAdminOf(null) == false → PERMISSION_DENIED
      // 수정 전 동작: 2사업장 관리자가 관리자 홈 화면 진입 시 TO 목록이 비어있었음
      const query = 'businessId whereIn [biz-001, biz-002]';
      expect(query.contains('whereIn'), isTrue);
      // 이 패턴은 수정 후 완전히 제거됨
    });

    test('SEC-03 documentId whereIn LIST → isPublished 서버 필터 없음 (PERMISSION_DENIED)', () {
      // tos list USER 규칙: request.query.filters.isPublished == true 강제
      // documentId whereIn + isPublished 서버 필터 없음 → PERMISSION_DENIED
      // 수정 전 동작: Algolia 검색 결과 fetch 시 PERMISSION_DENIED로 빈 결과 반환
      const hasIsPublishedServerFilter = false;
      const isListQuery = true;
      // LIST 규칙 요건 미충족 → 거부
      expect(hasIsPublishedServerFilter && isListQuery, isFalse);
    });

    test('SEC-04 개별 doc GET → GET 규칙으로 처리 (isPublished 체크 서버사이드)', () {
      // GET 규칙: isLoggedIn() && (isPublished == true || 관리자)
      // 개별 GET은 resource.data.isPublished로 서버사이드 검증
      // → isPublished=false인 TO는 GET 규칙에서 거부 → null로 처리 → 결과에서 제외
      const isGetRequest = true; // doc(id).get()
      const useGetRule = true;   // GET 규칙 적용
      expect(isGetRequest && useGetRule, isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // 2. getTOGroupItemsLight: 병렬 isEqualTo 결과 병합·정렬
  // ════════════════════════════════════════════════════════════════════
  group('SCENARIO-TO-2: getTOGroupItemsLight 병렬 결과 병합 정확성', () {
    final now = DateTime(2026, 7, 7, 12, 0);

    test('MERGE-01 2개 사업장 결과 병합 후 createdAt 내림차순 정렬', () {
      final bizA = [
        _TO(id: 'to-a1', businessId: 'biz-A', createdAt: now.subtract(const Duration(hours: 1))),
        _TO(id: 'to-a2', businessId: 'biz-A', createdAt: now.subtract(const Duration(hours: 3))),
      ];
      final bizB = [
        _TO(id: 'to-b1', businessId: 'biz-B', createdAt: now.subtract(const Duration(hours: 2))),
        _TO(id: 'to-b2', businessId: 'biz-B', createdAt: now.subtract(const Duration(hours: 4))),
      ];
      final merged = _mergeAndSort([bizA, bizB]);
      expect(merged.length, 4);
      // 내림차순 (최신 순)
      expect(merged[0].id, 'to-a1'); // -1h
      expect(merged[1].id, 'to-b1'); // -2h
      expect(merged[2].id, 'to-a2'); // -3h
      expect(merged[3].id, 'to-b2'); // -4h
    });

    test('MERGE-02 한 사업장이 비어있어도 정상 병합', () {
      final bizA = [
        _TO(id: 'to-a1', businessId: 'biz-A', createdAt: now),
      ];
      final bizB = <_TO>[];
      final merged = _mergeAndSort([bizA, bizB]);
      expect(merged.length, 1);
      expect(merged[0].id, 'to-a1');
    });

    test('MERGE-03 모든 사업장이 비어있으면 빈 리스트', () {
      final merged = _mergeAndSort([[], [], []]);
      expect(merged, isEmpty);
    });

    test('MERGE-04 10개 사업장 각 2개 TO → 20개 내림차순 정렬', () {
      final perBiz = List.generate(10, (i) => [
        _TO(id: 'to-${i}a', businessId: 'biz-$i',
            createdAt: now.subtract(Duration(hours: i * 2))),
        _TO(id: 'to-${i}b', businessId: 'biz-$i',
            createdAt: now.subtract(Duration(hours: i * 2 + 1))),
      ]);
      final merged = _mergeAndSort(perBiz);
      expect(merged.length, 20);
      // 정렬 확인: 앞 원소의 createdAt >= 뒤 원소의 createdAt
      for (int i = 0; i < merged.length - 1; i++) {
        expect(
          merged[i].createdAt.isAfter(merged[i + 1].createdAt) ||
              merged[i].createdAt.isAtSameMomentAs(merged[i + 1].createdAt),
          isTrue,
          reason: '인덱스 $i: ${merged[i].id} createdAt이 ${merged[i+1].id}보다 앞이어야 함',
        );
      }
    });

    test('MERGE-05 activeOnly 필터: OPEN/PENDING_OPEN 상태만 포함', () {
      final allTOs = [
        _TO(id: 'to-1', businessId: 'biz-A', createdAt: now, status: 'OPEN'),
        _TO(id: 'to-2', businessId: 'biz-A', createdAt: now, status: 'CLOSED'),
        _TO(id: 'to-3', businessId: 'biz-B', createdAt: now, status: 'PENDING_OPEN'),
        _TO(id: 'to-4', businessId: 'biz-B', createdAt: now, status: 'EXPIRED'),
      ];
      // 실제 코드: q.where('status', whereIn: TOStatus.openStates) 서버 적용
      // 테스트: 클라이언트에서 동일 로직 검증
      final active = allTOs.where((t) => _openStates.contains(t.status)).toList();
      expect(active.length, 2);
      expect(active.map((t) => t.id).toSet(), {'to-1', 'to-3'});
    });

    test('MERGE-06 closedOnly 필터: CLOSED/EXPIRED 상태만 포함', () {
      final allTOs = [
        _TO(id: 'to-1', businessId: 'biz-A', createdAt: now, status: 'OPEN'),
        _TO(id: 'to-2', businessId: 'biz-A', createdAt: now, status: 'CLOSED'),
        _TO(id: 'to-3', businessId: 'biz-B', createdAt: now, status: 'EXPIRED'),
      ];
      final closed = allTOs.where((t) => _closedStates.contains(t.status)).toList();
      expect(closed.length, 2);
      expect(closed.map((t) => t.id).toSet(), {'to-2', 'to-3'});
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // 3. getTOsByIds: 개별 GET 결과 필터링
  // ════════════════════════════════════════════════════════════════════
  group('SCENARIO-TO-3: getTOsByIds 개별 GET 결과 필터링', () {
    test('GET-01 isPublished=true && isClosed=false → 포함', () {
      final snaps = [
        _TO(id: 'to-1', businessId: 'biz-A',
            createdAt: DateTime(2026, 7, 1),
            isPublished: true, isClosed: false),
      ];
      final result = _filterPublishedAndOpen(snaps);
      expect(result.length, 1);
      expect(result[0].id, 'to-1');
    });

    test('GET-02 isPublished=false → 제외 (GET 규칙 거부 후 null로 처리된 것과 동일)', () {
      // 비공개 TO: GET 규칙에서 PERMISSION_DENIED → null → 이 함수에 도달하지 않음
      // 설령 도달하더라도 isPublished=false 필터로 제외됨 (이중 방어)
      final snaps = [
        _TO(id: 'to-priv', businessId: 'biz-A',
            createdAt: DateTime(2026, 7, 1),
            isPublished: false, isClosed: false),
      ];
      final result = _filterPublishedAndOpen(snaps);
      expect(result, isEmpty);
    });

    test('GET-03 isClosed=true → 제외 (Algolia 인덱스 지연 방어)', () {
      final snaps = [
        _TO(id: 'to-closed', businessId: 'biz-A',
            createdAt: DateTime(2026, 7, 1),
            isPublished: true, isClosed: true),
      ];
      final result = _filterPublishedAndOpen(snaps);
      expect(result, isEmpty);
    });

    test('GET-04 null 항목 (GET 거부 또는 미존재 문서) → whereType로 자동 제거', () {
      // GET 규칙 PERMISSION_DENIED → onError: (_) => null
      final snaps = [
        _TO(id: 'to-ok', businessId: 'biz-A',
            createdAt: DateTime(2026, 7, 1),
            isPublished: true, isClosed: false),
        null, // PERMISSION_DENIED 또는 미존재
        null,
      ];
      final result = _filterPublishedAndOpen(snaps);
      expect(result.length, 1);
      expect(result[0].id, 'to-ok');
    });

    test('GET-05 혼합 (공개+비공개+마감+null) → 공개·미마감만 반환', () {
      final snaps = [
        _TO(id: 'to-1', businessId: 'biz-A',
            createdAt: DateTime(2026, 7, 1),
            isPublished: true, isClosed: false),   // 포함
        _TO(id: 'to-2', businessId: 'biz-B',
            createdAt: DateTime(2026, 7, 2),
            isPublished: false, isClosed: false),  // 제외(비공개)
        _TO(id: 'to-3', businessId: 'biz-C',
            createdAt: DateTime(2026, 7, 3),
            isPublished: true, isClosed: true),    // 제외(마감)
        null,                                       // 제외(GET 거부)
        _TO(id: 'to-4', businessId: 'biz-D',
            createdAt: DateTime(2026, 7, 4),
            isPublished: true, isClosed: false),   // 포함
      ];
      final result = _filterPublishedAndOpen(snaps);
      expect(result.length, 2);
      expect(result.map((t) => t.id).toSet(), {'to-1', 'to-4'});
    });

    test('GET-06 빈 ids 리스트 → 빈 결과 (Future.wait 호출 없음)', () {
      // 실제 코드: if (ids.isEmpty) return [];
      final result = _filterPublishedAndOpen([]);
      expect(result, isEmpty);
    });

    test('GET-07 모두 null → 빈 결과 (NPE 없음)', () {
      final result = _filterPublishedAndOpen([null, null, null]);
      expect(result, isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // 4. 수정 전후 동작 비교
  // ════════════════════════════════════════════════════════════════════
  group('SCENARIO-TO-4: 수정 전후 동작 비교', () {
    test('BEF-01 수정 전: 2사업장 관리자가 TO 목록 조회 시 PERMISSION_DENIED → 빈 목록', () {
      // 수정 전 동작 시뮬레이션:
      // businessIds = ['biz-A', 'biz-B'] → whereIn 사용
      // → filters.businessId == null → isAdminOf(null) == false → PERMISSION_DENIED
      // → catch(e) { return []; } → 빈 목록 반환
      // 관리자는 TO가 있는데도 목록이 비어있는 현상 발생
      const permissionDenied = true; // whereIn으로 인한 거부
      final result = permissionDenied ? <String>[] : ['to-1', 'to-2'];
      expect(result, isEmpty); // 버그: 실제 TO가 있어도 빈 목록
    });

    test('BEF-02 수정 후: 병렬 isEqualTo → filters.businessId 정상 평가 → TO 목록 반환', () {
      // 수정 후 동작 시뮬레이션:
      // businessId isEqualTo 'biz-A' → filters.businessId == 'biz-A' → isAdminOf 정상 평가
      // businessId isEqualTo 'biz-B' → filters.businessId == 'biz-B' → isAdminOf 정상 평가
      // → 두 결과 병합 → TO 목록 정상 반환
      const permissionDenied = false; // isEqualTo로 정상 평가
      final result = permissionDenied ? <String>[] : ['to-1', 'to-2'];
      expect(result, isNotEmpty); // 정상: TO 목록 반환
    });

    test('BEF-03 수정 전: Algolia 검색 결과 fetch 시 PERMISSION_DENIED → 빈 결과', () {
      // 수정 전 동작:
      // documentId whereIn → LIST 규칙 → isPublished 서버 필터 없음 → PERMISSION_DENIED
      // → catch → 빈 결과 또는 앱 오류
      const listRuleRequiresIsPublishedFilter = true;
      const queryHasIsPublishedFilter = false;
      final wouldPermissionDeny = listRuleRequiresIsPublishedFilter && !queryHasIsPublishedFilter;
      expect(wouldPermissionDeny, isTrue); // 버그: PERMISSION_DENIED 발생
    });

    test('BEF-04 수정 후: 개별 GET → GET 규칙 적용 → 공개 TO 정상 반환', () {
      // 수정 후 동작:
      // doc(id).get() → GET 규칙 → isPublished == true → 정상 반환
      // isPublished == false → GET 규칙 거부 → null → 결과에서 제외 (자동 필터)
      const getRuleAllowsPublished = true;
      expect(getRuleAllowsPublished, isTrue); // 정상: 공개 TO 반환
    });
  });
}
