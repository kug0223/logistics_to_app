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
///   **업무 그룹 안도 예외가 아니다 — 최종 계약은 "이 화면의 모든 수치는 건"이다.**
///   그룹 키는 `businessId|toId|slotId|workDetailId` 이고(`wdId` 가 아니다 —
///   `wdSeg = app.workDetailId ?? ''`), `workDetailId` 가 **없는** legacy 문서는
///   `wdSeg` 가 빈 문자열이 되어 같은 슬롯의 서로 다른 업무가 한 그룹으로 합쳐진다.
///   그때 한 사람의 두 관계가 한 그룹 안에 함께 들어온다 — docId discriminator 는
///   `selectedWorkType` 이라 충돌하지 않기 때문이다(CLAUDE.md complexId 계약).
///   그래서 "그룹 안에서는 건수=인원수" 라는 이전 근거는 **성립하지 않는다**.
///   행 길이를 보여주는 자리는 전부 `건` 으로 말한다.
///
///   고유 인원을 표시해야 한다는 기존 요구는 없다 — 이 화면의 action 단위(출근·퇴근·
///   시간정정·노쇼)가 근무 건이므로 별도 unique uid 지표를 만들지 않았다.
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

    test('U-3 화면 문구에 명 라벨이 남아 있지 않다', () {
      // debugPrint 는 화면 문구가 아니므로 제외한다.
      final uiLines = code
          .split('\n')
          .where((l) => !l.contains('debugPrint'))
          .where((l) => l.contains('명\''))
          .toList();
      expect(uiLines, isEmpty, reason: '남은 명 라벨: $uiLines');
    });

    test('U-5 파트별 일괄 처리도 건으로 말한다', () {
      // 일괄 출퇴근의 대상은 근무 건이다(한 사람이 두 파트에 있을 수 있고,
      //   workDetailId 없는 구 문서는 한 파트로 합쳐진다).
      expect(code.contains("'\$totalCount건 선택 · \${groups.length}개 파트'"), isTrue);
      expect(code.contains("Text('\${workers.length}건',"), isTrue);
      expect(code.contains('final totalCount = groups.values.fold(0, (s, l) => s + l.length);'),
          isTrue, reason: 'totalCount 는 관계 수의 합이다');
    });

    test('U-6 그룹 헤더의 분자·분모가 같은 단위다', () {
      // 둘 다 그 그룹의 **행(관계)** 을 센다 — 단위어 없이 n/m 으로만 말한다.
      expect(code.contains("'출근 \$checkedInCount/\${workers.length - noShowCount}'"),
          isTrue);
      expect(code.contains('final checkedInCount = workers.where((a) {'), isTrue);
      expect(code.contains('final noShowCount = workers.where((a) {'), isTrue);
    });

    test('U-4 그룹 키의 조각은 workDetailId 다 — 없으면 한 그룹으로 합쳐진다', () {
      // 조각의 정체를 못 박는다 — `wdId` 가 아니다. 없으면 빈 문자열이 되어
      //   같은 슬롯의 다른 업무가 한 그룹이 된다(그래서 '명' 이 아니라 '건').
      expect(code.contains("final wdSeg = app.workDetailId ?? '';"), isTrue);
      expect(code.contains("final groupKey = '\${app.businessId}|\$toSeg|\$slotSeg|\$wdSeg';"),
          isTrue);
    });
  });
}
