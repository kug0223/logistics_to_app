// [CORRECTION-R7-PARTIAL-LOCAL-CAPACITY-AUTHORITY] mutation 직후의 로컬 산술이
// 현재 정원 truth 로 행세하지 않는다.
//
//   DEVICE.1E.1 은 "로컬 값을 과도기로 쓰고 canonical 로 수렴한다" 로 닫았다.
//   최종 수렴은 **중간 표시와 action 안전성을 증명하지 않는다.**
//
//   확인해 보니 `applyLocal` 이 `_failed = false` 로 두어 그 수가 성공한
//   canonical 값과 구분되지 않았다. 그래서 그 값으로
//
//     · `inviteCapacityStateOf` 가 `FULL`(모집 완료)을 **새로 확정**하고
//     · `staffingShortageOf` 가 초대 CTA 를 게이팅·라벨링했다.
//
//   그 산술은 canonical 과 두 가지가 다르다.
//     identity — 화면 재집계는 `workDetailId`(+workType·시간 폴백)로 맞추고
//                `wdId` 를 보지 않는다. canonical 은 `wdId` 를 먼저 본다.
//                workType·시간이 같고 wdId 만 다른 두 업무가 있으면 같은
//                지원서를 둘 다에 세어 **과대 집계**한다.
//     동시성   — 다른 관리자의 확정은 보이지 않는다.
//
//   그래서 표시는 하되 판단하지 않는다. 출처를 구분한다.
//
//   ── 정정 ────────────────────────────────────────────────────────
//   DEVICE.1E.1 은 근거를 "목록이 페이징돼 부분집합일 수 있다" 로 적었다.
//   그 근거는 **틀렸다** — `fetchApplicationsByBizPaged` 는 페이지를 모두
//   소진하고, 남으면 던진다. 실제 위험은 identity 와 동시성이다.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/capacity_load_state.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';

// ═══════════════════════════════════════════════════════════════
// fixture — §4 의 synthetic 시나리오 (DEV 사용자 데이터 조작 아님)
// ═══════════════════════════════════════════════════════════════

const _key = '사무업무_06:00_08:00';
const _required = 12;

WorkDetailData _work() => WorkDetailData(
      workType: '사무업무',
      startTime: '06:00',
      endTime: '08:00',
      requiredCount: _required,
      wage: 12000,
    );

Map<String, dynamic> _canonical(int confirmed) => {
      'workDetails': [_work()],
      'workStats': {
        _key: {'confirmed': confirmed, 'pending': 0}
      },
      'statsFailed': false,
    };

Map<String, dynamic> _failedRead() => {
      'workDetails': [_work()],
      // 실패해도 전부 0 으로 seed 된 map 이 함께 온다.
      'workStats': {
        _key: {'confirmed': 0, 'pending': 0}
      },
      'statsFailed': true,
    };

Map<String, Map<String, int>> _local(int confirmed) => {
      _key: {'confirmed': confirmed, 'pending': 0}
    };

// ═══════════════════════════════════════════════════════════════
// 화면 소비자가 읽는 상태 — 제품과 **같은 함수**로 파생한다.
//
//   `_canonicalConfirmed` → `inviteCapacityStateOf` → `staffingShortageOf`
//   → CTA gate. 계산식을 베끼지 않고 production 함수를 실행한다.
// ═══════════════════════════════════════════════════════════════

typedef Surface = ({
  int? displayed, // 화면에 적히는 충원 수 (null = 적지 않음)
  InviteCapacityState capacity,
  int? shortage, // null = 부족을 말하지 않는다
  bool pending, // `정원 갱신 중`
  bool errorNotice, // `정원 확인 불가 + 다시 시도`
  bool inviteAllowed, // 초대 action 을 허용하는가
  bool claimsFull, // `모집 완료`를 확정하는가
});

Surface surfaceOf(CapacityLoadState cap, {bool isClosed = false}) {
  final work = _work();
  final canonicalConfirmed = cap.confirmedFor(work); // 판단용
  final capacity = inviteCapacityStateOf(
    canonicalConfirmed: canonicalConfirmed,
    requiredCount: work.requiredCount,
    isClosed: isClosed,
  );
  final shortage = staffingShortageOf(
    capacity: capacity,
    requiredCount: work.requiredCount,
    seatedConfirmed: canonicalConfirmed ?? 0,
  );
  final unknown = capacity == InviteCapacityState.unknown;
  return (
    displayed: cap.displayConfirmedFor(work), // 표시용
    capacity: capacity,
    shortage: shortage,
    pending: unknown && cap.isPending,
    errorNotice: unknown && !cap.isPending,
    inviteAllowed:
        capacity == InviteCapacityState.available && (shortage ?? 0) > 0,
    claimsFull: capacity == InviteCapacityState.full,
  );
}

String _read(String p) => File(p).readAsStringSync();
String _codeOf(String d) => d
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  // ══════════════════════════════════════════════════════════════
  // A. mutation 성공 → 후속 조회 대기
  // ══════════════════════════════════════════════════════════════

  group('PLC-A 부분 로컬 값이 total 로 publish 되지 않는다', () {
    test('PLC-A1 canonical 10/12 → 로컬 5 → 대기 중 false shortage/FULL/action 없음',
        () async {
      final gate = Completer<Map<String, dynamic>>();
      final cap = CapacityLoadState(loader: () => gate.future);
      cap.seed(_local(10), parentFailed: false); // canonical 출처

      // 시작 상태: canonical 10 / 필요 12
      var s = surfaceOf(cap);
      expect(s.capacity, InviteCapacityState.available);
      expect(s.shortage, 2);
      expect(s.inviteAllowed, isTrue);

      // mutation 성공 → 화면 목록은 5명분만 보고 다시 세었다.
      cap.applyLocal(_local(5));

      s = surfaceOf(cap);
      expect(cap.isCanonical, isFalse, reason: '출처가 구분된다');
      expect(s.displayed, 5, reason: '방금 한 처리는 화면에 반영된다');
      expect(s.capacity, InviteCapacityState.unknown,
          reason: '부분 산술로 현재 total 을 주장하지 않는다');
      expect(s.shortage, isNull, reason: 'false shortage 를 말하지 않는다');
      expect(s.claimsFull, isFalse);
      expect(s.inviteAllowed, isFalse, reason: '확인되지 않은 값으로 초대를 허용하지 않는다');
      expect(s.pending, isTrue, reason: '갱신 중으로 말한다');
      expect(s.errorNotice, isFalse, reason: '성공한 처리를 실패처럼 말하지 않는다');

      // canonical 11 도착 → 정확히 반영.
      gate.complete(_canonical(11));
      await cap.load();
      s = surfaceOf(cap);
      expect(cap.isCanonical, isTrue);
      expect(s.displayed, 11);
      expect(s.capacity, InviteCapacityState.available);
      expect(s.shortage, 1);
      expect(s.inviteAllowed, isTrue);
      expect(s.pending, isFalse);
    });

    test('PLC-A2 과대 집계된 로컬 값이 FULL 을 확정하지 못한다', () async {
      // identity 매처가 달라 같은 지원서를 두 업무에 세면 이런 수가 나온다.
      final cap = CapacityLoadState(loader: () async => _canonical(10));
      cap.seed(_local(10), parentFailed: false);

      cap.applyLocal(_local(_required + 3)); // 12 필요에 15
      final s = surfaceOf(cap);
      expect(s.claimsFull, isFalse,
          reason: '이 값으로 모집 완료를 선언하면 초대 경로가 사라진다');
      expect(s.capacity, InviteCapacityState.unknown);
      expect(s.displayed, 15, reason: '표시는 한다 — 판단만 하지 않는다');

      await cap.load();
      expect(surfaceOf(cap).capacity, InviteCapacityState.available);
      expect(surfaceOf(cap).shortage, 2);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // B. 후속 조회 실패
  // ══════════════════════════════════════════════════════════════

  group('PLC-B 후속 조회 실패', () {
    test('PLC-B1 로컬 값이 현재 total 로 남지 않고 UNKNOWN 이 된다', () async {
      var calls = 0;
      final cap = CapacityLoadState(loader: () async {
        calls++;
        return calls == 1 ? _failedRead() : _canonical(11);
      });
      cap.seed(_local(10), parentFailed: false);
      cap.applyLocal(_local(5));

      await cap.load(); // 실패
      var s = surfaceOf(cap);
      expect(cap.failed, isTrue);
      expect(s.displayed, isNull, reason: '실패 상태에서는 수치를 적지 않는다');
      expect(s.capacity, InviteCapacityState.unknown);
      expect(s.shortage, isNull);
      expect(s.claimsFull, isFalse);
      expect(s.inviteAllowed, isFalse);
      expect(s.errorNotice, isTrue, reason: '이제는 오류 + 다시 시도가 맞다');
      expect(s.pending, isFalse);

      // 재시도 성공 → 복구.
      await cap.load();
      s = surfaceOf(cap);
      expect(s.displayed, 11);
      expect(s.shortage, 1);
      expect(s.errorNotice, isFalse);
    });

    test('PLC-B2 실패가 로컬 값을 stale canonical 로 만들지 않는다', () async {
      final cap = CapacityLoadState(loader: () async => _failedRead());
      cap.applyLocal(_local(5));
      await cap.load();
      expect(cap.isCanonical, isFalse);
      expect(cap.confirmedFor(_work()), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // C. canonical 이 한 번도 없었다
  // ══════════════════════════════════════════════════════════════

  group('PLC-C canonical 없음 + 로컬 행만', () {
    test('PLC-C1 0 도 부분 인원도 total 로 주장하지 않는다', () {
      final cap = CapacityLoadState(loader: () async => _canonical(11));
      cap.applyLocal(_local(3)); // canonical 조회 전
      final s = surfaceOf(cap);
      expect(s.capacity, InviteCapacityState.unknown);
      expect(s.shortage, isNull, reason: '12-3=9 라고 말하면 확인하지 못한 부족이다');
      expect(s.claimsFull, isFalse);
      expect(s.inviteAllowed, isFalse);
      expect(s.pending, isTrue, reason: 'failure/retry 가 아니라 갱신 중이다');
    });

    test('PLC-C2 아무 값도 없으면 UNKNOWN + 오류 표현이다', () {
      final cap = CapacityLoadState(loader: () async => _canonical(11));
      final s = surfaceOf(cap);
      expect(s.displayed, isNull);
      expect(s.capacity, InviteCapacityState.unknown);
      expect(s.pending, isFalse);
      expect(s.errorNotice, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // D. mutation 이전 응답이 늦게 도착
  // ══════════════════════════════════════════════════════════════

  group('PLC-D 늦게 온 mutation 이전 응답', () {
    test('PLC-D1 이전 값이 다시 노출되지 않는다', () async {
      final stale = Completer<Map<String, dynamic>>();
      final fresh = Completer<Map<String, dynamic>>();
      var calls = 0;
      final cap = CapacityLoadState(loader: () {
        calls++;
        return calls == 1 ? stale.future : fresh.future;
      });
      cap.seed(_local(10), parentFailed: false);

      final f1 = cap.load(); // mutation 이전에 나간 요청
      cap.applyLocal(_local(11)); // mutation 성공
      final f2 = cap.load(); // mutation 이후 재조회

      stale.complete(_canonical(10)); // 이전 응답이 먼저 도착
      await f1;
      expect(surfaceOf(cap).displayed, 11,
          reason: '성공한 사람 mutation 반영이 되돌려지면 안 된다');
      expect(cap.isCanonical, isFalse, reason: '아직 확인 전이다');

      fresh.complete(_canonical(11)); // 이후 응답
      await f2;
      final s = surfaceOf(cap);
      expect(s.displayed, 11);
      expect(cap.isCanonical, isTrue);
      expect(s.shortage, 1);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // E. 연속 mutation / concurrent canonical
  // ══════════════════════════════════════════════════════════════

  group('PLC-E 연속 mutation', () {
    test('PLC-E1 stale 로컬 산술이 최종 authoritative 응답을 덮지 않는다', () async {
      final cap = CapacityLoadState(loader: () async => _canonical(13));
      cap.seed(_local(10), parentFailed: false);

      cap.applyLocal(_local(11));
      cap.applyLocal(_local(12)); // 연속 확정
      expect(surfaceOf(cap).capacity, InviteCapacityState.unknown);

      // 다른 관리자가 한 건을 더 확정했다 — canonical 은 13 이다.
      await cap.load();
      final s = surfaceOf(cap);
      expect(s.displayed, 13, reason: '로컬 12 가 아니라 서버가 센 13 이다');
      expect(s.capacity, InviteCapacityState.full,
          reason: '필요 12 를 채웠다 — 이제는 확정해도 된다');
      expect(s.inviteAllowed, isFalse);
      expect(s.shortage, 0);
    });

    test('PLC-E2 canonical 이후 다시 로컬이 오면 또 판단을 멈춘다', () async {
      final cap = CapacityLoadState(loader: () async => _canonical(12));
      await cap.load();
      expect(surfaceOf(cap).claimsFull, isTrue);

      cap.applyLocal(_local(11)); // 취소 1건
      final s = surfaceOf(cap);
      expect(s.claimsFull, isFalse);
      expect(s.capacity, InviteCapacityState.unknown);
      expect(s.displayed, 11);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // F. 실패 후 재시도 — 도메인 재실행 없음
  // ══════════════════════════════════════════════════════════════

  group('PLC-F 재시도는 정원만 회복한다', () {
    test('PLC-F1 재시도가 정원 조회만 부른다 — 중복 약속/취소 없음', () async {
      var capacityReads = 0;
      final cap = CapacityLoadState(loader: () async {
        capacityReads++;
        return capacityReads < 3 ? _failedRead() : _canonical(11);
      });
      cap.applyLocal(_local(5));

      await cap.load();
      await cap.load();
      await cap.load();

      expect(capacityReads, 3);
      expect(surfaceOf(cap).displayed, 11);
      // 이 상태기계는 도메인 writer 를 갖지 않는다 — loader 하나뿐이다.
      final src = _codeOf(_read('lib/models/ui/capacity_load_state.dart'));
      for (final banned in [
        'callable',
        'FirebaseFunctions',
        'set(',
        'update(',
        'delete(',
      ]) {
        expect(src.contains(banned), isFalse,
            reason: '재시도가 도메인 처리를 다시 하지 않는다: $banned');
      }
    });

    test('PLC-F2 mutation 성공과 정원 갱신 실패가 구분된다', () async {
      final cap = CapacityLoadState(loader: () async => _failedRead());
      cap.applyLocal(_local(11)); // 확정은 성공했다
      await cap.load(); // 정원 갱신만 실패

      final s = surfaceOf(cap);
      expect(s.errorNotice, isTrue, reason: '정원을 못 읽었다는 표현');
      expect(s.inviteAllowed, isFalse);
      // 성공한 처리를 되돌리거나 재전송을 권하지 않는다 — 이 객체는
      // 도메인 상태를 갖지 않으므로 표현할 수단 자체가 없다.
      expect(cap.failed, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // PLC-W wiring (source) — 위 실행 증거보다 약한 보조 증거다.
  // ══════════════════════════════════════════════════════════════

  group('PLC-W wiring', () {
    test('PLC-W1 판단용과 표시용이 분리돼 있다', () {
      final s = _codeOf(_read('lib/models/ui/capacity_load_state.dart'));
      expect(s, contains('if (!_isCanonical) return null;'));
      expect(s, contains('int? displayConfirmedFor('));
      expect(s, contains('_isCanonical = false;'));
    });

    test('PLC-W2 화면이 갱신 중과 확인 불가를 구분한다', () {
      final dlg = _codeOf(_read(
          'lib/screens/business_admin/dialogs/work_applicants_dialog.dart'));
      expect(dlg, contains("_capacity.isPending ? '정원 갱신 중' : '정원 확인 불가'"));
      expect(dlg, contains('_buildCapacityPendingNotice(context)'));
      // 갱신 중 안내에는 `다시 시도`가 없다 — 도메인 재실행으로 읽힌다.
      final pending = dlg.substring(
          dlg.indexOf('Widget _buildCapacityPendingNotice('),
          dlg.indexOf('Widget _buildCapacityUnknownNotice('));
      expect(pending, isNot(contains('다시 시도')));
      // 판단은 canonical 만 쓴다.
      expect(dlg, contains('_capacity.confirmedFor(widget.work)'));
    });
  });
}
