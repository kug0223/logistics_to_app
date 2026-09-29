// [CONTRACT-PERIOD-RULE] v2 전환 — 혼합 버전과 전환 순서.
//
//   저장소는 v2 인데 **배포된 CF 는 v1** 이다(확인 근거는
//   `docs/r7-contract-monthend-audit.md` 의 전환 절). 앱과 CF 의 버전이
//   다른 동안 어떤 조합에서 날짜가 어긋나는지를 수치로 고정한다.
//
//   ruleVersion 문자열로 구별하지 않는다. **앱이 실제로 보내는 instant** 와
//   **서버가 그 instant 로 계산하는 값**을 그대로 재현해서 잇는다.
//
//     앱 v1: 달력 선택값 `DateTime(y,m,d)` 의 millis  → 기기 로컬 자정
//     앱 v2: `kstMidnightOfKstDay(kstDayKeyOfCivil(…))` → KST 자정
//     CF v1: instant 의 **UTC 성분**에 `setMonth/setDate`, `-1일`·clamp 없음
//     CF v2: instant → KST 달력일, 민법 160②③, 결과는 KST 자정
//
//   CF 는 확정 때 클라이언트가 보낸 종료일을 쓰지 않는다([M2-FIX]) —
//   `desiredStartDate` 로 **다시 계산**한다. 그래서 확정 날짜를 정하는 것은
//   **CF 버전**이고, 앱 버전은 (ㄱ) 지원자가 본 날짜와 (ㄴ) 기산 instant 를
//   정한다. 이 비대칭이 전환 순서를 결정한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/contract_period.dart';
import 'package:ALfit/utils/format_helper.dart';

const _kstMs = 9 * 60 * 60 * 1000;

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), isTrue, reason: '$p 를 찾지 못함');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

/// instant → KST 달력일 문자열. 화면·계약서·효력이 읽는 자.
String _kd(DateTime v) => FormatHelper.formatDateISO(v);

DateTime _ms(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

// ── 앱이 보내는 기산 instant ──────────────────────────────────────
int _appV1Start(int y, int m, int d, int tzHours) =>
    DateTime.utc(y, m, d).millisecondsSinceEpoch - tzHours * 3600000;
int _appV2Start(int y, int m, int d) =>
    FormatHelper.kstMidnightOfKstDay(DateTime.utc(y, m, d))
        .millisecondsSinceEpoch;

// ── 앱이 화면에 보여 주고 PENDING 으로 저장하는 종료일 ─────────────
int _appV1End(int y, int m, int d, int tzHours, String type) {
  if (type == '15days') {
    return DateTime.utc(y, m, d + 14).millisecondsSinceEpoch -
        tzHours * 3600000;
  }
  final months = const {'1month': 1, '3months': 3, '6months': 6, '1year': 12}[type]!;
  final raw = m + months;
  final ty = y + (raw - 1) ~/ 12;
  final tm = ((raw - 1) % 12) + 1;
  final last = DateTime.utc(ty, tm + 1, 0).day;
  final td = d < last ? d : last; // clamp
  return DateTime.utc(ty, tm, td).millisecondsSinceEpoch -
      tzHours * 3600000 -
      Duration.millisecondsPerDay; // -1일
}

int _appV2End(int y, int m, int d, String type) =>
    contractPeriodEndInstant(DateTime.utc(y, m, d), type)!
        .millisecondsSinceEpoch;

// ── CF 가 확정 때 계산해 덮어쓰는 값 ───────────────────────────────
int _cfV1End(int startMs, String type) {
  final s = _ms(startMs); // UTC 성분으로 조작 (setMonth/setDate 재현)
  switch (type) {
    case '15days':
      return DateTime.utc(s.year, s.month, s.day + 15, s.hour, s.minute)
          .millisecondsSinceEpoch;
    case '1month':
      return DateTime.utc(s.year, s.month + 1, s.day, s.hour, s.minute)
          .millisecondsSinceEpoch;
    case '3months':
      return DateTime.utc(s.year, s.month + 3, s.day, s.hour, s.minute)
          .millisecondsSinceEpoch;
    case '6months':
      return DateTime.utc(s.year, s.month + 6, s.day, s.hour, s.minute)
          .millisecondsSinceEpoch;
    case '1year':
      return DateTime.utc(s.year + 1, s.month, s.day, s.hour, s.minute)
          .millisecondsSinceEpoch;
  }
  throw ArgumentError(type);
}

int _cfV2End(int startMs, String type) {
  // 서버 v2: instant → KST 달력일 → 규칙 → KST 자정
  final kstDay = FormatHelper.toKstDate(_ms(startMs));
  return contractPeriodEndInstant(kstDay, type)!.millisecondsSinceEpoch;
}

void main() {
  // ══════════════════════════════════════════════════════════════
  // CPX-A. 배포 경계 — 저장소 v2, 빌드 산출물 v1
  // ══════════════════════════════════════════════════════════════
  group('CPX-A. 배포 경계', () {
    test('CPX-A1 저장소 소스는 v2 다', () {
      final cf = _src('functions/src/index.ts');
      expect(cf.contains('contractPeriodEndMs(startTs.toMillis(), periodType)'),
          isTrue);
      expect(cf.contains('d.setMonth(d.getMonth() + 1)'), isFalse);
    });

    test('CPX-A2 빌드 산출물이 v2 다 — 배포된 것이 이것이다', () {
      // [R7-P4.2 갱신] 이 셀은 배포 **전에** 쓰였고 그때는 맞았다 —
      //   "산출물은 아직 v1 이고 새 모듈은 컴파일된 적도 없다".
      //   그 뒤 표준 빌드로 lib 을 새로 만들고 `callableConfirmApplication`
      //   하나를 DEV 에 배포했다(소스 업로드 2026-09-29T07:02Z).
      //   그래서 기대를 **현재 사실로 옮긴다** — 셀을 지우지 않는다.
      //   지키는 성질은 그대로다: `firebase deploy` 가 올리는 것은 소스가
      //   아니라 **이 산출물**이므로, 산출물에서 규칙을 확인한다.
      final lib = File('functions/lib/index.js');
      if (!lib.existsSync()) {
        markTestSkipped('functions/lib 미빌드 — 배포 산출물 없음');
        return;
      }
      final js = lib.readAsStringSync();
      expect(js.contains('contractPeriodEndMs'), isTrue,
          reason: '컴파일된 확정 핸들러가 규칙 모듈을 부른다');
      for (final gone in const [
        'setMonth(d.getMonth() + 1)',
        'setFullYear(d.getFullYear() + 1)',
        'setDate(d.getDate() + 15)',
      ]) {
        expect(js.contains(gone), isFalse, reason: '산출물에 v1 식 잔존: $gone');
      }
      final mod = File('functions/lib/contract_period.js');
      expect(mod.existsSync(), isTrue, reason: 'v2 모듈이 컴파일돼 있다');
      expect(mod.readAsStringSync().contains('v2-kst-civil-160'), isTrue);
    });

    test('CPX-A3 클라이언트는 규칙 버전을 선언해 보내지 않는다', () {
      // 서버가 클라이언트 선언을 믿을 여지를 만들지 않는다.
      final svc = _src('lib/services/firestore/application_firestore.dart');
      expect(svc.contains('ruleVersion'), isFalse);
      expect(svc.contains('kContractPeriodRuleVersion'), isFalse);
      // 버전은 **서버가** 계산 결과에 붙인다.
      final cf = _src('functions/src/index.ts');
      expect(
          cf.contains('batchUpdate.workEndDateRuleVersion = '
              'CONTRACT_PERIOD_RULE_VERSION;'),
          isTrue);
    });

    test('CPX-A4 지원 시각은 서버가 찍는다 — 구/신 지원서를 서버가 가른다', () {
      final cf = _src('functions/src/index.ts');
      expect(
          cf.contains('appliedAt: admin.firestore.FieldValue.serverTimestamp()'),
          isTrue,
          reason: '클라이언트가 위조할 수 없는 생성 시점');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CPX-B. 혼합 버전 표 — 제시 날짜 vs 확정 날짜
  // ══════════════════════════════════════════════════════════════
  group('CPX-B. 앱 × CF 조합', () {
    // [라벨, y, m, d, 기간, 앱v1+CFv1, 앱v1+CFv2, 앱v2+CFv1, 앱v2+CFv2]
    //   각 칸은 '제시|확정'. 같으면 약속이 지켜진 것이다.
    const rows = <List<Object>>[
      ['1일+15days', 2026, 1, 1, '15days',
        '2026-01-15|2026-01-16', '2026-01-15|2026-01-15',
        '2026-01-15|2026-01-16', '2026-01-15|2026-01-15'],
      ['1일+1month', 2026, 1, 1, '1month',
        '2026-01-31|2026-02-01', '2026-01-31|2026-01-31',
        '2026-01-31|2026-02-01', '2026-01-31|2026-01-31'],
      ['1일+1year', 2026, 1, 1, '1year',
        '2026-12-31|2027-01-01', '2026-12-31|2026-12-31',
        '2026-12-31|2027-01-01', '2026-12-31|2026-12-31'],
      ['평년 1/31', 2026, 1, 31, '1month',
        '2026-02-27|2026-03-03', '2026-02-27|2026-02-28',
        '2026-02-28|2026-03-03', '2026-02-28|2026-02-28'],
      ['윤년 1/31', 2028, 1, 31, '1month',
        '2028-02-28|2028-03-02', '2028-02-28|2028-02-29',
        '2028-02-29|2028-03-02', '2028-02-29|2028-02-29'],
      ['월중 5/15', 2026, 5, 15, '1month',
        '2026-06-14|2026-06-15', '2026-06-14|2026-06-14',
        '2026-06-14|2026-06-15', '2026-06-14|2026-06-14'],
    ];

    for (final r in rows) {
      final label = r[0] as String;
      final y = r[1] as int, m = r[2] as int, d = r[3] as int;
      final type = r[4] as String;

      test('CPX-B $label — 네 조합', () {
        // 기기는 KST 로 둔다(표준 사례). 동쪽 기기는 CPX-C 에서 본다.
        const tz = 9;
        final pairs = <String, String>{
          '앱v1+CFv1': '${_kd(_ms(_appV1End(y, m, d, tz, type)))}'
              '|${_kd(_ms(_cfV1End(_appV1Start(y, m, d, tz), type)))}',
          '앱v1+CFv2': '${_kd(_ms(_appV1End(y, m, d, tz, type)))}'
              '|${_kd(_ms(_cfV2End(_appV1Start(y, m, d, tz), type)))}',
          '앱v2+CFv1': '${_kd(_ms(_appV2End(y, m, d, type)))}'
              '|${_kd(_ms(_cfV1End(_appV2Start(y, m, d), type)))}',
          '앱v2+CFv2': '${_kd(_ms(_appV2End(y, m, d, type)))}'
              '|${_kd(_ms(_cfV2End(_appV2Start(y, m, d), type)))}',
        };
        expect(pairs['앱v1+CFv1'], r[5], reason: '현행');
        expect(pairs['앱v1+CFv2'], r[6], reason: 'CF 만 먼저 전환');
        expect(pairs['앱v2+CFv1'], r[7], reason: '앱 만 먼저 전환');
        expect(pairs['앱v2+CFv2'], r[8], reason: '전환 완료');
      });
    }

    test('CPX-B0 조합별 약속 이행 건수 — 전환 순서를 이것이 정한다', () {
      const tz = 9;
      int kept(String app, String cf) {
        var n = 0;
        for (final r in rows) {
          final y = r[1] as int, m = r[2] as int, d = r[3] as int;
          final type = r[4] as String;
          final start = app == 'v1' ? _appV1Start(y, m, d, tz) : _appV2Start(y, m, d);
          final presented =
              app == 'v1' ? _appV1End(y, m, d, tz, type) : _appV2End(y, m, d, type);
          final confirmed = cf == 'v1' ? _cfV1End(start, type) : _cfV2End(start, type);
          if (_kd(_ms(presented)) == _kd(_ms(confirmed))) n++;
        }
        return n;
      }

      expect(kept('v1', 'v1'), 0, reason: '현행 — 6표본 전부 어긋난다');
      expect(kept('v2', 'v1'), 0,
          reason: '앱만 먼저 바꾸면 **나아지는 표본이 하나도 없다**');
      expect(kept('v1', 'v2'), 4,
          reason: 'CF 만 먼저 바꾸면 6 중 4 가 즉시 맞는다(월말 2건만 남는다)');
      expect(kept('v2', 'v2'), 6, reason: '전환 완료');
    });

    test('CPX-B1 CF 만 먼저 전환했을 때 남는 차이는 월말뿐이고 1일이다', () {
      const tz = 9;
      for (final r in rows) {
        final y = r[1] as int, m = r[2] as int, d = r[3] as int;
        final type = r[4] as String;
        final presented = _appV1End(y, m, d, tz, type);
        final confirmed = _cfV2End(_appV1Start(y, m, d, tz), type);
        final gap = FormatHelper.toKstDate(_ms(confirmed))
            .difference(FormatHelper.toKstDate(_ms(presented)))
            .inDays;
        expect(gap, inInclusiveRange(0, 1),
            reason: '${r[0]} — 현행 최대 4일 차가 0~1일로 줄어든다');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CPX-C. 동쪽 기기 — 기산일 자체가 밀린다
  // ══════════════════════════════════════════════════════════════
  group('CPX-C. 기기 시간대', () {
    test('CPX-C1 앱 v1 은 UTC+13 에서 기산일을 하루 앞당겨 보낸다', () {
      // 서버가 KST 로 읽는 날이 달라진다 → CF 버전과 무관하게 틀어진다.
      expect(_kd(_ms(_appV1Start(2026, 1, 31, 9))), '2026-01-31');
      expect(_kd(_ms(_appV1Start(2026, 1, 31, 0))), '2026-01-31');
      expect(_kd(_ms(_appV1Start(2026, 1, 31, 13))), '2026-01-30',
          reason: '동쪽 기기에서 기산일이 밀린다');
    });

    test('CPX-C2 앱 v2 는 어느 기기에서도 같은 기산일을 보낸다', () {
      final v2 = _kd(_ms(_appV2Start(2026, 1, 31)));
      expect(v2, '2026-01-31');
      // v2 는 기기 오프셋을 인자로 받지 않는다 — 성분만 쓴다.
      final svc = _src('lib/services/firestore/application_firestore.dart');
      expect(svc.contains('FormatHelper.kstMidnightOfKstDay('), isTrue);
      expect(svc.contains('FormatHelper.kstDayKeyOfCivil(desiredStartDate)'),
          isTrue);
    });

    test('CPX-C3 이 축은 CF 전환만으로는 닫히지 않는다 — 앱 전환이 필요하다', () {
      // CF v2 라도 기산 instant 가 이미 밀려 있으면 그 날짜로 계산한다.
      final start13 = _appV1Start(2026, 1, 31, 13);
      expect(_kd(_ms(_cfV2End(start13, '1month'))), '2026-02-28',
          reason: '1/30 기산 → 160③ 으로 2/28');
      final start9 = _appV2Start(2026, 1, 31);
      expect(_kd(_ms(_cfV2End(start9, '1month'))), '2026-02-28');
      // 종료일은 우연히 같지만 **기산일이 다르다** — 계약서 시작일이 틀어진다.
      expect(_kd(_ms(start13)) == _kd(_ms(start9)), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CPX-D. 구 PENDING 처리 — 서버가 스스로 판별한다
  // ══════════════════════════════════════════════════════════════
  group('CPX-D. 수정 전 PENDING', () {
    test('CPX-D1 서버는 클라이언트 선언 없이 차이를 본다', () {
      final cf = _src('functions/src/index.ts');
      // 저장된 제시값과 새로 계산한 값의 **KST 달력일**을 비교한다.
      expect(
          cf.contains('if (presented && '
              'srvKstDayStartMs(presented.toMillis()) !== endMs) {'),
          isTrue);
      // 같은 날의 다른 시각(기기 자정 vs KST 자정)은 변경이 아니다.
    });

    test('CPX-D2 같은 KST 날이면 instant 가 달라도 정정으로 세지 않는다', () {
      // 앱 v1(KST 기기)과 앱 v2 는 월중 기산에서 **같은 날**을 제시한다.
      //   instant 는 같지만, 다른 오프셋 기기였다면 달랐을 수 있다.
      final v1 = _appV1End(2026, 5, 15, 9, '1month');
      final v2 = _appV2End(2026, 5, 15, '1month');
      expect(_kd(_ms(v1)), _kd(_ms(v2)));
      // → CF v2 에서 이 건은 고지가 뜨지 않는다(정상 대조).
    });

    test('CPX-D3 월말 구 PENDING 은 CF v2 에서 반드시 고지된다', () {
      for (final d in const [29, 30, 31]) {
        final presented = _appV1End(2026, 1, d, 9, '1month');
        final confirmed = _cfV2End(_appV1Start(2026, 1, d, 9), '1month');
        expect(_kd(_ms(presented)) == _kd(_ms(confirmed)), isFalse,
            reason: '1/$d — 제시 ${_kd(_ms(presented))} vs 확정 '
                '${_kd(_ms(confirmed))}');
      }
    });

    test('CPX-D4 제시값을 지우지 않고 보관한다', () {
      final cf = _src('functions/src/index.ts');
      expect(cf.contains('batchUpdate.workEndDatePresentedAtApply ='), isTrue);
      expect(cf.contains('batchUpdate.workEndDateRevisedAt ='), isTrue);
      // 응답에 누구의 지원서인지도 담는다.
      expect(cf.contains('applicantName:'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CPX-E. 롤백 경계
  // ══════════════════════════════════════════════════════════════
  group('CPX-E. 롤백', () {
    test('CPX-E1 롤백은 기존 서명 계약을 재계산하지 않는다', () {
      // 계약서 종료일은 스냅샷 문자열이고 어디서도 다시 쓰지 않는다.
      final model = _src('lib/models/core/employment_contract_model.dart');
      expect(model.contains("'contractEnd': contractEnd,"), isTrue);
      final svc = _src('lib/services/contract_service.dart');
      expect(svc.contains('computeContractEndDate'), isFalse);
      for (final f in Directory('functions/src').listSync().whereType<File>()) {
        expect(f.readAsStringSync().contains('snapshot.contractEnd ='), isFalse);
      }
    });

    test('CPX-E2 CF 를 v1 으로 되돌리면 v2 앱의 약속이 다시 깨진다', () {
      // 이것이 롤백의 실제 비용이다. 서버 쪽에 보호 장치를 둘 수 없다 —
      // 되돌린 코드에는 그 장치가 없기 때문이다.
      const tz = 9;
      var broken = 0;
      for (final d in const [1, 15, 29, 30, 31]) {
        final presented = _appV2End(2026, 1, d, '1month');
        final confirmed = _cfV1End(_appV2Start(2026, 1, d), '1month');
        if (_kd(_ms(presented)) != _kd(_ms(confirmed))) broken++;
      }
      expect(broken, 5, reason: '앱 v2 + CF v1 은 전 표본에서 어긋난다');
      expect(tz, 9);
    });
  });
}
