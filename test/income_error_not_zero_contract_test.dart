// [PREDEVICE-ATTENDANCE-WAGE.2 §16] 수입 조회 실패는 0원이 아니다
//
// READ에서 확인된 것:
//   · getMyMonthlyAttendances는 실패하면 `cached ?? []`를 돌려줬다.
//     이 조회가 근로자의 수입 숫자를 만든다. 캐시가 없으면 빈 목록이 되고,
//     홈과 수입 상세는 "근무 완료 0원 · 예상 수입 0원"을 자신 있게 그렸다.
//   · 0원은 "그 달에 번 돈이 없다"는 사실이고, 조회 실패는 "얼마인지 모른다"는
//     전혀 다른 상태다. 둘을 같은 화면으로 그리면 일한 돈이 사라진 것으로 읽힌다.
//   · 같은 계열의 getMyApplications는 앞선 Phase에서 이미 고쳤다.
//
// 계약:
//   서비스는 실패를 삼키지 않는다(캐시가 있으면 stale 반환). 화면은 그 실패를
//   상태로 들고, 금액 자리에 0원 대신 모른다고 쓴다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _attFsPath = 'lib/services/firestore/attendance_firestore.dart';
const _incomePath = 'lib/screens/user/income_detail_screen.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

/// 메서드 선언부터 다음 최상위 doc 주석 직전까지.
String _memberOf(String source, String decl) {
  final start = source.indexOf(decl);
  if (start < 0) throw StateError('$decl 을 찾지 못함');
  final next = source.indexOf('\n  /// ', start + decl.length);
  return source.substring(start, next == -1 ? source.length : next);
}

void main() {
  group('서비스가 수입 조회 실패를 빈 목록으로 바꾸지 않는다', () {
    final body = _flat(_codeOf(_memberOf(
        _src(_attFsPath), 'Future<List<AttendanceModel>> getMyMonthlyAttendances(')));

    test('캐시가 없으면 rethrow한다', () {
      expect(body.contains('return cached ?? [];'), false,
          reason: '빈 목록은 "수입 0원"과 구분되지 않는다');
      expect(body.contains('if (cached != null) return cached;'), true,
          reason: '캐시가 있으면 stale을 주는 편이 빈 화면보다 낫다');
      expect(body.contains('rethrow;'), true);
    });
  });

  group('수입 화면이 0원과 모름을 구분한다', () {
    final src = _src(_incomePath);
    final code = _codeOf(src);
    final flat = _flat(code);

    test('실패가 화면 상태로 남는다', () {
      expect(flat.contains('bool _loadFailed = false;'), true);
      expect('_loadFailed = true;'.allMatches(flat).length >= 2, true,
          reason: '최초 로드와 월 이동 재로드 모두에서 기록돼야 한다');
      expect('_loadFailed = false;'.allMatches(flat).length >= 2, true,
          reason: '성공 시 복구되지 않으면 오류 상태가 눌러붙는다');
    });

    test('금액 자리에 0원 대신 모른다고 쓴다', () {
      expect(flat.contains('String _amountOrUnknown(int amount) =>'), true);
      expect(
        flat.contains("_loadFailed ? '확인 불가' : FormatHelper.formatWage(amount)"),
        true,
      );
    });

    test('세 요약 행 모두 그 판정을 거친다', () {
      expect('_amountOrUnknown('.allMatches(flat).length, 4,
          reason: '정의 1 + 근무 완료·근무 예정·예상 수입 3곳');
      // 요약 행이 formatWage를 직접 부르면 실패가 다시 0원으로 샌다.
      for (final label in ['근무 완료', '근무 예정', '예상 수입']) {
        final i = code.indexOf("label: '$label'");
        expect(i > 0, true, reason: '$label 행을 찾지 못함');
        final window = code.substring(i, i + 200);
        expect(window.contains('_amountOrUnknown('), true,
            reason: '$label 행이 실패 판정을 우회한다');
      }
    });

    test('월 이동 실패를 조용히 넘기지 않는다', () {
      final reload = _flat(_codeOf(
          _memberOf(src, 'Future<void> _reloadAttendances() async {')));
      expect(reload.contains('ToastHelper.showError'), true,
          reason: '이전 달 숫자가 그대로 남은 채 아무 말도 하지 않으면 안 된다');
    });
  });
}
