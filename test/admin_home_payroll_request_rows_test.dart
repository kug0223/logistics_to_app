import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// AH-V2-02A EXISTING-PENDING-ROWS-CONNECTION
//
// 중간정산 요청 / 급여 변경 요청은 이미
//   Firestore canonical state → CF 집계 → callable 응답 → Dart DTO
// 까지 전부 구현돼 있었고, Home action row만 없었다.
//
// 이 Phase는 새 기능을 만들지 않는다 — 있는 것을 Home에 연결한다.
// 서버를 붙이지 않고 실행할 수 없으므로 구조 수준 고정이다.
// ═══════════════════════════════════════════════════════════════

const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _dtoPath = 'lib/models/ui/admin_home_summary_model.dart';
const _indexPath = 'functions/src/index.ts';

String _src(String path) => File(path).readAsStringSync();

/// 주석 줄을 제거한 사본. 설명 주석이 배선 스캔에 잡히는 것을 막는다.
String _codeOf(String body) => body
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// 시그니처에서 시작해 중괄호 짝을 맞춰 메서드 본문만 잘라낸다.
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

/// _makeActionRows 안에서 특정 row 블록만 잘라낸다.
String _rowBlock(String rows, String label, String nextLabel) {
  final start = rows.indexOf("label: '$label'");
  expect(start, isNot(-1), reason: "'$label' row를 찾지 못함");
  final end = rows.indexOf("label: '$nextLabel'", start);
  return end == -1 ? rows.substring(start) : rows.substring(start, end);
}

void main() {
  late String home;
  late String rows;
  late String dto;

  setUpAll(() {
    home = _codeOf(_src(_homePath));
    // 호출부(_buildActionDashboard)가 파일에서 먼저 나오므로 정의부를 특정한다.
    rows = _bodyOf(home, '_makeActionRows(BuildContext context');
    dto = _src(_dtoPath);
  });

  // ───────────────────────────────────────────────────────────
  // 서버·DTO 선행 조건 (변경하지 않았음도 함께 확인)
  // ───────────────────────────────────────────────────────────
  group('AH-V2-02A 선행 조건 — 서버·DTO 무변경', () {
    test('CF가 두 섹션을 이미 집계해 응답에 담는다', () {
      final cf = _codeOf(_src(_indexPath));
      expect(cf.contains('wageChangeRequest: aggSimple("canManageWage"'), isTrue);
      expect(cf.contains('settlementRequest: aggSimple("canManageWage"'), isTrue);
      expect(cf.contains('srvHomeWageChangeRequest'), isTrue);
      expect(cf.contains('srvHomeSettlementRequest'), isTrue);
    });

    test('CF가 canonical 컬렉션의 PENDING을 센다', () {
      final cf = _src(_indexPath);
      expect(cf.contains('db.collection("payment_change_requests")'), isTrue);
      expect(cf.contains('db.collection("interim_settlement_requests")'), isTrue);
    });

    test('DTO 슬롯이 그대로다', () {
      expect(dto.contains('final AdminHomeSimpleSection wageChangeRequest;'), isTrue);
      expect(dto.contains('final AdminHomeSimpleSection settlementRequest;'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('AHV2-02A-01 중간정산 요청 row 표시', () {
    test('row가 canonical summary를 source로 쓴다', () {
      expect(rows.contains("label: '중간정산 요청'"), isTrue);
      expect(rows.contains('cs?.actions.settlementRequest'), isTrue);
    });

    test('건수 단위가 건이다', () {
      final block = _rowBlock(rows, '중간정산 요청', '계약 미발송');
      expect(block.contains("countStr: '\${settlement?.count ?? 0}건'"), isTrue);
    });
  });

  group('AHV2-02A-02 0건 숨김', () {
    test('add() 공통 규칙이 유지된다', () {
      expect(rows.contains('if (available && count == 0) return;'), isTrue,
          reason: 'ZERO_COUNT_ACTION_VISIBILITY = HIDE');
    });

    test('두 row 모두 count를 add()에 넘긴다 — 별도 표시 규칙 없음', () {
      for (final pair in [
        ['중간정산 요청', '계약 미발송'],
        ['급여 변경 요청', '중간정산 요청'],
      ]) {
        final block = _rowBlock(rows, pair[0], pair[1]);
        expect(block.contains('count: '), isTrue);
        expect(block.contains('available: '), isTrue);
      }
    });
  });

  group('AHV2-02A-03 조회 실패 semantics 재사용', () {
    test('available은 canonical 값에서 온다', () {
      final settlement = _rowBlock(rows, '중간정산 요청', '계약 미발송');
      expect(settlement.contains('available: settlement?.available ?? false'), isTrue);
      final wage = _rowBlock(rows, '급여 변경 요청', '중간정산 요청');
      expect(wage.contains('available: wageChange?.available ?? false'), isTrue);
    });

    test('탭 시 기존 실패 UX를 그대로 쓴다', () {
      for (final pair in [
        ['중간정산 요청', '계약 미발송'],
        ['급여 변경 요청', '중간정산 요청'],
      ]) {
        final block = _rowBlock(rows, pair[0], pair[1]);
        expect(block.contains('_ensureCanonicalSummary(context)'), isTrue);
        expect(block.contains('_showCanonicalError(context)'), isTrue);
      }
    });

    test('새 에러 UI를 만들지 않았다', () {
      final home2 = _src(_homePath);
      expect(home2.contains('중간정산 요청을 불러오지 못했습니다'), isFalse);
      expect(home2.contains('급여 변경 요청을 불러오지 못했습니다'), isFalse);
    });
  });

  group('AHV2-02A-04 중간정산 destination 정밀도', () {
    test('중간정산 탭(3) + PENDING 전용 필터로 진입한다', () {
      final block = _rowBlock(rows, '중간정산 요청', '계약 미발송');
      expect(block.contains('_toPayrollTabDrilldown('), isTrue);
      expect(block.contains('tab: 3'), isTrue);
      expect(block.contains('showPendingSettlementOnly: true'), isTrue);
    });

    test('dead parameter가 살아났다 — Home이 true를 넘기는 유일한 곳', () {
      final hits = 'showPendingSettlementOnly: true'.allMatches(home).length;
      expect(hits, 1);
    });

    test('사업장 drilldown에 byBusiness를 넘긴다', () {
      final block = _rowBlock(rows, '중간정산 요청', '계약 미발송');
      expect(block.contains('sec.byBusiness.where((b) => b.count > 0)'), isTrue);
    });
  });

  group('AHV2-02A-05 급여 변경 요청 row 표시', () {
    test('row가 canonical summary를 source로 쓴다', () {
      expect(rows.contains("label: '급여 변경 요청'"), isTrue);
      expect(rows.contains('cs?.actions.wageChangeRequest'), isTrue);
    });
  });

  group('AHV2-02A-06 급여 변경 destination 정밀도', () {
    test('변경요청 탭(2)으로 진입한다 — 급여 첫 화면 아님', () {
      final block = _rowBlock(rows, '급여 변경 요청', '중간정산 요청');
      expect(block.contains('_toPayrollTabDrilldown('), isTrue);
      expect(block.contains('tab: 2'), isTrue);
      expect(block.contains('showPendingSettlementOnly'), isFalse,
          reason: '변경요청 탭에는 정산 필터를 넘기지 않는다');
    });

    test('대시보드 탭 순서가 그대로다', () {
      final dash = _src(
          'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart');
      final t2 = dash.indexOf("label: '변경요청'");
      final t3 = dash.indexOf("label: '중간정산'");
      expect(t2, isNot(-1));
      expect(t3, greaterThan(t2), reason: '변경요청(2) → 중간정산(3) 순서');
    });
  });

  group('AHV2-02A-07 canManageWage 게이트', () {
    test('두 row 모두 canManageWage로 게이트된다', () {
      for (final pair in [
        ['급여 변경 요청', '중간정산 요청'],
        ['중간정산 요청', '계약 미발송'],
      ]) {
        final at = rows.indexOf("label: '${pair[0]}'");
        final before = rows.substring(0, at);
        final gate = before.lastIndexOf('if (!isSub || up.can(');
        expect(gate, isNot(-1));
        expect(before.substring(gate).contains('canManageWage'), isTrue,
            reason: '${pair[0]} 가 canManageWage 게이트 아래 있어야 한다');
      }
    });

    test('권한 확대가 없다', () {
      // row 블록은 다음 row의 권한 게이트 직전까지만 본다.
      for (final label in ['급여 변경 요청', '중간정산 요청']) {
        final at = rows.indexOf("label: '$label'");
        final nextGate = rows.indexOf('if (!isSub || up.can(', at);
        final block =
            nextGate == -1 ? rows.substring(at) : rows.substring(at, nextGate);
        expect(block.contains('canManageWorkers'), isFalse);
        expect(block.contains('canManageTo'), isFalse);
        expect(block.contains('canManageContract'), isFalse);
      }
    });

    test('서버도 canManageWage로 집계한다', () {
      final cf = _codeOf(_src(_indexPath));
      expect(cf.contains('wageChangeRequest: aggSimple("canManageWage"'), isTrue);
      expect(cf.contains('settlementRequest: aggSimple("canManageWage"'), isTrue);
    });

    test('목적지 헬퍼도 자체 권한 검증을 유지한다', () {
      final helper = _bodyOf(home, 'Future<void> _toPayrollTabDrilldown(');
      expect(helper.contains("up.can((p) => p.canManageWage)"), isTrue);
      expect(helper.contains('급여 관리 권한이 없습니다'), isTrue);
    });
  });

  group('AHV2-02A-08 알림 비의존', () {
    test('두 row 어디에도 notification 참조가 없다', () {
      for (final pair in [
        ['급여 변경 요청', '중간정산 요청'],
        ['중간정산 요청', '계약 미발송'],
      ]) {
        final block = _rowBlock(rows, pair[0], pair[1]);
        expect(block.contains('otification'), isFalse);
      }
    });

    test('_makeActionRows 전체가 canonical summary만 읽는다', () {
      expect(rows.contains('otification'), isFalse);
      expect(rows.contains('cs?.actions.'), isTrue);
    });
  });

  group('AHV2-02A-09 기존 row 회귀', () {
    test('기존 5종이 그대로 있다', () {
      for (final label in [
        '지원 검토', '마감 필요', '계약 미발송', '계약 종료 예정', '이체 대기',
      ]) {
        expect(rows.contains("label: '$label'"), isTrue);
      }
    });

    test('기존 row의 permission이 그대로다', () {
      expect(rows.contains('cs?.actions.approval'), isTrue);
      expect(rows.contains('cs?.actions.unclosed'), isTrue);
      expect(rows.contains('cs?.actions.unsentContract'), isTrue);
      expect(rows.contains('cs?.upcoming.expiringContract'), isTrue);
      expect(rows.contains('cs?.actions.unpaidWage'), isTrue);
    });

    test('기존 row 상대 순서가 바뀌지 않았다 — 삽입만 했다', () {
      final order = ['지원 검토', '마감 필요', '계약 미발송', '계약 종료 예정', '이체 대기'];
      var prev = -1;
      for (final label in order) {
        final at = rows.indexOf("label: '$label'");
        expect(at, greaterThan(prev), reason: '$label 순서가 바뀌었다');
        prev = at;
      }
    });

    test('신규 2종은 마감 필요와 계약 미발송 사이에 들어갔다', () {
      final unclosed = rows.indexOf("label: '마감 필요'");
      final wage = rows.indexOf("label: '급여 변경 요청'");
      final settle = rows.indexOf("label: '중간정산 요청'");
      final unsent = rows.indexOf("label: '계약 미발송'");
      expect(wage, greaterThan(unclosed));
      expect(settle, greaterThan(wage));
      expect(unsent, greaterThan(settle));
    });

    test('이체 대기의 전체기간 뷰 파라미터가 유지된다', () {
      final block = _rowBlock(rows, '이체 대기', 'ZZZ_NO_SUCH_LABEL');
      expect(block.contains('showAllOutstanding: true'), isTrue);
      expect(block.contains('tab: 0'), isTrue);
    });
  });

  group('AH-V2-02A 완료 후 갱신', () {
    test('목적지 pop 시 canonical summary를 재조회한다', () {
      final helper = _bodyOf(home, 'Future<void> _toPayrollTabDrilldown(');
      expect(helper.contains('route.popped.then('), isTrue);
      expect(helper.contains('_loadCanonicalSummary()'), isTrue);
    });

    test('새 global listener를 만들지 않았다', () {
      expect(home.contains('addListener(_onSettlement'), isFalse);
      expect(home.contains('StreamSubscription'), isFalse);
    });
  });

  group('AH-V2-02A 범위 제한', () {
    test('계약해지 row는 아직 없다', () {
      // 퇴사 요청은 AH-V2-02B, 스케줄 변경 요청은 AH-V2-02C에서 추가됐다.
      // 이 Phase의 범위 경계가 그만큼 옮겨졌다.
      expect(rows.contains('계약해지'), isFalse);
    });

    test('새 카드·섹션을 만들지 않았다', () {
      final body = _bodyOf(home, 'Widget build(');
      final order = [
        '_buildHeader(',
        '_buildStateBanner(',
        '_buildPostingSetupCard(',
        '_buildTodayOps(',
        '_buildFutureStaffing(',
        '_buildActionDashboard(',
      ];
      var prev = -1;
      for (final m in order) {
        final at = body.indexOf(m);
        expect(at, greaterThan(prev), reason: '$m 순서가 바뀌었다');
        prev = at;
      }
      final titles = RegExp(r"_sectionHeader\(context, s, '([^']+)'\)")
          .allMatches(home)
          .map((m) => m.group(1))
          .toSet();
      expect(titles, {'오늘 운영', '다가오는 인력 부족', '처리할 일'},
          reason: '섹션이 늘거나 줄지 않았다');
    });

    // [AH-V2-03 갱신] 향후 7일 empty copy는 두 상태로 분리됐다.
    // AH-V2-02A가 staffing을 건드리지 않았다는 사실은 유효하다.
    test('staffing·empty copy는 AH-V2-03 계약을 따른다', () {
      expect(home.contains('향후 7일 예정된 인력 운영이 없어요'), isTrue);
      expect(home.contains('향후 7일 인원이 모두 충원됐어요'), isTrue);
      expect(home.contains('처리할 업무가 없어요'), isTrue);
      expect(home.contains('인력 정보를 불러오지 못했습니다'), isTrue);
    });

    test('AH-V2-01의 ERROR≠ZERO 배선이 유지된다', () {
      expect(home.contains('getBusinessesByIdsOrThrow('), isTrue);
      final att = _bodyOf(home, 'Future<void> _loadTodayAttendance(');
      expect(att.contains('_todayCheckedIn      = null'), isTrue);
    });
  });
}
