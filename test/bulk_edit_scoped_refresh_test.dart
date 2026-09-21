// [R8-P4.1] 날짜 하나를 고쳤는데 목록 전체를 다시 읽고 펼침이 다 접혔다.
//
//   일괄수정은 편집한 공고의 슬롯과 totalRequired만 바꾼다. 그런데 저장 후
//   복귀하면 _reload()가 돌면서
//     · callableGetAdminTOs 로 사업장의 **모든** 공고를 다시 읽고
//     · 모든 flex 공고의 슬롯을 다시 읽고
//     · _expandedGroups/_expandedTOs 를 비웠다
//   DEV 실측으로 전체 재조회는 서버 기준 ~890ms(목록 716 + 슬롯 178),
//   공고 하나는 ~60ms(TO 33 + 슬롯 30)다.
//
//   영향 범위가 공고 하나로 확정된 경로만 그 공고를 다시 읽게 바꿨다.
//   값은 서버에서 다시 읽는다 — 보낸 payload로 화면을 지어내지 않는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/controllers/workforce_controller.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';

const _ctrlPath = 'lib/controllers/workforce_controller.dart';
const _listPath =
    'lib/screens/business_admin/workforce_management/workforce_list_view.dart';
const _cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';

String _read(String p) => File(p).readAsStringSync();

/// 주석으로 시작하는 줄(`//`·`///`)을 지운다 — 표지는 코드에서만 찾는다.
String _codeOf(String raw) => raw
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 그룹 수집 시점에도 불리므로 expect 대신 예외로 실패시킨다.
String _sliceOf(String raw, String from, String to) {
  final i = raw.indexOf(from);
  if (i < 0) throw StateError('시작 표지를 찾지 못함: $from');
  final j = raw.indexOf(to, i + from.length);
  if (j < 0) throw StateError('끝 표지를 찾지 못함: $to');
  return raw.substring(i, j);
}

void main() {
  final ctrl = _codeOf(_read(_ctrlPath));
  final list = _codeOf(_read(_listPath));
  final card = _codeOf(_read(_cardPath));
  // 표지는 코드 선언으로 잡는다 — _codeOf가 주석 줄을 지우므로 주석은 표지가 될 수 없다.
  final refreshGroup = _sliceOf(ctrl,
      'Future<TOGroupRefreshOutcome> refreshGroup(',
      'final Map<String, int> _groupRefreshSeq');
  final refreshEdited = _sliceOf(list,
      'Future<void> _refreshEditedTO(String toId) async {',
      'List<TOGroupItem> _getFilteredItems(');

  // ── BR-1 / BR-2 진입 경로 ────────────────────────────────────
  group('BR-1·BR-2 수정 경로가 scoped 갱신을 쓴다', () {
    test('BR-10 카드에 공고 단위 갱신 콜백이 있다', () {
      expect(card.contains('final void Function(String toId)? onTOChanged;'), true);
    });

    test('BR-1 단일 슬롯 수정이 scoped 경로를 탄다', () {
      final branch = _sliceOf(card,
          'destination: AdminEditTOScreen(to: masterTO, slot: widget.calendarSlot!.slot)',
          'destination: AdminEditTOScreen(to: masterTO),');
      expect(_flat(branch).contains('_notifyTOChanged(masterTO.id);'), true);
      expect(_flat(branch).contains('widget.onChanged();'), false);
    });

    test('BR-2 일괄수정이 scoped 경로를 탄다', () {
      final branch = _sliceOf(card,
          'destination: AdminEditTOScreen(to: masterTO, batchSlots: editSlots)',
          'break;');
      expect(_flat(branch).contains('_notifyTOChanged(masterTO.id);'), true);
      expect(_flat(branch).contains('widget.onChanged();'), false);
    });

    test('BR-2b 콜백이 없으면 기존 전체 갱신으로 떨어진다', () {
      final f = _flat(_sliceOf(card, 'void _notifyTOChanged(String toId) {',
          'late List<TOItem> _targetTOs;'));
      expect(f.contains('if (scoped != null) { scoped(toId); } else { widget.onChanged(); }'),
          true);
    });

    test('BR-2c 목록 화면이 그 콜백을 scoped 갱신에 연결한다', () {
      expect(_flat(list).contains('onTOChanged: _refreshEditedTO,'), true);
    });
  });

  // ── BR-8 unrelated TO 재조회 없음 ────────────────────────────
  group('BR-8 관련 없는 공고를 다시 읽지 않는다', () {
    test('BR-80 scoped 갱신은 목록 전체 조회를 부르지 않는다', () {
      // 전체 목록 조회(getTOGroupItemsLight)·전역 캐시 flush가 들어오면
      // scoped가 아니게 된다.
      expect(refreshGroup.contains('getTOGroupItemsLight'), false);
      expect(refreshGroup.contains('invalidateListCache'), false);
      expect(refreshGroup.contains('_requestLoad'), false);
      expect(refreshGroup.contains('load(context)'), false);
    });

    test('BR-81 읽는 것은 그 공고의 문서와 슬롯뿐이다', () {
      expect(refreshGroup.contains('_service.getTOOrFailure(toId)'), true);
      expect(refreshGroup.contains('_service.loadFlexSlots(toId, masterTO: fresh)'), true);
    });

    test('BR-82 기존 reader를 재사용한다 — 새 reader를 만들지 않았다', () {
      // 두 메서드 모두 이 Phase 이전부터 있던 경로다.
      expect(ctrl.contains('_service.loadFlexSlots('), true);
      expect(_read('lib/services/firestore/to_firestore.dart')
          .contains('Future<({TOModel? to, bool failed})> getTOOrFailure('), true);
    });

    test('BR-83 목록 화면은 scoped 갱신에서 _reload를 부르지 않는다', () {
      final body = refreshEdited;
      expect(body.contains('_reload()'), false);
      expect(body.contains('controller.refreshGroup(toId)'), true);
    });
  });

  // ── BR-3 / BR-4 펼침 상태 유지 ───────────────────────────────
  group('BR-3·BR-4 펼침 상태가 유지된다', () {
    test('BR-30 scoped 갱신은 펼침 집합을 비우지 않는다', () {
      final body = refreshEdited;
      expect(body.contains('_expandedGroups.clear()'), false);
      expect(body.contains('_expandedTOs.clear()'), false);
      expect(body.contains('_clearReveal()'), false);
    });

    test('BR-31 _reload는 여전히 비운다 — 새로고침 의미는 그대로다', () {
      final body = _sliceOf(list, 'Future<void> _reload() async {', 'final up =');
      expect(body.contains('_expandedGroups.clear();'), true);
      expect(body.contains('_expandedTOs.clear();'), true);
    });

    test('BR-4 key가 유지되어야 펼침이 살아남는다 — 같은 toId 자리에 넣는다', () {
      expect(refreshGroup.contains('final at = _items.indexWhere((g) => g.id == toId);'), true);
      expect(refreshGroup.contains('next[at] = rebuilt;'), true);
    });

    test('BR-41 삭제된 공고는 그 key만 정리한다', () {
      final body = _sliceOf(list,
          'case TOGroupRefreshOutcome.removed:', 'case TOGroupRefreshOutcome.notInList:');
      expect(body.contains('_expandedGroups.remove(toId);'), true);
      expect(body.contains('_expandedGroups.clear()'), false);
    });
  });

  // ── BR-5 / BR-6 canonical state ──────────────────────────────
  group('BR-5·BR-6 서버 값으로 갱신한다', () {
    test('BR-50 client가 값을 지어내지 않는다', () {
      // payload로 local state를 만들면 canonical truth가 아니다(§10).
      expect(refreshGroup.contains('totalRequired +='), false);
      expect(refreshGroup.contains('updateGroupStats('), false);
      expect(refreshGroup.contains('workDetails ='), false);
    });

    test('BR-51 공고 모델을 새로 읽어 그대로 쓴다', () {
      expect(refreshGroup.contains('TOGroupItem(singleTO: fresh)'), true);
    });

    test('BR-6 슬롯과 날짜를 새 snapshot에서 채운다', () {
      final f = _flat(refreshGroup);
      expect(f.contains('rebuilt.setGroupTOs(loaded.groupTOs);'), true);
      expect(f.contains('rebuilt.setSlotDates(loaded.slotDates);'), true);
    });

    test('BR-61 정렬은 로컬에서만 다시 한다 — 네트워크 없음', () {
      expect(refreshGroup.contains('_sortItemsForOperations();'), true);
    });

    test('BR-62 뷰의 필터 캐시가 무효화되도록 새 list 인스턴스로 교체한다', () {
      // identical(items, _lastCachedItems) 로 캐시를 판단하므로
      // 제자리 수정만 하면 낡은 목록이 그대로 그려진다.
      expect(refreshGroup.contains('final next = List<TOGroupItem>.of(_items);'), true);
      expect(refreshGroup.contains('_items = next;'), true);
    });
  });

  // ── BR-7 저장 성공 / 갱신 실패 구분 ──────────────────────────
  group('BR-7 갱신 실패를 저장 실패로 말하지 않는다', () {
    test('BR-70 결과가 구분되어 돌아온다', () {
      for (final v in ['refreshed', 'removed', 'failed', 'superseded', 'notInList']) {
        expect(ctrl.contains('  $v,'), true, reason: '결과 값 누락: $v');
      }
    });

    test('BR-71 실패 문구가 저장 성공을 먼저 말한다', () {
      final body = _sliceOf(list,
          'case TOGroupRefreshOutcome.failed:', 'break;');
      expect(body.contains('저장했습니다.'), true);
      expect(body.contains('저장에 실패'), false);
      expect(body.contains('수정에 실패'), false);
    });

    test('BR-72 실패해도 목록을 비우지 않는다 (ERROR ≠ EMPTY)', () {
      expect(refreshGroup.contains('_items = []'), false);
      expect(refreshGroup.contains('setGroupTOs([])'), false);
      // 읽기 실패와 삭제를 구분한 뒤에만 목록에서 뺀다.
      expect(_flat(refreshGroup)
          .contains('if (result.failed) return TOGroupRefreshOutcome.failed;'), true);
    });

    test('BR-73 없는 문서와 못 읽은 문서를 구분하는 reader를 쓴다', () {
      // getTO()는 둘 다 null로 만든다 — 그걸 쓰면 네트워크 오류가 "삭제됨"이 된다.
      expect(refreshGroup.contains('_service.getTO(toId)'), false);
      expect(refreshGroup.contains('getTOOrFailure'), true);
    });
  });

  // ── 경쟁 상태 / 구조 제약 ────────────────────────────────────
  group('BR-x 경쟁 상태와 구조 제약', () {
    test('BR-x1 세대 토큰으로 늦게 온 응답이 최신 결과를 덮지 않는다', () {
      final f = _flat(refreshGroup);
      expect(f.contains('final seq = (_groupRefreshSeq[toId] ?? 0) + 1;'), true);
      expect(f.contains('_groupRefreshSeq[toId] = seq;'), true);
      expect(f.contains('bool stale() => (_groupRefreshSeq[toId] ?? 0) != seq;'), true);
      // 두 await 뒤 모두에서 확인한다.
      expect('stale()'.allMatches(refreshGroup).length >= 3, true);
    });

    test('BR-x2 dispose 이후 notify하지 않는다', () {
      expect(refreshGroup.contains('if (_disposed || stale())'), true);
      expect(refreshGroup.contains('if (!_disposed) notifyListeners();'), true);
    });

    test('BR-x3 listener·polling을 새로 만들지 않았다 (§33)', () {
      expect(refreshGroup.contains('snapshots('), false);
      expect(refreshGroup.contains('Timer'), false);
      expect(refreshGroup.contains('Stream'), false);
    });

    test('BR-x4 전체 shell/탭 갱신을 부르지 않는다 (§34)', () {
      expect(refreshGroup.contains('notifyDataChanged'), false);
      final body = refreshEdited;
      expect(body.contains('notifyDataChanged'), false);
    });

    test('BR-9 권한 판정을 클라이언트에서 만들지 않는다 (§31)', () {
      // scoped 갱신은 읽기만 한다 — 쓰기·권한 분기가 없다.
      for (final w in ['canManageTo', 'isAdminOf', 'update(', 'set(', 'delete(']) {
        expect(refreshGroup.contains(w), false, reason: '읽기 전용이어야 한다: $w');
      }
    });
  });

  // ── 순수 함수 회귀 — 정렬은 그대로다 ─────────────────────────
  group('BR-s 로컬 재정렬 회귀', () {
    test('BR-s1 항목 2개 미만이면 같은 인스턴스를 돌려준다', () {
      final empty = <TOGroupItem>[];
      expect(
        identical(
          WorkforceController.sortForOperations(empty,
              detailErrorIds: <String>{}, now: DateTime(2026, 1, 1)),
          empty,
        ),
        true,
      );
    });
  });
}
