// [HOME-V2-08D.4] 다가오는 7일 + task visual + section rename
//
// 이 Phase가 닫는 세 가지:
//
//  1. `다가오는 7일`은 shortage monitor가 아니다.
//     앞으로 7일 중 **어느 날에 근무가 있고 그 준비가 얼마나 됐는지**를 본다.
//     부족한 날만 보여주면 전원 확정된 날의 약속이 화면에서 사라진다.
//
//  2. 날짜 행은 부족 여부와 무관하게 같은 곳으로 간다.
//     `날짜를 누르면 그날 사람을 본다`에 예외를 만들지 않는다.
//
//  3. task icon의 semantic rainbow 제거.
//     "무슨 일인가"와 "얼마나 급한가"가 같은 채널에서 섞이지 않게 한다.
//     순서는 순서, urgency badge는 urgency.

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
// 구현 규칙 replica
// ═══════════════════════════════════════════════════════════════

/// `_buildFutureStaffing`의 모집단 + 정렬 규칙.
List<StaffingDayData> upcomingRows(List<StaffingDayData> days) {
  return days.skip(1).where((d) => d.requiredCount > 0).toList()
    ..sort((a, b) {
      final aRank = a.shortageCount > 0 ? 0 : 1;
      final bRank = b.shortageCount > 0 ? 0 : 1;
      if (aRank != bRank) return aRank - bRank;
      return a.date.compareTo(b.date);
    });
}

/// 행 두 번째 줄의 문장 규칙.
String progressText(StaffingDayData d, {String? biz, bool showPending = true}) {
  final fully = d.shortageCount == 0 && d.confirmedCount >= d.requiredCount;
  final parts = <String>[
    fully
        ? '${d.requiredCount}명 전원 확정'
        : '${d.requiredCount}명 중 ${d.confirmedCount}명 확정',
  ];
  if (biz != null) parts.add(biz);
  if (showPending && d.pendingCount != null && d.pendingCount! > 0) {
    parts.add('지원 대기 ${d.pendingCount}명');
  }
  return parts.join(' · ');
}

/// 오른쪽 부족 표기. 없으면 null.
String? shortageBadge(StaffingDayData d) =>
    d.shortageCount > 0 ? '${d.shortageCount}명 부족' : null;

StaffingBizData _biz(String name,
        {int required_ = 0, int confirmed = 0, int shortage = 0}) =>
    StaffingBizData(
      businessId: 'biz_$name',
      businessName: name,
      requiredCount: required_,
      confirmedCount: confirmed,
      shortageCount: shortage,
      pendingCount: 0,
    );

StaffingDayData _day(
  String date, {
  int required_ = 0,
  int confirmed = 0,
  int shortage = 0,
  int? pending = 0,
  List<StaffingBizData> byBusiness = const [],
}) =>
    StaffingDayData(
      date: date,
      requiredCount: required_,
      confirmedCount: confirmed,
      shortageCount: shortage,
      pendingCount: pending,
      byBusiness: byBusiness,
    );

void main() {
  final home = _src(_homePath);
  final homeCode = _codeOf(home);
  final future = _bodyOf(home, 'Widget _buildFutureStaffing(');
  final futureCode = _codeOf(future);
  final row = _bodyOf(home, 'Widget _buildFutureShortageRow(');
  final rowCode = _codeOf(row);
  final taskRow = _bodyOf(home, 'Widget _buildActionRowWidget(');
  final taskRowCode = _codeOf(taskRow);
  final dash = _bodyOf(home, 'Widget _buildActionDashboard(');

  // D0는 첫 요소 — 모집단에서 제외된다
  final d0 = _day('2026-09-15', required_: 8, confirmed: 8);

  // ═══════════════════════════════════════════════════════════════
  // 01. section rename — §2, §36
  // ═══════════════════════════════════════════════════════════════
  group('[08D.4-01] section rename', () {
    test('01-a 세 섹션 제목이 최종형이다', () {
      final titles = RegExp(r"_sectionHeader\(context, s, '([^']+)'")
          .allMatches(homeCode)
          .map((m) => m.group(1))
          .toSet();
      expect(titles, {'오늘', '처리할 일', '다가오는 7일'});
    });

    test('01-b 옛 제목이 user-facing surface에서 사라졌다', () {
      expect(homeCode.contains("'오늘 운영'"), isFalse);
      expect(homeCode.contains("'다가오는 인력 부족'"), isFalse);
    });

    test('01-c `다가오는 7일` header에 action을 붙이지 않았다', () {
      // data horizon 자체가 7일이라 `전체보기`는 의미가 부정확하다
      expect(_flat(futureCode).contains("'다가오는 7일'), SizedBox"), isTrue);
      expect(futureCode.contains("'전체보기'"), isFalse);
      expect(futureCode.contains('action:'), isFalse);
    });

    test('01-d `오늘` header의 당일 명단은 그대로다', () {
      final ops = _codeOf(_bodyOf(home, 'Widget _buildTodayOps('));
      expect(ops.contains("_sectionHeader(context, s, '오늘',"), isTrue);
      expect(ops.contains("'당일 명단'"), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 02. upcoming population — §3, §4, §17, §33
  // ═══════════════════════════════════════════════════════════════
  group('[08D.4-02] upcoming population', () {
    test('02-a 부족한 날과 전원 확정된 날이 둘 다 보인다', () {
      final rows = upcomingRows([
        d0,
        _day('2026-09-16'),
        _day('2026-09-17', required_: 8, confirmed: 6, shortage: 2),
        _day('2026-09-18'),
        _day('2026-09-19'),
        _day('2026-09-20', required_: 6, confirmed: 6),
      ]);
      expect(rows.map((d) => d.date).toList(),
          ['2026-09-17', '2026-09-20']);
    });

    test('02-b requiredCount == 0인 날은 표시하지 않는다', () {
      final rows = upcomingRows([d0, _day('2026-09-16'), _day('2026-09-17')]);
      expect(rows, isEmpty);
    });

    test('02-c D0는 모집단에서 빠진다 (오늘은 Today의 것)', () {
      final rows = upcomingRows([
        _day('2026-09-15', required_: 9, confirmed: 1, shortage: 8),
        _day('2026-09-16', required_: 2, confirmed: 2),
      ]);
      expect(rows.map((d) => d.date).toList(), ['2026-09-16']);
    });

    test('02-d D+8 이후는 서버가 주지 않으므로 모집단에 없다', () {
      // CF가 D0~D+7 8개만 반환한다 — 클라이언트가 더 자르지 않는다
      final days = [d0, for (var i = 16; i <= 22; i++) _day('2026-09-$i', required_: 1)];
      expect(upcomingRows(days).length, 7);
    });

    test('02-e shortage-only 필터가 코드에서 사라졌다', () {
      expect(futureCode.contains('d.shortageCount > 0)'), isFalse,
          reason: '모집단 필터로 쓰이면 전원 확정된 날이 사라진다');
      expect(futureCode, contains('.where((d) => d.requiredCount > 0)'));
    });

    test('02-f `모두 충원됐어요` 카드가 사라졌다 — 이제 행으로 보인다', () {
      expect(homeCode.contains('향후 7일 인원이 모두 충원됐어요'), isFalse);
    });

    test('02-g `예정된 인력 운영이 없어요` empty card를 되살리지 않았다', () {
      expect(homeCode.contains('향후 7일 예정된 인력 운영이 없어요'), isFalse);
      expect(futureCode, contains('if (futureDays.isEmpty) return const SizedBox.shrink();'));
    });

    test('02-h gate와 builder가 같은 조건을 쓴다', () {
      final gate = _codeOf(_bodyOf(home, 'bool get _showUpcomingSection'));
      expect(gate, contains('d.requiredCount > 0'));
      expect(futureCode, contains('d.requiredCount > 0'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 03. sort — §5, §33
  // ═══════════════════════════════════════════════════════════════
  group('[08D.4-03] sort', () {
    test('03-a 부족 그룹 먼저, 각 그룹 안에서 날짜 ASC', () {
      final rows = upcomingRows([
        d0,
        _day('2026-09-17', required_: 4, confirmed: 4),               // D+2 full
        _day('2026-09-18', required_: 5, confirmed: 3, shortage: 2),  // D+3 short
        _day('2026-09-20', required_: 6, confirmed: 2, shortage: 4),  // D+5 short
        _day('2026-09-21', required_: 3, confirmed: 3),               // D+6 full
      ]);
      expect(rows.map((d) => d.date).toList(), [
        '2026-09-18', // D+3
        '2026-09-20', // D+5
        '2026-09-17', // D+2
        '2026-09-21', // D+6
      ]);
    });

    test('03-b 같은 그룹 안에서 날짜 순서가 뒤집히지 않는다', () {
      final rows = upcomingRows([
        d0,
        _day('2026-09-20', required_: 2, confirmed: 0, shortage: 2),
        _day('2026-09-16', required_: 2, confirmed: 0, shortage: 2),
        _day('2026-09-18', required_: 2, confirmed: 0, shortage: 2),
      ]);
      expect(rows.map((d) => d.date).toList(),
          ['2026-09-16', '2026-09-18', '2026-09-20']);
    });

    test('03-c 정렬이 결정적이다 — 같은 입력에 같은 결과', () {
      final days = [
        d0,
        _day('2026-09-17', required_: 4, confirmed: 4),
        _day('2026-09-18', required_: 5, confirmed: 3, shortage: 2),
      ];
      expect(upcomingRows(days).map((d) => d.date).toList(),
          upcomingRows(days).map((d) => d.date).toList());
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 04. row visual — §6, §7, §8, §9, §14
  // ═══════════════════════════════════════════════════════════════
  group('[08D.4-04] row visual', () {
    test('04-a 부족한 날 progress text', () {
      final d = _day('2026-09-18', required_: 8, confirmed: 6, shortage: 2);
      expect(progressText(d), '8명 중 6명 확정');
      expect(shortageBadge(d), '2명 부족');
    });

    test('04-b 전원 확정된 날 progress text', () {
      final d = _day('2026-09-22', required_: 6, confirmed: 6);
      expect(progressText(d), '6명 전원 확정');
      expect(shortageBadge(d), isNull);
    });

    test('04-c shortage > 0이면 confirmed >= required여도 전원 확정이 아니다', () {
      // shortageCount는 per-wdId 합산 — required - confirmed와 다를 수 있다
      final d = _day('2026-09-18', required_: 8, confirmed: 8, shortage: 2);
      expect(progressText(d), '8명 중 8명 확정');
    });

    test('04-d 날짜가 행의 주어다 — 15 w700 textPrimary', () {
      expect(
        _flat(rowCode),
        contains('fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary'),
      );
    });

    test('04-e 날짜 앞 calendar icon을 붙이지 않았다', () {
      for (final t in [
        'Icons.calendar', 'Icons.event', 'Icons.date_range', 'Icons.today',
      ]) {
        expect(rowCode.contains(t), isFalse, reason: t);
      }
    });

    test('04-f progress bar / chart를 쓰지 않았다', () {
      for (final t in [
        'LinearProgressIndicator', 'CircularProgressIndicator',
        'FractionallySizedBox', 'Chart', '%',
      ]) {
        expect(rowCode.contains(t), isFalse, reason: t);
      }
    });

    test('04-g 부족 표기는 semantic text — background badge 없음', () {
      final flat = _flat(rowCode);
      expect(flat, contains(r"Text('$shortage명 부족'"));
      expect(flat, contains('color: AppColors.errorDark'));
      // 배지 배경을 만들지 않는다 — surface는 neutral
      expect(rowCode.contains('withValues(alpha'), isFalse);
      expect(rowCode.contains('BoxDecoration'), isFalse);
    });

    test('04-h 13px 본문 대비 — error(#F44336)가 아닌 errorDark를 쓴다', () {
      // [POSTING-V2-03S.1] 13px 텍스트에 ~3.9:1 토큰을 쓰지 않는다
      expect(rowCode.contains('AppColors.error,'), isFalse);
      expect(rowCode.contains('AppColors.errorDark'), isTrue);
    });

    test('04-i 전용 `충원하기` 버튼이 사라졌다', () {
      expect(homeCode.contains('충원하기'), isFalse);
      expect(rowCode.contains('OutlinedButton'), isFalse);
    });

    test('04-j 부족 여부와 무관하게 chevron 하나뿐이다', () {
      expect(RegExp(r'Icons\.chevron_right').allMatches(rowCode).length, 1);
      // chevron이 shortage 조건 안에 들어가 있지 않다
      final shortAt = rowCode.indexOf('if (shortage > 0)');
      final chevAt = rowCode.indexOf('Icons.chevron_right');
      final navAt = rowCode.indexOf('if (canNavigate)');
      expect(navAt, greaterThan(shortAt));
      expect(chevAt, greaterThan(navAt));
    });

    test('04-k 좁은 화면 대응 — Expanded + ellipsis', () {
      expect(rowCode, contains('Expanded('));
      expect(rowCode, contains('overflow: TextOverflow.ellipsis'));
      expect(rowCode.contains('width: 66 * s'), isFalse,
          reason: '고정 width 날짜 칼럼 제거');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 05. interaction / destination — §10~§14, §34
  // ═══════════════════════════════════════════════════════════════
  group('[08D.4-05] interaction', () {
    test('05-a 모든 행이 같은 destination으로 간다', () {
      expect(
        RegExp(r'_navigateToDayApplicantsForDate\(context, day\)')
            .allMatches(rowCode)
            .length,
        1,
        reason: '부족/충원으로 갈림길을 만들지 않는다',
      );
      expect(rowCode, contains('InkWell('));
    });

    test('05-b tap 조건에 shortage가 들어가지 않는다', () {
      final flat = _flat(rowCode);
      expect(flat, contains('if (canNavigate) InkWell('));
      expect(flat.contains('shortage > 0 ? () =>'), isFalse);
      expect(flat.contains('shortage > 0 && canNavigate'), isFalse);
    });

    test('05-c 충원 완료 행을 dead state로 만들지 않았다', () {
      // fullyStaffed는 문장 하나만 고른다 — 색·불투명도·비활성화로 번지지 않는다
      expect(RegExp(r'fullyStaffed').allMatches(rowCode).length, 2,
          reason: '선언 1 + progress 문장 분기 1');
      expect(rowCode.contains('AppColors.grey300'), isFalse);
      expect(rowCode.contains('Opacity('), isFalse);
      expect(rowCode.contains('enabled:'), isFalse);
    });

    test('05-d _safeNavigate + _requireApprovedBusiness 게이트 유지', () {
      expect(_flat(rowCode),
          contains('_safeNavigate(() => _requireApprovedBusiness('));
    });

    test('05-e shortageBusinesses 우선 businessIds 계약 유지', () {
      final nav =
          _codeOf(_bodyOf(home, 'Future<void> _navigateToDayApplicantsForDate('));
      expect(nav, contains('day.shortageBusinesses'));
      expect(nav, contains('shortBizIds.isNotEmpty'));
      expect(nav, contains('businesses.map((b) => b.id).toList()'));
    });

    test('05-f 충원 완료 행 fallback은 authorized businesses 안에서만', () {
      final nav =
          _codeOf(_bodyOf(home, 'Future<void> _navigateToDayApplicantsForDate('));
      expect(nav, contains('await _getBusinesses()'));
      final gb = _codeOf(_bodyOf(home, 'Future<List<BusinessModel>> _getBusinesses('));
      expect(gb, contains('up.effectiveBusinessId'));
      expect(gb, contains('managedBusinessIds'));
    });

    test('05-g mutation freshness 유지', () {
      final nav =
          _codeOf(_bodyOf(home, 'Future<void> _navigateToDayApplicantsForDate('));
      expect(nav, contains('_loadStaffingReadiness()'));
      expect(nav, contains('AdminMutationOrigin.home'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 06. permission — §30, §31
  // ═══════════════════════════════════════════════════════════════
  group('[08D.4-06] permission', () {
    test('06-a 기존 canManageTo 게이트를 넓히지 않았다', () {
      expect(_flat(rowCode),
          contains('canNavigate = _verified(up, (p) => p.canManageTo)'));
    });

    test('06-b 권한이 없으면 chevron도 tap도 없다 — 거짓 affordance 금지', () {
      final flat = _flat(rowCode);
      expect(flat, contains(r'if (canNavigate) ...[ SizedBox(width: 4 * s), Icon(Icons.chevron_right'));
      expect(flat, contains('if (canNavigate) InkWell('));
      expect(flat, contains('else rowContent'));
    });

    test('06-c 권한이 없어도 날짜·준비 상태는 읽힌다', () {
      // rowContent 자체는 권한 분기 밖에서 만들어진다
      final flat = _flat(rowCode);
      final contentAt = flat.indexOf('final rowContent =');
      final navAt = flat.indexOf('if (canNavigate) InkWell(');
      expect(contentAt, greaterThan(-1));
      expect(contentAt, lessThan(navAt));
    });

    test('06-d 섹션 가시성 게이트가 그대로다', () {
      final flat = _flat(futureCode);
      expect(flat,
          contains('canSeeBlock = _verified(up, (p) => p.canManageTo) || _verified(up, (p) => p.canManageWorkers)'));
    });

    test('06-e Home이 businessIds를 새로 확장하지 않는다', () {
      expect(rowCode.contains('managedBusinessIds'), isFalse);
      expect(rowCode.contains('businessIds'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 07. business summary — §15, §16
  // ═══════════════════════════════════════════════════════════════
  group('[08D.4-07] business summary', () {
    test('07-a 단일 사업장 → 사업장명', () {
      final d = _day('2026-09-18',
          required_: 8, confirmed: 6, shortage: 2,
          byBusiness: [_biz('평택센터', required_: 8, confirmed: 6, shortage: 2)]);
      expect(d.targetLocationLabel(), '평택센터');
    });

    test('07-b 여러 곳이면 `외 N곳`을 반드시 붙인다', () {
      final d = _day('2026-09-18', required_: 10, confirmed: 8, shortage: 2,
          byBusiness: [
            _biz('안성센터', required_: 4, confirmed: 4),
            _biz('평택센터', required_: 6, confirmed: 4, shortage: 2),
          ]);
      expect(d.targetLocationLabel(), '안성센터 외 1곳');
    });

    test('07-c 대표 사업장만 남겨 단일 근무처럼 보이지 않는다', () {
      final d = _day('2026-09-18', required_: 9, byBusiness: [
        _biz('가센터', required_: 3),
        _biz('나센터', required_: 3),
        _biz('다센터', required_: 3),
      ]);
      expect(d.targetLocationLabel(), '가센터 외 2곳');
    });

    test('07-d 전원 확정된 날도 위치를 말한다 — shortage 기준이 아니다', () {
      final d = _day('2026-09-22', required_: 6, confirmed: 6,
          byBusiness: [_biz('평택센터', required_: 6, confirmed: 6)]);
      expect(d.shortageLocationLabel(), isNull, reason: '부족이 없으니 부족 위치는 없다');
      expect(d.targetLocationLabel(), '평택센터');
    });

    test('07-e 근무가 없는 사업장은 위치에 들어가지 않는다', () {
      final d = _day('2026-09-18', required_: 5, byBusiness: [
        _biz('평택센터', required_: 5),
        _biz('안성센터'),
      ]);
      expect(d.targetLocationLabel(), '평택센터');
    });

    test('07-f byBusiness 미집계면 위치 없이 수치만', () {
      expect(_day('2026-09-18', required_: 5).targetLocationLabel(), isNull);
      expect(progressText(_day('2026-09-18', required_: 5, confirmed: 3, shortage: 2)),
          '5명 중 3명 확정');
    });

    test('07-g 순서가 결정적이다 (사업장명 ASC)', () {
      final byBiz = [
        _biz('하센터', required_: 1),
        _biz('가센터', required_: 1),
      ];
      expect(_day('d', required_: 2, byBusiness: byBiz).targetLocationLabel(),
          '가센터 외 1곳');
    });

    test('07-h workType/time을 위해 새 필드를 만들지 않았다', () {
      for (final t in ['wdId', 'workDetail', 'workType', 'startTime']) {
        expect(rowCode.contains(t), isFalse, reason: t);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 08. task visual — §19~§23, §35
  // ═══════════════════════════════════════════════════════════════
  group('[08D.4-08] task visual', () {
    test('08-a icon이 중립이다 — semantic rainbow 제거', () {
      expect(_flat(taskRowCode),
          contains('Icon(item.icon, size: 18 * s, color: AppColors.grey600)'));
      expect(taskRowCode.contains('color: item.color.withValues(alpha: 0.10)'),
          isFalse, reason: 'icon 배경 tint도 종류별 색이었다');
      expect(_flat(taskRowCode), contains('color: AppColors.grey100'));
    });

    test('08-b count가 전부 같은 무게다', () {
      final flat = _flat(taskRowCode);
      expect(flat,
          contains('Text(item.countStr, style: TextStyle( fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary))'));
      expect(flat.contains('FontWeight.w800'), isFalse);
      expect(flat.contains('color: item.color)))'), isFalse);
    });

    test('08-c count pill 배경이 사라졌다', () {
      // 숫자 하나에 배경을 주면 종류별로 다른 강조가 다시 생긴다
      expect(RegExp(r'BoxDecoration').allMatches(taskRowCode).length, 1,
          reason: 'icon 컨테이너 하나만 남는다');
    });

    test('08-d label 15 / count 15 hierarchy', () {
      final flat = _flat(taskRowCode);
      expect(flat,
          contains('Text(item.label, style: TextStyle( fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary))'));
      expect(flat.contains('fontSize: 14,'), isFalse);
    });

    test('08-e urgency는 badge 한 채널에서만', () {
      // badge에만 item.color가 남는다
      expect(RegExp(r'item\.color').allMatches(taskRowCode).length, 1);
      expect(_flat(taskRowCode),
          contains('Text(item.badge!, style: TextStyle(fontSize: 12, color: item.color))'));
    });

    test('08-f badge는 실제 urgency metadata가 있을 때만 생긴다', () {
      final make = _codeOf(_bodyOf(home, '_makeActionRows(BuildContext context'));
      expect(make, contains(r"badge: soon > 0 ? '내일 자동 승인 $soon건' : null"));
      expect(make, contains('overdueCount'));
      // 새 urgency 계산을 만들지 않았다
      expect(make.contains('urgencyScore'), isFalse);
      expect(make.contains('priority ='), isFalse);
    });

    test('08-g 순서로 급함을 다시 encode하지 않는다', () {
      // 행 위젯은 자기 index를 모른다 — isLast(divider용)뿐이다
      expect(taskRowCode.contains('index'), isFalse);
      expect(taskRowCode.contains('atIndex'), isFalse);
      expect(taskRow.contains('required bool isLast'), isTrue);
    });

    test('08-h divider grey100, 마지막 행 제외', () {
      expect(_flat(taskRowCode),
          contains('if (!isLast) Padding( padding: EdgeInsets.symmetric(horizontal: 16 * s), child: Divider(height: 1, color: AppColors.grey100)'));
    });

    test('08-i 조회 실패는 0건으로 둔갑하지 않는다 (ERROR≠ZERO)', () {
      // [HOME-V2-08D.5] 행 안의 `조회 실패` 칩이 사라졌다. ERROR≠ZERO는
      //   더 강하게 지켜진다 — 확인하지 못한 항목은 0건으로도, 행으로도
      //   표현되지 않고 section notice가 사실만 말한다.
      expect(taskRowCode.contains('item.available'), isFalse);
      expect(taskRowCode.contains('조회 실패'), isFalse);
      final dashBody = _codeOf(_bodyOf(home, 'Widget _buildActionDashboard('));
      expect(dashBody, contains('_unknownTaskCount(up, cs)'));
      expect(dashBody,
          contains('final showReassurance = rows.isEmpty && !showNotice;'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 09. task behavior 무회귀 — §18, §24, §25
  // ═══════════════════════════════════════════════════════════════
  group('[08D.4-09] task behavior 무회귀', () {
    final make = _codeOf(_bodyOf(home, '_makeActionRows(BuildContext context'));

    test('09-a 9종과 순서가 그대로다', () {
      const order = [
        '퇴사 요청', '지원 검토', '스케줄 변경 요청', '계약 미발송', '마감 필요',
        '중간정산 요청', '급여 변경 요청', '이체 대기', '계약 종료 예정',
      ];
      var prev = -1;
      for (final label in order) {
        final at = make.indexOf("label: '$label'");
        expect(at, greaterThan(prev), reason: label);
        prev = at;
      }
    });

    test('09-b 재정렬 구조를 만들지 않았다', () {
      expect(make.contains('.sort('), isFalse);
      expect(make, contains('atIndex: wageOverdue ? overdueWageSlot : null,'));
    });

    test('09-c permission 게이트가 그대로다', () {
      // [CROSS-DOMAIN-R5.1F.5] 게이트는 그대로 있고 판정만 4상태가 됐다.
      expect(make, contains('_verified(up, (p) => p.'));
    });

    test('09-d task gate 의미를 바꾸지 않았다', () {
      final gate = _codeOf(_bodyOf(home, 'bool _showTaskSection('));
      expect(gate, contains('if (hasRows) return true;'));
      expect(gate, contains('!_isLifecycleHero(hero)'));
    });

    test('09-e 빈 상태 한 줄이 그대로다', () {
      expect(_codeOf(dash), contains("'처리할 업무가 없어요'"));
    });

    test('09-f posting lifecycle과 독립이다', () {
      final gate = _codeOf(_bodyOf(home, 'bool _showTaskSection('));
      expect(gate.contains('publishedPostingCount'), isFalse);
      expect(gate.contains('hasDraftPosting'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 10. 무회귀 — §26~§29, §32
  // ═══════════════════════════════════════════════════════════════
  group('[08D.4-10] 무회귀', () {
    test('10-a card contract 유지 — shadow 재도입 없음', () {
      expect(homeCode.contains('boxShadow'), isFalse);
      expect(homeCode.contains('BoxShadow'), isFalse);
      expect(homeCode.contains('elevation:'), isFalse);
      final deco =
          _codeOf(_bodyOf(home, 'static final BoxDecoration _groupSurface'));
      expect(_flat(deco), contains('color: AppColors.surface'));
      expect(_flat(deco), contains('borderRadius: BorderRadius.circular(16)'));
      expect(_flat(deco),
          contains('border: Border.all(color: AppColors.grey200, width: 1)'));
    });

    test('10-b Hero를 건드리지 않았다', () {
      expect(home, contains('enum _HeroState'));
      expect(home, contains('_HeroState _heroStateOf('));
      final hero = _codeOf(_bodyOf(home, 'Widget _buildAdaptiveHero('));
      expect(RegExp(r'ctaLabel:').allMatches(hero).length, 4);
    });

    test('10-c Today 구조를 건드리지 않았다', () {
      for (final t in [
        'Widget? _buildTodayStaffingSummary(',
        'List<Widget> _buildTodayIssueRows(',
        'Widget? _buildTodayAttendanceLine(',
        'Widget _todayIssueRow(',
      ]) {
        expect(home.contains(t), isTrue, reason: t);
      }
      final ops = _codeOf(_bodyOf(home, 'Widget _buildTodayOps('));
      expect(ops, contains('_openTodayAttendanceDialog(context)'));
    });

    test('10-d Today gate 교정(08D.3.1)이 유지된다', () {
      final gate = _codeOf(_bodyOf(home, 'bool get _showTodaySection'));
      expect(gate.contains('_todayCheckedIn'), isFalse);
      expect(gate, contains('_hasTodayRoster == true'));
    });

    test('10-e section 순서가 그대로다', () {
      final b = _codeOf(_bodyOf(home, 'Widget build(')) +
          _codeOf(_bodyOf(home, 'List<Widget> _buildSections('));
      var prev = -1;
      for (final m in [
        '_buildHeader(', '_buildStateBanner(', '_buildAdaptiveHero(',
        '_buildTodayOps(', '_buildActionDashboard(', '_buildFutureStaffing(',
      ]) {
        final at = b.indexOf(m);
        expect(at, greaterThan(prev), reason: m);
        prev = at;
      }
    });

    test('10-f partial notice가 두 섹션에 그대로 있다', () {
      expect(futureCode, contains('_partialStaffingNotice(s)'));
      expect(_codeOf(_bodyOf(home, 'Widget? _buildTodayStaffingSummary(')),
          contains('_partialStaffingNotice(s)'));
    });

    test('10-g staffing error row가 그대로다', () {
      expect(futureCode, contains("'향후 인력 현황을 불러오지 못했습니다'"));
      expect(futureCode, contains('_loadStaffingReadiness()'));
    });

    test('10-h read / callable / listener 0', () {
      for (final body in [futureCode, rowCode, taskRowCode]) {
        for (final token in [
          'httpsCallable', '_firestoreService', 'FirebaseFirestore',
          'snapshots(', 'await ',
        ]) {
          expect(body.contains(token), isFalse, reason: token);
        }
      }
      expect(RegExp(r'Future<void> _load\w+\(').allMatches(home).length, 5);
    });

    test('10-i Quick Menu / FAB를 만들지 않았다', () {
      expect(homeCode.contains('FloatingActionButton'), isFalse);
      expect(homeCode.contains('QuickMenu'), isFalse);
    });

    test('10-j 12px 가독성 하한 유지 (TYPO-50)', () {
      expect(RegExp(r'fontSize: (8|9|10|11)(\.\d+)?[,)\s]').hasMatch(homeCode),
          isFalse);
    });
  });
}
