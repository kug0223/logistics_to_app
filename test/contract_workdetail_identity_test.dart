// [R7-P1R.2] CONTRACT composite identity — writer invariant.
//
// R7-P1R.1에서 장기의 canonical identity를 composite로 확정했다.
//
//     CONTRACT canonical = toId × (workType_startTime_endTime)
//
// composite를 canonical로 쓰기로 한 이상, **writer가 그 유일성을 보장해야**
// 한다. 같은 키를 가진 두 행이 저장되면 지원·초대·확정·정원·계약 snapshot이
// 전부 그 키로 연결되므로 사람과 돈이 잘못 묶인다.
//
//     사무업무 06:00~08:00 시급 12,000 필요 2
//     사무업무 06:00~08:00 시급 15,000 필요 1
//
// identity는 같고 promise terms는 다르다 — 어떤 권한으로도 구분할 수 없다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/work_detail_data.dart';

const _cfPath = 'functions/src/index.ts';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String s) =>
    s.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// [name] 선언 이후 [chars]자.
String _after(String src, String name, int chars) {
  final i = src.indexOf(name);
  if (i < 0) throw StateError('$name 를 찾지 못함');
  return src.substring(i, (i + chars).clamp(0, src.length));
}

WorkDetailData _wd({
  String workType = '사무업무',
  String start = '06:00',
  String end = '08:00',
  int wage = 12000,
  int required = 2,
}) =>
    WorkDetailData(
      workType: workType,
      startTime: start,
      endTime: end,
      wage: wage,
      requiredCount: required,
    );

void main() {
  final cf = _codeOf(_src(_cfPath));

  // ══════════════════════════════════════════════════════════════
  // 01. key 형식 — 서버와 클라이언트가 같은 식을 쓴다
  // ══════════════════════════════════════════════════════════════
  group('01. composite key 형식', () {
    test('01-a 서버 helper가 WorkDetailData.id와 같은 식을 쓴다', () {
      final helper = _after(cf, 'function srvAssertUniqueWorkDetailIds(', 400);
      expect(helper.contains('workType'), true);
      expect(helper.contains('startTime'), true);
      expect(helper.contains('endTime'), true);
      // 클라이언트 쪽 canonical 식
      expect(_wd().id, '사무업무_06:00_08:00');
    });

    test('01-b 새 normalization을 만들지 않았다', () {
      final helper = _after(cf, 'function srvAssertUniqueWorkDetailIds(', 400);
      // trim/lowerCase/locale 같은 새 정책을 넣으면 저장된 값과 어긋난다.
      for (final banned in ['toLowerCase', 'trim()', 'normalize(']) {
        expect(helper.contains(banned), false, reason: banned);
      }
    });

    test('01-c identity에 promise terms를 넣지 않는다', () {
      final helper = _after(cf, 'function srvAssertUniqueWorkDetailIds(', 400);
      for (final banned in ['wage', 'requiredCount', 'breakMinutes', 'tax']) {
        expect(helper.contains(banned), false, reason: banned);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 02. 같은 helper가 create/update 양쪽에 걸린다
  // ══════════════════════════════════════════════════════════════
  group('02. writer invariant', () {
    test('02-a helper가 하나이고 create/update가 그것을 쓴다', () {
      expect(cf.contains('function srvAssertUniqueWorkDetailIds('), true);
      final create = _after(cf, 'export const callableCreateTO', 4000);
      expect(create.contains('srvAssertUniqueWorkDetailIds('), true);
      final update = _after(cf, 'export const callableUpdateTO', 6000);
      expect(update.contains('srvAssertUniqueWorkDetailIds('), true);
    });

    test('02-b update의 중복 검증이 역할 게이트 밖에 있다', () {
      // 이 검증은 `if (!isSuperAdmin && mutatesWorkDetails)` 안에 있었다.
      // 그 블록의 다른 검사들은 기존 지원자를 보호하는 **정책**이라 운영자가
      // 넘어설 수 있지만, composite 중복은 정책이 아니라 **키 계약**이다.
      final update = _after(cf, 'export const callableUpdateTO', 6000);
      final assertIdx = update.indexOf('srvAssertUniqueWorkDetailIds(');
      final gateIdx = update.indexOf('if (!isSuperAdmin && mutatesWorkDetails)');
      expect(assertIdx, greaterThan(-1));
      expect(gateIdx, greaterThan(-1));
      expect(assertIdx, lessThan(gateIdx),
          reason: '역할 게이트 안으로 들어가면 SUPER_ADMIN이 중복을 저장할 수 있다');
    });

    test('02-c 복사본이 남아 있지 않다', () {
      // 같은 규칙이 두 벌이면 한쪽만 고쳐질 수 있다.
      final inline =
          RegExp(r'newIdSet\.size !== newIds\.length').allMatches(cf).length;
      expect(inline, 0, reason: 'update 쪽 인라인 사본이 남아 있다');
    });

    test('02-d create의 호출이 어떤 역할 블록에도 들어 있지 않다', () {
      // 앞뒤 offset 비교는 무의미하다 — create에는 이 검증과 무관한
      // `role !== "SUPER_ADMIN"` 블록이 따로 있다(workType scope 검증).
      // 실제로 볼 것은 **중첩 깊이**다: 함수 본문 레벨(4칸)이면 어떤
      // 조건문 안에도 들어 있지 않다.
      final raw = _src(_cfPath);
      final line = raw
          .split('\n')
          .firstWhere((l) => l.contains('srvAssertUniqueWorkDetailIds(toWorkDetailsCreate)'));
      final indent = line.length - line.trimLeft().length;
      expect(indent, 4, reason: '더 깊으면 조건문 안에 있다는 뜻이다');
    });

    test('02-e update의 호출도 함수 본문 레벨이다', () {
      final raw = _src(_cfPath);
      final line = raw.split('\n').firstWhere((l) =>
          l.contains('srvAssertUniqueWorkDetailIds(updates.workDetails'));
      final indent = line.length - line.trimLeft().length;
      // `if (mutatesWorkDetails && ...) {` 한 겹 안이므로 6칸이다.
      expect(indent, 6);
      // 그 한 겹이 역할 조건이 아니라는 것을 확인한다.
      final update = _after(cf, 'export const callableUpdateTO', 6000);
      final i = update.indexOf('srvAssertUniqueWorkDetailIds(');
      final before = update.substring((i - 200).clamp(0, i), i);
      expect(before.contains('isSuperAdmin'), false);
      expect(before.contains('mutatesWorkDetails'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 03. 판정 — 같은 규칙을 순수 함수로 재현해 경계를 고정한다
  // ══════════════════════════════════════════════════════════════
  group('03. 중복 판정', () {
    // 서버 helper와 **같은 식**. 여기서 다른 식을 쓰면 테스트가 거짓이 된다.
    bool duplicated(List<WorkDetailData> wds) {
      final ids = wds.map((d) => d.id).toList();
      return ids.toSet().length != ids.length;
    }

    test('03-A 동일 composite · 같은 임금 → 중복', () {
      expect(duplicated([_wd(), _wd()]), true);
    });

    test('03-B 동일 composite · 다른 임금/정원 → 여전히 중복', () {
      // 이것이 이번 phase의 핵심 시나리오다. terms가 달라도 키는 같다.
      expect(
        duplicated([
          _wd(wage: 12000, required: 2),
          _wd(wage: 15000, required: 1),
        ]),
        true,
      );
    });

    test('03-C 같은 업무 · 다른 시간 → 허용', () {
      expect(
        duplicated([
          _wd(start: '06:00', end: '08:00'),
          _wd(start: '13:00', end: '18:00'),
        ]),
        false,
      );
    });

    test('03-D 다른 업무 · 같은 시간 → 허용', () {
      expect(
        duplicated([_wd(workType: '사무업무'), _wd(workType: '포장')]),
        false,
      );
    });

    test('03-E 끝 시간만 달라도 구분된다', () {
      expect(duplicated([_wd(end: '08:00'), _wd(end: '09:00')]), false);
    });

    test('03-F 단일 행은 언제나 허용', () {
      expect(duplicated([_wd()]), false);
      expect(duplicated([]), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 04. bypass writer
  // ══════════════════════════════════════════════════════════════
  group('04. 우회 writer', () {
    test('04-a 만료 트리거는 identity를 바꾸지 않는다', () {
      final i = cf.indexOf('closedReason: "TIME_EXPIRED"');
      expect(i, greaterThan(-1));
      // 행을 더하거나 workType/시간을 바꾸지 않는다 — spread + 두 필드뿐.
      final seg = cf.substring((i - 300).clamp(0, i), i + 100);
      expect(seg.contains('...wd'), true);
      expect(seg.contains('workType:'), false);
      expect(seg.contains('startTime:'), false);
    });

    test('04-b 클라이언트 배열 수정기는 identity를 바꾸지 않는다', () {
      final svc = _codeOf(_src('lib/services/firestore_service.dart'));
      expect(svc.contains('_updateWorkDetailInArray('), true);
      // 호출부 모두 closedAt/emergency만 건드린다.
      for (final u in const ['clearClosedAt: true', 'clearEmergency: true']) {
        expect(svc.contains(u), true, reason: u);
      }
      // updater가 workType/시간을 바꾸는 호출부가 없다.
      expect(svc.contains('updater: (d) => d.copyWith(workType:'), false);
      expect(svc.contains('updater: (d) => d.copyWith(startTime:'), false);
    });
  });
}
