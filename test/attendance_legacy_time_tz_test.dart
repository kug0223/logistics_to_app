// [R7-CROSSCUT-TIME.1D] AttendanceModel 의 legacy v1 시간 branch —
// 같은 근무일 D 를 기기 시간대와 무관하게 복원하는가.
//
// ── 무엇을 보는가 ───────────────────────────────────────────────────────
//   `AttendanceModel._parseTimeField` 는 `checkIn`/`checkOut` 이 **문자열**
//   ("H:mm"/"HH:mm"/"HH:mm:ss")일 때 `workDate` 를 기준으로 시각을 복원한다.
//   그 복원이 이렇게 되어 있다.
//
//     final wd = workDateRaw.toDate().toLocal();
//     return DateTime(wd.year, wd.month, wd.day, h, m);
//
//   `toLocal()` 은 instant 를 보존하고 flag 만 로컬로 바꾼다. 그런데 그 뒤의
//   `.year/.month/.day` 는 **기기 로컬 달력 성분**이고, `DateTime(...)` 는
//   **기기 로컬 생성자**다. 그래서 비-KST 기기에서는
//     ① 근무일이 D-1/D+1 로 밀리고,
//     ② 표시용 getter(`checkIn`)가 `toUtc().add(9h)` 로 KST 시각을 뽑기 때문에
//        **시각까지** 함께 밀린다.
//
//   예: workDate = 2026-10-05 KST 자정, checkIn = "09:00"
//       · KST 기기 → 2026-10-05 09:00 KST  → getter "09:00"  (정상)
//       · UTC 기기 → 2026-10-04 09:00 UTC  → getter "18:00"  (날짜·시각 둘 다)
//
// ── 이 파일을 어떻게 쓰는가 ─────────────────────────────────────────────
//   아래 legacy 셀들은 **의도된 불변식**을 적는다 — "문자열 시각은 canonical
//   KST 근무일 위에서 복원된다". 호스트가 KST 인 평소 스위트에서는 통과한다.
//   비-KST 로 돌리면 실패하고, 그 실패가 곧 결함 재현이다:
//
//     TZ=UTC   flutter test test/attendance_legacy_time_tz_test.dart
//     TZ=PST8  flutter test test/attendance_legacy_time_tz_test.dart
//
//   (Windows 의 Dart 는 IANA 이름을 무시하고 POSIX 형식만 받는다.
//    `KST-9`=UTC+9, `UTC`=0, `PST8`=UTC-8, `IST-5`=UTC+5, `NUT11`=UTC-11.
//    부호가 뒤집혀 있다 — 양수가 그리니치 서쪽이다.)
//
// ── 도달성 ──────────────────────────────────────────────────────────────
//   이 branch 는 현재 도달하지 않는다. 서버의 모든 attendance 시각 쓰기는
//   Timestamp 이고, Dart 에는 attendance 쓰기 경로가 아예 없다. 그래서
//   이 파일은 **수정 없이** 계약과 도달성을 함께 고정한다.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/attendance_model.dart';

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('없는 파일: $p');
  return f.readAsStringSync();
}

const _kModel = 'lib/models/core/attendance_model.dart';
const _kFn = 'functions/src/index.ts';
const _kAttSvc = 'lib/services/firestore/attendance_firestore.dart';

/// KST 달력일 D 의 자정 instant — 서버 writer 가 `workDate` 로 저장하는 모양.
DateTime _kstMidnight(int y, int m, int d) =>
    DateTime.utc(y, m, d).subtract(const Duration(hours: 9));

/// KST 벽시계 시각의 절대 instant — 기대값을 TZ 무관하게 적기 위한 표현.
DateTime _kstInstant(int y, int m, int d, int hh, int mm) =>
    DateTime.utc(y, m, d, hh, mm).subtract(const Duration(hours: 9));

/// 최소 attendance map. 시간 필드만 바꿔 끼운다.
Map<String, dynamic> _row({
  required DateTime workDate,
  Object? checkIn,
  Object? checkOut,
  Object? originalCheckIn,
  Object? originalCheckOut,
}) =>
    <String, dynamic>{
      'applicationId': 'app1',
      'userId': 'u1',
      'businessId': 'biz1',
      'businessName': '사업장',
      'workType': '홀서빙',
      'workDate': Timestamp.fromDate(workDate),
      if (checkIn != null) 'checkIn': checkIn,
      if (checkOut != null) 'checkOut': checkOut,
      if (originalCheckIn != null) 'originalCheckIn': originalCheckIn,
      if (originalCheckOut != null) 'originalCheckOut': originalCheckOut,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    };

void main() {
  setUpAll(() {
    final off = DateTime.now().timeZoneOffset.inMinutes;
    // ignore: avoid_print
    print('[환경] host offset = ${off}분 '
        '(${off == 540 ? "KST" : "비KST — legacy 셀이 결함을 재현한다"})');
  });

  // ══ V1~V6 · V12 legacy 문자열 — canonical KST 근무일 위에서 복원 ════════
  group('ALT-V legacy 문자열 시각', () {
    void legacy(String id, int y, int m, int d, String time, int hh, int mm) {
      test('$id "$time" + workDate ${y}-$m-$d → KST 같은 날 같은 시각', () {
        final a = AttendanceModel.fromMap(
            _row(workDate: _kstMidnight(y, m, d), checkIn: time), 'att1');
        expect(a.checkInAt, isNotNull);
        // instant 로 비교한다 — 표현(flag)이 아니라 순간이 계약이다.
        expect(a.checkInAt!.toUtc(), _kstInstant(y, m, d, hh, mm).toUtc(),
            reason: '복원된 순간이 KST ${y}-$m-$d $time 이 아니다');
        // 표시용 getter 도 같은 벽시계여야 한다.
        expect(a.checkIn,
            '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}');
        // workDate 자체는 instant 라 흔들리지 않는다.
        expect(a.workDate.toUtc(), _kstMidnight(y, m, d).toUtc());
      });
    }

    legacy('V1', 2026, 10, 5, '09:00', 9, 0);
    legacy('V2', 2026, 10, 5, '23:30', 23, 30);
    legacy('V2b', 2026, 10, 5, '9:05', 9, 5); // H:mm (한 자리 시)
    legacy('V2c', 2026, 10, 5, '09:05:30', 9, 5); // HH:mm:ss
    legacy('V2d', 2026, 10, 5, '00:00', 0, 0); // KST 자정 — 경계
    legacy('V4', 2026, 11, 1, '09:00', 9, 0); // §55 월 경계
    legacy('V4b', 2026, 10, 31, '23:59', 23, 59);
    legacy('V5', 2027, 1, 1, '09:00', 9, 0); // §56 연 경계
    legacy('V5b', 2026, 12, 31, '23:00', 23, 0);
    legacy('V6', 2028, 2, 29, '09:00', 9, 0); // §57 윤일

    test('V12 canonical workDate 의 달력일이 보존된다', () {
      final a = AttendanceModel.fromMap(
          _row(workDate: _kstMidnight(2026, 10, 5), checkIn: '09:00'), 'att1');
      // 복원된 순간을 KST 로 보면 그 날이어야 한다.
      final kst = a.checkInAt!.toUtc().add(const Duration(hours: 9));
      expect([kst.year, kst.month, kst.day], [2026, 10, 5]);
    });

    test('V3 야간교대 — 퇴근이 출근보다 이르면 익일로 보정 (§54 기존 정책)', () {
      final a = AttendanceModel.fromMap(
          _row(
            workDate: _kstMidnight(2026, 10, 5),
            checkIn: '22:00',
            checkOut: '06:00',
          ),
          'att1');
      expect(a.checkInAt!.toUtc(), _kstInstant(2026, 10, 5, 22, 0).toUtc());
      expect(a.checkOutAt!.toUtc(), _kstInstant(2026, 10, 6, 6, 0).toUtc());
      // 근무 길이는 8시간 — 상대 관계는 보정으로 지켜진다.
      expect(a.checkOutAt!.difference(a.checkInAt!), const Duration(hours: 8));
    });

    test('V3b originalCheckOut 도 같은 보정을 받는다', () {
      final a = AttendanceModel.fromMap(
          _row(
            workDate: _kstMidnight(2026, 10, 5),
            checkIn: '22:00',
            originalCheckIn: '22:00',
            checkOut: '06:00',
            originalCheckOut: '05:30',
          ),
          'att1');
      expect(a.originalCheckOutAt!.toUtc(),
          _kstInstant(2026, 10, 6, 5, 30).toUtc());
    });
  });

  // ══ V7·V8 잘못된 입력 — 현재 계약 유지 ═════════════════════════════════
  group('ALT-E 입력 오류', () {
    test('V7 깨진 문자열은 null 이다 — 오늘로 추측하지 않는다', () {
      for (final bad in ['', 'abc', '09', '0900', ':::', '9:', 'ab:cd',
        '09-00', 'null']) {
        final a = AttendanceModel.fromMap(
            _row(workDate: _kstMidnight(2026, 10, 5), checkIn: bad), 'att1');
        expect(a.checkInAt, isNull, reason: '깨진 입력 "$bad" 가 값을 만들었다');
      }
    });

    test('V7b 범위를 벗어난 시/분은 현재 계약대로 처리된다', () {
      // 현재 parser 는 범위 검사를 하지 않는다 — DateTime 이 넘침을 흘린다.
      //   이번 Phase 에서 정책을 새로 만들지 않는다(§40). 사실만 고정한다.
      final a = AttendanceModel.fromMap(
          _row(workDate: _kstMidnight(2026, 10, 5), checkIn: '25:00'), 'att1');
      expect(a.checkInAt, isNotNull);
      expect(a.checkInAt!.toUtc(), _kstInstant(2026, 10, 6, 1, 0).toUtc(),
          reason: '25:00 은 다음 날 01:00 으로 넘친다 (현재 동작)');
    });

    test('V8 null 시간은 null 이다', () {
      final a = AttendanceModel.fromMap(
          _row(workDate: _kstMidnight(2026, 10, 5)), 'att1');
      expect(a.checkInAt, isNull);
      expect(a.checkOutAt, isNull);
      expect(a.checkIn, isNull);
      expect(a.hasCheckedIn, isFalse);
    });

    test('V8b workDate 가 없으면 문자열을 복원할 근거가 없다', () {
      // workDate 누락은 모델 자체가 거부한다(§39 — 추측하지 않는다).
      expect(
          () => AttendanceModel.fromMap(
              <String, dynamic>{'checkIn': '09:00'}, 'att1'),
          throwsArgumentError);
    });
  });

  // ══ V9·V10·V11 modern 경로와 혼합 ══════════════════════════════════════
  group('ALT-M modern Timestamp 경로', () {
    test('V9 Timestamp row 는 기기 시간대와 무관하다 (§60·§73)', () {
      final instant = _kstInstant(2026, 10, 5, 9, 0);
      final a = AttendanceModel.fromMap(
          _row(
            workDate: _kstMidnight(2026, 10, 5),
            checkIn: Timestamp.fromDate(instant),
            checkOut: Timestamp.fromDate(_kstInstant(2026, 10, 5, 18, 0)),
          ),
          'att1');
      // instant 를 그대로 보존한다 — `toLocal()` 은 flag 만 바꾼다.
      expect(a.checkInAt!.toUtc(), instant.toUtc());
      expect(a.checkIn, '09:00');
      expect(a.checkOut, '18:00');
      expect(a.checkOutAt!.difference(a.checkInAt!), const Duration(hours: 9));
    });

    test('V9b CF 응답 Map 형식도 instant 를 보존한다', () {
      final instant = _kstInstant(2026, 10, 5, 9, 0);
      final a = AttendanceModel.fromMap(
          _row(
            workDate: _kstMidnight(2026, 10, 5),
            checkIn: {
              '_seconds': instant.millisecondsSinceEpoch ~/ 1000,
              '_nanoseconds': 0,
            },
          ),
          'att1');
      expect(a.checkInAt!.toUtc(), instant.toUtc());
      expect(a.checkIn, '09:00');
    });

    test('V9c Timestamp 야간교대도 보정 없이 그대로다', () {
      // 절대 instant 이므로 `isBefore` 보정이 걸리지 않는다.
      final a = AttendanceModel.fromMap(
          _row(
            workDate: _kstMidnight(2026, 10, 5),
            checkIn: Timestamp.fromDate(_kstInstant(2026, 10, 5, 22, 0)),
            checkOut: Timestamp.fromDate(_kstInstant(2026, 10, 6, 6, 0)),
          ),
          'att1');
      expect(a.checkOutAt!.difference(a.checkInAt!), const Duration(hours: 8));
    });

    test('V10 혼합 row — 한쪽 Timestamp / 한쪽 문자열', () {
      // 스키마가 막지 않으므로 가능하다. 두 branch 가 같은 날을 말해야 한다.
      final a = AttendanceModel.fromMap(
          _row(
            workDate: _kstMidnight(2026, 10, 5),
            checkIn: Timestamp.fromDate(_kstInstant(2026, 10, 5, 9, 0)),
            checkOut: '18:00',
          ),
          'att1');
      expect(a.checkInAt!.toUtc(), _kstInstant(2026, 10, 5, 9, 0).toUtc());
      expect(a.checkOutAt!.toUtc(), _kstInstant(2026, 10, 5, 18, 0).toUtc());
      expect(a.checkOutAt!.difference(a.checkInAt!), const Duration(hours: 9));
    });

    test('V11 modern 경로의 결과는 표현에 무관하다', () {
      final instant = _kstInstant(2026, 10, 5, 9, 0);
      final forms = <Object>[
        Timestamp.fromDate(instant),
        Timestamp.fromDate(instant.toUtc()),
        Timestamp.fromDate(instant.toLocal()),
        Timestamp.fromMillisecondsSinceEpoch(instant.millisecondsSinceEpoch),
      ];
      for (final f in forms) {
        final a = AttendanceModel.fromMap(
            _row(workDate: _kstMidnight(2026, 10, 5), checkIn: f), 'att1');
        expect(a.checkInAt!.toUtc(), instant.toUtc());
        expect(a.checkIn, '09:00');
      }
    });
  });

  // ══ 도달성 — 왜 지금 BLOCKER 가 아닌가 ════════════════════════════════
  group('ALT-R 도달성', () {
    test('R1 legacy branch 는 기기 로컬 성분으로 복원한다 (결함 구조)', () {
      final m = _read(_kModel);
      expect(
          m.contains("return DateTime(wd.year, wd.month, wd.day, h, m);"),
          isTrue,
          reason: '결함 구조가 바뀌었다면 이 Phase 의 판정을 다시 해야 한다');
      // 그 base 가 `toLocal()` 로 만들어진다.
      expect(m.contains('? workDateRaw.toDate().toLocal()'), isTrue);
      // 표시용 formatter 는 KST instant 기준이다 — 그래서 시각까지 밀린다.
      expect(
          m.contains('final kst = dt.toUtc().add(_kst);'), isTrue);
    });

    test('R2 Dart 에는 attendance 쓰기 경로가 없다 (§10·§11)', () {
      final svc = _read(_kAttSvc);
      // 이 파일이 attendance 컬렉션을 만지는 두 자리는 모두 읽기다.
      final touches = RegExp(r"collection\('attendance'\)").allMatches(svc).length;
      expect(touches, 2);
      // 두 자리 모두 `.get()` 으로 끝난다 — 들여쓰기에 기대지 않는다.
      for (final mt in RegExp(r"collection\('attendance'\)")
          .allMatches(svc)) {
        final tail = svc.substring(mt.end, (mt.end + 200).clamp(0, svc.length));
        expect(tail.contains('.get()'), isTrue, reason: '읽기가 아닌 자리: $tail');
      }
      // 쓰기 동사가 attendance 경로에 없다.
      expect(
          RegExp(r"collection\('attendance'\)[\s\S]{0,200}?\.(set|update|add)\(")
              .hasMatch(svc),
          isFalse,
          reason: 'Dart 에서 attendance 를 쓰면 String 시간이 생길 수 있다');
    });

    test('R3 서버의 시각 쓰기는 전부 Timestamp 다 (§8·§9)', () {
      // 주석을 먼저 걷어낸다 — 설명 문장에 `checkIn=null` 같은 표현이 있다.
      final fn = _read(_kFn)
          .split(RegExp(r'\r?\n'))
          .where((l) {
            final t = l.trimLeft();
            return !t.startsWith('//') && !t.startsWith('*') &&
                !t.startsWith('/*');
          })
          .join('\n');
      // 쓰기만 센다 — `==` 비교와 구별한다.
      //   ① 객체 리터럴:  `checkIn: <값>`
      //   ② 대괄호 대입:  `["checkIn"] = <값>`
      final writes = <String>[
        ...RegExp(r'(?:^|[\s{(])\b(?:original)?[cC]heck(?:In|Out)\s*:\s*([^,\n]+)')
            .allMatches(fn)
            .map((mt) => mt.group(1)!.trim()),
        ...RegExp(r'\[\s*"(?:original)?check(?:In|Out)"\s*\]\s*=(?!=)\s*([^;\n]+)')
            .allMatches(fn)
            .map((mt) => mt.group(1)!.trim()),
      ];
      expect(writes, isNotEmpty);
      for (final v in writes) {
        final ok = v.contains('Timestamp') ||
            v.contains('FieldValue.delete()') ||
            v.contains('checkInTs') ||
            v.contains('checkOutTs') ||
            v.startsWith('data.') ||
            v.startsWith('null');
        expect(ok, isTrue, reason: '문자열 시각을 쓸 수 있는 자리: $v');
      }
      // 문자열 리터럴 시각 쓰기 0.
      expect(RegExp(r'check(In|Out)\s*:\s*[`' "'" r'"]\d').hasMatch(fn), isFalse);
    });

    test('R4 파싱값이 급여 입력으로 흘러가는 자리를 기록한다 (§22·§43)', () {
      // 도달성이 생기면 이 자리가 영향 경로다 — 지금은 사실만 고정한다.
      final dlg = _read(
          'lib/screens/business_admin/dialogs/wage_confirm_dialog.dart');
      expect(
          dlg.contains("'actualStart': attendance.checkIn!.split(':').take(2).join(':')"),
          isTrue,
          reason: '급여 확정 입력이 파싱값에서 온다는 사실이 바뀌었다');
      expect(dlg.contains("httpsCallable('callableCalculateAndConfirmWage'"), isTrue);
    });
  });
}
