import 'dart:io';

import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// DS-08B.5 CONSENT-VERSION-CONTRACT-ALIGNMENT
//
// invariant:
//   documentAccessConsentVersion == 사용자가 실제로 본 고지 문구의 버전
//
// 서버가 배포 시점의 최신 버전을 무조건 기록하면, Functions가 앱보다
// 먼저 배포된 구간에서 v1 문구를 본 사용자에게 v2 범위가 적용된다.
//
// cohort 판별 (코드로 확인 가능한 사실 기준):
//   버전 전송              → 그 버전 (allowlist)
//   버전 없음 + given=true → 2026-08-21(75075a5) 이후 앱 = v1 문구 cohort
//   버전 없음 + given 없음 → 그 이전 앱 = 서류 접근 고지 미표시 → 기록 없음
// ═══════════════════════════════════════════════════════════════

const _indexPath = 'functions/src/index.ts';
const _v1 = '2026-08-21-v1';
const _v2 = '2026-09-12-v2';
// [R1.2] 채용 검토 목적 열람을 명시한 문구. v2 이하는 '근무 확정 시
//   소득신고·급여처리 목적'만 동의했으므로 자동 승격하지 않는다.
const _v3 = '2026-09-18-v3';

/// 지원 요청을 서버로 보내는 모든 UI 경로.
/// 각 경로는 고지 카드를 표시해야 한다 — 표시 없이 버전만 기록되면 안 된다.
const _applyEntryPoints = [
  'lib/widgets/dialogs/apply/apply_confirm_dialog.dart',
  'lib/widgets/dialogs/apply/multi_apply_confirm_sheet.dart',
  'lib/widgets/dialogs/apply/longterm_apply_sheet.dart',
];

String _src(String path) => File(path).readAsStringSync();

String _codeOf(String body) => body
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _callableBody(String source, String name) {
  final start = source.indexOf('export const $name = onCall(');
  expect(start, isNot(-1), reason: '$name 을 찾지 못함');
  var depth = 0;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    final c = source[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  fail('$name 본문의 끝을 찾지 못함');
}

String _between(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  expect(start, isNot(-1), reason: '$startMarker 를 찾지 못함');
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(end, isNot(-1), reason: '$startMarker 이후 $endMarker 를 찾지 못함');
  return source.substring(start, end);
}

// ── 서버 resolveDocumentAccessConsentVersion 의 Dart 복제 ─────────
// 값 자체를 검증한다. 배선은 아래 소스 단정이 확인한다.

class UnsupportedConsentVersion implements Exception {}

String? resolveVersion(String? raw, {required bool clientSentDocConsent}) {
  if (raw == null) return clientSentDocConsent ? _v1 : null;
  if (raw != _v1 && raw != _v2 && raw != _v3) throw UnsupportedConsentVersion();
  return raw;
}

void main() {
  late String source;
  late String code;
  late String applyToTO;

  setUpAll(() {
    source = _src(_indexPath);
    code = _codeOf(source);
    applyToTO = _codeOf(_callableBody(source, 'callableApplyToTO'));
  });

  // ───────────────────────────────────────────────────────────
  group('DS08B5-01 v2 클라이언트 → v2 기록', () {
    test('전송한 버전을 그대로 기록한다', () {
      expect(resolveVersion(_v2, clientSentDocConsent: true), _v2);
    });

    // [R1.2] 버전 문자열 자체를 고정하지 않는다. 고정할 것은
    //   '클라이언트가 보내는 버전과 서버 allowlist의 최신이 같다'이다.
    test('클라이언트 상수가 서버가 아는 최신 버전이다', () {
      expect(DocumentAccessConsent.version, _v3);
      final cf = _src(_indexPath);
      expect(cf.contains('DOCUMENT_ACCESS_CONSENT_V3 = "$_v3"'), isTrue);
    });

    test('표시 문구와 버전이 같은 파일에 있다 — drift 방지', () {
      final consent =
          _src('lib/widgets/dialogs/apply/document_access_consent.dart');
      expect(consent.contains("static const String version = '$_v3'"), isTrue);
      expect(consent.contains('마지막 근무일로부터 7일 후'), isTrue);
      expect(consent.contains('갱신된 근무관계에도 승계됩니다'), isTrue);
      // [R1.2] 새 목적이 문구에 실제로 적혀 있어야 버전이 의미를 갖는다.
      expect(consent.contains('지원자 확인 및 채용 검토'), isTrue);
    });

    test('클라이언트가 그 상수를 그대로 전송한다', () {
      final apply = _src('lib/services/firestore/application_firestore.dart');
      expect(
        apply.contains(
            "'documentAccessConsentVersion': DocumentAccessConsent.version"),
        isTrue,
      );
      expect(apply.contains("'documentAccessConsentVersion': '2026"), isFalse,
          reason: '리터럴을 따로 쓰면 문구와 어긋날 수 있다');
    });
  });

  group('DS08B5-02 구버전 클라이언트 호환', () {
    test('버전 없음 + 서류동의 전송 → v1', () {
      expect(resolveVersion(null, clientSentDocConsent: true), _v1);
    });

    test('버전 없음 + 서류동의 미전송 → 기록 없음', () {
      expect(resolveVersion(null, clientSentDocConsent: false), isNull,
          reason: '서류 접근 고지를 본 적 없는 cohort에 버전을 붙이면 안 된다');
    });

    test('v1을 v2로 승격하지 않는다', () {
      expect(resolveVersion(_v1, clientSentDocConsent: true), _v1);
    });
  });

  group('DS08B5-03 unknown version 거부', () {
    test('미지원 버전은 예외', () {
      for (final bad in ['2026-09-12-v3', 'latest', 'v2', '', 'null']) {
        expect(() => resolveVersion(bad, clientSentDocConsent: true),
            throwsA(isA<UnsupportedConsentVersion>()),
            reason: '$bad 를 조용히 통과시키면 안 된다');
      }
    });

    test('unknown을 최신 버전으로 치환하지 않는다', () {
      try {
        resolveVersion('made-up', clientSentDocConsent: true);
        fail('예외가 발생해야 한다');
      } on UnsupportedConsentVersion {
        // 기대 동작
      }
    });

    test('서버가 invalid-argument로 실패한다', () {
      final resolver = _between(
        code,
        'function resolveDocumentAccessConsentVersion(',
        'export const callableGetIdCardSignedUrl',
      );
      expect(resolver.contains('"invalid-argument"'), isTrue);
      expect(
        resolver.contains('SUPPORTED_DOCUMENT_ACCESS_CONSENT_VERSIONS.includes'),
        isTrue,
      );
    });
  });

  // ───────────────────────────────────────────────────────────
  group('DS08B5-04~05 access formula 무변경', () {
    test('v1은 confirmedAt + 7일 그대로', () {
      final helper = _between(
        code,
        'function calcPreConsentIdCardExpiryMs(',
        'function shortenedPreConsentExpiry(',
      );
      expect(helper.contains('return confirmedAtMs + ID_CARD_ACCESS_WINDOW_MS'),
          isTrue);
    });

    test('v2는 max(confirmedAt, lastWorkDate) + 7일 그대로', () {
      final helper = _between(
        code,
        'function calcPreConsentIdCardExpiryMs(',
        'function shortenedPreConsentExpiry(',
      );
      expect(helper.contains('Math.max(confirmedAtMs, lastWorkMs)'), isTrue);
      expect(helper.contains('isDocumentAccessConsentV2(appData)'), isTrue);
    });

    test('7일 duration 무변경', () {
      expect(
        code.contains('const ID_CARD_ACCESS_WINDOW_MS = 7 * 24 * 60 * 60 * 1000'),
        isTrue,
      );
    });
  });

  // ───────────────────────────────────────────────────────────
  group('DS08B5-06~08 표시 문구 == 전송 버전', () {
    test('DS08B5-06/07/08 모든 지원 UI가 동일 고지 카드를 쓴다', () {
      for (final path in _applyEntryPoints) {
        final ui = _src(path);
        expect(ui.contains('DocumentAccessConsent.card('), isTrue,
            reason: '$path 가 고지를 표시하지 않으면 기록된 버전이 거짓이 된다');
      }
    });

    test('문구를 인라인으로 복제한 곳이 없다', () {
      for (final path in _applyEntryPoints) {
        final ui = _src(path);
        expect(ui.contains('마지막 근무일로부터 7일 후'), isFalse,
            reason: '$path 에 문구 사본이 있으면 버전과 어긋날 수 있다');
      }
    });

    test('지원 요청은 단일 경로(applyToTO)를 통과한다', () {
      final svc = _src('lib/services/firestore/application_firestore.dart');
      final hits = "httpsCallable('callableApplyToTO'".allMatches(svc).length;
      expect(hits, 1, reason: '전송 지점이 하나여야 버전 누락이 생기지 않는다');
    });

    test('DS08B5-08 재지원도 이번 요청의 버전을 쓴다', () {
      expect(applyToTO.contains('reactivateData["documentAccessConsentVersion"]'),
          isTrue);
      expect(applyToTO.contains('resolvedConsentVersion'), isTrue);
      expect(
        applyToTO.contains(
            'reactivateData["documentAccessConsentVersion"] = DOCUMENT_ACCESS'),
        isFalse,
        reason: '서버 최신 상수를 무조건 쓰면 안 된다',
      );
    });
  });

  group('DS08B5-09 갱신 승계 유지', () {
    test('갱신은 원본 버전을 승계한다', () {
      final inherits = RegExp(
        r'documentAccessConsentVersion:\s*\n?\s*freshData\.documentAccessConsentVersion',
      ).allMatches(code).length;
      expect(inherits, greaterThanOrEqualTo(2));
    });

    test('갱신 경로가 버전을 새로 기록하지 않는다', () {
      final autoRenewal = _codeOf(_between(
        source,
        'async function processContractRenewalChecks',
        '"renewalDecision", "==", "TERMINATE"',
      ));
      expect(autoRenewal.contains('resolveDocumentAccessConsentVersion'), isFalse);
      expect(autoRenewal.contains('documentAccessConsentVersion: "'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('DS08B5 서버 계약', () {
    test('서버가 클라이언트 payload를 source로 쓴다', () {
      expect(
        applyToTO.contains('resolveDocumentAccessConsentVersion(') &&
            applyToTO.contains('data.documentAccessConsentVersion'),
        isTrue,
      );
    });

    test('서버 최신 상수를 무조건 기록하지 않는다', () {
      expect(applyToTO.contains('documentAccessConsentVersion: DOCUMENT_ACCESS_CONSENT_V2'),
          isFalse);
    });

    test('allowlist가 두 버전뿐이다', () {
      final list = _between(
        code,
        'const SUPPORTED_DOCUMENT_ACCESS_CONSENT_VERSIONS',
        'function resolveDocumentAccessConsentVersion',
      );
      expect(list.contains('DOCUMENT_ACCESS_CONSENT_V1'), isTrue);
      expect(list.contains('DOCUMENT_ACCESS_CONSENT_V2'), isTrue);
      expect(code.contains('const DOCUMENT_ACCESS_CONSENT_V1 = "$_v1"'), isTrue);
      expect(code.contains('const DOCUMENT_ACCESS_CONSENT_V2 = "$_v2"'), isTrue);
    });

    test('기록 없음일 때 필드를 만들지 않는다', () {
      expect(applyToTO.contains('resolvedConsentVersion !== null'), isTrue);
    });

    test('기존 동의 gate는 그대로다 — 버전은 metadata일 뿐', () {
      expect(applyToTO.contains('if (!idCardConsentGiven)'), isTrue);
      expect(applyToTO.contains('documentAccessConsentGiven: true'), isTrue);
    });
  });

  group('DS08B5 범위 제한', () {
    test('auto-grant·조기퇴사·갱신 grant 로직 무변경', () {
      // [CROSS-DOMAIN-R5.2] grant 생성 로직이 공용 헬퍼로 옮겨졌다 —
      //   초대 수락 경로가 같은 계약을 쓰기 위해서다. 조건 자체는 그대로다.
      final confirm =
          _codeOf(_callableBody(source, 'callableConfirmApplication'));
      expect(confirm.contains('ensureIdCardGrantForConfirmedApplication('), isTrue);
      final helper = _codeOf(source);
      expect(helper.contains('grantSource: "pre_consent",'), isTrue);
      expect(helper.contains('calcPreConsentIdCardExpiryMs(appData,'), isTrue);
      expect(code.contains('shortenedPreConsentExpiry('), isTrue);
    });

    test('권한 축 무변경', () {
      final signed =
          _codeOf(_callableBody(source, 'callableGetIdCardSignedUrl'));
      expect(signed.contains('permissions?.canManageWage'), isTrue);
      expect(signed.contains('canManageWorkers'), isFalse);
    });

    test('통장사본 무변경', () {
      final bank =
          _codeOf(_callableBody(source, 'callableGetBankbookSignedUrl'));
      expect(bank.contains('appStatus !== "CONFIRMED"'), isTrue);
      expect(bank.contains('resolveDocumentAccessConsentVersion'), isFalse);
    });

    test('수동 요청 경로 유지', () {
      expect(code.contains('export const callableCreateIdCardAccessRequest'),
          isTrue);
    });
  });
}
