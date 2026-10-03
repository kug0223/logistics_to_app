// [R7-P4.4E.11B.1B] 통장사본 재업로드가 옛 파일의 주인을 클라이언트에게
// 떠넘기지 않는다
//
// 삭제(callableDeleteBankInfo)와 계좌 변경(callableUpdateBankAccount)은
// 11B.1A 에서 durable owner 를 얻었다. 그런데 **가장 흔한 경로**는 그 둘이
// 아니다 — 통장사본을 다시 올리는 것이다.
//
//   old current A → new B 업로드 → callableMarkBankbookVerified(B)
//
// 이때 A 는 더 이상 current 가 아니지만 민감 bytes 로 남는다. 그 bytes 의
// 주인이 누구인지가 이 파일의 질문이다.
//
//   금지: 서버는 B 를 current 로 바꾸고 A 의 경로를 응답으로 돌려주며
//         실제 삭제는 클라이언트 best-effort 에만 맡긴다.
//         → 응답 수신 직후 앱이 죽으면 A 는 **untracked orphan**.
//
//   요구: B 를 current 로 만드는 **그 쓰기 안에서** A 가 cleanup 주인에게
//         등록된다. 클라이언트가 응답을 아예 읽지 않아도 A 는 추적된다.
//
// 이 파일이 고정하는 것
//   BANK-REPL-0x           Phase 1 atomic (B current + A pending)
//   BANK-REPL-CRASH-01     클라이언트가 죽어도 A 는 추적된다
//   BANK-REPL-OLDCLIENT-01 구버전 client 중복 삭제가 무해하다
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
const _modelPath = 'lib/models/core/user_model.dart';

void main() {
  final raw = _src(_cfPath);

  /// 재업로드 writer 전체.
  String writer() => _flat(_codeOf(_slice(
      raw, 'export const callableMarkBankbookVerified', '\n// ──')));

  /// 그 안의 Phase 1 트랜잭션 본문만 — 응답·drain 과 섞이지 않게.
  String tx() => _flat(_codeOf(_slice(
      raw,
      'const bbVersions = await db.runTransaction(async (tx) => {',
      'return {bb: nextBb, acc: curAcc};')));

  /// Phase 1 트랜잭션 **이후** 구간 — drain·응답.
  String afterTx() => _flat(_codeOf(_slice(
      raw, 'return {bb: nextBb, acc: curAcc};', '\n// ──')));

  String drain() => _flat(_codeOf(_slice(
      raw, 'async function srvDrainBankbookCleanup(', '\n}')));

  String reader() => _flat(_codeOf(_slice(
      raw, 'export const callableGetBankbookSignedUrl', '\n// ──')));

  // ══════════════════════════════════════════════════════════════
  group('BANK-REPL-0x 재업로드 durable ownership (§4·§7·§9)', () {
    test('BANK-REPL-01 old A → new B: B 가 current, A 가 pending 이 된다', () {
      final t = tx();
      // B 가 canonical current 가 된다.
      expect(t, contains('bankbookImagePath: storagePath,'));
      // A 는 같은 쓰기에서 cleanup 주인에게 등록된다.
      expect(t, contains(r'[BANKBOOK_CLEANUP_FIELD]: admin.firestore.FieldValue.arrayUnion(safePrevPath),'));
      expect(raw, contains(
          'const BANKBOOK_CLEANUP_FIELD = "bankbookCleanupPendingPaths";'));
    });

    test('BANK-REPL-02 Phase 1 원자성 — B current + A pending 없음 상태 불가', () {
      final t = tx();
      // 트랜잭션 경계 안이고, 쓰기는 하나다.
      expect(writer(), contains('await db.runTransaction(async (tx) => {'));
      expect('tx.update(bbUserRef,'.allMatches(t).length, 1,
          reason: '쓰기가 둘이면 "B current 성공 + A pending 실패"가 가능해진다');
      // arrayUnion 이 그 **같은** update 객체 안에 있다.
      final updAt = t.indexOf('tx.update(bbUserRef, {');
      final unionAt = t.indexOf(r'[BANKBOOK_CLEANUP_FIELD]:');
      final curAt = t.indexOf('bankbookImagePath: storagePath,');
      expect(updAt, greaterThan(-1));
      expect(unionAt, greaterThan(updAt));
      expect(curAt, greaterThan(updAt));
      // Phase 1 밖에 users 쓰기가 또 있으면 원자성이 깨진다. 특정 문자열
      //   하나를 막는 것으로는 부족하다 — 커밋 이후 구간에 Firestore 쓰기
      //   자체가 없어야 한다.
      final a = afterTx();
      expect(a, isNot(contains('.update(')),
          reason: '커밋 뒤 추가 쓰기가 있으면 중간 상태가 관측된다');
      expect(a, isNot(contains('.set(')));
      expect(a, contains('srvDrainBankbookCleanup('),
          reason: '이 구간이 실제로 커밋 이후를 가리키는지 확인 — 공허 단정 방지');
    });

    test('BANK-REPL-03 client delete 가 0이어도 A 의 주인은 존재한다 (§14·§15)', () {
      // 서버 상태에 A 가 남는 것은 트랜잭션 커밋의 결과다 — 응답 처리와
      //   무관하다. 응답 필드는 **힌트**이고 주인이 아니다.
      final t = tx();
      expect(t, contains(r'[BANKBOOK_CLEANUP_FIELD]:'));
      // 등록이 응답/클라이언트 조건에 걸려 있지 않다.
      expect(t, isNot(contains('request.data.deleteOld')));
      expect(t, isNot(contains('if (clientWillDelete')));
    });

    test('BANK-REPL-04 A Storage 삭제 실패 → B current 유지 + A pending 유지', () {
      final d = drain();
      expect(d, contains('out.failed++;'));
      expect(d, contains('continue;'),
          reason: '실패 항목이 목록에 남아야 다음 drain 이 다시 집는다');
      // §17 — drain 실패가 B 등록을 되돌리지 않는다.
      final a = afterTx();
      expect(a, isNot(contains('throw new HttpsError( "unavailable",')),
          reason: 'B 는 이미 current 다 — 던지면 재제출로 artifact C 가 생긴다');
      expect(a, contains('return { success: true,'));
    });

    test('BANK-REPL-05 A delete 성공 + marker 제거 실패 → pending 유지 (§11)', () {
      final d = drain();
      final delAt = d.indexOf('.delete({ignoreNotFound: true});');
      final remAt = d.indexOf('admin.firestore.FieldValue.arrayRemove(p),');
      expect(delAt, greaterThan(0));
      expect(remAt, greaterThan(delAt), reason: '삭제 → 목록 제거 순서');
      // 제거 실패도 failed 로 집계되고 항목은 남는다.
      expect(d, contains('cleanup 목록 제거 실패'));
    });

    test('BANK-REPL-06 다음 drain 이 not-found 로 수렴한다 (§11·§20)', () {
      expect(drain(), contains('.delete({ignoreNotFound: true});'),
          reason: '이미 없는 object 가 성공 동치가 아니면 항목이 영구 잔존한다');
    });

    test('BANK-REPL-07 새 current B 는 절대 지워지지 않는다 (§12·§21)', () {
      // ① 등록 시점 — 옛 경로가 새 경로와 같으면 queue 에 넣지 않는다.
      final t = tx();
      expect(t, contains(
          'safePrevPath = (prevSafe !== null && prevSafe !== storagePath) ? prevSafe : null;'));
      // ② drain 시점 — fresh 로 읽은 current 와 같으면 지우지 않는다.
      final d = drain();
      expect(d, contains('snap.data()?.["bankbookImagePath"] as string | undefined'));
      expect(d, contains('if (protectPath !== null && p === protectPath) {'));
      expect(d, contains('out.skippedCurrent++;'));
    });

    test('BANK-REPL-08 poisoned 옛 포인터는 pending 에 넣지 않는다 (§6·§23)', () {
      final t = tx();
      // 옛 포인터도 통장사본 술어를 거친다 — 신분증이면 null 이 된다.
      expect(t, contains(
          'const prevSafe = srvResolveOwnedBankbookStoragePath(callerUid, prevRaw);'));
      // null 이면 등록도 삭제도 없다. 그래도 B 는 current 가 된다.
      expect(t, contains('(prevSafe !== null &&'));
      expect(t, contains('bankbookImagePath: storagePath,'));
      // 재업로드 전용 경로 파서를 새로 만들지 않았다 (§23).
      expect(writer(), isNot(contains('.match(/\\/o\\/')));
      expect(
          'srvResolveOwnedBankbookStoragePath('.allMatches(writer()).length,
          greaterThanOrEqualTo(2),
          reason: '새 입력과 옛 포인터가 같은 술어를 쓴다');
    });

    test('BANK-REPL-09 기존 pending X 는 보존된다 — [X, A] (§28)', () {
      expect(tx(), contains('admin.firestore.FieldValue.arrayUnion(safePrevPath),'),
          reason: 'arrayUnion 이 아니면 기존 대기 항목을 덮어쓴다');
      expect(tx(), isNot(contains(r'[BANKBOOK_CLEANUP_FIELD]: [safePrevPath]')));
    });

    test('BANK-REPL-10 path/url 이 같은 object 면 논리적으로 한 건이다 (§25)', () {
      // 재업로드 writer 는 `path ?? url` 로 한 후보만 본다.
      expect(tx(), contains(
          'const prevRaw = (cur["bankbookImagePath"] as string | undefined) ?? (cur["bankbookImageUrl"] as string | undefined);'));
      // 그리고 arrayUnion 은 집합 의미다 — 이미 대기 중이면 중복되지 않는다.
      expect(tx(), contains('FieldValue.arrayUnion(safePrevPath),'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BANK-REPL-CRASH 클라이언트가 응답을 처리하지 못해도 안전하다 (§14·§15)', () {
    test('BANK-REPL-CRASH-01 서버 finalize 만으로 A 가 추적된다', () {
      // 이 셀이 이번 단계의 closure gate 다.
      //
      //   callableMarkBankbookVerified 성공
      //     → 응답 수신 직후 앱 crash
      //     → client physical delete 0
      //   이어도 A 는 server durable state 에 남아야 한다.
      //
      // 증거: A 등록이 **커밋 전에** 트랜잭션 쓰기 안에서 일어난다.
      //   응답 생성·drain·클라이언트 동작은 모두 그 뒤다.
      final t = tx();
      expect(t, contains(r'[BANKBOOK_CLEANUP_FIELD]: admin.firestore.FieldValue.arrayUnion(safePrevPath),'));

      final w = writer();
      final txAt = w.indexOf('await db.runTransaction(async (tx) => {');
      final drainAt = w.indexOf('await srvDrainBankbookCleanup(callerUid, "callableMarkBankbookVerified")');
      final retAt = w.indexOf('return { success: true,');
      expect(txAt, greaterThan(0));
      expect(drainAt, greaterThan(txAt), reason: 'drain 은 Phase 1 뒤다');
      expect(retAt, greaterThan(drainAt), reason: '응답은 마지막이다');

      // 그리고 등록이 클라이언트 삭제 성공에 의존하지 않는다 — 서버는
      //   클라이언트의 삭제 결과를 다시 받지 않는다.
      expect(w, isNot(contains('clientDeleted')));
      expect(w, isNot(contains('previousBankbookPathDeleted')));
    });

    test('BANK-REPL-CRASH-02 previousBankbookPath 는 주인이 아니라 힌트다 (§13)', () {
      final a = afterTx();
      // 응답에는 남아 있다 — 구버전 client 호환 + 중복 정리 힌트.
      expect(a, contains('previousBankbookPath: safePrevPath,'));
      expect(a, contains('cleanupPending: bbDrain.pendingAfter > 0,'));
      // 그러나 server queue 가 authoritative owner 다 — 응답을 만들기
      //   **전에** 이미 등록이 커밋됐다.
      final w = writer();
      expect(w.indexOf('FieldValue.arrayUnion(safePrevPath),'),
          lessThan(w.indexOf('previousBankbookPath: safePrevPath,')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BANK-REPL-OLDCLIENT 구버전 client 와 공존한다 (§19·§20)', () {
    test('BANK-REPL-OLDCLIENT-01 client 가 먼저 지워도 drain 이 수렴한다', () {
      // server: A pending 등록 → old client: A physical delete
      //   → later server drain: not-found 성공 → pending 제거
      final d = drain();
      expect(d, contains('.delete({ignoreNotFound: true});'),
          reason: 'not-found 를 실패로 보면 client 가 먼저 지운 항목이 영구 잔존한다');
      final delAt = d.indexOf('.delete({ignoreNotFound: true});');
      final remAt = d.indexOf('admin.firestore.FieldValue.arrayRemove(p),');
      expect(remAt, greaterThan(delAt));
      // 중복 삭제가 서로를 깨뜨리지 않는다 — drain 은 삭제 전에 존재
      //   확인을 하지 않는다. 확인하면 client 가 먼저 지운 경우를 실패로
      //   읽는다. (`.exists()` 는 이 파일 다른 writer 에 실재하는 패턴이라
      //   이 부정 단정은 공허하지 않다.)
      expect(d, isNot(contains('.exists();')));
      expect(_flat(_codeOf(raw)), contains('.exists();'),
          reason: '양성형이 어딘가 있어야 위 부정 단정이 의미를 가진다');
    });

    test('BANK-REPL-OLDCLIENT-02 client 삭제 대상은 서버가 검증한 값 하나다', () {
      final screen = _flat(_codeOf(
          _src('lib/screens/common/document_management_screen.dart')));
      expect(screen,
          contains("(markResult.data as Map)['previousBankbookPath'] as String?"));
      expect(screen, contains('await _storageService.deleteImage(prev);'));
      // 로컬 모델 값을 믿고 지우는 경로가 없다 — 새 current B 를 잘못
      //   잡을 수 있는 입구를 만들지 않았다 (§21·§36).
      expect(screen, isNot(contains('final oldPath = user.bankbookImagePath;')));
      expect(screen, isNot(contains('final oldUrl = user.bankbookImageUrl;')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BANK-REPL-4x 재업로드 후 truth (§40·§41)', () {
    test('BANK-REPL-40 signed URL 은 B 만 읽는다 — pending 은 fallback 아니다', () {
      final r = reader();
      expect(r, contains(
          'const bbPointer = (workerData.bankbookImagePath as string | undefined) ?? (workerData.bankbookImageUrl as string | undefined);'));
      expect(r, isNot(contains('bankbookCleanupPendingPaths')),
          reason: 'cleanup 대기 경로가 열람 source 가 되면 안 된다');
      expect(r, isNot(contains('BANKBOOK_CLEANUP_FIELD')));
      // 서명 직전 재검증은 그대로다.
      expect(r, contains(
          'const storagePath = srvResolveOwnedBankbookStoragePath(appUid, bbPointer);'));
    });

    test('BANK-REPL-41 readiness 는 B 기준이고 pending 과 무관하다', () {
      final model = _flat(_codeOf(_src(_modelPath)));
      expect(
        model.contains('bool get hasBankbookDocument => '
            '(bankbookImagePath != null && bankbookImagePath!.isNotEmpty) || '
            '(bankbookImageUrl != null && bankbookImageUrl!.isNotEmpty);'),
        true,
      );
      expect(model, isNot(contains('bankbookCleanupPendingPaths')),
          reason: 'cleanup ownership 은 readiness 가 아니다');
      // 서버 readiness 판정도 cleanup 필드를 보지 않는다.
      expect(_flat(_codeOf(raw)), contains(
          'const hasDoc = !!(u["bankbookImagePath"] ?? u["bankbookImageUrl"]);'));
    });

    test('BANK-REPL-42 replacement mutation semantics 무변경 (§34)', () {
      final t = tx();
      for (final f in [
        'bankbookDocumentVersion: nextBb,',
        'bankbookMatchStatus: bbMatchStatus,',
        'bankbookMatchEvidenceSource: MATCH_SOURCE_CLIENT_OCR,',
        'bankbookMatchAssurance: MATCH_ASSURANCE_CLIENT_EVIDENCE,',
        'bankbookMatchAccountVersion: curAcc,',
        'bankbookSelfCheck: bbDoc.evidence,',
        'bankbookDocumentState: bbDoc.state,',
        'bankbookReviewedBy: admin.firestore.FieldValue.delete(),',
      ]) {
        expect(t, contains(f), reason: '$f 가 바뀌면 안 된다');
      }
      // 계좌 버전은 재업로드가 올리지 않는다 — 통장사본만 바뀌었다.
      expect(t, isNot(contains('bankAccountVersion: admin.firestore.FieldValue.increment(1),')));
      // OCR·holder matching 정책을 재업로드가 바꾸지 않았다.
      expect(writer(), contains(
          'srvEvaluateMatchStatus(bbDoc.evidence, {requireName: false})'));
    });

    test('BANK-REPL-43 재업로드가 cleanup 필드를 노출하지 않는다 (§22)', () {
      // 사용자 조회 응답에서 제거되는 민감 필드 목록에 들어 있다.
      expect('"bankbookCleanupPendingPaths",'.allMatches(_flat(_codeOf(raw))).length,
          greaterThanOrEqualTo(2),
          reason: 'getUsersBatch·getAllUsers 양쪽에서 지워져야 한다');
      // rules 권위도 그대로다.
      final rules = _src('firestore.rules');
      expect("'bankbookCleanupPendingPaths'".allMatches(rules).length,
          greaterThanOrEqualTo(2));
      expect(rules, contains(
          "request.resource.data.get('bankbookCleanupPendingPaths', null) == null"));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // [§24 READ 결과 — 고정]
  //
  //   재업로드 writer 는 옛 후보를 `path ?? url` 로 **하나만** 본다.
  //   삭제·계좌변경은 `srvCollectOwnedBankbookPaths` 로 **둘 다 독립**
  //   수집한다. 비대칭이다.
  //
  //   그 비대칭이 실제 누수가 되려면 "path 와 url 이 서로 다른 valid
  //   bankbook object" 상태가 존재해야 한다. writer 전수로 확인한 결과
  //   그 상태를 만드는 writer 가 없다. 이 셀이 그 전제를 고정한다 —
  //   누군가 `bankbookImageUrl` 에 값을 쓰는 writer 를 추가하면 여기서
  //   깨지고, 그때 재업로드도 독립 수집으로 바꿔야 한다.
  group('BANK-REPL-5x 비대칭이 안전한 이유를 고정한다 (§24)', () {
    test('BANK-REPL-50 CF 는 bankbookImageUrl 에 값을 쓰지 않는다', () {
      final code = _codeOf(raw);
      // 값 설정 패턴이 없다 — 삭제만 있다.
      expect(code, isNot(contains('bankbookImageUrl: imageUrl')));
      expect(code, isNot(contains('bankbookImageUrl: rawBbInput')));
      expect(code, isNot(contains('bankbookImageUrl: url')));
      // 삭제 writer 세 곳은 그대로 있다.
      expect(
          'bankbookImageUrl: admin.firestore.FieldValue.delete(),'
              .allMatches(_flat(code))
              .length,
          3,
          reason: 'MarkBankbookVerified·DeleteBankInfo·UpdateBankAccount');
    });

    test('BANK-REPL-51 backfill 은 url 과 같은 object 를 path 로 승격한다', () {
      final b = _flat(_codeOf(_slice(
          raw, 'export const callableBackfillBankbookImagePath', '\n// ──')));
      // path 는 url 에서 환원한 값이다 → 둘은 같은 physical object.
      expect(b, contains(
          'const storagePath = srvResolveOwnedBankbookStoragePath(doc.id, imageUrl);'));
      expect(b, contains('bankbookImagePath: storagePath,'));
      // url 을 다른 값으로 바꾸지 않는다.
      expect(b, isNot(contains('bankbookImageUrl:')));
    });

    test('BANK-REPL-52 클라이언트는 두 포인터를 직접 쓸 수 없다', () {
      final rules = _src('firestore.rules');
      expect(rules, contains("'bankbookImagePath', 'bankbookImageUrl',"));
      expect(rules, contains(
          "request.resource.data.get('bankbookImagePath', null) == null"));
      expect(rules, contains(
          "request.resource.data.get('bankbookImageUrl', null) == null"));
    });
  });
}
