// [DU1 후속21 §1.1] 소비 구현은 lib 한 곳(lib/screens/business_admin/dialogs/wage_day_candidate.dart)으로 옮겼다.
//   이 support 는 그것을 그대로 다시 내보낸다 — 후속20 시험(du1_candb_wire_consumer_test.dart CC-1~4)이 같은 lib 구현을 돈다.
//   두 벌로 유지하지 않는다. (후속20 원본 aff3f02c… 는 D:\AlFit-evidence\DU1\source-before\du21 에 보존)
export 'package:ALfit/screens/business_admin/dialogs/wage_day_candidate.dart'
    show CandidateLink, CandidateRow, CandidateWageDay, consumeCandidateWageDay;
