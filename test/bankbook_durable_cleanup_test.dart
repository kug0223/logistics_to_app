// [R7-P4.4E.11B.1A] "사용자가 다시 호출하면 수렴한다"는 durable recovery 가 아니다
//
// 두 번의 설계를 거쳐 여기 왔다.
//
//   ① Firestore 먼저 → Storage 실패
//      = 포인터·소유자 동시 소멸 → **영구 untracked orphan** (B2)
//   ② Storage 먼저 → Firestore 실패
//      = 포인터는 남고 bytes 는 없음 → **canonical dangling pointer**
//        (readiness 는 true, 파일은 없음)
//
// 둘 다 "사용자가 재시도하면 수렴"에 기댔다. 사용자가 재시도하지 않으면
// 아무도 모른다. 그래서 시스템 자체에 **정확한 경로 + 대기 여부 + 재시도
// 주인**이 남아야 한다.
//
// 허용 상태는 셋뿐이다.
//   A CURRENT          포인터 있음 + object 있음
//   B CLEANUP_PENDING  readiness 포인터에서 제거 + 경로가 추적됨
//   C CLEANED          포인터 없음 + 대기 없음 + object 없음
//
// 금지:
//   포인터 있음 + object 없음 + cleanup owner 없음
//   포인터 없음 + object 있음 + cleanup owner 없음
//
// 이 파일이 고정하는 것
//   BANK-CLEAN-RULE  제어 필드는 CF 전용이다
//   BANK-CLEAN-0x    Phase 1 atomic (canonical + owner 동시)
//   BANK-CLEAN-1x    Phase 2 drain · not-found · 실제 실패 추적
//   BANK-CLEAN-2x    목록 제거 실패 복구
//   BANK-CLEAN-3x    cross-artifact · current-path 보호
//   BANK-UPD-DUR-xx  계좌 변경 return/version semantics
//   BANK-DEL-DUR-xx  삭제 partial/retry semantics
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
const _rulesPath = 'firestore.rules';
const _modelPath = 'lib/models/core/user_model.dart';
const _screenPath = 'lib/screens/common/document_management_screen.dart';

void main() {
  final raw = _src(_cfPath);
  final cf = _flat(_codeOf(raw));
  final rules = _codeOf(_src(_rulesPath));

  String phase1() => _flat(_codeOf(_slice(
      raw, 'async function srvResetBankStateWithCleanupOwner(', '\n}')));
  String drain() => _flat(_codeOf(_slice(
      raw, 'async function srvDrainBankbookCleanup(', '\n  return out;\n}')));
  String updater() => _flat(_codeOf(_slice(
      raw, 'export const callableUpdateBankAccount', '\n// ──')));
  String deleter() => _flat(_codeOf(_slice(
      raw, 'export const callableDeleteBankInfo', '\n// ──')));
  String marker() => _flat(_codeOf(_slice(
      raw, 'export const callableMarkBankbookVerified', '\n// ──')));
  String reader() => _flat(_codeOf(_slice(
      raw, 'export const callableGetBankbookSignedUrl', '\n// ──')));

  const field = 'bankbookCleanupPendingPaths';

  // ══════════════════════════════════════════════════════════════
  group('BANK-CLEAN-RULE 제어 필드는 CF 전용 (§7·§8)', () {
    String selfUpdate() => _flat(_slice(rules,
        'allow update: if isLoggedIn() &&\n                       isOwner(userId)', ']);'));
    String superUpdate() => _flat(_slice(rules,
        'allow update: if isSuperAdmin() &&', ']);'));

    test('BANK-CLEAN-RULE-01·02 owner inject/clear DENY', () {
      expect(selfUpdate(), contains("'$field'"),
          reason: 'denylist 는 열거되지 않은 필드를 허용한다 — 빠지면 그대로 열린다');
    });

    test('BANK-CLEAN-RULE-03 SUPER_ADMIN direct update DENY', () {
      expect(superUpdate(), contains("'$field'"));
    });

    test('BANK-CLEAN-RULE-04 CREATE with field DENY', () {
      expect(rules, contains("request.resource.data.get('$field', null) == null"));
    });

    test('BANK-CLEAN-RULE-05 무관한 프로필 수정은 영향 없다', () {
      final b = selfUpdate();
      for (final ok in ['profileImageUrl', 'address', 'regionKeys']) {
        expect(b, isNot(contains("'$ok'")), reason: '$ok 는 계속 허용되어야 한다');
      }
    });

    test('BANK-CLEAN-RULE-06 기존 canonical 보호가 회귀하지 않았다 (§46)', () {
      final b = selfUpdate();
      for (final keep in ['bankbookImagePath', 'bankbookImageUrl',
        'idDocumentAttemptSeq', 'idDocumentOrphanPaths', 'isIdVerified']) {
        expect(b, contains("'$keep'"), reason: '$keep 보호가 사라지면 안 된다');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BANK-CLEAN-0x Phase 1 atomic (§10·§11·§21·§22·§32)', () {
    test('BANK-CLEAN-01 canonical mutation 과 owner 등록이 한 트랜잭션이다', () {
      final p = phase1();
      expect(p, contains('return db.runTransaction(async (tx) => {'));
      expect(p, contains('const cur = (await tx.get(ref)).data() ?? {};'));
      expect(p, contains('const found = srvCollectOwnedBankbookPaths(uid, cur);'));
      expect(p, contains('tx.update(ref, write);'),
          reason: '패치와 목록 등록이 같은 쓰기에 들어간다');
      expect('tx.update('.allMatches(p).length, 1,
          reason: '두 번 쓰면 한쪽만 반영된 상태가 관측된다');
    });

    test('BANK-CLEAN-02 등록은 arrayUnion — 기존 대기를 덮지 않는다 (§21·§22)', () {
      final p = phase1();
      expect(p, contains('admin.firestore.FieldValue.arrayUnion(...found.paths)'));
      expect(p, contains('if (found.paths.size > 0) {'),
          reason: '없으면 필드를 만들지 않는다');
    });

    test('BANK-CLEAN-03 Phase 1 실패 시 물리 삭제가 실행되지 않는다 (§16·§32)', () {
      // drain 은 Phase 1 **뒤**에 온다. 트랜잭션이 던지면 거기서 끝난다.
      final u = updater();
      final p1 = u.indexOf('await srvResetBankStateWithCleanupOwner(');
      final p2 = u.indexOf('await srvDrainBankbookCleanup(');
      expect(p1, greaterThan(0));
      expect(p2, greaterThan(p1));
      final d = deleter();
      final dp1 = d.indexOf('await srvResetBankStateWithCleanupOwner(');
      final dp2 = d.indexOf('await srvDrainBankbookCleanup(');
      expect(dp1, greaterThan(0));
      expect(dp2, greaterThan(dp1));
      // Phase 1 앞에 Storage 삭제가 없다.
      expect(u.substring(0, p1), isNot(contains('.delete({ignoreNotFound')));
      expect(d.substring(0, dp1), isNot(contains('.delete({ignoreNotFound')));
    });

    test('BANK-CLEAN-04 invalid 포인터는 등록되지 않고 reset 은 진행된다 (§12)', () {
      final p = phase1();
      expect(p, contains('if (found.skipped > 0) {'));
      expect(p, isNot(contains('throw')),
          reason: 'INVALID_POINTER ≠ CLEANUP_PENDING ≠ STORAGE_FAILURE');
      // collector 가 invalid 를 걸러낸다.
      final c = _flat(_codeOf(_slice(
          raw, 'function srvCollectOwnedBankbookPaths(', '\n}')));
      expect(c, contains('const ok = srvResolveOwnedBankbookStoragePath(uid, raw);'));
      expect(c, contains('if (ok === null) { skipped++; continue; }'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BANK-CLEAN-1x Phase 2 drain (§13·§29·§33)', () {
    test('BANK-CLEAN-10·11 삭제 성공·not-found 모두 목록에서 제거된다', () {
      final d = drain();
      expect(d, contains('.delete({ignoreNotFound: true});'),
          reason: 'not-found 는 성공 동치');
      expect(d, contains('admin.firestore.FieldValue.arrayRemove(p)'));
      expect(d, contains('out.deleted++;'));
    });

    test('BANK-CLEAN-12 실제 삭제 실패는 항목을 남긴다 — 핵심 closure', () {
      final d = drain();
      final delIdx = d.indexOf('.delete({ignoreNotFound: true});');
      final catchIdx = d.indexOf('out.failed++;', delIdx);
      expect(catchIdx, greaterThan(delIdx));
      expect(d, contains('continue; '),
          reason: '항목을 남기고 다음으로 — 다음 drain 이 다시 시도한다');
      // 실패가 canonical 상태를 되돌리지 않는다 (drain 은 포인터를 안 만든다).
      expect(d, isNot(contains('bankbookImagePath:')));
    });

    test('BANK-CLEAN-13 drain 범위는 추적된 경로뿐이다 (§23)', () {
      final d = drain();
      expect(d, contains('snap.data()?.[BANKBOOK_CLEANUP_FIELD]'));
      expect(d, isNot(contains('getFiles(')),
          reason: 'users/{uid}/ 전체 열거 금지');
      expect(d, isNot(contains('prefix:')));
    });

    test('BANK-CLEAN-14 한 번에 처리량을 묶되 경로를 버리지 않는다 (§29)', () {
      final d = drain();
      expect(d, contains('.slice(0, BANKBOOK_CLEANUP_DRAIN_CAP)'));
      expect(cf, contains('const BANKBOOK_CLEANUP_DRAIN_CAP = 20;'));
      // cap 때문에 arrayRemove 되는 경로가 없다 — 제거는 삭제 성공 뒤에만.
      final rmIdx = d.indexOf('arrayRemove(p)');
      final delIdx = d.indexOf('.delete({ignoreNotFound: true});');
      expect(rmIdx, greaterThan(delIdx));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BANK-CLEAN-2x 목록 제거 실패 복구 (§15·§34)', () {
    test('BANK-CLEAN-20 삭제 성공 + 목록 제거 실패 → 항목 유지', () {
      final d = drain();
      final rmIdx = d.indexOf('arrayRemove(p)');
      final tail = d.substring(rmIdx);
      expect(tail, contains('out.failed++;'));
      expect(tail, contains('cleanup 목록 제거 실패'));
      // pendingAfter 를 깎지 않는다 → 다음 drain 이 집는다.
      final decIdx = d.indexOf('out.pendingAfter--;');
      expect(decIdx, greaterThan(0));
      expect(decIdx, lessThan(rmIdx + tail.indexOf('out.failed++;')),
          reason: '감소는 제거 성공 분기에만 있다');
    });

    test('BANK-CLEAN-21 다음 drain 은 not-found 로 수렴한다', () {
      expect(drain(), contains('.delete({ignoreNotFound: true});'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BANK-CLEAN-3x cross-artifact · current 보호 (§14·§35·§36·§42)', () {
    test('BANK-CLEAN-30 목록 항목도 통장사본 술어를 거친다 (§35)', () {
      final d = drain();
      expect(d, contains('if (!srvIsOwnedBankbookStoragePath(uid, p)) { out.skippedInvalid++; continue; }'));
    });

    test('BANK-CLEAN-31 current 경로는 절대 지우지 않는다 (§14·§36)', () {
      final d = drain();
      expect(d, contains('if (protectPath !== null && p === protectPath) { out.skippedCurrent++; continue; }'));
      // fresh 하게 읽는다 — 등록 시점 값이 아니라 drain 시점 값이다.
      expect(d, contains('const snap = await ref.get();'));
      expect(d, contains('snap.data()?.["bankbookImagePath"]'));
      final readIdx = d.indexOf('const snap = await ref.get();');
      final loopIdx = d.indexOf('for (const p of all.slice(');
      expect(loopIdx, greaterThan(readIdx));
    });

    test('BANK-CLEAN-32 새 통장사본 등록 후 drain 이 새 object 를 지키게 된다 (§42)', () {
      // MarkBankbookVerified 는 current 확정(트랜잭션) **뒤** drain 한다.
      final m = marker();
      final txIdx = m.indexOf('bankbookImagePath: storagePath,');
      final drainIdx = m.indexOf('await srvDrainBankbookCleanup(');
      expect(txIdx, greaterThan(0));
      expect(drainIdx, greaterThan(txIdx),
          reason: 'current 가 새 경로로 확정된 뒤 drain → fresh 보호가 B 를 지킨다');
    });

    test('BANK-CLEAN-33 signed URL 은 대기 경로를 fallback 으로 쓰지 않는다 (§40)', () {
      final r = reader();
      expect(r, isNot(contains(field)),
          reason: 'reader 는 current canonical 포인터만 본다');
      expect(r, contains('srvResolveOwnedBankbookStoragePath(appUid, bbPointer)'));
    });

    test('BANK-CLEAN-34 제어 필드가 generic DTO·모델·UI 에 없다 (§30)', () {
      expect(_src(_modelPath), isNot(contains(field)),
          reason: 'UserModel 에 넣지 않는다 — internal server state 다');
      expect(_src(_screenPath), isNot(contains(field)));
      expect(cf, contains('"$field",'),
          reason: 'getUsersBatch SENSITIVE_FIELDS 에 포함');
      expect('"$field",'.allMatches(cf).length, 2,
          reason: 'SENSITIVE_FIELDS 두 곳 모두');
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BANK-UPD-DUR 계좌 변경 return/version (§17·§18·§37·§43)', () {
    test('BANK-UPD-DUR-01 canonical update + 등록 + drain 순서', () {
      final u = updater();
      expect(u, contains('const bankUpdSkipped = await srvResetBankStateWithCleanupOwner('));
      expect(u, contains('await srvDrainBankbookCleanup(callerUid, "callableUpdateBankAccount")'));
    });

    test('BANK-UPD-DUR-02·03 drain 실패로 throw 하지 않는다 — version 중복 전진 금지', () {
      final u = updater();
      final drainIdx = u.indexOf('await srvDrainBankbookCleanup(');
      final tail = u.substring(drainIdx);
      expect(tail, isNot(contains('throw ')),
          reason: '던지면 사용자가 같은 계좌 변경을 반복해 version 이 또 +1 된다');
      expect(u, contains('return {success: true, cleanupPending: bankUpdDrain.pendingAfter > 0};'));
    });

    test('BANK-UPD-DUR-04 version semantics 불변 (§41)', () {
      final u = updater();
      expect(u, contains('bankAccountVersion: admin.firestore.FieldValue.increment(1),'));
      expect(u, contains('bankbookDocumentVersion: admin.firestore.FieldValue.increment(1),'));
      // cleanup 목록은 version 의미에 참여하지 않는다.
      expect(phase1(), isNot(contains('Version')));
    });

    test('BANK-UPD-DUR-05 invalid 포인터에도 계좌 변경이 성공한다 (§12)', () {
      final u = updater();
      expect(u, contains('skippedInvalidPointer=\${bankUpdSkipped}'));
      expect(u, isNot(contains('if (bankUpdSkipped > 0) { throw')));
    });

    test('BANK-UPD-DUR-06 통장사본 없으면 목록 변화가 없다 (§18)', () {
      expect(phase1(), contains('if (found.paths.size > 0) {'));
    });

    test('BANK-UPD-DUR-07 검증이 전부 끝난 뒤 mutation 을 시작한다 (§4)', () {
      final u = updater();
      final p1 = u.indexOf('await srvResetBankStateWithCleanupOwner(');
      for (final v in ['"은행명이 필요합니다."', '"계좌번호가 필요합니다."',
        '"지원자 계정만 급여 계좌를 등록할 수 있습니다."',
        '"사용자 이름이 등록되지 않았습니다."']) {
        final at = u.indexOf(v);
        expect(at, greaterThan(0), reason: v);
        expect(p1, greaterThan(at));
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BANK-DEL-DUR 삭제 partial/retry (§4·§19·§20·§38)', () {
    test('BANK-DEL-DUR-01 canonical delete + 등록 + drain', () {
      final d = deleter();
      expect(d, contains('await srvResetBankStateWithCleanupOwner( callerUid, "callableDeleteBankInfo"'));
      expect(d, contains('await srvDrainBankbookCleanup(callerUid, "callableDeleteBankInfo")'));
    });

    test('BANK-DEL-DUR-02·03 남아 있으면 성공이라 말하지 않는다 (§4)', () {
      final d = deleter();
      expect(d, contains('if (bankDelDrain.pendingAfter > 0) { throw new HttpsError( "unavailable",'));
      expect(d, contains('"통장사본 파일 정리가 끝나지 않았습니다. 잠시 후 다시 시도해주세요."'));
    });

    test('BANK-DEL-DUR-04 재호출이 version 을 두 번 올리지 않는다 (§19·§20)', () {
      final d = deleter();
      expect(d, contains('const bankDelAlreadyClean = [ "bankName", "accountNumber", "accountHolder", "bankbookImagePath", "bankbookImageUrl", ].every((f) => bankDelPre[f] === undefined);'));
      expect(d, contains('if (!bankDelAlreadyClean) {'),
          reason: '지울 것이 없으면 canonical mutation 을 다시 적용하지 않는다');
      // version 증가는 그 분기 안에만 있다.
      final cleanIdx = d.indexOf('if (!bankDelAlreadyClean) {');
      final verIdx = d.indexOf('bankAccountVersion: admin.firestore.FieldValue.increment(1),');
      expect(verIdx, greaterThan(cleanIdx));
    });

    test('BANK-DEL-DUR-05 이미 비었으면 drain 만 돈다', () {
      final d = deleter();
      final drainIdx = d.indexOf('await srvDrainBankbookCleanup(');
      final cleanIdx = d.indexOf('if (!bankDelAlreadyClean) {');
      expect(drainIdx, greaterThan(cleanIdx),
          reason: 'drain 은 분기 밖 — 어느 경로에서도 실행된다');
    });

    test('BANK-DEL-DUR-06 최종 0 이면 성공이다', () {
      expect(deleter(), contains('return {success: true};'));
    });

    test('BANK-DEL-DUR-07 canonical state cleanup 범위 불변 (§41)', () {
      final d = deleter();
      for (final f in [
        'bankName: admin.firestore.FieldValue.delete(),',
        'bankbookImagePath: admin.firestore.FieldValue.delete(),',
        'bankbookMatchStatus: admin.firestore.FieldValue.delete(),',
        'bankbookReviewNote: admin.firestore.FieldValue.delete(),',
      ]) {
        expect(d, contains(f), reason: '$f 가 바뀌면 안 된다');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BANK-CLEAN-4x readiness · 비변경 증명 (§39·§41·§51·§55)', () {
    test('BANK-CLEAN-40 cleanup pending 은 readiness 가 아니다 (§39)', () {
      final model = _flat(_codeOf(_src(_modelPath)));
      expect(model, contains('bool get hasWageDocumentsReady => hasBankAccount && hasBankbookDocument;'));
      expect(model, isNot(contains(field)));
      // Phase 1 이 포인터를 지우므로 readiness 는 즉시 false 가 된다.
      expect(deleter(), contains('bankbookImagePath: admin.firestore.FieldValue.delete(),'));
      expect(updater(), contains('bankbookImagePath: admin.firestore.FieldValue.delete(),'));
    });

    test('BANK-CLEAN-41 ID 문서 lifecycle 영향 0 (§51)', () {
      expect(cf, contains('function srvIsOwnedIdDocumentStoragePath('));
      expect(cf, contains('idDocumentAttemptSeq'));
      expect(cf, contains('idDocumentOrphanPaths'));
      // 통장 drain 이 신분증 목록을 건드리지 않는다.
      expect(drain(), isNot(contains('idDocument')));
      expect(phase1(), isNot(contains('idDocument')));
    });

    test('BANK-CLEAN-42 B6 account-delete 변경 0 (§52)', () {
      final acc = _flat(_codeOf(_slice(raw,
          'export const callableDeleteAccountFinal', '\n// ──')));
      expect(acc, isNot(contains(field)),
          reason: '이번 queue 를 계정 삭제에 억지로 연결하지 않는다');
    });

    test('BANK-CLEAN-43 OCR/match/alias 변경 0 (§55)', () {
      final m = marker();
      expect(m, contains('srvEvaluateMatchStatus(bbDoc.evidence, {requireName: false})'));
      expect(m, contains('MATCH_SOURCE_CLIENT_OCR'));
    });

    test('BANK-CLEAN-44 historical residue 자동 backfill 0 (§53)', () {
      // 어디에도 "포인터 없는 bankbook object 를 목록에 넣는" 코드가 없다.
      expect(cf, isNot(contains('prefix: `users/\${uid}/bankbook')));
      expect(drain(), isNot(contains('getFiles(')));
    });

    test('BANK-CLEAN-45 global scheduler 추가 0 (§25)', () {
      final before = _src(_cfPath);
      expect(before, isNot(contains('cleanup_jobs')));
      expect(before, isNot(contains('onSchedule("every 48 hours")')));
    });
  });
}
