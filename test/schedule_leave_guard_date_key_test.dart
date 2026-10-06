// [R7-CROSSCUT-TIME.1B] 휴무 승인 guard 가 보는 날짜는 **KST 근무일 D** 하나다.
//
// ── 질문 ────────────────────────────────────────────────────────────────
//   관리자가 10/5 휴무를 승인하려 할 때, 관리자 기기의 timezone 이 무엇이든
//   ALfit 은 항상 10/5 의 attendance 만 확인해서, 이미 10/5 에 출근한 근로자의
//   휴무 승인을 잘못 허용하지 않는가?
//
// ── 실제 구조 (READ 결과) ───────────────────────────────────────────────
//   금지 변경을 막는 권위는 **서버**다.
//     `callableApproveScheduleChangeRequest` 는 승인 트랜잭션 안에서
//     `targetDate.toMillis() + 9h` → `getUTC*` 로 KST 날짜 키를 만들고,
//     `attendance/{applicationId}_{YYYYMMDD}` 를 `tx.get` 으로 읽은 뒤
//     `checkIn != null` 이면 `failed-precondition` 으로 던진다.
//     instant 기반이므로 호출자 기기·런타임 timezone 과 무관하다.
//
//   클라이언트의 사전조회(`createScheduleChangeRequest` 의 LEAVE 분기)는
//   예전에 `targetDate.year/.month/.day` 를 그대로 썼다. 모델 파서가
//   `toLocal()` 이므로 비-KST 기기에서는 하루 어긋난 문서를 조회한다.
//   다만 그 분기는 `LEAVE + APPLICANT` 조합에서만 동작하고, 그 조합을 만드는
//   production 코드가 없다(호출부 둘 다 ADMIN · EXTRA_WORK/NO_WORK).
//   그래서 금지 변경은 발생하지 않는다 — CORRECTION 이다.
//
// ── 이 파일이 고정하는 것 ───────────────────────────────────────────────
//   · 날짜 키는 **instant 의 함수**다. 같은 순간이면 어떤 표현을 줘도 같은 키.
//   · 서버 키 ≡ 클라이언트 키 ≡ attendance writer 키 (한 포맷, zero padding).
//   · 식을 복제하지 않는다 — Dart 쪽 canonical owner 는 `formatDateStamp`.
//   · 출근기록이 있는 날의 휴무 승인은 서버가 막는다(read-before-write).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/format_helper.dart';

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('없는 파일: $p');
  return f.readAsStringSync();
}

const _kFn = 'functions/src/index.ts';
const _kAttSvc = 'lib/services/firestore/attendance_firestore.dart';
const _kScrModel = 'lib/models/core/schedule_change_request_model.dart';
const _kFixedDlg =
    'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart';

/// 서버가 쓰는 식을 그대로 옮긴 것 — 비교 기준(oracle).
///   `new Date(ts.toMillis() + KST_OFFSET_MS)` 뒤 `getUTC*` + zero padding.
String _serverKey(DateTime instant) {
  final kst = instant.toUtc().add(const Duration(hours: 9));
  return '${kst.year}'
      '${kst.month.toString().padLeft(2, '0')}'
      '${kst.day.toString().padLeft(2, '0')}';
}

/// 패치 **전** 클라이언트 식 — 기기 로컬 성분을 그대로 쓴다(결함 재현용).
String _legacyLocalKey(DateTime t) =>
    '${t.year}'
    '${t.month.toString().padLeft(2, '0')}'
    '${t.day.toString().padLeft(2, '0')}';

/// 기기 timezone 이 [offsetHours] 인 기기가 `toLocal()` 한 값에서 **읽게 되는
/// 달력 성분**. 프로세스 TZ 를 바꾸지 않고도 재현할 수 있다 — 로컬 성분은
/// `instant + offset` 의 UTC 성분과 같기 때문이다.
///
/// 주의: 이 값은 "성분 모델"이다. 실제 `toLocal()` 결과는 **같은 instant** 를
/// 로컬 flag 로만 돌려주므로, `toUtc()` 로 다시 정규화하는 식(=패치 후)에는
/// 이 모델을 먹이면 오프셋이 두 번 적용된다. 성분을 그대로 읽는 식(=패치 전)
/// 에만 쓴다.
DateTime _deviceComponents(DateTime instant, int offsetHours) =>
    instant.toUtc().add(Duration(hours: offsetHours));

/// 같은 instant 의 여러 표현. 어떤 기기에서 와도 `toUtc()` 가 같은 순간을
/// 복원하므로, instant 만 보는 식은 이 모두에 같은 답을 내야 한다.
List<DateTime> _sameInstantForms(DateTime instant) => [
      instant,
      instant.toUtc(),
      instant.toLocal(), // 실제 기기가 쥐는 모양 (isUtc == false)
      DateTime.fromMillisecondsSinceEpoch(instant.millisecondsSinceEpoch),
      DateTime.fromMillisecondsSinceEpoch(instant.millisecondsSinceEpoch,
          isUtc: true),
    ];

/// KST 달력일 D 의 자정 instant (= 전날 15:00Z).
DateTime _kstMidnight(int y, int m, int d) =>
    DateTime.utc(y, m, d).subtract(const Duration(hours: 9));

/// 관리자 다이얼로그가 저장하는 DATE_ONLY 비교 키 (= UTC 자정).
DateTime _dateOnlyKey(int y, int m, int d) => DateTime.utc(y, m, d);

void main() {
  // 테스트 환경 사실을 먼저 적어 둔다 — 결론의 등급을 과장하지 않기 위해.
  setUpAll(() {
    final off = DateTime.now().timeZoneOffset.inHours;
    // ignore: avoid_print
    print('[환경] host timeZoneOffset = ${off}h '
        '(${off == 9 ? "KST" : "비KST"}) — 아래 기기 TZ 는 값으로 재현한다');
  });

  // ══ S1~S5 기기 timezone 매트릭스 ════════════════════════════════════════
  group('SLG-S 기기 timezone 매트릭스 — 같은 D, 같은 키', () {
    // §13 최소 매트릭스 + 양/음 오프셋 확장.
    const devices = <String, int>{
      'Asia/Seoul': 9,
      'UTC': 0,
      'America/Los_Angeles': -7,
      'Pacific/Midway': -11,
      'Pacific/Kiritimati': 14,
      'Asia/Kolkata': 5, // 반시간 오프셋의 정수부
    };

    void matrix(String id, int y, int m, int d) {
      test('$id ${y}-$m-$d — 키는 instant 의 함수다', () {
        final expected = '${y}'
            '${m.toString().padLeft(2, '0')}'
            '${d.toString().padLeft(2, '0')}';

        // 저장 관례 두 가지 모두 — KST 자정 instant / DATE_ONLY 비교 키.
        for (final instant in [_kstMidnight(y, m, d), _dateOnlyKey(y, m, d)]) {
          expect(_serverKey(instant), expected,
              reason: '서버 키가 D 를 벗어났다: $instant');
          // 같은 순간의 어떤 표현을 줘도 같은 키 — 기기 TZ 가 바꿀 수 있는 것은
          //   flag 와 성분뿐이고, 이 식은 성분을 읽지 않는다.
          for (final form in _sameInstantForms(instant)) {
            expect(FormatHelper.formatDateStamp(form), expected,
                reason: '표현이 바뀌자 키가 달라졌다: $form (isUtc=${form.isUtc})');
            expect(FormatHelper.formatDateStamp(form), _serverKey(instant),
                reason: '서버와 키가 갈렸다: $form');
          }
        }
      });

      test('$id ${y}-$m-$d — 패치 전 식은 기기별로 갈린다', () {
        final expected = '${y}'
            '${m.toString().padLeft(2, '0')}'
            '${d.toString().padLeft(2, '0')}';
        final instant = _kstMidnight(y, m, d);
        final keys = <String, String>{};
        for (final e in devices.entries) {
          keys[e.key] =
              _legacyLocalKey(_deviceComponents(instant, e.value));
        }
        // KST 기기만 맞는다 — 나머지는 다른 날을 가리킨다.
        expect(keys['Asia/Seoul'], expected);
        expect(keys['UTC'], isNot(expected));
        expect(keys['America/Los_Angeles'], isNot(expected));
        expect(keys.values.toSet().length, greaterThan(1),
            reason: '기기에 따라 키가 갈리지 않으면 결함 재현이 아니다');
      });
    }

    // S1·S2·S3 — §12 의 통제 타임스탬프 (2026-10-05 00:00 KST = 10-04 15:00 UTC)
    matrix('S1~S3', 2026, 10, 5);
    // S4 — 월 경계
    matrix('S4', 2026, 11, 1);
    // S5 — 연 경계
    matrix('S5', 2027, 1, 1);
    // 경계 보강 — 윤년 2/29, 월말
    matrix('S5b', 2028, 2, 29);
    matrix('S5c', 2026, 12, 31);

    test('S3b 분 단위 오프셋 기기의 성분도 재현한다 — 패치 전 식만 흔들린다', () {
      final instant = _kstMidnight(2026, 10, 5);
      for (final mins in [-660, -570, -480, -210, 0, 210, 330, 345, 840]) {
        final comp = instant.toUtc().add(Duration(minutes: mins));
        // 패치 후 식은 성분을 읽지 않으므로 instant 만 본다.
        expect(FormatHelper.formatDateStamp(instant), '20261005');
        if (mins < 540) {
          expect(_legacyLocalKey(comp), isNot('20261005'),
              reason: 'offset ${mins}분 기기에서 패치 전 식은 전날을 가리킨다');
        }
      }
      // +14h(키리바시)는 반대로 다음 날을 가리킨다.
      expect(
          _legacyLocalKey(instant.toUtc().add(const Duration(hours: 14))),
          '20261005',
          reason: 'KST 자정 +14h 는 같은 날 05:00 — 날이 넘지 않는다');
      expect(
          _legacyLocalKey(_dateOnlyKey(2026, 10, 5)
              .toUtc()
              .add(const Duration(hours: 14))),
          '20261005');
    });
  });

  // ══ 결함 재현 — 패치 전 식은 기기 TZ 에 끌려간다 ═══════════════════════
  group('SLG-D 결함 재현 (패치 전 식)', () {
    test('D1 UTC·음수 오프셋 기기에서 하루 어긋난 키가 나온다', () {
      // §12 통제 타임스탬프: 2026-10-05 00:00 KST
      final instant = _kstMidnight(2026, 10, 5);
      expect(_serverKey(instant), '20261005');

      // KST 기기 — 우연히 맞는다.
      expect(_legacyLocalKey(_deviceComponents(instant, 9)), '20261005');
      // UTC 기기 — §15 의 재현 조건.
      expect(_legacyLocalKey(_deviceComponents(instant, 0)), '20261004');
      // 음수 오프셋 — 더 크게 밀린다.
      expect(_legacyLocalKey(_deviceComponents(instant, -7)), '20261004');
      expect(_legacyLocalKey(_deviceComponents(instant, -11)), '20261004');
    });

    test('D2 패치 후 식은 성분을 읽지 않는다 — 양성 대조', () {
      // 관리자 다이얼로그가 저장하는 DATE_ONLY 키에서도, KST 자정 instant 에서도
      //   같은 답이다. 그리고 같은 순간의 어떤 표현이든 같다.
      for (final instant in [
        _kstMidnight(2026, 10, 5),
        _dateOnlyKey(2026, 10, 5),
      ]) {
        for (final form in _sameInstantForms(instant)) {
          expect(FormatHelper.formatDateStamp(form), '20261005');
        }
      }
    });

    test('D2b 식이 로컬 성분을 읽지 않는다는 것은 구조로도 참이다', () {
      final fh = _read('lib/utils/format_helper.dart');
      final i = fh.indexOf('static String formatDateStamp(DateTime date) {');
      expect(i, greaterThan(-1));
      final body = fh.substring(i, fh.indexOf('\n  }', i));
      // 먼저 instant 로 정규화한다 — 그 뒤의 성분은 KST 성분이다.
      expect(body.contains('_toKst(date)'), isTrue);
      expect(body.contains('date.year'), isFalse);
      expect(body.contains('date.month'), isFalse);
      expect(body.contains('date.day'), isFalse);
      expect(body.contains('toLocal()'), isFalse);
      // `_toKst` 자체가 toUtc() 로 시작한다.
      expect(fh.contains('static DateTime _toKst(DateTime dt) => dt.toUtc().add(_kst);'),
          isTrue);
    });

    test('D3 패치 전 식이 소스에 남아 있지 않다', () {
      final svc = _read(_kAttSvc);
      // 날짜 키를 로컬 성분으로 조립하는 식 — attendance docId 경로에 0.
      expect(svc.contains("'\${t.year}\${t.month.toString().padLeft(2, '0')}"),
          isFalse);
      expect(
          svc.contains(
              "'\${d.year}\${d.month.toString().padLeft(2, '0')}\${d.day.toString().padLeft(2, '0')}'"),
          isFalse,
          reason: 'getTodayAttendance 의 복제 식도 제거됐다');
      // canonical helper 로 수렴.
      expect(svc.contains('FormatHelper.formatDateStamp(request.targetDate)'),
          isTrue);
      expect(
          svc.contains(
              "'\${applicationId}_\${FormatHelper.formatDateStamp(date)}'"),
          isTrue);
    });
  });

  // ══ S6~S12 attendance 문서 identity ════════════════════════════════════
  group('SLG-I attendance 문서 identity', () {
    String docId(String appId, DateTime instant) =>
        '${appId}_${FormatHelper.formatDateStamp(instant)}';

    test('S6 D 의 문서를 정확히 가리킨다', () {
      expect(docId('app1', _kstMidnight(2026, 10, 5)), 'app1_20261005');
    });

    test('S7 D-1 문서를 D 로 착각하지 않는다', () {
      final d = docId('app1', _kstMidnight(2026, 10, 5));
      final dPrev = docId('app1', _kstMidnight(2026, 10, 4));
      expect(dPrev, 'app1_20261004');
      expect(d, isNot(dPrev));
    });

    test('S8 D+1 문서도 구별된다', () {
      final d = docId('app1', _kstMidnight(2026, 10, 5));
      final dNext = docId('app1', _kstMidnight(2026, 10, 6));
      expect(dNext, 'app1_20261006');
      expect(d, isNot(dNext));
    });

    test('S11 같은 D 라도 다른 Application 끼리 충돌하지 않는다', () {
      final a = docId('appA', _kstMidnight(2026, 10, 5));
      final b = docId('appB', _kstMidnight(2026, 10, 5));
      expect(a, isNot(b));
      expect(a.endsWith('_20261005'), isTrue);
      expect(b.endsWith('_20261005'), isTrue);
    });

    test('S12 같은 Application 의 다른 D 끼리 충돌하지 않는다', () {
      final ids = <String>{};
      for (var i = 1; i <= 31; i++) {
        ids.add(docId('appA', _kstMidnight(2026, 10, i)));
      }
      expect(ids.length, 31);
    });

    test('S12b 키 포맷은 writer 와 같다 — zero padding 있음', () {
      // 1월 5일이 `202615` 가 되면 `2026-01-05` 와 `2026-1-5` 가 섞인다.
      expect(FormatHelper.formatDateStamp(_kstMidnight(2026, 1, 5)), '20260105');
      expect(FormatHelper.formatDateStamp(_kstMidnight(2026, 1, 5)).length, 8);
      // 서버 writer 들도 padStart(2, "0") 를 쓴다.
      final fn = _read(_kFn);
      expect(
          RegExp(r'padStart\(2, "0"\)').allMatches(fn).length,
          greaterThanOrEqualTo(6),
          reason: 'attendance 키 생성 지점들이 모두 zero padding 한다');
    });
  });

  // ══ S9·S10 guard 의 판단 기준 — 서버 소스 계약 ══════════════════════════
  group('SLG-G 서버 guard', () {
    late String guard;

    setUpAll(() {
      final fn = _read(_kFn);
      final i = fn.indexOf('// [LEAVE-GUARD]');
      expect(i, greaterThan(-1), reason: 'LEAVE-GUARD 블록을 찾지 못했다');
      // 고정 길이로 자르면 이웃 코드까지 들어온다 — 끝 마커로 경계를 조인다.
      final e = fn.indexOf('// 요청 상태 업데이트', i);
      expect(e, greaterThan(i), reason: 'guard 의 끝 경계를 찾지 못했다');
      guard = fn.substring(i, e);
    });

    test('G1 guard 의 날짜 키는 canonical owner 하나에서 온다', () {
      // [R7-CROSSCUT-TIME.1B] 식을 이 자리에서 다시 조립하지 않는다 —
      //   writer 와 같은 helper 를 쓴다. 줄 전체를 고정해야 `- 86400000`
      //   같은 오프셋 혼입을 잡는다(부분문자열 pin 은 통과시킨다).
      expect(
          guard.contains(
              'const leaveDateStr = srvKstDateKey(targetDateTs.toDate());'),
          isTrue);
      // 인라인 조립의 흔적이 남지 않았다.
      //   `targetDateTs` 안에 `getDate` 가 부분문자열로 들어 있으므로
      //   메서드 호출 형태로 본다.
      expect(guard.contains('KST_OFFSET_MS'), isFalse);
      expect(guard.contains('padStart'), isFalse);
      expect(guard.contains('.getUTC'), isFalse);
      expect(guard.contains('.getFullYear('), isFalse);
      expect(guard.contains('.getMonth('), isFalse);
      expect(guard.contains('.getDate('), isFalse);
      // 날짜에 산술을 더하지 않는다 — D 는 D 다.
      expect(guard.contains('86400000'), isFalse);
      expect(RegExp(r'toDate\(\)\s*\.\s*set').hasMatch(guard), isFalse);
    });

    test('G1b canonical owner 는 instant → KST 성분이다', () {
      final fn = _read(_kFn);
      expect(
          fn.contains('function srvKstDateKey(d: Date): string {\r\n'
              '  return String(srvKstDateNum(d));\r\n}') ||
              fn.contains('function srvKstDateKey(d: Date): string {\n'
                  '  return String(srvKstDateNum(d));\n}'),
          isTrue,
          reason: 'srvKstDateKey 의 본문이 바뀌었다');
      // srvKstDateNum → commitment_dates.kstDateNum (순수 모듈, getUTC* 기반)
      expect(fn.contains('function srvKstDateNum(d: Date): number {'), isTrue);
      final cd = _read('functions/src/commitment_dates.ts');
      final i = cd.indexOf('export function kstDateNum(');
      expect(i, greaterThan(-1));
      final body = cd.substring(i, cd.indexOf('\n}', i));
      expect(body.contains('KST_OFFSET_MS'), isTrue);
      expect(body.contains('getUTCFullYear()'), isTrue);
      expect(body.contains('getUTCMonth()'), isTrue);
      expect(body.contains('getUTCDate()'), isTrue);
      // 런타임 로컬 성분을 쓰지 않는다.
      expect(RegExp(r'[^C]getFullYear\(\)').hasMatch(body), isFalse);
      expect(RegExp(r'[^C]getMonth\(\)').hasMatch(body), isFalse);
      expect(RegExp(r'[^C]getDate\(\)').hasMatch(body), isFalse);
    });

    test('G2 문서 id 는 applicationId + 그 날짜다', () {
      expect(
          guard.contains(
              'db.collection("attendance").doc(`\${scrData.applicationId as string}_\${leaveDateStr}`)'),
          isTrue);
    });

    test('S10 checkIn 이 있으면 승인을 막는다', () {
      // 조건문 줄 전체를 고정한다 — `if (false && ...)` 처럼 문자열은 남고
      //   실행만 꺼지는 변경을 존재 검사로는 잡을 수 없다.
      expect(
          guard.contains(
              'if (attSnap.exists && attSnap.data()?.checkIn != null) {'),
          isTrue);
      expect(guard.contains('if (false'), isFalse);
      expect(guard.contains('if (0'), isFalse);
      expect(guard.contains('&& false'), isFalse);
      expect(
          guard.contains(
              'throw new HttpsError("failed-precondition", "이미 출근한 날짜는 휴무/미출근 처리를 할 수 없습니다.")'),
          isTrue);
      // guard 와 throw 사이에 다른 조건이 끼지 않는다.
      const cond = 'if (attSnap.exists && attSnap.data()?.checkIn != null) {';
      final between = guard.substring(
          guard.indexOf(cond) + cond.length, guard.indexOf('throw new HttpsError'));
      expect(between.contains('if ('), isFalse);
      expect(between.contains('return'), isFalse);
    });

    test('S9 문서가 없거나 checkIn 이 null 이면 기존 결과 그대로다', () {
      // `exists && checkIn != null` 이므로 두 경우 모두 통과한다 — 이번
      //   Phase 에서 정책을 새로 만들지 않는다.
      expect(guard.contains('attSnap.exists &&'), isTrue);
      expect(guard.contains('checkIn == null'), isFalse);
      expect(guard.contains('|| !attSnap.exists'), isFalse);
    });

    test('G3 guard 는 LEAVE·NO_WORK 에만 적용된다 — EXTRA_WORK 정책 무변경', () {
      expect(
          guard.contains(
              'if (requestTypeEarly === "LEAVE" || requestTypeEarly === "NO_WORK")'),
          isTrue);
      expect(guard.contains('EXTRA_WORK'), isFalse,
          reason: 'EXTRA_WORK 에 guard 를 새로 붙이지 않는다');
    });

    test('G4 읽기는 트랜잭션 안, 첫 쓰기보다 앞이다', () {
      final fn = _read(_kFn);
      final i = fn.indexOf('export const callableApproveScheduleChangeRequest');
      final body = fn.substring(i, i + 14000);
      final txAt = body.indexOf('await db.runTransaction(async (tx) => {');
      final readAt = body.indexOf('const attSnap = await tx.get(attRef);');
      final writeAt = body.indexOf('tx.update(requestRef, updateData);');
      expect(txAt, greaterThan(-1));
      expect(readAt, greaterThan(txAt), reason: '트랜잭션 밖 조회면 경쟁과 직렬화되지 않는다');
      expect(writeAt, greaterThan(readAt), reason: 'read-before-write');
    });

    test('G5 권한 guard 를 건드리지 않았다', () {
      final fn = _read(_kFn);
      final i = fn.indexOf('export const callableApproveScheduleChangeRequest');
      final body = fn.substring(i, i + 14000);
      // 식별자 경계까지 고정한다 — `canManageWorkersXX` 로 바꿔치기해도
      //   부분문자열 검사는 통과한다.
      expect(RegExp(r'\bcanManageWorkers\b').hasMatch(body), isTrue);
      expect(body.contains('canManageWorkersXX'), isFalse);
    });
  });

  // ══ 도달 가능성 — 왜 BLOCKER 가 아닌가 ═════════════════════════════════
  group('SLG-R 도달 가능성', () {
    test('R1 LEAVE+APPLICANT 를 만드는 production 코드가 없다', () {
      final svc = _read(_kAttSvc);
      // 사전조회는 그 조합에서만 동작한다.
      expect(svc.contains('request.requestType == RequestType.LEAVE &&'), isTrue);
      expect(svc.contains('request.requestedBy == RequesterType.APPLICANT'),
          isTrue);
      // 호출부는 둘뿐이고 둘 다 ADMIN 이다.
      final dlg = _read(_kFixedDlg);
      final calls = RegExp(r'createScheduleChangeRequest\(request\)')
          .allMatches(dlg)
          .length;
      expect(calls, 2);
      expect(dlg.contains('requestType: RequestType.EXTRA_WORK'), isTrue);
      expect(dlg.contains('requestType: RequestType.NO_WORK'), isTrue);
      expect(dlg.contains('requestType: RequestType.LEAVE'), isFalse);
      expect(RegExp(r'requestedBy: RequesterType\.ADMIN').allMatches(dlg).length,
          2);
      expect(dlg.contains('requestedBy: RequesterType.APPLICANT'), isFalse);
    });

    test('R2 모델 파서가 toLocal() 이라는 사실을 기록한다', () {
      // 이것이 결함의 원천이었다. 이번 Phase 에서 파서를 바꾸지 않는다 —
      //   표시 경로(formatDateLong/formatDateKorean)는 instant 기반이라
      //   안전하고, 날짜 키 경로만 helper 로 수렴시켰다.
      final m = _read(_kScrModel);
      expect(m.contains("(map['targetDate'] as Timestamp?)?.toDate().toLocal()"),
          isTrue,
          reason: '파서는 이번 범위가 아니다 — 사실만 고정한다');
    });

    test('R3 서버가 금지 변경을 막으므로 클라이언트 단독 guard 가 아니다', () {
      final fn = _read(_kFn);
      expect(fn.contains('// [LEAVE-GUARD]'), isTrue);
      expect(fn.contains('"이미 출근한 날짜는 휴무/미출근 처리를 할 수 없습니다."'), isTrue);
      // 승인은 CF 단일 입구다 — 클라이언트가 배열을 직접 쓰지 않는다.
      final svc = _read(_kAttSvc);
      expect(svc.contains("httpsCallable('callableApproveScheduleChangeRequest')"),
          isTrue);
      expect(svc.contains("'leaveDates': "), isFalse,
          reason: '클라이언트가 leaveDates 를 직접 쓰면 서버 guard 를 우회한다');
    });

    test('R4 leaveDates·extraWorkDates semantics 무변경', () {
      final fn = _read(_kFn);
      final i = fn.indexOf('export const callableApproveScheduleChangeRequest');
      final body = fn.substring(i, i + 14000);
      // LEAVE/NO_WORK → leaveDates 추가 + 같은 날 extraWorkDates 제거(상호배타).
      //   LEAVE 와 EXTRA_WORK 두 분기가 **각각** 두 배열을 함께 쓴다 —
      //   존재 검사만 하면 한쪽이 빠져도 통과한다(§28).
      expect(
          RegExp(r'tx\.update\(appRef, \{leaveDates, extraWorkDates\}\);')
              .allMatches(body)
              .length,
          2,
          reason: '상호배타 갱신이 두 분기 모두에 있어야 한다');
      expect(body.contains('parseDates("extraWorkDates")'), isTrue);
      expect(body.contains('parseDates("leaveDates")'), isTrue);
      // 취소 분기는 한쪽만 손댄다 — 그 비대칭도 그대로 둔다.
      expect(body.contains('tx.update(appRef, {leaveDates});'), isTrue);
      expect(body.contains('tx.update(appRef, {extraWorkDates});'), isTrue);
    });
  });
}
