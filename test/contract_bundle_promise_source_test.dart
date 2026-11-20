// [SHORT-TERM-CONTRACT-PROMISE-CORRECTION] 번들 선택과 날짜별 약속의 **출처**.
//
//   감사(DATE-MODEL-AUDIT.1)에서 두 GAP 이 나왔다. 모델은 그대로 두고 출처만 고쳤다.
//
//   GAP-1 — 번들 탐색이 상태를 묻지 않았다.
//     `callableGetContractsByBiz` 에 `orderBy` 가 없어 문서 id 순으로 주고
//     auto-id 는 무작위다. 같은 키에 계약이 둘 이상이면(사업주 서명 뒤 날짜가
//     추가돼 쪼개진 경우) **아무거나** 왔고, 그게 서명된 쪽이면 이어붙일 수
//     있는 미서명 계약을 놓쳤다.
//
//   GAP-2 — 계약 슬롯의 **시간**이 마스터 TO 에서 왔다.
//     슬롯(날짜)은 자기 `workDetails` 를 갖고 날짜 하나만 바꿀 수 있다.
//     갈라지면 계약서에 그 날의 실제 시간이 아닌 값이 적힌다.
//     임금은 이미 지원서에서 가져오고 있었다 — 시간만 비대칭이었다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _svc() =>
    File('lib/services/contract_service.dart').readAsStringSync();
String _fn() => File('functions/src/index.ts').readAsStringSync();

/// 주석을 지운다 — 왜 바꿨는지 적은 문장에 옛 표현이 남아 있다.
String _codeOf(String raw) => raw
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 그룹 수집 시점에도 불리므로 expect 대신 예외로 실패시킨다.
String _sliceOf(String raw, String from, String to) {
  final i = raw.indexOf(from);
  if (i < 0) throw StateError('시작 표지를 찾지 못함: $from');
  final j = raw.indexOf(to, i + from.length);
  if (j < 0) throw StateError('끝 표지를 찾지 못함: $to');
  return raw.substring(i, j);
}

void main() {
  final svc = _svc();
  final svcCode = _codeOf(svc);
  final fn = _fn();

  // `callableGetContractsByBiz` 는 여러 곳에서 불린다 — **_findBundle 본문**만 본다.
  //   `_codeOf` 가 주석을 지우므로 끝 표지도 **코드**여야 한다.
  final findBundle = _sliceOf(svcCode,
      'Future<EmploymentContractModel?> _findBundle',
      'Future<EmploymentContractModel> _addSlot');

  group('CBP-1 — 번들 탐색은 "추가할 수 있는" 계약만 고른다', () {
    test('CBP-01 _findBundle 이 status 를 서버에 넘긴다', () {
      final slice = findBundle;
      expect(_flat(slice), contains("'status': 'pending_employer'"),
          reason: '상태를 묻지 않으면 서명된 계약이 후보로 올 수 있다');
      expect(_flat(slice), contains("'limit': 1"));
    });

    test('CBP-02 클라이언트가 받아 놓고 거르지 않는다', () {
      // 서버가 걸러야 한다 — limit 이 필터보다 먼저면 후보가 잘린다.
      final slice = findBundle;
      expect(slice.contains('.where((c) => c.status'), isFalse,
          reason: '클라이언트 필터링은 limit 뒤라 후보를 놓친다');
    });

    test('CBP-03 서버는 status 를 limit **앞**에서 적용한다', () {
      final cf = _sliceOf(fn, 'export const callableGetContractsByBiz',
          'export const ');
      final statusAt = cf.indexOf('q = q.where("status", "==", status)');
      final limitAt = cf.indexOf('q = q.limit(cap)');
      expect(statusAt, greaterThan(-1));
      expect(limitAt, greaterThan(-1));
      expect(statusAt, lessThan(limitAt),
          reason: 'limit 이 먼저면 필터가 의미를 잃는다');
    });

    test('CBP-04 pending_employer 가 서버 허용 목록에 있다', () {
      final cf = _sliceOf(fn, 'export const callableGetContractsByBiz',
          'export const ');
      expect(cf, contains('VALID_CONTRACT_STATUSES_SET'));
      expect(_flat(cf), contains('"pending_employer"'));
    });

    test('CBP-05 서명된 계약은 슬롯 추가 후보가 되지 않는다 (K-001 유지)', () {
      // 상태 가드는 그대로 둔다 — 서버 필터는 그 **앞단**을 정확히 할 뿐이다.
      expect(_flat(svcCode),
          contains('existing.status == ContractStatus.pendingEmployer'));
    });

    test('CBP-06 번들 identity 는 그대로다', () {
      final slice = findBundle;
      for (final k in ['businessId', 'toId', 'workDetailId', 'workerId']) {
        expect(_flat(slice), contains("'$k':"),
            reason: '번들 키가 바뀌면 다른 업무가 섞인다');
      }
      expect(_flat(slice), contains("'isLongTerm': false"));
    });
  });

  group('CBP-2 — 날짜별 약속의 출처는 그 날짜의 지원서다', () {
    test('CBP-10 슬롯 시간이 지원서에서 온다 (두 writer 모두)', () {
      // _addSlot
      final add = _sliceOf(svcCode, 'Future<EmploymentContractModel> _addSlot',
          'final contractRef =');
      expect(_flat(add), contains('_promisedTimes(application)'));
      expect(add.contains('startTime: workDetail.startTime'), isFalse,
          reason: '마스터 TO 시간이 다시 들어왔다');
      // _createNew
      final create = _sliceOf(svcCode, 'final slots = isLong', 'final ref =');
      expect(_flat(create), contains('_promisedTimes(application).start'));
      expect(_flat(create), contains('_promisedTimes(application).end'));
      expect(create.contains('startTime: workDetail.startTime'), isFalse);
    });

    test('CBP-11 빈 시간을 마스터 값으로 조용히 대체하지 않는다', () {
      final h = _sliceOf(svcCode, '_promisedTimes(ApplicationModel application)',
          'WorkDetailData _withPromisedWage');
      expect(_flat(h), contains('start.isEmpty || end.isEmpty'));
      expect(_flat(h), contains('throw StateError'));
      expect(h.contains('workDetail'), isFalse,
          reason: '여기서 마스터 값을 참조하면 폴백이 생긴다');
    });

    test('CBP-12 임금은 기존 정책 그대로 지원서 약속값이다', () {
      final w = _sliceOf(svcCode, 'WorkDetailData _withPromisedWage',
          'Future<EmploymentContractModel> saveEmployerSignature');
      expect(_flat(w), contains('application.wage'));
      expect(_flat(w), contains('promisedWage <= 0'));
      expect(_flat(w), contains('throw StateError'));
    });

    test('CBP-13 슬롯 스키마는 그대로다 (재설계 아님)', () {
      final model =
          File('lib/models/core/employment_contract_model.dart').readAsStringSync();
      final cls = _sliceOf(model, 'class ContractSlot {', 'String get wageTypeLabel');
      for (final f in ['applicationId', 'workDate', 'startTime', 'endTime',
        'wage', 'wageType']) {
        expect(cls, contains(f), reason: '$f 가 사라졌다');
      }
      // 이번 수정으로 필드를 늘리지 않았다.
      expect(cls.contains('breakMinutes'), isFalse,
          reason: '휴게시간은 정책 결정 전까지 추가하지 않는다');
    });
  });

  group('CBP-3 — 서버가 약속을 해상도한다 (출처 신뢰 근거)', () {
    test('CBP-20 지원은 **슬롯의** workDetails 에서 매칭된다', () {
      final apply = _sliceOf(fn, 'export const callableApplyToTO', 'export const ');
      expect(_flat(apply), contains('srvMatchWorkDetail('));
      expect(_flat(apply), contains('sd["workDetails"]'),
          reason: '마스터가 아니라 슬롯에서 찾아야 날짜별 조건이 산다');
    });

    test('CBP-21 지원서에 시간과 보상 snapshot 이 함께 저장된다', () {
      final apply = _sliceOf(fn, 'export const callableApplyToTO', 'export const ');
      expect(_flat(apply), contains('startTime, endTime,'));
      expect(_flat(apply), contains('...compensationSnapshot,'));
    });

    test('CBP-22 초대도 같은 snapshot 을 쓴다 (의미 일치)', () {
      expect(fn, contains('...buildCompensationSnapshot(inviteMatchedWD),'),
          reason: '초대와 직접지원이 다른 의미를 저장하면 출처를 믿을 수 없다');
    });

    test('CBP-23 휴게시간은 지원서 snapshot 에 **이미** 있다', () {
      // 정책 결정이 남았을 뿐, 복원 불가가 아니다.
      final b = _sliceOf(fn, 'export function buildCompensationSnapshot',
          '\n}\n');
      expect(_flat(b), contains('out.breakMinutes ='));
    });
  });
}
