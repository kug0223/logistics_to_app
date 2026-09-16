// [PREDEVICE-CONTRACT-GATE] 계약 완료는 출근의 전제조건이 아니다
//
// READ + DEV runtime에서 확인된 것:
//   · callableCheckIn은 employment_contracts를 한 번도 읽지 않는다.
//   · 허용 상태는 ["CONFIRMED", "CONTRACT_PENDING"]이다. CONTRACT_PENDING은
//     정의상 완료된 계약서가 없는 상태이므로, 계약 gate를 의도했다면
//     그 자체로 모순이다.
//   · DEV 실측: 계약이 아예 없는 CONTRACT_PENDING 좌석 → HTTP 200 출근 성공.
//     계약서 status를 pending_employer / pending_worker / completed / voided로
//     바꿔 가며 같은 호출을 반복해도 네 상태 모두 200 허용.
//
//   그런데 출근 화면은 서명 대기(pending_worker) 계약서가 있으면 출근 버튼
//   자체를 계약 CTA로 **대체**했다. gate가 클라이언트에만 있었고, 방향도
//   뒤집혀 있었다 — 계약이 아예 없는 최악의 상태는 통과시키고, 거의 다 끝난
//   상태만 막았다.
//
//   그 차단은 노쇼와 충돌한다. 출근 버튼이 없으면 근로자는 앱에서 출근을
//   찍을 수 없고, 다음 날 06:00 processAutoNoShow가 그 자리를 무단결근으로
//   기록한다. 그 기록은 trust 트리거를 타고 noShowCount를 올리며 90일 3회면
//   계정이 제한된다. 앱이 막고 앱이 벌점을 주는 구조였다.
//
// 계약:
//   화면이 서버보다 엄격한 gate를 스스로 만들지 않는다.
//   계약 안내와 CTA는 남기되 출근 경로는 열어 둔다.
//   정책을 뒤집으려면 서버 guard가 먼저 생기고, 자동 NO_SHOW 제외가 함께 와야 한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnsPath = 'functions/src/index.ts';
const _checkInScreen = 'lib/screens/user/attendance_check_screen.dart';

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

  group('서버 gate — 무엇이 출근을 가르는가', () {
    test('callableCheckIn은 employment_contracts를 읽지 않는다', () {
      expect(checkIn.contains('employment_contracts'), false,
          reason: '계약을 출근 조건으로 삼으려면 여기에 guard가 있어야 한다. '
              '없다면 클라이언트도 막아서는 안 된다.');
    });

    test('허용 상태는 좌석 두 가지다 — CONTRACT_PENDING 포함', () {
      expect(
        _flat(checkIn)
            .contains('const confirmedStatuses = ["CONFIRMED", "CONTRACT_PENDING"];'),
        true,
      );
      // CONTRACT_PENDING을 허용한다는 것은 "완료된 계약서 없이도 출근한다"는 뜻이다.
      // 이 두 사실이 함께 있어야 현재 정책이 일관된다.
    });

    test('출근을 가르는 조건은 신원·시간·장소·좌석이다', () {
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

  group('클라이언트가 서버보다 엄격한 gate를 만들지 않는다', () {
    final area =
        _memberOf(_src(_checkInScreen), 'Widget _buildCheckInArea(');
    final code = _codeOf(area);
    final flat = _flat(code);

    test('미서명 계약서가 있어도 출근 버튼이 사라지지 않는다', () {
      // 예전 구조: pendingContract != null 이면 early return으로 버튼을 대체했다.
      expect(flat.contains('if (pendingContract == null) return checkInButton;'),
          true,
          reason: '계약 없음일 때만 단독 버튼, 있을 때는 안내와 함께 버튼을 같이 둔다');
      expect("LoadingButton.primary(".allMatches(flat).length, 1,
          reason: '출근 버튼은 하나이고 두 분기가 같은 버튼을 쓴다');
      expect(flat.contains('checkInButton,'), true,
          reason: '계약 안내 분기에서도 출근 버튼이 렌더돼야 한다');
    });

    test('이유와 해결 CTA를 함께 준다 — 막기만 하지 않는다', () {
      expect(code.contains('계약서 서명이 필요해요'), true);
      expect(code.contains('출근은 지금 할 수 있어요'), true,
          reason: '출근이 막히지 않는다는 사실을 사용자가 알아야 한다');
      expect(code.contains('계약서 확인'), true, reason: 'CTA가 있어야 한다');
      expect(code.contains('ContractSignScreen('), true,
          reason: '해당 계약서로 바로 이동해야 한다');
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

    test('서명 화면에서 돌아오면 계약 목록을 다시 받는다', () {
      expect(flat.contains('refreshPendingContracts()'), true,
          reason: '다른 기기에서 서명했을 수 있다 — stale 목록으로 안내를 유지하면 안 된다');
    });
  });

  group('계약 gate와 자동 NO_SHOW가 충돌하지 않는다', () {
    test('자동 NO_SHOW는 계약 상태를 보지 않는다 — 그래서 출근이 열려 있어야 한다', () {
      final sweep = _codeOf(fns.substring(
        fns.indexOf('async function processAutoNoShow('),
        fns.indexOf('\nexport ', fns.indexOf('async function processAutoNoShow(')),
      ));
      expect(sweep.contains('employment_contracts'), false,
          reason: '노쇼 판정이 계약을 보지 않는다면, 계약 때문에 출근을 막아서는 안 된다. '
              '막으면 시스템이 만든 결근을 근로자에게 벌점으로 돌린다.');
      expect(
        sweep.contains('.where("status", "in", ["CONFIRMED", "CONTRACT_PENDING"])'),
        true,
        reason: '노쇼 대상 좌석 정의가 바뀌면 이 충돌 판단도 다시 해야 한다',
      );
    });
  });
}
