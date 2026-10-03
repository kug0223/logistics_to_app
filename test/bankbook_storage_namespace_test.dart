// [R7-P4.4E.11B] 통장사본 포인터가 통장사본만 가리키게 한다
//
// 무엇이 잘못됐었나
//
//   writer·reader·delete 가 모두 `srvIsOwnedStoragePath`(= `users/{uid}/`
//   접두만)를 썼다. **소유자만 보고 무슨 서류인지는 보지 않았다.**
//
//     B3  자기 신분증 경로를 통장사본으로 등록할 수 있었다
//         → 급여 권한(canManageWage)만으로 신분증 Signed URL 을 받았다
//           (신분증은 ID-CONSENT Grant 가 필요한 별도 경계다)
//         → 통장사본을 한 번도 내지 않고 지원 준비 상태를 만들 수 있었다
//         → 다음 교체 때 클라이언트가 그 경로를 지워 신분증 object 가 삭제됐다
//
//     B2  `callableDeleteBankInfo` 가 legacy `bankbookImageUrl` 하나만
//         수집했다. V3 사용자는 canonical 이 `bankbookImagePath` 이므로
//         포인터만 지우고 물리 object 는 한 번도 지우지 않았다 —
//         포인터·소유자·재시도 경로가 동시에 사라졌다.
//
// 이 파일이 고정하는 것
//
//   BANK-NS-xx   네임스페이스 술어 (writer 권위)
//   BANK-READ-xx Signed URL reader 보호
//   BANK-DEL-xx  삭제 lifecycle · 실패 순서 · 멱등
//   BANK-X-xx    cross-artifact 보존 · 교체 · 비변경 증명
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
const _screenPath = 'lib/screens/common/document_management_screen.dart';

void main() {
  final raw = _src(_cfPath);
  final cf = _flat(_codeOf(raw));
  final screen = _flat(_codeOf(_src(_screenPath)));

  String validator() => _flat(_codeOf(_slice(
      raw, 'function srvIsOwnedBankbookStoragePath(', '\n}')));
  String resolver() => _flat(_codeOf(_slice(
      raw, 'function srvResolveOwnedBankbookStoragePath(', '\n}')));
  String writer() => _flat(_codeOf(_slice(
      raw, 'export const callableMarkBankbookVerified', '\n// ──')));
  String reader() => _flat(_codeOf(_slice(
      raw, 'export const callableGetBankbookSignedUrl', '\n// ──')));
  String deleter() => _flat(_codeOf(_slice(
      raw, 'export const callableDeleteBankInfo', '\n// ──')));
  String backfill() => _flat(_codeOf(_slice(
      raw, 'export const callableBackfillBankbookImagePath', '\n// ──')));
  // [R7-P4.4E.11B.1 §21] 삭제 후보 수집·물리 삭제가 공유 helper 로 수렴했다.
  //   `callableDeleteBankInfo` 와 `callableUpdateBankAccount` 가 같은 계약을
  //   쓰도록 하기 위해서다. 계약 자체는 그대로이고 사는 곳만 바뀌었다.
  String collector() => _flat(_codeOf(_slice(
      raw, 'function srvCollectOwnedBankbookPaths(', '\n}')));
  String updater() => _flat(_codeOf(_slice(
      raw, 'export const callableUpdateBankAccount', '\n// ──')));
  // [R7-P4.4E.11B.1A] `srvDeleteOwnedBankbookArtifacts` 는 사라졌다.
  //   물리 삭제는 Phase 2 drain 하나가 소유하고, canonical mutation +
  //   cleanup owner 등록은 Phase 1 helper 가 소유한다. 예전 셀들은
  //   이 두 접근자로 **갱신**된다 — 삭제하지 않는다.
  String phase1() => _flat(_codeOf(_slice(
      raw, 'async function srvResetBankStateWithCleanupOwner(', '\n}')));
  String drain() => _flat(_codeOf(_slice(
      raw, 'async function srvDrainBankbookCleanup(', '\n}')));

  // ══════════════════════════════════════════════════════════════
  group('BANK-NS-0x 네임스페이스 술어 (§7·§10)', () {
    test('BANK-NS-01 canonical 통장사본 모양만 허용한다', () {
      final v = validator();
      expect(v, contains(r'const prefix = `users/${uid}/`;'));
      expect(v, contains('if (!p.startsWith(prefix)) return false;'));
      expect(v, contains(
          r'/^bankbook_\d{10,}\.(jpg|jpeg|png|gif|webp|heic|heif)$/i.test(name)'),
          reason: '실제 writer 가 만드는 bankbook_{millis}.{img} 만');
    });

    test('BANK-NS-03·04·05 같은 사용자 소유라도 다른 서류는 거부된다', () {
      // 술어가 `bankbook_` 로 시작하는 파일명만 통과시키므로
      //   idCard_* · businessLicense_* · profile/* · 임의 파일명은 전부 탈락.
      final v = validator();
      for (final other in ['idCard', 'businessLicense', 'profile']) {
        expect(v, isNot(contains(other)),
            reason: '$other 를 통장사본으로 인정하는 분기가 있으면 안 된다');
      }
    });

    test('BANK-NS-06·08 다른 uid·접두 유사는 거부된다', () {
      final v = validator();
      expect(v, contains(r'users/${uid}/'), reason: 'uid 가 접두에 박혀 있다');
      expect(v, contains('if (uid.includes("/") || uid.includes("..")) return false;'),
          reason: 'uid 자체로 접두를 우회하지 못한다');
    });

    test('BANK-NS-07·09 business/contracts·nested·traversal 거부', () {
      final v = validator();
      // users/ 접두가 아니면 애초에 탈락 — businesses/·contracts/ 포함.
      expect(v, contains('if (name.includes("/") || name.includes("..")) return false;'));
      expect(v, contains('if (typeof p !== "string" || p.length === 0 || p.length > 500) return false;'),
          reason: '빈 경로·과다 길이 거부');
    });

    test('BANK-NS-10 legacy URL 은 환원 후 같은 술어를 거친다 (§8)', () {
      final r = resolver();
      expect(r, contains(r'const m = urlOrPath.match(/\/o\/([^?#]+)/);'));
      expect(r, contains('return null; '), reason: '깨진 인코딩은 null');
      expect(r, contains('srvIsOwnedBankbookStoragePath(uid, candidate) ? candidate : null;'));
      // 단순 접두 비교로 끝내지 않는다.
      expect(r, isNot(contains(r'candidate.startsWith(`users/${uid}/`)')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BANK-NS-1x writer 권위 (§9·§11)', () {
    test('BANK-NS-11 storagePath·imageUrl 두 분기가 한 술어를 거친다', () {
      final w = writer();
      expect(w, contains('const resolvedBb = srvResolveOwnedBankbookStoragePath(callerUid, rawBbInput);'));
      expect(w, contains('if (resolvedBb === null) {'));
      expect(w, contains('"permission-denied", "본인 통장사본 이미지만 등록 가능합니다."'));
      // 넓은 술어가 남아 있지 않다.
      expect(w, isNot(contains('srvIsOwnedStoragePath(storagePath, callerUid)')));
    });

    test('BANK-NS-02 object 존재 검사는 유지된다', () {
      final w = writer();
      expect(w, contains('const [fileExists] = await admin.storage().bucket().file(storagePath).exists();'));
      expect(w, contains('"not-found", "Storage에 해당 통장사본 파일이 존재하지 않습니다."'));
    });

    test('BANK-NS-12 invalid artifact 면 bankbookImagePath 를 쓰지 않는다', () {
      final w = writer();
      final rejectAt = w.indexOf('if (resolvedBb === null) {');
      final writeAt = w.indexOf('bankbookImagePath: storagePath,');
      expect(rejectAt, greaterThan(0));
      expect(writeAt, greaterThan(rejectAt), reason: '검증이 쓰기보다 앞에 있어야 한다');
    });

    test('BANK-NS-13 backfill writer 도 같은 술어를 거친다 (§9)', () {
      final b = backfill();
      expect(b, contains('srvResolveOwnedBankbookStoragePath(doc.id, imageUrl)'));
      expect(b, isNot(contains('decodeURIComponent(match[1])')),
          reason: 'legacy URL 을 검증 없이 canonical 포인터로 승격하면 안 된다');
      expect(b, contains('bankbookImagePath: storagePath,'));
    });

    test('BANK-NS-14 술어 정의는 각각 하나다 (§29)', () {
      expect('function srvIsOwnedBankbookStoragePath('.allMatches(cf).length, 1);
      expect('function srvResolveOwnedBankbookStoragePath('.allMatches(cf).length, 1);
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BANK-READ-0x Signed URL reader 보호 (§12·§13·§29)', () {
    test('BANK-READ-01 canonical 포인터만 서명 대상이 된다', () {
      final r = reader();
      expect(r, contains('const storagePath = srvResolveOwnedBankbookStoragePath(appUid, bbPointer);'));
      expect(r, contains('if (storagePath === null) {'));
      expect(r, contains('await file.getSignedUrl({'));
    });

    test('BANK-READ-02·03·04 poisoned 포인터는 서명되지 않는다', () {
      final r = reader();
      // 넓은 술어가 사라졌다 — 신분증/사업자등록증/타인 경로가 통과할 수 없다.
      expect(r, isNot(contains('srvIsOwnedStoragePath(storagePath, appUid)')));
      expect(r, contains('"통장사본 파일 경로가 올바르지 않습니다. 근로자에게 재등록을 요청해주세요."'));
      // 거절이 서명·감사로그보다 앞이다 → 감사 로그에 성공으로 남지 않는다.
      final rejectAt = r.indexOf('if (storagePath === null) {');
      final signAt = r.indexOf('await file.getSignedUrl({');
      final auditAt = r.indexOf('db.collection("bankbook_access_logs").add(');
      expect(rejectAt, greaterThan(0));
      expect(signAt, greaterThan(rejectAt));
      expect(auditAt, greaterThan(signAt),
          reason: '감사 로그는 서명 성공 뒤에만 기록된다');
    });

    test('BANK-READ-05 object 없음은 기존 not-found semantics 유지', () {
      final r = reader();
      expect(r, contains('const [exists] = await file.exists();'));
      expect(r, contains('"not-found", "통장사본 파일이 Storage에 존재하지 않습니다."'));
    });

    test('BANK-READ-07 이 그룹은 reader 하나만 본다 — 나머지 둘도 좁혀졌다', () {
      // [R7-P4.4E.11B.1C] 이 그룹의 맹점이 11B2 BLOCKER 였다. BANK-READ-01~06
      //   은 `callableGetBankbookSignedUrl` **하나만** 검사했고, 통장사본
      //   bytes 를 돌려줄 수 있는 입구가 셋이라는 사실을 아무 셀도 보지
      //   않았다. 그래서 나머지 둘이 `srvIsOwnedStoragePath`(소유자 접두만)로
      //   남아 있는 상태가 세 단계를 통과했다.
      //
      //   reader 전수 inventory 는 bankbook_reader_namespace_contract_test
      //   가 소유한다(네 번째 reader 가 생기면 거기서 깨진다). 여기서는 이
      //   파일이 한 reader 만 보는 것이 **의도된 범위**임을 분명히 하고,
      //   나머지 둘이 같은 술어를 쓰는지 최소 확인만 한다.
      for (final other in [
        'export const callableGetPayrollBankbookUrl',
        'export const callableGetApplicantDocumentUrl',
      ]) {
        final body = _flat(_codeOf(_slice(raw, other, '\n// ──')));
        expect(body, contains('srvResolveOwnedBankbookStoragePath('),
            reason: '$other 이 exact 통장사본 술어를 쓰지 않는다');
      }
    });

    test('BANK-READ-06 인가 축(canManageWage·확정·동의)은 바뀌지 않았다', () {
      final r = reader();
      for (final keep in [
        '"급여 관리 권한이 없습니다."',
        '"확정된 지원서의 통장사본만 열람 가능합니다."',
        '"근로자가 서류 접근에 동의하지 않았습니다."',
      ]) {
        expect(r, contains(keep), reason: '$keep 가 바뀌면 안 된다');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // [R7-P4.4E.11B.1A 갱신 — 삭제 아님]
  //
  //   이 그룹의 셀들은 §19~§28 의 "Storage 먼저 → 실패하면 Firestore 를
  //   건드리지 않는다" 계약을 고정하고 있었다. 그 계약이 반대 방향의
  //   실패를 만들었다 — Storage 삭제 성공 + Firestore update 실패 =
  //   포인터는 남고 bytes 는 없는 **canonical dangling pointer**.
  //
  //   그래서 순서가 바뀌었다: Phase 1(canonical mutation + cleanup owner
  //   등록, atomic) → Phase 2(물리 삭제 drain). 셀 ID 는 그대로 두고
  //   **같은 질문을 새 구조에 다시 묻는다.** 셀을 지우면 그 질문이 다시
  //   퇴행했을 때 아무도 모른다.
  group('BANK-DEL-0x 삭제 lifecycle (§19~§28 → 11B.1A 2단계로 갱신)', () {
    test('BANK-DEL-01 canonical path 를 후보로 수집한다 (B2 핵심)', () {
      // 수집은 여전히 공유 collector 가 한다. 호출 지점만 Phase 1 로 옮겼다.
      expect(phase1(), contains('srvCollectOwnedBankbookPaths(uid, cur)'));
      expect(deleter(), contains('await srvResetBankStateWithCleanupOwner('));
      expect(collector(), contains('data?.["bankbookImagePath"]'),
          reason: 'V3 canonical 포인터가 수집되지 않으면 물리 삭제가 일어나지 않는다');
    });

    test('BANK-DEL-02 legacy URL 도 독립 후보다 (§21)', () {
      final c = collector();
      expect(c, contains('data?.["bankbookImageUrl"]'));
      // `path ?? url` 우선순위가 아니라 **둘 다** 돈다.
      expect(c, contains('for (const raw of [data?.["bankbookImagePath"], data?.["bankbookImageUrl"]])'));
      expect(c, isNot(contains('bankbookImagePath"] ?? ')));
    });

    test('BANK-DEL-03·04·05 후보마다 resolve+validate 를 거친다', () {
      final c = collector();
      expect(c, contains('const ok = srvResolveOwnedBankbookStoragePath(uid, raw);'));
      expect(c, contains('if (ok === null) { skipped++; continue; }'));
      // 검증 없는 삭제 경로가 사라졌다.
      final d = deleter();
      expect(d, isNot(contains('oldImageUrl.match(')));
      expect(d, isNot(contains('decodeURIComponent(pathMatch[1])')));
    });

    test('BANK-DEL-06 중복 후보는 한 번만 지운다', () {
      expect(collector(), contains('const paths = new Set<string>();'));
      // 큐에 들어갈 때도 집합 의미다 — 이미 대기 중인 경로를 중복시키지 않는다.
      expect(phase1(), contains('admin.firestore.FieldValue.arrayUnion(...found.paths)'));
    });

    test('BANK-DEL-07 not-found 는 성공 동치다 (§28)', () {
      expect(drain(), contains('.delete({ignoreNotFound: true});'));
    });

    test('BANK-DEL-08 Storage 오류가 canonical state 를 되돌리지 않는다 (§22 갱신)', () {
      // [갱신] 예전 기대는 "Storage 실패 → Firestore 미도달"이었다. 이제
      //   순서가 반대다. 같은 걱정("한쪽만 성립한 채 침묵")을 새 구조에
      //   묻는다 — Phase 1 이 atomic 하게 먼저 끝나고, Phase 2 실패는
      //   **항목을 큐에 남긴다**. 되돌리지 않고, 삼키지도 않는다.
      final d = deleter();
      final p1At = d.indexOf('await srvResetBankStateWithCleanupOwner(');
      final p2At = d.indexOf('await srvDrainBankbookCleanup(callerUid, "callableDeleteBankInfo")');
      expect(p1At, greaterThan(0));
      expect(p2At, greaterThan(p1At), reason: 'Phase 1 → Phase 2 순서');
      final dr = drain();
      expect(dr, contains('out.failed++;'));
      expect(dr, contains('continue;'),
          reason: '실패한 항목은 목록에 남아야 다음 drain 이 다시 집는다');
      expect(dr, isNot(contains('Storage 삭제 실패 (무시)')),
          reason: '삼키고 성공으로 끝내는 경로가 남아 있으면 안 된다');
    });

    test('BANK-DEL-09·10 재호출이 아니라 **큐가** 주인이다 (§23 갱신)', () {
      // [갱신] 예전 계약은 "사용자가 다시 호출하면 수렴한다"였다. 그건
      //   durable recovery 가 아니다. 이제 경로·대기 여부·재시도 주인이
      //   `bankbookCleanupPendingPaths` 에 남는다.
      final d = deleter();
      expect(d, contains('const bankDelDrain ='));
      expect(cf, contains('const BANKBOOK_CLEANUP_FIELD = "bankbookCleanupPendingPaths";'));
      // Phase 1 은 쓰기 경계가 하나다 — 중간 상태가 관측되지 않는다.
      final p = phase1();
      expect(p, contains('db.runTransaction(async (tx) => {'));
      expect('tx.update(ref,'.allMatches(p).length, 1,
          reason: '쪼개 쓰면 "포인터는 지워졌는데 주인은 없는" 금지 상태가 생긴다');
      // 재호출해도 수렴한다는 성질 자체는 유지된다(not-found = 성공).
      expect(drain(), contains('.delete({ignoreNotFound: true});'));
    });

    test('BANK-DEL-11 canonical state cleanup 은 그대로다 (§25)', () {
      // 필드 집합은 helper 인자로 **위치만** 옮겼다 — 내용 무변경.
      final d = deleter();
      for (final f in [
        'bankName: admin.firestore.FieldValue.delete(),',
        'accountNumber: admin.firestore.FieldValue.delete(),',
        'bankbookImagePath: admin.firestore.FieldValue.delete(),',
        'bankbookImageUrl: admin.firestore.FieldValue.delete(),',
        'bankAccountVersion: admin.firestore.FieldValue.increment(1),',
        'bankbookDocumentVersion: admin.firestore.FieldValue.increment(1),',
        'bankbookMatchStatus: admin.firestore.FieldValue.delete(),',
        'bankbookDocumentState: admin.firestore.FieldValue.delete(),',
      ]) {
        expect(d, contains(f), reason: '$f 가 바뀌면 안 된다');
      }
      // 그 패치가 실제로 Phase 1 로 전달된다.
      expect(phase1(), contains('const write: Record<string, unknown> = {...patch};'));
    });

    test('BANK-DEL-12 invalid 포인터 때문에 계좌 삭제가 막히지 않는다 (§24)', () {
      // [갱신] 예전엔 호출부에 `if (bankDel.skipped > 0)` 분기가 있었다.
      //   이제 skip 집계는 Phase 1 안에서 끝나고, 같은 트랜잭션이 canonical
      //   패치를 그대로 적용한다 — 건너뛴 포인터가 삭제를 막을 수 없다.
      final p = phase1();
      expect(p, contains('if (found.skipped > 0) {'));
      expect(p, contains('return found.skipped;'));
      expect(p, isNot(contains('if (found.skipped > 0) { throw')));
      // collector 가 skip 을 실패로 승격시키지 않는다.
      expect(collector(), isNot(contains('throw')));
      // 호출부도 skip 때문에 던지지 않는다.
      final d = deleter();
      expect(d, isNot(contains('if (bankDelSkipped > 0) { throw')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BANK-UPD-xx 계좌 변경이 옛 통장사본 bytes 를 종료한다 (§0·§4·§10)', () {
    test('BANK-UPD-01·02·03·04 같은 helper 로 후보를 모으고 지운다', () {
      final u = updater();
      expect(u, contains('const bankUpdSkipped = await srvResetBankStateWithCleanupOwner('));
      expect(u, contains('await srvDrainBankbookCleanup(callerUid, "callableUpdateBankAccount")'));
      // path·URL 독립 수집 + dedupe 는 collector 계약이다(BANK-DEL-02·06 참조).
      expect(collector(), contains('const paths = new Set<string>();'));
      // 삭제와 **같은** 두 소유자를 쓴다 — 경로 문법이 복제되지 않았다.
      expect(deleter(), contains('await srvResetBankStateWithCleanupOwner('));
    });

    test('BANK-UPD-05 검증이 전부 끝난 뒤에 Phase 1 을 시작한다 (§4)', () {
      final u = updater();
      final bankNameAt = u.indexOf('"은행명이 필요합니다."');
      final acctAt = u.indexOf('"계좌번호가 필요합니다."');
      final roleAt = u.indexOf('"지원자 계정만 급여 계좌를 등록할 수 있습니다."');
      final holderAt = u.indexOf('"사용자 이름이 등록되지 않았습니다."');
      final delAt = u.indexOf('await srvResetBankStateWithCleanupOwner(');
      for (final at in [bankNameAt, acctAt, roleAt, holderAt]) {
        expect(at, greaterThan(0));
        expect(delAt, greaterThan(at),
            reason: '검증보다 cleanup 등록이 먼저면 invalid 입력에 통장사본을 잃는다');
      }
    });

    test('BANK-UPD-10~13 invalid 포인터는 건너뛰되 계좌 변경을 막지 않는다 (§9)', () {
      // [갱신] skip 집계가 Phase 1 반환값으로 옮겨졌다. canonical 패치는
      //   같은 트랜잭션에서 그대로 적용되므로 skip 이 변경을 막을 수 없다.
      final u = updater();
      expect(u, contains('bankName: bankName.trim(),'));
      expect(u, isNot(contains('if (bankUpdSkipped > 0) { throw')),
          reason: 'INVALID_POINTER ≠ STORAGE_FAILURE — DOS 로 만들지 않는다');
      expect(phase1(), contains('return found.skipped;'));
    });

    test('BANK-UPD-30·31 drain 실패가 새 계좌를 되돌리지 않는다 (§11·§15 갱신)', () {
      // [갱신] 예전 기대는 "Storage 실패면 Firestore 에 도달하지 않는다"
      //   였다. 이제 순서가 반대이고, 실패한 bytes 는 큐에 남는다. 같은
      //   걱정("한쪽만 성립")을 새 구조에 묻는다.
      final u = updater();
      final p1At = u.indexOf('await srvResetBankStateWithCleanupOwner(');
      final p2At = u.indexOf('const bankUpdDrain =');
      expect(p1At, greaterThan(0));
      expect(p2At, greaterThan(p1At));
      // §17·§18 — 여기서는 던지지 않는다. version 이 중복 전진하면 안 된다.
      final seg = u.substring(p2At);
      expect(seg, isNot(contains('throw new HttpsError( "unavailable",')),
          reason: '계좌 변경은 이미 성립했다 — 던지면 version 이 두 번 오른다');
      expect(u, contains('return {success: true, cleanupPending: bankUpdDrain.pendingAfter > 0};'));
    });

    test('BANK-UPD-40 bankAccountVersion semantics 불변 (§15)', () {
      final u = updater();
      expect(u, contains('bankAccountVersion: admin.firestore.FieldValue.increment(1),'));
      expect(u, contains('bankbookDocumentVersion: admin.firestore.FieldValue.increment(1),'));
      // [갱신] 단일 경계는 이제 Phase 1 트랜잭션이다 — 호출부는 users 문서를
      //   직접 쓰지 않는다. 쪼개 쓰면 중간 상태가 관측된다 (§14).
      expect(u, isNot(contains('db.collection("users").doc(callerUid).update({')),
          reason: 'canonical 쓰기가 Phase 1 밖에 또 있으면 원자성이 깨진다');
      expect('tx.update(ref,'.allMatches(phase1()).length, 1);
    });

    test('BANK-UPD-41 bankbook reset semantics 불변 (§2·§38)', () {
      final u = updater();
      for (final f in [
        'bankbookImagePath: admin.firestore.FieldValue.delete(),',
        'bankbookImageUrl: admin.firestore.FieldValue.delete(),',
        'bankbookUploadedAt: admin.firestore.FieldValue.delete(),',
        'bankbookDocumentState: admin.firestore.FieldValue.delete(),',
        'bankbookSelfCheck: admin.firestore.FieldValue.delete(),',
        'bankbookMatchStatus: admin.firestore.FieldValue.delete(),',
        'bankReviewedAt: admin.firestore.FieldValue.delete(),',
      ]) {
        expect(u, contains(f), reason: '$f 가 바뀌면 안 된다');
      }
    });

    test('BANK-UPD-16 accountHolder 정책 불변 (§16)', () {
      final u = updater();
      expect(u, contains('const isForeign = srvIsForeignIdentity(userData);'));
      expect(u, contains('accountHolder = userData.name as string;'),
          reason: '내국인은 서버가 users.name 에서 읽는다');
      expect(u, contains('"외국인 근로자는 예금주명을 입력해야 합니다."'));
    });

    test('BANK-UPD-37 암호화·정규화 비변경 (§37)', () {
      final u = updater();
      expect(u, contains('accountNumber: accountNumber.trim(),'));
      expect(u, isNot(contains('EncryptionHelper')));
      expect(u, isNot(contains('decrypt')));
    });

    test('BANK-UPD-39 side-effect notification 0 (§39)', () {
      final u = updater();
      for (final s in ['messaging()', 'sendNotification', 'createNotification',
        'notifications', 'audit']) {
        expect(u, isNot(contains(s)), reason: '$s 가 있으면 재시도로 중복된다');
      }
    });

    test('BANK-UPD-21 drain 이 not-found 를 성공으로 본다 (§12)', () {
      expect(drain(), contains('.delete({ignoreNotFound: true});'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // [R7-P4.4E.11B.1A 신규] 네임스페이스 축에서 본 2단계 소유자.
  //
  //   lifecycle **상세**(drain cap, current 보호, 목록 제거 실패 복구,
  //   rules 권위, return semantics)는 bankbook_durable_cleanup_test.dart
  //   가 소유한다. 이 파일은 네임스페이스 권위를 소유하므로, 큐에 들어가고
  //   큐에서 나오는 양쪽이 **같은 술어**를 거치는지만 여기서 고정한다.
  group('BANK-*-20 2단계 소유자가 네임스페이스 술어를 거친다', () {
    test('BANK-DEL-20 삭제가 Phase 1 helper + drain 을 쓴다', () {
      final d = deleter();
      expect(d, contains('await srvResetBankStateWithCleanupOwner('));
      expect(d, contains('await srvDrainBankbookCleanup(callerUid, "callableDeleteBankInfo")'));
      expect(d, isNot(contains('oldImageUrl.match(')));
      expect(d, isNot(contains('decodeURIComponent(pathMatch[1])')));
    });

    test('BANK-UPD-20 계좌 변경이 같은 두 소유자를 쓴다', () {
      final u = updater();
      expect(u, contains('await srvResetBankStateWithCleanupOwner('));
      expect(u, contains('await srvDrainBankbookCleanup(callerUid, "callableUpdateBankAccount")'));
    });

    test('BANK-NS-20 큐 입구·출구가 모두 통장사본 술어를 본다', () {
      final c = collector();
      expect(c, contains('const ok = srvResolveOwnedBankbookStoragePath(uid, raw);'));
      expect(c, contains('if (ok === null) { skipped++; continue; }'));
      expect(c, contains('data?.["bankbookImagePath"]'));
      expect(c, contains('data?.["bankbookImageUrl"]'));
      expect(c, contains('const paths = new Set<string>();'));
      // 출구에서도 본다 — 목록이 오염돼도 다른 서류를 지우지 않는다.
      expect(drain(), contains('if (!srvIsOwnedBankbookStoragePath(uid, p)) {'));
    });
  });

  group('BANK-X-xx 교체 권위 · cross-artifact · 비변경 (§15~§17·§38·§41·§46)', () {
    test('BANK-X-01 교체 시 지울 경로는 서버가 검증해서 돌려준다 (§16)', () {
      final w = writer();
      expect(w, contains('const prevRaw = (cur["bankbookImagePath"] as string | undefined) ?? (cur["bankbookImageUrl"] as string | undefined);'));
      expect(w, contains('const prevSafe = srvResolveOwnedBankbookStoragePath(callerUid, prevRaw);'));
      expect(w, contains('safePrevPath = (prevSafe !== null && prevSafe !== storagePath) ? prevSafe : null;'),
          reason: '새 경로와 같으면 null — 현재 것을 지우지 않는다');
      // [R7-P4.4E.11B.1A 갱신] 응답에 `cleanupPending` 이 더해졌다 —
      //   교체도 같은 durable owner 를 쓰게 됐기 때문이다.
      //   `previousBankbookPath` 는 구버전 클라이언트 호환으로 유지된다.
      expect(w, contains('previousBankbookPath: safePrevPath,'));
      expect(w, contains('cleanupPending: bbDrain.pendingAfter > 0,'));
      expect(w, contains('admin.firestore.FieldValue.arrayUnion(safePrevPath)'),
          reason: '포인터 교체와 같은 트랜잭션에서 cleanup owner 를 등록한다');
    });

    test('BANK-X-02 클라이언트는 서버가 준 값만 지운다 (§17)', () {
      expect(screen, contains("(markResult.data as Map)['previousBankbookPath'] as String?"));
      expect(screen, contains('await _storageService.deleteImage(prev);'));
      // 로컬 모델 값을 믿고 지우는 경로가 사라졌다.
      expect(screen, isNot(contains('final oldPath = user.bankbookImagePath;')));
      expect(screen, isNot(contains('final oldUrl = user.bankbookImageUrl;')));
      // 경로 문법을 클라이언트에 복제하지 않았다.
      expect(screen, isNot(contains("startsWith('users/")));
    });

    test('BANK-X-03 신분증·사업자등록증 네임스페이스는 건드리지 않았다', () {
      // 각 artifact 가 자기 술어를 그대로 쓴다.
      expect(cf, contains('function srvIsOwnedIdDocumentStoragePath('));
      expect(cf, contains('function srvIsOwnedBusinessStoragePath('));
      expect(cf, contains('function srvIsOwnedStoragePath('),
          reason: '신분증·사업자등록증이 쓰는 기존 술어는 남는다');
      // 신분증 writer 는 여전히 자기 술어를 쓴다.
      final idWriter = _flat(_codeOf(_slice(raw,
          'export const callableMarkIdCardVerified', '[SEC-IDCARD-EXIST]')));
      expect(idWriter, contains('srvIsOwnedIdDocumentStoragePath(callerUid, directPath)'));
      expect(idWriter, isNot(contains('Bankbook')));
    });

    test('BANK-X-04 사업자등록증 writer 는 자기 접두를 유지한다', () {
      final lic = _flat(_codeOf(_slice(raw,
          'export const callableRegisterBusinessLicense', 'BUSINESS_ADMIN 만')));
      expect(lic, contains(r'storagePath.startsWith(`users/${callerUid}/businessLicense_`)'));
      expect(lic, isNot(contains('Bankbook')));
    });

    test('BANK-X-05 OCR/match 정책 비변경 (§41)', () {
      // 통장 OCR·holder·alias·match 어휘를 이번 patch 가 건드리지 않았다.
      final w = writer();
      expect(w, contains('srvEvaluateMatchStatus(bbDoc.evidence, {requireName: false})'),
          reason: 'requireName:false 통장 정책 그대로');
      expect(w, contains('MATCH_SOURCE_CLIENT_OCR'));
      expect(w, contains('MATCH_ASSURANCE_CLIENT_EVIDENCE'));
    });

    test('BANK-X-06 account delete·business image·contracts 비변경 (§42·§46)', () {
      // 이번 patch 가 손대지 않은 경계를 확인한다.
      expect(cf, contains('export const callableDeleteAccountFinal'));
      expect(cf, isNot(contains('srvIsOwnedBankbookStoragePath(uid, path)')),
          reason: '계정 삭제 sweep 에 통장 술어를 끼워 넣지 않았다');
      final bizDel = _flat(_codeOf(_slice(raw,
          'export const onBusinessDeleted = onDocumentDeleted(', '\n// ═══')));
      expect(bizDel, isNot(contains('Bankbook')));
    });

    test('BANK-X-07 readiness getter 는 변경하지 않았다 (§14 보고 대상)', () {
      final model = _flat(_codeOf(_src('lib/models/core/user_model.dart')));
      expect(model, contains('bool get hasWageDocumentsReady => hasBankAccount && hasBankbookDocument;'));
    });
  });
}
