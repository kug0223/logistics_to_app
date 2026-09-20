// [PII-B4-R1.4.1] 등록은 전역, 확인은 사업장별
//
// 이 파일이 고정하는 것:
//
//   INV-1  권한 격리와 확인 격리는 다른 것이다
//   INV-2  권한 있는 두 번째 사업장은 UNREVIEWED로 시작한다
//   INV-3  한 사업장의 확인이 다른 사업장으로 새지 않는다
//   INV-4  낡음 판정은 읽을 때 계산한다 (fan-out 아님)
//   INV-5  근로자는 사업장마다 다시 등록하지 않는다

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _sliceOf(String raw, String from, String to) {
  final a = raw.indexOf(from);
  if (a < 0) throw StateError('$from 를 찾지 못함');
  final b = raw.indexOf(to, a + from.length);
  if (b < 0) throw StateError('$to 를 찾지 못함');
  return raw.substring(a, b);
}

const _cfPath = 'functions/src/index.ts';

void main() {
  final cfRaw = _src(_cfPath);
  final cf = _codeOf(cfRaw);

  group('INV-1 — 권한과 확인은 다른 축이다 (§24)', () {
    test('01 권한 없는 사업장은 읽지도 못한다', () {
      final rv = _flat(_codeOf(_sliceOf(cfRaw,
          'export const callableGetTaxIdentityReview',
          'async function srvValidateKoreanTaxIdentifierOrThrow(')));
      expect(rv, contains('srvAssertTaxIdentityAuthority(callerUid, businessId)'));
      expect(rv, contains('srvHasBusinessWorkerRelationship(businessId, targetUid)'));
    });

    test('02 권한 판정이 사업장 소속을 본다', () {
      final a = _flat(_codeOf(_sliceOf(cfRaw,
          'async function srvAssertTaxIdentityAuthority(', '\n}')));
      // 소유자 / 관리자 / canManageWage 멤버.
      expect(a, contains('ownerId'));
      expect(a, contains('adminIds'));
      expect(a, contains('canManageWage'));
    });

    test('03 권한 거부와 미확인은 다른 응답이다', () {
      // 권한 없음 = throw, 미확인 = state 값. 하나로 뭉개지 않는다.
      expect(cf, contains('const TAX_REVIEW_UNREVIEWED = "UNREVIEWED";'));
      final a = _flat(_codeOf(_sliceOf(cfRaw,
          'async function srvAssertTaxIdentityAuthority(', '\n}')));
      expect(a, contains('permission-denied'));
      expect(a, isNot(contains('UNREVIEWED')));
    });
  });

  group('INV-2 — 두 번째 사업장은 UNREVIEWED로 시작한다 (§25)', () {
    final resolve = _flat(_codeOf(_sliceOf(cfRaw,
        'function srvResolveTaxIdentityReview(', '\n}')));

    test('04 검토 문서가 없으면 UNREVIEWED다', () {
      expect(resolve, contains('if (!decision)'));
      expect(resolve, contains('state: TAX_REVIEW_UNREVIEWED, valid: false'));
    });

    test('05 근무 이력으로 확인을 추정하지 않는다', () {
      // 과거에 일했다는 사실은 이 사업장이 봤다는 뜻이 아니다.
      expect(resolve, isNot(contains('applications')));
      expect(resolve, isNot(contains('attendance')));
    });

    test('06 세무 레코드가 전역이어도 확인은 아니다', () {
      // 지문은 전역 값이지만 decision은 사업장 문서에서 온다.
      expect(resolve, contains('review?.["taxIdentityDecision"]'));
      expect(resolve, contains('srvTaxIdentityFingerprint(userData, tax)'));
    });
  });

  group('INV-3 — 확인은 사업장 문서에 갇힌다 (§28)', () {
    test('07 검토 문서 id가 사업장×근로자다', () {
      final id = _flat(_codeOf(_sliceOf(cfRaw,
          'function srvBizReviewId(', '\n}')));
      expect(id, contains('businessId'));
      expect(id, contains('workerUid'));
    });

    test('08 읽기·쓰기가 모두 그 id를 쓴다', () {
      expect(cf, contains('.doc(srvBizReviewId(businessId, targetUid))'));
      // 전 사업장에 뿌리는 쓰기가 없다.
      expect(cf, isNot(contains('BIZ_DOC_REVIEW_COL).where("workerUid"')));
    });

    test('09 다른 축(지원자 서류 검토)을 건드리지 않는다', () {
      final sub = _flat(_codeOf(_sliceOf(cfRaw,
          'export const callableReviewTaxIdentity', 'correctionOpened')));
      expect(sub, contains('taxIdentityDecision: decision'));
      // 새 문서를 만들 때만 다른 축을 NOT_REVIEWED로 초기화한다.
      expect(sub, contains('if (!fr.exists)'));
      expect(sub, contains('patch["idDecision"] = REVIEW_NOT_REVIEWED'));
    });
  });

  group('INV-4 — 낡음은 읽을 때 계산한다 (§29)', () {
    final resolve = _flat(_codeOf(_sliceOf(cfRaw,
        'function srvResolveTaxIdentityReview(', '\n}')));

    test('10 저장된 버전·지문과 현재 값을 비교한다', () {
      expect(resolve, contains('rIdV !== curIdV || rFp !== curFp'));
      expect(resolve, contains('state: TAX_REVIEW_STALE'));
    });

    test('11 근로자 변경이 사업장 문서를 건드리지 않는다', () {
      // 세무 수정·복구 어디에도 검토 문서 쓰기가 없다.
      for (final fn in [
        'export const callableUpdateTaxIdentity',
        'export const callableRecoverForeignTaxIdentity',
      ]) {
        final body = _flat(_codeOf(_sliceOf(cfRaw, fn,
            'export const callableGet')));
        expect(body, isNot(contains('BIZ_DOC_REVIEW_COL')), reason: fn);
      }
    });

    test('12 신분증 재등록도 같은 방식이다', () {
      // idDocumentVersion만 올리고, 검토 문서는 그대로 둔다.
      final mark = _flat(_codeOf(_sliceOf(cfRaw,
          'idDocumentVersion: nextV,', 'return nextV;')));
      expect(mark, isNot(contains('taxIdentityDecision')));
      expect(mark, isNot(contains('BIZ_DOC_REVIEW_COL')));
    });
  });

  group('INV-5 — 등록은 전역, 재입력 없음 (§27·§46)', () {
    test('13 세무 레코드가 사업장과 무관하다', () {
      expect(cf, contains('db.collection(TAX_ID_COL).doc(uid)'));
      final set = _flat(_sliceOf(cfRaw, 'tx.set(ref, {\n        uid,', '});'));
      expect(set, isNot(contains('businessId')));
    });

    test('14 지원 게이트는 등록 여부만 본다', () {
      final block = _flat(_codeOf(_sliceOf(cfRaw,
          'async function srvTaxIdentityOnboardingBlock(', '\n}')));
      expect(block, contains('snap.exists'));
      // 사업장별 검토 결과를 지원 조건으로 쓰지 않는다(§52).
      expect(block, isNot(contains('REVIEWED_OK')));
      expect(block, isNot(contains('BIZ_DOC_REVIEW_COL')));
    });

    test('15 재사용 키가 사업장·근로자·버전·지문 넷이다', () {
      expect(cf, contains('reviewedTaxIdDocumentVersion: curIdV'));
      expect(cf, contains('reviewedTaxIdentityFingerprint: curFp'));
      expect(cf, contains('businessId, workerUid: targetUid'));
    });
  });
}
