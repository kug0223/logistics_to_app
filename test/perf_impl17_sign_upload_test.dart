// [PERF impl_17 · 2026-11-26] 계약 서명(L41) · 서류 업로드 진행률(L42).
//
//   P  PDF — 별도 isolate 에서 만든 문서와 이 isolate 에서 만든 문서가 같다(같은 입력 → 같은 출력).
//      pdf 패키지는 문서마다 무작위 ID·생성 시각을 넣는다 — 압축을 끈 시험용 출력에서 그 두 값과
//      그 뒤의 위치표(xref)만 빼고 바이트 그대로 비교한다. 해시도 같다.
//   S  서명 화면 — 사업주 서명 바이트 미리 받기(없으면 누를 때 예전처럼) · offMain · 서명 저장 병렬 ·
//      출근 화면 복귀 시 중복 미서명 조회 제거
//   U  업로드 — 진행률(snapshotEvents) · 압축 구간 단계 문구 · 통장 이전 사진 이중 삭제 제거(서버가 지운다)
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/screens/contract/contract_pdf_builder.dart';

String _src(String p) => File(p).readAsStringSync();
String _code(String s) => s
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i >= 0 ? l.substring(0, i) : l;
    })
    .join('\n');

/// 1×1 PNG(서명 자리 — 이미지가 실제로 들어가는지 함께 본다).
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

ContractSnapshot _snapshot() => ContractSnapshot(
      businessName: '합성 사업장',
      businessNumber: '000-00-00000',
      businessAddress: '합성 주소',
      ownerName: '합성 대표',
      workerName: '합성 근로자',
      workType: '합성 업무',
      workPlace: '합성 근무지',
      isLongTerm: true,
      contractStart: '2026-10-01',
      contractEnd: '2026-12-31',
      workDays: const ['월', '화', '수', '목', '금'],
      startTime: '09:00',
      endTime: '18:00',
      breakMinutes: 60,
      wage: 12000,
      wageType: 'hourly',
      paymentMethod: '계좌이체',
      wagePaymentDay: 10,
      taxDeductionType: 'none',
    );

/// 압축 끈 PDF 에서 무작위·시각 값을 걸러 낸 본문(위치표 앞까지).
String _stable(Uint8List bytes) {
  final s = latin1.decode(bytes);
  final cut = s.lastIndexOf('\nxref');
  final body = cut > 0 ? s.substring(0, cut) : s;
  return body.replaceAll(RegExp(r'/CreationDate \(D:[^)]*\)'), '/CreationDate ()');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P PDF 동일성(L41)', () {
    test('P1 별도 isolate 결과 = 이 isolate 결과(시험용 비압축 · 무작위 ID·시각 제외 · 해시 동일)', () async {
      Future<Uint8List> make({required bool offMain}) => ContractPdfBuilder.build(
            snapshot: _snapshot(),
            contractDate: DateTime(2026, 10, 1),
            employerSignatureBytes: _png,
            workerSignatureBytes: _png,
            offMain: offMain,
            debugUncompressed: true,
          );
      final here = await make(offMain: false);
      final there = await make(offMain: true);
      expect(String.fromCharCodes(there.take(5)), '%PDF-');
      final a = _stable(here);
      final b = _stable(there);
      expect(a.length, greaterThan(1000));
      expect(sha256.convert(latin1.encode(b)), sha256.convert(latin1.encode(a)),
          reason: '같은 입력이면 같은 문서여야 한다');
      expect(b, a);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('P2 기본(offMain=false) 경로는 그대로 — 다른 호출자·시험 영향 0', () {
      final c = _code(_src('lib/screens/contract/contract_pdf_builder.dart'));
      expect(c, contains('bool offMain = false,'));
      expect(c, contains('if (!offMain || kIsWeb) return here();'));
      expect(c, contains('return here();'), reason: '실패·시간 초과 시 이 isolate 에서 같은 방식으로');
      expect(c, contains('.timeout(_offMainTimeout)'));
    });
  });

  group('S 서명 화면(L41)', () {
    test('S1 사업주 서명 미리 받기 — 없으면 누를 때 예전처럼 받는다 · offMain 빌드', () {
      final c = _code(_src('lib/screens/contract/contract_sign_screen.dart'));
      expect(c, contains('_prefetchEmployerSignature();'));
      expect(c, contains('employerSigBytes = _employerSigPrefetched ??'));
      expect(c, contains('_service.fetchContractSignatureBytes('));
      expect(c, contains('offMain: true,'));
    });

    test('S2 서명 저장은 계약 서명과 함께 진행한다(저장을 먼저 기다리지 않는다)', () {
      final c = _code(_src('lib/screens/contract/contract_sign_screen.dart'));
      final perform = c.indexOf('if (mounted) await _performSign(bytes);\n    await saveSignature;');
      expect(perform, greaterThan(-1));
      expect(c.contains('await _service.saveUserSignature(uid: uid, base64: b64);\n            signatureSaved = true;'),
          isFalse);
    });

    test('S3 출근 화면 — 서명하고 돌아오면 미서명 목록을 다시 읽지 않는다(서명 화면이 읽었다) · 출근 근거는 새로', () {
      final c = _code(_src('lib/screens/user/attendance_check_screen.dart'));
      expect(c, contains('if (result is! EmploymentContractModel) {'));
      expect(c, contains('await userProvider.refreshPendingContracts();'));
      expect(c, contains('await _loadTodayWorks();'));
    });
  });

  group('U 업로드(L42)', () {
    test('U1 진행률은 전송 이벤트에서 · 결과 의미는 그대로', () {
      final s = _code(_src('lib/services/storage_service.dart'));
      expect(s, contains('task.snapshotEvents.listen('));
      expect(s, contains('await task;'));
      expect(s, contains('{void Function(double fraction)? onProgress}'));
      final d = _code(_src('lib/screens/common/document_management_screen.dart'));
      expect('onProgress: _uploadProgress'.allMatches(d).length, 2, reason: '신분증·통장');
      expect("_stage('사진을 준비하고 있어요');".allMatches(d).length, 2, reason: '압축 구간 문구');
    });

    test('U2 통장 이전 사진 — 서버가 지운다, 서버가 못 지웠다고 할 때만 클라이언트가 한 번', () {
      final d = _code(_src('lib/screens/common/document_management_screen.dart'));
      expect(d, contains("(markResult.data as Map)['cleanupPending'] == true"));
      expect(d, contains('if (cleanupPending && prev != null && prev.isNotEmpty) {'));
      final idx = _code(_src('functions/src/index.ts'));
      expect(idx, contains('cleanupPending: bbDrain.pendingAfter > 0,'));
      expect(idx, contains('await srvDrainBankbookCleanup(callerUid, "callableMarkBankbookVerified")'));
    });
  });
}
