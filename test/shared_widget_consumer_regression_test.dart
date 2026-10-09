// [R7-PREDEVICE-STABILIZATION.1A] 공용 컴포넌트를 고쳤다 — 소비 쪽이 멀쩡한가.
//
// ── 이 Phase 가 건드린 공용 표면 셋 ────────────────────────────────
//   ① `CommonWidgets.sectionHeader`  제목이 `Expanded` 로 자리를 양보한다
//        → 소비 3파일 · 21곳 (사업장 상세 7 · 사업장 양식 10 · 업무유형 상세 4)
//   ② `CommonWidgets.primaryButton` / `outlineButton`  라벨이 `Flexible`
//        → 앱 전체
//   ③ `attendancePolicyLines`  근로자 고지 문구가 **길어졌다**
//        → 공고 상세 · 계약 PDF · 계약 서명 · 내 지원 · 수락 시트 · 지원 확인
//
//   ③ 이 가장 위험하다. 글자 수가 늘어난 변경은 **계약서**까지 흐르고,
//   계약서는 법적 문서다. 그래서 여기서 PDF 를 **실제로 만들어** 본다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/screens/contract/contract_pdf_builder.dart';
import 'package:ALfit/utils/attendance_policy_disclosure.dart';
import 'package:ALfit/widgets/common/common_widgets.dart';

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

AttendanceRules _rules({int unit = 30, int grace = 5}) =>
    AttendanceRules.defaults().copyWith(
      earlyWindow: 30,
      earlyArrivalUnit: unit,
      lateGrace: grace,
      lateUnit: unit,
      lateWindow: 30,
      overtimeUnit: unit,
      earlyLeaveUnit: unit,
    );

ContractSnapshot _snapshot({AttendanceRules? policy}) => ContractSnapshot(
      businessName: '중앙물류센터 수도권 1센터',
      businessNumber: '123-45-67890',
      businessAddress: '경기도 화성시 동탄순환대로 1길 23 3층 물류동 A구역',
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
      attendancePolicy: policy ?? _rules(),
    );

void main() {
  // ═══════════════════════════════════════════════════════════
  // ③ 계약 PDF — 실제로 만들어 본다
  // ═══════════════════════════════════════════════════════════
  group('SWC-PDF 길어진 고지가 계약서를 깨지 않는다', () {
    testWidgets('SWC-PDF-01 새 문구로 PDF 가 실제로 만들어진다', (tester) async {
      // 번들 한글 폰트를 읽는다 — 테스트 자산 번들에서 로드된다.
      final bytes = await ContractPdfBuilder.build(
        snapshot: _snapshot(),
        contractDate: DateTime(2026, 10, 1),
        articles: const [],
      );
      expect(bytes.lengthInBytes, greaterThan(1000),
          reason: 'PDF 가 비어 있다');
      // PDF 서명(magic) 확인 — 진짜 문서인가.
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    testWidgets('SWC-PDF-02 단위가 커져 문구가 길어져도 만들어진다',
        (tester) async {
      // 유예 30 · 단위 60 → "31분 늦으면 60분" 처럼 숫자가 두 자리로 늘고
      //   문장이 가장 길어지는 조합이다.
      final long = _rules(unit: 60, grace: 30);
      final lines = attendancePolicyLines(long);
      expect(lines.any((l) => l.value.length > 30), isTrue,
          reason: '긴 문구 조합을 만들지 못했다 — 테스트 전제가 깨졌다');

      final bytes = await ContractPdfBuilder.build(
        snapshot: _snapshot(policy: long),
        contractDate: DateTime(2026, 10, 1),
        articles: const [],
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    testWidgets('SWC-PDF-03 조항이 많아 여러 장이 되어도 만들어진다',
        (tester) async {
      // `pw.MultiPage` 가 페이지를 넘긴다 — 넘침이 아니라 분할이어야 한다.
      final articles = [
        for (var i = 1; i <= 40; i++)
          ContractArticle(
            title: '제$i조 (시험 조항)',
            content: '이 조항은 페이지 분할을 확인하기 위한 긴 본문이다. ' * 12,
          ),
      ];
      final bytes = await ContractPdfBuilder.build(
        snapshot: _snapshot(),
        contractDate: DateTime(2026, 10, 1),
        articles: articles,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.lengthInBytes, greaterThan(10000),
          reason: '여러 장 문서가 만들어지지 않았다');
    });

    test('SWC-PDF-04 고지 값은 줄바꿈하는 칸에 들어간다', () {
      final src = _read('lib/screens/contract/contract_pdf_builder.dart');
      final i = src.indexOf('static pw.Widget _row(');
      expect(i, greaterThan(-1));
      final body = src.substring(i, i + 900);
      // 값은 남은 폭을 받아 **줄바꿈**한다 — 고정폭·클립이 아니다.
      expect(body.contains('pw.Expanded('), isTrue,
          reason: '값이 고정폭이면 긴 문구가 잘린다');
      expect(body.contains('maxLines'), isFalse,
          reason: '계약서 문구를 줄 수로 자르지 않는다');
      // 페이지는 흐른다.
      expect(src.contains('pw.MultiPage('), isTrue,
          reason: '단일 Page 면 길어진 문서가 넘친다');
    });

    test('SWC-PDF-05 PDF 도 화면과 같은 formatter 를 쓴다', () {
      final src = _read('lib/screens/contract/contract_pdf_builder.dart');
      expect(src.contains('attendancePolicyLines(policy)'), isTrue);
      expect(src.contains("AttendancePolicyLine('"), isFalse,
          reason: 'PDF 가 목록을 직접 만들면 화면과 갈린다');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 서명 완료 계약의 불변성
  // ═══════════════════════════════════════════════════════════
  group('SWC-FROZEN 이미 서명된 계약은 바뀌지 않는다', () {
    test('SWC-FROZEN-01 PDF 는 서명 시점에 한 번 만들어져 저장된다', () {
      // 문구를 고쳐도 **이미 서명된** 계약서가 달라지면 안 된다.
      //   이 제품은 근로자 서명 시 PDF 를 만들어 업로드하고, 완료 계약은
      //   저장된 `pdfUrl` 을 받아 쓴다 — 그래서 바이트가 얼어 있다.
      final builderCalls = <String>[];
      for (final p in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (p.readAsStringSync().contains('ContractPdfBuilder.build(')) {
          builderCalls.add(p.path.replaceAll(r'\', '/'));
        }
      }
      expect(builderCalls.length, 1,
          reason: 'PDF 생성 지점이 늘었다 — 서명본을 다시 만드는 경로가 '
              '생기면 문구 변경이 과거 계약서를 바꾼다: $builderCalls');
      expect(builderCalls.single,
          'lib/screens/contract/contract_sign_screen.dart');

      // 그 호출이 서명 저장과 같은 흐름에 있다.
      final sign = _read('lib/screens/contract/contract_sign_screen.dart');
      final b = sign.indexOf('ContractPdfBuilder.build(');
      final save = sign.indexOf('saveWorkerSignature(', b);
      expect(save, greaterThan(b),
          reason: '만든 PDF 를 저장하지 않으면 얼지 않는다');
      expect(sign.substring(b, save).contains('pdfBytes'), isFalse);
      expect(sign.contains('pdfBytes: pdfBytes'), isTrue);
    });

    test('SWC-FROZEN-02 완료 계약은 저장본을 받아 쓴다 — 재생성하지 않는다', () {
      final sign = _read('lib/screens/contract/contract_sign_screen.dart');
      final i = sign.indexOf('Future<void> _sharePdf()');
      expect(i, greaterThan(-1));
      final body = sign.substring(i, i + 700);
      expect(body.contains('widget.contract.pdfUrl'), isTrue,
          reason: '저장본 URL 을 쓰지 않으면 과거 계약서가 새 문구로 바뀐다');
      expect(body.contains('ContractPdfBuilder'), isFalse,
          reason: '공유 경로가 PDF 를 다시 만들면 불변이 깨진다');
    });

    test('SWC-FROZEN-03 고지 숫자는 계약 snapshot 에서 온다', () {
      // 문구는 바뀌어도 **숫자**는 그 근무에 고정된 snapshot 값이다.
      //   사업장이 지금 기준을 바꿔도 과거 계약서의 숫자는 그대로다.
      final pdf = _read('lib/screens/contract/contract_pdf_builder.dart');
      expect(pdf.contains('snapshot.attendancePolicy case final policy?'),
          isTrue,
          reason: 'live 사업장 기준을 읽으면 과거 계약서가 흔들린다');
      expect(pdf.contains('attendanceRules'), isFalse,
          reason: 'PDF 가 사업장 현재 기준을 직접 읽는다');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // ①② 공용 컴포넌트의 성질
  // ═══════════════════════════════════════════════════════════
  group('SWC-SHARED 공용 컴포넌트가 자리를 양보한다', () {
    final cw = _read('lib/widgets/common/common_widgets.dart');

    test('SWC-SHARED-01 sectionHeader 제목이 Expanded 다', () {
      final i = cw.indexOf('static Widget sectionHeader(');
      expect(i, greaterThan(-1));
      final body = cw.substring(i, i + 1600);
      expect(body.contains('Expanded('), isTrue);
      expect(body.contains('maxLines'), isFalse,
          reason: '섹션 제목을 줄 수로 자르면 그 섹션이 무엇인지 알 수 없다');
      expect(body.contains('TextOverflow.ellipsis'), isFalse);
    });

    test('SWC-SHARED-02 두 버튼 라벨이 모두 Flexible 이다', () {
      for (final name in const ['primaryButton', 'outlineButton']) {
        final i = cw.indexOf('static Widget $name(');
        expect(i, greaterThan(-1), reason: '$name 을 찾지 못했다');
        final body = cw.substring(i, i + 2600);
        expect(body.contains('Flexible('), isTrue,
            reason: '$name 라벨이 자리를 양보하지 않는다');
      }
    });

    test('SWC-SHARED-03 눌러 담는 우회를 쓰지 않았다', () {
      // 금지어를 **주석에도** 적지 않는다 — 전역 사용처 집계가 리터럴을
      //   세므로(TYPO-42) 주석이 사용처로 잡힌다.
      for (final bad in const ['FittedBox', 'Transform.scale']) {
        expect(cw.contains(bad), isFalse, reason: '$bad 가 들어 있다');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════
  // sectionHeader 소비 3화면 — 실제 렌더
  // ═══════════════════════════════════════════════════════════
  group('SWC-CONSUMER sectionHeader 소비 화면이 넘치지 않는다', () {
    /// 공용 헤더만 떼어 소비 화면과 같은 폭·배율로 그린다.
    ///
    ///   세 화면 전체는 Firestore·provider 의존이 커서 이 Phase 에서
    ///   통째로 pump 하지 않는다(사업장 양식은 전용 테스트가 따로 있다).
    ///   여기서 보는 것은 **공용 헤더 자체**가 긴 제목·큰 배율에서
    ///   줄바꿈하는가다.
    Future<void> pumpHeaders(
      WidgetTester tester, {
      required List<String> titles,
      required Size size,
      required double textScale,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Builder(
              builder: (c) => Column(
                children: [
                  for (final t in titles)
                    CommonWidgets.sectionHeader(
                        context: c, title: t, icon: Icons.store_outlined),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
    }

    /// 세 소비 파일에 실제로 적힌 제목을 그대로 쓴다.
    List<String> realTitles() {
      final titles = <String>[];
      final re = RegExp(r"sectionHeader\([^)]*?title:\s*'([^']+)'",
          dotAll: true);
      for (final p in const [
        'lib/screens/business_admin/business_detail_screen.dart',
        'lib/screens/business_admin/business_form_screen.dart',
        'lib/screens/business_admin/work_type_detail_screen.dart',
      ]) {
        for (final m in re.allMatches(_read(p))) {
          titles.add(m.group(1)!);
        }
      }
      return titles;
    }

    test('SWC-CONSUMER-00 소비 제목을 실제로 모았다', () {
      final t = realTitles();
      expect(t.length, greaterThanOrEqualTo(10),
          reason: '제목을 못 모으면 아래 렌더가 빈 검사가 된다: $t');
    });

    for (final w in const [320.0, 360.0]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('SWC-CONSUMER ${w.toInt()}dp × 배율 $scale — 넘침 0',
            (tester) async {
          await pumpHeaders(tester,
              titles: realTitles(), size: Size(w, 900), textScale: scale);
          expect(tester.takeException(), isNull,
              reason: '${w.toInt()}dp × $scale 에서 섹션 헤더가 넘친다');
        });
      }
    }

    testWidgets('SWC-CONSUMER-07 긴 제목은 잘리지 않고 줄바꿈한다',
        (tester) async {
      const long = '사업장 운영 시간 및 근태 처리 기준 상세 설정';
      await pumpHeaders(tester,
          titles: const [long], size: const Size(320, 900), textScale: 2.0);
      expect(tester.takeException(), isNull);
      // 글자가 사라지지 않았다.
      expect(find.text(long), findsOneWidget);
      final rendered = tester.renderObject<RenderBox>(find.text(long));
      expect(rendered.size.height, greaterThan(30),
          reason: '한 줄에 눌러 담았다 — 줄바꿈하지 않았다');
    });
  });
}
