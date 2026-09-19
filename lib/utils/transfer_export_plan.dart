// lib/utils/transfer_export_plan.dart
//
// [PII-DOC-R0.1] 은행 이체 목록을 만들기 전에 **무엇이 나가고 무엇이 왜 빠지는지**
// 먼저 정한다.
//
// 이전 구조는 이랬다:
//
//   계좌 정보 없음  → continue
//   금액 0 이하     → continue
//   조회 실패       → 토스트 한 번, 파일에는 흔적 없음
//
// 세 개의 서로 다른 사실이 전부 "행 없음"으로 붕괴했다. 그래서 103명을
// 이체하려고 눌렀는데 100행짜리 파일이 나오고, 그 차이를 파일만 보고는
// 알 수 없었다. PARTIAL을 SUCCESS처럼 보여준 것이다.
//
// 그리고 더 나쁜 것: 계좌 출처가 `users/{uid}`의 **현재 프로필**이었다.
// 급여 확정은 그 시점 계좌를 attendance에 스냅샷하고, 이체 CF는 그 스냅샷의
// 4필드 완전성을 검사한다. 그런데 관리자가 실제로 은행에 올리는 파일만
// 그 경로를 지나지 않았다. 검증이 우회된 게 아니라 애초에 그 자리에 없었다.
//
//   [INV-2] 급여 확정 시 확정된 계좌
//           = 이체 완료 CF가 쓰는 계좌
//           = 은행 업로드용 Excel이 쓰는 계좌
//
// 여기서 그 세 번째를 첫 번째에 맞춘다.

import 'package:flutter/foundation.dart';

import '../models/core/attendance_model.dart';

/// 이 급여 건이 이체 목록에 들어가지 못하는 이유.
///
/// 이유마다 운영자가 해야 할 일이 다르다 — 그래서 하나로 합치지 않는다.
enum TransferBlockReason {
  /// 사업장의 계좌 검토가 낡아 서버가 스냅샷을 만들지 않았다.
  /// (`wageAccountReviewRequired == true`)
  reviewRequired,

  /// V3 경로로 마감됐는데 스냅샷 4필드가 완전하지 않다.
  /// 확정 시점에 계좌가 등록돼 있지 않았던 경우가 대부분이다.
  noAccountSnapshot,

  /// 스냅샷 개념 이전(legacy)의 급여 건.
  ///
  /// 현재 프로필 계좌로 메우지 않는다 — 그건 "확정 시점 계좌"가 아니라
  /// "지금 계좌"이고, 둘을 같게 취급하는 순간 INV-2가 무너진다.
  legacyNoSnapshot,

  /// 지급액이 0원인데 그 이유가 설명되지 않는다.
  /// 결근·무단결근 0원과 달리 여기서는 무엇이 맞는지 알 수 없다 — UNKNOWN ≠ EMPTY.
  zeroAmountUnexplained,

  /// 금액을 읽을 수 없다 (wageDetail 없음 / 음수).
  dataError,
}

/// 지급 대상 자체가 아닌 건 — 결근·무단결근 0원.
/// 오류가 아니므로 "확인 필요"와 섞지 않는다.
const String kNotApplicableLabel = '지급 대상 아님';

extension TransferBlockReasonLabel on TransferBlockReason {
  String get label => switch (this) {
        TransferBlockReason.reviewRequired => '급여계좌 확인 필요',
        TransferBlockReason.noAccountSnapshot => '확정 시점 계좌 기록 없음',
        TransferBlockReason.legacyNoSnapshot => '이전 방식 급여 — 계좌 기록 없음',
        TransferBlockReason.zeroAmountUnexplained => '지급액 0원 — 확인 필요',
        TransferBlockReason.dataError => '급여 데이터 오류',
      };

  /// 운영자가 다음에 할 일.
  String get action => switch (this) {
        TransferBlockReason.reviewRequired =>
          '지원자 상세에서 급여계좌를 다시 확인한 뒤 급여를 재확정해주세요.',
        TransferBlockReason.noAccountSnapshot =>
          '근로자의 급여계좌 등록 여부를 확인한 뒤 급여를 재확정해주세요.',
        TransferBlockReason.legacyNoSnapshot =>
          '급여 마감을 취소한 뒤 다시 확정하면 확정 시점 계좌가 기록됩니다.',
        TransferBlockReason.zeroAmountUnexplained =>
          '근태·급여 내역을 확인해주세요.',
        TransferBlockReason.dataError => '근태·급여 내역을 확인해주세요.',
      };
}

/// Excel 한 행 — 한 근로자의 **한 계좌**에 대한 합산.
///
/// 근로자 단위가 아니라 (근로자 × 계좌) 단위다. 9월 1일 급여가 계좌 A로,
/// 9월 10일 급여가 계좌 B로 스냅샷됐다면 두 번 이체해야 한다. 한 행으로
/// 합치면 둘 중 하나는 틀린 계좌로 나간다.
@immutable
class TransferExportRow {
  final String uid;
  final String workerName;
  final String bankName;
  final String accountNumber;
  final String accountHolder;
  final int netAmount;
  final String memo;
  final int recordCount;

  const TransferExportRow({
    required this.uid,
    required this.workerName,
    required this.bankName,
    required this.accountNumber,
    required this.accountHolder,
    required this.netAmount,
    required this.memo,
    required this.recordCount,
  });
}

/// Excel에 들어가지 못한 근로자 한 명 × 한 사유.
@immutable
class TransferBlockedEntry {
  final String uid;
  final String workerName;
  final TransferBlockReason reason;
  final int recordCount;

  /// 이 사유로 빠진 금액. 모르는 경우(dataError) null.
  final int? netAmount;

  const TransferBlockedEntry({
    required this.uid,
    required this.workerName,
    required this.reason,
    required this.recordCount,
    this.netAmount,
  });
}

/// 지급 대상이 아닌 근로자 한 명 — 결근·무단결근 0원.
@immutable
class TransferNotApplicableEntry {
  final String uid;
  final String workerName;
  final int recordCount;

  const TransferNotApplicableEntry({
    required this.uid,
    required this.workerName,
    required this.recordCount,
  });
}

/// 이체 목록 생성 계획 — 파일을 만들기 전에 이미 전부 결정돼 있다.
///
/// 불변식: `totalRecords == exportedRecords + blockedRecords + notApplicableRecords`
/// 이 셋의 합이 전체와 같지 않으면 어딘가에서 건이 조용히 사라진 것이다.
@immutable
class TransferExportPlan {
  final List<TransferExportRow> rows;
  final List<TransferBlockedEntry> blocked;
  final List<TransferNotApplicableEntry> notApplicable;

  final int totalRecords;
  final int exportedRecords;
  final int blockedRecords;
  final int notApplicableRecords;

  /// 전체 대상 근로자 수 (중복 제거).
  final int totalWorkers;

  const TransferExportPlan({
    required this.rows,
    required this.blocked,
    required this.notApplicable,
    required this.totalRecords,
    required this.exportedRecords,
    required this.blockedRecords,
    required this.notApplicableRecords,
    required this.totalWorkers,
  });

  int get exportedWorkers => rows.map((r) => r.uid).toSet().length;
  int get blockedWorkers => blocked.map((e) => e.uid).toSet().length;
  int get notApplicableWorkers => notApplicable.map((e) => e.uid).toSet().length;

  /// Excel에 실제로 찍히는 행 수. 화면이 말하는 숫자와 같아야 한다.
  int get rowCount => rows.length;

  int get exportedTotal =>
      rows.fold<int>(0, (a, r) => a + r.netAmount);

  /// 일부 건만 포함된 근로자 — 같은 사람이 '포함'과 '확인 필요' 양쪽에 있다.
  /// 이 값이 0이 아니면 근로자 수 합계가 전체와 다르게 보이는데, 버그가 아니다.
  int get partialWorkers {
    final exported = rows.map((r) => r.uid).toSet();
    final blockedSet = blocked.map((e) => e.uid).toSet();
    return exported.intersection(blockedSet).length;
  }

  bool get hasAnything => rows.isNotEmpty;

  /// 모든 건이 어느 한 갈래에 정확히 한 번씩 담겼는가.
  bool get isComplete =>
      totalRecords ==
          exportedRecords + blockedRecords + notApplicableRecords;
}

/// 한 급여 건의 판정 결과.
///
/// 테스트가 건별 판정을 직접 확인할 수 있도록 공개 타입으로 둔다.
@immutable
class TransferRecordVerdict {
  final TransferBlockReason? blocked;
  final bool notApplicable;
  final String? accountKey;
  final String? bankName;
  final String? accountNumber;
  final String? accountHolder;
  final int net;

  const TransferRecordVerdict({
    this.blocked,
    this.notApplicable = false,
    this.accountKey,
    this.bankName,
    this.accountNumber,
    this.accountHolder,
    this.net = 0,
  });
}

/// 급여 건 하나를 판정한다.
///
/// [decrypt]는 계좌번호 복호화 함수. 테스트에서 주입할 수 있도록 분리했다 —
/// `EncryptionHelper`는 `--dart-define` 키에 의존하므로 단위 테스트에서 쓸 수 없다.
TransferRecordVerdict classifyRecord(
  AttendanceModel r,
  String? Function(String) decrypt,
) {
  // 1. 지급 대상 자체가 아닌 건 — 서버 이체 CF와 같은 식.
  //    (callableMarkTransferredBatch: status NO_SHOW/absent && finalWage == 0)
  final status = r.status;
  final isNonWork = status == AttendanceModel.statusNoShow ||
      status == AttendanceModel.statusAbsent;
  if (isNonWork && (r.finalWage ?? 0) == 0) {
    return const TransferRecordVerdict(notApplicable: true);
  }

  // 2. 금액 — 모르는 것과 0원을 구분한다.
  final wd = r.wageDetail;
  if (wd == null) {
    return const TransferRecordVerdict(blocked: TransferBlockReason.dataError);
  }
  final net = wd.effectiveNetWage;
  if (net < 0) {
    return const TransferRecordVerdict(blocked: TransferBlockReason.dataError);
  }
  if (net == 0) {
    return const TransferRecordVerdict(
        blocked: TransferBlockReason.zeroAmountUnexplained);
  }

  // 3. 계좌 — 출처는 **오직** 확정 시점 스냅샷이다.
  //    현재 프로필로 메우지 않는다. [INV-2]
  if (r.wageAccountReviewRequired == true) {
    return TransferRecordVerdict(
        blocked: TransferBlockReason.reviewRequired, net: net);
  }
  if (r.wageAccountSnapshotVersion != 1) {
    return TransferRecordVerdict(
        blocked: TransferBlockReason.legacyNoSnapshot, net: net);
  }

  final bank = r.wageAccountBankName;
  final encrypted = r.wageAccountNumberEncrypted;
  final holder = r.wageAccountHolder;
  final snapshotAt = r.wageAccountSnapshotAt;
  // 서버 이체 invariant와 같은 4필드 — 한 곳이라도 비면 이체 불가다.
  if (bank == null || bank.isEmpty ||
      encrypted == null || encrypted.isEmpty ||
      holder == null || holder.isEmpty ||
      snapshotAt == null) {
    return TransferRecordVerdict(
        blocked: TransferBlockReason.noAccountSnapshot, net: net);
  }

  final plain = decrypt(encrypted);
  if (plain == null || plain.isEmpty) {
    return TransferRecordVerdict(blocked: TransferBlockReason.dataError, net: net);
  }

  return TransferRecordVerdict(
    accountKey: '$bank|$plain|$holder',
    bankName: bank,
    accountNumber: plain,
    accountHolder: holder,
    net: net,
  );
}

/// 이체 대상 급여 건들로부터 export 계획을 만든다.
///
/// [names]는 uid → 표시 이름. 없으면 `'이름 확인 불가'`로 남긴다 —
/// uid를 이름 칸에 넣으면 운영자가 그걸 사람 이름으로 읽는다.
///
/// [formatDate]는 memo의 근무일 표기.
TransferExportPlan buildTransferExportPlan({
  required List<AttendanceModel> records,
  required Map<String, String> names,
  required String? Function(String) decrypt,
  required String Function(DateTime) formatDate,
}) {
  String nameOf(String uid) {
    final n = names[uid];
    return (n != null && n.isNotEmpty) ? n : '이름 확인 불가';
  }

  // (uid, accountKey) → 포함 대상
  final readyGroups = <String, List<AttendanceModel>>{};
  final readyMeta = <String, TransferRecordVerdict>{};
  // (uid, reason) → 제외 대상
  final blockedGroups = <String, List<AttendanceModel>>{};
  final blockedNet = <String, int?>{};
  final naGroups = <String, List<AttendanceModel>>{};

  var exportedRecords = 0;
  var blockedRecords = 0;
  var naRecords = 0;

  for (final r in records) {
    final v = classifyRecord(r, decrypt);

    if (v.notApplicable) {
      (naGroups[r.userId] ??= []).add(r);
      naRecords++;
      continue;
    }
    if (v.blocked != null) {
      final key = '${r.userId}|${v.blocked!.name}';
      (blockedGroups[key] ??= []).add(r);
      // dataError는 금액을 모른다 — 0으로 적지 않는다.
      if (v.blocked == TransferBlockReason.dataError) {
        blockedNet[key] = null;
      } else {
        blockedNet[key] = (blockedNet[key] ?? 0) + v.net;
      }
      blockedRecords++;
      continue;
    }

    final key = '${r.userId}|${v.accountKey}';
    (readyGroups[key] ??= []).add(r);
    readyMeta[key] = v;
    exportedRecords++;
  }

  // ── 포함 행 ──────────────────────────────────────────────
  final rows = <TransferExportRow>[];
  for (final entry in readyGroups.entries) {
    final recs = entry.value;
    final v = readyMeta[entry.key]!;
    final uid = recs.first.userId;

    recs.sort((a, b) => a.workDate.compareTo(b.workDate));
    final range = recs.length == 1
        ? formatDate(recs.first.workDate)
        : '${formatDate(recs.first.workDate)}~${formatDate(recs.last.workDate)}';

    rows.add(TransferExportRow(
      uid: uid,
      workerName: nameOf(uid),
      bankName: v.bankName!,
      accountNumber: v.accountNumber!,
      accountHolder: v.accountHolder!,
      netAmount: recs.fold<int>(
          0, (a, r) => a + (r.wageDetail?.effectiveNetWage ?? 0)),
      memo: '${recs.first.businessName} 급여 $range',
      recordCount: recs.length,
    ));
  }
  rows.sort((a, b) {
    final c = a.workerName.compareTo(b.workerName);
    return c != 0 ? c : a.bankName.compareTo(b.bankName);
  });

  // ── 확인 필요 ────────────────────────────────────────────
  final blocked = <TransferBlockedEntry>[];
  for (final entry in blockedGroups.entries) {
    final recs = entry.value;
    final uid = recs.first.userId;
    final reasonName = entry.key.split('|').last;
    final reason = TransferBlockReason.values
        .firstWhere((e) => e.name == reasonName);
    blocked.add(TransferBlockedEntry(
      uid: uid,
      workerName: nameOf(uid),
      reason: reason,
      recordCount: recs.length,
      netAmount: blockedNet[entry.key],
    ));
  }
  blocked.sort((a, b) {
    final c = a.reason.index.compareTo(b.reason.index);
    return c != 0 ? c : a.workerName.compareTo(b.workerName);
  });

  // ── 지급 대상 아님 ───────────────────────────────────────
  final notApplicable = naGroups.entries
      .map((e) => TransferNotApplicableEntry(
            uid: e.key,
            workerName: nameOf(e.key),
            recordCount: e.value.length,
          ))
      .toList()
    ..sort((a, b) => a.workerName.compareTo(b.workerName));

  return TransferExportPlan(
    rows: rows,
    blocked: blocked,
    notApplicable: notApplicable,
    totalRecords: records.length,
    exportedRecords: exportedRecords,
    blockedRecords: blockedRecords,
    notApplicableRecords: naRecords,
    totalWorkers: records.map((r) => r.userId).toSet().length,
  );
}
