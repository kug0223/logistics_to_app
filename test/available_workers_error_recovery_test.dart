import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [R8 O05] 후보 조회가 `invalid-argument` 로 거절될 때 화면이 하는 일.
///
///   서버는 두 경우에 거절한다(7차에 맞춘 계약, Emulator 증거는
///   `scripts/r7-emu-c7-fallback.js` C7-3·C7-7):
///     · 맞출 수 없는 `workDetailId` — 조용히 첫 업무로 바꾸지 않는다
///     · 같은 이름의 업무가 둘인데 workType 만 온 경우 — 아무거나 고르지 않는다
///
///   그 거절을 caller 가 어떻게 다루는지가 이 파일의 계약이다.
///   같은 입력으로는 다시 성공할 수 없으므로 `다시 시도` 를 주지 않는다 —
///   눌러도 안 되는 버튼은 무한 재시도가 된다. 서버가 준 구체적인 안내를
///   일반 문구로 덮지도 않는다.

String _src(String p) => File(p).readAsStringSync();
String _codeOf(String b) => b
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('*'))
    .join('\n');

const _sheet =
    'lib/screens/business_admin/dialogs/available_workers_bottom_sheet.dart';
const _cf = 'functions/src/index.ts';

void main() {
  final sheet = _codeOf(_src(_sheet));
  final cf = _codeOf(_src(_cf));

  group('AWE-A 서버 계약', () {
    test('A-1 맞출 수 없는 식별자는 거부한다 — 첫 업무로 바꾸지 않는다', () {
      expect(cf.contains('"요청한 업무를 찾을 수 없습니다. 목록을 새로고침한 뒤 다시 시도해주세요."'),
          isTrue);
      // 업무 정의가 하나뿐일 때만 폴백이 남는다.
      expect(cf.contains('if (rawWDs.length === 1) {'), isTrue);
    });

    test('A-2 같은 workType 이 둘이면 아무거나 고르지 않는다', () {
      expect(
          cf.contains('"같은 업무 이름이 여러 개입니다. 목록에서 근무 시간을 골라 다시 시도해주세요."'),
          isTrue);
      expect(cf.contains('if (sameType.length === 1) {'), isTrue,
          reason: '유일할 때만 workType 단독을 받아들인다');
    });
  });

  group('AWE-B caller 가 안내하고 복구 경로를 준다', () {
    test('B-1 서버 문구를 일반 문구로 덮지 않는다', () {
      expect(sheet.contains('bool _isStaleRequestError(Object e) =>'), isTrue);
      expect(sheet.contains("e.toString().toLowerCase().contains('invalid-argument')"),
          isTrue);
      // 서버 message 를 우선 쓴다.
      expect(sheet.contains('e is FirebaseFunctionsException ? e.message : null'),
          isTrue);
    });

    test('B-2 같은 입력으로 다시 성공할 수 없는 오류에는 재시도를 주지 않는다', () {
      expect(sheet.contains('bool _staleRequest = false;'), isTrue);
      expect(sheet.contains('_staleRequest = _isStaleRequestError(e);'), isTrue);
      final flat = sheet.replaceAll(RegExp(r'\s+'), ' ');
      // stale 이면 닫기, 아니면 다시 시도.
      expect(
          flat.contains("if (_staleRequest) OutlinedButton( onPressed: () => "
              "Navigator.of(context).maybePop(), child: const Text('닫기'), ) else "
              "OutlinedButton( onPressed: _load, child: const Text('다시 시도'), )"),
          isTrue,
          reason: '무한 재시도를 주거나, 복구 가능한 실패에서 재시도를 없애면 안 된다');
    });

    test('B-3 성공하면 stale 표시가 남지 않는다', () {
      final flat = sheet.replaceAll(RegExp(r'\s+'), ' ');
      expect(flat.contains('_error = null; _staleRequest = false;'), isTrue);
    });

    test('B-4 빈 후보와 오류를 같은 화면으로 말하지 않는다', () {
      // 오류는 오류 블록에서, 빈 pool 은 별도 블록에서 말한다.
      expect(sheet.contains('if (_error != null) {'), isTrue);
      expect(sheet.contains('if (_recommendedOrder.isEmpty && !_hasMore) {'), isTrue);
    });
  });
}
