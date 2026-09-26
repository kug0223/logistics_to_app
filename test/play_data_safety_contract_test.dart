// [DATA-SAFETY-FINALIZATION] Play 데이터 안전 선언 ↔ 실제 소스 계약.
//
//   데이터 안전 선언은 한 번 쓰고 끝나는 문서가 아니다. SDK 하나가 늘거나
//   권한 하나가 붙으면 그 순간 낡는다. 그리고 낡았다는 사실은 아무도
//   알려주지 않는다 — 심사에서 지적받기 전까지는.
//
//   그래서 여기서 지키는 것은 "문서가 예쁜가"가 아니라 이것이다.
//
//     지금 코드가 실제로 모으는 것이 선언에 다 들어 있는가.
//     선언의 모든 YES/NO 에 근거가 붙어 있는가.
//
//   주석은 검사 대상이 아니다 — 소스 검사는 `_codeOf()` 로 주석을 걷어내고
//   한다. 문서에 이름만 적어두고 코드에서는 다르게 하는 일을 막기 위해서다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

/// Dart 원문에서 주석 줄을 걷어낸다 — 문자열 검사는 **코드**에만 걸린다.
String _codeOf(String dart) => dart
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// pubspec 의 runtime 의존성 이름 전부.
List<String> _dependencies(String pubspec) {
  final s = pubspec.indexOf('\ndependencies:');
  final e = pubspec.indexOf('\ndev_dependencies:');
  expect(s, greaterThan(-1));
  expect(e, greaterThan(s));
  return RegExp(r'^  ([a-z0-9_]+):', multiLine: true)
      .allMatches(pubspec.substring(s, e))
      .map((m) => m.group(1)!)
      .toList();
}

/// XML 주석을 걷어낸다 — manifest 검사도 **선언된 것**에만 걸린다.
String _xmlCode(String xml) => xml.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

/// manifest 의 uses-permission 마지막 토큰들.
List<String> _permissions(String manifest) => RegExp(
        r'uses-permission android:name="android\.permission\.([A-Z_]+)"')
    .allMatches(manifest)
    .map((m) => m.group(1)!)
    .toSet()
    .toList();

/// 문서를 `## n.` 단위로 자른다.
String _section(String doc, String heading) {
  final i = doc.indexOf(heading);
  expect(i, greaterThan(-1), reason: '섹션을 찾지 못했다: $heading');
  final next = doc.indexOf('\n## ', i + heading.length);
  return doc.substring(i, next == -1 ? doc.length : next);
}

/// Google Play 데이터 안전 taxonomy — 여기 없는 이름을 쓰면 발명이다.
const _playTaxonomy = {
  'Approximate location', 'Precise location',
  'Name', 'Email address', 'User IDs', 'Address', 'Phone number',
  'Race and ethnicity', 'Political or religious beliefs',
  'Sexual orientation', 'Other info',
  'User payment info', 'Purchase history', 'Credit score',
  'Other financial info',
  'Health info', 'Fitness info',
  'Emails', 'SMS or MMS', 'Other in-app messages',
  'Photos', 'Videos',
  'Voice or sound recordings', 'Music files', 'Other audio files',
  'Files and docs', 'Calendar events', 'Contacts',
  'App interactions', 'In-app search history', 'Installed apps',
  'Other user-generated content', 'Other actions',
  'Web browsing history',
  'Crash logs', 'Diagnostics', 'Other app performance data',
  'Device or other IDs',
};

/// Play 가 인정하는 공유 예외 — 문서가 쓸 수 있는 토큰은 이것뿐이다.
const _exceptionTokens = [
  'USER-INITIATED',
  'DISCLOSED-CONSENTED',
  'SERVICE-PROVIDER',
  'LEGAL',
];

void main() {
  late String doc;
  late String pubspec;
  late String manifest;
  late String analyticsSrc;
  late String mainSrc;
  late String locationSrc;
  late String attendanceSrc;
  late String taxSrc;
  late String userModelSrc;
  late String fcmSrc;
  late String legalTermsSrc;
  late String firebaserc;

  setUpAll(() {
    doc = _read('docs/play-data-safety-final.md');
    pubspec = _read('pubspec.yaml');
    manifest = _xmlCode(_read('android/app/src/main/AndroidManifest.xml'));
    analyticsSrc = _codeOf(_read('lib/services/analytics_service.dart'));
    mainSrc = _codeOf(_read('lib/main.dart'));
    locationSrc = _codeOf(_read('lib/utils/location_helper.dart'));
    attendanceSrc =
        _codeOf(_read('lib/screens/user/attendance_check_screen.dart'));
    taxSrc = _codeOf(_read('lib/services/tax_identity_service.dart'));
    userModelSrc = _codeOf(_read('lib/models/core/user_model.dart'));
    fcmSrc = _codeOf(_read('lib/services/fcm_service.dart'));
    legalTermsSrc = _read('lib/models/core/legal_terms_model.dart');
    firebaserc = _read('.firebaserc');
  });

  // ══════════════════════════════════════════════════════════════
  // A. 실제 수집 주체가 선언에 빠짐없이 들어 있는가
  // ══════════════════════════════════════════════════════════════

  group('DS-A 수집 주체 전수', () {
    test('DS-A1 모든 runtime 의존성이 문서에 분류돼 있다', () {
      final missing = <String>[];
      for (final d in _dependencies(pubspec)) {
        if (!doc.contains('`$d`')) missing.add(d);
      }
      expect(missing, isEmpty,
          reason: '새 SDK 가 들어왔는데 데이터 안전 선언이 그대로다. '
              '수집 주체인지 아닌지 문서에 적어야 한다: $missing');
    });

    test('DS-A2 모든 Android 권한이 문서에 설명돼 있다', () {
      final missing = <String>[];
      for (final p in _permissions(manifest)) {
        if (!doc.contains(p)) missing.add(p);
      }
      expect(missing, isEmpty,
          reason: '새 권한이 선언됐는데 실제 수집 여부가 문서에 없다: $missing');
    });

    test('DS-A3 선언에 쓴 data type 이 모두 Play taxonomy 안에 있다', () {
      final rows = RegExp(r'^\| ([A-Z][A-Za-z /·]+?) \| (?:\*\*)?(?:YES|NO)',
              multiLine: true)
          .allMatches(doc)
          .map((m) => m.group(1)!.trim())
          .toSet();
      expect(rows, isNotEmpty, reason: '선언 표를 하나도 읽지 못했다');
      final invented = rows.where((r) => !_playTaxonomy.contains(r)).toList();
      expect(invented, isEmpty, reason: '없는 data type 을 만들었다: $invented');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // B·C. Analytics / Crashlytics
  // ══════════════════════════════════════════════════════════════

  group('DS-B Analytics', () {
    test('DS-B1 Analytics 가 살아 있으면 선언에 있어야 한다', () {
      expect(analyticsSrc, contains('FirebaseAnalytics.instance'));
      expect(mainSrc, contains('AnalyticsService.observer'),
          reason: '화면 추적이 붙어 있다');
      expect(doc, contains('App interactions'));
      expect(_section(doc, '## 3. Firebase Analytics'), contains('YES'));
    });

    test('DS-B2 setUserId 전송 사실이 선언과 일치한다', () {
      expect(analyticsSrc, contains('setUserId'));
      expect(doc, contains('User IDs'));
      expect(doc, contains('setUserId(uid)'));
    });

    test('DS-B3 수집 opt-out 이 없다는 선언이 소스와 맞는다', () {
      // 토글이 생기면 Required 판정이 틀려진다 — 그때 이 테스트가 먼저 깨진다.
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        expect(_codeOf(f.readAsStringSync()),
            isNot(contains('setAnalyticsCollectionEnabled')),
            reason: '${f.path} — 수집 토글이 생겼다. Required 판정을 다시 해야 한다');
      }
      expect(_section(doc, '## 3. Firebase Analytics'), contains('없음'));
      expect(doc, contains('OPTIONAL = NO (Required)'));
    });
  });

  group('DS-C Crashlytics', () {
    test('DS-C1 Crashlytics 가 살아 있으면 선언에 있어야 한다', () {
      expect(mainSrc, contains('recordFlutterFatalError'));
      expect(doc, contains('Crash logs'));
      expect(doc, contains('Diagnostics'));
    });

    test('DS-C2 opt-out 없음 → Optional 로 쓰지 않았다', () {
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        expect(_codeOf(f.readAsStringSync()),
            isNot(contains('setCrashlyticsCollectionEnabled')),
            reason: '${f.path} — 수집 토글이 생겼다. Required 판정을 다시 해야 한다');
      }
      expect(_section(doc, '## 4. Firebase Crashlytics'), contains('Required'));
      // 선언 표에서도 Optional 로 적히지 않았는지 본다 — 결론이 사는 곳은 여기다.
      final decl = _section(doc, '### App info and performance');
      expect(decl, contains('**Required**'));
      expect(decl, isNot(contains('Optional')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // D. 정밀 위치
  // ══════════════════════════════════════════════════════════════

  group('DS-D 정밀 위치', () {
    test('DS-D1 수집기가 살아 있으면 선언이 있어야 한다', () {
      expect(locationSrc, contains('LocationAccuracy.high'));
      expect(attendanceSrc, contains('LocationHelper.getCurrentPosition'));
      expect(doc, contains('Precise location'));
      expect(doc, contains('checkInLat'));
    });

    test('DS-D2 백그라운드 미수집 선언이 소스와 맞는다', () {
      expect(manifest, isNot(contains('ACCESS_BACKGROUND_LOCATION')),
          reason: '백그라운드 위치 권한이 생기면 선언이 거짓이 된다');
      // 스트림 정의는 있어도 호출부가 0이어야 "앱을 쓰지 않는 동안 수집 없음"이 참이다.
      var callers = 0;
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('location_helper.dart')) continue;
        if (_codeOf(f.readAsStringSync()).contains('getPositionStream')) {
          callers++;
        }
      }
      expect(callers, 0, reason: '위치 스트림을 쓰기 시작했다 — 선언을 다시 써야 한다');
      expect(doc, contains('ACCESS_BACKGROUND_LOCATION'));
    });

    test('DS-D3 Required 판정에 서버 근거가 있다', () {
      final cf = _read('functions/src/index.ts');
      expect(cf, contains('출근 위치 정보(GPS)가 필요합니다'),
          reason: '좌표 없이 출근이 통과되면 Required 가 아니다');
      expect(doc, contains('Required'));
      expect(doc, contains('index.ts:32491'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // E·F. 금융 / 세무 식별정보
  // ══════════════════════════════════════════════════════════════

  test('DS-E 계좌 수집기가 살아 있으면 선언이 있어야 한다', () {
    expect(userModelSrc, contains('accountNumber'));
    expect(userModelSrc, contains('EncryptionHelper.decrypt'));
    expect(doc, contains('User payment info'));
    expect(doc, contains('Other financial info'));
  });

  test('DS-F 세무 식별정보 수집기가 살아 있으면 선언이 있어야 한다', () {
    expect(taxSrc, contains('callableRegisterTaxIdentity'));
    expect(doc, contains('callableGetTaxIdentityNumber'));
    expect(_section(doc, '## 5. 세무 식별정보'), contains('Other info'));
    // Play 에 항목이 없다는 이유로 신고를 빼지 않았다.
    expect(doc, contains('없다고 신고하지 않는다'));
  });

  test('DS-F2 기기 식별자 수집기가 살아 있으면 선언이 있어야 한다', () {
    expect(fcmSrc, contains('fcmTokens'));
    expect(doc, contains('Device or other IDs'));
  });

  // ══════════════════════════════════════════════════════════════
  // G. Required / Optional 에 사용자 통제 근거가 있는가
  // ══════════════════════════════════════════════════════════════

  group('DS-G Required/Optional 근거', () {
    test('DS-G1 Optional 로 적은 항목에는 실제 회피 경로가 있다', () {
      // 현재 Optional 은 Address 하나뿐이다 — 프로필 수정에서만 입력한다.
      expect(doc, contains('**Optional**'));
      expect(doc, contains('profile_edit_screen.dart:265'));
      final profile = _codeOf(_read('lib/screens/common/profile_edit_screen.dart'));
      expect(profile, contains("updates['address']"),
          reason: '주소 입력 경로가 사라지면 선언을 다시 써야 한다');
    });

    test('DS-G2 "기능이 선택사항"만으로 Optional 을 만들지 않았다', () {
      // 비콘 전용 사업장도 좌표를 요구한다 — 위치는 Optional 이 아니다.
      final cf = _read('functions/src/index.ts');
      expect(cf, contains('BARE_BEACON_REMOTE_CHECKIN'));
      final loc = _section(doc, '### Location');
      expect(loc, contains('**Required**'));
      expect(doc, contains('Optional 이 아니다'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // H. Shared = NO 에는 정확한 예외 근거가 붙어 있는가
  // ══════════════════════════════════════════════════════════════

  group('DS-H 공유 예외', () {
    test('DS-H1 예외 토큰 4종이 모두 정의돼 있다', () {
      for (final t in _exceptionTokens) {
        expect(doc, contains('`$t`'), reason: '예외 토큰 정의 누락: $t');
      }
    });

    test('DS-H2 모든 전달 항목이 예외 토큰을 갖는다', () {
      final s = _section(doc, '## 6. 신분증 / 통장 사본');
      const rows = [
        '이름 · 연락처 · 일반 지원 정보',
        '계좌 정보',
        '통장 사본 원본',
        '신분증 원본',
        '세무 식별번호',
        '정밀 위치',
        '본인인증 정보',
        '진단·이용 통계',
      ];
      for (final r in rows) {
        final line = s
            .split('\n')
            .firstWhere((l) => l.contains(r), orElse: () => '');
        expect(line, isNotEmpty, reason: '전달 항목 행이 없다: $r');
        expect(_exceptionTokens.any(line.contains), isTrue,
            reason: '$r — 예외 근거 없이 Shared=NO 로 적었다');
      }
    });

    test('DS-H3 한국 법 용어와 Play 기준을 섞지 않았다', () {
      expect(doc, contains('제3자 제공'));
      expect(doc, contains('같은 말로 쓰지 않는다'));
    });

    test('DS-H4 판정이 뒤집히는 조건을 적어 두었다', () {
      expect(doc, contains('이 판정이 뒤집히는 조건'));
      expect(doc, contains('Shared = YES'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // I·J. 삭제 URL / 방침 개정 정합
  // ══════════════════════════════════════════════════════════════

  group('DS-I 계정 삭제 진입점', () {
    test('DS-I1 공개 삭제 페이지가 실제로 있다', () {
      expect(File('public/account-deletion.html').existsSync(), isTrue);
      expect(doc, contains('https://alfit-89567.web.app/account-deletion'));
    });

    test('DS-I2 PROD URL 을 검증된 것처럼 적지 않았다', () {
      expect(firebaserc, contains('alfit-prod'));
      final s = _section(doc, '## 9. 계정 삭제 URL');
      expect(s, contains('alfit-prod'));
      expect(s, contains('미배포'),
          reason: '배포하지 않은 URL 을 제출용으로 확정하면 안 된다');
    });

    test('DS-I3 앱 내 삭제 경로가 문서에 적혀 있다', () {
      expect(doc, contains('callableDeleteAccountFinal'));
      expect(doc, contains('회원탈퇴'));
    });
  });

  test('DS-J 방침 개정과 선언 기준이 같다', () {
    final rev = RegExp(r"const kPrivacyPolicyRevision = '([^']+)';")
        .firstMatch(legalTermsSrc)!
        .group(1)!;
    expect(doc, contains(rev),
        reason: '방침이 개정됐는데 데이터 안전 문서가 옛 기준을 가리킨다');
  });

  // ══════════════════════════════════════════════════════════════
  // K. 제출 가능 상태인가
  // ══════════════════════════════════════════════════════════════

  test('DS-K 매트릭스에 UNKNOWN 이 남아 있지 않다', () {
    final upTo = doc.substring(0, doc.indexOf('\n## 10.'));
    for (final bad in ['UNKNOWN', 'TBD', '미정', '???']) {
      expect(upTo, isNot(contains(bad)),
          reason: '$bad 가 남아 있으면 제출용 final 이 아니다');
    }
  });

  test('DS-L 전송 암호화 답변에 전수 확인 근거가 있다', () {
    // 평문 HTTP 가 하나라도 생기면 "모두 암호화"는 거짓이 된다.
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final code = _codeOf(f.readAsStringSync());
      expect(code, isNot(contains('http://')),
          reason: '${f.path} — 평문 HTTP 경로가 생겼다');
    }
    expect(manifest, isNot(contains('usesCleartextTraffic')));
    expect(doc, contains('`http://` 0건'));
  });

  test('DS-M Play Console 제출 자체는 이 문서의 범위가 아니다', () {
    expect(doc, contains('제출물이 아니다'));
  });
}
