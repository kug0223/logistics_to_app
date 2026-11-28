import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/users_create_rule.dart';

// ═══════════════════════════════════════════════════════════════
// [POSTING-QUOTA-42] 공고 한도·서브관리자 권한 — 소스 계약
//
// 실제 동작 증거는 LOCAL 에뮬레이터 하네스(서버 SDK + firestore.rules)에 있다
// (REPORT-POSTING-QUOTA-AND-SUBADMIN-AUTHORITY.42 §4). 이 시험은 그 수정이
// 소스에서 빠지지 않도록 위치만 고정한다.
//
//   PQ-1 rules: 본인·가입 문서가 maxActiveTOs 를 쓰지 못한다(한도 자가 상향 차단).
//   PQ-2 앱 2차 방어 목록도 같은 필드를 뺀다(rules denylist 와 동기화 계약).
//   PQ-3 서버: 생성·공개·재개·편집 트랜잭션이 권한을 다시 판정한다.
//   PQ-4 서버: 일반 편집이 공고를 새로 한도 집계에 넣으면 같은 한도를 본다.
//   PQ-5 화면: 한도·권한 거절을 '수정/등록에 실패했습니다'로 뭉개지 않는다.
// ═══════════════════════════════════════════════════════════════

const _rulesPath = 'firestore.rules';
const _userFsPath = 'lib/services/firestore/user_firestore.dart';
const _fnPath = 'functions/src/index.ts';
const _editPath = 'lib/screens/business_admin/to_management/edit_to_screen.dart';
const _createPath =
    'lib/screens/business_admin/to_management/create_to_screen.dart';

String _src(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// `//` 주석 줄 제거 — 주석 안의 문자열이 코드로 오탐되는 것을 막는다.
String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// `export const NAME = onCall(` 부터 다음 최상위 export 직전까지.
String _exportBody(String src, String name) {
  final start = src.indexOf('export const $name = ');
  if (start == -1) throw StateError('$name 를 찾지 못함');
  final next = src.indexOf('\nexport const ', start + 10);
  return src.substring(start, next == -1 ? src.length : next);
}

void main() {
  group('PQ-1 rules — 한도 필드는 슈퍼관리자(callable)만 쓴다', () {
    final rules = _codeOf(_src(_rulesPath));

    test('PQ-1a 본인 수정 denylist 에 maxActiveTOs 가 있다', () {
      final i = rules.indexOf("'managedBusinessIds',");
      expect(i, greaterThan(0));
      final window = rules.substring(i, i + 400);
      expect(window.contains("'maxActiveTOs',"), true,
          reason: '본인이 maxActiveTOs 를 쓰면 서버 한도 판정이 그 값을 그대로 쓴다');
    });

    test('PQ-1b 가입(create) 문서는 maxActiveTOs 를 null 로만 가진다', () {
      // [ALFIT-AUTH-KAKAO-ONBOARDING.1 갱신] users create 전면 거부(판정278 C278-3) — 가입 문서에 maxActiveTOs 를 심을 수 없다(더 강함).
      //   다시 열리면 옛 null 조건을 요구한다.
      expect(
          usersCreateClosed(rules) ||
              rules.contains(
                  "request.resource.data.get('maxActiveTOs', null) == null &&"),
          true);
    });
  });

  test('PQ-2 앱 2차 방어 목록이 rules 와 같이 maxActiveTOs 를 뺀다', () {
    final code = _codeOf(_src(_userFsPath));
    final i = code.indexOf('static const _protectedUserFields = {');
    final j = code.indexOf('};', i);
    expect(code.substring(i, j).contains("'maxActiveTOs',"), true);
  });

  group('PQ-3 서버 — 권한을 저장 트랜잭션 안에서 사업장 관계로 판정한다', () {
    final fn = _src(_fnPath);

    test('PQ-3a 헬퍼는 역할이 아니라 소유자·adminIds·배정·canManageTo 로 본다', () {
      final i = fn.indexOf('async function srvAssertPostingAuthorityInTx(');
      expect(i, greaterThan(0));
      final body = fn.substring(i, fn.indexOf('\n}\n', i));
      expect(body.contains('tx.get(bizRef.collection("members").doc(callerUid))'),
          true);
      expect(body.contains('biz?.ownerId === callerUid || adminIds.includes(callerUid)'),
          true);
      expect(body.contains('perms.canManageTo !== true'), true);
      expect(body.contains('"BUSINESS_ADMIN"'), false,
          reason: 'BUSINESS_ADMIN 역할이라는 이유로 건너뛰면 다른 소유자 사업장 배정이 권한을 우회한다');
    });

    test('PQ-3b 생성(즉시·비공개)·공개·재개·편집 트랜잭션이 모두 부른다', () {
      final create = _exportBody(fn, 'callableCreateTO');
      expect(
          'await srvAssertPostingAuthorityInTx(tx, callerUid, businessId)'
              .allMatches(create)
              .length,
          2);
      expect(
          _exportBody(fn, 'callablePublishTO')
              .contains('await srvAssertPostingAuthorityInTx(tx, callerUid, businessId)'),
          true);
      final update = _exportBody(fn, 'callableUpdateTO');
      expect(update.contains('await srvAssertPostingAuthorityInTx(txReopen, callerUid,'),
          true);
      expect(update.contains('await srvAssertPostingAuthorityInTx(txEdit, callerUid,'),
          true);
    });
  });

  test('PQ-4 서버 — 일반 편집이 새로 집계에 넣으면 같은 트랜잭션에서 한도를 본다', () {
    final update = _exportBody(_src(_fnPath), 'callableUpdateTO');
    final guard = update.indexOf('!srvCountsTowardPostingQuota(freshData, nowMsEdit)');
    final write = update.indexOf('txEdit.update(toRef, {...finalUpdates');
    expect(guard, greaterThan(0));
    expect(write, greaterThan(guard), reason: '판정은 쓰기 전에 있어야 한다');
    final block = update.substring(guard, write);
    expect(block.contains('resolvePostingCapacityContextTx(txEdit,'), true);
    expect(block.contains('getEffectiveActivePostingCountTx(txEdit,'), true);
    expect(block.contains('MAX_ACTIVE_TO_LIMIT:'), true);
    expect(block.contains('finalUpdates.postingCapacityScopeKey = editScopeKey'), true);
  });

  test('PQ-6 SA 메뉴 설명이 한도 단위를 사업장이 아닌 관리자 계정으로 말한다', () {
    final s = _codeOf(_src('lib/screens/super_admin/system_settings_screen.dart'));
    expect(s.contains("subtitle: '관리자 계정당 동시 진행 공고 최대 개수'"), true);
    expect(s.contains('사업장 당 동시 진행 공고'), false,
        reason: '한도 화면·서버는 계정의 모든 사업장 합계다(Pixel_5 .42 관찰)');
  });

  group('PQ-5 화면 — 한도·권한 거절을 구분한다', () {
    test('PQ-5a 수정 화면: resource-exhausted(한도)·permission-denied(권한) 문구', () {
      final edit = _codeOf(_src(_editPath));
      final i = edit.indexOf('String? _cfErrorMessage(Object e) {');
      final body = edit.substring(i, edit.indexOf('\n  }\n', i));
      // 한도는 CF 예외(편집·재개)와 서비스가 바꾼 Exception(공개) 두 모양으로 온다 — 타입을 가리지 않는다.
      final limitAt = body.indexOf("raw.contains('MAX_ACTIVE_TO_LIMIT')");
      expect(limitAt, greaterThan(0));
      expect(limitAt, lessThan(body.indexOf('if (e is FirebaseFunctionsException)')),
          reason: 'FirebaseFunctionsException 분기 안에 두면 Exception(MAX_ACTIVE_TO_LIMIT) 이 빠진다');
      expect(body.contains("'진행 중인 공고가 \$limitStr개를 초과할 수 없습니다'"), true);
      expect(body.contains("e.code == 'permission-denied'"), true);
      // 저장 뒤 첫 공개 분기: 권한 거절을 '잠시 후 다시 시도'로 말하지 않는다
      final pub = edit.indexOf('await _firestoreService.publishTO(widget.to.id);');
      final pubCatch = edit.substring(pub, edit.indexOf('return;', pub));
      expect(pubCatch.contains("e.code == 'permission-denied'"), true);
      // 호출부 모양은 그대로(기존 계약: `_cfErrorMessage(e) ?? '수정에 실패했습니다'`)
      expect("_cfErrorMessage(e) ?? '수정에 실패했습니다'".allMatches(edit).length, 3);
    });

    test('PQ-5b 등록 화면: permission-denied 를 일반 실패와 나눈다', () {
      final create = _codeOf(_src(_createPath));
      final p = create.indexOf("e.code == 'permission-denied'");
      final g = create.indexOf("ToastHelper.showError('공고 등록에 실패했습니다');",
          create.indexOf('debugPrint(\'❌ TO 생성 실패: \$e\');'));
      expect(p, greaterThan(0));
      expect(p, lessThan(g), reason: '권한 분기가 일반 실패보다 먼저 판정된다');
    });
  });
}
