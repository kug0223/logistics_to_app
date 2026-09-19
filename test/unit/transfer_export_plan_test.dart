// test/unit/transfer_export_plan_test.dart
//
// [PII-DOC-R0.1] 이체 목록 판정 — PATCH B / PATCH C의 실질 검증.
//
//   B2: 확정 시점 스냅샷이 지급 계좌다. 현재 프로필은 이 계산에 들어오지 않는다.
//   B3: 제외는 조용히 일어나지 않는다. 모든 건이 한 갈래에 정확히 한 번 담긴다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/utils/transfer_export_plan.dart';

// 테스트용 복호화 — 'enc:' 접두사를 떼는 가짜 암호.
// EncryptionHelper는 --dart-define 키에 의존하므로 단위 테스트에서 쓸 수 없다.
String? fakeDecrypt(String s) => s.startsWith('enc:') ? s.substring(4) : null;

String fmt(DateTime d) => '${d.month}/${d.day}';

WageDetailModel _wage(int net) => WageDetailModel(
      wageType: 'hourly',
      baseWage: 10320,
      totalAmount: net,
      netWage: net,
    );

AttendanceModel att({
  required String id,
  required String uid,
  int net = 100000,
  String status = AttendanceModel.statusPresent,
  int? finalWage,
  WageDetailModel? wageDetail,
  // 스냅샷
  int? snapshotVersion = 1,
  String? bankName = '국민은행',
  String? encrypted = 'enc:110-1234-5678',
  String? holder = '김근로',
  DateTime? snapshotAt,
  bool noSnapshotAt = false,
  bool? reviewRequired,
  DateTime? workDate,
}) {
  return AttendanceModel(
    id: id,
    applicationId: 'app_$id',
    userId: uid,
    businessId: 'biz1',
    businessName: '위워커',
    workDate: workDate ?? DateTime(2026, 9, 1),
    workType: '사무업무',
    status: status,
    createdAt: DateTime(2026, 9, 1),
    wageStatus: 'confirmed',
    finalWage: finalWage ?? net,
    wageDetail: wageDetail ?? _wage(net),
    wageAccountBankName: bankName,
    wageAccountNumberEncrypted: encrypted,
    wageAccountHolder: holder,
    wageAccountSnapshotAt:
        noSnapshotAt ? null : (snapshotAt ?? DateTime(2026, 9, 2)),
    wageAccountSnapshotVersion: snapshotVersion,
    wageAccountReviewRequired: reviewRequired,
  );
}

TransferExportPlan planOf(List<AttendanceModel> recs,
        {Map<String, String>? names}) =>
    buildTransferExportPlan(
      records: recs,
      names: names ?? {'u1': '김근로', 'u2': '박근로', 'u3': '이근로'},
      decrypt: fakeDecrypt,
      formatDate: fmt,
    );

void main() {
  group('B2 — 지급 계좌 source of truth는 확정 시점 스냅샷이다', () {
    test('정상 스냅샷 1건 → 스냅샷 계좌 그대로 출력', () {
      final p = planOf([att(id: 'a1', uid: 'u1')]);

      expect(p.rowCount, 1);
      final r = p.rows.single;
      expect(r.bankName, '국민은행');
      expect(r.accountNumber, '110-1234-5678'); // 복호화된 스냅샷 값
      expect(r.accountHolder, '김근로');
      expect(r.netAmount, 100000);
    });

    test('Scenario A — 확정 후 계좌가 바뀌어도 스냅샷은 그대로다', () {
      // 9/01 확정: 계좌 A 스냅샷. 그 뒤 사용자가 계좌 B로 변경.
      // 현재 프로필은 이 함수에 **입력조차 되지 않는다** — 침투 경로가 없다.
      final a = att(
        id: 'a1', uid: 'u1',
        bankName: '국민은행', encrypted: 'enc:AAA-111', holder: '김근로',
      );
      final p = planOf([a]);

      expect(p.rows.single.bankName, '국민은행');
      expect(p.rows.single.accountNumber, 'AAA-111');
      expect(p.rows.single.accountHolder, '김근로');
    });

    test('예금주도 스냅샷 값을 쓴다 — 현재 이름으로 덮어쓰지 않는다', () {
      // names에는 현재 이름 '김개명'이 들어오지만 예금주 칸은 스냅샷 '김근로'다.
      final p = planOf(
        [att(id: 'a1', uid: 'u1', holder: '김근로')],
        names: {'u1': '김개명'},
      );
      expect(p.rows.single.workerName, '김개명');  // 표시 이름은 현재
      expect(p.rows.single.accountHolder, '김근로'); // 예금주는 확정 시점
    });

    test('확정 사이에 계좌가 바뀌면 계좌별로 행이 나뉜다', () {
      // 한 행으로 합치면 둘 중 하나는 틀린 계좌로 나간다.
      final p = planOf([
        att(id: 'a1', uid: 'u1', encrypted: 'enc:AAA-111',
            workDate: DateTime(2026, 9, 1)),
        att(id: 'a2', uid: 'u1', encrypted: 'enc:BBB-222',
            workDate: DateTime(2026, 9, 10)),
      ]);

      expect(p.rowCount, 2);
      expect(p.exportedWorkers, 1);
      expect(p.rows.map((r) => r.accountNumber).toSet(),
          {'AAA-111', 'BBB-222'});
      expect(p.exportedTotal, 200000);
    });

    test('같은 계좌 여러 건은 합산되고 근무일 범위가 메모에 남는다', () {
      final p = planOf([
        att(id: 'a2', uid: 'u1', workDate: DateTime(2026, 9, 10)),
        att(id: 'a1', uid: 'u1', workDate: DateTime(2026, 9, 1)),
      ]);

      expect(p.rowCount, 1);
      expect(p.rows.single.netAmount, 200000);
      expect(p.rows.single.recordCount, 2);
      expect(p.rows.single.memo, contains('9/1~9/10'));
    });
  });

  group('B3 — 제외는 조용히 일어나지 않는다', () {
    test('review required → 확인 필요, 금액 보존 (ERROR ≠ ZERO)', () {
      final p = planOf([
        att(id: 'a1', uid: 'u1', reviewRequired: true,
            bankName: null, encrypted: null, holder: null, noSnapshotAt: true),
      ]);

      expect(p.rowCount, 0);
      expect(p.blocked.single.reason, TransferBlockReason.reviewRequired);
      expect(p.blocked.single.netAmount, 100000); // 0으로 만들지 않는다
      expect(p.isComplete, isTrue);
    });

    test('V3인데 스냅샷 4필드 불완전 → noAccountSnapshot', () {
      for (final broken in [
        att(id: 'b1', uid: 'u1', bankName: null),
        att(id: 'b2', uid: 'u1', encrypted: null),
        att(id: 'b3', uid: 'u1', holder: null),
        att(id: 'b4', uid: 'u1', noSnapshotAt: true),
      ]) {
        final p = planOf([broken]);
        expect(p.rowCount, 0, reason: broken.id);
        expect(p.blocked.single.reason,
            TransferBlockReason.noAccountSnapshot, reason: broken.id);
      }
    });

    test('legacy(version 없음) → 현재 계좌로 메우지 않고 별도 사유로 분리', () {
      final p = planOf([att(id: 'a1', uid: 'u1', snapshotVersion: null)]);

      expect(p.rowCount, 0);
      expect(p.blocked.single.reason, TransferBlockReason.legacyNoSnapshot);
      expect(p.blocked.single.netAmount, 100000);
    });

    test('NO_SHOW/결근 0원 → 지급 대상 아님 (오류가 아니다)', () {
      final p = planOf([
        att(id: 'a1', uid: 'u1',
            status: AttendanceModel.statusNoShow, net: 0, finalWage: 0),
        att(id: 'a2', uid: 'u2',
            status: AttendanceModel.statusAbsent, net: 0, finalWage: 0),
      ]);

      expect(p.rowCount, 0);
      expect(p.blocked, isEmpty);
      expect(p.notApplicableRecords, 2);
      expect(p.notApplicableWorkers, 2);
    });

    test('설명되지 않는 0원 → 확인 필요 (UNKNOWN ≠ EMPTY)', () {
      // 정상 출근인데 0원. 결근 0원과 같은 칸에 넣지 않는다.
      final p = planOf([att(id: 'a1', uid: 'u1', net: 0, finalWage: 0)]);

      expect(p.notApplicableRecords, 0);
      expect(p.blocked.single.reason,
          TransferBlockReason.zeroAmountUnexplained);
    });

    test('wageDetail 없음 → dataError, 금액은 null(모름)', () {
      final r = AttendanceModel(
        id: 'a1', applicationId: 'app', userId: 'u1',
        businessId: 'biz1', businessName: '위워커',
        workDate: DateTime(2026, 9, 1), workType: '사무업무',
        status: AttendanceModel.statusPresent,
        createdAt: DateTime(2026, 9, 1),
        wageStatus: 'confirmed',
        wageAccountSnapshotVersion: 1,
      );
      final p = planOf([r]);

      expect(p.blocked.single.reason, TransferBlockReason.dataError);
      expect(p.blocked.single.netAmount, isNull); // 0으로 적지 않는다
    });

    test('복호화 실패 → dataError. 빈 계좌번호로 행을 만들지 않는다', () {
      final p = planOf([att(id: 'a1', uid: 'u1', encrypted: 'NOT_ENCRYPTED')]);

      expect(p.rowCount, 0);
      expect(p.blocked.single.reason, TransferBlockReason.dataError);
    });

    test('이름을 모르면 uid를 이름 칸에 넣지 않는다', () {
      final p = planOf([att(id: 'a1', uid: 'u9')], names: const {});
      expect(p.rows.single.workerName, '이름 확인 불가');
      expect(p.rows.single.workerName, isNot(contains('u9')));
    });
  });

  group('INV-3 — PARTIAL은 SUCCESS가 아니다', () {
    test('전체 = 포함 + 확인 필요 + 지급 대상 아님 (건 단위로 정확히)', () {
      final p = planOf([
        att(id: 'r1', uid: 'u1'),                                  // ready
        att(id: 'r2', uid: 'u2'),                                  // ready
        att(id: 'b1', uid: 'u3', snapshotVersion: null),           // legacy
        att(id: 'b2', uid: 'u3', reviewRequired: true,
            bankName: null, encrypted: null, holder: null, noSnapshotAt: true),
        att(id: 'n1', uid: 'u2',
            status: AttendanceModel.statusNoShow, net: 0, finalWage: 0),
      ]);

      expect(p.totalRecords, 5);
      expect(p.exportedRecords, 2);
      expect(p.blockedRecords, 2);
      expect(p.notApplicableRecords, 1);
      expect(p.isComplete, isTrue);
      // 화면이 말하는 행 수 == 엑셀 행 수
      expect(p.rowCount, p.rows.length);
      expect(p.rowCount, 2);
    });

    test('일부만 포함된 근로자는 양쪽에 나타나고 partialWorkers로 드러난다', () {
      final p = planOf([
        att(id: 'r1', uid: 'u1'),                        // 포함
        att(id: 'b1', uid: 'u1', snapshotVersion: null), // 확인 필요
      ]);

      expect(p.exportedWorkers, 1);
      expect(p.blockedWorkers, 1);
      expect(p.partialWorkers, 1); // 같은 사람 — 합계가 안 맞는 게 아니다
      expect(p.isComplete, isTrue);
    });

    test('같은 사람의 서로 다른 사유는 따로 보인다', () {
      final p = planOf([
        att(id: 'b1', uid: 'u1', snapshotVersion: null),
        att(id: 'b2', uid: 'u1', reviewRequired: true,
            bankName: null, encrypted: null, holder: null, noSnapshotAt: true),
      ]);

      expect(p.blocked.length, 2);
      expect(p.blocked.map((b) => b.reason).toSet(), {
        TransferBlockReason.legacyNoSnapshot,
        TransferBlockReason.reviewRequired,
      });
    });

    test('모든 사유가 운영자에게 할 일을 말한다', () {
      for (final r in TransferBlockReason.values) {
        expect(r.label, isNotEmpty);
        expect(r.action, isNotEmpty);
      }
    });

    test('대상이 없어도 빈 계획은 완전하다', () {
      final p = planOf(const []);
      expect(p.isComplete, isTrue);
      expect(p.hasAnything, isFalse);
      expect(p.totalWorkers, 0);
    });
  });
}
