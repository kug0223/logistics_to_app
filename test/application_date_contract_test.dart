// [SYSTEM-INTEGRATION-R1.2] Application workDate — business date contract
//
// 실기기(시뮬레이터 timezone = UTC)에서 발견:
//   canonical Application
//     workDate = Timestamp(1789916400) = 2026-09-20T15:00:00Z = KST 2026-09-21 00:00
//   관리자 '지원 검토'
//     9월 20일 일요일
//
// 원인 — writer는 정확하고 reader가 기기 timezone으로 읽었다:
//   parseTimestamp(firestore_helper.dart:9)  Timestamp.toDate().toLocal()
//     → instant는 보존되지만 year/month/day는 기기 timezone 값
//   support_review_queue_screen  DateFormat('yyyy-MM-dd').format(app.workDate)
//     → UTC 기기에서 2026-09-20
//   같은 화면의 _priorityOf는 [AH-V2-04C.1]에서 FormatHelper.toKstDate로
//   고쳐졌지만 '표시·그룹' 경로는 그대로 남아 있었다.
//
// 제품 계약:
//   workDate = 사업장이 운영되는 날짜 = Asia/Seoul calendar date.
//   기기 timezone이 Seoul이든 UTC든 Los_Angeles든 같은 날짜로 보여야 한다.
//
// 아래 1군 테스트는 FormatHelper가 `dt.toUtc().add(9h)`로 계산하므로
// host timezone과 무관하게 같은 답을 내는지 실제 instant로 검증한다.
// 2군은 각 reader가 그 canonical 경로를 실제로 타는지 소스로 고정한다.

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

const _queuePath = 'lib/screens/business_admin/support_review_queue_screen.dart';
const _myAppsPath = 'lib/screens/user/my_applications_screen.dart';
const _notifPath = 'lib/models/core/notification_model.dart';
const _applyPath = 'lib/widgets/dialogs/apply/apply_work_dialog.dart';
const _longTermPath = 'lib/widgets/dialogs/apply/longterm_apply_sheet.dart';
const _detailPath = 'lib/widgets/dialogs/worker_detail_dialog.dart';
const _queueSvcPath = 'lib/services/support_review_queue_service.dart';
const _userHomePath = 'lib/screens/user/user_home_screen.dart';

/// R1-GOLDEN slot/application의 실제 저장값.
/// `db.collection('tos').doc('kcwGL5K4SjWFhuPP54bF')` 하위 슬롯 date._seconds
const _goldenSeconds = 1789916400; // 2026-09-20T15:00:00Z = KST 2026-09-21 00:00

DateTime _goldenUtc() =>
    DateTime.fromMillisecondsSinceEpoch(_goldenSeconds * 1000, isUtc: true);

/// parseTimestamp가 실제로 돌려주는 모양 — Timestamp.toDate().toLocal()
DateTime _goldenAsParsed() =>
    DateTime.fromMillisecondsSinceEpoch(_goldenSeconds * 1000);

void main() {
  // ═════════════════════════════════════════════════════════════
  // 1. canonical business date — 같은 instant는 어디서 읽어도 9/21
  // ═════════════════════════════════════════════════════════════
  group('R1.2-01 canonical KST business date', () {
    test('01-a KST 자정 instant의 ISO 키는 2026-09-21', () {
      expect(FormatHelper.formatDateISO(_goldenUtc()), '2026-09-21');
    });

    test('01-b parseTimestamp가 준 local DateTime도 같은 키', () {
      // parseTimestamp는 .toLocal()을 붙이지만 instant는 그대로다.
      // FormatHelper가 toUtc()로 되돌리므로 host timezone이 무엇이든 같다.
      expect(
        FormatHelper.formatDateISO(_goldenAsParsed()),
        FormatHelper.formatDateISO(_goldenUtc()),
      );
      expect(FormatHelper.formatDateISO(_goldenAsParsed()), '2026-09-21');
    });

    test('01-c 표시 포맷 3종 모두 9/21', () {
      expect(FormatHelper.formatDateKorean(_goldenAsParsed()), '9월 21일 (월)');
      expect(FormatHelper.formatDateCompact(_goldenAsParsed()), '9/21(월)');
      expect(FormatHelper.formatDateShort(_goldenAsParsed()), '9/21');
    });

    test('01-d 요일도 KST 기준 — 2026-09-21은 월요일', () {
      // UTC로 읽으면 9/20 일요일이 된다. 그것이 실기기에서 본 값이었다.
      expect(FormatHelper.weekday(_goldenAsParsed()), '월');
    });

    test('01-e 비교 키(toKstDate)와 표시 키가 같은 날짜를 가리킨다', () {
      final k = FormatHelper.toKstDate(_goldenAsParsed());
      expect(k, DateTime.utc(2026, 9, 21));
      expect(
        '${k.year}-${k.month.toString().padLeft(2, '0')}-${k.day.toString().padLeft(2, '0')}',
        FormatHelper.formatDateISO(_goldenAsParsed()),
      );
    });

    test('01-f 여러 timezone offset으로 표현한 같은 instant → 같은 날짜', () {
      // 같은 순간을 UTC / KST / LA 오프셋으로 각각 만든다.
      // FormatHelper는 instant만 보므로 셋 다 2026-09-21이어야 한다.
      final asUtc = DateTime.parse('2026-09-20T15:00:00Z');
      final asKst = DateTime.parse('2026-09-21T00:00:00+09:00');
      final asLa = DateTime.parse('2026-09-20T08:00:00-07:00');
      expect(asUtc.isAtSameMomentAs(asKst), isTrue);
      expect(asUtc.isAtSameMomentAs(asLa), isTrue);
      for (final d in [asUtc, asKst, asLa]) {
        expect(FormatHelper.formatDateISO(d), '2026-09-21');
        expect(FormatHelper.formatDateKorean(d), '9월 21일 (월)');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 2. 경계 — 월말/연말
  // ═════════════════════════════════════════════════════════════
  group('R1.2-02 date boundary', () {
    test('02-a 월 경계: KST 10/1 자정은 9/30 15:00Z', () {
      final d = DateTime.parse('2026-09-30T15:00:00Z');
      expect(FormatHelper.formatDateISO(d), '2026-10-01');
      expect(FormatHelper.formatYearMonthISO(d), '2026-10');
    });

    test('02-b 연 경계: KST 2027-01-01 자정은 2026-12-31 15:00Z', () {
      final d = DateTime.parse('2026-12-31T15:00:00Z');
      expect(FormatHelper.formatDateISO(d), '2027-01-01');
      expect(FormatHelper.formatYearMonth(d), '2027년 1월');
    });

    test('02-c KST 자정 직전(23:59)은 같은 날 유지', () {
      final d = DateTime.parse('2026-09-21T14:59:00Z'); // KST 9/21 23:59
      expect(FormatHelper.formatDateISO(d), '2026-09-21');
    });

    test('02-d KST 자정 직후는 다음 날로 넘어간다', () {
      final d = DateTime.parse('2026-09-21T15:00:00Z'); // KST 9/22 00:00
      expect(FormatHelper.formatDateISO(d), '2026-09-22');
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 3. reader가 canonical 경로를 탄다 (관리자 지원 검토)
  // ═════════════════════════════════════════════════════════════
  group('R1.2-03 관리자 지원 검토 reader', () {
    final src = _src(_queuePath);
    final code = _codeOf(src);

    test('03-a 이 화면은 더 이상 intl DateFormat을 만들지 않는다', () {
      expect(code.contains('DateFormat('), isFalse,
          reason: 'DateFormat은 기기 timezone으로 찍힌다 — FormatHelper를 쓸 것');
      expect(code.contains("import 'package:intl/intl.dart'"), isFalse);
    });

    test('03-b 그룹 키는 FormatHelper.formatDateISO(workDate)', () {
      final body = _bodyOf(code, 'List<_DateGroup> _buildGroups()');
      expect(body.contains('FormatHelper.formatDateISO(item.app.workDate)'), isTrue);
    });

    test('03-c 날짜 헤더는 FormatHelper.formatDateKorean', () {
      final body = _bodyOf(code, 'Widget _buildDateGroupHeader(_DateGroup group)');
      expect(body.contains('FormatHelper.formatDateKorean(group.date)'), isTrue);
    });

    test('03-d 분류(_priorityOf)와 그룹이 같은 KST 경계를 쓴다', () {
      final p = _bodyOf(code, '_Priority _priorityOf(ApplicationModel app)');
      expect(p.contains('FormatHelper.toKstDate'), isTrue);
      // 표시·분류가 서로 다른 timezone 기준을 쓰면 '예정'인데 어제 날짜가 된다.
      final g = _bodyOf(code, 'List<_DateGroup> _buildGroups()');
      expect(g.contains('FormatHelper.'), isTrue);
    });

    test('03-e 장기 지원 기간 표기도 KST', () {
      expect(code.contains('FormatHelper.formatDateCompact(app.workDate)'), isTrue);
      expect(code.contains('FormatHelper.formatDateCompact(app.workEndDate!)'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 4. reader가 canonical 경로를 탄다 (지원자 쪽)
  // ═════════════════════════════════════════════════════════════
  group('R1.2-04 지원자 reader', () {
    test('04-a 내 지원 — workDate 요일을 기기 기준으로 읽지 않는다', () {
      final code = _codeOf(_src(_myAppsPath));
      expect(code.contains('_korWeekday'), isFalse);
      expect(code.contains('workDate.weekday'), isFalse);
      expect(code.contains('FormatHelper.formatDateKorean(dt)'), isTrue);
      expect(code.contains('FormatHelper.formatDateKorean(workDate)'), isTrue);
    });

    test('04-b 지원하기 — 슬롯 날짜 표기가 FormatHelper 경유', () {
      final code = _codeOf(_src(_applyPath));
      expect(code.contains("DateFormat('M/d (E)'"), isFalse);
      expect(code.contains("DateFormat('M월 d일 (E)'"), isFalse);
      expect(code.contains('const dateFormat = FormatHelper.formatDateCompact'), isTrue);
      expect(code.contains('const dateFormat = FormatHelper.formatDateKorean'), isTrue);
    });

    test('04-c 장기 지원 시트 — 희망 시작일/기간도 FormatHelper', () {
      final code = _codeOf(_src(_longTermPath));
      expect(code.contains('DateFormat('), isFalse);
      expect(code.contains('FormatHelper.formatDateKorean('), isTrue);
    });

    test('04-d 근무자 홈 — 다음 근무 날짜도 같은 기준', () {
      // 내 지원이 9/21인데 홈이 9/20이면 같은 모순이 화면만 옮겨간 것이다.
      final code = _codeOf(_src(_userHomePath));
      expect(code.contains(r'${app.workDate.month}'), isFalse);
      expect(code.contains('FormatHelper.formatDateCompact(app.workDate)'), isTrue);
      expect(code.contains('FormatHelper.toKstDate(app.workDate)'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 5. 알림 본문의 근무일
  // ═════════════════════════════════════════════════════════════
  group('R1.2-05 notification body', () {
    final code = _codeOf(_src(_notifPath));

    test('05-a 근무일을 기기 local month/day로 조립하지 않는다', () {
      expect(code.contains(r'${workDate.month}/${workDate.day}'), isFalse);
    });

    test('05-b FormatHelper.formatDateShort로 통일', () {
      // 같은 Application이 화면과 알림에서 다른 날짜로 보이면 안 된다.
      final n = RegExp(r'FormatHelper\.formatDateShort\(workDate\)')
          .allMatches(code)
          .length;
      expect(n, greaterThanOrEqualTo(11));
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 6. 지원 검토 → 지원자 상세 (decision context)
  // ═════════════════════════════════════════════════════════════
  group('R1.2-06 applicant decision context', () {
    final src = _src(_queuePath);
    final code = _codeOf(src);

    test('06-a 기존 WorkerDetailDialog를 재사용한다 (새 프로필 화면 없음)', () {
      expect(code.contains("import '../../widgets/dialogs/worker_detail_dialog.dart'"),
          isTrue);
      expect(code.contains('WorkerDetailDialog.show('), isTrue);
    });

    test('06-b 상세가 이번 지원 context를 유지한다', () {
      final body = _bodyOf(code, 'Future<void> _openApplicantDetail(_QueueItem item)');
      expect(body.contains('application: item.app'), isTrue);
      expect(body.contains('businessId: item.app.businessId'), isTrue);
    });

    test('06-c 확정 mutation을 상세로 확장하지 않는다 (R2 scope)', () {
      final body = _bodyOf(code, 'Future<void> _openApplicantDetail(_QueueItem item)');
      expect(body.contains('showApprovalButtons: false'), isTrue);
    });

    test('06-d 민감정보 섹션이 열리지 않도록 isConfirmed:false로 연다', () {
      // worker_detail_dialog는 isConfirmed일 때만 계좌·통장사본·신분증·계약을 그린다.
      final body = _bodyOf(code, 'Future<void> _openApplicantDetail(_QueueItem item)');
      expect(body.contains('isConfirmed: false'), isTrue);

      final detail = _codeOf(_src(_detailPath));
      final build = _bodyOf(detail, 'Widget build(BuildContext context) {');
      final gated = build.substring(build.indexOf('if (widget.isConfirmed)'));
      final elseAt = gated.indexOf('] else ...[');
      final confirmedOnly = gated.substring(0, elseAt);
      final reviewSide = gated.substring(elseAt);
      for (final s in ['_buildPaymentInfo', '_buildIdCardSection', '_buildContractStatusSection']) {
        expect(confirmedOnly.contains(s), isTrue, reason: '$s 는 확정자 전용이어야 한다');
        expect(reviewSide.contains(s), isFalse, reason: '$s 가 검토 단계에 노출됨');
      }
    });

    test('06-e 지원자 문서를 못 읽으면 상세를 열지 않는다', () {
      final body = _bodyOf(code, 'Widget _buildAppRow(_QueueItem item)');
      expect(body.contains('final canOpenDetail = user != null'), isTrue);
      expect(body.contains('canOpenDetail ? () => _openApplicantDetail(item) : null'),
          isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 7. ERROR != ZERO — 판단 정보의 진실성
  // ═════════════════════════════════════════════════════════════
  group('R1.2-07 decision data truth', () {
    test('07-a 사용자 배치 조회 실패를 빈 Map으로 삼키지 않는다', () {
      final code = _codeOf(_src(_queueSvcPath));
      final body = _bodyOf(code, 'Future<Map<String, UserModel>?> loadUsers(');
      expect(body.contains('return null;'), isTrue,
          reason: '실패는 null(UNKNOWN) — {}(0건)와 구분해야 한다');
    });

    test('07-b 조회 실패 행은 0건이 아니라 실패라고 말한다', () {
      final code = _codeOf(_src(_queuePath));
      final body = _bodyOf(code, 'Widget _buildApplicantSummary(UserModel? user)');
      expect(body.contains("'지원자 정보를 불러오지 못했어요'"), isTrue);
    });

    test('07-c 노쇼·지각 0을 사실로 단언하지 않는다', () {
      final code = _codeOf(_src(_queuePath));
      final body = _bodyOf(code, 'Widget _buildApplicantSummary(UserModel? user)');
      // UserModel의 0은 '사건 없음'과 '아직 집계 안 됨'을 구분하지 못한다.
      expect(body.contains('user.recentNoShowCount > 0'), isTrue);
      expect(body.contains('user.recentLateCount > 0'), isTrue);
      expect(body.contains("노쇼 0"), isFalse);
      expect(body.contains("지각 0"), isFalse);
    });

    test('07-d 상세: 이력/리뷰 조회 실패를 없음으로 바꾸지 않는다', () {
      final detail = _codeOf(_src(_detailPath));
      final hist = _bodyOf(detail, 'Widget _buildBusinessHistory(BuildContext context)');
      expect(hist.contains('_loadFailed'), isTrue);
      expect(hist.contains("'근무 이력을 확인하지 못했어요'"), isTrue);
      expect(hist.contains("'이 사업장에서 근무한 이력이 없습니다'"), isTrue);

      final rev = _bodyOf(detail, 'Widget _buildRecentReviews(BuildContext context)');
      expect(rev.contains('_loadFailed'), isTrue);
      expect(rev.contains("'리뷰를 확인하지 못했어요'"), isTrue);
    });

    test('07-e 로드 실패 시 _loadFailed가 실제로 켜진다', () {
      final detail = _codeOf(_src(_detailPath));
      final load = _bodyOf(detail, 'Future<void> _loadAdditionalData() async');
      expect(load.contains('_loadFailed = true'), isTrue);
    });
  });
}
