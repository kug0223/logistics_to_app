// [R8-P10] 근무시간 맵을 만들려고 같은 공고를 두 번 읽지 않는다.
//
//   WorkDetailTimeService 는 이미 근로자 수가 아니라 고유 (toId, slotId)
//   쌍으로 읽는다. 문제는 그 뒤에 붙은 세 번째 라운드였다 —
//   슬롯을 가진 모든 toId 의 마스터 문서를 무조건 한 번 더 읽었다.
//
//   DEV 실측: 확정 19건 → 읽기 25회. 그중 마스터 10회가 맵에 더한 키는 0개.
//   그 라운드가 채우는 것은 `timeMap[workType]` 하나뿐이고, 그 키는
//   _resolveLive 의 마지막 폴백이라 앞 두 키로 풀린 지원서에는 쓰이지 않는다.
//
//   그래서 "아직 안 풀린 지원서가 있을 때만" 읽도록 좁혔다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/utils/work_detail_helper.dart';

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

ApplicationModel _app({
  String toId = 'to-1',
  String? slotId = 'slot-1',
  String workType = '홀서빙',
  String startTime = '09:00',
  String endTime = '18:00',
  String? workDetailId,
}) =>
    ApplicationModel(
      id: 'app-1',
      uid: 'u-1',
      businessId: 'biz-1',
      businessName: '사업장',
      toTitle: '공고',
      toId: toId,
      slotId: slotId,
      workDetailId: workDetailId,
      selectedWorkType: workType,
      startTime: startTime,
      endTime: endTime,
      workDate: DateTime(2026, 9, 22),
      status: AppStatus.confirmed,
      appliedAt: DateTime(2026, 9, 1),
      wage: 10000,
    );

Map<String, dynamic> _entry(String s, String e) => <String, dynamic>{
      'startTime': s,
      'endTime': e,
      'wage': 12000,
      'wageType': 'hourly',
      'breakMinutes': 60,
    };

void main() {
  const svc = 'lib/services/work_detail_time_service.dart';
  const helper = 'lib/utils/work_detail_helper.dart';

  group('[R8P10] 추가 조회가 필요한지의 판정', () {
    test('H2-1 복합키로 풀리면 마스터를 읽을 이유가 없다', () {
      final app = _app();
      final map = {'홀서빙_09:00_18:00': _entry('09:00', '18:00')};
      expect(WorkDetailHelper.resolveLive(app, map), isNotNull);
    });

    test('H2-1b workDetailId 로 풀려도 마찬가지다', () {
      final app = _app(startTime: '', endTime: '', workDetailId: 'wd-7');
      final map = {'wd-7': _entry('10:00', '19:00')};
      expect(WorkDetailHelper.resolveLive(app, map), isNotNull);
    });

    test('H2-2 아무 키로도 안 풀리면 마스터가 필요하다', () {
      final app = _app(workType: '주방', startTime: '07:00', endTime: '15:00');
      final map = {'홀서빙_09:00_18:00': _entry('09:00', '18:00')};
      expect(WorkDetailHelper.resolveLive(app, map), isNull);
    });

    test('H2-2b workType 단독키가 있으면 풀린 것이다 (마지막 폴백)', () {
      final app = _app(workType: '주방', startTime: '07:00', endTime: '15:00');
      final map = {'주방': _entry('08:00', '17:00')};
      expect(WorkDetailHelper.resolveLive(app, map), isNotNull,
          reason: '이 키를 채우는 것이 마스터 라운드의 유일한 목적이다');
    });

    test('H2-2c 슬롯 없는 지원서는 마스터 라운드 대상이 아니다', () {
      // 그 TO 는 2단계에서 이미 읽었다 — 같은 문서를 또 읽어도 달라지지 않는다.
      final code = _flat(_codeOf(_read(svc)));
      expect(code.contains("if (app.slotId == null || app.slotId!.isEmpty) continue;"),
          isTrue);
      expect(code.contains('if (!slotPairs.containsKey(toId)) continue;'), isTrue);
    });
  });

  group('[R8P10] 스냅샷 불변', () {
    test('H2-3 약속 스냅샷이 공고 현재값을 덮는다', () {
      // resolve = {...live, ...promised} — 약속에 키가 있으면 그것이 이긴다.
      final code = _flat(_codeOf(_read(helper)));
      expect(code.contains('final merged = <String, dynamic>{...live, ...promised};'),
          isTrue);
      expect(code.contains('if (live == null) return promised;'), isTrue,
          reason: '공고를 못 읽어도 약속은 남아야 한다');
    });

    test('H2-4 resolveLive 는 약속을 반영하지 않는다 (판정 전용)', () {
      final code = _codeOf(_read(helper));
      final i = code.indexOf('static Map<String, dynamic>? resolveLive(');
      expect(i, greaterThan(0));
      final body = code.substring(i, i + 260);
      expect(body.contains('_resolveLive(app, timeMap)'), isTrue);
      expect(body.contains('promisedCompensation'), isFalse,
          reason: '로더 판정에 약속을 섞으면 공고 조회 필요 여부가 왜곡된다');
    });

    test('H2-6 마스터가 슬롯 값을 되돌리지 않는다 (??=)', () {
      final code = _flat(_codeOf(_read(svc)));
      expect(code.contains('timeInfoMap[workType] ??='), isTrue,
          reason: '슬롯이 채운 값을 마스터 구시간이 덮으면 안 된다');
    });
  });

  group('[R8P10] 조회 경계 / 실패 의미', () {
    test('H2-5 맵이 비어도 시간은 지원서 자기 값으로 떨어진다', () {
      final app = _app();
      // 공고를 못 읽은 경우 — 0 이나 빈 문자열이 아니라 약속된 시각이다.
      expect(WorkDetailHelper.effectiveStart(app, const {}), '09:00');
      expect(WorkDetailHelper.effectiveEnd(app, const {}), '18:00');
    });

    test('H2-5b 지원서에도 시각이 없을 때만 기본값이 나온다', () {
      final app = _app(startTime: '', endTime: '');
      expect(WorkDetailHelper.effectiveStart(app, const {}), '09:00');
      expect(WorkDetailHelper.effectiveEnd(app, const {}), '18:00');
    });

    test('H2-7 읽기는 근로자 수가 아니라 고유 쌍에 비례한다', () {
      final code = _flat(_codeOf(_read(svc)));
      expect(code.contains('final slotPairs = <String, Set<String>>{};'), isTrue);
      expect(code.contains('slotPairs.putIfAbsent(app.toId!, () => {}).add(app.slotId!);'),
          isTrue, reason: '동일 (toId, slotId) 는 한 번만 읽는다');
    });

    test('H2-8 마스터 라운드가 무조건 돌지 않는다', () {
      final code = _flat(_codeOf(_read(svc)));
      expect(code.contains('final masterIds = slotPairs.keys.toSet();'), isFalse,
          reason: '슬롯을 가진 모든 TO 를 무조건 읽던 자리');
      expect(code.contains('if (WorkDetailHelper.resolveLive(app, timeInfoMap) != null) continue;'),
          isTrue);
      expect(code.contains('if (masterIds.isNotEmpty) {'), isTrue);
    });
  });
}
