// [R7-PRE0] 정원 맵을 만드는 쪽과 찾는 쪽이 같은 키를 해석한다.
//
//   canonical key 는 wdId 다. WorkDetailData 가 이미 그렇게 적어 두었다 —
//     String get canonicalId => wdId ?? id;   // id 는 계산되는 composite
//
//   그런데 두 쪽이 서로 다른 필드를 보고 있었다.
//     맵 생성 : map['id']            ← 슬롯 workDetail 에 없는 필드 (DEV 259건 중 0건)
//     조회    : app.workDetailId     ← 문서형 ID
//   결과: DEV 120건 중 111건이 빗나가 `?? 0` → "정원 0" → 충원 버튼 소멸.
//
//   이 파일은 두 쪽의 **키 우선순위가 같다**는 것만 고정한다.
//   capacity 구조 자체는 건드리지 않는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/work_detail_data.dart';

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

/// 맵 생성 측 키 선택 replica (to_firestore.getSlotWorkDetailCapacities).
String mapKeyOf({String? wdId, String? id, required String workType,
    required String startTime, required String endTime}) {
  if (wdId != null && wdId.isNotEmpty) return wdId;
  if (id != null && id.isNotEmpty) return id;
  return '${workType}_${startTime}_$endTime';
}

/// 조회 측 키 선택 replica (day_applicants_dialog).
String lookupKeyOf({String? wdId, String? workDetailId,
    required String workType, required String startTime,
    required String endTime}) {
  if (wdId != null && wdId.isNotEmpty) return wdId;
  if (workDetailId != null && workDetailId.isNotEmpty) return workDetailId;
  return '${workType}_${startTime}_$endTime';
}

void main() {
  const toSvc = 'lib/services/firestore/to_firestore.dart';
  const dayDlg = 'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';

  group('[R7PRE0] 두 쪽이 같은 키를 만든다', () {
    test('CK-1 현행 데이터: 양쪽 wdId → 일치', () {
      // DEV 실측 형상 — 슬롯은 wdId 만, 지원서는 wdId 와 workDetailId 둘 다.
      const wd = '5M1auMotqhkmWeQtuepH';
      final mapKey = mapKeyOf(
          wdId: wd, id: null,
          workType: '사무업무', startTime: '12:56', endTime: '13:21');
      final lookKey = lookupKeyOf(
          wdId: wd, workDetailId: wd,
          workType: '사무업무', startTime: '12:56', endTime: '13:21');
      expect(mapKey, lookKey);
      expect(mapKey, wd);
    });

    test('CK-2 예전 형상(맵 id / 조회 workDetailId)이 어긋났다는 것을 기록', () {
      // 고치기 전 동작 — 회귀하면 이 값이 다시 같아진다.
      String oldMapKey(Map<String, String?> m) =>
          (m['id']?.isNotEmpty == true)
              ? m['id']!
              : '${m['workType']}_${m['startTime']}_${m['endTime']}';
      final oldKey = oldMapKey({
        'id': null, 'workType': '사무업무',
        'startTime': '12:56', 'endTime': '13:21',
      });
      expect(oldKey, '사무업무_12:56_13:21');
      expect(oldKey, isNot('5M1auMotqhkmWeQtuepH'),
          reason: '조회는 문서형 ID 로 찾았으므로 빗나갔다');
    });

    test('CK-3 legacy: wdId 없고 슬롯에 id 가 있으면 그 값으로 만난다', () {
      const legacy = 'legacy-composite-id';
      expect(
          mapKeyOf(wdId: null, id: legacy,
              workType: '홀', startTime: '09:00', endTime: '18:00'),
          legacy);
      expect(
          lookupKeyOf(wdId: null, workDetailId: legacy,
              workType: '홀', startTime: '09:00', endTime: '18:00'),
          legacy);
    });

    test('CK-4 legacy: 양쪽 다 아무 id 도 없으면 composite 로 만난다', () {
      const wt = '홀', s = '09:00', e = '18:00';
      expect(mapKeyOf(wdId: null, id: null,
              workType: wt, startTime: s, endTime: e),
          lookupKeyOf(wdId: null, workDetailId: null,
              workType: wt, startTime: s, endTime: e));
      expect(mapKeyOf(wdId: null, id: null,
              workType: wt, startTime: s, endTime: e), '홀_09:00_18:00');
    });

    test('CK-5 빈 문자열은 값이 아니다 — 다음 폴백으로 내려간다', () {
      expect(
          mapKeyOf(wdId: '', id: '',
              workType: '홀', startTime: '09:00', endTime: '18:00'),
          '홀_09:00_18:00');
      expect(
          lookupKeyOf(wdId: '', workDetailId: '',
              workType: '홀', startTime: '09:00', endTime: '18:00'),
          '홀_09:00_18:00');
    });

    test('CK-6 우선순위가 모델의 canonicalId 와 같은 방향이다', () {
      const wd = WorkDetailData(
        wdId: 'wd-1', workType: '홀', startTime: '09:00', endTime: '18:00',
        wage: 10000, requiredCount: 3,
      );
      expect(wd.canonicalId, 'wd-1', reason: 'wdId 가 있으면 그것이 canonical');
      expect(wd.id, '홀_09:00_18:00', reason: 'id 는 계산되는 composite');
      expect(
          mapKeyOf(wdId: wd.wdId, id: null, workType: wd.workType,
              startTime: wd.startTime, endTime: wd.endTime),
          wd.canonicalId);
    });
  });

  group('[R7PRE0] 소비 측 identity 조회', () {
    const modern = WorkDetailData(
      wdId: 'wd-1', workType: '홀', startTime: '09:00', endTime: '18:00',
      wage: 10000, requiredCount: 3,
    );
    const legacy = WorkDetailData(
      workType: '홀', startTime: '09:00', endTime: '18:00',
      wage: 10000, requiredCount: 3,
    );

    test('CK-11 wdId 로 집계된 통계를 찾는다', () {
      final stats = {'wd-1': {'confirmed': 1, 'pending': 0}};
      expect(modern.lookupByIdentity(stats)?['confirmed'], 1,
          reason: 'work.id(composite) 만 보면 놓치던 자리다');
    });

    test('CK-12 composite 로 집계된 legacy 통계도 찾는다', () {
      final stats = {'홀_09:00_18:00': {'confirmed': 2, 'pending': 1}};
      expect(modern.lookupByIdentity(stats)?['confirmed'], 2,
          reason: 'wdId 가 없는 옛 집계와도 만나야 한다');
      expect(legacy.lookupByIdentity(stats)?['confirmed'], 2);
    });

    test('CK-13 canonical 이 우선이다', () {
      final stats = {
        'wd-1': {'confirmed': 1, 'pending': 0},
        '홀_09:00_18:00': {'confirmed': 9, 'pending': 9},
      };
      expect(modern.lookupByIdentity(stats)?['confirmed'], 1);
    });

    test('CK-14 없으면 null — 0 으로 바꾸지 않는다', () {
      expect(modern.lookupByIdentity(<String, Map<String, int>>{}), isNull);
      expect(modern.lookupByIdentity<Map<String, int>>(null), isNull,
          reason: '맵 자체가 없는 것(UNKNOWN)과 0 은 다르다');
    });
  });

  group('[R7PRE0] 소스 고정', () {
    test('CK-7 맵 생성이 wdId 를 먼저 본다', () {
      final code = _flat(_codeOf(_read(toSvc)));
      expect(code.contains("(map['wdId'] as String?)?.isNotEmpty == true ? map['wdId'] as String"),
          isTrue);
      // legacy 폴백 둘 다 남아 있어야 한다.
      expect(code.contains("(map['id'] as String?)?.isNotEmpty == true"), isTrue);
      expect(code.contains("'\${map['workType']}_\${map['startTime']}_\${map['endTime']}'"),
          isTrue);
    });

    test('CK-8 조회가 wdId 를 먼저 본다', () {
      final code = _flat(_codeOf(_read(dayDlg)));
      expect(code.contains('final compositeKey = app.wdId?.isNotEmpty == true ? app.wdId!'),
          isTrue);
      expect(code.contains('app.workDetailId?.isNotEmpty == true ? app.workDetailId!'),
          isTrue, reason: 'legacy 지원서 폴백 유지');
    });

    test('CK-9 그룹키와 정원 조회키가 같은 우선순위를 쓴다', () {
      // 그룹키(wKey)는 원래 wdId 를 먼저 봤다. 이제 정원 조회도 같다.
      final code = _flat(_codeOf(_read(dayDlg)));
      expect(code.contains('final wKey = app.wdId?.isNotEmpty == true ? app.wdId!'),
          isTrue);
    });

    test('CK-15 집계 측이 app.wdId 를 먼저 본다', () {
      final code = _flat(_codeOf(_read('lib/services/firestore_service.dart')));
      expect(code.contains('final canonical = app.wdId;'), isTrue);
      expect(code.contains('legacyId != app.selectedWorkType'), isTrue,
          reason: 'legacy 폴백 유지');
    });

    test('CK-16 통계 소비처가 work.id 단독으로 찾지 않는다', () {
      const consumers = [
        'lib/widgets/admin/cards/admin_to_group_card.dart',
        'lib/widgets/admin/cards/admin_to_item_card.dart',
        'lib/widgets/admin/cards/admin_work_detail.dart',
        'lib/models/ui/admin_to_list_ui_models.dart',
        'lib/screens/business_admin/dialogs/work_detail_management_dialog.dart',
        'lib/screens/business_admin/dialogs/work_applicants_dialog.dart',
        'lib/screens/common/job_posting_screen.dart',
      ];
      for (final p in consumers) {
        final code = _flat(_codeOf(_read(p)));
        expect(RegExp(r'workDetailStats\?\[\w+(\.\w+)*\.id\]').hasMatch(code),
            isFalse, reason: '$p 에 work.id 단독 조회가 남아 있다');
      }
    });

    test('CK-17 WorkApplicants 매칭이 canonical 을 먼저 본다', () {
      final code = _flat(_codeOf(
          _read('lib/screens/business_admin/dialogs/work_applicants_dialog.dart')));
      expect(code.contains('return appWdId == workWdId;'), isTrue);
      expect(code.contains('if (wdId == widget.work!.id) return true;'), isTrue,
          reason: 'legacy composite 매칭은 남아 있어야 한다');
    });

    test('CK-10 capacity 구조를 리팩터링하지 않았다', () {
      final code = _flat(_codeOf(_read(toSvc)));
      expect(code.contains('Future<Map<String, int>> getSlotWorkDetailCapacities('),
          isTrue, reason: '시그니처 유지');
      expect(code.contains('rethrow;'), isTrue, reason: 'P7.3 ERROR!=ZERO 유지');
      expect(code.contains('getSlotWorkDetailCapacities: 슬롯 문서를 찾지 못했다'),
          isTrue, reason: 'P9E 문서부재 UNKNOWN 유지');
    });
  });
}
