// [PRIVACY-REWRITE.1] 공개 정책 · 외부 계정삭제 경로 계약.
//
//   지키는 문장은 둘이다.
//
//     앱이 보여주는 정책과 공개된 정책이 같아야 한다.
//     앱 없이도 계정 삭제를 요청할 수 있어야 한다.
//
//   공개 페이지는 앱 원문에서 생성된다. 그래서 여기서는 "두 문서가 같은가"를
//   글자 단위로 확인할 수 있다 — 버전 문자열만 맞추는 것으로는 다시 갈라진다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

/// Dart 원문에서 정책 본문을 뽑는다 — 렌더러와 같은 규칙.
String _policyBody(String dart) {
  const marker = "const _defaultPrivacyPolicy = '''";
  final i = dart.indexOf(marker);
  expect(i, greaterThan(-1), reason: '정책 원문을 찾지 못했다');
  final start = i + marker.length;
  final end = dart.indexOf("''';", start);
  expect(end, greaterThan(start));
  return dart.substring(start, end);
}

String _revision(String dart) {
  final m =
      RegExp(r"const kPrivacyPolicyRevision = '([^']+)';").firstMatch(dart);
  expect(m, isNotNull, reason: 'kPrivacyPolicyRevision 을 찾지 못했다');
  return m!.group(1)!;
}

/// HTML 엔티티를 되돌린다 — 렌더러의 esc 역함수.
String _unesc(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

void main() {
  late String dart;
  late String body;
  late String rev;
  late String publicHtml;
  late String deletionHtml;

  setUpAll(() {
    dart = _read('lib/models/core/legal_terms_model.dart');
    body = _policyBody(dart);
    rev = _revision(dart);
    publicHtml = _read('public/privacy.html');
    deletionHtml = _read('public/account-deletion.html');
  });

  // ───────────────────────────────────────────────────────────
  group('PR-1x 공개 페이지 (§19 A·B)', () {
    test('A 공개 정책 파일이 존재한다', () {
      expect(File('public/privacy.html').existsSync(), isTrue);
      expect(publicHtml.length, greaterThan(1000));
    });

    test('B 제목이 개인정보 처리방침임을 분명히 한다', () {
      expect(publicHtml.contains('<title>AlFit 개인정보 처리방침</title>'), isTrue);
      expect(publicHtml.contains('<h1>AlFit 개인정보 처리방침</h1>'), isTrue);
    });

    test('호스팅이 public 디렉터리를 서빙한다', () {
      // 공백 표기에 흔들리지 않게 읽는다.
      final fb = _read('firebase.json').replaceAll(RegExp(r'\s+'), '');
      expect(fb.contains('"hosting"'), isTrue);
      expect(fb.contains('"public":"public"'), isTrue);
      expect(fb.contains('"cleanUrls":true'), isTrue,
          reason: '/privacy · /account-deletion 로 접근한다');
    });
  });

  // ───────────────────────────────────────────────────────────
  group('PR-2x 앱·웹 parity (§14·§15·§19 C)', () {
    test('C 같은 개정 번호를 쓴다', () {
      expect(dart.contains("version: kPrivacyPolicyRevision"), isTrue,
          reason: '앱 정책 항목이 상수를 쓴다');
      expect(publicHtml.contains('content="$rev"'), isTrue);
      expect(publicHtml.contains('개정 $rev'), isTrue);
    });

    test('C2 본문이 글자 단위로 같다 — 버전만 맞추지 않는다', () {
      final i = publicHtml.indexOf('<div class="content-text">');
      expect(i, greaterThan(-1));
      final s = i + '<div class="content-text">'.length;
      final e = publicHtml.indexOf('</div>', s);
      expect(_unesc(publicHtml.substring(s, e)), body,
          reason: '공개 페이지는 앱 원문에서 생성된다 — 다르면 렌더러를 다시 돌려야 한다');
    });

    test('C3 시행일이 본문·머리글에 함께 있다', () {
      expect(body.contains('본 처리방침은 2026년 9월 26일부터 적용됩니다'), isTrue);
      expect(publicHtml.contains('시행일 2026년 9월 26일'), isTrue);
    });

    test('생성기가 원문 한 곳만 읽는다', () {
      final r = _read('scripts/render-privacy.js');
      expect(r.contains('_defaultPrivacyPolicy'), isTrue);
      expect(r.contains('kPrivacyPolicyRevision'), isTrue);
      expect(r.contains("'public', 'privacy.html'"), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('PR-3x 정책 내용이 실제 처리와 맞는가 (§19 D·I·J·K·L)', () {
    test('D 현재 처리하는 민감 범주가 들어 있다', () {
      for (final k in <String>[
        '외국인등록번호', '신분증', '통장 사본', '계좌번호', 'GPS',
        '체류자격', '전자 서명', '사업자등록번호',
      ]) {
        expect(body.contains(k), isTrue, reason: k);
      }
    });

    test('D2 수집하지 않는 것을 수집한다고 쓰지 않는다', () {
      expect(body.contains('주민등록번호 — 현재 수집하지 않습니다'), isTrue,
          reason: '실제 동작(신규 미수집)과 일치해야 한다');
    });

    test('I Analytics·Crashlytics 고지가 있다', () {
      expect(body.contains('Crashlytics'), isTrue);
      expect(body.contains('Analytics'), isTrue);
      expect(body.contains('앱 충돌 분석'), isTrue);
      expect(body.contains('이용 통계 분석'), isTrue);
    });

    test('J 위치는 출퇴근 목적으로만 기술된다', () {
      expect(body.contains('출퇴근 시 GPS 위도·경도 좌표'), isTrue);
      expect(body.contains('GPS·비콘 기반 출퇴근 인증'), isTrue);
      // 상시·백그라운드 수집을 주장하지 않는다.
      expect(body.contains('백그라운드에서 항상'), isFalse);
      expect(body.contains('상시 위치 수집'), isFalse);
    });

    test('K 신분증·통장·세무 식별정보 처리 기술이 있다', () {
      expect(body.contains('복원이 불가능한 고유값'), isTrue);
      expect(body.contains('세무 처리용으로 보관하던 식별번호 정보'), isTrue);
      expect(body.contains('소득신고·원천징수'), isTrue);
    });

    test('L 익명화를 과장하지 않는다 (§12)', () {
      // 식별자 제거는 사실대로, "완전 익명" 같은 확정 표현은 쓰지 않는다.
      expect(body.contains('이용자 식별자를'), isTrue);
      for (final over in <String>[
        '완전히 익명', '복원이 불가능한 익명', '영구히 익명', '재식별이 불가능',
      ]) {
        expect(body.contains(over), isFalse, reason: over);
      }
    });

    test('1A-A 근로기준법 일괄 5년 문구가 없다 (§4)', () {
      expect(body.contains('급여·근로 관련 회계 기록 및 출퇴근 기록: 5년'), isFalse,
          reason: '기록 종류를 뭉뚱그려 한 기간으로 적지 않는다');
      expect(body.contains('3년 (근로기준법 제42조)'), isTrue,
          reason: '근로자 명부·근로계약 중요 서류의 근거와 기간');
      // [1C] 통신비밀보호법 3개월도 적용 근거가 없어 함께 제거됐다.
      expect(body.contains('3개월 (통신비밀보호법)'), isFalse);
    });

    test('1A-A2 세무 자료에 없는 기간을 지어내지 않는다 (§4)', () {
      expect(body.contains('세무 관련 자료: 관계 세법이 정한 기간'), isTrue);
      // 확인되지 않은 세법 이름·연수를 쓰지 않는다.
      for (final invented in <String>[
        '국세기본법', '법인세법', '부가가치세법', '세무 관련 자료: 5년',
      ]) {
        expect(body.contains(invented), isFalse, reason: invented);
      }
    });

    test('1A-A3 출퇴근 기록은 목적으로 기술한다 (§5)', () {
      expect(body.contains('출퇴근 기록: 임금 계산의 근거가 되는 기록으로 보존'),
          isTrue);
      // 독립 법정 class 를 단정하지 않는다.
      expect(body.contains('출퇴근 기록: 5년'), isFalse);
      expect(body.contains('출퇴근 기록: 3년'), isFalse);
    });

    test('1A-A4 민감 원본과 지급 기록을 구분한다 (§9)', () {
      expect(body.contains('[민감 원본과 근무·지급 기록의 구분]'), isTrue);
      expect(body.contains('이용 목적이 끝나면 지체 없이 파기하며'), isTrue);
      expect(
        body.contains('민감 원본을 목적 종료 시 삭제한다고 해서, '
            '위 지급 증빙이 함께 삭제된다는'),
        isTrue,
        reason: '전자의 삭제가 후자의 삭제를 뜻하지 않는다',
      );
    });

    test('1B-A "삭제 대상 아님" 표현이 없다 (§3)', () {
      // "함께 삭제되지 않습니다"는 §3 이 지정한 표현이라 금지 대상이 아니다.
      //   금지하는 것은 보존 의무를 단정하거나 영구성을 암시하는 쪽이다.
      for (final s in <String>[
        '삭제 대상 아님', '지워지지 않습니다', '같은 기준으로 지우지 않습니다',
        '삭제하지 않습니다.',
      ]) {
        expect(body.contains(s), isFalse, reason: s);
        expect(deletionHtml.contains(s), isFalse, reason: 's/$s');
      }
    });

    test('1B-A2 지급 증빙 문구가 지정된 방향을 따른다 (§3)', () {
      expect(body.contains('법적·세무·분쟁 대응 목적의 별도 보존 대상이며'), isTrue);
      expect(body.contains('현재 자동 삭제는 적용하지 않습니다'), isTrue);
      expect(
        body.contains('구체적인 보존기간·기산점·삭제 방식은\n'
            '  관련 법령 및 세무·법률 검토에 따라 확정합니다'),
        isTrue,
      );
    });

    test('1B-C 전자상거래법 blanket 귀속이 없다 (§4)', () {
      expect(body.contains('전자상거래법'), isFalse,
          reason: '소비자 거래 기록으로 묶을 근거를 확인하지 못했다');
      expect(body.contains('청약철회'), isFalse);
      // 대신 근거 미확정을 밝힌다.
      expect(body.contains('근거가 확인되지 않은 기간을'), isTrue);
    });

    test('1B-D·E 삭제 처리 기록이 공개되고 최소화돼 있다 (§5)', () {
      expect(body.contains('[삭제 처리 기록]'), isTrue);
      expect(body.contains('계정 삭제 요청 처리 기록'), isTrue);
      // 민감 원본을 담지 않는다고 명시.
      expect(body.contains('신분증·통장 사본·계좌번호·세무 식별번호는 포함하지'),
          isTrue);
    });

    /// 실제 저장 필드 — 공개 문구는 이것과 일치해야 한다.
    String auditWrite() {
      final tool = _read('scripts/operator-delete-account.js');
      final i = tool.indexOf("collection('account_deletion_records')");
      expect(i, greaterThan(-1));
      return tool.substring(i, i + 420);
    }

    test('1C-A·B 저장되는 필드가 공개문구와 일치한다 (§2·§3)', () {
      final w = auditWrite();
      // 코드가 실제로 대상 계정 식별자를 남긴다.
      expect(w.contains('targetUid: UID'), isTrue);
      expect(w.contains('targetRole: role'), isTrue);
      expect(w.contains('steps:'), isTrue);
      // 그 사실이 공개 문구 양쪽에 적혀 있다.
      for (final s in <String>['대상 계정 식별자', '계정 유형', '수행 결과']) {
        expect(body.contains(s), isTrue, reason: 'policy/$s');
        expect(deletionHtml.contains(s), isTrue, reason: 'deletion/$s');
      }
      expect(body.contains('삭제 요청 처리·보안·분쟁 대응 목적에 한해 제한적으로'),
          isTrue);
      // 숫자를 지어내지 않는다.
      expect(body.contains('보존 기간은 관련 법령 검토에 따라 확정합니다'), isTrue);
    });

    test('1C-C 감사 기록에 민감 원본이 없다 (§4)', () {
      final w = auditWrite();
      for (final pii in <String>[
        'ciHash', 'phoneHash', 'accountNumber', 'idCard', 'bankbook',
        'taxIdentifier', 'foreignIdentityFingerprint', 'rrn', 'phone',
      ]) {
        expect(w.contains(pii), isFalse, reason: pii);
      }
      for (final k in <String>['requestId', 'actor', 'reason', 'targetUid',
        'executedAt', 'steps']) {
        expect(w.contains(k), isTrue, reason: k);
      }
      // 자유 입력 사유에 PII 를 적지 말라는 운영 지침이 있다.
      final rb = _read('docs/account-deletion-runbook.md');
      expect(rb.contains('`--reason` 은 자유 입력이다'), isTrue);
    });

    test('1C-D 통신비밀보호법 3개월 문구가 없다 (§5·§6)', () {
      expect(body.contains('통신비밀보호법'), isFalse,
          reason: 'ALfit 이 적용 대상이라는 근거를 확인하지 못했다');
      expect(body.contains('3개월'), isFalse);
      // 대신 실제 목적만 적는다.
      expect(
        body.contains('서비스 접속·이용 로그: 서비스 보안, 오류 분석, '
            '부정 이용 방지에 필요한'),
        isTrue,
      );
      expect(body.contains('특정 법률에 따른 의무 보관이 아니며'), isTrue);
    });

    test('1C-E 새 기간을 지어내지 않았다 (§6)', () {
      // 보존 항목 목록 안에서만 본다 — 시행일 날짜는 기간이 아니다.
      final s = body.indexOf('• 법령에 따른 보존 항목:');
      final e = body.indexOf('[민감 원본과', s);
      expect(s, greaterThan(-1));
      expect(e, greaterThan(s));
      final periods = RegExp(r'[0-9]+\s*(년|개월|일)')
          .allMatches(body.substring(s, e))
          .map((m) => m.group(0)!.replaceAll(' ', '')).toSet();
      expect(periods.difference({'3년'}), isEmpty,
          reason: '근로기준법 3년 외의 기간이 생겼다: $periods');
    });

    test('1B-F 익명화를 주장하지 않는다 (§7)', () {
      for (final claim in <String>['익명화', '완전 비식별', '비식별화']) {
        expect(body.contains(claim), isFalse, reason: claim);
        expect(deletionHtml.contains(claim), isFalse, reason: 's/$claim');
      }
      expect(body.contains('[직접 식별정보를 제거한 뒤 유지]'), isTrue);
      expect(body.contains('완전한 비식별 처리를 뜻하지는 않습니다'), isTrue);
    });

    test('1B-H 자동 삭제를 추가하지 않았다 (§2)', () {
      final cf = _read('functions/src/index.ts');
      for (final bad in <String>[
        'purgeAttendance', 'purgeMoneyAudit', 'retentionScheduler',
        'cleanupExpiredPayroll', 'ttlDelete',
      ]) {
        expect(cf.contains(bad), isFalse, reason: bad);
      }
      final tool = _read('scripts/operator-delete-account.js');
      expect(tool.contains("RETAIN(법정 보존)"), isTrue,
          reason: '근무 이력은 지우지 않는다');
    });

    test('H 근거 없는 일괄 보존기간을 쓰지 않는다 (§11)', () {
      // 기간을 적은 줄에는 법령 근거가 함께 있어야 한다.
      // 보존 항목 목록만 본다 — 시행일 줄까지 쓸어담으면 오진한다.
      final s = body.indexOf('• 법령에 따른 보존 항목:');
      expect(s, greaterThan(-1));
      final e = body.indexOf('[민감 원본과', s);
      expect(e, greaterThan(s));
      final lines = body.substring(s, e).split('\n')
          .where((l) => l.trimLeft().startsWith('-'))
          .where((l) => RegExp(r'[0-9]+\s*(년|개월)').hasMatch(l))
          .toList();
      expect(lines, isNotEmpty);
      for (final l in lines) {
        // 법령 표기는 '(근로기준법 제42조)' 처럼 조문이 붙을 수 있다.
        expect(RegExp(r'\([^)]*법[^)]*\)|재가입|30일|관계 세법').hasMatch(l), isTrue,
            reason: '근거 없는 기간: $l');
      }
      // 영구 보관을 확정하지 않는다.
      expect(body.contains('영구 보관'), isFalse);
    });

    test('재가입 제한 보관을 사실대로 적는다 (§13)', () {
      expect(body.contains('탈퇴 후 30일간 동일인 재가입을 제한'), isTrue);
      expect(body.contains('재가입 제한과 부정 이용 차단 외의 목적으로 사용하지 않습니다'),
          isTrue);
    });

    test('탈퇴 후 처리가 세 갈래로 구분된다 (§12)', () {
      for (final k in <String>[
        '[즉시 삭제]', '[법령·계약에 따라 보존]',
        '[직접 식별정보를 제거한 뒤 유지]', '[삭제 처리 기록]',
      ]) {
        expect(body.contains(k), isTrue, reason: k);
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  group('PR-4x 외부 계정삭제 경로 (§19 E·F·G)', () {
    test('E 정책이 계정 삭제 방법을 알려준다', () {
      expect(body.contains('회원 탈퇴 (계정 삭제)'), isTrue);
      expect(body.contains('설정 화면 > 회원탈퇴'), isTrue);
      expect(body.contains('account-deletion'), isTrue,
          reason: '앱 없이 요청할 수 있는 경로가 정책에 있어야 한다');
    });

    test('외부 삭제 페이지가 존재하고 제목이 분명하다', () {
      expect(File('public/account-deletion.html').existsSync(), isTrue);
      expect(deletionHtml.contains('<title>AlFit 계정 삭제 요청</title>'), isTrue);
    });

    test('F 앱 재설치·재로그인을 요구하지 않는다', () {
      expect(
        deletionHtml.contains('앱을 설치하거나 다시 로그인하지 않아도'),
        isTrue,
      );
      for (final bad in <String>['앱을 설치한 뒤', '앱에서만', '재설치']) {
        expect(deletionHtml.contains(bad), isFalse, reason: bad);
      }
    });

    test('G 실제 접수 경로가 있다 — 안내만 하고 끝나지 않는다', () {
      expect(deletionHtml.contains('mailto:corebridge87@gmail.com'), isTrue);
      // 메일 앱이 없어도 쓸 수 있게 주소를 글자로도 준다.
      expect(deletionHtml.contains('>corebridge87@gmail.com<'), isTrue);
      // [1A §7] 근거 없는 기한 대신 실제 처리 순서를 약속한다.
      expect(deletionHtml.contains('완료되면'), isTrue);
      expect(deletionHtml.contains('완료 사실을 회신'), isTrue);
    });

    test('§7 과도한 본인확인 정보를 요구하지 않는다', () {
      expect(deletionHtml.contains('가입에 사용한 휴대폰 번호'), isTrue);
      expect(deletionHtml.contains('보내지 마세요'), isTrue,
          reason: '주민등록번호·신분증을 새로 요구하지 않는다');
    });

    test('§5 삭제 범위와 보존 항목을 함께 설명한다', () {
      for (final k in <String>[
        '즉시 삭제', '직접 식별정보를 제거한 뒤 유지', '법령·계약에 따라 보존',
        '재가입 제한', '삭제 처리 기록',
      ]) {
        expect(deletionHtml.contains(k), isTrue, reason: k);
      }
    });

    test('1A-C 개정 표기가 미래처럼 읽히지 않는다 (§6)', () {
      expect(rev, '2026-09-26', reason: '시행일과 같은 날짜여야 한다');
      expect(dart.contains('(개정 2026-09-26)'), isTrue);
      expect(dart.contains("kPrivacyPolicyRevision = '2026.10'"), isFalse,
          reason: '월 단위 표기는 시행일보다 나중처럼 읽힌다');
      expect(publicHtml.contains('개정 2026.10'), isFalse);
    });

    test('1A-H 근거 없는 고정 처리기한을 약속하지 않는다 (§7)', () {
      expect(body.contains('3일 이내'), isFalse);
      expect(deletionHtml.contains('3일 이내'), isFalse);
      expect(body.contains('본인 확인과 법령상 보존 대상 여부를 확인한 뒤 처리하며'),
          isTrue);
      expect(deletionHtml.contains('완료되면\n         회신드립니다') ||
          deletionHtml.contains('완료되면'), isTrue);
    });

    test('1A-F 운영자 도구가 앱 callable 이 아니다 (§2·§9)', () {
      expect(File('scripts/operator-delete-account.js').existsSync(), isTrue);
      final t = _read('scripts/operator-delete-account.js');
      expect(t.contains('앱에 callable 을 만들지 않는다'), isTrue);
      // 실행 근거가 필수다 — 기억에 의존하지 않는다.
      for (final k in <String>['--request', '--actor', '--reason',
        'account_deletion_records']) {
        expect(t.contains(k), isTrue, reason: k);
      }
      // 서버에 cross-user 삭제 callable 이 생기지 않았다.
      final cf = _read('functions/src/index.ts');
      for (final bad in <String>[
        'callableAdminDeleteAccount', 'callableOperatorDeleteAccount',
        'callableForceDeleteUser',
      ]) {
        expect(cf.contains(bad), isFalse, reason: bad);
      }
    });

    test('1A 자동 삭제를 구현하지 않았다', () {
      final rb = _read('docs/account-deletion-runbook.md');
      expect(rb.contains('자동 삭제(scheduler·TTL·일괄 정리)를 규정하지 않는다'),
          isTrue);
      final gate = _read('docs/release-privacy-gate.md');
      expect(gate.contains('자동 삭제를 구현했다는 뜻이 아니다'), isTrue);
    });

    test('§6 웹과 앱이 같은 기준임을 명시한다', () {
      expect(deletionHtml.contains('앱에서 직접 탈퇴하는 경우와 같은 기준'), isTrue);
      expect(body.contains('앱에서 직접 탈퇴하든 웹으로 요청하든'), isTrue);
    });

    test('페이지끼리 연결된다', () {
      expect(deletionHtml.contains('href="/privacy"'), isTrue);
      expect(publicHtml.contains('href="/account-deletion"'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('PR-5x 운영 절차 (§17)', () {
    test('runbook 이 canonical 삭제 의미를 따른다', () {
      final rb = _read('docs/account-deletion-runbook.md');
      for (final k in <String>[
        'deleted_accounts', 'nativeIdentityFingerprints',
        'foreignIdFingerprints', 'taxIdentities',
        'callableDeleteAccountPreData', 'callableDeleteAccountApplications',
      ]) {
        expect(rb.contains(k), isTrue, reason: k);
      }
      // 순서 근거가 적혀 있다 — 기록이 sentinel 삭제보다 먼저다.
      expect(rb.contains('sentinel 삭제보다 **먼저**'), isTrue);
    });

    test('운영자 실행이 도구로 고정돼 있다', () {
      final rb = _read('docs/account-deletion-runbook.md');
      expect(rb.contains('scripts/operator-delete-account.js'), isTrue);
      expect(rb.contains('Firebase Console 에서 컬렉션을 하나씩 지우지 않는다'),
          isTrue);
      expect(rb.contains('앱에는 타인 계정을 지우는 기능을 만들지 않는다'), isTrue);
    });

    test('보존 대상에 지급 증빙이 명시돼 있다', () {
      final rb = _read('docs/account-deletion-runbook.md');
      for (final k in <String>['money_audit', 'finalWage', '이체·취소·재이체']) {
        expect(rb.contains(k), isTrue, reason: k);
      }
    });

    test('PROD 동기화가 릴리스 게이트로 남아 있다 (§12)', () {
      final gate = _read('docs/release-privacy-gate.md');
      expect(gate.contains('PROD `app_settings/legal_terms`'), isTrue);
      expect(gate.contains('PENDING — 출시 전 필수'), isTrue);
      expect(gate.contains('CLOSED 가 아니다'), isTrue);
    });
  });
}
