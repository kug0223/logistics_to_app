import '../models/core/application_model.dart';
import '../models/core/attendance_model.dart';
import 'format_helper.dart';

/// [NOSHOW-CONTRACT-GUARD] 노쇼·결근 단기 근무일에는 계약서를 권하지 않는다.
///
///   서버 `srvContractBlockedByAttendance`(발행 callable·미발송 목록·홈 숫자가 함께
///   쓰는 판정)와 **같은 규칙**이다. 화면이 다른 규칙을 쓰면 버튼은 뜨는데
///   누르면 서버가 거절한다(DEV 10-20: 지원자 명단 다이얼로그 두 곳이 그랬다).
///
///   근태는 그 지원서·그 근무일에 정확히 대응하는 문서 하나만 본다 —
///   `attendance/{appId}_{KST yyyyMMdd}` 이고 문서의 applicationId 가 같은 지원서일 때.
///     · 근태가 없는 지난 근무는 막지 않는다(사후 계약 가능).
///     · 장기 근무는 막지 않는다(하루 노쇼가 계약 전체를 없애지 않는다).
///     · 근태를 **읽지 못했으면** 단기 근무는 발행 가능하다고 말하지 않는다.
abstract class ContractAttendanceGate {
  static const Set<String> blockingStatuses = {
    AttendanceModel.statusNoShow,
    AttendanceModel.statusAbsent,
  };

  /// 서버와 같은 장기 판정 — `isLongTermApplication` 과 다르다(그쪽은 type=short 가 우선).
  static bool isLongTermForContract(ApplicationModel app) {
    final days = app.workDays ?? const <String>[];
    final end = app.workEndDate;
    return app.applicationType == AppType.longTerm ||
        days.isNotEmpty ||
        (end != null &&
            end.millisecondsSinceEpoch != app.workDate.millisecondsSinceEpoch);
  }

  /// 발행을 막을 수 있는 근태 문서 id — 단기일 때만.
  static String? attendanceDocId(ApplicationModel app) =>
      isLongTermForContract(app)
          ? null
          : '${app.id}_${FormatHelper.formatDateStamp(app.workDate)}';

  static bool blockedBy(ApplicationModel app, Iterable<AttendanceModel> atts) {
    final id = attendanceDocId(app);
    if (id == null) return false;
    return atts.any((a) =>
        a.id == id &&
        a.applicationId == app.id &&
        blockingStatuses.contains(a.status));
  }

  /// 근태를 읽었으면 막힌 지원서 id 집합, 읽지 못했으면 null(모름).
  static Set<String>? blockedIds(
    Iterable<ApplicationModel> apps,
    Iterable<AttendanceModel>? atts,
  ) {
    if (atts == null) return null;
    final list = atts.toList(growable: false);
    return {for (final a in apps) if (blockedBy(a, list)) a.id};
  }

  /// 근태 쪽에서 발행을 막지 않는가. 단기 근무인데 근태를 모르면 false.
  static bool clearForIssue(ApplicationModel app, Set<String>? blocked) {
    if (attendanceDocId(app) == null) return true;
    if (blocked == null) return false;
    return !blocked.contains(app.id);
  }
}
