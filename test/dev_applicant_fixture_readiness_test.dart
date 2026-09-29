// DEV 지원자 fixture(test1~test6) 가 **실제 지원 게이트**를 지나는가.
//
//   시드 스크립트가 "READY" 라고 말하는 것만으로는 부족하다 — 그 스크립트는
//   게이트를 **재현**한 것이지 제품 코드가 아니다. 여기서는 시드된 문서를
//   `UserModel.fromMap` 으로 **제품 모델에 넣고**, 화면이 쓰는
//   `meetsApplyPrerequisites` 를 그대로 불러 판정한다.
//
//   입력은 DEV 에서 실제로 읽어 온 덤프다
//   (`scripts/seed_dev_applicants.js --check` 가 만드는 것과 같은 값).
//   개인정보는 없다 — 합성 계좌 끝 4자리와 fixture 이름뿐이다.

import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/screens/user/apply_prerequisites_screen.dart';
import 'package:ALfit/services/tax_identity_service.dart';
import 'package:ALfit/utils/identity_identifier.dart';

/// DEV 에서 읽어 온 시드 결과를 그대로 옮긴 것.
///   `residentNumber`·`ci` 는 **null** 이다 — 세무 수집이 꺼져 있어
///   지원 게이트가 묻지 않으므로 합성 주민번호를 저장하지 않았다.
Map<String, dynamic> _seeded({
  required String username,
  required String name,
  required String uid,
}) =>
    {
      'username': username,
      'name': name,
      'email': '$username@ALfit-system.com',
      'role': 'USER',
      'accountStatus': 'active',
      'passVerifiedAt': Timestamp.fromDate(DateTime(2026, 9, 29)),
      'idCardImagePath': 'users/$uid/idCard_1790667483846.jpg',
      'idCardVerifiedAt': Timestamp.fromDate(DateTime(2026, 9, 29)),
      'isIdVerified': true,
      'bankName': '국민은행',
      // 앱과 같은 형식(base64(IV):base64(ct)). 값 자체는 검증 대상이 아니다 —
      // 게이트는 "있는가" 만 묻는다.
      'accountNumber': 'AAAAAAAAAAAAAAAAAAAAAA==:BBBBBBBBBBBBBBBBBBBBBB==',
      'accountHolder': name,
      'bankbookImagePath': 'users/$uid/bankbook_1790667484688.jpg',
      'bankbookUploadedAt': Timestamp.fromDate(DateTime(2026, 9, 29)),
      'isBlacklisted': false,
      'restrictedUntil': null,
      'residentNumber': null,
      'ci': null,
      'foreignIdNumber': null,
      'homeRegion': {
        'province': '서울특별시',
        'city': '강남구',
        'district': '역삼동',
      },
      'notifPrefs': {
        'workReminder': true,
        'applicationUpdate': true,
        'reviewAlert': true,
        'contractAlert': true,
        'wageAlert': true,
        'toMatchAlert': true,
      },
      'subAdminBusinessIds': <String>[],
      'devFixture': true,
    };

const _fixtures = <List<String>>[
  ['test1', '테스트하나', 'psKpbHANvkdPU9PgJoBiPNoeIT93'],
  ['test2', '테스트둘', 'XbPwShFixtureUid2'],
  ['test3', '테스트셋', 'dDxuqjFixtureUid3'],
  ['test4', '테스트넷', '6lJF4KFixtureUid4'],
  ['test5', '테스트다섯', 'pXr1U9FixtureUid5'],
  ['test6', '테스트여섯', 'MdF4zJFixtureUid6'],
];

/// 현재 DEV 의 세무 수집 설정 — `app_settings/tax_identity_collection.enabled`
/// 가 **false** 다. 그래서 세무 축은 지원을 막지 않는다.
const _taxOff = TaxIdentityStatus(
  registered: false,
  identifierType: null,
  collectionEnabled: false,
  documentMatch: DocFieldOutcome.unassessed,
  documentMatchCurrent: false,
  loadFailed: false,
);

void main() {
  group('DEV fixture 지원자 — 지원 게이트', () {
    for (final f in _fixtures) {
      final username = f[0], name = f[1], uid = f[2];

      test('$username 은 장기·단기 공고 모두 지원 가능하다', () {
        final u = UserModel.fromMap(_seeded(
          username: username,
          name: name,
          uid: uid,
        ), uid);

        // 화면이 부르는 그 함수다.
        expect(
            meetsApplyPrerequisites(u, isFlexType: false, taxStatus: _taxOff),
            isTrue,
            reason: '장기(슬롯 없는) 공고');
        expect(
            meetsApplyPrerequisites(u, isFlexType: true, taxStatus: _taxOff),
            isTrue,
            reason: '단기(슬롯) 공고 — isIdVerified 추가 요구');

        // canonical readiness getter 도 같은 답을 해야 한다.
        expect(u.hasApplicationDocumentsReady, isTrue);
        expect(u.hasWageDocumentsReady, isTrue);
      });
    }

    test('role 은 USER 이고 관리자 권한이 없다', () {
      for (final f in _fixtures) {
        final u = UserModel.fromMap(
            _seeded(username: f[0], name: f[1], uid: f[2]), f[2]);
        expect(u.role, UserRole.USER);
        expect(u.isBusinessAdmin, isFalse);
        expect(u.isSuperAdmin, isFalse);
        expect(u.isSubAdmin, isFalse, reason: 'subAdminBusinessIds 비어 있다');
      }
    });

    test('예금주는 본인 이름이다 — 가입 writer 와 같은 규칙', () {
      for (final f in _fixtures) {
        final u = UserModel.fromMap(
            _seeded(username: f[0], name: f[1], uid: f[2]), f[2]);
        expect(u.accountHolder, u.name);
      }
    });

    test('주민번호·CI 를 저장하지 않았다 — 세무 수집 OFF 라 게이트가 묻지 않는다', () {
      for (final f in _fixtures) {
        final u = UserModel.fromMap(
            _seeded(username: f[0], name: f[1], uid: f[2]), f[2]);
        expect(u.residentNumber, isNull);
        expect(u.ci, isNull);
        // 그래도 내국인 지원 게이트는 통과한다(passVerifiedAt 로).
        expect(u.isPassVerified, isTrue);
        expect(u.isForeign, isFalse);
      }
    });
  });

  group('게이트가 실제로 판별력이 있다 (반례)', () {
    UserModel withPatch(Map<String, dynamic> patch) {
      final m = _seeded(username: 'test1', name: '테스트하나', uid: 'u1')
        ..addAll(patch);
      return UserModel.fromMap(m, 'u1');
    }

    test('통장사본이 없으면 막힌다', () {
      final u = withPatch({'bankbookImagePath': null, 'bankbookImageUrl': null});
      expect(meetsApplyPrerequisites(u, isFlexType: false, taxStatus: _taxOff),
          isFalse);
    });

    test('계좌 정보가 없으면 막힌다', () {
      final u = withPatch({'bankName': null});
      expect(meetsApplyPrerequisites(u, isFlexType: false, taxStatus: _taxOff),
          isFalse);
    });

    test('신분증이 없으면 막힌다', () {
      final u = withPatch({'idCardImagePath': null, 'idCardImageUrl': null});
      expect(meetsApplyPrerequisites(u, isFlexType: false, taxStatus: _taxOff),
          isFalse);
    });

    test('isIdVerified 가 false 면 **단기만** 막힌다', () {
      final u = withPatch({'isIdVerified': false});
      expect(meetsApplyPrerequisites(u, isFlexType: false, taxStatus: _taxOff),
          isTrue, reason: '장기는 통과');
      expect(meetsApplyPrerequisites(u, isFlexType: true, taxStatus: _taxOff),
          isFalse, reason: '단기(슬롯)는 막힌다');
    });

    test('passVerifiedAt 이 없으면 내국인은 막힌다', () {
      final u = withPatch({'passVerifiedAt': null});
      expect(meetsApplyPrerequisites(u, isFlexType: false, taxStatus: _taxOff),
          isFalse);
    });

    test('세무 수집이 켜지면 등록 없이는 막힌다 — 이 fixture 의 전제', () {
      // 지금 DEV 는 꺼져 있다. 켜지는 순간 이 계정들은 taxIdentities 가
      // 없어서 막힌다 — 시드가 그 문서를 만들지 않았기 때문이다(의도).
      const taxOn = TaxIdentityStatus(
        registered: false,
        identifierType: null,
        collectionEnabled: true,
        documentMatch: DocFieldOutcome.unassessed,
        documentMatchCurrent: false,
        loadFailed: false,
      );
      final u = withPatch({});
      expect(meetsApplyPrerequisites(u, isFlexType: false, taxStatus: taxOn),
          isFalse,
          reason: '세무 수집이 켜지면 CF 전용 authority 로 별도 등록이 필요하다');
    });
  });
}
