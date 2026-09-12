import 'dart:io';

import 'package:ALfit/models/core/schedule_change_request_model.dart';
import 'package:ALfit/models/ui/admin_home_summary_model.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// AH-V2-02C SCHEDULE-CHANGE-REQUEST-HOME-ENTRY
//
// schedule_change_requests.status == "PENDING" 은 canonical state지만
// 관리자 발견 경로가 알림뿐이었다.
//
// 이 업무의 특징은 '방향'이다.
//   requestedBy == APPLICANT → 관리자가 응답해야 한다 (처리할 일)
//   requestedBy == ADMIN     → 근로자 응답 대기 (처리할 일 아님)
// 방향을 섞으면 Home이 "내가 기다리는 것"을 "내가 처리할 것"으로 표시한다.
//
// 서버를 붙이지 않고 실행할 수 없으므로 DTO·enum은 값으로,
// 쿼리·배선은 소스 단정으로 고정한다.
// ═══════════════════════════════════════════════════════════════

const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _indexPath = 'functions/src/index.ts';
const _indexesJson = 'firestore.indexes.json';

String _src(String path) => File(path).readAsStringSync();

String _codeOf(String body) => body
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

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

/// 최상위 함수 본문 — 반환 타입에 중괄호가 있는 경우용
String _fnBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: '$signature 를 찾지 못함');
  final end = source.indexOf('\n}', start);
  expect(end, isNot(-1), reason: '$signature 의 끝을 찾지 못함');
  return source.substring(start, end + 2);
}

String _rowBlock(String rows, String label) {
  final at = rows.indexOf("label: '$label'");
  expect(at, isNot(-1), reason: "'$label' row를 찾지 못함");
  final next = rows.indexOf('if (!isSub || up.can(', at);
  return next == -1 ? rows.substring(at) : rows.substring(at, next);
}

void main() {
  late String home;
  late String rows;
  late String cf;

  setUpAll(() {
    home = _codeOf(_src(_homePath));
    rows = _bodyOf(home, '_makeActionRows(BuildContext context');
    cf = _codeOf(_src(_indexPath));
  });

  // ───────────────────────────────────────────────────────────
  group('AHV2-02C-01 PENDING + APPLICANT만 count', () {
    test('쿼리가 세 조건을 모두 포함한다', () {
      final helper = _fnBody(cf, 'async function srvHomeScheduleChangeRequest(');
      expect(helper.contains('.where("businessId", "==", bizId)'), isTrue);
      expect(helper.contains('.where("status", "==", "PENDING")'), isTrue);
      expect(helper.contains('.where("requestedBy", "==", "APPLICANT")'), isTrue);
    });

    test('DTO가 count를 파싱한다', () {
      final sec = AdminHomeSimpleSection.fromMap(
          {'available': true, 'count': 4, 'byBusiness': []});
      expect(sec.count, 4);
      expect(sec.hasData, isTrue);
    });
  });

  group('AHV2-02C-02 ADMIN 발신은 제외', () {
    test('방향 필터가 쿼리에 있다 — 메모리 필터 아님', () {
      final helper = _fnBody(cf, 'async function srvHomeScheduleChangeRequest(');
      expect(helper.contains('"APPLICANT"'), isTrue);
      expect(helper.contains('"ADMIN"'), isFalse);
      expect(helper.contains('.docs'), isFalse,
          reason: 'PENDING 전체를 받아 거르면 문서 fetch가 발생한다');
      expect(helper.contains('.filter('), isFalse);
    });

    test('요청자 타입이 두 가지뿐이다', () {
      expect(RequesterType.values.map((e) => e.name).toSet(),
          {'APPLICANT', 'ADMIN'});
    });
  });

  group('AHV2-02C-11 ADMIN 발신 유형이 Home에 없다', () {
    test('NO_WORK / EXTRA_WORK는 ADMIN 발신이다', () {
      // 모델 주석이 방향을 정의한다 — 서버 필터는 requestedBy를 쓴다
      final model = _src('lib/models/core/schedule_change_request_model.dart');
      expect(model.contains('NO_WORK,      // 관리자 → 지원자'), isTrue);
      expect(model.contains('EXTRA_WORK,   // 관리자 → 지원자'), isTrue);
    });

    test('LEAVE / CANCEL_LEAVE / CANCEL_EXTRA는 APPLICANT 발신이다', () {
      final model = _src('lib/models/core/schedule_change_request_model.dart');
      expect(model.contains('LEAVE,        // 지원자 → 관리자'), isTrue);
      expect(model.contains('CANCEL_LEAVE,    // 지원자 → 관리자'), isTrue);
      expect(model.contains('CANCEL_EXTRA,    // 지원자 → 관리자'), isTrue);
    });

    test('서버가 type이 아니라 requestedBy로 거른다', () {
      final helper = _fnBody(cf, 'async function srvHomeScheduleChangeRequest(');
      for (final t in ['LEAVE', 'NO_WORK', 'EXTRA_WORK', 'CANCEL_LEAVE']) {
        expect(helper.contains('"$t"'), isFalse,
            reason: 'type 열거로 추론하지 않고 canonical 방향 필드를 쓴다');
      }
    });

    test('요청 유형이 5종 그대로다', () {
      expect(RequestType.values.map((e) => e.name).toSet(),
          {'LEAVE', 'NO_WORK', 'EXTRA_WORK', 'CANCEL_LEAVE', 'CANCEL_EXTRA'});
    });
  });

  group('AHV2-02C-03 처리된 상태 제외', () {
    test('APPROVED / REJECTED / CANCELED를 세지 않는다', () {
      final helper = _fnBody(cf, 'async function srvHomeScheduleChangeRequest(');
      for (final s in ['APPROVED', 'REJECTED', 'CANCELED']) {
        expect(helper.contains('"$s"'), isFalse);
      }
    });

    test('상태 값이 모델과 일치한다', () {
      expect(RequestStatus.values.map((e) => e.name).toSet(),
          {'PENDING', 'APPROVED', 'REJECTED', 'CANCELED'});
    });
  });

  group('AHV2-02C-04 canManageWorkers 게이트', () {
    test('서버가 canManageWorkers로 집계한다', () {
      expect(
        cf.contains('scheduleChangeRequest: aggSimple("canManageWorkers"'),
        isTrue,
      );
      expect(cf.contains('canWork  ? srvHomeScheduleChangeRequest(bizId)'), isTrue);
    });

    test('클라이언트 row도 같은 게이트 아래 있다', () {
      final at = rows.indexOf("label: '스케줄 변경 요청'");
      final gate = rows.substring(0, at).lastIndexOf('if (!isSub || up.can(');
      expect(rows.substring(gate, at).contains('canManageWorkers'), isTrue);
    });

    test('탭 시점에도 재확인한다', () {
      final block = _rowBlock(rows, '스케줄 변경 요청');
      expect(block.contains("up.can((p) => p.canManageWorkers)"), isTrue);
      expect(block.contains('근로자 관리 권한이 없습니다'), isTrue);
    });

    test('승인 callable과 같은 권한 축이다', () {
      final approve =
          _bodyOf(cf, 'export const callableApproveScheduleChangeRequest = onCall(');
      expect(approve.contains('canManageWorkers'), isTrue);
    });

    test('권한 확대가 없다', () {
      final block = _rowBlock(rows, '스케줄 변경 요청');
      expect(block.contains('canManageWage'), isFalse);
      expect(block.contains('canManageTo'), isFalse);
      expect(block.contains('canManageContract'), isFalse);
    });
  });

  group('AHV2-02C-05 알림 비의존', () {
    test('row가 notification을 참조하지 않는다', () {
      final block = _rowBlock(rows, '스케줄 변경 요청');
      expect(block.contains('otification'), isFalse);
    });

    test('서버 헬퍼도 notification을 보지 않는다', () {
      final helper = _fnBody(cf, 'async function srvHomeScheduleChangeRequest(');
      expect(helper.contains('notification'), isFalse);
      expect(helper.contains('collection("schedule_change_requests")'), isTrue);
    });
  });

  group('AHV2-02C-06 ERROR != ZERO', () {
    test('응답이 없으면 available:false, hasData:false', () {
      final sec = AdminHomeSimpleSection.fromMap({});
      expect(sec.available, isFalse);
      expect(sec.count, 0);
      expect(sec.hasData, isFalse);
    });

    test('row가 기존 조회 실패 semantics를 쓴다', () {
      final block = _rowBlock(rows, '스케줄 변경 요청');
      expect(block.contains('available: sched?.available ?? false'), isTrue);
      expect(block.contains('_showCanonicalError(context)'), isTrue);
    });

    test('실패 사업장이 있으면 available이 false다', () {
      expect(cf.contains('available: permCount > 0 && successCount === permCount'),
          isTrue);
    });
  });

  group('AHV2-02C-07 multi-business scope', () {
    test('서버 scope model을 그대로 쓴다', () {
      final block = _rowBlock(rows, '스케줄 변경 요청');
      expect(block.contains('sec.byBusiness'), isTrue);
      expect(block.contains('managedBusinessIds'), isFalse);
    });

    test('byBusiness가 유지된다', () {
      final sec = AdminHomeSimpleSection.fromMap({
        'available': true,
        'count': 3,
        'byBusiness': [
          {'businessId': 'b1', 'count': 2},
          {'businessId': 'b2', 'count': 1},
        ],
      });
      expect(sec.byBusiness.length, 2);
    });

    test('여러 사업장이면 선택 시트를 거친다', () {
      final block = _rowBlock(rows, '스케줄 변경 요청');
      expect(block.contains('_pickBizFromSummary('), isTrue);
    });
  });

  group('AHV2-02C-08 기존 처리 UI 정밀 진입', () {
    test('ScheduleRequestManagementDialog로 진입한다', () {
      final block = _rowBlock(rows, '스케줄 변경 요청');
      expect(block.contains('ScheduleRequestManagementDialog('), isTrue);
      expect(block.contains('businessId: bizId'), isTrue);
    });

    test('다이얼로그가 businessId만 받고 목록을 자체 조회한다', () {
      final dlg = _src(
          'lib/screens/business_admin/dialogs/schedule_request_management_dialog.dart');
      expect(dlg.contains('final String businessId;'), isTrue);
      expect(dlg.contains('getAllScheduleChangeRequests('), isTrue);
    });

    test('다이얼로그도 APPLICANT 발신만 보여준다', () {
      final dlg = _src(
          'lib/screens/business_admin/dialogs/schedule_request_management_dialog.dart');
      expect(dlg.contains('r.requestedBy == RequesterType.APPLICANT'), isTrue,
          reason: 'Home count와 목록 내용이 같은 방향이어야 한다');
      expect(dlg.contains("_selectedFilter = 'PENDING'"), isTrue);
    });

    test('새 Request Center를 만들지 않았다', () {
      expect(home.contains('RequestCenter'), isFalse);
      expect(
        File('lib/screens/business_admin/schedule_request_center_screen.dart')
            .existsSync(),
        isFalse,
      );
    });
  });

  group('AHV2-02C-09 처리 후 Home 갱신', () {
    test('다이얼로그 닫힌 뒤 canonical summary를 재조회한다', () {
      final block = _rowBlock(rows, '스케줄 변경 요청');
      final dlgAt = block.indexOf('ScheduleRequestManagementDialog(');
      final reloadAt = block.indexOf('_loadCanonicalSummary()');
      expect(reloadAt, greaterThan(dlgAt));
      expect(block.contains('await showDialog<void>('), isTrue);
    });

    test('새 listener·stream을 만들지 않았다', () {
      expect(home.contains('StreamSubscription'), isFalse);
      expect(home.contains('addListener(_onSchedule'), isFalse);
    });
  });

  group('AHV2-02C-10 서버 중복 처리 차단', () {
    test('승인 callable이 PENDING을 재검증한다', () {
      final approve =
          _bodyOf(cf, 'export const callableApproveScheduleChangeRequest = onCall(');
      expect(approve.contains('!== "PENDING"'), isTrue);
      expect(approve.contains('이미 처리된 요청입니다'), isTrue);
    });

    test('트랜잭션 안에서 fresh 상태를 다시 본다', () {
      final approve =
          _bodyOf(cf, 'export const callableApproveScheduleChangeRequest = onCall(');
      expect(approve.contains('freshSnap.data()!.status'), isTrue);
    });
  });

  group('AH-V2-02C 우선순위·인덱스·비용', () {
    test('스케줄 변경이 중간정산 뒤, 계약 미발송 앞이다', () {
      final settle = rows.indexOf("label: '중간정산 요청'");
      final sched = rows.indexOf("label: '스케줄 변경 요청'");
      final unsent = rows.indexOf("label: '계약 미발송'");
      expect(sched, greaterThan(settle));
      expect(unsent, greaterThan(sched));
    });

    test('필요한 복합 인덱스를 추가했다', () {
      final idx = _src(_indexesJson).replaceAll(RegExp(r'\s+'), ' ');
      expect(
        idx.contains('"collectionGroup": "schedule_change_requests", '
            '"queryScope": "COLLECTION", "fields": [ '
            '{ "fieldPath": "businessId", "order": "ASCENDING" }, '
            '{ "fieldPath": "requestedBy", "order": "ASCENDING" }, '
            '{ "fieldPath": "status", "order": "ASCENDING" } ]'),
        isTrue,
      );
    });

    test('인덱스 JSON이 유효하다', () {
      expect(() => _src(_indexesJson), returnsNormally);
      final idx = _src(_indexesJson);
      expect(idx.trim().startsWith('{'), isTrue);
      expect(idx.trim().endsWith('}'), isTrue);
    });

    test('사업장당 count() 1회 — 문서 fetch 없음', () {
      final helper = _fnBody(cf, 'async function srvHomeScheduleChangeRequest(');
      expect('.count()'.allMatches(helper).length, 1);
      expect(helper.contains('.docs'), isFalse);
    });
  });

  group('AH-V2-02C 기존 row 회귀', () {
    test('기존 8종이 그대로다', () {
      for (final label in [
        '퇴사 요청', '지원 검토', '마감 필요', '급여 변경 요청', '중간정산 요청',
        '계약 미발송', '계약 종료 예정', '이체 대기',
      ]) {
        expect(rows.contains("label: '$label'"), isTrue);
      }
    });

    test('기존 row 상대 순서가 유지된다', () {
      final order = [
        '퇴사 요청', '지원 검토', '마감 필요', '급여 변경 요청', '중간정산 요청',
        '계약 미발송', '계약 종료 예정', '이체 대기',
      ];
      var prev = -1;
      for (final label in order) {
        final at = rows.indexOf("label: '$label'");
        expect(at, greaterThan(prev), reason: '$label 순서가 바뀌었다');
        prev = at;
      }
    });

    test('기존 summary 키가 전부 남아 있다', () {
      for (final key in [
        'approval:', 'unsentContract:', 'unpaidWage:', 'unclosed:',
        'wageChangeRequest:', 'settlementRequest:', 'resignRequest:',
        'expiringContract:',
      ]) {
        expect(cf.contains(key), isTrue);
      }
    });

    test('퇴사 요청의 soonCount 배지가 유지된다', () {
      final block = _rowBlock(rows, '퇴사 요청');
      expect(block.contains("'내일 자동 승인 \$soon건'"), isTrue);
    });
  });

  group('AH-V2-02C 범위 제한', () {
    test('계약해지 요청을 구현하지 않았다', () {
      expect(rows.contains('계약해지'), isFalse);
      expect(cf.contains('srvHomeTerminationRequest'), isFalse);
    });

    test('Home 섹션 구성이 그대로다', () {
      final titles = RegExp(r"_sectionHeader\(context, s, '([^']+)'\)")
          .allMatches(home)
          .map((m) => m.group(1))
          .toSet();
      expect(titles, {'오늘 운영', '다가오는 인력 부족', '처리할 일'});
    });

    test('staffing·empty copy를 건드리지 않았다', () {
      expect(home.contains('향후 7일 인원 충원 완료'), isTrue);
      expect(home.contains('처리할 업무가 없어요'), isTrue);
    });

    test('AH-V2-01의 ERROR≠ZERO 배선이 유지된다', () {
      expect(home.contains('getBusinessesByIdsOrThrow('), isTrue);
    });
  });
}
