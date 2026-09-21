// [POSTING-V2-03R.1] 운영 카드 IA 정렬
//
// 03R READ에서 확인된 것:
//   · 카드의 FLEX 날짜가 `groupTOs.first`(마감 여부를 보지 않는 가장 이른 슬롯)
//     였다. 03Q.1이 목록을 열린 슬롯 기준으로 정렬한 뒤로, 9/25 자리에 놓인
//     카드가 9/10을 표시하는 모순이 생겼다.
//   · `[N일]` 배지와 `외 N일`이 같은 수를 두 번 말했고, 둘 다 끝난 날짜를 셌다.
//   · FLEX 다중·CONTRACT collapsed에는 `필요 인원` 숫자가 아예 없었다.
//   · 지원자까지 가는 유일한 경로가 펼침 → 칩 → 명단(3탭)이었고 collapsed에
//     단서가 없었다.
//   · SlotStatusBadge의 Text에 Flexible이 없어 긴 라벨이 날짜를 0폭으로 밀었다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/controllers/workforce_controller.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/slot_status_util.dart';
import 'package:ALfit/widgets/admin/cards/admin_to_group_card.dart';
import 'package:ALfit/widgets/common/slot_status_badge.dart';

// ═══════════════════════════════════════════════════════════════
// fixture
// ═══════════════════════════════════════════════════════════════

final _now = DateTime.utc(2025, 9, 14, 1, 0); // KST 2025-09-14 10:00
DateTime _day(int month, int dayOfMonth) => DateTime.utc(2025, month, dayOfMonth);

WorkDetailData _wd({
  String workType = '피킹 보조',
  String startTime = '09:00',
  String endTime = '18:00',
  int requiredCount = 2,
}) =>
    WorkDetailData(
      workType: workType,
      startTime: startTime,
      endTime: endTime,
      wage: 12000,
      wageType: 'hourly',
      requiredCount: requiredCount,
    );

TOModel _to({
  required String id,
  String type = 'flex',
  String status = TOStatus.active,
  List<WorkDetailData> workDetails = const [],
  DateTime? rangeStart,
  DateTime? rangeEnd,
  int totalRequired = 10,
  int totalConfirmed = 6,
  int totalPending = 2,
}) =>
    TOModel(
      id: id,
      businessId: 'biz1',
      businessName: '평택센터',
      type: type,
      title: '공고 $id',
      creatorUID: 'uid1',
      status: status,
      deadlineType: 'HOURS_BEFORE',
      hoursBeforeStart: 2,
      workDetails: workDetails,
      totalRequired: totalRequired,
      totalConfirmed: totalConfirmed,
      totalPending: totalPending,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime.utc(2025, 1, 1),
      statusUpdatedAt: DateTime.utc(2025, 1, 1),
    );

TOItem _slot(
  TOModel master,
  DateTime date, {
  String? closedBy,
  List<WorkDetailData> workDetails = const [],
}) =>
    TOItem(
      to: master,
      slot: SlotModel(
        id: 'slot_${date.month}_${date.day}',
        toId: master.id,
        date: date,
        status: 'OPEN',
        closedBy: closedBy,
        workDetails: workDetails,
        createdAt: DateTime.utc(2025, 1, 1),
      ),
      confirmedCount: 0,
      pendingCount: 0,
      totalRequired: 2,
    );

/// 슬롯이 preload된 FLEX 공고 + controller가 날짜를 확정한 상태.
TOGroupItem _flex(
  String id, {
  List<DateTime> openDates = const [],
  List<DateTime> closedDates = const [],
  List<WorkDetailData> slotWorkDetails = const [],
  DateTime? rangeStart,
  DateTime? rangeEnd,
  bool resolve = true,
  Set<String> detailErrorIds = const {},
}) {
  final master = _to(id: id, rangeStart: rangeStart, rangeEnd: rangeEnd);
  final group = TOGroupItem(singleTO: master);
  group.setGroupTOs([
    for (final d in openDates) _slot(master, d, workDetails: slotWorkDetails),
    for (final d in closedDates)
      _slot(master, d, closedBy: 'admin', workDetails: slotWorkDetails),
  ]);
  group.setSlotDates([...openDates, ...closedDates]);
  if (resolve) {
    group.setOperationalDate(WorkforceController.priorityDateOf(group, _now,
        detailErrorIds: detailErrorIds));
  }
  return group;
}

// ═══════════════════════════════════════════════════════════════
// 소스 helper
// ═══════════════════════════════════════════════════════════════

const _cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';
const _badgePath = 'lib/widgets/common/slot_status_badge.dart';
const _modelPath = 'lib/models/ui/admin_to_list_ui_models.dart';
const _ctrlPath = 'lib/controllers/workforce_controller.dart';

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
  // §1 §2 §25 — 정렬 날짜와 카드 날짜가 한 source
  // ══════════════════════════════════════════════════════════════
  group('01. canonical date source', () {
    test('01-a 9/10 종료 + 9/25 모집중 → comparator·카드 모두 9/25', () {
      final g = _flex('A', openDates: [_day(9, 25)], closedDates: [_day(9, 10)]);
      final sortKey = WorkforceController.priorityDateOf(g, _now,
          detailErrorIds: const {});
      expect(sortKey, _day(9, 25));
      expect(g.operationalDate, sortKey, reason: '두 값이 같은 계산에서 나와야 한다');
      expect(FormatHelper.formatDate(g.operationalDate!), '9/25 (목)');
    });

    test('01-b CTA destination도 같은 9/25다', () {
      final g = _flex('A', openDates: [_day(9, 25)], closedDates: [_day(9, 10)]);
      final slot = g.operationalSlot;
      expect(slot, isNotNull);
      expect(FormatHelper.toKstDate(slot!.slot!.date), g.operationalDate);
    });

    test('01-c 종료된 날짜를 대표 날짜로 쓰지 않는다', () {
      final g = _flex('A', openDates: [_day(9, 25)], closedDates: [_day(9, 10)]);
      expect(g.operationalDate, isNot(_day(9, 10)));
      expect(g.operationalSlot!.slot!.closedBy, isNull);
    });

    test('01-d stale rangeStart가 실제 슬롯을 이기지 않는다', () {
      final g = _flex('A',
          openDates: [_day(9, 25)],
          rangeStart: _day(9, 5),
          rangeEnd: _day(9, 25));
      expect(g.operationalDate, _day(9, 25));
    });

    test('01-e sortForOperations가 모든 group에 날짜를 심는다', () {
      final items = [
        _flex('A', openDates: [_day(9, 25)], resolve: false),
        _flex('B', openDates: [_day(9, 16)], resolve: false),
      ];
      expect(items.every((g) => !g.hasOperationalDate), true);
      final sorted = WorkforceController.sortForOperations(items,
          detailErrorIds: const {}, now: _now);
      expect(sorted.map((g) => g.id).toList(), ['B', 'A']);
      for (final g in sorted) {
        expect(g.hasOperationalDate, true);
      }
      expect(sorted.first.operationalDate, _day(9, 16));
    });

    test('01-f 단건 목록에서도 날짜가 확정된다', () {
      final items = [_flex('A', openDates: [_day(9, 25)], resolve: false)];
      WorkforceController.sortForOperations(items,
          detailErrorIds: const {}, now: _now);
      expect(items.single.hasOperationalDate, true);
      expect(items.single.operationalDate, _day(9, 25));
    });

    test('01-g detail error면 날짜를 주장하지 않는다', () {
      final g = _flex('A',
          openDates: [_day(9, 25)],
          rangeEnd: _day(9, 30),
          detailErrorIds: {'A'});
      expect(g.hasOperationalDate, true);
      expect(g.operationalDate, isNull, reason: '확정된 unknown이다');
      expect(g.operationalSlot, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §3 §C — 남은 날짜만 센다
  // ══════════════════════════════════════════════════════════════
  group('02. 남은 운영 날짜 수', () {
    test('02-a 종료된 날짜는 세지 않는다', () {
      final g = _flex('A',
          openDates: [_day(9, 25), _day(9, 30)],
          closedDates: [_day(9, 10), _day(9, 12)]);
      expect(g.groupTOs.length, 4);
      expect(g.openSlotCount(_now), 2);
    });

    test('02-b 지난 날짜는 closedBy 없이도 빠진다', () {
      final master = _to(id: 'A');
      final g = TOGroupItem(singleTO: master);
      g.setGroupTOs([_slot(master, _day(9, 10)), _slot(master, _day(9, 25))]);
      expect(g.openSlotCount(_now), 1);
    });

    test('02-c 전부 종료면 0', () {
      final g = _flex('A', closedDates: [_day(9, 10), _day(9, 12)]);
      expect(g.openSlotCount(_now), 0);
    });

    test('02-d CONTRACT에는 남은 날짜 개념이 없다', () {
      final g = TOGroupItem(singleTO: _to(id: 'C', type: 'contract'));
      expect(g.openSlotCount(_now), 0);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §7 §8 §27 — 업무/시간 요약
  // ══════════════════════════════════════════════════════════════
  group('03. 업무 요약', () {
    test('03-a 업무 하나면 실제 이름', () {
      expect(collapsedWorkSummary([_wd(workType: '피킹 보조')]), '피킹 보조');
    });

    test('03-b 같은 업무가 시간만 달라도 하나로 본다', () {
      expect(
        collapsedWorkSummary([
          _wd(workType: '피킹 보조', startTime: '09:00'),
          _wd(workType: '피킹 보조', startTime: '14:00'),
        ]),
        '피킹 보조',
      );
    });

    test('03-c 여러 업무는 하나를 대표로 세우지 않는다', () {
      final summary = collapsedWorkSummary([
        _wd(workType: '피킹 보조'),
        _wd(workType: '포장'),
        _wd(workType: '상하차'),
      ]);
      expect(summary, '업무 3개');
      expect(summary!.contains('피킹'), false);
    });

    test('03-d 업무명을 알 수 없으면 null — 가짜 fallback 없음', () {
      expect(collapsedWorkSummary(const []), isNull);
      expect(collapsedWorkSummary([_wd(workType: '')]), isNull);
    });
  });

  group('04. 시간 요약', () {
    test('04-a 시간대 하나면 실제 시간', () {
      expect(collapsedTimeSummary([_wd(startTime: '09:00', endTime: '18:00')]),
          '09:00–18:00');
    });

    test('04-b 업무가 여럿이어도 시간대가 같으면 실제 시간', () {
      expect(
        collapsedTimeSummary([
          _wd(workType: '피킹', startTime: '09:00', endTime: '18:00'),
          _wd(workType: '포장', startTime: '09:00', endTime: '18:00'),
        ]),
        '09:00–18:00',
      );
    });

    test('04-c 시간대가 여럿이면 하나로 위장하지 않는다', () {
      final summary = collapsedTimeSummary([
        _wd(startTime: '09:00', endTime: '18:00'),
        _wd(startTime: '14:00', endTime: '22:00'),
      ]);
      expect(summary, '시간대 2개');
      expect(summary!.contains('09:00'), false);
      expect(summary.contains('14:00'), false);
    });

    test('04-d 시간을 알 수 없으면 생략한다', () {
      expect(collapsedTimeSummary(const []), isNull);
      expect(collapsedTimeSummary([_wd(startTime: '', endTime: '')]), isNull);
    });

    test('04-e 일부만 시간이 있으면 있는 것만 센다', () {
      expect(
        collapsedTimeSummary([
          _wd(startTime: '09:00', endTime: '18:00'),
          _wd(startTime: '', endTime: ''),
        ]),
        '09:00–18:00',
      );
    });

    test('04-f TOModel.timeRange(min~max 합성)를 쓰지 않는다', () {
      final details = [
        _wd(startTime: '09:00', endTime: '12:00'),
        _wd(startTime: '14:00', endTime: '22:00'),
      ];
      final to = _to(id: 'X', workDetails: details);
      expect(to.timeRange, '09:00 ~ 22:00');
      expect(collapsedTimeSummary(details), isNot(to.timeRange),
          reason: '아무도 09~22시에 일하지 않는다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §21 §22 §29 — overflow
  // ══════════════════════════════════════════════════════════════
  group('05. overflow 보호', () {
    Future<void> pumpBadge(WidgetTester tester, double width,
        {required SlotDisplayStatus status, DateTime? scheduledAt}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: Row(
                children: [
                  const Expanded(
                    child: Text('9/25 (목) · 09:00–18:00',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Flexible(
                    child: SlotStatusBadge(
                        status: status, scheduledAt: scheduledAt),
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
    }

    testWidgets('05-a 긴 예약공개 라벨이 좁은 폭에서 overflow하지 않는다',
        (tester) async {
      await pumpBadge(tester, 160,
          status: SlotDisplayStatus.scheduled,
          scheduledAt: DateTime(2025, 9, 20, 14, 0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('05-b 아주 좁은 폭에서도 버틴다', (tester) async {
      await pumpBadge(tester, 90,
          status: SlotDisplayStatus.scheduled,
          scheduledAt: DateTime(2025, 9, 20, 14, 0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('05-c 다른 상태들도 동일', (tester) async {
      for (final status in SlotDisplayStatus.values) {
        await pumpBadge(tester, 120, status: status);
        expect(tester.takeException(), isNull, reason: '$status');
      }
    });

    testWidgets('05-d 배지를 비-flex로 둬도 렌더된다 (기존 호출부 호환)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [SlotStatusBadge(status: SlotDisplayStatus.recruiting)],
              ),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('모집중'), findsOneWidget);
    });

    test('05-e SlotStatusBadge의 Text가 Flexible로 감싸져 있다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_badgePath), 'Widget _badge(')));
      expect(
        body.contains(
            'Flexible( child: Text(label, style: textStyle, overflow: TextOverflow.ellipsis, maxLines: 1), ),'),
        true,
      );
    });

    test('05-f _buildLongTermMeta / _buildDeadlineMeta에 flex 보호가 있다', () {
      final src = _src(_cardPath);
      for (final sig in [
        'Widget _buildLongTermMeta(',
        'Widget _buildDeadlineMeta(',
      ]) {
        final body = _codeOf(_bodyOf(src, sig));
        expect(body.contains('Flexible('), true, reason: sig);
        expect(body.contains('TextOverflow.ellipsis'), true, reason: sig);
      }
    });

    test('05-g 날짜 줄은 Wrap이라 배지가 날짜를 밀어내지 못한다 (§22)', () {
      final body = _codeOf(_bodyOf(_src(_cardPath), 'Widget _buildWhenLine('));
      expect(body.contains('Wrap('), true);
      expect(body.contains('_buildStatusBadge('), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §4 §5 §6 §9 §10 §11 §12 §26 — collapsed 구조
  // ══════════════════════════════════════════════════════════════
  group('06. collapsed 구조', () {
    final src = _src(_cardPath);
    final build = _codeOf(_bodyOf(src, 'Widget build(BuildContext context)'));

    test('06-a 줄 순서: 언제 → 어떤 일 → 관리용 제목 → 인원 → 액션', () {
      final when = build.indexOf('_buildWhenLine(');
      final work = build.indexOf('_buildWorkLine(');
      final title = build.indexOf('_buildManagedTitleLine(');
      final staffing = build.indexOf('_buildStaffingLine(');
      final action = build.indexOf('_buildActionBar(');
      for (final i in [when, work, title, staffing, action]) {
        expect(i, greaterThan(-1));
      }
      expect(when, lessThan(work));
      expect(work, lessThan(title));
      expect(title, lessThan(staffing));
      expect(staffing, lessThan(action));
    });

    test('06-b 날짜가 관리용 제목보다 큰 typography다 (§5)', () {
      final whenBody = _codeOf(_bodyOf(src, 'Widget _buildWhenLine('));
      final titleBody =
          _codeOf(_bodyOf(src, 'List<Widget> _buildManagedTitleLine('));
      expect(whenBody.contains('ResponsiveHelper.subtitleStyle('), true);
      expect(titleBody.contains('ResponsiveHelper.smallStyle('), true);
      expect(build.contains('ResponsiveHelper.titleStyle('), false,
          reason: '19px bold 관리 제목이 1순위였던 구조가 사라져야 한다');
    });

    test('06-c `N시간 전` 생성 시각이 collapsed에서 빠졌다 (§6)', () {
      expect(_codeOf(src).contains('_getCreatedAtText'), false);
      expect(build.contains('시간 전'), false);
    });

    test('06-d 슬롯 수 배지와 `외 N일` 중복이 사라졌다 (§3)', () {
      final code = _codeOf(src);
      expect(code.contains('_buildSlotCountBadge'), false);
      expect(code.contains('외 \${count - 1}일'), false);
      expect(code.contains('_getDateText'), false);
    });

    test('06-e 남은 날짜는 열린 슬롯만 센다', () {
      final body =
          _codeOf(_bodyOf(src, 'String? _collapsedRemainingText('));
      expect(body.contains('openSlotCount(now)'), true);
      expect(body.contains('남은 \$open일'), true);
      expect(body.contains('groupTOs.length'), false);
      expect(body.contains('totalSlots'), false);
    });

    test('06-f 관리용 제목은 업무명과 같으면 생략된다 (§9)', () {
      final body =
          _flat(_codeOf(_bodyOf(src, 'List<Widget> _buildManagedTitleLine(')));
      expect(body.contains('if (name == _collapsedWorkText('), true);
      expect(body.contains('maxLines: 1'), true);
    });

    test('06-g FLEX 날짜는 operationalDate만 읽는다 — 재계산 없음 (§2)', () {
      final body = _codeOf(_bodyOf(src, 'String? _collapsedDateText('));
      expect(body.contains('widget.groupItem.operationalDate'), true);
      expect(body.contains('groupTOs.first'), false);
      expect(body.contains('CloseStateUtils'), false,
          reason: '판정 로직을 카드에 복제하지 않는다');
    });

    test('06-h CONTRACT 기간에서 createdAt 폴백이 사라졌다', () {
      final body = _codeOf(_bodyOf(src, 'String? _collapsedDateText('));
      expect(body.contains('createdAt'), false,
          reason: '등록일은 근무일이 아니다');
      expect(body.contains('formatWorkPeriod('), true);
    });
  });

  group('07. 인원 표현', () {
    final src = _src(_cardPath);
    final body = _flat(_codeOf(_bodyOf(src, 'Widget _buildStaffingLine(')));

    test('07-a 확정 / 필요 / 대기 셋을 모두 말한다', () {
      expect(body.contains("'확정 \$safeConfirmed'"), true);
      expect(body.contains("' / 필요 \$required'"), true);
      expect(body.contains("'대기 \$pending'"), true);
    });

    test('07-b 필요 인원이 항상 표시된다 — 0이면 미설정', () {
      expect(body.contains("required == 0 ? ' / 필요 미설정'"), true);
    });

    test('07-c 확정과 대기를 합치지 않는다 (§12)', () {
      expect(body.contains('confirmed + pending'), false);
      expect(body.contains('safeConfirmed + pending'), false);
      expect(body.contains('충원'), false);
    });

    test('07-d 미충원을 정렬·요약 수치로 승격하지 않는다 (§11)', () {
      expect(body.contains('미충원'), false);
      expect(body.contains('- pending'), false);
    });

    test('07-e 세 variant가 같은 한 줄을 쓴다 (§10)', () {
      final build = _codeOf(_bodyOf(src, 'Widget build(BuildContext context)'));
      expect(
          RegExp(r'_buildStaffingLine\(').allMatches(build).length, 1,
          reason: 'variant 분기 없이 하나여야 한다');
      expect(build.contains('_buildDot('), false);
      expect(build.contains('_buildPersonnelBadge('), false);
    });

    test('07-f 확정 음수 방어가 유지된다', () {
      expect(body.contains('confirmed < 0 ? 0 : confirmed'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §15 §16 §17 §18 §28 — action
  // ══════════════════════════════════════════════════════════════
  group('08. 지원 현황 CTA', () {
    final src = _src(_cardPath);

    test('08-a 카피는 `지원 현황` — 집계 숫자를 넣지 않는다 (§15)', () {
      final body = _codeOf(_bodyOf(src, 'Widget _buildActionBar('));
      expect(body.contains("'지원 현황'"), true);
      expect(body.contains('명 보기'), false);
    });

    test('08-b 액션 바가 헤더 InkWell 바깥이다 (§28 double-trigger)', () {
      final build = _codeOf(_bodyOf(src, 'Widget build(BuildContext context)'));
      // 헤더 InkWell의 실제 괄호 범위를 잡는다.
      final headerStart = build.indexOf('InkWell(');
      expect(headerStart, greaterThan(-1));
      var depth = 0;
      var headerEnd = -1;
      for (var i = build.indexOf('(', headerStart); i < build.length; i++) {
        if (build[i] == '(') depth++;
        if (build[i] == ')') {
          depth--;
          if (depth == 0) {
            headerEnd = i;
            break;
          }
        }
      }
      expect(headerEnd, greaterThan(headerStart));
      expect(
        build.substring(headerStart, headerEnd).contains('_buildWhenLine('),
        true,
        reason: '헤더 안에 collapsed 본문이 있어야 한다',
      );
      expect(
        build.substring(headerStart, headerEnd).contains('_buildActionBar('),
        false,
        reason: 'CTA가 헤더 InkWell 안에 있으면 탭이 펼침과 함께 걸린다',
      );
      expect(build.indexOf('_buildActionBar('), greaterThan(headerEnd));
    });

    test('08-c FLEX는 화면에 보이는 그 날짜의 슬롯으로 간다 (§16)', () {
      final body = _codeOf(_bodyOf(src, '_ApplicantTarget? _applicantTarget('));
      expect(body.contains('widget.groupItem.operationalSlot'), true);
      expect(body.contains('groupTOs.first'), false);
    });

    test('08-d 슬롯 target은 기존 DayApplicantsDialog 경로를 재사용한다 (§17)', () {
      final body = _codeOf(_bodyOf(src, 'Future<void> _openApplicants('));
      expect(body.contains('_showSlotRoster(context, slot)'), true);
      final roster = _codeOf(_bodyOf(src, 'Future<void> _showSlotRoster('));
      expect(roster.contains('DayApplicantsDialog('), true);
      expect(roster.contains('filterToId: masterTO.id'), true);
    });

    test('08-e CONTRACT는 업무가 하나일 때만 확정된다 (§17)', () {
      final body = _codeOf(_bodyOf(src, '_ApplicantTarget? _applicantTarget('));
      expect(body.contains('if (details.length != 1) return null;'), true);
      expect(body.contains('details.first'), true);
    });

    test('08-f 확정할 수 없으면 펼침으로 넘긴다 — 임의 target 없음', () {
      final body = _codeOf(_bodyOf(src, 'Widget _buildActionBar('));
      expect(
        _flat(body).contains('onTap: target == null ? widget.onToggleExpand'),
        true,
      );
    });

    test('08-g work target은 기존 WorkApplicantsDialog + 권한 계약을 쓴다', () {
      final body = _flat(_codeOf(_bodyOf(src, 'Future<void> _openApplicants(')));
      expect(body.contains('WorkApplicantsDialog('), true);
      expect(
        body.contains(
            'targetPermissions: context .read<UserProvider>() .permissionsForBusiness(item.to.businessId)'),
        true,
        reason: 'WorkDetailRow와 동일한 사업장 기준 권한',
      );
      expect(body.contains('WorkforceController.notifyDataChanged('), true);
    });

    test('08-h 카드 본체 tap은 여전히 펼침이다 (§18)', () {
      final build = _flat(_codeOf(_bodyOf(src, 'Widget build(BuildContext context)')));
      expect(build.contains('InkWell( onTap: widget.onToggleExpand,'), true);
      expect(build.contains('NavigationHelper.push'), false);
    });

    test('08-i 같은 action을 ⋮ 메뉴에 또 만들지 않았다 (§19)', () {
      final menu = _codeOf(_bodyOf(src, 'void _showSingleTOMenuSheet('));
      expect(menu.contains("'지원 현황'"), false);
      // 기존 메뉴 항목은 그대로 유지
      for (final label in [
        "'인력 초대'",
        "'보낸 초대 관리'",
        "'관리용 카드명 변경'",
        "'다시 모집하기'",
      ]) {
        expect(menu.contains(label), true, reason: label);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §13 §14 §20 §23 §24 — 무회귀
  // ══════════════════════════════════════════════════════════════
  group('09. 무회귀', () {
    final src = _src(_cardPath);

    test('09-a SlotStatusBadge 라벨 copy 무변경 (§13, §14)', () {
      final badge = _src(_badgePath);
      for (final label in [
        "label: '미공개'",
        "closedLabel ?? '마감'",
        "'모집중'",
        "'예약 공개'",
        "'공개 대기'",
      ]) {
        expect(badge.contains(label), true, reason: label);
      }
      // [POSTING-V2-03S.1] '모집 완료' 문자열이 상수로 옮겨졌다. copy는 그대로다.
      expect(
          badge.contains(
              "static const String recruitmentCompleteLabel = '모집 완료';"),
          true);
      expect(
          _codeOf(src).contains('SlotStatusBadge.recruitmentCompleteLabel'),
          true);
      expect(_codeOf(src).contains("'종료됨'"), false,
          reason: 'FULL을 운영 종료로 바꾸지 않는다');
    });

    test('09-b 카드 shell radius와 expanded 구조 유지', () {
      // [POSTING-V2-03S.1] shadow와 좌측 컬러바는 이 Phase에서 의도적으로
      //   제거됐다 — 그 검증은 posting_visual_semantics_test가 소유한다.
      //   여기서는 03R.1이 의존하는 것, 즉 카드 경계와 펼침 구조만 고정한다.
      expect(src.contains('BorderRadius.circular(16)'), true);
      expect(src.contains('AnimatedSize('), true);
      expect(src.contains('_buildExpandedBodyContent('), true);
    });

    test('09-c expanded 구조 유지 (§20)', () {
      final expanded =
          _codeOf(_bodyOf(src, 'Widget _buildExpandedBodyContent('));
      expect(expanded.contains("'업무 상세'"), true);
      expect(expanded.contains('WorkDetailRow('), true);
      final multi = _codeOf(_bodyOf(src, 'Widget _buildMultiSlotLayout('));
      expect(multi.contains("'날짜별 현황'"), true);
      expect(multi.contains('_buildDateChip('), true);
      final panel = _codeOf(_bodyOf(src, 'Widget _buildDayPanel('));
      expect(panel.contains("'당일 명단 전체 보기'"), true);
    });

    test('09-d 급여는 collapsed로 올라오지 않았다 (§20)', () {
      final build = _codeOf(_bodyOf(src, 'Widget build(BuildContext context)'));
      expect(build.contains('Wage'), false);
      expect(build.contains('formatWage'), false);
    });

    test('09-e collapsed 때문에 추가 조회를 넣지 않았다 (§24)', () {
      for (final sig in [
        'String? _collapsedDateText(',
        'List<WorkDetailData> _collapsedWorkDetails(',
        'String? _collapsedRemainingText(',
        'Widget _buildStaffingLine(',
        '_ApplicantTarget? _applicantTarget(',
      ]) {
        final body = _codeOf(_bodyOf(src, sig));
        expect(body.contains('await'), false, reason: sig);
        expect(body.contains('loadTOWorkDetails'), false, reason: sig);
        expect(body.contains('firestoreService'), false, reason: sig);
      }
    });

    test('09-f 타입별 카드 component를 만들지 않았다 (§23)', () {
      expect(src.contains('class TOGroupCard'), true);
      expect(src.contains('class FlexTOCard'), false);
      expect(src.contains('class ContractTOCard'), false);
    });

    test('09-g 03Q 정렬을 건드리지 않았다', () {
      final ctrl = _codeOf(_bodyOf(
          _src(_ctrlPath), 'static List<TOGroupItem> sortForOperations('));
      expect(ctrl.contains('preOperational'), true);
      expect(ctrl.contains('id.compareTo'), true);
      for (final forbidden in ['totalConfirmed', 'shortage', 'openSlotCount']) {
        expect(ctrl.contains(forbidden), false, reason: forbidden);
      }
    });

    test('09-h operationalDate는 controller만 쓴다', () {
      final ctrl = _src(_ctrlPath);
      expect(
          RegExp(r'setOperationalDate\(').allMatches(ctrl).length, 3,
          reason: 'root load + group detail 재조회 + [R8-P4.1] 단일 공고 갱신');
      expect(_codeOf(_src(_cardPath)).contains('setOperationalDate('), false,
          reason: '카드는 읽기만 한다');
    });

    test('09-i 모델의 날짜 상태가 unknown과 미계산을 구분한다', () {
      final model = _src(_modelPath);
      expect(model.contains('bool get hasOperationalDate'), true);
      expect(model.contains('DateTime? get operationalDate'), true);
    });
  });
}
