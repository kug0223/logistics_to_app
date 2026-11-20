// [BUSINESS-ARCHIVE 2026-10-16] 사업장 종료 = 비활성화·보관, 직접 하드 삭제 차단
//
// 무엇이 잘못됐었나
//
//   사업장 목록의 '삭제' 메뉴가 사업장 문서를 앱에서 직접 지웠다. rules 는
//   소유자·SUPER_ADMIN 삭제를 허용했고, onBusinessDeleted 가 공고를 하드 삭제 →
//   onTODeleted 가 그 공고의 지원서 전부(확정·실근무 포함)를 지웠다. 중간정산·
//   급여 변경 요청도 함께 사라졌다.
//
//   공고 직접 삭제도 같았다. 직전 후보의 "구 앱 롤백 예외"는 rules 가 지원서를
//   볼 수 없어, 합계 0 이지만 거절·취소 이력이 있는 공고까지 허용했다(실제 연쇄로
//   이력 삭제 확인 — scripts/invite-delete-rules-runtime.js).
//
// 이 파일이 고정하는 것
//
//   BAR-0x  rules: businesses·tos·slots 직접 delete 는 false
//   BAR-1x  앱: 운영 종료는 callableArchiveOwnBusiness, 사업장 문서 직접 삭제 없음
//   BAR-2x  서버: 소유자만, 멱등, 기록은 지우지 않는다, 생성 실패는 서버 soft delete
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

/// `match /<path> {` 블록에서 delete 규칙 한 줄을 꺼낸다(주석 제외).
String _deleteRule(String rules, String matchHead) {
  final i = rules.indexOf(matchHead);
  expect(i, greaterThanOrEqualTo(0), reason: '$matchHead 블록이 없다');
  final lines = rules.substring(i).split('\n');
  for (final l in lines.skip(1)) {
    final t = l.trim();
    if (t.startsWith('match /')) break; // 하위 블록 전에 끝나야 한다
    if (t.startsWith('allow delete')) return t;
  }
  fail('$matchHead 에 allow delete 가 없다');
}

void main() {
  final rules = _read('firestore.rules');
  final list = _read('lib/screens/business_admin/business_list_screen.dart');
  final server = _read('functions/src/index.ts');

  group('BAR-0x rules 직접 삭제 차단', () {
    test('BAR-01 businesses 직접 delete 는 false', () {
      expect(_deleteRule(rules, 'match /businesses/{businessId} {'), 'allow delete: if false;');
    });
    test('BAR-02 tos 직접 delete 는 false(구 앱 롤백 예외 철회)', () {
      expect(_deleteRule(rules, 'match /tos/{toId} {'), 'allow delete: if false;');
      expect(rules.contains('srvOldAppRollbackTarget'), isFalse,
          reason: 'rules 는 과거 관계 부재를 증명할 수 없다 — 예외를 다시 열지 않는다');
    });
    test('BAR-03 slots 직접 delete 는 false', () {
      expect(_deleteRule(rules, 'match /slots/{slotId} {'), 'allow delete: if false;');
    });
  });

  group('BAR-1x 앱 운영 종료', () {
    test('BAR-11 메뉴는 운영 종료이고 서버 callable 로 간다', () {
      expect(list.contains("label: '운영 종료'"), isTrue);
      expect(list.contains("'callableArchiveOwnBusiness'"), isTrue);
      expect(list.contains('_deleteBusiness'), isFalse);
    });
    test('BAR-12 사업장 문서를 앱이 직접 지우지 않는다', () {
      expect(RegExp(r"collection\('businesses'\)[\s\S]{0,200}?\.delete\(\)").hasMatch(list), isFalse);
    });
    test('BAR-13 소유자만·이미 종료된 사업장엔 메뉴 없음', () {
      expect(list.contains('business.ownerId == context.read<UserProvider>().currentUser?.uid'), isTrue);
      expect(list.contains('!business.isDeactivated'), isTrue);
    });
    test('BAR-14 확인창은 기록 보존을 말한다', () {
      // [BUSINESS-ARCHIVE] 문구는 사전 조회 건수와 함께 만든다(archiveConfirmMessage).
      // [4단계] 확인 문구는 세 갈래 구조가 됐다 — 보존 문장은 마지막 줄에 있다.
      expect(list.contains('기록은 지워지지 않고, 급여 탭과 계약 관리에서 계속 처리할 수 있어요.'), isTrue); // [DU400 후보] 문구 계약 추종
    });
  });

  group('BAR-2x 서버', () {
    final i = server.indexOf('export const callableArchiveOwnBusiness');
    final body = server.substring(i, server.indexOf('\nexport const ', i + 10));
    test('BAR-21 소유자만, 멱등, 하드 삭제 없음', () {
      expect(i, greaterThanOrEqualTo(0));
      expect(body.contains('ownerId'), isTrue);
      expect(body.contains('alreadyArchived'), isTrue);
      expect(body.contains('isApproved: false'), isTrue);
      expect(RegExp(r'\.delete\(\)').hasMatch(body), isFalse);
      expect(RegExp(r'recursiveDelete').hasMatch(body), isFalse);
    });
    test('BAR-22 생성 실패 롤백은 서버 soft delete 이고 관계가 있으면 하지 않는다', () {
      final r = server.indexOf('async function srvRollbackFailedFlexCreate');
      expect(r, greaterThanOrEqualTo(0));
      final rb = server.substring(r, server.indexOf('\n}\n', r));
      expect(rb.contains('assertNoPostingRelations'), isTrue);
      expect(rb.contains('isDeleted: true'), isTrue);
      expect(rb.contains('CREATE_ROLLBACK'), isTrue);
      // 필드 제거(FieldValue.delete())는 문서 삭제가 아니다.
      expect(RegExp(r'(?<!FieldValue)\.delete\(\)').hasMatch(rb), isFalse);
    });
  });
}
