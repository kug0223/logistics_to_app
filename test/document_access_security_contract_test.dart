// [DOC-S1A] 민감문서 접근 보안 계약.
//
//   이 테스트가 지키는 문장은 둘이다.
//
//     감사 기록이 성공하지 않으면 민감정보는 client 로 가지 않는다.
//     예외·불일치·보완요청 상태는 접근 자격이 아니다.
//
//   창 계산은 Dart 에서 재구현해 경계를 직접 고정하고(순수 함수),
//   서버 배선은 소스 문자열로 고정한다 — 둘 다 없으면 한쪽만 고쳐도 통과한다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 주석을 걷어낸 코드만 본다. 마커가 주석에만 있으면 계약이 아니다.
String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// [name] 선언 이후 [chars] 구간. 창이 다음 함수로 넘치지 않게 길이를 잰다.
String _after(String src, String name, int chars) {
  final i = src.indexOf(name);
  expect(i, greaterThan(-1), reason: '$name 을 찾지 못했다');
  final end = (i + chars) > src.length ? src.length : i + chars;
  return src.substring(i, end);
}

// ─────────────────────────────────────────────────────────────
// 창 계산 — 서버 srvIdWindowLastWorkDay / srvIdWindowOpen 과 같은 식
// ─────────────────────────────────────────────────────────────

const _kstMs = 9 * 3600 * 1000;
const _windowMs = 7 * 24 * 60 * 60 * 1000;
const _longTypes = {'long_term', 'contract'};
const _shortTypes = {'short', 'flex'};

int _kstDateNum(DateTime d) {
  final k = d.toUtc().add(const Duration(milliseconds: _kstMs));
  return k.year * 10000 + k.month * 100 + k.day;
}

/// 지원서 한 건이 기여하는 마지막 근무일. 모르면 null.
DateTime? idWindowLastWorkDay({
  String? type,
  DateTime? actualResignDate,
  DateTime? workEndDate,
  DateTime? workDate,
  List<String>? workDays,
}) {
  if (actualResignDate != null) return actualResignDate;
  if (type != null && _shortTypes.contains(type)) return workDate;
  if (type != null && _longTypes.contains(type)) return workEndDate;
  final looksLong = workDays != null &&
      workDays.isNotEmpty &&
      workEndDate != null &&
      workDate != null &&
      _kstDateNum(workEndDate) != _kstDateNum(workDate);
  return looksLong ? workEndDate : workDate;
}

bool idWindowOpen(DateTime? end, DateTime now) {
  if (end == null) return false;
  final k = end.toUtc().add(const Duration(milliseconds: _kstMs));
  final midnightKstAsUtcMs =
      DateTime.utc(k.year, k.month, k.day).millisecondsSinceEpoch - _kstMs;
  return now.toUtc().millisecondsSinceEpoch < midnightKstAsUtcMs + _windowMs;
}

const _v1 = '2026-08-21-v1';
const _v2 = '2026-09-12-v2';
const _v3 = '2026-09-18-v3';

/// [DS-08B.4] 창의 기준점은 동의 버전마다 다르다.
///   v2/v3 → 마지막 근무일 · v1/legacy → 확정일
const _supported = {_v1, _v2, _v3};

/// [DOC-S1A.2] 원본 신분증 문은 **명시적으로 기록된** 지원 버전만 근거로 본다.
bool explicitConsent({bool given = true, String? consentVersion}) =>
    given && consentVersion != null && _supported.contains(consentVersion);

DateTime? windowBase({
  String? consentVersion,
  DateTime? confirmedAt,
  String? type,
  DateTime? actualResignDate,
  DateTime? workEndDate,
  DateTime? workDate,
  List<String>? workDays,
}) {
  if (consentVersion == _v2 || consentVersion == _v3) {
    return idWindowLastWorkDay(
      type: type,
      actualResignDate: actualResignDate,
      workEndDate: workEndDate,
      workDate: workDate,
      workDays: workDays,
    );
  }
  if (consentVersion == _v1) return confirmedAt;
  // 버전 없음 · 미지원 버전 → 기준점을 고르지 않는다.
  return null;
}

/// KST 기준 시각 → UTC DateTime.
DateTime _kst(int y, int m, int d, [int h = 0, int mi = 0]) =>
    DateTime.utc(y, m, d, h, mi).subtract(const Duration(milliseconds: _kstMs));

void main() {
  late String raw;
  late String code;

  setUpAll(() {
    raw = File('functions/src/index.ts').readAsStringSync();
    code = _codeOf(raw);
  });

  // ═══════════════════════════════════════════════════════════
  // RAW ID — 창 경계
  // ═══════════════════════════════════════════════════════════
  group('DOCS1A RAW ID 창', () {
    test('S1A-01 단기는 workDate 가 마지막 근무일 — 공고 종료일이 아니다', () {
      final end = idWindowLastWorkDay(
        type: 'short',
        workDate: _kst(2026, 9, 1),
        workEndDate: _kst(2026, 9, 30), // TO 전체 종료일
      );
      expect(end, _kst(2026, 9, 1));
    });

    test('S1A-02 flex 도 단기와 같다', () {
      final end = idWindowLastWorkDay(
        type: 'flex',
        workDate: _kst(2026, 9, 1),
        workEndDate: _kst(2026, 9, 30),
      );
      expect(end, _kst(2026, 9, 1));
    });

    test('S1A-03 장기는 workEndDate — workDate(시작일)를 종료로 보지 않는다', () {
      final end = idWindowLastWorkDay(
        type: 'long_term',
        workDate: _kst(2026, 9, 1), // 시작일
        workEndDate: _kst(2026, 10, 31),
      );
      expect(end, _kst(2026, 10, 31));
    });

    test('S1A-04 contract 도 장기다', () {
      final end = idWindowLastWorkDay(
        type: 'contract',
        workDate: _kst(2026, 9, 1),
        workEndDate: _kst(2026, 10, 31),
      );
      expect(end, _kst(2026, 10, 31));
    });

    test('S1A-05 조기 종료가 최우선 — 단축 방향만', () {
      final end = idWindowLastWorkDay(
        type: 'long_term',
        workEndDate: _kst(2026, 10, 31),
        actualResignDate: _kst(2026, 10, 10),
      );
      expect(end, _kst(2026, 10, 10));
    });

    test('S1A-06 NO_END 장기 → null → DENY (fail closed)', () {
      final end = idWindowLastWorkDay(
        type: 'long_term',
        workDate: _kst(2026, 9, 1),
      );
      expect(end, isNull);
      expect(idWindowOpen(end, _kst(2026, 9, 2)), isFalse,
          reason: '종료일을 모르면 창을 주지 않는다');
    });

    test('S1A-07 경계 — D+6 23:59 허용 / D+7 00:00 거부', () {
      final d = _kst(2026, 9, 1);
      expect(idWindowOpen(d, _kst(2026, 9, 7, 23, 59)), isTrue);
      expect(idWindowOpen(d, _kst(2026, 9, 8, 0, 0)), isFalse);
    });

    test('S1A-08 D+8 거부', () {
      expect(idWindowOpen(_kst(2026, 9, 1), _kst(2026, 9, 9)), isFalse);
    });

    test('S1A-09 재직 중(미래 종료일)은 열려 있다', () {
      final end = idWindowLastWorkDay(
        type: 'long_term',
        workDate: _kst(2026, 9, 1),
        workEndDate: _kst(2026, 10, 31),
      );
      expect(idWindowOpen(end, _kst(2026, 9, 15)), isTrue);
    });

    test('S1A-10 legacy(type 없음) — workDays 있고 날짜 다르면 장기로 읽는다', () {
      final end = idWindowLastWorkDay(
        workDays: const ['월', '수'],
        workDate: _kst(2026, 9, 1),
        workEndDate: _kst(2026, 10, 31),
      );
      expect(end, _kst(2026, 10, 31));
    });

    test('S1A-11 legacy 애매하면 가장 좁게 — workDate', () {
      final end = idWindowLastWorkDay(
        workDate: _kst(2026, 9, 1),
        workEndDate: _kst(2026, 9, 30),
      );
      expect(end, _kst(2026, 9, 1), reason: 'workDays 가 없으면 단기로 읽는다');
    });

    // ── [DOC-S1A.1] 버전별 기준점 ──────────────────────────────
    test('S1A-13 v2 는 마지막 근무일이 기준 — 문구 그대로', () {
      final b = windowBase(
        consentVersion: _v2,
        confirmedAt: _kst(2026, 8, 25),
        type: 'long_term',
        workDate: _kst(2026, 9, 1),
        workEndDate: _kst(2026, 10, 31),
      );
      expect(b, _kst(2026, 10, 31));
    });

    test('S1A-14 v3 도 마지막 근무일', () {
      final b = windowBase(
        consentVersion: _v3,
        confirmedAt: _kst(2026, 8, 25),
        type: 'long_term',
        workEndDate: _kst(2026, 10, 31),
      );
      expect(b, _kst(2026, 10, 31));
    });

    test('S1A-15 v1 은 확정일이 기준 — 장기라도 늘어나지 않는다', () {
      final b = windowBase(
        consentVersion: _v1,
        confirmedAt: _kst(2026, 8, 25),
        type: 'long_term',
        workDate: _kst(2026, 9, 1),
        workEndDate: _kst(2026, 10, 31),
      );
      expect(b, _kst(2026, 8, 25),
          reason: 'v1 문구는 "확정일로부터 7일간"이다');
      // 고지하지 않은 범위로 넓어지지 않는다.
      expect(idWindowOpen(b, _kst(2026, 9, 2)), isFalse);
      expect(idWindowOpen(_kst(2026, 10, 31), _kst(2026, 9, 2)), isTrue,
          reason: 'v2 기준이었다면 열려 있었을 시점');
    });

    // ── [DOC-S1A.2] 버전 없는 동의는 근거가 아니다 ──────────────
    test('S1A-16 버전 없음 → 기준점 없음 → DENY', () {
      final b = windowBase(
        confirmedAt: _kst(2026, 8, 25),
        type: 'long_term',
        workEndDate: _kst(2026, 10, 31),
      );
      expect(b, isNull, reason: '어떤 문구를 보았는지 모르면 기준을 고르지 않는다');
      expect(idWindowOpen(b, _kst(2026, 8, 26)), isFalse);
      expect(explicitConsent(consentVersion: null), isFalse);
    });

    test('S1A-18 미지원 버전 → DENY', () {
      expect(explicitConsent(consentVersion: '2026-08-v1'), isFalse,
          reason: 'idCardConsentVersion 계열을 documentAccessConsentVersion 로 읽지 않는다');
      expect(explicitConsent(consentVersion: '2099-01-v9'), isFalse);
      expect(windowBase(
        consentVersion: '2026-08-v1',
        confirmedAt: _kst(2026, 8, 25),
      ), isNull);
    });

    test('S1A-19 given=false 면 버전이 있어도 근거가 아니다', () {
      expect(explicitConsent(given: false, consentVersion: _v3), isFalse);
    });

    test('S1A-19b 명시적 v1/v2/v3 는 근거가 된다', () {
      for (final v in [_v1, _v2, _v3]) {
        expect(explicitConsent(consentVersion: v), isTrue, reason: v);
      }
    });

    test('S1A-17 v1 인데 미확정이면 창이 없다', () {
      final b = windowBase(consentVersion: _v1, type: 'long_term',
          workEndDate: _kst(2026, 10, 31));
      expect(b, isNull);
      expect(idWindowOpen(b, _kst(2026, 9, 1)), isFalse);
    });

    test('S1A-12 explicit type 이 structural 추론을 이긴다', () {
      // 단기인데 workDays 를 물려받은 경우 — 공고 종료일로 늘어나면 안 된다.
      final end = idWindowLastWorkDay(
        type: 'short',
        workDays: const ['월', '수'],
        workDate: _kst(2026, 9, 1),
        workEndDate: _kst(2026, 9, 30),
      );
      expect(end, _kst(2026, 9, 1));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 서버 배선 — 권한 / 목적
  // ═══════════════════════════════════════════════════════════
  group('DOCS1A 서버 gate 배선', () {
    test('S1A-20 신분증 원본 door 는 상위 권한을 요구한다', () {
      final body = _after(code, 'callableGetTaxIdentityIdCardUrl', 2200);
      expect(body.contains('srvCanReviewApplicantDocuments('), isTrue,
          reason: 'canManageWage 단독으로 원본이 열리면 안 된다');
      expect(body.contains('srvHasActiveIdentityDocumentPurpose('), isTrue,
          reason: '고지된 창 밖에서 열리면 안 된다');
    });

    test('S1A-21 세무 3 door 가 목적 술어를 쓴다', () {
      for (final f in [
        'callableGetTaxIdentityReview',
        'callableGetTaxIdentityNumber',
        'callableReviewTaxIdentity',
      ]) {
        expect(_after(code, f, 2000).contains('srvHasCurrentTaxIdentityPurpose('),
            isTrue,
            reason: '$f 가 현재 세무 목적을 확인하지 않는다');
      }
    });

    test('S1A-22 기한 없는 관계 술어가 사라졌다', () {
      expect(code.contains('srvHasBusinessWorkerRelationship'), isFalse,
          reason: '관계 존재만으로 민감문서를 여는 경로가 남아 있으면 안 된다');
    });

    test('S1A-23 세무 목적은 실근무 status 집합으로 판정한다', () {
      // [DOC-S1A.4] 토큰을 여기서 다시 적지 않는다 — 한 번 적었다가
      //   조퇴를 "earlyLeave" 로 써서 존재하지 않는 값을 비교했다.
      final body = _after(code, 'srvHasCurrentTaxIdentityPurpose', 1600);
      expect(body.contains('.where("status", "in", ACTUAL_WORK_STATUSES)'),
          isTrue);
      expect(body.contains('"earlyLeave"'), isFalse,
          reason: '저장되는 값은 early_leave 다');
      expect(body.contains('NO_SHOW'), isFalse,
          reason: 'NO_SHOW·absent 는 실근무가 아니다');
      expect(body.contains('wageStatus'), isFalse,
          reason: '급여 확정을 기다리면 지급 전에 불일치를 잡을 수 없다');
    });

    test('S1A-23b [DOC-S1A.4] canonical 집합이 저장되는 값과 같다', () {
      expect(
        code.contains(
            'const ACTUAL_WORK_STATUSES = ["present", "late", "early_leave"];'),
        isTrue,
      );
      // 조퇴를 쓰는 writer 가 같은 토큰을 쓴다.
      expect(code.contains('status = "early_leave";'), isTrue);
      // 서버 어디에도 status 비교로 쓰이는 camelCase 표기가 없다.
      //   (earlyLeaveUnit 은 반올림 단위 설정 필드명이라 대상이 아니다.)
      final drift = RegExp(r'"earlyLeave"').allMatches(code).length;
      expect(drift, 0, reason: '$drift 곳에 남아 있다');
    });

    test('S1A-24 신분증 목적에 correction 축이 없다 — 창을 연장하지 않는다', () {
      final body = _after(code, 'srvHasActiveIdentityDocumentPurpose', 1800);
      expect(body.contains('DOC_CORRECTION_COL'), isFalse);
      expect(body.contains('CORRECTION_LIVE'), isFalse);
      expect(body.contains('RESUBMITTED'), isFalse);
    });

    test('S1A-27 [DOC-S1A.1] 창 기준점이 동의 버전에 묶여 있다', () {
      final body = _after(code, 'function srvIdWindowOpen', 1400);
      expect(body.contains('documentAccessConsentVersion'), isTrue,
          reason: '사용자가 본 문구의 범위를 적용해야 한다');
      expect(body.contains('DOCUMENT_ACCESS_CONSENT_V2'), isTrue);
      expect(body.contains('DOCUMENT_ACCESS_CONSENT_V3'), isTrue);
      expect(body.contains('DOCUMENT_ACCESS_CONSENT_V1'), isTrue);
      expect(body.contains('confirmedAt'), isTrue,
          reason: 'v1 은 확정일 기준이다');
      expect(body.contains('srvIdWindowLastWorkDay'), isTrue);
    });

    test('S1A-28 [DOC-S1A.2] 원본 문은 명시적 버전만 근거로 본다', () {
      final p = _after(code, 'srvHasActiveIdentityDocumentPurpose', 2400);
      expect(
        p.contains('SUPPORTED_DOCUMENT_ACCESS_CONSENT_VERSIONS.includes(v)'),
        isTrue,
        reason: 'given=true + 버전 없음을 v1 으로 추론하면 안 된다',
      );
      // 창 함수에도 이중 방어가 있다 — 미지원 버전은 기준점을 고르지 않는다.
      final w = _after(code, 'function srvIdWindowOpen', 1400);
      expect(RegExp(r'\}\s*else\s*\{[\s\S]{0,300}?return false;').hasMatch(w),
          isTrue,
          reason: '버전 없음·미지원 버전은 기본 기준점 없이 닫힌다');
    });

    test('S1A-30w [DOC-S1A.3] 약속 writer 는 명시적 버전을 요구한다', () {
      final h = _after(code, 'function srvResolveCommitmentConsentVersion', 700);
      expect(h.contains('if (!given) return null'), isTrue,
          reason: '동의하지 않으면 기록도 자격도 없다');
      expect(RegExp(r'raw === undefined[\s\S]{0,200}?throw new HttpsError')
          .hasMatch(h), isTrue,
          reason: '버전 없음은 추론하지 않고 거절한다');
      expect(h.contains('resolveDocumentAccessConsentVersion(raw, given)'),
          isTrue, reason: '미지원 버전 거절은 기존 규칙 재사용');
    });

    test('S1A-31w [DOC-S1A.3] 세 commitment writer 가 그 술어를 쓴다', () {
      for (final f in [
        'export const callableApplyToTO',
        'callableAcceptTOInvitation',
        'CR_PROPOSAL_COL',
      ]) {
        final i = code.indexOf(f);
        expect(i, greaterThan(-1), reason: f);
      }
      // resolver 직접 호출은 wrapper 정의 안에만 남아야 한다.
      final direct = RegExp(r'(?<!srvResolveCommitmentConsentVersion\()'
          r'\bresolveDocumentAccessConsentVersion\(')
          .allMatches(code).length;
      expect(direct, lessThanOrEqualTo(2),
          reason: '정의 1 + wrapper 내부 1 외에 직접 호출이 남으면 안 된다');
      expect(
        RegExp(r'srvResolveCommitmentConsentVersion\(').allMatches(code).length,
        greaterThanOrEqualTo(4),
        reason: '정의 1 + 호출 3 (지원·초대수락·재배치수락)',
      );
    });

    test('S1A-32w [DOC-S1A.3] 자격을 만들기 **전에** 막는다', () {
      // 지원 경로: 버전 판정이 좌석 트랜잭션보다 앞에 있어야 한다.
      //   함수가 길어 창을 넉넉히 잡는다 — 다음 export 전까지.
      final start = code.indexOf('export const callableApplyToTO');
      expect(start, greaterThan(-1));
      final next = code.indexOf('\nexport const ', start + 10);
      final a = code.substring(start, next > 0 ? next : code.length);
      final gate = a.indexOf('srvResolveCommitmentConsentVersion');
      final tx = a.indexOf('runTransaction');
      expect(gate, greaterThan(-1), reason: '지원 경로에 gate 가 없다');
      expect(tx, greaterThan(-1), reason: '좌석 트랜잭션을 찾지 못했다');
      expect(tx, greaterThan(gate),
          reason: '좌석 트랜잭션 이전에 거절되어야 한다');
    });

    test('S1A-33w [DOC-S1A.3] 세 저장부가 모두 "동의함"을 못박는다', () {
      // 이게 이 패치의 전제다. 저장부가 given 을 무조건 true 로 쓰기 때문에
      //   버전만 비면 "버전 없는 동의" 행이 남는다 — DEV 에 실제로 2건 있었다.
      //   그래서 세 경로 모두 버전을 요구해야 한다.
      for (final f in <String>[
        'export const callableApplyToTO',
        'export const callableAcceptTOInvitation',
        'export const callableAcceptConfirmedReassignment',
      ]) {
        final s = code.indexOf(f);
        expect(s, greaterThan(-1), reason: f);
        final n = code.indexOf('\nexport const ', s + 10);
        final body = code.substring(s, n > 0 ? n : code.length);
        expect(body.contains('documentAccessConsentGiven: true'), isTrue,
            reason: '$f 저장부가 동의를 못박지 않는다면 전제가 바뀐 것이다');
      }
    });

    test('S1A-34w [DOC-S1A.3] 두 수락 경로는 미동의를 먼저 거절한다', () {
      // 지원 경로는 given 을 true 로 고정해 넘기지만, 수락 두 경로는
      //   raw given 을 그대로 넘긴다. 그래도 안전한 이유는 미동의를
      //   좌석 확정 전에 거절하기 때문이다 — 그 가드를 고정한다.
      for (final f in <String>[
        'export const callableAcceptTOInvitation',
        'export const callableAcceptConfirmedReassignment',
      ]) {
        final s = code.indexOf(f);
        final n = code.indexOf('\nexport const ', s + 10);
        final body = code.substring(s, n > 0 ? n : code.length);
        expect(
          body.contains('동의해야 초대를 수락할 수 있습니다') ||
              body.contains('동의해야 변경을 수락할 수 있습니다'),
          isTrue,
          reason: '$f 에 미동의 거절이 없다',
        );
      }
    });

    test('S1A-29 [DOC-S1A.2] resolve 규칙 자체는 그대로 둔다', () {
      // 기록 규칙을 전역으로 바꾸면 다른 legacy 호환 경로가 깨진다.
      expect(code.contains('function resolveDocumentAccessConsentVersion'),
          isTrue);
      final r = _after(code, 'function resolveDocumentAccessConsentVersion', 700);
      expect(r.contains('DOCUMENT_ACCESS_CONSENT_V1'), isTrue,
          reason: '기록 시 v1 폴백은 유지 — 원본 문에서만 거부한다');
    });

    test('S1A-25 기준을 모르면 양쪽 술어 모두 거부한다 (fail closed)', () {
      // 이름이 아니라 동작을 고정한다 — 기준 timestamp 가 없으면 false.
      final w = _after(code, 'function srvIdWindowOpen', 1200);
      expect(RegExp(r'if \(!\w+\) return false;').hasMatch(w), isTrue,
          reason: 'NO_END·미확정·malformed 는 창을 주지 않는다');
      final t = _after(code, 'srvHasCurrentTaxIdentityPurpose', 1600);
      expect(RegExp(r'if \(!\w+\) return false;').hasMatch(t), isTrue,
          reason: '약속의 끝을 모르면 세무 목적을 인정하지 않는다');
    });

    test('S1A-26 거부 문구가 단일화돼 존재를 누설하지 않는다', () {
      expect(code.contains('TAX_PURPOSE_DENY_MSG'), isTrue);
      expect(code.contains('ID_DOC_DENY_MSG'), isTrue);
      final n = _after(code, 'callableGetTaxIdentityIdCardUrl', 2200);
      expect(n.contains('이 사업장의 근로자가 아닙니다'), isFalse,
          reason: '관계 유무가 응답으로 새면 안 된다');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 감사 fail-closed
  // ═══════════════════════════════════════════════════════════
  // ─────────────────────────────────────────────────────────────
  // [DOC-S1A.4] 세무 목적 실근무 판정 — 저장되는 값으로 판정하는가
  // ─────────────────────────────────────────────────────────────
  group('DOCS1A.4 세무 목적 실근무 status', () {
    // 서버 A 분기와 같은 식: status ∈ ACTUAL_WORK_STATUSES.
    //   wageStatus 는 보지 않고, 지원서 현재 상태도 보지 않는다.
    const canonical = {'present', 'late', 'early_leave'};
    bool actualWorkBranch(List<String> statuses) =>
        statuses.any(canonical.contains);

    test('S1A-4A present 만 있어도 목적이 선다', () {
      expect(actualWorkBranch(['present']), isTrue);
    });
    test('S1A-4B late 만 있어도 목적이 선다', () {
      expect(actualWorkBranch(['late']), isTrue);
    });
    test('S1A-4C early_leave 만 있어도 목적이 선다', () {
      expect(actualWorkBranch(['early_leave']), isTrue,
          reason: '조퇴도 실제로 일한 것이다 — 이 줄이 이번 BLOCKER 다');
    });
    test('S1A-4C2 존재하지 않는 표기로는 아무것도 걸리지 않는다', () {
      expect(canonical.contains('earlyLeave'), isFalse,
          reason: '저장된 값과 비교 토큰이 다르면 영원히 0건이다');
    });
    test('S1A-4D NO_SHOW 만 있으면 실근무 분기가 서지 않는다', () {
      expect(actualWorkBranch(['NO_SHOW']), isFalse);
    });
    test('S1A-4E absent 만 있으면 실근무 분기가 서지 않는다', () {
      expect(actualWorkBranch(['absent']), isFalse);
    });
    // A 분기는 `if (!worked.empty) return true;` 에서 끝난다.
    //   주석은 _codeOf 가 걷어내므로 경계 마커는 코드여야 한다.
    String aBranchOf() {
      final body = _after(code, 'srvHasCurrentTaxIdentityPurpose', 1600);
      final end = body.indexOf('if (!worked.empty) return true;');
      expect(end, greaterThan(-1), reason: 'A 분기 끝을 찾지 못했다');
      return body.substring(0, end);
    }

    test('S1A-4F wageStatus 와 무관하다', () {
      // 쿼리에 wageStatus 조건이 없다 — pending 이어도 목적은 선다.
      expect(aBranchOf().contains('wageStatus'), isFalse);
      expect(actualWorkBranch(['early_leave']), isTrue);
    });
    test('S1A-4G 지원서가 CANCELED 여도 실근무 분기는 선다', () {
      // A 분기는 attendance 만 읽는다 — applications 를 보지 않는다.
      final a = aBranchOf();
      expect(a.contains('collection("attendance")'), isTrue);
      expect(a.contains('collection("applications")'), isFalse,
          reason: '과거 근무는 현재 관계 상태가 지우지 못한다');
    });
    test('S1A-4H 실근무도 남은 약속도 없으면 거부한다', () {
      final body = _after(code, 'srvHasCurrentTaxIdentityPurpose', 1600);
      expect(body.contains('return false'), isTrue,
          reason: '두 분기 모두 실패하면 fail closed');
      expect(actualWorkBranch(['NO_SHOW', 'absent']), isFalse);
    });

    test('S1A-4W 세 세무 door 가 모두 이 술어를 쓴다', () {
      final n = RegExp(r'srvHasCurrentTaxIdentityPurpose\(businessId, targetUid\)')
          .allMatches(code).length;
      expect(n, 3, reason: 'Review · Number · ReviewTaxIdentity');
    });

    test('S1A-4X 신분증 원본 문은 이 수정으로 넓어지지 않았다', () {
      // raw-ID door 는 별도 계약(동의 창)이다 — 같은 술어를 쓰지 않는다.
      final f = _after(code, 'export const callableGetTaxIdentityIdCardUrl', 1400);
      expect(f.contains('srvHasActiveIdentityDocumentPurpose('), isTrue);
      expect(f.contains('srvHasCurrentTaxIdentityPurpose('), isFalse);
    });
  });

  group('DOCS1A 감사 fail-closed', () {
    test('S1A-30 지원자 서류 감사 실패는 URL 을 막는다', () {
      final body = _after(code, 'callableGetApplicantDocumentUrl', 3000);
      expect(
        body.contains('.catch((e) => console.error("[applicantDocumentUrl]'),
        isFalse,
        reason: '감사 실패를 삼키면 URL 이 감사 없이 나간다',
      );
      final logIdx = body.indexOf('applicant_document_access_logs');
      final retIdx = body.indexOf('return {');
      expect(logIdx, greaterThan(-1));
      expect(retIdx, greaterThan(logIdx),
          reason: '감사 기록이 반환보다 먼저여야 한다');
      expect(body.contains('throw new HttpsError('), isTrue);
    });

    test('S1A-31 번호 열람은 failClosed 로 감사한다', () {
      final body = _after(code, 'callableGetTaxIdentityNumber', 2400);
      expect(body.contains('{failClosed: true}'), isTrue);
      final logIdx = body.indexOf('srvLogTaxIdentityAudit');
      final retIdx = body.indexOf('return {identifier');
      expect(retIdx, greaterThan(logIdx),
          reason: '감사 성공 이후에만 번호를 반환한다');
    });

    test('S1A-32 helper 는 기본이 삼키기 — 이미 끝난 mutation 을 뒤집지 않는다', () {
      final h = _after(code, 'async function srvLogTaxIdentityAudit', 900);
      expect(h.contains('if (opts?.failClosed)'), isTrue,
          reason: 'failClosed 일 때만 던져야 한다');
      // 기본 경로는 여전히 catch 로 흡수한다.
      expect(h.contains('catch (err)'), isTrue);
    });

    test('S1A-33 Register/Update/Recover 는 failClosed 를 쓰지 않는다', () {
      for (final f in [
        'callableRegisterTaxIdentity',
        'callableUpdateTaxIdentity',
        'callableRecoverForeignTaxIdentity',
      ]) {
        expect(_after(code, f, 2600).contains('{failClosed: true}'), isFalse,
            reason: '$f 는 쓰기 성공 뒤의 기록이다 — 감사 실패로 실패 보고하면 안 된다');
      }
    });

    test('S1A-34 감사 실패 응답에 내부 사정이 실리지 않는다', () {
      final h = _after(code, 'async function srvLogTaxIdentityAudit', 900);
      expect(h.contains('err)'), isTrue, reason: 'console 에는 남긴다');
      expect(h.contains('HttpsError(\n        "internal"'), isTrue);
      expect(h.contains('String(err)'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // viewer / index
  // ═══════════════════════════════════════════════════════════
  group('DOCS1A viewer · index', () {
    test('S1A-40 지원자 서류 viewer 가 disk cache 를 쓰지 않는다', () {
      final d = _codeOf(
          File('lib/widgets/dialogs/worker_detail_dialog.dart').readAsStringSync());
      final i = d.indexOf('_viewApplicantDocument');
      expect(i, greaterThan(-1));
      final body = d.substring(i, i + 900);
      expect(body.contains('showFullScreenViewer'), isTrue);
      expect(body.contains('noCache: true'), isTrue,
          reason: '신분증·통장사본 원본이 관리자 기기 disk 에 남으면 안 된다');
    });

    test('S1A-41 attendance 목적 쿼리 인덱스가 있다', () {
      final idx = File('firestore.indexes.json').readAsStringSync();
      final hit = RegExp(
        r'"collectionGroup":\s*"attendance"[\s\S]{0,400}?'
        r'"businessId"[\s\S]{0,200}?"userId"[\s\S]{0,200}?"status"',
      ).hasMatch(idx);
      expect(hit, isTrue,
          reason: 'businessId+userId+status 복합 인덱스가 필요하다');
    });
  });
}
