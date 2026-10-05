// [R7-P4.4E.11C.1.2] 관리자는 남았는데 사업장이 아무것도 할 수 없었다
//
// `.11C.1` DEV runtime 에서 실측한 상태다.
//
//   owner + co-admin 인 사업장의 owner 가 탈퇴
//   → adminIds = [coAdmin], business 생존(isApproved, deactivatedAt 없음)
//   → ownerId = 삭제된 uid, users/{ownerId} 없음
//   → 새 근로자 지원: "지금은 지원을 받지 않는 공고예요."
//
// 고용주 날인 gate 가 `business.ownerId` → `users/{ownerId}.sealBase64` 를
// 보기 때문이다. 사업장은 살아 있는 것처럼 보이는데 공고 등록·예약 게시·
// 지원·확정·초대수락이 전부 막힌다. 그리고 남은 관리자는 그것을 해소할
// 길이 없다 — `ownerId` 를 바꾸는 production writer 가 없다.
//
// 그래서 OPTION A 다. 소유권 이전 기능이 없으므로 승계를 발명하지 않고,
// **그 상태가 만들어지는 삭제 자체를 완료시키지 않는다.**
//
// 고정하는 것
//   O1-*      ownerId canonical writer inventory
//   O2-*      고용주 날인 reader 가 ownerId 를 따른다
//   O3-*      체결된 계약 snapshot 을 다시 쓰지 않는다
//   O4-*      관리자 → owner 암묵 승격이 없다
//   OSB-A*    삭제 후 상태로 판정한다(단독/공동/비활성/adminIds 제외)
//   OSB-P*    preview ↔ 서버 동일 술어
//   OSB-G*    freeze 전 차단 + 파괴 직전 재확인 + fail-closed
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

/// 주석을 지운 코드만 — 주석 문구가 바뀌어도 깨지지 않게.
String _codeOf(String path) {
  final out = StringBuffer();
  for (final line in _src(path).split('\n')) {
    final t = line.trimLeft();
    if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) continue;
    out.writeln(line);
  }
  return out.toString();
}

const _cf = 'functions/src/index.ts';
const _rules = 'firestore.rules';
const _settings = 'lib/screens/common/settings_screen.dart';

/// 두 앵커 사이 구간. 순서 고정에 쓴다.
String _between(String code, String from, String to) {
  final a = code.indexOf(from);
  expect(a, greaterThan(-1), reason: '앵커를 찾지 못했다: $from');
  final b = code.indexOf(to, a);
  expect(b, greaterThan(a), reason: '앵커를 찾지 못했다: $to');
  return code.substring(a, b);
}

void main() {
  group('O1 ownerId canonical writer inventory', () {
    test('O1-01 서버에 ownerId 를 쓰는 자리가 없다', () {
      final code = _codeOf(_cf);
      expect(code.contains('ownerId:'), isFalse,
          reason: 'ownerId 는 사업장 생성 때 정해지고 그 뒤 바뀌지 않는다. '
              '새 occurrence 가 생겼다면 소유권 이전 정책부터 결정해야 한다');
    });

    test('O1-02 클라이언트는 생성에서만 ownerId 를 쓴다', () {
      final form = _src('lib/screens/business_admin/business_form_screen.dart');
      expect(form.contains("if (!_isEditMode) 'ownerId': ownerId"), isTrue,
          reason: '수정 모드에서 ownerId 를 보내면 소유권이 조용히 바뀐다');
    });

    test('O1-03 rules 가 BUSINESS_ADMIN 의 ownerId/adminIds 변경을 막는다', () {
      final rules = _src(_rules);
      expect(rules.contains("hasAny(['ownerId', 'adminIds', 'approvedAt',"),
          isTrue);
    });

    test('O1-04 rules 가 생성 시 ownerId==본인 + adminIds==[본인] 을 강제한다', () {
      final rules = _src(_rules);
      expect(
          rules.contains('request.resource.data.ownerId == request.auth.uid'),
          isTrue);
      expect(
          rules.contains(
              'request.resource.data.adminIds.hasOnly([request.auth.uid])'),
          isTrue,
          reason: '생성 시점에는 adminIds == [owner] 하나다');
    });
  });

  group('O2 고용주 날인 reader 가 ownerId 를 따른다', () {
    test('O2-01 employerSealPresent 가 ownerId 의 user 문서를 읽는다', () {
      final code = _codeOf(_cf);
      final body =
          _between(code, 'async function employerSealPresent(', '\n}\n');
      expect(body.contains('bizData?.ownerId'), isTrue);
      expect(body.contains('db.collection("users").doc(ownerId)'), isTrue);
      expect(body.contains('sealBase64'), isTrue);
    });

    test('O2-02 날인이 없으면 NO_EMPLOYER_SEAL 이다', () {
      final code = _codeOf(_cf);
      expect(code.contains('return "NO_EMPLOYER_SEAL"'), isTrue);
    });

    test('O2-03 그 판정을 소비하는 경로가 여럿이다', () {
      final code = _codeOf(_cf);
      final capability =
          RegExp(r'evaluateContractCapability\(').allMatches(code).length;
      final posting = RegExp(r'evaluatePostingReadinessFirestore\(')
          .allMatches(code)
          .length;
      expect(capability, greaterThanOrEqualTo(4),
          reason: '지원·확정·초대수락이 같은 판정을 쓴다');
      expect(posting, greaterThanOrEqualTo(3),
          reason: '공고 준비·예약 게시도 같은 판정을 쓴다');
    });
  });

  group('O3 체결된 계약 snapshot 불변', () {
    test('O3-01 계약 문서가 고용주 identity 를 snapshot 으로 들고 있다', () {
      final model = _src('lib/models/core/employment_contract_model.dart');
      expect(model.contains('ownerName'), isTrue,
          reason: '계약서 사업주란은 체결 시점 값을 저장한다');
      expect(model.contains('employerSignedAt'), isTrue);
    });

    test('O3-02 이번 술어는 읽기 전용이다 — 계약/소유 필드를 쓰지 않는다', () {
      final code = _codeOf(_cf);
      final body = _between(
          code, 'async function srvCountStaleOwnerBusinesses(', '\n}\n');
      for (final w in ['.update(', '.set(', '.delete(', 'arrayRemove', 'arrayUnion']) {
        expect(body.contains(w), isFalse, reason: '집계가 $w 를 한다');
      }
    });
  });

  group('O4 관리자 → owner 암묵 승격 없음', () {
    test('O4-01 남은 관리자를 owner 로 올리는 코드가 없다', () {
      final code = _codeOf(_cf);
      for (final cheat in [
        'ownerId: adminIds[0]',
        'ownerId: survivingAdmin',
        'ownerId = adminIds',
      ]) {
        expect(code.contains(cheat), isFalse);
      }
    });

    test('O4-02 날인은 본인 문서에만 쓴다 — 대상 uid 를 받지 않는다', () {
      final code = _codeOf(_cf);
      final body =
          _between(code, 'export const callableSaveSeal = onCall(', '\n);\n');
      expect(body.contains('const uid = request.auth.uid'), isTrue);
      expect(body.contains('db.collection("users").doc(uid).update('), isTrue);
      expect(body.contains('targetUid'), isFalse,
          reason: '다른 사람의 날인을 등록할 수 있으면 법적 서명 주체가 흔들린다');
    });

    test('O4-03 삭제된 owner 의 날인을 복제·이관하지 않는다', () {
      final code = _codeOf(_cf);
      final body = _between(
          code, 'async function srvCountStaleOwnerBusinesses(', '\n}\n');
      expect(body.contains('sealBase64'), isFalse);
    });
  });

  group('OSB-A 삭제 후 상태로 판정한다', () {
    String predicate() => _between(_codeOf(_cf),
        'async function srvCountStaleOwnerBusinesses(', '\n}\n');

    test('OSB-A1 단독 관리자 사업장은 세지 않는다 — 정리가 비활성화한다', () {
      final body = predicate();
      expect(body.contains('adminIds.length === 1 && adminIds.includes(uid)'),
          isTrue);
      expect(body.contains('if (willBeDeactivated) continue;'), isTrue);
    });

    test('OSB-A2 그 밖에 활성으로 남는 사업장은 센다', () {
      final body = predicate();
      expect(body.contains('out.count++'), isTrue);
    });

    test('OSB-A3 이미 비활성화된 사업장은 세지 않는다', () {
      final body = predicate();
      expect(body.contains('if (d["deactivatedAt"]) continue;'), isTrue,
          reason: '비활성 사업장은 신규 모집 능력이 없으므로 모순이 아니다');
    });

    test('OSB-A4 adminIds 가 아니라 ownerId 로 조회한다', () {
      final body = predicate();
      expect(body.contains('.where("ownerId", "==", uid)'), isTrue,
          reason: 'rules[SEC-100] 자기 제거로 owner 가 adminIds 에서 빠질 수 있다 — '
              'adminIds 로 찾으면 정리도 preview 도 그 사업장을 지나친다');
      expect(body.contains('array-contains'), isFalse);
    });

    test('OSB-A5 정리가 돌지 않는 role 에서는 단독도 면제하지 않는다', () {
      final body = predicate();
      expect(
          body.contains(
              'const cleanupWillRun = role === "BUSINESS_ADMIN" || role === "SUPER_ADMIN"'),
          isTrue);
      expect(body.contains('cleanupWillRun &&'), isTrue);
    });
  });

  group('OSB-P preview ↔ 서버 동일 술어', () {
    test('OSB-P1 preview 가 같은 helper 를 쓴다 — 로직 복제 없음', () {
      final code = _codeOf(_cf);
      final preview = _between(
          code, 'export const callableGetWithdrawBlockers = onCall(', '\n);\n');
      expect(preview.contains('srvCountStaleOwnerBusinesses(callerUid, role)'),
          isTrue);
      expect(preview.contains('BUSINESS_OWNER_SUCCESSION_REQUIRED'), isTrue);
    });

    test('OSB-P2 preview 검사가 사업장 조회 early-return 앞에 있다', () {
      final code = _codeOf(_cf);
      final preview = _between(
          code, 'export const callableGetWithdrawBlockers = onCall(', '\n);\n');
      final checkAt = preview.indexOf('srvCountStaleOwnerBusinesses');
      final earlyAt = preview.indexOf('if (bizIds.length === 0)');
      expect(checkAt, greaterThan(-1));
      expect(earlyAt, greaterThan(-1));
      expect(checkAt, lessThan(earlyAt),
          reason: 'early-return 뒤에 두면 adminIds 에 없는 owner 는 영원히 안 보인다');
    });

    test('OSB-P3 early-return 이 담은 blocker 를 버리지 않는다', () {
      final code = _codeOf(_cf);
      final preview = _between(
          code, 'export const callableGetWithdrawBlockers = onCall(', '\n);\n');
      expect(preview.contains('return {hardBlocks, warnings};'), isTrue);
      expect(preview.contains('return {hardBlocks: [], warnings: []};'), isFalse,
          reason: '빈 리터럴을 돌려주면 위에서 담은 blocker 가 사라진다');
    });

    test('OSB-P4 서버 precondition 이 role 블록 밖에서 검사한다', () {
      final code = _codeOf(_cf);
      final body = _between(
          code, 'async function srvAssertAccountDeletionAllowed(', '\n}\n');
      expect(
          body.contains(
              'srvAssertNoStaleOwnerBusiness(\n    await srvCountStaleOwnerBusinesses(uid, role));'),
          isTrue);
      // role 블록은 `if (role === "BUSINESS_ADMIN" || role === "SUPER_ADMIN") {`
      // 로 열린다. 그 블록이 닫힌 **뒤**에 호출돼야 모든 role 에 적용된다.
      final lastRoleIf =
          body.lastIndexOf('if (role === "BUSINESS_ADMIN" || role === "SUPER_ADMIN") {');
      final callAt = body.indexOf('srvAssertNoStaleOwnerBusiness(');
      expect(lastRoleIf, greaterThan(-1));
      expect(callAt, greaterThan(lastRoleIf));
      final tail = body.substring(lastRoleIf, callAt);
      expect(tail.contains('\n  }\n'), isTrue,
          reason: 'role 블록 안에 있으면 USER role 소유자를 지나친다');
    });
  });

  group('OSB-G 차단 지점과 fail-closed', () {
    test('OSB-G1 freeze 보다 앞에서 막는다 — 부분 freeze 를 만들지 않는다', () {
      final code = _codeOf(_cf);
      final preData = _between(code,
          'export const callableDeleteAccountPreData = onCall(', '\n);\n');
      final assertAt = preData.indexOf('srvAssertAccountDeletionAllowed(');
      final freezeAt = preData.indexOf('srvEnsureAccountDeletionTombstone(');
      expect(assertAt, greaterThan(-1));
      expect(freezeAt, greaterThan(assertAt),
          reason: 'precondition 이 freeze 앞이라 막혀도 tombstone 이 안 생긴다');
    });

    test('OSB-G2 Final 이 사업장 정리 뒤에 같은 술어로 재확인한다', () {
      final code = _codeOf(_cf);
      final body = _between(
          code, 'export const callableDeleteAccountFinal = onCall(', '\n);\n');
      final cleanupAt = body.indexOf('bizCleanupFailed) {');
      final recheckAt = body.indexOf('staleOwnerResidual');
      final userDeleteAt = body.indexOf('userRef.delete()');
      expect(cleanupAt, greaterThan(-1));
      expect(recheckAt, greaterThan(cleanupAt),
          reason: '정리를 돌린 뒤의 상태를 봐야 한다');
      expect(userDeleteAt, greaterThan(recheckAt),
          reason: '파괴 직전에 확인해야 의미가 있다');
      expect(body.contains('srvAssertNoStaleOwnerBusiness(staleOwnerResidual)'),
          isTrue);
    });

    test('OSB-G3 쿼리 실패를 0 으로 읽지 않는다', () {
      final code = _codeOf(_cf);
      final predicate = _between(
          code, 'async function srvCountStaleOwnerBusinesses(', '\n}\n');
      expect(predicate.contains('out.queryFailed = true'), isTrue);
      final gate = _between(
          code, 'function srvAssertNoStaleOwnerBusiness(', '\n}\n');
      expect(gate.contains('if (s.queryFailed) {'), isTrue);
      final preview = _between(
          code, 'export const callableGetWithdrawBlockers = onCall(', '\n);\n');
      expect(preview.contains('staleOwner.queryFailed'), isTrue);
      final fin = _between(
          code, 'export const callableDeleteAccountFinal = onCall(', '\n);\n');
      expect(fin.contains('staleOwnerResidual.queryFailed'), isTrue);
    });

    test('OSB-G4 판정을 상수로 무력화하지 않았다', () {
      final code = _codeOf(_cf);
      final predicate = _between(
          code, 'async function srvCountStaleOwnerBusinesses(', '\n}\n');
      final gate = _between(
          code, 'function srvAssertNoStaleOwnerBusiness(', '\n}\n');
      for (final cheat in ['false &&', '&& false', 'true ||', '|| true']) {
        expect(predicate.contains(cheat), isFalse, reason: '집계에 $cheat');
        expect(gate.contains(cheat), isFalse, reason: '판정에 $cheat');
      }
    });

    test('OSB-G5 blocker code 는 기존 style 을 따르고 중복 enum 을 만들지 않는다', () {
      final code = _codeOf(_cf);
      final n = RegExp('BUSINESS_OWNER_SUCCESSION_REQUIRED')
          .allMatches(code)
          .length;
      expect(n, 2, reason: '서버 메시지 1 + preview push 1 — 그 이상이면 복제됐다');
    });
  });

  group('OSB-UX 없는 행동을 요구하지 않는다', () {
    test('OSB-UX1 클라이언트가 blocker 를 사람 문장으로 보여준다', () {
      final s = _src(_settings);
      expect(s.contains("'BUSINESS_OWNER_SUCCESSION_REQUIRED' =>"), isTrue);
    });

    test('OSB-UX2 존재하지 않는 "대표자 변경" CTA 를 만들지 않는다', () {
      final s = _src(_settings);
      final navStart = s.indexOf('String? blockNavKey(');
      expect(navStart, greaterThan(-1));
      final navBody = s.substring(navStart, s.indexOf('};', navStart));
      expect(navBody.contains('BUSINESS_OWNER_SUCCESSION_REQUIRED'), isFalse,
          reason: '소유권 이전 화면이 없으므로 이동 CTA 도 없어야 한다');
    });

    test('OSB-UX3 소유권 이전 기능을 새로 만들지 않았다', () {
      final code = _codeOf(_cf);
      for (final invented in [
        'callableTransferBusinessOwner',
        'callableChangeBusinessOwner',
        'transferOwnership',
      ]) {
        expect(code.contains(invented), isFalse,
            reason: '이번 Phase 는 승계 기능을 만들지 않는다');
      }
    });
  });
}
