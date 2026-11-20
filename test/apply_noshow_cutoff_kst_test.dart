// [E1-CUTOFF] 취소가 **노쇼 상당**인지, 화면과 서버가 같은 시각으로 판단한다.
//
// ── canonical (서버) ──────────────────────────────────────────────────
//   `callableCancelConfirmedApplication`:
//
//     scheduledStartMs = workDate.toMillis() + (hh * 60 + mm) * 60000
//     noShowEquivalent = Date.now() >= scheduledStartMs - 5 * 60 * 1000
//
//   `workDate.toMillis()` 는 **KST 자정 instant** 다(저장 관례).
//   넘으면 `SAME_DAY_CANCEL`, 아니면 `USER_CANCELED` 로 기록된다.
//
// ── 재현된 결함 ───────────────────────────────────────────────────────
//   화면(`apply_work_dialog`)은 `FormatHelper.toKstDate(workDate)` 가
//   돌려주는 `DateTime.utc(y, m, d)` — 즉 **UTC 자정** — 에 근무 시각을
//   더했다. 그래서 근무 시작이 실제보다 **9시간 늦게** 잡혔고, 이 오차는
//   기기 시간대와 무관하게 **항상** 생긴다.
//
//   결과: KST `시작-5분` 부터 `시작+8시간55분` 사이에 취소하면
//   서버는 노쇼로 기록하는데 화면은 `확정이 취소되었습니다` 라고만 했다.
//   사용자는 노쇼 1회가 쌓인 것을 모른다.
//
// 이 파일은 KST 기본 환경과 `TZ=UTC` 양쪽에서 통과해야 한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/services/schedule_conflict_service.dart';
import 'package:ALfit/utils/format_helper.dart';

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp(
          {String? name, FirebaseOptions? options}) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

late final ScheduleConflictService _svc;

/// 근무일 2026-10-15 (KST 달력일 키) — 저장 관례와 같은 `DateTime.utc(y,m,d)`.
final DateTime _workDate = DateTime.utc(2026, 10, 15);

/// 서버와 **같은 식**으로 계산한 기대 경계.
///   KST 자정 instant = utc(y,m,d) - 9h. 거기에 시각을 더한다.
DateTime _serverStart(String hhmm) {
  final p = hhmm.split(':');
  return _workDate
      .subtract(const Duration(hours: 9))
      .add(Duration(hours: int.parse(p[0]), minutes: int.parse(p[1])));
}

bool? _ask(String startTime, DateTime now) => _svc.isNoShowEquivalentCancel(
      workDate: _workDate,
      startTime: startTime,
      now: now,
    );

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    _svc = ScheduleConflictService();
  });
  group('[NC-A] 경계가 서버와 같은 instant 다', () {
    test('NC-1 16:00 근무의 시작 instant 는 KST 16:00 (= UTC 07:00)', () {
      final start = FormatHelper.kstWallClockInstant(_workDate, '16:00');
      expect(start!.toUtc().toIso8601String(), '2026-10-15T07:00:00.000Z');
      expect(start, _serverStart('16:00'),
          reason: '서버 workDate.toMillis() + 분 과 같은 값이어야 한다');
    });

    test('NC-2 [재현] 옛 식은 9시간 늦었다', () {
      // 예전 화면 계산: toKstDate(workDate) 에 시각을 그대로 더함.
      final old = FormatHelper.toKstDate(_workDate)
          .add(const Duration(hours: 16));
      expect(old.difference(_serverStart('16:00')),
          const Duration(hours: 9),
          reason: '이 9시간이 사용자가 모르고 노쇼를 쌓던 창이다');
    });
  });

  group('[NC-B] 5분 전 경계 — 서버 연산자(>=)와 일치', () {
    final start = _serverStart('16:00');
    final cutoff = start.subtract(const Duration(minutes: 5));

    test('NC-3 cutoff 1초 전 → 패널티 아님', () {
      expect(_ask('16:00', cutoff.subtract(const Duration(seconds: 1))), isFalse);
    });

    test('NC-4 cutoff 정각 → 패널티 (>= 이므로 포함)', () {
      expect(_ask('16:00', cutoff), isTrue);
    });

    test('NC-5 cutoff 1초 후 → 패널티', () {
      expect(_ask('16:00', cutoff.add(const Duration(seconds: 1))), isTrue);
    });

    test('NC-6 [재현] 근무 시작 직후 — 옛 식이 "패널티 없음"이라 답하던 시점',
        () {
      final justStarted = start.add(const Duration(minutes: 1));
      expect(_ask('16:00', justStarted), isTrue,
          reason: '서버는 이미 SAME_DAY_CANCEL 로 기록한다');
      // 옛 식이었다면 아직 cutoff 전이라 false 였다.
      final oldCutoff = FormatHelper.toKstDate(_workDate)
          .add(const Duration(hours: 16))
          .subtract(const Duration(minutes: 5));
      expect(justStarted.isBefore(oldCutoff), isTrue,
          reason: '옛 식의 창이 실재했음을 고정한다');
    });

    test('NC-7 근무 한참 전 → 패널티 아님', () {
      expect(_ask('16:00', start.subtract(const Duration(hours: 5))), isFalse);
    });
  });

  group('[NC-C] 기기 시간대와 무관하다', () {
    test('NC-8 같은 instant 를 어떤 표현으로 줘도 같은 답', () {
      final start = _serverStart('16:00');
      final probe = start.add(const Duration(minutes: 1));
      expect(_ask('16:00', probe.toUtc()), isTrue);
      expect(_ask('16:00', probe.toLocal()), isTrue);
      expect(
          _ask('16:00',
              DateTime.fromMillisecondsSinceEpoch(probe.millisecondsSinceEpoch)),
          isTrue);
    });

    test('NC-9 경계 자체가 기기 시간대를 타지 않는다', () {
      // 어떤 환경에서 돌려도 UTC 07:00 이라는 절대 시각이다.
      expect(FormatHelper.kstWallClockInstant(_workDate, '16:00')!.toUtc(),
          DateTime.utc(2026, 10, 15, 7));
    });
  });

  group('[NC-D] 날짜 경계와 심야 근무', () {
    test('NC-10 KST 00:30 근무 — UTC 로는 전날이어도 그 날 근무다', () {
      final start = FormatHelper.kstWallClockInstant(_workDate, '00:30')!;
      expect(start.toUtc().toIso8601String(), '2026-10-14T15:30:00.000Z');
      expect(start, _serverStart('00:30'));
      expect(_ask('00:30', start.subtract(const Duration(minutes: 10))), isFalse);
      expect(_ask('00:30', start.subtract(const Duration(minutes: 4))), isTrue);
    });

    test('NC-11 KST 23:00 시작(익일 종료) — 시작 기준만 본다', () {
      final start = _serverStart('23:00');
      expect(_ask('23:00', start.subtract(const Duration(minutes: 6))), isFalse);
      expect(_ask('23:00', start.add(const Duration(hours: 2))), isTrue,
          reason: '종료 시각은 이 판정에 들어가지 않는다');
    });

    test('NC-12 KST 자정 정각 근무', () {
      final start = FormatHelper.kstWallClockInstant(_workDate, '00:00')!;
      expect(start, FormatHelper.kstMidnightOfKstDay(_workDate));
      expect(start, _serverStart('00:00'));
    });
  });

  group('[NC-E] 시각을 못 읽으면 단정하지 않는다', () {
    test('NC-13 형식 오류는 null — 호출부가 fallback 을 쓴다', () {
      final now = DateTime.utc(2026, 10, 15, 7);
      expect(_ask('', now), isNull);
      expect(_ask('abc', now), isNull);
      expect(_ask('16', now), isNull);
      expect(_ask('24:00', now), isNull);
      expect(_ask('16:99', now), isNull);
    });

    test('NC-14 fallback(shouldApplyPenalty)은 날짜 단위 보수 판정이다', () {
      // 넓게 잡는 쪽이라 사용자를 위험에 빠뜨리지 않는다.
      expect(_svc.shouldApplyPenalty(DateTime.utc(2000, 1, 1)), isTrue);
      expect(
          _svc.shouldApplyPenalty(
              DateTime.now().add(const Duration(days: 30))),
          isFalse);
    });
  });

  group('[NC-F] 소스 계약', () {
    test('NC-15 화면이 서버와 같은 식 하나를 호출한다', () {
      final src = File('lib/widgets/dialogs/apply/apply_work_dialog.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code.contains('isNoShowEquivalentCancel'), isTrue);
      expect(
          code.contains("FormatHelper.toKstDate(workDateForPenalty)\n"),
          isFalse,
          reason: 'UTC 자정에 근무 시각을 더하던 계산이 남아 있으면 안 된다');
    });

    test('NC-17 취소 확인창도 같은 식을 쓴다', () {
      // 사용자가 **취소 전에** 경고를 보는 지점이다. 여기가 9시간 늦으면
      //   노쇼가 기록되는 줄 모른 채 결정하게 된다.
      final src = File('lib/widgets/dialogs/apply/confirm_cancel_dialog.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code.contains('isNoShowEquivalentCancel'), isTrue);
      expect(code.contains('workDay.add(Duration(hours: hh, minutes: mm))'),
          isFalse,
          reason: 'UTC 자정에 근무 시각을 더하던 계산');
      // 시각을 못 읽을 때의 당일 fallback 은 그대로 남는다.
      expect(code.contains('workDay.isAtSameMomentAs(today)'), isTrue);
    });

    test('NC-16 서버 정책·writer 는 건드리지 않았다', () {
      final svc = File('lib/services/schedule_conflict_service.dart')
          .readAsStringSync();
      // 이 서비스는 제재 상태를 **읽기만** 한다(restrictedUntil 조회).
      //   쓰기·정책 값 생성은 서버 몫이다.
      for (final banned in [
        'noShowCount',
        'SAME_DAY_CANCEL',
        'restrictedUntil:',
        '.set(',
        '.update(',
      ]) {
        expect(svc.contains(banned), isFalse, reason: banned);
      }
    });
  });
}
