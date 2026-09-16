// [PREDEVICE-WORK-CALENDAR] 달력 marker는 근무 목록과 같은 현실을 말한다
//
// READ에서 확인된 것:
//   · 근무 탭은 운영 화면이다. 선택 날짜의 목록은 좌석을 확보한 근로자
//     (CONFIRMED + CONTRACT_PENDING)를 읽는다 — 모집 상태(OPEN/FULL/CLOSED)나
//     TO 존재 여부를 보지 않는다.
//   · 그런데 주간 strip에는 marker가 없었고, 월 달력은
//     `eventLoader: (_) => const []`로 열려 marker가 아예 존재하지 않았다.
//     관리자는 날짜를 하나씩 눌러보기 전에는 일이 있는지 알 수 없었다.
//
// 계약:
//   marker(date) 는 selectedDateWorkList(date).isNotEmpty 와 같은 규칙에서 나온다.
//   주간과 월간이 같은 집합을 읽는다. 날짜마다 조회하지 않는다.
//   모르는 것과 없는 것을 구분한다.
//
// DEV runtime (KST · America/New_York 양쪽):
//   범위 44일을 사업장당 2회 조회 · marker 날짜 = 목록 날짜 완전 일치 ·
//   CLOSED TO의 좌석도 marker 유지 · 다른 사업장 날짜 누출 없음.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _viewPath =
    'lib/screens/business_admin/workforce_management/workforce_operational_view.dart';
const _appFsPath = 'lib/services/firestore/application_firestore.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  final view = _src(_viewPath);
  final viewCode = _codeOf(view);
  final viewFlat = _flat(viewCode);
  final fs = _codeOf(_src(_appFsPath));
  final fsFlat = _flat(fs);

  group('marker는 근무 목록과 같은 규칙에서 나온다', () {
    test('장기 근무 판정이 한 곳에만 있다', () {
      expect(fs.contains('static bool isLongTermSeatedOnDate('), true,
          reason: '당일 조회와 범위 조회가 같은 함수를 불러야 한다');
      expect('isLongTermSeatedOnDate('.allMatches(fsFlat).length >= 3, true,
          reason: '선언 1 + 당일 조회 + 범위 조회');
    });

    test('범위 조회가 당일 조회와 같은 좌석 상태를 본다', () {
      expect(
        'const confirmedStatuses = {AppStatus.confirmed, AppStatus.contractPending};'
            .allMatches(fsFlat)
            .length,
        2,
        reason: '두 조회가 다른 상태 집합을 쓰면 marker와 목록이 갈라진다',
      );
    });

    test('marker는 모집 상태를 보지 않는다', () {
      final i = fs.indexOf('getSeatedWorkDatesInRange');
      expect(i > 0, true);
      final body = fs.substring(i, i + 3000);
      for (final forbidden = ['FULL', 'CLOSED', 'isManualClosed', "'tos'"];
          false;) {}
      for (final f in ['FULL', 'CLOSED', 'isManualClosed', "'tos'"]) {
        expect(body.contains(f), false,
            reason: '$f 를 보면 FULL/CLOSED가 근무를 지우는 셈이 된다');
      }
    });
  });

  group('날짜마다 조회하지 않는다', () {
    test('범위 조회는 사업장당 고정 횟수다', () {
      final i = fs.indexOf('getSeatedWorkDatesInRange');
      final body = _flat(fs.substring(i, i + 3000));
      expect('callable.call<Map<String, dynamic>>('.allMatches(body).length, 2,
          reason: '단기 범위 1회 + 장기 후보 1회 — 날짜 수와 무관해야 한다');
      // 루프 안에서 조회하면 N+1이 된다.
      final loopAt = body.indexOf('for (var d = rangeStart;');
      expect(loopAt > 0, true);
      expect(body.substring(loopAt).contains('callable.call'), false,
          reason: '날짜 루프 안에서 조회하면 N+1이다');
    });

    test('marker를 위한 새 listener나 polling을 만들지 않는다', () {
      expect(viewFlat.contains('Timer.periodic'), false);
      expect(viewFlat.contains('snapshots()'), false);
      // 기존 refresh 경로에 얹는다.
      expect(viewFlat.contains('_loadMarkerRange(_selectedDay, force: true)'),
          true, reason: '_reload가 marker도 함께 갱신해야 한다');
      expect(
        'WorkforceController.dataRevision.addListener'.allMatches(viewFlat).length,
        1,
        reason: '기존 listener 하나만 유지 — marker용 구독을 늘리지 않는다',
      );
    });
  });

  group('주간과 월간이 같은 집합을 읽는다', () {
    test('월 달력이 자기 조회를 따로 하지 않는다', () {
      expect(viewFlat.contains('final Set<DateTime>? workDates;'), true);
      expect(viewFlat.contains('workDates: _workDates,'), true,
          reason: '시트가 주간 strip의 집합을 그대로 받아야 한다');
      expect(viewFlat.contains('eventLoader: (_) => const [],'), false,
          reason: 'marker 없는 옛 월 달력이 남아 있다');
    });

    test('두 표면이 같은 날짜 키를 쓴다 — KST', () {
      expect(viewFlat.contains('dates.contains(FormatHelper.toKstDate(day))'),
          true, reason: '주간 strip 판정');
      expect(
        viewFlat.contains('dates.contains(FormatHelper.toKstDate(day))'),
        true,
        reason: '월 달력 eventLoader도 같은 키',
      );
      expect(fsFlat.contains('FormatHelper.kstDayRange(start)'), true);
      expect(fsFlat.contains('dates.add(FormatHelper.toKstDate(app.workDate));'),
          true, reason: '기기 로컬 자정을 쓰면 비KST에서 하루 밀린다');
    });
  });

  group('marker 하나 · 선택 상태에서도 보인다', () {
    test('같은 날 업무가 여럿이어도 dot은 하나다', () {
      expect(viewFlat.contains('const Object _kWorkMarker = Object();'), true);
      expect(viewFlat.contains('? const [_kWorkMarker]'), true,
          reason: '개수만큼 marker를 만들지 않는다');
    });

    test('선택 배경 위에서 marker가 사라지지 않는다', () {
      expect(
        viewFlat.contains('_dot(isSelected ? Colors.white : AppColors.grey600)'),
        true,
        reason: '선택 색 위에서 같은 색 dot을 그리면 안 보인다',
      );
    });

    test('상태별 다색 taxonomy를 만들지 않는다', () {
      final i = viewCode.indexOf('Widget _dot(Color color)');
      expect(i > 0, true);
      // marker 색은 두 가지(선택 여부)뿐이다.
      expect(viewCode.contains('AppColors.error'), true); // 일요일 등 기존 용도
      expect(viewFlat.contains('shortage'), false,
          reason: '부족/근태/계약 상태를 색으로 표현하지 않는다');
    });
  });

  group('모르는 것과 없는 것을 구분한다', () {
    test('marker 집합이 nullable이다', () {
      expect(viewFlat.contains('Set<DateTime>? _workDates;'), true);
      expect(viewFlat.contains('if (dates == null) return null;'), true,
          reason: '모르면 null — false(일 없음)로 답하지 않는다');
      expect(viewFlat.contains('if (dates == null) return const [];'), true,
          reason: '월 달력도 모르면 marker를 그리지 않는다');
    });

    test('실패를 일 없음으로 그리지 않는다', () {
      expect(viewFlat.contains('bool _markerFailed = false;'), true);
      expect(viewFlat.contains('_workDates = null; _markerFailed = true;'), true,
          reason: '실패 시 빈 Set을 넣으면 "이번 달 일 없음"이 된다');
      expect(viewCode.contains('근무가 있는 날짜를 표시하지 못했어요'), true);
      expect(viewFlat.contains('_loadMarkerRange(_selectedDay, force: true)'),
          true, reason: '다시 시도 경로가 있어야 한다');
    });
  });
}
