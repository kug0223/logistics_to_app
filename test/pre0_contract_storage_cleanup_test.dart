// [CORRECTION-DEV-CONTRACT-STORAGE-ORPHAN-CLEANUP]
//
// fixture cleanup 이 계약서를 지우면서 서명 PNG 와 계약 PDF 는 한 번도
// 지우지 못하고 있었다.
//
//     r7-fixture-lib initializeApp   ← storageBucket 없음
//       → admin.storage().bucket()   ← 매번 throw
//         → cleanup 의 catch (_) {}  ← 예외를 삼킴
//           → "삭제 완료" 로 보임
//
// Firestore 계약서는 사라지고 artifact 만 남아 229건이 쌓였다. 그 파일에는
// 임금과 개인정보가 들어 있다. 실패를 성공처럼 적는 코드가 실제 데이터를
// 남긴 사례다.
//
// 이 파일이 고정하는 것은 두 가지다.
//   1. 버킷 설정과 안전 guard 가 살아 있다.
//   2. 정리 실패가 **다시는 조용히 성공으로 보이지 않는다**.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _libPath = 'scripts/r7-fixture-lib.js';
const _cleanupPath = 'scripts/r7-fixture-cleanup.js';
const _seedPath = 'scripts/seed-r7-fixtures-dev.js';
const _orphanPath = 'scripts/pre0-contract-storage-orphan-cleanup.js';
const _probePath = 'scripts/pre0-fixture-cleanup-probe.js';
const _buildPath = 'scripts/r7-fixture-build.js';
const _firebaseJson = 'firebase.json';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// 주석 줄을 지운 본문. 앵커는 주석이 아니라 **코드**여야 한다.
String _codeOf(String s) => s
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');

String _after(String src, String name, int chars) {
  final i = src.indexOf(name);
  if (i < 0) throw StateError('$name 를 찾지 못함');
  return src.substring(i, (i + chars).clamp(0, src.length));
}

void main() {
  final lib = _codeOf(_src(_libPath));
  final cleanup = _codeOf(_src(_cleanupPath));
  final seed = _codeOf(_src(_seedPath));
  final orphan = _codeOf(_src(_orphanPath));
  final probe = _codeOf(_src(_probePath));
  final build = _codeOf(_src(_buildPath));

  // ══════════════════════════════════════════════════════════════
  // 01. 버킷 설정 — root cause
  // ══════════════════════════════════════════════════════════════
  group('01. storageBucket', () {
    test('01-a initializeApp 이 storageBucket 을 준다', () {
      expect(lib.contains('storageBucket: STORAGE_BUCKET'), true);
      expect(lib.contains('projectId: EXPECTED_PROJECT'), true);
    });

    test('01-b 버킷 이름을 추측하지 않고 firebase.json 에서 읽는다', () {
      expect(lib.contains('function canonicalBucket()'), true);
      expect(lib.contains("path.join(ROOT, 'firebase.json')"), true);
      expect(lib.contains('cfg.storage.bucket') || lib.contains('cfg.storage && cfg.storage.bucket'),
          true);
    });

    test('01-c firebase.json 에 실제로 그 값이 있다', () {
      // 설정이 사라지면 lib 이 throw 하도록 돼 있다 — 값 자체도 확인한다.
      final cfg = _src(_firebaseJson);
      expect(cfg.contains('"bucket":"alfit-89567.firebasestorage.app"') ||
          cfg.contains('"bucket": "alfit-89567.firebasestorage.app"'), true);
    });

    test('01-d DEV 프로젝트의 버킷이 아니면 던진다', () {
      final f = _after(lib, 'function canonicalBucket()', 800);
      expect(f.contains(r'!b.startsWith(`${EXPECTED_PROJECT}.`)'), true);
      expect(f.contains('throw new Error('), true);
    });

    test('01-e 삭제 경로는 devBucket() 으로만 버킷을 얻는다', () {
      expect(lib.contains('function devBucket()'), true);
      final f = _after(lib, 'function devBucket()', 600);
      // 이름과 프로젝트를 둘 다 확인한다.
      expect(f.contains('b.name !== STORAGE_BUCKET'), true);
      expect(f.contains(r'!b.name.startsWith(`${EXPECTED_PROJECT}.`)'), true);
    });

    test('01-f cleanup 이 기본 버킷을 직접 부르지 않는다', () {
      // admin.storage().bucket() 은 스크립트에서 해상도되지 않는다.
      expect(cleanup.contains('admin.storage().bucket()'), false);
      expect(cleanup.contains('devBucket()'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 02. 실패 가시성 — silent success 금지
  // ══════════════════════════════════════════════════════════════
  group('02. 실패 가시성', () {
    test('02-a 예외를 삼키는 catch 가 없다', () {
      // `catch (_) {}` / `catch (e) {}` 는 실패를 성공으로 만든다.
      for (final banned in ['catch (_) {}', 'catch (e) {}', 'catch(_){}']) {
        expect(cleanup.contains(banned), false, reason: banned);
      }
      // 어떤 모양으로 쓰든 빈 catch 본문이 없어야 한다.
      //   (주석에 남은 `catch (_) {}` 는 사고 기록이다 — 코드만 본다.)
      expect(RegExp(r'catch\s*\([^)]*\)\s*\{\s*\}').hasMatch(cleanup), false);
    });

    test('02-b 결과를 deleted / notFound / failed 로 나눈다', () {
      for (final k in ['storageDeleted', 'storageMissing', 'storageFailed']) {
        expect(cleanup.contains(k), true, reason: k);
      }
      expect(cleanup.contains('storageErrors'), true);
    });

    test('02-c 404 만 멱등 성공으로 본다', () {
      // 버킷 설정 오류·권한 오류를 not-found 와 같이 삼키면 안 된다.
      final seg = _after(cleanup, 'const prefix = `contracts/', 1200);
      expect(seg.contains('if (e && e.code === 404) removed.storageMissing++;'),
          true);
      expect(seg.contains('removed.storageFailed++;'), true);
    });

    test('02-d 목록 조회 실패도 실패로 남는다', () {
      // deleteFiles 가 아니라 getFiles 가 터지는 경우가 원래 사고였다.
      final seg = _after(cleanup, 'const prefix = `contracts/', 1600);
      expect(seg.contains('목록 조회 실패'), true);
    });

    test('02-e 실패가 있으면 전체 결과가 PARTIAL 이다', () {
      expect(seed.contains('CLEANUP PARTIAL'), true);
      expect(seed.contains('cleanupPartial = true;'), true);
      expect(seed.contains('process.exitCode = 1;'), true);
    });

    test('02-f Storage 결과가 화면에 나온다', () {
      expect(seed.contains('storageDeleted'), true);
      expect(seed.contains('storageFailed'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 03. 일회성 정리 스크립트 — guard
  // ══════════════════════════════════════════════════════════════
  group('03. orphan cleanup guard', () {
    test('03-a PROD 프로젝트는 즉시 거부', () {
      expect(orphan.contains("const PROD_PROJECT_ID = 'alfit-prod';"), true);
      expect(orphan.contains('if (projectId === PROD_PROJECT_ID)'), true);
      expect(orphan.contains('process.exit(2);'), true);
    });

    test('03-b DEV 프로젝트가 아니면 거부', () {
      expect(orphan.contains('if (projectId !== EXPECTED_DEV_PROJECT)'), true);
    });

    test('03-c 기본이 dry-run 이고 --execute 가 있어야 삭제', () {
      expect(orphan.contains("const EXECUTE = argv.includes('--execute');"), true);
      final i = orphan.indexOf('if (!EXECUTE) {');
      final j = orphan.indexOf('.delete()');
      expect(i, greaterThan(-1));
      expect(j, greaterThan(-1));
      expect(i, lessThan(j), reason: 'dry-run 반환이 삭제보다 먼저여야 한다');
    });

    test('03-d 버킷을 devBucket() 으로 얻고 이름을 다시 확인한다', () {
      expect(orphan.contains('const bucket = devBucket();'), true);
      expect(orphan.contains('if (bucket.name !== STORAGE_BUCKET)'), true);
    });

    test('03-e 삭제 직전 부모 계약을 다시 확인한다', () {
      // scan 과 delete 사이에 상태가 바뀔 수 있다.
      final seg = _after(orphan, 'const recheck = new Map();', 900);
      expect(seg.contains("db.collection('employment_contracts').doc(c.contractId).get()"),
          true);
      expect(seg.contains('result.skippedBecauseParentAppeared++;'), true);
    });

    test('03-f 참조 중인 artifact 는 후보가 되지 않는다', () {
      // 어떤 계약이든 URL 로 가리키고 있으면 건너뛴다 — 상태와 무관하게.
      final seg = _after(orphan, 'if (referenced.has(p)) {', 400);
      expect(seg.contains('continue;'), true);
      expect(orphan.contains("const ARTIFACT_URL_FIELDS =\n  ['employerSignatureUrl', 'workerSignatureUrl', 'pdfUrl'];") ||
          (orphan.contains('employerSignatureUrl') &&
              orphan.contains('workerSignatureUrl') &&
              orphan.contains('pdfUrl')), true);
    });

    test('03-g parentless 만 후보다 — B/C/D/E 는 남긴다', () {
      expect(orphan.contains('tally.A_PARENTLESS++'), true);
      expect(orphan.contains('tally.B_UNREFERENCED_ATTEMPT++'), true);
      expect(orphan.contains('tally.E_UNKNOWN++'), true);
      // candidates 에 들어가는 것은 A 뿐이다.
      final pushes = RegExp(r'candidates\.push\(').allMatches(orphan).length;
      expect(pushes, 1);
      final seg = _after(orphan, 'if (!knownIds.has(cid)) {', 300);
      expect(seg.contains('candidates.push('), true);
    });

    test('03-h 결과를 다섯 갈래로 집계한다', () {
      for (final k in [
        'requested', 'deleted', 'alreadyMissing',
        'skippedBecauseParentAppeared', 'failed',
      ]) {
        expect(orphan.contains(k), true, reason: k);
      }
    });

    test('03-i Firestore 를 쓰지 않는다', () {
      for (final banned in ['.set(', '.update(', '.delete()', 'runTransaction']) {
        final inFirestoreCall = RegExp(
                r"collection\('employment_contracts'\)[^\n]*" +
                    RegExp.escape(banned))
            .hasMatch(orphan);
        expect(inFirestoreCall, false, reason: banned);
      }
    });

    test('03-j 개인정보를 읽거나 찍지 않는다', () {
      // 내용 다운로드·해시 계산을 하지 않는다 — 목적은 orphan 정리다.
      for (final banned in ['.download(', 'createHash', 'workerName', 'wage']) {
        expect(orphan.contains(banned), false, reason: banned);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 04. 범위 — fixture 가 만든 것만 지운다
  // ══════════════════════════════════════════════════════════════
  group('04. cleanup ownership', () {
    test('04-a fixture cleanup 은 contractId prefix 만 본다', () {
      expect(cleanup.contains(r'const prefix = `contracts/${entities.contractId}/`;'),
          true);
    });

    test('04-b 광범위 prefix 로 지우지 않는다', () {
      // contracts/ 전체, businessId, uid, 날짜 범위로 쓸어 담는 경로가 없다.
      expect(cleanup.contains("prefix: 'contracts/'"), false);
      expect(cleanup.contains('deleteFiles({prefix: `contracts/`'), false);
    });

    test('04-c 남의 지원서는 남기고 그 경우 공고도 남긴다', () {
      // R7-PRE0.1 에서 세운 규칙이 그대로 살아 있어야 한다.
      expect(cleanup.contains('const ownerUids = new Set();'), true);
      expect(cleanup.contains('if (entities.toId && removed.foreign === 0) {'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 05. probe — 실제로 끝까지 작동하는가
  // ══════════════════════════════════════════════════════════════
  group('05. cleanup probe', () {
    test('05-a probe 가 patch 한 그 cleanup 을 부른다', () {
      expect(probe.contains("require('./r7-fixture-cleanup')"), true);
      expect(probe.contains('removeScenario('), true);
    });

    test('05-b Storage 0건이 되는 것을 확인한다', () {
      expect(probe.contains('§25 Storage artifact 가 0건이다'), true);
      expect(probe.contains('§10 Storage 삭제 실패 0'), true);
    });

    test('05-c 두 번 실행해도 죽지 않는 것을 확인한다', () {
      expect(probe.contains('§26 두 번째 실행이 예외로 죽지 않는다'), true);
      expect(probe.contains('§26 두 번째는 지울 것이 없다'), true);
    });

    test('05-d probe 도 DEV guard 를 갖는다', () {
      expect(probe.contains('if (projectId !== EXPECTED_DEV_PROJECT)'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 06. PRE0 contractData 헬퍼 — 단기 전용 (§29)
  // ══════════════════════════════════════════════════════════════
  group('06. 단기 전용 헬퍼', () {
    test('06-a 이름이 단기 전용임을 말한다', () {
      expect(build.contains('async function contractDataShortTerm('), true);
      expect(RegExp(r'async function contractData\(').hasMatch(build), false);
    });

    test('06-b 장기로 부르면 던진다', () {
      final f = _after(build, 'async function contractDataShortTerm(', 900);
      expect(f.contains('if (isLong) {'), true);
      expect(f.contains('단기 전용이다'), true);
    });

    test('06-c 그 guard 가 payload 를 만들기 전에 있다', () {
      final f = _after(build, 'async function contractDataShortTerm(', 1400);
      final guard = f.indexOf('if (isLong) {');
      final body = f.indexOf('const biz = ctx.biz;');
      expect(guard, greaterThan(-1));
      expect(body, greaterThan(-1));
      expect(guard, lessThan(body));
    });

    test('06-d 장기 fixture 는 이 헬퍼를 쓰지 않는다', () {
      final lt = _codeOf(_src('scripts/lt-contract-dual-signature-runtime.js'));
      expect(lt.contains('contractDataShortTerm'), false);
      expect(lt.contains('async function buildLongTermContractData('), true);
      // 장기는 기간과 요일을 지원서에서 가져온다.
      final f = _after(lt, 'async function buildLongTermContractData(', 2600);
      expect(f.contains('contractStart: fmt(app.desiredStartDate || app.workDate)'),
          true);
      expect(f.contains('contractEnd: fmt(app.workEndDate)'), true);
      expect(f.contains('workDays: app.workDays || []'), true);
    });
  });
}
