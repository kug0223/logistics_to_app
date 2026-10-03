// [R7-P4.4E.11A.3] 도메인 정리가 실패해도 성공이라 말했다
//
// 무엇이 잘못됐었나
//
//   `onBusinessDeleted` 의 Phase A 는 여러 정리 branch 를
//   `Promise.allSettled` 로 돌린다. 그건 의도다 — 한 branch 실패가 다른
//   정리를 막으면 안 된다. 문제는 **결과를 버렸다는 것**이다.
//
//     사업장 문서 삭제
//     → 지원서/계약/요청 정리 일부 실패
//     → allSettled 가 rejection 을 값으로 흡수
//     → 트리거 resolve
//     → retry:true 인데 재시도 없음
//
//   그러면 사업장은 사라졌는데 지원서는 확정 계열로 남고, 계약은
//   pending_worker 로 남고, 정산·리뷰 요청은 사용자에게 계속 행동을
//   요구한다. 같은 사건에 대한 business truth 가 갈라진다.
//
//   그리고 겉의 allSettled 만이 아니었다. `srvLifecycleCancelBulk` 는
//   트랜잭션 실패를 **"보존"으로 되돌려** 완전히 비가시였고(정상 보존과
//   구별 불가), 계약 IIFE 내부의 두 allSettled 도 로그만 남겼다.
//
// 이 파일이 고정하는 것
//
//   BDEL-DOM-0x  branch inventory 와 분류가 코드에 박혀 있다
//   BDEL-DOM-1x  required 실패는 최종 throw 이고, B·C 는 그래도 실행된다
//   BDEL-DOM-2x  skip 류는 throw 사유가 아니다
//   BDEL-DOM-3x  retry 전제와 멱등·이중적용 금지
//   BDEL-DOM-4x  Application·Attendance·Contract 의미 불변
//   BDEL-DOM-5x  세 축 동시 실패가 모두 사유에 들어온다
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

String _codeOf(String src) => src
    .split(RegExp(r'\r?\n'))
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

String _slice(String raw, String from, String to) {
  final a = raw.indexOf(from);
  if (a < 0) throw StateError('$from 를 찾지 못함');
  final b = raw.indexOf(to, a + from.length);
  if (b < 0) throw StateError('$to 를 찾지 못함');
  return raw.substring(a, b);
}

const _cfPath = 'functions/src/index.ts';

void main() {
  final raw = _src(_cfPath);
  final cf = _flat(_codeOf(raw));

  String hardDelete() => _flat(_codeOf(_slice(
      raw, 'export const onBusinessDeleted = onDocumentDeleted(', '\n// ═══')));
  String verdict() => _flat(_codeOf(_slice(
      raw, 'function srvBusinessCleanupVerdict(', '\n}')));
  String cancelBulk() => _flat(_codeOf(_slice(
      raw, 'async function srvLifecycleCancelBulk(', '\n}')));

  // ══════════════════════════════════════════════════════════════
  group('BDEL-DOM-0x branch inventory · classification (§1·§6)', () {
    test('BDEL-DOM-01 Phase-A 의 모든 allSettled 결과가 수집된다', () {
      final h = hardDelete();
      // 결과를 버리는 `await Promise.allSettled([` 호출이 하나도 없다.
      // (수집하는 형태는 `countDomain(... await Promise.allSettled` 또는
      //  `const settled = await Promise.allSettled` 다.)
      final bare = RegExp(r'(?<!= )await Promise\.allSettled\(\s*\[')
          .allMatches(h).length;
      expect(bare, 0, reason: '결과를 버리는 allSettled 가 남아 있다');
      // 세 수집 지점: 서브컬렉션 · TO slots · 이름 있는 도메인 branch
      expect(h, contains('countDomain("subcollection", await Promise.allSettled('));
      expect(h, contains('countDomain("to-slots", await Promise.allSettled('));
      expect(h, contains('const settled = await Promise.allSettled(domainNamed.map((b) => b.p));'));
    });

    test('BDEL-DOM-02 REQUIRED branch 이름이 고정돼 있다', () {
      final h = hardDelete();
      for (final name in [
        'schedule_change_requests',
        'employment_contracts',
        'monthly_reviews',
        'payment_change_requests',
        'interim_settlement_requests',
        'review_requests',
      ]) {
        expect(h, contains('name: "$name"'), reason: '$name branch 이름 누락');
      }
      // 서브컬렉션 세 개도 이름으로 돈다.
      expect(h, contains('const subColBranches = ["workTypes", "members", "contract_templates"];'));
    });

    test('BDEL-DOM-03 BEST_EFFORT 는 계약 Storage 정리 하나이고 이름을 남긴다', () {
      // `_cleanupContractFiles` 는 **자기 안에서** 파일별 실패를 삼키도록
      //   설계돼 있다(기존 주석이 그렇게 말한다). 그래서 이 allSettled 는
      //   애초에 reject 될 수 없고, 재시도도 계약 문서가 이미 지워져
      //   복구원이 없다 — required 로 올리면 영구 retry loop 가 된다.
      final helper = _flat(_codeOf(_slice(
          raw, 'async function _cleanupContractFiles(', '\n}')));
      expect(helper, contains('try {'));
      expect(helper, contains('console.warn('),
          reason: '파일별 실패를 helper 가 삼킨다 — 설계 명시');
      expect(helper, isNot(contains('throw')));
      // 그 사실이 주석으로 코드에 남아 있다.
      expect(raw, contains('파일별 실패는 경고만 — 전체 흐름 중단 않음'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BDEL-DOM-1x required 실패 → throw · B·C 계속 (§7·§19)', () {
    test('BDEL-DOM-10 required 실패가 최종 throw 사유다', () {
      expect(verdict(), contains('if (t.domainRequiredFailed > 0) {'));
      expect(verdict(), contains(r'parts.push(`domain=${t.domainRequiredFailed}`);'));
      expect(hardDelete(), contains('bizCleanup.domainRequiredFailed++;'));
    });

    test('BDEL-DOM-11·12 required 실패에도 mirror·Storage 가 실행된다', () {
      final h = hardDelete();
      final domainAt = h.indexOf('const settled = await Promise.allSettled(domainNamed.map((b) => b.p));');
      final mirrorAt = h.indexOf('const adminRes = await srvRemoveUserBusinessMirrors(');
      final storageAt = h.indexOf('const bucket = admin.storage().bucket();');
      final throwAt = h.indexOf('if (bizRetryReason !== null) { throw new Error(');
      expect(domainAt, greaterThan(0));
      expect(mirrorAt, greaterThan(domainAt), reason: 'A 실패 후 B 실행');
      expect(storageAt, greaterThan(mirrorAt), reason: 'B 후 C 실행');
      expect(throwAt, greaterThan(storageAt), reason: 'throw 는 맨 마지막');
    });

    test('BDEL-DOM-13 domain 집계 지점이 즉시 throw 하지 않는다', () {
      final h = hardDelete();
      // 집계 직후에 throw 가 붙어 있지 않다 — 사이에 B·C 가 들어간다.
      final idx = h.indexOf('bizCleanup.domainRequiredFailed++;');
      final tail = h.substring(idx, idx + 400);
      expect(tail, isNot(contains('throw ')));
    });

    test('BDEL-DOM-14 계약 IIFE 내부 실패가 branch reject 로 올라온다 (§17)', () {
      final h = hardDelete();
      expect(h, contains('let contractInnerFailed = 0;'));
      expect(h, contains('contractInnerFailed++;'),
          reason: 'pending_worker TX 실패를 센다');
      expect(h, contains('contractInnerFailed += indiv.filter((r) => r.status === "rejected").length;'),
          reason: 'historicalOwnerUid 개별 fallback 실패도 센다');
      expect(h, contains('if (contractInnerFailed > 0) { throw new Error('));
    });

    test('BDEL-DOM-15 지원서 판정 실패가 올라온다 (§17)', () {
      expect(cancelBulk(), contains('failed.push(d.id);'));
      expect(cancelBulk(), contains('return {canceled, preserved, skipped, failed};'));
      expect(hardDelete(),
          contains('bizCleanup.domainRequiredFailed += bizDelReport.failed.length;'));
    });

    test('BDEL-DOM-15n 실패 건은 preserved 보호에서 빼지 않는다', () {
      // 분류를 바꾸면 TO 삭제 호출자가 실근무 미확인 건을 강제 취소한다.
      final c = cancelBulk();
      final at = c.indexOf('failed.push(d.id);');
      expect(at, greaterThan(0));
      expect(c.substring(at, at + 80), contains('return "preserved"'),
          reason: 'failed 는 추가 신호일 뿐 — preserved 분류는 그대로다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BDEL-DOM-2x skip 류는 throw 사유가 아니다 (§9)', () {
    test('BDEL-DOM-20·21 missing user / foreign path 는 사유에서 제외', () {
      final v = verdict();
      expect(v, isNot(contains('missingSkipped')));
      expect(v, isNot(contains('foreignSkipped')));
    });

    test('BDEL-DOM-22 not-found 는 성공과 같다', () {
      expect(hardDelete(), contains('.delete({ignoreNotFound: true})'));
      final m = _flat(_codeOf(_slice(
          raw, 'async function srvRemoveUserBusinessMirrors(', '\n}')));
      expect(m, contains('else missingSkipped++;'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BDEL-DOM-3x retry 전제 · 멱등 (§10·§11·§12)', () {
    test('BDEL-DOM-30 retry: true pin', () {
      final head = _flat(_slice(raw,
          'export const onBusinessDeleted = onDocumentDeleted(', 'async (event)'));
      expect(head, contains('retry: true,'),
          reason: 'required failure → reject → CF retry 가 이 설계의 전제다');
    });

    test('BDEL-DOM-31·32 재시도 경로가 쿼리 기반이라 남은 것만 다시 집는다', () {
      final h = hardDelete();
      // 모든 REQUIRED branch 가 "현재 남아 있는 것"을 쿼리해서 처리한다.
      expect(h, contains('.where("businessId", "==", businessId)'));
      expect(h, contains('if (snap.empty) break;'),
          reason: '이미 비면 no-op — 재실행 안전');
      // Storage 는 네임스페이스 열거로 복구한다(11A.2).
      expect(h, contains(r'await bucket.getFiles({ prefix: `businesses/${businessId}/`, })'));
    });

    test('BDEL-DOM-33 Phase A 에 counter/seat 이중적용 mutation 이 없다', () {
      // 이게 retry 에서 가장 위험한 축이다. 사업장 삭제 cascade 는
      //   좌석·카운터를 건드리지 않는다 — 코드에 없다는 사실을 고정한다.
      final h = hardDelete();
      for (final danger in [
        'confirmedCount',
        'pendingCount',
        'workDetailCounts',
        'shortage',
        'FieldValue.increment',
      ]) {
        expect(h, isNot(contains(danger)),
            reason: '$danger 가 들어오면 재시도가 이중 적용된다');
      }
    });

    test('BDEL-DOM-34 Phase A 에 알림/FCM side effect 가 없다', () {
      // 있으면 재시도마다 중복 알림이 나간다.
      final h = hardDelete();
      for (final danger in ['messaging()', 'sendNotification', 'createNotification']) {
        expect(h, isNot(contains(danger)), reason: '$danger 가 재시도로 중복된다');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BDEL-DOM-4x 도메인 의미 불변 (§5·§13·§14·§15)', () {
    test('BDEL-DOM-40 Application terminal 의미 그대로', () {
      final h = hardDelete();
      expect(h, contains('status: "CANCELED", cancelReason: "BUSINESS_DELETED",'));
      expect(h, contains('status: "AUTO_CANCELED", cancelReason: "BUSINESS_DELETED",'));
      // 확정 계열만 트랜잭션 판정 대상 — 상태 역행 가드는 helper 에 있다.
      expect(cancelBulk(), contains('allowedStatuses'));
      final one = _flat(_codeOf(_slice(
          raw, 'async function srvLifecycleCancelOne(', '\n}')));
      expect(one, contains('if (!allowedStatuses.includes(st)) return "skipped";'),
          reason: '이미 terminal 인 건을 다시 쓰지 않는다');
      expect(one, contains('if (!fresh.exists) return "skipped";'));
    });

    test('BDEL-DOM-41 Attendance 는 취소된 건의 scheduled 만 건드린다', () {
      final h = hardDelete();
      expect(h, contains('.where("status", "==", "scheduled")'));
      expect(h, contains('attBatch.update(doc.ref, {status: "absent", updatedAt: Timestamp.now()});'));
      // 실근무 보존 건은 대상에서 빠진다 — canceled 목록만 쓴다.
      expect(h, contains('const appIds = bizDelReport.canceled.map((d) => d.id);'));
    });

    test('BDEL-DOM-42 Contract historical 의미 그대로', () {
      final h = hardDelete();
      expect(h, contains('if (status === "pending_employer") { deletableDocs.push(d);'));
      expect(h, contains('status: "voided", voidReason: "BUSINESS_DELETED",'));
      expect(h, contains('if (freshStatus === "pending_worker") {'),
          reason: 'TOCTOU — completed 를 voided 로 내리지 않는다');
      expect(h, contains(r'return `TOCTOU_SKIPPED(${freshStatus ?? "unknown"})`;'));
      // completed/voided/unknown 은 보존되고 historicalOwnerUid 만 찍는다.
      expect(h, contains('stableRetainedDocs.push(d);'));
      expect(h, contains('ownerBatch.update(d.ref, {historicalOwnerUid});'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BDEL-DOM-5x 세 축 통합 · 기존 회귀 (§9·§20·§21·§27)', () {
    test('BDEL-DOM-50 verdict 가 네 축을 모두 본다', () {
      final v = verdict();
      for (final axis in ['domainRequiredFailed', 'mirrorFailed', 'listFailed', 'deleteFailed']) {
        expect(v, contains(axis), reason: '$axis 축 누락');
      }
    });

    test('BDEL-DOM-51 완료 로그에 네 축 + skip 두 축이 남는다 (§25)', () {
      final h = hardDelete();
      for (final k in ['domainRequiredFailed=', 'missingSkipped=', 'mirrorFailed=',
        'listFailed=', 'deleteFailed=', 'foreignSkipped=']) {
        expect(h, contains(k));
      }
    });

    test('BDEL-DOM-52 11A.2 missing-user 계약 유지 (§21)', () {
      final m = _flat(_codeOf(_slice(
          raw, 'async function srvRemoveUserBusinessMirrors(', '\n}')));
      expect(m, contains('const snaps = await db.getAll('));
      expect(m, isNot(contains('.set(')), reason: '탈퇴 계정 부활 금지');
      expect(m, isNot(contains('merge')));
    });

    test('BDEL-DOM-53 11A B1/B4 계약 유지 (§27)', () {
      final h = hardDelete();
      expect(h, contains('srvResolveBusinessStoragePath(businessId, url)'));
      expect(h, contains('srvIsOwnedBusinessStoragePath(businessId, f.name)'));
      expect(h, contains('deletedData["businessLicenseImageUrl"]'));
      expect(h, isNot(contains('bucket.file(decodeURIComponent(')));
      // 비활성화는 여전히 Storage 를 건드리지 않는다.
      final d = _flat(_codeOf(_slice(raw,
          'export const onBusinessDeactivated = onDocumentUpdated(', '\n// ═══')));
      expect(d, isNot(contains('admin.storage()')));
      expect(d, isNot(contains('.delete()')));
      expect(d, isNot(contains('bizCleanup')));
    });

    test('BDEL-DOM-54 verdict 정의는 하나다', () {
      expect('function srvBusinessCleanupVerdict('.allMatches(cf).length, 1);
      expect('srvBusinessCleanupVerdict('.allMatches(cf).length, 2,
          reason: '정의 1 + 호출 1');
    });
  });
}
