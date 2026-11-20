// [DSE-CAPACITY DEV RUNTIME] **배포된 서버가 실제로 준 응답**을 production
// 파서로 읽는다.
//
//   fixture 를 손으로 짜지 않았다. `callableGetApplicationsByBiz(purpose:
//   capacity)` 를 실제 QA 관리자 Auth + App Check 로 호출해 받은 JSON 을
//   그대로 저장하고(`test/fixtures/dsecap_dev_capacity_response.json`),
//   여기서 같은 hydrate → `ApplicationModel.tryFromMap` → 좌석 판정을 거친다.
//
//   재생성: scratchpad `dsecap-runtime.js` (READ ONLY, DEV).
//
//   canonical 사실 (DEV `ZujrV62Z2ctTDtdVZy9y`)
//     10/12  필요 2 · 확정 1 (wdId UBxR73VI78Z6MSkSd04Z, 09:00~13:00)
//     10/13  필요 2 · 확정 0
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';

const _fixture = 'test/fixtures/dsecap_dev_capacity_response.json';

Map<String, dynamic> _load() {
  final f = File(_fixture);
  if (!f.existsSync()) {
    throw StateError('$_fixture 없음 — dsecap-runtime.js 로 다시 받아야 한다');
  }
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

/// `_cfHydrate` 와 같은 변환 — CF 는 Timestamp 를 {_seconds,_nanoseconds} 로 준다.
dynamic _hydrate(dynamic v) {
  if (v is Map) {
    final m = Map<String, dynamic>.from(v);
    if (m.containsKey('_seconds')) {
      return Timestamp((m['_seconds'] as num).toInt(),
          (m['_nanoseconds'] as num? ?? 0).toInt());
    }
    return m.map((k, x) => MapEntry(k, _hydrate(x)));
  }
  if (v is List) return v.map(_hydrate).toList();
  return v;
}

List<ApplicationModel> _parse(List rows) => rows
    .cast<Map<String, dynamic>>()
    .map((m) {
      final raw = Map<String, dynamic>.from(
          (_hydrate(m) as Map).cast<String, dynamic>());
      final id = raw.remove('id') as String? ?? '';
      return ApplicationModel.tryFromMap(raw, id);
    })
    .whereType<ApplicationModel>()
    .toList();

/// `loadTOWorkDetails.countsAsSeat` 와 같은 판정 — 식을 복제하지 않고
///   production getter 들을 그대로 부른다.
bool _countsAsSeat(ApplicationModel a, DateTime day) =>
    const {'PENDING', 'CONFIRMED', 'CONTRACT_PENDING'}.contains(a.status) &&
    !a.isStaffingReleased &&
    a.occupiesSeatOn(day);

void main() {
  final data = _load();
  final slots = data['slots'] as Map<String, dynamic>;

  group('[RT-A] 배포된 DTO 가 파서 계약을 지킨다', () {
    test('RT-1 10/12 응답 1건이 **하나도 버려지지 않는다**', () {
      final s = slots['2026-10-12'] as Map<String, dynamic>;
      expect(s['http'], 200);
      final rows = s['applications'] as List;
      expect(rows.length, 1, reason: '원장에 확정 1건이 있다');
      expect(_parse(rows).length, rows.length,
          reason: '파싱 누락이 있으면 확정자가 화면에서 사라진다');
    });

    test('RT-2 응답에 appliedAt 이 들어 있다 — 이번 배포의 핵심', () {
      final rows = (slots['2026-10-12'] as Map)['applications'] as List;
      expect((rows.first as Map).containsKey('appliedAt'), isTrue);
    });

    test('RT-3 사람을 식별하는 값은 여전히 오지 않는다', () {
      final keys = ((slots['2026-10-12'] as Map)['applications'] as List)
          .cast<Map>()
          .expand((m) => m.keys.cast<String>())
          .toSet();
      for (final banned in [
        'uid', 'workerId', 'userName', 'name', 'phone',
        'wage', 'snapshotWage', 'trustScore', 'idCardConsentGiven',
      ]) {
        expect(keys, isNot(contains(banned)), reason: '최소 노출 계약 위반: $banned');
      }
    });
  });

  group('[RT-B] 좌석 판정 — 확정 1 은 1, 정상 0 은 0', () {
    test('RT-4 10/12 는 좌석 1 개를 차지한다', () {
      final apps = _parse((slots['2026-10-12'] as Map)['applications'] as List);
      final seated = apps.where((a) => _countsAsSeat(a, DateTime.now())).toList();
      expect(seated.length, 1);
      final a = seated.single;
      expect(a.status, 'CONTRACT_PENDING');
      expect(a.isStaffingReleased, isFalse);
      expect(a.wdId, 'UBxR73VI78Z6MSkSd04Z',
          reason: '집계 키가 원장 workDetailCounts 와 같아야 만난다');
      expect(AppStatus.confirmedStatuses.contains(a.status), isTrue,
          reason: '확정으로 세어야 한다');
    });

    test('RT-5 10/13 은 **정상 0** 이다 — 파싱 실패가 아니다', () {
      final s = slots['2026-10-13'] as Map<String, dynamic>;
      expect(s['http'], 200);
      final rows = s['applications'] as List;
      expect(rows, isEmpty);
      expect(_parse(rows).length, rows.length,
          reason: '버려진 것이 없으므로 0 을 그대로 말해도 된다');
    });

    test('RT-6 업무별로 모으면 원장과 같다', () {
      final apps = _parse((slots['2026-10-12'] as Map)['applications'] as List);
      final byWd = <String, int>{};
      for (final a in apps) {
        if (!_countsAsSeat(a, DateTime.now())) continue;
        if (!AppStatus.confirmedStatuses.contains(a.status)) continue;
        final key = (a.wdId != null && a.wdId!.isNotEmpty)
            ? a.wdId!
            : '${a.selectedWorkType}_${a.startTime}_${a.endTime}';
        byWd[key] = (byWd[key] ?? 0) + 1;
      }
      // 원장: workDetailCounts.UBxR73VI78Z6MSkSd04Z.confirmedCount = 1
      expect(byWd, {'UBxR73VI78Z6MSkSd04Z': 1});
    });
  });

  group('[RT-C] 권한 경계는 그대로다', () {
    test('RT-7 다른 사업장·무권한 사용자는 거부된다', () {
      final az = data['authz'] as Map<String, dynamic>;
      expect((az['otherBiz'] as Map)['status'], 'PERMISSION_DENIED');
      expect((az['worker'] as Map)['status'], 'PERMISSION_DENIED');
    });
  });
}
