// [HOME-V2-08B.2] FULL staffing correctness + lifecycle signal
//
// 08B.1 READ에서 확인된 것:
//   · syncTOStats(applications onDocumentWritten)가 인원이 차는 순간 TO를
//     자동으로 FULL로 바꾼다 — ACTIVE는 IMMUTABLE_TO_STATUSES에 없다.
//   · 그런데 callableGetStaffingReadiness는 ACTIVE/SCHEDULED만 조회했다.
//     FULL TO의 required와 confirmed가 **둘 다** 집계에서 사라졌다.
//   · 오늘 근무가 전부 충원되면 required=0 → hasTodayTarget=false →
//     Home이 `오늘 예정된 인력 운영이 없어요`라고 말하면서 바로 아래에
//     `현재 출근 6/6`을 함께 보여줬다. 운영이 잘될수록 Home이 비었다.
//   · DRAFT는 반대로 절대 들어가면 안 된다 — 확정 지원서가 없어 shortage
//     전량이 유령으로 잡힌다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/ui/staffing_readiness_model.dart';

const _fnPath = 'functions/src/index.ts';
const _modelPath = 'lib/models/ui/staffing_readiness_model.dart';
const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _indexesPath = 'firestore.indexes.json';

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

/// `export const <name> = ...` 부터 다음 top-level export 직전까지.
String _callableOf(String source, String name) {
  final start = source.indexOf('export const $name');
  if (start == -1) throw StateError('$name 를 찾지 못함');
  final next = source.indexOf('\nexport const ', start + 1);
  return next == -1 ? source.substring(start) : source.substring(start, next);
}

// ═══════════════════════════════════════════════════════════════
// 서버 집계 replica
// ═══════════════════════════════════════════════════════════════

const staffingStates = {'ACTIVE', 'SCHEDULED', 'FULL'};
const publishedStates = {'ACTIVE', 'SCHEDULED', 'FULL'};

class ToDoc {
  final String id;
  final String businessId;
  final String status;

  /// D0~D+7 중 근무가 걸린 날짜 index → 필요 인원
  final Map<int, int> requiredByDay;

  /// 같은 날짜의 확정 인원
  final Map<int, int> confirmedByDay;

  /// null = 필드 자체가 없음(레거시). true = 소프트 삭제.
  final bool? isDeleted;

  const ToDoc({
    required this.id,
    required this.businessId,
    required this.status,
    this.requiredByDay = const {},
    this.confirmedByDay = const {},
    this.isDeleted,
  });

  bool get live => isDeleted != true;
}

class DayAcc {
  int required = 0;
  int confirmed = 0;
  int shortage = 0;
}

class StaffingResult {
  final List<DayAcc> days;
  final int publishedPostingCount;
  final bool hasDraftPosting;
  const StaffingResult(this.days, this.publishedPostingCount,
      this.hasDraftPosting);

  bool get hasTodayTarget => days[0].required > 0;
  bool get hasFutureTarget => days.skip(1).any((d) => d.required > 0);
}

/// 이전 구현 — ACTIVE/SCHEDULED만.
StaffingResult legacyAggregate(List<ToDoc> all, List<String> scope) =>
    _aggregate(all, scope, const {'ACTIVE', 'SCHEDULED'});

/// 현재 구현 — ACTIVE/SCHEDULED/FULL + lifecycle signal.
StaffingResult aggregate(List<ToDoc> all, List<String> scope) =>
    _aggregate(all, scope, staffingStates);

StaffingResult _aggregate(
    List<ToDoc> all, List<String> scope, Set<String> states) {
  final days = List.generate(8, (_) => DayAcc());
  var published = 0;
  var hasDraft = false;

  for (final biz in scope) {
    for (final d in all.where((d) => d.businessId == biz)) {
      // DRAFT existence — cursor scan replica: 살아있는 것을 만나면 true
      if (d.status == 'DRAFT') {
        if (d.live) hasDraft = true;
        continue; // staffing population에 절대 들어가지 않는다
      }
      if (!states.contains(d.status)) continue;
      if (!d.live) continue;
      if (publishedStates.contains(d.status)) published++;
      for (final entry in d.requiredByDay.entries) {
        final i = entry.key;
        final req = entry.value;
        final conf = d.confirmedByDay[i] ?? 0;
        days[i].required += req;
        days[i].confirmed += conf;
        days[i].shortage += (req - conf) < 0 ? 0 : (req - conf);
      }
    }
  }
  return StaffingResult(days, published, hasDraft);
}

// ═══════════════════════════════════════════════════════════════
// DRAFT existence — cursor scan (cap 없음)
// ═══════════════════════════════════════════════════════════════

class DraftScanResult {
  final bool hasDraft;
  final int docsRead;
  const DraftScanResult(this.hasDraft, this.docsRead);
}

/// `createdAt desc` 정렬된 DRAFT 목록에서 살아있는 것을 찾는다.
/// 한 page가 전부 삭제됐다고 false로 확정하지 않는다.
DraftScanResult scanDrafts(List<ToDoc> draftsNewestFirst, {int page = 100}) {
  var read = 0;
  var offset = 0;
  while (true) {
    final chunk = draftsNewestFirst.skip(offset).take(page).toList();
    if (chunk.isEmpty) return DraftScanResult(false, read);
    for (final d in chunk) {
      read++;
      if (d.live) return DraftScanResult(true, read);
    }
    if (chunk.length < page) return DraftScanResult(false, read);
    offset += page;
  }
}

// ═══════════════════════════════════════════════════════════════
// fixture
// ═══════════════════════════════════════════════════════════════

ToDoc _to(
  String id, {
  String biz = 'A',
  required String status,
  Map<int, int> required = const {},
  Map<int, int> confirmed = const {},
  bool? isDeleted,
}) =>
    ToDoc(
      id: id,
      businessId: biz,
      status: status,
      requiredByDay: required,
      confirmedByDay: confirmed,
      isDeleted: isDeleted,
    );

void main() {
  // ══════════════════════════════════════════════════════════════
  // §3 — 오늘 전부 FULL
  // ══════════════════════════════════════════════════════════════
  group('01. 오늘 근무가 전부 FULL', () {
    final all = [
      _to('t1',
          status: 'FULL',
          required: {0: 5},
          confirmed: {0: 5},
          isDeleted: false),
      _to('t2',
          status: 'FULL',
          required: {0: 3},
          confirmed: {0: 3},
          isDeleted: false),
    ];

    test('01-a 이전에는 오늘 대상이 사라졌다', () {
      final before = legacyAggregate(all, ['A']);
      expect(before.days[0].required, 0);
      expect(before.hasTodayTarget, false,
          reason: '`오늘 예정된 인력 운영이 없어요`가 나오던 원인');
    });

    test('01-b 이제 required가 실제 값이다', () {
      final after = aggregate(all, ['A']);
      expect(after.days[0].required, 8);
      expect(after.hasTodayTarget, true);
    });

    test('01-c confirmed도 함께 회복된다', () {
      expect(aggregate(all, ['A']).days[0].confirmed, 8);
    });

    test('01-d shortage는 0이다 — 충원 완료가 부족으로 둔갑하지 않는다', () {
      expect(aggregate(all, ['A']).days[0].shortage, 0);
    });

    test('01-e `오늘 근무 없음 + 출근 6/6` 모순이 사라진다', () {
      // 출근 수치는 applications를 직접 읽어 TO status와 무관하다.
      //   staffing이 대상을 인정해야 두 숫자가 같은 사실을 말한다.
      const rosterCount = 8;
      final after = aggregate(all, ['A']);
      expect(after.hasTodayTarget, true);
      expect(after.days[0].confirmed, rosterCount);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §4 — 미래 전부 FULL
  // ══════════════════════════════════════════════════════════════
  group('02. 다가오는 근무가 전부 FULL', () {
    final all = [
      _to('f1',
          status: 'FULL',
          required: {2: 4, 5: 6},
          confirmed: {2: 4, 5: 6},
          isDeleted: false),
    ];

    test('02-a 이전에는 미래 대상도 사라졌다', () {
      expect(legacyAggregate(all, ['A']).hasFutureTarget, false);
    });

    test('02-b 이제 미래 대상이 존재한다', () {
      final after = aggregate(all, ['A']);
      expect(after.hasFutureTarget, true);
      expect(after.days[2].required, 4);
      expect(after.days[5].required, 6);
    });

    test('02-c required == confirmed, shortage == 0', () {
      final after = aggregate(all, ['A']);
      for (final i in [2, 5]) {
        expect(after.days[i].required, after.days[i].confirmed);
        expect(after.days[i].shortage, 0);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §1 §2 — population 구성
  // ══════════════════════════════════════════════════════════════
  group('03. staffing population', () {
    test('03-a ACTIVE · SCHEDULED · FULL 셋 다 포함', () {
      final all = [
        _to('a', status: 'ACTIVE', required: {0: 1}, isDeleted: false),
        _to('s', status: 'SCHEDULED', required: {0: 2}, isDeleted: false),
        _to('f', status: 'FULL', required: {0: 4}, isDeleted: false),
      ];
      expect(aggregate(all, ['A']).days[0].required, 7);
    });

    test('03-b CLOSED · EXPIRED는 제외', () {
      final all = [
        _to('c', status: 'CLOSED', required: {0: 9}, isDeleted: false),
        _to('e', status: 'EXPIRED', required: {0: 9}, isDeleted: false),
      ];
      expect(aggregate(all, ['A']).days[0].required, 0);
    });

    test('03-c 삭제된 문서는 제외', () {
      final all = [
        _to('f', status: 'FULL', required: {0: 5}, isDeleted: true),
      ];
      expect(aggregate(all, ['A']).days[0].required, 0);
    });

    test('03-d FULL도 canonical count로 계산된다 — synthetic 없음', () {
      // status가 FULL이라고 confirmed = required로 만들지 않는다.
      //   실제 집계가 부족을 말하면 그대로 나와야 한다.
      final all = [
        _to('f',
            status: 'FULL',
            required: {0: 10},
            confirmed: {0: 7},
            isDeleted: false),
      ];
      final r = aggregate(all, ['A']);
      expect(r.days[0].confirmed, 7);
      expect(r.days[0].shortage, 3);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §5 — DRAFT isolation
  // ══════════════════════════════════════════════════════════════
  group('04. DRAFT는 staffing에 0의 영향', () {
    test('04-a DRAFT FLEX가 있어도 숫자가 변하지 않는다', () {
      final base = [
        _to('a', status: 'ACTIVE', required: {0: 3}, confirmed: {0: 1},
            isDeleted: false),
      ];
      final withDraft = [
        ...base,
        _to('d', status: 'DRAFT', required: {0: 100}, isDeleted: false),
      ];
      final a = aggregate(base, ['A']);
      final b = aggregate(withDraft, ['A']);
      expect(b.days[0].required, a.days[0].required);
      expect(b.days[0].confirmed, a.days[0].confirmed);
      expect(b.days[0].shortage, a.days[0].shortage);
    });

    test('04-b DRAFT CONTRACT도 동일', () {
      final withDraft = [
        _to('d', status: 'DRAFT', required: {0: 50, 3: 50}, isDeleted: false),
      ];
      final r = aggregate(withDraft, ['A']);
      for (var i = 0; i < 8; i++) {
        expect(r.days[i].required, 0, reason: 'day $i');
        expect(r.days[i].shortage, 0, reason: 'day $i');
      }
    });

    test('04-c DRAFT만 있으면 오늘·미래 대상이 없다', () {
      final r = aggregate(
          [_to('d', status: 'DRAFT', required: {0: 9}, isDeleted: false)], ['A']);
      expect(r.hasTodayTarget, false);
      expect(r.hasFutureTarget, false);
    });

    test('04-d 그래도 lifecycle signal에는 잡힌다', () {
      final r = aggregate(
          [_to('d', status: 'DRAFT', required: {0: 9}, isDeleted: false)], ['A']);
      expect(r.hasDraftPosting, true);
      expect(r.publishedPostingCount, 0);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §6 — publishedPostingCount
  // ══════════════════════════════════════════════════════════════
  group('05. publishedPostingCount', () {
    test('05-a ACTIVE+SCHEDULED+FULL live만 센다', () {
      final all = [
        _to('a', status: 'ACTIVE', isDeleted: false),
        _to('s', status: 'SCHEDULED', isDeleted: false),
        _to('f', status: 'FULL', isDeleted: false),
        _to('c', status: 'CLOSED', isDeleted: false),
        _to('e', status: 'EXPIRED', isDeleted: false),
        _to('d', status: 'DRAFT', isDeleted: false),
      ];
      expect(aggregate(all, ['A']).publishedPostingCount, 3);
    });

    test('05-b 삭제된 문서는 빠진다', () {
      final all = [
        _to('a', status: 'ACTIVE', isDeleted: false),
        _to('f', status: 'FULL', isDeleted: true),
      ];
      expect(aggregate(all, ['A']).publishedPostingCount, 1);
    });

    test('05-c isDeleted 필드가 없는 레거시는 live로 센다', () {
      final all = [_to('legacy', status: 'ACTIVE')]; // isDeleted 없음
      expect(aggregate(all, ['A']).publishedPostingCount, 1);
    });

    test('05-d 근무 날짜가 없어도(D+8 이후) 센다', () {
      // staffing days와 모집단이 다르다 — lifecycle은 날짜와 무관하다
      final all = [_to('far', status: 'ACTIVE', isDeleted: false)];
      final r = aggregate(all, ['A']);
      expect(r.publishedPostingCount, 1);
      expect(r.hasTodayTarget, false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §8 §10 — DRAFT existence, cap 없음
  // ══════════════════════════════════════════════════════════════
  group('06. DRAFT 존재 판정', () {
    ToDoc draft(String id, {bool? deleted}) =>
        _to(id, status: 'DRAFT', isDeleted: deleted);

    test('06-a live DRAFT 1건 → true', () {
      expect(scanDrafts([draft('d1', deleted: false)]).hasDraft, true);
    });

    test('06-b DRAFT 없음 → false', () {
      expect(scanDrafts([]).hasDraft, false);
    });

    test('06-c 삭제된 DRAFT만 → false', () {
      final r = scanDrafts([
        draft('d1', deleted: true),
        draft('d2', deleted: true),
      ]);
      expect(r.hasDraft, false);
    });

    test('06-d 레거시(필드 없음) live DRAFT → true', () {
      // 2026-08-10 소프트 삭제 도입 시 backfill을 하지 않았다.
      //   `isDeleted == false` equality였다면 이 문서를 놓쳤을 것이다.
      expect(scanDrafts([draft('legacy')]).hasDraft, true);
    });

    test('06-e 삭제 5건 뒤 live → true (limit(5) cap이었다면 false)', () {
      final docs = [
        for (var i = 0; i < 5; i++) draft('del$i', deleted: true),
        draft('live', deleted: false),
      ];
      expect(scanDrafts(docs).hasDraft, true);
      // 임의 cap 구현이었다면 실패했을 지점
      expect(docs.take(5).every((d) => !d.live), true);
    });

    test('06-f 삭제 250건 뒤 live → true (page 경계를 넘어간다)', () {
      final docs = [
        for (var i = 0; i < 250; i++) draft('del$i', deleted: true),
        draft('live', deleted: false),
      ];
      final r = scanDrafts(docs, page: 100);
      expect(r.hasDraft, true);
      expect(r.docsRead, 251);
    });

    test('06-g best case는 1 read다', () {
      final docs = [
        draft('live', deleted: false),
        for (var i = 0; i < 500; i++) draft('del$i', deleted: true),
      ];
      final r = scanDrafts(docs, page: 100);
      expect(r.hasDraft, true);
      expect(r.docsRead, 1, reason: '살아있는 문서를 만나면 즉시 멈춘다');
    });

    test('06-h worst case는 전량 — false를 말하려면 전량을 봐야 한다', () {
      final docs = [for (var i = 0; i < 230; i++) draft('del$i', deleted: true)];
      final r = scanDrafts(docs, page: 100);
      expect(r.hasDraft, false);
      expect(r.docsRead, 230);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §13 — 다사업장
  // ══════════════════════════════════════════════════════════════
  group('07. 다사업장', () {
    test('07-a publishedPostingCount는 scope 전체 합', () {
      final all = [
        _to('a1', biz: 'A', status: 'ACTIVE', isDeleted: false),
        _to('b1', biz: 'B', status: 'FULL', isDeleted: false),
      ];
      expect(aggregate(all, ['A', 'B']).publishedPostingCount, 2);
    });

    test('07-b A에만 공고가 있어도 empty가 아니다', () {
      final all = [_to('a1', biz: 'A', status: 'ACTIVE', isDeleted: false)];
      expect(aggregate(all, ['A', 'B']).publishedPostingCount, 1);
    });

    test('07-c B의 DRAFT 하나로도 hasDraft는 true', () {
      final all = [_to('b1', biz: 'B', status: 'DRAFT', isDeleted: false)];
      expect(aggregate(all, ['A', 'B']).hasDraftPosting, true);
    });

    test('07-d scope 밖 사업장은 세지 않는다', () {
      final all = [
        _to('c1', biz: 'C', status: 'ACTIVE', isDeleted: false),
        _to('c2', biz: 'C', status: 'DRAFT', isDeleted: false),
      ];
      final r = aggregate(all, ['A', 'B']);
      expect(r.publishedPostingCount, 0);
      expect(r.hasDraftPosting, false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §11 §12 — ERROR ≠ ZERO
  // ══════════════════════════════════════════════════════════════
  group('08. 실패 / partial 의미', () {
    test('08-a partial이면 소비자는 공고 없음을 확정하면 안 된다', () {
      const m = StaffingReadinessModel(
        available: false,
        partial: true,
        failedBusinessCount: 1,
        days: [],
        publishedPostingCount: 0,
        hasDraftPosting: false,
      );
      expect(m.hasUsableData, true);
      expect(m.partial, true,
          reason: 'publishedPostingCount 0은 부분합이므로 lifecycle 확정 불가');
    });

    test('08-b 전체 실패면 hasUsableData가 false다', () {
      const m = StaffingReadinessModel(available: false, days: []);
      expect(m.hasUsableData, false);
    });

    test('08-c 정상 성공 + 0건은 확정된 공고 없음이다', () {
      const m = StaffingReadinessModel(
        available: true,
        days: [],
        publishedPostingCount: 0,
        hasDraftPosting: false,
      );
      expect(m.hasUsableData, true);
      expect(m.partial, false);
      expect(m.publishedPostingCount, 0);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 서버 소스 고정
  // ══════════════════════════════════════════════════════════════
  group('09. callableGetStaffingReadiness 소스', () {
    final fn = _callableOf(_src(_fnPath), 'callableGetStaffingReadiness');
    final code = _codeOf(fn);
    final flat = _flat(code);

    test('09-a staffing population에 FULL이 포함됐다', () {
      expect(
        flat.contains(
            '.where("status", "in", ["ACTIVE", "SCHEDULED", "FULL"])'),
        true,
      );
      expect(flat.contains('.where("status", "in", ["ACTIVE", "SCHEDULED"])'),
          false);
    });

    test('09-b DRAFT는 staffing 쿼리에 없다', () {
      final tosQuery = flat.substring(
          flat.indexOf('const tosSnap'), flat.indexOf('type WdEntry'));
      expect(tosQuery.contains('DRAFT'), false);
    });

    test('09-c FULL을 synthetic으로 계산하지 않는다 (§2)', () {
      // status === "FULL" 분기로 confirmed를 만들어내는 코드가 없어야 한다
      expect(code.contains('=== "FULL"'), false);
      expect(code.contains('"FULL" ?'), false);
      // 기존 canonical 계산은 그대로
      expect(code.contains('workDetailCounts'), true);
      expect(code.contains('CONFIRMED_STATUSES'), true);
    });

    test('09-d publishedCount는 같은 루프에서 센다 — 추가 조회 없음', () {
      expect(flat.contains('let publishedCount = 0;'), true);
      // 소프트 삭제 skip 직후에 증가한다 = tosSnap 루프 안, 별도 쿼리 없음
      final loopAt = flat.indexOf('for (const toDoc of tosSnap.docs)');
      final skipAt = flat.indexOf('if (d["isDeleted"] === true) continue', loopAt);
      final incAt = flat.indexOf('publishedCount++;', loopAt);
      expect(loopAt, greaterThan(-1));
      expect(skipAt, greaterThan(loopAt));
      expect(incAt, greaterThan(skipAt));
      // 증가 지점이 루프 안에 있다 (다음 쿼리 시작 전)
      expect(incAt, lessThan(flat.indexOf('flexResults')));
      expect(RegExp(r'publishedCount\+\+;').allMatches(flat).length, 1);
    });

    test('09-e DRAFT 존재 판정은 cursor scan이고 cap이 없다 (§8)', () {
      final draftBlock = code.substring(code.indexOf('let hasDraft = false;'));
      expect(draftBlock.contains('.where("status", "==", "DRAFT")'), true);
      expect(draftBlock.contains('startAfter(cursor)'), true);
      expect(draftBlock.contains('if (page.size < DRAFT_PAGE) break;'), true);
      // 살아있는 문서를 만나면 즉시 종료
      expect(draftBlock.contains('hasDraft = true;'), true);
      // isDeleted equality 쿼리로 레거시를 놓치지 않는다
      expect(draftBlock.contains('where("isDeleted"'), false);
    });

    test('09-f DRAFT 조회 실패를 false로 내리지 않는다 (§11)', () {
      final draftBlock = code.substring(code.indexOf('let hasDraft = false;'));
      final catchAt = draftBlock.indexOf('} catch (e) {');
      expect(catchAt, greaterThan(-1));
      final catchBody = draftBlock.substring(catchAt);
      expect(catchBody.contains('success = false;'), true,
          reason: '실패는 partial 계약으로 전달된다');
      expect(catchBody.contains('hasDraft = false'), false);
    });

    test('09-g 실패한 사업장은 signal 합산에서 빠진다 (§12)', () {
      final agg = flat.substring(flat.indexOf('okBusinessCount++;'));
      expect(agg.contains('publishedPostingCount += r.value.publishedCount;'),
          true);
      expect(agg.contains('if (r.value.hasDraft) hasDraftPosting = true;'),
          true);
      // 합산은 okBusinessCount++ 이후 — 실패 분기는 이미 continue했다
      final okAt = flat.indexOf('okBusinessCount++;');
      final failAt = flat.indexOf('failedBusinessCount++;');
      expect(failAt, lessThan(okAt));
    });

    test('09-h 응답에 두 필드가 추가됐다 (§17)', () {
      expect(flat.contains('publishedPostingCount, hasDraftPosting, };'), true);
      // 기존 계약 무변경
      expect(flat.contains('available: failedBusinessCount === 0,'), true);
      expect(
        flat.contains(
            'partial: okBusinessCount > 0 && failedBusinessCount > 0,'),
        true,
      );
      expect(flat.contains('failedBusinessCount, days: aggDays,'), true);
    });

    test('09-i authorization이 그대로다 (§14)', () {
      expect(code.contains('subAdminBusinessIds'), true);
      expect(code.contains('canManageTo'), true);
      expect(code.contains('canManageWorkers'), true);
      expect(
        flat.contains(
            'if (!businessIds.includes(trimmedId)) { throw new HttpsError("permission-denied"'),
        true,
      );
    });

    test('09-j callableGetAdminTOs를 부르지 않는다', () {
      expect(code.contains('callableGetAdminTOs'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §18 §20 — 클라이언트 / 인덱스
  // ══════════════════════════════════════════════════════════════
  group('10. 클라이언트 모델', () {
    final model = _src(_modelPath);

    test('10-a 두 필드를 파싱한다', () {
      expect(model.contains('final int publishedPostingCount;'), true);
      expect(model.contains('final bool hasDraftPosting;'), true);
      expect(
        _flat(model).contains(
            "publishedPostingCount: (map['publishedPostingCount'] as num?)?.toInt() ?? 0,"),
        true,
      );
      expect(
        model.contains(
            "hasDraftPosting: (map['hasDraftPosting'] as bool?) ?? false,"),
        true,
      );
    });

    test('10-b 구 서버 응답에서 0 / false로 파싱된다', () {
      const m = StaffingReadinessModel(available: true, days: []);
      expect(m.publishedPostingCount, 0);
      expect(m.hasDraftPosting, false);
    });

    test('10-c 기존 getter 계약 무변경', () {
      const m = StaffingReadinessModel(available: true, days: []);
      expect(m.hasUsableData, true);
      expect(m.hasTodayTarget, false);
      expect(m.hasFutureTarget, false);
    });

    test('10-d signal이 Hero 분기에만 쓰인다', () {
      // [HOME-V2-08D.2] 08B.2에서는 "아직 UI에 쓰지 않았다"를 고정했다.
      //   이제 Adaptive Hero가 쓴다. 다만 쓰이는 곳은 상태 판정 한 곳뿐이고,
      //   task gate에는 절대 들어가지 않는다(공고 없음 ≠ 처리할 업무 없음).
      final home = _codeOf(_src(_homePath));
      final derive = _bodyOf(home, '_HeroState _heroStateOf(');
      expect(derive.contains('sr.publishedPostingCount == 0'), true);
      expect(derive.contains('sr.hasDraftPosting'), true);
      expect(
        RegExp(r'publishedPostingCount').allMatches(home).length,
        1,
        reason: 'Hero 상태 판정 외에는 쓰이지 않는다',
      );
      final taskGate = _bodyOf(home, 'bool _showTaskSection(');
      expect(taskGate.contains('publishedPostingCount'), false);
      expect(taskGate.contains('hasDraftPosting'), false);
      // 기존 섹션·문구 그대로
      for (final s in ["'오늘 운영'", "'처리할 일'", "'다가오는 인력 부족'"]) {
        expect(home.contains(s), true, reason: s);
      }
    });
  });

  group('11. Firestore index', () {
    final indexes = _flat(_src(_indexesPath));

    test('11-a businessId + status + createdAt 인덱스가 존재한다', () {
      expect(
        indexes.contains(
            '"collectionGroup": "tos", "queryScope": "COLLECTION", "fields": [ { "fieldPath": "businessId", "order": "ASCENDING" }, { "fieldPath": "status", "order": "ASCENDING" }, { "fieldPath": "createdAt", "order": "DESCENDING" } ]'),
        true,
        reason: 'DRAFT cursor scan(businessId== + status== + orderBy createdAt)',
      );
    });

    test('11-b 신규 인덱스를 추가하지 않았다', () {
      final tosIndexes =
          RegExp(r'"collectionGroup": "tos"').allMatches(indexes).length;
      expect(tosIndexes, 11, reason: '03T 시점과 동일');
    });
  });
}
