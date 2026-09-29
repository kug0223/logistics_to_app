// test/utils/trust_score_helper_test.dart
//
// [R7-FS-1 A] 이 파일의 원래 주제는 **신뢰도 점수 공식**이었다
//   (`TrustScoreHelper.calculate` / `calculateFromData`, 기준점 60, 경험
//   가산, 평판 기여, 노쇼·지각 감점, storedTrustScore 우선 …  485줄).
//
//   그 체계는 제품에서 폐기됐다([5A.2A]):
//     · `lib/utils/trust_score_helper.dart` 삭제
//     · `UserModel.storedTrustScore` 필드 삭제
//     · `UserModel.trustScore / trustGrade / trustGradeEmoji` getter 삭제
//     · Firestore 의 `trustScore` 필드는 읽지도 쓰지도 않는다
//
//   그래서 이 파일은 오랫동안 **컴파일조차 되지 않았다**(존재하지 않는
//   import). 되살릴 공식이 없으므로 셀을 하나씩 옮길 대상도 없다.
//   대신 두 가지를 지킨다:
//
//     1. 폐기가 **유지되는가** — 누가 점수/등급을 조용히 되살리면 걸린다.
//     2. 그 자리를 이어받은 축이 **실제로 동작하는가** — 누적 노쇼가
//        만드는 제재(`noShowCount` / `recentNoShowCount` / `restrictedUntil`
//        / `isRestricted`)와 그것을 읽는 canonical 소비자.
//
//   점수를 지웠다는 사실만 적어 두면 다음 사람이 "그럼 노쇼는 어디서
//   막히나" 를 다시 찾아야 한다. 여기에 답을 둔다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/user_model.dart';

// ── 최소 UserModel 생성 헬퍼 ──────────────────────────────────────
UserModel _user({
  int noShowCount = 0,
  int recentNoShowCount = 0,
  int lateCount = 0,
  DateTime? restrictedUntil,
}) =>
    UserModel(
      uid: 'u1',
      username: 'tester',
      name: '테스터',
      email: 'test@example.com',
      role: UserRole.USER,
      noShowCount: noShowCount,
      recentNoShowCount: recentNoShowCount,
      lateCount: lateCount,
      restrictedUntil: restrictedUntil,
    );

String _read(String p) {
  final f = File(p);
  expect(f.existsSync(), isTrue, reason: '$p 를 찾지 못함');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

void main() {
  // ══════════════════════════════════════════════════════════════
  // A. 폐기가 유지된다
  // ══════════════════════════════════════════════════════════════
  group('A. 신뢰도 점수/등급 폐기 유지', () {
    test('A-01: trust_score_helper.dart 가 없다', () {
      expect(File('lib/utils/trust_score_helper.dart').existsSync(), isFalse,
          reason: '점수 공식을 되살리지 않는다');
    });

    test('A-02: UserModel 에 점수·등급 멤버가 없다', () {
      final src = _read('lib/models/core/user_model.dart');
      for (final name in const [
        'storedTrustScore',
        'get trustScore',
        'get trustGrade',
        'get trustGradeEmoji',
      ]) {
        // 주석에 남은 폐기 기록은 허용한다 — 코드로 살아나는 것만 막는다.
        final codeOnly = src
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(codeOnly.contains(name), isFalse, reason: '$name 이 되살아났다');
      }
    });

    test('A-03: Firestore 의 trustScore 필드를 쓰지 않는다', () {
      final codeOnly = _read('lib/models/core/user_model.dart')
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(codeOnly.contains("'trustScore'"), isFalse);
    });

    test('A-04: 근무가능인력 표면도 점수를 노출하지 않는다', () {
      // 이 파일의 머리말이 노출 금지 목록으로 그것을 적고 있다.
      final codeOnly = _read('lib/models/core/available_worker_model.dart')
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//') &&
              !l.trimLeft().startsWith('///'))
          .join('\n');
      expect(codeOnly.contains('trustScore'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // B. 점수를 대신하는 축 — 누적 노쇼와 제재
  // ══════════════════════════════════════════════════════════════
  group('B. 노쇼 카운트', () {
    test('B-01: 기본값은 0 이다 — 모르는 상태를 감점으로 만들지 않는다', () {
      final u = _user();
      expect(u.noShowCount, 0);
      expect(u.recentNoShowCount, 0);
    });

    test('B-02: 문서에 최근 카운터가 없으면 누적값으로 떨어진다', () {
      // 90일 카운터는 CF 가 갱신한다. 아직 한 번도 갱신되지 않은 문서에서
      // 0 으로 읽히면 "최근 노쇼 없음" 이 되어 제재 판정이 느슨해진다.
      // 폴백은 생성자가 아니라 **파싱 자리**에 있다.
      final u = UserModel.fromMap({
        'username': 'tester',
        'name': '테스터',
        'email': 'test@example.com',
        'role': 'USER',
        'noShowCount': 4,
        // recentNoShowCount 키 없음 — 미갱신 계정
      }, 'u1');
      expect(u.recentNoShowCount, 4, reason: '미갱신은 누적으로 본다');

      // 키가 있으면 그것을 쓴다.
      final fresh = UserModel.fromMap({
        'username': 'tester',
        'name': '테스터',
        'email': 'test@example.com',
        'role': 'USER',
        'noShowCount': 9,
        'recentNoShowCount': 2,
      }, 'u1');
      expect(fresh.recentNoShowCount, 2);
    });

    test('B-03: 누적과 최근은 서로 다른 값이다', () {
      final u = _user(noShowCount: 9, recentNoShowCount: 2);
      expect(u.noShowCount, 9);
      expect(u.recentNoShowCount, 2);
    });
  });

  group('C. 제재 판정 (isRestricted)', () {
    test('C-01: 제재 시각이 없으면 제재가 아니다', () {
      expect(_user().isRestricted, isFalse);
      expect(_user(noShowCount: 99).isRestricted, isFalse,
          reason: '노쇼 수 자체가 제재는 아니다 — 서버가 제재 시각을 준다');
    });

    test('C-02: 미래 시각이면 제재 중이다', () {
      final u = _user(
          restrictedUntil: DateTime.now().add(const Duration(hours: 1)));
      expect(u.isRestricted, isTrue);
    });

    test('C-03: 지난 시각이면 자동으로 풀린다', () {
      final u = _user(
          restrictedUntil: DateTime.now().subtract(const Duration(hours: 1)));
      expect(u.isRestricted, isFalse,
          reason: '만료를 지우는 writer 없이도 화면에서 풀려야 한다');
    });

    test('C-04: 영구 제재 표식(year 9999)은 풀리지 않는다', () {
      expect(_user(restrictedUntil: DateTime(9999)).isRestricted, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // D. 그 판정을 실제로 읽는 자리 — 점수가 아니라 제재가 지원을 막는다
  // ══════════════════════════════════════════════════════════════
  group('D. 제재가 지원을 막는다', () {
    test('D-01: 공고 화면이 restrictedUntil 로 남은 기간을 말한다', () {
      final src = _read('lib/screens/common/job_posting_screen.dart');
      expect(src.contains('user.restrictedUntil'), isTrue);
    });

    test('D-02: 지원 준비 화면도 같은 필드를 본다 — 점수가 아니다', () {
      final src = _read('lib/screens/user/apply_prerequisites_screen.dart');
      expect(src.contains('restrictedUntil'), isTrue);
      final codeOnly = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(codeOnly.contains('trustScore'), isFalse,
          reason: '지원 자격을 점수로 판정하지 않는다');
    });
  });
}
