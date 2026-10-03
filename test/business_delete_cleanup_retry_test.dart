// [R7-P4.4E.11A.2] 정리가 실패했으면 성공이라고 말하지 않는다
//
// 무엇이 잘못됐었나
//
//   ① `batch.update(users/{uid}, …)` 를 바로 commit 했다. Firestore batch 는
//      대상 문서가 없으면 **전체가** NOT_FOUND 로 실패한다. 탈퇴한 관리자가
//      한 명이라도 끼면 batch 가 터지고 그 뒤 cascade — TO·계약·그리고
//      **Storage 이미지 정리** — 가 아예 실행되지 않았다. DEV 런타임에서
//      실제로 관찰됐다(11A.1 §26). 탈퇴는 사업장을 비활성화만 하므로
//      (`callableDeleteAccountFinal`) 그런 사업장이 실제로 존재한다.
//
//   ② Storage 삭제 실패를 `Promise.allSettled` 로 개수만 로그하고 함수는
//      성공으로 끝났다. `retry: true` 가 있어도 재시도되지 않았고, 고아는
//      추적되지 않은 채 남았다.
//
//   ③ 그리고 재시도가 가능해도 **무엇을 지워야 하는지** 다시 알 수 없었다.
//      1차에서 workType·business 문서를 이미 지웠으면 포인터가 사라진다.
//
// 이 파일이 고정하는 것
//
//   BDEL-RTRY-0x  없는 사용자는 건너뛴다 — 되살리지 않는다
//   BDEL-RTRY-1x  살아 있는 mirror 는 포기하지 않는다
//   BDEL-RTRY-2x  Storage 실패는 표면화되고, 재시도는 네임스페이스로 복구한다
//   BDEL-RTRY-3x  열거 실패는 실패다 / 외부 경로 건너뜀은 실패가 아니다
//   BDEL-RTRY-4x  기존 계약 유지 (retry:true · validator · 보호 · 비활성화)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

/// 주석을 뺀 실행 코드만 — 계약은 주석에 대한 것이 아니다.
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
  String deactivate() => _flat(_codeOf(_slice(
      raw, 'export const onBusinessDeactivated = onDocumentUpdated(', '\n// ═══')));
  String mirror() => _flat(_codeOf(_slice(
      raw, 'async function srvRemoveUserBusinessMirrors(', '\n}')));
  String verdict() => _flat(_codeOf(_slice(
      raw, 'function srvBusinessCleanupVerdict(', '\n}')));

  // ══════════════════════════════════════════════════════════════
  group('BDEL-RTRY-0x 없는 사용자는 건너뛴다 (§5)', () {
    test('BDEL-RTRY-01 존재 확인 후 없는 사용자는 skip 으로 센다', () {
      final m = mirror();
      expect(m, contains('const snaps = await db.getAll('),
          reason: '쓰기 전에 존재를 확인한다');
      expect(m, contains('if (s.exists) existing.push(s.id); else missingSkipped++;'));
      expect(m, contains('batch.update(db.collection("users").doc(u), patch);'),
          reason: '존재하는 사용자만 쓴다');
    });

    test('BDEL-RTRY-01n 없는 계정을 되살리지 않는다 (§26 negative control)', () {
      final m = mirror();
      expect(m, isNot(contains('.set(')),
          reason: 'set(...merge) 는 탈퇴 계정을 부활시킨다 — 금지');
      expect(m, isNot(contains('merge')));
      expect(m, isNot(contains('SetOptions')));
      // 전체 cascade 에도 users 문서를 만드는 경로가 없다.
      expect(hardDelete(), isNot(contains('db.collection("users").doc(')),
          reason: 'cascade 본문은 users 쓰기를 helper 에만 맡긴다');
    });

    test('BDEL-RTRY-02 살아 있는 사용자 mirror 는 실제로 지운다', () {
      final h = hardDelete();
      expect(h, contains('{managedBusinessIds: admin.firestore.FieldValue.arrayRemove(businessId)},'));
      expect(h, contains('subAdminBusinessIds: admin.firestore.FieldValue.arrayRemove(businessId), subAdminOf: admin.firestore.FieldValue.delete(),'));
    });

    test('BDEL-RTRY-03 두 mirror 축이 모두 같은 helper 를 쓴다', () {
      expect('srvRemoveUserBusinessMirrors('.allMatches(cf).length, 3,
          reason: '정의 1 + admin 1 + subAdmin 1');
      // 예전의 즉시 commit 두 곳이 사라졌다.
      expect(cf, isNot(contains('await adminBatch.commit();')));
      expect(cf, isNot(contains('let userBatch = db.batch();')));
    });

    test('BDEL-RTRY-03b 없는 사용자는 throw 사유에 들어가지 않는다', () {
      expect(verdict(), isNot(contains('missingSkipped')),
          reason: '영구히 없는 계정이 retry loop 원인이 되면 안 된다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BDEL-RTRY-1x 살아 있는 mirror 를 포기하지 않는다 (§6·§18)', () {
    test('BDEL-RTRY-10 mirror 실패가 Storage 단계를 막지 않는다', () {
      final h = hardDelete();
      // helper 는 던지지 않고 집계만 올린다 → 아래 Storage 블록이 실행된다.
      expect(mirror(), isNot(contains('throw ')));
      final mirrorAt = h.indexOf('bizCleanup.mirrorFailed += adminRes.failed;');
      final storageAt = h.indexOf('const bucket = admin.storage().bucket();');
      final throwAt = h.indexOf('throw new Error(');
      expect(mirrorAt, greaterThan(0));
      expect(storageAt, greaterThan(mirrorAt),
          reason: 'Storage 정리가 mirror 집계 뒤에 온다');
      expect(throwAt, greaterThan(storageAt),
          reason: 'throw 는 Storage 정리까지 끝난 뒤에만 한다');
    });

    test('BDEL-RTRY-11 mirror 실패는 최종 throw 사유다', () {
      expect(verdict(), contains('if (t.mirrorFailed > 0) parts.push('));
      expect(hardDelete(), contains('bizCleanup.mirrorFailed += subRes.failed;'));
      expect(hardDelete(), contains('bizCleanup.mirrorFailed += adminRes.failed;'));
    });

    test('BDEL-RTRY-11n catch 후 성공 ACK 로 끝내지 않는다 (§26)', () {
      final h = hardDelete();
      // 최종 판정이 반드시 존재하고, 그 결과로 던진다.
      expect(h, contains('const bizRetryReason = srvBusinessCleanupVerdict(bizCleanup);'));
      expect(h, contains('if (bizRetryReason !== null) { throw new Error('));
    });

    test('BDEL-RTRY-12 chunk 단위 실패라 재시도가 남은 것만 고친다 (§7)', () {
      final m = mirror();
      expect(m, contains('const WRITE_CHUNK = 400;'));
      expect(m, contains('await batch.commit(); updated += slice.length;'));
      expect(m, contains('} catch (e) { failed++;'),
          reason: 'chunk 실패가 다른 chunk 를 막지 않는다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BDEL-RTRY-2x Storage 실패 표면화 · 네임스페이스 복구 (§2·§10·§12)', () {
    test('BDEL-RTRY-20 삭제 실패가 최종 throw 사유다', () {
      expect(hardDelete(), contains('bizCleanup.deleteFailed += failed;'));
      expect(verdict(), contains('if (t.deleteFailed > 0) parts.push('));
    });

    test('BDEL-RTRY-21 성공한 삭제를 되돌리지 않는다', () {
      final h = hardDelete();
      expect(h, contains('Promise.allSettled('),
          reason: '한 건 실패가 다른 삭제를 취소하지 않는다');
      expect(h, isNot(contains('rollback')));
      expect(h, isNot(contains('.save(')));
    });

    test('BDEL-RTRY-22 재시도 복구원은 네임스페이스 열거다 (포인터 독립)', () {
      final h = hardDelete();
      expect(h, contains(r'await bucket.getFiles({ prefix: `businesses/${businessId}/`, })'),
          reason: '포인터가 사라진 뒤에도 남은 object 를 다시 찾아야 한다');
      // license 접두만 보던 11A 구현은 더 이상 없다 — root 접두가 그것을 포함한다.
      expect(h, isNot(contains('licensePrefix')));
    });

    test('BDEL-RTRY-23 열거 결과도 validator 를 거쳐 삭제 대상이 된다', () {
      expect(hardDelete(),
          contains('if (srvIsOwnedBusinessStoragePath(businessId, f.name)) { ownedPaths.add(f.name); }'));
    });

    test('BDEL-RTRY-24 잔여 0 이면 resolve 한다', () {
      // 집계가 모두 0 이면 verdict 는 null 이고 throw 하지 않는다.
      expect(verdict(), contains('return parts.length > 0 ? parts.join(" ") : null;'));
    });

    test('BDEL-RTRY-25 멱등 — 이미 없는 object 는 성공과 같다 (§12)', () {
      expect(hardDelete(), contains('.delete({ignoreNotFound: true})'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BDEL-RTRY-3x 열거 실패 vs 외부 경로 (§11·§13)', () {
    test('BDEL-RTRY-30 열거 실패는 "지울 게 없었다"가 아니다', () {
      expect(hardDelete(), contains('bizCleanup.listFailed++;'));
      expect(verdict(), contains('if (t.listFailed > 0) parts.push('));
    });

    test('BDEL-RTRY-31 외부 경로 건너뜀은 실패가 아니다', () {
      expect(hardDelete(), contains('bizCleanup.foreignSkipped++;'));
      expect(verdict(), isNot(contains('foreignSkipped')),
          reason: 'security skip 이 throw 사유가 되면 영구 retry loop 다');
    });

    test('BDEL-RTRY-32 집계 항목이 로그에 남는다 (§24)', () {
      final h = hardDelete();
      for (final k in ['missingSkipped=', 'mirrorFailed=', 'listFailed=',
        'deleteFailed=', 'foreignSkipped=']) {
        expect(h, contains(k), reason: '$k 가 로그에 없다');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BDEL-RTRY-4x 기존 계약 유지 (§19·§20·§23)', () {
    test('BDEL-RTRY-40 retry: true 가 이 해법의 전제다 — pin', () {
      final h = _flat(_slice(raw,
          'export const onBusinessDeleted = onDocumentDeleted(', 'async (event)'));
      expect(h, contains('retry: true,'),
          reason: 'retry 를 false 로 바꾸면 이 설계의 recovery owner 가 사라진다');
    });

    test('BDEL-RTRY-41 same-business validator 유지 (B1)', () {
      final h = hardDelete();
      expect(h, contains('srvResolveBusinessStoragePath(businessId, url)'));
      expect(h, contains('srvIsOwnedBusinessStoragePath(businessId, f.name)'));
      expect(cf, contains('function srvIsOwnedBusinessStoragePath('));
    });

    test('BDEL-RTRY-42 타 사용자·타 사업장 보호 유지 (B1)', () {
      // 술어가 businesses/{businessId}/ 접두만 허용한다.
      final v = _flat(_codeOf(_slice(
          raw, 'function srvIsOwnedBusinessStoragePath(', '\n}')));
      expect(v, contains(r'const prefix = `businesses/${businessId}/`;'));
      expect(v, contains('if (!p.startsWith(prefix)) return false;'));
      expect(v, contains('if (p.includes("..")) return false;'));
      expect(hardDelete(), isNot(contains('bucket.file(decodeURIComponent(')),
          reason: '무검증 삭제 경로가 되살아나면 안 된다');
    });

    test('BDEL-RTRY-43 비활성화는 여전히 Storage 를 건드리지 않는다', () {
      final d = deactivate();
      expect(d, isNot(contains('admin.storage()')));
      expect(d, isNot(contains('bucket.file(')));
      expect(d, isNot(contains('.delete()')));
    });

    test('BDEL-RTRY-44 사업자등록증 수집 유지 (B4)', () {
      expect(hardDelete(), contains('deletedData["businessLicenseImageUrl"]'));
    });

    test('BDEL-RTRY-45 비이미지 lifecycle 의미 불변 (§20)', () {
      final h = hardDelete();
      for (final keep in [
        'cancelReason: "BUSINESS_DELETED"',
        'srvLifecycleCancelBulk(appsSnap.docs',
        'status: "AUTO_CANCELED"',
        'status: "absent"',
        'voidReason: "BUSINESS_DELETED"',
        'historicalOwnerUid',
        r'deleteSubcollection(`businesses/${businessId}/workTypes`)',
        r'deleteSubcollection(`businesses/${businessId}/members`)',
      ]) {
        expect(h, contains(keep), reason: '$keep 가 바뀌면 안 된다');
      }
    });

    test('BDEL-RTRY-46 다른 두 배포 대상 함수는 이 Phase 에서 미변경', () {
      // callableDeleteBusinessImage 는 11A 의 모습 그대로다.
      final del = _flat(_codeOf(_slice(raw,
          'export const callableDeleteBusinessImage', 'Admin SDK로 삭제')));
      expect(del, contains('if (!srvIsOwnedBusinessStoragePath(businessId, filePath)) {'));
      expect(del, contains('adminIds.includes(callerUid)'));
      expect(del, isNot(contains('bizCleanup')));
      expect(deactivate(), isNot(contains('bizCleanup')));
    });
  });
}
