import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// DS-08B.3 RENEWAL-CONSENT-INHERITANCE-ALIGNMENT
//
// [DOCUMENT-ACCESS-CONSENT-RENEWAL-POLICY]
// 동일 고용관계의 계약 갱신은 원 application의 서류 접근 사전동의를
// 그대로 승계한다. 갱신마다 재동의를 받지 않는다.
//
// 감사에서 두 갱신 경로가 상반된 구현을 갖고 있었다.
//   자동 갱신(processContractRenewalChecks) — 화이트리스트 누락 → 승계 안 됨
//   수동 갱신(callableCreateContractRenewal) — ...freshData 스프레드 → 승계됨
// 이 테스트는 두 경로가 같은 승계 계약을 갖는 상태를 고정한다.
//
// 서버 동작은 emulator 없이 실행할 수 없으므로 구조 수준 고정이다.
// ═══════════════════════════════════════════════════════════════

const _indexPath = 'functions/src/index.ts';

/// 승계 대상 3개 필드. given과 version이 함께 움직여야 한다.
const _consentFields = [
  'documentAccessConsentGiven',
  'idCardConsentGiven',
  'documentAccessConsentVersion',
];

String _source() => File(_indexPath).readAsStringSync();

/// 주석 줄을 제거한 사본. 설명 주석이 배선 스캔에 잡히는 것을 막는다.
String _codeOf(String body) => body
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// 시작 마커부터 종료 마커까지 잘라낸다.
String _between(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  expect(start, isNot(-1), reason: '$startMarker 를 찾지 못함');
  final end = source.indexOf(endMarker, start);
  expect(end, isNot(-1), reason: '$startMarker 이후 $endMarker 를 찾지 못함');
  return source.substring(start, end);
}

/// `export const <name> = onCall(` 부터 괄호 짝을 맞춰 callable 전체를 잘라낸다.
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

/// "원본에 있으면 복사, 없으면 만들지 않음" 형태.
String _inheritGuard(String field) => '$field !== undefined';

/// `field: freshData.field` — 줄바꿈·들여쓰기에 무관하게 매칭한다.
bool _inheritsFromOriginal(String body, String field) =>
    RegExp('$field:\\s*freshData\\.$field').hasMatch(body);

void main() {
  late String source;
  late String autoRenewal;
  late String manualRenewal;

  setUpAll(() {
    source = _source();
    // 자동 갱신: 신규 application을 쓰는 tx.set 블록
    autoRenewal = _codeOf(_between(
      source,
      'async function processContractRenewalChecks',
      '"renewalDecision", "==", "TERMINATE"',
    ));
    manualRenewal =
        _codeOf(_callableBody(source, 'callableCreateContractRenewal'));
  });

  // ───────────────────────────────────────────────────────────
  group('DS08B3-01 자동 갱신 — 원본 동의 승계', () {
    for (final field in _consentFields) {
      test('$field 을 원본에서 복사한다', () {
        expect(_inheritsFromOriginal(autoRenewal, field), isTrue,
            reason: '자동 갱신 화이트리스트에 $field 승계가 있어야 한다');
      });
    }

    test('원본 snapshot을 source로 쓴다 — users/신분증 등 다른 근거 사용 안 함', () {
      final block = _between(
        autoRenewal,
        'documentAccessConsentGiven',
        'status: "CONFIRMED"',
      );
      expect(block.contains('isIdVerified'), isFalse);
      expect(block.contains('users'), isFalse);
    });
  });

  group('DS08B3-02 자동 갱신 — false는 false로', () {
    test('true를 강제로 만들어내지 않는다', () {
      for (final field in _consentFields) {
        expect(autoRenewal.contains('$field: true'), isFalse,
            reason: '$field 에 리터럴 true를 쓰면 안 된다');
      }
    });

    test('기본값으로 true를 채우지 않는다', () {
      for (final field in _consentFields) {
        expect(autoRenewal.contains('$field ?? true'), isFalse);
      }
    });
  });

  group('DS08B3-03 자동 갱신 — legacy 미보유는 그대로 미보유', () {
    for (final field in _consentFields) {
      test('$field 이 없으면 새 문서에도 만들지 않는다', () {
        expect(autoRenewal.contains(_inheritGuard(field)), isTrue,
            reason: '조건부 승계여야 한다 (undefined는 필드 자체를 생성하지 않음)');
      });
    }

    test('null로 채워 넣지도 않는다', () {
      for (final field in _consentFields) {
        expect(autoRenewal.contains('$field: null'), isFalse);
        expect(autoRenewal.contains('$field ?? null'), isFalse);
      }
    });
  });

  group('DS08B3-04 수동 갱신 — 승계 계약 유지', () {
    for (final field in _consentFields) {
      test('$field 승계가 명시돼 있다', () {
        expect(_inheritsFromOriginal(manualRenewal, field), isTrue);
      });
    }

    test('원본 스프레드 기반 복사도 그대로 유지된다', () {
      expect(manualRenewal.contains('...freshData'), isTrue,
          reason: '수동 갱신 semantics를 바꾸지 않는다');
    });

    test('수동 갱신도 true를 만들어내지 않는다', () {
      for (final field in _consentFields) {
        expect(manualRenewal.contains('$field: true'), isFalse);
      }
    });
  });

  group('DS08B3-05 두 경로 semantics 일치', () {
    test('동일한 조건부 승계 형태를 쓴다', () {
      for (final field in _consentFields) {
        expect(autoRenewal.contains(_inheritGuard(field)), isTrue);
        expect(manualRenewal.contains(_inheritGuard(field)), isTrue);
      }
    });

    test('동일한 source(freshData)를 쓴다', () {
      for (final field in _consentFields) {
        expect(autoRenewal.contains('freshData.$field'), isTrue);
        expect(manualRenewal.contains('freshData.$field'), isTrue);
      }
    });
  });

  group('DS08B3-06 version 동반 승계', () {
    test('given만 승계하고 version을 빠뜨리지 않는다', () {
      for (final body in [autoRenewal, manualRenewal]) {
        final hasGiven =
            _inheritsFromOriginal(body, 'documentAccessConsentGiven');
        final hasVersion =
            _inheritsFromOriginal(body, 'documentAccessConsentVersion');
        expect(hasGiven && hasVersion, isTrue,
            reason: 'given과 version은 같은 snapshot으로 함께 움직여야 한다');
      }
    });

    test('새 consent version을 만들지 않는다', () {
      for (final body in [autoRenewal, manualRenewal]) {
        expect(body.contains('documentAccessConsentVersion: "'), isFalse,
            reason: '갱신 경로에서 버전 문자열을 새로 쓰면 안 된다');
      }
    });

    test('버전을 쓰는 곳은 지원 경로뿐이다', () {
      // [DS-08B.4] 리터럴 → DOCUMENT_ACCESS_CONSENT_V2 상수로 이동.
      // 갱신은 원본 값을 승계할 뿐 버전을 새로 기록하지 않는다.
      final code = _codeOf(source);
      final writes =
          'documentAccessConsentVersion'.allMatches(code).length;
      final inherits = RegExp(
        r'documentAccessConsentVersion:\s*\n?\s*freshData\.documentAccessConsentVersion',
      ).allMatches(code).length;
      final constWrites =
          'DOCUMENT_ACCESS_CONSENT_V2'.allMatches(code).length;
      expect(inherits, 3,
          reason: '자동·수동 갱신 승계 2곳 + 자동 갱신 grant 만료 계산 입력 1곳');
      expect(constWrites, greaterThanOrEqualTo(2),
          reason: 'callableApplyToTO 신규·재지원 2곳이 상수로 기록');
      expect(writes, greaterThan(0));
    });
  });

  group('DS08B3-07 접근권 생성 — DS-08B.4에서 v2 한정으로 열림', () {
    // DS-08B.3 시점에는 두 갱신 경로 모두 grant를 만들지 않았다.
    // DS-08B.4에서 v2 동의 승계 건에 한해 생성하도록 열었고,
    // v1/legacy cohort는 여전히 생성하지 않는다.
    test('자동 갱신은 v2 동의일 때만 grant를 만든다', () {
      expect(autoRenewal.contains('isDocumentAccessConsentV2(freshData)'), isTrue,
          reason: 'v1/legacy에 새 접근 창을 열면 안 된다');
      expect(autoRenewal.contains('grantSource: "pre_consent"'), isTrue);
    });

    test('수동 갱신은 CONTRACT_PENDING 생성 시점에 grant를 만들지 않는다', () {
      expect(manualRenewal.contains('idCardAccessRequests'), isFalse);
      expect(manualRenewal.contains('grantSource'), isFalse);
      expect(manualRenewal.contains('expiresAt'), isFalse);
    });

    test('auto-grant 생성은 확정 callable에도 그대로 있다', () {
      final confirm = _codeOf(_callableBody(source, 'callableConfirmApplication'));
      expect(confirm.contains('grantSource: "pre_consent"'), isTrue);
    });
  });

  group('DS08B3-08 사용자 노출 문구 무변경', () {
    test('지원 동의 문구가 v2 문안이다', () {
      // [DS-08B.4] 접근 종료 기준이 바뀌면서 문구도 함께 개정됐다.
      // [DS-08B.5] 문구와 버전이 drift하지 않도록 한 파일로 모았다.
      final consent = File(
        'lib/widgets/dialogs/apply/document_access_consent.dart',
      ).readAsStringSync();
      expect(consent.contains('마지막 근무일로부터 7일 후 자동 종료됩니다'), isTrue);
      expect(consent.contains('급여처리 관계가 유효한 동안'), isTrue);
      expect(consent.contains('갱신된 근무관계에도 승계됩니다'), isTrue);
      expect(consent.contains('확정일로부터 7일간'), isFalse,
          reason: '구 문구가 남아 있으면 안 된다');

      for (final path in [
        'lib/widgets/dialogs/apply/apply_confirm_dialog.dart',
        'lib/widgets/dialogs/apply/multi_apply_confirm_sheet.dart',
      ]) {
        expect(File(path).readAsStringSync().contains('DocumentAccessConsent.card('),
            isTrue);
      }
    });

    test('자동 갱신 알림 문구가 그대로다', () {
      expect(autoRenewal.contains('"계약 자동 연장"'), isTrue);
      expect(autoRenewal.contains('까지 자동 연장되었습니다.'), isTrue);
    });

    test('갱신 경로에 재동의 UI가 추가되지 않았다', () {
      for (final body in [autoRenewal, manualRenewal]) {
        expect(body.contains('동의'), isFalse,
            reason: '갱신 경로는 사용자에게 동의를 다시 묻지 않는다');
      }
    });
  });

  group('DS08B3 회귀 — 갱신 lifecycle 무변경', () {
    test('자동 갱신은 CONFIRMED, 수동 갱신은 CONTRACT_PENDING 그대로다', () {
      expect(autoRenewal.contains('status: "CONFIRMED"'), isTrue);
      expect(manualRenewal.contains('status: "CONTRACT_PENDING"'), isTrue);
    });

    test('갱신 링크 필드가 유지된다', () {
      expect(autoRenewal.contains('renewedFromApplicationId'), isTrue);
      expect(autoRenewal.contains('renewedToApplicationId'), isTrue);
      expect(manualRenewal.contains('renewedFromApplicationId'), isTrue);
      expect(manualRenewal.contains('renewedToApplicationId'), isTrue);
      expect(manualRenewal.contains('renewalDecision: "EXTEND"'), isTrue);
    });

    test('근무 기간·확정 시각 기록이 유지된다', () {
      for (final body in [autoRenewal, manualRenewal]) {
        expect(body.contains('workEndDate'), isTrue);
        expect(body.contains('confirmedAt'), isTrue);
      }
    });

    // [PREDEVICE-CONTRACT-OBLIGATION] 이 계약은 뒤집혔다.
    //   예전에는 자동 갱신이 employment_contracts 문서를 미리 하나 만들었다.
    //   그 문서에는 snapshot·toId·isLongTerm·articles가 없어
    //   EmploymentContractModel이 파싱을 거부했고(tryFromMap → null),
    //   근로자에게도 관리자에게도 보이지 않았다. 서명 흐름도 그것을 쓰지 않는다
    //   — 장기 계약의 findOrCreateContract는 항상 _createNew로 가고 저장은
    //   callableFinalizeEmployerSignature가 pending_worker로 새 문서에 한다.
    //   즉 아무도 쓰지 않는 고아였고, 남겨두면 srvContractIssuedFor가 그것을
    //   보고 "계약서 있음"으로 오판한다. 갱신된 근무관계의 계약 의무는
    //   문서를 미리 만드는 대신 srvNeedsContractIssue가 좌석으로 판정한다.
    test('자동 갱신은 계약서 문서를 미리 만들지 않는다', () {
      expect(autoRenewal.contains('employment_contracts'), isFalse,
          reason: 'parse 불가 고아 계약서를 다시 만들면 계약 의무 판정이 왜곡된다');
    });

    test('집계 필드 초기화가 유지된다', () {
      for (final body in [autoRenewal, manualRenewal]) {
        expect(body.contains('wageStatus: "pending"'), isTrue);
        expect(body.contains('finalWage: null'), isTrue);
      }
    });
  });

  group('DS08B3 범위 제한', () {
    test('신분증 권한 축이 canManageWage 그대로다', () {
      final signed = _codeOf(_callableBody(source, 'callableGetIdCardSignedUrl'));
      expect(signed.contains('permissions?.canManageWage'), isTrue);
      expect(signed.contains('canManageWorkers'), isFalse);
    });

    test('통장사본 권한 축이 canManageWage 그대로다', () {
      final bank = _codeOf(_callableBody(source, 'callableGetBankbookSignedUrl'));
      expect(bank.contains('permissions?.canManageWage'), isTrue);
      expect(bank.contains('canManageWorkers'), isFalse);
    });

    test('7일 duration이 그대로다', () {
      // [DS-08B.4] 리터럴이 ID_CARD_ACCESS_WINDOW_MS 상수로 이동했다.
      // 바뀐 것은 기준점이고 7일이라는 길이는 유지된다.
      final code = _codeOf(source);
      expect(code.contains('const ID_CARD_ACCESS_WINDOW_MS = 7 * 24 * 60 * 60 * 1000'),
          isTrue);
      final confirm = _codeOf(_callableBody(source, 'callableConfirmApplication'));
      expect(confirm.contains('calcPreConsentIdCardExpiryMs('), isTrue);
    });
  });
}
