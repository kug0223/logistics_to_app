// [CONTRACT-BEFORE-CHECKIN] 계약 동의(양측 서명 완료)는 출근의 전제조건이다 — 2026-10-25 사용자 지시
//
// 연혁:
//   · 2026-09-16 a713dbc [PREDEVICE-CONTRACT-GATE] — 이 파일은 정반대 계약을 고정했다
//     ("계약 완료는 출근의 전제조건이 아니다"). 근거는 셋이었다.
//       1) 서버 callableCheckIn 이 employment_contracts 를 읽지 않았다
//          (DEV 실측: 계약이 없는 CONTRACT_PENDING 도 200 출근 성공).
//       2) 화면 gate 가 pending_worker 만 막는 뒤집힌 모양이었다.
//       3) 앱만 막으면 06:00 자동 NO_SHOW 가 그 자리를 결근으로 기록한다.
//     그리고 "정책을 뒤집으려면 서버 guard 가 먼저"라고 적었다.
//   · 2026-10-25 사용자 지시: "관리자가 확정 시 바로 지원자에게 계약서를 보내게 하고 있고,
//     지원자는 그 계약서를 동의 안하면 출근버튼 비활성화로 진행되어야해".
//     → 서버 guard 를 먼저 넣는다(callableCheckIn 트랜잭션 안 계약 문서 판정).
//       화면은 같은 판정으로 버튼을 닫는다. 판정 근거는 지원서 status 가 아니라 계약 문서다.
//   · 같은 날 R1: 자동 노쇼 면제는 **만들지 않는다**. 미동의로 출근 기록이 없으면 기존대로
//     NO_SHOW 이고, 실제로 일했다면 관리자 근태 정정(노쇼 취소 → 일괄 출근 → 일괄 퇴근)으로 고친다.
//     그래서 아래 마지막 그룹은 "자동 노쇼는 계약을 보지 않는다"를 그대로 고정한다(의도된 상태).
//
// 음성 대조: 각 그룹에 "이 판정이 없으면 이 시험이 실패한다"는 역조건을 함께 둔다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnsPath = 'functions/src/index.ts';
const _checkInScreen = 'lib/screens/user/attendance_check_screen.dart';
const _gatePath = 'lib/screens/user/checkin_contract_gate.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _callableOf(String source, String name) {
  final start = source.indexOf('export const $name = onCall(');
  if (start < 0) throw StateError('$name 을 찾지 못함');
  final next = source.indexOf('\nexport ', start + 10);
  return source.substring(start, next == -1 ? source.length : next);
}

String _fnOf(String source, String decl) {
  final start = source.indexOf(decl);
  if (start < 0) throw StateError('$decl 을 찾지 못함');
  final next = source.indexOf('\n}\n', start);
  return source.substring(start, next == -1 ? source.length : next + 2);
}

/// 메서드 본문을 다음 최상위 멤버 주석 직전까지 자른다.
String _memberOf(String source, String decl) {
  final start = source.indexOf(decl);
  if (start < 0) throw StateError('$decl 을 찾지 못함');
  final next = source.indexOf('\n  /// ', start + decl.length);
  return source.substring(start, next == -1 ? source.length : next);
}

void main() {
  final fns = _src(_fnsPath);
  final checkIn = _codeOf(_callableOf(fns, 'callableCheckIn'));
  final helper = _codeOf(_fnOf(fns, 'async function srvContractConsentState('));

  group('서버 gate — 출근 트랜잭션이 계약 문서를 읽는다', () {
    test('callableCheckIn 트랜잭션 안에서 계약 판정을 tx.get 으로 한다', () {
      final flat = _flat(checkIn);
      expect(
          flat.contains(
              'const ciContract = await srvContractConsentState((q) => tx.get(q), applicationId, callerUid, businessId);'),
          true,
          reason: '확인과 근태 쓰기 사이 경쟁은 같은 트랜잭션에서 읽어야 막힌다');
      expect(flat.contains('if (!ciContract.ok) { throw new HttpsError("failed-precondition", ciContract.message, {code: ciContract.reason});'),
          true);
    });

    test('판정은 좌석 상태 확인 뒤, 근태 쓰기 전에 있다', () {
      final iStatus = checkIn.indexOf('confirmedStatuses.includes(freshAppStatus)');
      final iGate = checkIn.indexOf('srvContractConsentState(');
      final iWrite = checkIn.indexOf('tx.set(ref');
      expect(iStatus >= 0 && iGate > iStatus, true);
      expect(iWrite < 0 || iGate < iWrite, true,
          reason: '거절이면 근태·카운터 쓰기가 0 이어야 한다');
      // 재전송 멱등: 이미 출근한 문서는 계약 판정보다 먼저 already-exists 로 받는다
      expect(checkIn.indexOf('if (snap.exists)') < iGate, true);
    });

    test('좌석 상태 두 가지(CONFIRMED·CONTRACT_PENDING)는 그대로 — 계약은 별도 판정', () {
      expect(
        _flat(checkIn)
            .contains('const confirmedStatuses = ["CONFIRMED", "CONTRACT_PENDING"];'),
        true,
        reason: '좌석 술어를 좁혀 계약을 흉내 내지 않는다 — 초대 수락은 계약 전 CONFIRMED 다',
      );
    });

    test('동의로 치는 것은 그 지원서·근로자·사업장의 양측 서명 완료 계약뿐이다', () {
      final flat = _flat(helper);
      expect(flat.contains('if (c.workerId !== workerUid || c.businessId !== businessId) continue;'), true);
      expect(flat.contains('if (c.applicationId !== applicationId && !ids.includes(applicationId)) continue;'), true);
      expect(flat.contains('c.status === "completed" && c.employerSignedAt && c.workerSignedAt'), true);
      expect(helper.contains('"voided"'), false,
          reason: '무효 계약을 동의 근거로 세는 분기가 없어야 한다');
      // 음성 대조: 지원서 status 로 동의를 추정하지 않는다
      expect(helper.contains('CONTRACT_PENDING'), false);
      expect(helper.contains('freshAppStatus'), false);
    });

    test('거절 사유는 세 가지 코드로 구별된다', () {
      for (final code in [
        'CONTRACT_MISSING',
        'CONTRACT_EMPLOYER_PENDING',
        'CONTRACT_WORKER_PENDING',
      ]) {
        expect(fns.contains('$code:'), true, reason: '$code 문구가 있어야 한다');
      }
    });

    test('출근을 가르는 기존 조건(신원·시간·장소·좌석)은 그대로다', () {
      for (final guard in [
        'restrictedUntil',
        'accountStatus',
        '지원서에 지정된 날짜',
        'selectedWorkType',
      ]) {
        expect(checkIn.contains(guard), true,
            reason: '$guard guard가 사라졌다면 출근 정책이 바뀐 것이다');
      }
    });
  });

  group('화면 gate — 서버와 같은 판정으로 버튼을 닫는다', () {
    final area = _memberOf(_src(_checkInScreen), 'Widget _buildCheckInArea(');
    final code = _codeOf(area);
    final flat = _flat(code);
    final gate = _codeOf(_src(_gatePath));

    test('출근 버튼의 onPressed 는 계약 동의가 없으면 null 이다', () {
      expect(flat.contains('(notYetOpen || !gate.allowsCheckIn) ? null : () async => _checkIn(work)'),
          true);
      expect('LoadingButton.primary('.allMatches(flat).length, 1,
          reason: '출근 버튼은 하나다 — 닫힌 상태도 같은 버튼이 비활성으로 보인다');
      // 음성 대조: 예전의 "안내는 보여도 출근은 열어 둔다" 문구가 남아 있으면 안 된다
      expect(code.contains('출근은 지금 할 수 있어요'), false);
      expect(flat.contains('if (pendingContract == null) return checkInButton;'), false,
          reason: 'UserProvider 서명 대기 캐시(pending_worker 만)로 판정하지 않는다');
    });

    test('판정 근거는 화면이 새로 읽은 계약 목록이다 — 캐시·지원서 status 아님', () {
      expect(flat.contains('CheckInContractGate.evaluate( work: work, uid: uid, contracts: _contracts)'),
          true);
      expect(code.contains('pendingContractForTo'), false);
      expect(gate.contains('if (contracts == null)'), true,
          reason: '읽기 실패(null)는 unknown — 동의가 아니다');
      expect(gate.contains('ContractStatus.voided:'), true);
      expect(gate.contains('c.employerSignedAt != null && c.workerSignedAt != null'), true);
    });

    test('이유와 다음 행동을 준다 — 서명 대기면 그 계약으로 바로 간다', () {
      for (final s in [
        '근로계약서에 동의해야 출근할 수 있어요',
        '사업주 서명을 기다리고 있어요',
        '아직 근로계약서를 받지 않았어요',
        '계약서 상태를 확인하지 못했어요',
        '계약서 확인하고 동의하기',
      ]) {
        expect(code.contains(s), true, reason: '"$s" 안내가 있어야 한다');
      }
      expect(code.contains('ContractSignScreen('), true);
      expect(code.contains('결근 처리될 수 있어요'), true,
          reason: 'R1: 미동의·미출근의 기존 결과(노쇼)를 숨기지 않는다');
    });

    test('서명 화면에서 돌아오면 계약을 다시 읽고 그 결과로만 판단한다', () {
      expect(flat.contains('await _loadTodayWorks();'), true);
      expect(flat.contains('refreshPendingContracts()'), true);
    });

    test('내부 enum을 그대로 노출하지 않는다', () {
      for (final internal in [
        'CONTRACT_PENDING',
        'pending_worker',
        'pending_employer',
      ]) {
        expect(code.contains("'$internal'"), false,
            reason: '$internal 같은 내부 상태명을 화면 문구로 쓰지 않는다');
      }
    });
  });

  group('R1 — 자동 NO_SHOW 는 바꾸지 않는다(면제 없음)', () {
    test('자동 NO_SHOW 는 계약 상태를 보지 않는다 — 미동의 미출근도 기존대로 노쇼', () {
      final sweep = _codeOf(fns.substring(
        fns.indexOf('async function processAutoNoShow('),
        fns.indexOf('\nexport ', fns.indexOf('async function processAutoNoShow(')),
      ));
      expect(sweep.contains('employment_contracts'), false,
          reason: 'R1(2026-10-25): 계약 미완료만으로 노쇼를 면제하거나 대상에서 빼지 않는다');
      expect(sweep.contains('srvContractConsentState'), false);
      expect(
        sweep.contains('.where("status", "in", ["CONFIRMED", "CONTRACT_PENDING"])'),
        true,
        reason: '노쇼 대상 좌석 정의는 그대로다',
      );
    });
  });
}
