// [PREDEVICE-LIFECYCLE-CONTRACT-PDF-ACCESS §8] 서명 완료 계약서 PDF 의 **현행**
// 접근 계약을 정확히 고정한다.
//
//   왜 "고정"인가
//     이 Phase 의 판정은 **BLOCKER** 다 — 계약서 PDF 는 아직 영구 bearer URL 로
//     배포된다. 고치는 것(발급을 callable Signed URL 로 돌리는 것)은 **공유 방식
//     변경 + 기존 링크 무효화**를 수반하므로 승인 전에는 손대지 않는다(§7).
//     그 사이에 이 파일이 두 가지를 한다:
//       ① 지금 무엇이 참인지 못박아, 고칠 때 이 테스트가 **반드시 함께** 바뀌게 한다
//       ② 이미 지켜지고 있는 것(Firestore 인가·list 차단·Storage SDK 차단·
//          snapshot 불변)이 조용히 약해지지 않게 막는다
//
//   선례: `test/bankbook_no_permanent_url_test.dart` — 통장사본은 같은 결함을
//   이미 끊었다(영구 URL 제거 → 1시간 Signed URL callable). 계약서만 남았다.
//
//   실제 계약서·실제 토큰·실제 개인정보를 쓰지 않는다. 소스 계약만 읽는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnPath = 'functions/src/index.ts';
const _storageRules = 'storage.rules';
const _firestoreRules = 'firestore.rules';
const _signScreen = 'lib/screens/contract/contract_sign_screen.dart';
const _histScreen = 'lib/screens/business_admin/historical_contract_detail_screen.dart';
const _service = 'lib/services/contract_service.dart';
const _model = 'lib/models/core/employment_contract_model.dart';

String _read(String p) => File(p).readAsStringSync();

/// 주석 줄을 지운다 — 표지는 코드에서만 찾는다.
String _codeOf(String raw) => raw
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

String _sliceOf(String raw, String from, String to) {
  final i = raw.indexOf(from);
  if (i < 0) throw StateError('시작 표지를 찾지 못함: $from');
  final j = raw.indexOf(to, i + from.length);
  if (j < 0) throw StateError('끝 표지를 찾지 못함: $to');
  return raw.substring(i, j);
}

void main() {
  final fn = _read(_fnPath);
  final fnCode = _codeOf(fn);
  final storage = _codeOf(_read(_storageRules));
  final firestore = _codeOf(_read(_firestoreRules));

  // ════════════════════════════════════════════════════════════════
  // 1. 발급 — 지금은 영구 다운로드 토큰 URL 이다 (BLOCKER 의 본체)
  // ════════════════════════════════════════════════════════════════

  group('CPA-1 PDF 발급 형태 — 단계 A: 경로 + 레거시 URL 동시 기록', () {
    test('CPA-01 단계 A — PDF 토큰을 유지하고 전환 지점을 표시한다', () {
      final worker = _sliceOf(fn, 'export const callableFinalizeWorkerSignature',
          'export const callableFinalizeEmployerSignature');
      // [REMEDIATION.3 §2] 단계 A 는 토큰을 **유지한다** — 구버전 앱이
      //   계약 문서의 pdfUrl 로 신규 계약서를 열어야 한다. 끊으면 업데이트
      //   전 사용자가 방금 서명한 자기 계약서를 못 본다.
      expect(_flat(worker), contains(
          '_saveContractArtifact(pdfStoragePath, pdfBytes, "application/pdf", '
          'crypto.randomBytes(16).toString("hex"))'));
      // 단계 C 전환 지점이 표시돼 있어야 한다 — 한 곳만 바꾸면 되도록.
      expect(worker, contains('STAGE-C-SWITCH'),
          reason: '전환 지점 표지가 없으면 단계 C 에서 무엇을 바꿀지 흩어진다');
      // 헬퍼는 빈 토큰이면 메타데이터를 붙이지 않는다(단계 C 대비).
      final save = _sliceOf(fnCode, 'async function _saveContractArtifact(',
          'async function _deleteOwnAttemptArtifact(');
      expect(_flat(save), contains('downloadToken.length > 0 ?'),
          reason: '단계 C 에서 빈 토큰을 넘기면 메타데이터가 붙지 않아야 한다');
    });

    test('CPA-02 완료 계약은 경로를 canonical 로 쓰고 레거시 URL 도 함께 쓴다', () {
      final upd = _sliceOf(fn,
          'tx.update(contractRef, {\n          status: "completed",', '});');
      final f = _flat(upd);
      // canonical — 신규 앱의 Signed URL 발급 근거.
      expect(f, contains('pdfStoragePath: computedPdfPath'));
      // 단계 A — 구버전 앱 열람용. 단계 C 에서 지운다.
      expect(f, contains('pdfUrl: computedPdfUrl'));
      expect(f, contains('STAGE-C-SWITCH'),
          reason: '지울 줄에 표지가 없으면 단계 C 에서 놓친다');
    });

    test('CPA-03 서명 CF 응답이 경로와 레거시 URL 을 함께 돌려준다', () {
      final worker = _sliceOf(fn, 'export const callableFinalizeWorkerSignature',
          'export const callableFinalizeEmployerSignature');
      final f = _flat(worker);
      // 신규 앱은 경로만 쓰고, 구버전 앱은 URL 을 쓴다.
      expect(f, contains('pdfStoragePath: computedPdfPath'));
      expect(f, contains('pdfUrl: computedPdfUrl'));
    });

    test('CPA-04 계약서 전용 Signed URL callable 이 있다', () {
      // 다른 민감 서류 6종의 선례가 유지되는지도 같이 본다.
      for (final has in [
        'callableGetIdCardSignedUrl',
        'callableGetBankbookSignedUrl',
        'callableGetApplicantDocumentUrl',
        'callableGetTaxIdentityIdCardUrl',
        'callableGetPayrollBankbookUrl',
        'callableGetBusinessLicenseSignedUrl',
        'callableGetContractPdfSignedUrl',
      ]) {
        expect(fnCode, contains('export const $has'),
            reason: '$has 가 없다');
      }
    });

    test('CPA-05 pdfHash 는 여전히 CF 가 계산한다', () {
      // URL 방식이 바뀌어도 이 보호는 그대로여야 한다.
      expect(fn, contains('pdfHash: pdfHash'));
      expect(_flat(fnCode).contains('pdfHash: request.data.pdfHash'), isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 1-B. Signed URL callable — 인가·수명·경로 주입
  // ════════════════════════════════════════════════════════════════

  group('CPA-1B Signed URL 발급 계약', () {
    final cf = _sliceOf(fn, 'export const callableGetContractPdfSignedUrl',
        'export const callableGetContractsByBiz');
    final cfFlat = _flat(cf);

    test('CPA-06 입력은 contractId 뿐 — 경로·사업장을 클라이언트에서 받지 않는다', () {
      expect(cfFlat, contains('const {contractId} = (request.data ?? {}) as {contractId?: string}'));
      // 경로·사업장을 입력으로 받으면 그것이 접근 근거가 된다.
      expect(cfFlat.contains('storagePath?: string'), isFalse);
      expect(cfFlat.contains('businessId?: string'), isFalse);
    });

    test('CPA-07 비로그인은 거부된다', () {
      expect(cfFlat, contains('if (!request.auth)'));
      expect(cfFlat, contains('unauthenticated'));
      expect(cf, contains('enforceAppCheck: true'));
    });

    test('CPA-08 PDF 와 서명이 같은 인가 판정 하나를 쓴다', () {
      // [REMEDIATION.3 §3] 같은 계약에서 PDF 는 열리고 서명은 막히는(또는
      //   반대의) 상태가 생기지 않게 판정을 한 함수로 모았다.
      expect(cfFlat, contains('await srvAssertContractViewAccess(callerUid, data)'));
      final shared = _sliceOf(fnCode,
          'async function srvAssertContractViewAccess(', '\n}');
      final sf = _flat(shared);
      expect(sf, contains('workerId === callerUid'));
      expect(sf, contains('await assertBizAdmin(callerUid, businessId)'));
      expect(sf, contains('perms["canManageContract"] !== true'));
      expect(sf, contains('permission-denied'));
      // 서명 callable 도 같은 함수를 쓴다.
      final sig = _sliceOf(fn, 'export const callableGetContractSignatureUrl',
          'export const callableGetContractsByBiz');
      expect(_flat(sig),
          contains('await srvAssertContractViewAccess(callerUid, data)'));
    });

    test('CPA-09 권한 판정이 계약 목록 CF 와 같은 한 벌이다', () {
      // 같은 capability 를 서로 다르게 해석하면 화면과 링크가 어긋난다.
      final byBiz = _sliceOf(fn, 'export const callableGetContractsByBiz',
          'const cap = Math.min(');
      for (final token in [
        'assertBizAdmin',
        'callerRole === "BUSINESS_ADMIN"',
        'canManageContract',
      ]) {
        expect(_flat(byBiz), contains(token));
        expect(cfFlat, contains(token), reason: '$token 해석이 갈렸다');
      }
    });

    test('CPA-10 Signed URL 수명은 15분이다', () {
      expect(cfFlat, contains('const ttlSeconds = 15 * 60'));
      expect(cfFlat, contains('expires: Date.now() + ttlSeconds * 1000'));
      expect(cfFlat, contains('return {signedUrl, expiresInSeconds: ttlSeconds}'));
    });

    test('CPA-11 다른 계약의 경로를 주입할 수 없다', () {
      // 저장된 경로라도 **이 계약의** 경로인지 서명 직전에 본다.
      expect(cfFlat, contains('srvIsOwnedContractPdfPath(storagePath, contractId)'));
      final pred = _sliceOf(fnCode, 'function srvIsOwnedContractPdfPath(', '\n}');
      expect(_flat(pred), contains('path.includes("..")'));
      expect(_flat(pred), contains('m[1] === contractId'),
          reason: '경로의 contractId 와 요청 contractId 가 같아야 한다');
    });

    test('CPA-12 파일 없음과 PDF 미생성을 다른 말로 돌려준다', () {
      expect(cfFlat, contains('아직 계약서 PDF가 생성되지 않았습니다'));
      expect(cfFlat, contains('계약서 파일이 존재하지 않습니다'));
      expect(cfFlat, contains('const [exists] = await file.exists()'));
    });

    test('CPA-13 URL·토큰을 로그에 남기지 않는다', () {
      // 로그는 "누가 무엇을 열었다"까지만 말한다.
      expect(cfFlat, contains(r'uid=${callerUid} contract=${contractId}'));
      expect(cfFlat.contains(r'${signedUrl}'), isFalse);
      expect(cfFlat.contains('token='), isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 1-C. 레거시 호환 — 기존 계약도 열려야 한다
  // ════════════════════════════════════════════════════════════════

  group('CPA-1C 레거시 계약', () {
    test('CPA-14 pdfStoragePath 가 없으면 레거시 URL 에서 경로만 역산한다', () {
      final cf = _sliceOf(fn, 'export const callableGetContractPdfSignedUrl',
          'export const callableGetContractsByBiz');
      expect(_flat(cf), contains('srvContractPdfPathFromLegacyUrl(data["pdfUrl"])'));
      final parser = _sliceOf(fnCode,
          'function srvContractPdfPathFromLegacyUrl(', '\n}');
      final p = _flat(parser);
      expect(p, contains('const marker = "/o/"'));
      // `?` 앞까지만 떼므로 토큰은 읽지 않는다.
      expect(p, contains('const q = rawUrl.indexOf("?", i)'));
      expect(p.contains('token'), isFalse,
          reason: '파서가 토큰을 다루면 로그·응답에 샐 수 있다');
    });

    test('CPA-15 보존 계약 상세는 자기 인가를 유지한 채 Signed URL 을 만든다', () {
      // 사업장이 삭제된 뒤의 열람이라 assertBizAdmin 이 성립하지 않는다.
      final hist = _sliceOf(fn, 'export const callableGetHistoricalContractById',
          'return serializeFirestoreData(detail)');
      final f = _flat(hist);
      expect(f, contains('data.historicalOwnerUid !== callerUid'));
      expect(f, contains('srvHistoricalContractPdfSignedUrl(contractId.trim(), data)'));
      final helper = _sliceOf(fnCode,
          'async function srvHistoricalContractPdfSignedUrl(', '\n}');
      expect(_flat(helper), contains('expires: Date.now() + 15 * 60 * 1000'));
      expect(_flat(helper), contains('srvIsOwnedContractPdfPath(path, contractId)'));
    });

    test('CPA-16 목록 응답에서 경로는 빠지고, 레거시 URL 은 전환 기간 남는다', () {
      final strip = _sliceOf(fnCode, 'function srvStripContractPdfUrl(', '\n}');
      final f = _flat(strip);
      // 경로는 클라이언트가 들 이유가 없다 — 접근 근거가 되면 안 된다.
      expect(f, contains('delete data["pdfStoragePath"]'));
      expect(f, contains('pdfAvailable: available'));
      // [REMEDIATION.2 §4] `pdfUrl` 은 **지우지 않는다.** 구버전 앱이 그것으로
      //   기존 계약서를 연다 — 지우면 이미 서명한 계약서를 못 보게 된다.
      //   레거시 이관이 그 필드를 삭제하면 이 분기는 저절로 사라진다.
      expect(f.contains('delete data["pdfUrl"]'), isFalse,
          reason: '구버전 앱의 기존 계약 열람이 끊긴다');
      // 두 목록 CF 가 모두 이 헬퍼를 지난다.
      expect(fnCode, contains('items: docs.map((d) => srvStripContractPdfUrl(d.id, d.data()))'));
      expect(fnCode, contains('contracts: docs.map((d) => srvStripContractPdfUrl(d.id, d.data()))'));

      // [SIG-CUTOVER] 서명도 **같은 모양**이다 — 경로는 빼고 있다/없다만 준다.
      expect(f, contains('delete data["employerSignatureStoragePath"]'));
      expect(f, contains('delete data["workerSignatureStoragePath"]'));
      expect(f, contains('employerSignatureAvailable,'));
      expect(f, contains('workerSignatureAvailable,'));
      // 서명 URL 도 전환 기간 남긴다 — 구버전 앱이 그것으로 서명을 그린다.
      expect(f.contains('delete data["employerSignatureUrl"]'), isFalse,
          reason: '구버전 앱의 서명 렌더가 끊긴다');
      expect(f.contains('delete data["workerSignatureUrl"]'), isFalse);
    });

    test('CPA-16B 신규 계약은 pdfAvailable 로 공유 버튼 근거를 얻는다', () {
      // 신규 계약은 응답에 pdfUrl·pdfStoragePath 가 둘 다 없다.
      //   그래서 boolean 하나가 유일한 근거다 — 모델이 그것을 읽어야 한다.
      final model = _codeOf(_read(_model));
      expect(model, contains('final bool pdfAvailable;'));
      expect(model, contains("pdfAvailable: d['pdfAvailable'] == true"));
      final getter = _sliceOf(model, 'bool get hasPdf =>', ';');
      expect(_flat(getter), contains('pdfAvailable ||'),
          reason: 'hasPdf 가 pdfAvailable 을 보지 않으면 신규 계약에서 버튼이 사라진다');
    });

    test('CPA-16C 서명도 같은 근거 구조를 쓴다 (SIG-CUTOVER)', () {
      final model = _codeOf(_read(_model));
      expect(model, contains('final bool employerSignatureAvailable;'));
      expect(model, contains('final bool workerSignatureAvailable;'));
      expect(model,
          contains("employerSignatureAvailable: d['employerSignatureAvailable'] == true"));
      // 레거시 계약은 남아 있는 URL 로, 신규 계약은 boolean 으로 판정한다.
      final emp = _sliceOf(model, 'bool get hasEmployerSignature =>', ';');
      expect(_flat(emp), contains('employerSignatureAvailable ||'));
      expect(_flat(emp), contains('employerSignatureUrl != null'),
          reason: '레거시 계약에서 서명란이 빈다');
      final wrk = _sliceOf(model, 'bool get hasWorkerSignature =>', ';');
      expect(_flat(wrk), contains('workerSignatureAvailable ||'));
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 1-D. 레거시 이관 — 네 단계를 구별한다
  // ════════════════════════════════════════════════════════════════

  group('CPA-1D 레거시 이관 계약', () {
    test('CPA-25 완료 판정은 네 단계 전부를 요구한다', () {
      final f = _sliceOf(fnCode,
          'function srvIsContractPdfMigrationComplete(', '\n}');
      final flat = _flat(f);
      // pdfStoragePath 존재만으로 완료라고 하지 않는다.
      for (final stage in ['m.pathAt', 'm.revokedAt', 'm.verifiedAt',
        'm.urlClearedAt']) {
        expect(flat, contains(stage), reason: '$stage 단계가 판정에서 빠졌다');
      }
      expect(flat, contains('&&'), reason: '네 단계는 모두 충족돼야 한다');
    });

    test('CPA-26 순서는 경로 → 회수 → 확인 → URL 정리다', () {
      final f = _sliceOf(fnCode, 'async function srvMigrateOneContractPdf(',
          '\n}');
      final pathAt = f.indexOf('"pdfMigration.pathAt"');
      final revoke = f.indexOf('firebaseStorageDownloadTokens: ""');
      final verify = f.indexOf('"pdfMigration.verifiedAt"');
      final clear = f.indexOf('pdfUrl: admin.firestore.FieldValue.delete()');
      expect(pathAt, greaterThan(-1));
      expect(revoke, greaterThan(pathAt), reason: '경로를 먼저 기록해야 한다');
      expect(verify, greaterThan(revoke), reason: '회수 뒤에 확인한다');
      expect(clear, greaterThan(verify),
          reason: 'URL 을 먼저 지우면 경로 역산 근거를 잃는다');
    });

    test('CPA-27 토큰 회수 실패는 완료로 표시하지 않는다', () {
      final f = _flat(_sliceOf(fnCode,
          'async function srvMigrateOneContractPdf(', '\n}'));
      expect(f, contains('error: "revokeFailed"'));
      expect(f, contains('complete: false'));
      // 실패 시 revokedAt 을 쓰지 않는다 — 사유만 남긴다.
      expect(f, contains(r'"pdfMigration.lastError": `revoke: ${revokeError}`'));
    });

    test('CPA-28 옛 URL 이 아직 열리면 URL 을 지우지 않는다', () {
      final f = _flat(_sliceOf(fnCode,
          'async function srvMigrateOneContractPdf(', '\n}'));
      expect(f, contains('error: "stillOpen"'));
      // 네트워크 실패를 "막혔다"로 읽지 않는다.
      expect(f, contains('blocked = false'));
    });

    test('CPA-29 PDF 파일·해시·서명·snapshot 을 건드리지 않는다', () {
      final f = _sliceOf(fnCode, 'async function srvMigrateOneContractPdf(',
          '\n}');
      // 계약 내용에 해당하는 필드를 쓰지 않는다.
      for (final forbidden in ['pdfHash', 'workerSignatureUrl',
        'employerSignatureUrl', 'snapshot']) {
        expect(f.contains(forbidden), isFalse,
            reason: '이관이 $forbidden 를 건드린다');
      }
      // Storage 파일을 지우지 않는다 — 법정 보존. 끊는 것은 토큰 하나다.
      expect(f.contains('.file(path).delete('), isFalse,
          reason: '이관이 계약서 파일을 지운다');
      expect(f.contains('bucket().deleteFiles'), isFalse);
      // Firestore 에서 지우는 것은 레거시 URL 필드 하나뿐이다.
      final deletes = RegExp(r'FieldValue\.delete\(\)').allMatches(f).length;
      expect(deletes, 1, reason: 'FieldValue.delete() 가 pdfUrl 외에도 쓰인다');
      expect(_flat(f), contains('pdfUrl: admin.firestore.FieldValue.delete()'));
    });

    test('CPA-30 배치 callable 은 SUPER_ADMIN 전용이고 기본이 dryRun 이다', () {
      final cf = _sliceOf(fn, 'export const callableMigrateContractPdfPaths',
          'export const callableGetContractPdfSignedUrl');
      final f = _flat(cf);
      expect(f, contains('!== "SUPER_ADMIN"'));
      expect(f, contains('const dryRun = rawDryRun !== false'),
          reason: '기본이 dryRun 이어야 실수로 회수되지 않는다');
      // 이미 끝난 계약은 건너뛴다(멱등).
      //   [TARGET-DISCOVERY] 완료 판정이 `srvClassifyContract` 로 옮겨갔다 —
      //   PDF·고용주·근로자를 **각각** 보기 때문이다. 묻는 성질은 그대로다:
      //   "손댈 것이 없으면 건너뛴다".
      expect(f, contains('srvContractNeedsMigration(cls)'));
      expect(f, contains('const cls = srvClassifyContract(d.id, data)'));
      // 부분 실패가 전체를 멈추지 않는다.
      expect(f, contains('failed++'));
    });

    test('CPA-30B 일괄 탐색이 pdfUrl 에 의존하지 않는다 (TARGET-DISCOVERY)', () {
      // 예전에는 `orderBy("pdfUrl")` 이었다. PDF 이관 ④단계가 그 필드를
      //   지우는 순간, 서명이 남은 계약이 **검색에서 사라졌다**.
      final cf = _sliceOf(fn, 'export const callableMigrateContractPdfPaths',
          'export const callableGetContractPdfSignedUrl');
      final f = _flat(cf);
      expect(f.contains('.orderBy("pdfUrl")'), isFalse,
          reason: 'pdfUrl 이 지워진 계약이 검색에서 빠진다');
      expect(f, contains('orderBy(admin.firestore.FieldPath.documentId())'),
          reason: '문서 id 는 모든 문서가 가지므로 누락이 없다');
      // 커서는 대상이 0건인 페이지에서도 전진해야 한다.
      expect(f, contains('scannedIds = snap.docs.map((d) => d.id)'));
      expect(f, contains('nextCursor'));
      // 훑은 수와 대상 수를 따로 돌려준다 — "없다"와 "못 찾았다"의 구별.
      expect(f, contains('scannedDocs: scannedIds.length'));
      expect(f, contains('candidates: docs.length'));
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 2. 이미 지켜지는 것 — 약해지면 안 된다
  // ════════════════════════════════════════════════════════════════

  group('CPA-2 URL 노출 경로 가드', () {
    test('CPA-05 Storage SDK 직접 읽기는 막혀 있다', () {
      final block = _sliceOf(storage,
          'match /contracts/{contractId}/{allPaths=**} {', '}');
      expect(_flat(block), contains('allow read: if false'));
      expect(_flat(block), contains('allow update: if false'));
      expect(_flat(block), contains('allow delete: if false'));
    });

    test('CPA-06 계약 문서 get 은 당사자·사업장 관리자·canManageContract 로 제한된다', () {
      final block = _sliceOf(firestore,
          'match /employment_contracts/{contractId} {', 'allow list:');
      final f = _flat(block);
      expect(f, contains('isOwner(resource.data.workerId)'));
      expect(f, contains('isAdminOf(resource.data.businessId)'));
      expect(f, contains('subAdminCanManageContract(resource.data.businessId)'));
      expect(f, contains('isLoggedIn()'),
          reason: '비로그인에게 계약 문서를 열어 주면 URL 이 그대로 유출된다');
    });

    test('CPA-07 클라이언트 직접 list 는 차단된다 (CF 전용)', () {
      final block = _sliceOf(firestore,
          'match /employment_contracts/{contractId} {', 'allow create:');
      expect(_flat(block), contains('allow list: if false'));
    });

    test('CPA-08 과거 계약 요약 목록은 pdfUrl 을 내보내지 않는다', () {
      // 목록 단계에서 URL 을 흘리면 인가 범위가 목록 권한까지 넓어진다.
      final list = _sliceOf(fn,
          'export const callableGetHistoricalContracts',
          'export const callableGetHistoricalContractById');
      expect(list.contains('pdfAvailable'), isTrue,
          reason: '요약은 boolean 으로만 알린다');
      expect(_flat(list).contains('pdfUrl: data.pdfUrl'), isFalse,
          reason: '요약 목록에 실제 URL 이 실리면 안 된다');
    });

    test('CPA-09 과거 계약 상세는 historicalOwnerUid 본인에게만 응답한다', () {
      final detail = _sliceOf(fn,
          'export const callableGetHistoricalContractById', '\n// ──');
      final f = _flat(detail);
      expect(f, contains('data.historicalOwnerUid !== callerUid'));
      // 없는 것과 권한 없는 것을 같은 말로 돌려준다(존재 노출 방지).
      expect(f, contains('not-found'));
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 3. 조회는 인증 없는 평문 GET 이다 — 이것이 bearer 성질의 증거
  // ════════════════════════════════════════════════════════════════

  group('CPA-3 클라이언트 조회 방식 — 열 때마다 권한을 받는다', () {
    test('CPA-17 서명 화면은 계약 문서의 URL 을 쓰지 않고 callable 로 받는다', () {
      final s = _codeOf(_read(_signScreen));
      final share = _sliceOf(s, 'Future<void> _sharePdf() async {', 'Future<void> _sign()');
      final f = _flat(share);
      expect(f, contains('_service.fetchContractPdfUrl(widget.contract.id)'));
      // 문서에 저장된 URL 을 직접 열지 않는다.
      expect(f.contains('widget.contract.pdfUrl'), isFalse,
          reason: '문서의 영구 URL 로 되돌아갔다');
      expect(f, contains('widget.contract.hasPdf'));
    });

    test('CPA-18 받은 URL 을 계약서에 저장하지 않는다', () {
      final svc = _codeOf(_read(_service));
      final m = _sliceOf(svc, 'Future<String> fetchContractPdfUrl(', '\n  }');
      final f = _flat(m);
      expect(f, contains("httpsCallable('callableGetContractPdfSignedUrl'"));
      expect(f, contains("data?['signedUrl'] as String?"));
      // copyWith·set·update 로 흘려 보내지 않는다 — 일시 사용이다.
      expect(f.contains('copyWith'), isFalse);
      expect(f.contains('.update('), isFalse);
    });

    test('CPA-19 서명 완료 저장은 경로를 쓰고 URL 을 쓰지 않는다', () {
      final svc = _codeOf(_read(_service));
      final f = _flat(svc);
      expect(f, contains("cfData?['pdfStoragePath'] as String?"));
      expect(f, contains('pdfStoragePath: cfPdfPath'));
      expect(f.contains("cfData?['pdfUrl']"), isFalse,
          reason: 'CF 응답의 URL 을 다시 읽기 시작했다');
    });

    test('CPA-20 지난 계약 화면은 만료 시 재발급해 다시 시도한다', () {
      final s = _codeOf(_read(_histScreen));
      final share = _sliceOf(s, 'Future<void> _sharePdf() async {', 'Widget');
      final f = _flat(share);
      expect(f, contains('http.get(Uri.parse(url))'));
      // 만료된 링크로 끝내지 않는다 — 상세를 다시 읽어 새 URL 을 받는다.
      expect(f, contains('await _loadDetail()'));
      expect(f, contains('final retryUrl = _detail?.pdfUrl'));
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 4. 계약 내용·snapshot 불변 (§6 전제)
  // ════════════════════════════════════════════════════════════════

  group('CPA-4 서명 완료 계약의 불변', () {
    test('CPA-21 완료 전이는 서명·해시·시각만 쓰고 임금 조항을 건드리지 않는다', () {
      final upd = _sliceOf(fn,
          'tx.update(contractRef, {\n          status: "completed",', '});');
      final f = _flat(upd);
      for (final field in [
        'status: "completed"',
        'workerSignatureUrl: sigUrl',
        'workerSignatureHash: computedSigHash',
        'pdfStoragePath: computedPdfPath',
        'pdfHash: pdfHash',
      ]) {
        expect(f, contains(field));
      }
      // 임금·근무시간·조항은 이 전이에서 다시 쓰이지 않는다.
      for (final forbidden in ['hourlyWage', 'articles:', 'slots:', 'baseWage']) {
        expect(f.contains(forbidden), isFalse,
            reason: '완료 전이가 $forbidden 을 덮어쓰면 서명 당시 내용이 바뀐다');
      }
    });

    test('CPA-22 PDF 해시는 CF 가 Storage 에서 직접 계산한다', () {
      // 클라이언트가 보낸 해시를 믿으면 다른 파일로 바꿔 끼울 수 있다.
      expect(fn, contains('SEC-CONTRACT-PDF-HASH'));
      expect(_flat(fnCode).contains('pdfHash: request.data.pdfHash'), isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 5. 회수 수단의 존재 여부 — 지금은 없다
  // ════════════════════════════════════════════════════════════════

  // ════════════════════════════════════════════════════════════════
  // 4-B. 서명 PNG — 아직 영구 bearer URL 이다 (이번 범위 밖, 기록)
  // ════════════════════════════════════════════════════════════════

  group('CPA-4B 서명 이미지 접근', () {
    test('CPA-31 서명 PNG 도 경로를 canonical 로 저장한다 (단계 A)', () {
      // [REMEDIATION.3 §3] 서명 PNG 도 PDF 와 같은 결함을 갖고 있었다.
      //   단계 A 에서는 **경로를 함께 저장**하고 열람 callable 을 제공한다.
      //   토큰 자체는 유지한다 — 끊으면 구버전 근로자가 사업주 서명을
      //   내려받지 못해 **서명 자체를 못 한다**(PDF 생성이 실패한다).
      expect(fnCode, contains('workerSignatureStoragePath: sigStoragePath'));
      expect(fnCode, contains('employerSignatureStoragePath: storagePath'));
      // 단계 C 전환 지점 표지.
      final worker = _sliceOf(fn, 'export const callableFinalizeWorkerSignature',
          'export const callableFinalizeEmployerSignature');
      expect(worker, contains('STAGE-C-SWITCH'));
      // 레거시 호환용 URL 은 아직 남는다.
      expect(fnCode, contains('workerSignatureUrl: sigUrl'));
    });

    test('CPA-31B 서명 전용 Signed URL callable 이 있다', () {
      final sig = _sliceOf(fn, 'export const callableGetContractSignatureUrl',
          'export const callableGetContractsByBiz');
      final f = _flat(sig);
      expect(f, contains('role !== "employer" && role !== "worker"'),
          reason: 'role 을 제한하지 않으면 임의 경로 필드를 고를 수 있다');
      expect(f, contains('srvIsOwnedContractSigPath(storagePath, contractId, role)'),
          reason: '계약·역할이 모두 맞는 경로여야 한다');
      expect(f, contains('const ttlSeconds = 15 * 60'));
      expect(f, contains('아직 서명이 등록되지 않았습니다'));
      expect(f, contains('서명 파일이 존재하지 않습니다'));
      // 로그에 URL·토큰이 없다.
      expect(f.contains(r'${signedUrl}'), isFalse);
      // 역할 술어가 경로의 역할까지 본다.
      final pred = _sliceOf(fnCode, 'function srvIsOwnedContractSigPath(', '\n}');
      expect(_flat(pred), contains('m[2] === role'));
      expect(_flat(pred), contains('path.includes("..")'));
    });

    test('CPA-32 서명 PNG 소비자는 영구 URL 을 쓰지 않는다 (SIG-CUTOVER)', () {
      // [R8P6-SIG-CUTOVER] 이 셀은 전환 **전** 상태를 못박고 있었다:
      //   미리보기가 `imageUrl: employerSignatureUrl`, PDF 생성기가
      //   `http.get(Uri.parse(employerSignatureUrl))`. 둘 다 영구 토큰 URL 이다.
      //   이제 소비자는 계약 id·역할만 알고, 링크는 그때의 권한으로 받는다.
      final sign = _codeOf(_read(_signScreen));

      // ① 미리보기는 계약·역할로 링크를 받는다.
      final block = _sliceOf(sign, 'child: hasUrl', 'hasBase64');
      expect(_flat(block), contains('_ContractSignatureImage('));
      expect(_flat(block).contains('employerSignatureUrl'), isFalse,
          reason: '영구 URL 이 다시 렌더 입력으로 돌아왔다');

      // ② 렌더 입력에 서명 URL 필드가 없다 — 존재 여부만 받는다.
      expect(sign.contains('final String? employerSignatureUrl;'), isFalse,
          reason: 'ContractTemplateWidget 이 URL 을 다시 받는다');
      expect(sign, contains('final bool hasEmployerSignature;'));
      expect(sign, contains('final bool hasWorkerSignature;'));

      // ③ PDF 생성기는 네트워크를 모른다 — 바이트를 받아 그린다.
      final pdf = _codeOf(_read('lib/screens/contract/contract_pdf_builder.dart'));
      expect(_flat(pdf).contains('http.get'), isFalse,
          reason: '빌더가 다시 URL 을 직접 가져온다');
      expect(_flat(pdf), contains('Uint8List? employerSignatureBytes'));

      // ④ 바이트는 권한을 확인하는 경로로만 들어온다.
      final svc = _codeOf(_read('lib/services/contract_service.dart'));
      expect(_flat(svc), contains('callableGetContractSignatureUrl'));
      final signCall = _sliceOf(sign, 'if (widget.contract.hasEmployerSignature)',
          'final pdfBytes = await ContractPdfBuilder.build(');
      expect(_flat(signCall),
          contains('_service.fetchContractSignatureBytes('));
    });

    test('CPA-33 Storage rules 는 서명 PNG 직접 읽기를 막는다 (토큰 경로만 열림)', () {
      final block = _sliceOf(storage,
          'match /contracts/{contractId}/{allPaths=**} {', '}');
      expect(_flat(block), contains('allow read: if false'));
      // 즉 PDF 와 **같은 구조**다 — 토큰 URL 만이 실제 열람 경로다.
    });
  });

  group('CPA-5 링크 회수 — 신규는 발급 안 함 / 레거시는 별도 단계', () {
    test('CPA-23 토큰 무효화 수단은 이 저장소에 이미 있다 (레거시 회수에 쓸 것)', () {
      // [TOKEN-REVOKE] 신분증은 영구 토큰을 **끊는다**:
      //   setMetadata({metadata: {firebaseStorageDownloadTokens: ""}})
      // 즉 "회수 수단이 없다"가 아니라 "계약서에 쓰지 않았다"가 정확한 사실이다.
      expect(fnCode, contains('firebaseStorageDownloadTokens: ""'),
          reason: '신분증 쪽 회수 패턴이 사라졌다 — 선례가 깨졌다');
      final idCard = _sliceOf(fn, 'export const callableMarkIdCardVerified',
          'export const callableGetIdCard');
      expect(_flat(idCard), contains('firebaseStorageDownloadTokens: ""'),
          reason: '신분증 업로드 확정이 토큰을 끊는 경로');
      // 레거시 일괄 회수 선례도 있다.
      expect(fnCode, contains('export const callableMigrateIdCardPaths'),
          reason: '레거시 토큰 일괄 회수 선례');

      // 그런데 계약서 완료 경로에는 회수가 없다.
      final worker = _sliceOf(fn, 'export const callableFinalizeWorkerSignature',
          'export const callableFinalizeEmployerSignature');
      // 서명 CF 자체는 회수를 하지 않는다 — 신규는 애초에 토큰을 안 심는다.
      expect(worker.contains('firebaseStorageDownloadTokens: ""'), isFalse,
          reason: '서명 경로가 회수를 겸하기 시작했다 — 책임이 섞인다');
      // [REMEDIATION.2 §2] 레거시 회수는 **전용 callable** 이 맡는다.
      expect(fnCode, contains('export const callableMigrateContractPdfPaths'),
          reason: '레거시 회수 경로가 사라졌다');
    });

    test('CPA-24 계약 무효화(void)가 PDF 파일을 지우지 않는다 (보존 의무)', () {
      // 계약을 void 해도 파일과 URL 은 그대로다 — 보존 의무상 파일은 남겨야 하지만,
      // 그것이 "링크가 계속 열려야 한다"는 뜻은 아니다.
      final v = _sliceOf(fn, 'export const callableVoidContract',
          'export const callableVoidContractWithApplications');
      expect(v.contains('firebaseStorageDownloadTokens'), isFalse);
      expect(v.contains('pdfUrl: null'), isFalse,
          reason: 'void 가 pdfUrl 을 지우기 시작했다면 이 판정을 다시 쓰라');
    });
  });
}
