// ignore_for_file: lines_longer_than_80_chars
//
// 계약서 관리 성능 최적화 시뮬레이션 테스트
//
// 검증 대상:
//   A. 탭 캐시 로직 — 히트/미스/무효화
//   B. pull-to-refresh vs mutation 캐시 정책
//   C. _openContract 단건 업데이트 분기
//   D. getUnsentApplicationsByBusiness 미발송 필터 로직
//   E. CF callableGetUnsentApplicationsByBiz 시뮬레이션
//   F. _loadMore 캐시 누적 로직
//   G. 탭별 상태 격리
//   H. _filteredItems / _filteredUnsentApps 검색 필터
//   I. 검색 debounce 로직 (Timer 기반)
//   J. 엣지케이스 — 빈 목록, 캐시 충돌, 탭 경계값

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';

// ════════════════════════════════════════════════════════════
// 시뮬레이션 헬퍼
// ════════════════════════════════════════════════════════════

final _now = DateTime.now();
final _nowTs = Timestamp.fromDate(_now);

ApplicationModel _makeApp({
  required String id,
  String? name,
  String workType = '주방보조',
  String status = 'CONTRACT_PENDING',
}) =>
    ApplicationModel.fromMap({
      'uid': 'worker_$id',
      'toId': 'to_1',
      'businessId': 'biz_1',
      'status': status,
      'workDate': _nowTs,
      'appliedAt': _nowTs,
      'applicantName': name ?? '근무자$id',
      'selectedWorkType': workType,
    }, id);

EmploymentContractModel _makeContract({
  required String id,
  ContractStatus status = ContractStatus.pendingWorker,
  String workerName = '근무자',
}) =>
    EmploymentContractModel(
      id: id,
      applicationId: 'app_$id',
      businessId: 'biz_1',
      workerId: 'worker_$id',
      isLongTerm: false,
      toId: 'to_1',
      workDetailId: 'wd_1',
      slots: [],
      applicationIds: ['app_$id'],
      status: status,
      snapshot: ContractSnapshot(
        businessName: '테스트 사업장',
        businessNumber: '000-00-00000',
        businessAddress: '서울시',
        businessPhone: '02-0000-0000',
        ownerName: '대표자',
        workerName: workerName,
        workType: '주방보조',
        workPlace: '주방',
        isLongTerm: false,
        startTime: '09:00',
        endTime: '18:00',
        breakMinutes: 60,
        wage: 10000,
        wageType: 'hourly',
      ),
      articles: [],
      createdAt: _now,
    );

// ══════════════════════════════════════════════════════════════════════
// 탭 캐시 시뮬레이터 — AdminContractManagementScreen 핵심 로직 재현
// ══════════════════════════════════════════════════════════════════════

class _TabCacheSim {
  final Map<int, ({List<EmploymentContractModel> items, String? lastDocId, bool hasMore})>
      tabCache = {};
  List<ApplicationModel>? unsentCache;

  int fetchCount = 0; // CF 호출 횟수 추적

  // 탭 2~4 (계약서 목록 탭) 로드 시뮬레이션
  Future<List<EmploymentContractModel>> load({
    required int tabIdx,
    required List<EmploymentContractModel> serverData,
    bool useCache = true,
  }) async {
    if (useCache && tabCache.containsKey(tabIdx)) {
      // 캐시 히트 — CF 호출 없음
      return List.from(tabCache[tabIdx]!.items);
    }
    // 캐시 미스 — CF 호출
    fetchCount++;
    tabCache[tabIdx] = (items: List.from(serverData), lastDocId: null, hasMore: false);
    return serverData;
  }

  // 미발송 탭 (index 1) 로드 시뮬레이션
  Future<List<ApplicationModel>> loadUnsent({
    required List<ApplicationModel> serverData,
    bool useCache = true,
  }) async {
    if (useCache && unsentCache != null) {
      return List.from(unsentCache!);
    }
    fetchCount++;
    unsentCache = List.from(serverData);
    return serverData;
  }

  // pull-to-refresh: 현재 탭 캐시만 무효화
  void refreshTab(int tabIdx, {bool isUnsentTab = false}) {
    if (isUnsentTab) {
      unsentCache = null;
    } else {
      tabCache.remove(tabIdx);
    }
  }

  // mutation: 전체 탭 캐시 무효화
  void invalidateAll() {
    tabCache.clear();
    unsentCache = null;
  }

  // 페이지네이션 후 캐시 갱신
  void updateCacheAfterPagination(
    int tabIdx,
    List<EmploymentContractModel> allItems,
    String? lastDocId,
    bool hasMore,
  ) {
    tabCache[tabIdx] = (items: List.from(allItems), lastDocId: lastDocId, hasMore: hasMore);
  }

  // 단건 업데이트 후 캐시 동기화
  void syncSingleItem(int tabIdx, String contractId, EmploymentContractModel? updated,
      ContractStatus? currentFilter) {
    final cached = tabCache[tabIdx];
    if (cached == null) return;
    final items = List<EmploymentContractModel>.from(cached.items);
    final idx = items.indexWhere((c) => c.id == contractId);
    if (idx < 0) return;
    if (updated == null) {
      items.removeAt(idx);
    } else if (currentFilter != null && updated.status != currentFilter) {
      items.removeAt(idx);
    } else {
      items[idx] = updated;
    }
    tabCache[tabIdx] = (items: items, lastDocId: cached.lastDocId, hasMore: cached.hasMore);
  }
}

// ══════════════════════════════════════════════════════════════════════
// CF 미발송 필터 로직 시뮬레이터
// ══════════════════════════════════════════════════════════════════════

class _UnsentFilterSim {
  // CF callableGetUnsentApplicationsByBiz 핵심 로직 재현
  static List<ApplicationModel> filter({
    required List<ApplicationModel> contractPendingApps,
    required Map<String, String?> contractStatusByAppId,
    // null = 계약서 없음, 'voided' = 무효화, 'pending_worker'/'completed' = 활성
  }) {
    return contractPendingApps.where((app) {
      final status = contractStatusByAppId[app.id];
      // 계약서 없거나 voided인 경우만 미발송으로 간주
      return status == null || status.isEmpty || status == 'voided';
    }).toList();
  }
}

// ══════════════════════════════════════════════════════════════════════
// 검색 필터 시뮬레이터
// ══════════════════════════════════════════════════════════════════════

class _SearchFilterSim {
  static List<EmploymentContractModel> filterContracts(
    List<EmploymentContractModel> items,
    String query,
  ) {
    if (query.isEmpty) return items;
    final q = query.toLowerCase();
    return items.where((c) => c.snapshot.workerName.toLowerCase().contains(q)).toList();
  }

  static List<ApplicationModel> filterUnsent(
    List<ApplicationModel> apps,
    String query,
  ) {
    if (query.isEmpty) return apps;
    final q = query.toLowerCase();
    return apps
        .where((a) =>
            (a.applicantName ?? '').toLowerCase().contains(q) ||
            a.selectedWorkType.toLowerCase().contains(q))
        .toList();
  }
}

// ════════════════════════════════════════════════════════════
// 테스트
// ════════════════════════════════════════════════════════════

void main() {
  // ─── A. 탭 캐시 — 히트/미스 ─────────────────────────────
  group('A. 탭 캐시 히트/미스', () {
    test('A-01: 최초 로드는 CF 호출 (캐시 미스)', () async {
      final sim = _TabCacheSim();
      final contracts = [_makeContract(id: '1'), _makeContract(id: '2')];
      await sim.load(tabIdx: 0, serverData: contracts);
      expect(sim.fetchCount, 1);
    });

    test('A-02: 동일 탭 재방문은 캐시 히트 → CF 호출 없음', () async {
      final sim = _TabCacheSim();
      final contracts = [_makeContract(id: '1'), _makeContract(id: '2')];
      await sim.load(tabIdx: 0, serverData: contracts);
      await sim.load(tabIdx: 0, serverData: contracts);
      expect(sim.fetchCount, 1, reason: '두 번째 로드는 캐시 히트여야 함');
    });

    test('A-03: 다른 탭은 별도 캐시 — 탭 2 로드 후 탭 3 로드 시 CF 2번', () async {
      final sim = _TabCacheSim();
      final c1 = [_makeContract(id: '1', status: ContractStatus.pendingWorker)];
      final c2 = [_makeContract(id: '2', status: ContractStatus.completed)];
      await sim.load(tabIdx: 2, serverData: c1);
      await sim.load(tabIdx: 3, serverData: c2);
      expect(sim.fetchCount, 2);
    });

    test('A-04: 탭 2 캐시 히트 후 탭 3 재방문도 캐시 히트', () async {
      final sim = _TabCacheSim();
      final c1 = [_makeContract(id: '1', status: ContractStatus.pendingWorker)];
      final c2 = [_makeContract(id: '2', status: ContractStatus.completed)];
      await sim.load(tabIdx: 2, serverData: c1);
      await sim.load(tabIdx: 3, serverData: c2);
      await sim.load(tabIdx: 2, serverData: c1); // 재방문
      await sim.load(tabIdx: 3, serverData: c2); // 재방문
      expect(sim.fetchCount, 2, reason: '재방문은 캐시 히트여야 함');
    });

    test('A-05: 미발송 탭(index 1) 캐시 히트', () async {
      final sim = _TabCacheSim();
      final apps = [_makeApp(id: '1'), _makeApp(id: '2')];
      await sim.loadUnsent(serverData: apps);
      await sim.loadUnsent(serverData: apps);
      expect(sim.fetchCount, 1);
    });

    test('A-06: 캐시 히트 시 반환 데이터는 원본과 동일 내용', () async {
      final sim = _TabCacheSim();
      final contracts = [
        _makeContract(id: '1', workerName: '김철수'),
        _makeContract(id: '2', workerName: '이영희'),
      ];
      await sim.load(tabIdx: 0, serverData: contracts);
      final cached = await sim.load(tabIdx: 0, serverData: []);
      expect(cached.map((c) => c.snapshot.workerName).toList(),
          ['김철수', '이영희']);
    });

    test('A-07: 캐시는 원본 리스트와 독립적(defensive copy)', () async {
      final sim = _TabCacheSim();
      final contracts = [_makeContract(id: '1')];
      await sim.load(tabIdx: 0, serverData: contracts);
      contracts.add(_makeContract(id: '99')); // 원본 변경
      final cached = await sim.load(tabIdx: 0, serverData: contracts);
      expect(cached.length, 1, reason: '캐시는 원본 변경에 영향받지 않아야 함');
    });
  });

  // ─── B. 캐시 무효화 정책 ──────────────────────────────────
  group('B. 캐시 무효화 정책', () {
    test('B-01: pull-to-refresh는 현재 탭 캐시만 무효화', () async {
      final sim = _TabCacheSim();
      final c0 = [_makeContract(id: '1')];
      final c2 = [_makeContract(id: '2', status: ContractStatus.pendingWorker)];
      await sim.load(tabIdx: 0, serverData: c0);
      await sim.load(tabIdx: 2, serverData: c2);

      sim.refreshTab(0); // 전체 탭만 무효화
      expect(sim.tabCache.containsKey(0), isFalse, reason: '탭 0 캐시 제거됨');
      expect(sim.tabCache.containsKey(2), isTrue, reason: '탭 2 캐시 유지됨');
    });

    test('B-02: mutation 후 invalidateAll은 모든 탭 캐시 제거', () async {
      final sim = _TabCacheSim();
      await sim.load(tabIdx: 0, serverData: [_makeContract(id: '1')]);
      await sim.load(tabIdx: 2, serverData: [_makeContract(id: '2', status: ContractStatus.pendingWorker)]);
      await sim.load(tabIdx: 3, serverData: [_makeContract(id: '3', status: ContractStatus.completed)]);
      await sim.loadUnsent(serverData: [_makeApp(id: '4')]);

      sim.invalidateAll();

      expect(sim.tabCache.isEmpty, isTrue);
      expect(sim.unsentCache, isNull);
    });

    test('B-03: invalidateAll 후 재로드 시 CF 다시 호출', () async {
      final sim = _TabCacheSim();
      final contracts = [_makeContract(id: '1')];
      await sim.load(tabIdx: 0, serverData: contracts);
      expect(sim.fetchCount, 1);

      sim.invalidateAll();
      await sim.load(tabIdx: 0, serverData: contracts, useCache: true);
      expect(sim.fetchCount, 2, reason: '캐시 무효화 후 재로드는 CF 호출해야 함');
    });

    test('B-04: 미발송 탭 pull-to-refresh는 unsentCache만 제거', () async {
      final sim = _TabCacheSim();
      final apps = [_makeApp(id: '1')];
      await sim.loadUnsent(serverData: apps);
      await sim.load(tabIdx: 0, serverData: [_makeContract(id: '2')]);

      sim.refreshTab(1, isUnsentTab: true); // 미발송 탭 무효화
      expect(sim.unsentCache, isNull);
      expect(sim.tabCache.containsKey(0), isTrue, reason: '탭 0 캐시 유지됨');
    });

    test('B-05: voidContract 후 전체 캐시 무효화 + 재로드 CF 호출 확인', () async {
      final sim = _TabCacheSim();
      await sim.load(tabIdx: 0, serverData: [_makeContract(id: '1')]);
      await sim.load(tabIdx: 2, serverData: [_makeContract(id: '2', status: ContractStatus.pendingWorker)]);

      // void 뮤테이션 시뮬레이션
      sim.invalidateAll();
      // 현재 탭(0) 재로드
      await sim.load(tabIdx: 0, serverData: [], useCache: false);

      expect(sim.fetchCount, 3); // 초기 2번 + 재로드 1번
      expect(sim.tabCache.containsKey(2), isFalse, reason: '탭 2 캐시도 무효화됨');
    });
  });

  // ─── C. _openContract 단건 업데이트 분기 ─────────────────
  group('C. _openContract 단건 업데이트 분기', () {
    late _TabCacheSim sim;
    late List<EmploymentContractModel> contracts;

    setUp(() async {
      sim = _TabCacheSim();
      contracts = [
        _makeContract(id: '1', status: ContractStatus.pendingWorker, workerName: '김철수'),
        _makeContract(id: '2', status: ContractStatus.pendingWorker, workerName: '이영희'),
      ];
      await sim.load(tabIdx: 2, serverData: contracts);
    });

    test('C-01: 상태 미변경 — 인플레이스 교체', () {
      final updated = _makeContract(id: '1', status: ContractStatus.pendingWorker, workerName: '김철수(수정)');
      sim.syncSingleItem(2, '1', updated, ContractStatus.pendingWorker);
      expect(sim.tabCache[2]!.items[0].snapshot.workerName, '김철수(수정)');
      expect(sim.tabCache[2]!.items.length, 2);
    });

    test('C-02: 상태 변경으로 현재 탭 필터 이탈 — 목록에서 제거', () {
      // pending_worker 탭에서 completed로 변경 → 제거
      final updated = _makeContract(id: '1', status: ContractStatus.completed);
      sim.syncSingleItem(2, '1', updated, ContractStatus.pendingWorker);
      expect(sim.tabCache[2]!.items.length, 1);
      expect(sim.tabCache[2]!.items.first.id, '2');
    });

    test('C-03: 전체 탭(currentFilter == null) — 상태 변경돼도 제거 안 함', () {
      final updated = _makeContract(id: '1', status: ContractStatus.completed);
      sim.syncSingleItem(0, '1', updated, null); // 전체 탭: filter == null
      // 탭 0 캐시는 없으므로 아무 변화 없어야 함
      expect(sim.tabCache.containsKey(0), isFalse);
    });

    test('C-04: 계약서가 null(삭제됨) — 목록에서 제거', () {
      sim.syncSingleItem(2, '1', null, ContractStatus.pendingWorker);
      expect(sim.tabCache[2]!.items.length, 1);
      expect(sim.tabCache[2]!.items.first.id, '2');
    });

    test('C-05: 존재하지 않는 contractId — 변화 없음', () {
      final updated = _makeContract(id: 'NONEXISTENT', status: ContractStatus.completed);
      sim.syncSingleItem(2, 'NONEXISTENT', updated, ContractStatus.pendingWorker);
      expect(sim.tabCache[2]!.items.length, 2, reason: '없는 ID면 목록 그대로');
    });
  });

  // ─── D. 미발송 필터 로직 ──────────────────────────────────
  group('D. 미발송 필터 로직 (CF callableGetUnsentApplicationsByBiz 재현)', () {
    final apps = [
      _makeApp(id: '1', name: '계약서없음'),
      _makeApp(id: '2', name: '계약서대기중'),
      _makeApp(id: '3', name: '계약서완료'),
      _makeApp(id: '4', name: 'voided계약'),
      _makeApp(id: '5', name: '빈status'),
    ];

    test('D-01: 계약서 없음(null) → 미발송 포함', () {
      final result = _UnsentFilterSim.filter(
        contractPendingApps: apps,
        contractStatusByAppId: {'1': null},
      );
      expect(result.any((a) => a.id == '1'), isTrue);
    });

    test('D-02: 계약서 pending_worker → 발송됨 제외', () {
      final result = _UnsentFilterSim.filter(
        contractPendingApps: apps,
        contractStatusByAppId: {'2': 'pending_worker'},
      );
      expect(result.any((a) => a.id == '2'), isFalse);
    });

    test('D-03: 계약서 completed → 발송됨 제외', () {
      final result = _UnsentFilterSim.filter(
        contractPendingApps: apps,
        contractStatusByAppId: {'3': 'completed'},
      );
      expect(result.any((a) => a.id == '3'), isFalse);
    });

    test('D-04: 계약서 voided → 미발송 포함 (재발송 필요)', () {
      final result = _UnsentFilterSim.filter(
        contractPendingApps: apps,
        contractStatusByAppId: {'4': 'voided'},
      );
      expect(result.any((a) => a.id == '4'), isTrue);
    });

    test('D-05: status 빈 문자열 → 미발송 포함', () {
      final result = _UnsentFilterSim.filter(
        contractPendingApps: apps,
        contractStatusByAppId: {'5': ''},
      );
      expect(result.any((a) => a.id == '5'), isTrue);
    });

    test('D-06: 혼합 시나리오 — 5건 중 미발송 3건', () {
      final result = _UnsentFilterSim.filter(
        contractPendingApps: apps,
        contractStatusByAppId: {
          '1': null,           // 미발송
          '2': 'pending_worker', // 발송됨
          '3': 'completed',    // 발송됨
          '4': 'voided',       // 미발송 (재발송 필요)
          '5': '',             // 미발송
        },
      );
      expect(result.length, 3);
      expect(result.map((a) => a.id).toSet(), {'1', '4', '5'});
    });

    test('D-07: 모두 발송됨 → 빈 목록', () {
      final result = _UnsentFilterSim.filter(
        contractPendingApps: apps,
        contractStatusByAppId: {
          '1': 'pending_worker',
          '2': 'pending_worker',
          '3': 'completed',
          '4': 'completed',
          '5': 'pending_worker',
        },
      );
      expect(result.isEmpty, isTrue);
    });

    test('D-08: 모두 미발송 → 전체 반환', () {
      final result = _UnsentFilterSim.filter(
        contractPendingApps: apps,
        contractStatusByAppId: {},
      );
      expect(result.length, 5);
    });
  });

  // ─── E. CF 미발송 로직 — 병렬 처리 시뮬레이션 ─────────────
  group('E. CF 병렬 계약서 존재 확인 시뮬레이션', () {
    // CF 내 Promise.all 로직 재현 — 각 applicationId에 대해 독립적으로 계약서 조회
    Future<bool> checkContractExists(
      String appId,
      Map<String, String?> db,
    ) async {
      final status = db[appId];
      if (status == null) return false; // 계약서 없음
      return status != 'voided'; // voided도 "없음"으로 처리
    }

    test('E-01: 10건 병렬 확인 — 독립적 결과', () async {
      final appIds = List.generate(10, (i) => 'app_$i');
      final db = {
        'app_0': null,
        'app_1': 'pending_worker',
        'app_2': 'completed',
        'app_3': 'voided',
        'app_4': null,
        'app_5': 'pending_worker',
        'app_6': null,
        'app_7': 'completed',
        'app_8': 'voided',
        'app_9': null,
      };

      final results = await Future.wait(
        appIds.map((id) => checkContractExists(id, db)),
      );

      // has_active: 1, 2, 5, 7 (4개)
      // no_active: 0, 3, 4, 6, 8, 9 (6개 — 미발송)
      final unsentCount = results.where((r) => !r).length;
      expect(unsentCount, 6);
    });

    test('E-02: 모두 활성 계약서 있음 → 미발송 0건', () async {
      final appIds = ['a1', 'a2', 'a3'];
      final db = {'a1': 'pending_worker', 'a2': 'completed', 'a3': 'pending_worker'};
      final results = await Future.wait(
        appIds.map((id) => checkContractExists(id, db)),
      );
      expect(results.every((r) => r), isTrue);
    });

    test('E-03: 모두 계약서 없음 → 미발송 전체', () async {
      final appIds = ['a1', 'a2', 'a3'];
      final db = <String, String?>{};
      final results = await Future.wait(
        appIds.map((id) => checkContractExists(id, db)),
      );
      expect(results.every((r) => !r), isTrue);
    });
  });

  // ─── F. _loadMore 캐시 누적 로직 ─────────────────────────
  group('F. _loadMore 페이지네이션 후 캐시 누적', () {
    test('F-01: 첫 페이지 로드 → 두 번째 페이지 추가 → 캐시에 전체 반영', () async {
      final sim = _TabCacheSim();
      final page1 = [_makeContract(id: '1'), _makeContract(id: '2')];
      final page2 = [_makeContract(id: '3'), _makeContract(id: '4')];

      // 첫 페이지 로드
      await sim.load(tabIdx: 0, serverData: page1);

      // 페이지네이션 — 기존 items에 page2 추가
      final allItems = [...page1, ...page2];
      sim.updateCacheAfterPagination(0, allItems, 'doc_4', false);

      expect(sim.tabCache[0]!.items.length, 4);
      expect(sim.tabCache[0]!.lastDocId, 'doc_4');
      expect(sim.tabCache[0]!.hasMore, isFalse);
    });

    test('F-02: 재방문 시 페이지네이션 누적 결과 캐시 히트', () async {
      final sim = _TabCacheSim();
      final allItems = List.generate(40, (i) => _makeContract(id: '$i'));
      await sim.load(tabIdx: 0, serverData: allItems.take(20).toList());
      sim.updateCacheAfterPagination(0, allItems, null, false);

      // 다른 탭 방문 후 재방문
      await sim.load(tabIdx: 2, serverData: []);
      final cached = await sim.load(tabIdx: 0, serverData: []);

      expect(cached.length, 40);
      expect(sim.fetchCount, 2, reason: '탭 0 재방문은 캐시 히트');
    });

    test('F-03: hasMore=true 캐시 저장 → 탭 재방문 시 hasMore 복원', () async {
      final sim = _TabCacheSim();
      final page1 = [_makeContract(id: '1'), _makeContract(id: '2')];
      await sim.load(tabIdx: 0, serverData: page1);
      sim.updateCacheAfterPagination(0, page1, 'doc_2', true);

      expect(sim.tabCache[0]!.hasMore, isTrue);
      expect(sim.tabCache[0]!.lastDocId, 'doc_2');
    });
  });

  // ─── G. 탭별 상태 격리 ──────────────────────────────────
  group('G. 탭별 상태 격리', () {
    test('G-01: 탭 0 캐시 무효화가 탭 2·3 캐시에 영향 없음', () async {
      final sim = _TabCacheSim();
      await sim.load(tabIdx: 0, serverData: [_makeContract(id: '1')]);
      await sim.load(tabIdx: 2, serverData: [_makeContract(id: '2', status: ContractStatus.pendingWorker)]);
      await sim.load(tabIdx: 3, serverData: [_makeContract(id: '3', status: ContractStatus.completed)]);

      sim.refreshTab(0); // 탭 0만 무효화

      expect(sim.tabCache.containsKey(0), isFalse);
      expect(sim.tabCache.containsKey(2), isTrue);
      expect(sim.tabCache.containsKey(3), isTrue);
    });

    test('G-02: 미발송 캐시는 계약서 탭 캐시와 완전히 분리', () async {
      final sim = _TabCacheSim();
      await sim.loadUnsent(serverData: [_makeApp(id: '1')]);
      await sim.load(tabIdx: 0, serverData: [_makeContract(id: '2')]);

      sim.refreshTab(0); // 계약서 탭 무효화
      expect(sim.unsentCache, isNotNull, reason: '미발송 캐시 유지됨');

      sim.refreshTab(1, isUnsentTab: true); // 미발송 탭 무효화
      expect(sim.tabCache.containsKey(0), isFalse, reason: '탭 0은 이미 무효화됨');
    });

    test('G-03: 5탭 모두 독립 캐시 — 각각 다른 데이터 저장', () async {
      final sim = _TabCacheSim();
      await sim.loadUnsent(serverData: [_makeApp(id: 'u1')]);
      await sim.load(tabIdx: 0, serverData: [_makeContract(id: 'c0')]);
      await sim.load(tabIdx: 2, serverData: [_makeContract(id: 'c2', status: ContractStatus.pendingWorker)]);
      await sim.load(tabIdx: 3, serverData: [_makeContract(id: 'c3', status: ContractStatus.completed)]);
      await sim.load(tabIdx: 4, serverData: [_makeContract(id: 'c4', status: ContractStatus.voided)]);

      expect(sim.tabCache.length, 4);
      expect(sim.unsentCache!.length, 1);
      expect(sim.tabCache[2]!.items.first.status, ContractStatus.pendingWorker);
      expect(sim.tabCache[3]!.items.first.status, ContractStatus.completed);
      expect(sim.tabCache[4]!.items.first.status, ContractStatus.voided);
    });
  });

  // ─── H. 검색 필터 ─────────────────────────────────────────
  group('H. _filteredItems / _filteredUnsentApps 검색 필터', () {
    final contracts = [
      _makeContract(id: '1', workerName: '김철수'),
      _makeContract(id: '2', workerName: '이영희'),
      _makeContract(id: '3', workerName: '박민준'),
    ];
    final apps = [
      _makeApp(id: '1', name: '김철수', workType: '주방보조'),
      _makeApp(id: '2', name: '이영희', workType: '홀서빙'),
      _makeApp(id: '3', name: '박민준', workType: '주방보조'),
    ];

    test('H-01: 빈 쿼리 → 전체 반환', () {
      expect(_SearchFilterSim.filterContracts(contracts, '').length, 3);
      expect(_SearchFilterSim.filterUnsent(apps, '').length, 3);
    });

    test('H-02: 이름 검색 — 계약서', () {
      final result = _SearchFilterSim.filterContracts(contracts, '김');
      expect(result.length, 1);
      expect(result.first.snapshot.workerName, '김철수');
    });

    test('H-03: 이름 검색 — 미발송 탭', () {
      final result = _SearchFilterSim.filterUnsent(apps, '이영');
      expect(result.length, 1);
      expect(result.first.applicantName, '이영희');
    });

    test('H-04: 업무유형 검색 — 미발송 탭', () {
      final result = _SearchFilterSim.filterUnsent(apps, '주방');
      expect(result.length, 2);
    });

    test('H-05: 대소문자 무관 검색 (한국어는 대소문자 없으므로 소문자 변환 무해)', () {
      final result = _SearchFilterSim.filterContracts(contracts, '철수');
      expect(result.length, 1);
    });

    test('H-06: 매칭 없음 → 빈 목록', () {
      expect(_SearchFilterSim.filterContracts(contracts, 'NONEXISTENT').isEmpty, isTrue);
      expect(_SearchFilterSim.filterUnsent(apps, '없는이름').isEmpty, isTrue);
    });

    test('H-07: 부분 일치 검색 지원', () {
      final result = _SearchFilterSim.filterContracts(contracts, '민');
      expect(result.first.id, '3');
    });
  });

  // ─── I. debounce 타이머 로직 ─────────────────────────────
  group('I. 검색 debounce 로직', () {
    test('I-01: 250ms 내 연속 입력 — 마지막 입력만 적용', () async {
      var applyCount = 0;
      Timer? debounce;

      void simulateInput(String text) {
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 250), () {
          applyCount++;
        });
      }

      simulateInput('ㄱ');
      simulateInput('김');
      simulateInput('김철');
      await Future.delayed(const Duration(milliseconds: 300));

      expect(applyCount, 1, reason: '연속 입력 → 마지막 1회만 적용');
      debounce?.cancel();
    });

    test('I-02: 250ms 초과 간격 입력 — 각각 독립 적용', () async {
      var applyCount = 0;
      Timer? debounce;

      void simulateInput(String text) {
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 250), () {
          applyCount++;
        });
      }

      simulateInput('김');
      await Future.delayed(const Duration(milliseconds: 300));
      simulateInput('이');
      await Future.delayed(const Duration(milliseconds: 300));

      expect(applyCount, 2, reason: '간격이 충분하면 각각 적용');
      debounce?.cancel();
    });

    test('I-03: dispose 전 cancel — 타이머 미실행', () async {
      var applyCount = 0;
      Timer? debounce;

      debounce = Timer(const Duration(milliseconds: 250), () {
        applyCount++;
      });
      debounce.cancel(); // dispose 시뮬레이션

      await Future.delayed(const Duration(milliseconds: 300));
      expect(applyCount, 0, reason: 'cancel 후 타이머 실행 안 됨');
    });
  });

  // ─── J. 엣지케이스 ───────────────────────────────────────
  group('J. 엣지케이스', () {
    test('J-01: 빈 목록 캐시 — 히트 시 빈 목록 반환', () async {
      final sim = _TabCacheSim();
      await sim.load(tabIdx: 0, serverData: []);
      final cached = await sim.load(tabIdx: 0, serverData: [_makeContract(id: 'x')]);
      expect(cached.isEmpty, isTrue, reason: '빈 캐시도 히트 처리 — 서버 데이터 재조회 안 함');
    });

    test('J-02: invalidateAll 후 모든 캐시가 null/empty', () async {
      final sim = _TabCacheSim();
      await sim.load(tabIdx: 0, serverData: [_makeContract(id: '1')]);
      await sim.loadUnsent(serverData: [_makeApp(id: '2')]);
      sim.invalidateAll();
      expect(sim.tabCache.isEmpty, isTrue);
      expect(sim.unsentCache, isNull);
    });

    test('J-03: 탭 인덱스 경계 — 0~4 모두 독립 캐시', () async {
      final sim = _TabCacheSim();
      for (int i = 0; i <= 4; i++) {
        if (i == 1) continue; // 미발송 탭은 별도 처리
        await sim.load(tabIdx: i, serverData: [_makeContract(id: '$i')]);
      }
      expect(sim.tabCache.keys.toSet(), {0, 2, 3, 4});
    });

    test('J-04: 동시성 가드 — fetchInProgress 중 _load 재진입 방지', () async {
      int loadCallCount = 0;
      bool fetchInProgress = false;

      Future<void> guardedLoad() async {
        if (fetchInProgress) return; // 재진입 방지
        fetchInProgress = true;
        loadCallCount++;
        await Future.delayed(const Duration(milliseconds: 10));
        fetchInProgress = false;
      }

      // 동시에 3번 호출
      await Future.wait([guardedLoad(), guardedLoad(), guardedLoad()]);
      expect(loadCallCount, 1, reason: 'fetchInProgress guard로 1번만 실행');
    });

    test('J-05: 미발송 캐시 — sort 순서 유지', () async {
      final sim = _TabCacheSim();
      final apps = [
        _makeApp(id: 'late'),
        _makeApp(id: 'early'),
      ];
      // 이미 workDate 기준 정렬된 상태로 캐시에 저장
      await sim.loadUnsent(serverData: apps);
      final cached = await sim.loadUnsent(serverData: []);
      expect(cached.map((a) => a.id).toList(), ['late', 'early']);
    });

    test('J-06: syncSingleItem — 캐시 없는 탭은 무작동', () {
      final sim = _TabCacheSim();
      // 탭 9에 캐시 없음
      expect(
        () => sim.syncSingleItem(9, 'any', null, null),
        returnsNormally,
      );
    });

    test('J-07: 미발송 defensive copy — 반환값 변경이 캐시에 영향 없음', () async {
      final sim = _TabCacheSim();
      final apps = [_makeApp(id: '1')];
      await sim.loadUnsent(serverData: apps);
      final cached = await sim.loadUnsent(serverData: []);
      cached.add(_makeApp(id: 'INJECTED')); // 반환값 변경
      final cachedAgain = await sim.loadUnsent(serverData: []);
      expect(cachedAgain.length, 1, reason: '캐시 불변성 유지');
    });
  });
}
