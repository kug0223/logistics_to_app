// [POSTING-V2-03Q.1] 근무 날짜 중심 공고 정렬
//
// 03Q READ에서 확인된 것:
//   · 진행중 탭의 유일한 정렬 키가 createdAt DESC였다. 문서를 만든 시각은
//     FLEX에서 근무일과 아무 상관관계가 없다 — 한 달 치를 미리 만든 공고와
//     전날 급히 만든 공고의 순서가 뒤집혔다.
//   · 방금 만든 미공개 DRAFT가 항상 목록 최상단을 차지했다.
//   · FLEX의 rangeStart/rangeEnd는 생성 시점에 한 번 기록되고 슬롯 추가·삭제에서
//     갱신되지 않는다(drift). 정렬 키로 쓸 수 없다.
//   · 키가 하나뿐이라 동일 createdAt에서 rebuild마다 순서가 흔들릴 수 있었다.
//
// shortage/pending/confirmed는 의도적으로 정렬에 넣지 않는다 — 카드의 미충원
// (required-confirmed-pending)과 Home canonical shortage(per-wdId 합산, pending
// 제외)의 의미가 다르고, 이번 Phase는 어느 쪽이 canonical인지 정하지 않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/controllers/workforce_controller.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';

// ═══════════════════════════════════════════════════════════════
// fixture
// ═══════════════════════════════════════════════════════════════

/// 기준 시각: 2025-09-14 10:00 (KST 계산용 — toKstDate가 정규화한다)
final _now = DateTime.utc(2025, 9, 14, 1, 0); // KST 09-14 10:00
DateTime _day(int month, int dayOfMonth) =>
    DateTime.utc(2025, month, dayOfMonth);

TOModel _to({
  required String id,
  String type = 'flex',
  String status = TOStatus.active,
  DateTime? createdAt,
  DateTime? rangeStart,
  DateTime? rangeEnd,
  bool isPublished = true,
  String publishMode = 'immediate',
  DateTime? publishAt,
}) {
  return TOModel(
    id: id,
    businessId: 'biz1',
    businessName: '테스트 사업장',
    type: type,
    title: '공고 $id',
    creatorUID: 'uid1',
    status: status,
    deadlineType: 'HOURS_BEFORE',
    hoursBeforeStart: 2,
    workDetails: const [],
    totalRequired: 10,
    totalConfirmed: 0,
    totalPending: 0,
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
    isPublished: isPublished,
    publishMode: publishMode,
    publishAt: publishAt,
    createdAt: createdAt ?? DateTime.utc(2025, 1, 1),
    statusUpdatedAt: DateTime.utc(2025, 1, 1),
  );
}

/// 열린 슬롯 하나를 감싼 TOItem. 정원 여유가 있어 CloseStateUtils가 open으로 본다.
TOItem _slot(
  TOModel master,
  DateTime date, {
  String? closedBy,
  int confirmed = 0,
  int required = 2,
  String slotStatus = 'OPEN',
}) {
  return TOItem(
    to: master,
    slot: SlotModel(
      id: 'slot_${date.month}_${date.day}',
      toId: master.id,
      date: date,
      status: slotStatus,
      closedBy: closedBy,
      createdAt: DateTime.utc(2025, 1, 1),
    ),
    confirmedCount: confirmed,
    pendingCount: 0,
    totalRequired: required,
  );
}

/// FLEX 공고 — 슬롯이 preload된 상태를 재현한다.
TOGroupItem _flex(
  String id, {
  List<DateTime> openDates = const [],
  List<DateTime> closedDates = const [],
  List<DateTime>? rawSlotDates,
  DateTime? createdAt,
  DateTime? rangeStart,
  DateTime? rangeEnd,
  String status = TOStatus.active,
  bool isPublished = true,
  String publishMode = 'immediate',
  DateTime? publishAt,
  bool detailLoaded = true,
}) {
  final master = _to(
    id: id,
    createdAt: createdAt,
    status: status,
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
    isPublished: isPublished,
    publishMode: publishMode,
    publishAt: publishAt,
  );
  final group = TOGroupItem(singleTO: master);
  if (detailLoaded) {
    group.setGroupTOs([
      for (final d in openDates) _slot(master, d),
      // closedBy가 있으면 CloseStateUtils 2번 규칙으로 마감
      for (final d in closedDates) _slot(master, d, closedBy: 'admin'),
    ]);
    group.setSlotDates(
      rawSlotDates ?? [...openDates, ...closedDates],
    );
  }
  return group;
}

/// CONTRACT 공고.
TOGroupItem _contract(
  String id, {
  DateTime? rangeStart,
  DateTime? rangeEnd,
  DateTime? createdAt,
  String status = TOStatus.active,
  bool isPublished = true,
  String publishMode = 'immediate',
  DateTime? publishAt,
}) {
  return TOGroupItem(
    singleTO: _to(
      id: id,
      type: 'contract',
      createdAt: createdAt,
      status: status,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      isPublished: isPublished,
      publishMode: publishMode,
      publishAt: publishAt,
    ),
  );
}

List<String> _order(
  List<TOGroupItem> items, {
  Set<String> detailErrorIds = const {},
}) =>
    WorkforceController.sortForOperations(
      items,
      detailErrorIds: detailErrorIds,
      now: _now,
    ).map((g) => g.id).toList();

DateTime? _priority(
  TOGroupItem g, {
  Set<String> detailErrorIds = const {},
}) =>
    WorkforceController.priorityDateOf(g, _now,
        detailErrorIds: detailErrorIds);

// ═══════════════════════════════════════════════════════════════
// 마감됨 탭 replica
// ═══════════════════════════════════════════════════════════════

List<String> closedOrder(List<TOGroupItem> items) {
  final sorted = items.toList()
    ..sort((a, b) {
      final aDate =
          a.masterTO.closedAt ?? a.masterTO.statusUpdatedAt ?? a.masterTO.date;
      final bDate =
          b.masterTO.closedAt ?? b.masterTO.statusUpdatedAt ?? b.masterTO.date;
      final byDate = bDate.compareTo(aDate);
      if (byDate != 0) return byDate;
      return a.id.compareTo(b.id);
    });
  return sorted.map((g) => g.id).toList();
}

// ═══════════════════════════════════════════════════════════════
// 소스 helper
// ═══════════════════════════════════════════════════════════════

const _ctrlPath = 'lib/controllers/workforce_controller.dart';
const _listPath =
    'lib/screens/business_admin/workforce_management/workforce_list_view.dart';
const _svcPath = 'lib/services/firestore_service.dart';
const _fnPath = 'functions/src/index.ts';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

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

void main() {
  // ══════════════════════════════════════════════════════════════
  // §4, §5, §19 FLEX priority date
  // ══════════════════════════════════════════════════════════════
  group('01. FLEX priority date', () {
    test('01-a 9/15 + 9/20 → 9/15', () {
      final g = _flex('A', openDates: [_day(9, 20), _day(9, 15)]);
      expect(_priority(g), _day(9, 15));
    });

    test('01-b 지난 9/10 + 미래 9/25 → 9/25', () {
      final g = _flex('A',
          openDates: [_day(9, 25)], closedDates: [_day(9, 10)]);
      expect(_priority(g), _day(9, 25),
          reason: '이미 지난 첫 슬롯으로 정렬하지 않는다');
    });

    test('01-c 날짜 경과만으로도 슬롯이 걸러진다 (closedBy 없이)', () {
      final master = _to(id: 'A');
      final g = TOGroupItem(singleTO: master);
      g.setGroupTOs([
        _slot(master, _day(9, 10)), // 과거 — CloseStateUtils 1번 규칙
        _slot(master, _day(9, 25)),
      ]);
      g.setSlotDates([_day(9, 10), _day(9, 25)]);
      expect(_priority(g), _day(9, 25));
    });

    test('01-d 오늘 근무가 있으면 오늘이 priority다', () {
      final g = _flex('A', openDates: [_day(9, 14), _day(9, 20)]);
      expect(_priority(g), _day(9, 14));
    });

    test('01-e 가장 이른 슬롯을 지워도 stale rangeStart가 이기지 않는다', () {
      // 9/05 슬롯을 삭제한 뒤에도 rangeStart는 9/05로 남아 있다(drift).
      final g = _flex(
        'A',
        openDates: [_day(9, 25)],
        rangeStart: _day(9, 5),
        rangeEnd: _day(9, 25),
      );
      expect(_priority(g), _day(9, 25),
          reason: '실제 slot 문서가 range metadata를 이긴다');
    });

    test('01-f 모든 슬롯이 마감이면 raw slotDates 중 오늘 이후 최소값', () {
      final g = _flex(
        'A',
        closedDates: [_day(9, 10), _day(9, 22)],
      );
      expect(_priority(g), _day(9, 22),
          reason: '지난 9/10은 제외된다');
    });

    test('01-g 열린 슬롯도 유효한 raw 날짜도 없으면 range fallback', () {
      final master = _to(id: 'A', rangeEnd: _day(9, 30));
      final g = TOGroupItem(singleTO: master);
      g.setGroupTOs([]);
      g.setSlotDates([]);
      expect(_priority(g), _day(9, 30));
    });

    test('01-h fallback도 없으면 null', () {
      final master = _to(id: 'A');
      final g = TOGroupItem(singleTO: master);
      g.setGroupTOs([]);
      g.setSlotDates([]);
      expect(_priority(g), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §6 FLEX detail load failure
  // ══════════════════════════════════════════════════════════════
  group('02. slot 조회 실패 / overflow', () {
    test('02-a detail error면 range fallback도 쓰지 않고 null', () {
      final g = _flex(
        'A',
        openDates: [_day(9, 25)],
        rangeStart: _day(9, 5),
        rangeEnd: _day(9, 30),
      );
      expect(_priority(g, detailErrorIds: {'A'}), isNull,
          reason: '오류를 정상 slot date처럼 위장하지 않는다');
    });

    test('02-b overflow도 같은 경로다 — caller가 같은 error set에 넣는다', () {
      final g = _flex('A', openDates: [_day(9, 15)]);
      expect(_priority(g, detailErrorIds: {'A'}), isNull);
    });

    test('02-c 다른 공고의 error는 영향을 주지 않는다', () {
      final g = _flex('A', openDates: [_day(9, 15)]);
      expect(_priority(g, detailErrorIds: {'B'}), _day(9, 15));
    });

    test('02-d preload 자체가 안 된 그룹은 range fallback이 허용된다', () {
      final g = _flex('A', detailLoaded: false, rangeEnd: _day(9, 18));
      expect(_priority(g), _day(9, 18),
          reason: '오류가 아니라 정보 부재 — 최후 fallback 계약');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §8, §21 CONTRACT
  // ══════════════════════════════════════════════════════════════
  group('03. CONTRACT priority date', () {
    test('03-a 시작 전이면 rangeStart', () {
      final g = _contract('C', rangeStart: _day(9, 20), rangeEnd: _day(12, 31));
      expect(_priority(g), _day(9, 20));
    });

    test('03-b 이미 시작해 진행 중이면 오늘', () {
      final g = _contract('C', rangeStart: _day(8, 1), rangeEnd: _day(12, 31));
      expect(_priority(g), _day(9, 14),
          reason: '지난 시작일로 목록 맨 앞에 고정되지 않는다');
    });

    test('03-c 오늘 시작이면 오늘', () {
      final g = _contract('C', rangeStart: _day(9, 14), rangeEnd: _day(12, 31));
      expect(_priority(g), _day(9, 14));
    });

    test('03-d rangeStart가 없으면 unknown', () {
      expect(_priority(_contract('C')), isNull);
    });

    test('03-e 미래 시작일끼리는 ASC', () {
      expect(
        _order([
          _contract('late', rangeStart: _day(10, 1)),
          _contract('soon', rangeStart: _day(9, 16)),
        ]),
        ['soon', 'late'],
      );
    });

    test('03-f createdAt이 최신이어도 먼 근무가 가까운 근무를 앞지르지 않는다', () {
      expect(
        _order([
          _contract('new_far',
              rangeStart: _day(11, 1), createdAt: DateTime.utc(2025, 9, 14)),
          _contract('old_near',
              rangeStart: _day(9, 16), createdAt: DateTime.utc(2025, 6, 1)),
        ]),
        ['old_near', 'new_far'],
      );
    });

    test('03-g FLEX와 CONTRACT가 같은 날짜 축에서 섞인다', () {
      expect(
        _order([
          _contract('c_0920', rangeStart: _day(9, 20)),
          _flex('f_0916', openDates: [_day(9, 16)]),
          _contract('c_0918', rangeStart: _day(9, 18)),
        ]),
        ['f_0916', 'c_0918', 'c_0920'],
      );
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §3, §20 미공개
  // ══════════════════════════════════════════════════════════════
  group('04. DRAFT / pending publish', () {
    test('04-a 공개 공고가 같은 날짜의 DRAFT보다 앞', () {
      expect(
        _order([
          _flex('draft', openDates: [_day(9, 15)], status: TOStatus.draft),
          _flex('live', openDates: [_day(9, 15)]),
        ]),
        ['live', 'draft'],
      );
    });

    test('04-b 방금 만든 DRAFT가 최상단을 차지하지 않는다', () {
      expect(
        _order([
          _flex('draft_new',
              openDates: [_day(9, 15)],
              status: TOStatus.draft,
              createdAt: DateTime.utc(2025, 9, 14)),
          _flex('live_old',
              openDates: [_day(9, 25)], createdAt: DateTime.utc(2025, 5, 1)),
        ]),
        ['live_old', 'draft_new'],
      );
    });

    test('04-c DRAFT가 더 가까운 날짜여도 공개 공고 뒤', () {
      expect(
        _order([
          _flex('draft_soon',
              openDates: [_day(9, 15)], status: TOStatus.draft),
          _flex('live_far', openDates: [_day(12, 1)]),
        ]),
        ['live_far', 'draft_soon'],
      );
    });

    test('04-d 예약 공개(pending publish)도 뒤로 간다', () {
      final pending = _flex(
        'scheduled',
        openDates: [_day(9, 15)],
        status: TOStatus.scheduled,
        isPublished: false,
        publishMode: 'scheduled',
        publishAt: DateTime.now().add(const Duration(days: 30)),
      );
      expect(pending.isPendingPublish, true, reason: 'fixture 전제 확인');
      expect(
        _order([pending, _flex('live', openDates: [_day(9, 25)])]),
        ['live', 'scheduled'],
      );
    });

    test('04-e 미공개끼리는 내부적으로 날짜순이 유지된다', () {
      expect(
        _order([
          _flex('d_late', openDates: [_day(10, 5)], status: TOStatus.draft),
          _flex('d_soon', openDates: [_day(9, 16)], status: TOStatus.draft),
        ]),
        ['d_soon', 'd_late'],
        reason: 'unpublished 필터에서 보는 순서',
      );
    });

    test('04-f 공개 공고끼리도 동일한 operational order', () {
      expect(
        _order([
          _flex('p_late', openDates: [_day(10, 5)]),
          _flex('p_soon', openDates: [_day(9, 16)]),
        ]),
        ['p_soon', 'p_late'],
      );
    });

    test('04-g 미공개는 숨기지 않는다 — 목록에서 사라지지 않는다', () {
      final sorted = _order([
        _flex('draft', openDates: [_day(9, 15)], status: TOStatus.draft),
        _flex('live', openDates: [_day(9, 20)]),
      ]);
      expect(sorted.length, 2);
      expect(sorted.contains('draft'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §9 unknown date
  // ══════════════════════════════════════════════════════════════
  group('05. 날짜 미상', () {
    test('05-a 날짜를 아는 공고가 먼저', () {
      expect(
        _order([
          _contract('unknown'),
          _flex('dated', openDates: [_day(12, 31)]),
        ]),
        ['dated', 'unknown'],
      );
    });

    test('05-b createdAt이 최신이어도 날짜 미상이 앞서지 않는다', () {
      expect(
        _order([
          _contract('unknown_new', createdAt: DateTime.utc(2025, 9, 14)),
          _flex('dated_old',
              openDates: [_day(12, 31)], createdAt: DateTime.utc(2025, 1, 2)),
        ]),
        ['dated_old', 'unknown_new'],
      );
    });

    test('05-c unknown 내부는 createdAt DESC → id ASC', () {
      expect(
        _order([
          _contract('u_b', createdAt: DateTime.utc(2025, 3, 1)),
          _contract('u_a', createdAt: DateTime.utc(2025, 3, 1)),
          _contract('u_new', createdAt: DateTime.utc(2025, 8, 1)),
        ]),
        ['u_new', 'u_a', 'u_b'],
      );
    });

    test('05-d detail error로 unknown이 된 공고도 같은 자리', () {
      expect(
        _order([
          _flex('broken', openDates: [_day(9, 15)]),
          _flex('ok', openDates: [_day(11, 1)]),
        ], detailErrorIds: {'broken'}),
        ['ok', 'broken'],
      );
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §10, §11, §22 동일 키 / 결정성
  // ══════════════════════════════════════════════════════════════
  group('06. 동일 priority date', () {
    test('06-a 같은 날짜면 createdAt DESC', () {
      expect(
        _order([
          _flex('old', openDates: [_day(9, 15)], createdAt: DateTime.utc(2025, 1, 5)),
          _flex('new', openDates: [_day(9, 15)], createdAt: DateTime.utc(2025, 7, 5)),
        ]),
        ['new', 'old'],
      );
    });

    test('06-b publish state·날짜·createdAt이 모두 같으면 id ASC', () {
      final made = DateTime.utc(2025, 4, 4);
      expect(
        _order([
          _flex('zz', openDates: [_day(9, 15)], createdAt: made),
          _flex('aa', openDates: [_day(9, 15)], createdAt: made),
          _flex('mm', openDates: [_day(9, 15)], createdAt: made),
        ]),
        ['aa', 'mm', 'zz'],
      );
    });

    test('06-c 입력 순서를 바꿔도 결과가 같다', () {
      final made = DateTime.utc(2025, 4, 4);
      List<TOGroupItem> build() => [
            _flex('zz', openDates: [_day(9, 15)], createdAt: made),
            _flex('aa', openDates: [_day(9, 15)], createdAt: made),
            _flex('mm', openDates: [_day(9, 15)], createdAt: made),
          ];
      final forward = _order(build());
      final reversed = _order(build().reversed.toList());
      expect(reversed, forward);
    });

    test('06-d 반복 호출에서 순서가 흔들리지 않는다', () {
      final made = DateTime.utc(2025, 4, 4);
      final items = [
        for (final id in ['e', 'c', 'a', 'd', 'b'])
          _flex(id, openDates: [_day(9, 15)], createdAt: made),
      ];
      final first = _order(items);
      for (var i = 0; i < 5; i++) {
        expect(_order(items), first);
      }
      expect(first, ['a', 'b', 'c', 'd', 'e']);
    });

    test('06-e shortage / confirmed 수치는 순서를 바꾸지 않는다', () {
      final master = _to(id: 'short', createdAt: DateTime.utc(2025, 4, 4));
      final short = TOGroupItem(singleTO: master);
      short.setGroupTOs([_slot(master, _day(9, 15), confirmed: 0, required: 9)]);
      short.setSlotDates([_day(9, 15)]);

      final masterB = _to(id: 'staffed', createdAt: DateTime.utc(2025, 4, 4));
      final staffed = TOGroupItem(singleTO: masterB);
      staffed.setGroupTOs([_slot(masterB, _day(9, 15), confirmed: 8, required: 9)]);
      staffed.setSlotDates([_day(9, 15)]);

      expect(_order([staffed, short]), ['short', 'staffed'],
          reason: 'id ASC로만 결정된다 — 부족 여부는 tie-break가 아니다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §12, §23 마감됨 탭
  // ══════════════════════════════════════════════════════════════
  group('07. 마감됨 탭', () {
    TOGroupItem closed(String id, {DateTime? statusUpdatedAt}) {
      return TOGroupItem(
        singleTO: TOModel(
          id: id,
          businessId: 'biz1',
          businessName: '테스트 사업장',
          type: 'flex',
          title: id,
          creatorUID: 'uid1',
          status: TOStatus.closed,
          deadlineType: 'HOURS_BEFORE',
          hoursBeforeStart: 2,
          workDetails: const [],
          totalRequired: 1,
          totalConfirmed: 0,
          totalPending: 0,
          isPublished: true,
          publishMode: 'immediate',
          createdAt: DateTime.utc(2025, 1, 1),
          statusUpdatedAt: statusUpdatedAt ?? DateTime.utc(2025, 1, 1),
        ),
      );
    }

    test('07-a 최근 종료순(DESC)을 유지한다 — 날짜 ASC로 바뀌지 않았다', () {
      expect(
        closedOrder([
          closed('old', statusUpdatedAt: DateTime.utc(2025, 3, 1)),
          closed('recent', statusUpdatedAt: DateTime.utc(2025, 9, 1)),
        ]),
        ['recent', 'old'],
      );
    });

    test('07-b 동일 key에서 id ASC', () {
      final same = DateTime.utc(2025, 9, 1);
      expect(
        closedOrder([
          closed('zz', statusUpdatedAt: same),
          closed('aa', statusUpdatedAt: same),
        ]),
        ['aa', 'zz'],
      );
    });

    test('07-c 진행중 comparator가 마감됨 순서를 오염시키지 않는다', () {
      final items = [
        closed('old', statusUpdatedAt: DateTime.utc(2025, 3, 1)),
        closed('recent', statusUpdatedAt: DateTime.utc(2025, 9, 1)),
      ];
      expect(closedOrder(items).first, 'recent');
      // 운영 comparator를 같은 집합에 돌리면 결과가 다르다 — 두 탭은 다른 질문이다
      expect(_order(items), isNot(closedOrder(items)));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 소스 고정 — §13 §14 §15 §18
  // ══════════════════════════════════════════════════════════════
  group('08. 정렬 소유권과 비용', () {
    final ctrl = _src(_ctrlPath);

    test('08-a 정렬은 slot preload가 끝난 뒤 load 회차당 1회 돈다', () {
      final body = _codeOf(_bodyOf(ctrl, 'Future<void> _runOneLoad('));
      final preload = body.indexOf('loadFlexSlots(');
      final sortAt = body.indexOf('_sortItemsForOperations();');
      expect(preload, greaterThan(-1));
      expect(sortAt, greaterThan(preload),
          reason: 'slot이 채워지기 전에 정렬하면 FLEX 날짜를 알 수 없다');
      expect(
        RegExp(r'_sortItemsForOperations\(\);').allMatches(body).length,
        1,
      );
    });

    test('08-b 진행중 탭은 화면에서 재정렬하지 않는다', () {
      final body =
          _codeOf(_bodyOf(_src(_listPath), 'List<TOGroupItem> _computeFilteredItems('));
      final closedBranch = body.indexOf("_selectedTab != TOStatus.closed");
      final firstSort = body.indexOf('..sort(');
      expect(closedBranch, greaterThan(-1));
      expect(firstSort, greaterThan(closedBranch),
          reason: '정렬은 마감됨 분기 뒤에만 있어야 한다');
      expect(RegExp(r'\.\.sort\(').allMatches(body).length, 1);
    });

    test('08-c 마감됨 정렬에 id tie-break가 있다', () {
      final body =
          _flat(_codeOf(_bodyOf(_src(_listPath), 'List<TOGroupItem> _computeFilteredItems(')));
      expect(body.contains('return a.id.compareTo(b.id);'), true);
    });

    test('08-d service의 createdAt 예비 정렬은 그대로 남아 있다 (§14)', () {
      expect(
        _src(_svcPath).contains(
            '..sort((a, b) => b.singleTO.createdAt.compareTo(a.singleTO.createdAt));'),
        true,
        reason: 'controller가 최종 owner — service contract를 흔들지 않는다',
      );
    });

    test('08-e 서버는 표시 순서를 소유하지 않는다', () {
      // [POSTING-V2-03T.1] 사업장별 단일 window(PER_BIZ_LIMIT)가 OPEN/CLOSED
      //   두 모집단으로 갈렸다. 03Q.1이 의존하는 사실은 "서버 orderBy는 절단
      //   기준일 뿐 UI ordering contract가 아니다"이고, 그것은 그대로다 —
      //   OPEN은 아예 정렬 없이 전량, CLOSED만 createdAt DESC로 잘린다.
      final fn = _flat(_src(_fnPath));
      expect(
        fn.contains(
            '.where("status", "in", closedStates) .orderBy("createdAt", "desc") .limit(CLOSED_HISTORY_LIMIT)'),
        true,
      );
      expect(_src(_fnPath).contains('const CLOSED_HISTORY_LIMIT = 500;'), true);
      // 최종 순서는 controller가 정한다
      final ctrl = _src(_ctrlPath);
      expect(ctrl.contains('_sortItemsForOperations();'), true);
    });

    test('08-f 정렬 때문에 추가 조회를 넣지 않았다 (§18)', () {
      final sortBody = _codeOf(_bodyOf(
          ctrl, 'static List<TOGroupItem> sortForOperations('));
      final dateBody =
          _codeOf(_bodyOf(ctrl, 'static DateTime? priorityDateOf('));
      for (final body in [sortBody, dateBody]) {
        expect(body.contains('await'), false);
        expect(body.contains('_service.'), false);
        expect(body.contains('httpsCallable'), false);
      }
    });

    test('08-g 정렬 키에 shortage / confirmed / pending이 없다 (§1, §10)', () {
      final sortBody = _codeOf(_bodyOf(
          ctrl, 'static List<TOGroupItem> sortForOperations('));
      for (final forbidden in [
        'totalConfirmed',
        'totalPending',
        'totalRequired',
        'shortage',
        'confirmedCount',
      ]) {
        expect(sortBody.contains(forbidden), false, reason: forbidden);
      }
    });

    test('08-h comparator 순서가 문서화된 계약과 같다', () {
      final body = _codeOf(_bodyOf(
          ctrl, 'static List<TOGroupItem> sortForOperations('));
      final pre = body.indexOf('preOperational');
      final unknown = body.indexOf('ad == null');
      final byDate = body.indexOf('ad.compareTo(bd)');
      final created = body.indexOf('createdAt.compareTo');
      final id = body.indexOf('id.compareTo');
      expect(pre, greaterThan(-1));
      expect(pre, lessThan(unknown));
      expect(unknown, lessThan(byDate));
      expect(byDate, lessThan(created));
      expect(created, lessThan(id));
    });

    test('08-i FLEX는 slot을 range metadata보다 먼저 본다 (§7)', () {
      final body = _codeOf(_bodyOf(ctrl, 'static DateTime? priorityDateOf('));
      final errorGuard = body.indexOf('detailErrorIds.contains(group.id)');
      final groupTOs = body.indexOf('group.groupTOs');
      final slotDates = body.indexOf('group.slotDates');
      final range = body.indexOf('to.rangeEnd ?? to.rangeStart');
      expect(errorGuard, greaterThan(-1));
      expect(errorGuard, lessThan(groupTOs));
      expect(groupTOs, lessThan(slotDates));
      expect(slotDates, lessThan(range));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §24 무회귀
  // ══════════════════════════════════════════════════════════════
  group('09. 기존 계약 무회귀', () {
    test('09-a reveal lift가 정렬 뒤에 그대로 남아 있다', () {
      final body =
          _codeOf(_bodyOf(_src(_listPath), 'List<TOGroupItem> _computeFilteredItems('));
      expect(RegExp(r'_liftRevealTarget\(').allMatches(body).length, 2,
          reason: '진행중/마감됨 두 분기 모두 유지');
    });

    test('09-b 필터 술어(_matchesFilters)를 건드리지 않았다', () {
      final body = _codeOf(_bodyOf(_src(_listPath), 'bool _matchesFilters('));
      for (final key in [
        'selectedBusinessId',
        'selectedTOType',
        'selectedPublishStatus',
        'selectedDateRange',
      ]) {
        expect(body.contains(key), true, reason: key);
      }
    });

    test('09-c 03P loading semantics 유지', () {
      expect(ctrlHas('bool get hasLoadedOnce => _hasLoadedOnce;'), true);
      expect(ctrlHas('bool get lastSuccessfulWasEmpty => _lastSuccessfulWasEmpty;'),
          true);
      expect(ctrlHas('bool get lastLoadFailed => _lastLoadFailed;'), true);
    });

    test('09-d 03O coalescing / 03N scope recovery 유지', () {
      expect(ctrlHas('Future<void>? _loadCycle;'), true);
      expect(ctrlHas('bool _pendingLoad = false;'), true);
      expect(ctrlHas('_scopeShrinkCandidates'), true);
    });

    test('09-e FLEX slot preload 계약(TO당 1회) 유지', () {
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> _runOneLoad('));
      expect(RegExp(r'loadFlexSlots\(').allMatches(body).length, 1);
      expect(body.contains('group.setSlotDates(loaded.slotDates);'), true);
    });

    test('09-f Home 정렬을 건드리지 않았다', () {
      final home =
          _src('lib/screens/business_admin/business_admin_home_screen.dart');
      expect(home.contains('.where((d) => d.requiredCount > 0)'), true);
    });
  });
}

bool ctrlHas(String needle) => _src(_ctrlPath).contains(needle);
