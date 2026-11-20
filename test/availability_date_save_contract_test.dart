// [E1-DATE] 화면이 말하는 날짜 수와 **서버가 실제로 저장할 날짜**가 같다.
//
// ── 반례 (DEV 실측) ───────────────────────────────────────────────────
//   Firestore 원본 `dates` = [2026-10-11, 2026-10-15], KST 오늘 = 2026-10-14.
//   배너 `근무 가능일 2일 등록됨` · 수정 화면 버튼 `2일 저장`.
//   그런데 `callableSetAvailability` 는 `filterValidDates` 로 과거를 떨어내므로
//   실제 저장은 10-15 하루뿐이다. 사용자는 모르는 채 하루를 잃는다.
//
// ── 고친 것 ───────────────────────────────────────────────────────────
//   배너·달력·수정 초기 선택·저장 버튼·전송 payload 가 **같은 한 집합**을
//   쓴다. 서버 정책을 화면에 다시 적지 않고 canonical
//   `WorkerAvailabilityModel.filterValidDates` 를 그대로 호출한다.
//   저장 원본은 건드리지 않는다 — 과거 기록의 보관은 별개 문제다.
//
// ── 함께 고친 것: 달력의 '오늘' ───────────────────────────────────────
//   `TableCalendar` 는 `currentDay` 가 없으면 `DateTime.now()` 로 today 를
//   정하고, 가능일 선택 범위도 기기 날짜로 잘렸다. 서버는 KST day key 로
//   자르므로 기기 시간대에 따라 **저장되지 않을 날짜를 열어 주게** 된다.
//   이제 둘 다 KST 오늘을 쓴다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/worker_availability_model.dart';
import 'package:ALfit/utils/format_helper.dart';

/// KST day key — 기기 시간대와 무관하다.
String _kstKey(DateTime instant) => WorkerAvailabilityModel.dateKeyFrom(instant);

String _kstToday() => WorkerAvailabilityModel.todayKey();

String _kstOffsetKey(int days) =>
    _kstKey(DateTime.now().add(Duration(days: days)));

void main() {
  group('[DS-A] canonical 유효 날짜 정책', () {
    test('DS-1 과거 1일 + 미래 1일 → 미래만 남는다 (DEV 반례)', () {
      final past = _kstOffsetKey(-3);
      final future = _kstOffsetKey(1);
      final valid = WorkerAvailabilityModel.filterValidDates([past, future]);
      expect(valid, [future]);
      expect(valid.length, 1,
          reason: '화면이 2일이라고 말하면 저장 결과와 어긋난다');
    });

    test('DS-2 미래 2일은 둘 다 남는다', () {
      final a = _kstOffsetKey(1);
      final b = _kstOffsetKey(2);
      expect(WorkerAvailabilityModel.filterValidDates([a, b]).length, 2);
    });

    test('DS-3 KST 오늘은 유효하다 — 경계를 잘라내지 않는다', () {
      final today = _kstToday();
      expect(WorkerAvailabilityModel.filterValidDates([today]), [today]);
    });

    test('DS-4 KST 어제는 유효하지 않다', () {
      expect(WorkerAvailabilityModel.filterValidDates([_kstOffsetKey(-1)]),
          isEmpty);
    });

    test('DS-5 KST 내일은 유효하다', () {
      final t = _kstOffsetKey(1);
      expect(WorkerAvailabilityModel.filterValidDates([t]), [t]);
    });

    test('DS-6 과거만 있으면 유효 0일 — 조회 실패와는 다른 상태다', () {
      final onlyPast = [_kstOffsetKey(-5), _kstOffsetKey(-2)];
      expect(WorkerAvailabilityModel.filterValidDates(onlyPast), isEmpty);
      // 원본은 그대로 남는다 — 화면이 거르는 것이지 데이터를 지우는 게 아니다.
      expect(onlyPast.length, 2);
    });

    test('DS-7 빈 입력은 빈 결과', () {
      expect(WorkerAvailabilityModel.filterValidDates(const []), isEmpty);
    });

    test('DS-8 90일 경계 — 포함, 91일 — 제외', () {
      final d90 = _kstOffsetKey(90);
      final d91 = _kstOffsetKey(91);
      final valid = WorkerAvailabilityModel.filterValidDates([d90, d91]);
      expect(valid.contains(d90), isTrue);
      expect(valid.contains(d91), isFalse);
    });

    test('DS-9 정렬만 한다 — 중복 제거는 서버가 맡는다', () {
      final a = _kstOffsetKey(5);
      final b = _kstOffsetKey(2);
      final valid = WorkerAvailabilityModel.filterValidDates([a, b, a, b]);
      // canonical 클라 필터는 중복을 건드리지 않는다. 화면의 선택 집합이
      //   Set 이고 CF 가 다시 `new Set` 으로 묶으므로 실제 저장은 2일이다.
      expect(valid, [b, b, a, a]);
      expect(valid.toSet().length, 2);
    });

    test('DS-10 60개 상한 — 넘으면 뒤쪽(가까운 날)이 남는다', () {
      final many = List.generate(70, (i) => _kstOffsetKey(i + 1));
      final valid = WorkerAvailabilityModel.filterValidDates(many);
      expect(valid.length, 60);
      expect(valid.last, many.last, reason: 'FIFO — 앞부분을 떨어낸다');
    });
  });

  group('[DS-B] KST day key 는 기기 시간대와 무관하다', () {
    test('DS-11 같은 instant 는 어떤 기기에서도 같은 key 를 준다', () {
      // KST 2026-10-14 09:00 = UTC 2026-10-14 00:00.
      final instant = DateTime.utc(2026, 10, 14, 0, 0);
      expect(_kstKey(instant), '2026-10-14');
    });

    test('DS-12 KST 00:00 직후는 그 날이다 (UTC 로는 전날)', () {
      // KST 2026-10-14 00:10 = UTC 2026-10-13 15:10.
      expect(_kstKey(DateTime.utc(2026, 10, 13, 15, 10)), '2026-10-14');
    });

    test('DS-13 KST 23:59 는 아직 그 날이다', () {
      // KST 2026-10-14 23:59 = UTC 2026-10-14 14:59.
      expect(_kstKey(DateTime.utc(2026, 10, 14, 14, 59)), '2026-10-14');
    });

    test('DS-14 KST 자정을 넘기면 다음 날이다', () {
      expect(_kstKey(DateTime.utc(2026, 10, 14, 15, 0)), '2026-10-15');
    });

    test('DS-15 달력 셀(civil)은 성분 그대로 key 가 된다', () {
      // 달력 셀은 기기 local 의 `DateTime(y, m, d)` 다. 여기에 instant→KST
      //   변환을 쓰면 UTC+9 를 넘는 기기에서 하루가 밀린다. 성분을 쓴다.
      final cell = DateTime(2026, 10, 15);
      expect(
          FormatHelper.toKstDateKey(FormatHelper.kstDayKeyOfCivil(cell)),
          '2026-10-15');
    });
  });

  group('[DS-C] 화면이 같은 자를 쓴다', () {
    String src(String p) =>
        File(p).readAsStringSync().replaceAll('\r\n', '\n');

    test('DS-16 배너·달력·수정·payload 가 모두 유효 집합을 쓴다', () {
      final s = src('lib/screens/user/my_schedule_screen.dart');
      expect(s.contains('_validAvailabilityDates'), isTrue);
      expect(s.contains('final count = _validAvailabilityDates.length;'), isTrue,
          reason: '배너는 저장 원본이 아니라 유효 날짜를 센다');
      expect(s.contains('availabilityDates: _validAvailabilityDates,'), isTrue,
          reason: '달력도 유효 날짜만 가능일로 강조한다');
      expect(
          s.contains('_editingDates = Set<String>.from(_validAvailabilityDates);'),
          isTrue,
          reason: '수정은 유효 날짜에서 시작한다');
      expect(s.contains('final payload = _editingPayload;'), isTrue);
      expect(s.contains('dates: payload,'), isTrue);
    });

    test('DS-17 저장 버튼의 수와 전송 payload 가 같은 getter 에서 나온다', () {
      final s = src('lib/screens/user/my_schedule_screen.dart');
      expect(s.contains('_editingPayload.isEmpty'), isTrue);
      expect(s.contains('\${_editingPayload.length}일 저장'), isTrue);
      expect(s.contains('\${_editingDates.length}일 저장'), isFalse,
          reason: '선택 집합을 그대로 세면 저장되지 않을 수를 약속한다');
    });

    test('DS-18 저장 후 화면 상태는 보낸 값이 아니라 서버가 받은 집합이다', () {
      final s = src('lib/screens/user/my_schedule_screen.dart');
      expect(s.contains('final saved = Set<String>.from(payload);'), isTrue);
      expect(s.contains('final saved = Set<String>.from(_editingDates);'),
          isFalse);
    });

    test('DS-19 서버 정책을 화면에 다시 적지 않는다', () {
      final s = src('lib/screens/user/my_schedule_screen.dart');
      // 유효성 판정은 canonical 함수 호출로만 이뤄진다.
      expect(s.contains('WorkerAvailabilityModel.filterValidDates'), isTrue);
      expect(s.contains('todayKey()'), isFalse,
          reason: '날짜 경계를 화면에서 다시 계산하지 않는다');
    });

    test('DS-20 달력의 오늘·선택 범위가 KST 를 쓴다', () {
      final cal = src('lib/widgets/calendar/app_calendar.dart');
      expect(cal.contains('currentDay: today'), isTrue,
          reason: 'TableCalendar 기본값(DateTime.now)을 쓰면 기기 날짜가 된다');
      expect(cal.contains('FormatHelper.toKstDate(DateTime.now())'), isTrue);

      final sc = src('lib/widgets/calendar/schedule_calendar.dart');
      expect(sc.contains('FormatHelper.toKstDate(DateTime.now())'), isTrue,
          reason: '선택 가능 범위도 서버와 같은 KST 기준이어야 한다');
      // 주석 줄은 제외한다 — 설명문이 자기 자신을 잡는다.
      final scCode = sc
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(scCode.contains('WorkerAvailabilityModel.dateKeyFrom'), isFalse,
          reason: '달력 셀은 civil 성분으로 key 를 만든다');
      expect(sc.contains('_civilDateKey'), isTrue);
    });
  });

  group('[DS-D] 조회 실패 보호가 유지된다', () {
    test('DS-21 유효 0일과 조회 실패는 다른 상태다', () {
      final s = File('lib/screens/user/my_schedule_screen.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      // 직전 Phase 의 _AvailLoad 계약이 그대로 있다.
      expect(s.contains('_AvailLoad.loading'), isTrue);
      expect(s.contains('_AvailLoad.failed'), isTrue);
      expect(s.contains('if (_availLoad != _AvailLoad.ok) {'), isTrue,
          reason: '못 읽은 상태로 수정에 들어가면 저장 한 번에 지워진다');
    });
  });
}
