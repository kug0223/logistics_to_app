// [R7-P4.4C.2] READY 는 영구 flag 가 아니다 — prerequisite 가 사라지면 다시
// NOT_READY 이고, **빠진 항목만** 복구 대상이다.
//
// ── 확정 정책(재논의 아님) ─────────────────────────────────────────
//   지원 = 관심 / 확정 = 약속.
//   확정 이후에 관리자에게 계약 준비를 다시 요구하고 근로자를 계약 대기로
//   세워 두지 않는다.
//
// ── 이번에 찾은 것 ─────────────────────────────────────────────────
//   공고를 **만들 때만** readiness 를 봤다. 만든 뒤 계약서 템플릿이나 사업주
//   날인이 지워지면 공고는 그대로 모집을 계속하고, 지원자는 확정까지 받은
//   다음 계약 단계에서 막혔다 — 정책이 금지한 바로 그 상태다.
//
// ── 무엇을 하지 않았는가 ────────────────────────────────────────────
//   공고를 자동으로 내리지 않는다. 기존 확정·계약·근태·급여도 손대지 않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/services/business_posting_readiness.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), isTrue, reason: '$p 를 찾지 못함');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

String _fns() => File('functions/src/index.ts').readAsStringSync();

/// 다섯 축을 모두 갖춘 사업장.
BusinessPostingReadiness _ready({
  bool approved = true,
  bool license = true,
  bool workTypes = true,
  bool seal = true,
}) =>
    BusinessPostingReadiness(
      bizId: 'b1',
      isApproved: approved,
      hasCanonicalLicense: license,
      hasOwnerLegacyLicense: false,
      hasActiveWorkTypes: workTypes,
      hasEmployerSeal: seal,
    );

/// Home 체크리스트 4칸을 사업장 readiness + 템플릿으로 조립한다.
/// (`_loadPostingReadiness` 와 같은 조립 규칙)
FirstPostingReadiness _checklist(
  BusinessPostingReadiness r, {
  required bool template,
}) {
  final map = {r.bizId: r};
  return FirstPostingReadiness(
    hasAnyBusiness: true,
    businessReady: map.values.any((x) => x.isApproved && x.hasLicense),
    workTypesReady: BusinessPostingReadiness.hasReadyBusiness(map),
    contractTemplateReady: template,
    sealReady: map.values.any((x) => x.hasEmployerSeal),
  );
}

void main() {
  // ══════════════════════════════════════════════════════════════
  // REG. READY → 하나 상실 → NOT_READY (그리고 빠진 항목만)
  // ══════════════════════════════════════════════════════════════
  group('REG readiness 회귀', () {
    test('REG-01 다섯 축 모두 있으면 READY', () {
      final r = _checklist(_ready(), template: true);
      expect(r.allReady, isTrue);
      expect(r.completedCount, FirstPostingReadiness.totalTasks);
    });

    test('REG-02 마지막 활성 업무 상실 → 업무 칸만 미완료', () {
      final r = _checklist(_ready(workTypes: false), template: true);
      expect(r.allReady, isFalse);
      expect(r.isDone(FirstPostingTask.workType), isFalse);
      // 나머지는 완료로 남는다 — 처음부터 다시 하라고 하지 않는다.
      expect(r.isDone(FirstPostingTask.business), isTrue);
      expect(r.isDone(FirstPostingTask.contractTemplate), isTrue);
      expect(r.isDone(FirstPostingTask.seal), isTrue);
      expect(r.completedCount, FirstPostingReadiness.totalTasks - 1);
    });

    test('REG-03 마지막 사용 가능 템플릿 상실 → 템플릿 칸만 미완료', () {
      final r = _checklist(_ready(), template: false);
      expect(r.allReady, isFalse);
      expect(r.isDone(FirstPostingTask.contractTemplate), isFalse);
      expect(r.isDone(FirstPostingTask.business), isTrue);
      expect(r.isDone(FirstPostingTask.workType), isTrue);
      expect(r.isDone(FirstPostingTask.seal), isTrue);
    });

    test('REG-04 사업주 날인 상실 → 인감 칸만 미완료', () {
      final r = _checklist(_ready(seal: false), template: true);
      expect(r.allReady, isFalse);
      expect(r.isDone(FirstPostingTask.seal), isFalse);
      expect(r.isDone(FirstPostingTask.business), isTrue);
      expect(r.isDone(FirstPostingTask.workType), isTrue);
      expect(r.isDone(FirstPostingTask.contractTemplate), isTrue);
    });

    test('REG-05 승인 해제 → 사업장 칸 + 업무 칸(identity 보존 결과)', () {
      // `workTypesReady` 는 "같은 사업장에서 승인·등록증·업무가 모두" 이므로
      // 승인이 빠지면 함께 false 가 된다. 이것은 잘못된 귀인이 아니라
      // **공고를 낼 수 있는 사업장이 없다**는 사실이고, P4.4 에서 그 줄에
      // `사업장 승인 후 반영돼요` 라는 이유를 붙여 뒀다.
      final r = _checklist(_ready(approved: false), template: true);
      expect(r.allReady, isFalse);
      expect(r.isDone(FirstPostingTask.business), isFalse);
      expect(r.isDone(FirstPostingTask.workType), isFalse);
      // 승인과 무관한 두 칸은 완료로 남는다.
      expect(r.isDone(FirstPostingTask.contractTemplate), isTrue);
      expect(r.isDone(FirstPostingTask.seal), isTrue);
    });

    test('REG-06 등록증 상실 → 사업장 칸', () {
      final r = _checklist(_ready(license: false), template: true);
      expect(r.allReady, isFalse);
      expect(r.isDone(FirstPostingTask.business), isFalse);
      expect(r.isDone(FirstPostingTask.seal), isTrue);
    });

    test('REG-07 빠진 항목만 복구하면 다시 READY', () {
      for (final broken in [
        _checklist(_ready(workTypes: false), template: true),
        _checklist(_ready(), template: false),
        _checklist(_ready(seal: false), template: true),
        _checklist(_ready(approved: false), template: true),
        _checklist(_ready(license: false), template: true),
      ]) {
        expect(broken.allReady, isFalse);
      }
      expect(_checklist(_ready(), template: true).allReady, isTrue);
    });

    test('REG-08 못 읽은 것을 "없다" 로 단정하지 않는다', () {
      // 읽기 실패는 미완료와 다른 사실이다 — 안내 문장을 만들지 않는다.
      const unknownWt = BusinessPostingReadiness(
        bizId: 'b1',
        isApproved: true,
        hasCanonicalLicense: true,
        hasOwnerLegacyLicense: false,
        hasActiveWorkTypes: false,
        workTypesUnknown: true,
        hasEmployerSeal: true,
      );
      expect(unknownWt.isMissingWorkTypes, isFalse);
      const unknownSeal = BusinessPostingReadiness(
        bizId: 'b1',
        isApproved: true,
        hasCanonicalLicense: true,
        hasOwnerLegacyLicense: false,
        hasActiveWorkTypes: true,
        employerSealUnknown: true,
      );
      expect(unknownSeal.isMissingEmployerSeal, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // WRITER. 각 축을 실제로 없앨 수 있는 자
  // ══════════════════════════════════════════════════════════════
  group('WRITER 상실 경로', () {
    test('WRITER-01 승인 해제는 관리 callable 의 deactivate 하나다', () {
      final s = _fns();
      expect(s.contains('isApproved: false,'), isTrue);
      final i = s.indexOf('isApproved: false,');
      final head = s.substring((i - 300).clamp(0, i), i);
      expect(head.contains('action === "deactivate"'), isTrue);
      // 비활성 표시가 같이 남고, 공고 생성은 그것만으로도 막힌다.
      final tail = s.substring(i, i + 260);
      expect(tail.contains('deactivatedAt'), isTrue);
    });

    test('WRITER-02 업무는 soft delete 다 — 기존 snapshot 을 지우지 않는다', () {
      final s = _src('lib/services/firestore/business_firestore.dart');
      final i = s.indexOf('Future<bool> deleteBusinessWorkType(');
      expect(i, greaterThan(-1));
      final body = s.substring(i, i + 1800);
      expect(body.contains(".update({'isActive': false})"), isTrue);
      expect(body.contains('.delete()'), isFalse,
          reason: '문서를 지우면 과거 공고·지원의 업무 참조가 끊긴다');
    });

    test('WRITER-03 등록증 Storage 객체를 지우는 writer 가 없다', () {
      // client: rules 로 전면 차단.
      final rules = _src('storage.rules');
      final i = rules.indexOf('match /businesses/{businessId}/license/{allPaths=**}');
      expect(i, greaterThan(-1));
      final block = rules.substring(i, i + 400);
      expect(block.contains('allow delete: if false;'), isTrue);
      expect(block.contains('allow read: if false;'), isTrue);
      // server: 사업장 삭제 정리 대상에 license 가 없다.
      final s = _fns();
      final di = s.indexOf('const bizImageUrls: string[] = [];');
      expect(di, greaterThan(-1));
      final dblock = s.substring(di, di + 700);
      expect(dblock.contains('businessLicense'), isFalse,
          reason: '정리 대상에 들어가면 그때부터 삭제 writer 가 생긴다');
    });

    test('WRITER-04 날인 삭제는 서버 callable 을 지난다', () {
      final s = _fns();
      expect(s.contains('export const callableSaveSeal'), isTrue);
      // 클라이언트가 users 문서의 sealBase64 를 직접 쓰지 않는다.
      final rules = _src('firestore.rules');
      expect(rules.contains('sealBase64'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // ACTIVE. 이미 공개된 공고 — 정책 Model B
  // ══════════════════════════════════════════════════════════════
  group('ACTIVE 공고 정책', () {
    late final String s;
    setUpAll(() => s = _fns());

    test('ACTIVE-01 새 관심(지원)을 받는 지점에서 막는다', () {
      expect(s.contains('async function assertBusinessCanAcceptApplications('),
          isTrue);
      final i = s.indexOf('export const callableApplyToTO');
      final end = s.indexOf('export const', i + 10);
      final body = s.substring(i, end);
      expect(body.contains('await assertBusinessCanAcceptApplications('), isTrue);
    });

    test('ACTIVE-02 TO 상태 검사를 통과한 뒤에 본다', () {
      // 어차피 거부될 지원에 조회를 쓰지 않는다.
      final i = s.indexOf('export const callableApplyToTO');
      final end = s.indexOf('export const', i + 10);
      final body = s.substring(i, end);
      final notPublished = body.indexOf('아직 공개되지 않은 공고입니다');
      final gate = body.indexOf('assertBusinessCanAcceptApplications(');
      expect(notPublished, greaterThan(-1));
      expect(gate, greaterThan(notPublished));
    });

    test('ACTIVE-03 계약 dead-end 를 만드는 두 축을 본다', () {
      final i = s.indexOf('async function assertBusinessCanAcceptApplications(');
      final end = s.indexOf('/** [P4.4C.1] `db` 와 `transaction`', i);
      expect(end, greaterThan(i));
      final body = s.substring(i, end);
      expect(body.contains('contract_templates'), isTrue);
      expect(body.contains('sealBase64'), isTrue);
      expect(body.contains('deactivatedAt'), isTrue);
      // 업무 축은 보지 않는다 — 공고가 자기 workDetails 를 이미 들고 있으므로
      // 지금 지원을 막을 이유가 아니다.
      expect(body.contains('collection("workTypes")'), isFalse);
      // 등록증도 보지 않는다 — Storage 객체를 지우는 writer 가 제품에 없고
      // (WRITER-03), 지원 경로마다 Storage 를 부르지 않는다.
      expect(body.contains('hasValidBusinessLicense'), isFalse);
    });

    test('ACTIVE-04 근로자에게 고용주 설정 내부를 알리지 않는다', () {
      final i = s.indexOf('async function assertBusinessCanAcceptApplications(');
      final body = s.substring(i, i + 2200);
      expect(body.contains('지금은 지원을 받지 않는 공고예요'), isTrue);
      for (final leak in const ['계약서 템플릿을', '인감', '사업주 날인을 먼저']) {
        expect(body.contains('"$leak'), isFalse, reason: leak);
      }
    });

    test('ACTIVE-05 공고를 자동으로 내리지 않는다', () {
      // 자동 unpublish 는 복구 후 "누가 다시 켜는가" 라는 또 다른 정책을
      // 만든다. 이번 정책은 새 관심만 막는다.
      final i = s.indexOf('async function assertBusinessCanAcceptApplications(');
      final body = s.substring(i, i + 2200);
      expect(body.contains('isPublished'), isFalse);
      expect(body.contains('status:'), isFalse);
      expect(body.contains('isManualClosed'), isFalse);
    });

    test('ACTIVE-06 기존 확정·계약·근태·급여를 건드리지 않는다', () {
      final i = s.indexOf('async function assertBusinessCanAcceptApplications(');
      final body = s.substring(i, i + 2200);
      for (final banned in const [
        'applications',
        'employment_contracts',
        'attendances',
        'confirmedCount',
        'totalConfirmed',
      ]) {
        expect(body.contains(banned), isFalse, reason: banned);
      }
      // 읽기만 한다 — write 가 없다.
      expect(body.contains('.update('), isFalse);
      expect(body.contains('.set('), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // LICENSE. Storage provenance
  // ══════════════════════════════════════════════════════════════
  group('LICENSE provenance', () {
    test('LICENSE-01 canonical 경로 prefix 를 강제한다', () {
      final s = _fns();
      expect(
          s.contains('if (!storagePath.startsWith(`businesses/'
              '\${businessId}/license/`)) return null;'),
          isTrue,
          reason: '다른 사업장·임의 경로 객체를 등록증으로 인정하면 안 된다');
    });

    test('LICENSE-02 owner 레거시도 서버가 쓴 경로를 우선한다', () {
      final s = _fns();
      expect(s.contains('businessLicenseImagePath'), isTrue);
      expect(s.contains('callableRegisterBusinessLicense'), isTrue);
    });

    test('LICENSE-03 필드는 하나뿐이다 — version/uploadedAt 축이 없다', () {
      // 없는 개념을 있다고 보고하지 않기 위해 고정한다.
      final b = _src('lib/models/core/business_model.dart');
      expect(b.contains('final String? businessLicenseImageUrl;'), isTrue);
      for (final absent in const [
        'businessLicensePath',
        'licenseVersion',
        'licenseValidatedAt',
      ]) {
        expect(b.contains(absent), isFalse, reason: absent);
      }
    });

    test('LICENSE-04 승인과 등록증 readiness 를 합치지 않는다', () {
      // 등록증이 사라졌다고 isApproved 를 false 로 만들지 않는다.
      final s = _fns();
      expect(s.contains('type BusinessLicenseCheck = "VALID" | "MISSING" | '
          '"CHECK_FAILED";'), isTrue);
      // MISSING 처리 지점에서 승인 필드를 건드리지 않는다.
      final i = s.indexOf('async function checkBusinessLicense(');
      final end = s.indexOf('async function hasValidBusinessLicense(', i);
      final body = s.substring(i, end);
      expect(body.contains('isApproved'), isFalse);
    });
  });
}
