// [SIG-CUTOVER §2·§5] 서명 이미지 소비자가 **권한 기반 링크**로 옮겨졌는지,
// 실제 위젯을 띄워 확인한다.
//
//   전환 전: 계약 문서의 `employerSignatureUrl`(영구 다운로드 토큰)을 그대로
//     `CachedNetworkImage` 에 넣었다. 만료도 로그인도 없는 URL 이라 한 번 본
//     사람이 권한을 잃은 뒤에도 계속 열 수 있었고, PDF 생성기는 그 URL 을
//     `http.get` 으로 직접 가져왔다.
//
//   전환 후: 렌더 입력은 **계약 id + 역할 + 있다/없다** 뿐이다. 링크는 열 때마다
//     서버가 권한을 보고 15분짜리로 낸다.
//
//   네트워크를 쓰지 않는다 — 링크 발급을 resolver 로 주입하고, 위젯 트리에
//   실제로 올라간 `CachedNetworkImage` 의 속성을 읽는다.
//
// 이 파일이 지키는 성질:
//   ① 서명이 있는 계약은 **역할마다** 링크를 받는다 (employer / worker)
//   ② 캐시 키에 **판(attempt)** 이 들어간다 — 재서명 후 옛 이미지가 남지 않는다
//   ③ 서명이 없거나 계약이 없으면 링크를 **받으려 하지 않는다**
//   ④ 발급 실패는 **침묵이 아니다** — 말하고, 다시 시도할 수 있다
//   ⑤ 로딩 중임을 알린다
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/screens/contract/contract_pdf_builder.dart';
import 'package:ALfit/screens/contract/contract_sign_screen.dart';
import 'package:ALfit/services/contract_service.dart';

ContractSnapshot _snapshot() => ContractSnapshot(
      businessName: '중앙물류센터 수도권 1센터',
      businessNumber: '123-45-67890',
      businessAddress: '경기도 화성시 동탄순환대로 1길 23',
      ownerName: '박사장',
      workerName: '김근로',
      workType: '냉장 분류',
      workPlace: '경기도 화성시 동탄순환대로 1길 23',
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

/// 링크 발급을 대신한다 — 호출 기록을 남긴다.
class _FakeResolver {
  final List<String> calls = [];
  final String version;
  final Object? throwThis;
  final Completer<void>? gate;

  _FakeResolver({this.version = 'a1b2c3d4', this.throwThis, this.gate});

  Future<ContractSignatureLink> call(String contractId, String role) async {
    calls.add('$contractId/$role');
    if (gate != null) await gate!.future;
    if (throwThis != null) throw throwThis!;
    return ContractSignatureLink(
      url: 'https://signed.example/$role.png?X-Goog-Signature=AAA',
      version: version,
    );
  }
}

/// 주석 줄(`//`)을 지운다 — 소스 검사는 **코드만** 봐야 한다.
///   왜 바꿨는지 적은 주석에 옛 표현이 남아 있으면 그게 걸린다(실측).
String _codeOf(String raw) => raw
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Widget _template({
  required String? contractId,
  required bool hasEmployer,
  required bool hasWorker,
  ContractSignatureResolver? resolver,
  String? sealBase64,
}) =>
    _host(ContractTemplateWidget(
      snapshot: _snapshot(),
      contractDate: DateTime(2026, 10, 1),
      contractId: contractId,
      hasEmployerSignature: hasEmployer,
      hasWorkerSignature: hasWorker,
      employerSealBase64: sealBase64,
      signatureResolver: resolver,
    ));

List<CachedNetworkImage> _images(WidgetTester t) =>
    t.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage)).toList();

void main() {
  // ════════════════════════════════════════════════════════════════════
  // SIGX-1 역할마다 링크를 받는다
  // ════════════════════════════════════════════════════════════════════
  group('SIGX-1 역할 분리', () {
    testWidgets('SIGX-01 서명 둘 다 있으면 employer·worker 로 각각 받는다',
        (t) async {
      final r = _FakeResolver();
      await t.pumpWidget(_template(
        contractId: 'c_001',
        hasEmployer: true,
        hasWorker: true,
        resolver: r.call,
      ));
      await t.pump();

      expect(r.calls, containsAll(<String>['c_001/employer', 'c_001/worker']));
      expect(r.calls.length, 2, reason: '블록마다 한 번씩 — 더 부르면 낭비다');
    });

    testWidgets('SIGX-02 사업주만 서명한 계약은 employer 만 받는다', (t) async {
      // `pending_worker` 의 화면 모습이다 — 근로자가 보는 그 상태.
      final r = _FakeResolver();
      await t.pumpWidget(_template(
        contractId: 'c_002',
        hasEmployer: true,
        hasWorker: false,
        resolver: r.call,
      ));
      await t.pump();

      expect(r.calls, <String>['c_002/employer']);
    });

    testWidgets('SIGX-03 링크는 역할마다 다른 이미지로 들어간다', (t) async {
      final r = _FakeResolver();
      await t.pumpWidget(_template(
        contractId: 'c_003',
        hasEmployer: true,
        hasWorker: true,
        resolver: r.call,
      ));
      await t.pump();

      final imgs = _images(t);
      expect(imgs.length, 2);
      final urls = imgs.map((i) => i.imageUrl).toSet();
      expect(urls.length, 2, reason: '두 블록이 같은 이미지를 가리키면 섞인 것이다');
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // SIGX-2 캐시 키 — 판이 들어간다
  // ════════════════════════════════════════════════════════════════════
  group('SIGX-2 캐시 키', () {
    testWidgets('SIGX-10 키는 계약·역할·판 세 조각이다', (t) async {
      final r = _FakeResolver(version: 'deadbeef');
      await t.pumpWidget(_template(
        contractId: 'c_010',
        hasEmployer: true,
        hasWorker: true,
        resolver: r.call,
      ));
      await t.pump();

      final keys = _images(t).map((i) => i.cacheKey).toList();
      expect(keys, contains('contract_sig_c_010_employer_deadbeef'));
      expect(keys, contains('contract_sig_c_010_worker_deadbeef'));
    });

    testWidgets('SIGX-11 URL 이 바뀌어도 키는 그대로다 (15분마다 재발급)',
        (t) async {
      // 같은 판, 다른 서명 파라미터 → 같은 캐시 키여야 한다.
      //   아니면 링크를 새로 받을 때마다 같은 이미지를 다시 내려받는다.
      String? firstKey;
      for (final sig in ['AAA', 'BBB']) {
        // 같은 위치의 위젯은 element 가 재사용되어 initState 가 다시 돌지
        //   않는다 — 링크를 **다시 받는** 상황을 만들려면 트리를 비운다.
        await t.pumpWidget(const SizedBox.shrink());
        final r = _FakeResolver(version: 'ver1');
        await t.pumpWidget(_host(ContractTemplateWidget(
          snapshot: _snapshot(),
          contractDate: DateTime(2026, 10, 1),
          contractId: 'c_011',
          hasEmployerSignature: true,
          signatureResolver: (c, role) async => ContractSignatureLink(
            url: 'https://signed.example/$role.png?X-Goog-Signature=$sig',
            version: 'ver1',
          ),
        )));
        await t.pump();
        final img = _images(t).first;
        expect(img.imageUrl, contains(sig));
        firstKey ??= img.cacheKey;
        expect(img.cacheKey, firstKey);
        expect(r.calls, isEmpty); // 이 셀은 인라인 resolver 를 쓴다
      }
    });

    testWidgets('SIGX-12 재서명하면 키가 달라진다 — 옛 이미지가 남지 않는다',
        (t) async {
      // 서버는 요청마다 새 attempt 경로에 저장한다. 계약·역할만으로 키를
      //   만들면 재서명 후에도 옛 서명이 계속 보인다 — 그것을 막는 셀이다.
      final keys = <String?>[];
      for (final v in ['attempt_one', 'attempt_two']) {
        await t.pumpWidget(const SizedBox.shrink()); // 트리를 비워 재발급시킨다
        await t.pumpWidget(_template(
          contractId: 'c_012',
          hasEmployer: true,
          hasWorker: false,
          resolver: _FakeResolver(version: v).call,
        ));
        await t.pump();
        keys.add(_images(t).first.cacheKey);
      }
      expect(keys[0], isNot(keys[1]));
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // SIGX-3 받으려 하지 않는 경우
  // ════════════════════════════════════════════════════════════════════
  group('SIGX-3 링크를 받지 않는 상태', () {
    testWidgets('SIGX-20 서명이 없으면 링크를 받지 않는다', (t) async {
      final r = _FakeResolver();
      await t.pumpWidget(_template(
        contractId: 'c_020',
        hasEmployer: false,
        hasWorker: false,
        resolver: r.call,
      ));
      await t.pump();

      expect(r.calls, isEmpty, reason: '없는 서명을 받으러 가면 매번 실패한다');
      expect(_images(t), isEmpty);
    });

    testWidgets('SIGX-21 계약이 없으면(템플릿 미리보기) 링크를 받지 않는다',
        (t) async {
      // `contract_template_preview_screen` 의 모습 — dummy snapshot, 계약 없음.
      final r = _FakeResolver();
      await t.pumpWidget(_template(
        contractId: null,
        hasEmployer: true, // 플래그가 참이라도 계약이 없으면 받을 수 없다
        hasWorker: true,
        resolver: r.call,
      ));
      await t.pump();

      expect(r.calls, isEmpty);
      expect(_images(t), isEmpty);
    });

    testWidgets('SIGX-22 서명 전에는 인감 base64 미리보기를 쓴다', (t) async {
      // 1x1 투명 PNG
      const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4'
          'nGNgYAAAAAMAAWgmWQ0AAAAASUVORK5CYII=';
      await t.pumpWidget(_template(
        contractId: 'c_022',
        hasEmployer: false,
        hasWorker: false,
        sealBase64: png,
      ));
      await t.pump();

      expect(find.byType(Image), findsWidgets,
          reason: '서명 전 미리보기 경로가 사라졌다');
      expect(_images(t), isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // SIGX-4 실패와 로딩을 말한다
  // ════════════════════════════════════════════════════════════════════
  group('SIGX-4 실패·로딩 표면', () {
    testWidgets('SIGX-30 발급 실패는 침묵이 아니다 — 말하고 다시 시도한다',
        (t) async {
      final r = _FakeResolver(throwThis: Exception('permission-denied'));
      await t.pumpWidget(_template(
        contractId: 'c_030',
        hasEmployer: true,
        hasWorker: false,
        resolver: r.call,
      ));
      await t.pump();
      await t.pump();

      expect(find.textContaining('서명 불러오기 실패'), findsOneWidget,
          reason: '예전에는 SizedBox.shrink() 였다 — 빈 칸과 구별되지 않았다');
      expect(r.calls.length, 1);

      // 다시 시도가 실제로 또 부른다.
      //   서명란은 계약서 맨 아래다 — 스크롤해서 닿게 한 뒤 누른다.
      await t.ensureVisible(find.textContaining('서명 불러오기 실패'));
      await t.pump();
      await t.tap(find.textContaining('서명 불러오기 실패'));
      await t.pump();
      await t.pump();
      expect(r.calls.length, 2);
    });

    testWidgets('SIGX-31 받는 동안 로딩을 알린다', (t) async {
      final gate = Completer<void>();
      final r = _FakeResolver(gate: gate);
      await t.pumpWidget(_template(
        contractId: 'c_031',
        hasEmployer: true,
        hasWorker: false,
        resolver: r.call,
      ));
      await t.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_images(t), isEmpty, reason: '아직 링크가 없는데 이미지를 그렸다');

      gate.complete();
      await t.pump();
      await t.pump();
      expect(_images(t).length, 1);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // SIGX-6 PDF 에 서명 이미지가 실제로 들어간다 (§4·§8)
  // ════════════════════════════════════════════════════════════════════
  //
  //   전환 전 빌더는 URL 을 받아 스스로 가져왔고, URL 이 없으면 **조용히**
  //   서명 없는 PDF 를 만들었다. 이제 바이트를 받으므로 "넣었는가"를 직접 센다.
  group('SIGX-6 PDF 서명 삽입', () {
    // 2x2 빨간 PNG — 실제 디코드되는 바이트여야 PDF 에 들어간다.
    //   (`pdf` 패키지의 `MemoryImage` 는 디코드 실패 시 예외를 던진다.)
    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGO4Iyf3H4QZ'
        'YAwASnwIXWJvAVEAAAAASUVORK5CYII=');

    /// PDF 안의 이미지 XObject 수 — 서명이 들어갔는지 보는 눈금.
    ///
    ///   [실측] 서명 **1개당 2개**가 나온다. 알파 채널이 있는 PNG 는
    ///   이미지와 알파 마스크(SMask)가 각각 XObject 가 되기 때문이다.
    ///   그 비율은 `pdf` 패키지의 구현 세부이므로, 셀은 절대 개수가 아니라
    ///   **늘어나는 관계**만 단정한다.
    int imageCount(List<int> bytes) =>
        RegExp(r'/Subtype\s*/Image')
            .allMatches(String.fromCharCodes(bytes))
            .length;

    testWidgets('SIGX-50 서명 바이트가 없으면 이미지가 없다 (기준선)',
        (t) async {
      final bytes = await ContractPdfBuilder.build(
        snapshot: _snapshot(),
        contractDate: DateTime(2026, 10, 1),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(imageCount(bytes), 0, reason: '서명을 안 줬는데 이미지가 들어갔다');
    });

    testWidgets('SIGX-51 서명을 넣을수록 PDF 의 이미지가 늘어난다', (t) async {
      Future<int> count({Uint8List? emp, Uint8List? wrk}) async {
        final b = await ContractPdfBuilder.build(
          snapshot: _snapshot(),
          contractDate: DateTime(2026, 10, 1),
          employerSignatureBytes: emp,
          workerSignatureBytes: wrk,
        );
        expect(String.fromCharCodes(b.take(5)), '%PDF-');
        return imageCount(b);
      }

      final none = await count();
      final one = await count(emp: png);
      final both = await count(emp: png, wrk: png);

      expect(none, 0, reason: '서명을 안 줬는데 이미지가 있다');
      expect(one, greaterThan(none), reason: '사업주 서명이 PDF 에 안 들어갔다');
      expect(both, greaterThan(one), reason: '근로자 서명이 PDF 에 안 들어갔다');
    });

    testWidgets('SIGX-52 근로자 서명만 줘도 들어간다 (사업주 미서명 계약)',
        (t) async {
      final bytes = await ContractPdfBuilder.build(
        snapshot: _snapshot(),
        contractDate: DateTime(2026, 10, 1),
        workerSignatureBytes: png,
      );
      expect(imageCount(bytes), greaterThan(0));
    });

    test('SIGX-53 빈 서명 바이트는 조용히 넘어가지 않는다', () async {
      // 못 가져온 것을 "서명 없음"으로 처리하면 서명란이 빈 계약서가 완료된다.
      //   검증이 폰트 로드보다 앞이므로 위젯 바인딩 없이 확인된다.
      for (final who in ['employer', 'worker']) {
        await expectLater(
          ContractPdfBuilder.build(
            snapshot: _snapshot(),
            contractDate: DateTime(2026, 10, 1),
            employerSignatureBytes:
                who == 'employer' ? Uint8List(0) : null,
            workerSignatureBytes: who == 'worker' ? Uint8List(0) : null,
          ),
          throwsA(predicate(
              (e) => e.toString().contains('비어 있'), '빈 서명을 알린다')),
        );
      }
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // SIGX-5 모델 — 구버전 호환과 단계 C 를 함께 센다
  // ════════════════════════════════════════════════════════════════════
  group('SIGX-5 서명 존재 판정', () {
    EmploymentContractModel c({
      String? empUrl,
      String? wrkUrl,
      bool empAvail = false,
      bool wrkAvail = false,
    }) =>
        EmploymentContractModel(
          id: 'c1',
          businessId: 'b1',
          workerId: 'w1',
          toId: 't1',
          applicationId: 'a1',
          isLongTerm: true,
          workDetailId: 'wd1',
          createdAt: DateTime(2026, 10, 1),
          status: ContractStatus.completed,
          snapshot: _snapshot(),
          employerSignatureUrl: empUrl,
          workerSignatureUrl: wrkUrl,
          employerSignatureAvailable: empAvail,
          workerSignatureAvailable: wrkAvail,
        );

    test('SIGX-40 레거시 계약은 남아 있는 URL 로 판정한다 (구버전 호환)', () {
      final m = c(empUrl: 'https://legacy/sig.png?token=t');
      expect(m.hasEmployerSignature, isTrue);
      expect(m.hasWorkerSignature, isFalse);
    });

    test('SIGX-41 단계 C 신규 계약은 boolean 만으로 판정한다', () {
      // 응답에 URL 도 경로도 없다 — CF 가 주는 표식이 유일한 근거다.
      final m = c(empAvail: true, wrkAvail: true);
      expect(m.hasEmployerSignature, isTrue);
      expect(m.hasWorkerSignature, isTrue);
    });

    test('SIGX-42 아무 근거도 없으면 없다고 말한다', () {
      final m = c();
      expect(m.hasEmployerSignature, isFalse);
      expect(m.hasWorkerSignature, isFalse);
    });

    test('SIGX-43 빈 문자열 URL 은 서명이 아니다', () {
      final m = c(empUrl: '', wrkUrl: '');
      expect(m.hasEmployerSignature, isFalse);
      expect(m.hasWorkerSignature, isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // SIGX-7 Stage B — 영구 URL 이 **사라진 뒤에도** 앱이 깨지지 않는다
  // ════════════════════════════════════════════════════════════════════
  //
  //   레거시 토큰 이관은 `employer/workerSignatureUrl` 과 `pdfUrl` 을 **지운다**.
  //   단계 C 의 신규 계약은 애초에 그 필드를 받지 않는다. 두 경우 모두
  //   "URL 이 없다 = 서명이 없다"로 읽으면 멀쩡한 계약이 깨져 보인다.
  group('SIGX-7 Stage B — URL 없는 계약', () {
    test('SIGX-60 서명 완료 판정이 URL 에 매달리지 않는다', () {
      // 예전 코드: `contract.employerSignatureUrl != null`
      //   → 이관이 끝난 계약이 관리자 화면에서 "미서명"으로 보였다.
      // 주석에도 같은 문구가 나오므로(왜 바꿨는지 적어 뒀다) **코드만** 본다.
      final src = _codeOf(File('lib/screens/business_admin/'
          'admin_contract_management_screen.dart').readAsStringSync());
      expect(src.contains('employerSignatureUrl != null'), isFalse,
          reason: '이관된 계약이 미서명으로 보인다');
      expect(src.contains('workerSignatureUrl != null'), isFalse);
      expect(src, contains('contract.employerSignedAt != null'));
      expect(src, contains('contract.workerSignedAt != null'));
    });

    test('SIGX-61 서명 저장이 URL 부재로 실패하지 않는다', () {
      // 예전 코드: `if (url.isEmpty) throw …employerSignatureUrl 없음`
      //   → 단계 C 에서 CF 가 URL 발급을 멈추면 **서명 자체가 막힌다**.
      final svc = _codeOf(
          File('lib/services/contract_service.dart').readAsStringSync());
      expect(svc.contains("CF 응답에 employerSignatureUrl 없음"), isFalse,
          reason: '단계 C 에서 사업주 서명이 막힌다');
      expect(svc.contains("CF 응답에 sigUrl 없음"), isFalse,
          reason: '단계 C 에서 근로자 서명이 막힌다');
      // 경로가 있으면 통과해야 한다 — 둘 다 비었을 때만 실패.
      expect(svc, contains("cfMap?['employerSignatureStoragePath']"));
      expect(svc, contains("cfData?['workerSignatureStoragePath']"));
      expect(svc, contains('sigPath.isEmpty && url.isEmpty'));
      expect(svc, contains('cfSigPath.isEmpty && cfSigUrl.isEmpty'));
    });

    test('SIGX-62 서버가 서명 경로를 응답에 담는다', () {
      // 클라이언트가 경로를 보려면 서버가 줘야 한다 — 양쪽이 한 쌍이다.
      final fn = File('functions/src/index.ts').readAsStringSync();
      expect(fn, contains('employerSignatureStoragePath: storagePath,\n    };'),
          reason: '사업주 서명 응답에 경로가 없다');
      expect(fn, contains('workerSignatureStoragePath: sigStoragePath,'),
          reason: '근로자 서명 응답에 경로가 없다');
    });

    test('SIGX-62B 서버 응답 필드명과 클라이언트가 읽는 이름이 **같다**', () {
      // §2: "서버·클라이언트 중 한쪽만 다른 필드명을 쓰면 배포 금지."
      //   사람이 눈으로 맞추던 것을 기계가 맞춘다.
      final fn = File('functions/src/index.ts').readAsStringSync();
      final svc = _codeOf(
          File('lib/services/contract_service.dart').readAsStringSync());
      for (final field in [
        'employerSignatureStoragePath',
        'workerSignatureStoragePath',
        'pdfStoragePath',
      ]) {
        expect(fn.contains('$field:'), isTrue,
            reason: '서버가 $field 를 응답에 담지 않는다');
        expect(svc.contains("['$field']"), isTrue,
            reason: '클라이언트가 $field 를 읽지 않는다');
      }
    });

    test('SIGX-62C 응답 경로는 **실제 저장에 쓴 변수**와 같다', () {
      // 응답에만 따로 계산한 경로를 넣으면 다른 attempt 를 가리킬 수 있다.
      final fn = File('functions/src/index.ts').readAsStringSync();
      // 줄바꿈·들여쓰기에 묶이지 않게 공백을 접는다.
      final flat = fn.replaceAll(RegExp(r'\s+'), ' ');
      // employer: 저장·Firestore·응답이 전부 `storagePath`
      expect(flat, contains('_saveContractArtifact( storagePath, signatureBytes'));
      expect(flat, contains('employerSignatureStoragePath: storagePath,'));
      // worker: 저장·Firestore·응답이 전부 `sigStoragePath`
      expect(flat, contains('_saveContractArtifact(sigStoragePath, signatureBytes'));
      expect(flat, contains('workerSignatureStoragePath: sigStoragePath,'));
      // PDF 는 서명과 **다른 변수**다 — 혼동하면 서명 자리에 PDF 가 간다.
      // raw 문자열 — Dart 가 `${…}` 를 보간해 버린다.
      expect(fn, contains(r'const pdfStoragePath = `${attemptPrefix}/contract.pdf`'));
      expect(fn,
          contains(r'const sigStoragePath = `${attemptPrefix}/signature_worker.png`'));
    });

    test('SIGX-63 URL 없이도 모델이 서명·PDF 를 있다고 말한다', () {
      // 이관 완료 계약이 CF 에서 오는 모양: URL 3종 없음 + available 3종 참.
      final m = EmploymentContractModel(
        id: 'c1', businessId: 'b1', workerId: 'w1', toId: 't1',
        applicationId: 'a1', isLongTerm: true, workDetailId: 'wd1',
        createdAt: DateTime(2026, 10, 1), status: ContractStatus.completed,
        snapshot: _snapshot(),
        pdfAvailable: true,
        employerSignatureAvailable: true,
        workerSignatureAvailable: true,
        employerSignedAt: DateTime(2026, 10, 1),
        workerSignedAt: DateTime(2026, 10, 2),
      );
      expect(m.hasPdf, isTrue);
      expect(m.hasEmployerSignature, isTrue);
      expect(m.hasWorkerSignature, isTrue);
      expect(m.pdfUrl, isNull);
      expect(m.employerSignatureUrl, isNull);
      expect(m.workerSignatureUrl, isNull);
    });
  });
}
