// [PII-B4-R1] 세무 identity 육안 확인 + 확정 auto-grant 폐기
//
// 이 파일이 고정하는 것:
//
//   AG   확정은 더 이상 신분증 열람 권한을 만들지 않는다.
//   EP   다이얼로그를 여는 것만으로 원본이 발급되지 않는다.
//   RV   확인 사실은 사업장 × 근로자 × 현재 신분증 × 현재 세무 identity 에 묶인다.
//   RU   같은 사업장 재지원·재근무는 다시 보지 않는다. 값이 바뀌면 다시 본다.
//   LG   과거 근무·legacy grant 를 확인 완료로 추정하지 않는다.
//   PM   권한은 canManageWage, 소유자도 canonical 경로로 통과한다.
//   PR   generic 화면에 주민번호 전체·원본 경로가 없다.
//   WD   문구는 진위 인증을 주장하지 않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _sliceOf(String raw, String from, String to) {
  final a = raw.indexOf(from);
  if (a < 0) throw StateError('$from 를 찾지 못함');
  final b = raw.indexOf(to, a + from.length);
  if (b < 0) throw StateError('$to 를 찾지 못함');
  return raw.substring(a, b);
}

const _cfPath = 'functions/src/index.ts';
const _dlgPath = 'lib/widgets/dialogs/worker_detail_dialog.dart';
const _svcPath = 'lib/services/tax_identity_review_service.dart';

void main() {
  final rawCf = _src(_cfPath);
  final cf = _codeOf(rawCf);
  final fp = _codeOf(
      _sliceOf(rawCf, 'function srvTaxIdentityFingerprint(', '\n}'));
  final resolver = _codeOf(
      _sliceOf(rawCf, 'function srvResolveTaxIdentityReview(', '\n}'));
  final authz = _codeOf(
      _sliceOf(rawCf, 'async function srvAssertTaxIdentityAuthority(', '\n}'));
  final rel = _codeOf(_sliceOf(rawCf,
      'async function srvHasBusinessWorkerRelationship(', '\n}'));
  final urlCf = _codeOf(_sliceOf(rawCf,
      'export const callableGetTaxIdentityIdCardUrl = onCall(', '\n);'));
  final review = _codeOf(_sliceOf(rawCf,
      'export const callableReviewTaxIdentity = onCall(', '\n);'));
  final dlg = _src(_dlgPath);
  final svc = _src(_svcPath);

  // ── AG. auto-grant 폐기 ─────────────────────────────────────────
  group('AG — 확정은 신분증 열람 권한이 아니다 (§12)', () {
    test('01 auto-grant helper 가 사라졌다', () {
      expect(cf, isNot(contains('ensureIdCardGrantForConfirmedApplication')));
    });

    test('02 AG1·AG2·AG3 — 확정·초대수락·재배치에 grant 생성 없음', () {
      for (final entry in [
        'export const callableConfirmApplication = onCall(',
        'export const callableAcceptTOInvitation = onCall(',
        'export const callableAcceptConfirmedReassignment = onCall(',
      ]) {
        final body = _codeOf(_sliceOf(rawCf, entry, '\n);'));
        expect(body, isNot(contains('idCardAccessRequests')), reason: entry);
      }
    });

    test('03 AG4 — 신분증 뒤늦은 등록의 소급 grant 없음', () {
      final mark = _codeOf(_sliceOf(rawCf,
          'export const callableMarkIdCardVerified = onCall(', '\n);'));
      expect(mark, isNot(contains('idCardAccessRequests')));
      expect(mark, isNot(contains('pre_consent')));
    });

    test('04 계약 서명 CONFIRMED 전환에도 grant 생성 없음', () {
      final sign = _codeOf(_sliceOf(rawCf,
          'export const callableFinalizeWorkerSignature = onCall(', '\n);'));
      expect(sign, isNot(contains('idCardAccessRequests')));
    });

    test('05 §13 — 좌석·상태 mutation 은 그대로다', () {
      final confirm = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableConfirmApplication = onCall(', '\n);')));
      expect(confirm, contains('FieldValue.increment(1)'));
      expect(confirm, contains('"CONFIRMED"'));
    });

    test('06 §14 — legacy generic grant 를 현재 권한으로 인정하지 않는다', () {
      final signed = _codeOf(_sliceOf(rawCf,
          'export const callableGetIdCardSignedUrl = onCall(', '\n);'));
      expect(signed, contains('legacySource.startsWith("pre_consent")'));
    });
  });

  // ── EP. eager preload 제거 ──────────────────────────────────────
  group('EP — 화면을 여는 것은 볼 이유가 아니다 (§22)', () {
    test('07 EA2 — 다이얼로그가 선제 발급하지 않는다', () {
      expect(dlg, isNot(contains('getIdCardSignedUrl(widget.user.uid, silent: true)')));
      expect(_codeOf(dlg), isNot(contains('_loadIdCardSignedUrl')));
      expect(_codeOf(dlg), isNot(contains('_idCardSignedUrl')));
    });

    test('08 확인 상태만 미리 읽는다', () {
      expect(dlg, contains('_loadTaxIdentityReview()'));
      final load = _codeOf(
          _sliceOf(dlg, 'Future<void> _loadTaxIdentityReview()', '\n  }'));
      expect(load, contains('TaxIdentityReviewService.load('));
      expect(load, isNot(contains('idCardUrl')));
    });

    test('09 상태 조회 응답에 원본이 없다', () {
      final get = _codeOf(_sliceOf(rawCf,
          'export const callableGetTaxIdentityReview = onCall(', '\n);'));
      expect(get, isNot(contains('signedUrl')));
      expect(get, isNot(contains('getSignedUrl')));
    });

    test('10 원본은 명시 클릭 경로에서만 부른다', () {
      final open = _codeOf(
          _sliceOf(dlg, 'Future<void> _openTaxIdentityReview()', '\n  }'));
      expect(open, contains('TaxIdentityReviewService.idCardUrl('));
      expect(dlg, contains("label: ok ? '다시 보기' : '신분증 확인'"));
    });
  });

  // ── RV. 검토 truth ──────────────────────────────────────────────
  group('RV — 확인 사실의 identity (§2·§28·§31)', () {
    test('11 사업장 × 근로자 문서에 기록한다 — 새 컬렉션 없음', () {
      expect(review, contains('BIZ_DOC_REVIEW_COL'));
      expect(review, contains('srvBizReviewId(businessId, targetUid)'));
      expect(cf, isNot(contains('taxIdentityReviews')));
    });

    test('12 현재 신분증 버전과 세무 지문에 묶인다', () {
      expect(review, contains('reviewedTaxIdDocumentVersion: curIdV'));
      expect(review, contains('reviewedTaxIdentityFingerprint: curFp'));
      expect(resolver, contains('rIdV !== curIdV || rFp !== curFp'));
    });

    test('13 §38 — 누가 언제 확인했는지 남는다', () {
      for (final f in ['taxIdentityReviewedBy', 'taxIdentityReviewedAt',
        'taxIdentityReviewPurpose']) {
        expect(review, contains(f), reason: f);
      }
      expect(review, contains('TAX_REVIEW_PURPOSE'));
    });

    test('14 §31 — Application 상태를 검토 조건으로 쓰지 않는다', () {
      expect(rel, contains('collection("applications")'));
      expect(rel, isNot(contains('"status"')));
      expect(review, isNot(contains('CONFIRMED')));
    });

    test('15 §11 — 가짜 버전을 만들지 않는다 (값에서 파생)', () {
      expect(fp, contains('crypto.createHash("sha256")'));
      for (final f in ['legalName', 'name', 'koreanName', 'birthDate',
        'gender', 'foreignIdentityFingerprint']) {
        expect(fp, contains(f), reason: f);
      }
      expect(fp, isNot(contains('Date.now')));
      expect(fp, isNot(contains('applicationId')));
    });

    // ── [PII-B4-R1.1] 주민등록번호 값 정확성 ──────────────────
    test('15a F2·F4·F5 — 주민번호 **값**이 지문에 들어간다', () {
      // R1에서는 존재 여부만 담아서 A→B 변경이 감지되지 않았다.
      expect(fp, contains('d["residentNumber"]'));
      expect(fp, isNot(contains('"R1" : "R0"')),
          reason: '있음/없음 두 가지로 뭉개지 않는다');
      expect(fp, contains('"R:ABSENT"'), reason: '없음도 하나의 값이다');
      expect(fp, contains('"R:" + (d["residentNumber"] as string)'));
    });

    test('15b §4·§5 — 서버가 계산한다. 클라이언트 지문을 받지 않는다', () {
      // 제출은 받은 지문을 **비교에만** 쓰고, 저장은 서버 계산값이다.
      expect(review, contains('const curFp = srvTaxIdentityFingerprint(wd)'));
      expect(review, contains('reviewedTaxIdentityFingerprint: curFp'));
      expect(review,
          isNot(contains('reviewedTaxIdentityFingerprint: expectedTaxIdentityFingerprint')));
    });

    test('15c §3·§12 — 재암호화로 인한 false STALE 을 구조로 막는다', () {
      // 서버에 ENCRYPT_KEY 가 없어 평문 HMAC 이 불가능하다. 대신 암호문을
      // 쓰되, 클라이언트가 그 필드를 다시 쓸 수 없게 해 재암호화를 없앤다.
      final rules = _src('firestore.rules');
      final ownerBlock = _sliceOf(rules,
          'allow update: if isLoggedIn() &&', 'allow delete:');
      expect(ownerBlock, contains("'residentNumber'"));
      final uf = _src('lib/services/firestore/user_firestore.dart');
      final guard = _sliceOf(uf, '_protectedUserFields = {', '};');
      expect(guard, contains("'residentNumber'"));
    });

    test('15d §9 — 평문이 로그·응답으로 새지 않는다', () {
      final get = _codeOf(_sliceOf(rawCf,
          'export const callableGetTaxIdentityReview = onCall(', '\n);'));
      expect(get, isNot(contains('residentNumber')));
      expect(review, isNot(contains('residentNumber')));
      expect(urlCf, isNot(contains('residentNumber')));
      // 지문은 해시 결과만 밖으로 나간다.
      expect(fp, contains('digest("hex")'));
    });

    test('16 다른 축(지원자 서류 검토)을 건드리지 않는다', () {
      expect(review, isNot(contains('idDecision: REVIEW_OK')));
      expect(review, contains('patch["idDecision"] = REVIEW_NOT_REVIEWED'));
      final mr = _codeOf(
          _sliceOf(rawCf, 'function srvResolveMatchingReadiness(', '\n}'));
      expect(mr, isNot(contains('taxIdentityDecision')));
    });
  });

  // ── RU. 재사용 / 무효화 ─────────────────────────────────────────
  group('RU — 값이 그대로면 다시 보지 않는다 (§4·§40·§41)', () {
    test('17 RR1·RR2 — 재사용 조건은 값 일치뿐이다', () {
      expect(resolver, contains('TAX_REVIEW_OK'));
      // 시간 만료가 없다.
      expect(resolver, isNot(contains('expiresAt')));
      expect(resolver, isNot(contains('7 * 24')));
      expect(resolver, isNot(contains('Date.now')));
    });

    test('18 RR3·RR4 — 신분증·세무 identity 변경은 STALE', () {
      expect(resolver, contains('TAX_REVIEW_STALE'));
      expect(resolver, contains('srvDocumentVersionsOf'));
      expect(resolver, contains('srvTaxIdentityFingerprint'));
    });

    test('19 §3 — 상태 4개', () {
      for (final s in ['TAX_REVIEW_UNREVIEWED', 'TAX_REVIEW_OK',
        'TAX_REVIEW_REUPLOAD', 'TAX_REVIEW_STALE']) {
        expect(cf, contains(s), reason: s);
      }
    });

    test('20 RA1·RA2 — 제출 시 현재 값을 다시 확인한다', () {
      expect(review, contains('curIdV !== expectedIdDocumentVersion'));
      expect(review, contains('curFp !== expectedTaxIdentityFingerprint'));
      expect(review, contains('db.runTransaction'));
      expect(_flat(review), contains('throw new HttpsError("aborted"'));
    });

    test('21 §36 — 원본도 현재 문서 버전에 묶인다', () {
      expect(urlCf, contains('expectedIdDocumentVersion !== curIdV'));
      expect(urlCf, contains('srvIsOwnedStoragePath(storagePath, targetUid)'));
    });

    test('22 §30 — 불일치는 근로자 할 일로 넘어간다', () {
      expect(review, contains('CORRECTION_DOMAIN_TAX'));
      expect(review, contains('CORRECTION_OPEN'));
      // 지원 취소·페널티를 만들지 않는다.
      for (final f in ['AUTO_CANCELED', 'trustScore', 'noShowCount']) {
        expect(review, isNot(contains(f)), reason: f);
      }
    });
  });

  // ── LG. 추정 금지 ───────────────────────────────────────────────
  group('LG — 일했다는 사실은 확인했다는 뜻이 아니다 (§6·§42)', () {
    test('23 RR5 — 검토 기록이 없으면 UNREVIEWED', () {
      expect(_flat(resolver), contains(
          'if (!decision) { return {...base, state: TAX_REVIEW_UNREVIEWED, '
          'valid: false}; }'));
    });

    test('24 근무 이력으로 REVIEWED_OK 를 만들지 않는다', () {
      expect(resolver, isNot(contains('attendance')));
      expect(cf, isNot(contains('backfillTaxIdentityReview')));
    });

    test('25 RR6·§7 — 사업장별로 분리된다', () {
      expect(review, contains('srvBizReviewId(businessId, targetUid)'));
      expect(resolver, isNot(contains('collectionGroup')));
    });
  });

  // ── PM. 권한 ────────────────────────────────────────────────────
  group('PM — 권한 (§26·§27)', () {
    test('26 canManageWage 필수', () {
      expect(authz, contains('perms.canManageWage !== true'));
      expect(authz, isNot(contains('canManageWorkers')));
      expect(authz, isNot(contains('canManageTo')));
    });

    test('27 §27 — 소유자도 canonical 경로로 통과한다', () {
      expect(authz, contains('biz["ownerId"]'));
      expect(authz, contains('adminIds.includes(callerUid)'));
      expect(authz, isNot(contains('callerData?.businessId')));
    });

    test('28 세 CF 모두 같은 가드를 쓴다', () {
      for (final body in [urlCf, review]) {
        expect(body, contains('srvAssertTaxIdentityAuthority('));
        expect(body, contains('srvHasBusinessWorkerRelationship('));
      }
    });

    test('29 §37 — 감사 로그에 목적·버전·사업장', () {
      expect(urlCf, contains('purpose: TAX_REVIEW_PURPOSE'));
      expect(urlCf, contains('idDocumentVersion: curIdV'));
      expect(urlCf, contains('businessId,'));
      expect(urlCf, contains('60 * 60 * 1000'));
    });
  });

  // ── PR. generic 최소화 ──────────────────────────────────────────
  group('PR — generic 화면·DTO 최소화 (§24·§44)', () {
    test('30 GP1 — 주민번호 전체 표시·복사가 없다', () {
      expect(_codeOf(dlg), isNot(contains('residentNumber')));
      expect(_codeOf(dlg), isNot(contains('callableLogResidentNumberCopy')));
      expect(dlg, isNot(contains('주민번호가 복사되었습니다')));
    });

    test('31 GP2 — generic DTO 에 원본 경로가 없다', () {
      final dto = _codeOf(rawCf);
      // users DTO 목록만 본다 — "ci"가 들어 있는 블록이 그것이다.
      final blocks = dto
          .split('SENSITIVE_FIELDS = new Set([')
          .skip(1)
          .map((b) => b.split(']);').first)
          .where((b) => b.contains('"ci"'))
          .toList();
      expect(blocks.length, 2, reason: 'users DTO denylist 2곳');
      for (final body in blocks) {
        expect(body, contains('"idCardImagePath"'));
        expect(body, contains('"idCardImageUrl"'));
      }
    });

    test('32 지원자 검토 allowlist 에도 없다', () {
      final allow = _codeOf(_sliceOf(rawCf,
          'const APPLICANT_REVIEW_ALLOWED = new Set([', ']);'));
      expect(allow, isNot(contains('idCard')));
      expect(allow, isNot(contains('residentNumber')));
    });

    test('33 §15 — 확정 전 지원자 서류 검토는 그대로다', () {
      expect(cf, contains('callableGetApplicantDocumentUrl'));
      expect(cf, contains('srvCanReviewApplicantDocuments'));
    });
  });

  // ── WD. 문구 ────────────────────────────────────────────────────
  group('WD — 진위 인증을 주장하지 않는다 (§21)', () {
    test('34 허용 문구', () {
      expect(svc, contains("'확인 완료'"));
      expect(svc, contains("'확인 필요'"));
      expect(svc, contains("'재확인 필요'"));
      expect(svc, contains("'정보 수정 필요'"));
    });

    test('35 금지 문구가 없다', () {
      for (final p in [_svcPath, _dlgPath]) {
        final s = _src(p);
        for (final banned in ['신분증 인증 완료', '정부 인증 완료', '공인 인증 완료',
          '진위 확인 완료']) {
          expect(s, isNot(contains(banned)), reason: '$p 에 "$banned"');
        }
      }
    });

    test('36 시트가 대조 대상을 함께 보여준다 (§23)', () {
      expect(dlg, contains("'등록 성명'"));
      expect(dlg, contains("'생년월일'"));
      expect(dlg, contains('_TaxIdentityReviewSheet'));
      // §25 — 복사 기능은 제공하지 않는다.
      expect(_codeOf(dlg), isNot(contains('Clipboard.setData')));
    });
  });
}
