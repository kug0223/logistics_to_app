// [R8-P9D] flex 근무 날짜를 등록일로 추론하지 않는다.
//
//   P9C 에서 노출 게이트의 rangeEnd 의존을 걷어냈는데, 같은 뿌리가 두 곳
//   더 있었다. 둘 다 "날짜를 모르면 없는 것으로 친다"는 같은 실수다.
//
//     일자리 탭 날짜범위 필터  — `to.rangeEnd ?? to.date`, to.date 는 createdAt 폴백
//     구직자 홈 날짜칩/칩필터  — `rangeStart == null` 이면 통째로 제외
//
//   DEV 에서 노출 가능한 flex 공고 4건이 전부 rangeStart·rangeEnd 가 없다.
//   kcwGL5K4 는 오늘 근무가 열려 있는데 createdAt 이 일주일 전이라,
//   "이번 주"로 거르면 사라졌다. 등록한 날이 일하는 날을 대신할 수 없다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/utils/format_helper.dart';

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('파일을 찾지 못했다: $p');
  return f.readAsStringSync();
}

String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// DEV 의 kcwGL5K4 와 같은 형상 — rangeStart·rangeEnd 없음, 슬롯만 있음.
TOModel _flexLikeDev({
  List<String> dates = const ['2026-09-21', '2026-09-22'],
  int? totalSlots,
  DateTime? createdAt,
}) =>
    TOModel(
      id: 'to-1',
      businessId: 'biz-1',
      businessName: '사업장',
      title: '공고',
      creatorUID: 'admin-1',
      type: TOType.flex,
      status: TOStatus.active,
      isPublished: true,
      slotDateKeys: dates,
      totalSlots: totalSlots ?? dates.length,
      totalRequired: 3,
      createdAt: createdAt ?? DateTime.utc(2026, 9, 15),
    );

void main() {
  const jobTab = 'lib/screens/user/tabs/user_job_tab.dart';
  const home = 'lib/screens/user/user_home_screen.dart';

  group('[R8P9D] 날짜 키 헬퍼', () {
    test('KEY-1 toKstDateKey 와 parseKstDateKey 가 왕복한다', () {
      final d = DateTime.utc(2026, 9, 22);
      expect(FormatHelper.toKstDateKey(d), '2026-09-22');
      expect(FormatHelper.parseKstDateKey('2026-09-22'), d);
    });

    test('KEY-2 parseKstDateKey 는 어긋난 형식을 null 로 돌려준다', () {
      for (final bad in ['2026-9-22', 'not-a-date', '', '2026-13-01',
        '2026-09-32']) {
        expect(FormatHelper.parseKstDateKey(bad), isNull, reason: bad);
      }
    });

    test('KEY-3 키 문자열 비교가 날짜 대소와 같다', () {
      expect('2026-09-21'.compareTo('2026-09-22') < 0, isTrue);
      expect('2026-10-01'.compareTo('2026-09-30') > 0, isTrue);
    });
  });

  group('[R8P9D] 등록일이 근무일을 대신하지 않는다', () {
    test('DEV-1 DEV 형상: rangeStart·rangeEnd 가 없고 createdAt 이 앞선다', () {
      final to = _flexLikeDev();
      expect(to.rangeStart, isNull);
      expect(to.rangeEnd, isNull);
      // TOModel.date 는 rangeStart ?? workStartAvailableFrom ?? createdAt
      expect(FormatHelper.toKstDateKey(to.date), '2026-09-15',
          reason: 'to.date 가 createdAt 으로 떨어진다 — 이것이 예전 필터의 경계였다');
      expect(to.slotDateKeys, contains('2026-09-22'),
          reason: '실제 근무일은 따로 있다');
    });

    test('DEV-2 "이번 주" 범위가 실제 근무일과 겹친다', () {
      final to = _flexLikeDev();
      const from = '2026-09-22', until = '2026-09-28';
      final hit = to.slotDateKeys
          .any((d) => d.compareTo(from) >= 0 && d.compareTo(until) <= 0);
      expect(hit, isTrue);
      // 예전 방식(createdAt 경계)으로는 걸러졌다는 것을 함께 고정한다.
      final oldEnd = FormatHelper.toKstDateKey(to.date);
      expect(oldEnd.compareTo(from) < 0, isTrue,
          reason: '예전 경계로는 "범위보다 이전"이라 제외됐다');
    });

    test('DEV-3 날짜를 모르면 걸러내지 않는다', () {
      final unknown = _flexLikeDev(dates: const [], totalSlots: 0);
      expect(unknown.slotDateKeys, isEmpty);
      // 소비부 계약: 비었거나 불완전하면 범위 판정을 하지 않는다.
      expect(unknown.slotDatesLookComplete, isFalse);
    });

    test('DEV-4 dates 가 뒤처졌으면 범위 판정을 하지 않는다', () {
      final stale = _flexLikeDev(dates: const ['2026-09-18'], totalSlots: 4);
      expect(stale.slotDatesLookComplete, isFalse,
          reason: 'totalSlots 가 더 크다 — 기록되지 않은 날짜가 있다');
    });
  });

  group('[R8P9D] 소비부 계약', () {
    test('CONS-1 일자리 탭 날짜필터가 rangeEnd 를 flex 경계로 쓰지 않는다', () {
      final code = _flat(_codeOf(_read(jobTab)));
      expect(code.contains('(to.rangeEnd ?? to.date)'), isFalse,
          reason: '등록일이 근무 종료일을 대신하던 자리다');
      expect(code.contains('to.slotDateKeys.any('), isTrue);
      expect(code.contains('to.slotDatesLookComplete'), isTrue,
          reason: '뒤처진 dates 로 걸러내면 안 된다');
    });

    test('CONS-2 홈 날짜칩이 flex 를 슬롯 날짜로 센다', () {
      final code = _flat(_codeOf(_read(home)));
      expect(code.contains('if (to.isFlexType) { for (final key in to.slotDateKeys)'),
          isTrue, reason: 'flex 는 범위를 훑지 않고 실제 날짜만 센다');
      expect(code.contains('FormatHelper.parseKstDateKey(key)'), isTrue);
    });

    test('CONS-3 칩 선택 필터가 rangeStart 없음으로 flex 를 버리지 않는다', () {
      final code = _flat(_codeOf(_read(home)));
      expect(code.contains('if (to.slotDateKeys.isEmpty || !to.slotDatesLookComplete) return true;'),
          isTrue, reason: '모르면 남긴다 — 모르는 것으로 숨기지 않는다');
      expect(code.contains('return to.slotDateKeys.contains(sdKey);'), isTrue);
    });

    test('CONS-5 홈이 flex 를 공고 전체 FULL 로 닫지 않는다', () {
      // 서버가 이미 정한 기준이다 — 슬롯 지원은 그 날짜 정원을 직접 본다.
      // 한 날짜가 찼다고 다른 날짜 모집까지 사라지면 안 된다.
      final code = _flat(_codeOf(_read(home)));
      expect(
          code.contains('if (!to.isFlexType && (to.status == TOStatus.full '
              '|| (to.totalRequired > 0 && to.totalConfirmed >= to.totalRequired)))'),
          isTrue);
      // flex 를 무조건 거르던 옛 형태가 남아 있으면 안 된다.
      expect(
          code.contains('to.status == TOStatus.expired || to.status == TOStatus.full'),
          isFalse,
          reason: 'status FULL 을 closed/expired 와 같은 줄에서 거르던 자리');
    });

    test('CONS-4 contract 경로는 그대로다', () {
      final home2 = _flat(_codeOf(_read(home)));
      expect(home2.contains('to.hasWorkStartAvailableRange ? to.workStartAvailableFrom : to.rangeStart'),
          isTrue, reason: 'contract 는 rangeStart/rangeEnd 가 canonical 이다');
      final job2 = _flat(_codeOf(_read(jobTab)));
      expect(job2.contains('to.endDate ?? to.date'), isTrue,
          reason: 'contract 날짜필터 경계는 변경 대상이 아니다');
    });
  });
}
