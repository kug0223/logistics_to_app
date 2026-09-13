// [POSTING-V2-02D.1] flex 슬롯 single snapshot
//
// 02D READ에서 확인된 문제:
//   공고 탭 root load가 flex TO 하나당 tos/{toId}/slots 를 두 번 읽었다.
//     getFlexTOSlotDates  — 날짜만 쓰지만 Dart SDK에 projection이 없어 문서 전량 전송
//     _preloadFlexTOSlots — 같은 문서를 다시 읽어 SlotModel로 파싱
//   두 번째 결과가 첫 번째의 slotDates까지 덮어썼으므로 절반이 순수 낭비였다.
//
// 단순히 slotDates = groupTOs.map(date) 로 합치면 안 된다:
//   SlotModel.fromMap은 createdAt을 필수로 요구한다. date는 멀쩡한데 createdAt이
//   없는 레거시 슬롯은 모델 파싱에서 탈락하고, 그 슬롯의 날짜는 마감 판정과
//   날짜 필터의 폴백 truth다. 성능 수정 때문에 사라지면 안 된다.
//
// 해법: 한 snapshot에서 두 projection.
//   slotDates — raw 문서에서 직접 파생 (관대)
//   groupTOs  — 기존 SlotModel 파서 그대로 (엄격)
//
// 파싱 계약은 순수 단위 테스트로, 배선은 소스로 검증한다
// (FirestoreService는 Firebase 초기화를 요구해 widget/통합 테스트가 불가능하다).

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/services/firestore_service.dart';

const _svcPath = 'lib/services/firestore_service.dart';
const _ctrlPath = 'lib/controllers/workforce_controller.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// `//` 주석 줄 제거 — 주석 문자열이 코드로 오탐되는 것을 막는다.
String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// 공백 1칸 평탄화 — 들여쓰기/줄바꿈에 의존하지 않는 비교용.
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

/// 정상 슬롯 raw 문서.
Map<String, dynamic> _rawSlot(
  DateTime date, {
  bool withCreatedAt = true,
  Object? dateOverride,
  bool omitDate = false,
}) =>
    {
      if (!omitDate) 'date': dateOverride ?? Timestamp.fromDate(date),
      'status': 'open',
      'confirmedCount': 0,
      'pendingCount': 0,
      if (withCreatedAt) 'createdAt': Timestamp.fromDate(date),
    };

void main() {
  // ── §2, §3 두 projection은 같은 snapshot·다른 tolerance ─────────
  group('FLEX-SINGLE-READ-02 레거시 createdAt 슬롯의 날짜가 보존된다', () {
    final d = DateTime(2026, 9, 20);

    test('02-a createdAt 없는 슬롯도 slotDates에 포함된다', () {
      final raw = _rawSlot(d, withCreatedAt: false);
      expect(raw.containsKey('createdAt'), false);
      final dates = FirestoreService.slotDatesFromRaw([raw]);
      expect(dates.length, 1);
      expect(dates.first, d);
    });

    test('02-b 같은 슬롯은 SlotModel 파싱에서 탈락한다 (기존 계약 유지)', () {
      // §5 — 이 계약을 완화하는 방식으로 해결하지 않는다.
      expect(
        () => SlotModel.fromMap(
            _rawSlot(d, withCreatedAt: false), 'slot1', 'to1'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('02-c 따라서 slotDates는 groupTOs에서 파생될 수 없다', () {
      // 두 projection이 갈라지는 지점을 명시적으로 고정한다.
      final raws = [
        _rawSlot(DateTime(2026, 9, 20)),
        _rawSlot(DateTime(2026, 9, 21), withCreatedAt: false), // 레거시
      ];
      final dates = FirestoreService.slotDatesFromRaw(raws);
      expect(dates.length, 2, reason: 'raw projection이 레거시 슬롯을 잃었다');

      final parsed = raws
          .map((r) {
            try {
              return SlotModel.fromMap(r, 'x', 'to1');
            } catch (_) {
              return null;
            }
          })
          .whereType<SlotModel>()
          .toList();
      expect(parsed.length, 1);
      // DATE_VISIBILITY_REGRESSION = NO 의 근거
      expect(dates.length, greaterThan(parsed.length));
    });

    test('02-d 소스가 groupTOs 기반 파생을 쓰지 않는다', () {
      final code = _flat(_codeOf(_src(_svcPath)));
      expect(
          code.contains(
              'slotDates: slotDatesFromRaw(snap.docs.map((d) => d.data())),'),
          true);
      // controller의 어떤 경로도 slotDates를 파싱된 item에서 파생하지 않는다
      expect(_flat(_codeOf(_src(_ctrlPath))).contains('.slotDate)'), false,
          reason: 'slotDates를 groupTOs에서 파생하면 레거시 날짜가 사라진다');
      expect(
          '_service.loadFlexSlots('
              .allMatches(_codeOf(_src(_ctrlPath)))
              .length,
          2,
          reason: 'root load와 펼침/재시도 두 경로 모두 single-snapshot loader를 써야 한다');
    });
  });

  // ── §4, §34 malformed 문서 격리 ─────────────────────────────────
  group('FLEX-SINGLE-READ-04 malformed 슬롯 하나가 TO 전체를 날리지 않는다', () {
    test('04-a date 타입이 잘못된 문서 하나만 건너뛴다', () {
      final raws = [
        _rawSlot(DateTime(2026, 9, 20)),
        _rawSlot(DateTime(2026, 9, 21), dateOverride: '2026-09-21'), // String
        _rawSlot(DateTime(2026, 9, 22)),
      ];
      final dates = FirestoreService.slotDatesFromRaw(raws);
      expect(dates.length, 2);
      expect(dates, [DateTime(2026, 9, 20), DateTime(2026, 9, 22)]);
    });

    test('04-b date가 없는 문서 하나만 건너뛴다', () {
      final raws = [
        _rawSlot(DateTime(2026, 9, 20)),
        _rawSlot(DateTime(2026, 9, 21), omitDate: true),
      ];
      expect(FirestoreService.slotDatesFromRaw(raws).length, 1);
    });

    test('04-c 캐스트가 아니라 타입 검사를 쓴다', () {
      // `as Timestamp?` 였다면 String 하나가 TypeError를 던져
      // 옛 구현처럼 TO 전체(또는 chunk 전체)의 날짜가 사라진다.
      final code = _flat(_codeOf(_bodyOf(
          _src(_svcPath), 'static List<DateTime> slotDatesFromRaw(')));
      expect(code.contains('if (raw is Timestamp) dates.add('), true);
      expect(code.contains("as Timestamp"), false);
    });

    test('04-d 옛 date path의 붕괴 방식은 더 이상 존재하지 않는다', () {
      final code = _codeOf(_src(_svcPath));
      expect(code.contains("(d.data()['date'] as Timestamp?)"), false);
    });
  });

  // ── §35 genuine empty ──────────────────────────────────────────
  group('FLEX-SINGLE-READ-05 실제 0건과 실패를 구분한다', () {
    test('05-a 슬롯 0개는 빈 결과이고 예외가 아니다', () {
      expect(FirestoreService.slotDatesFromRaw(const []), isEmpty);
    });

    test('05-b loadFlexSlots가 빈 snapshot을 정상 반환한다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_svcPath), 'Future<FlexSlotLoad> loadFlexSlots(')));
      expect(
          body.contains(
              'const empty = (groupTOs: <TOItem>[], slotDates: <DateTime>[]);'),
          true);
      expect(body.contains('if (snap.docs.isEmpty) return empty;'), true);
    });

    test('05-c 조회 실패는 rethrow — 빈 결과로 삼키지 않는다 (§13)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_svcPath), 'Future<FlexSlotLoad> loadFlexSlots(')));
      expect(body.contains('rethrow;'), true);
      expect(body.contains('return {};'), false,
          reason: 'getFlexTOSlotDates의 ERROR==EMPTY 의미가 되살아났다');
    });
  });

  // ── §1, §31 query 1회 ──────────────────────────────────────────
  group('FLEX-SINGLE-READ-01 flex TO당 slot query는 1회다', () {
    test('01-a flex slot 목록 query가 한 곳에만 정의된다', () {
      final code = _flat(_codeOf(_src(_svcPath)));
      // 슬롯 목록 query(orderBy+limit)는 _flexSlotSnapshot 하나뿐이어야 한다.
      // 단건 .doc(slotId) 접근이나 cascade 평가용 query는 이 대상이 아니다.
      expect("collection('slots') .orderBy('date')".allMatches(code).length, 1,
          reason: 'slot 목록 query가 둘 이상 — 중복 구현이 다시 생겼다');
      // [POSTING-V2-03C.1] limit 리터럴이 상한+1 상수로 바뀌었다.
      //   고정해야 할 것은 "정렬된 단일 bounded query"이지 숫자 자체가 아니다.
      final body = _flat(_codeOf(_bodyOf(
          _src(_svcPath), 'Future<QuerySnapshot<Map<String, dynamic>>>')));
      expect(
          body.contains(".orderBy('date') .limit(_kFlexSlotProbeLimit) .get()"),
          true);
    });

    test('01-b root load가 flex TO별로 loadFlexSlots를 정확히 한 번 부른다', () {
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load('));
      expect('_service.loadFlexSlots('.allMatches(body).length, 1);
    });

    test('01-c 펼침/재시도도 같은 loader를 쓴다 — 두 구현으로 갈라지지 않는다 (§7)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_ctrlPath), 'Future<void> loadGroupDetails(')));
      expect(
          body.contains('_service.loadFlexSlots(group.id, masterTO: group.masterTO)'),
          true);
      // caller 0이 된 옛 wrapper는 남기지 않는다
      expect(_codeOf(_src(_svcPath)).contains('loadGroupTOsLight'), false);
      expect(_codeOf(_src(_ctrlPath)).contains('loadGroupTOsLight'), false);
    });

    test('01-d SlotModel.fromMap 호출 지점이 하나뿐이다', () {
      final code = _codeOf(_src(_svcPath));
      expect('SlotModel.fromMap('.allMatches(code).length, 1);
    });
  });

  // ── §8, §9, §19, §40 낡은 경로 제거 ────────────────────────────
  group('FLEX-SINGLE-READ-06 중복 경로가 남아 있지 않다', () {
    test('06-a getFlexTOSlotDates가 제거됐다', () {
      // 주석에는 폐기 경위를 남긴다 — 실행 코드에만 없으면 된다.
      expect(_codeOf(_src(_svcPath)).contains('getFlexTOSlotDates'), false);
      expect(_codeOf(_src(_ctrlPath)).contains('getFlexTOSlotDates'), false);
    });

    test('06-b _preloadFlexTOSlots가 제거됐다', () {
      expect(_codeOf(_src(_ctrlPath)).contains('_preloadFlexTOSlots'), false);
    });

    test('06-c whereIn 30개 chunking 잔재가 제거됐다', () {
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load('));
      expect(body.contains('chunkSize'), false);
      expect(body.contains('chunks'), false);
      expect(body.contains('sublist('), false);
    });

    test('06-d 프로젝트 어디에도 남은 caller가 없다', () {
      final hits = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final code = _codeOf(f.readAsStringSync());
        if (code.contains('getFlexTOSlotDates') ||
            code.contains('loadGroupTOsLight')) {
          hits.add(f.path);
        }
      }
      expect(hits, isEmpty, reason: '남은 caller: $hits');
    });
  });

  // ── §10 blocking contract ──────────────────────────────────────
  group('FLEX-SINGLE-READ-07 첫 렌더 전에 slot을 확보한다', () {
    test('07-a flex slot 로드가 await된다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load(')));
      expect(body.contains('await Future.wait(flexGroups.map((group) async {'),
          true);
    });

    test('07-b fire-and-forget 사전로드가 남아 있지 않다', () {
      final code = _codeOf(_src(_ctrlPath));
      expect(code.contains('.then((toItems)'), false);
      // isLoading 해제(=첫 렌더) 이전에 끝나야 한다
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load('));
      final flexIdx = body.indexOf('_service.loadFlexSlots(');
      final doneIdx = body.indexOf('_isLoading = false;');
      expect(flexIdx, greaterThan(-1));
      expect(doneIdx, greaterThan(flexIdx),
          reason: 'slot 로드가 첫 렌더 이후로 밀렸다');
    });
  });

  // ── §11, §12, §33, §36 TO별 error isolation ────────────────────
  group('FLEX-SINGLE-READ-03 TO 하나의 실패가 목록 전체를 죽이지 않는다', () {
    test('03-a TO별 try/catch가 group detail error로 연결된다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load(')));
      expect(body.contains('_groupDetailErrorIds.add(group.id);'), true);
    });

    test('03-b 실패가 root _loadError로 승격되지 않는다', () {
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load('));
      // catch 블록은 두 개: flex TO별 catch, root catch.
      // flex catch가 _loadError를 건드리면 01B 회귀다.
      final flexStart = body.indexOf('flexGroups.map((group) async {');
      final flexEnd = body.indexOf('} // else 블록 닫힘');
      expect(flexStart, greaterThan(-1));
      expect(flexEnd, greaterThan(flexStart));
      final flexBlock = body.substring(flexStart, flexEnd);
      expect(flexBlock.contains('_loadError'), false,
          reason: 'flex 슬롯 실패가 목록 전체를 ERROR로 만든다');
      expect(flexBlock.contains('rethrow'), false);
    });

    test('03-c 성공한 그룹의 state는 실패한 그룹과 무관하게 채워진다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load(')));
      // 각 TO가 자기 try 안에서 자기 group만 갱신한다
      expect(body.contains('group.setGroupTOs(loaded.groupTOs);'), true);
      expect(body.contains('group.setSlotDates(loaded.slotDates);'), true);
    });

    test('03-d 새 시도마다 이전 detail 실패가 초기화된다', () {
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load('));
      final clearIdx = body.indexOf('_groupDetailErrorIds.clear();');
      final addIdx = body.indexOf('_groupDetailErrorIds.add(group.id);');
      expect(clearIdx, greaterThan(-1));
      expect(addIdx, greaterThan(clearIdx),
          reason: 'clear가 add 뒤에 오면 이번 로드의 실패까지 지워진다');
    });

    test('03-e 펼침 재시도 경로가 그대로 남아 있다', () {
      final code = _codeOf(_src(_ctrlPath));
      expect(code.contains('Future<void> loadGroupDetails('), true);
      expect(code.contains('_groupDetailErrorIds.remove(group.id);'), true);
      expect(code.contains('bool hasGroupDetailError(String groupId)'), true);
    });
  });

  // ── §15, §16, §37 최종 slotDates 계약 ──────────────────────────
  group('FLEX-SINGLE-READ-08 최종 slotDates가 덮어써지지 않는다', () {
    test('08-a setSlotDates가 setGroupTOs 뒤에 온다', () {
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load('));
      final g = body.indexOf('group.setGroupTOs(loaded.groupTOs);');
      final d = body.indexOf('group.setSlotDates(loaded.slotDates);');
      expect(g, greaterThan(-1));
      expect(d, greaterThan(g),
          reason: 'setGroupTOs가 뒤에 오면 raw 날짜가 덮어써질 여지가 생긴다');
    });

    test('08-b setGroupTOs는 slotDates를 건드리지 않는다', () {
      final body = _flat(_codeOf(_bodyOf(
          _src('lib/models/ui/admin_to_list_ui_models.dart'),
          'void setGroupTOs(')));
      expect(body.contains('_slotDates'), false,
          reason: 'setter가 slotDates를 자동 파생하면 레거시 날짜가 사라진다');
    });

    test('08-c setSlotDates는 주어진 리스트를 그대로 보관한다', () {
      final code = _flat(
          _codeOf(_src('lib/models/ui/admin_to_list_ui_models.dart')));
      expect(
          code.contains('void setSlotDates(List<DateTime> dates) => '
              '_slotDates = dates;'),
          true);
    });
  });

  // ── §17, §38, §39 ordering / limit ─────────────────────────────
  group('FLEX-SINGLE-READ-09 정렬과 limit 계약', () {
    test('09-a canonical query는 date ASC · bounded', () {
      final body = _flat(_codeOf(_bodyOf(
          _src(_svcPath), 'Future<QuerySnapshot<Map<String, dynamic>>>')));
      expect(body.contains(".orderBy('date')"), true);
      // [POSTING-V2-03C.1] 상한은 kMaxFlexSlotsPerTO, query는 그보다 1 크다
      expect(body.contains('.limit(_kFlexSlotProbeLimit)'), true,
          reason: '무제한 read로 바뀌면 안 된다');
      final svc = _flat(_codeOf(_src(_svcPath)));
      expect(svc.contains('const int kMaxFlexSlotsPerTO = 500;'), true);
    });

    test('09-b slotDates에 별도 정렬 정책을 넣지 않았다 (§17)', () {
      final body = _codeOf(_bodyOf(
          _src(_svcPath), 'static List<DateTime> slotDatesFromRaw('));
      expect(body.contains('sort('), false);
      // snapshot 순서를 그대로 따른다
      final dates = FirestoreService.slotDatesFromRaw([
        _rawSlot(DateTime(2026, 9, 20)),
        _rawSlot(DateTime(2026, 9, 21)),
      ]);
      expect(dates, [DateTime(2026, 9, 20), DateTime(2026, 9, 21)]);
    });

    test('09-c pagination을 추가하지 않았다 (§18)', () {
      final code = _codeOf(_src(_svcPath));
      expect(code.contains('startAfterDocument'), false);
      expect(code.contains('startAfter('), false);
    });
  });

  // ── §20 cascade close ──────────────────────────────────────────
  group('FLEX-SINGLE-READ-10 cascade close semantics 보존', () {
    test('10-a 여전히 fire-and-forget write다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_ctrlPath), 'void _maybeCascadeCloseExpiredTO(')));
      expect(body.contains('_service.markTOAsExpired(to.id).then((_) {'), true);
      expect(body.contains('.catchError('), true);
    });

    test('10-b load 성공 후에만 실행된다 (신뢰할 수 없는 상태에서 write 금지)', () {
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load('));
      final guard = body.indexOf('if (_loadError != null) return;');
      final call = body.indexOf('_maybeCascadeCloseExpiredTO(group, group.groupTOs);');
      expect(guard, greaterThan(-1));
      expect(call, greaterThan(guard),
          reason: '실패한 로드의 stale items로 write하면 안 된다');
    });

    test('10-c 슬롯 로드에 실패한 그룹은 마감 대상에서 빠진다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load(')));
      expect(
          body.contains(
              '_items.where( (g) => g.masterTO.isFlexType && g.isGroupDetailLoaded)'),
          true,
          reason: '실패를 슬롯 없음으로 오인해 공고를 마감할 수 있다');
    });

    test('10-d contract TO cascade는 그대로다', () {
      final code = _codeOf(_src(_ctrlPath));
      expect(code.contains('_maybeCascadeCloseExpiredContractTOs();'), true);
    });
  });

  // ── §21, §22 expand ────────────────────────────────────────────
  group('FLEX-SINGLE-READ-11 펼침 시 추가 read', () {
    test('11-a 로드된 그룹을 펼치면 query 0', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_ctrlPath), 'Future<void> loadGroupDetails(')));
      expect(
          body.contains('if (group.isGroupDetailLoaded || '
              '_loadingGroupIds.contains(group.id)) return;'),
          true);
    });

    test('11-b setGroupTOs가 isGroupDetailLoaded를 세운다', () {
      final body = _flat(_codeOf(_bodyOf(
          _src('lib/models/ui/admin_to_list_ui_models.dart'),
          'void setGroupTOs(')));
      expect(body.contains('isGroupDetailLoaded = true;'), true);
    });

    test('11-c preload 중 펼침 gap 경로가 사라졌다 (§22)', () {
      // root 로드가 blocking이므로 "preload 진행 중 펼침"이라는 상태가 없다.
      final code = _codeOf(_src(_ctrlPath));
      expect(code.contains('_preloadFlexTOSlots'), false);
      // root load 경로는 _loadingGroupIds를 쓰지 않는다 — 조기 리턴 gap의 원인이었다
      final body = _codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load('));
      expect(body.contains('_loadingGroupIds'), false);
    });
  });

  // ── §26, §30, §43 범위 밖 무변경 ───────────────────────────────
  group('FLEX-SINGLE-READ-12 범위 밖 무변경', () {
    test('12-a 새 callable / index를 만들지 않았다', () {
      final body = _codeOf(
          _bodyOf(_src(_svcPath), 'Future<FlexSlotLoad> loadFlexSlots('));
      expect(body.contains('httpsCallable'), false);
      expect(body.contains('where('), false,
          reason: '새 필터를 넣으면 복합 index가 필요해진다');
    });

    test('12-b 전역 cache를 만들지 않았다 (§6, §43)', () {
      final code = _codeOf(_src(_ctrlPath));
      for (final forbidden in ['_slotCache', 'slotCache', 'static final _cache']) {
        expect(code.contains(forbidden), false);
      }
    });

    test('12-c dual Root 구조를 건드리지 않았다 (§27)', () {
      final jobs = _codeOf(
          _src('lib/screens/business_admin/jobs_root_screen.dart'));
      final wf = _codeOf(_src(
          'lib/screens/business_admin/workforce_management/workforce_root_screen.dart'));
      expect(jobs.contains('final WorkforceController _controller = WorkforceController();'),
          true);
      expect(wf.contains('final WorkforceController _controller = WorkforceController();'),
          true);
    });

    test('12-d 필터는 여전히 client-side다 (§26)', () {
      final code = _codeOf(_src(_ctrlPath));
      for (final setter in [
        'void setBusinessIdFilter(String? businessId) { _selectedBusinessId = businessId; notifyListeners(); }',
        'void setDateRangeFilter(DateTimeRange? value) { _selectedDateRange = value; notifyListeners(); }',
      ]) {
        expect(_flat(code).contains(setter), true,
            reason: '필터 변경이 Firestore read를 유발하게 됐다');
      }
    });

    test('12-e 02B.2 invalidation 계약 무변경 (§24)', () {
      final code = _codeOf(_src(_ctrlPath));
      expect(code.contains('static void notifyDataChanged({required AdminMutationOrigin origin})'),
          true);
      expect(code.contains('_onExternalReloadCallback?.call();'), true);
    });

    test('12-f 서버 무변경 (§44)', () {
      final fns = _src('functions/src/index.ts');
      expect(fns.contains('export const callableGetAdminTOs'), true);
    });

    test('12-g SlotModel required 필드 정책 무변경 (§5)', () {
      final m = _codeOf(_src('lib/models/core/slot_model.dart'));
      expect(m.contains("(throw ArgumentError('SlotModel: date is required'))"),
          true);
      expect(
          m.contains(
              "(throw ArgumentError('SlotModel: createdAt is required'))"),
          true);
    });
  });
}
