import 'dart:io';

import 'package:ALfit/models/ui/staffing_readiness_model.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// AH-V2-04B BUSINESS-SCOPE-VISIBILITY
//
// 다사업장 관리자가 Home에서 알아야 하는 것:
//   전체 상황  +  문제가 있는 위치  +  다음 행동
//
// 서버는 days[i].byBusiness로 이미 위치를 보내고 있었고
// Home은 destination에만 쓰고 표시에서 버리고 있었다.
//
// 정보 밀도는 통제한다 — 부족이 있을 때만, 상위 2곳 + 외 N곳.
// ═══════════════════════════════════════════════════════════════

const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _dialogPath =
    'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';

String _src(String p) => File(p).readAsStringSync();
String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: '$signature 를 찾지 못함');
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
  fail('$signature 본문의 끝을 찾지 못함');
}

Map<String, Object?> _biz(String id, String name, int shortage,
        {int req = 10, int conf = 8}) =>
    {
      'businessId': id,
      'businessName': name,
      'requiredCount': req,
      'confirmedCount': conf,
      'shortageCount': shortage,
      'pendingCount': 0,
    };

StaffingDayData _day(List<Map<String, Object?>> byBusiness,
    {int req = 0, int conf = 0, int short = 0}) {
  return StaffingDayData.fromMap({
    'date': '2026-09-13',
    'requiredCount': req,
    'confirmedCount': conf,
    'shortageCount': short,
    'pendingCount': 0,
    'byBusiness': byBusiness,
  });
}

void main() {
  late String home;
  late String dialog;

  setUpAll(() {
    home = _codeOf(_src(_homePath));
    dialog = _codeOf(_src(_dialogPath));
  });

  // ───────────────────────────────────────────────────────────
  // SCOPE-03 / 04 부족 위치
  // ───────────────────────────────────────────────────────────
  group('SCOPE-03 부족한 사업장만 노출', () {
    final day = _day([
      _biz('a', 'A센터', 4),
      _biz('b', 'B센터', 2),
      _biz('c', 'C센터', 0),
    ], req: 30, conf: 24, short: 6);

    test('부족 0인 사업장은 빠진다', () {
      expect(day.shortageBusinesses.map((b) => b.businessId), ['a', 'b']);
    });

    test('요약 문자열에 C센터가 없다', () {
      final s = day.shortageScopeLabel()!;
      expect(s.contains('A센터'), isTrue);
      expect(s.contains('B센터'), isTrue);
      expect(s.contains('C센터'), isFalse);
    });

    test('합계는 그대로 6명', () {
      expect(day.shortageCount, 6);
    });
  });

  group('SCOPE-04 shortage DESC 정렬', () {
    test('큰 부족이 먼저', () {
      final day = _day([
        _biz('a', 'A센터', 1),
        _biz('b', 'B센터', 5),
        _biz('c', 'C센터', 3),
      ]);
      expect(day.shortageBusinesses.map((b) => b.businessName),
          ['B센터', 'C센터', 'A센터']);
    });

    test('동률이면 사업장명 오름차순 — 순서가 흔들리지 않는다', () {
      final day = _day([
        _biz('z', '하남센터', 3),
        _biz('a', '가산센터', 3),
        _biz('m', '마포센터', 3),
      ]);
      expect(day.shortageBusinesses.map((b) => b.businessName),
          ['가산센터', '마포센터', '하남센터']);
    });

    test('입력 순서를 바꿔도 결과가 같다', () {
      final f = _day([_biz('a', 'A', 1), _biz('b', 'B', 5)]);
      final r = _day([_biz('b', 'B', 5), _biz('a', 'A', 1)]);
      expect(f.shortageScopeLabel(), r.shortageScopeLabel());
    });
  });

  // ───────────────────────────────────────────────────────────
  // SCOPE-05 표시 수 제한
  // ───────────────────────────────────────────────────────────
  group('SCOPE-05 표시 limit', () {
    test('1곳', () {
      expect(_day([_biz('a', 'A센터', 4)]).shortageScopeLabel(), 'A센터 4명');
    });

    test('2곳 — 전부 표시', () {
      final s = _day([_biz('a', 'A센터', 4), _biz('b', 'B센터', 2)])
          .shortageScopeLabel();
      expect(s, 'A센터 4명 · B센터 2명');
    });

    test('3곳 이상 — 상위 2곳 + 외 N곳', () {
      final s = _day([
        _biz('a', 'A센터', 4),
        _biz('b', 'B센터', 2),
        _biz('c', 'C센터', 1),
      ]).shortageScopeLabel();
      expect(s, 'A센터 4명 · B센터 2명 · 외 1곳');
    });

    test('5곳 — 외 3곳', () {
      final s = _day([
        _biz('a', 'A', 9), _biz('b', 'B', 7), _biz('c', 'C', 5),
        _biz('d', 'D', 3), _biz('e', 'E', 1),
      ]).shortageScopeLabel();
      expect(s, 'A 9명 · B 7명 · 외 3곳');
    });

    test('사업장 목록이 되지 않는다 — 항상 3토막 이하', () {
      final day = _day(List.generate(
          12, (i) => _biz('b$i', '사업장$i', 12 - i)));
      expect(day.shortageScopeLabel()!.split(' · ').length, lessThanOrEqualTo(3));
    });

    test('businessName이 비면 id로 대체 (빈 라벨 방지)', () {
      final s = _day([_biz('biz123', '', 2)]).shortageScopeLabel();
      expect(s, 'biz123 2명');
    });
  });

  // ───────────────────────────────────────────────────────────
  // SCOPE-07 / 08 empty · error
  // ───────────────────────────────────────────────────────────
  group('SCOPE-07/08 부족 없음 · 대상 없음', () {
    test('부족 0 → 요약 없음', () {
      expect(
        _day([_biz('a', 'A센터', 0), _biz('b', 'B센터', 0)]).shortageScopeLabel(),
        isNull,
        reason: '문제가 없는데 사업장별 0명 목록을 만들지 않는다',
      );
    });

    test('byBusiness 비어도 안전', () {
      expect(_day(const []).shortageScopeLabel(), isNull);
      expect(_day(const []).shortageBusinesses, isEmpty);
    });

    test('UI가 부족이 있을 때만 요약을 만든다', () {
      // [HOME-V2-08D.3] 부족 위치는 KPI 옆 보조줄에서 issue row로 옮겨졌다.
      //   `부족이 있을 때만 만든다`는 조건은 그대로 남아 있다.
      final m = _bodyOf(home, 'List<Widget> _buildTodayIssueRows(');
      expect(m.contains('if (day != null && shortage > 0) {'), isTrue);
      expect(m.contains('day.shortageLocationLabel()'), isTrue);
    });

    test('에러 분기가 요약보다 먼저 — ERROR면 요약 없음', () {
      // [HOME-V2-08D.3] 요약 줄과 issue row는 서로 다른 builder가 됐지만
      //   ERROR/대상없음에서 아무 수치도 주장하지 않는 순서는 같다.
      final m = _bodyOf(home, 'Widget? _buildTodayStaffingSummary(');
      expect(m.indexOf('hasUsableData'), lessThan(m.indexOf('명 필요 · ')));
      expect(m.indexOf('hasTodayTarget'), lessThan(m.indexOf('명 필요 · ')),
          reason: '대상 없음 상태에도 수치를 억지로 붙이지 않는다');
      // issue row도 staffing이 로딩/실패면 숫자를 말하지 않는다
      final i = _bodyOf(home, 'List<Widget> _buildTodayIssueRows(');
      expect(i.indexOf('!_staffingLoading'), lessThan(i.indexOf('명 부족')));
      expect(i.contains('_todayStaffingDay'), isTrue,
          reason: 'hasUsableData가 false면 null을 돌려주는 getter');
    });
  });

  // ───────────────────────────────────────────────────────────
  // SCOPE-01 / 02 scope label
  // ───────────────────────────────────────────────────────────
  group('SCOPE-01 단일 사업장', () {
    test('scope label을 붙이지 않는다', () {
      final f = _bodyOf(home, 'String? _staffingScopeLabel(');
      expect(f.contains('if (!_isMultiBusinessScope) return null;'), isTrue);
    });

    test('부족 위치 요약도 다사업장일 때만', () {
      // [HOME-V2-08D.3] 위치가 issue row로 옮겨졌다 — 단일 사업장에서는
      //   header가 이미 사업장명을 말하므로 붙이지 않는다는 규칙은 그대로다.
      final m = _bodyOf(home, 'List<Widget> _buildTodayIssueRows(');
      expect(m.contains('_isMultiBusinessScope ? day.shortageLocationLabel() : null'),
          isTrue);
      final r = _bodyOf(home, 'Widget _buildFutureShortageRow(');
      expect(r.contains('_isMultiBusinessScope ? day.targetLocationLabel() : null'),
          isTrue);
    });

    test('다사업장 판정이 staffing 집계 범위와 같은 소스', () {
      final g = _bodyOf(home, 'bool get _isMultiBusinessScope');
      expect(g.contains('_businesses.length > 1'), isTrue);
      // _getBusinesses()가 CF와 같은 scope를 쓴다 (SubAdmin 1곳 / OWNER managed)
      final gb = _bodyOf(home, 'Future<List<BusinessModel>> _getBusinesses(');
      expect(gb.contains('up.effectiveBusinessId'), isTrue);
      expect(gb.contains('managedBusinessIds'), isTrue);
    });
  });

  group('SCOPE-02 다사업장 aggregate', () {
    test('합계임을 알리는 라벨이 있다', () {
      final f = _bodyOf(home, 'String? _staffingScopeLabel(');
      expect(f.contains("'전체 \${_businesses.length}개 사업장 합계'"), isTrue);
    });

    test('필요·확정·부족 지표는 그대로', () {
      // [HOME-V2-08D.3] 세 수치는 KPI 셀에서 문장·issue row로 표현만 바뀌었다.
      //   어떤 수치를 말하는가는 그대로다.
      final m = _bodyOf(home, 'Widget? _buildTodayStaffingSummary(');
      expect(m.contains('명 필요 · '), isTrue);
      expect(m.contains('명 확정'), isTrue);
      final i = _bodyOf(home, 'List<Widget> _buildTodayIssueRows(');
      expect(i.contains('명 부족'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // SCOPE-06 partial
  // ───────────────────────────────────────────────────────────
  group('SCOPE-06 부분 실패', () {
    test('partial이면 scope label을 숨긴다', () {
      final f = _bodyOf(home, 'String? _staffingScopeLabel(');
      expect(f.contains('_staffingReadiness?.partial == true'), isTrue);
      expect(f.contains('return null'), isTrue);
    });

    test('partial notice는 유지된다', () {
      final m = _bodyOf(home, 'Widget? _buildTodayStaffingSummary(');
      expect(m.contains('_partialStaffingNotice(s)'), isTrue);
      final w = _bodyOf(home, 'Widget _partialStaffingNotice(');
      expect(w.contains('나머지 사업장 기준으로 표시했어요'), isTrue);
      expect(w.contains('재시도'), isTrue);
    });

    test('부족 위치 요약은 성공 사업장 데이터만 담는다', () {
      // byBusiness는 서버가 실패 사업장을 합산에서 제외한 뒤 만든 것이다.
      final day = _day([_biz('a', 'A센터', 4), _biz('b', 'B센터', 2)],
          short: 6);
      expect(day.shortageBusinesses.length, 2);
      expect(day.shortageScopeLabel(), 'A센터 4명 · B센터 2명');
    });

    test('partial에서도 부족 위치는 계속 보인다 (숨기지 않음)', () {
      // [HOME-V2-08D.3] issue row 전체에 partial 가드가 없어야 한다.
      //   partial은 "합계가 일부"라는 뜻이지 "부족이 없다"는 뜻이 아니다.
      final m = _codeOf(_bodyOf(home, 'List<Widget> _buildTodayIssueRows('));
      expect(m.contains('partial'), isFalse);
      expect(m.contains('shortageLocationLabel'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // SCOPE-09 / 10 destination
  // ───────────────────────────────────────────────────────────
  group('SCOPE-09/10 destination 유지', () {
    test('부족 사업장만 전달한다', () {
      final f = _bodyOf(home, 'Future<void> _navigateToDayApplicantsForDate(');
      expect(f.contains('day.shortageBusinesses'), isTrue);
      expect(f.contains('shortBizIds.isNotEmpty'), isTrue,
          reason: '부족 사업장이 없으면 전체로 폴백하는 기존 동작 유지');
    });

    test('오늘·향후 모두 같은 함수를 쓴다', () {
      expect(home.contains('_navigateToDayApplicantsForDate(context, day)'), isTrue);
      // [HOME-V2-08D.3] 오늘 issue row도 같은 helper를 같은 인자 형태로 쓴다
      expect(_bodyOf(home, 'List<Widget> _buildTodayIssueRows(')
          .contains('_navigateToDayApplicantsForDate(context, day)'), isTrue);
    });

    test('전달 순서가 Home 표시 순서와 같다 (부족 큰 순)', () {
      final day = _day([
        _biz('a', 'A센터', 1),
        _biz('b', 'B센터', 5),
      ]);
      expect(day.shortageBusinesses.first.businessId, 'b');
      // 화면 요약도 같은 순서
      expect(day.shortageScopeLabel()!.startsWith('B센터'), isTrue);
    });

    test('dialog architecture는 그대로', () {
      final f = _bodyOf(home, 'Future<void> _navigateToDayApplicantsForDate(');
      expect(f.contains('DayApplicantsDialog('), isTrue);
      expect(f.contains('businesses: businesses'), isTrue);
      expect(f.contains('_loadStaffingReadiness()'), isTrue, reason: '변동 시 재조회');
    });
  });

  // ───────────────────────────────────────────────────────────
  // §16 1-option selector
  // ───────────────────────────────────────────────────────────
  group('1-option selector', () {
    test('선택지 수로 판단한다', () {
      expect(dialog.contains('trailing: widget.businessIds.length > 1'), isTrue);
      expect(dialog.contains('trailing: widget.businesses.length > 1'), isFalse);
    });

    test('selector 옵션 소스는 그대로 businessIds', () {
      expect(dialog.contains('items: widget.businessIds'), isTrue);
    });

    test('이름 조회는 여전히 businesses 전체 목록을 쓴다', () {
      final f = _bodyOf(dialog, 'String _bizName(');
      expect(f.contains('widget.businesses'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // 범위 제한
  // ───────────────────────────────────────────────────────────
  group('AH-V2-04B 범위 제한', () {
    test('업무유형을 Home에 표시하지 않는다', () {
      final m = _bodyOf(home, 'Widget? _buildTodayStaffingSummary(');
      final r = _bodyOf(home, 'Widget _buildFutureShortageRow(');
      for (final t in ['wdId', 'workDetail', 'workType']) {
        expect(m.contains(t), isFalse, reason: 'today: $t');
        expect(r.contains(t), isFalse, reason: 'future: $t');
      }
    });

    test('Home scope selector를 만들지 않았다', () {
      expect(home.contains('DropdownButton'), isFalse);
      expect(home.contains("sheetTitle: '사업장 선택'"), isFalse);
    });

    test('새 카드·섹션을 만들지 않았다', () {
      final titles = RegExp(r"_sectionHeader\(context, s, '([^']+)'")
          .allMatches(home)
          .map((m) => m.group(1))
          .toSet();
      expect(titles, {'오늘', '다가오는 7일', '처리할 일'});
    });

    test('Home section 순서 유지', () {
      // [HOME-V2-08D.2] 섹션 조립이 _buildSections로 옮겨졌다 — 순서는 그대로.
      final b = _bodyOf(home, 'Widget build(') +
          _bodyOf(home, 'List<Widget> _buildSections(');
      var prev = -1;
      for (final m in [
        '_buildHeader(', '_buildStateBanner(', '_buildAdaptiveHero(',
        // [AH-V2-05B] TODAY → TASK → NEXT
        '_buildTodayOps(', '_buildActionDashboard(', '_buildFutureStaffing(',
      ]) {
        final at = b.indexOf(m);
        expect(at, greaterThan(prev));
        prev = at;
      }
    });

    test('header의 N개 사업장 관리를 지우지 않았다', () {
      expect(home.contains(r"'${_businesses.length}개 사업장 관리'"), isTrue);
    });

    test('secondary hierarchy — 부족 수치보다 약하게', () {
      // [HOME-V2-08D.3] 위계의 값은 바뀌었지만 방향은 같다:
      //   부족 issue 15 w600 > 요약/출근 13 textSecondary > scope 12 grey400.
      //   12px 가독성 하한(TYPO-50)은 그대로다.
      final m = _bodyOf(home, 'Widget? _buildTodayStaffingSummary(');
      expect(m.contains('fontSize: 12, color: AppColors.grey400'), isTrue);
      expect(m.contains('fontSize: 13, color: AppColors.textSecondary'), isTrue);
      final row = _bodyOf(home, 'Widget _todayIssueRow(')
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(row.contains('fontSize: 15, fontWeight: FontWeight.w600'), isTrue);
    });

    test('12px 가독성 하한을 지킨다 (TYPO-50)', () {
      final added = [
        _bodyOf(home, 'Widget? _buildTodayStaffingSummary('),
        _bodyOf(home, 'Widget _buildFutureShortageRow('),
      ].join('\n');
      expect(RegExp(r'fontSize: (8|9|10|11)(\.\d+)?[,)\s]').hasMatch(added),
          isFalse);
    });

    test('긴 사업장명 overflow 대응 (폰트 축소 아님)', () {
      // [HOME-V2-08D.3] 사업장명이 들어가는 곳은 이제 issue row다.
      final m = _bodyOf(home, 'Widget _todayIssueRow(');
      expect(m.contains('overflow: TextOverflow.ellipsis'), isTrue);
      expect(m.contains('maxLines: 2'), isTrue);
      expect(m.contains('Expanded('), isTrue, reason: '고정 width 금지');
      final r = _bodyOf(home, 'Widget _buildFutureShortageRow(');
      expect(r.contains('maxLines: 1'), isTrue);
      expect(r.contains('overflow: TextOverflow.ellipsis'), isTrue);
    });

    test('permission 게이트 유지', () {
      final t = _bodyOf(home, 'Widget _buildTodayOps(');
      expect(t.contains('canManageTo'), isTrue);
      expect(t.contains('canManageWorkers'), isTrue);
      final r = _bodyOf(home, 'Widget _buildFutureShortageRow(');
      expect(r.contains('canManageTo'), isTrue);
    });

    test('AH-V2-03 상태 의미 유지', () {
      expect(home.contains('hasUsableData'), isTrue);
      // [HOME-V2-08D.2] '대상 없음'은 이제 gate가 섹션을 숨기고 Hero가 말한다.

      // [HOME-V2-08D.2] '대상 없음'은 이제 gate가 섹션을 숨기고 Hero가 말한다.

      expect(home.contains('향후 인력 현황을 불러오지 못했습니다'), isTrue);
    });

    test('AH-V2-04A 근태 확인 유지', () {
      expect(home.contains(r"'근태 확인 $needsAttention건'"), isTrue);
      expect(home.contains('AttendanceReviewHelper.requiresReviewNow('), isTrue);
    });

    test('처리할 일 9종 유지', () {
      final rows = _bodyOf(home, '_makeActionRows(BuildContext context');
      for (final label in [
        '퇴사 요청', '지원 검토', '마감 필요', '급여 변경 요청', '중간정산 요청',
        '스케줄 변경 요청', '계약 미발송', '계약 종료 예정', '이체 대기',
      ]) {
        expect(rows.contains("label: '$label'"), isTrue);
      }
    });

    test('capacity 필드 의미 미변경 — 표시만 추가', () {
      final dto = _codeOf(_src('lib/models/ui/staffing_readiness_model.dart'));
      expect(dto.contains('shortageCount'), isTrue);
      // 파생 getter는 필터·정렬만 한다
      final g = _bodyOf(dto, 'List<StaffingBizData> get shortageBusinesses');
      expect(g.contains('b.shortageCount > 0'), isTrue);
      expect(g.contains('+') || g.contains('-'), isFalse,
          reason: '재계산 금지 — 서버 값을 그대로 쓴다');
    });
  });
}
