// [R7-GOLDEN-PATH-DEV-E2E.1 §A] Dart 가 만드는 계약서 payload 가
// DEV 가 실제로 저장한 것과 같은 진실을 말하는가
//
// 직전 Phase 에서는 `contractData` 형태를 손으로 재현해 CF 를 호출했다.
// 그래서 "CF 는 통과했다" 는 증거였지만 "앱이 같은 것을 보낸다" 는 증거는
// 아니었다. 이 테스트는 **실제 production 직렬화 코드**
// (EmploymentContractModel / ContractSnapshot / ContractSlot /
//  ContractArticle 의 toMap)를 그대로 실행해, DEV 에 저장된 계약서 문서의
// 구조와 대조한다.
//
// 아래 기대값은 DEV 실측에서 뽑은 것이다 (R7-GOLDEN-PATH-DEV-E2E Step D 로
// 만들어진 employment_contracts 문서). 값이 아니라 **필드 소유권**을 고정한다 —
// 어느 필드를 클라이언트가 말하고 어느 필드를 서버가 정하는가.
//
// 고정하는 것
//   CPP-1  모델 직렬화 키 집합 (실제 toMap 실행)
//   CPP-2  클라이언트가 보내기 전에 지우는 필드 = 서버 권위 필드
//   CPP-3  보내는 payload 가 DEV 저장 문서의 클라이언트 소유 필드와 일치
//   CPP-4  snapshot 키 집합 — 지급일정 3필드는 서버가 덮어쓴다
//   CPP-5  slots / articles 직렬화
//   CPP-6  taxDeductionType 은 none 이면 보내지 않는다
//   CPP-7  중복 계약 방지의 두 겹 (클라이언트 재조회 + CF 트랜잭션 판정)
import 'dart:io';

import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';
import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

/// DEV `employment_contracts` 문서의 top-level 키 (실측).
const _devDocKeys = <String>{
  'applicationId', 'applicationIds', 'articles', 'businessId',
  'createdAt', 'employerSignatureHash', 'employerSignatureUrl',
  'employerSignedAt', 'isLongTerm', 'pdfHash', 'pdfUrl', 'slots',
  'snapshot', 'status', 'templateId', 'toId', 'updatedAt',
  'workDetailId', 'workerId', 'workerSignatureHash', 'workerSignatureUrl',
  'workerSignedAt',
};

/// 서버만이 정하는 필드 — 클라이언트가 보내도 CF 가 지운다.
const _serverOwned = <String>{
  'status',
  'employerSignatureUrl', 'employerSignatureHash', 'employerSignedAt',
  'workerSignatureUrl', 'workerSignatureHash', 'workerSignedAt',
  'pdfUrl', 'pdfHash',
  'createdAt', 'updatedAt',
};

/// DEV snapshot 키 (실측).
const _devSnapshotKeys = <String>{
  'baseHourlyWage', 'breakMinutes', 'businessAddress', 'businessName',
  'businessNumber', 'businessPhone', 'contractEnd', 'contractStart',
  'endTime', 'isLongTerm', 'ownerName', 'payScheduleDay', 'payScheduleTime',
  'payScheduleType', 'paymentMethod', 'startTime', 'wage', 'wagePaymentDay',
  'wageType', 'workDays', 'workPlace', 'workType', 'workerAddress',
  'workerBirthDate', 'workerName', 'workerPhone',
};

/// 지급일정은 지원서의 약속에서 온다 — CF 가 snapshot 에 주입한다.
const _payScheduleServerInjected = <String>{
  'payScheduleType', 'payScheduleDay', 'payScheduleTime',
};

ContractSnapshot _snapshot({String? payScheduleType, String? taxType}) =>
    ContractSnapshot(
      businessName: '사업장',
      businessNumber: '000-00-00000',
      businessAddress: '주소',
      businessPhone: '02-0000-0000',
      ownerName: '대표',
      workerName: '근로자',
      workerBirthDate: '1990-01-01',
      workerPhone: '010-0000-0000',
      workerAddress: null,
      workType: '업무',
      workPlace: '주소',
      isLongTerm: false,
      startTime: '14:00',
      endTime: '18:00',
      breakMinutes: 0,
      wage: 12000,
      wageType: 'hourly',
      paymentMethod: '계좌이체',
      payScheduleType: payScheduleType,
      taxDeductionType: taxType ?? InsuranceRateModel.typeNone,
    );

EmploymentContractModel _contract({ContractSnapshot? snap}) =>
    EmploymentContractModel(
      id: 'c1',
      applicationId: 'to1_slot1_wd1_u1',
      businessId: 'biz1',
      workerId: 'u1',
      isLongTerm: false,
      toId: 'to1',
      workDetailId: 'wd1',
      slots: const [
        ContractSlot(
          applicationId: 'to1_slot1_wd1_u1',
          workDate: '2026-10-07',
          startTime: '14:00',
          endTime: '18:00',
          wage: 12000,
          wageType: 'hourly',
        ),
      ],
      applicationIds: const ['to1_slot1_wd1_u1'],
      status: ContractStatus.pendingEmployer,
      snapshot: snap ?? _snapshot(),
      articles: const [ContractArticle(title: '제1조', content: '내용')],
      templateId: 'tpl1',
      createdAt: DateTime(2026, 10, 7, 14),
      isNewUnsaved: true,
    );

void main() {
  group('계약서 payload parity — 실제 Dart 직렬화', () {
    test('CPP-1 모델 toMap 키 집합', () {
      final m = _contract().toMap();
      expect(
        m.keys.toSet(),
        {
          'applicationId', 'businessId', 'workerId', 'isLongTerm', 'toId',
          'workDetailId', 'slots', 'applicationIds', 'status',
          'employerSignatureUrl', 'employerSignedAt',
          'workerSignatureUrl', 'workerSignedAt', 'pdfUrl',
          'snapshot', 'articles', 'templateId', 'createdAt', 'updatedAt',
        },
        reason: '직렬화 키가 늘거나 줄면 CF 계약이 바뀐다',
      );
    });

    test('CPP-2 클라이언트는 서버 권위 필드를 보내기 전에 지운다', () {
      // saveEmployerSignature 가 지우는 목록 — 소스에서 그대로 읽는다.
      final svc = _src('lib/services/contract_service.dart');
      final i = svc.indexOf("for (final key in ['employerSignatureUrl'");
      expect(i, greaterThan(0), reason: '제거 목록을 찾지 못했다');
      final open = svc.indexOf('[', i);
      final close = svc.indexOf(']', open);
      final removed = RegExp(r"'([A-Za-z]+)'")
          .allMatches(svc.substring(open, close))
          .map((m) => m.group(1)!)
          .toSet();
      expect(removed, {
        'employerSignatureUrl', 'employerSignatureHash', 'employerSignedAt',
        'createdAt', 'updatedAt',
      });
      // 지운 것은 모두 서버 소유여야 한다 — 클라이언트 소유 필드를 지우면
      // 계약 내용이 소실된다.
      expect(removed.difference(_serverOwned), isEmpty);
    });

    test('CPP-3 보내는 payload = DEV 문서의 클라이언트 소유 필드', () {
      final m = _contract().toMap();
      // 클라이언트가 지우는 5개
      for (final k in ['employerSignatureUrl', 'employerSignatureHash',
        'employerSignedAt', 'createdAt', 'updatedAt']) {
        m.remove(k);
      }
      // CF 가 추가로 지우는 것(status·worker 서명)을 빼면 남는 것이
      // 실제로 계약 내용으로 저장되는 집합이다.
      final sent = m.keys.toSet().difference(_serverOwned);
      final devClientOwned = _devDocKeys.difference(_serverOwned);
      expect(sent, devClientOwned,
          reason: 'Dart 가 말하는 계약 내용과 DEV 저장 내용이 어긋난다');
    });

    test('CPP-4 snapshot 키 — 지급일정 3필드는 서버가 넣는다', () {
      // Dart 는 payScheduleType 이 null 이면 넣지 않는다.
      final without = _snapshot().toMap().keys.toSet();
      expect(without.intersection(_payScheduleServerInjected), isEmpty,
          reason: 'null 지급일정을 보내지 않는다');
      expect(without.union(_payScheduleServerInjected), _devSnapshotKeys,
          reason: 'Dart 가 보내는 것 + 서버가 넣는 것 = DEV 저장 snapshot');

      // 값이 있으면 그 필드만 실린다.
      final withType = _snapshot(payScheduleType: 'next_day').toMap();
      expect(withType['payScheduleType'], 'next_day');
      expect(withType.containsKey('payScheduleDay'), isFalse);
    });

    test('CPP-5 slots / articles 직렬화', () {
      final m = _contract().toMap();
      final slot = (m['slots'] as List).first as Map<String, dynamic>;
      expect(slot.keys.toSet(),
          {'applicationId', 'workDate', 'startTime', 'endTime', 'wage',
            'wageType'});
      expect(slot['workDate'], '2026-10-07',
          reason: "슬롯 날짜는 'yyyy-MM-dd' 문자열이다");
      final art = (m['articles'] as List).first as Map<String, dynamic>;
      expect(art.keys.toSet(), {'title', 'content'});
    });

    test('CPP-6 taxDeductionType 은 none 이면 보내지 않는다', () {
      expect(_snapshot().toMap().containsKey('taxDeductionType'), isFalse);
      expect(
          _snapshot(taxType: InsuranceRateModel.typeFreelancer33).toMap()
              .containsKey('taxDeductionType'),
          isTrue);
    });

    test('CPP-7 중복 계약 방지는 두 겹이다', () {
      final svc = _src('lib/services/contract_service.dart');
      // 클라이언트: 생성 전 번들 재조회
      expect(svc.contains('final existing = await _findBundle('), isTrue,
          reason: '클라이언트 재조회가 1차 방어다');
      // 서버: 같은 지원서에 발송된 계약서가 있으면 거절 (트랜잭션 안에서 재판정)
      final cf = _src('functions/src/index.ts');
      expect(cf.contains('srvIssuedContractExists(dupAppId, dupBizId, tx)'),
          isTrue,
          reason: '서버 트랜잭션 판정이 최종 권위다');
    });
  });
}
