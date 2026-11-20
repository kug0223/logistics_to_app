// [DU1 followup_5 §4] SubAdmin 급여 입력 — 후보 지원서 projection LOCAL 계약(미구현·미배포·미연결).
//   서버가 줄 수 있는 최소 필드(WageDayClassification.candidateApplicationProjection)로
//   CF 직렬화({_seconds,_nanoseconds}) → 축소 → 클라이언트 재수화 → ApplicationModel → 급여 입력이
//   **전체 문서와 같은 결과**를 내는지 본다. 같지 않으면 그 필드가 빠졌다는 뜻이다.
//   PC-1 MANUAL 약속(통상시급 지정) / PC-2 AUTO 약속 / PC-3 레거시(스냅샷 없음) — resolve·급여창 사용 필드 동일
//   PC-4 필드 하나씩 빼기 — appliedAt·workDate 는 파싱 실패, 약속 필드는 resolve 가 달라진다(필수 근거)
//   PC-5 민감·무관 필드는 projection 에 없다
//   서버 미리보기 일치(PREVIEW_MISMATCH)는 서버가 지원서 원문을 다시 읽어 계산하므로(index.ts:27736) 이 시험은
//   클라이언트 입력 동치까지만 본다 — 서버 측 동치는 후보 CF 를 만들 때 에뮬레이터로 잰다(미실행).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/screens/business_admin/dialogs/wage_day_inputs_loader.dart';
import 'package:ALfit/utils/work_detail_helper.dart';

const _proj = WageDayClassification.candidateApplicationProjection;

/// CF serializeFirestoreData 와 같은 모양으로 직렬화.
Object? _ser(Object? v) {
  if (v is Timestamp) return {'_seconds': v.seconds, '_nanoseconds': v.nanoseconds};
  if (v is Map) return v.map((k, e) => MapEntry(k, _ser(e)));
  if (v is List) return v.map(_ser).toList();
  return v;
}

/// lib/services/firestore_service.dart:111 `_cfHydrate` 와 같은 재수화(그 함수는 private 라 여기 옮겨 둔다).
Map<String, dynamic> _hydrate(Map<String, dynamic> m) => m.map((k, v) {
      if (v is Map) {
        final vm = Map<String, dynamic>.from(v);
        if (vm.containsKey('_seconds')) {
          return MapEntry(k, Timestamp((vm['_seconds'] as num).toInt(), (vm['_nanoseconds'] as num? ?? 0).toInt()));
        }
        return MapEntry(k, _hydrate(vm));
      }
      return MapEntry(k, v);
    });

Map<String, dynamic> _viaProjection(Map<String, dynamic> full, {Set<String> fields = _proj}) {
  final wire = Map<String, dynamic>.from(_ser(full) as Map);
  wire.removeWhere((k, _) => !fields.contains(k));
  return _hydrate(wire);
}

Timestamp _kst(int d, [int h = 0]) =>
    Timestamp.fromMillisecondsSinceEpoch(DateTime.utc(2026, 11, d, h).millisecondsSinceEpoch - 9 * 3600 * 1000);

Map<String, dynamic> _full({String? mode, int? baseHourly, bool snapshot = true}) => {
      'uid': 'w1', 'businessId': 'b1', 'businessName': 'B', 'toTitle': '단기', 'status': 'CONFIRMED',
      'toId': 'to1', 'slotId': 's1', 'workDetailId': 'QA_09:00_18:00', 'wdId': 'wd1', 'selectedWorkType': 'QA',
      'startTime': '09:00', 'endTime': '18:00', 'workDate': _kst(3), 'appliedAt': _kst(1, 10), 'confirmedAt': _kst(2),
      'wage': 13000, 'wageType': 'hourly',
      if (snapshot) ...{
        'breakMinutes': 45, 'nightAllowanceApplied': false, 'nightIncluded': true, 'taxDeductionType': 'freelancer_3_3',
        if (baseHourly != null) 'baseHourlyWage': baseHourly,
        if (mode != null) 'baseHourlyWageMode': mode,
      },
      // 급여창이 쓰지 않는 민감·무관 필드
      'applicationMessage': '연락 주세요 010-0000-0000', 'cancelReason': '개인 사정', 'resignRequestDate': _kst(20),
      'attendancePolicyAcknowledgement': {'v': 1}, 'conflictingBusiness': '다른 사업장', 'workTypeIcon': 'box',
    };

/// 공고 현재(live) 정의 — 약속과 일부러 다르게 둔다(약속 우선이 보이도록).
final _timeMap = <String, dynamic>{
  'QA_09:00_18:00': <String, dynamic>{
    'wage': 15000, 'wageType': 'hourly', 'breakMinutes': 60, 'baseHourlyWage': 16000,
    'nightAllowanceApplied': true, 'nightIncluded': false, 'taxDeductionType': 'none',
  },
};

void _expectSameInputs(Map<String, dynamic> full) {
  final a = ApplicationModel.tryFromMap(full, 'app1');
  final b = ApplicationModel.tryFromMap(_viaProjection(full), 'app1');
  expect(a, isNotNull);
  expect(b, isNotNull, reason: 'projection 만으로 파싱된다');
  // 급여창이 읽는 필드(wage_confirm_dialog.dart 의 app.* 전수)
  expect([b!.id, b.uid, b.toId, b.slotId, b.selectedWorkType, b.workDetailId, b.wageType, b.startTime, b.endTime, b.wage],
      [a!.id, a.uid, a.toId, a.slotId, a.selectedWorkType, a.workDetailId, a.wageType, a.startTime, a.endTime, a.wage]);
  expect(b.workDate, a.workDate);
  expect(b.promisedCompensation, a.promisedCompensation);
  expect(b.hasCompensationSnapshot, a.hasCompensationSnapshot);
  expect(WorkDetailHelper.baseHourlyWageModeOf(b), WorkDetailHelper.baseHourlyWageModeOf(a));
  expect(WorkDetailHelper.resolve(b, _timeMap), WorkDetailHelper.resolve(a, _timeMap), reason: '약속 우선 결과가 같다');
}

void main() {
  test('PC-1 MANUAL 약속 — projection 이 전체 문서와 같은 급여 입력을 만든다', () {
    _expectSameInputs(_full(mode: 'MANUAL', baseHourly: 14000));
    final r = WorkDetailHelper.resolve(ApplicationModel.tryFromMap(_viaProjection(_full(mode: 'MANUAL', baseHourly: 14000)), 'x')!, _timeMap)!;
    expect(r['wage'], 13000, reason: '공고 현재 15,000 이 아니라 약속');
    expect(r['breakMinutes'], 45);
    expect(r['baseHourlyWage'], 14000);
    expect(r['taxDeductionType'], 'freelancer_3_3');
  });

  test('PC-2 AUTO 약속 — live 통상시급을 지운 결과까지 같다', () {
    _expectSameInputs(_full(mode: 'AUTO'));
    final r = WorkDetailHelper.resolve(ApplicationModel.tryFromMap(_viaProjection(_full(mode: 'AUTO')), 'x')!, _timeMap)!;
    expect(r.containsKey('baseHourlyWage'), isFalse);
  });

  test('PC-3 레거시(스냅샷 없음) — 같은 결과(공고 현재값 위에 wage 만), 추정 기본값 없음', () {
    _expectSameInputs(_full(snapshot: false));
  });

  test('PC-4 하나씩 빼면 깨진다 — 각 필드의 필요 근거', () {
    final full = _full(mode: 'MANUAL', baseHourly: 14000);
    for (final k in const ['workDate', 'appliedAt']) {
      expect(ApplicationModel.tryFromMap(_viaProjection(full, fields: {..._proj}..remove(k)), 'x'), isNull, reason: '$k 없으면 파싱 실패');
    }
    final base = WorkDetailHelper.resolve(ApplicationModel.tryFromMap(full, 'x')!, _timeMap);
    for (final k in const ['wage', 'breakMinutes', 'baseHourlyWage', 'nightAllowanceApplied', 'nightIncluded', 'taxDeductionType']) {
      final m = ApplicationModel.tryFromMap(_viaProjection(full, fields: {..._proj}..remove(k)), 'x');
      final got = m == null ? null : WorkDetailHelper.resolve(m, _timeMap);
      expect(got, isNot(equals(base)), reason: '$k 를 빼면 약속/연결 결과가 달라진다');
    }
    // 일정·관계 키 — resolve 는 workDetailId 키로 풀려 startTime·selectedWorkType 없이도 같을 수 있다(실측).
    //   그러나 급여창은 app.startTime/endTime 을 예정 시각으로, toId/slotId 를 슬롯·공고 조회에 직접 쓴다.
    List<Object?> used(ApplicationModel m) => [m.toId, m.slotId, m.startTime, m.endTime, m.workDetailId, m.selectedWorkType];
    final ref = used(ApplicationModel.tryFromMap(full, 'x')!);
    for (final k in const ['toId', 'slotId', 'startTime', 'endTime', 'workDetailId', 'selectedWorkType']) {
      final m = ApplicationModel.tryFromMap(_viaProjection(full, fields: {..._proj}..remove(k)), 'x');
      expect(m == null ? null : used(m), isNot(equals(ref)), reason: '$k 를 빼면 급여창이 읽는 값이 달라진다');
    }
  });

  test('PC-5 민감·무관 필드는 projection 에 없다', () {
    for (final k in const ['applicationMessage', 'cancelReason', 'resignRequestDate', 'attendancePolicyAcknowledgement',
        'conflictingBusiness', 'workTypeIcon', 'confirmedAt', 'toTitle']) {
      expect(_proj.contains(k), isFalse, reason: k);
    }
    final wire = _viaProjection(_full(mode: 'MANUAL', baseHourly: 14000));
    expect(wire.keys.toSet().difference(_proj), isEmpty);
  });
}
