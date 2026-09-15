// [HOME-V2-08D.3] Today operational group
//
// 3-column KPI(필요·확정·부족 / 현재 출근·근태 확인)를 폐기하고
//
//     8명 필요 · 5명 확정      ← 요약 (context, tap 없음)
//     ⚠ 3명 부족 · 평택센터 ›   ← 실제 문제
//     ⏱ 근태 확인 2건 ›
//     출근 4/5                ← 보조 정보
//
// 로 바꾼다.
//
// 이번 Phase의 핵심 계약:
//   · `부족 0` / `근태 확인 0`은 행 자체가 없다 — 0을 지면에 남기지 않는다
//   · 부족 위치는 shortageBusinesses에서만 온다 (_todayWorkSummary와 섞지 않는다)
//   · ERROR ≠ ZERO — 실패를 `0명 필요 · 0명 확정` / `출근 0/0`으로 쓰지 않는다
//   · 권한 없음 → issue row는 상태만, `당일 명단` CTA는 비노출

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/ui/staffing_readiness_model.dart';

const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) throw StateError('$signature 를 찾지 못함');
  var paren = 0;
  var afterParams = start;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    if (source[i] == '(') paren++;
    if (source[i] == ')') {
      paren--;
      if (paren == 0) {
        afterParams = i;
        break;
      }
    }
  }
  final open = source.indexOf('{', afterParams);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('$signature 본문의 끝을 찾지 못함');
}

// ═══════════════════════════════════════════════════════════════
// 화면 로직 replica — 구현과 같은 규칙
// ═══════════════════════════════════════════════════════════════

/// `_buildTodayStaffingSummary`의 문장 규칙.
/// null = 이 덩어리를 렌더하지 않음 (divider까지 함께 빠진다).
String? summaryText({
  required bool loading,
  required bool hasUsableData,
  required bool hasTodayTarget,
  required int required_,
  required int confirmed,
  required int shortage,
}) {
  if (loading) return '__spinner__';
  if (!hasUsableData) return '__error__';
  if (!hasTodayTarget) return null;
  final allStaffed = required_ > 0 && shortage == 0 && confirmed >= required_;
  return allStaffed
      ? '$required_명 전원 확정'
      : '$required_명 필요 · $confirmed명 확정';
}

/// `_buildTodayAttendanceLine`의 문장 규칙.
String attendanceText({
  required bool loading,
  required int? checkedIn,
  required int? dueNow,
}) {
  if (loading) return '__spinner__';
  if (checkedIn == null) return '__error__';
  final due = dueNow ?? 0;
  return due == 0 ? '출근 예정 전' : '출근 $checkedIn/$due';
}

/// [HOME-V2-08D.3.1] `_showTodaySection`의 판정 규칙.
///
/// 섹션의 존재 근거는 **오늘 운영 대상이 실재하는가** 하나뿐이다.
/// attendance 실패는 그 자체로 존재 근거가 아니다.
bool showToday({
  bool staffingLoading = false,
  bool attendanceLoading = false,
  bool hasUsableData = true,
  bool hasTodayTarget = false,
  bool? hasTodayRoster,
  bool attendanceFailed = false,
}) {
  if (staffingLoading || attendanceLoading) return true;
  if (!hasUsableData) return true;
  if (hasTodayTarget) return true;
  // 조회 실패면 로스터는 null — '없다'가 아니라 '모른다'
  return (attendanceFailed ? null : hasTodayRoster) == true;
}

class _IssueRow {
  final String label;
  final String kind; // 'shortage' | 'attendance'
  final bool actionable;
  const _IssueRow(this.kind, this.label, this.actionable);
}

/// `_buildTodayIssueRows`의 구성 규칙.
List<_IssueRow> issueRows({
  bool canSeeStaffing = true,
  bool canSeeAttendance = true,
  bool staffingLoading = false,
  bool attendanceLoading = false,
  StaffingDayData? day,
  bool multiBusiness = false,
  bool canManageTo = true,
  bool canManageWorkers = true,
  int? checkedIn = 0,
  int? needsAttention = 0,
}) {
  final rows = <_IssueRow>[];

  if (canSeeStaffing && !staffingLoading) {
    final shortage = day?.shortageCount ?? 0;
    if (day != null && shortage > 0) {
      final where = multiBusiness ? day.shortageLocationLabel() : null;
      rows.add(_IssueRow(
        'shortage',
        where == null ? '$shortage명 부족' : '$shortage명 부족 · $where',
        canManageTo,
      ));
    }
  }

  if (canSeeAttendance && !attendanceLoading && checkedIn != null) {
    final n = needsAttention ?? 0;
    if (n > 0) {
      rows.add(_IssueRow('attendance', '근태 확인 $n건', canManageWorkers));
    }
  }

  return rows;
}

StaffingBizData _biz(String name, int shortage,
        {int required_ = 0, int confirmed = 0}) =>
    StaffingBizData(
      businessId: 'biz_$name',
      businessName: name,
      requiredCount: required_,
      confirmedCount: confirmed,
      shortageCount: shortage,
      pendingCount: 0,
    );

StaffingDayData _day({
  int required_ = 0,
  int confirmed = 0,
  int shortage = 0,
  List<StaffingBizData> byBusiness = const [],
}) =>
    StaffingDayData(
      date: '2026-09-15',
      requiredCount: required_,
      confirmedCount: confirmed,
      shortageCount: shortage,
      pendingCount: 0,
      byBusiness: byBusiness,
    );

void main() {
  final home = _src(_homePath);
  final homeCode = _codeOf(home);
  final todayOps = _bodyOf(home, 'Widget _buildTodayOps(');
  final todayOpsCode = _codeOf(todayOps);
  final summaryBody = _bodyOf(home, 'Widget? _buildTodayStaffingSummary(');
  final issueBody = _bodyOf(home, 'List<Widget> _buildTodayIssueRows(');
  final attendanceBody = _bodyOf(home, 'Widget? _buildTodayAttendanceLine(');
  final issueRowBody = _bodyOf(home, 'Widget _todayIssueRow(');

  // ═══════════════════════════════════════════════════════════════
  // 01. state matrix — §37
  // ═══════════════════════════════════════════════════════════════
  group('[08D.3-01] Today state matrix', () {
    test('01-a normal: 전원 확정 + 출근 6/6, issue row 없음', () {
      expect(
        summaryText(
            loading: false,
            hasUsableData: true,
            hasTodayTarget: true,
            required_: 8,
            confirmed: 8,
            shortage: 0),
        '8명 전원 확정',
      );
      expect(
        attendanceText(loading: false, checkedIn: 6, dueNow: 6),
        '출근 6/6',
      );
      expect(
        issueRows(day: _day(required_: 8, confirmed: 8), needsAttention: 0),
        isEmpty,
      );
    });

    test('01-b normal에서 `부족 0` / `근태 확인 0` 문자열이 만들어지지 않는다', () {
      final rows =
          issueRows(day: _day(required_: 8, confirmed: 8), needsAttention: 0);
      expect(rows.any((r) => r.label.contains('부족')), isFalse);
      expect(rows.any((r) => r.label.contains('근태 확인')), isFalse);
    });

    test('01-c shortage: 요약은 필요·확정, 문제는 별도 행', () {
      expect(
        summaryText(
            loading: false,
            hasUsableData: true,
            hasTodayTarget: true,
            required_: 8,
            confirmed: 5,
            shortage: 3),
        '8명 필요 · 5명 확정',
      );
      final rows = issueRows(
        day: _day(
            required_: 8,
            confirmed: 5,
            shortage: 3,
            byBusiness: [_biz('평택센터', 3)]),
        multiBusiness: true,
      );
      expect(rows.length, 1);
      expect(rows.single.label, '3명 부족 · 평택센터');
      expect(rows.single.kind, 'shortage');
    });

    test('01-d attendance: 전원 확정이어도 근태 확인 행은 뜬다', () {
      expect(
        summaryText(
            loading: false,
            hasUsableData: true,
            hasTodayTarget: true,
            required_: 8,
            confirmed: 8,
            shortage: 0),
        '8명 전원 확정',
      );
      final rows = issueRows(
        day: _day(required_: 8, confirmed: 8),
        checkedIn: 6,
        needsAttention: 2,
      );
      expect(rows.length, 1);
      expect(rows.single.label, '근태 확인 2건');
      expect(attendanceText(loading: false, checkedIn: 6, dueNow: 8), '출근 6/8');
    });

    test('01-e shortage + attendance: 두 행, 부족이 먼저', () {
      final rows = issueRows(
        day: _day(
            required_: 8,
            confirmed: 5,
            shortage: 3,
            byBusiness: [_biz('평택센터', 3)]),
        multiBusiness: true,
        checkedIn: 4,
        needsAttention: 2,
      );
      expect(rows.map((r) => r.kind).toList(), ['shortage', 'attendance']);
    });

    test('01-f before-start: `출근 0/0` 금지', () {
      final text = attendanceText(loading: false, checkedIn: 0, dueNow: 0);
      expect(text, '출근 예정 전');
      expect(text.contains('0/0'), isFalse);
    });

    test('01-g staffing error: zero summary 금지', () {
      final text = summaryText(
          loading: false,
          hasUsableData: false,
          hasTodayTarget: false,
          required_: 0,
          confirmed: 0,
          shortage: 0);
      expect(text, '__error__');
      expect(text, isNot(contains('0명 필요')));
    });

    test('01-h attendance error: zero attendance 금지', () {
      final text = attendanceText(loading: false, checkedIn: null, dueNow: null);
      expect(text, '__error__');
      expect(text, isNot(contains('0/0')));
    });

    test('01-i staffing 실패 중에는 부족 행을 주장하지 않는다', () {
      // day는 남아 있을 수 있지만 로딩 중이면 숫자를 말하지 않는다
      expect(
        issueRows(
            staffingLoading: true,
            day: _day(required_: 8, confirmed: 5, shortage: 3)),
        isEmpty,
      );
    });

    test('01-j attendance 조회 실패면 근태 확인 행이 없다 (ERROR≠ZERO)', () {
      expect(
        issueRows(day: _day(required_: 8, confirmed: 8), checkedIn: null),
        isEmpty,
      );
    });

    test('01-k required == 0은 `0명 전원 확정`이 되지 않는다', () {
      final text = summaryText(
          loading: false,
          hasUsableData: true,
          hasTodayTarget: true,
          required_: 0,
          confirmed: 0,
          shortage: 0);
      expect(text, isNot('0명 전원 확정'));
      expect(text, '0명 필요 · 0명 확정');
    });

    test('01-l hasTodayTarget == false면 요약 덩어리 자체가 없다', () {
      expect(
        summaryText(
            loading: false,
            hasUsableData: true,
            hasTodayTarget: false,
            required_: 0,
            confirmed: 0,
            shortage: 0),
        isNull,
      );
    });

    test('01-m shortage > 0이면 confirmed >= required여도 전원 확정이 아니다', () {
      // shortageCount는 per-wdId 합산 — required - confirmed와 다를 수 있다
      expect(
        summaryText(
            loading: false,
            hasUsableData: true,
            hasTodayTarget: true,
            required_: 8,
            confirmed: 8,
            shortage: 2),
        '8명 필요 · 8명 확정',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 02. shortage location — §11, §12, §13
  // ═══════════════════════════════════════════════════════════════
  group('[08D.3-02] shortage location source', () {
    test('02-a 부족 사업장 1곳 → 사업장명', () {
      final d = _day(shortage: 3, byBusiness: [_biz('평택센터', 3)]);
      expect(d.shortageLocationLabel(), '평택센터');
    });

    test('02-b 부족 사업장 여러 곳 → `외 N곳`을 반드시 붙인다', () {
      final d = _day(shortage: 5, byBusiness: [
        _biz('평택센터', 3),
        _biz('안성센터', 2),
      ]);
      expect(d.shortageLocationLabel(), '평택센터 외 1곳');
    });

    test('02-c 대표 사업장만 남겨 단일 사업장 문제처럼 보이지 않는다', () {
      final d = _day(shortage: 6, byBusiness: [
        _biz('평택센터', 3),
        _biz('안성센터', 2),
        _biz('오산센터', 1),
      ]);
      final label = d.shortageLocationLabel()!;
      expect(label, '평택센터 외 2곳');
      expect(label, isNot('평택센터'));
    });

    test('02-d 부족 없는 사업장은 위치에 들어가지 않는다', () {
      final d = _day(shortage: 3, byBusiness: [
        _biz('평택센터', 3),
        _biz('안성센터', 0),
      ]);
      expect(d.shortageLocationLabel(), '평택센터');
    });

    test('02-e byBusiness 미집계면 위치 없이 수치만', () {
      final d = _day(shortage: 3);
      expect(d.shortageLocationLabel(), isNull);
      final rows = issueRows(day: d, multiBusiness: true);
      expect(rows.single.label, '3명 부족');
    });

    test('02-f shortageScopeLabel과 목적이 다르다 — 숫자를 두 번 말하지 않는다', () {
      final d = _day(shortage: 5, byBusiness: [
        _biz('평택센터', 3),
        _biz('안성센터', 2),
      ]);
      expect(d.shortageScopeLabel(), contains('명'));
      expect(d.shortageLocationLabel(), isNot(contains('명')));
    });

    test('02-g issue row는 _todayWorkSummary를 쓰지 않는다', () {
      expect(_codeOf(issueBody).contains('_todayWorkSummary'), isFalse);
      expect(_codeOf(issueBody).contains('shortageLocationLabel'), isTrue);
    });

    test('02-h workType/time을 shortage row에 지어내지 않는다', () {
      final code = _codeOf(issueBody);
      expect(code.contains('_todayFirstStart'), isFalse);
      expect(code.contains('workType'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 03. permission — §6, §15, §18
  // ═══════════════════════════════════════════════════════════════
  group('[08D.3-03] permission', () {
    test('03-a canManageTo 없으면 부족 상태는 보이되 tap 없음', () {
      final rows = issueRows(
        day: _day(shortage: 3, byBusiness: [_biz('평택센터', 3)]),
        multiBusiness: true,
        canManageTo: false,
      );
      expect(rows.single.label, '3명 부족 · 평택센터');
      expect(rows.single.actionable, isFalse);
    });

    test('03-b canManageWorkers 없으면 근태 확인 상태는 보이되 tap 없음', () {
      final rows = issueRows(
        day: _day(required_: 8, confirmed: 8),
        needsAttention: 2,
        canManageWorkers: false,
      );
      expect(rows.single.label, '근태 확인 2건');
      expect(rows.single.actionable, isFalse);
    });

    test('03-c staffing을 볼 수 없으면 부족 행 자체가 없다', () {
      expect(
        issueRows(canSeeStaffing: false, day: _day(shortage: 3)),
        isEmpty,
      );
    });

    test('03-d attendance를 볼 수 없으면 근태 행 자체가 없다', () {
      expect(
        issueRows(canSeeAttendance: false, needsAttention: 2),
        isEmpty,
      );
    });

    test('03-e `당일 명단`은 canSeeAttendance일 때만 — disabled teaser 없음', () {
      final flat = _flat(_codeOf(todayOps));
      expect(flat, contains('canOpenRoster = canSeeAttendance'));
      expect(flat, contains("action: canOpenRoster ? '당일 명단' : null"));
      expect(flat, isNot(contains('disabled')));
    });

    test('03-f 기존 canSeeStaffing/canSeeAttendance 계약을 넓히지 않는다', () {
      final flat = _flat(_codeOf(todayOps));
      expect(flat, contains('canSeeAttendance = !isSub || up.can((p) => p.canManageWorkers)'));
      expect(flat, contains('canManageTo'));
    });

    test('03-g chevron은 onTap이 있을 때만 그려진다', () {
      final flat = _flat(_codeOf(issueRowBody));
      expect(flat, contains('if (onTap != null) Icon(Icons.chevron_right'));
      expect(flat, contains('onTap == null ? row : InkWell'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 04. destination — §5, §14, §17, §38
  // ═══════════════════════════════════════════════════════════════
  group('[08D.3-04] destination', () {
    test('04-a `당일 명단` → 기존 _openTodayAttendanceDialog', () {
      expect(_codeOf(todayOps), contains('_openTodayAttendanceDialog(context)'));
    });

    test('04-b 새 dialog/screen을 만들지 않는다', () {
      final code = _codeOf(todayOps) + _codeOf(issueBody);
      expect(code.contains('showDialog'), isFalse);
      expect(code.contains('Navigator.push'), isFalse);
    });

    test('04-c shortage issue → _navigateToDayApplicantsForDate(today)', () {
      expect(_codeOf(issueBody),
          contains('_navigateToDayApplicantsForDate(context, day)'));
    });

    test('04-d attendance issue → _openTodayAttendanceDialog', () {
      expect(_codeOf(issueBody), contains('_openTodayAttendanceDialog(context)'));
    });

    test('04-e 두 destination 모두 _safeNavigate + _requireApprovedBusiness 게이트', () {
      final flat = _flat(_codeOf(issueBody));
      expect(
        RegExp(r'_safeNavigate\(\(\) => _requireApprovedBusiness\(')
            .allMatches(flat)
            .length,
        2,
      );
      expect(
        _flat(_codeOf(todayOps)),
        contains('_safeNavigate(() => _requireApprovedBusiness('),
      );
    });

    test('04-f shortageBusinesses 우선 businessIds 계약 유지', () {
      final nav = _codeOf(_bodyOf(home, 'Future<void> _navigateToDayApplicantsForDate('));
      expect(nav, contains('day.shortageBusinesses'));
      expect(nav, contains('shortBizIds.isNotEmpty'));
    });

    test('04-g HOME-V2-07.1 freshness 계약이 그대로다', () {
      final dlg =
          _codeOf(_bodyOf(home, 'Future<void> _openTodayAttendanceDialog('));
      expect(dlg, contains('_loadTodayAttendance()'));
      expect(dlg, contains('_loadStaffingReadiness()'));
      expect(dlg, contains('AdminMutationOrigin.home'));
    });

    test('04-h 요약 줄과 출근 줄은 tap하지 않는다', () {
      for (final body in [summaryBody, attendanceBody]) {
        final code = _codeOf(body);
        expect(code.contains('onTap'), isFalse);
        expect(code.contains('InkWell'), isFalse);
        expect(code.contains('GestureDetector'), isFalse);
        expect(code.contains('chevron_right'), isFalse);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 05. visual structure — §39
  // ═══════════════════════════════════════════════════════════════
  group('[08D.3-05] visual structure', () {
    test('05-a 3-column KPI helper가 제거됐다', () {
      expect(home.contains('_opsMetric'), isFalse);
      expect(home.contains('_opsMetricDivider'), isFalse);
    });

    test('05-b 옛 KPI 라벨이 남아 있지 않다', () {
      expect(homeCode.contains("label: '필요'"), isFalse);
      expect(homeCode.contains("label: '확정'"), isFalse);
      expect(homeCode.contains("label: '부족'"), isFalse);
      expect(homeCode.contains("'현재 출근'"), isFalse);
    });

    test('05-c 18px w800 KPI typography가 Today에서 사라졌다', () {
      final flat = _flat(_codeOf(todayOps) +
          _codeOf(summaryBody) +
          _codeOf(issueBody) +
          _codeOf(attendanceBody) +
          _codeOf(issueRowBody));
      expect(flat.contains('FontWeight.w800'), isFalse);
      expect(flat.contains('fontSize: 18,'), isFalse);
    });

    test('05-d _todayIssueRow는 최소 책임만 갖는다', () {
      final code = _codeOf(issueRowBody);
      expect(code, contains('required IconData icon'));
      expect(code, contains('required String label'));
      expect(code, contains('required Color color'));
      expect(code, contains('VoidCallback? onTap'));
      // business logic 금지
      for (final token in [
        '_staffingReadiness',
        '_todayCheckedIn',
        'up.can',
        'shortage',
      ]) {
        expect(code.contains(token), isFalse, reason: '$token 은 row의 책임이 아니다');
      }
    });

    test('05-e 두 issue row는 같은 helper·같은 typography를 쓴다', () {
      expect(
        RegExp(r'_todayIssueRow\(s,').allMatches(issueBody).length,
        2,
      );
      final flat = _flat(_codeOf(issueRowBody));
      expect(flat, contains('fontSize: 15, fontWeight: FontWeight.w600'));
    });

    test('05-f semantic color만 다르다', () {
      final code = _codeOf(issueBody);
      expect(code, contains('color: AppColors.error'));
      expect(code, contains('color: AppColors.warning'));
    });

    test('05-g 요약·출근 줄은 13px secondary', () {
      for (final body in [summaryBody, attendanceBody]) {
        expect(
          _flat(_codeOf(body)),
          contains('fontSize: 13, color: AppColors.textSecondary'),
        );
      }
    });

    test('05-h 빈 issue slot을 만들지 않는다 — 덩어리 단위로 divider를 넣는다', () {
      final flat = _flat(_codeOf(todayOps));
      expect(flat, contains('if (issues.isNotEmpty)'));
      expect(flat, contains('if (i > 0)'));
      expect(flat, contains('blocks.isEmpty'));
    });

    test('05-i 08D.1 _groupSurface를 그대로 쓴다 — 새 surface 없음', () {
      expect(_codeOf(todayOps), contains('decoration: _groupSurface'));
      final flat = _flat(_codeOf(todayOps));
      expect(flat.contains('BoxShadow'), isFalse);
      expect(flat.contains('Color(0xFF'), isFalse);
    });

    test('05-j section title은 `오늘`', () {
      // [HOME-V2-08D.4] rename이 08D.4에서 이뤄졌다. 08D.3이 지키려던 것은
      //   "Today 재구성 Phase에서 rename까지 하지 않는다"였고, 지금은 그 rename Phase다.
      expect(_codeOf(todayOps), contains("_sectionHeader(context, s, '오늘',"));
      expect(homeCode.contains("'오늘 운영'"), isFalse);
    });

    test('05-k header action은 generic 문구가 아니다', () {
      final flat = _flat(_codeOf(todayOps));
      expect(flat.contains("'상세보기'"), isFalse);
      expect(flat.contains("'전체보기'"), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 06. error / partial / loading — §26, §27, §28, §32
  // ═══════════════════════════════════════════════════════════════
  group('[08D.3-06] error · partial · loading', () {
    test('06-a 영역별 error row가 보존됐다', () {
      final code = _codeOf(summaryBody) + _codeOf(attendanceBody);
      expect(code, contains("message: '인력 정보를 불러오지 못했습니다'"));
      expect(code, contains("message: '출근 현황을 불러오지 못했습니다'"));
      expect(
        RegExp(r'_todayOpsErrorRow\(s,').allMatches(code).length,
        2,
      );
    });

    test('06-b 각 error row는 자기 loader로 재시도한다', () {
      expect(_codeOf(summaryBody), contains('_loadStaffingReadiness()'));
      expect(_codeOf(attendanceBody), contains('_loadTodayAttendance()'));
    });

    test('06-c _partialStaffingNotice가 요약 아래에 남아 있다', () {
      expect(_codeOf(summaryBody), contains('_partialStaffingNotice(s)'));
    });

    test('06-d partial에서도 받은 수치는 표시한다', () {
      // partial은 error 분기에 걸리지 않는다 — hasUsableData가 true다
      expect(
        summaryText(
            loading: false,
            hasUsableData: true,
            hasTodayTarget: true,
            required_: 5,
            confirmed: 3,
            shortage: 2),
        '5명 필요 · 3명 확정',
      );
    });

    test('06-e scope label은 partial에서 숨는다 (기존 계약)', () {
      final scope = _codeOf(_bodyOf(home, 'String? _staffingScopeLabel()'));
      expect(scope, contains('partial == true'));
    });

    test('06-f Today skeleton을 새로 만들지 않는다 — 기존 spinner 유지', () {
      final code = _codeOf(summaryBody) + _codeOf(attendanceBody);
      expect(code, contains('CircularProgressIndicator'));
      expect(code.contains('_heroSkeleton'), isFalse);
      expect(code.contains('shimmer'), isFalse);
    });

    test('06-g 분모 semantics(_todayDueNow)를 재정의하지 않는다', () {
      expect(_codeOf(attendanceBody), contains('_todayDueNow'));
      final loader = _codeOf(_bodyOf(home, 'Future<void> _loadTodayAttendance('));
      expect(loader, contains('_todayDueNow'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 08. [08D.3.1] Today 존재 근거 — empty vs attendance error
  //
  //   실기기 regression:
  //     Hero       현재 등록된 공고가 없어요
  //     오늘 운영   출근 현황을 불러오지 못했습니다  재시도
  //
  //   출근 조회 실패가 섹션의 존재 이유가 되면서, 있지도 않은 오늘 운영의
  //   출근을 못 읽었다고 말하고 있었다.
  // ═══════════════════════════════════════════════════════════════
  group('[08D.3.1-08] Today 존재 근거', () {
    test('08-a noPosting + attendance 실패 → Today 숨김 (실기기 regression)', () {
      expect(
        showToday(hasTodayTarget: false, hasTodayRoster: null, attendanceFailed: true),
        isFalse,
      );
    });

    test('08-b draftOnly + attendance 실패 → Today 숨김', () {
      // attendance error가 lifecycle 상태를 오염시키지 않는다
      expect(
        showToday(hasTodayTarget: false, hasTodayRoster: null, attendanceFailed: true),
        isFalse,
      );
    });

    test('08-c future-only + attendance 실패 → Today 숨김', () {
      // 오늘 대상은 없고 D+1~D+7에만 있는 상태
      expect(
        showToday(hasTodayTarget: false, hasTodayRoster: null, attendanceFailed: true),
        isFalse,
      );
    });

    test('08-d 오늘 target 있음 + attendance 실패 → Today 표시', () {
      expect(
        showToday(hasTodayTarget: true, hasTodayRoster: null, attendanceFailed: true),
        isTrue,
        reason: '대상이 실재하면 그 대상의 출근 실패는 사용자에게 관련 있는 오류다',
      );
      // 그리고 그 실패는 `출근 0/0`이 아니라 에러 행으로 표현된다
      expect(attendanceText(loading: false, checkedIn: null, dueNow: null), '__error__');
    });

    test('08-e roster true + target false → Today 표시 (cross-source 안전망)', () {
      expect(
        showToday(hasTodayTarget: false, hasTodayRoster: true),
        isTrue,
        reason: 'FULL 교정 지연 등으로 두 값이 어긋나도 근무자는 실재한다',
      );
    });

    test('08-f target false + roster false → Today 숨김', () {
      expect(showToday(hasTodayTarget: false, hasTodayRoster: false), isFalse);
    });

    test('08-g target false + roster null(조회 실패) → Today 숨김', () {
      // null은 '로스터가 없다'가 아니라 '모른다'다.
      // 모르는 것을 근거로 존재하지 않는 operational surface를 만들지 않는다.
      expect(
        showToday(hasTodayTarget: false, hasTodayRoster: null, attendanceFailed: true),
        isFalse,
      );
    });

    test('08-h staffing 실패는 여전히 Today를 남긴다', () {
      expect(showToday(hasUsableData: false, hasTodayTarget: false), isTrue);
      expect(showToday(staffingLoading: true, hasTodayTarget: false), isTrue);
      expect(showToday(attendanceLoading: true, hasTodayTarget: false), isTrue);
    });

    test('08-i attendance 실패를 0으로 해석하지 않는다 (ERROR≠ZERO 불변)', () {
      final gate = _codeOf(_bodyOf(home, 'bool get _showTodaySection'));
      // 실패를 0/false로 바꿔치기하는 코드가 없다
      expect(gate.contains('?? 0'), isFalse);
      expect(gate.contains('?? false'), isFalse);
      // 렌더 쪽은 여전히 에러 행을 낸다
      expect(_codeOf(attendanceBody), contains("'출근 현황을 불러오지 못했습니다'"));
    });

    test('08-j _todayCheckedIn이 단독 존재 근거로 쓰이지 않는다', () {
      final gate = _codeOf(_bodyOf(home, 'bool get _showTodaySection'));
      expect(gate.contains('_todayCheckedIn'), isFalse);
      expect(gate, contains('sr.hasTodayTarget'));
      expect(gate, contains('_hasTodayRoster == true'));
    });

    test('08-k 공고 없음 + historical task → Hero + Task, Today 없음', () {
      // task truth는 posting lifecycle과도, attendance 실패와도 무관하다
      expect(
        showToday(hasTodayTarget: false, hasTodayRoster: null, attendanceFailed: true),
        isFalse,
      );
      final taskGate = _codeOf(_bodyOf(home, 'bool _showTaskSection('));
      expect(taskGate.contains('_todayCheckedIn'), isFalse);
      expect(taskGate.contains('hasTodayTarget'), isFalse);
      expect(taskGate, contains('if (hasRows) return true;'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 07. regression — §33, §34, §36, §40
  // ═══════════════════════════════════════════════════════════════
  group('[08D.3-07] regression', () {
    test('07-a section gate를 바꾸지 않았다', () {
      final gate = _codeOf(_bodyOf(home, 'bool get _showTodaySection'));
      expect(gate, contains('sr.hasTodayTarget'));
      expect(gate, contains('_hasTodayRoster'));
    });

    test('07-b Today 구조 변경이 empty section을 되살리지 않는다', () {
      expect(homeCode.contains('오늘 예정된 인력 운영이 없어요'), isFalse);
      expect(homeCode.contains('향후 7일 예정된 인력 운영이 없어요'), isFalse);
    });

    test('07-c Adaptive Hero가 그대로다', () {
      expect(home, contains('enum _HeroState'));
      expect(home, contains('Widget _buildAdaptiveHero('));
      expect(home, contains('_HeroState _heroStateOf('));
    });

    test('07-d Hero CTA를 추가하지 않았다', () {
      final hero = _bodyOf(home, 'Widget _buildAdaptiveHero(');
      expect(RegExp(r'ctaLabel:').allMatches(_codeOf(hero)).length, 4);
    });

    test('07-e upcoming gate를 건드리지 않았다', () {
      // [HOME-V2-08D.4] upcoming 재구성은 08D.4의 범위였다.
      //   08D.3이 지키려던 것 — Today Phase가 upcoming gate를 흔들지 않는다 — 는 그대로다.
      expect(home, contains('bool get _showUpcomingSection'));
      expect(_codeOf(_bodyOf(home, 'bool get _showUpcomingSection')),
          contains('d.requiredCount > 0'));
      expect(homeCode, contains("'다가오는 7일'"));
    });

    test('07-f Today가 새 read/callable/listener를 만들지 않는다', () {
      for (final body in [
        todayOpsCode,
        _codeOf(summaryBody),
        _codeOf(issueBody),
        _codeOf(attendanceBody),
        _codeOf(issueRowBody),
      ]) {
        for (final token in [
          'httpsCallable',
          '_firestoreService',
          'FirebaseFirestore',
          'snapshots(',
          'await ',
        ]) {
          expect(body.contains(token), isFalse,
              reason: '$token 은 Today 렌더 경로에 있으면 안 된다');
        }
      }
    });

    test('07-g loader 수가 그대로다', () {
      expect(RegExp(r'Future<void> _load\w+\(').allMatches(home).length, 5);
    });

    test('07-h FULL staffing / lifecycle signal 계약 유지', () {
      final model = _src('lib/models/ui/staffing_readiness_model.dart');
      expect(model, contains('publishedPostingCount'));
      expect(model, contains('hasDraftPosting'));
    });

    test('07-i task 영역을 건드리지 않았다', () {
      expect(home, contains('bool _showTaskSection('));
      expect(homeCode, contains("'처리할 일'"));
    });
  });
}
