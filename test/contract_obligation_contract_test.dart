// [PREDEVICE] 계약 의무는 좌석으로 판정한다
//
// Application commitment state ≠ Contract lifecycle state.
//
// READ에서 확인된 것:
//   · 홈의 "계약 미발송"과 계약 관리 화면 미발송 탭이 각자 따로
//     `status == "CONTRACT_PENDING"`을 셌다.
//   · callableAcceptTOInvitation은 INVITED → CONFIRMED로 바로 간다.
//     그래서 초대를 수락한 근로자는 계약서 없이 확정되고도 두 화면 어디에도
//     나타나지 않았다. 서명 CF는 이미 CONFIRMED를 받아들이고 있었으므로
//     막혀 있던 것은 실행이 아니라 발견이었다.
//   · 계약서 linking은 2단계(applicationId, applicationIds array-contains)인데
//     두 화면은 1단계만 봤다. 번들 2차 지원서는 계약서가 있어도 미발송이 된다.
//   · D-0 자동연장이 snapshot 없는 계약서를 미리 만들어, 새 판정이 그것을
//     "발송됨"으로 오인할 수 있었다.
//   · 그리고 홈 쿼리는 orderBy("createdAt")로 페이징했는데 applications에는
//     createdAt이 없다. Firestore는 정렬 필드가 없는 문서를 빼므로 이 카운트는
//     available:true인 채 언제나 0이었다.
//
// 계약:
//   정책은 srvNeedsContractIssue 한 곳에 있고, 두 화면이 그것을 쓴다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnsPath = 'functions/src/index.ts';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _sliceOf(String source, String decl, {String end = '\nexport '}) {
  final start = source.indexOf(decl);
  if (start < 0) throw StateError('$decl 을 찾지 못함');
  final next = source.indexOf(end, start + decl.length);
  return source.substring(start, next == -1 ? source.length : next);
}

void main() {
  final fns = _src(_fnsPath);
  final code = _codeOf(fns);
  final flat = _flat(code);

  group('정책은 한 곳에만 있다', () {
    test('srvNeedsContractIssue canonical helper가 존재한다', () {
      expect(flat.contains('async function srvNeedsContractIssue('), true);
      expect(flat.contains('async function srvContractIssuedFor('), true);
      expect(flat.contains('function srvContractNotIssuedYet('), true);
    });

    test('홈과 계약 관리 화면이 모두 같은 helper를 호출한다', () {
      expect('srvNeedsContractIssue('.allMatches(flat).length >= 3, true,
          reason: '선언 1 + 소비자 2(홈, 미발송 탭) 이상이어야 한다');

      final home = _flat(_codeOf(
          _sliceOf(fns, 'async function srvHomeUnsentContract(')));
      expect(home.contains('srvNeedsContractIssue('), true,
          reason: '홈이 자체 판정 사본을 들고 있으면 두 화면이 다른 숫자를 말한다');

      final tab = _flat(_codeOf(_sliceOf(
          fns, 'export const callableGetUnsentApplicationsByBiz = onCall(')));
      expect(tab.contains('srvNeedsContractIssue('), true,
          reason: '미발송 탭도 같은 helper를 써야 한다');
    });

    test('어느 쪽도 CONTRACT_PENDING 단독 조건을 쓰지 않는다', () {
      for (final decl in [
        'async function srvHomeUnsentContract(',
        'export const callableGetUnsentApplicationsByBiz = onCall(',
      ]) {
        final body = _flat(_codeOf(_sliceOf(fns, decl)));
        expect(
          body.contains('"status", "==", "CONTRACT_PENDING"'),
          false,
          reason: '$decl 이 CONTRACT_PENDING만 세면 초대 수락자를 놓친다',
        );
        expect(body.contains('"status", "in", CONTRACT_SEAT_STATUSES'), true,
            reason: '$decl 은 좌석 상태 전체를 봐야 한다');
      }
    });

    test('좌석 정의가 서명 CF의 허용 상태와 같다', () {
      expect(
        flat.contains(
          'const CONTRACT_SEAT_STATUSES = ["CONTRACT_PENDING", "CONFIRMED"];',
        ),
        true,
      );
      // 발견 대상과 실행 가능 대상이 어긋나면 누를 수 없는 CTA가 생긴다.
      expect(
        flat.contains('["CONFIRMED", "CONTRACT_PENDING"].includes('),
        true,
        reason: 'callableFinalizeEmployerSignature의 허용 집합이 바뀌었다',
      );
    });
  });

  group('계약서 linking은 2단계다', () {
    test('srvContractIssuedFor가 applicationIds array-contains까지 본다', () {
      final body =
          _flat(_codeOf(_sliceOf(fns, 'async function srvContractIssuedFor(')));
      expect(body.contains('"applicationId", "==", appId'), true);
      expect(body.contains('"applicationIds", "array-contains", appId'), true,
          reason: '번들 2차 지원서는 applicationIds에만 들어 있다');
      expect(body.contains('"businessId", "==", bizId'), true,
          reason: '타 사업장 계약서로 의무가 상쇄되면 안 된다');
    });

    test('pending_employer는 발송으로 치지 않는다', () {
      final body = _flat(
          _codeOf(_sliceOf(fns, 'function srvContractNotIssuedYet(')));
      for (final s in ['voided', 'pending_employer', 'draft']) {
        expect(body.contains('status === "$s"'), true,
            reason: '$s 는 아직 근로자에게 전달되지 않은 상태다');
      }
      expect(body.contains('pending_worker'), false,
          reason: 'pending_worker는 이미 전달됐으므로 미발송이 아니다');
    });
  });

  group('의무가 아닌 좌석은 제외한다', () {
    test('반납된 좌석과 종료된 고용관계는 제외', () {
      final body =
          _flat(_codeOf(_sliceOf(fns, 'async function srvNeedsContractIssue(')));
      expect(body.contains('appData["staffingReleasedAt"] != null'), true,
          reason: 'NO_SHOW 대체충원으로 반납된 자리는 발송 대상이 아니다');
      expect(body.contains('CONTRACT_ENDED_STATUSES.includes(term)'), true);
      expect(body.contains('CONTRACT_ENDED_STATUSES.includes(resign)'), true);
      expect(
        flat.contains(
          'const CONTRACT_ENDED_STATUSES = ["APPROVED", "AUTO_APPROVED"];',
        ),
        true,
      );
    });
  });

  group('판정을 왜곡하던 두 원인이 제거됐다', () {
    test('D-0 자동연장은 더 이상 계약서 문서를 미리 만들지 않는다', () {
      expect(flat.contains('status: "pending_employer", createdAt: now,'), false,
          reason: 'parse 불가 고아 계약서가 다시 생기면 "발송됨"으로 오판된다');
      expect(code.contains('newContractRef'), false,
          reason: '고아 writer의 ref 선언도 남기지 않는다');
    });

    test('홈 카운트가 없는 필드로 정렬하지 않는다', () {
      final home =
          _flat(_codeOf(_sliceOf(fns, 'async function srvHomeUnsentContract(')));
      expect(home.contains('orderBy("createdAt"'), false,
          reason: 'applications에는 createdAt이 없어 결과가 통째로 비었다');
      expect(home.contains('.limit(PAGE_SIZE)') && home.contains('startAfter'),
          true,
          reason: '전수 보장을 위한 페이징 자체는 유지돼야 한다');
      expect(home.contains('throw new Error('), true,
          reason: '상한 초과 시 거짓 count 대신 오류를 내는 계약은 유지된다');
    });
  });
}
