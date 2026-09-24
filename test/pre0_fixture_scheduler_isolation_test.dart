// [BLOCKER-PRE0-FIXTURE-SCHEDULER-CONTAMINATION]
//
//   보호 fixture `R7_FIX_LT_WORKER` 는 "오늘도 근무일"이어야 한다고 적혀
//   있었다. 그래야 체크인 CTA 를 증명한다. 그리고 아무도 체크인하지
//   않는다 — fixture 니까.
//
//   그것이 정확히 auto NO_SHOW 의 조건이다.
//
//       영원히 보호되는 fixture  AND  영원히 근태 대상
//
//   둘은 원천적으로 충돌한다. scheduler 는 잘못하지 않았다 — fixture 의
//   현재 일정을 보고 정상적으로 행동했다. 그래서 제품에 예외를 넣지
//   않고 fixture 의 역할을 나눈다.
//
//   검증이 그것을 못 잡은 이유도 같다. 검증은 **오늘** 문서가 없는지만
//   봤는데 scheduler 는 **어제** 자리에 쓴다. 오염이 매일 늘어나는 동안
//   7/7 이었다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';

const _cfPath = 'functions/src/index.ts';
const _buildPath = 'scripts/r7-fixture-build.js';
const _verifyPath = 'scripts/r7-fixture-verify.js';
const _seedPath = 'scripts/seed-r7-fixtures-dev.js';
const _repairPath = 'scripts/pre0-fixture-scheduler-isolation.js';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String s) =>
    s.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _after(String src, String name, int chars) {
  final i = src.indexOf(name);
  if (i < 0) throw StateError('$name 를 찾지 못함');
  return src.substring(i, (i + chars).clamp(0, src.length));
}

DateTime _d(int y, int m, int day) => DateTime(y, m, day);

/// 격리된 anchor: 2026-09-09 ~ 2026-09-22, 전 요일 근무, 종료 결정됨.
ApplicationModel _anchor({DateTime? end, String? renewalDecision}) =>
    ApplicationModel(
      id: 'zqa_사무업무_tJ8',
      businessId: 'fLmSOHVKUwmBHcbwQE0I',
      businessName: '위워커',
      toTitle: '[R7FIX] 장기 근무 공고',
      workDate: _d(2026, 9, 9),
      workEndDate: end ?? _d(2026, 9, 22),
      workDays: const ['월', '화', '수', '목', '금', '토', '일'],
      startTime: '06:00',
      endTime: '08:00',
      uid: 'tJ8izfP2nNYN79aPTLb6YARiPqC3',
      selectedWorkType: '사무업무',
      wage: 12000,
      wageType: 'hourly',
      status: AppStatus.contractPending,
      appliedAt: _d(2026, 9, 1),
      confirmedAt: _d(2026, 9, 2),
      renewalDecision: renewalDecision ?? AppStatus.renewalTerminate,
    );

void main() {
  final cf = _codeOf(_src(_cfPath));
  final build = _codeOf(_src(_buildPath));
  final verify = _codeOf(_src(_verifyPath));
  final seed = _src(_seedPath); // 주석(NOT_SEEDED 설명)도 본다
  final repair = _codeOf(_src(_repairPath));

  // ══════════════════════════════════════════════════════════════
  // 01. 제품에 예외를 넣지 않았다 (§1·§29·§56)
  // ══════════════════════════════════════════════════════════════
  group('01. product code 무개입', () {
    test('01-a scheduler 에 fixture id · 테스트 계정 예외가 없다', () {
      for (final banned in [
        'R7_FIX', 'R7FIX', 'tJ8izfP2nN', 'fLmSOHVKUwmBHcbwQE0I',
        'zqaJEjUVPA', 'isFixture', 'testWorker', 'skipFixture',
      ]) {
        expect(cf.contains(banned), false, reason: banned);
      }
    });

    test('01-b auto NO_SHOW 조건은 그대로다', () {
      final ns = _after(cf, '  const longSnap = await db.collection("applications")', 1400);
      expect(ns, contains('.where("status", "in", ["CONFIRMED", "CONTRACT_PENDING"])'));
      expect(ns, contains('if (d.type !== "long_term") continue;'));
      expect(ns, contains('srvLongTermEligibleOnDay('));
    });

    test('01-c 근무일 판정식도 그대로다', () {
      final r = _after(cf, 'function srvLongTermEligibleOnDay(', 1638);
      expect(r, contains('if (dayNum < startNum) return {eligible: false, reason: "BEFORE_START"}'));
      expect(r, contains('reason: resign ? "AFTER_RESIGN" : "AFTER_END"'));
      expect(r, contains('!Array.isArray(wd) || wd.length === 0 || !wd.includes(dayWkd)'));
    });

    test('01-d 90일 3회 제한 정책도 그대로다', () {
      final c = _after(cf, 'function _compute90dRestriction(', 500);
      expect(c, contains('if (recent < 3) return null;'));
      expect(c, contains('24 * 60 * 60 * 1000'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 02. anchor 는 어떤 날도 근무일이 아니다 (§25·§46·§51)
  // ══════════════════════════════════════════════════════════════
  group('02. future eligibility 0', () {
    test('02-a 종료 다음 날부터 근무일이 아니다', () {
      final a = _anchor();
      expect(a.isWorkingOnDate(_d(2026, 9, 22)), true, reason: '마지막 근무일');
      expect(a.isWorkingOnDate(_d(2026, 9, 23)), false);
    });

    test('02-b 오늘 하루가 아니라 45일을 훑어도 0일이다', () {
      final a = _anchor();
      var eligible = 0;
      for (var i = 0; i <= 45; i++) {
        if (a.isWorkingOnDate(_d(2026, 9, 24).add(Duration(days: i)))) {
          eligible++;
        }
      }
      expect(eligible, 0);
    });

    test('02-c 전 요일 근무여도 기간이 끝났으면 대상이 아니다', () {
      // 요일을 비정상 값으로 만들어 회피한 것이 아님을 고정한다.
      expect(_anchor().workDays, hasLength(7));
    });

    test('02-d 기간이 열려 있으면 다시 대상이 된다 — 회귀 재현', () {
      // 이것이 blocker 였다. 종료일을 미래로 되돌리면 매일 근무일이 된다.
      final open = _anchor(end: _d(2026, 12, 31));
      var eligible = 0;
      for (var i = 0; i <= 45; i++) {
        if (open.isWorkingOnDate(_d(2026, 9, 24).add(Duration(days: i)))) {
          eligible++;
        }
      }
      expect(eligible, 46, reason: '고치기 전 상태');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 03. builder 가 기간을 닫는다 (§8·§12·§27)
  // ══════════════════════════════════════════════════════════════
  group('03. seed', () {
    test('03-a 마지막 근태일을 계약 종료일로 삼는다', () {
      expect(build, contains('const lastWorkOffset = Math.max(...attendanceOffsets);'));
      expect(build, contains('workEndDate: admin.firestore.Timestamp.fromMillis(lastWorkMs)'));
    });

    test('03-b 끝난 관계라고 적는다 — 결정 queue 에 남기지 않는다', () {
      expect(build, contains("renewalDecision: 'TERMINATE'"));
    });

    test('03-c 미래로 밀어두기만 한 것이 아니다', () {
      // 종료일이 근태 목록에서 나오므로 언제 seed 해도 과거다.
      expect(build.contains('toOffset: 365'), false);
      expect(build.contains("kstMidnightMs(400)"), false);
    });

    test('03-d workDays 를 비우거나 leaveDates 로 회피하지 않았다', () {
      final b = _after(build, 'async function buildLongTermWorker(', 1200);
      expect(b, contains("const workDays = ['월', '화', '수', '목', '금', '토', '일'];"));
      expect(build.contains('leaveDates: ['), false);
    });

    test('03-e status 를 거짓으로 바꾸지 않았다', () {
      // CONTRACT_PENDING 그대로 — 검증 의미를 바꾸지 않는다.
      expect(build.contains("status: 'CANCELED'"), false);
      expect(build.contains("status: 'REJECTED'"), false);
    });

    test('03-f 분리된 역할을 기록했다', () {
      expect(seed, contains('ACTIVE LONG-TERM (오늘 근무일 · 체크인 CTA)'));
      expect(seed, contains('BLOCKER-PRE0-FIXTURE-SCHEDULER-CONTAMINATION'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 04. verify 가 오염을 잡는다 (§23·§24·§52)
  // ══════════════════════════════════════════════════════════════
  group('04. verify contract', () {
    test('04-a 다섯 가지를 모두 본다', () {
      for (final k in [
        'PRE0-SCHED-01', 'PRE0-SCHED-02', 'PRE0-SCHED-03',
        'PRE0-SCHED-04', 'PRE0-SCHED-05',
      ]) {
        expect(verify, contains(k), reason: k);
      }
    });

    test('04-b 예상 밖 근태와 자동 NO_SHOW 를 직접 찾는다', () {
      expect(verify, contains("d.data().status === 'NO_SHOW'"));
      expect(verify, contains('!!d.data().autoNoShowAt'));
      expect(verify, contains('!anchorIds.has(d.id)'));
    });

    test('04-c 오늘 하루가 아니라 기간 전체를 훑는다', () {
      expect(verify, contains('const horizon = 45;'));
      expect(verify, contains('for (let i = 0; i <= horizon; i++)'));
    });

    test('04-d 판정에 다섯 결과가 모두 들어간다', () {
      expect(verify, contains('schedIsolatedOk && lastDoneOk && noExtraOk &&'));
      expect(verify, contains('noNoShowOk && noPenaltyOk && restrictionOk && wagesOk'));
    });

    test('04-e 예전 검증은 오늘 문서만 봤다 — 그래서 못 잡았다', () {
      // scheduler 는 어제 자리에 쓴다. 그 앵커가 사라졌는지 고정한다.
      expect(verify.contains('const todayMissing = !(await db'), false);
      expect(verify.contains('workTodayOk'), false);
    });

    test('04-f 실패를 성공으로 바꾸지 않는다', () {
      expect(verify.contains('catch (_) {}'), false);
      expect(verify.contains('catch { return true'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 05. repair 도구 (§16·§18·§19·§31·§32)
  // ══════════════════════════════════════════════════════════════
  group('05. repair guard', () {
    test('05-a DEV 전용 · PROD 차단', () {
      expect(repair, contains("const EXPECTED_DEV_PROJECT = 'alfit-89567'"));
      expect(repair, contains('PROD 프로젝트입니다. 실행하지 않습니다.'));
      expect(repair, contains('process.exit(2)'));
    });

    test('05-b dry-run 이 기본이다', () {
      expect(repair, contains("const EXECUTE = argv.includes('--execute')"));
      expect(repair, contains('dry-run 종료. 쓰려면 --execute'));
    });

    test('05-c identity 는 manifest 에서 읽는다 — 추측하지 않는다', () {
      expect(repair, contains('manifest.scenarios && manifest.scenarios.R7_FIX_LT_WORKER'));
      expect(repair, contains('manifest 에 R7_FIX_LT_WORKER 가 없다'));
    });

    test('05-d 삭제 전에 소유권을 증명한다', () {
      expect(repair, contains('a.applicationId === id.applicationId'));
      expect(repair, contains('a.userId === workerUid'));
      expect(repair, contains('a.businessId === businessId'));
      expect(repair, contains('!!a.autoNoShowAt'));
      expect(repair, contains('소유권 증명 실패'));
    });

    test('05-e 출처를 모르는 문서는 건드리지 않는다', () {
      expect(repair, contains('출처를 모르는 문서는 건드리지 않는다'));
    });

    test('05-f 급여 anchor 는 오염이 아니다', () {
      expect(repair, contains('!id.payrollIds.includes(a.id)'));
    });

    test('05-g 신뢰도는 남은 사건에서 다시 센다 — 산술 보정 아님', () {
      expect(repair, contains('const remaining = foreign'));
      expect(repair, contains('const recent = remaining.filter'));
      expect(repair, contains('recent >= 3 ?'));
      expect(repair.contains('- 3'), false);
    });

    test('05-h 무관한 NO_SHOW 가 사라지면 실패한다', () {
      expect(repair, contains('foreignAfter.length !== foreign.length'));
      expect(repair, contains('무관한 NO_SHOW 가 사라졌다'));
    });

    test('05-i 넓은 초기화를 하지 않는다', () {
      for (final banned in [
        'recentNoShowCount: 0', 'noShowDates: []', 'noShowCount: 0',
      ]) {
        expect(repair.contains(banned), false, reason: banned);
      }
    });

    test('05-j 조용한 catch 가 없다', () {
      expect(repair.contains('catch (_) {}'), false);
      expect(repair.contains('catch {}'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 06. 신뢰도 재계산 규칙 (§19·§20)
  // ══════════════════════════════════════════════════════════════
  group('06. reliability recompute', () {
    /// 제품 정책의 거울 — 최근 90일 3회 이상이면 1일 제한.
    bool restricted(List<int> daysAgo) =>
        daysAgo.where((d) => d <= 90).length >= 3;

    test('06-a fixture 사건 1건을 빼면 3회 → 2회', () {
      expect(restricted([9, 5, 0]), true, reason: '고치기 전');
      expect(restricted([9, 5]), false, reason: 'fixture 사건 제거 후');
    });

    test('06-b 다른 runtime 사건이 3건이면 제한이 유지된다', () {
      expect(restricted([9, 5, 2]), true);
    });

    test('06-c 90일 밖 사건은 세지 않는다', () {
      expect(restricted([100, 120, 5]), false);
    });
  });
}
