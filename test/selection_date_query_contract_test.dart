// [SYSTEM-INTEGRATION-R1.2.1] Selection date QUERY contract + applicant review least-privilege
//
// R1.2는 '표시'를 고쳤다. 남아 있던 것은 '쿼리'였다.
//
//   승인대기 캘린더 grouping key (기기 local)
//   → _openDayApplicants(date)
//   → getPendingApplicationsByDateAndBusiness
//   → DateTime(date.year, date.month, date.day)        ← 기기 local 자정
//   → workDateGteMs / workDateLtMs                     ← 서버 day-range 쿼리 입력
//
// DEV 실측 (R1-GOLDEN, canonical workDate = 2026-09-20T15:00Z = KST 9/21):
//   기기 local 자정 창 [2026-09-21T00:00Z, 2026-09-22T00:00Z)  → 0건
//   KST 영업일 창     [2026-09-20T15:00Z, 2026-09-21T15:00Z)  → 1건
//
// 즉 UTC 기기에서 9/21을 고르면 그 날 지원자가 사라진다. label 문제가 아니었다.
//
// R1.2에서 캘린더 키만 KST로 고치지 않은 이유도 여기 있다 — 키를 고치면
// 쿼리 창이 따라오지 않아 '9/21을 눌렀는데 0건'이 됐을 것이다. 두 개는 함께 고쳐야 했다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/format_helper.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _bodyOf(String source, String signature) {
  final a = source.indexOf(signature);
  if (a == -1) throw StateError('$signature 를 찾지 못함');
  final open = source.indexOf('{', a);
  if (open == -1) throw StateError('$signature 본문 시작을 찾지 못함');
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(a, i + 1);
    }
  }
  throw StateError('$signature 본문 끝을 찾지 못함');
}

/// named-parameter 메서드는 signature 뒤 첫 `{` 가 파라미터 목록이라
/// 중괄호 매칭으로는 본문을 잡을 수 없다. signature 이후 고정 길이를 본다.
String _after(String source, String signature, [int chars = 2200]) {
  final a = source.indexOf(signature);
  if (a == -1) throw StateError('$signature 를 찾지 못함');
  final end = a + chars;
  return source.substring(a, end > source.length ? source.length : end);
}

String _tsSliceOf(String source, String from, String to) {
  final a = source.indexOf(from);
  if (a == -1) throw StateError('$from 를 찾지 못함');
  final b = source.indexOf(to, a + from.length);
  if (b == -1) throw StateError('$to 를 찾지 못함');
  return source.substring(a, b);
}

const _cfPath = 'functions/src/index.ts';
const _appSvcPath = 'lib/services/firestore/application_firestore.dart';
const _attSvcPath = 'lib/services/firestore/attendance_firestore.dart';
const _calendarPath =
    'lib/screens/business_admin/dialogs/pending_approval_calendar_dialog.dart';
const _fsSvcPath = 'lib/services/firestore_service.dart';
const _queueSvcPath = 'lib/services/support_review_queue_service.dart';
const _detailPath = 'lib/widgets/dialogs/worker_detail_dialog.dart';

/// R1-GOLDEN slot/application의 실제 저장값 — KST 2026-09-21 00:00
const _goldenMs = 1789916400 * 1000;

void main() {
  // ═════════════════════════════════════════════════════════════
  // 1. KST 영업일 창 — device timezone 독립
  // ═════════════════════════════════════════════════════════════
  group('R1.2.1-01 kstDayRange', () {
    test('01-a canonical workDate를 포함하는 창을 만든다', () {
      final golden = DateTime.fromMillisecondsSinceEpoch(_goldenMs, isUtc: true);
      final (start, end) = FormatHelper.kstDayRange(golden);
      expect(start.toUtc().toIso8601String(), '2026-09-20T15:00:00.000Z');
      expect(end.toUtc().toIso8601String(), '2026-09-21T15:00:00.000Z');
      expect(!golden.isBefore(start) && golden.isBefore(end), isTrue,
          reason: 'gte <= workDate < lt 를 만족해야 한다');
    });

    test('01-b 같은 영업일을 어떤 offset으로 표현해도 같은 창', () {
      // 기기 timezone이 Seoul / UTC / LA 인 상황을 각각의 자정으로 표현한다.
      final reps = [
        DateTime.parse('2026-09-21T00:00:00+09:00'), // Asia/Seoul 자정
        DateTime.parse('2026-09-21T00:00:00Z'), // UTC 자정
        DateTime.parse('2026-09-21T00:00:00-07:00'), // America/LA 자정
        DateTime.fromMillisecondsSinceEpoch(_goldenMs, isUtc: true), // canonical
        DateTime.utc(2026, 9, 21), // 캘린더 키 정규화값
      ];
      for (final d in reps) {
        final (s, e) = FormatHelper.kstDayRange(d);
        expect(s.toUtc().toIso8601String(), '2026-09-20T15:00:00.000Z',
            reason: '$d 에서 창이 달라졌다');
        expect(e.toUtc().toIso8601String(), '2026-09-21T15:00:00.000Z');
      }
    });

    test('01-c 기기 local 자정 창은 canonical workDate를 놓친다 (회귀 증명)', () {
      // 수정 전 동작: DateTime(d.year, d.month, d.day)
      // UTC 기기에서 9/21을 고르면 [9/21T00:00Z, 9/22T00:00Z) 가 되고
      // canonical 9/20T15:00Z 는 그 밖이다 → 0건.
      final golden = DateTime.fromMillisecondsSinceEpoch(_goldenMs, isUtc: true);
      final localStart = DateTime.utc(2026, 9, 21);
      final localEnd = localStart.add(const Duration(days: 1));
      expect(!golden.isBefore(localStart) && golden.isBefore(localEnd), isFalse,
          reason: '이 창이 지원자를 놓치는 것이 BLOCKER의 실체다');
    });

    test('01-d 창은 정확히 24시간이고 인접 영업일과 겹치지 않는다', () {
      final (s1, e1) = FormatHelper.kstDayRange(DateTime.utc(2026, 9, 21));
      final (s2, e2) = FormatHelper.kstDayRange(DateTime.utc(2026, 9, 22));
      expect(e1.difference(s1), const Duration(days: 1));
      expect(e1, s2, reason: '앞 창의 끝이 뒤 창의 시작 — 빈틈도 겹침도 없다');
      expect(e2.difference(s2), const Duration(days: 1));
    });
  });

  group('R1.2.1-02 kstMonthRange', () {
    test('02-a KST 9월은 8/31 15:00Z 에서 시작한다', () {
      final (s, e) = FormatHelper.kstMonthRange(DateTime.utc(2026, 9, 15));
      expect(s.toUtc().toIso8601String(), '2026-08-31T15:00:00.000Z');
      expect(e.toUtc().toIso8601String(), '2026-09-30T15:00:00.000Z');
    });

    test('02-b KST 1일 근무가 전달로 빠지지 않는다', () {
      // KST 2026-09-01 00:00 = 2026-08-31T15:00Z
      final firstDay = DateTime.parse('2026-08-31T15:00:00Z');
      final (s, e) = FormatHelper.kstMonthRange(DateTime.utc(2026, 9, 15));
      expect(!firstDay.isBefore(s) && firstDay.isBefore(e), isTrue);
      // 기기 local(UTC) 월 창이었다면 놓쳤다
      final localStart = DateTime.utc(2026, 9, 1);
      expect(firstDay.isBefore(localStart), isTrue);
    });

    test('02-c 다음 달 1일이 끼어들지 않는다', () {
      // KST 2026-10-01 00:00 = 2026-09-30T15:00Z
      final nextFirst = DateTime.parse('2026-09-30T15:00:00Z');
      final (s, e) = FormatHelper.kstMonthRange(DateTime.utc(2026, 9, 15));
      expect(nextFirst.isBefore(e), isFalse);
      expect(nextFirst.isBefore(s), isFalse);
      // 기기 local(UTC) 월 창이었다면 포함됐다
      expect(nextFirst.isBefore(DateTime.utc(2026, 10, 1)), isTrue);
    });

    test('02-d 연 경계 — 12월 창은 다음 해 1월로 닫힌다', () {
      final (s, e) = FormatHelper.kstMonthRange(DateTime.utc(2026, 12, 10));
      expect(s.toUtc().toIso8601String(), '2026-11-30T15:00:00.000Z');
      expect(e.toUtc().toIso8601String(), '2026-12-31T15:00:00.000Z');
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 3. 쿼리가 실제로 그 창을 쓴다
  // ═════════════════════════════════════════════════════════════
  group('R1.2.1-03 day/month query', () {
    final appSvc = _codeOf(_src(_appSvcPath));
    final attSvc = _codeOf(_src(_attSvcPath));

    test('03-a 대기 지원자 일자 조회가 KST 창을 쓴다', () {
      final b = _after(
          appSvc, 'getPendingApplicationsByDateAndBusiness({', 1400);
      expect(b.contains('FormatHelper.kstDayRange(date)'), isTrue);
      expect(b.contains('DateTime(date.year, date.month, date.day)'), isFalse);
    });

    test('03-b 확정 근무자 일자 조회도 같은 창', () {
      final b = _after(appSvc, 'getConfirmedWorkersByDateAndBusinessOrThrow({', 1200);
      expect(b.contains('FormatHelper.kstDayRange(date)'), isTrue);
      expect(b.contains('DateTime(date.year, date.month, date.day)'), isFalse);
    });

    test('03-c 같은 다이얼로그의 근태 조회도 같은 창', () {
      // 지원자 쿼리만 KST로 고치고 여기를 두면 '이미 근무한 사람'이 비어
      // 확정취소 가드가 풀린다. 두 목록은 uid로 맞춰지므로 경계가 같아야 한다.
      final b = _after(attSvc, 'getAttendanceByDate({', 700);
      expect(b.contains('FormatHelper.kstDayRange(date)'), isTrue);
      expect(b.contains('DateTime(date.year, date.month, date.day)'), isFalse);
    });

    test('03-d 승인대기 월별 조회가 KST 월 창을 쓴다', () {
      final b = _after(appSvc, 'getPendingApplicationsByMonthAndBusiness({', 1500);
      expect(b.contains('FormatHelper.kstMonthRange(month)'), isTrue);
      expect(b.contains('DateTime(month.year, month.month, 1)'), isFalse);
    });

    test('03-e 서버로 나가는 값은 여전히 절대 시각 ms — 서버 계약 불변', () {
      final b = _after(appSvc, 'getPendingApplicationsByDateAndBusiness({', 1400);
      expect(b.contains("'workDateGteMs': dateStart.millisecondsSinceEpoch"), isTrue);
      expect(b.contains("'workDateLtMs': dateEnd.millisecondsSinceEpoch"), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 4. 캘린더 — 키·비교·표시가 한 기준
  // ═════════════════════════════════════════════════════════════
  group('R1.2.1-04 승인대기 캘린더', () {
    final cal = _codeOf(_src(_calendarPath));

    test('04-a 그룹 키가 KST', () {
      expect(cal.contains('FormatHelper.formatDateISO(app.workDate)'), isTrue);
      expect(cal.contains("DateFormat('yyyy-MM-dd')"), isFalse);
    });

    test('04-b 오늘/기한지남 판정이 같은 KST 키끼리 비교된다', () {
      // 전에는 키가 기기 local, todayOnly가 DateTime.utc라 서로 다른 기준끼리
      // isBefore로 비교되고 있었다.
      final stats = _bodyOf(cal, 'void _calculateStats()');
      expect(stats.contains('FormatHelper.formatDateISO(DateTime.now())'), isTrue);
      expect(stats.contains('DateTime.parse('), isFalse);
      expect(stats.contains('compareTo(todayKey) < 0'), isTrue);
    });

    test('04-c 선택한 날짜를 KST calendar date로 넘긴다', () {
      final body = _bodyOf(cal, 'Widget _buildContent(ThemeData theme)');
      expect(body.contains('DateTime.utc(parsed.year, parsed.month, parsed.day)'), isTrue);
      expect(body.contains('_openDayApplicants(date)'), isTrue);
    });

    test('04-d 날짜 라벨도 KST', () {
      expect(cal.contains('FormatHelper.formatDateCompact(date)'), isTrue);
      expect(cal.contains("DateFormat('M/d(E)'"), isFalse);
    });

    test('04-e 조회 실패를 0건으로 보여주지 않는다', () {
      expect(cal.contains('_hasLoadError'), isTrue);
      expect(cal.contains("'승인 대기 현황을 불러오지 못했어요'"), isTrue);
      // 실패 상태에서 0건 요약 카드를 띄우지 않는다
      expect(cal.contains('if (!isLoading && !_hasLoadError) _buildSummaryCard()'), isTrue);
      final svc = _codeOf(_src(_appSvcPath));
      final b = _after(svc, 'getPendingApplicationsByMonthAndBusiness({', 1500);
      expect(b.contains('rethrow;'), isTrue);
      expect(b.contains('return [];'), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 5. Applicant review — capability
  // ═════════════════════════════════════════════════════════════
  group('R1.2.1-05 applicant review capability', () {
    final cf = _src(_cfPath);

    test('05-a users 조회의 applicantReview는 canManageTo를 요구한다', () {
      final s = _tsSliceOf(cf, 'export const callableGetUsersBatch = onCall',
          'const BANK_ONLY_FIELDS');
      expect(s.contains('isApplicantReview && !isSuperAdmin && !isAdmin'), isTrue);
      expect(s.contains('reviewPerms?.canManageTo !== true'), isTrue);
    });

    test('05-b 지원서 조회의 applicantReview도 canManageTo', () {
      final s = _tsSliceOf(cf, 'export const callableGetApplicationsByBiz = onCall',
          'const cap = Math.min(');
      expect(s.contains('appsPerms?.canManageTo !== true'), isTrue);
    });

    test('05-c membership만으로 지원서를 읽을 수 없다', () {
      // UI에 진입 경로가 없다는 것은 서버 authorization이 아니다.
      final s = _tsSliceOf(cf, 'export const callableGetApplicationsByBiz = onCall',
          'const cap = Math.min(');
      expect(s.contains('APPLICATION_READ_PERMISSIONS'), isTrue);
      for (final p in [
        'canManageTo', 'canManageWorkers', 'canManageWage', 'canManageContract',
      ]) {
        expect(s.contains('"$p"'), isTrue);
      }
      expect(s.contains('"지원서 조회 권한이 없습니다."'), isTrue);
    });

    test('05-d purpose 값은 allowlist 검증을 거친다', () {
      final n = RegExp(r'허용되지 않는 purpose 값').allMatches(cf).length;
      expect(n, greaterThanOrEqualTo(2));
    });

    test('05-e 클라이언트가 지원 검토 경로에서 purpose를 실제로 보낸다', () {
      // [PII-DOC-R0.1] 큐 서비스는 canonical 상수를 쓴다 — 리터럴이 아니라.
      //   상수 값이 서버 문자열과 같다는 것은
      //   transfer_export_truth_contract_test 05가 따로 고정한다.
      final q = _codeOf(_src(_queueSvcPath));
      expect(q.contains('purpose: FirestoreService.purposeApplicantReview'),
          isTrue);
      // 상세 화면은 getBusinessWorkHistory 경로 — 여기는 그대로다.
      final d = _codeOf(_src(_detailPath));
      expect(d.contains("widget.isConfirmed ? null : 'applicantReview'"), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 6. Applicant review — purpose-scoped projection
  // ═════════════════════════════════════════════════════════════
  group('R1.2.1-06 purpose projection', () {
    final cf = _src(_cfPath);
    final proj = _tsSliceOf(cf, 'const APPLICANT_REVIEW_ALLOWED = new Set([',
        '/** [R2.1] Seat Commit 겹침 계약 — 수집 결과. */');

    test('06-a denylist가 아니라 allowlist다', () {
      expect(cf.contains('APPLICANT_REVIEW_ALLOWED'), isTrue);
      expect(cf.contains('isApplicantReview && !APPLICANT_REVIEW_ALLOWED.has(key)'), isTrue);
    });

    test('06-b 급여·신원·문서 필드는 allowlist에 없다', () {
      for (final f in [
        'accountNumber', 'bankName', 'accountHolder', 'bankVerificationStatus',
        'bankbookImagePath', 'bankbookImageUrl', 'bankbookUploadedAt',
        'idCardImagePath', 'idCardImageUrl', 'residentNumber', 'foreignIdNumber',
        'ci', 'ciHash', 'passVerifiedAt', 'signatureBase64', 'sealBase64',
      ]) {
        expect(proj.contains('"$f"'), isFalse, reason: '$f 가 지원 검토 응답에 포함됨');
      }
    });

    test('06-c 정확한 주거 주소는 allowlist에 없고 coarse region만 있다', () {
      expect(proj.contains('"address"'), isFalse);
      expect(proj.contains('"detailAddress"'), isFalse);
      expect(proj.contains('"homeRegion"'), isTrue);
    });

    test('06-d 판단에 필요한 필드는 allowlist에 있다', () {
      for (final f in [
        'name', 'profileImageUrl', 'bio',
        'recentNoShowCount', 'recentLateCount', 'isBlacklisted',
        'totalWorkDays', 'workTypeStats', 'averageRating', 'reviewCount', 'rehireRate',
      ]) {
        expect(proj.contains('"$f"'), isTrue, reason: '$f 가 빠지면 판단이 불가능하다');
      }
    });

    test('06-e purpose 응답은 캐시에 섞이지 않는다', () {
      // 축약본이 캐시에 남으면 확정자 화면이 계좌 없는 사용자를 받는다.
      //
      // [PII-DOC-R0.1] 같은 불변식을 다른 방법으로 지킨다.
      //   예전에는 purpose 호출이 캐시를 아예 쓰지 않았다(usesCache).
      //   purpose가 목록 화면 전체로 퍼지면서 그 방식은 1시간 캐시를
      //   통째로 잃는다는 뜻이 됐다. 그래서 우회 대신 **네임스페이스**로 나눈다:
      //   키에 목적이 들어가므로 축약본과 전체본은 애초에 같은 칸에 못 들어간다.
      final s = _codeOf(_src(_fsSvcPath));
      final b = _after(s, 'getUsersBatch(', 2600);
      expect(b.contains("String ck(String uid) => purpose == null"), isTrue,
          reason: '캐시 키가 목적별로 나뉘어야 한다');
      expect(b.contains(r"'$purpose|$uid'"), isTrue);
      expect(b.contains('_userCache[ck(uid)]'), isTrue);
      expect(b.contains('_userCacheTimestamps[ck(uid)]'), isTrue);
      // 전체본 키는 그대로 uid — 기존 캐시 semantics 보존.
      expect(b.contains('purpose == null ? uid :'), isTrue);
    });

    test('06-f purpose 미지정 호출은 기존 semantics 그대로', () {
      final s = _codeOf(_src(_fsSvcPath));
      final b = _after(s, 'getUsersBatch(', 2600);
      expect(b.contains("if (purpose != null) 'purpose': purpose"), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 7. 주소 정밀도
  // ═════════════════════════════════════════════════════════════
  group('R1.2.1-07 address granularity', () {
    final d = _codeOf(_src(_detailPath));

    test('07-a 검토 단계는 시/군/구만, 확정자만 정확한 주소', () {
      final b = _bodyOf(d, 'Widget _buildBasicInfo(BuildContext context)');
      expect(b.contains('if (!widget.isConfirmed)'), isTrue);
      expect(b.contains("_buildInfoRow(context, '거주 지역'"), isTrue);
      // 정확한 주소 행은 확정자 분기에만 남는다
      final addrAt = b.indexOf("'주소'");
      final elseAt = b.indexOf('else if (widget.user.address != null)');
      expect(elseAt, greaterThan(0));
      expect(addrAt, greaterThan(elseAt));
    });

    test('07-b coarse label에 동/읍/면을 붙이지 않는다', () {
      final b = _after(d, 'String _coarseRegionLabel(UserRegion r)', 200);
      expect(b.contains('r.district'), isFalse);
      expect(b.contains('r.city'), isTrue);
    });
  });
}
