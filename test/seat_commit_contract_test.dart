// [SYSTEM-INTEGRATION-R2.1] Canonical Seat Commit — 세 writer의 한 계약
//
// 자리를 확보하는 사건은 세 곳에서 일어난다.
//
//   callableApproveApplicationForReview   PENDING → CONTRACT_PENDING   (지원 검토)
//   callableConfirmApplication            PENDING → CONTRACT_PENDING   (지원현황·상세)
//   callableAcceptTOInvitation            INVITED → CONFIRMED          (초대 수락)
//
// 진입 화면이 다를 뿐 같은 사건인데 계약이 갈려 있었다:
//   · 겹침 계약이 callableConfirmApplication에만 있었다.
//     → 지원 검토 승인·초대 수락은 그 근로자의 겹치는 다른 관심 상태를 남겼고,
//       같은 시간에 두 곳과 약속이 성립할 수 있었다.
//   · 겹치는 관계를 접어도 그 자리의 workDetailCounts.pendingCount를 돌려주지
//     않았다. 이 카운터는 syncTOStats가 재계산하지 않으므로 오차가 영구였다.
//
// DEV 실측 (수정 후):
//   지원 경로  승인 → A confirmed+1, 겹치는 B AUTO_CANCELED, B pending 0
//   초대 경로  수락 → 동일
//   race       남은 자리 1에 두 명 수락 → 한 명만 성공, confirmed 2, 진 쪽은 INVITED 유지
//   mixed-date 9/21 FULL / 9/22 부족2 → 9/22가 사라지지 않음
//
// 또한 R2 보고의 BLOCKER-3("confirmApplication이 정원 초과를 허용")은 **사실이
// 아니었다.** 세 writer 모두 트랜잭션 안에서 정원을 막는다. DEV에 배포돼 있던
// callableApproveApplicationForReview가 정원 가드 이전 빌드(revision 00001,
// 9/02)였을 뿐이다. 실측: 3/3 상태에서 두 writer 모두
// `정원이 초과되었습니다`로 거부.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _after(String source, String signature, [int chars = 2000]) {
  final a = source.indexOf(signature);
  if (a == -1) throw StateError('$signature 를 찾지 못함');
  final end = a + chars;
  return source.substring(a, end > source.length ? source.length : end);
}

/// callable 하나의 본문 — 다음 `\n);` 까지.
String _callableBodyOf(String source, String name) {
  final a = source.indexOf('export const $name = onCall(');
  if (a == -1) throw StateError('$name 을 찾지 못함');
  final b = source.indexOf('\n);', a);
  if (b == -1) throw StateError('$name 본문 끝을 찾지 못함');
  return source.substring(a, b);
}

String _tsSliceOf(String source, String from, String to) {
  final a = source.indexOf(from);
  if (a == -1) throw StateError('$from 를 찾지 못함');
  final b = source.indexOf(to, a + from.length);
  if (b == -1) throw StateError('$to 를 찾지 못함');
  return source.substring(a, b);
}

const _cfPath = 'functions/src/index.ts';
const _appSvcPath = 'lib/services/firestore/application_firestore.dart';

void main() {
  final cf = _codeOf(_src(_cfPath));

  // ═════════════════════════════════════════════════════════════
  // 1. 공통 계약이 한 벌로 존재한다
  // ═════════════════════════════════════════════════════════════
  group('R2.1-01 canonical Seat Commit helper', () {
    final helper = _tsSliceOf(cf, 'async function srvCollectSeatCommitOverlap',
        'export const callableReportLate');

    test('01-a 수집(읽기)과 적용(쓰기)이 분리돼 있다', () {
      // Firestore 트랜잭션은 모든 읽기가 모든 쓰기보다 앞서야 한다.
      expect(cf.contains('async function srvCollectSeatCommitOverlap'), isTrue);
      expect(cf.contains('function srvApplySeatCommitOverlap'), isTrue);
    });

    test('01-b 겹치는 CONFIRMED/CONTRACT_PENDING은 차단', () {
      expect(
        helper.contains('.where("status", "in", ["CONFIRMED", "CONTRACT_PENDING"])'),
        isTrue,
      );
      expect(helper.contains('이미 확정된 근무가 있습니다'), isTrue);
    });

    test('01-c 겹치는 PENDING과 INVITED를 함께 정리 대상으로 본다', () {
      // INVITED를 빼면 약속이 선 뒤에도 수락할 수 없는 초대가 살아남는다.
      expect(
        helper.contains('.where("status", "in", ["PENDING", "INVITED"])'),
        isTrue,
      );
    });

    test('01-d 자기 자신은 제외한다', () {
      final n = RegExp(r'if \(\w+\.id === applicationId\) continue;')
          .allMatches(helper).length;
      expect(n, greaterThanOrEqualTo(2),
          reason: '차단 루프와 수집 루프 양쪽에서 identity를 제외해야 한다');
    });

    test('01-e 시간 겹침 판정 규칙은 하나만 쓴다', () {
      expect(helper.contains('_isConflictLongTerm'), isTrue);
      expect(helper.contains('_isConflictShortTerm'), isTrue);
      // 자체 시간 비교를 새로 만들지 않았다
      expect(helper.contains('startTime <'), isFalse);
    });

    test('01-f AUTO_CANCELED에 맥락을 남긴다', () {
      final apply = _tsSliceOf(cf, 'function srvApplySeatCommitOverlap',
          'export const callableReportLate');
      for (final f in [
        '"AUTO_CANCELED"', 'cancelReason: "SCHEDULE_CONFLICT"',
        'conflictingAppId', 'conflictingBusiness', 'conflictingTime',
      ]) {
        expect(apply.contains(f), isTrue, reason: '$f 누락');
      }
    });

    test('01-g 접힌 자리의 canonical pending counter를 돌려준다', () {
      final apply = _tsSliceOf(cf, 'function srvApplySeatCommitOverlap',
          'export const callableReportLate');
      expect(
        apply.contains('`workDetailCounts.\${cWdId}.pendingCount`'),
        isTrue,
      );
      // slot/TO 집계는 syncTOStats가 절대값으로 다시 쓴다 — 여기서 또 줄이면 음수가 스친다
      expect(apply.contains('pendingCount: admin.firestore.FieldValue.increment(-1)'),
          isFalse);
      expect(apply.contains('totalPending'), isFalse);
    });

    test('01-h reliability 패널티를 매기지 않는다', () {
      final apply = _tsSliceOf(cf, 'function srvApplySeatCommitOverlap',
          'export const callableReportLate');
      for (final f in ['trustScore', 'noShowCount', 'recentNoShowCount', 'penalty']) {
        expect(apply.contains(f), isFalse, reason: '$f — 자동취소는 근로자의 선택이 아니다');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 2. 세 writer가 그 한 벌을 쓴다
  // ═════════════════════════════════════════════════════════════
  group('R2.1-02 three-writer convergence', () {
    // [CROSS-DOMAIN-R5.3E.2] 이전에는 호출 수를 3으로 고정했다.
    //   그 숫자는 "모든 seat-commit writer가 같은 계약을 쓴다"의 대리값이었고,
    //   writer가 정당하게 늘면(확정 재배치 수락) 계약은 그대로인데 테스트만
    //   깨졌다. 세는 대신 **이름을 대고** 확인한다 — 빠뜨린 writer는 여전히
    //   잡히고, 새 writer를 더할 때는 여기에 이름을 추가하게 된다.
    const seatCommitWriters = [
      'callableApproveApplicationForReview',
      'callableConfirmApplication',
      'callableAcceptTOInvitation',
      'callableAcceptConfirmedReassignment',
    ];

    test('02-a 모든 seat-commit writer가 수집 helper를 호출한다', () {
      for (final w in seatCommitWriters) {
        expect(_callableBodyOf(cf, w).contains('srvCollectSeatCommitOverlap(tx, {'),
            isTrue,
            reason: '$w 가 겹침 수집을 건너뛰면 그 경로에서만 겹침이 남는다');
      }
    });

    test('02-b 모든 seat-commit writer가 적용 helper를 호출한다', () {
      for (final w in seatCommitWriters) {
        expect(_callableBodyOf(cf, w).contains('srvApplySeatCommitOverlap(tx,'),
            isTrue, reason: w);
      }
    });

    test('02-c 지원 검토 승인에 겹침 계약이 들어갔다', () {
      final fn = _tsSliceOf(cf, 'export const callableApproveApplicationForReview',
          'export const callableGetMonthlyReviewsByBiz');
      expect(fn.contains('srvCollectSeatCommitOverlap'), isTrue);
      expect(fn.contains('srvApplySeatCommitOverlap'), isTrue);
    });

    test('02-d 초대 수락에 겹침 계약이 들어갔다', () {
      final fn = _tsSliceOf(cf, 'export const callableAcceptTOInvitation',
          'export const callableDeclineTOInvitation');
      expect(fn.contains('srvCollectSeatCommitOverlap'), isTrue);
      expect(fn.contains('srvApplySeatCommitOverlap'), isTrue);
    });

    test('02-e confirmApplication이 자기 사본을 갖고 있지 않다', () {
      final fn = _tsSliceOf(cf, 'export const callableConfirmApplication',
          'export const callableBatchAdminConfirm');
      expect(fn.contains('srvCollectSeatCommitOverlap'), isTrue);
      // 인라인 판정이 남아 있으면 규칙이 두 벌이 되어 다시 갈라진다
      expect(fn.contains('const pendingToCancel'), isFalse);
      expect(fn.contains('confirmedSnap.docs'), isFalse);
    });

    test('02-f 세 writer 모두 트랜잭션 안에서 정원을 막는다', () {
      // 경고 후 허용(overbooking)은 제품에 없다.
      for (final entry in {
        'export const callableApproveApplicationForReview':
            'export const callableGetMonthlyReviewsByBiz',
        'export const callableConfirmApplication':
            'export const callableBatchAdminConfirm',
      }.entries) {
        final fn = _tsSliceOf(cf, entry.key, entry.value);
        expect(fn.contains('정원이 초과되었습니다'), isTrue, reason: entry.key);
      }
      final accept = _tsSliceOf(cf, 'export const callableAcceptTOInvitation',
          'export const callableDeclineTOInvitation');
      expect(accept.contains('정원이 초과되었습니다'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 3. counter drift
  // ═════════════════════════════════════════════════════════════
  group('R2.1-03 pending counter cleanup', () {
    test('03-a 초대 만료가 canonical pending counter를 돌려준다', () {
      final fn = _tsSliceOf(cf, 'export const callableExpireApplications',
          'export const callableCancelResignRequest');
      expect(fn.contains('`workDetailCounts.\${exWdId}.pendingCount`'), isTrue);
      expect(fn.contains('increment(-1)'), isTrue);
    });

    test('03-b 초대 철회도 같은 자리만 되돌린다', () {
      final fn = _tsSliceOf(cf, 'export const callableCancelTOInvitation',
          'export const callableCancelApprovedInterimSettlement');
      expect(fn.contains('`workDetailCounts.\${cancelWdId}.pendingCount`'), isTrue);
    });

    test('03-c batch 한도를 넘지 않도록 쓰기 수를 센다', () {
      final fn = _tsSliceOf(cf, 'export const callableExpireApplications',
          'export const callableCancelResignRequest');
      // 문서 1건당 최대 2 write이므로 499가 아니라 여유를 둔 값이어야 한다
      expect(fn.contains('count >= 498'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 4. notification idempotency
  // ═════════════════════════════════════════════════════════════
  group('R2.1-04 notification idempotency', () {
    test('04-a 확정 알림이 결정적 id + create()', () {
      final fn = _tsSliceOf(cf, 'export const callableConfirmApplication',
          'export const callableBatchAdminConfirm');
      expect(fn.contains('`application_confirmed_\${applicationId}`'), isTrue);
      expect(fn.contains('.create({'), isTrue);
      // ALREADY_EXISTS(6)는 정상
      expect(fn.contains('?.code !== 6'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 5. over-capacity 카피
  // ═════════════════════════════════════════════════════════════
  group('R2.1-05 capacity copy', () {
    test('05-a 정원이 찬 것을 "초과 확정"이라고 말하지 않는다', () {
      final code = _codeOf(_src(_appSvcPath));
      final body = _after(code, 'final capacityWarning =', 700);
      expect(body.contains('초과 확정됩니다'), isFalse,
          reason: '서버는 초과를 막는다 — 이 신호는 마지막 자리가 찼다는 뜻이다');
      expect(body.contains('모두 찼습니다'), isTrue);
    });
  });
}
