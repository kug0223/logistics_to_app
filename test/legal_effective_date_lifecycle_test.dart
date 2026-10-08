// [R7-PAYROLL-POLICY.5A] 발행 ≠ 시행 — 클라이언트 쪽 계약.
//
// 서버 쪽 판정은 `functions/test/legal_effective_date.test.js` 가 고정한다.
// 이 파일이 지키는 것은 **클라이언트가 그 판정을 거스르지 않는가** 다.
//
//   L-1  시행일 변환이 KST 자정이고, 한 곳에만 있다
//   L-2  시행 예정은 할 일도 차단 사유도 아니다
//   L-3  고지기간 숫자를 클라이언트가 들고 있지 않다
//   L-4  발행 호출이 변경 방향·시행일을 보낸다 (기본값 없음)
//   L-5  예정 판이 base 를 대체하지 않는다
//   L-6  시행 예정 안내는 현재 약관과 다른 말로 적는다

import 'dart:io';

import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// 주석을 뺀 소스 — 설명문에 들어 있는 숫자를 코드로 오인하지 않게.
String _code(String p) => _read(p)
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
    })
    .join('\n');

const _kDay = Duration(milliseconds: 24 * 60 * 60 * 1000);

void main() {
  // ───────────────────────────────────────────────────────────
  group('L-1 시행일은 KST 자정이다', () {
    test('01 UTC 자정이 아니라 9시간 앞이다', () {
      final d = kstMidnightOfDate(2026, 11, 7);
      expect(d.toUtc(), DateTime.utc(2026, 11, 6, 15, 0, 0));
      expect(d.toUtc(), isNot(DateTime.utc(2026, 11, 7, 0, 0, 0)),
          reason: 'UTC 자정으로 만들면 국내 사용자에게 하루 어긋난다');
    });

    test('02 모든 날짜가 같은 오프셋을 쓴다', () {
      // KST 자정의 epoch ms 는 하루 격자에서 항상 같은 잔여를 갖는다.
      const want = 15 * 60 * 60 * 1000; // 24h - 9h
      for (final ymd in [
        [2026, 1, 1], [2026, 3, 31], [2026, 10, 8], [2026, 12, 31],
        [2027, 2, 28], [2028, 2, 29],
      ]) {
        final ms = kstMidnightOfDate(ymd[0], ymd[1], ymd[2])
            .millisecondsSinceEpoch;
        expect(ms % _kDay.inMilliseconds, want,
            reason: '$ymd 가 KST 자정이 아니다');
      }
    });

    test('03 KST 자정을 만드는 곳은 하나다', () {
      // KST 오프셋 자체는 앱 전역에서 쓴다(근태·일정). 여기서 막는 것은
      // **시행일용 KST 자정을 법적 문서 쪽에서 또 만드는 것**이다. 두 곳에서
      // 각자 만들면 한쪽만 고쳐졌을 때 시행일이 하루 어긋난다.
      const owner = 'lib/models/core/legal_terms_model.dart';
      expect(_code(owner).contains('DateTime.utc(year, month, day)'), isTrue,
          reason: 'canonical 변환이 사라졌다');

      for (final p in [
        'lib/services/legal_terms_service.dart',
        'lib/screens/super_admin/legal_terms_management_screen.dart',
        'lib/screens/legal/legal_consent_screen.dart',
        'lib/models/core/legal_readiness.dart',
      ]) {
        final src = _code(p);
        expect(RegExp(r'DateTime\.utc\(').hasMatch(src), isFalse,
            reason: '$p 가 시행일을 직접 만든다');
      }

      // 발행 payload 는 canonical 변환을 거쳐야 한다.
      final mgmt = _code(
          'lib/screens/super_admin/legal_terms_management_screen.dart');
      expect(mgmt.contains('kstMidnightOfDate('), isTrue,
          reason: '발행 화면이 canonical 변환을 쓰지 않는다');
    });
  });

  // ───────────────────────────────────────────────────────────
  group('L-2 시행 예정은 차단 사유가 아니다', () {
    LegalReadiness parse(Map<String, Object?> data) =>
        LegalReadiness.fromServer(data);

    test('04 예정 판만 있으면 CURRENT 이고 아무것도 막지 않는다', () {
      final r = parse({
        'status': 'CURRENT',
        'reconsentRequired': <String>[],
        'legacyUnknown': <String>[],
        'optionalUnanswered': <String>[],
        'upcoming': [
          {
            'itemId': 'service_terms',
            'version': '2026-11-07',
            'effectiveAtMs':
                kstMidnightOfDate(2026, 11, 7).millisecondsSinceEpoch,
          },
        ],
      });
      expect(r.status, LegalReadinessStatus.current);
      expect(r.upcoming, hasLength(1));
      expect(r.upcoming.first.version, '2026-11-07');
      // 여기가 핵심이다 — 아직 효력 없는 약관으로 앱을 잠그지 않는다.
      expect(r.blocksNewCommitment, isFalse,
          reason: '시행 전 약관으로 지원·확정을 막으면 안 된다');
      expect(r.needsAttention, isFalse,
          reason: '시행 전 약관은 할 일이 아니다');
      expect(r.attentionItems, isEmpty);
    });

    test('05 시행 후 재동의는 그대로 막는다', () {
      final r = parse({
        'status': 'RECONSENT_REQUIRED',
        'reconsentRequired': ['service_terms'],
        'legacyUnknown': <String>[],
        'optionalUnanswered': <String>[],
        'upcoming': <Object>[],
      });
      expect(r.blocksNewCommitment, isTrue);
      expect(r.needsAttention, isTrue);
    });

    test('06 모양이 깨진 예정 항목은 없는 것으로 친다', () {
      for (final bad in <Object?>[
        null,
        'soon',
        42,
        [null],
        [
          {'itemId': '', 'version': 'x'},
        ],
        [
          {'itemId': 'a', 'version': ''},
        ],
        [
          {'version': 'x'},
        ],
      ]) {
        final r = parse({
          'status': 'CURRENT',
          'upcoming': bad,
        });
        expect(r.upcoming, isEmpty, reason: '$bad');
        expect(r.blocksNewCommitment, isFalse);
      }
    });

    test('07 시각이 없어도 항목 자체는 읽는다 — 날짜만 모른다', () {
      final r = parse({
        'status': 'CURRENT',
        'upcoming': [
          {'itemId': 'service_terms', 'version': '2026-11-07'},
        ],
      });
      expect(r.upcoming, hasLength(1));
      expect(r.upcoming.first.effectiveAt, isNull);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('L-3 고지기간 숫자는 서버가 갖는다', () {
    test('08 클라이언트에 7일·30일 상수가 없다', () {
      // 두 곳에 적어 두면 앱 버전에 따라 다른 기간을 주장하게 된다.
      for (final p in [
        'lib/models/core/legal_terms_model.dart',
        'lib/services/legal_terms_service.dart',
        'lib/screens/super_admin/legal_terms_management_screen.dart',
        'lib/models/core/legal_readiness.dart',
      ]) {
        final src = _code(p);
        for (final bad in [
          'noticeDays', 'NOTICE_DAYS',
          'Duration(days: 7)', 'Duration(days: 30)',
        ]) {
          expect(src.contains(bad), isFalse, reason: '$p 에 $bad 가 있다');
        }
      }
    });

    test('09 서버가 그 숫자를 갖고 있고 약관이 약속한 값이다', () {
      final ts = _read('functions/src/legal_publication.ts');
      expect(ts.contains('LEGAL_NOTICE_DAYS'), isTrue);
      expect(RegExp(r'neutral:\s*7').hasMatch(ts), isTrue);
      expect(RegExp(r'adverse:\s*30').hasMatch(ts), isTrue);
      // 약관 본문의 약속과 같은 숫자여야 한다.
      final terms = LegalTerms.defaultTerms()
          .items
          .firstWhere((i) => i.id == 'service_terms')
          .content;
      expect(terms.contains('최소 7일 전'), isTrue);
      expect(terms.contains('최소 30일 전'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('L-4 발행 호출', () {
    test('10 변경 방향과 시행일을 함께 보낸다', () {
      final src = _code('lib/services/legal_terms_service.dart');
      expect(src.contains("'changeType': changeType.wire"), isTrue);
      expect(src.contains("'effectiveAt': effectiveAtMs"), isTrue);
      expect(src.contains('required LegalChangeType changeType'), isTrue);
      expect(src.contains('required DateTime effectiveAt'), isTrue);
    });

    test('11 변경 방향에 기본값이 없다', () {
      final src = _code(
          'lib/screens/super_admin/legal_terms_management_screen.dart');
      // 기본값이 있으면 아무 생각 없이 짧은 쪽으로 발행된다.
      expect(src.contains('LegalChangeType? _changeType;'), isTrue,
          reason: '기본값 없는 nullable 이어야 한다');
      expect(RegExp(r'_changeType\s*=\s*LegalChangeType\.\w+;')
          .hasMatch(src), isFalse,
          reason: '초기값을 박아 두면 선택을 건너뛴다');
      expect(src.contains("ToastHelper.showError('변경 방향을 선택하세요')"), isTrue);
      expect(src.contains("ToastHelper.showError('시행일을 선택하세요')"), isTrue);
    });

    test('12 거절 이유를 그대로 전한다 — 침묵하지 않는다', () {
      final src = _code(
          'lib/screens/super_admin/legal_terms_management_screen.dart');
      for (final reason in [
        'NOTICE_PERIOD_TOO_SHORT',
        'EFFECTIVE_AT_IMMUTABLE',
        'EFFECTIVE_AT_IN_PAST',
        'INITIAL_NOT_ALLOWED',
        'INITIAL_REQUIRED',
        'INITIAL_MUST_BE_IMMEDIATE',
      ]) {
        expect(src.contains(reason), isTrue, reason: reason);
      }
      // 가장 이른 시행일은 **서버가 보낸 값**을 쓴다.
      expect(src.contains("details['earliestEffectiveAtMs']"), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('L-5 예정 판은 base 를 대체하지 않는다', () {
    Map<String, dynamic> itemMap({Map<String, dynamic>? upcoming}) => {
          'id': 'service_terms',
          'title': 'A 제목',
          'content': 'A 본문',
          'isRequired': true,
          'isActive': true,
          'version': '2026.08',
          'revisionId': 'service_terms__2026.08',
          'order': 1,
          'effectiveAt': Timestamp.fromDate(kstMidnightOfDate(2026, 8, 1)),
          if (upcoming != null) 'upcoming': upcoming,
        };

    test('13 예정 판이 있어도 현재 약관은 base 다', () {
      final it = LegalTermsItem.fromMap(itemMap(upcoming: {
        'version': '2026-11-07',
        'revisionId': 'service_terms__2026-11-07',
        'title': 'B 제목',
        'content': 'B 본문',
        'effectiveAt': Timestamp.fromDate(kstMidnightOfDate(2026, 11, 7)),
      }));
      expect(it.version, '2026.08');
      expect(it.content, 'A 본문');
      expect(it.revisionId, 'service_terms__2026.08');
      expect(it.upcoming, isNotNull);
      expect(it.upcoming!.version, '2026-11-07');
      expect(it.upcoming!.effectiveAt, isNotNull);
    });

    test('14 모양이 깨진 예정 판은 없는 것으로 친다', () {
      for (final bad in <Object?>[
        'soon',
        42,
        <String, dynamic>{},
        {'version': '2026-11-07'},
        {'revisionId': 'x'},
        {'version': '', 'revisionId': 'x'},
        {'version': 'x', 'revisionId': ''},
      ]) {
        final it = LegalTermsItem.fromMap({
          ...itemMap(),
          'upcoming': bad,
        });
        expect(it.upcoming, isNull, reason: '$bad');
        expect(it.version, '2026.08');
      }
    });

    test('15 예정 판 없이도 읽힌다 — 기존 항목이 깨지지 않는다', () {
      final it = LegalTermsItem.fromMap(itemMap());
      expect(it.upcoming, isNull);
      expect(it.effectiveAt, isNotNull);
      // 1B 이전 항목에는 시행일조차 없다.
      final legacy = LegalTermsItem.fromMap({
        'id': 'x', 'title': 't', 'content': 'c',
        'isRequired': true, 'version': '2026.08',
      });
      expect(legacy.effectiveAt, isNull);
      expect(legacy.upcoming, isNull);
    });

    test('16 copyWith 가 시행일·예정 판을 잃지 않는다', () {
      final it = LegalTermsItem.fromMap(itemMap(upcoming: {
        'version': '2026-11-07',
        'revisionId': 'service_terms__2026-11-07',
        'effectiveAt': Timestamp.fromDate(kstMidnightOfDate(2026, 11, 7)),
      }));
      final next = it.copyWith(isActive: false);
      expect(next.effectiveAt, it.effectiveAt,
          reason: '노출 토글이 시행일을 지우면 다시 발행할 수 없다');
      expect(next.upcoming?.version, '2026-11-07',
          reason: '노출 토글이 대기 중인 고지를 지우면 안 된다');
    });

    test('17 노출 토글은 시행일을 모르면 보내지 않는다', () {
      final src = _code('lib/services/legal_terms_service.dart');
      expect(src.contains('final at = item.effectiveAt;'), isTrue);
      expect(src.contains('throw StateError('), isTrue,
          reason: '모르는 날짜를 지어내면 발행본과 어긋난다');
    });
  });

  // ───────────────────────────────────────────────────────────
  group('L-6 안내 문구', () {
    test('18 시행 예정을 현재 약관처럼 말하지 않는다', () {
      final src = _read('lib/screens/legal/legal_consent_screen.dart');
      expect(src.contains('변경된 약관이 공지되어 있습니다'), isTrue);
      expect(src.contains('시행일부터 적용됩니다') ||
          src.contains('부터 적용됩니다'), isTrue);
      // 예정 판에 동의를 받는 경로를 만들지 않는다.
      expect(src.contains('upcoming'), isTrue);
      expect(RegExp(r'_choices\s*=\s*\{[^}]*upcoming').hasMatch(src), isFalse);
    });

    test('19 과도한 절대어·내부 기술어가 안내에 없다', () {
      final src = _read('lib/screens/legal/legal_consent_screen.dart');
      for (final bad in [
        'projection', 'revisionId 를', '반드시 지금', '즉시 동의',
      ]) {
        expect(src.contains(bad), isFalse, reason: bad);
      }
    });
  });
}
