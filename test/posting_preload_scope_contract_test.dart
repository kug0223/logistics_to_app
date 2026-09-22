// [R8-P9F] 진행중 2건을 보여주려고 종료된 52건의 슬롯까지 읽지 않는다.
//
//   DEV 실측: flex 64건 중 수동 종료 52건. 첫 진입에서 64회 슬롯 쿼리가
//   FMP 를 막고 있었다.
//
//   건너뛰어도 되는 근거는 **탭 분류가 같다**는 것 하나다.
//     슬롯 로드됨  → isToItemClosed 첫 줄 masterTO.isManualClosed → 종료
//     슬롯 미로드  → singleTO.isClosed 가 isManualClosed 포함    → 종료
//
//   이 파일은 그 등가성과, 건너뛰면 안 되는 나머지 경우를 고정한다.
//   P9B Model C: 명시적 전체 종료 > 슬롯,  파생 CLOSED/EXPIRED < 살아 있는 슬롯.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/to_model.dart';

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('파일을 찾지 못했다: $p');
  return f.readAsStringSync();
}

String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

TOModel _to({
  String type = TOType.flex,
  String status = TOStatus.active,
  bool isManualClosed = false,
  int totalRequired = 3,
  int totalConfirmed = 0,
}) =>
    TOModel(
      id: 'to-1',
      businessId: 'b',
      businessName: 'n',
      title: 't',
      creatorUID: 'c',
      type: type,
      status: status,
      isManualClosed: isManualClosed,
      totalRequired: totalRequired,
      totalConfirmed: totalConfirmed,
      createdAt: DateTime(2026, 9, 1),
    );

/// 컨트롤러의 preload 대상 술어 replica.
bool _preloads(TOModel to) => to.isFlexType && !to.isManualClosed;

void main() {
  const ctrl = 'lib/controllers/workforce_controller.dart';

  group('[R8P9F] preload 대상', () {
    test('POST-PERF-1 수동 전체 종료 FLEX → 건너뛴다', () {
      final to = _to(status: TOStatus.closed, isManualClosed: true);
      expect(_preloads(to), isFalse);
      // 슬롯 없이도 종료로 분류된다 — 그래서 건너뛸 수 있다.
      expect(to.isClosed, isTrue);
    });

    test('POST-PERF-2 자동 CLOSED + 살아 있는 슬롯 가능성 → 유지', () {
      // isManualClosed=false 인 파생 CLOSED. Model C 에서 슬롯이 우선한다.
      final to = _to(status: TOStatus.closed);
      expect(_preloads(to), isTrue,
          reason: '슬롯을 안 읽으면 살아 있는 날짜를 놓친다');
    });

    test('POST-PERF-2b 자동 EXPIRED → 유지', () {
      expect(_preloads(_to(status: TOStatus.expired)), isTrue);
    });

    test('POST-PERF-3 ACTIVE FLEX → 유지', () {
      expect(_preloads(_to()), isTrue);
    });

    test('POST-PERF-4 TO 전체 FULL + 다른 날짜 부족 → 유지', () {
      final to = _to(
          status: TOStatus.full, totalRequired: 3, totalConfirmed: 3);
      expect(to.isFull, isTrue);
      expect(to.isClosed, isTrue, reason: 'isClosed 는 FULL 을 포함한다');
      expect(_preloads(to), isTrue,
          reason: 'FULL 로 건너뛰면 남은 날짜의 모집이 사라진다');
    });

    test('POST-PERF-5 contract 는 애초에 대상이 아니다 (기존 동작)', () {
      expect(_preloads(_to(type: TOType.contract)), isFalse);
      expect(_preloads(_to(type: TOType.contract, isManualClosed: true)),
          isFalse);
    });
  });

  group('[R8P9F] 분류 등가성 — 건너뛰기의 유일한 근거', () {
    test('EQ-1 수동 종료는 슬롯 유무와 무관하게 종료다', () {
      final to = _to(status: TOStatus.closed, isManualClosed: true);
      // 슬롯 미로드 경로: TOGroupItem.isClosed → singleTO.isClosed
      expect(to.isClosed, isTrue);
      // 슬롯 로드 경로: CloseStateUtils.isToItemClosed 첫 줄이 같은 값을 본다.
      final utils = _read('lib/utils/close_state_utils.dart');
      expect(_flat(_codeOf(utils))
          .contains('if (masterTO.isManualClosed) return true;'), isTrue,
          reason: '이 줄이 사라지면 두 경로가 갈라지고 건너뛰기가 위험해진다');
    });

    test('EQ-2 자동 CLOSED 는 두 경로가 갈릴 수 있다 — 그래서 유지한다', () {
      final to = _to(status: TOStatus.closed);
      expect(to.isClosed, isTrue, reason: '슬롯 미로드면 종료로 보인다');
      // 슬롯 로드 시 isToItemClosed 는 masterTO.status 를 보지 않는다.
      final utils = _flat(_codeOf(_read('lib/utils/close_state_utils.dart')));
      expect(utils.contains('masterTO.isClosed'), isFalse,
          reason: '슬롯 경로는 status 를 보지 않으므로 살아 있는 슬롯이 이긴다');
    });
  });

  group('[R8P9F] 소비부 계약', () {
    test('SC-1 preload 술어가 isManualClosed 만 쓴다', () {
      final code = _flat(_codeOf(_read(ctrl)));
      expect(
          code.contains('_items .where((g) => g.masterTO.isFlexType && !g.masterTO.isManualClosed)'),
          isTrue);
    });

    test('SC-2 금지된 기준을 preload 술어에 쓰지 않는다 (§4)', () {
      final code = _flat(_codeOf(_read(ctrl)));
      for (final bad in [
        'g.masterTO.isClosed',
        'g.masterTO.isFull',
        'g.masterTO.rangeEnd',
      ]) {
        expect(code.contains(bad), isFalse, reason: bad);
      }
    });

    test('SC-3 펼침 lazy 경로는 그대로다', () {
      final code = _flat(_codeOf(_read(ctrl)));
      expect(code.contains('if (group.isGroupDetailLoaded || _loadingGroupIds.contains(group.id)) return;'),
          isTrue, reason: '건너뛴 그룹은 펼칠 때 읽어야 한다');
      expect(code.contains('Future<void> loadGroupDetails('), isTrue);
      expect(code.contains('Future<TOGroupRefreshOutcome> refreshGroup('), isTrue);
    });

    test('SC-4 슬롯 로드 실패는 여전히 UNKNOWN 이다 (§19)', () {
      final code = _flat(_codeOf(_read(ctrl)));
      expect(code.contains('_groupDetailErrorIds.add(group.id);'), isTrue,
          reason: '실패를 "슬롯 없음"으로 커밋하지 않는다');
    });
  });
}
