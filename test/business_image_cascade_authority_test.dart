// [R7-P4.4E.11A] 비활성화는 서류를 버리지 않는다 · 삭제는 자기 것만 지운다
//
// 무엇이 잘못됐었나
//
//   사업장 이미지 cascade 는 Firestore 에 적힌 URL 에서 경로를 뽑아 Admin SDK
//   로 지웠다. Admin SDK 는 Storage rules 를 우회한다. 그런데 그 필드들
//   (`mainImageUrl`·`imageUrls[]`·`transportImageUrls[]`, 그리고
//   `businesses/{id}/workTypes` 의 이미지 필드)은 사업장 관리자가
//   **클라이언트에서 직접 쓸 수 있다.** 그래서:
//
//     ① 남의 네임스페이스 경로를 적어 두고 자기 사업장을 삭제하면
//        타인의 신분증 object 가 지워졌다. 포인터와 isIdVerified 는
//        남아 "제출 완료"로 보이는데 파일만 없는 상태가 됐다.
//     ② 같은 삭제가 **비활성화**에서도 돌았다. 비활성화는 임시 중단인데
//        이미지를 물리 삭제해, 재활성화해도 돌아오지 않았다.
//
// 이 파일이 고정하는 것
//
//   BUS-IMG-0x  비활성화는 비파괴다 (DEACTIVATE != DELETE)
//   BUS-IMG-1x  영구 삭제는 자기 네임스페이스를 지운다 (positive control)
//   BUS-IMG-2x  남의 네임스페이스는 건너뛴다 (negative control)
//   BUS-IMG-3x  사업자등록증이 정리 대상에 들어온다
//   BUS-IMG-4x  술어는 한 벌이고, 다른 cascade 를 깨지 않는다
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
    .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('*'))
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

  /// 비활성화 트리거 본문 (실행 코드만).
  String deactivate() => _flat(_codeOf(_slice(
      raw, 'export const onBusinessDeactivated = onDocumentUpdated(',
      '\n// ═══')));

  /// 영구 삭제 트리거 본문 (실행 코드만).
  String hardDelete() => _flat(_codeOf(_slice(
      raw, 'export const onBusinessDeleted = onDocumentDeleted(',
      '\n// ═══')));

  String validator() => _flat(_codeOf(_slice(
      raw, 'function srvIsOwnedBusinessStoragePath(', '\n}')));

  String resolver() => _flat(_codeOf(_slice(
      raw, 'function srvResolveBusinessStoragePath(', '\n}')));

  // ══════════════════════════════════════════════════════════════
  group('BUS-IMG-0x 비활성화는 비파괴다 (§2·§3·§14)', () {
    test('BUS-IMG-01 비활성화 경로에 Storage 삭제 호출이 하나도 없다', () {
      final d = deactivate();
      expect(d, isNot(contains('.delete()')),
          reason: '임시 중단이 파일을 지우면 재활성화가 불가능해진다');
      expect(d, isNot(contains('delete({ignoreNotFound')));
      expect(d, isNot(contains('admin.storage()')),
          reason: 'bucket 을 잡지도 않는다 — 지울 의도가 없다');
      expect(d, isNot(contains('bucket.file(')));
    });

    test('BUS-IMG-02 대표 이미지 포인터를 건드리지 않는다', () {
      expect(deactivate(), isNot(contains('mainImageUrl')));
    });

    test('BUS-IMG-03 추가·교통 이미지 포인터를 건드리지 않는다', () {
      final d = deactivate();
      expect(d, isNot(contains('imageUrls')));
      expect(d, isNot(contains('transportImageUrls')));
    });

    test('BUS-IMG-04 업무유형 이미지를 읽지도 지우지도 않는다', () {
      final d = deactivate();
      expect(d, isNot(contains('thumbnailUrl')));
      expect(d, isNot(contains('"images"')));
      expect(d, isNot(contains("work_types")),
          reason: '이미지 수집을 위해 work_types 를 조회하던 블록이 사라졌다');
    });

    test('BUS-IMG-05 사업자등록증을 건드리지 않는다', () {
      expect(deactivate(), isNot(contains('businessLicense')));
    });

    test('BUS-IMG-06 비활성화가 하는 일은 TO·지원서·계약 상태 전이뿐이다', () {
      // 재활성화 invariant: 포인터를 그대로 두므로 같은 이미지를 다시 쓸 수 있다.
      final d = deactivate();
      expect(d, contains('BUSINESS_DEACTIVATED'));
      expect(d, contains('db.collection("tos")'));
      // 그리고 이미지 축은 전혀 등장하지 않는다 (위 01~05).
      expect(d, isNot(contains('Storage')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BUS-IMG-1x 영구 삭제 positive control (§4·§9)', () {
    test('BUS-IMG-10 대표 이미지가 수집된다', () {
      expect(hardDelete(), contains('deletedData["mainImageUrl"]'));
    });

    test('BUS-IMG-11 추가 이미지 배열이 수집된다', () {
      expect(hardDelete(), contains('deletedData["imageUrls"]'));
    });

    test('BUS-IMG-12 교통 이미지 배열이 수집된다', () {
      expect(hardDelete(), contains('deletedData["transportImageUrls"]'));
    });

    test('BUS-IMG-13 root·sub 업무유형 이미지가 수집된다', () {
      final h = hardDelete();
      expect(h, contains('workTypeUrls'));
      expect(h, contains('subWorkTypeUrls'));
      expect(h, contains('...workTypeUrls, ...subWorkTypeUrls'));
    });

    test('BUS-IMG-14 사업자등록증이 수집된다 (§10)', () {
      expect(hardDelete(),
          contains('deletedData["businessLicenseImageUrl"]'));
    });

    test('BUS-IMG-15 삭제는 멱등이다 — 없는 파일은 성공과 같다 (§12)', () {
      expect(hardDelete(), contains('.delete({ignoreNotFound: true})'));
    });

    test('BUS-IMG-16 중복 입력도 한 번만 지운다 (§12)', () {
      final h = hardDelete();
      expect(h, contains('const ownedPaths = new Set<string>()'));
      expect(h, contains('[...ownedPaths].map('));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BUS-IMG-2x cross-tenant negative control (§7·§8)', () {
    test('BUS-IMG-20·21 남의 users/ 경로는 통과할 수 없다', () {
      // 술어는 `businesses/{businessId}/` 접두만 허용한다 —
      //   users/{victim}/idCard_* 도 users/{victim}/bankbook_* 도 접두가 다르다.
      final v = validator();
      expect(v, contains(r'const prefix = `businesses/${businessId}/`;'));
      expect(v, contains('if (!p.startsWith(prefix)) return false;'));
      expect(v, isNot(contains('users/')),
          reason: 'users 네임스페이스를 허용하는 분기가 있으면 안 된다');
    });

    test('BUS-IMG-22 다른 사업장 경로는 통과할 수 없다', () {
      // 접두에 businessId 가 박혀 있으므로 businesses/{other}/ 는 탈락한다.
      expect(validator(), contains(r'businesses/${businessId}/'));
      // businessId 자체에 경로 조각이 들어오는 우회도 막는다.
      expect(validator(),
          contains('if (businessId.includes("/") || businessId.includes("..")) return false;'));
    });

    test('BUS-IMG-23 URL 이 아니거나 망가진 값은 null 로 떨어진다', () {
      final r = resolver();
      expect(r, contains('if (typeof urlOrPath !== "string" || urlOrPath.length === 0) return null;'));
      expect(r, contains('return null; '),
          reason: 'decodeURIComponent 실패도 null 이다');
      expect(r, contains('srvIsOwnedBusinessStoragePath(businessId, candidate) ?'));
    });

    test('BUS-IMG-24 경로 순회(..)는 거부된다', () {
      expect(validator(), contains('if (p.includes("..")) return false;'));
      expect(validator(), contains('return p.length > prefix.length;'),
          reason: '접두만 같고 뒤가 빈 값(폴더 자체)도 거부한다');
    });

    test('BUS-IMG-25 삭제는 validator 를 통과한 집합만 대상으로 한다', () {
      final h = hardDelete();
      // 집합에 넣는 지점은 두 곳이고 **둘 다** 검증을 거친다.
      expect('ownedPaths.add('.allMatches(h).length, 2);
      expect(h, contains('const p = srvResolveBusinessStoragePath(businessId, url);'));
      // [R7-P4.4E.11A.2 갱신] 카운터가 지역변수에서 단계별 집계로 옮겨졌다.
      //   건너뛴다는 계약은 그대로다.
      expect(h, contains('if (p === null) {'));
      expect(h, contains('bizCleanup.foreignSkipped++;'));
      expect(h, contains('if (srvIsOwnedBusinessStoragePath(businessId, f.name)) { ownedPaths.add(f.name); }'));
      // 예전의 무검증 삭제가 남아 있지 않다.
      expect(h, isNot(contains('bucket.file(decodeURIComponent(')));
    });

    test('BUS-IMG-26 건너뛰기가 사업장 삭제를 실패시키지 않는다 (§7)', () {
      // [R7-P4.4E.11A.2 갱신] 이제 cascade 는 **정리 실패 시 일부러 던진다**
      //   (retry owner 에게 넘긴다). 그러나 외부 경로 건너뜀은 실패가 아니므로
      //   던지는 사유에 들어가지 않는다 — 그것이 이 셀의 원래 계약이다.
      final h = hardDelete();
      expect(h, contains('bizCleanup.foreignSkipped++;'));
      expect(h, contains('console.warn('));
      final verdict = _flat(_codeOf(_slice(
          raw, 'function srvBusinessCleanupVerdict(', '\n}')));
      expect(verdict, isNot(contains('foreignSkipped')),
          reason: '건너뜀이 throw 사유가 되면 영구 retry loop 다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BUS-IMG-3x 사업자등록증 정리 (§10·§11·§13)', () {
    test('BUS-IMG-30 사업장 네임스페이스를 정확한 접두로만 열거한다', () {
      // [R7-P4.4E.11A.2 갱신] license 접두 전용 sweep 이 **사업장 root 접두**
      //   sweep 으로 넓어졌다 — 재시도가 포인터 없이도 잔여를 찾아야 해서다
      //   (§2). license/ 는 그 안에 포함되므로 계약은 강화됐다.
      //   그 범위가 안전한 근거: 이 네임스페이스의 production writer 는
      //   callableUploadBusinessImage 하나이고 보존 대상이 없다(§1 READ).
      final h = hardDelete();
      expect(h, contains(r'await bucket.getFiles({ prefix: `businesses/${businessId}/`, })'));
      expect(h, isNot(contains('licensePrefix')),
          reason: '좁은 접두만 보던 구현이 남아 있으면 재시도 복구가 불완전하다');
    });

    test('BUS-IMG-31 열거 결과도 validator 를 거친다', () {
      expect(hardDelete(),
          contains('if (srvIsOwnedBusinessStoragePath(businessId, f.name)) { ownedPaths.add(f.name); }'));
    });

    test('BUS-IMG-32 열거 실패가 cascade 를 막지 않는다 — 그리고 삼켜지지도 않는다', () {
      // [R7-P4.4E.11A.2 갱신] 예전엔 "삼키고 기록"이 전부였다. 그건 기존
      //   residual(실패가 추적되지 않음) 그 자체였다. 이제는 기록 + 집계 +
      //   마지막에 throw 다 — 다른 정리는 계속하되 성공으로 ACK 하지 않는다.
      final h = hardDelete();
      expect(h, contains('네임스페이스 열거 실패'), reason: '기록은 유지');
      expect(h, contains('bizCleanup.listFailed++;'), reason: '집계로 올린다');
      final listAt = h.indexOf('bizCleanup.listFailed++;');
      // Storage 삭제 전용 anchor — `Promise.allSettled(` 는 cascade 앞쪽
      //   도메인 정리에도 있어서 첫 등장을 집으면 엉뚱한 곳을 가리킨다.
      final delAt = h.indexOf('.delete({ignoreNotFound: true})');
      final throwAt = h.indexOf('throw new Error(');
      expect(delAt, greaterThan(listAt), reason: '열거 실패 후에도 삭제 단계는 실행된다');
      expect(throwAt, greaterThan(delAt), reason: 'throw 는 마지막이다');
    });

    test('BUS-IMG-33 owner-scoped 등록증은 사업장 삭제로 지우지 않는다 (§13)', () {
      // `users/{uid}/businessLicense_*` 는 접두가 달라 validator 가 거른다.
      //   사업장 삭제 cascade 가 그 경로를 명시적으로 집는 코드도 없다.
      final h = hardDelete();
      expect(h, isNot(contains('businessLicenseImagePath')),
          reason: 'owner-scoped 포인터는 이 cascade 의 대상이 아니다');
      expect(h, isNot(contains(r'users/${')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BUS-IMG-4x 술어 통합·회귀 (§6·§19·§21)', () {
    test('BUS-IMG-40 validator 정의는 하나다', () {
      expect('function srvIsOwnedBusinessStoragePath('.allMatches(cf).length, 1);
      expect('function srvResolveBusinessStoragePath('.allMatches(cf).length, 1);
    });

    test('BUS-IMG-41 기존 안전 패턴도 같은 술어를 쓴다 (§19)', () {
      final del = _flat(_codeOf(_slice(raw,
          'export const callableDeleteBusinessImage', 'Admin SDK로 삭제')));
      expect(del, contains('if (!srvIsOwnedBusinessStoragePath(businessId, filePath)) {'));
      // 기존 소속 검증(adminIds)은 그대로다 — 권한 축을 바꾸지 않았다.
      expect(del, contains('adminIds.includes(callerUid)'));
    });

    test('BUS-IMG-42 non-image cascade 가 그대로다 (§21)', () {
      final h = hardDelete();
      // §21 이 지목한 네 축을 그대로 고정한다.
      //   TO 는 `deleteByBusinessId` 가 아니라 페이지네이션 루프로 지운다 —
      //   처음에 그렇게 썼다가 틀렸고, 실제 본문으로 맞췄다.
      for (final keep in [
        // TO / Application lifecycle
        'cancelReason: "BUSINESS_DELETED"',
        'srvLifecycleCancelBulk(appsSnap.docs',
        'status: "AUTO_CANCELED"',
        // workType cleanup
        r'deleteSubcollection(`businesses/${businessId}/workTypes`)',
        // contract / attendance retention
        'voidReason: "BUSINESS_DELETED"',
        'historicalOwnerUid',
        'status: "absent"',
        // business member cleanup
        r'deleteSubcollection(`businesses/${businessId}/members`)',
        'subAdminBusinessIds: admin.firestore.FieldValue.arrayRemove(businessId)',
        'managedBusinessIds: admin.firestore.FieldValue.arrayRemove(businessId)',
      ]) {
        expect(h, contains(keep), reason: '이미지 패치가 $keep 를 건드리면 안 된다');
      }
    });

    test('BUS-IMG-43 비활성화의 비이미지 처리가 그대로다 (§21)', () {
      final d = deactivate();
      expect(d, contains('closedReason: "BUSINESS_DEACTIVATED"'));
      expect(d, contains('employment_contracts'));
    });

    test('BUS-IMG-44 다른 네임스페이스 cleanup helper 를 건드리지 않았다', () {
      // 신분증 전용 술어는 그대로 — artifact 별로 각자의 술어를 쓴다.
      expect(cf, contains('function srvIsOwnedIdDocumentStoragePath('));
      expect(cf, contains('function srvIsOwnedStoragePath('));
    });
  });
}
