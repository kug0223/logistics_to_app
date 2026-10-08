// [R7-P4.4E.11C.0C.0a.4.1] cleanup key 를 바꿀 수 있으면 삭제는 그냥 실패한다
//
// 탈퇴 cleanup 은 행을 **field 로** 찾는다. 그 field 를 기존 행에서 다른 값으로
// 바꿀 수 있으면 쿼리가 그 행을 영원히 못 찾고, 삭제는 "성공"하고 데이터는
// 남는다. create 를 막는 것만으로는 부족하다.
//
// 그리고 그 통로는 하나였다 — 여섯 컬렉션의 `allow update` 가 모두 **필드 제한
// 없는 `isSuperAdmin()`** 으로 끝나거나(members·초대·열람요청·review_requests·
// applications) SUPER_ADMIN 분기에서 그 key 를 빼먹고 있었다(attendance).
//
// 이 파일은 그 불변 조건이 **분기 괄호 앞**에 있다는 것까지 고정한다. 뒤에 있으면
// `isSuperAdmin()` 으로 우회된다.
//
// 동작 검증은 rules 에뮬레이터가 한다
// (rules-test/src/rules/cleanup_key_immutability.test.ts). 이 파일은 Flutter
// 스위트에서 **조건이 제거되는 것**을 잡는 소스 핀이다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

int _at(String s, String needle) {
  final i = s.indexOf(needle);
  if (i < 0) throw StateError('경계를 찾지 못함: $needle');
  return i;
}

/// `match` 블록 안에서 `allow update:` 절만 떼어낸다.
///
///   블록 시작부터 자르면 앞선 `allow get`·`allow list` 의 `isSuperAdmin()` 이
///   끼어들어 "불변 조건이 분기보다 앞인가"를 엉뚱한 것과 비교하게 된다.
String _updateClause(String rules, String matchLine) {
  final a = _at(rules, matchLine);
  final u = rules.indexOf('allow update:', a);
  if (u < 0) throw StateError('allow update 를 찾지 못함: $matchLine');
  // 절의 끝 — 다음 `allow ` 선언 직전.
  final nxt = rules.indexOf('      allow ', u + 10);
  final end = nxt < 0 ? rules.length : nxt;
  return _flat(rules.substring(u, end));
}

const _immutableConjunct =
    '!request.resource.data.diff(resource.data).affectedKeys() .hasAny(';

void main() {
  final rules = _src('firestore.rules');

  /// 불변 조건이 존재하고, **모든 분기보다 앞**에 있는지 확인한다.
  void expectKeysImmutable(
    String matchLine,
    String keyList, {
    String? branchMarker,
  }) {
    final c = _updateClause(rules, matchLine);
    final guard = '$_immutableConjunct$keyList)';
    expect(c, contains(guard),
        reason: '$matchLine 의 update 에 cleanup key 불변 조건이 없다');
    final marker = branchMarker ?? 'isSuperAdmin()';
    expect(c, contains(marker),
        reason: '$matchLine 에 $marker 분기가 있어야 이 단정이 의미를 갖는다');
    expect(c.indexOf(guard), lessThan(c.indexOf(marker)),
        reason: '불변 조건이 $marker 뒤에 있으면 역할로 우회된다');
  }

  group('CK-SRC-0x — 이번에 닫은 여섯 컬렉션', () {
    test('CK-SRC-01 members.uid / businessId', () {
      expectKeysImmutable(
          'match /businesses/{businessId}/members/{uid}', "['uid', 'businessId']");
    });

    test('CK-SRC-02 member_invitations.targetUid / invitedBy', () {
      expectKeysImmutable('match /member_invitations/{invitationId}',
          "['targetUid', 'invitedBy']");
    });

    test('CK-SRC-03 idCardAccessRequests.targetUserId / requesterId', () {
      expectKeysImmutable('match /idCardAccessRequests/{requestId}',
          "['targetUserId', 'requesterId']");
    });

    test('CK-SRC-04 review_requests.workerId', () {
      expectKeysImmutable('match /review_requests/{requestId}', "['workerId']");
    });

    test('CK-SRC-05 applications.uid', () {
      // [R7-PAYROLL-POLICY.4A] 같은 불변 조건에 근태 기준 snapshot·확인 기록이
      //   함께 들어갔다(그 둘도 CF 전용이다). 지키려던 것은 **`uid` 가 그
      //   목록에 있고 분기보다 앞이라는 것**이므로 목록이 길어진 사실만
      //   반영한다 — 한 글자도 바꾸지 않은 계약이다.
      expectKeysImmutable('match /applications/{applicationId}',
          "['uid', 'attendancePolicySnapshot', "
              "'attendancePolicyAcknowledgement']");
    });

    test('CK-SRC-06 attendance.userId', () {
      // attendance 의 update 는 분기 앞에 여러 공통 조건이 있고 SUPER_ADMIN
      // 분기는 `(isSuperAdmin() &&` 형태다.
      expectKeysImmutable('match /attendance/{attendanceId}', "['userId']",
          branchMarker: '(isSuperAdmin() &&');
    });
  });

  group('CK-SRC-1x — 이미 안전했던 것들 (계약 고정)', () {
    test('CK-SRC-10 monthly_reviews 는 SUPER_ADMIN 분기에서 key 를 제외한다', () {
      final c = _updateClause(rules, 'match /monthly_reviews/{reviewId}');
      expect(c, contains('isSuperAdmin() &&'));
      expect(c, contains("'reviewerId', 'targetUserId', 'businessId'])"));
      // SUPER_ADMIN 분기가 제외 목록 **없이** 끝나지 않는다.
      expect(c, isNot(contains('|| isSuperAdmin() );')));
    });

    test('CK-SRC-11 trust_score_history 는 update surface 자체가 없다', () {
      final c = _updateClause(rules, 'match /trust_score_history/{historyId}');
      expect(c, contains('allow update: if false;'));
    });

    test('CK-SRC-12 schedule_change_requests 도 update 가 없다', () {
      final c =
          _updateClause(rules, 'match /schedule_change_requests/{requestId}');
      expect(c, contains('allow update: if false;'));
    });

    test('CK-SRC-13 payment_change_requests 는 공통 hasOnly 로 막힌다', () {
      // 두 번째 괄호가 **모든 actor** 에 적용된다 — SUPER_ADMIN 도 status·
      // processedBy·processedAt·rejectReason·updatedAt 만 바꿀 수 있다.
      final c =
          _updateClause(rules, 'match /payment_change_requests/{reqId}');
      expect(c, contains("hasOnly(['status', 'processedBy', 'processedAt',"));
      expect(c, isNot(contains('workerId')));
    });

    test('CK-SRC-14 worker_locations 는 클라이언트 쓰기가 전면 차단이다', () {
      final i = _at(rules, 'match /worker_locations/{locationId}');
      final seg = _flat(rules.substring(i, i + 200));
      expect(seg, contains('allow read, write: if false;'));
    });
  });

  group('CK-SRC-2x — docId 로 식별되는 상태 (§41·§42)', () {
    test('CK-SRC-20 update 로 문서 ID 를 바꿀 수 없다 — 대상 목록', () {
      // 이 넷은 cleanup key 가 문서 ID 다. Firestore 에서 문서 ID 는 update 로
      // 바뀌지 않으므로 key evasion 이 구조적으로 불가능하다.
      for (final m in [
        'match /worker_availability/{uid}',
        'match /trust_settings/',
        'match /taxIdentities/{uid}',
        'match /nativeIdentityFingerprints/{fpId}',
        'match /foreignIdFingerprints/{fpId}',
      ]) {
        // trust_settings 는 rules 에 match 가 없다(최상위 wildcard 차단) —
        // 그 사실 자체를 기록한다.
        if (m == 'match /trust_settings/') {
          expect(rules, isNot(contains(m)),
              reason: 'trust_settings 는 catch-all 로 차단된다');
          continue;
        }
        expect(rules, contains(m), reason: '$m 블록이 사라졌다');
      }
    });

    test('CK-SRC-21 최상위 wildcard 가 여전히 전면 차단이다', () {
      expect(_flat(rules),
          contains('match /{document=**} { allow read, write: if false; }'));
    });
  });

  group('CK-SRC-3x — .0a.4 barrier 회귀 (§72)', () {
    test('CK-SRC-30 create barrier 세 곳이 그대로다', () {
      expect(rules, contains('function accountDeletionBarrierExists(uid)'));
      final mem = _flat(_src('firestore.rules'));
      expect(mem, contains('!accountDeletionBarrierExists(uid) &&'));
      expect(mem,
          contains('!accountDeletionBarrierExists(request.resource.data.targetUid)'));
      expect(
          mem,
          contains(
              '!accountDeletionBarrierExists(request.resource.data.targetUserId)'));
    });

    test('CK-SRC-31 members create 의 path↔data binding 이 그대로다', () {
      final i = _at(rules, 'match /businesses/{businessId}/members/{uid}');
      final u = rules.indexOf('allow update:', i);
      final createClause = _flat(rules.substring(i, u));
      expect(createClause, contains("request.resource.data.get('uid', '') == uid"));
      expect(createClause,
          contains("request.resource.data.get('businessId', '') == businessId"));
    });

    test('CK-SRC-32 tombstone 은 클라이언트에게 닫혀 있다', () {
      final i = _at(rules, 'match /account_deletion_tombstones/{uid}');
      final seg = _flat(rules.substring(i, i + 300));
      expect(seg, contains('allow read: if false;'));
      expect(seg, contains('allow create: if false;'));
      expect(seg, contains('allow update: if false;'));
      expect(seg, contains('allow delete: if false;'));
    });
  });

  group('CK-SRC-4x — 서버(Admin SDK) identity 재지정 writer 0 (§48~§50)', () {
    final fnSrc = _src('functions/src/index.ts');

    test('CK-SRC-40 members 는 CF 에 update writer 가 없다', () {
      // 생성 1곳(tx.set) · 삭제 경로만 존재한다. update 가 생기면 Rules 를
      // 우회하므로 이 단정이 먼저 깨져야 한다.
      expect(fnSrc, contains('tx.set(memberRef, {'));
      expect(fnSrc, isNot(contains('tx.update(memberRef')));
      expect(fnSrc, isNot(contains('memberRef.update(')));
    });

    test('CK-SRC-41 cleanup key 를 재지정하는 CF 패치가 없다', () {
      // 서버가 기존 행의 소유자를 다른 사람으로 바꾸는 코드가 있으면
      // Rules 불변성은 무의미하다.
      for (final bad in [
        'targetUid: newUid',
        'workerId: newUid',
        'targetUserId: newUid',
        'reassignWorker',
        'reassignTarget',
      ]) {
        expect(fnSrc, isNot(contains(bad)));
      }
    });

    test('CK-SRC-42 review/monthly CF update 는 게시 필드만 바꾼다', () {
      // `isPublished`/`publishedAt` 외의 identity 변경이 없다는 근거를 고정한다.
      expect(_flat(fnSrc),
          contains('batch.update(reqRef, {isPublished: true, publishedAt: now});'));
    });
  });
}
