// [PRELAUNCH-LONGTERM-LIFECYCLE-INTEGRITY.2]
// 장기 계약 — 생성 · 양측 서명 · 약속 보존.
//
// DEV employment_contracts 17건은 **전부 단기**였다. 장기 계약서는 하나도
// 없었고, 그래서 장기의 기간·요일·약속이 서명본에 살아남는지는 코드로만
// 확인돼 있었다.
//
// 장기 계약은 단기와 저장 모양이 다르다:
//
//     단기   slots[].workDate 에 그 하루가 들어간다
//     장기   slots 는 비어 있고, 기간은 snapshot.contractStart/End 에 있다
//            workDays 가 있어야 실제 근무일이 복원된다
//            wdId 가 없다 — composite identity 가 canonical
//
// 그래서 단기 계약 테스트를 이름만 바꿔 쓸 수 없다. 여기서 보는 것은
// **장기에서만 성립하는 것들**이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/employment_contract_model.dart';

const _cfPath = 'functions/src/index.ts';
const _svcPath = 'lib/services/contract_service.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// 주석 줄을 지운 본문. 앵커는 주석이 아니라 **코드**여야 한다.
String _codeOf(String s) =>
    s.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _after(String src, String name, int chars) {
  final i = src.indexOf(name);
  if (i < 0) throw StateError('$name 를 찾지 못함');
  return src.substring(i, (i + chars).clamp(0, src.length));
}

/// Firestore 가 돌려주는 모양의 시각 — 모델이 이 형태를 직접 파싱한다.
Map<String, dynamic> _ts(int y, int m, int d) => {
      '_seconds': DateTime.utc(y, m, d).millisecondsSinceEpoch ~/ 1000,
      '_nanoseconds': 0,
    };

/// DEV 런타임이 실제로 만든 장기 계약 문서와 같은 모양.
Map<String, dynamic> _longTermContractDoc({
  String status = 'completed',
  List<dynamic> slots = const [],
  String? contractStart = '2026-09-20',
  String? contractEnd = '2026-10-20',
  List<String>? workDays = const ['월', '화', '수', '목', '금', '토', '일'],
  int wage = 13500,
}) =>
    {
      'applicationId': 'TO1_사무업무_worker1',
      'applicationIds': ['TO1_사무업무_worker1'],
      'businessId': 'biz1',
      'workerId': 'worker1',
      'isLongTerm': true,
      'toId': 'TO1',
      // 장기에는 wdId 가 없다 — composite 가 그 자리를 대신한다.
      'workDetailId': '사무업무_03:00_05:00',
      'slots': slots,
      'status': status,
      'employerSignatureUrl': 'https://example/emp.png',
      'employerSignedAt': _ts(2026, 9, 23),
      'workerSignatureUrl': 'https://example/wrk.png',
      'workerSignedAt': _ts(2026, 9, 23),
      'pdfUrl': 'https://example/contract.pdf',
      'pdfHash': 'a' * 64,
      'createdAt': _ts(2026, 9, 23),
      'snapshot': {
        'businessName': '위워커',
        'businessNumber': '123-45-67890',
        'businessAddress': '경기도 용인시',
        'ownerName': '김광석',
        'workerName': '김지현',
        'workType': '사무업무',
        'workPlace': '경기도 용인시',
        'isLongTerm': true,
        'contractStart': contractStart,
        'contractEnd': contractEnd,
        'workDays': workDays,
        'startTime': '03:00',
        'endTime': '05:00',
        'breakMinutes': 0,
        'wage': wage,
        'wageType': 'hourly',
        'paymentMethod': '계좌이체',
        'payScheduleType': 'same_day',
        'taxDeductionType': 'none',
      },
      'articles': const [],
    };

void main() {
  final cf = _codeOf(_src(_cfPath));
  final svc = _codeOf(_src(_svcPath));

  // ══════════════════════════════════════════════════════════════
  // 01. 장기 계약 문서 모양 — 기간이 살아남는가
  // ══════════════════════════════════════════════════════════════
  group('01. 장기 계약 snapshot', () {
    test('01-a 기간·요일이 그대로 복원된다', () {
      final c = EmploymentContractModel.tryFromMap(_longTermContractDoc(), 'c1');
      expect(c, isNotNull);
      expect(c!.isLongTerm, true);
      expect(c.snapshot.contractStart, '2026-09-20');
      expect(c.snapshot.contractEnd, '2026-10-20');
      expect(c.snapshot.workDays, ['월', '화', '수', '목', '금', '토', '일']);
    });

    test('01-b 장기에는 slots 가 비어 있다 — 그래도 파싱된다', () {
      // 단기라면 slots[0].workDate 가 근무일이다. 장기에 그것을 요구하면
      // 계약서가 통째로 버려진다.
      final c = EmploymentContractModel.tryFromMap(_longTermContractDoc(), 'c1');
      expect(c, isNotNull);
      expect(c!.slots, isEmpty);
    });

    test('01-c 기간이 slots 로 축약되면 요일을 복원할 수 없다 — 회귀 고정', () {
      // 단기 모양(하루)으로 저장된 장기 계약은 근무일을 말할 수 없다.
      final c = EmploymentContractModel.tryFromMap(
        _longTermContractDoc(
          slots: [
            {
              'applicationId': 'TO1_사무업무_worker1',
              'workDate': '2026-09-20',
              'startTime': '03:00',
              'endTime': '05:00',
              'wage': 13500,
              'wageType': 'hourly',
            }
          ],
          contractStart: null,
          contractEnd: null,
          workDays: null,
        ),
        'c1',
      );
      expect(c, isNotNull);
      expect(c!.slots.length, 1);
      // 기간이 사라졌다 — 이 상태를 정상으로 받아들이면 안 된다.
      expect(c.snapshot.contractEnd, isNull);
      expect(c.snapshot.workDays, isNull);
    });

    test('01-d 종료일 없는 장기 계약도 파싱은 된다 — 기간 미정', () {
      final c = EmploymentContractModel.tryFromMap(
          _longTermContractDoc(contractEnd: null), 'c1');
      expect(c, isNotNull);
      expect(c!.snapshot.contractStart, isNotNull);
      expect(c.snapshot.contractEnd, isNull);
    });

    test('01-e composite identity 가 workDetailId 자리에 온다', () {
      final c = EmploymentContractModel.tryFromMap(_longTermContractDoc(), 'c1');
      expect(c!.workDetailId, '사무업무_03:00_05:00');
      expect(c.workDetailId.contains('_'), true);
    });

    test('01-f 양측 서명 artifact 가 모두 참조된다', () {
      final c = EmploymentContractModel.tryFromMap(_longTermContractDoc(), 'c1');
      expect(c!.employerSignatureUrl, isNotNull);
      expect(c.workerSignatureUrl, isNotNull);
      expect(c.pdfUrl, isNotNull);
      expect(c.status, ContractStatus.completed);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 02. 약속 authority — 공고가 아니라 지원서에서 온다
  // ══════════════════════════════════════════════════════════════
  group('02. promise authority', () {
    test('02-a 임금은 지원 시점 약속을 쓴다', () {
      expect(svc.contains('WorkDetailData _withPromisedWage('), true);
      final w = _after(svc, 'WorkDetailData _withPromisedWage(', 1400);
      expect(w.contains('final promisedWage = application.wage;'), true);
      // 약속이 없으면 현재 모집 임금으로 덮지 않고 던진다.
      expect(w.contains('지원 시점 임금 정보가 없어 계약서를 만들 수 없습니다.'), true);
    });

    test('02-b 장기 기간은 지원서에서 온다', () {
      final s = _after(svc, 'ContractSnapshot _buildSnapshot(', 2500);
      expect(s.contains('contractStart: isLong'), true);
      expect(
        s.contains('_fmtDate(application.desiredStartDate ?? application.workDate)'),
        true,
      );
      expect(
        s.contains('contractEnd: isLong && application.workEndDate != null'),
        true,
      );
      expect(s.contains('_fmtDate(application.workEndDate)'), true);
      expect(s.contains('workDays: application.workDays'), true);
    });

    test('02-c 지급일정은 서버가 지원서 값으로 덮어쓴다', () {
      // 확정과 서명 사이에 공고가 바뀌면 계약서만 새 값을 갖게 된다.
      final e = _after(cf, 'export const callableFinalizeEmployerSignature', 9000);
      expect(e.contains('const ps = srvReadPaySchedule(appData as Record<string, unknown>);'),
          true);
      expect(e.contains('sn["payScheduleType"] = ps.t;'), true);
    });

    test('02-d 장기는 번들 탐색 없이 항상 새 계약서를 만든다', () {
      // slots 를 덧붙이는 경로는 단기 전용이다.
      final f = _after(svc, 'Future<EmploymentContractModel> findOrCreateContract(', 1600);
      expect(f.contains('if (!isLong) {'), true);
      expect(f.contains('return _addSlot(existing, application, workDetail);'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 03. 서명 lifecycle — 서버 계약
  // ══════════════════════════════════════════════════════════════
  group('03. 서명 lifecycle', () {
    final emp = _after(cf, 'export const callableFinalizeEmployerSignature', 9000);
    final wrk = _after(cf, 'export const callableFinalizeWorkerSignature', 9000);

    test('03-a 사업주 서명 → pending_worker', () {
      expect(emp.contains('status: "pending_worker",'), true);
      expect(emp.contains('employerSignedAt: admin.firestore.FieldValue.serverTimestamp()'),
          true);
    });

    test('03-b 사업주 서명만으로는 지원서를 CONFIRMED 로 바꾸지 않는다', () {
      // 확정은 양측 계약이 끝난 뒤다.
      expect(emp.contains('status: "CONFIRMED"'), false);
    });

    test('03-c 근로자 서명 → completed + 지원서 CONFIRMED', () {
      expect(wrk.contains('status: "completed",'), true);
      expect(wrk.contains('status: "CONFIRMED",'), true);
      expect(wrk.contains('action: "CONTRACT_SIGNED",'), true);
    });

    test('03-d 근로자 서명은 화이트리스트 상태에서만', () {
      expect(wrk.contains('if (status !== "pending_worker") {'), true);
    });

    test('03-e 본인 계약서만 서명할 수 있다 — TX 안에서도 확인', () {
      final n = RegExp(r'본인의 계약서만 서명할 수 있습니다').allMatches(wrk).length;
      expect(n, greaterThanOrEqualTo(2),
          reason: 'pre-read 와 트랜잭션 양쪽에 있어야 TOCTOU 가 막힌다');
    });

    test('03-f 사업주 서명이 없으면 근로자 서명이 막힌다', () {
      expect(wrk.contains('사업주 서명이 완료되지 않은 계약서입니다.'), true);
    });

    test('03-g pdfHash 는 서버가 계산한다', () {
      // 클라이언트가 보낸 해시를 믿으면 위조된 PDF 를 진본으로 기록한다.
      expect(wrk.contains('const pdfHash = crypto.createHash("sha256").update(pdfBytes).digest("hex");'),
          true);
      expect(wrk.contains('pdfHash: pdfHash,'), true);
    });

    test('03-h 지원서 상태 전이는 같은 사업장 것만', () {
      expect(wrk.contains('appData?.["businessId"] === contractBizId'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 04. 중복·권한
  // ══════════════════════════════════════════════════════════════
  group('04. 중복과 권한', () {
    final emp = _after(cf, 'export const callableFinalizeEmployerSignature', 9000);

    test('04-a 같은 지원서에 두 번째 계약서를 막는다 — TX 안에서도', () {
      final n = RegExp(r'srvIssuedContractExists\(').allMatches(emp).length;
      expect(n, greaterThanOrEqualTo(2),
          reason: 'pre-read 만으로는 동시 요청 둘 다 통과한다');
      expect(emp.contains('이미 계약서가 발송된 근무입니다.'), true);
    });

    test('04-b 계약 권한은 canManageContract 다', () {
      // 사업장 관리자이거나, SubAdmin 이면 이 capability 를 가져야 한다.
      expect(emp.contains('assertBizAdmin(callerUid, bizId)'), true);
      expect(emp.contains('memberPerms.canManageContract'), true);
      expect(emp.contains('계약서 관리 권한이 없습니다.'), true);
    });

    test('04-c 인가가 Storage 업로드보다 먼저다', () {
      // 순서가 뒤집히면 권한 없는 호출자가 남의 서명 이미지를 덮어쓴다.
      final auth = emp.indexOf('assertBizAdmin(callerUid, bizId)');
      final upload = emp.indexOf('_saveContractArtifact(');
      expect(auth, greaterThan(-1));
      expect(upload, greaterThan(-1));
      expect(auth, lessThan(upload));
    });

    test('04-d 실패한 시도는 자기 artifact 만 지운다', () {
      expect(emp.contains('_deleteOwnAttemptArtifact(sigUpload)'), true);
      expect(emp.contains('_newContractAttemptPrefix(contractId)'), true);
    });

    test('04-e 클라이언트가 보낸 서명 필드는 버린다', () {
      expect(emp.contains('"workerSignatureUrl", "workerSignatureHash", "workerSignedAt",'),
          true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 05. 좌석 — 계약 완료가 인원을 늘리지 않는다
  // ══════════════════════════════════════════════════════════════
  group('05. staffing seat', () {
    test('05-a 좌석 집합에 CONTRACT_PENDING 과 CONFIRMED 가 함께 있다', () {
      // 둘 중 하나만 세면 서명 순간 인원이 1 → 2 로 뛰거나 0 으로 떨어진다.
      expect(cf.contains('const CONFIRMED_STATUSES = ["CONFIRMED", "CONTRACT_PENDING"]') ||
          cf.contains('CONFIRMED_STATUSES = ["CONTRACT_PENDING", "CONFIRMED"]'), true,
          reason: 'canonical 좌석 집합');
    });

    test('05-b 하루 좌석 판정은 장기 resolver 하나를 쓴다', () {
      final seat = _after(cf, 'function srvContractConfirmedOnDay(', 700);
      expect(seat.contains('srvLongTermEligibleOnDay('), true);
      // 그 resolver 는 status 를 보지 않는다 — caller 가 이미 걸렀다.
      final r = _after(cf, 'function srvLongTermEligibleOnDay(', 2200);
      expect(r.contains('CONTRACT_PENDING'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 06. reader 도달성 — 장기라고 빠지지 않는다
  // ══════════════════════════════════════════════════════════════
  group('06. reader 도달성', () {
    test('06-a 계약 조회가 slotId 를 요구하지 않는다', () {
      // 장기에는 slot 이 없다. 그것을 조건으로 걸면 통째로 사라진다.
      final list = _after(cf, 'export const callableGetContractsByBiz', 4000);
      expect(list.contains('slotId'), false);
    });

    test('06-b isLongTerm 으로 장기를 걸러낼 수 있다', () {
      final list = _after(cf, 'export const callableGetContractsByBiz', 4000);
      expect(list.contains('q.where("isLongTerm", "==", isLongTerm)'), true);
    });

    test('06-c 지원서 연결이 두 축 모두로 조회된다', () {
      // 레거시(applicationId 단건)와 신규(applicationIds 배열).
      expect(cf.contains('.where("applicationId", "==", '), true);
      expect(cf.contains('.where("applicationIds", "array-contains", '), true);
    });
  });
}
