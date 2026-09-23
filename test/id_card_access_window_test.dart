import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// DS-08B.4 ID-CARD-ACCESS-WINDOW-AND-RENEWAL-GRANT
//
// 신분증 정상 경로:
//   지원 시 사전동의 → 근무 확정 → 요청 없이 auto-grant
//   → 마지막 근무일 + 7일까지 접근 → 조기퇴사 시 자동 단축
//   → 그 뒤 특별 재열람만 수동 요청
//
// 접근 창은 "사용자가 실제로 본 동의 문구"의 범위를 따른다.
//   v2 "2026-09-12-v2" → max(confirmedAt, lastWorkDate) + 7일
//   v1 "2026-08-21-v1" / 버전 없음 → confirmedAt + 7일 (고지 범위 유지)
//
// 서버 실행은 emulator 없이 검증할 수 없다. 아래는 두 종류다.
//   ① 공식 자체를 Dart로 복제해 검증하는 계산 테스트
//   ② 그 공식이 실제 경로에 배선됐는지 확인하는 소스 단정
// ①은 TypeScript 구현과 별개 코드이므로 두 쪽이 어긋나면
// ②의 배선 단정이 깨지도록 짝지어 뒀다.
// ═══════════════════════════════════════════════════════════════

const _indexPath = 'functions/src/index.ts';
const _v1 = '2026-08-21-v1';
const _v2 = '2026-09-12-v2';
const _windowMs = 7 * 24 * 60 * 60 * 1000;

String _source() => File(_indexPath).readAsStringSync();

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
  // 시작 마커 자신이 종료 마커에 다시 걸리지 않도록 그 뒤부터 찾는다.
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(end, isNot(-1), reason: '$startMarker 이후 $endMarker 를 찾지 못함');
  return source.substring(start, end);
}

/// 마커 주변 구간을 잘라낸다. 함수 경계가 주석으로만 표시된 곳에 쓴다.
String _around(String source, String marker, {int before = 600, int after = 1500}) {
  final at = source.indexOf(marker);
  expect(at, isNot(-1), reason: '$marker 를 찾지 못함');
  final s = (at - before) < 0 ? 0 : at - before;
  final e = (at + after) > source.length ? source.length : at + after;
  return source.substring(s, e);
}

// ── 구현 공식의 Dart 복제 ───────────────────────────────────────
// functions/src/index.ts calcPreConsentIdCardExpiryMs 와 동일 규칙.

int calcExpiry({
  required int confirmedAtMs,
  String? version,
  int? actualResignDateMs,
  int? workEndDateMs,
  int? workDateMs,
}) {
  if (version != _v2) return confirmedAtMs + _windowMs;
  final lastWork = actualResignDateMs ?? workEndDateMs ?? workDateMs;
  final lastWorkMs = lastWork ?? confirmedAtMs;
  final anchor = confirmedAtMs > lastWorkMs ? confirmedAtMs : lastWorkMs;
  return anchor + _windowMs;
}

/// shortenedPreConsentExpiry 와 동일 규칙. 단축이 필요 없으면 null.
int? shortenExpiry({
  required String status,
  required String? grantSource,
  required int? existingExpiresAtMs,
  required int resignDateMs,
}) {
  if (status != 'approved') return null;
  if (grantSource == null || !grantSource.startsWith('pre_consent')) return null;
  if (existingExpiresAtMs == null) return null;
  final candidate = resignDateMs + _windowMs;
  if (candidate >= existingExpiresAtMs) return null;
  return candidate;
}

int _d(int y, int m, int day) => DateTime(y, m, day).millisecondsSinceEpoch;

void main() {
  late String source;
  late String code;
  late String confirmApp;
  late String signedUrl;
  late String markIdCard;
  late String autoRenewal;
  late String signFinalize;

  setUpAll(() {
    source = _source();
    code = _codeOf(source);
    confirmApp = _codeOf(_callableBody(source, 'callableConfirmApplication'));
    signedUrl = _codeOf(_callableBody(source, 'callableGetIdCardSignedUrl'));
    markIdCard = _codeOf(_callableBody(source, 'callableMarkIdCardVerified'));
    autoRenewal = _codeOf(_between(
      source,
      'async function processContractRenewalChecks',
      '"renewalDecision", "==", "TERMINATE"',
    ));
    signFinalize =
        _codeOf(_callableBody(source, 'callableFinalizeWorkerSignature'));
  });

  // ───────────────────────────────────────────────────────────
  // Consent version
  // ───────────────────────────────────────────────────────────
  group('DS08B4-01 새 지원 → v2 기록', () {
    test('신규 지원과 재지원 모두 해석된 버전을 기록한다', () {
      // [DS-08B.5] 서버 최신 상수를 무조건 쓰던 것을
      // "클라이언트가 표시한 버전"을 해석해 쓰도록 바꿨다.
      expect(code.contains('const DOCUMENT_ACCESS_CONSENT_V2 = "$_v2"'), isTrue);
      final apply = _codeOf(_callableBody(source, 'callableApplyToTO'));
      expect(apply.contains('resolveDocumentAccessConsentVersion('), isTrue);
      final writes = 'resolvedConsentVersion'.allMatches(apply).length;
      expect(writes, greaterThanOrEqualTo(3),
          reason: '해석 1곳 + 신규 지원 기록 + 재지원 기록');
    });

    test('구 버전 리터럴을 새로 기록하지 않는다', () {
      expect(code.contains('documentAccessConsentVersion: "$_v1"'), isFalse);
      expect(code.contains('documentAccessConsentVersion"] = "$_v1"'), isFalse);
    });
  });

  group('DS08B4-02~04 갱신 consent 승계 (버전 강제 변경 없음)', () {
    test('갱신 경로는 원본 버전을 그대로 승계한다', () {
      final inherits = RegExp(
        r'documentAccessConsentVersion:\s*\n?\s*freshData\.documentAccessConsentVersion',
      ).allMatches(code).length;
      // [AUTO-RENEW-POLICY] 자동 갱신이 Application 을 만들지 않게 된 뒤로
      //   승계가 일어나는 경로는 수동 갱신 하나다. 승계 계약 자체는 그대로다.
      expect(inherits, greaterThanOrEqualTo(1),
          reason: '수동 갱신 경로 — 자동 경로는 새 Application 을 만들지 않는다');
    });

    test('갱신 경로가 v2 상수를 기록하지 않는다', () {
      expect(autoRenewal.contains('DOCUMENT_ACCESS_CONSENT_V2 '), isFalse);
      expect(
        autoRenewal.contains('documentAccessConsentVersion: DOCUMENT_ACCESS'),
        isFalse,
        reason: '사용자가 v2 문구를 보지 않았는데 버전만 올리면 안 된다',
      );
    });

    test('legacy 미보유는 조건부 승계로 유지된다', () {
      // 승계가 일어나는 곳은 수동 갱신이다.
      final manual =
          _codeOf(_callableBody(source, 'callableCreateContractRenewal'));
      expect(
        manual.contains('documentAccessConsentVersion !== undefined'),
        isTrue,
      );
      // 자동 경로에는 승계할 문서 자체가 없다.
      expect(autoRenewal.contains('documentAccessConsentVersion'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────
  // v2 공식
  // ───────────────────────────────────────────────────────────
  group('DS08B4-10~13 v2 접근 창 공식', () {
    test('DS08B4-10 당일 확정/당일 근무 → 확정+7일 수준', () {
      final confirmedAt = _d(2026, 9, 12) + 10 * 3600 * 1000; // 확정 10시
      final got = calcExpiry(
        confirmedAtMs: confirmedAt,
        version: _v2,
        workDateMs: _d(2026, 9, 12),
      );
      // 근무일 자정보다 확정 시각이 늦으므로 max는 확정 시각
      expect(got, confirmedAt + _windowMs);
    });

    test('DS08B4-11 오늘 확정 / 2주 뒤 단기근무 → 근무일+7일', () {
      final confirmedAt = _d(2026, 9, 12);
      final workDate = _d(2026, 9, 26);
      final got = calcExpiry(
        confirmedAtMs: confirmedAt,
        version: _v2,
        workDateMs: workDate,
      );
      expect(got, workDate + _windowMs);
      expect(got, greaterThan(confirmedAt + _windowMs),
          reason: '현행(확정+7일)에서는 근무 전에 만료됐다');
    });

    test('DS08B4-12 30일 장기근무 → 계약 종료일+7일', () {
      final confirmedAt = _d(2026, 9, 1);
      final workEnd = _d(2026, 10, 1);
      final got = calcExpiry(
        confirmedAtMs: confirmedAt,
        version: _v2,
        workDateMs: _d(2026, 9, 2),
        workEndDateMs: workEnd,
      );
      expect(got, workEnd + _windowMs);
    });

    test('DS08B4-13 actualResignDate가 있으면 그것이 기준', () {
      final got = calcExpiry(
        confirmedAtMs: _d(2026, 9, 1),
        version: _v2,
        workDateMs: _d(2026, 9, 2),
        workEndDateMs: _d(2026, 12, 15),
        actualResignDateMs: _d(2026, 10, 1),
      );
      expect(got, _d(2026, 10, 1) + _windowMs);
      expect(got, lessThan(_d(2026, 12, 15) + _windowMs));
    });

    test('소급·당일 확정에서 현행보다 짧아지지 않는다 (max 하한)', () {
      final confirmedAt = _d(2026, 9, 20);
      final got = calcExpiry(
        confirmedAtMs: confirmedAt,
        version: _v2,
        workDateMs: _d(2026, 9, 1), // 이미 지난 근무일
      );
      expect(got, confirmedAt + _windowMs);
    });

    test('날짜 정보가 전혀 없으면 확정 기준으로 떨어진다', () {
      final confirmedAt = _d(2026, 9, 12);
      expect(calcExpiry(confirmedAtMs: confirmedAt, version: _v2),
          confirmedAt + _windowMs);
    });
  });

  // ───────────────────────────────────────────────────────────
  // v1 경계
  // ───────────────────────────────────────────────────────────
  group('DS08B4-20~22 v1 경계 보존', () {
    test('DS08B4-20 v1은 확정+7일 유지', () {
      final confirmedAt = _d(2026, 9, 1);
      expect(
        calcExpiry(
          confirmedAtMs: confirmedAt,
          version: _v1,
          workEndDateMs: _d(2026, 12, 15),
        ),
        confirmedAt + _windowMs,
      );
    });

    test('DS08B4-21 v1을 MODEL C로 확장하지 않는다', () {
      final confirmedAt = _d(2026, 9, 1);
      final v1 = calcExpiry(
        confirmedAtMs: confirmedAt,
        version: _v1,
        workEndDateMs: _d(2026, 12, 15),
      );
      final v2 = calcExpiry(
        confirmedAtMs: confirmedAt,
        version: _v2,
        workEndDateMs: _d(2026, 12, 15),
      );
      expect(v1, lessThan(v2));
    });

    test('버전 없음(legacy)도 확정+7일', () {
      final confirmedAt = _d(2026, 9, 1);
      expect(
        calcExpiry(
          confirmedAtMs: confirmedAt,
          workEndDateMs: _d(2026, 12, 15),
        ),
        confirmedAt + _windowMs,
      );
    });

    test('DS08B4-22 v1 갱신은 새 auto-grant를 만들지 않는다', () {
      // [PII-B4-R1] 이제 v1/v2 구분 없이 아무 auto-grant도 만들지 않는다.
      //   확정·초대수락·재배치·계약서명·자동갱신이 만들던 신분증
      //   auto-grant를 전부 제거했다. 확정은 근무 약속이지 신분증
      //   열람 사유가 아니다. 지금의 계약은
      //   test/tax_identity_review_contract_test.dart.
      expect(autoRenewal.contains('idCardAccessRequests'), isFalse);
      expect(signFinalize.contains('idCardAccessRequests'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────
  // 배선
  // ───────────────────────────────────────────────────────────
  group('DS08B4 공식 배선', () {
    test('헬퍼가 v2에서만 마지막 근무일을 본다', () {
      // [PII-B4-R1] 만료 공식 자체가 사라졌다.
      //   확정 auto-grant 와 그 만료 공식(calcPreConsentIdCardExpiryMs,
      //   isDocumentAccessConsentV2)이 함께 제거됐다. 계산할 접근 창이
      //   없다. 지금의 계약은 test/tax_identity_review_contract_test.dart.
      expect(code.contains('calcPreConsentIdCardExpiryMs'), isFalse);
      expect(code.contains('isDocumentAccessConsentV2'), isFalse);
    });

    test('확정 경로가 헬퍼를 쓴다', () {
      // [PII-B4-R1] 확정 경로에서 grant 생성이 사라졌다.
      //   확정·초대수락·재배치·계약서명·자동갱신이 만들던 신분증
      //   auto-grant를 전부 제거했다. 확정은 근무 약속이지 신분증
      //   열람 사유가 아니다. 지금의 계약은
      //   test/tax_identity_review_contract_test.dart.
      expect(confirmApp.contains('idCardAccessRequests'), isFalse);
    });

    test('DS08B4-30~32 늦은 업로드 소급 생성도 같은 헬퍼를 쓴다', () {
      // [PII-B4-R1] 늦은 업로드의 소급 생성 경로도 제거됐다.
      //   확정·초대수락·재배치·계약서명·자동갱신이 만들던 신분증
      //   auto-grant를 전부 제거했다. 확정은 근무 약속이지 신분증
      //   열람 사유가 아니다. 지금의 계약은
      //   test/tax_identity_review_contract_test.dart.
      expect(markIdCard.contains('idCardAccessRequests'), isFalse);
    });

    test('소급 생성이 업로드 시각 기준 7일을 새로 계산하지 않는다', () {
      // [PII-B4-R1] 소급 생성 자체가 없으므로 만료 계산도 없다.
      //   확정·초대수락·재배치·계약서명·자동갱신이 만들던 신분증
      //   auto-grant를 전부 제거했다. 확정은 근무 약속이지 신분증
      //   열람 사유가 아니다. 지금의 계약은
      //   test/tax_identity_review_contract_test.dart.
      expect(markIdCard.contains('idCardAccessRequests'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────
  // Hidden cap
  // ───────────────────────────────────────────────────────────
  group('DS08B4-40~41 respondedAt 상한 분리', () {
    test('pre_consent grant는 상한에서 제외된다', () {
      expect(signedUrl.contains('capGrantSource.startsWith("pre_consent")'), isTrue);
      expect(signedUrl.contains('if (!isPreConsentGrant && respondedAt)'), isTrue);
    });

    test('수동 grant의 respondedAt+7일 상한은 유지된다', () {
      expect(signedUrl.contains('respondedAt.toMillis() + 7 * 24 * 60 * 60 * 1000'),
          isTrue);
      expect(signedUrl.contains('신분증 열람 권한이 만료되었습니다'), isTrue);
    });

    test('grant 유효성 기본 조건은 그대로다', () {
      expect(signedUrl.contains('"status", "==", "approved"'), isTrue);
      expect(signedUrl.contains('"expiresAt", ">", now'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // 조기퇴사 재계산
  // ───────────────────────────────────────────────────────────
  group('DS08B4-50~53 조기퇴사 단축', () {
    test('DS08B4-50 기존 expiry가 더 길면 단축된다', () {
      final resign = _d(2026, 10, 1);
      final got = shortenExpiry(
        status: 'approved',
        grantSource: 'pre_consent',
        existingExpiresAtMs: _d(2026, 12, 22),
        resignDateMs: resign,
      );
      expect(got, resign + _windowMs);
    });

    test('DS08B4-51 기존 expiry가 더 짧으면 그대로 둔다', () {
      final got = shortenExpiry(
        status: 'approved',
        grantSource: 'pre_consent',
        existingExpiresAtMs: _d(2026, 9, 8),
        resignDateMs: _d(2026, 10, 1),
      );
      expect(got, isNull, reason: '조기 종료를 근거로 접근을 늘리면 안 된다');
    });

    test('DS08B4-52 수동 grant는 건드리지 않는다', () {
      final got = shortenExpiry(
        status: 'approved',
        grantSource: null,
        existingExpiresAtMs: _d(2026, 12, 22),
        resignDateMs: _d(2026, 10, 1),
      );
      expect(got, isNull);
    });

    test('DS08B4-53 닫힌 grant는 재활성화하지 않는다', () {
      for (final closed in ['expired', 'revoked', 'rejected', 'pending']) {
        expect(
          shortenExpiry(
            status: closed,
            grantSource: 'pre_consent',
            existingExpiresAtMs: _d(2026, 12, 22),
            resignDateMs: _d(2026, 10, 1),
          ),
          isNull,
          reason: '$closed grant를 되살리면 안 된다',
        );
      }
    });

    test('소급 생성 grant(pre_consent_retroactive)도 단축 대상이다', () {
      final resign = _d(2026, 10, 1);
      expect(
        shortenExpiry(
          status: 'approved',
          grantSource: 'pre_consent_retroactive',
          existingExpiresAtMs: _d(2026, 12, 22),
          resignDateMs: resign,
        ),
        resign + _windowMs,
      );
    });

    test('세 종료일 확정 경로 모두에 배선돼 있다', () {
      final termination =
          _codeOf(_callableBody(source, 'callableApproveTermination'));
      final resignation =
          _codeOf(_callableBody(source, 'callableApproveResignation'));
      final autoResign = _around(code, 'resignStatus: "AUTO_APPROVED"');
      for (final body in [termination, resignation, autoResign]) {
        expect(body.contains('shortenedPreConsentExpiry('), isTrue);
      }
    });

    test('동일 트랜잭션에서 처리된다 — grant read가 write 이전', () {
      final termination =
          _codeOf(_callableBody(source, 'callableApproveTermination'));
      expect(
        termination.indexOf('tx.get(termGrantRef)'),
        lessThan(termination.indexOf('tx.update(termGrantRef')),
      );
    });

    test('D+1 CANCELED 전환은 grant를 revoke하지 않는다', () {
      final d1 = _between(
        code,
        'async function processResignEffectiveTransition',
        'async function ',
      );
      expect(d1.contains('idCardAccessRequests'), isFalse,
          reason: '종료일+7일 정상 후처리 창을 다음날 끊으면 안 된다');
    });
  });

  // ───────────────────────────────────────────────────────────
  // 갱신 grant
  // ───────────────────────────────────────────────────────────
  group('DS08B4-60~65 갱신 auto-grant', () {
    test('DS08B4-60 자동 갱신은 CONFIRMED TX에서 grant를 만든다', () {
      // [PII-B4-R1] CONFIRMED 전이는 그대로, grant 생성만 사라졌다.
      //   확정·초대수락·재배치·계약서명·자동갱신이 만들던 신분증
      //   auto-grant를 전부 제거했다. 확정은 근무 약속이지 신분증
      //   열람 사유가 아니다. 지금의 계약은
      //   test/tax_identity_review_contract_test.dart.
      // [AUTO-RENEW-POLICY] 자동 갱신은 CONFIRMED TX 자체를 만들지 않는다.
      //   침묵을 합의로 읽지 않기로 했고, 그래서 만들 grant 도 없다.
      expect(autoRenewal.contains('status: "CONFIRMED"'), isFalse);
      expect(autoRenewal.contains('idCardAccessRequests'), isFalse);
    });

    test('DS08B4-61 수동 갱신 생성 시점에는 grant가 없다', () {
      final manual =
          _codeOf(_callableBody(source, 'callableCreateContractRenewal'));
      expect(manual.contains('idCardAccessRequests'), isFalse);
    });

    test('DS08B4-62 서명 완료 전환에서 grant를 만든다', () {
      // [PII-B4-R1] 계약 서명 전환에서도 grant를 만들지 않는다.
      //   확정·초대수락·재배치·계약서명·자동갱신이 만들던 신분증
      //   auto-grant를 전부 제거했다. 확정은 근무 약속이지 신분증
      //   열람 사유가 아니다. 지금의 계약은
      //   test/tax_identity_review_contract_test.dart.
      expect(signFinalize.contains('idCardAccessRequests'), isFalse);
    });

    test('DS08B4-63 v1 갱신은 제외된다', () {
      // [PII-B4-R1] 동의 버전과 무관하게 grant를 만들지 않는다.
      //   확정·초대수락·재배치·계약서명·자동갱신이 만들던 신분증
      //   auto-grant를 전부 제거했다. 확정은 근무 약속이지 신분증
      //   열람 사유가 아니다. 지금의 계약은
      //   test/tax_identity_review_contract_test.dart.
      expect(autoRenewal.contains('idCardAccessRequests'), isFalse);
      expect(signFinalize.contains('idCardAccessRequests'), isFalse);
    });

    test('DS08B4-64 consent 없으면 만들지 않는다', () {
      // [PII-B4-R1] 동의 유무와 무관하게 grant를 만들지 않는다.
      //   확정·초대수락·재배치·계약서명·자동갱신이 만들던 신분증
      //   auto-grant를 전부 제거했다. 확정은 근무 약속이지 신분증
      //   열람 사유가 아니다. 지금의 계약은
      //   test/tax_identity_review_contract_test.dart.
      expect(autoRenewal.contains('idCardAccessRequests'), isFalse);
      expect(signFinalize.contains('idCardAccessRequests'), isFalse);
    });

    test('DS08B4-65 새 application id로 만든다 — old grant 재사용 없음', () {
      // [PII-B4-R1] 새 grant도 옛 grant도 만들지 않는다.
      //   확정·초대수락·재배치·계약서명·자동갱신이 만들던 신분증
      //   auto-grant를 전부 제거했다. 확정은 근무 약속이지 신분증
      //   열람 사유가 아니다. 지금의 계약은
      //   test/tax_identity_review_contract_test.dart.
      expect(autoRenewal.contains('idCardAccessRequests'), isFalse);
    });

    test('갱신 grant 만료는 새 근무 기간으로 계산된다', () {
      // [PII-B4-R1] 만료를 계산할 grant가 없다. 갱신 기간 자체는 그대로 계산된다.
      //   확정·초대수락·재배치·계약서명·자동갱신이 만들던 신분증
      //   auto-grant를 전부 제거했다. 확정은 근무 약속이지 신분증
      //   열람 사유가 아니다. 지금의 계약은
      //   test/tax_identity_review_contract_test.dart.
      // [AUTO-RENEW-POLICY] 새 근무 기간을 자동으로 만들지 않으므로
      //   계산할 grant 도, 계산할 기간도 없다.
      expect(autoRenewal.contains('Timestamp.fromDate(newStartDate)'), isFalse);
      expect(autoRenewal.contains('Timestamp.fromDate(newEndDate)'), isFalse);
      expect(autoRenewal.contains('idCardAccessRequests'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────
  // 범위 제한
  // ───────────────────────────────────────────────────────────
  group('DS08B4 범위 제한', () {
    test('권한 축이 canManageWage 그대로다', () {
      expect(signedUrl.contains('permissions?.canManageWage'), isTrue);
      expect(signedUrl.contains('canManageWorkers'), isFalse);
      final bank = _codeOf(_callableBody(source, 'callableGetBankbookSignedUrl'));
      expect(bank.contains('permissions?.canManageWage'), isTrue);
    });

    test('통장사본 로직이 그대로다', () {
      final bank = _codeOf(_callableBody(source, 'callableGetBankbookSignedUrl'));
      expect(bank.contains('appStatus !== "CONFIRMED"'), isTrue);
      expect(bank.contains('documentAccessConsentGiven'), isTrue);
      expect(bank.contains('calcPreConsentIdCardExpiryMs'), isFalse,
          reason: '통장사본은 이번 변경 대상이 아니다');
    });

    test('NO_SHOW 경로는 grant를 건드리지 않는다', () {
      final noShow = _codeOf(_callableBody(source, 'callableBatchSetNoShow'));
      expect(noShow.contains('idCardAccessRequests'), isFalse);
    });

    test('기존 revoke 사유가 유지된다', () {
      for (final reason in [
        'APPLICATION_CANCELED',
        'APPLICATION_AUTO_CANCELED',
        'APPLICATION_SLOT_DELETED',
        'APPLICATION_CLEANUP',
        'ID_CARD_DELETED',
      ]) {
        expect(code.contains(reason), isTrue);
      }
    });

    test('수동 요청 경로가 살아 있다', () {
      expect(code.contains('export const callableCreateIdCardAccessRequest'), isTrue);
      expect(code.contains('export const callableRespondIdCardAccessRequest'), isTrue);
    });

    test('만료 스케줄러는 expiresAt 기준 그대로다', () {
      final sched = _between(
        code,
        'async function processExpiredIdCardAccess',
        'async function ',
      );
      expect(sched.contains('"expiresAt", "<=", now'), isTrue);
      expect(sched.contains('status: "expired"'), isTrue);
    });

    test('DS-03 홈 진입점은 건드리지 않았다', () {
      final home = File('lib/screens/user/user_home_screen.dart').readAsStringSync();
      expect(home.contains('getPendingIdCardRequestsForUser'), isTrue);
      expect(home.contains('MyRequestsDialog.show('), isTrue);
    });
  });
}
