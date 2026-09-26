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

    test('H 근거 없는 일괄 보존기간을 쓰지 않는다 (§11)', () {
      // 기간을 적은 줄에는 법령 근거가 함께 있어야 한다.
      final lines = body.split('\n')
          .where((l) => RegExp(r'[0-9]+\s*(년|개월)').hasMatch(l))
          .where((l) => l.contains('-') || l.contains('•'))
          .toList();
      expect(lines, isNotEmpty);
      for (final l in lines) {
        expect(RegExp(r'\(.*법\)|재가입|30일').hasMatch(l), isTrue,
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
        '[즉시 삭제]', '[법령·계약에 따라 보존]', '[식별자를 제거한 뒤 유지]',
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
      expect(deletionHtml.contains('3일 이내'), isTrue);
      expect(deletionHtml.contains('완료 사실을 회신'), isTrue);
    });

    test('§7 과도한 본인확인 정보를 요구하지 않는다', () {
      expect(deletionHtml.contains('가입에 사용한 휴대폰 번호'), isTrue);
      expect(deletionHtml.contains('보내지 마세요'), isTrue,
          reason: '주민등록번호·신분증을 새로 요구하지 않는다');
    });

    test('§5 삭제 범위와 보존 항목을 함께 설명한다', () {
      for (final k in <String>[
        '즉시 삭제', '식별자를 제거한 뒤 유지', '법령·계약에 따라 보존',
        '재가입 제한',
      ]) {
        expect(deletionHtml.contains(k), isTrue, reason: k);
      }
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

    test('운영자 실행 경로 부재가 명시돼 있다', () {
      final rb = _read('docs/account-deletion-runbook.md');
      expect(rb.contains('운영자가 다른 사람의 계정을 대신 삭제 실행하는 경로는'),
          isTrue);
      expect(rb.contains('미결 — 결정 필요'), isTrue);
    });
  });
}
