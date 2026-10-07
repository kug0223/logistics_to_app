// [R7-PAYROLL-POLICY.3] 확정된 약속에 근태 기준이 빠져 있었다
//
// ALfit 의 책임구조는 이렇다.
//   사업장이 근태·급여 정책을 결정한다.
//   ALfit 은 그 정책을 정확히 기록하고, **확정 시 고정하고**, 이후 변경을
//   소급하지 않는다.
//
// 그런데 두 군데가 비어 있었다.
//
//   ① 출퇴근이 `businesses.attendanceRules` 를 **live** 로 읽었다. 확정 뒤
//      사업장이 설정을 바꾸면 이미 약속된 근무의 급여 계산 기준이 소급해서
//      달라졌다. 임금·시간·업무를 공고 수정으로 소급 변경하지 않는 기존
//      원칙에서 근태 기준만 빠져 있었다.
//
//   ② 기본값과 사업장의 선택을 구별할 수 없었다. 슬라이더를 한 번도
//      건드리지 않아도 `rulesUpdatedBy: ownerId` 가 찍혔다. 그러면 그 정책의
//      책임이 사업장에 귀속되지 않는다 — 급여를 깎는 `lateUnit 30` 은
//      ALfit 기본값이다.
//
// 반올림 계산식은 **한 줄도 바꾸지 않았다.**
//
// 고정하는 것
//   OWN-1  기본값은 ALfit 출처다
//   OWN-2  값이 실제로 바뀌면 사업장 선택이다
//   OWN-3  저장 버튼만으로는 선택이 아니다
//   OWN-4  실제 편집자 uid 를 기록한다 (ownerId 하드코딩 회귀 방지)
//   OWN-5  과거 데이터를 선택으로 위조하지 않는다
//   SNAP-1 확정이 snapshot 을 만든다
//   SNAP-2 7개 숫자를 그대로 복사한다
//   SNAP-3 capturedAt 이 있다
//   SNAP-4 재확정이 snapshot 을 덮지 않는다
//   SNAP-5 출근이 snapshot 을 쓴다
//   SNAP-6 퇴근이 snapshot 을 쓴다
//   SNAP-7 관리자 batch 도 snapshot 을 쓴다
//   SNAP-8 legacy fallback 은 분리돼 있다
//   SNAP-9 snapshot 은 서버가 만든다 (클라이언트 값 금지)
//   SNAP-10 반올림 계산식 변경 0
import 'dart:io';

import 'package:ALfit/models/core/business_model.dart';
import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

String _code(String s) => s
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');

String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  if (i < 0) throw StateError('구간 시작을 찾지 못했다: $start');
  final j = src.indexOf(end, i + start.length);
  if (j <= i) throw StateError('구간 끝을 찾지 못했다: $end');
  return src.substring(i, j);
}

String _callable(String ts, String name) =>
    _slice(ts, 'export const $name = onCall(', '\nexport const ');

void main() {
  final cfRaw = _src('functions/src/index.ts');
  final cf = _code(cfRaw);
  final form =
      _code(_src('lib/screens/business_admin/business_form_screen.dart'));

  group('정책 출처 — 누가 정했는가', () {
    test('OWN-1 기본값은 ALfit 출처다', () {
      final d = AttendanceRules.defaults();
      expect(d.policySource, AttendanceRules.sourceAlfitDefault,
          reason: '기본값을 사업장이 고른 것으로 기록하면 책임 귀속이 거짓이 된다');
      // 급여를 깎는 값이 기본값에 들어 있다는 사실 자체를 고정한다.
      expect(d.lateUnit, 30);
      expect(d.earlyLeaveUnit, 30);
      expect(d.lateGrace, 5);
    });

    test('OWN-2 급여에 영향하는 7개 숫자만 비교한다', () {
      const a = AttendanceRules();
      // 감사 필드만 다르면 "같은 규칙" 이다 — 저장마다 변경으로 보면 안 된다.
      final b = a.copyWith(
          rulesUpdatedBy: 'someone', policySource: 'admin_selected');
      expect(a.sameRulesAs(b), isTrue);
      // 숫자가 하나라도 다르면 변경이다.
      expect(a.sameRulesAs(a.copyWith(lateUnit: 10)), isFalse);
      expect(a.sameRulesAs(a.copyWith(lateGrace: 0)), isFalse);
      expect(a.sameRulesAs(a.copyWith(overtimeUnit: 5)), isFalse);
    });

    test('OWN-3 저장 버튼만으로는 선택이 아니다', () {
      expect(form.contains('_attendanceRules.sameRulesAs(_initialAttendanceRules)'),
          isTrue, reason: '실제 값 변경으로 판정해야 한다');
      expect(form.contains('policyChanged'), isTrue);
      expect(
          form.contains('? AttendanceRules.sourceAdminSelected'), isTrue);
    });

    test('OWN-4 실제 편집자 uid 를 기록한다', () {
      expect(form.contains('rulesUpdatedBy: policyChanged ? user.uid : null'),
          isTrue, reason: '소유자 uid 가 아니라 호출자 uid 여야 한다');
      // 회귀 방지 — 옛 하드코딩이 돌아오면 잡는다.
      expect(form.contains('rulesUpdatedBy: ownerId'), isFalse,
          reason: '공동관리자가 바꿔도 소유자가 바꾼 것으로 남는다');
    });

    test('OWN-5 과거 데이터를 선택으로 위조하지 않는다', () {
      // fromMap 은 없는 출처를 채우지 않는다.
      final legacy = AttendanceRules.fromMap(const {'lateUnit': 30});
      expect(legacy.policySource, isNull,
          reason: '없는 것을 admin_selected 로 backfill 하면 증거 위조다');
      expect(AttendanceRules.sourceLegacy, 'legacy');
      // 서버도 없는 출처를 legacy 로만 읽는다.
      final builder = _code(_slice(
          cfRaw, 'function srvBuildAttendancePolicySnapshot(', '\n/**'));
      expect(builder.contains('"legacy"'), isTrue);
      expect(builder.contains('"admin_selected"'), isFalse,
          reason: '서버가 출처를 만들어내지 않는다');
    });
  });

  group('확정 snapshot — 약속은 고정된다', () {
    final confirm = _code(_callable(cfRaw, 'callableConfirmApplication'));
    final builder = _code(_slice(
        cfRaw, 'function srvBuildAttendancePolicySnapshot(', '\n/**'));
    final resolver = _code(_slice(
        cfRaw, 'function srvEffectiveAttendanceRules(', '\n/**'));

    test('SNAP-1 확정이 snapshot 을 만든다', () {
      expect(confirm.contains('srvBuildAttendancePolicySnapshot('), isTrue);
      expect(confirm.contains('attendancePolicySnapshot'), isTrue);
    });

    test('SNAP-2 7개 숫자를 그대로 복사한다', () {
      for (final k in [
        'earlyWindow', 'earlyArrivalUnit', 'lateGrace', 'lateUnit',
        'lateWindow', 'overtimeUnit', 'earlyLeaveUnit',
      ]) {
        expect(builder.contains('$k:'), isTrue, reason: '$k 누락');
      }
      // 계산하지 않는다 — 복사만 한다.
      for (final forbidden in ['Math.ceil', 'Math.floor', 'Math.trunc']) {
        expect(builder.contains(forbidden), isFalse,
            reason: 'snapshot 은 반올림하지 않는다');
      }
    });

    test('SNAP-3 capturedAt 이 있다', () {
      expect(builder.contains('capturedAt'), isTrue);
      expect(builder.contains('serverTimestamp()'), isTrue,
          reason: '클라이언트 시각을 쓰지 않는다');
    });

    test('SNAP-4 재확정이 snapshot 을 덮지 않는다', () {
      expect(confirm.contains('if (fd["attendancePolicySnapshot"] == null) {'),
          isTrue, reason: '멱등 재호출이 약속을 바꾸면 안 된다');
    });

    test('SNAP-5 출근이 snapshot 을 쓴다', () {
      final ci = _code(_callable(cfRaw, 'callableCheckIn'));
      expect(ci.contains('srvEffectiveAttendanceRules(appData, bizSnap.data())'),
          isTrue);
      // live 규칙을 직접 집어 쓰는 경로가 남아 있으면 안 된다.
      expect(ci.contains('bizSnap.data()?.attendanceRules'), isFalse);
    });

    test('SNAP-6 퇴근이 snapshot 을 쓴다', () {
      final co = _code(_callable(cfRaw, 'callableCheckOut'));
      // 대입 형태까지 고정한다 — 호출만 남겨 두고 값은 live 로 바꾸는 변형이
      //   실제로 빠져나갔다.
      expect(co.contains('serverCheckoutRules = srvEffectiveAttendanceRules('),
          isTrue);
      // 퇴근 본문에 사업장 규칙을 직접 집는 경로가 아예 없어야 한다.
      expect(co.contains('attendanceRules'), isFalse,
          reason: '출근과 퇴근이 다른 기준을 쓰면 같은 근무에 두 정책이 생긴다');
    });

    test('SNAP-7 관리자 batch 도 snapshot 을 쓴다', () {
      final bci = _code(_callable(cfRaw, 'callableBatchCheckIn'));
      expect(bci.contains('srvEffectiveAttendanceRules('), isTrue);
      expect(bci.contains('batchCheckInBizData?.attendanceRules'), isFalse,
          reason: 'self 와 admin 이 다른 정책으로 판정하면 안 된다');
    });

    test('SNAP-8 legacy fallback 은 분리돼 있다', () {
      // snapshot 이 있으면 그것을, 없으면 live — 그 순서여야 한다.
      final iSnap = resolver.indexOf('attendancePolicySnapshot');
      final iLive = resolver.indexOf('attendanceRules');
      expect(iSnap, greaterThan(-1));
      expect(iSnap, lessThan(iLive),
          reason: 'live 를 먼저 보면 snapshot 이 무의미하다');
      expect(resolver.contains('return snap as AttendanceRulesData'), isTrue);
    });

    test('SNAP-9 snapshot 은 서버가 만든다', () {
      // 확정 payload 에 정책이 들어올 자리가 없어야 한다.
      final destructure = _slice(confirm, 'const {', '} = ');
      expect(destructure.contains('attendanceRules'), isFalse);
      expect(destructure.contains('policy'), isFalse);
      // 트랜잭션 안에서 읽은 사업장 문서를 쓴다 — 어느 시점인지 결정적이다.
      expect(confirm.contains('srvBuildAttendancePolicySnapshot(cfmBizSnap.data())'),
          isTrue);
    });

    test('SNAP-10 반올림 계산식 변경 0', () {
      // 이 Phase 는 정책을 고정할 뿐 계산을 바꾸지 않는다.
      final ci = _code(_slice(cfRaw, 'function _processCheckin(', '\n/**'));
      expect(ci.contains('Math.ceil(offsetMinutes / lateUnit) * lateUnit'),
          isTrue);
      expect(ci.contains('offsetMinutes <= lateGrace'), isTrue);
      final co = _code(_slice(cfRaw, 'function _processCheckout(', '\n/**'));
      expect(co.contains('Math.floor(offsetMinutes / overtimeUnit) * overtimeUnit'),
          isTrue);
      expect(co.contains('Math.ceil(earlyDiff / earlyLeaveUnit)'), isTrue);
    });
  });
}
