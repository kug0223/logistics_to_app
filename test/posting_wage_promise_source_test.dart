// [POSTING-V2-03I.1] 임금 source — 모집 임금과 약속 임금의 분리
//
// 03I READ에서 확인된 것:
//   · 지원 시 서버가 슬롯에서 임금을 해석해 application.wage로 복사한다
//     ([SERVER-WAGE-FIX] 클라이언트 값 폴백 차단).
//   · 체크인은 application.wage를 attendance.snapshotWage로 복사하고,
//     급여 계산은 그 스냅샷을 클라이언트 값보다 우선한다.
//   · 즉 지급액은 이미 cohort별로 보호돼 있었다.
//   · 그런데 **계약서만** 진입점에 따라 현재 슬롯 임금(TOItem.workDetails)이나
//     갱신되지 않는 마스터 TO 템플릿(to.workDetails)을 썼다.
//     그래서 계약서 금액과 실제 지급액이 어긋날 수 있었다.
//
// 확정된 정책:
//   현재 모집 임금 = slot.workDetails[].wage  (이후 지원자에게 적용)
//   개인 약속 임금 = application.wage/wageType (immutable snapshot)
//   CURRENT POSTING WAGE != EXISTING WORKER PROMISED WAGE 는 정상이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _contractSvc = 'lib/services/contract_service.dart';
const _editPath = 'lib/screens/business_admin/to_management/edit_to_screen.dart';
const _dayApplicants =
    'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';
const _fnsPath = 'functions/src/index.ts';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) throw StateError('$signature 를 찾지 못함');
  var paren = 0;
  var afterParams = start;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    if (source[i] == '(') paren++;
    if (source[i] == ')') {
      paren--;
      if (paren == 0) {
        afterParams = i;
        break;
      }
    }
  }
  final open = source.indexOf('{', afterParams);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('$signature 본문의 끝을 찾지 못함');
}

// ── cohort replica ──────────────────────────────────────────────
// 서버·클라이언트 전 구간의 임금 흐름을 그대로 모델링한다.

class Application {
  final String id;
  final int wage; // 지원 시점 스냅샷 (0 = 레거시 결측)
  final String? wageType;
  String status;
  Application(this.id, this.wage, {this.wageType = 'daily', this.status = 'PENDING'});
}

class Slot {
  int wage; // 현재 모집 임금
  String wageType;
  Slot(this.wage, {this.wageType = 'daily'});
}

/// callableApplyToTO — 서버가 슬롯에서 해석해 복사한다.
Application apply(String id, Slot slot) =>
    Application(id, slot.wage, wageType: slot.wageType);

/// callableUpdateSlotWorkDetails — 슬롯만 바꾼다. 기존 지원서는 건드리지 않는다.
void editSlotWage(Slot slot, List<Application> existing, int newWage) {
  slot.wage = newWage;
  // 기존 application.wage를 덮어쓰지 않는다 (§12)
  for (final _ in existing) {}
}

/// ContractService._withPromisedWage — 계약 임금은 약속 임금이다.
int contractWage(Application app, Slot currentSlot) {
  if (app.wage <= 0) throw StateError('약속 임금 없음');
  return app.wage; // currentSlot은 참조하지 않는다
}

/// callableCheckIn — attendance.snapshotWage ← application.wage
int attendanceSnapshotWage(Application app) => app.wage;

/// callableCalculateAndConfirmWage — snapshotWage 우선
int payrollBaseWage(Application app, {int? clientBaseWage}) {
  final snap = attendanceSnapshotWage(app);
  return snap > 0 ? snap : (clientBaseWage ?? 0);
}

void main() {
  // ── §1, §12 스냅샷 불변 ────────────────────────────────────────
  group('WAGE-01 모집 임금 변경이 기존 약속을 바꾸지 않는다', () {
    test('01-a 서버가 지원 시점 임금을 복사한다 (전제)', () {
      final fns = _src(_fnsPath);
      expect(fns.contains('const effectiveWage = serverWage;'), true);
      expect(
          fns.contains('"해당 업무 유형의 임금 정보를 서버에서 찾을 수 없습니다."'), true,
          reason: '클라이언트 wage 폴백 차단 — 스냅샷이 서버 권위다');
      expect(fns.contains('wage: effectiveWage, wageType: effectiveWageType,'), true);
    });

    test('01-b 슬롯 임금 수정이 application을 덮어쓰지 않는다 (§12)', () {
      final slot = Slot(100000);
      final a = apply('A', slot);
      editSlotWage(slot, [a], 110000);
      expect(a.wage, 100000);
      expect(slot.wage, 110000);
    });

    test('01-c 슬롯 임금 수정 경로에 application write가 없다 (§12)', () {
      final fns = _src(_fnsPath);
      final start = fns.indexOf('export const callableUpdateSlotWorkDetails = onCall(');
      expect(start, greaterThan(-1));
      final end = fns.indexOf('export const ', start + 40);
      final body = fns.substring(start, end > start ? end : fns.length);
      expect(body.contains('collection("applications").doc('), false,
          reason: '임금 변경이 기존 지원서를 재작성하면 안 된다');
      expect(body.contains('wage:'), false);
    });

    test('01-d 서버 hard block을 추가하지 않았다 (§1)', () {
      final fns = _src(_fnsPath);
      expect(fns.contains('확정된 근무자가 있어 임금을 변경할 수 없습니다'), false);
      expect(fns.contains('확정자가 있는 슬롯의 임금'), false);
    });
  });

  // ── §2, §5, §15 계약 임금 ──────────────────────────────────────
  group('WAGE-02 계약 임금 = 약속 임금', () {
    test('02-a overlay가 application.wage를 쓴다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_contractSvc), 'WorkDetailData _withPromisedWage(')));
      expect(body.contains('final promisedWage = application.wage;'), true);
      expect(body.contains('wage: promisedWage,'), true);
      expect(body.contains('wageType: promisedType ?? workDetail.wageType,'), true);
    });

    // [POSTING-V2-03I.3 재작성] 03I.1에서는 금액 두 필드만 덮었다. 03I.2가
    // 그것만으로는 계약서가 mixed-version으로 남는다는 것을 확인해(휴게·야간·
    // 연장 단가는 현재 값이었다), 약속 범위를 급여 산정 조건 전체로 넓혔다.
    // 지키는 선은 그대로다 — 업무 정체성과 지급일 설정은 건드리지 않는다.
    test('02-b 임금 조건만 바꾸고 업무 정체성은 두지 않는다 (§5)', () {
      final body = _codeOf(
          _bodyOf(_src(_contractSvc), 'WorkDetailData _withPromisedWage('));
      expect(body.contains('workDetail.copyWith('), true);
      for (final other in [
        'workType:',
        'requiredCount:',
        'payScheduleType:',
        'payScheduleDay:',
      ]) {
        expect(body.contains(other), false, reason: '$other 까지 건드리면 안 된다');
      }
    });

    test('02-c 두 진입점 모두 overlay를 거친다 (§15)', () {
      final code = _codeOf(_src(_contractSvc));
      for (final sig in [
        'Future<EmploymentContractModel> findOrCreateContract(',
        'Future<EmploymentContractModel> buildPreviewContract(',
      ]) {
        final body = _codeOf(_bodyOf(_src(_contractSvc), sig));
        expect(body.contains('_withPromisedWage(application, workDetail)'), true,
            reason: sig);
      }
      // 내부 생성 경로는 이 둘 뿐 — caller마다 고치지 않는다
      expect('_withPromisedWage('.allMatches(code).length, 3,
          reason: '정의 1 + 진입점 2');
    });

    test('02-d 계약 임금이 현재 슬롯 임금을 참조하지 않는다', () {
      final slot = Slot(100000);
      final a = apply('A', slot);
      a.status = 'CONFIRMED';
      editSlotWage(slot, [a], 110000);
      expect(contractWage(a, slot), 100000);
      final b = apply('B', slot);
      expect(contractWage(b, slot), 110000);
    });

    test('02-e 13개 호출부가 모두 같은 두 진입점을 쓴다 (§3, §15)', () {
      var sites = 0;
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.replaceAll(r'\', '/').endsWith(_contractSvc)) continue;
        final s = f.readAsStringSync();
        sites += 'findOrCreateContract('.allMatches(s).length;
        sites += 'buildPreviewContract('.allMatches(s).length;
      }
      expect(sites, 13,
          reason: '호출부 수가 바뀌면 이 테스트를 다시 본다 — overlay는 진입점에 있으므로 안전하다');
    });
  });

  // ── §4 day_applicants 마스터 TO 제거 ──────────────────────────
  group('WAGE-03 마스터 TO 템플릿을 임금 source로 쓰지 않는다', () {
    test('03-a day_applicants가 to.workDetails 임금을 계약에 넘기지 않는다 (§4)', () {
      // workDetail은 여전히 업무명·시간 조회에 쓰이지만, 임금은 overlay가 덮는다.
      final code = _codeOf(_src(_dayApplicants));
      expect(code.contains('to.workDetails'), true,
          reason: '업무 식별용 조회 자체는 남는다');
      // 그 값이 계약 임금이 되지 않는다는 것은 service 진입점이 보장한다
      final svc = _codeOf(_src(_contractSvc));
      expect(svc.contains('workDetail = _withPromisedWage(application, workDetail);'),
          true);
    });

    test('03-b 계약 임금 필드가 overlay 이후 workDetail에서 온다', () {
      final code = _codeOf(_src(_contractSvc));
      // _addSlot / _createNew 는 그대로 workDetail.wage를 읽는다 —
      // 그 workDetail이 이미 약속 임금으로 덮인 상태다.
      expect(code.contains('wage: workDetail.wage,'), true);
      expect(code.contains('wageType: workDetail.wageType,'), true);
      expect(code.contains('wage: application.wage'), false,
          reason: '하위 함수를 고치지 않는다 — 진입점 overlay 하나로 충분하다');
    });
  });

  // ── §6 legacy ─────────────────────────────────────────────────
  group('WAGE-04 약속 임금이 없으면 조용히 대체하지 않는다', () {
    test('04-a 레거시 결측은 명시적 실패다 (§6)', () {
      final slot = Slot(110000);
      final legacy = Application('L', 0); // wage 없음 → fromMap ?? 0
      expect(() => contractWage(legacy, slot), throwsA(isA<StateError>()));
    });

    test('04-b 현재 모집 임금으로 폴백하지 않는다', () {
      final body = _codeOf(
          _bodyOf(_src(_contractSvc), 'WorkDetailData _withPromisedWage('));
      final throwIdx = body.indexOf('throw StateError(');
      final returnIdx = body.indexOf('return workDetail.copyWith(');
      expect(throwIdx, greaterThan(-1));
      expect(returnIdx, greaterThan(throwIdx),
          reason: '결측 검사가 폴백보다 앞이어야 한다');
      // 금액은 폴백이 없다. (wageType만 `promisedType ?? workDetail.wageType`)
      expect(body.contains('wage: promisedWage,'), true);
      expect(body.contains('?? workDetail.wage,'), false,
          reason: '현재 모집 임금으로 과거 약속 금액을 재작성하지 않는다');
      expect(body.contains('promisedWage ??'), false);
    });

    test('04-c 결측 판정 기준이 모델과 맞는다', () {
      final model = _codeOf(_src('lib/models/core/application_model.dart'));
      expect(model.contains("wage: (data['wage'] as num?)?.toInt() ?? 0,"), true,
          reason: 'null이 아니라 0으로 파싱되므로 <= 0 으로 본다');
      final body = _codeOf(
          _bodyOf(_src(_contractSvc), 'WorkDetailData _withPromisedWage('));
      expect(body.contains('if (promisedWage <= 0) {'), true);
    });
  });

  // ── §13, §14 A/B cohort ───────────────────────────────────────
  group('WAGE-05 A/B cohort 분리', () {
    test('05-a 확정 후 모집 임금을 올려도 A의 전 구간이 유지된다 (§13)', () {
      final slot = Slot(100000);
      final a = apply('A', slot);
      a.status = 'CONFIRMED';
      editSlotWage(slot, [a], 110000);

      expect(slot.wage, 110000, reason: 'Posting 현재 모집 임금');
      expect(a.wage, 100000, reason: 'Workforce 약속 임금');
      expect(contractWage(a, slot), 100000, reason: '계약');
      expect(attendanceSnapshotWage(a), 100000, reason: '근태');
      expect(payrollBaseWage(a, clientBaseWage: 110000), 100000,
          reason: '급여 — 클라이언트 값보다 스냅샷 우선');
    });

    test('05-b 이후 지원한 B는 새 임금을 받는다 (§13)', () {
      final slot = Slot(100000);
      final a = apply('A', slot);
      editSlotWage(slot, [a], 110000);
      final b = apply('B', slot);

      expect(b.wage, 110000);
      expect(contractWage(b, slot), 110000);
      expect(attendanceSnapshotWage(b), 110000);
      expect(payrollBaseWage(b), 110000);
      expect(a.wage, 100000, reason: 'B가 새 임금을 받아도 A는 그대로다');
    });

    test('05-c A와 B가 같은 슬롯에서 다른 약속을 갖는다', () {
      final slot = Slot(100000);
      final a = apply('A', slot);
      editSlotWage(slot, [a], 110000);
      final b = apply('B', slot);
      expect(a.wage == b.wage, false,
          reason: 'cohort 분리는 오류가 아니라 정상이다');
      expect(a.wage, 100000);
      expect(b.wage, 110000);
    });

    test('05-d PENDING / INVITED도 스냅샷이 유지된다 (§14)', () {
      for (final st in ['PENDING', 'INVITED', 'CONTRACT_PENDING']) {
        final slot = Slot(100000);
        final a = apply('A', slot)..status = st;
        editSlotWage(slot, [a], 110000);
        expect(a.wage, 100000, reason: st);
        // 나중에 확정돼도 그 스냅샷을 따른다
        a.status = 'CONFIRMED';
        expect(contractWage(a, slot), 100000, reason: '$st → CONFIRMED');
        expect(payrollBaseWage(a), 100000, reason: '$st → CONFIRMED');
      }
    });
  });

  // ── §10, §11 WAGE-GUARD ───────────────────────────────────────
  group('WAGE-06 경고 문구가 실제 동작과 일치한다', () {
    test('06-a 네 상태 모두를 cohort로 본다 (§11)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_editPath), 'Future<bool> _showWageGuardWarning(')));
      expect(
          body.contains('const cohortStatuses = [ AppStatus.pending, '
              'AppStatus.invited, AppStatus.contractPending, AppStatus.confirmed, ];'),
          true,
          reason: 'PENDING·INVITED에도 이미 스냅샷이 있다');
      expect(body.contains('if (!hasCohort) return true;'), true);
    });

    test('06-b 새 query를 만들지 않았다 (§11, §16)', () {
      final body = _codeOf(
          _bodyOf(_src(_editPath), 'Future<bool> _showWageGuardWarning('));
      expect(body.contains('_applicationRelations.fresh()'), true,
          reason: '03G.1 freshness 계약 유지 (§18)');
      expect(body.contains('httpsCallable'), false);
      expect(body.contains('FirebaseFirestore'), false);
      final code = _codeOf(_src(_editPath));
      expect("httpsCallable('callableGetApplicationsByBiz'".allMatches(code).length,
          1);
    });

    test('06-c 틀린 문구가 제거됐다 (§10)', () {
      final code = _codeOf(_src(_editPath));
      expect(code.contains('미확정 급여 계산에 영향을 줄 수 있습니다'), false,
          reason: '기존 지원자의 급여는 스냅샷으로 유지된다 — 사실과 달랐다');
    });

    // [POSTING-V2-03I.3 재작성] 03I.1 문구는 금액만 말했다. 약속 범위가
    // 급여 산정 조건 전체로 확정되면서 문구도 그에 맞게 넓어졌다.
    test('06-d 실제 의미를 말한다 (§10)', () {
      final body = _codeOf(
          _bodyOf(_src(_editPath), 'Future<bool> _showWageGuardWarning('));
      expect(
          body.contains('임금이나 급여 산정 조건을 변경해도 기존 지원자의 지원 당시 조건은 유지됩니다. '),
          true);
      expect(body.contains('변경된 조건은 이후 새로 지원하는 사람부터 적용됩니다.'), true);
      expect(body.contains('이미 확정된 근무자의 약속된 임금과 지급 기준도 변경되지 않습니다.'), true);
      // 금액만 말하던 옛 문구는 남아 있지 않다
      expect(body.contains('임금을 변경하면 기존 지원자의 지원 당시 임금은 유지되고'), false);
    });

    test('06-e 확정자 유무로 안내가 갈린다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_editPath), 'Future<bool> _showWageGuardWarning(')));
      expect(
          body.contains("subtitle: hasConfirmed ? '이 공고에 확정된 근무자가 있습니다' "
              ": '이 공고에 기존 지원자가 있습니다',"),
          true);
      expect(body.contains('hasConfirmed ?'), true);
    });

    test('06-f FAIL CLOSE 유지 (§18)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_editPath), 'Future<bool> _showWageGuardWarning(')));
      expect(body.contains('if (appsRaw == null) {'), true);
      expect(
          body.contains("ToastHelper.showError('지원자 상태를 확인하지 못했습니다. "
              "잠시 후 다시 시도해주세요.'); return false;"),
          true);
    });
  });

  // ── §8, §19 범위 ──────────────────────────────────────────────
  group('WAGE-07 범위를 넘지 않았다', () {
    test('07-a Posting 표시는 현재 모집 임금을 유지한다 (§8)', () {
      final svc = _codeOf(_src('lib/services/firestore_service.dart'));
      expect(
          svc.contains('(slotWorkDetails != null && slotWorkDetails.isNotEmpty)'),
          true,
          reason: '공고/날짜 카드는 계속 슬롯 현재값을 본다');
      // 초대 다이얼로그는 모집 조건 표시이므로 그대로다
      final invite = _codeOf(
          _src('lib/screens/business_admin/dialogs/invite_worker_dialog.dart'));
      expect(invite.contains('FormatHelper.formatWage(wd.wage)'), true);
    });

    test('07-b worker-specific 화면은 이미 스냅샷을 쓴다 (§7)', () {
      for (final p in [
        'lib/widgets/dialogs/long_term_work_management_dialog.dart',
        'lib/widgets/dialogs/schedule_detail_dialog.dart',
      ]) {
        final code = _codeOf(_src(p));
        expect(code.contains('app.wage'), true, reason: '$p — 수정 불필요했다');
      }
    });

    test('07-c Functions 무수정 (§19)', () {
      final fns = _src(_fnsPath);
      for (final marker in [
        'const effectiveWage = serverWage;',
        'snapshotWage: typeof appData.wage === "number" ? appData.wage : undefined,',
        'const effectiveBaseWage = (snapshotWage != null && snapshotWage > 0) '
            '? snapshotWage : d.baseWage;',
      ]) {
        expect(fns.contains(marker), true, reason: '$marker 가 사라졌다');
      }
    });

    test('07-d 임금 변경 workflow를 신설하지 않았다 (§20)', () {
      final svc = _codeOf(_src(_contractSvc));
      expect(svc.contains('updateApplicationWage'), false);
      expect(svc.contains('requestWageChange'), false);
      final edit = _codeOf(_src(_editPath));
      expect(edit.contains("'wage':"), false,
          reason: '기존 application의 임금을 쓰는 코드가 없다');
    });
  });
}
