// [R7-P1-2 DEVICE.1E] 인력 현황 다이얼로그 — 정원 로드 / 현재좌석 vs 이력 / 끝난 관계의 할 일
//
//   실기기에서 같은 공고 한 장이 이렇게 말했다.
//
//     공고 카드   충원 0 / 필요 2 · 부족 2        (읽었다)
//     인력 현황   지원 0 · 확정 1 · 정원 확인 불가 (못 읽었다 + 확정은 1)
//
//   세 가지가 동시에 틀려 있었다.
//
//     A. 다이얼로그가 정원을 **스스로 지웠다**.
//        `_updateLocalStats` 가 `widget.toItem.workDetails` 만 보고 집계를
//        다시 만드는데, 공고 카드가 넘기는 합성 TOItem 은 그 목록이 비어
//        있다. 빈 map 이 정원 map 을 덮었고, 그 함수는 initState 에서
//        불린다 — 열리자마자 자기 눈을 가린 것이다.
//        게다가 `다시 시도` 는 지원서만 다시 읽었다.
//
//     B. 9/22 에 끝난 관계가 `확정 1명` 으로 서서 `계약서 작성` 을 요구했다.
//        끝난 약속에 새 근로계약을 맺으라는 **없는 할 일**이다.
//
//     C. 약속 기간이 기기 달력으로 그려졌다 — KST 9/16~9/22 가 UTC 기기에서
//        9/15~9/21 로 보였다.
//
//   이 파일은 **실행되는** 판정만 검사한다. 소스 문자열 고정은
//   `_WIRING` 그룹에 따로 모았다 — 둘은 증거의 무게가 다르다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';
import 'package:ALfit/utils/posting_presentation_mode.dart';

// ═══════════════════════════════════════════════════════════════
// fixture — DEV 실측값 그대로 (alfit-89567 / zqaJEjUVPA6O1FWajlTX)
//
//   TO        [R7FIX] 장기 근무 공고, contract, 2026-09-09 ~ 2026-10-23
//   업무      사무업무 06:00~08:00, requiredCount 2, wdId 없음
//   지원서    CANCELED 1건 + CONTRACT_PENDING 1건
//             (workDate 9/9, confirmedAt 9/16 05:00, workEndDate 9/22,
//              renewalDecision TERMINATE, actualResignDate 없음)
// ═══════════════════════════════════════════════════════════════

/// KST 달력일의 실제 instant. 기기 timezone 과 무관하게 같은 순간이다.
DateTime _kst(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min).subtract(const Duration(hours: 9));

final _today = _kst(2026, 9, 27, 12);

const _workType = '사무업무';
const _start = '06:00';
const _end = '08:00';
const _compositeId = '${_workType}_${_start}_$_end';

WorkDetailData _work({int required = 2, String? wdId}) => WorkDetailData(
      workType: _workType,
      startTime: _start,
      endTime: _end,
      requiredCount: required,
      wage: 12000,
      wdId: wdId,
    );

TOModel _to({
  String type = 'contract',
  DateTime? rangeEnd,
  /// `rangeEnd: null` 은 기본값으로 대체되므로 "정말 없음"을 따로 표현한다.
  bool noRangeEnd = false,
  List<WorkDetailData>? workDetails,
  int totalConfirmed = 0,
  int totalPending = 0,
  int totalRequired = 2,
}) =>
    TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: '위워커',
      type: type,
      title: '[R7FIX] 장기 근무 공고',
      creatorUID: 'uid1',
      status: TOStatus.active,
      deadlineType: 'HOURS_BEFORE',
      hoursBeforeStart: 2,
      workDetails: workDetails ?? [_work()],
      totalRequired: totalRequired,
      totalConfirmed: totalConfirmed,
      totalPending: totalPending,
      rangeStart: _kst(2026, 9, 9),
      rangeEnd: noRangeEnd ? null : (rangeEnd ?? _kst(2026, 10, 23)),
      createdAt: _kst(2026, 9, 1),
      statusUpdatedAt: _kst(2026, 9, 1),
    );

ApplicationModel _app({
  required String status,
  DateTime? workEndDate,
  DateTime? actualResignDate,
  DateTime? confirmedAt,
  DateTime? desiredStartDate,
  String type = AppType.longTerm,
}) =>
    ApplicationModel(
      id: 'a1',
      toId: 'to1',
      uid: 'u1',
      businessId: 'biz1',
      businessName: '위워커',
      toTitle: '[R7FIX] 장기 근무 공고',
      status: status,
      applicationType: type,
      selectedWorkType: _workType,
      startTime: _start,
      endTime: _end,
      wage: 12000,
      workDate: _kst(2026, 9, 9),
      confirmedAt: confirmedAt,
      desiredStartDate: desiredStartDate,
      workEndDate: workEndDate,
      actualResignDate: actualResignDate,
      workDays: const ['월', '화', '수', '목', '금', '토', '일'],
      appliedAt: _kst(2026, 9, 15, 9),
    );

/// DEV 의 그 지원서.
ApplicationModel _endedFixture() => _app(
      status: AppStatus.contractPending,
      confirmedAt: _kst(2026, 9, 16, 5),
      workEndDate: _kst(2026, 9, 22),
    );

String _read(String p) => File(p).readAsStringSync();
String _codeOf(String dart) => dart
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  // ══════════════════════════════════════════════════════════════
  // A. 정원 — 모르는 것을 0 이라고 말하지 않는다
  // ══════════════════════════════════════════════════════════════

  group('DLG-A 정원 UNKNOWN != ZERO', () {
    test('DLG-A1 실패 flag 가 생성자로 전달된다', () {
      // 합성 TOItem 이 이 사실을 버리면 다음 소비자가 0 을 진실로 읽는다.
      final item = TOItem(
        to: _to(),
        confirmedCount: 0,
        pendingCount: 0,
        totalRequired: 2,
        // loadTOWorkDetails 는 실패해도 **전부 0 으로 seed 된 map** 을 준다.
        workDetailStats: const {
          _compositeId: {'confirmed': 0, 'pending': 0}
        },
        isWorkDetailLoaded: true,
        workDetailStatsFailed: true,
      );
      expect(item.workDetailStatsFailed, isTrue);
      expect(item.hasLoadedStats, isFalse,
          reason: '실패한 seed 를 로드된 집계로 세지 않는다');
    });

    test('DLG-A2 실패 flag 없이 같은 seed 는 0 으로 읽힌다 — 그래서 전달이 필수다', () {
      final lost = TOItem(
        to: _to(),
        confirmedCount: 0,
        pendingCount: 0,
        totalRequired: 2,
        workDetailStats: const {
          _compositeId: {'confirmed': 0, 'pending': 0}
        },
        isWorkDetailLoaded: true,
        // flag 를 전달하지 못한 과거 상태
      );
      expect(lost.hasLoadedStats, isTrue);
      expect(lost.resolveStats().confirmed, 0,
          reason: '아무도 읽지 못한 0 이 canonical 처럼 보인다 — DLG-A1 이 막는 상태');
    });

    test('DLG-A3 capacity 를 모르면 부족은 null 이다', () {
      final cap = inviteCapacityStateOf(
          canonicalConfirmed: null, requiredCount: 2);
      expect(cap, InviteCapacityState.unknown);
      expect(
          staffingShortageOf(
              capacity: cap, requiredCount: 2, seatedConfirmed: 0),
          isNull,
          reason: '부족 0 으로 말하면 FULL 처럼 읽힌다');
    });

    test('DLG-A4 성공한 0 은 진짜 0 이다', () {
      final cap =
          inviteCapacityStateOf(canonicalConfirmed: 0, requiredCount: 2);
      expect(cap, InviteCapacityState.available);
      expect(
          staffingShortageOf(
              capacity: cap, requiredCount: 2, seatedConfirmed: 0),
          2);
    });

    test('DLG-A5 wdId 없는 업무도 composite 로 찾힌다 (DEV fixture)', () {
      // 이 공고의 workDetails 에는 wdId 가 없다 — canonicalId == composite.
      final w = _work();
      expect(w.canonicalId, _compositeId);
      expect(
          w.lookupByIdentity(const {
            _compositeId: {'confirmed': 0, 'pending': 0}
          }),
          isNotNull);
      expect(w.lookupByIdentity(const <String, Map<String, int>>{}), isNull,
          reason: '빈 map 은 hit 이 아니라 UNKNOWN 이다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // B. 현재 좌석 vs 이력
  // ══════════════════════════════════════════════════════════════

  group('DLG-B 끝난 관계', () {
    test('DLG-B1 DEV fixture 는 오늘 좌석을 차지하지 않는다', () {
      final app = _endedFixture();
      expect(app.occupiesSeatOn(_today), isFalse,
          reason: 'workEndDate 9/22 < 오늘 9/27');
    });

    test('DLG-B2 종료일 당일은 아직 현재 관계다', () {
      expect(_endedFixture().occupiesSeatOn(_kst(2026, 9, 22, 23)), isTrue);
    });

    test('DLG-B3 미래 종료 예정은 현재 관계로 남는다', () {
      final future = _app(
          status: AppStatus.contractPending,
          confirmedAt: _kst(2026, 9, 16, 5),
          workEndDate: _kst(2026, 10, 5));
      expect(future.occupiesSeatOn(_today), isTrue,
          reason: '종료가 예정됐다고 지금 자리를 비우는 것이 아니다');
    });

    test('DLG-B4 종료일을 모르면 좌석을 빼앗지 않는다', () {
      final unknownEnd =
          _app(status: AppStatus.confirmed, confirmedAt: _kst(2026, 9, 16, 5));
      expect(unknownEnd.occupiesSeatOn(_today), isTrue,
          reason: '모르는 것을 근거로 부족을 부풀리지 않는다');
    });

    test('DLG-B5 단기는 날짜 축이 없다 — 기존 판정 그대로', () {
      final short = _app(
          status: AppStatus.confirmed,
          type: AppType.shortTerm,
          workEndDate: _kst(2026, 9, 22));
      expect(short.occupiesSeatOn(_today), isTrue);
    });

    test('DLG-B6 현재 확정 0 · 이력 1 이 동시에 참이다', () {
      // 다이얼로그가 섹션을 나누는 바로 그 술어를 그대로 실행한다.
      final rows = [
        _endedFixture(),
        _app(status: AppStatus.canceled, workEndDate: _kst(2026, 10, 23)),
      ];
      final confirmedLike = rows
          .where((a) => AppStatus.confirmedStatuses.contains(a.status))
          .toList();
      final current =
          confirmedLike.where((a) => a.occupiesSeatOn(_today)).toList();
      final ended =
          confirmedLike.where((a) => !a.occupiesSeatOn(_today)).toList();

      expect(confirmedLike.length, 1, reason: 'CANCELED 는 확정 모집단이 아니다');
      expect(current.length, 0, reason: '현재 좌석 0');
      expect(ended.length, 1, reason: '이력 1 — 사람을 지우지 않는다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // C. 약속 기간은 KST 달력이다
  // ══════════════════════════════════════════════════════════════

  group('DLG-C 날짜', () {
    test('DLG-C1 DEV fixture 의 약속 기간 = 9/16~9/22', () {
      // 기기가 UTC 든 KST 든 같은 문자열이어야 한다.
      //   workDate 9/9 < confirmedAt 9/16 → 실제 근무 시작은 9/16
      //   종료일 9/22 (기기 달력으로 읽으면 9/21 로 밀렸다)
      expect(_endedFixture().workPeriodDisplay, '9/16~9/22');
    });

    test('DLG-C2 desiredStartDate 가 있으면 그것이 시작이다', () {
      final a = _app(
        status: AppStatus.contractPending,
        confirmedAt: _kst(2026, 9, 16, 5),
        desiredStartDate: _kst(2026, 9, 20),
        workEndDate: _kst(2026, 9, 22),
      );
      expect(a.workPeriodDisplay, '9/20~9/22',
          reason: 'confirmedAt 보정은 desiredStartDate 가 없을 때만이다');
    });

    test('DLG-C3 actualResignDate 가 workEndDate 를 이긴다', () {
      final a = _app(
        status: AppStatus.confirmed,
        confirmedAt: _kst(2026, 9, 16, 5),
        workEndDate: _kst(2026, 9, 22),
        actualResignDate: _kst(2026, 9, 19),
      );
      expect(a.workPeriodDisplay, '9/16~9/19');
    });

    test('DLG-C4 KST 자정 직전/직후가 같은 날을 말한다', () {
      // KST 9/22 23:59 는 UTC 로 9/22 14:59 — 기기 성분을 읽으면 갈렸다.
      final a = _app(
        status: AppStatus.confirmed,
        confirmedAt: _kst(2026, 9, 16, 5),
        workEndDate: _kst(2026, 9, 22, 23, 59),
      );
      expect(a.workPeriodDisplay, endsWith('~9/22'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // D. 운영 종료일 source — FLEX != CONTRACT (§9)
  // ══════════════════════════════════════════════════════════════

  group('DLG-D operationEndDate', () {
    TOItem slot(TOModel master, DateTime date) => TOItem(
          to: master,
          slot: SlotModel(
            id: 'slot_${date.month}_${date.day}',
            toId: master.id,
            date: date,
            status: 'OPEN',
            createdAt: _kst(2026, 9, 1),
          ),
          confirmedCount: 0,
          pendingCount: 0,
          totalRequired: 2,
        );

    test('DLG-D1 CONTRACT 는 rangeEnd 다', () {
      final g = TOGroupItem(singleTO: _to(rangeEnd: _kst(2026, 10, 23)));
      expect(g.operationEndDate, _kst(2026, 10, 23));
    });

    test('DLG-D2 FLEX 는 마지막 슬롯 날짜다 — master rangeEnd 가 아니다', () {
      final master = _to(type: 'flex', rangeEnd: _kst(2026, 9, 1));
      final g = TOGroupItem(singleTO: master);
      g.setGroupTOs([
        slot(master, _kst(2026, 10, 2)),
        slot(master, _kst(2026, 10, 9)),
      ]);
      expect(g.operationEndDate, _kst(2026, 10, 9),
          reason: 'FLEX 의 rangeEnd 는 슬롯 추가·삭제에서 갱신되지 않는다(drift)');
    });

    test('DLG-D3 FLEX 슬롯 미로드 → null (끝났다고 단정하지 않는다)', () {
      final g = TOGroupItem(
          singleTO: _to(type: 'flex', rangeEnd: _kst(2026, 9, 1)));
      expect(g.operationEndDate, isNull);
      expect(
          resolvePostingPresentationMode(
              operationEnd: g.operationEndDate,
              recruitmentClosed: false,
              now: _today),
          isNot(PostingPresentationMode.pastEnded),
          reason: '모르는 것으로 PAST_ENDED 를 만들어 내지 않는다');
    });

    test('DLG-D4 FLEX slotDates 만 있어도 쓴다', () {
      final g = TOGroupItem(singleTO: _to(type: 'flex'));
      g.setSlotDates([_kst(2026, 9, 12), _kst(2026, 9, 30)]);
      expect(g.operationEndDate, _kst(2026, 9, 30));
    });

    test('DLG-D5 생성일로 폴백하지 않는다', () {
      final g = TOGroupItem(singleTO: _to(noRangeEnd: true));
      // rangeEnd 가 없는 CONTRACT — endDate 는 createdAt 으로 떨어지지만
      // operationEndDate 는 모른다고 말해야 한다.
      expect(g.endDate, _kst(2026, 9, 1));
      expect(g.operationEndDate, isNull);
    });

    test('DLG-D6 DEV fixture 는 오늘 ACTIVE 다', () {
      final g = TOGroupItem(singleTO: _to(rangeEnd: _kst(2026, 10, 23)));
      expect(
          resolvePostingPresentationMode(
              operationEnd: g.operationEndDate,
              recruitmentClosed: false,
              now: _today),
          PostingPresentationMode.active,
          reason: '근로자 한 명이 9/22 에 끝나도 공고는 10/23 까지 운영한다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // E. 요약 집계 — 카드와 다이얼로그가 같은 모집단을 본다
  // ══════════════════════════════════════════════════════════════

  group('DLG-E 집계', () {
    test('DLG-E1 마스터 TO 폴백으로 같은 집계를 본다 (DEVICE.1D 유지)', () {
      final item = TOItem(
        to: _to(),
        confirmedCount: 9, // 낡은 카운터
        pendingCount: 9,
        totalRequired: 2,
        workDetailStats: const {
          _compositeId: {'confirmed': 0, 'pending': 0}
        },
        isWorkDetailLoaded: true,
      );
      final s = item.resolveStats();
      expect((s.confirmed, s.pending, s.required, s.shortage), (0, 0, 2, 2),
          reason: '집계가 있으면 카운터를 쓰지 않는다');
    });

    test('DLG-E2 실패면 카운터로 돌아간다', () {
      final item = TOItem(
        to: _to(),
        confirmedCount: 1,
        pendingCount: 0,
        totalRequired: 2,
        workDetailStats: const {
          _compositeId: {'confirmed': 0, 'pending': 0}
        },
        isWorkDetailLoaded: true,
        workDetailStatsFailed: true,
      );
      expect(item.resolveStats().confirmed, 1);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // _WIRING — 소스 고정. 위 실행 테스트보다 약한 증거다.
  // ══════════════════════════════════════════════════════════════

  group('DLG-W wiring (source)', () {
    late String dlg, card;

    setUpAll(() {
      dlg = _codeOf(_read(
          'lib/screens/business_admin/dialogs/work_applicants_dialog.dart'));
      card = _codeOf(_read('lib/widgets/admin/cards/admin_to_group_card.dart'));
    });

    test('DLG-W1 다이얼로그가 정원을 직접 읽는다', () {
      // [DEVICE.1E.1] 상태기계가 `CapacityLoadState` 로 분리됐다 —
      //   실패→재시도·순서 역전·dispose 를 실행으로 증명하기 위해서다.
      //   계약은 그대로: 부모 snapshot 이 아니라 자기 상태를 본다.
      expect(dlg, contains('Future<void> _loadCapacity()'));
      expect(dlg, contains('_firestoreService.loadTOWorkDetails('),
          reason: '새 API 를 만들지 않는다 — 카드와 같은 경로');
      expect(dlg, contains('CapacityLoadState('));
      expect(dlg, contains('_capacity.confirmedFor(widget.work)'),
          reason: '정원은 그 상태기계가 답한다');
      expect(dlg, isNot(contains('widget.toItem.workDetailStatsFailed) return null')),
          reason: '부모 flag 를 직접 읽지 않는다');
    });

    test('DLG-W2 다시 시도가 정원을 다시 읽는다', () {
      // 예전에는 `_loadApplicants` 를 불러 배너가 사라질 수 없었다.
      final notice = dlg.substring(
          dlg.indexOf('Widget _buildCapacityUnknownNotice('),
          dlg.indexOf('Future<void> _openInviteMethod('));
      expect(notice, contains('onPressed: _loadCapacity'));
      expect(notice, isNot(contains('onPressed: _isProcessing ? null : _loadApplicants')));
    });

    test('DLG-W3 정원과 사람 목록의 로드 상태가 분리돼 있다', () {
      // 정원 상태는 `CapacityLoadState` 가, 사람 목록 상태는 화면이 갖는다.
      final cls = _codeOf(_read('lib/models/ui/capacity_load_state.dart'));
      expect(cls, contains('bool _failed'));
      expect(cls, contains('int _seq'), reason: '늦게 온 응답이 새 상태를 덮지 않는다');
      expect(cls, contains('if (_disposed) return;'));
      expect(dlg, contains('bool _loadFailed'), reason: '사람 목록 상태는 그대로다');
      expect(dlg, contains('_capacity.dispose()'));
      expect(dlg, contains('_capacity.clearOnRevocation()'),
          reason: '권한 회수가 확인되면 읽어 둔 정원도 남기지 않는다');
    });

    test('DLG-W4 로컬 재집계가 아는 값을 빈 map 으로 덮지 않는다', () {
      expect(dlg, contains('if (newStats.isNotEmpty)'));
      expect(dlg, contains('widget.toItem.to.workDetails'),
          reason: '합성 TOItem 의 빈 workDetails 를 폴백한다');
    });

    test('DLG-W5 로컬 재집계가 섹션 분류와 **같은 함수**를 쓴다', () {
      // [DEVICE.1E.1] 좌석 규칙을 두 번 쓰지 않는다 — 한쪽만 고치면 갈린다.
      expect(dlg, contains('staffingRelationOf(a, seatDay).isCurrentStaffing'));
      expect(dlg,
          contains('staffingRelationOf(app, seatDay).isCurrentStaffing'),
          reason: '폴백 경로도 같은 함수를 쓴다');
      expect(dlg, isNot(contains('!a.isStaffingReleased && a.occupiesSeatOn')),
          reason: '조건문 복제를 남기지 않는다');
    });

    test('DLG-W6b mutation 뒤 canonical 재조회가 이어진다', () {
      expect(dlg, contains('Future.microtask(_loadCapacity)'),
          reason: '로컬 값이 영구히 권위를 갖지 않는다');
      expect(dlg, contains('_capacity.applyLocal('));
    });

    test('DLG-W6c 최초 로드에서는 로컬 집계를 정원으로 쓰지 않는다 (§3)', () {
      // `_allApplications` 는 페이징되는 callable 결과다 — 부분집합일 수
      //   있으므로 전체 자리 수의 근거가 될 수 없다. 그리고 initState 가
      //   이미 canonical 조회를 시작했으므로, 여기서 applyLocal 하면 그
      //   응답을 폐기해 버린다(그 경로에는 후속 재조회가 없다).
      expect(dlg, contains('final applyToCapacity = markChanged;'));
      expect(dlg, contains('if (applyToCapacity) _capacity.applyLocal('));
      // 최초 호출은 markChanged: false 다.
      expect(dlg, contains('_updateLocalStats(markChanged: false)'));
    });

    test('DLG-W9 좌석 아님과 계약 종료를 구분한다 (§4)', () {
      expect(dlg, contains('staffingRelationOf(app, DateTime.now()).resolvedEnded'),
          reason: '만료+미결정을 종료로 단정하지 않는다');
      expect(dlg, contains("'계약 확인 필요'"), reason: '결정이 남은 섹션');
      expect(dlg, contains("'좌석 반납'"), reason: '자리 해제 != 관계 종료');
      expect(dlg, contains('staffingRelationLabel(app, DateTime.now())'),
          reason: '라벨도 canonical 조합이 정한다');
    });

    test('DLG-W10 끝난 관계의 신분증 요구형 강조만 내린다 (§5)', () {
      // 기록(제출·승인)은 남기고 요구형(none/expired/rejected)만 감춘다.
      expect(dlg, contains('IdCardHelper.isRequestable(idCardStatus))'));
      expect(dlg, contains('if (!(_isEndedRelation(app) &&'));
      // 공용 helper 를 전역으로 바꾸지 않았다.
      final helper = _codeOf(_read('lib/utils/id_card_helper.dart'));
      expect(helper, contains("status == 'none' || status == 'expired'"),
          reason: 'active worker 용 판정은 그대로다');
    });

    test('DLG-W11 장기 부족에 다음 경로를 말한다 (§6)', () {
      expect(dlg, contains('_buildLongTermShortageRoute('));
      expect(dlg, contains('인력 초대'), reason: '기존 canonical 경로를 가리킨다');
      // 새 초대 CTA 를 이 화면에 만들지 않았다.
      final route = dlg.substring(
          dlg.indexOf('Widget _buildLongTermShortageRoute('),
          dlg.indexOf('Widget _buildCapacityUnknownNotice('));
      expect(route, isNot(contains('onPressed')),
          reason: '안내다 — 여기서 초대를 열면 약속 범위를 이 화면이 정하게 된다');
    });

    test('DLG-W6 합성 TOItem 이 실패 flag 를 싣는다', () {
      expect(card, contains('workDetailStatsFailed: _singleTOStatsFailed()'));
    });

    test('DLG-W7 끝난 관계에 계약 작성·신분증 요청을 붙이지 않는다', () {
      expect(dlg, contains('!_isEndedRelation(app) &&'),
          reason: '계약서 작성 CTA 게이트');
      // 줄바꿈을 가로질러 매칭하지 않는다 — 이 저장소는 CRLF 다.
      expect(dlg, contains("'계약 종료', _ended.length"),
          reason: '끝난 관계는 이력 섹션으로 남는다 — 목록에서 지우지 않는다');
      expect(dlg, isNot(contains('_applicants.removeWhere')));
    });

    test('DLG-W8 운영 종료일 source 가 canonical 이다', () {
      expect(card, contains('operationEnd: widget.groupItem.operationEndDate'));
      expect(card, isNot(contains('operationEnd: widget.groupItem.masterTO.rangeEnd')));
    });
  });
}
