import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// R7-PRE1A  PERSON-IDENTITY-CONTRACT
//
//   표시 이름       = presentation only
//   person identity = uid
//   row identity    = applicationId / attendanceId / contractId
//
//   이름·전화·성별·생년월일·계좌번호는 identity 가 아니다.
//
//   이 테스트는 "동명이인이 들어와도 화면이 두 사람을 합치지 않는다"를
//   코드 수준에서 고정한다. DEV 에는 동명 USER 계정이 없고, 제품에
//   이름 변경 경로가 없어(rules 가 users.name 본인 수정을 차단) 그 상태를
//   런타임으로 만들 수 없다 — 만들려면 본인인증을 우회해야 한다.
//   그래서 재현 대신 **key 로 쓰이는 값**을 검사한다.
// ═══════════════════════════════════════════════════════════════

const _dayApplicants =
    'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';
const _workApplicants =
    'lib/screens/business_admin/dialogs/work_applicants_dialog.dart';
const _attendanceDialog =
    'lib/screens/business_admin/dialogs/attendance_status_dialog.dart';
const _payrollDash =
    'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';
const _statsSvc = 'lib/services/admin_stats_service.dart';
const _rules = 'firestore.rules';

String _src(String p) => File(p).readAsStringSync();

String _codeOf(String b) => b
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  group('PID-1x 선택 키는 행 identity 다', () {
    test('PID-10 당일명단 선택은 applicationId', () {
      final s = _flat(_codeOf(_src(_attendanceDialog)));
      expect(s.contains('_selectedIds.addAll(pendingList.map((a) => a.id))'),
          isTrue,
          reason: '이름으로 고르면 동명이인 둘이 함께 선택된다.');
      expect(s.contains('_workerIdMap = {for (final a in confirmedWorkers) a.id: a}'),
          isTrue, reason: '행 조회 맵도 applicationId 키여야 한다.');
    });

    test('PID-11 급여 선택은 attendanceId', () {
      final s = _flat(_codeOf(_src(_payrollDash)));
      expect(s.contains('_allRecords.where((r) => _selectedIds.contains(r.id))'),
          isTrue, reason: '이체 대상은 근태 문서 단위로 고른다.');
    });

    test('PID-12 지원자 선택은 applicationId', () {
      for (final p in [_dayApplicants, _workApplicants]) {
        final s = _flat(_codeOf(_src(p)));
        expect(s.contains('final Set<String> _selectedIds = {}'), isTrue,
            reason: '$p: 선택 집합이 있어야 한다.');
        // 이름 문자열을 담는 선택 집합이 생기면 안 된다.
        expect(s.contains('_selectedNames'), isFalse,
            reason: '$p: 이름 기반 선택 집합이 생겼다.');
      }
    });
  });

  group('PID-2x 그룹/집계 키는 uid 다', () {
    test('PID-20 급여 그룹 키는 userId + 지급일', () {
      final s = _flat(_codeOf(_src(_payrollDash)));
      expect(s.contains(r"map['${r.userId}::$duePart'] ??= []"), isTrue,
          reason: '이름으로 묶으면 동명이인의 급여가 한 줄로 합쳐진다.');
    });

    test('PID-21 급여 인원 수는 userId 집합 크기', () {
      final s = _flat(_codeOf(_src(_payrollDash)));
      expect(s.contains('.map((r) => r.userId).toSet().length'), isTrue,
          reason: '인원 수를 이름 집합으로 세면 동명이인이 1명이 된다.');
    });

    test('PID-22 월 상세 근태 중복 제거는 문서 id', () {
      final s = _flat(_codeOf(_src(_statsSvc)));
      expect(s.contains('attendance.where((a) => seen.add(a.id))'), isTrue);
      expect(s.contains('workerMap.putIfAbsent(a.userId'), isTrue,
          reason: '직원별 집계는 uid 로 묶어야 한다.');
    });
  });

  group('PID-3x 이름은 표시 전용이다', () {
    test('PID-30 이름은 폴백과 함께 읽는다 — 없으면 화면이 멈추지 않는다', () {
      final s = _flat(_codeOf(_src(_workApplicants)));
      expect(
          s.contains("user?.name ?? app.applicantName ?? '이름 없음'"), isTrue,
          reason: '이름은 표시값이다 — 없다고 사람이 사라지면 안 된다.');
    });

    test('PID-31 검색은 필터일 뿐 key 가 아니다', () {
      // 검색은 그룹을 지우기만 하고, 지워지는 단위는 uid 키 그룹이다.
      final s = _flat(_codeOf(_src(_payrollDash)));
      expect(s.contains("final uid = key.split('::').first"), isTrue,
          reason: '검색이 이름으로 그룹을 찾아 들어가면 안 된다 — uid 로 되짚는다.');
    });
  });

  group('PID-4x 이름은 클라이언트가 바꿀 수 없다', () {
    test('PID-40 rules 가 users.name 본인 수정을 차단한다', () {
      final rules = _src(_rules);
      final idx = rules.indexOf('allow update: if isLoggedIn() &&');
      expect(idx, isNot(-1));
      final block = rules.substring(idx, idx + 2500);
      expect(block.contains("'name', 'legalName', 'koreanName'"), isTrue,
          reason: '이 차단이 풀리면 이름이 사실상 가변 식별자가 된다. '
              '그때는 이름을 쓰는 모든 표시 지점을 다시 봐야 한다.');
    });
  });

  group('PID-5x 과거 귀속은 스냅샷이 지킨다', () {
    test('PID-50 계약서는 workerId 로 사람을, snapshot 으로 명의를 가진다', () {
      final s = _flat(_codeOf(
          _src('lib/models/core/employment_contract_model.dart')));
      expect(s.contains("'workerId': workerId"), isTrue);
      expect(s.contains("'workerName': workerName"), isTrue,
          reason: '명의는 서명 시점 사본이어야 한다 — 개명해도 과거 계약이 바뀌면 안 된다.');
    });

    test('PID-51 이체 계획의 계좌는 확정 시점 스냅샷에서만 온다', () {
      final s = _flat(_codeOf(_src('lib/utils/transfer_export_plan.dart')));
      expect(s.contains('r.wageAccountBankName'), isTrue);
      expect(s.contains('r.wageAccountNumberEncrypted'), isTrue);
      expect(s.contains('r.wageAccountHolder'), isTrue);
      // 현재 프로필로 메우지 않는다.
      expect(s.contains('users/'), isFalse,
          reason: '계좌를 현재 프로필에서 읽으면 INV-2 가 깨진다.');
    });
  });
}
