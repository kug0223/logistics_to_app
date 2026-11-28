// [PERF impl_19 · 2026-11-26] 무거운 생성(명세서 PDF · 출근부 PDF · xlsx)을 메인 isolate 밖으로.
//
//   X  같은 입력 → 같은 출력. PDF 는 시험용 비압축 출력에서 무작위 ID·생성 시각·위치표만 빼고 바이트 비교(해시 동일),
//      xlsx 는 되읽은 값이 같다. 그리고 **정말 다른 isolate 에서 돌았는지**(`OffMain.debugLastPath`)도 본다.
//      (실제 isolate 를 쓰므로 FakeAsync 인 testWidgets 가 아니라 실제 이벤트 루프의 test 로 돈다 — runAsync 와 같은 뜻.)
//   F  보낼 수 없는 값 · isolate 실패면 이 isolate 에서 같은 결과(결과가 사라지지 않는다).
//   C  호출부 — 진행 표시가 있는 생성 지점만 offMain · 공유 뒤 임시파일 삭제 그대로 · 결제 명세 화면이 메인에서 폰트를 해석하지 않는다.
//   G  업무 사진 고르기 — 창이 뜨기 전 연타의 두 번째 진입이 창을 한 번 더 띄우지 않는다.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/screens/payroll/payslip_pdf_builder.dart';
import 'package:ALfit/screens/payroll/payslip_period_helper.dart';
import 'package:ALfit/utils/attendance_list_pdf.dart';
import 'package:ALfit/utils/off_main.dart';
import 'package:ALfit/utils/pdf_font_cache.dart';

String _code(String p) => File(p)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i >= 0 ? l.substring(0, i) : l;
    })
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 압축 끈 PDF 에서 무작위·시각 값을 걸러 낸 본문(위치표 앞까지) — impl_17 P1 과 같은 식.
String _stable(Uint8List bytes) {
  final s = latin1.decode(bytes);
  final cut = s.lastIndexOf('\nxref');
  final body = cut > 0 ? s.substring(0, cut) : s;
  return body
      .replaceAll(RegExp(r'/CreationDate \(D:[^)]*\)'), '/CreationDate ()')
      .replaceAll(RegExp(r'/ModDate \(D:[^)]*\)'), '/ModDate ()')
      .replaceAll(RegExp(r'/ID \[<[0-9a-fA-F]*> ?<[0-9a-fA-F]*>\]'), '/ID []');
}

void _expectSamePdf(Uint8List here, Uint8List there) {
  expect(String.fromCharCodes(there.take(5)), '%PDF-');
  final a = _stable(here), b = _stable(there);
  expect(a.length, greaterThan(1000));
  expect(sha256.convert(latin1.encode(b)), sha256.convert(latin1.encode(a)), reason: '같은 입력이면 같은 문서');
  expect(b, a);
}

/// xlsx 되읽기 — 시트 이름 · 각 칸 값(문자열)
Map<String, List<List<String>>> _readBack(List<int> bytes) {
  final x = Excel.decodeBytes(bytes);
  return {
    for (final name in x.tables.keys)
      name: [
        for (final row in x.tables[name]!.rows) [for (final c in row) c?.value?.toString() ?? '']
      ]
  };
}

WageDetailModel _wage() => WageDetailModel(
      wageType: 'hourly',
      baseWage: 12000,
      totalAmount: 96000,
      incomeTaxDeduction: 3168,
    );

AttendanceModel _att(int day) => AttendanceModel(
      id: 'att-$day',
      applicationId: 'app-$day',
      userId: 'u1',
      businessId: 'biz1',
      businessName: '합성 사업장',
      workDate: DateTime(2026, 11, day),
      workType: '합성 업무',
      checkInAt: DateTime(2026, 11, day, 9),
      checkOutAt: DateTime(2026, 11, day, 18),
      status: AttendanceModel.statusPresent,
      wageStatus: AttendanceModel.wageConfirmed,
      finalWage: 96000,
      wageDetail: _wage(),
      createdAt: DateTime(2026, 11, day),
    );

PayslipData _payslip() => PayslipData(
      businessName: '합성 사업장',
      workerName: '합성 근로자',
      workDate: DateTime(2026, 11, 3),
      workType: '합성 업무',
      checkIn: '09:00',
      checkOut: '18:00',
      workMinutes: 480,
      wageDetail: _wage(),
    );

AggregatedPayslipData _aggregated() => AggregatedPayslipData.fromRecords(
      records: [_att(3), _att(4), _att(5)],
      workerName: '합성 근로자',
      issueType: PayslipIssueType.monthly,
      year: 2026,
      month: 11,
      periodStart: DateTime(2026, 11, 1),
      periodEnd: DateTime(2026, 11, 30),
    );

AttendanceListData _list() => AttendanceListData(
      businessName: '합성 사업장',
      date: DateTime(2026, 11, 26),
      workTypeGroups: {
        '합성 업무': [
          for (var i = 0; i < 12; i++)
            AttendanceListItem(
              workType: '합성 업무',
              name: '근로자$i',
              personNo: 'W-${i.toString().padLeft(3, '0')}',
              gender: i.isEven ? '남' : '여',
              phone: '010-0000-${i.toString().padLeft(4, '0')}',
              workTime: '09:00~18:00',
              startTime: '09:00',
              endTime: '18:00',
            ),
        ],
      },
      workTypeTimeMap: const {'합성 업무': '09:00~18:00'},
      totalCount: 12,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    PdfFontCache.resetForTest();
    // 번들 대신 파일에서 — 별도 isolate 로는 바이트만 넘어간다(해석은 저쪽).
    PdfFontCache.loader = (k) => SynchronousFuture<ByteData>(ByteData.view(File(k).readAsBytesSync().buffer));
  });
  tearDownAll(PdfFontCache.resetForTest);
  setUp(() => OffMain.debugLastPath = null);

  group('X 같은 입력 → 같은 출력 · 정말 별도 isolate', () {
    test('X1 임금명세서(일별) PDF', () async {
      final here = await PayslipPdfBuilder.build(_payslip(), debugUncompressed: true);
      expect(OffMain.debugLastPath, 'main');
      final there = await PayslipPdfBuilder.build(_payslip(), offMain: true, debugUncompressed: true);
      expect(OffMain.debugLastPath, 'isolate', reason: '조용히 메인으로 되돌아갔다 — 보낼 수 없는 값이 끼었나');
      _expectSamePdf(here, there);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('X2 임금명세서(월간 집계 · 2쪽) PDF', () async {
      final here = await PayslipPdfBuilder.buildAggregated(_aggregated(), debugUncompressed: true);
      final there = await PayslipPdfBuilder.buildAggregated(_aggregated(), offMain: true, debugUncompressed: true);
      expect(OffMain.debugLastPath, 'isolate');
      _expectSamePdf(here, there);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('X3 출근부(근무 명단) PDF', () async {
      AttendanceListPdf.debugResetFonts();
      final here = await AttendanceListPdf.generatePdf(_list(), debugUncompressed: true);
      final there = await AttendanceListPdf.generatePdf(_list(), offMain: true, debugUncompressed: true);
      expect(OffMain.debugLastPath, 'isolate');
      _expectSamePdf(here, there);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('X4 출근부 xlsx — 되읽은 값 동일 · 별도 isolate', () async {
      final here = await AttendanceListPdf.generateExcel(_list());
      expect(OffMain.debugLastPath, 'main');
      final there = await AttendanceListPdf.generateExcel(_list(), offMain: true);
      expect(OffMain.debugLastPath, 'isolate');
      final a = _readBack(here), b = _readBack(there);
      expect(a.keys, contains('근무명단'));
      expect(a['근무명단']!.length, greaterThan(12));
      expect(b, a);
    });

    test('X5 공용 encodeExcel — 되읽은 값 동일(급여·월간 근태 내보내기가 쓰는 길)', () async {
      final x = Excel.createExcel();
      final s = x['시트'];
      for (var r = 0; r < 200; r++) {
        s.appendRow([TextCellValue('행$r'), IntCellValue(r * 1000), TextCellValue('한글 $r')]);
      }
      final main = x.encode()!;
      final off = await OffMain.encodeExcel(x);
      expect(OffMain.debugLastPath, 'isolate');
      expect(_readBack(off!), _readBack(main));
    });
  });

  group('F 실패 · 보낼 수 없는 값 → 이 isolate 에서 같은 결과', () {
    test('F1 보낼 수 없는 값을 잡은 계산은 메인에서 돈다(결과 같음 · 경로 main-fallback)', () async {
      final port = ReceivePort(); // isolate 로 보낼 수 없다
      addTearDown(port.close);
      final r = await OffMain.run('t', () => port.hashCode >= 0 ? 42 : 0);
      expect(r, 42);
      expect(OffMain.debugLastPath, 'main-fallback');
    });

    test('F2 꺼 두면 메인 · 웹 아님에서만 isolate', () async {
      expect(await OffMain.run('t', () => 7, enabled: false), 7);
      expect(OffMain.debugLastPath, 'main');
      expect(await OffMain.run('t', () => 8), 8);
      expect(OffMain.debugLastPath, 'isolate');
    });

    test('F3 소스 — 시간 상한 · 실패 시 이 isolate · 폰트 바이트 차례 읽기(Future.wait 0)', () {
      final c = _code('lib/utils/off_main.dart');
      expect(c, contains('.timeout(timeout)'));
      expect(c, contains("debugLastPath = 'main-fallback';"));
      final i = c.indexOf('static Future<Uint8List> buildPdf(');
      final body = c.substring(i, c.indexOf('static Future<Uint8List> _pdfIsolate('));
      expect(body.indexOf('loadBytes(PdfFontCache.regularAsset)'), lessThan(body.indexOf('loadBytes(PdfFontCache.boldAsset)')));
      expect(body.contains('Future.wait'), isFalse, reason: 'SynchronousFuture 함정(PF-5)');
    });
  });

  group('C 호출부', () {
    test('C1 진행 표시가 있는 생성 지점만 offMain(기본값 false 유지 · FakeAsync 시험 영향 0)', () {
      expect(_flat(_code('lib/screens/payroll/payslip_pdf_builder.dart')),
          contains('static Future<Uint8List> build(PayslipData data, {bool offMain = false,'));
      expect(_code('lib/screens/business_admin/payroll/payroll_worker_detail_screen.dart'),
          contains('PayslipPdfBuilder.buildAggregated(data, offMain: true)'));
      expect(_code('lib/screens/payroll/payslip_view_screen.dart'),
          contains('PayslipPdfBuilder.build(data, offMain: true)'));
      expect(_code('lib/screens/business_admin/dialogs/attendance_status_dialog.dart'),
          contains('AttendanceListPdf.generatePdf(data, offMain: true)'));
      final a = _code('lib/utils/attendance_list_pdf.dart');
      expect(a, contains('AttendanceListPdf.generatePdf(newData, offMain: true)'));
      expect(a, contains('await generateExcel(data, offMain: true);'));
      expect(_code('lib/utils/payroll_excel_helper.dart'), contains("OffMain.encodeExcel(excel, tag: 'payrollXlsx')"));
      expect(_code('lib/screens/business_admin/admin_month_detail_screen.dart'),
          contains("OffMain.encodeExcel(excel, tag: 'monthDetailXlsx')"));
    });

    test('C2 명세서 화면은 메인 isolate 에서 폰트를 해석하지 않는다(있는지만 본다 · 차례로)', () {
      final v = _code('lib/screens/payroll/payslip_view_screen.dart');
      expect(v.contains('PayslipPdfBuilder.loadFonts()'), isFalse);
      expect(v.indexOf('PdfFontCache.loadBytes(PdfFontCache.regularAsset)'),
          lessThan(v.indexOf('PdfFontCache.loadBytes(PdfFontCache.boldAsset)')));
    });

    test('C3 공유 직후 임시파일 삭제는 그대로(share → finally delete)', () {
      for (final p in [
        'lib/utils/attendance_list_pdf.dart',
        'lib/screens/business_admin/admin_month_detail_screen.dart',
        'lib/utils/payroll_excel_helper.dart',
      ]) {
        final f = _flat(_code(p));
        final share = f.indexOf('Share.shareXFiles(');
        expect(share, greaterThan(-1), reason: p);
        final fin = f.indexOf('finally', share);
        final del = f.indexOf('.delete()', fin);
        expect(fin > share && del > fin, isTrue, reason: '$p — 공유 뒤 finally 에서 삭제');
      }
    });
  });

  group('G 업무 사진 고르기', () {
    test('G1 고르기 창 전에 잠근다(ActionGuard · 본문 그대로)', () {
      final c = _flat(_code('lib/screens/business_admin/work_type_detail_screen.dart'));
      expect(c, contains("Future<void> _pickImages() => ActionGuard.runVoid(ActionGuard.ownerKey('workTypeDetail.pickImages', this), () => _pickImagesLocked());"));
      expect(c, contains('Future<void> _pickImagesLocked() async {'));
    });
  });
}
