import 'dart:io';

import 'package:ALfit/models/ui/admin_home_summary_model.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// AH-V2-02B RESIGN-REQUEST-HOME-ENTRY
//
// 퇴사 요청은 canonical state(applications.resignStatus == "PENDING")가
// 있는데 관리자 발견 경로가 알림뿐이었다.
//
// 다른 Home task와 결정적으로 다른 점:
//   방치하면 D+3에 masterScheduler가 AUTO_APPROVED로 확정한다.
//   즉 "결정하지 않은 것"과 "못 본 것"이 같은 결과를 낸다.
//
// 서버를 붙이지 않고 실행할 수 없으므로 DTO 파싱은 값으로,
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

/// 최상위 함수 본문 — 시그니처부터 컬럼 0의 닫는 중괄호까지.
/// 반환 타입에 `Promise<{...}>` 처럼 중괄호가 있으면 _bodyOf가 오인하므로
/// 최상위 함수에는 이 쪽을 쓴다.
String _fnBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: '$signature 를 찾지 못함');
  final end = source.indexOf('\n}', start);
  expect(end, isNot(-1), reason: '$signature 의 끝을 찾지 못함');
  return source.substring(start, end + 2);
}

/// row 블록 — 다음 권한 게이트 직전까지
String _rowBlock(String rows, String label) {
  final at = rows.indexOf("label: '$label'");
  expect(at, isNot(-1), reason: "'$label' row를 찾지 못함");
  final next = rows.indexOf('if (_verified(up, (p) => p.', at);
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
  group('AHV2-02B-01 PENDING만 count에 포함', () {
    test('서버가 resignStatus == PENDING으로만 센다', () {
      final helper = _fnBody(cf, 'async function srvHomeResignRequest(');
      expect(helper.contains('.where("resignStatus", "==", "PENDING")'), isTrue);
      expect(helper.contains('.where("businessId", "==", bizId)'), isTrue);
    });

    test('DTO가 count를 파싱한다', () {
      final sec = AdminHomeResignRequestSection.fromMap(
          {'available': true, 'count': 3, 'soonCount': 1, 'byBusiness': []});
      expect(sec.count, 3);
      expect(sec.available, isTrue);
      expect(sec.hasData, isTrue);
    });
  });

  group('AHV2-02B-02 처리된 상태는 제외', () {
    test('APPROVED / AUTO_APPROVED / REJECTED를 세지 않는다', () {
      final helper = _fnBody(cf, 'async function srvHomeResignRequest(');
      for (final s in ['APPROVED', 'AUTO_APPROVED', 'REJECTED']) {
        expect(helper.contains('"$s"'), isFalse,
            reason: '$s 를 쿼리 조건으로 쓰면 안 된다');
      }
    });

    test('자동 승인된 건은 PENDING이 아니므로 자연히 빠진다', () {
      // 스케줄러가 resignStatus를 AUTO_APPROVED로 바꾼다
      expect(cf.contains('resignStatus: "AUTO_APPROVED"'), isTrue);
    });
  });

  group('AHV2-02B-03 canManageWorkers 게이트', () {
    test('서버가 canManageWorkers로 집계한다', () {
      expect(cf.contains('aggSimple("canManageWorkers"'), isTrue);
      expect(cf.contains('canWork  ? srvHomeResignRequest('), isTrue);
    });

    test('권한 없는 SubAdmin은 헬퍼 자체를 호출하지 않는다', () {
      expect(cf.contains('perms["canManageWorkers"] === true'), isTrue);
    });

    test('클라이언트 row도 canManageWorkers 아래 있다', () {
      final at = rows.indexOf("label: '퇴사 요청'");
      final gate = rows.substring(0, at).lastIndexOf('if (_verified(up, (p) => p.');
      expect(rows.substring(gate, at).contains('canManageWorkers'), isTrue);
    });

    test('탭 시점에도 권한을 재확인한다', () {
      final block = _rowBlock(rows, '퇴사 요청');
      expect(block.contains("_verified(up, (p) => p.canManageWorkers)"), isTrue);
      expect(block.contains('근로자 관리 권한이 없습니다'), isTrue);
    });

    test('승인 callable과 같은 권한 축이다', () {
      // callableApproveResignation도 canManageWorkers를 요구한다
      final approve = _bodyOf(cf, 'export const callableApproveResignation = onCall(');
      expect(approve.contains('canManageWorkers'), isTrue);
    });
  });

  group('AHV2-02B-04 multi-business scope', () {
    test('서버 scope model을 그대로 쓴다 — 클라이언트 재계산 없음', () {
      final block = _rowBlock(rows, '퇴사 요청');
      expect(block.contains('sec.byBusiness'), isTrue);
      expect(block.contains('managedBusinessIds'), isFalse);
    });

    test('byBusiness가 유지된다', () {
      final sec = AdminHomeResignRequestSection.fromMap({
        'available': true,
        'count': 5,
        'soonCount': 2,
        'byBusiness': [
          {'businessId': 'b1', 'count': 3},
          {'businessId': 'b2', 'count': 2},
        ],
      });
      expect(sec.byBusiness.length, 2);
      expect(sec.byBusiness.first.businessId, 'b1');
    });

    test('여러 사업장이면 선택 시트를 거친다', () {
      final block = _rowBlock(rows, '퇴사 요청');
      expect(block.contains('_pickBizFromSummary('), isTrue);
    });
  });

  group('AHV2-02B-05 알림 비의존', () {
    test('row가 notification을 참조하지 않는다', () {
      final block = _rowBlock(rows, '퇴사 요청');
      expect(block.contains('otification'), isFalse);
    });

    test('서버 헬퍼도 notification을 보지 않는다', () {
      final helper = _fnBody(cf, 'async function srvHomeResignRequest(');
      expect(helper.contains('notification'), isFalse);
      expect(helper.contains('collection("applications")'), isTrue);
    });
  });

  group('AHV2-02B-06 ERROR != ZERO', () {
    test('available이 false면 0건으로 표시하지 않는다', () {
      final sec = AdminHomeResignRequestSection.fromMap({});
      expect(sec.available, isFalse);
      expect(sec.count, 0);
      expect(sec.hasData, isFalse, reason: '실패를 "처리할 일 없음"으로 읽으면 안 된다');
    });

    test('row가 기존 조회 실패 semantics를 쓴다', () {
      final block = _rowBlock(rows, '퇴사 요청');
      expect(block.contains('available: resign?.available ?? false'), isTrue);
      expect(block.contains('_showCanonicalError(context)'), isTrue);
    });

    test('실패 사업장이 있으면 available이 false가 된다', () {
      // aggSimple: permCount > 0 && successCount === permCount
      expect(cf.contains('available: permCount > 0 && successCount === permCount'),
          isTrue);
    });

    test('noAccess 상수가 거짓 0을 만들지 않는다', () {
      expect(AdminHomeResignRequestSection.noAccess.available, isFalse);
      expect(AdminHomeResignRequestSection.noAccess.hasData, isFalse);
    });
  });

  group('AHV2-02B-07 자동 승인 기한이 스케줄러와 같은 기준', () {
    test('스케줄러는 resignRequestedAt + KST 자정 + 3일을 쓴다', () {
      expect(cf.contains('const threeDaysAgo = new Date(todayKST.getTime() - 3 * 24 * 60 * 60 * 1000)'),
          isTrue);
      expect(cf.contains('.where("resignRequestedAt", "<=", threeDaysAgoUTC)'), isTrue);
    });

    test('헬퍼가 같은 필드·같은 KST 자정 기준을 쓴다', () {
      final helper = _fnBody(cf, 'async function srvHomeResignRequest(');
      expect(helper.contains('"resignRequestedAt", "<="'), isTrue);
      expect(helper.contains('todayKSTMidnight.getTime() - 2 * 24 * 60 * 60 * 1000'),
          isTrue,
          reason: '스케줄러 −3일 경계보다 하루 앞선 −2일 = 내일 자동 승인 대상');
    });

    test('Home이 넘기는 기준값이 스케줄러와 동일 시점이다', () {
      expect(cf.contains('const todayKSTMidnight = srvHomeKSTMidnight()'), isTrue);
      expect(cf.contains('srvHomeResignRequest(bizId, todayKSTMidnight)'), isTrue);
    });

    test('임박 건수가 badge로 표현된다', () {
      final block = _rowBlock(rows, '퇴사 요청');
      expect(block.contains("'내일 자동 승인 \$soon건'"), isTrue);
      expect(block.contains('soon > 0'), isTrue);
    });

    test('soonCount를 DTO가 파싱한다', () {
      final sec = AdminHomeResignRequestSection.fromMap(
          {'available': true, 'count': 4, 'soonCount': 2});
      expect(sec.soonCount, 2);
    });
  });

  group('AHV2-02B-08 기존 처리 UI 재사용', () {
    test('ResignRequestManagementDialog로 진입한다', () {
      final block = _rowBlock(rows, '퇴사 요청');
      expect(block.contains('ResignRequestManagementDialog('), isTrue);
      expect(block.contains('businessId: bizId'), isTrue);
    });

    test('다이얼로그는 businessId만 받고 목록을 자체 조회한다', () {
      final dlg = _src(
          'lib/screens/business_admin/dialogs/resign_request_management_dialog.dart');
      expect(dlg.contains('final String businessId;'), isTrue);
      expect(dlg.contains('getResignRequests('), isTrue,
          reason: '단건 전용이 아니라 PENDING 목록 다이얼로그여야 Home에서 재사용 가능하다');
    });

    test('새 Request Center를 만들지 않았다', () {
      expect(File('lib/screens/business_admin/resign_request_center_screen.dart')
          .existsSync(), isFalse);
      expect(home.contains('RequestCenter'), isFalse);
    });

    test('알림 화면의 진입 계약을 바꾸지 않았다', () {
      final notif = _src('lib/screens/common/notification_screen.dart');
      expect(notif.contains('ResignRequestManagementDialog('), isTrue);
      expect(notif.contains('requiredPermission: (p) => p.canManageWorkers'), isTrue);
    });
  });

  group('AHV2-02B-09 처리 후 Home 갱신', () {
    test('다이얼로그 닫힌 뒤 canonical summary를 재조회한다', () {
      final block = _rowBlock(rows, '퇴사 요청');
      final dlgAt = block.indexOf('ResignRequestManagementDialog(');
      final reloadAt = block.indexOf('_loadCanonicalSummary()');
      expect(reloadAt, greaterThan(dlgAt));
      expect(block.contains('await showDialog<void>('), isTrue);
    });

    test('새 listener·stream을 만들지 않았다', () {
      expect(home.contains('StreamSubscription'), isFalse);
      expect(home.contains('addListener(_onResign'), isFalse);
    });
  });

  group('AHV2-02B-10 중복 처리 서버 차단', () {
    test('승인 callable이 PENDING을 재검증한다', () {
      final approve = _bodyOf(cf, 'export const callableApproveResignation = onCall(');
      expect(approve.contains('resignStatus !== "PENDING"'), isTrue);
      expect(approve.contains('failed-precondition'), isTrue);
    });

    test('거절 callable도 재검증한다', () {
      final reject = _bodyOf(cf, 'export const callableRejectResignation = onCall(');
      expect(reject.contains('resignStatus !== "PENDING"'), isTrue);
    });

    test('자동 승인 TX도 PENDING을 재확인한다', () {
      expect(cf.contains('snap.data()?.resignStatus !== "PENDING"'), isTrue);
    });
  });

  group('AH-V2-02B 우선순위·인덱스', () {
    test('퇴사 요청이 처리할 일 최상단이다', () {
      final resign = rows.indexOf("label: '퇴사 요청'");
      for (final label in [
        '지원 검토', '마감 필요', '급여 변경 요청', '중간정산 요청',
        '계약 미발송', '계약 종료 예정', '이체 대기',
      ]) {
        expect(rows.indexOf("label: '$label'"), greaterThan(resign),
            reason: '$label 보다 위에 있어야 한다');
      }
    });

    test('필요한 복합 인덱스가 이미 존재한다', () {
      // businessId + resignStatus + resignRequestedAt
      // count()는 이 인덱스의 prefix(businessId+resignStatus)로도,
      // soonCount의 범위 조건은 세 번째 필드로 충족된다.
      final idx = _src(_indexesJson)
          .replaceAll(RegExp(r'\s+'), ' '); // 공백·줄바꿈 정규화
      expect(
        idx.contains('"fieldPath": "businessId", "order": "ASCENDING" }, '
            '{ "fieldPath": "resignStatus", "order": "ASCENDING" }, '
            '{ "fieldPath": "resignRequestedAt"'),
        isTrue,
        reason: '기존 인덱스를 재사용한다 — 신규 추가 불필요',
      );
    });

    test('문서 전체 fetch 없이 count() aggregation을 쓴다', () {
      final helper = _fnBody(cf, 'async function srvHomeResignRequest(');
      expect(helper.contains('.count()'), isTrue);
      expect(helper.contains('.get()'), isTrue);
      expect(helper.contains('.docs'), isFalse, reason: '문서를 받아 세면 안 된다');
    });
  });

  group('AH-V2-02B 범위 제한', () {
    test('계약해지를 구현하지 않았다', () {
      // 스케줄 변경 요청은 AH-V2-02C에서 추가됐다 — 범위 경계가 옮겨졌다.
      expect(rows.contains('계약해지'), isFalse);
      expect(cf.contains('srvHomeTerminationRequest'), isFalse);
    });

    test('기존 7종 row가 그대로다', () {
      for (final label in [
        '지원 검토', '마감 필요', '급여 변경 요청', '중간정산 요청',
        '계약 미발송', '계약 종료 예정', '이체 대기',
      ]) {
        expect(rows.contains("label: '$label'"), isTrue);
      }
    });

    // [AH-V2-05B 갱신] 운영 urgency 기준으로 재정렬됐다.
    test('기존 row가 새 우선순위 순서를 따른다', () {
      final order = [
        '지원 검토', '계약 미발송', '마감 필요', '중간정산 요청',
        '급여 변경 요청', '이체 대기', '계약 종료 예정',
      ];
      var prev = -1;
      for (final label in order) {
        final at = rows.indexOf("label: '$label'");
        expect(at, greaterThan(prev), reason: '$label 순서가 바뀌었다');
        prev = at;
      }
    });

    test('Home 섹션 구성이 그대로다', () {
      final titles = RegExp(r"_sectionHeader\(context, s, '([^']+)'")
          .allMatches(home)
          .map((m) => m.group(1))
          .toSet();
      expect(titles, {'오늘', '다가오는 7일', '처리할 일'});
    });

    test('AH-V2-01의 ERROR≠ZERO 배선이 유지된다', () {
      expect(home.contains('getBusinessesByIdsOrThrow('), isTrue);
    });
  });
}
