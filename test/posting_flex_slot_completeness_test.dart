// [POSTING-V2-03C.1] flex 슬롯 완전성 — TRUNCATED != SUCCESS
//
// 03C READ에서 확인된 것:
//   · slot document = 날짜 1개 (workDetails는 문서 내 배열)
//   · 두 client reader가 orderBy('date').limit(500)
//     → 501개 이상이면 **가장 미래의 날짜부터** 잘린다
//   · slotDates와 groupTOs가 같은 snapshot에서 파생되므로
//     둘이 나란히 틀린다 — 서로 어긋나지 않는다는 것이 정상의 근거가 못 된다
//   · truncation 탐지 수단이 전혀 없었다
//
// 61(실은 14)이라는 상한은 Flutter 위젯 상수일 뿐 server invariant가 아니므로
// 501+ 데이터가 존재할 가능성을 배제할 수 없다. limit을 상한+1로 두어
// "정확히 상한"과 "상한 초과"를 구분하고, 초과는 명시적 실패로 만든다.
//
// FirestoreService는 Firebase 초기화를 요구해 단위 테스트로 호출할 수 없다.
// 상한 계약은 상수/예외로, 배선은 소스로 검증한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/services/firestore_service.dart';

const _svcPath = 'lib/services/firestore_service.dart';
const _toPath = 'lib/services/firestore/to_firestore.dart';
const _selectorPath =
    'lib/screens/business_admin/to_management/widgets/to_date_selector.dart';
const _jobPostingPath = 'lib/screens/common/job_posting_screen.dart';
const _ctrlPath = 'lib/controllers/workforce_controller.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
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

/// reader 판정 replica — docs 개수만으로 성공/초과가 갈린다.
bool overflows(int docCount) => docCount > kMaxFlexSlotsPerTO;

void main() {
  // ── §10 개수 경계 ───────────────────────────────────────────────
  group('COMPLETE-01 상한 경계', () {
    test('01-a 61개 — 현재 UI가 만들 수 있는 최대치는 정상', () {
      expect(overflows(61), false);
    });

    test('01-b 500개 — 정확히 상한도 정상', () {
      expect(overflows(kMaxFlexSlotsPerTO), false,
          reason: '상한과 초과를 구분하지 못하면 500개가 정상인지 잘린 건지 알 수 없다');
    });

    test('01-c 501개 — 초과', () {
      expect(overflows(kMaxFlexSlotsPerTO + 1), true);
    });

    test('01-d probe limit이 상한보다 정확히 1 크다', () {
      final code = _flat(_codeOf(_src(_svcPath)));
      expect(code.contains('const int kMaxFlexSlotsPerTO = 500;'), true);
      expect(
          code.contains('const int _kFlexSlotProbeLimit = kMaxFlexSlotsPerTO + 1;'),
          true,
          reason: 'probe가 상한과 같으면 초과를 탐지할 수 없다');
    });
  });

  // ── §2, §3 두 reader 모두 ───────────────────────────────────────
  group('COMPLETE-02 두 reader가 같은 계약을 쓴다', () {
    test('02-a canonical snapshot이 probe limit을 쓴다', () {
      final body = _flat(_codeOf(_bodyOf(
          _src(_svcPath), 'Future<QuerySnapshot<Map<String, dynamic>>>')));
      expect(body.contains(".orderBy('date') .limit(_kFlexSlotProbeLimit) .get()"),
          true);
      expect(body.contains('.limit(500)'), false);
    });

    test('02-b loadFlexSlots가 초과를 예외로 올린다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_svcPath), 'Future<FlexSlotLoad> loadFlexSlots(')));
      expect(
          body.contains('if (snap.docs.length > kMaxFlexSlotsPerTO) { '
              'throw FlexSlotOverflowException(toId, kMaxFlexSlotsPerTO); }'),
          true);
    });

    test('02-c 초과 검사가 empty 검사보다 먼저다', () {
      final body = _codeOf(
          _bodyOf(_src(_svcPath), 'Future<FlexSlotLoad> loadFlexSlots('));
      final overflowIdx = body.indexOf('snap.docs.length > kMaxFlexSlotsPerTO');
      final emptyIdx = body.indexOf('if (snap.docs.isEmpty) return empty;');
      expect(overflowIdx, greaterThan(-1));
      expect(emptyIdx, greaterThan(overflowIdx));
    });

    test('02-d getSlots도 같은 probe/검사를 쓴다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_toPath), 'Future<List<SlotModel>> getSlots(')));
      expect(body.contains('.limit(_kFlexSlotProbeLimit)'), true);
      expect(
          body.contains('if (snap.docs.length > kMaxFlexSlotsPerTO) { '
              'throw FlexSlotOverflowException(toId, kMaxFlexSlotsPerTO); }'),
          true,
          reason: '한쪽만 guard하면 화면마다 completeness 의미가 달라진다');
      expect(body.contains('.limit(500)'), false);
    });

    test('02-e 남은 slot limit(500)이 없다', () {
      for (final p in [_svcPath, _toPath]) {
        final code = _codeOf(_src(p));
        expect(code.contains('.limit(500)'), false, reason: p);
      }
    });
  });

  // ── §4 ERROR != ZERO / TRUNCATED != SUCCESS ─────────────────────
  group('COMPLETE-03 잘린 결과를 정상으로 돌려주지 않는다', () {
    test('03-a 앞 500개를 반환하지 않는다', () {
      final svc = _codeOf(
          _bodyOf(_src(_svcPath), 'Future<FlexSlotLoad> loadFlexSlots('));
      expect(svc.contains('.take('), false);
      expect(svc.contains('sublist('), false);
      final get = _codeOf(_bodyOf(_src(_toPath), 'Future<List<SlotModel>> getSlots('));
      expect(get.contains('.take('), false);
      expect(get.contains('sublist('), false);
    });

    // [POSTING-V2-03D.1 재작성] 03C 시점에는 generic 실패가 범위 밖이라
    // `return [];` 유지가 계약이었다. 03D에서 그 return이 "조회 실패를
    // 근무일 0개로 바꾸는" 경로임이 확인되어, 이제 두 실패 모두 전파된다.
    test('03-b getSlots가 초과도 일반 실패도 삼키지 않는다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_toPath), 'Future<List<SlotModel>> getSlots(')));
      expect(body.contains('} on FlexSlotOverflowException { rethrow; }'), true,
          reason: 'TRUNCATED != SUCCESS');
      expect(body.contains('} catch (e) { debugPrint('), true);
      expect(body.contains('return []; }'), false,
          reason: 'ERROR != ZERO — 실패를 빈 목록으로 바꾸면 caller가 구분할 수 없다');
      expect(body.endsWith('rethrow; } }'), true,
          reason: '마지막 catch가 전파로 끝나야 한다');
    });

    test('03-c 예외가 어느 공고인지 말한다', () {
      const e = FlexSlotOverflowException('to_1', kMaxFlexSlotsPerTO);
      expect(e.toId, 'to_1');
      expect(e.limit, 500);
      expect(e.toString().contains('to_1'), true);
    });
  });

  // ── §8 single-snapshot 계약 유지 ────────────────────────────────
  group('COMPLETE-04 02D 구조를 유지한다', () {
    test('04-a 여전히 one query → 두 projection', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_svcPath), 'Future<FlexSlotLoad> loadFlexSlots(')));
      expect('_flexSlotSnapshot(toId)'.allMatches(body).length, 1);
      expect(body.contains('groupTOs: _slotItemsFromSnapshot(snap, model, toId),'),
          true);
      expect(
          body.contains(
              'slotDates: slotDatesFromRaw(snap.docs.map((d) => d.data())),'),
          true);
    });

    test('04-b truncated snapshot에서 두 projection이 만들어지지 않는다', () {
      // 초과 검사가 파생보다 앞서면 어느 쪽도 잘린 데이터로 만들어지지 않는다.
      final body = _codeOf(
          _bodyOf(_src(_svcPath), 'Future<FlexSlotLoad> loadFlexSlots('));
      final overflowIdx = body.indexOf('throw FlexSlotOverflowException');
      final groupIdx = body.indexOf('_slotItemsFromSnapshot(');
      final datesIdx = body.indexOf('slotDatesFromRaw(');
      expect(overflowIdx, greaterThan(-1));
      expect(groupIdx, greaterThan(overflowIdx));
      expect(datesIdx, greaterThan(overflowIdx));
    });

    test('04-c pagination을 도입하지 않았다 (§11)', () {
      for (final p in [_svcPath, _toPath]) {
        final code = _codeOf(_src(p));
        expect(code.contains('startAfterDocument'), false, reason: p);
        expect(code.contains('startAfter('), false, reason: p);
      }
    });

    test('04-d limit을 제거하지 않았다 (§11)', () {
      final body = _flat(_codeOf(_bodyOf(
          _src(_svcPath), 'Future<QuerySnapshot<Map<String, dynamic>>>')));
      expect(body.contains('.limit('), true, reason: '무제한 read 전환 금지');
    });
  });

  // ── §5 caller 회귀 ──────────────────────────────────────────────
  group('COMPLETE-05 caller가 초과를 empty로 오인하지 않는다', () {
    test('05-a Posting canonical — 기존 group detail error 경로 재사용', () {
      // loadFlexSlots가 rethrow → controller의 TO별 catch → _groupDetailErrorIds
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load('));
      expect(body.contains('_groupDetailErrorIds.add(group.id);'), true);
      final detail =
          _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> loadGroupDetails('));
      expect(detail.contains('_groupDetailErrorIds.add(group.id);'), true);
    });

    test('05-b 토스트로 실패를 알리는 caller 3곳은 그대로 동작한다', () {
      // getSlots가 rethrow하면 각 caller의 기존 catch가 잡는다.
      for (final p in [
        'lib/screens/business_admin/dialogs/slot_batch_select_dialog.dart',
        'lib/screens/business_admin/to_management/edit_to_screen.dart',
        'lib/widgets/admin/cards/admin_to_group_card.dart',
      ]) {
        final code = _codeOf(_src(p));
        expect(code.contains('getSlots('), true, reason: p);
        expect(code.contains('ToastHelper.showError'), true, reason: p);
      }
    });

    // [POSTING-V2-03D.1 재작성] 03C에서는 generic 실패가 범위 밖이라
    // `catch { debugPrint; }` 유지가 계약이었다. 이제 같은 실패 상태로 합류한다.
    test('05-c 삼키던 caller가 두 실패를 모두 기록한다', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_jobPostingPath), 'Future<void> _loadSlots(')));
      expect(body.contains('} on FlexSlotOverflowException catch (e) {'), true);
      expect(body.contains('_allSlots = [];'), true,
          reason: '잘린 목록을 화면에 남기지 않는다');
      expect(body.contains('ToastHelper.showError('), true);
      expect(body.contains("} catch (e) { debugPrint('⚠️ 슬롯 로드 실패: \$e'); }"),
          false,
          reason: '일반 실패만 무표시로 남으면 "근무 날짜 없음"과 같은 화면이 된다');
      expect('_slotLoadError = true;'.allMatches(body).length, 2,
          reason: 'overflow · 일반 실패 두 경로 모두');
    });
  });

  // ── EMPTY != OVERFLOW (지원자 화면) ─────────────────────────────
  group('COMPLETE-08 overflow가 true empty로 표현되지 않는다', () {
    test('08-a 별도 실패 상태가 있다', () {
      final code = _codeOf(_src(_jobPostingPath));
      expect(code.contains('bool _slotLoadError = false;'), true,
          reason: '_allSlots=[] 만으로는 "근무일 0개"와 구분되지 않는다');
      final load = _flat(
          _codeOf(_bodyOf(_src(_jobPostingPath), 'Future<void> _loadSlots(')));
      // 매 로드 시작 시 초기화되고, 실패 경로에서 세워진다
      // (03C: overflow만 / 03D.1: 일반 조회 실패 포함)
      expect(load.contains('_slotLoadError = false;'), true);
      expect(load.contains('_slotLoadError = true;'), true);
    });

    test('08-b 실패 분기가 empty 분기보다 먼저 평가된다', () {
      final code = _codeOf(_src(_jobPostingPath));
      final errIdx = code.indexOf('if (_to!.isFlexType && _slotLoadError)');
      final emptyIdx = code.indexOf('else if (_to!.isFlexType && _allSlots.isEmpty)');
      expect(errIdx, greaterThan(-1), reason: '실패 분기가 없다');
      expect(emptyIdx, greaterThan(errIdx),
          reason: 'empty가 먼저면 overflow가 "날짜 없음"으로 표시된다');
    });

    test('08-c toast가 유일한 신호가 아니다 — 화면에 남는다', () {
      final body = _flat(_codeOf(_bodyOf(
          _src(_jobPostingPath), 'Widget _buildSlotLoadErrorMessage(')));
      expect(body.contains("'근무 일정을 불러오지 못했습니다.\\n잠시 후 다시 시도해주세요.'"),
          true);
      // 기존 앱 error language 재사용 (카드 group detail error와 같은 문구 계열)
      final card =
          _codeOf(_src('lib/widgets/admin/cards/admin_to_group_card.dart'));
      expect(card.contains("message: '근무 일정을 불러오지 못했습니다',"), true);
    });

    test('08-d true empty 문구는 그대로다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_jobPostingPath), 'Widget _buildNoSlotsMessage(')));
      expect(body.contains("'현재 선택 가능한 근무 날짜가 없습니다.'"), true);
      expect(body.contains('Icons.event_busy_outlined'), true);
      // 두 화면이 서로 다른 것을 말한다
      final err = _flat(_codeOf(_bodyOf(
          _src(_jobPostingPath), 'Widget _buildSlotLoadErrorMessage(')));
      expect(err.contains('Icons.cloud_off_rounded'), true);
      expect(err.contains('선택 가능한 근무 날짜가 없습니다'), false);
    });

    test('08-e slot 의존 지원 action이 차단된다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_jobPostingPath), 'Future<void> _showConfirmAndApply(')));
      expect(
          body.contains('if (_to!.isFlexType && _slotLoadError) { '
              "ToastHelper.showError('근무 일정을 불러오지 못했습니다'); return; }"),
          true,
          reason: '_allSlots가 비어도 _currentWorkDetails 폴백으로 지원이 성립했다');
      // 차단이 items 수집보다 앞이어야 한다
      final guardIdx = body.indexOf('_slotLoadError) {');
      final itemsIdx = body.indexOf('final List<({SlotModel? slot, WorkDetailModel work})> items');
      expect(guardIdx, greaterThan(-1));
      expect(itemsIdx, greaterThan(guardIdx));
    });

    test('08-f 공고 전체를 unusable하게 만들지 않았다', () {
      final code = _codeOf(_src(_jobPostingPath));
      // 헤더·업무 섹션·하단바 조건은 그대로 (flex slot 의존 action만 차단)
      expect(code.contains('_isLoading || _to == null ? null : _buildBottomBar(context)'),
          true);
      expect(code.contains('_buildPostingHeader(context),'), true);
      expect(code.contains('_buildWorkSection(context),'), true);
    });

    // [POSTING-V2-03D.1 재작성] 03C에서는 "일반 실패는 다음 phase 범위"라는
    // 뜻으로 현상 유지를 고정했다. 03D가 그 범위를 열었으므로, 이제 같은
    // 테스트가 "overflow 전용 UI를 따로 만들지 않았다"를 지킨다.
    test('08-g overflow 전용 UI를 따로 만들지 않았다 (§8)', () {
      final code = _codeOf(_src(_jobPostingPath));
      // 실패 상태·문구·차단은 하나로 공유된다 — overflow 전용 분기가 없다
      expect('bool _slotLoadError'.allMatches(code).length, 1);
      expect(code.contains('_overflowError'), false);
      expect('Widget _buildSlotLoadErrorMessage('.allMatches(code).length, 1);
      final body = _flat(
          _codeOf(_bodyOf(_src(_jobPostingPath), 'Future<void> _loadSlots(')));
      expect("ToastHelper.showError('근무 일정을 불러오지 못했습니다')".allMatches(body).length,
          2,
          reason: 'overflow · 일반 실패가 같은 문구를 쓴다');
    });
  });

  // ── §1, §6 60일/14개의 성격과 서버 결정 ─────────────────────────
  group('COMPLETE-06 write contract', () {
    test('06-a flex 날짜 selector 상한이 그대로다', () {
      final code = _codeOf(_src(_selectorPath));
      expect(code.contains('static const int _maxFutureDays = 60;'), true);
      expect(
          code.contains(
              'final isTooFar = date.isAfter(today.add(const Duration(days: _maxFutureDays)));'),
          true);
      // 과거·초과 날짜는 탭 자체가 차단된다
      expect(
          _flat(code).contains(
              'onTap: (isPast || isTooFar) ? null : () => _handleDateTap(date, today),'),
          true);
    });

    test('06-b 개수 상한과 사용자 문구도 그대로다', () {
      final code = _codeOf(_src(_selectorPath));
      expect(code.contains('this.maxSelectableDays = 14,'), true);
      expect(
          code.contains(
              "ToastHelper.showWarning('최대 \${widget.maxSelectableDays}일까지 선택 가능합니다')"),
          true);
    });

    test('06-c 서버에 임의의 61/14 cap을 추가하지 않았다 (CASE B)', () {
      // 상한 값이 위젯 생성자 기본값이고 위젯마다 다르며(14 vs 30) 정책 레지스트리에
      // 근거가 없다 → CLIENT UX LIMIT. 서버 canonical로 승격하지 않는다.
      final fns = _src('functions/src/index.ts');
      expect(fns.contains('dates.length > 61'), false);
      expect(fns.contains('dates.length > 14'), false);
      expect(fns.contains('maxSelectableDays'), false);
      // 기존 dates 검증(비어있음·과거·중복)은 그대로
      expect(
          fns.contains(
              'if (!Array.isArray(dates) || dates.length === 0) throw new HttpsError("invalid-argument", "dates 필요");'),
          true);
      expect(fns.contains('const uniqueDates: string[] = [...new Set(dates as string[])];'),
          true);
    });

    test('06-d 두 위젯의 기본값이 달라 단일 정책 상수가 아니다', () {
      final selector = _codeOf(_src(_selectorPath));
      final carrot = _codeOf(_src('lib/widgets/calendar/carrot_style_calendar.dart'));
      expect(selector.contains('this.maxSelectableDays = 14,'), true);
      expect(carrot.contains('this.maxSelectableDays = 30,'), true);
    });
  });

  // ── §9 비용 ─────────────────────────────────────────────────────
  group('COMPLETE-07 정상 공고의 read cost가 늘지 않는다', () {
    test('07-a query 수는 그대로 1', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_svcPath), 'Future<FlexSlotLoad> loadFlexSlots(')));
      expect('await _flexSlotSnapshot('.allMatches(body).length, 1);
    });

    test('07-b ceiling만 501 — 실제 읽히는 문서 수는 데이터가 정한다', () {
      // limit은 상한이지 요구치가 아니다. 14개짜리 공고는 여전히 14개만 읽는다.
      expect(_kFlexSlotProbeLimitFromSource(), 501);
    });

    test('07-c 서버 slot 조회는 건드리지 않았다', () {
      final fns = _src('functions/src/index.ts');
      expect(fns.contains('collection("slots").get()'), true,
          reason: '서버는 limit이 없고 이번 범위가 아니다');
    });
  });
}

/// 소스에서 probe limit 값을 읽어온다 (private 상수라 직접 참조 불가).
int _kFlexSlotProbeLimitFromSource() {
  final code = _flat(_codeOf(_src(_svcPath)));
  expect(code.contains('const int _kFlexSlotProbeLimit = kMaxFlexSlotsPerTO + 1;'),
      true);
  return kMaxFlexSlotsPerTO + 1;
}
