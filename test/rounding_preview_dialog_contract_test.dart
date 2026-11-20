// [ROUNDING-PREVIEW.27] 근태 기준(반올림) 적용 확인 창이 **결과 시각을 먼저** 보여 준다.
//
//   예전 창은 "일부 근로자에게 다르게 적용될 수 있습니다" 만 말해서, 적용을 눌러 처리가
//   끝나야 몇 시로 기록됐는지 알 수 있었다(관리자 지적, 10-29). 미리보기는 실제 처리와
//   **같은 함수**(`_roundedCheckIn`/`_roundedCheckOut`)로 만들어야 화면과 저장이 갈리지 않는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  expect(i, greaterThan(-1), reason: start);
  final j = src.indexOf(end, i + start.length);
  expect(j, greaterThan(i), reason: end);
  return src.substring(i, j);
}

void main() {
  final dlg = _code('lib/screens/business_admin/dialogs/attendance_status_dialog.dart');

  test('RP-1 짧은 이름 — 반올림 정책 → 근태 기준 적용(설정 화면 이름과 같은 말)', () {
    expect(dlg.contains("'반올림 정책'"), isFalse);
    expect(dlg.contains("'정책 반올림 적용'"), isFalse);
    expect(dlg.contains("'근태 기준 반올림 적용'"), isFalse);
    expect(dlg.contains("Text('근태 기준 적용'"), isTrue);
    expect(dlg.contains("'근태 기준 적용',"), isTrue, reason: '시간 조정 스위치');
  });

  test('RP-2 확인 창은 근로자별 입력 → 적용 시 시각을 받는다(호출 4곳 모두)', () {
    final fn = _slice(dlg, 'Future<bool?> _showRoundingPreviewDialog(', 'String _deriveStatus(');
    expect(fn, contains('required List<RoundingPreviewRow> rows'));
    expect(fn, contains('r.raw'));
    expect(fn, contains('r.applied'));
    expect(fn.contains('사업장 정책'), isFalse);
    expect(RegExp(r'_showRoundingPreviewDialog\(').allMatches(dlg).length, 5,
        reason: '정의 1 + 호출 4');
    expect(RegExp(r'_showRoundingPreviewDialog\([^)]*rawTime').hasMatch(dlg), isFalse);
  });

  test('RP-3 결과가 하나면 버튼에 시각을 적는다', () {
    final fn = _slice(dlg, 'Future<bool?> _showRoundingPreviewDialog(', 'String _deriveStatus(');
    expect(fn, contains(r"'${raws.first} 그대로'"));
    expect(fn, contains(r"'${applieds.first}으로 기록'"));
  });

  test('RP-4 미리보기 = 처리와 같은 함수 · 같은 출근 기준식 · 같은 제외 조건', () {
    final outPrev = _slice(dlg, 'List<RoundingPreviewRow> _checkOutPreviews(', 'List<RoundingPreviewRow> _adjustPreviews(');
    expect(outPrev, contains('_roundedCheckOut(app, att.checkInAt ?? _hmToDateTime(_kstDay, att.checkIn!), time)'));
    expect(outPrev, contains('att.checkIn != null'));
    expect(outPrev, contains('AttendanceModel.wageConfirmed'));
    final process = _slice(dlg, 'Future<void> _processBatchCheckOut(', 'Future<void> _processBatchCheckInByGroup(');
    expect(process, contains('attendance.checkInAt ?? _hmToDateTime(_kstDay, checkIn)'));
    expect(process, contains('_roundedCheckOut(app, checkInDtForOut, time)'));
    final inPrev = _slice(dlg, 'List<RoundingPreviewRow> _checkInPreviews(', 'List<RoundingPreviewRow> _checkOutPreviews(');
    expect(inPrev, contains("_getAttendanceStatus(app)['status'] == 'pending'"));
    expect(inPrev, contains('_roundedCheckIn(app, time)'));
  });

  test('RP-6 같은 사람 같은 날 두 근무 — 줄마다 근무 시간대가 있다(이름만으로 갈리지 않는다)', () {
    expect(dlg, contains('typedef RoundingPreviewRow = ({String name, String shift, String raw, String applied});'));
    final fn = _slice(dlg, 'Future<bool?> _showRoundingPreviewDialog(', 'String _deriveStatus(');
    expect(fn, contains('Text(r.shift,'));
    // 파트별 창 머리말과 같은 시간대(지원서 시간)
    expect(dlg, contains('app.startTime.isNotEmpty ? app.startTime'));
  });

  test('RP-5 시간 조정도 켜면 결과를 보여 준다 — 처리식과 같은 순서(출근 먼저)', () {
    final adj = _slice(dlg, 'List<RoundingPreviewRow> _adjustPreviews(', 'Future<bool?> _showRoundingPreviewDialog(');
    expect(adj, contains('_roundedCheckIn(app, newIn)'));
    expect(adj, contains('_roundedCheckOut(app, inDt, newOut)'));
    expect(dlg, contains('_adjustPreviews(targets, adjustCheckIn, adjustCheckOut)'));
  });
}
