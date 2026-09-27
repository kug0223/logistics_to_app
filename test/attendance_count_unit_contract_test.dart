import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [R7-P1-3] 당일명단의 숫자는 **무엇을 세는지** 말해야 한다.
///
///   이 화면의 모든 집계는 `List<ApplicationModel>` 위에서 돈다
///   (`_calculateStats`, 탭별 목록, 선택 목록). 즉 단위는 **근무 건**이다.
///   한 사람이 같은 날 겹치지 않는 두 업무를 확정받을 수 있으므로
///   (지원 게이트는 **겹치는** 확정만 막는다) 건수와 인원수는 다를 수 있다.
///   그런데 라벨이 전부 `명` 이었다 — 1명이 2건이면 "미출근 2명" 이 된다.
///
///   업무 그룹 **안**은 예외다. 그룹 키가 `businessId|toId|slotId|wdId` 이고
///   지원서 docId 가 `{toId}_{slotId}_{wdId}_{uid}` 로 uid 당 유일하므로
///   (CLAUDE.md 의 complexId 계약) 그룹 안에서 한 사람은 한 번만 나온다.
///   그래서 그룹 헤더만 `명` 이 맞다.
///
///   같은 계열의 이웃 화면은 이미 건/명을 구분해 쓴다
///   (`DayApplicantsDialog`: `지원 N건 · 확정 N건`).

String _src(String p) => File(p).readAsStringSync();

const _dialog = 'lib/screens/business_admin/dialogs/attendance_status_dialog.dart';

void main() {
  final code = _src(_dialog);

  group('ACU 집계 단위', () {
    test('U-1 집계는 지원서 목록 위에서 돈다 — 단위는 근무 건이다', () {
      expect(code.contains('Map<String, int> _calculateStats({List<ApplicationModel>? workers})'),
          isTrue);
      expect(code.contains('final list = workers ?? _confirmedWorkers;'), isTrue);
      expect(code.contains('List<ApplicationModel> _confirmedWorkers = [];'), isTrue);
    });

    test('U-2 업무 그룹을 넘는 수치는 건으로 말한다', () {
      for (final s in [
        "'미출근 \${pendingList.length}건'",
        "'지각 \${lateList.length}건'",
        "'퇴근미기록 \${missedList.length}건'",
        "'근태 확인 \${confirmable.length}건'",
        "'취소 \${cancellable.length}건'",
        "'\$processedCount/\${_confirmedWorkers.length}건'",
        "'확인완료 \$confirmedTabCount건'",
      ]) {
        expect(code.contains(s), isTrue, reason: '없음: $s');
      }
    });

    test('U-3 그룹을 넘는 수치에 명이 남아 있지 않다', () {
      // debugPrint 는 화면 문구가 아니므로 제외한다.
      final uiLines = code
          .split('\n')
          .where((l) => !l.contains('debugPrint'))
          .where((l) => l.contains('명\''))
          .toList();
      // 남는 것은 업무 그룹 헤더 하나뿐이다.
      expect(uiLines.length, 1, reason: '남은 명 라벨: $uiLines');
      expect(uiLines.first.contains('workers.length'), isTrue);
    });

    test('U-4 그룹 헤더의 명이 맞는 근거 — 그룹 키가 wdId 까지 좁혀져 있다', () {
      expect(code.contains("final groupKey = '\${app.businessId}|\$toSeg|\$slotSeg|\$wdSeg';"),
          isTrue);
    });
  });
}
