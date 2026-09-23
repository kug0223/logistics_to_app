// [PREDEVICE-RUNTIME-CLOSURE.1A] 끝난 근무에 대체 인력을 충원하지 않는다
//
// READ에서 확인된 것:
//   · 자동 노쇼는 06:00에 "어제" 근무를 NO_SHOW로 기록한다. 그 기록은 좌석을
//     반납하지 않으므로 staffingReleasedAt이 비어 있고, 나머지 조건
//     (NO_SHOW · 단기 · 확정 · canManageTo)은 모두 만족한다.
//   · 근태 화면(AttendanceStatusDialog)에는 당일 게이트가 이미 있었다.
//     지원자 화면(DayApplicantsDialog)에는 없었고, 근무 탭이 주간/월간 달력에서
//     고른 **과거 날짜**로 그 화면을 연다.
//   · 서버(callableReleaseNoshowSeat)에도 날짜 조건이 없었다. 즉 막는 것이
//     한쪽 화면뿐이었고, 다른 화면에서는 실제로 실행할 수 있었다.
//   · 실행되면 totalConfirmed가 줄고 FULL이 ACTIVE로 돌아간다 —
//     이미 지나간 날짜에 대해 다시 사람을 구하는 상태가 만들어진다.
//
// 그리고 client는 "당일"인데 server는 "오늘 이후"였다 — 같은 action의 권위
// 판정이 화면과 서버에서 갈렸다. NO_SHOW를 쓰는 writer는 둘뿐이고 둘 다 미래
// 날짜를 만들 수 없으므로(관리자 경로는 [NS-02-FIX]로 skip, 자동 경로는 어제만),
// 서버도 당일로 좁혔다.
//
// DEV runtime (최종):
//   어제 · NO_SHOW · 미반납  → 400  좌석 유지 · TO confirmed 1 · FULL
//   오늘 · NO_SHOW · 미반납  → 200  좌석 반납 · TO confirmed 0 · ACTIVE
//   내일 · NO_SHOW · 미반납  → 400  좌석 유지 · TO confirmed 1 · FULL
//   오늘 · 이미 반납         → 200  alreadyReleased (중복 감소 없음)
//   오늘 · NO_SHOW 기록 없음 → 400  거절
//
// 계약:
//   과거 NO_SHOW 기록 자체는 그대로 보인다. 막는 것은 action뿐이다.
//   당일 replacement는 그대로 살아 있다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnsPath = 'functions/src/index.ts';
const _dayDialogPath =
    'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';
const _attDialogPath =
    'lib/screens/business_admin/dialogs/attendance_status_dialog.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _callableOf(String source, String name) {
  final start = source.indexOf('export const $name = onCall(');
  if (start < 0) throw StateError('$name 을 찾지 못함');
  final next = source.indexOf('\nexport ', start + 10);
  return source.substring(start, next == -1 ? source.length : next);
}

void main() {
  group('서버가 지난 근무의 좌석 반납을 막는다', () {
    final cf = _codeOf(_callableOf(_src(_fnsPath), 'callableReleaseNoshowSeat'));
    final flat = _flat(cf);

    test('workDate를 오늘(KST)과 비교한다', () {
      expect(flat.contains('const relWorkDateTs = appData.workDate'), true);
      expect(flat.contains('if (wdKstStartMs !== todayKstStartMs)'), true,
          reason: '날짜 조건이 없으면 끝난 근무의 좌석이 반납된다');
      expect(cf.contains('이미 지난 근무는 대체 인력을 충원할 수 없습니다.'), true);
    });

    test('쓰기 전에 막는다 — 트랜잭션 진입 이전', () {
      final guardAt = flat.indexOf('if (wdKstStartMs !== todayKstStartMs)');
      final txAt = flat.indexOf('await db.runTransaction(');
      expect(guardAt > 0 && txAt > guardAt, true,
          reason: '좌석 감소가 일어난 뒤 막으면 의미가 없다');
    });

    test('기존 guard가 느슨해지지 않았다', () {
      for (final g in [
        'staffingReleasedAt != null',
        'long_term',
        'CONFIRMED_STATUSES.includes(appStatus)',
        '"status", "==", "NO_SHOW"',
        'canManageTo',
      ]) {
        expect(flat.contains(g), true, reason: '$g guard가 사라졌다');
      }
    });

    test('당일만 허용한다 — 과거도 미래도 막는다', () {
      // client 두 화면이 "오늘"을 쓰므로 서버도 같은 식이어야 한다.
      // 과거만 막는 단방향 비교로 되돌아가면 같은 action의 권위 판정이
      // 화면과 서버에서 갈린다.
      expect(flat.contains('if (wdKstStartMs !== todayKstStartMs)'), true,
          reason: '부등호 비교로 되돌아가면 서버만 미래를 허용하게 된다');
      expect(flat.contains('"당일 근무만 대체 인력을 충원할 수 있습니다."'), true,
          reason: '미래와 과거는 이유가 다르므로 문구도 달라야 한다');
      expect(flat.contains('"이미 지난 근무는 대체 인력을 충원할 수 없습니다."'), true);
    });

    test('미래 NO_SHOW를 만드는 writer가 없다 — 당일 한정의 근거', () {
      final src = _src(_fnsPath);
      final code = _codeOf(src);
      // NO_SHOW를 쓰는 writer는 둘뿐이다.
      expect('status: "NO_SHOW",'.allMatches(code).length, 2,
          reason: 'NO_SHOW writer가 늘면 미래 날짜 가능성을 다시 판단해야 한다');
      // 관리자 수동 경로는 미래 날짜를 skip한다.
      expect(_flat(code).contains('if (workDateMs > todayKSTStartMs) { skippedSet.add(resolvedId); return undefined; }'),
          true, reason: '[NS-02-FIX] 미래 NO_SHOW 선제 생성 차단이 사라졌다');
      // 자동 경로는 어제만 훑는다.
      //   [LONGTERM-DATE-ELIGIBILITY] 요일 계산이 공용 resolver로 올라가면서
      //   지역 변수(yesterdayWeekday)는 사라졌다. 여기서 확인할 것은 요일
      //   변수의 존재가 아니라 **훑는 창이 어제 하루**라는 사실이다.
      expect(code.contains('.where("workDate", ">=", Timestamp.fromDate(yesterdayStartUTC))'),
          true, reason: '단기 자동 노쇼가 어제 하루만 본다');
      expect(code.contains('.where("workDate", "<",  Timestamp.fromDate(todayStartUTC))'),
          true, reason: '오늘 이후는 훑지 않는다');
      expect(code.contains('const nsDayDate = new Date(yesterdayStartUTC.getTime());'),
          true, reason: '장기 자동 노쇼도 어제 날짜로만 판정한다');
    });
  });

  group('두 화면이 같은 게이트를 쓴다', () {
    test('지원자 화면에 날짜 게이트가 생겼다', () {
      final d = _codeOf(_src(_dayDialogPath));
      expect(d.contains('bool get _isReplacementActionable'), true);
      expect(
        _flat(d).contains('return dateKst.isAtSameMomentAs(todayKst);'),
        true,
        reason: '서버와 같은 식 — 당일만',
      );
    });

    test('CTA 표시 조건 두 곳 모두에 적용됐다', () {
      final d = _flat(_codeOf(_src(_dayDialogPath)));
      expect('_isReplacementActionable'.allMatches(d).length, 3,
          reason: '정의 1 + Row 렌더 조건 + 버튼 조건');
    });

    test('근태 화면의 기존 당일 게이트는 그대로다', () {
      final a = _flat(_codeOf(_src(_attDialogPath)));
      expect(a.contains('final todayKst = FormatHelper.toKstDate(DateTime.now());'),
          true);
      expect(a.contains('return const SizedBox.shrink();'), true);
    });
  });

  group('기록은 남기고 action만 막는다', () {
    test('과거 NO_SHOW 배지·기록 렌더가 게이트에 묶이지 않았다', () {
      final d = _codeOf(_src(_dayDialogPath));
      // 배지 블록은 isStaffingReleased만 보고 날짜를 보지 않는다.
      final guardAt = d.indexOf('if (app.isStaffingReleased) ...[');
      final badgeAt = d.indexOf("'대체 충원 진행 중'");
      expect(guardAt > 0 && badgeAt > guardAt, true,
          reason: '배지가 isStaffingReleased 분기 안에 있어야 한다');
      final block = d.substring(guardAt, badgeAt);
      expect(block.contains('_isReplacementActionable'), false,
          reason: '이미 반납된 과거 기록까지 숨기면 이력이 사라진다');
    });

    test('다른 상태에는 CTA가 생기지 않는다', () {
      final d = _flat(_codeOf(_src(_dayDialogPath)));
      // NO_SHOW 목록에 들어 있는 지원서만 대상이다.
      expect(d.contains('_noShowApplicationIds.contains(app.id)'), true);
      expect(d.contains('!app.isLongTermApplication'), true);
    });
  });
}
