// [R7-P4.4E.10A.1 / E10-D] 재업로드 늦은 완료가 현재 문서를 되살리지 않는다.
//
// 결함: `callableMarkIdCardVerified` 는 **도착 순서**만 알았다.
//   A→B 순서로 올렸는데 A 의 호출이 나중에 완료되면 A 가 `cur + 1` 로 더 높은
//   버전을 받고 **A 의 경로·근거가 현재 truth** 가 됐다 — 바꿔치기한 옛 문서가
//   최신이 된다. 클라이언트 `_isLoading` 가드는 같은 화면 내 이중 시작만 막는다.
//
// Storage 확인(§9): 경로가 이미 `users/{uid}/idCard_{millis}.jpg` 로
//   **attempt 별로 다르다.** 그리고 지울 옛 경로(`oldPath`)는 업로드 **전**에
//   캡처되므로 늦은 A 가 B 의 물리 파일을 지우지도 않는다. 그래서 막아야 하는
//   것은 **Firestore 의 현재 포인터** 하나이고, 서버 finalize 가드로 충분하다.
//   Storage 계약을 리팩터하지 않았다.
//
// 이 파일은 CF/클라이언트 **소스 계약**을 고정한다 — DEV 배포 전에는 runtime
// 으로 확인할 수 없으므로, 배포 후 §14 runtime matrix 로 다시 본다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) {
    throw StateError('소스를 찾지 못했다: $p');
  }
  return f.readAsStringSync();
}

/// 주석을 뺀 실행 코드만 — 계약은 주석에 대한 것이 아니다.
String _codeOf(String src) => src
    .split(RegExp(r'\r?\n'))
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  final cf = _flat(_codeOf(_src('functions/src/index.ts')));
  final screen = _flat(
      _codeOf(_src('lib/screens/common/document_management_screen.dart')));

  group('SUB-1x 서버 순번', () {
    test('SUB-10 제출 시작 callable 이 서버 순번을 발급한다', () {
      expect(cf, contains('export const callableBeginIdDocumentSubmission'));
      expect(cf, contains('idDocumentAttemptSeq'));
      expect(cf, contains('return {attemptSeq: seq};'));
    });

    test('SUB-11 순번은 트랜잭션에서 증가한다', () {
      expect(cf, contains('tx.update(ref, {idDocumentAttemptSeq: next});'),
          reason: '동시 begin 이 같은 순번을 받으면 가드가 성립하지 않는다');
    });

    test('SUB-12 finalize 가 자기 순번보다 새 제출이 있으면 no-op', () {
      expect(cf, contains('if (myAttemptSeq !== null && myAttemptSeq < latestSeq)'),
          reason: '늦게 도착한 옛 제출은 아무것도 바꾸지 않는다');
      expect(cf, contains('return null; // stale — no-op'));
      expect(cf, contains('return {success: false, stale: true};'));
    });

    test('SUB-13 클라이언트 시계를 권위로 쓰지 않는다', () {
      // 순번은 서버가 센다 — 클라이언트가 보낸 시각으로 순서를 정하지 않는다.
      expect(cf, isNot(contains('clientSubmittedAt')));
      expect(cf, isNot(contains('clientTimestamp')));
    });

    test('SUB-14 순번이 없는 구버전 호출은 종전대로 받는다', () {
      // 거부하면 배포 전 앱이 신분증을 등록할 수 없게 된다.
      expect(cf, contains('attemptSeq > 0 ? attemptSeq : null'));
    });

    test('SUB-15 stale 은 버전·경로·판정을 바꾸지 않는다', () {
      // no-op 이 트랜잭션 **안에서** 먼저 돌아가므로 tx.update 에 도달하지
      //   않는다 — 버전 증가·현재 경로·판정·검토 필드 전부 그대로다.
      final idx = cf.indexOf('return null; // stale — no-op');
      final upd = cf.indexOf('tx.update(idUserRef, {');
      expect(idx, greaterThan(0));
      expect(upd, greaterThan(idx),
          reason: 'stale 반환이 쓰기보다 앞에 있어야 한다');
    });
  });

  group('SUB-2x 클라이언트 연결', () {
    test('SUB-20 업로드 전에 순번을 받는다', () {
      expect(screen, contains("httpsCallable('callableBeginIdDocumentSubmission')"));
      expect(screen, contains("attemptSeq = (begin.data['attemptSeq'] as num?)?.toInt();"));
    });

    test('SUB-21 finalize 에 순번을 함께 보낸다', () {
      expect(screen, contains("if (attemptSeq != null) 'attemptSeq': attemptSeq,"));
    });

    test('SUB-22 순번 발급 실패가 등록을 막지 않는다', () {
      expect(screen, contains('순번 없이 진행'),
          reason: '가드는 안전장치다 — 그것 때문에 등록이 불가능해지면 안 된다');
    });

    test('SUB-23 Storage 경로는 attempt 별로 다르다 (§9)', () {
      expect(screen,
          contains("'users/\${user.uid}/idCard_\${DateTime.now().millisecondsSinceEpoch}.jpg'"),
          reason: '같은 object 를 덮어쓰면 서버 가드만으로 부족하다');
    });
  });

  group('SUB-3x 서버 구조 재검증', () {
    test('SUB-30 서버가 후보 구조를 다시 본다', () {
      expect(cf, contains('idUsableCandidates'));
      expect(cf, contains('idIsForeignUser ? [5, 6, 7, 8] : [1, 2, 3, 4]'),
          reason: '내국인 1~4 / 외국인 5~8');
    });

    test('SUB-31 구조를 만족하는 후보가 없으면 UNREADABLE', () {
      expect(cf,
          contains('if (idUsableCandidates.length === 0) { srvIdentifierOutcome = DOC_FIELD_UNREADABLE;'));
    });

    test('SUB-32 일치는 지문으로만 판정한다', () {
      expect(cf,
          contains('srvTaxIdentifierFingerprint(c) === canonicalFpForId'));
    });

    test('SUB-33 canonical 평문을 돌려주지 않는다', () {
      // 반환은 상태뿐이다. 응답에 주민번호를 싣지 않는다.
      expect(cf, isNot(contains('residentNumberPlain')));
      expect(cf, isNot(contains('return {residentNumber')));
    });

    test('SUB-34 legacy checksum 을 hard gate 로 쓰지 않는다', () {
      expect(cf, isNot(contains('rrnChecksum')));
      expect(cf, isNot(contains('checksumValid')));
    });
  });
}
