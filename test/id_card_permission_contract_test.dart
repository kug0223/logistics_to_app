import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// DS-08A SUBADMIN-ID-CARD-GRANT-VISIBILITY-FIX
//
// 신분증 열람 권한 축은 canManageWage 하나다.
// 권한은 businesses/{bizId}/members/{uid}.permissions 하위에 저장된다.
//
// 세 callable이 같은 권한을 서로 다른 경로로 읽고 있었다.
//   callableGetIdCardSignedUrl      permissions.canManageWage   정상
//   callableCheckIdCardAccess       top-level canManageWage     오판
//   callableCheckIdCardAccessBatch  SubAdmin 분기 없음          누락
// 그 결과 canManageWage를 가진 SubAdmin이 유효한 auto-grant를 두고도
// UI에서 권한 없음으로 표시됐다.
//
// 이 테스트는 세 callable의 권한 판정 경로가 한 곳으로 정렬된 상태를 고정한다.
// 서버 동작 자체는 emulator 없이 실행할 수 없으므로 구조 수준 고정이다.
// ═══════════════════════════════════════════════════════════════

const _indexPath = 'functions/src/index.ts';

/// canonical 권한 경로. 세 callable이 모두 이 형태로 읽어야 한다.
const _canonicalRead = 'permissions?.canManageWage';

/// 잘못된 top-level 조회 형태 (DS-08A 이전 callableCheckIdCardAccess).
const _topLevelRead = 'memberSnap.data()?.canManageWage';

String _source() => File(_indexPath).readAsStringSync();

/// `export const <name> = onCall(` 부터 괄호 짝을 맞춰 callable 전체를 잘라낸다.
String _callableBody(String source, String name) {
  final start = source.indexOf('export const $name = onCall(');
  expect(start, isNot(-1), reason: '$name 을 찾지 못함');
  var depth = 0;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    final c = source[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  fail('$name 본문의 끝을 찾지 못함');
}

/// 주석 줄을 제거한 사본. 설명 주석이 배선 스캔에 잡히는 것을 막는다.
String _codeOf(String body) => body
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  late String source;
  late String signedUrl;
  late String singleCheck;
  late String batchCheck;

  setUpAll(() {
    source = _source();
    signedUrl = _codeOf(_callableBody(source, 'callableGetIdCardSignedUrl'));
    singleCheck = _codeOf(_callableBody(source, 'callableCheckIdCardAccess'));
    batchCheck = _codeOf(_callableBody(source, 'callableCheckIdCardAccessBatch'));
  });

  // ───────────────────────────────────────────────────────────
  // Case A — canManageWage 보유 SubAdmin은 sentinel 조회에 도달해야 한다
  // ───────────────────────────────────────────────────────────
  group('DS08A-01 SubAdmin + canManageWage → sentinel 조회 도달', () {
    test('단건 check가 canonical 권한 경로를 읽는다', () {
      expect(singleCheck.contains(_canonicalRead), isTrue);
    });

    test('단건 check에 top-level 오판 경로가 남아 있지 않다', () {
      expect(singleCheck.contains(_topLevelRead), isFalse,
          reason: 'members 문서에 top-level canManageWage는 존재하지 않는다');
    });

    test('단건 check가 SubAdmin 소속 목록에서 사업장을 모은다', () {
      expect(singleCheck.contains('subAdminBusinessIds'), isTrue);
      expect(singleCheck.contains('subAdminOf'), isTrue);
    });

    test('단건 check가 business sentinel을 조회한다', () {
      expect(singleCheck.contains(r'`business:${bizId}`'), isTrue);
    });

    test('Signed URL 발급도 같은 권한 경로를 쓴다 — 기준점', () {
      expect(signedUrl.contains(_canonicalRead), isTrue);
      expect(signedUrl.contains(_topLevelRead), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────
  // Case B — canManageWage 없으면 유효 grant가 있어도 막혀야 한다
  // ───────────────────────────────────────────────────────────
  group('DS08A-02 SubAdmin + canManageWage 없음 → 차단', () {
    test('단건 check는 권한 미통과 사업장을 건너뛴다', () {
      expect(singleCheck.contains('$_canonicalRead !== true) continue'), isTrue,
          reason: '권한 없는 사업장은 sentinel 조회 자체를 하지 않아야 한다');
    });

    test('batch는 권한 통과 사업장만 조회 목록에 넣는다', () {
      expect(batchCheck.contains('$_canonicalRead === true'), isTrue);
      expect(batchCheck.contains('sentinelBizIds.push('), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // Case C / D — 다른 권한으로 대체 불가
  // ───────────────────────────────────────────────────────────
  group('DS08A-03 canManageWorkers로 대체 금지', () {
    test('세 callable 어디에도 canManageWorkers 근거가 없다', () {
      expect(signedUrl.contains('canManageWorkers'), isFalse);
      expect(singleCheck.contains('canManageWorkers'), isFalse);
      expect(batchCheck.contains('canManageWorkers'), isFalse);
    });
  });

  group('DS08A-04 canManageTo로 대체 금지', () {
    test('세 callable 어디에도 canManageTo 근거가 없다', () {
      expect(signedUrl.contains('canManageTo'), isFalse);
      expect(singleCheck.contains('canManageTo'), isFalse);
      expect(batchCheck.contains('canManageTo'), isFalse);
    });

    test('신분증 권한 축은 canManageWage 하나뿐이다', () {
      for (final body in [signedUrl, singleCheck, batchCheck]) {
        final perms = RegExp(r'canManage[A-Za-z]+')
            .allMatches(body)
            .map((m) => m.group(0))
            .toSet();
        expect(perms.difference({'canManageWage'}), isEmpty);
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  // Case E — grant 유효성 정의는 그대로
  // ───────────────────────────────────────────────────────────
  group('DS08A-05 grant 유효성 정의 무변경', () {
    test('Signed URL은 approved + 미만료 grant만 인정한다', () {
      expect(signedUrl.contains('"status", "==", "approved"'), isTrue);
      expect(signedUrl.contains('"expiresAt", ">", now'), isTrue);
    });

    test('Signed URL은 respondedAt + 7일을 서버에서 재검증한다', () {
      expect(signedUrl.contains('7 * 24 * 60 * 60 * 1000'), isTrue);
    });

    test('단건 check의 만료 자동 전환이 남아 있다', () {
      expect(singleCheck.contains('"expired"'), isTrue);
    });

    test('batch의 active personal grant 판정이 남아 있다', () {
      expect(batchCheck.contains('nowSecBatch5'), isTrue);
      expect(batchCheck.contains("g.status === \"approved\""), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // Case F — batch가 단건과 같은 contract를 갖는다
  // ───────────────────────────────────────────────────────────
  group('DS08A-06 batch도 동일 permission contract', () {
    test('batch에 SubAdmin 분기가 존재한다', () {
      expect(batchCheck.contains('subAdminBusinessIds'), isTrue);
      expect(batchCheck.contains('subAdminOf'), isTrue);
    });

    test('batch가 canonical 권한 경로를 읽는다', () {
      expect(batchCheck.contains(_canonicalRead), isTrue);
    });

    test('batch가 권한 통과 사업장의 sentinel을 조회한다', () {
      expect(batchCheck.contains(r'`business:${sentinelBizId}`'), isTrue);
    });

    test('batch의 scope 검증(본인 요청만)은 유지된다', () {
      expect(batchCheck.contains('callerUid !== requesterId'), isTrue);
    });

    test('batch의 30개 청크 분할이 유지된다', () {
      expect(batchCheck.contains('i += 30'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // Case G — BUSINESS_ADMIN 경로 무변경
  // ───────────────────────────────────────────────────────────
  group('DS08A-07 BUSINESS_ADMIN 기존 동작 유지', () {
    test('세 callable 모두 users.businessId 단일 경로를 먼저 본다', () {
      for (final body in [signedUrl, singleCheck, batchCheck]) {
        expect(body.contains('callerDoc.data()?.businessId'), isTrue);
      }
    });

    test('BUSINESS_ADMIN sentinel 조회 형태가 유지된다', () {
      expect(signedUrl.contains(r'`business:${callerBusinessId}`'), isTrue);
      expect(singleCheck.contains(r'`business:${callerBusinessId}`'), isTrue);
      expect(batchCheck.contains('sentinelBizIds.push(callerBusinessId)'), isTrue);
    });

    test('SUPER_ADMIN 우회가 유지된다', () {
      expect(signedUrl.contains('SUPER_ADMIN'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // 범위 제한 — 이번 Phase에서 건드리지 않은 것들
  // ───────────────────────────────────────────────────────────
  group('DS08A 범위 제한', () {
    test('auto-grant 생성 로직이 그대로다', () {
      final confirm = _codeOf(_callableBody(source, 'callableConfirmApplication'));
      expect(confirm.contains(r'`auto_${applicationId}`'), isTrue);
      expect(confirm.contains('grantSource: "pre_consent"'), isTrue);
      expect(confirm.contains('status: "approved"'), isTrue);
    });

    test('7일 정책이 그대로다', () {
      final confirm = _codeOf(_callableBody(source, 'callableConfirmApplication'));
      expect(confirm.contains('7 * 24 * 60 * 60 * 1000'), isTrue);
    });

    test('통장사본 권한 로직은 건드리지 않았다', () {
      final bankbook =
          _codeOf(_callableBody(source, 'callableGetBankbookSignedUrl'));
      expect(bankbook.contains(_canonicalRead), isTrue);
      expect(bankbook.contains('canManageWage'), isTrue);
      expect(bankbook.contains('appStatus !== "CONFIRMED"'), isTrue);
      expect(bankbook.contains('documentAccessConsentGiven'), isTrue);
    });

    test('수동 요청 경로가 살아 있다', () {
      expect(source.contains('export const callableCreateIdCardAccessRequest'),
          isTrue);
      expect(source.contains('export const callableRespondIdCardAccessRequest'),
          isTrue);
    });

    test('권한 확대가 없다 — SubAdmin 판정은 canManageWage 통과 시에만 참', () {
      // 무조건 통과시키는 형태가 들어오지 않았는지 고정
      expect(singleCheck.contains('canManageWage !== false'), isFalse);
      expect(batchCheck.contains('canManageWage !== false'), isFalse);
      expect(batchCheck.contains('sentinelBizIds.push(...allBizIds)'), isFalse);
    });
  });
}
