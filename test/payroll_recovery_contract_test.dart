// [PII-DOC-R1.6.1] PAYROLL RECOVERY / WORKER TASK / SNAPSHOT REFRESH
//
// 이 파일이 고정하는 것:
//
//   AC   막힌 이유마다 풀 사람이 다르다 (actor 분류).
//   CW   근로자가 고칠 수 있는 문제는 canonical 보완 요청을 연다.
//   TK   Worker Home Task 의 source 는 알림이 아니라 OPEN correction 이다.
//   RS   Task 는 실제 준비가 회복돼야 닫힌다.
//   UI   관리자는 자기가 풀 수 있는 것에만 버튼을 받는다.
//   IM   임금·근태·이체 완료 기록은 회복 과정에서 바뀌지 않는다.

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
const _dashPath =
    'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';
const _homePath = 'lib/screens/user/user_home_screen.dart';
const _corrSvc = 'lib/services/payroll_correction_service.dart';
const _readySvc = 'lib/services/payroll_readiness_service.dart';

void main() {
  final rawCf = _src(_cfPath);
  final actor = _codeOf(
      _sliceOf(rawCf, 'function srvPayrollActorFor(', '\n}'));
  final actorBlock = _codeOf(
      _sliceOf(rawCf, 'function srvPayrollActorForBlock(', '\n}'));
  final ensure = _codeOf(
      _sliceOf(rawCf, 'async function srvEnsurePayrollCorrection(', '\n}\n'));
  final corrId = _codeOf(
      _sliceOf(rawCf, 'function srvPayrollCorrectionId(', '\n}'));
  final myCorr = _codeOf(_sliceOf(rawCf,
      'export const callableGetMyDocumentCorrections = onCall(', '\n);'));
  final batch = _codeOf(_sliceOf(rawCf,
      'export const callableGetPayrollReadinessBatch = onCall(', '\n);'));
  final refresh = _codeOf(_sliceOf(rawCf,
      'export const callableRefreshWagePaymentSnapshot = onCall(', '\n);'));
  final dash = _src(_dashPath);
  final home = _src(_homePath);

  // ── AC. 행동 주체 ───────────────────────────────────────────────
  group('AC — 막힌 이유마다 풀 사람이 다르다 (§4)', () {
    test('01 근로자가 고칠 수 있는 사유', () {
      for (final s in ['PR_MISSING_BANK_ACCOUNT', 'PR_MISSING_BANKBOOK',
        'PR_BANK_MISMATCH']) {
        expect(actor, contains(s), reason: s);
      }
      expect(actor, contains('PAY_ACTOR_WORKER'));
    });

    test('02 판정 불가는 근로자 잘못이 아니다 (§10)', () {
      expect(actor, contains('PAY_ACTOR_WORKER_OR_REVIEW'));
      // 자동 불확실이 강제 보완으로 이어지지 않는다.
      final states = _codeOf(_sliceOf(rawCf,
          'const PAYROLL_CORRECTION_STATES = [', '];'));
      expect(states, contains('PR_MISSING_BANK_ACCOUNT'));
      expect(states, contains('PR_BANK_MISMATCH'));
      expect(states, isNot(contains('PR_BANK_OCR_UNCERTAIN')));
      expect(states, isNot(contains('PR_BANK_UNASSESSED')));
    });

    test('03 READY 면 풀 것이 없다', () {
      expect(actor, contains('PAY_ACTOR_NONE'));
    });

    test('04 스냅샷 문제는 관리자 몫이다', () {
      expect(actorBlock, contains('XFER_STALE_PAYMENT_SNAPSHOT'));
      expect(actorBlock, contains('XFER_SNAPSHOT_PROVENANCE_UNKNOWN'));
      expect(actorBlock, contains('PAY_ACTOR_MANAGER_REFRESH'));
    });

    test('05 이체 응답이 사유와 함께 주체를 돌려준다 (§16)', () {
      final xfer = _codeOf(_sliceOf(rawCf,
          'export const callableMarkTransferredBatch = onCall(', '\n);'));
      expect(xfer, contains('blockedActors'));
      expect(xfer, contains('srvPayrollActorForBlock('));
    });
  });

  // ── CW. 보완 요청 ───────────────────────────────────────────────
  group('CW — 근로자가 고칠 수 있으면 요청을 연다 (§8·§9·§10)', () {
    test('06 기존 correction 도메인을 확장했다 — 새 컬렉션 없음', () {
      expect(ensure, contains('DOC_CORRECTION_COL'));
      expect(ensure, contains('CORRECTION_DOMAIN_PAYROLL'));
      expect(rawCf, isNot(contains('payrollCorrectionRequests')));
    });

    test('07 C2 — 결정적 id 로 중복을 막는다', () {
      expect(corrId, contains('businessId'));
      expect(corrId, contains('workerUid'));
      expect(corrId, contains('CORRECTION_DOMAIN_PAYROLL'));
      expect(corrId, contains('accV'));
      expect(corrId, contains('bbV'));
      expect(_flat(ensure), contains('if (fresh.exists)'));
      expect(ensure, contains('db.runTransaction'));
    });

    test('08 C1 — 급여 확정이 막히면 요청이 열린다', () {
      final wage = _codeOf(_sliceOf(rawCf,
          'export const callableConfirmFinalWage = onCall(',
          'export const callableCancelFinalConfirmation'));
      expect(wage, contains('srvEnsurePayrollCorrection('));
      expect(wage, contains('PAYROLL_CORRECTION_STATES.includes(pr.state)'));
    });

    test('09 요청 생성 실패가 마감을 되돌리지 않는다 (§2)', () {
      final wage = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableConfirmFinalWage = onCall(',
          'export const callableCancelFinalConfirmation')));
      expect(wage, contains('보완 요청 생성 실패(마감은 유지)'));
    });

    test('10 §28 — 지급 문제로 지원·근무를 취소하지 않는다', () {
      for (final f in ['AUTO_CANCELED', 'applications', 'trustScore',
        'finalWage', 'wageStatus']) {
        expect(ensure, isNot(contains(f)), reason: f);
      }
    });
  });

  // ── TK. Worker Task ─────────────────────────────────────────────
  group('TK — Task source 는 알림이 아니다 (§11·§12)', () {
    test('11 T1 — Home 이 OPEN correction 을 읽어 Task 를 만든다', () {
      expect(home, contains('PayrollCorrectionService.loadMine()'));
      expect(home, contains('_buildCorrectionTaskCard'));
      final svc = _src(_corrSvc);
      expect(svc, contains('callableGetMyDocumentCorrections'));
    });

    test('12 T2 — 알림을 읽거나 지워도 Task 는 남는다', () {
      final card = _codeOf(
          _sliceOf(home, 'Widget _buildCorrectionTaskCard(', '\n  }'));
      for (final f in ['notification', 'Notification', 'fcm', '_notif']) {
        expect(card, isNot(contains(f)), reason: '$f — Task 는 알림 수명과 무관하다');
      }
      expect(card, contains('_correctionSurface'));
    });

    test('13 T4 — 본인 것만 본다', () {
      expect(myCorr, contains('const workerUid = request.auth.uid'));
      expect(myCorr, contains('.where("workerUid", "==", workerUid)'));
      // 클라이언트가 uid 를 넘기지 않는다.
      expect(_src(_corrSvc), isNot(contains("'workerUid'")));
    });

    test('14 §26 — 사업장 문맥을 잃지 않는다', () {
      expect(myCorr, contains('businessId'));
      expect(myCorr, contains('businessName'));
      expect(_src(_corrSvc), contains('businessName'));
    });

    test('15 지급 출처와 지원 출처를 구분해 말한다', () {
      final svc = _src(_corrSvc);
      expect(svc, contains("sourceDomain == 'PAYROLL'"));
      expect(svc, contains('급여 지급을 위해 필요해요'));
      expect(svc, contains('서류 재등록을 요청했어요'));
    });

    test('16 조회 실패를 "할 일 없음"으로 바꾸지 않는다', () {
      final svc = _src(_corrSvc);
      expect(svc, contains('loadFailed'));
      expect(svc, contains('UNKNOWN ≠ EMPTY'));
      final card = _codeOf(
          _sliceOf(home, 'Widget _buildCorrectionTaskCard(', '\n  }'));
      expect(card, contains('_correctionSurface.loadFailed'));
    });
  });

  // ── RS. 해결 ────────────────────────────────────────────────────
  group('RS — 실제 회복돼야 닫힌다 (§13)', () {
    test('17 C3·C4 — 업로드 성공만으로 닫지 않는다', () {
      expect(myCorr, contains('srvResolvePayrollReadiness('));
      expect(_flat(myCorr), contains('if (!pr.ready) return;'));
      expect(myCorr, contains('CORRECTION_RESOLVED'));
    });

    test('18 지급 도메인 요청만 이 경로로 닫는다', () {
      expect(myCorr, contains('sourceDomain") === CORRECTION_DOMAIN_PAYROLL'));
    });

    test('19 T3 — 닫힌 요청은 응답에서 빠진다', () {
      expect(myCorr, contains('resolvedIds'));
      expect(myCorr, contains('requests: live.map('));
    });

    test('20 갱신 성공도 요청을 닫는다', () {
      expect(refresh, contains('CORRECTION_RESOLVED'));
      expect(refresh, contains('CORRECTION_DOMAIN_PAYROLL'));
    });

    test('21 닫지 못해도 없는 할 일을 만들지 않는다', () {
      expect(myCorr, contains('지급 보완 재판정 실패'));
    });
  });

  // ── UI. 관리자 ──────────────────────────────────────────────────
  group('UI — 풀 수 있는 것에만 버튼을 준다 (§5·§7·§16)', () {
    test('22 U1·U2 — 갱신 CTA 조건', () {
      final cond = _codeOf(
          _sliceOf(dash, 'bool _needsSnapshotRefresh(', '\n  }'));
      expect(cond, contains('_readinessUnknown.contains(uid)'));
      expect(cond, contains('!info.ready'));
      expect(cond, contains('snapshotNeedsRefresh'));
      final svc = _codeOf(_sliceOf(_src(_readySvc),
          'bool snapshotNeedsRefresh(', '\n  }'));
      expect(svc, contains('wageTransferred'));
      expect(svc, contains('wageConfirmed'));
      expect(svc, contains('srcAcc == null || srcBb == null'));
    });

    test('23 U3 — NOT READY 면 버튼 대신 상태를 보여준다', () {
      final wait = _codeOf(
          _sliceOf(dash, 'String? _payrollWaitLabel(', '\n  }'));
      expect(wait, contains('근로자 정보 보완 대기'));
      expect(wait, contains('통장사본 확인 필요'));
      expect(dash, contains("waitLabel != null"));
    });

    test('24 CTA 문구가 급여 재확정을 뜻하지 않는다 (§5)', () {
      // 주석에는 "그게 아니다"라는 설명이 남아 있으므로 코드만 본다.
      final code = _codeOf(dash);
      expect(code, contains("'지급정보 갱신'"));
      expect(code, isNot(contains("'급여 다시 확정'")));
      expect(code, isNot(contains("'근태 다시 마감'")));
    });

    test('25 U4·§25 — 권한은 canManageWage 다', () {
      expect(batch, contains('perms.canManageWage'));
      expect(refresh, contains('perms.canManageWage'));
      for (final f in ['canManageWorkers', 'canManageTo']) {
        expect(batch, isNot(contains(f)), reason: f);
        expect(refresh, isNot(contains(f)), reason: f);
      }
    });

    test('26 §29 — 조회 실패를 "확인 필요"에 넣지 않는다', () {
      expect(batch, contains('failed'));
      expect(batch, contains('Promise.allSettled'));
      expect(dash, contains('_readinessUnknown'));
      expect(dash, contains('지급 준비 상태 조회 실패'));
    });

    test('27 갱신 결과의 PARTIAL 을 성공으로 숨기지 않는다', () {
      final fn = _codeOf(
          _sliceOf(dash, 'Future<void> _refreshSnapshots(', '\n  }'));
      expect(fn, contains('res.skipped.isNotEmpty'));
      expect(fn, contains('갱신하지 못한 건이 있습니다'));
    });
  });

  // ── IM. 불변 ────────────────────────────────────────────────────
  group('IM — 회복이 임금·근태·과거 지급을 바꾸지 않는다 (§2·§27)', () {
    test('28 §6 — 갱신은 금액·근태를 건드리지 않는다', () {
      for (final f in ['finalWage', 'netWage', 'wageDetail', 'wageStatus:',
        'checkInAt', 'workMinutes']) {
        expect(refresh, isNot(contains(f)), reason: f);
      }
    });

    test('29 §27 — 이체 완료 건에는 갱신을 만들지 않는다', () {
      expect(refresh, contains('d.wageStatus === "transferred"'));
      final svc = _codeOf(_sliceOf(_src(_readySvc),
          'bool snapshotNeedsRefresh(', '\n  }'));
      expect(svc, contains('wageTransferred) return false'));
    });

    test('30 §20 — 서버가 몰래 provenance 를 추정하지 않는다', () {
      // 갱신은 명시적 호출이다. 이체 경로가 근거를 지어내지 않는다.
      final stale = _codeOf(
          _sliceOf(rawCf, 'function srvWageSnapshotStaleReason(', '\n}'));
      expect(stale, contains('XFER_SNAPSHOT_PROVENANCE_UNKNOWN'));
      expect(stale, isNot(contains('update')));
      expect(stale, isNot(contains('set(')));
    });

    test('31 근로자 화면도 금액이 남아 있음을 말한다', () {
      expect(_src('lib/screens/user/wage_detail_screen.dart'),
          contains('급여 금액은 그대로 확정되어 있습니다'));
      final card = _sliceOf(home, 'Widget _buildCorrectionTaskCard(', '\n  }');
      expect(card, contains('확정된 급여 금액은 그대로 유지돼요'));
    });
  });
}
