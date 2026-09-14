// [POSTING-V2-03G.1] 업무 수정 제한 — 헛수고 전에 알린다
//
// 03G READ에서 확인된 것:
//   · 서버는 전체 Edit을 막지 않는다. 제목·설명·공개설정·마감시각은 허용되고,
//     지원자의 선택 전제를 바꾸는 것(업무 identity·필요인원 하한)만 거부한다.
//   · 그런데 관리자는 업무를 다 고치고 저장을 누른 뒤에야 그것을 알았다.
//   · 카드가 가진 카운터로는 사전 판단이 불가능하다 — totalPending은
//     status == "PENDING" 하나만 세는데(index.ts syncTOStats), 서버 predicate는
//     INVITED와 CONTRACT_PENDING을 포함한다. `지원자 수 > 0` 식 추정은 틀린다.
//   · 마스터 경로에는 `totalConfirmed > 0 && "workDetails" in updates` blanket
//     guard가 있는데, 화면은 workDetails를 **항상** 실어 보냈다. 그래서 확정
//     근무자가 있는 공고는 제목만 고쳐도 '근무 조건은 수정할 수 없습니다'였다.
//
// 채택 모델: MODEL B.5 — LAZY FIELD PRECHECK
//   진입 시 조회 없음. 업무를 실제로 바꾸려는 첫 순간에 기존 callable로 한 번
//   읽고 세션 동안 재사용. 판정은 advisory이며 서버가 최종 방어선이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/screens/business_admin/to_management/edit_to_screen.dart';

const _editPath = 'lib/screens/business_admin/to_management/edit_to_screen.dart';
const _fnsPath = 'functions/src/index.ts';

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

// ── predicate replica ───────────────────────────────────────────
// _workChangeBlockReason과 같은 규칙. 서버 predicate와의 일치는 아래
// PREFLIGHT-02/03가 소스로 교차 검증한다.

const _slotIdentity = ['PENDING', 'INVITED', 'CONTRACT_PENDING', 'CONFIRMED'];
const _toIdentity = ['PENDING', 'INVITED', 'CONTRACT_PENDING'];
const _occupancy = ['CONFIRMED', 'CONTRACT_PENDING'];

class Work {
  final String workType;
  final String startTime;
  final String endTime;
  final int requiredCount;
  final String? wdId;
  const Work(this.workType, this.startTime, this.endTime,
      {this.requiredCount = 1, this.wdId});
  String get id => '${workType}_${startTime}_$endTime';
}

class App {
  final String status;
  final String? slotId;
  final String? workDetailId;
  final String? wdId;
  final String? selectedWorkType;
  const App(this.status,
      {this.slotId, this.workDetailId, this.wdId, this.selectedWorkType});
}

// ── EditApplicationRelations 동작 테스트용 ──────────────────────
Map<String, dynamic> _app(String status) => {'status': status};

const _confirmedish = ['CONFIRMED', 'CONTRACT_PENDING'];

/// WAGE-GUARD가 실제로 쓰는 판정 — 확정/서명대기 근무자가 있는가.
bool _hasConfirmed(List<Map<String, dynamic>> apps) =>
    apps.any((m) => _confirmedish.contains(m['status']));

bool _matches(App a, Work w) {
  if (a.workDetailId == w.id) return true;
  if (a.workDetailId == w.workType) return true;
  if (w.wdId != null && a.wdId == w.wdId) return true;
  return false;
}

String? blockReason({
  required List<App> apps,
  required List<Work> original,
  required List<Work> next,
  required bool isSlotMode,
  List<String> slotIds = const [],
}) {
  final nextIds = next.map((w) => w.id).toSet();
  final removed = original.where((w) => !nextIds.contains(w.id)).toList();

  if (isSlotMode) {
    for (final work in removed) {
      final blocked = apps.any((a) =>
          _slotIdentity.contains(a.status) &&
          slotIds.contains(a.slotId) &&
          _matches(a, work));
      if (blocked) return 'IDENTITY_SLOT';
    }
    for (final work in next) {
      final occupied = apps
          .where((a) =>
              _occupancy.contains(a.status) &&
              slotIds.contains(a.slotId) &&
              _matches(a, work))
          .length;
      if (occupied > 0 && work.requiredCount < occupied) return 'REQUIRED_COUNT';
    }
    return null;
  }

  // [POSTING-V2-03J.1] 마스터 경로도 필드별 판정이다. 확정자가 있다는 것만으로
  //   근무 조건 전체를 막지 않는다 — 기존 약속은 03I 스냅샷이 지킨다.
  for (final work in removed) {
    final blocked = apps.any((a) =>
        _toIdentity.contains(a.status) && a.selectedWorkType == work.workType);
    if (blocked) return 'IDENTITY_TO';
  }
  for (final work in next) {
    final orig = original.where((o) => o.id == work.id).firstOrNull;
    if (orig == null) continue; // 새 업무는 기존 약속과 무관하다
    if (work.requiredCount < orig.requiredCount) {
      final occupied = apps
          .where((a) =>
              _occupancy.contains(a.status) &&
              a.selectedWorkType == work.workType)
          .length;
      if (work.requiredCount < occupied) return 'REQUIRED_COUNT';
    }
  }
  return null;
}

void main() {
  // ── §3, §18 lazy trigger ───────────────────────────────────────
  group('PREFLIGHT-01 진입이 아니라 업무 변경 시점에 조회한다', () {
    test('01-a 화면 진입 경로에 지원 조회가 없다 (§3, entry = +0)', () {
      final body = _codeOf(_bodyOf(_src(_editPath), 'Future<void> _loadData('));
      expect(body.contains('_ensureApplicationSnapshot'), false,
          reason: '허용된 field만 고치고 나가는 경우 조회는 순수한 낭비다');
      expect(body.contains('callableGetApplicationsByBiz'), false);
      expect(body.contains('applications'), false);
    });

    test('01-b 업무 추가·수정·삭제 세 경로가 사전 확인을 거친다 (§A)', () {
      for (final sig in [
        'Future<void> _showAddWorkDialog(',
        'Future<void> _showEditWorkDialog(',
        'Future<void> _deleteWork(',
      ]) {
        final body = _flat(_codeOf(_bodyOf(_src(_editPath), sig)));
        expect(body.contains('await _canApplyWorkChange('), true, reason: sig);
      }
    });

    test('01-c 변경이 form에 반영되기 전에 확인한다 (§8)', () {
      for (final entry in [
        ('Future<void> _showAddWorkDialog(', '_workDetails.add(candidate);'),
        ('Future<void> _showEditWorkDialog(', '_workDetails[index] = updated;'),
        ('Future<void> _deleteWork(', '_workDetails.remove(work);'),
      ]) {
        final body = _codeOf(_bodyOf(_src(_editPath), entry.$1));
        final guard = body.indexOf('await _canApplyWorkChange(');
        final apply = body.indexOf(entry.$2);
        expect(guard, greaterThan(-1), reason: entry.$1);
        expect(apply, greaterThan(guard),
            reason: '${entry.$1} — 고쳐 놓고 저장에서 되돌려받는 것이 원래 문제였다');
      }
    });

    // [TC2 재작성] 캐시 정책이 State 메서드에서 EditApplicationRelations로
    // 옮겨졌다. 안내용(advisory)은 세션 재사용, 임금 판단(fresh)은 매번 조회다.
    test('01-d 안내용은 세션 안에서 두 번 읽지 않는다 (repeat = +0, §5)', () async {
      var calls = 0;
      final r = EditApplicationRelations(() async {
        calls++;
        return [_app('PENDING')];
      });
      await r.advisory();
      await r.advisory();
      await r.advisory();
      expect(calls, 1, reason: '필드를 만질 때마다 재조회하지 않는다');
    });

    test('01-e 새 callable / 새 Firestore query를 만들지 않았다 (§6)', () {
      final body = _codeOf(_bodyOf(
          _src(_editPath), 'Future<List<Map<String, dynamic>>> _fetchApplications('));
      expect(body.contains("'callableGetApplicationsByBiz'"), true);
      expect(body.contains('FirebaseFirestore.instance'), false);
      expect(body.contains('.collection('), false);
      // 원본 조회 지점은 파일 전체에서 하나뿐 — 두 경로가 같은 fetch를 공유한다
      final code = _codeOf(_src(_editPath));
      expect("httpsCallable('callableGetApplicationsByBiz'".allMatches(code).length, 1);
    });

    test('01-f 화면을 닫으면 사라지는 세션 상태다 (§16)', () {
      final code = _codeOf(_src(_editPath));
      expect(
          code.contains('late final EditApplicationRelations _applicationRelations ='),
          true,
          reason: 'State 필드 — 전역 캐시로 승격하지 않는다');
      expect(code.contains('static EditApplicationRelations'), false);
      expect(code.contains('FirestoreService().cacheApplications'), false);
    });
  });

  // ── TC2 §1, §2, §7, §8 — advisory / wage 분리 ──────────────────
  group('PREFLIGHT-08 안내용 캐시가 임금 판단을 대신하지 않는다', () {
    test('08-a 임금 경로는 캐시가 있어도 다시 읽는다 (§2, §B)', () async {
      var calls = 0;
      final r = EditApplicationRelations(() async {
        calls++;
        return [_app('PENDING')];
      });
      await r.advisory();
      expect(calls, 1);
      await r.fresh();
      expect(calls, 2, reason: '세션 캐시로 최종 방어선을 대체하면 경고가 무의미해진다');
      await r.fresh();
      expect(calls, 3, reason: '저장할 때마다 그 시점의 확정 관계를 본다');
    });

    test('08-b CASE A — 안내 이후 생긴 확정자를 임금 조회가 잡는다 (§7, §D)', () async {
      var confirmedExists = false;
      final r = EditApplicationRelations(() async =>
          confirmedExists ? [_app('CONFIRMED')] : <Map<String, dynamic>>[]);

      // 업무를 고치던 시점: 확정자 0
      final advisory = await r.advisory();
      expect(advisory, isEmpty);

      // 그 사이 다른 관리자가 한 명을 확정했다
      confirmedExists = true;

      // 임금 저장 시점
      final wage = await r.fresh();
      expect(wage, isNotNull);
      expect(_hasConfirmed(wage!), true,
          reason: 'stale 캐시를 썼다면 확정자 없음으로 통과했을 것');
    });

    test('08-c 안내용 캐시는 fresh 결과로 갱신된다 (§6)', () async {
      var confirmedExists = false;
      final r = EditApplicationRelations(() async =>
          confirmedExists ? [_app('CONFIRMED')] : <Map<String, dynamic>>[]);
      await r.advisory();
      confirmedExists = true;
      await r.fresh();
      final again = await r.advisory();
      expect(_hasConfirmed(again!), true,
          reason: '더 새 값을 얻었는데 낡은 안내를 계속 쓸 이유가 없다');
    });

    test('08-d 안내 실패는 기억하고, 임금 실패는 기억하지 않는다 (§4, §8)', () async {
      var shouldFail = true;
      var calls = 0;
      final r = EditApplicationRelations(() async {
        calls++;
        if (shouldFail) throw StateError('network');
        return [_app('CONFIRMED')];
      });

      // 안내: 실패 → 이후 재시도하지 않는다
      expect(await r.advisory(), isNull);
      expect(await r.advisory(), isNull);
      expect(calls, 1, reason: '필드를 만질 때마다 실패한 조회를 반복하지 않는다');

      // 임금: 안내가 실패했더라도 다시 시도한다
      expect(await r.fresh(), isNull);
      expect(calls, 2, reason: '안내 실패가 저장 시 조회까지 막으면 안 된다');

      // 재저장: 또 시도한다 (permanent failure cache 금지)
      expect(await r.fresh(), isNull);
      expect(calls, 3);

      // 복구되면 성공하고, 안내도 함께 되살아난다
      shouldFail = false;
      final recovered = await r.fresh();
      expect(_hasConfirmed(recovered!), true);
      expect(_hasConfirmed((await r.advisory())!), true,
          reason: '한 번 실패했다고 세션 내내 안내를 포기하지 않는다');
    });

    test('08-e 임금 경로가 fresh를, 안내 경로가 advisory를 쓴다 (배선)', () {
      final wage = _flat(
          _codeOf(_bodyOf(_src(_editPath), 'Future<bool> _showWageGuardWarning(')));
      expect(wage.contains('await _applicationRelations.fresh();'), true);
      expect(wage.contains('advisory()'), false,
          reason: '최종 방어선이 안내용 캐시를 쓰면 안 된다');

      final preflight = _flat(
          _codeOf(_bodyOf(_src(_editPath), 'Future<bool> _canApplyWorkChange(')));
      expect(preflight.contains('await _applicationRelations.advisory();'), true);
      expect(preflight.contains('fresh()'), false,
          reason: '안내는 세션 캐시로 충분하다 — 서버가 최종 판정한다');
    });
  });

  // ── §4, §10 CONTRACT predicate ─────────────────────────────────
  group('PREFLIGHT-02 마스터 경로가 서버 blanket guard와 일치한다', () {
    // [POSTING-V2-03J.1 재작성] blanket이 필드별 정책으로 좁혀졌다.
    //   `mutatesWorkDetails`는 여전히 키 존재로 계산되고 03G.1 payload
    //   조건화의 근거로 남지만, 확정자 차단 조건은 이제
    //   `touchesUnverifiedFields`다 — 임금·인원·새 업무는 개별 guard가 본다.
    test('02-a 서버가 키 존재로 변경 여부를 판단한다 (전제 확인)', () {
      final fns = _src(_fnsPath);
      expect(fns.contains('const mutatesWorkDetails = "workDetails" in updates;'),
          true,
          reason: '값 비교가 아니라 키 존재 검사다 — 이 사실이 03G.1 payload 조건화의 근거');
      expect(
          fns.contains('if (!isSuperAdmin && touchesUnverifiedFields && '
              'freshConfirmed > 0) {'),
          true,
          reason: '확정자 차단은 미검증 필드에만 적용된다 (03J.1 §16)');
      expect(fns.contains('"확정된 지원자가 있는 공고의 근무 조건은 수정할 수 없습니다."'), true);
    });

    // [POSTING-V2-03J.1 재작성] 이 둘은 03G.1 시점의 blanket을 고정하고
    //   있었다. 정책이 필드별로 바뀌었으므로 기대값도 뒤집힌다 —
    //   확정자가 있어도 identity를 건드리지 않으면 허용된다.
    test('02-b 확정자가 있어도 인원 증가는 허용된다 (§10)', () {
      final apps = [const App('CONFIRMED', selectedWorkType: '피킹')];
      final original = [const Work('피킹', '09:00', '13:00')];
      final next = [const Work('피킹', '09:00', '13:00', requiredCount: 9)];
      expect(
          blockReason(
              apps: apps, original: original, next: next, isSlotMode: false),
          isNull,
          reason: '기존 약속은 스냅샷이 지킨다 — 모집 조건은 바꿀 수 있다');
    });

    test('02-b2 인원을 점유 인원 아래로 줄이면 막힌다', () {
      final apps = [
        const App('CONFIRMED', selectedWorkType: '피킹'),
        const App('CONTRACT_PENDING', selectedWorkType: '피킹'),
      ];
      final original = [const Work('피킹', '09:00', '13:00', requiredCount: 5)];
      final next = [const Work('피킹', '09:00', '13:00', requiredCount: 1)];
      expect(
          blockReason(
              apps: apps, original: original, next: next, isSlotMode: false),
          'REQUIRED_COUNT');
    });

    test('02-c 업무 추가는 허용된다', () {
      final apps = [const App('CONTRACT_PENDING', selectedWorkType: '피킹')];
      final original = [const Work('피킹', '09:00', '13:00')];
      final next = [
        const Work('피킹', '09:00', '13:00'),
        const Work('포장', '14:00', '18:00'),
      ];
      expect(
          blockReason(
              apps: apps, original: original, next: next, isSlotMode: false),
          isNull,
          reason: '새 업무 때문에 기존 확정자를 취소하게 만들지 않는다');
    });

    test('02-d 확정자가 없으면 identity만 본다 — 업무명 기준 (§4)', () {
      final apps = [const App('PENDING', selectedWorkType: '피킹')];
      final original = [
        const Work('피킹', '09:00', '13:00'),
        const Work('포장', '14:00', '18:00'),
      ];
      // 지원자 없는 '포장'만 제거 → 허용
      expect(
          blockReason(
              apps: apps,
              original: original,
              next: [const Work('피킹', '09:00', '13:00')],
              isSlotMode: false),
          isNull);
      // 지원자 있는 '피킹' 제거 → 차단
      expect(
          blockReason(
              apps: apps,
              original: original,
              next: [const Work('포장', '14:00', '18:00')],
              isSlotMode: false),
          'IDENTITY_TO');
    });

    test('02-e 서버도 이 경로에서 selectedWorkType으로 본다', () {
      final fns = _src(_fnsPath);
      expect(fns.contains('.where("selectedWorkType", "==", wt)'), true,
          reason: '슬롯 경로의 workDetailId 매칭과 다르다 — 복제 대상이 다름');
      final code = _flat(_codeOf(
          _bodyOf(_src(_editPath), 'String? _workChangeBlockReason(')));
      expect(code.contains("app['selectedWorkType'] == work.workType"), true);
    });

    test('02-f INVITED가 빠지지 않았다 (§K)', () {
      final apps = [const App('INVITED', selectedWorkType: '피킹')];
      expect(
          blockReason(
              apps: apps,
              original: [const Work('피킹', '09:00', '13:00')],
              next: const [],
              isSlotMode: false),
          'IDENTITY_TO',
          reason: 'INVITED는 어떤 클라이언트 카운터에도 없다 — 스냅샷으로만 알 수 있다');
      final code = _codeOf(_src(_editPath));
      expect(code.contains('AppStatus.invited,'), true);
    });

    test('02-g 종료된 지원은 제한 대상이 아니다', () {
      for (final st in ['REJECTED', 'CANCELED', 'AUTO_CANCELED', 'EXPIRED']) {
        expect(
            blockReason(
                apps: [App(st, selectedWorkType: '피킹')],
                original: [const Work('피킹', '09:00', '13:00')],
                next: const [],
                isSlotMode: false),
            isNull,
            reason: '$st 는 서버 predicate 어디에도 없다');
      }
    });
  });

  // ── §5, §11 FLEX predicate ─────────────────────────────────────
  group('PREFLIGHT-03 슬롯 경로가 날짜별로 독립이다', () {
    const workA = Work('피킹', '09:00', '13:00');

    test('03-a A에 지원자, B에는 없음 → B는 계속 수정 가능 (§5)', () {
      final apps = [
        const App('PENDING', slotId: 'slotA', workDetailId: '피킹_09:00_13:00'),
      ];
      expect(
          blockReason(
              apps: apps,
              original: [workA],
              next: const [],
              isSlotMode: true,
              slotIds: ['slotA']),
          'IDENTITY_SLOT');
      expect(
          blockReason(
              apps: apps,
              original: [workA],
              next: const [],
              isSlotMode: true,
              slotIds: ['slotB']),
          isNull,
          reason: 'B까지 과도하게 잠그지 않는다');
    });

    test('03-b 슬롯 경로는 CONFIRMED도 identity guard에 포함된다', () {
      expect(
          blockReason(
              apps: [
                const App('CONFIRMED',
                    slotId: 'slotA', workDetailId: '피킹_09:00_13:00')
              ],
              original: [workA],
              next: const [],
              isSlotMode: true,
              slotIds: ['slotA']),
          'IDENTITY_SLOT');
      final fns = _src(_fnsPath);
      expect(
          fns.contains('const ACTIVE_STATUSES_WITH_CONFIRMED = '
              '["PENDING", "INVITED", "CONTRACT_PENDING", "CONFIRMED"];'),
          true);
    });

    test('03-c 세 가지 매칭 패턴을 모두 본다', () {
      const legacy = App('PENDING', slotId: 's', workDetailId: '피킹');
      const byWdId = App('PENDING', slotId: 's', wdId: 'wd_1');
      const composite =
          App('PENDING', slotId: 's', workDetailId: '피킹_09:00_13:00');
      const work = Work('피킹', '09:00', '13:00', wdId: 'wd_1');
      for (final a in [legacy, byWdId, composite]) {
        expect(_matches(a, work), true);
      }
      final code = _flat(
          _codeOf(_bodyOf(_src(_editPath), 'bool _appMatchesWork(')));
      expect(code.contains("workDetailId == work.id"), true);
      expect(code.contains("workDetailId == work.workType"), true);
      expect(code.contains("app['wdId'] == wdId"), true);
    });

    test('03-d 필요 인원은 확정 인원 미만일 때만 막힌다 (§11)', () {
      final apps = [
        const App('CONFIRMED', slotId: 's', workDetailId: '피킹_09:00_13:00'),
        const App('CONFIRMED', slotId: 's', workDetailId: '피킹_09:00_13:00'),
        const App('CONTRACT_PENDING',
            slotId: 's', workDetailId: '피킹_09:00_13:00'),
      ];
      const original = [Work('피킹', '09:00', '13:00', requiredCount: 5)];
      // 5 → 4 : occupied(3) 이상이므로 허용
      expect(
          blockReason(
              apps: apps,
              original: original,
              next: const [Work('피킹', '09:00', '13:00', requiredCount: 4)],
              isSlotMode: true,
              slotIds: ['s']),
          isNull);
      // 3 → 2 : occupied 미만이므로 차단
      expect(
          blockReason(
              apps: apps,
              original: original,
              next: const [Work('피킹', '09:00', '13:00', requiredCount: 2)],
              isSlotMode: true,
              slotIds: ['s']),
          'REQUIRED_COUNT');
    });

    test('03-e 지원자가 있다는 이유만으로 인원 변경을 막지 않는다 (§11)', () {
      // PENDING만 있으면 정원을 차지하지 않는다
      expect(
          blockReason(
              apps: [
                const App('PENDING', slotId: 's', workDetailId: '피킹_09:00_13:00')
              ],
              original: const [Work('피킹', '09:00', '13:00', requiredCount: 5)],
              next: const [Work('피킹', '09:00', '13:00', requiredCount: 1)],
              isSlotMode: true,
              slotIds: ['s']),
          isNull);
    });

    test('03-f 슬롯 경로에는 마스터 blanket guard를 적용하지 않는다', () {
      // 다른 날짜의 확정자가 이 날짜의 수정을 막으면 안 된다
      expect(
          blockReason(
              apps: [
                const App('CONFIRMED',
                    slotId: 'other', workDetailId: '피킹_09:00_13:00')
              ],
              original: const [Work('포장', '14:00', '18:00')],
              next: const [],
              isSlotMode: true,
              slotIds: ['s']),
          isNull);
    });
  });

  // ── §2, §9 harmless edit ───────────────────────────────────────
  group('PREFLIGHT-04 허용된 수정은 계속 가능하다', () {
    test('04-a 수정 CTA를 숨기지 않았다 (§2)', () {
      final card = _codeOf(
          _src('lib/widgets/admin/cards/admin_to_group_card.dart'));
      expect(card.contains('if (canManageTo && !isClosed)'), true,
          reason: '지원자 존재를 CTA 조건에 넣지 않는다');
      expect(card.contains('totalConfirmed > 0'), false);
      expect(card.contains('hasActiveApplication'), false);
    });

    test('04-b 업무를 안 바꿨으면 payload에서 뺀다 (§9)', () {
      final body = _flat(_codeOf(_bodyOf(_src(_editPath), 'Future<void> _saveChanges(')));
      expect(body.contains('final workDetailsChanged = _hasWorkDetailsChanged();'),
          true);
      expect(
          body.contains("if (workDetailsChanged) ...{ "
              "'workDetails': WorkDetailData.listToFirestore(_workDetails), "
              "'totalRequired': totalRequired, },"),
          true,
          reason: '확정자가 있으면 키가 실린 것만으로 전체 저장이 거부된다');
    });

    test('04-c 변경 감지가 필드를 빠뜨리지 않는다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_editPath), 'bool _hasWorkDetailsChanged(')));
      // 직렬화 전체를 비교한다 — 필드 목록을 손으로 나열하지 않는다
      expect(body.contains('WorkDetailData.listToCFPayload(_originalWorkDetails)'),
          true);
      expect(body.contains('WorkDetailData.listToCFPayload(_workDetails)'), true);
      expect(body.contains('if (a.length != b.length) return true;'), true);
    });

    test('04-d 제한을 만나도 화면 전체를 잠그지 않는다 (§9)', () {
      final code = _codeOf(_src(_editPath));
      expect(code.contains('_isReadOnly'), false);
      expect(code.contains('_editLocked'), false);
      expect(code.contains('AbsorbPointer'), false);
      // 제목/설명/공개설정은 언제나 payload에 실린다
      final body = _flat(_codeOf(_bodyOf(_src(_editPath), 'Future<void> _saveChanges(')));
      expect(body.contains("'title': _titleController.text.trim(),"), true);
      expect(body.contains("'description': _descriptionController.text.trim(),"),
          true);
      expect(body.contains("'publishMode': _publishMode,"), true);
    });

    test('04-e 저장 버튼을 지원자 유무로 비활성화하지 않았다', () {
      final code = _codeOf(_src(_editPath));
      expect(code.contains('_applicationSnapshot == null ? null :'), false);
      expect(code.contains('_applicationSnapshotFailed ? null :'), false);
    });
  });

  // ── §7 fetch failure ───────────────────────────────────────────
  group('PREFLIGHT-05 조회 실패가 수정을 막지 않는다', () {
    test('05-a 스냅샷이 없으면 통과시키고 서버에 맡긴다 (§7)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_editPath), 'Future<bool> _canApplyWorkChange(')));
      expect(body.contains('if (apps == null) return true;'), true,
          reason: "조회 실패를 '지원자가 있으므로 불가'로 오인하지 않는다");
    });

    // [TC2 재작성] 실패 기록은 advisory 전용이다 — fresh는 기억하지 않는다.
    test('05-b 안내 실패를 기록하되 차단 상태로 쓰지 않는다', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_editPath), 'Future<List<Map<String, dynamic>>?> advisory(')));
      expect(body.contains('_advisoryFailed = true; return null;'), true);
      expect(body.contains('rethrow'), false);
      expect(body.contains('ToastHelper'), false,
          reason: '조회 실패 자체는 사용자 행동을 요구하지 않는다');

      final fresh = _flat(
          _codeOf(_bodyOf(_src(_editPath), 'Future<List<Map<String, dynamic>>?> fresh(')));
      expect(fresh.contains('_advisoryFailed = true'), false,
          reason: '저장은 다시 눌러 볼 수 있어야 한다 (§4, §8)');
    });

    test('05-c WAGE-GUARD의 FAIL CLOSE는 그대로다 (§13, TC2 §4)', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_editPath), 'Future<bool> _showWageGuardWarning(')));
      expect(body.contains('if (appsRaw == null) {'), true);
      expect(
          body.contains("ToastHelper.showError('지원자 상태를 확인하지 못했습니다. "
              "잠시 후 다시 시도해주세요.'); return false;"),
          true,
          reason: '임금은 서버 가드가 없어 이 경고가 마지막 방어선이다');
      // [POSTING-V2-03I.3 재작성] 경고의 구조(확인 후 계속 저장)는 그대로다.
      //   제목만 두 번 바뀌었다: '급여 계산 조건 변경'(부정확) →
      //   '모집 임금 변경'(금액만) → '임금 및 급여 산정 조건 변경'(현재).
      //   약속 범위가 금액에서 산정 조건 전체로 확정된 결과다.
      expect(body.contains("title: '임금 및 급여 산정 조건 변경',"), true);
      expect(body.contains("text: '계속 저장',"), true);
      expect(body.contains("title: '급여 계산 조건 변경',"), false);
      expect(body.contains("title: '모집 임금 변경',"), false);
    });

    test('05-d 조회 실패를 확정자 없음으로 간주하지 않는다 (TC2 §4)', () async {
      final r = EditApplicationRelations(() async => throw StateError('network'));
      final apps = await r.fresh();
      expect(apps, isNull, reason: 'null과 빈 목록은 다르다');
      expect(apps == null, isNot(false));
      // 빈 목록이었다면 _hasConfirmed가 false를 돌려 저장이 통과했을 것이다
      expect(_hasConfirmed(const []), false);
    });
  });

  // ── §14, §15 서버 canonical 유지 ───────────────────────────────
  group('PREFLIGHT-06 서버가 최종 판정을 계속 한다', () {
    test('06-a 서버 guard를 제거·완화하지 않았다 (§14)', () {
      final fns = _src(_fnsPath);
      for (final marker in [
        '"확정된 지원자가 있는 공고의 근무 조건은 수정할 수 없습니다."',
        '업무에 활성 지원자가 있어 업무 구성을 변경할 수 없습니다',
        '"해당 업무 시간대에 활성 지원자가 있어 업무 구성을 변경할 수 없습니다. 해당 지원을 먼저 처리해주세요."',
        '활성 지원자가 있는 공고의 계약 기간을 변경할 수 없습니다',
        // [POSTING-V2-03J.1] CONFIRMED 추가 — blanket이 좁아지면서 이 guard가
        //   확정 근무자의 업무·시간 약속을 지키는 자리가 됐다.
        'const ACTIVE_STATUSES =\n'
            '          ["PENDING", "INVITED", "CONTRACT_PENDING", "CONFIRMED"];',
      ]) {
        expect(fns.contains(marker), true, reason: '$marker 가 사라졌다');
      }
    });

    test('06-b 저장 실패 경로가 그대로 서버 문구를 쓴다 (§14)', () {
      for (final sig in [
        'Future<void> _saveChanges(',
        'Future<void> _saveSlotChanges(',
        'Future<void> _saveBatchSlotChanges(',
      ]) {
        final body = _flat(_codeOf(_bodyOf(_src(_editPath), sig)));
        expect(body.contains("_cfErrorMessage(e) ?? '수정에 실패했습니다'"), true,
            reason: '$sig — preflight 이후 도착한 지원자는 여기서 걸린다');
      }
    });

    test('06-c preflight 결과를 최종 허가로 쓰지 않는다', () {
      final body = _codeOf(_bodyOf(_src(_editPath), 'Future<void> _saveChanges('));
      expect(body.contains('if (_applicationSnapshot != null) return;'), false);
      expect(body.contains('_workChangeBlockReason'), false,
          reason: '저장 경로에서 다시 판정하지 않는다 — 서버가 한다');
    });

    test('06-d 서버 transaction 구조를 건드리지 않았다 (§15)', () {
      final fns = _src(_fnsPath);
      expect(fns.contains('// identity 변경/삭제 → ACTIVE 지원자 검증 (transaction 외부에서 실행)'),
          true,
          reason: '[BACKLOG-EDIT-IDENTITY-GUARD-NON-TRANSACTIONAL] 은 이번 범위 밖');
    });
  });

  // ── §12, §13 범위 ──────────────────────────────────────────────
  group('PREFLIGHT-07 범위를 넘지 않았다', () {
    test('07-a 계약 기간은 화면에서 읽기 전용이다 — preflight 대상 아님 (§12)', () {
      final code = _flat(_codeOf(_src(_editPath)));
      expect(code.contains('TODateSelector( isLongTerm: widget.to.isContractType, isReadOnly: true,'),
          true,
          reason: 'rangeStart/rangeEnd는 payload에 실리지 않는다');
      final body = _flat(_codeOf(_bodyOf(_src(_editPath), 'Future<void> _saveChanges(')));
      expect(body.contains("'rangeStart'"), false);
      expect(body.contains("'rangeEnd'"), false);
    });

    test('07-b FLEX 임금 정책을 건드리지 않았다 (§13)', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_editPath), 'bool _hasWageFieldsChanged(')));
      expect(body.contains('cur.wage != orig.wage'), true);
      expect(body.contains('cur.wageType != orig.wageType'), true);
      // preflight가 임금 변경을 막지 않는다 — 서버에 가드가 없고 정책 결정 전이다
      final reason = _flat(_codeOf(
          _bodyOf(_src(_editPath), 'String? _workChangeBlockReason(')));
      expect(reason.contains('wage'), false);
    });

    test('07-c 새 장문 policy dialog를 만들지 않았다 (§8)', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_editPath), 'Future<bool> _canApplyWorkChange(')));
      expect(body.contains('ToastHelper.showError(reason);'), true);
      expect(body.contains('showDialog'), false);
      expect(body.contains('StyledDialog'), false);
    });

    test('07-d 안내 문구가 서버와 같은 계열이다 (§8)', () {
      final body = _codeOf(
          _bodyOf(_src(_editPath), 'String? _workChangeBlockReason('));
      expect(body.contains('활성 지원자가 있어 업무 구성을 변경할 수 없습니다'), true);
      expect(body.contains('보다 작게 설정할 수 없습니다'), true);
      // [POSTING-V2-03J.1 재작성] 마스터 경로의 blanket 문구는 client에서
      //   사라졌다 — 서버가 미검증 필드에만 쓰므로 client가 선제로 말하면
      //   서버는 허용하는데 화면이 먼저 막는 상태가 된다.
      expect(body.contains('확정된 지원자가 있는 공고의 근무 조건은 수정할 수 없습니다.'), false);
      expect(_src(_fnsPath).contains('"확정된 지원자가 있는 공고의 근무 조건은 수정할 수 없습니다."'),
          true, reason: '서버 canonical 문구는 그대로 남는다');
    });
  });
}
