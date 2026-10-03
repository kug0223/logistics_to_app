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
  group('BANK-DEL-0x 삭제 lifecycle (§19~§28)', () {
    test('BANK-DEL-01 canonical path 를 후보로 수집한다 (B2 핵심)', () {
      final d = deleter();
      expect(d, contains('userSnap.data()?.bankbookImagePath as string | undefined,'),
          reason: 'V3 canonical 포인터가 수집되지 않으면 물리 삭제가 일어나지 않는다');
    });

    test('BANK-DEL-02 legacy URL 도 독립 후보다 (§21)', () {
      final d = deleter();
      expect(d, contains('userSnap.data()?.bankbookImageUrl as string | undefined,'));
      // `path ?? url` 우선순위가 아니라 **둘 다** 돈다.
      expect(d, contains('for (const raw of ['));
      expect(d, isNot(contains('bankbookImagePath ?? ')));
    });

    test('BANK-DEL-03·04·05 후보마다 resolve+validate 를 거친다', () {
      final d = deleter();
      expect(d, contains('const ok = srvResolveOwnedBankbookStoragePath(callerUid, raw);'));
      expect(d, contains('if (ok === null) {'));
      expect(d, contains('bankDelSkippedForeign++;'));
      // 검증 없는 삭제 경로가 사라졌다.
      expect(d, isNot(contains('oldImageUrl.match(')));
      expect(d, isNot(contains('decodeURIComponent(pathMatch[1])')));
    });

    test('BANK-DEL-06 중복 후보는 한 번만 지운다', () {
      expect(deleter(), contains('const bankDelCandidates = new Set<string>();'));
    });

    test('BANK-DEL-07 not-found 는 성공 동치다 (§28)', () {
      expect(deleter(), contains('.delete({ignoreNotFound: true});'));
    });

    test('BANK-DEL-08 실제 Storage 오류면 Firestore 를 건드리지 않고 실패한다 (§22)', () {
      final d = deleter();
      final delAt = d.indexOf('.delete({ignoreNotFound: true});');
      final throwAt = d.indexOf('"unavailable",');
      final fsAt = d.indexOf('bankName: admin.firestore.FieldValue.delete(),');
      expect(delAt, greaterThan(0));
      expect(throwAt, greaterThan(delAt));
      expect(fsAt, greaterThan(throwAt),
          reason: '물리 삭제 → (실패 시 throw) → Firestore 정리 순서');
      expect(d, isNot(contains('Storage 삭제 실패 (무시)')),
          reason: '삼키고 성공으로 끝내는 경로가 남아 있으면 안 된다');
    });

    test('BANK-DEL-09·10 재호출로 복구된다 (§23)', () {
      final d = deleter();
      // Storage 는 not-found 로 지나가고 Firestore 정리만 다시 시도된다.
      expect(d, contains('.delete({ignoreNotFound: true});'));
      // Firestore update 실패를 삼키지 않는다 — await 그대로 전파한다.
      //   Storage 삭제 쪽 catch 는 의도된 것이다(rethrow 해서 Firestore 를
      //   건드리지 않는다). 그래서 **Firestore 정리 구간만** 본다.
      expect(d, contains('await db.collection("users").doc(callerUid).update({'));
      final fsBlock = _flat(_codeOf(_slice(raw,
          'await db.collection("users").doc(callerUid).update({\n      bankName:',
          'return {success: true};')));
      expect(fsBlock, isNot(contains('catch')),
          reason: 'Firestore 정리를 try/catch 로 감싸 성공으로 끝내면 안 된다');
      // Storage 쪽 catch 는 rethrow 한다 — 삼키지 않는다.
      expect(d, contains('throw new HttpsError( "unavailable",'));
    });

    test('BANK-DEL-11 canonical state cleanup 은 그대로다 (§25)', () {
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
    });

    test('BANK-DEL-12 invalid 포인터 때문에 계좌 삭제가 막히지 않는다 (§24)', () {
      final d = deleter();
      final skipAt = d.indexOf('bankDelSkippedForeign++;');
      final fsAt = d.indexOf('bankName: admin.firestore.FieldValue.delete(),');
      expect(skipAt, greaterThan(0));
      expect(fsAt, greaterThan(skipAt),
          reason: '건너뛰고도 Firestore 정리는 진행한다');
      expect(d, isNot(contains('if (bankDelSkippedForeign > 0) { throw')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BANK-X-xx 교체 권위 · cross-artifact · 비변경 (§15~§17·§38·§41·§46)', () {
    test('BANK-X-01 교체 시 지울 경로는 서버가 검증해서 돌려준다 (§16)', () {
      final w = writer();
      expect(w, contains('const prevRaw = (cur["bankbookImagePath"] as string | undefined) ?? (cur["bankbookImageUrl"] as string | undefined);'));
      expect(w, contains('const prevSafe = srvResolveOwnedBankbookStoragePath(callerUid, prevRaw);'));
      expect(w, contains('safePrevPath = (prevSafe !== null && prevSafe !== storagePath) ? prevSafe : null;'),
          reason: '새 경로와 같으면 null — 현재 것을 지우지 않는다');
      expect(w, contains('return {success: true, previousBankbookPath: safePrevPath};'));
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
