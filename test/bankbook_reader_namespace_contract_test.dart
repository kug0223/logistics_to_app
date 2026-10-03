// [R7-P4.4E.11B.1C] 통장사본을 읽을 수 있는 입구가 셋인데 하나만 좁혀져 있었다
//
// 11B 는 통장사본 네임스페이스를 닫았다고 선언하며 이렇게 적었다 —
//
//   "writer 가 인정하는 경로 = reader 가 읽을 수 있는 경로
//    = delete 가 지울 수 있는 경로. 세 곳이 같은 술어를 쓴다."
//
// 그런데 **reader 가 셋**이었다. 좁혀진 것은 `callableGetBankbookSignedUrl`
// 하나였고, 나머지 둘은 `srvIsOwnedStoragePath`(= `users/{uid}/` 접두만)로
// 통과시켰다.
//
//   callableGetPayrollBankbookUrl
//     급여 권한(`canManageWage`)만 가진 열람자가, `bankbookImagePath` 에
//     같은 사용자의 신분증 경로가 들어 있으면 **신분증 bytes** 를 받는다.
//     감사 로그에는 `view_bankbook_image` 로 남는다. 신분증은 ID-CONSENT
//     Grant 가 필요한 서류인데 그 경계를 우회한다.
//
//   callableGetApplicantDocumentUrl
//     `documentType` 을 클라이언트가 보내고 두 분기가 한 변수로 합쳐진 뒤
//     같은 넓은 술어를 거쳤다. `documentType = BANKBOOK` 요청이 신분증을
//     돌려주면서 감사에는 BANKBOOK 으로 남는다 — 감사가 말하는 서류와
//     실제로 준 서류가 다르다.
//
// 왜 세 단계(11B·11B.1A·11B.1B)를 통과했나: 기존 `BANK-READ-01~06` 은
// reader **한 개**만 검사했고, reader 를 전수 열거하는 셀이 없었다.
// `BANK-NS-14`("술어 정의는 각각 하나다")도 정의 수만 세고 사용처를
// 세지 않았다.
//
// 그래서 이 파일은 개별 함수가 아니라 **inventory** 를 고정한다.
// 네 번째 byte-reader 를 추가하면서 exact validator 를 빼먹으면 여기서
// 깨진다.
//
// 이 파일이 고정하는 것
//   BANK-READ-INV-xx  reader 전수 + 전원 exact 술어 + 순서
//   BANK-PAYREAD-xx   급여 reader cross-artifact 거부·정상 허용
//   BANK-APPREAD-xx   지원자 reader BANKBOOK 분기 + ID 분기 무변경
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

/// 주석 줄을 지운다 — 표지는 코드에서만 찾는다.
bool _isCode(String l) {
  final t = l.trimLeft();
  return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
}

String _codeOf(String src) =>
    src.split(RegExp(r'\r?\n')).where(_isCode).join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

const _cfPath = 'functions/src/index.ts';

/// 세 reader 의 canonical 이름. inventory 가 이 집합과 정확히 일치해야 한다.
const _knownBankbookReaders = <String>{
  'callableGetBankbookSignedUrl',
  'callableGetPayrollBankbookUrl',
  'callableGetApplicantDocumentUrl',
};

/// `export const <name> = onCall(...)` 단위로 소스를 쪼갠다.
/// 주석은 소유자 판정에서만 제외하고, 본문은 원문을 유지한다.
Map<String, String> _exportBodies(String raw) {
  final lines = raw.split(RegExp(r'\r?\n'));
  final out = <String, List<String>>{};
  String? cur;
  for (final l in lines) {
    final m = RegExp(r'^export const (\w+) = (onCall|onDocument\w*|onSchedule|onRequest)')
        .firstMatch(l);
    if (m != null) {
      cur = m.group(1);
      out[cur!] = <String>[];
    } else if (RegExp(r'^export const \w+').hasMatch(l) ||
        RegExp(r'^(async )?function \w+').hasMatch(l)) {
      // 다른 top-level 선언을 만나면 현재 함수는 끝난 것으로 본다.
      cur = null;
    }
    if (cur != null) out[cur]!.add(l);
  }
  return out.map((k, v) => MapEntry(k, v.join('\n')));
}

void main() {
  final raw = _src(_cfPath);
  final bodies = _exportBodies(raw);

  /// 코드에서 `getSignedUrl(` 를 호출하는 export 함수.
  Set<String> signedUrlOwners() => bodies.entries
      .where((e) => _codeOf(e.value).contains('getSignedUrl('))
      .map((e) => e.key)
      .toSet();

  /// 통장사본 포인터·분기를 만지는 export 함수.
  Set<String> bankbookTouchers() => bodies.entries.where((e) {
        final c = _codeOf(e.value);
        return c.contains('bankbookImagePath') ||
            c.contains('bankbookImageUrl') ||
            c.contains('DOC_TYPE_BANKBOOK') ||
            c.contains('view_bankbook_image');
      }).map((e) => e.key).toSet();

  /// 통장사본 bytes 를 반환할 수 있는 reader = 서명 발급 ∩ 통장사본 접촉.
  Set<String> bankbookReaders() =>
      signedUrlOwners().intersection(bankbookTouchers());

  String body(String name) {
    final b = bodies[name];
    if (b == null) throw StateError('$name 을 찾지 못함');
    return b;
  }

  String code(String name) => _codeOf(body(name));

  /// `.file(<ident>)` 에 실제로 전달되는 식별자.
  String signedTarget(String name) {
    final m = RegExp(r'\.file\(([A-Za-z_][\w.]*)\)').firstMatch(code(name));
    if (m == null) throw StateError('$name 에서 .file(ident) 를 찾지 못함');
    return m.group(1)!;
  }

  // ══════════════════════════════════════════════════════════════
  // [§20·§21·§22] inventory — 개별 함수가 아니라 집합을 고정한다.
  group('BANK-READ-INV 통장사본 byte-reader 전수', () {
    test('BANK-READ-INV-01 통장사본 Signed URL reader 는 정확히 3개다', () {
      final readers = bankbookReaders();
      expect(readers, equals(_knownBankbookReaders),
          reason: '네 번째 reader 가 생겼거나 이름이 바뀌었다. '
              '추가한 reader 도 exact 술어를 쓰는지 확인하고 이 집합을 갱신하라.');
      // 서명 발급 지점 자체의 총수도 고정한다 — 새 서류 reader 를 추가하면
      //   여기서 먼저 보인다(통장사본이 아니어도 눈에 띄게).
      expect(signedUrlOwners().length, 6,
          reason: 'getSignedUrl 호출 export 함수 총수. 늘었으면 어떤 서류의 '
              'reader 인지 분류하고 네임스페이스 술어를 확인하라.');
    });

    test('BANK-READ-INV-02 3개 모두 exact bankbook resolver 를 쓴다', () {
      for (final r in _knownBankbookReaders) {
        expect(code(r), contains('srvResolveOwnedBankbookStoragePath('),
            reason: '$r 이 exact 통장사본 술어를 쓰지 않는다');
      }
    });

    test('BANK-READ-INV-03 넓은 술어만으로 통장사본을 서명하는 reader = 0', () {
      for (final r in _knownBankbookReaders) {
        final c = code(r);
        if (!c.contains('srvIsOwnedStoragePath(')) continue;
        // 넓은 술어가 남아 있다면 그것은 **통장사본 분기가 아닌** 곳이어야
        //   한다. 지원자 reader 의 ID 분기가 유일한 합법 사례다.
        expect(r, 'callableGetApplicantDocumentUrl',
            reason: '$r 에서 넓은 술어가 통장사본 최종 인가로 쓰이고 있다');
        // 그 경우에도 BANKBOOK 분기는 exact 술어를 거친다.
        expect(_flat(c), contains(
            'if (documentType === DOC_TYPE_BANKBOOK) { safeStoragePath = '
            'srvResolveOwnedBankbookStoragePath(targetUid, storagePath); }'),
            reason: 'BANKBOOK 분기가 exact 술어로 분리돼 있지 않다');
      }
    });

    test('BANK-READ-INV-04 exact 검증이 getSignedUrl 보다 앞이다', () {
      for (final r in _knownBankbookReaders) {
        final c = code(r);
        final vAt = c.indexOf('srvResolveOwnedBankbookStoragePath(');
        final sAt = c.indexOf('getSignedUrl(');
        expect(vAt, greaterThan(-1), reason: '$r');
        expect(sAt, greaterThan(vAt), reason: '$r — 서명이 검증보다 먼저다');
      }
    });

    test('BANK-READ-INV-05 성공 감사가 검증보다 먼저인 reader = 0', () {
      for (final r in _knownBankbookReaders) {
        final c = code(r);
        final vAt = c.indexOf('srvResolveOwnedBankbookStoragePath(');
        final aAt = c.indexOf('_access_logs").add({');
        expect(aAt, greaterThan(-1), reason: '$r 의 성공 감사 지점을 찾지 못함');
        expect(aAt, greaterThan(vAt),
            reason: '$r — invalid 포인터인데 성공 감사가 먼저 남는다');
        // 서명보다도 뒤여야 한다 — 발급 실패를 열람 성공으로 기록하지 않는다.
        expect(aAt, greaterThan(c.indexOf('getSignedUrl(')), reason: '$r');
      }
    });

    test('BANK-READ-INV-06 서명 대상은 resolver 가 돌려준 값이다 (§47)', () {
      // 호출만 하고 raw 를 서명하는 우회를 잡는다.
      final expected = <String, String>{
        'callableGetBankbookSignedUrl': 'storagePath',
        'callableGetPayrollBankbookUrl': 'safeBankbookPath',
        'callableGetApplicantDocumentUrl': 'safeStoragePath',
      };
      for (final r in _knownBankbookReaders) {
        final target = signedTarget(r);
        expect(target, expected[r], reason: '$r 의 .file() 인자가 바뀌었다');
        // 그 식별자가 resolver 의 반환값으로 묶여 있는지 확인한다.
        final c = _flat(code(r));
        final boundToResolver =
            c.contains('const $target = srvResolveOwnedBankbookStoragePath(') ||
            c.contains('$target = srvResolveOwnedBankbookStoragePath(');
        expect(boundToResolver, true,
            reason: '$r — .file($target) 의 $target 이 resolver 반환값이 아니다');
      }
    });

    test('BANK-READ-INV-07 cleanup 대기 경로는 열람 source 가 아니다 (§19)', () {
      for (final r in _knownBankbookReaders) {
        final c = code(r);
        expect(c, isNot(contains('bankbookCleanupPendingPaths')), reason: r);
        expect(c, isNot(contains('BANKBOOK_CLEANUP_FIELD')), reason: r);
      }
    });

    test('BANK-READ-INV-08 reader 마다 읽는 포인터를 고정한다 (§16)', () {
      // legacy fallback 을 임의로 추가하거나 제거하지 않았다.
      expect(_flat(code('callableGetBankbookSignedUrl')), contains(
          'const bbPointer = (workerData.bankbookImagePath as string | undefined) '
          '?? (workerData.bankbookImageUrl as string | undefined);'));
      expect(_flat(code('callableGetPayrollBankbookUrl')), contains(
          'const storagePath = w["bankbookImagePath"] as string | undefined;'));
      expect(code('callableGetPayrollBankbookUrl'),
          isNot(contains('bankbookImageUrl')),
          reason: '급여 reader 에 legacy fallback 을 새로 넣지 않았다');
      expect(_flat(code('callableGetApplicantDocumentUrl')), contains(
          '(w["bankbookImagePath"] as string | undefined);'));
      expect(code('callableGetApplicantDocumentUrl'),
          isNot(contains('bankbookImageUrl')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BANK-PAYREAD 급여 통장사본 reader (§4~§9·§26)', () {
    test('BANK-PAYREAD-01 정상 통장사본은 서명된다 — 허용 경로 무변경', () {
      final c = code('callableGetPayrollBankbookUrl');
      // 검증 통과 → 존재 확인 → 서명. 추가 round-trip 을 만들지 않았다 (§30).
      expect(c, contains('const [exists] = await file.exists();'));
      expect(_flat(c), contains(
          'const [signedUrl] = await file.getSignedUrl({ action: "read", '
          'expires: Date.now() + 60 * 60 * 1000, });'));
      expect('file.exists()'.allMatches(c).length, 1,
          reason: '존재 확인이 늘어나면 불필요한 왕복이다');
    });

    test('BANK-PAYREAD-02 same-user 신분증 경로는 거부된다 — 이번 BLOCKER 핵심', () {
      final c = code('callableGetPayrollBankbookUrl');
      // 넓은 술어가 최종 인가로 남아 있지 않다.
      expect(c, isNot(contains('srvIsOwnedStoragePath(storagePath, targetUid)')),
          reason: '소유자 접두만 보면 같은 사용자의 신분증이 통과한다');
      // exact 술어가 그 자리를 대신한다.
      expect(_flat(c), contains(
          'const safeBankbookPath = srvResolveOwnedBankbookStoragePath(targetUid, storagePath);'));
      expect(c, contains('if (safeBankbookPath === null) {'));
      // 그리고 그 술어가 실제로 `bankbook_` 모양만 허용한다.
      expect(_flat(_codeOf(raw)), contains(
          r'return /^bankbook_\d{10,}\.(jpg|jpeg|png|gif|webp|heic|heif)$/i.test(name);'));
    });

    test('BANK-PAYREAD-03·04 businessLicense·profile·타인·중첩 경로 거부', () {
      // 거부는 술어 하나에서 나온다 — 술어가 세그먼트 하나로 제한하고
      //   소유자 uid 접두를 요구하므로 아래가 모두 걸린다.
      final v = _flat(_codeOf(_sliceOf(raw,
          'function srvIsOwnedBankbookStoragePath(', '\n}')));
      expect(v, contains(r'const prefix = `users/${uid}/`;'));
      expect(v, contains('if (!p.startsWith(prefix)) return false;'));
      expect(v, contains(
          'if (name.includes("/") || name.includes("..")) return false;'),
          reason: 'businesses/ · contracts/ · 중첩 · traversal 이 여기서 걸린다');
      // 급여 reader 가 그 술어를 타고 들어간다.
      expect(_flat(_codeOf(_sliceOf(raw,
              'function srvResolveOwnedBankbookStoragePath(', '\n}'))),
          contains('srvIsOwnedBankbookStoragePath(uid, candidate)'));
    });

    test('BANK-PAYREAD-05 검증이 서명보다 앞이다', () {
      final c = code('callableGetPayrollBankbookUrl');
      expect(c.indexOf('srvResolveOwnedBankbookStoragePath('),
          lessThan(c.indexOf('.file(')));
      expect(c.indexOf('.file('), lessThan(c.indexOf('getSignedUrl(')));
    });

    test('BANK-PAYREAD-06 invalid 포인터에 성공 감사를 남기지 않는다 (§9)', () {
      final c = code('callableGetPayrollBankbookUrl');
      final throwAt = c.indexOf('if (safeBankbookPath === null) {');
      final auditAt = c.indexOf('bankbook_access_logs');
      expect(throwAt, greaterThan(0));
      expect(auditAt, greaterThan(throwAt),
          reason: 'throw 보다 감사가 먼저면 거부가 열람으로 기록된다');
      expect(_flat(c), contains('action: "view_bankbook_image",'),
          reason: '감사 semantics 는 그대로다');
    });

    test('BANK-PAYREAD-07 인가·목적 gate 무변경 (§5·§26)', () {
      final c = code('callableGetPayrollBankbookUrl');
      for (final keep in [
        'await srvAssertPayrollDocumentAccess(callerUid, businessId);',
        'await srvAssertCurrentPayrollPurpose(businessId, targetUid, attendanceId);',
        '"통장사본이 변경되었습니다. 목록을 새로고침해주세요."',
        '"통장사본이 등록되지 않았습니다."',
      ]) {
        expect(c, contains(keep), reason: '$keep 가 바뀌면 안 된다');
      }
      // 인가가 target 문서 읽기보다 앞이다 — artifact oracle 을 만들지 않는다 (§3).
      final authAt = c.indexOf('srvAssertPayrollDocumentAccess(');
      final readAt = c.indexOf('db.collection("users").doc(targetUid).get()');
      final nsAt = c.indexOf('srvResolveOwnedBankbookStoragePath(');
      expect(authAt, greaterThan(0));
      expect(readAt, greaterThan(authAt));
      expect(nsAt, greaterThan(readAt));
    });

    test('BANK-PAYREAD-08 없음과 통장사본아님의 오류가 구별된다 (§17·§18)', () {
      final c = code('callableGetPayrollBankbookUrl');
      // MISSING → not-found (권한 문제로 바뀌지 않았다)
      expect(_flat(c), contains(
          'if (!storagePath) { throw new HttpsError("not-found", "통장사본이 등록되지 않았습니다."); }'));
      // INVALID → failed-precondition (NO_PERMISSION 이 아니다)
      expect(_flat(c), contains(
          'throw new HttpsError("failed-precondition", "통장사본 파일 경로가 올바르지 않습니다.'));
      expect(c, isNot(contains('"permission-denied", "통장사본 파일 경로')));
    });

    test('BANK-PAYREAD-09 오류 메시지·로그가 서류 종류·경로를 누설하지 않는다 (§31)', () {
      final c = code('callableGetPayrollBankbookUrl');
      final msg = '통장사본 파일 경로가 올바르지 않습니다. 근로자에게 재등록을 요청해주세요.';
      expect(c, contains(msg));
      // 메시지에 idCard/businessLicense/raw path 가 없다.
      for (final leak in ['idCard', 'businessLicense', 'users/']) {
        expect(msg.contains(leak), false, reason: '$leak 가 메시지에 들어 있다');
      }
      // 로그에도 raw 경로를 찍지 않는다.
      expect(c, isNot(contains(r'경로가 아니다 — path=${storagePath}')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BANK-APPREAD 지원자 서류 reader BANKBOOK 분기 (§10~§15·§27)', () {
    test('BANK-APPREAD-01 BANKBOOK 정상 경로는 서명된다', () {
      final c = code('callableGetApplicantDocumentUrl');
      expect(c, contains('const file = admin.storage().bucket().file(safeStoragePath);'));
      expect(_flat(c), contains(
          'const [signedUrl] = await file.getSignedUrl({ action: "read", '
          'expires: Date.now() + 60 * 60 * 1000, });'));
    });

    test('BANK-APPREAD-02 BANKBOOK 에 신분증 경로가 있으면 거부된다', () {
      final c = _flat(code('callableGetApplicantDocumentUrl'));
      expect(c, contains(
          'if (documentType === DOC_TYPE_BANKBOOK) { safeStoragePath = '
          'srvResolveOwnedBankbookStoragePath(targetUid, storagePath); }'));
      // raw 가 서명 대상이 되는 경로가 사라졌다.
      expect(code('callableGetApplicantDocumentUrl'),
          isNot(contains('.file(storagePath)')));
    });

    test('BANK-APPREAD-03·04 businessLicense·타인·중첩은 같은 술어에서 걸린다', () {
      // BANKBOOK 분기는 통장사본 술어 하나만 믿는다.
      final c = _flat(code('callableGetApplicantDocumentUrl'));
      expect(c, contains('srvResolveOwnedBankbookStoragePath(targetUid, storagePath)'));
      // 그 술어는 uid 접두 + 단일 세그먼트 + bankbook_ 모양을 요구한다.
      expect(_flat(_codeOf(_sliceOf(raw,
              'function srvIsOwnedBankbookStoragePath(', '\n}'))),
          contains(r'const prefix = `users/${uid}/`;'));
    });

    test('BANK-APPREAD-05 감사가 말하는 서류와 준 서류가 같다 (§14)', () {
      final c = code('callableGetApplicantDocumentUrl');
      // 감사는 서명 뒤에 남고, 서명 대상은 BANKBOOK 분기에서 exact 검증된 값이다.
      final nsAt = c.indexOf('srvResolveOwnedBankbookStoragePath(');
      final signAt = c.indexOf('getSignedUrl(');
      final auditAt = c.indexOf('applicant_document_access_logs');
      expect(nsAt, greaterThan(0));
      expect(signAt, greaterThan(nsAt));
      expect(auditAt, greaterThan(signAt));
      // 감사 필드 semantics 는 그대로다 — 새 collection 을 만들지 않았다 (§28).
      expect(_flat(c), contains('documentType, purpose: "APPLICANT_REVIEW",'));
    });

    test('BANK-APPREAD-06 ID 분기 behavior 무변경 (§12·§35)', () {
      final c = code('callableGetApplicantDocumentUrl');
      // ID 는 기존 넓은 술어를 그대로 쓴다 — 별도 owner 다.
      expect(_flat(c), contains(
          '} else if (srvIsOwnedStoragePath(storagePath, targetUid)) { '
          'safeStoragePath = storagePath; }'));
      expect(_flat(c), contains(
          'const storagePath = documentType === DOC_TYPE_ID ? '
          '(w["idCardImagePath"] as string | undefined) : '
          '(w["bankbookImagePath"] as string | undefined);'));
      // ID 전용 reader 두 개는 이번에 건드리지 않았다.
      expect(code('callableGetIdCardSignedUrl'),
          contains('srvIsOwnedStoragePath(storagePath, targetUserId)'));
      expect(code('callableGetTaxIdentityIdCardUrl'),
          contains('srvIsOwnedStoragePath(storagePath, targetUid)'));
    });

    test('BANK-APPREAD-07 unknown documentType 이 BANKBOOK 으로 흐르지 않는다 (§49)', () {
      final c = _flat(code('callableGetApplicantDocumentUrl'));
      // 진입에서 두 값만 허용한다.
      expect(c, contains(
          'if (documentType !== DOC_TYPE_ID && documentType !== DOC_TYPE_BANKBOOK) {'));
      expect(c, contains('"지원하지 않는 문서 유형입니다."'));
      // 그리고 BANKBOOK 분기는 명시 비교다 — else 로 떨어지지 않는다.
      expect(c, contains('if (documentType === DOC_TYPE_BANKBOOK) {'));
    });

    test('BANK-APPREAD-08 인가·동의 gate 무변경 (§27)', () {
      final c = code('callableGetApplicantDocumentUrl');
      for (final keep in [
        'await assertBizAdmin(callerUid, businessId);',
        'if (!await srvCanReviewApplicantDocuments(callerUid, businessId)) {',
        'srvApplicantReviewAccessBlock(appSnap.data()!, businessId, targetUid);',
        '"등록된 서류가 없습니다."',
      ]) {
        expect(c, contains(keep), reason: '$keep 가 바뀌면 안 된다');
      }
      // 인가가 네임스페이스 검증보다 앞이다 (§3 — artifact oracle 금지).
      expect(c.indexOf('srvCanReviewApplicantDocuments('),
          lessThan(c.indexOf('srvResolveOwnedBankbookStoragePath(')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  group('BANK-READ-NC 이번 patch 가 건드리지 않은 것 (§23·§36~§39·§55)', () {
    test('BANK-READ-NC-01 넓은 술어는 다른 서류에서 계속 쓰인다 (§23)', () {
      // 전역 금지 테스트를 만들지 않는다 — 다른 artifact 의 정당한 술어다.
      final users = <String>[
        'callableGetIdCardSignedUrl',
        'callableGetTaxIdentityIdCardUrl',
        'callableGetApplicantDocumentUrl',
        'callableRegisterBusinessLicense',
      ];
      for (final u in users) {
        expect(code(u), contains('srvIsOwnedStoragePath('), reason: u);
      }
      // 정의 자체도 그대로다.
      expect(_flat(_codeOf(_sliceOf(raw, 'function srvIsOwnedStoragePath(', '\n}'))),
          contains(r'return path.startsWith(`users/${ownerUid}/`);'));
    });

    test('BANK-READ-NC-02 통장사본 술어 정의 ±0 (§55)', () {
      expect(_flat(_codeOf(_sliceOf(raw,
          'function srvIsOwnedBankbookStoragePath(', '\n}'))), contains(
          r'return /^bankbook_\d{10,}\.(jpg|jpeg|png|gif|webp|heic|heif)$/i.test(name);'));
      expect(_flat(_codeOf(_sliceOf(raw,
          'function srvResolveOwnedBankbookStoragePath(', '\n}'))), contains(
          'srvIsOwnedBankbookStoragePath(uid, candidate)'));
    });

    test('BANK-READ-NC-03 writer·delete·durable cleanup ±0 (§36·§37)', () {
      expect(code('callableMarkBankbookVerified'),
          contains('srvResolveOwnedBankbookStoragePath(callerUid, rawBbInput)'));
      expect(code('callableMarkBankbookVerified'),
          contains('srvDrainBankbookCleanup(callerUid, "callableMarkBankbookVerified")'));
      expect(code('callableDeleteBankInfo'),
          contains('await srvResetBankStateWithCleanupOwner('));
      expect(code('callableUpdateBankAccount'),
          contains('await srvResetBankStateWithCleanupOwner('));
      expect(code('callableBackfillBankbookImagePath'),
          contains('srvResolveOwnedBankbookStoragePath(doc.id, imageUrl)'));
      expect(_codeOf(raw), contains('const BANKBOOK_CLEANUP_DRAIN_CAP = 20;'));
    });

    test('BANK-READ-NC-04 readiness·OCR·match ±0 (§38·§39)', () {
      final model = _flat(_codeOf(_src('lib/models/core/user_model.dart')));
      expect(
        model.contains('bool get hasBankbookDocument => '
            '(bankbookImagePath != null && bankbookImagePath!.isNotEmpty) || '
            '(bankbookImageUrl != null && bankbookImageUrl!.isNotEmpty);'),
        true,
      );
      expect(code('callableMarkBankbookVerified'), contains(
          'srvEvaluateMatchStatus(bbDoc.evidence, {requireName: false})'));
      // reader 들이 readiness·match 를 건드리지 않는다.
      for (final r in _knownBankbookReaders) {
        expect(code(r), isNot(contains('bankbookMatchStatus:')), reason: r);
        expect(code(r), isNot(contains('hasBankbookDocument')), reason: r);
      }
    });
  });
}

/// 그룹 수집 시점에도 불리므로 expect 대신 예외로 실패시킨다.
String _sliceOf(String raw, String from, String to) {
  final a = raw.indexOf(from);
  if (a < 0) throw StateError('시작 표지를 찾지 못함: $from');
  final b = raw.indexOf(to, a + from.length);
  if (b < 0) throw StateError('끝 표지를 찾지 못함: $to');
  return raw.substring(a, b);
}
