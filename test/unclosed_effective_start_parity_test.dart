import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// R7-PRE0  UNCLOSED-EFFECTIVE-START-PARITY
//
//   "그 사람이 그 날 근무일이었는가"는 한 가지 규칙이어야 한다.
//
//   클라이언트 canonical 규칙(ApplicationModel.effectiveStart,
//   당일명단, calendar_helper):
//       desiredStartDate 있으면 그것.
//       없고 confirmedAt 이 workDate 보다 늦으면 **confirmedAt**.
//
//   Home 「마감 필요」와 Unclosed Queue 는 서버에서 같은 전개를 한다.
//   거기에만 confirmedAt 보정이 없었다. custom 기간 장기 지원은
//   desiredStartDate 를 저장하지 않고 workDate 에 공고 rangeStart 를
//   넣으므로(longterm_apply_sheet.dart _isCustom), 공고를 연 뒤 며칠
//   지나 확정하면 확정 이전 날짜들이 전부 '마감 필요'로 잡혔다.
//   그 날들의 당일명단에는 아무도 없다 — 열어도 할 일이 없는 Task.
//
//   DEV 실측(2026-09-22): 마감 필요 11일 → 그중 10일이 대상 0명.
//   보정 후 1일, 그 1일에 실제 대상 1명.
// ═══════════════════════════════════════════════════════════════

const _cfPath = 'functions/src/index.ts';
const _appModelPath = 'lib/models/core/application_model.dart';
const _rosterPath =
    'lib/screens/business_admin/dialogs/attendance_status_dialog.dart';
const _applySheetPath = 'lib/widgets/dialogs/apply/longterm_apply_sheet.dart';

String _src(String p) => File(p).readAsStringSync();

/// 주석은 계약이 아니다 — 코드 줄만 남긴다.
String _codeOf(String b) => b
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// `signature` 로 시작하는 함수 본문(중괄호 균형)을 돌려준다.
///
/// 본문 여는 중괄호는 "줄 끝의 `{`"로 찾는다. 첫 `{` 를 그냥 쓰면
/// `): Promise<{count: number}> {` 같은 반환 타입 안의 중괄호에 걸려
/// 본문이 두 줄에서 끊긴다 — 그러면 검사가 조용히 통과/실패한다.
String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: '$signature 를 찾지 못함');
  final open = RegExp(r'\{[ \t]*\r?\n').firstMatch(source.substring(start))!.start + start;
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  fail('$signature 본문의 끝을 찾지 못함');
}

void main() {
  final cf = _src(_cfPath);

  group('UES-1x 서버에 보정 규칙이 있다', () {
    test('UES-10 srvLongTermEffectiveStart 헬퍼가 존재한다', () {
      expect(cf.contains('function srvLongTermEffectiveStart('), isTrue,
          reason: '실효 시작일 보정을 한 곳에 모아 둔다 — 두 집계가 각자 쓰면 또 갈라진다.');
    });

    test('UES-11 헬퍼가 desiredStartDate → confirmedAt 순서로 판단한다', () {
      final body = _flat(_codeOf(
          _bodyOf(cf, 'function srvLongTermEffectiveStart(')));
      expect(body.contains('d["desiredStartDate"]'), isTrue);
      expect(body.contains('d["confirmedAt"]'), isTrue);
      expect(body.contains('d["workDate"]'), isTrue);
      // desiredStartDate 가 있으면 확정일을 보지 않는다 — 사용자 지정이 우선.
      final desiredIdx = body.indexOf('desiredStartDate');
      final confirmedIdx = body.indexOf('confirmedAt');
      expect(desiredIdx < confirmedIdx, isTrue,
          reason: 'desiredStartDate 가 먼저 판정돼야 한다.');
    });

    test('UES-12 KST 달력 날짜로 비교한다 (시각 차이로 하루 밀리지 않게)', () {
      final body = _flat(_codeOf(
          _bodyOf(cf, 'function srvLongTermEffectiveStart(')));
      expect(body.contains('9 * 60 * 60 * 1000'), isTrue,
          reason: 'KST 보정 없이 비교하면 자정 근처에서 하루가 어긋난다.');
      expect(body.contains('Date.UTC('), isTrue);
    });
  });

  group('UES-2x 두 집계가 모두 그 헬퍼를 쓴다', () {
    test('UES-20 srvHomeUnclosed 가 헬퍼를 쓴다 (Home 마감 필요)', () {
      final body = _codeOf(_bodyOf(cf, 'async function srvHomeUnclosed('));
      expect(body.contains('srvLongTermEffectiveStart(d)'), isTrue,
          reason: 'Home 이 확정 이전 날짜를 마감 필요로 세면 없는 업무가 생긴다.');
      expect(
          _flat(body).contains('(d["desiredStartDate"] ?? d["workDate"])'),
          isFalse,
          reason: '보정 없는 옛 식이 남아 있으면 안 된다.');
    });

    test('UES-21 srvUnclosedQueueForBiz 가 같은 헬퍼를 쓴다', () {
      final body =
          _codeOf(_bodyOf(cf, 'async function srvUnclosedQueueForBiz('));
      expect(body.contains('srvLongTermEffectiveStart(d)'), isTrue,
          reason: 'Home 과 Queue 가 다른 규칙을 쓰면 두 화면이 다른 수를 말한다.');
      expect(
          _flat(body).contains('(d["desiredStartDate"] ?? d["workDate"])'),
          isFalse);
    });

    test('UES-22 두 쿼리가 confirmedAt 을 실제로 읽어 온다', () {
      // select() 에 없으면 헬퍼가 항상 undefined 를 본다 — 조용히 옛 동작으로 돌아간다.
      final home = _codeOf(_bodyOf(cf, 'async function srvHomeUnclosed('));
      final queue =
          _codeOf(_bodyOf(cf, 'async function srvUnclosedQueueForBiz('));
      for (final entry in {'srvHomeUnclosed': home, 'srvUnclosedQueueForBiz': queue}
          .entries) {
        expect(_flat(entry.value).contains('"confirmedAt"'), isTrue,
            reason: '${entry.key}: select 에 confirmedAt 이 없으면 보정이 죽는다.');
      }
    });
  });

  group('UES-3x 클라이언트 canonical 규칙과 같은 규칙이다', () {
    test('UES-30 ApplicationModel 이 같은 보정을 갖고 있다', () {
      final src = _flat(_codeOf(_src(_appModelPath)));
      expect(src.contains('desiredStartDate ?? workDate'), isTrue);
      expect(src.contains('confirmedAt != null && desiredStartDate == null'),
          isTrue,
          reason: '서버 보정은 이 클라이언트 규칙을 따라간 것이다 — 이쪽이 바뀌면 서버도 바꿔야 한다.');
    });

    test('UES-31 당일명단도 같은 보정을 쓴다', () {
      final src = _flat(_codeOf(_src(_rosterPath)));
      expect(
          src.contains(
              'app.confirmedAt != null && app.desiredStartDate == null'),
          isTrue,
          reason: '이 화면이 Home 과 대조되는 상대다.');
    });
  });

  group('UES-4x 보정이 왜 필요한가 — desiredStartDate 결측은 정상 경로다', () {
    test('UES-40 custom 기간 장기 지원은 desiredStartDate 를 저장하지 않는다', () {
      final src = _flat(_codeOf(_src(_applySheetPath)));
      expect(src.contains('effectiveDesiredStart = null'), isTrue,
          reason: 'desiredStartDate 결측이 레거시가 아니라 현재 지원 경로다 — '
              '이 줄이 사라지면 보정의 전제가 바뀐 것이므로 다시 판단해야 한다.');
      expect(src.contains('effectiveWorkDate = widget.to.rangeStart!'), isTrue,
          reason: 'workDate 에 공고 시작일이 들어간다 — 확정보다 며칠 앞설 수 있다.');
    });
  });
}
