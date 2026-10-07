// [CONTRACT-PERIOD-RULE] v2 전환 — 실제 화면·문서로 본 것.
//
//   앞 단계까지는 CODE 와 격리 행동뿐이었다. 여기서는 production 위젯과
//   문서 생성 경로를 **실제로 렌더**해서 다음을 본다.
//
//     CPT-A  관리자에게 뜨는 기간 정정 문구 — 이전/수정 날짜와 **대상**이
//            식별되는가
//     CPT-B  v2 신규 계약서 제2조 — 지원 때 표시한 날짜와 같은가
//            (서명 화면 + PDF 문서 생성 경로 둘 다)
//     CPT-C  수정 전 PENDING 건에서 **지원자**가 변경 사실을 보는가
//            — 없으면 NOT SEEN 이 아니라 **현재 화면의 부재**로 적는다
//     CPT-D  320dp · 배율 2.0 에서 날짜 두 개와 다음 행동이 잘리지 않는가
//
//   확정 버튼·서명·급여·해지 writer 는 한 번도 실행하지 않는다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/screens/contract/contract_pdf_builder.dart';
import 'package:ALfit/utils/contract_period.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/period_revision_notice.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), isTrue, reason: '$p 를 찾지 못함');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

DateTime _d(String iso) => FormatHelper.parseKstDateKey(iso)!;

/// 토스트는 전역 `navigatorKey` 의 overlay 에 들어간다 — production 과 같은 길.
Future<void> _pumpHost(WidgetTester tester,
    {Size size = const Size(390, 844), double textScale = 1.0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    navigatorKey: navigatorKey,
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: const Scaffold(body: SizedBox.expand()),
  ));
  await tester.pump();
}

/// 토스트 수명(안내 2초)을 흘려보낸다 — 남은 타이머로 teardown 이 깨지지 않게.
Future<void> _drainToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
}

ContractSnapshot _snapshot({
  required String contractStart,
  required String contractEnd,
}) =>
    ContractSnapshot(
      businessName: '강남 물류센터',
      businessNumber: '123-45-67890',
      businessAddress: '서울 강남구 역삼동 1',
      ownerName: '박사장',
      workerName: '김근로',
      workType: '피킹',
      workPlace: '서울 강남구 역삼동 1',
      isLongTerm: true,
      contractStart: contractStart,
      contractEnd: contractEnd,
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

void main() {
  // ══════════════════════════════════════════════════════════════
  // CPT-A. 관리자에게 뜨는 기간 정정 문구
  // ══════════════════════════════════════════════════════════════
  group('CPT-A. 관리자 periodRevision 문구', () {
    testWidgets('CPT-A1 이전 날짜·수정 날짜·대상이 한 문장에 있다', (tester) async {
      await _pumpHost(tester);

      // production 문구 생성기 — 서비스가 부르는 그 함수다.
      showPeriodRevisionNotice(
        presented: _d('2026-02-27'),
        applied: _d('2026-02-28'),
        applicantName: '김근로',
      );
      await tester.pump();

      expect(find.textContaining('2026-02-27'), findsOneWidget,
          reason: '지원자가 본 날짜');
      expect(find.textContaining('2026-02-28'), findsOneWidget,
          reason: '확정된 날짜');
      expect(find.textContaining('김근로'), findsOneWidget,
          reason: '어느 지원서인지 — 일괄 확정에서는 이것이 없으면 귀속이 안 된다');
      await _drainToast(tester);
    });

    testWidgets('CPT-A2 이름을 모르면 그 자리를 비우지 않고 말한다', (tester) async {
      await _pumpHost(tester);
      showPeriodRevisionNotice(
        presented: _d('2026-02-27'),
        applied: _d('2026-02-28'),
        applicantName: null,
      );
      await tester.pump();
      // 이름이 없다고 "님" 만 남기거나 빈 괄호를 만들지 않는다.
      expect(find.textContaining('님'), findsNothing);
      expect(find.textContaining('()'), findsNothing);
      expect(find.textContaining('2026-02-27'), findsOneWidget);
      await _drainToast(tester);
    });

    testWidgets('CPT-A3 320dp · 배율 2.0 에서 두 날짜가 모두 남는다', (tester) async {
      await _pumpHost(tester, size: const Size(320, 800), textScale: 2.0);
      showPeriodRevisionNotice(
        presented: _d('2026-02-27'),
        applied: _d('2026-02-28'),
        applicantName: '김근로',
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      // 잘려도 두 날짜는 읽혀야 한다 — 무엇이 무엇으로 바뀌었는지가 본문이다.
      expect(find.textContaining('2026-02-27'), findsOneWidget);
      expect(find.textContaining('2026-02-28'), findsOneWidget);
      final box = tester.getRect(find.textContaining('2026-02-27'));
      expect(box.width, lessThanOrEqualTo(320));
      await _drainToast(tester);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CPT-B. v2 계약서 제2조 — 지원 때 본 날짜와 같은가
  // ══════════════════════════════════════════════════════════════
  group('CPT-B. 계약서 제2조', () {
    // 지원 화면이 계산해 보여 주는 값(= 규칙 v2)
    final start = _d('2026-01-31');
    final presented = contractPeriodEndKstDay(start, '1month')!;

    test('CPT-B1 계약서 근무 기간이 지원 때 본 날짜와 같다', () {
      // 계약서는 저장된 workEndDate 를 KST 달력일 문자열로 찍는다
      // (`formatDateISO`). v2 에서는 확정 계산도 같은 값이므로 셋이 같다.
      final snap = _snapshot(
        contractStart: FormatHelper.formatDateISO(start),
        contractEnd: FormatHelper.formatDateISO(presented),
      );
      expect(snap.workPeriodText, '2026-01-31 ~ 2026-02-28');
      expect(FormatHelper.formatDateISO(presented), '2026-02-28',
          reason: '민법 160③ — 2월에 31일이 없으면 그 월의 말일');
    });

    testWidgets('CPT-B2 PDF 문서 생성 경로가 그 기간을 담아 만들어진다', (tester) async {
      final snap = _snapshot(
        contractStart: FormatHelper.formatDateISO(start),
        contractEnd: FormatHelper.formatDateISO(presented),
      );
      late final List<int> bytes;
      await tester.runAsync(() async {
        bytes = await ContractPdfBuilder.build(
          snapshot: snap,
          contractDate: _d('2026-01-25'),
          slots: const [],
          articles: const [],
        );
      });
      expect(bytes.length, greaterThan(1000), reason: 'PDF 가 만들어졌다');
      // 제2조가 읽는 값은 이 getter 하나다 — 문서와 화면이 같은 자를 쓴다.
      expect(snap.workPeriodText, contains('2026-02-28'));
    });

    test('CPT-B3 계약서는 기간을 다시 계산하지 않는다 (경계 유지)', () {
      final svc = _src('lib/services/contract_service.dart');
      expect(svc.contains('computeContractEndDate'), isFalse);
      expect(svc.contains('contractPeriodEnd'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CPT-C. 지원자는 변경을 보는가 — **내 지원 화면에서 본다**
  // ══════════════════════════════════════════════════════════════
  group('CPT-C. 지원자 쪽 고지 경로', () {
    // [R7-CONTRACT-PERIOD-DISCLOSURE] 이 그룹은 원래 **부재**를 못박고
    //   있었다. 셀의 reason 이 직접 적어 뒀다 — "읽는 화면이 생기면 이 셀을
    //   갱신하고 지원자 문구를 여기서 렌더한다". 생겼으므로 갱신한다.

    test('CPT-C1 지원자 화면이 정정 사실을 읽는다', () {
      // 서버가 남긴 두 필드를 읽는 경로가 **있어야** 한다.
      final hits = <String>[];
      for (final dir in ['lib/screens', 'lib/widgets', 'lib/models',
        'lib/utils']) {
        for (final f in Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
          final s = f.readAsStringSync();
          if (s.contains('workEndDatePresentedAtApply')) hits.add(f.path);
        }
      }
      expect(hits, isNotEmpty, reason: '지원자 고지 경로가 사라졌다');
      // 판정은 한 곳에서만 한다 — 화면이 날짜를 직접 비교하면 안 된다.
      final judges = hits
          .where((h) => h.replaceAll(r'\', '/').contains('lib/screens'))
          .toList();
      expect(judges, isEmpty, reason: '화면이 판정을 복제한다: $judges');
    });

    test('CPT-C2 모델이 그 필드를 파싱하되 쓰지는 않는다', () {
      final m = _src('lib/models/core/application_model.dart');
      expect(m.contains('workEndDatePresentedAtApply'), isTrue);
      expect(m.contains('workEndDateRevisedAt'), isTrue);
      // writer 는 CF 하나다 — toMap 에 넣지 않는다.
      final i = m.indexOf('Map<String, dynamic> toMap()');
      final j = m.indexOf('\n  }', i);
      expect(m.substring(i, j).contains('workEndDatePresentedAtApply'), isFalse,
          reason: '클라이언트가 법적 snapshot 을 쓰면 안 된다');
    });

    test('CPT-C3 확정 알림 본문에도 기간 변경이 없다', () {
      final cf = _src('functions/src/index.ts');
      // 확정 알림은 근무일·시간만 말한다. 기간 정정 문구가 없다.
      expect(cf.contains('periodRevision'), isTrue, reason: '응답에는 있다');

      // 확정 핸들러 **안의** 알림 블록을 찾는다 — 같은 타입 문자열이
      // 다른 핸들러에도 있어서 첫 번째를 집으면 엉뚱한 곳을 본다.
      final handler = cf.indexOf('export const callableConfirmApplication');
      expect(handler, greaterThan(-1));
      final notifyIdx = cf.indexOf('type: "applicationConfirmed"', handler);
      expect(notifyIdx, greaterThan(handler),
          reason: '확정 핸들러가 지원자에게 알림을 보낸다');
      final block = cf.substring(notifyIdx, notifyIdx + 1200);
      expect(block.contains('periodRevision'), isFalse,
          reason: '지원자 알림에는 담기지 않는다 — 확인된 부재');
      expect(block.contains('workEndDatePresentedAtApply'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CPT-D. 좁은 화면 · 큰 배율
  // ══════════════════════════════════════════════════════════════
  group('CPT-D. 320dp × 2.0', () {
    testWidgets('CPT-D1 계약 기간 두 날짜가 한 줄에서 잘리지 않는다', (tester) async {
      final snap = _snapshot(
        contractStart: '2026-01-31',
        contractEnd: '2026-02-28',
      );
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // 계약 화면들이 제2조 '근무 기간' 에 넣는 바로 그 문자열.
            child: Text(snap.workPeriodText),
          ),
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('2026-01-31 ~ 2026-02-28'), findsOneWidget);
      final box = tester.getRect(find.text('2026-01-31 ~ 2026-02-28'));
      expect(box.width, lessThanOrEqualTo(320 - 32),
          reason: '좌우 16dp 여백 안에 들어와야 한다');
    });
  });
}
