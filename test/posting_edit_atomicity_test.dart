// [POSTING-V2-03H.1] CONTRACT 공고 수정 — 지원 관계와의 원자성
//
// 03H READ에서 확인된 것:
//   · callableUpdateTO의 identity guard와 확정자 guard가 runTransaction **밖**에
//     있었다. 트랜잭션은 재시도돼도 callback만 다시 돌므로, 그 두 판정은
//     한 번 계산된 뒤 재검증되지 않았다.
//   · apply·invite·confirm은 모두 toRef를 쓴다. 그래서 edit 트랜잭션은 반드시
//     충돌해 재시도되는데, 재시도에서 guard가 다시 실행되지 않으니
//     "조회 0건 → 지원 발생 → commit 성공"이 그대로 성립했다.
//   · 창은 좁지 않다. guard 조회부터 최종 commit까지 권한 조회·업무 범위 조회·
//     트랜잭션 왕복이 모두 들어간다. 오히려 재시도가 난 경우가 정확히 위험했다.
//   · FLEX 슬롯 경로는 guard가 callback 안에 있어 재시도 때 다시 실행된다 —
//     쿼리가 트랜잭션 읽기가 아니어도 보호된다. 그래서 손대지 않는다.
//
// 공식 문서 근거(03H READ):
//   "a function calling a transaction (transaction function) might run more than
//    once if a concurrent edit affects a document that the transaction reads"
//   "A transaction's lock on a document blocks other transactions, batched
//    writes, and non-transactional writes."
//
// Functions는 Dart 테스트에서 실행할 수 없다. 배선은 소스로, 재시도 의미는
// 트랜잭션 수명주기 replica로 검증한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnsPath = 'functions/src/index.ts';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

/// `export const callableX = onCall(` 부터 짝이 맞는 닫는 괄호까지.
String _callableOf(String source, String name) {
  final start = source.indexOf('export const $name = onCall(');
  if (start == -1) throw StateError('$name 을 찾지 못함');
  var depth = 0;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    if (source[i] == '(') depth++;
    if (source[i] == ')') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('$name 본문의 끝을 찾지 못함');
}

/// `await db.runTransaction(async (name) => {` 의 callback 본문.
String _txBodyOf(String source, String txVar) {
  final marker = 'db.runTransaction(async ($txVar) => {';
  final start = source.indexOf(marker);
  if (start == -1) throw StateError('$txVar 트랜잭션을 찾지 못함');
  final open = source.indexOf('{', start + marker.length - 1);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('$txVar 트랜잭션 본문의 끝을 찾지 못함');
}

// ═══════════════════════════════════════════════════════════════
// 트랜잭션 수명주기 replica
// ═══════════════════════════════════════════════════════════════

class AppRow {
  final String status;
  final String selectedWorkType;
  const AppRow(this.status, this.selectedWorkType);
}

/// 서버 상태 — apply/invite/confirm이 바꾸는 부분만.
class ServerState {
  int totalConfirmed;
  int toRefVersion; // apply·invite·confirm이 toRef를 쓸 때마다 증가
  final List<AppRow> applications;
  ServerState({
    this.totalConfirmed = 0,
    this.toRefVersion = 0,
    List<AppRow>? applications,
  }) : applications = applications ?? [];

  /// 신규 PENDING / INVITED — application 생성 + toRef.totalPending +1
  void createApplication(String status, String workType) {
    applications.add(AppRow(status, workType));
    toRefVersion++; // tx.update(toRef, {totalPending: increment(1)})
  }

  /// PENDING → CONTRACT_PENDING / CONFIRMED — 카운터가 toRef를 바꾼다
  void promoteToConfirmed(String workType) {
    applications.removeWhere((a) => a.selectedWorkType == workType);
    applications.add(AppRow('CONFIRMED', workType));
    totalConfirmed++;
    toRefVersion++;
  }
}

class EditRejected implements Exception {
  final String reason;
  EditRejected(this.reason);
}

const _identityStatuses = ['PENDING', 'INVITED', 'CONTRACT_PENDING'];

/// callableUpdateTO 실행 replica.
///
/// [guardsInsideTx] false = 수정 전(guard가 TX 밖, 재시도해도 재실행 안 됨)
/// [guardsInsideTx] true  = 수정 후(guard가 callback 안, 재시도마다 재실행)
///
/// [duringAttempt]는 각 시도의 read 직후·commit 직전에 끼어드는 동시 작업이다.
({bool committed, String? reason, int attempts, int identityQueries}) runUpdateTO({
  required ServerState server,
  required List<String> removedWorkTypes,
  required bool mutatesWorkDetails,
  required bool guardsInsideTx,
  void Function(ServerState)? duringAttempt,
  int maxAttempts = 5,
}) {
  var identityQueries = 0;

  // ── TX 밖 (한 번만 실행된다) ──
  bool preConfirmedBlocked = false;
  bool preIdentityBlocked = false;
  if (!guardsInsideTx) {
    preConfirmedBlocked = mutatesWorkDetails && server.totalConfirmed > 0;
    if (removedWorkTypes.isNotEmpty) {
      identityQueries++;
      preIdentityBlocked = server.applications.any((a) =>
          _identityStatuses.contains(a.status) &&
          removedWorkTypes.contains(a.selectedWorkType));
    }
    if (preConfirmedBlocked) {
      return (
        committed: false,
        reason: 'CONFIRMED_BLANKET',
        attempts: 0,
        identityQueries: identityQueries
      );
    }
    if (preIdentityBlocked) {
      return (
        committed: false,
        reason: 'IDENTITY',
        attempts: 0,
        identityQueries: identityQueries
      );
    }
  }

  // ── runTransaction ──
  var attempts = 0;
  var interfered = false;
  while (attempts < maxAttempts) {
    attempts++;
    final readVersion = server.toRefVersion; // txEdit.get(toRef)
    final freshConfirmed = server.totalConfirmed;

    if (guardsInsideTx) {
      if (mutatesWorkDetails && freshConfirmed > 0) {
        return (
          committed: false,
          reason: 'CONFIRMED_BLANKET',
          attempts: attempts,
          identityQueries: identityQueries
        );
      }
      if (removedWorkTypes.isNotEmpty) {
        identityQueries++;
        final blocked = server.applications.any((a) =>
            _identityStatuses.contains(a.status) &&
            removedWorkTypes.contains(a.selectedWorkType));
        if (blocked) {
          return (
            committed: false,
            reason: 'IDENTITY',
            attempts: attempts,
            identityQueries: identityQueries
          );
        }
      }
    }

    // 첫 시도에서만 동시 작업이 끼어든다
    if (!interfered && duringAttempt != null) {
      duringAttempt(server);
      interfered = true;
    }

    // commit — 읽은 toRef가 그 사이 바뀌었으면 충돌 → 재시도
    if (server.toRefVersion != readVersion) continue;
    return (
      committed: true,
      reason: null,
      attempts: attempts,
      identityQueries: identityQueries
    );
  }
  return (
    committed: false,
    reason: 'RETRY_EXHAUSTED',
    attempts: attempts,
    identityQueries: identityQueries
  );
}

void main() {
  // ── §20 structural ────────────────────────────────────────────
  group('ATOMICITY-01 guard가 트랜잭션 안에 있다', () {
    late final String updateTO = _callableOf(_src(_fnsPath), 'callableUpdateTO');
    late final String txEdit = _txBodyOf(updateTO, 'txEdit');

    test('01-a identity application query가 TX 밖에 없다 (§3)', () {
      final outside = updateTO.replaceFirst(txEdit, '');
      expect(outside.contains('.where("selectedWorkType", "==", wt)'), false,
          reason: 'TX 밖 조회는 재시도 때 다시 실행되지 않는다');
      expect(outside.contains('const hasActive'), false);
    });

    test('01-b identity query가 txEdit.get(query)를 쓴다 (§4)', () {
      final body = _flat(_codeOf(txEdit));
      expect(
          body.contains('txEdit.get( db.collection("applications") '
              '.where("toId", "==", toId) '
              '.where("selectedWorkType", "==", wt) '
              '.where("status", "==", st) .limit(1) )'),
          true,
          reason: 'date guard와 같은 방식으로 정렬한다');
    });

    test('01-c identity guard가 txEdit.update보다 앞이다 (§5)', () {
      final body = _codeOf(txEdit);
      final guard = body.indexOf('identityWorkTypesToGuard.length > 0');
      final write = body.indexOf('txEdit.update(toRef,');
      expect(guard, greaterThan(-1));
      expect(write, greaterThan(guard), reason: 'read-before-write를 지킨다');
    });

    test('01-d 모든 read가 write보다 앞이다 (§D)', () {
      final body = _codeOf(txEdit);
      final write = body.indexOf('txEdit.update(toRef,');
      expect(write, greaterThan(-1));
      for (final read in ['txEdit.get(toRef)', 'txEdit.get(']) {
        expect(body.lastIndexOf(read), lessThan(write), reason: read);
      }
    });

    test('01-e 확정자 guard가 freshData를 쓴다 (§6)', () {
      final body = _flat(_codeOf(txEdit));
      expect(
          body.contains('const freshConfirmed = '
              '(freshData.totalConfirmed as number | undefined) ?? 0;'),
          true);
      // [POSTING-V2-03J.1 재작성] 조건이 `mutatesWorkDetails` →
      //   `touchesUnverifiedFields`로 좁혀졌다(§16). 03H가 고정한 것은
      //   "판정이 freshData 기준"이라는 점이고 그것은 그대로다.
      expect(
          body.contains('if (!isSuperAdmin && touchesUnverifiedFields && freshConfirmed > 0) {'),
          true);
    });

    test('01-f stale toData 기반 canonical guard가 제거됐다 (§6)', () {
      final outside = _flat(_codeOf(updateTO.replaceFirst(txEdit, '')));
      expect(
          outside.contains('"workDetails" in updates && totalConfirmed > 0'), false,
          reason: 'TX 밖 스냅샷으로 확정 여부를 최종 판단하지 않는다');
    });

    test('01-g removedOrChanged 계산은 TX 밖에 남는다 (§2)', () {
      final outside = _codeOf(updateTO.replaceFirst(txEdit, ''));
      expect(outside.contains('identityWorkTypesToGuard.push('), true,
          reason: 'application read가 아닌 순수 비교다');
      expect(outside.contains('const identityWorkTypesToGuard: string[] = [];'),
          true);
    });

    test('01-h 서버 메시지가 그대로다 (§18)', () {
      final body = _codeOf(txEdit);
      expect(body.contains('"확정된 지원자가 있는 공고의 근무 조건은 수정할 수 없습니다."'), true);
      expect(
          body.contains("업무에 활성 지원자가 있어 업무 구성을 변경할 수 없습니다. 해당 지원을 먼저 처리해주세요."),
          true);
      // [POSTING-V2-03J.1 재작성] 03H 시점에는 확정자를 blanket이 따로 막고
      //   있어 identity guard에 CONFIRMED가 없어도 됐다. blanket이 좁아지면서
      //   이 guard가 확정 약속을 지키는 자리가 되어 CONFIRMED가 추가됐다.
      //   메시지 자체는 그대로다.
      expect(
          body.contains('const ACTIVE_STATUSES =\n'
              '          ["PENDING", "INVITED", "CONTRACT_PENDING", "CONFIRMED"];'),
          true,
          reason: 'FLEX의 ACTIVE_STATUSES_WITH_CONFIRMED와 같은 집합');
    });
  });

  // ── §9~§11 behavior ───────────────────────────────────────────
  group('ATOMICITY-02 수정 후에는 race가 막힌다', () {
    test('02-a PENDING race — 재시도에서 잡는다 (§9)', () {
      final server = ServerState();
      final r = runUpdateTO(
        server: server,
        removedWorkTypes: ['A'],
        mutatesWorkDetails: true,
        guardsInsideTx: true,
        duringAttempt: (s) => s.createApplication('PENDING', 'A'),
      );
      expect(r.committed, false);
      expect(r.reason, 'IDENTITY');
      expect(r.attempts, 2, reason: 'toRef 충돌로 한 번 재시도한다');
      expect(r.identityQueries, 2, reason: '재시도에서 다시 조회했다');
      // 최종 상태: 지원서가 살아 있고 업무는 그대로다
      expect(server.applications.length, 1);
    });

    test('02-b INVITED race (§10)', () {
      final server = ServerState();
      final r = runUpdateTO(
        server: server,
        removedWorkTypes: ['A'],
        mutatesWorkDetails: true,
        guardsInsideTx: true,
        duringAttempt: (s) => s.createApplication('INVITED', 'A'),
      );
      expect(r.committed, false);
      expect(r.reason, 'IDENTITY');
    });

    test('02-c CONTRACT_PENDING race', () {
      final server = ServerState();
      final r = runUpdateTO(
        server: server,
        removedWorkTypes: ['A'],
        mutatesWorkDetails: true,
        guardsInsideTx: true,
        duringAttempt: (s) => s.createApplication('CONTRACT_PENDING', 'A'),
      );
      expect(r.committed, false);
      expect(r.reason, 'IDENTITY');
    });

    test('02-d CONFIRMED transition race — blanket guard가 잡는다 (§11)', () {
      final server = ServerState();
      server.createApplication('PENDING', 'A');
      final r = runUpdateTO(
        server: server,
        removedWorkTypes: const [], // identity는 그대로, 임금/인원만 변경
        mutatesWorkDetails: true,
        guardsInsideTx: true,
        duringAttempt: (s) => s.promoteToConfirmed('A'),
      );
      expect(r.committed, false);
      expect(r.reason, 'CONFIRMED_BLANKET');
      expect(r.attempts, 2, reason: '확정이 toRef를 바꿔 재시도됐다');
    });

    test('02-e 다른 업무의 지원자는 막지 않는다', () {
      final server = ServerState();
      final r = runUpdateTO(
        server: server,
        removedWorkTypes: ['A'],
        mutatesWorkDetails: true,
        guardsInsideTx: true,
        duringAttempt: (s) => s.createApplication('PENDING', 'B'),
      );
      expect(r.committed, true, reason: 'B 지원자가 A 삭제를 막을 이유가 없다');
    });

    test('02-f 종료된 지원은 막지 않는다', () {
      for (final st in ['REJECTED', 'CANCELED', 'AUTO_CANCELED', 'EXPIRED']) {
        final server = ServerState();
        final r = runUpdateTO(
          server: server,
          removedWorkTypes: ['A'],
          mutatesWorkDetails: true,
          guardsInsideTx: true,
          duringAttempt: (s) => s.createApplication(st, 'A'),
        );
        expect(r.committed, true, reason: '$st 는 predicate에 없다');
      }
    });

    test('02-g 방해가 없으면 정상 commit — 조회 1회 (§17)', () {
      final server = ServerState();
      final r = runUpdateTO(
        server: server,
        removedWorkTypes: ['A'],
        mutatesWorkDetails: true,
        guardsInsideTx: true,
      );
      expect(r.committed, true);
      expect(r.attempts, 1);
      expect(r.identityQueries, 1, reason: '정상 경로 read는 이전과 같다');
    });

    test('02-h workDetails를 안 보내면 확정자가 있어도 통과 (§7, 03G 무회귀)', () {
      final server = ServerState(totalConfirmed: 3);
      final r = runUpdateTO(
        server: server,
        removedWorkTypes: const [],
        mutatesWorkDetails: false, // 제목만 수정
        guardsInsideTx: true,
      );
      expect(r.committed, true);
      expect(r.identityQueries, 0, reason: '조회할 이유가 없다');
    });

    test('02-i workDetails를 보내면 확정자가 있을 때 막힌다 (§7 정책 무변경)', () {
      final server = ServerState(totalConfirmed: 1);
      final r = runUpdateTO(
        server: server,
        removedWorkTypes: const [],
        mutatesWorkDetails: true,
        guardsInsideTx: true,
      );
      expect(r.committed, false);
      expect(r.reason, 'CONFIRMED_BLANKET',
          reason: '"값이 바뀌었는지"로 좁히지 않는다 — 키 존재 기준 유지');
    });
  });

  // ── 수정 전 구조가 왜 위험했는지 ───────────────────────────────
  group('ATOMICITY-03 이전 구조는 같은 race를 통과시킨다', () {
    test('03-a TX 밖 guard는 재시도해도 다시 검사하지 않는다', () {
      final server = ServerState();
      final before = runUpdateTO(
        server: server,
        removedWorkTypes: ['A'],
        mutatesWorkDetails: true,
        guardsInsideTx: false, // 수정 전
        duringAttempt: (s) => s.createApplication('PENDING', 'A'),
      );
      expect(before.committed, true,
          reason: '이것이 03H가 찾은 결함이다 — 지원서는 남고 업무는 사라진다');
      expect(before.attempts, 2, reason: '재시도는 났지만 guard가 다시 돌지 않았다');
      expect(before.identityQueries, 1);

      // 같은 시나리오가 수정 후에는 막힌다
      final server2 = ServerState();
      final after = runUpdateTO(
        server: server2,
        removedWorkTypes: ['A'],
        mutatesWorkDetails: true,
        guardsInsideTx: true,
        duringAttempt: (s) => s.createApplication('PENDING', 'A'),
      );
      expect(after.committed, false);
    });

    test('03-b 확정 transition도 마찬가지였다', () {
      final server = ServerState();
      server.createApplication('PENDING', 'A');
      final before = runUpdateTO(
        server: server,
        removedWorkTypes: const [],
        mutatesWorkDetails: true,
        guardsInsideTx: false,
        duringAttempt: (s) => s.promoteToConfirmed('A'),
      );
      expect(before.committed, true);
      expect(server.totalConfirmed, 1,
          reason: '확정자가 생겼는데 근무 조건이 바뀌었다');
    });
  });

  // ── §12~§15 무회귀 ────────────────────────────────────────────
  group('ATOMICITY-04 나머지는 건드리지 않았다', () {
    late final String updateTO = _callableOf(_src(_fnsPath), 'callableUpdateTO');

    test('04-a date guard 그대로 (§13)', () {
      final body = _flat(_codeOf(_txBodyOf(updateTO, 'txEdit')));
      expect(
          body.contains('const DATE_ACTIVE_STATUSES = '
              '["PENDING", "INVITED", "CONTRACT_PENDING", "CONFIRMED"];'),
          true);
      expect(body.contains('if (isDateChange && !isSuperAdmin) {'), true);
      expect(
          body.contains('"활성 지원자가 있는 공고의 계약 기간을 변경할 수 없습니다. 지원자를 먼저 처리해주세요."'),
          true);
    });

    test('04-b totalRequired guard 그대로 (§12)', () {
      final body = _flat(_codeOf(_txBodyOf(updateTO, 'txEdit')));
      expect(body.contains('if (!isSuperAdmin && "totalRequired" in finalUpdates) {'),
          true);
      expect(body.contains('newReq !== 0 && newReq < freshConfirmed'), true,
          reason: '별도 count 쿼리를 추가하지 않았다');
    });

    test('04-c FLEX 경로 무수정 (§14)', () {
      final slot = _callableOf(_src(_fnsPath), 'callableUpdateSlotWorkDetails');
      expect(slot.contains('await checkActiveApplications('), true);
      expect(slot.contains('await checkRequiredCountLowerBound('), true);
      // 불필요한 tx.get(query) 전환을 하지 않았다
      expect(slot.contains('tx.get(\n'), false);
      final helper = _flat(_codeOf(slot));
      expect(helper.contains('const ACTIVE_STATUSES_WITH_CONFIRMED = '
          '["PENDING", "INVITED", "CONTRACT_PENDING", "CONFIRMED"];'), true);
    });

    test('04-d application mutation 무수정 (§15)', () {
      final fns = _src(_fnsPath);
      for (final name in [
        'callableApplyToTO',
        'callableInviteWorker',
        'callableConfirmApplication',
      ]) {
        expect(fns.contains('export const $name = onCall('), true, reason: name);
      }
      // toRef를 쓰는 성질이 동기화 지점이다 — 그대로 유지
      final apply = _codeOf(_callableOf(fns, 'callableApplyToTO'));
      expect(
          apply.contains('tx.update(toRef, {totalPending: admin.firestore.FieldValue.increment(1)});'),
          true,
          reason: '이 write가 사라지면 edit 트랜잭션이 충돌하지 않는다');
    });

    test('04-e editRevision 의미를 확대하지 않았다 (§16)', () {
      final fns = _src(_fnsPath);
      final apply = _codeOf(_callableOf(fns, 'callableApplyToTO'));
      expect(apply.contains('editRevision'), false,
          reason: '지원이 configuration revision을 올리게 만들지 않는다');
      final confirm = _codeOf(_callableOf(fns, 'callableConfirmApplication'));
      expect(confirm.contains('editRevision: admin.firestore.FieldValue.increment'),
          false);
      expect(fns.contains('relationRevision'), false);
    });

    test('04-f schema 변경 없음 (§22)', () {
      final fns = _src(_fnsPath);
      expect(fns.contains('applicationRevision'), false);
      expect(fns.contains('relationVersion'), false);
    });
  });
}
