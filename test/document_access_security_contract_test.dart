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
DateTime? windowBase({
  String? consentVersion,
  DateTime? confirmedAt,
  String? type,
  DateTime? actualResignDate,
  DateTime? workEndDate,
  DateTime? workDate,
  List<String>? workDays,
}) {
  final anchoredToLastWorkDay =
      consentVersion == _v2 || consentVersion == _v3;
  if (!anchoredToLastWorkDay) return confirmedAt;
  return idWindowLastWorkDay(
    type: type,
    actualResignDate: actualResignDate,
    workEndDate: workEndDate,
    workDate: workDate,
    workDays: workDays,
  );
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

    test('S1A-16 버전 없는 legacy 도 확정일 기준', () {
      final b = windowBase(
        confirmedAt: _kst(2026, 8, 25),
        type: 'long_term',
        workEndDate: _kst(2026, 10, 31),
      );
      expect(b, _kst(2026, 8, 25));
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
      final body = _after(code, 'srvHasCurrentTaxIdentityPurpose', 1600);
      expect(body.contains('"present", "late", "earlyLeave"'), isTrue);
      expect(body.contains('NO_SHOW'), isFalse,
          reason: 'NO_SHOW·absent 는 실근무가 아니다');
      expect(body.contains('wageStatus'), isFalse,
          reason: '급여 확정을 기다리면 지급 전에 불일치를 잡을 수 없다');
    });

    test('S1A-24 신분증 목적에 correction 축이 없다 — 창을 연장하지 않는다', () {
      final body = _after(code, 'srvHasActiveIdentityDocumentPurpose', 1800);
      expect(body.contains('DOC_CORRECTION_COL'), isFalse);
      expect(body.contains('CORRECTION_LIVE'), isFalse);
      expect(body.contains('RESUBMITTED'), isFalse);
    });

    test('S1A-27 [DOC-S1A.1] 창 기준점이 동의 버전에 묶여 있다', () {
      final body = _after(code, 'function srvIdWindowOpen', 1200);
      expect(body.contains('documentAccessConsentVersion'), isTrue,
          reason: '사용자가 본 문구의 범위를 적용해야 한다');
      expect(body.contains('DOCUMENT_ACCESS_CONSENT_V2'), isTrue);
      expect(body.contains('DOCUMENT_ACCESS_CONSENT_V3'), isTrue);
      expect(body.contains('confirmedAt'), isTrue,
          reason: 'v1·legacy 는 확정일 기준이다');
      expect(body.contains('srvIdWindowLastWorkDay'), isTrue);
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
