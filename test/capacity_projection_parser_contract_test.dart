// [DSE-CAPACITY-PROJECTION] 정원 DTO 와 그것을 읽는 파서의 계약.
//
// ── 기기에서 본 것 (DEV `ZujrV62Z2ctTDtdVZy9y`, 10/12) ──────────────────
//   원장        slot.confirmedCount = 1
//               slot.workDetailCounts.UBxR73VI78Z6MSkSd04Z.confirmedCount = 1
//   날짜 칩     선택 전 `1/2` → 선택 후 **`0/2`**
//   업무 행     `확정 0 · 대기 0 · 미충원 1`
//
//   원인은 범위도 identity 도 아니었다. `callableGetApplicationsByBiz` 의
//   `purpose: capacity` projection 이 **파서가 구조적으로 요구하는 필드**를
//   빼고 보냈고, `ApplicationModel.tryFromMap` 이 null 을 돌려주자
//   `whereType<ApplicationModel>()` 이 그 지원서를 통째로 지웠다. 집계에는
//   seed 된 0 만 남는다 — 확정된 근로자가 화면에서 사라진 것이다.
//
//   그래서 이 파일은 **두 언어의 계약을 맞댄다.** Dart 파서가 필수로 선언한
//   필드를 모델 소스에서 뽑아, CF allowlist 가 그것을 전부 담고 있는지 본다.
//   어느 쪽이 바뀌어도 여기서 깨진다.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';

const _cfPath = 'functions/src/index.ts';
const _modelPath = 'lib/models/core/application_model.dart';
const _appFsPath = 'lib/services/firestore/application_firestore.dart';

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _slice(String src, String from, String to) {
  final a = src.indexOf(from);
  if (a == -1) throw StateError('$from 를 찾지 못함');
  final b = src.indexOf(to, a + from.length);
  if (b == -1) throw StateError('$to 를 찾지 못함');
  return src.substring(a, b + to.length);
}

/// `ApplicationModel.fromMap` 이 **없으면 throw** 하는 필드 이름들.
///
///   판정식을 복제하지 않는다 — production 소스에 적힌 그 문장에서 읽는다.
Set<String> _parserRequiredFields() {
  final src = _read(_modelPath);
  final re = RegExp(r"ArgumentError\('ApplicationModel: (\w+) 필드 누락");
  final names = re.allMatches(src).map((m) => m.group(1)!).toSet();
  if (names.isEmpty) {
    throw StateError('파서 필수 필드 선언을 찾지 못했다 — 표현이 바뀌었는가');
  }
  return names;
}

/// CF 의 정원 allowlist.
Set<String> _capacityAllowlist() {
  final slice = _slice(_read(_cfPath),
      'const CAPACITY_ALLOWED_FIELDS = new Set([', ']);');
  return RegExp(r'"(\w+)"')
      .allMatches(_codeOf(slice))
      .map((m) => m.group(1)!)
      .toSet();
}

/// CF allowlist 그대로 만든 정원 DTO — 실제 DEV 문서가 가진 값만 담는다.
Map<String, dynamic> _capacityDto({bool dropAppliedAt = false}) {
  final dto = <String, dynamic>{
    'businessId': 'qa_qamv2ef85p_biz',
    'toId': 'ZujrV62Z2ctTDtdVZy9y',
    'slotId': '7xWPBKHrY0UnRdBWp0Q9',
    'workDetailId': 'UBxR73VI78Z6MSkSd04Z',
    'wdId': 'UBxR73VI78Z6MSkSd04Z',
    'status': 'CONTRACT_PENDING',
    'type': 'short',
    'selectedWorkType': 'QA 분류',
    'startTime': '09:00',
    'endTime': '13:00',
    // KST 2026-10-12 00:00
    'workDate': Timestamp(1791730800, 0),
    'appliedAt': Timestamp(1791600000, 0),
  };
  if (dropAppliedAt) dto.remove('appliedAt');
  return dto;
}

void main() {
  group('[CPP-A] 서버 DTO 가 파서 계약을 지킨다', () {
    test('CPP-1 파서 필수 필드는 workDate·appliedAt 둘이다', () {
      expect(_parserRequiredFields(), {'workDate', 'appliedAt'},
          reason: '필수가 늘면 정원 DTO 도 같이 넓혀야 한다');
    });

    test('CPP-2 정원 allowlist 가 파서 필수 필드를 전부 담는다', () {
      final allow = _capacityAllowlist();
      for (final f in _parserRequiredFields()) {
        expect(allow, contains(f),
            reason: '정원 응답에 "$f" 가 없으면 지원서가 통째로 버려진다');
      }
    });

    test('CPP-3 그래도 사람을 식별하는 값은 넣지 않았다', () {
      final allow = _capacityAllowlist();
      for (final banned in [
        'uid', 'userName', 'name', 'phone', 'wage', 'snapshotWage',
        'idCardConsentGiven', 'trustScore', 'bankName', 'accountNumber',
      ]) {
        expect(allow, isNot(contains(banned)),
            reason: '정원 계산에 필요 없는 값을 내보낸다: $banned');
      }
    });

    test('CPP-4 좌석 판정에 쓰는 값은 그대로 남아 있다', () {
      final allow = _capacityAllowlist();
      for (final need in [
        'status', 'wdId', 'workDetailId', 'slotId',
        'staffingReleasedAt', 'workEndDate', 'actualResignDate',
      ]) {
        expect(allow, contains(need), reason: '정원 계산이 깨진다: $need');
      }
    });
  });

  group('[CPP-B] production 파서로 실제 DTO 를 읽는다', () {
    test('CPP-5 현재 DTO 는 파싱된다 — 확정 1 명이 살아남는다', () {
      final a = ApplicationModel.tryFromMap(_capacityDto(), 'app1');
      expect(a, isNotNull, reason: '파싱되지 않으면 확정자가 사라진다');
      expect(AppStatus.confirmedStatuses.contains(a!.status), isTrue,
          reason: 'CONTRACT_PENDING 은 좌석을 차지한 확정이다');
      expect(a.isStaffingReleased, isFalse);
      expect(a.occupiesSeatOn(DateTime.now()), isTrue);
      expect(a.wdId, 'UBxR73VI78Z6MSkSd04Z',
          reason: '집계 키가 원장(workDetailCounts)과 같아야 만난다');
    });

    test('CPP-6 appliedAt 을 빼면 다시 사라진다 — 이것이 그 버그였다', () {
      expect(ApplicationModel.tryFromMap(_capacityDto(dropAppliedAt: true),
              'app1'),
          isNull);
    });

    test('CPP-7 10/13 처럼 지원서가 없는 날짜는 **정상 0** 이다', () {
      // 서버가 0 건을 주는 것과 파싱이 실패하는 것은 다르다.
      //   전자는 그대로 0 이고, 후자는 아래 CPP-8 이 막는다.
      const rows = <Map<String, dynamic>>[];
      final parsed = rows
          .map((m) => ApplicationModel.tryFromMap(m, 'x'))
          .whereType<ApplicationModel>()
          .toList();
      expect(parsed.length, rows.length,
          reason: '버려진 것이 없으므로 0 을 그대로 말해도 된다');
    });
  });

  group('[CPP-C] 못 읽은 것을 0 으로 말하지 않는다', () {
    final code = _codeOf(_read(_appFsPath));

    test('CPP-8 정원 조회는 파싱 누락을 던진다', () {
      expect(code.contains('purpose == FirestoreService.purposeCapacity &&'),
          isTrue);
      expect(code.contains('parsed.length != rawRows.length'), isTrue,
          reason: '버려진 건수를 세지 않으면 소비자는 차이를 알 수 없다');
      expect(code.contains('정원 조회 파싱 누락'), isTrue);
    });

    test('CPP-9 다른 목적의 동작은 바꾸지 않았다', () {
      // 던지는 조건이 capacity 로 한정돼 있다.
      final guard = _slice(code, 'if (purpose == FirestoreService.purposeCapacity', ');');
      expect(guard.contains('purposeApplicantReview'), isFalse);
      expect(guard.contains('purposeWorkerOperation'), isFalse);
    });

    test('CPP-10 소비자는 실패를 모름/차단으로 다룬다 — 0 으로 쓰지 않는다', () {
      // 업무별 집계: statsFailed 로 올려 `모름 + 다시 시도` 를 그린다.
      final fs = _codeOf(_read('lib/services/firestore_service.dart'));
      expect(fs.contains('statsFailed = true'), isTrue);
      // 공고 삭제 전 확인: fail-closed (삭제 차단).
      final toFs = _codeOf(_read('lib/services/firestore/to_firestore.dart'));
      expect(toFs.contains("'hasApplicants': true"), isTrue,
          reason: '조회 실패 시 삭제를 막는 기존 계약');
    });
  });
}
