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
      // [R7-P4.4E.10A.2 갱신] 분기가 fail-closed 로 바뀌었다(§1).
      expect(cf.contains('} else if (myAttemptSeq < latestSeq) {'), isTrue,
          reason: '늦게 도착한 옛 제출은 아무것도 바꾸지 않는다');
      expect(cf.contains('reason: "stale-seq"'), isTrue);
      expect(cf.contains('return {success: false, stale: true, reason:'), isTrue);
    });

    test('SUB-13 클라이언트 시계를 권위로 쓰지 않는다', () {
      // 순번은 서버가 센다 — 클라이언트가 보낸 시각으로 순서를 정하지 않는다.
      expect(cf, isNot(contains('clientSubmittedAt')));
      expect(cf, isNot(contains('clientTimestamp')));
    });

    test('SUB-14 protocol 이 켜진 사용자는 순번 없는 finalize 를 못 쓴다', () {
      // [R7-P4.4E.10A.2 / §1 갱신] 예전에는 순번이 없으면 **무조건** 받았다.
      //   그건 가드를 우회하는 길이었다 — 늦은 호출이 순번을 빼고 오면
      //   그대로 현재 truth 가 됐다. 이제 fail-closed 다:
      //     latestSeq == 0 (protocol 미사용) + 순번 없음 → legacy 허용
      //     latestSeq  > 0 (protocol 사용)   + 순번 없음 → no-op
      expect(cf, contains('attemptSeq > 0 ? attemptSeq : null'),
          reason: '순번 파싱은 그대로');
      expect(cf, contains('if (myAttemptSeq === null) { if (latestSeq > 0) {'),
          reason: 'protocol 이 켜졌으면 순번 없는 finalize 를 거절한다');
      expect(cf, contains('reason: "missing-seq"'));
      expect(cf, contains('reason: "stale-seq"'));
    });

    test('SUB-15 stale 은 버전·경로·판정을 바꾸지 않는다', () {
      // no-op 이 트랜잭션 **안에서** 먼저 돌아가므로 tx.update 에 도달하지
      //   않는다 — 버전 증가·현재 경로·판정·검토 필드 전부 그대로다.
      final idx = cf.indexOf('reason: "stale-seq"');
      final upd = cf.indexOf('tx.update(idUserRef, {');
      expect(idx, greaterThan(0));
      expect(upd, greaterThan(idx),
          reason: 'stale 반환이 쓰기보다 앞에 있어야 한다');
    });
  });

  group('SUB-2x 클라이언트 연결', () {
    test('SUB-20 업로드 전에 순번을 받는다', () {
      expect(screen, contains("httpsCallable('callableBeginIdDocumentSubmission')"));
      expect(screen, contains("final seq = (begin.data['attemptSeq'] as num?)?.toInt();"));
    });

    test('SUB-21 finalize 에 순번을 함께 보낸다', () {
      expect(screen, contains("'attemptSeq': attemptSeq,"));
    });

    test('SUB-22 순번을 못 받으면 finalize 까지 가지 않는다', () {
      // [R7-P4.4E.10A.2 / §2 갱신] 예전 계약은 "순번 없이 진행" 이었다.
      //   서버가 fail-closed 가 된 지금 그대로 진행하면 업로드만 하고 등록은
      //   실패하는 더 나쁜 결과가 된다. 재시도 가능한 오류로 말하고 끝낸다.
      expect(screen, isNot(contains('순번 없이 진행')));
      expect(screen, contains("throw StateError('attemptSeq 없음');"));
      expect(screen, contains('return; // finalize 까지 진행하지 않는다'));
      expect(screen, contains("ToastHelper.showError('잠시 후 다시 시도해주세요')"),
          reason: '사용자가 무엇을 할 수 있는지 말한다');
    });

    test('SUB-24 finalize 는 항상 순번을 보낸다', () {
      expect(screen, contains("'attemptSeq': attemptSeq,"));
      expect(screen, isNot(contains("if (attemptSeq != null) 'attemptSeq'")),
          reason: '조건부가 아니다 — 없으면 애초에 여기 오지 않는다');
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

  // ══════════════════════════════════════════════════════════════
  // [R7-P4.4E.10A.2 §3·§4·§5·§6] 고아 object 정리
  // ══════════════════════════════════════════════════════════════
  group('SUB-4x 정리', () {
    test('SUB-40 stale 제출이 올린 object 를 치운다', () {
      expect(cf, contains('await srvDeleteOrQueueOrphan( callerUid, storagePath, idTxResult.curPath);'),
          reason: 'stale 이 남긴 파일을 그냥 두지 않는다');
    });

    test('SUB-41 현재 accepted 경로는 절대 지우지 않는다 (§4)', () {
      expect(cf, contains('if (protect !== null && path === protect) return;'),
          reason: '정리가 데이터 손실이 되면 안 된다');
    });

    test('SUB-42 남의 경로는 건드리지 않는다', () {
      expect(cf, contains(r'if (!path.startsWith(`users/${uid}/`)) return;'));
    });

    test('SUB-43 멱등 — 이미 없는 파일은 성공과 같다 (§5)', () {
      expect(cf, contains('.delete({ignoreNotFound: true});'));
    });

    test('SUB-44 삭제 실패는 정리 대기로 기록한다 (§3)', () {
      expect(cf, contains('idDocumentOrphanPaths: admin.firestore.FieldValue.arrayUnion(path),'));
      expect(cf, contains('idDocumentOrphanPaths: admin.firestore.FieldValue.arrayRemove(path),'),
          reason: '성공하면 대기 목록에서 빠진다');
    });

    test('SUB-45 정리 실패가 현재 truth 를 뒤집지 않는다 (§3)', () {
      // 정리는 트랜잭션 **밖**에서, 상태를 이미 확정한 뒤에 한다.
      // 헬퍼 정의는 파일 앞쪽에 있으므로 **callable 내부** 기준으로 본다 —
      //   `const idNextVersion = idTxResult.version;` 는 이 callable 에만 있다.
      final txEnd = cf.indexOf('const idNextVersion = idTxResult.version;');
      final drain =
          cf.indexOf('await srvDrainOrphanPaths(callerUid, storagePath);');
      expect(txEnd, greaterThan(0));
      expect(drain, greaterThan(txEnd),
          reason: '정리가 상태 확정 뒤에 와야 롤백을 유발하지 않는다');
      // 그리고 정리 경로의 모든 실패는 catch 로 삼킨다.
      expect(cf, contains('console.warn(`[orphan] delete 실패'));
      expect(cf, contains('console.warn(`[orphan] drain 실패'));
    });

    test('SUB-46 성공한 제출 뒤 대기 목록을 비운다 (retry)', () {
      expect(cf, contains('await srvDrainOrphanPaths(callerUid, storagePath);'));
      expect(cf, contains('async function srvDrainOrphanPaths('));
    });

    test('SUB-47 교체된 이전 current 도 서버가 치운다 (§6)', () {
      // 클라이언트도 지우지만 그쪽은 실패가 조용히 묻히고, A/B 경합에서는
      //   업로드 전에 캡처한 경로라 실제 이전 current 와 다를 수 있다.
      expect(cf, contains('await srvDeleteOrQueueOrphan( callerUid, idTxResult.curPath, storagePath);'));
    });

    test('SUB-48 drain 은 한 번에 처리량을 묶는다', () {
      expect(cf, contains('.slice(0, 20);'),
          reason: '대기 목록이 길어도 한 호출을 붙잡지 않는다');
    });
  });
}
