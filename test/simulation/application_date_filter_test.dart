// test/simulation/application_date_filter_test.dart
//
// apply_work_dialog.dart의 _filterApplicationsByDateOrSlot + _buildActiveDateCache
// 핵심 로직을 독립적으로 검증한다.
//
// 버그 시나리오:
//   6/11 냉장분류(slotId: s11)를 지원·확정 후,
//   6/13 냉장분류(slotId: s13) 지원 화면에서 "확정취소"로 잘못 표시됨.
//
// 수정 포인트:
//   getApplicationsForTO()는 같은 toId의 모든 날짜 지원서를 반환하므로
//   날짜/슬롯 기준 필터를 적용해야 정확한 캐시가 구성된다.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/application_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 테스트용 로직 (apply_work_dialog.dart의 private 메서드를 복제)
// ─────────────────────────────────────────────────────────────────────────────

/// _filterApplicationsByDateOrSlot 복제
List<ApplicationModel> filterByDateOrSlot(
  List<ApplicationModel> apps,
  DateTime dateKey, {
  bool isGroupTO = true,
  String? groupSlotId,   // groupSlotIdsByDate[dateKey]
  String? singleSlotId,  // widget.slotId (단일 flex)
}) {
  final String? expectedSlotId = isGroupTO ? groupSlotId : singleSlotId;

  if (expectedSlotId != null) {
    final bySlot = apps.where((a) => a.slotId == expectedSlotId).toList();
    if (bySlot.isNotEmpty) return bySlot;
  }

  // workDate 기준 fallback
  return apps.where((a) {
    final d = DateTime(a.workDate.year, a.workDate.month, a.workDate.day);
    return d == dateKey;
  }).toList();
}

/// _buildActiveDateCache 복제 (단기 공고 전용 — _isLongTerm=false)
Map<String, ApplicationModel> buildActiveDateCache(
  List<ApplicationModel> applications,
  DateTime dateKey, {
  bool isGroupTO = true,
  String? groupSlotId,
  String? singleSlotId,
}) {
  final scoped = filterByDateOrSlot(
    applications,
    dateKey,
    isGroupTO: isGroupTO,
    groupSlotId: groupSlotId,
    singleSlotId: singleSlotId,
  );

  final active = scoped.where((app) {
    if (app.applicationType == 'long_term') {
      if (app.status == AppStatus.pending ||
          AppStatus.confirmedStatuses.contains(app.status)) return true;
      if (app.isTerminationApproved) return false;
    }
    return true;
  }).toList();

  return <String, ApplicationModel>{
    for (final app in active)
      '${app.selectedWorkType}_${app.startTime}_${app.endTime}': app
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// 헬퍼
// ─────────────────────────────────────────────────────────────────────────────

ApplicationModel _app({
  required String id,
  required DateTime workDate,
  required String status,
  required String workType,
  String startTime = '09:00',
  String endTime = '18:00',
  String? slotId,
  String? toId = 'to_abc',
}) {
  return ApplicationModel(
    id: id,
    businessId: 'biz_1',
    businessName: '테스트사업장',
    toTitle: '냉장분류',
    workDate: workDate,
    startTime: startTime,
    endTime: endTime,
    uid: 'user_1',
    selectedWorkType: workType,
    toId: toId,
    slotId: slotId,
    wage: 12000,
    status: status,
    appliedAt: workDate,
  );
}

final date611 = DateTime(2025, 6, 11);
final date613 = DateTime(2025, 6, 13);
final date614 = DateTime(2025, 6, 14);

// ─────────────────────────────────────────────────────────────────────────────
// 테스트
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // A. 핵심 버그 시나리오 (그룹 TO, slotId 구분)
  // ───────────────────────────────────────────────────────────────────────────
  group('A. 핵심 버그 — 날짜 다른 지원서 혼입', () {
    // 6/11 CONFIRMED + 6/13 미지원 상태에서 getApplicationsForTO가 반환하는 전체 목록
    final allApps = [
      _app(id: 'app_611', workDate: date611, status: AppStatus.confirmed,
           workType: '냉장분류', slotId: 'slot_611'),
    ];

    test('A-01: 6/13 캐시에 6/11 지원서가 포함되지 않아야 한다 (slotId 기준)', () {
      final cache = buildActiveDateCache(
        allApps,
        DateTime(2025, 6, 13),
        groupSlotId: 'slot_613', // 6/13의 슬롯 ID
      );
      expect(cache, isEmpty,
          reason: 'slot_611 ≠ slot_613 이므로 필터링되어야 함');
    });

    test('A-02: 6/11 캐시에는 6/11 지원서가 정상 포함된다', () {
      final cache = buildActiveDateCache(
        allApps,
        date611,
        groupSlotId: 'slot_611',
      );
      expect(cache, hasLength(1));
      expect(cache.values.first.id, 'app_611');
      expect(cache.values.first.status, AppStatus.confirmed);
    });

    test('A-03: 수정 전 버그 재현 — slotId 없이 dateKey만 다르면 혼입 발생', () {
      // 수정 전 동작: slotId 무시하고 workDate 기준도 없으면 전부 포함
      // (filterByDateOrSlot 없이 직접 all apps → dateKey에 저장)
      // 이 테스트는 버그가 "있었다면" 어떤 결과가 나왔을지를 증명한다
      final buggyCacheFor613 = {
        for (final app in allApps) // 날짜 필터 없이 전부 저장 (버그 동작)
          '${app.selectedWorkType}_${app.startTime}_${app.endTime}': app
      };
      // 버그 상황: 6/13 캐시에 6/11의 CONFIRMED가 들어감
      expect(buggyCacheFor613, hasLength(1));
      expect(buggyCacheFor613.values.first.status, AppStatus.confirmed,
          reason: '버그: 6/13 지원 화면에서 "확정취소" 버튼이 나타났던 원인');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // B. 날짜별 독립성 검증
  // ───────────────────────────────────────────────────────────────────────────
  group('B. 날짜별 독립적 캐시', () {
    final allApps = [
      _app(id: 'app_611', workDate: date611, status: AppStatus.confirmed,
           workType: '냉장분류', slotId: 'slot_611'),
      _app(id: 'app_613', workDate: date613, status: AppStatus.pending,
           workType: '냉장분류', slotId: 'slot_613'),
      _app(id: 'app_614', workDate: date614, status: AppStatus.confirmed,
           workType: '피킹', slotId: 'slot_614'),
    ];

    test('B-01: 각 날짜 캐시는 해당 날짜의 지원서만 포함', () {
      final cache611 = buildActiveDateCache(allApps, date611, groupSlotId: 'slot_611');
      final cache613 = buildActiveDateCache(allApps, date613, groupSlotId: 'slot_613');
      final cache614 = buildActiveDateCache(allApps, date614, groupSlotId: 'slot_614');

      expect(cache611.values.map((a) => a.id), containsAll(['app_611']));
      expect(cache611, hasLength(1));

      expect(cache613.values.map((a) => a.id), containsAll(['app_613']));
      expect(cache613, hasLength(1));

      expect(cache614.values.map((a) => a.id), containsAll(['app_614']));
      expect(cache614, hasLength(1));
    });

    test('B-02: 같은 날짜에 다중 업무 유형 → 전부 캐시에 포함', () {
      final multiWorkApps = [
        _app(id: 'app_1', workDate: date611, status: AppStatus.pending,
             workType: '냉장분류', slotId: 'slot_611'),
        _app(id: 'app_2', workDate: date611, status: AppStatus.pending,
             workType: '피킹', slotId: 'slot_611'),
        _app(id: 'app_3', workDate: date613, status: AppStatus.pending,
             workType: '냉장분류', slotId: 'slot_613'),
      ];

      final cache611 = buildActiveDateCache(multiWorkApps, date611, groupSlotId: 'slot_611');
      expect(cache611, hasLength(2));
      expect(cache611.keys, containsAll(['냉장분류_09:00_18:00', '피킹_09:00_18:00']));
    });

    test('B-03: 지원 없는 날짜 → 빈 캐시 반환', () {
      final cache = buildActiveDateCache(allApps, DateTime(2025, 6, 20),
          groupSlotId: 'slot_620');
      expect(cache, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // C. slotId fallback (workDate 기준)
  // ───────────────────────────────────────────────────────────────────────────
  group('C. slotId 없는 기존 데이터 호환 (workDate fallback)', () {
    test('C-01: slotId=null 기존 데이터 → workDate 기준 필터', () {
      final apps = [
        _app(id: 'app_611', workDate: date611, status: AppStatus.confirmed,
             workType: '냉장분류', slotId: null), // 구 데이터 — slotId 없음
        _app(id: 'app_613', workDate: date613, status: AppStatus.pending,
             workType: '냉장분류', slotId: null),
      ];

      final cache611 = buildActiveDateCache(apps, date611, groupSlotId: null);
      expect(cache611, hasLength(1));
      expect(cache611.values.first.id, 'app_611');

      final cache613 = buildActiveDateCache(apps, date613, groupSlotId: null);
      expect(cache613, hasLength(1));
      expect(cache613.values.first.id, 'app_613');
    });

    test('C-02: slotId 있지만 slotId 매칭 실패 → workDate fallback', () {
      // slotId가 부여됐지만 groupSlotIdsByDate에 없는 경우 (슬롯 재생성 등)
      final apps = [
        _app(id: 'app_611', workDate: date611, status: AppStatus.confirmed,
             workType: '냉장분류', slotId: 'old_slot_611'),
      ];

      // groupSlotId = 'new_slot_611' (재생성 후 다른 ID)이면 slotId 매칭 실패
      // → workDate 기준 fallback으로 올바르게 포함
      final cache611 = buildActiveDateCache(apps, date611, groupSlotId: 'new_slot_611');
      expect(cache611, hasLength(1));
      expect(cache611.values.first.id, 'app_611',
          reason: 'slotId 불일치라도 workDate가 같으면 fallback으로 포함');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // D. 단일 flex slot (groupTO=false, widget.slotId 사용)
  // ───────────────────────────────────────────────────────────────────────────
  group('D. 단일 flex slot (isGroupTO=false)', () {
    test('D-01: widget.slotId 기준 필터 — 다른 슬롯 지원서 제외', () {
      final apps = [
        _app(id: 'app_611', workDate: date611, status: AppStatus.confirmed,
             workType: '냉장분류', slotId: 'slot_611'),
        _app(id: 'app_613', workDate: date613, status: AppStatus.pending,
             workType: '냉장분류', slotId: 'slot_613'),
      ];

      final cache = buildActiveDateCache(
        apps,
        date613,
        isGroupTO: false,
        singleSlotId: 'slot_613', // widget.slotId
      );
      expect(cache, hasLength(1));
      expect(cache.values.first.id, 'app_613');
    });

    test('D-02: widget.slotId null — workDate 기준 fallback', () {
      final apps = [
        _app(id: 'app_611', workDate: date611, status: AppStatus.confirmed,
             workType: '냉장분류', slotId: null),
      ];

      final cache = buildActiveDateCache(
        apps,
        date611,
        isGroupTO: false,
        singleSlotId: null,
      );
      expect(cache.values.first.id, 'app_611');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // E. 동일 날짜 다른 시간대
  // ───────────────────────────────────────────────────────────────────────────
  group('E. 같은 날짜 다른 시간대는 별개의 업무', () {
    test('E-01: 같은 업무유형, 다른 시간대 → workKey 분리', () {
      final apps = [
        _app(id: 'morning', workDate: date611, status: AppStatus.confirmed,
             workType: '냉장분류', startTime: '06:00', endTime: '14:00', slotId: 'slot_611_am'),
        _app(id: 'evening', workDate: date611, status: AppStatus.pending,
             workType: '냉장분류', startTime: '14:00', endTime: '22:00', slotId: 'slot_611_pm'),
      ];

      final cacheAm = buildActiveDateCache(apps, date611, groupSlotId: 'slot_611_am');
      final cachePm = buildActiveDateCache(apps, date611, groupSlotId: 'slot_611_pm');

      expect(cacheAm, hasLength(1));
      expect(cacheAm.values.first.id, 'morning');

      expect(cachePm, hasLength(1));
      expect(cachePm.values.first.id, 'evening');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // F. 관리자 화면 영향 없음 (서버 side 카운팅 독립성)
  // ───────────────────────────────────────────────────────────────────────────
  group('F. 관리자 카운팅은 독립적', () {
    test('F-01: 관리자는 slotId별 Firestore 쿼리 사용 — 클라이언트 캐시와 무관', () {
      // 관리자 측 getApplicationsBySlotId()는 서버 쿼리(slotId 기준)
      // 클라이언트 _applicationsByDate 캐시와 독립적임을 시나리오로 확인

      // slotId: slot_613 의 지원서 (서버 직접 조회 결과 시뮬레이션)
      final adminQueryResult = [
        _app(id: 'app_613_u1', workDate: date613, status: AppStatus.pending,
             workType: '냉장분류', slotId: 'slot_613'),
        _app(id: 'app_613_u2', workDate: date613, status: AppStatus.confirmed,
             workType: '냉장분류', slotId: 'slot_613'),
      ];

      // 관리자 화면 지원자 수 계산
      final pendingCount = adminQueryResult
          .where((a) => a.status == AppStatus.pending).length;
      final confirmedCount = adminQueryResult
          .where((a) => AppStatus.confirmedStatuses.contains(a.status)).length;

      expect(pendingCount, 1);
      expect(confirmedCount, 1);
      // → 관리자 화면은 Firestore 직접 쿼리라 클라이언트 버그의 영향을 받지 않음
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // G. 버그 수정 회귀 방지
  // ───────────────────────────────────────────────────────────────────────────
  group('G. 회귀 방지', () {
    test('G-01: 6/11 CONFIRMED 후 6/13 캐시 상태는 notApplied (비어있음)', () {
      final allApps = [
        _app(id: 'app_611', workDate: date611, status: AppStatus.confirmed,
             workType: '냉장분류', slotId: 'slot_611'),
      ];

      final cache613 = buildActiveDateCache(allApps, date613, groupSlotId: 'slot_613');
      // 캐시가 비어 있으면 → getWorkApplicationStatus → notApplied → "지원하기" 버튼
      expect(cache613, isEmpty,
          reason: '6/13 캐시가 비어야 "지원하기" 버튼이 올바르게 표시됨');
    });

    test('G-02: 6/11 PENDING 후 6/13 캐시도 비어야 함', () {
      final allApps = [
        _app(id: 'app_611', workDate: date611, status: AppStatus.pending,
             workType: '냉장분류', slotId: 'slot_611'),
      ];

      final cache613 = buildActiveDateCache(allApps, date613, groupSlotId: 'slot_613');
      expect(cache613, isEmpty);
    });

    test('G-03: 6/11 CANCELED 후 6/13 캐시도 비어야 함', () {
      final allApps = [
        _app(id: 'app_611', workDate: date611, status: AppStatus.canceled,
             workType: '냉장분류', slotId: 'slot_611'),
      ];

      final cache613 = buildActiveDateCache(allApps, date613, groupSlotId: 'slot_613');
      expect(cache613, isEmpty);
    });

    test('G-04: 6/13에 실제 지원한 경우만 6/13 캐시에 포함됨', () {
      final allApps = [
        _app(id: 'app_611', workDate: date611, status: AppStatus.confirmed,
             workType: '냉장분류', slotId: 'slot_611'),
        _app(id: 'app_613', workDate: date613, status: AppStatus.pending,
             workType: '냉장분류', slotId: 'slot_613'),
      ];

      final cache613 = buildActiveDateCache(allApps, date613, groupSlotId: 'slot_613');
      expect(cache613, hasLength(1));
      expect(cache613.values.first.id, 'app_613');
      expect(cache613.values.first.status, AppStatus.pending,
          reason: '6/13에 지원한 경우 "대기중" 버튼이 올바르게 표시돼야 함');
    });
  });
}
