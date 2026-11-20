// [PREDEVICE-LIFECYCLE-EXPORT-PARITY §4·§5] **실제 XLSX 파일을 만들어 되읽는다.**
//
//   소스를 읽어 "컬럼이 맞다"고 말하는 것으로는 부족하다. 은행·회계로 넘어가는
//   파일이므로, production 생성기가 실제로 쓴 바이트를 다시 파싱해 canonical
//   원장과 대조한다.
//
//   어떻게 실제 파일을 얻는가
//     `PayrollExcelHelper._shareExcel` 은 임시 파일을 쓰고 공유한 **뒤 지운다**.
//     그래서 `SharePlatform` 을 갈아끼워 **공유 시점에 바이트를 가로챈다** —
//     production 경로(Excel 생성 → encode → 파일 쓰기)를 그대로 지난 결과물이다.
//     `PathProviderPlatform` 도 테스트 디렉터리로 바꾼다.
//
//   바꿔 끼우는 것은 그 두 플랫폼 경계와 `decrypt` 하나뿐이다. 계획 수립
//   (`buildTransferExportPlan`), 시트 구성, 합계, 메모 행은 production 코드다.
//
//   실제 계좌번호·개인정보는 쓰지 않는다. 전부 합성값이다.
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/utils/payroll_excel_helper.dart';
import 'package:ALfit/utils/person_label.dart';
import 'package:ALfit/utils/transfer_export_plan.dart';
import 'package:ALfit/utils/format_helper.dart';

// ── 플랫폼 경계 double ────────────────────────────────────────────────

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// 공유 시점에 **그 파일의 바이트를 붙잡는다**. production 이 직후에 지우므로
/// 여기서 읽지 않으면 검증할 대상이 사라진다.
class _CapturingShare extends SharePlatform with MockPlatformInterfaceMixin {
  final List<({String name, Uint8List bytes})> captured = [];

  @override
  Future<ShareResult> shareXFiles(
    List<XFile> files, {
    String? subject,
    String? text,
    Rect? sharePositionOrigin,
    List<String>? fileNameOverrides,
  }) async {
    for (final f in files) {
      captured.add((
        name: f.path.split(RegExp(r'[\\/]')).last,
        bytes: await File(f.path).readAsBytes(),
      ));
    }
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

// ── 합성 원장 ─────────────────────────────────────────────────────────

/// 합성 "암호문" — 앞에 표식을 붙여 두면 복호화를 거치지 않은 값이 파일에
/// 새어 나왔는지 바로 보인다.
String _enc(String plain) => 'ENC::$plain';
String? _decrypt(String cipher) =>
    cipher.startsWith('ENC::') ? cipher.substring(5) : null;

final _kDay = DateTime(2026, 10, 2);

/// 이체 금액의 출처는 `finalWage` 가 아니라 **`wageDetail.effectiveNetWage`** 다
/// (`classifyRecord` 실측). `effectiveNetWage` 는 `calculatedAt != null`
/// (= `isCalculated`) 일 때만 `netWage` 를 쓴다 — 그래서 확정 시각이 필요하다.
WageDetailModel _wd(int net) => WageDetailModel(
      wageType: 'hourly',
      baseWage: 12000,
      workMinutes: 480,
      totalAmount: net,
      netWage: net,
      calculatedAt: _kDay,
      confirmedAt: _kDay,
    );

AttendanceModel _att({
  required String id,
  required String uid,
  String businessId = 'bizA',
  String businessName = '가 물류센터',
  String workType = '상하차',
  DateTime? workDate,
  String status = 'completed',
  String wageStatus = AttendanceModel.wageConfirmed,
  int? finalWage = 100000,
  /// null 이면 wageDetail 자체가 없는 상태(= 금액을 **모르는** 건)를 만든다.
  int? net = 100000,
  String? bank = '아이엠뱅크',
  String? accountPlain = '0123456789',
  String? holder = '김합성',
  bool snapshot = true,
  int? snapshotVersion = 1,
}) =>
    AttendanceModel(
      id: id,
      applicationId: 'app_$id',
      userId: uid,
      businessId: businessId,
      businessName: businessName,
      workDate: workDate ?? _kDay,
      workType: workType,
      status: status,
      createdAt: _kDay,
      wageStatus: wageStatus,
      finalWage: finalWage,
      wageDetail: net == null ? null : _wd(net),
      wageAccountBankName: snapshot ? bank : null,
      wageAccountNumberEncrypted:
          snapshot && accountPlain != null ? _enc(accountPlain) : null,
      wageAccountHolder: snapshot ? holder : null,
      wageAccountSnapshotAt: snapshot ? _kDay : null,
      wageAccountSnapshotVersion: snapshot ? snapshotVersion : null,
    );

TransferExportPlan _plan(
  List<AttendanceModel> records, {
  Map<String, String> names = const {},
  Map<String, String> personNos = const {},
}) =>
    buildTransferExportPlan(
      records: records,
      names: names,
      personNos: personNos,
      decrypt: _decrypt,
      formatDate: FormatHelper.formatDateDot,
    );

// ── 실제 파일을 만들고 되읽는다 ───────────────────────────────────────

late Directory _tmp;
late _CapturingShare _share;

/// production `exportTransferList` 를 돌려 **실제 XLSX 를 파싱해** 돌려준다.
Future<({Excel book, Sheet sheet, String fileName})> _exportAndRead(
  WidgetTester t,
  TransferExportPlan plan, {
  String title = '이체목록 (2026년 10월)',
  String filename = '이체목록_2026-10.xlsx',
}) async {
  _share.captured.clear();
  late BuildContext ctx;
  await t.pumpWidget(MaterialApp(
    home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold(body: SizedBox.expand());
    }),
  ));
  // [함정] `testWidgets` 의 가짜 시계에서는 **실제 파일 I/O 가 진행되지 않는다.**
  //   `getTemporaryDirectory()` / `writeAsBytes` 의 Future 가 큐에 남아 영원히
  //   완료되지 않아 셀이 멈춘다(실측: XP-01 이 그렇게 걸렸다).
  //   실제 I/O 를 타는 production 경로는 `runAsync` 안에서 돌려야 한다.
  await t.runAsync(() => PayrollExcelHelper.exportTransferList(
      context: ctx, plan: plan, title: title, filename: filename));
  await t.pump();

  expect(_share.captured, hasLength(1),
      reason: '파일이 공유 경계까지 가지 않았다 — 생성 자체가 실패했을 수 있다');
  final cap = _share.captured.single;
  final book = Excel.decodeBytes(cap.bytes);
  expect(book.tables.keys, contains('이체목록'));
  return (book: book, sheet: book['이체목록'], fileName: cap.name);
}

String _text(Sheet s, int row, int col) {
  final v = s.rows.length > row && s.rows[row].length > col
      ? s.rows[row][col]?.value
      : null;
  if (v == null) return '';
  return v is TextCellValue ? v.value.toString() : v.toString();
}

num? _num(Sheet s, int row, int col) {
  final v = s.rows.length > row && s.rows[row].length > col
      ? s.rows[row][col]?.value
      : null;
  if (v is IntCellValue) return v.value;
  if (v is DoubleCellValue) return v.value;
  return null;
}

/// 데이터 행만 (제목 0행 · 헤더 1행 제외, 합계/메모 전까지).
List<List<String>> _dataRows(Sheet s, int count) => [
      for (var i = 0; i < count; i++)
        [for (var c = 0; c < 7; c++) _text(s, 2 + i, c)]
    ];

void main() {
  setUpAll(() async {
    _tmp = await Directory.systemTemp.createTemp('alfit_export_');
    PathProviderPlatform.instance = _FakePathProvider(_tmp.path);
    _share = _CapturingShare();
    SharePlatform.instance = _share;
  });
  tearDownAll(() async {
    try {
      await _tmp.delete(recursive: true);
    } catch (_) {}
  });

  // ══════════════════════════════════════════════════════════════════
  // 1. 파일 구조 — 머리글이 사실을 구분해 말하는가
  // ══════════════════════════════════════════════════════════════════

  testWidgets('XP-01 실제 파일의 머리글이 이름과 예금주를 구분한다', (t) async {
    final r = await _exportAndRead(
        t, _plan([_att(id: 'a1', uid: 'u1')], names: {'u1': '김하나'}));

    expect(_text(r.sheet, 1, 0), PersonLabel.fieldLabel);
    expect(_text(r.sheet, 1, 1), '근로자명(현재)');
    expect(_text(r.sheet, 1, 2), '은행명');
    expect(_text(r.sheet, 1, 3), '계좌번호');
    // 이름 ≠ 예금주. 개명하면 달라질 수 있고 그건 오류가 아니다.
    expect(_text(r.sheet, 1, 4), '예금주(급여확정시)');
    expect(_text(r.sheet, 1, 5), '이체금액');
    expect(_text(r.sheet, 1, 6), '메모');
    expect(t.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════
  // 2. 계좌번호 — 앞자리 0 이 살아 있는가 (§4 명시 요구)
  // ══════════════════════════════════════════════════════════════════

  testWidgets('XP-02 계좌번호 앞자리 0 이 파일에서 사라지지 않는다', (t) async {
    final r = await _exportAndRead(
        t,
        _plan([
          _att(id: 'a1', uid: 'u1', accountPlain: '0123456789'),
        ], names: {'u1': '김하나'}));

    // 숫자 셀로 쓰면 0123456789 → 123456789 가 된다. 문자로 남아야 한다.
    expect(_text(r.sheet, 2, 3), '0123456789');
    expect(_num(r.sheet, 2, 3), isNull,
        reason: '계좌번호가 숫자 셀이면 앞자리 0 이 사라진다');
    // 금액은 반대로 숫자여야 한다 — 받는 쪽이 합을 낸다.
    expect(_num(r.sheet, 2, 5), 100000);
    expect(t.takeException(), isNull);
  });

  testWidgets('XP-03 하이픈·공백이 섞인 계좌번호도 원문 그대로 나간다', (t) async {
    final r = await _exportAndRead(
        t,
        _plan([_att(id: 'a1', uid: 'u1', accountPlain: '012-3456-7890')],
            names: {'u1': '김하나'}));
    expect(_text(r.sheet, 2, 3), '012-3456-7890');
    expect(t.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════
  // 3. 사람 식별 — 동명이인을 파일에서 가를 수 있는가
  // ══════════════════════════════════════════════════════════════════

  testWidgets('XP-04 같은 이름 다른 사람이 인력번호로 구별된다', (t) async {
    final r = await _exportAndRead(
        t,
        _plan([
          _att(id: 'a1', uid: 'u1', accountPlain: '1111111111'),
          _att(id: 'a2', uid: 'u2', accountPlain: '2222222222'),
        ],
            names: {'u1': '김동명', 'u2': '김동명'},
            personNos: {'u1': 'W-001', 'u2': 'W-014'}));

    final rows = _dataRows(r.sheet, 2);
    expect(rows.map((x) => x[1]).toSet(), {'김동명'}, reason: '이름은 같다');
    // 이름이 같아도 사람은 다르다 — 번호가 그것을 말해야 한다.
    expect(rows.map((x) => x[0]).toList()..sort(), ['W-001', 'W-014']);
    expect(rows.map((x) => x[3]).toSet(), {'1111111111', '2222222222'});
    expect(t.takeException(), isNull);
  });

  testWidgets('XP-05 이름을 모르면 빈칸이 아니라 모른다고 적는다', (t) async {
    // 조회 실패를 빈 이름으로 내보내면 받는 쪽은 "이름 없는 사람"을 본다.
    final r = await _exportAndRead(t, _plan([_att(id: 'a1', uid: 'uX')]));
    expect(_text(r.sheet, 2, 1), '이름 확인 불가');
    expect(t.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════
  // 4. 금액 합산 — 한 사람의 여러 근무가 어떻게 합쳐지는가
  // ══════════════════════════════════════════════════════════════════

  testWidgets('XP-06 같은 사람 · 같은 계좌 여러 건은 한 행으로 합산된다', (t) async {
    final plan = _plan([
      _att(id: 'a1', uid: 'u1', finalWage: 100000, net: 100000),
      _att(id: 'a2', uid: 'u1', finalWage: 55000, net: 55000, workType: '사무업무'),
      _att(
          id: 'a3',
          uid: 'u1',
          finalWage: 20000,
          net: 20000,
          workDate: DateTime(2026, 10, 3)),
    ], names: {'u1': '김하나'});

    expect(plan.rows, hasLength(1), reason: '이체는 계좌 단위다');
    final r = await _exportAndRead(t, plan);
    expect(_num(r.sheet, 2, 5), 175000);
    // 합계 행도 같은 값이어야 한다 — 행이 하나니까.
    expect(_text(r.sheet, 3, 4), '합계');
    expect(_num(r.sheet, 3, 5), 175000);
    expect(t.takeException(), isNull);
  });

  testWidgets('XP-07 같은 사람이라도 계좌가 다르면 행이 갈린다', (t) async {
    // 급여 확정 후 계좌를 바꾼 경우. snapshot 은 소급 변경되지 않으므로
    // 한 사람에게 서로 다른 계좌로 보낼 돈이 생긴다 — 합치면 한쪽이 사라진다.
    final plan = _plan([
      _att(
          id: 'a1',
          uid: 'u1',
          accountPlain: '1111111111',
          finalWage: 100000,
          net: 100000),
      _att(
          id: 'a2',
          uid: 'u1',
          accountPlain: '9999999999',
          finalWage: 70000,
          net: 70000),
    ], names: {'u1': '김하나'});

    expect(plan.rows, hasLength(2));
    final r = await _exportAndRead(t, plan);
    final rows = _dataRows(r.sheet, 2);
    expect(rows.map((x) => x[3]).toList()..sort(),
        ['1111111111', '9999999999']);
    final total = rows
        .asMap()
        .entries
        .map((e) => _num(r.sheet, 2 + e.key, 5)!)
        .fold<num>(0, (a, b) => a + b);
    expect(total, 170000, reason: '두 계좌 금액의 합이 보존돼야 한다');
    expect(_num(r.sheet, 4, 5), 170000, reason: '합계 행');
    expect(t.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════
  // 5. 상태별 포함·제외 (§5) — 잘못 포함하거나 누락하면 BLOCKER
  // ══════════════════════════════════════════════════════════════════

  testWidgets('XP-08 이미 이체완료된 근무는 조회 단계에서 걸러진다 (2계층 계약)', (t) async {
    // 실측 계약: `classifyRecord` 는 `wageStatus` 를 **보지 않는다.**
    //   이체완료 제외의 주인은 미이체 탭의 reader 술어
    //   `AttendanceModel.isPayableForTransfer`(= wageStatus==confirmed
    //   && !isNonPayableZero) 다. 그래서 두 계층을 **둘 다** 확인한다 —
    //   exporter 만 보면 "이체완료가 파일에 들어간다"는 잘못된 결론이 나온다.
    final all = [
      _att(id: 'a1', uid: 'u1', wageStatus: AttendanceModel.wageConfirmed),
      _att(
          id: 'a2',
          uid: 'u2',
          wageStatus: AttendanceModel.wageTransferred,
          accountPlain: '2222222222'),
      _att(
          id: 'a3',
          uid: 'u3',
          wageStatus: AttendanceModel.wageCalculated,
          accountPlain: '3333333333'),
    ];

    // ① 계층 1 — production getter 가 confirmed 하나만 통과시킨다.
    final payable = all.where((r) => r.isPayableForTransfer).toList();
    expect(payable.map((r) => r.id).toList(), ['a1'],
        reason: '이체완료·계산중이 미이체 목록에 남으면 이중 지급 위험이다');

    // ② 계층 2 — 그 집합만 파일로 간다.
    final plan = _plan(payable, names: {'u1': '김하나', 'u2': '이둘', 'u3': '박셋'});
    final r = await _exportAndRead(t, plan);
    final rows = _dataRows(r.sheet, plan.rows.length);
    expect(rows.map((x) => x[1]).toList(), ['김하나']);

    // ③ exporter 단독으로는 걸러지지 않는다는 사실도 못박는다 —
    //    reader 를 건너뛰고 전체를 주면 3행이 된다.
    expect(_plan(all).rows, hasLength(3),
        reason: 'exporter 가 wageStatus 를 보지 않는다는 현재 계약');
    expect(t.takeException(), isNull);
  });

  testWidgets('XP-09 급여 미확정 근무는 포함되지 않고 제외 사유가 남는다', (t) async {
    final plan = _plan([
      _att(id: 'a1', uid: 'u1'),
      _att(
          id: 'a2',
          uid: 'u2',
          wageStatus: AttendanceModel.wagePending,
          finalWage: null,
          snapshot: false,
          accountPlain: null),
    ], names: {'u1': '김하나', 'u2': '이둘'});

    expect(plan.rows.map((x) => x.workerName).toList(), ['김하나']);
    expect(plan.blockedRecords + plan.notApplicableRecords, greaterThan(0),
        reason: '빠진 건이 조용히 사라지면 안 된다');

    final r = await _exportAndRead(t, plan);
    // 메모 행이 "전체 N건 중 M건 포함"을 말한다 — 파일만 보고도 누락을 안다.
    final note = [
      for (var i = 0; i < r.sheet.rows.length; i++) _text(r.sheet, i, 0)
    ].firstWhere((s) => s.contains('전체 급여'), orElse: () => '');
    expect(note, contains('전체 급여 ${plan.totalRecords}건 중 '
        '${plan.exportedRecords}건 포함'));
    expect(t.takeException(), isNull);
  });

  testWidgets('XP-10 NO_SHOW 0원은 지급 대상이 아니다 — 데이터 오류와 다르다', (t) async {
    final plan = _plan([
      _att(id: 'a1', uid: 'u1'),
      _att(
          id: 'a2',
          uid: 'u2',
          status: 'NO_SHOW',
          finalWage: 0,
          accountPlain: '2222222222'),
    ], names: {'u1': '김하나', 'u2': '이둘'});

    expect(plan.rows.map((x) => x.workerName).toList(), ['김하나'],
        reason: '0원을 이체 목록에 넣으면 받는 쪽이 0원 송금을 시도한다');
    // "해당 없음"과 "확인 필요"는 서로 다른 칸으로 세어야 한다.
    expect(plan.notApplicableRecords, greaterThan(0));
    expect(t.takeException(), isNull);
  });

  testWidgets('XP-11 계좌 복호화 실패는 조용히 빠지지 않는다', (t) async {
    // 복호화가 실패하면 "계좌를 모르는 상태"다 — 빈 계좌로 내보내면 안 되고,
    // 목록에서 사라져서도 안 된다(돈 받을 사람이 있다).
    final plan = _plan([
      _att(id: 'a1', uid: 'u1'),
      // 표식이 없는 값 → _decrypt 가 null 을 돌려준다.
      AttendanceModel(
        id: 'a2',
        applicationId: 'app_a2',
        userId: 'u2',
        businessId: 'bizA',
        businessName: '가 물류센터',
        workDate: _kDay,
        workType: '상하차',
        status: 'completed',
        createdAt: _kDay,
        wageStatus: AttendanceModel.wageConfirmed,
        finalWage: 70000,
        wageAccountBankName: '아이엠뱅크',
        wageAccountNumberEncrypted: 'BROKEN-CIPHER',
        wageAccountHolder: '이둘',
        wageAccountSnapshotAt: _kDay,
        wageAccountSnapshotVersion: 1,
      ),
    ], names: {'u1': '김하나', 'u2': '이둘'});

    final exported = plan.rows.map((x) => x.uid).toSet();
    expect(exported.contains('u2'), isFalse,
        reason: '계좌를 모르는 채로 이체 파일에 넣으면 안 된다');
    expect(plan.blockedRecords, greaterThan(0),
        reason: '복호화 실패가 집계에서 사라지면 운영자가 모른다');
    final r = await _exportAndRead(t, plan);
    // 파일 어디에도 암호문이 새지 않아야 한다.
    final all = [
      for (var i = 0; i < r.sheet.rows.length; i++)
        for (var c = 0; c < 7; c++) _text(r.sheet, i, c)
    ].join('|');
    expect(all.contains('BROKEN-CIPHER'), isFalse);
    expect(all.contains('ENC::'), isFalse, reason: '암호문이 파일로 나갔다');
    expect(t.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════
  // 6. 빈 결과 · 재현성
  // ══════════════════════════════════════════════════════════════════

  testWidgets('XP-12 대상 0건이면 파일을 만들지 않는다', (t) async {
    _share.captured.clear();
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox.expand());
      }),
    ));
    await t.runAsync(() => PayrollExcelHelper.exportTransferList(
        context: ctx,
        plan: _plan(const []),
        title: 't',
        filename: 'empty.xlsx'));
    await t.pump();
    // 빈 파일을 건네면 받는 쪽은 "이체할 사람이 없다"를 "파일이 비었다"로 읽는다.
    expect(_share.captured, isEmpty);
    await t.pump(const Duration(seconds: 3));   // 토스트 타이머 비우기
  });

  testWidgets('XP-13 같은 계획을 두 번 내보내면 같은 파일이 나온다', (t) async {
    final plan = _plan([
      _att(id: 'a1', uid: 'u1', accountPlain: '1111111111'),
      _att(id: 'a2', uid: 'u2', accountPlain: '2222222222'),
      _att(id: 'a3', uid: 'u3', accountPlain: '3333333333'),
    ], names: {'u1': '김하나', 'u2': '이둘', 'u3': '박셋'});

    final a = await _exportAndRead(t, plan);
    final rowsA = _dataRows(a.sheet, 3);
    final b = await _exportAndRead(t, plan);
    final rowsB = _dataRows(b.sheet, 3);
    expect(rowsB, rowsA, reason: '재다운로드가 순서를 바꾸면 대조가 불가능해진다');
    expect(b.fileName, a.fileName);
    expect(t.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════
  // 7. 개인정보 — 필요 없는 것이 섞이지 않는가 (§7)
  // ══════════════════════════════════════════════════════════════════

  testWidgets('XP-14 파일에 CI·주민번호·로그인 ID·연락처가 없다', (t) async {
    final r = await _exportAndRead(
        t,
        _plan([_att(id: 'a1', uid: 'u1')],
            names: {'u1': '김하나'}, personNos: {'u1': 'W-001'}));

    final all = [
      for (var i = 0; i < r.sheet.rows.length; i++)
        for (var c = 0; c < 8; c++) _text(r.sheet, i, c)
    ].join('|');
    // uid 자체도 은행 파일에 들어갈 이유가 없다 — 사람은 인력번호로 가린다.
    expect(all.contains('u1'), isFalse, reason: 'uid 가 파일에 나갔다');
    for (final forbidden in ['ciHash', '주민', 'username', '@ALfit-system.com',
      '010', 'idCard']) {
      expect(all.contains(forbidden), isFalse, reason: '$forbidden 가 파일에 있다');
    }
    expect(t.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════
  // 8. 사업장 격리 (§7) — 다른 사업장 건이 섞이지 않는가
  // ══════════════════════════════════════════════════════════════════

  testWidgets('XP-15 사업장 격리의 주인은 조회 단계다 — exporter 는 받은 집합을 쓴다', (t) async {
    // 실측 계약: `buildTransferExportPlan` 에는 `businessId` 매개변수가 **없다**.
    //   격리는 화면의 조회(`widget.businessId` 로 범위를 준 reader)가 하고,
    //   `prepareTransferPlan` 의 businessId 는 **이름·인력번호 조회용**이다.
    //   그래서 "exporter 가 다른 사업장을 걸러 준다"고 기대하면 안 된다 —
    //   섞인 집합을 주면 섞인 파일이 나온다. 그 사실을 여기서 못박아,
    //   격리 검증을 조회 계층에서 하도록 남긴다.
    final plan = _plan([
      _att(id: 'a1', uid: 'u1', businessId: 'bizA'),
      _att(id: 'a2', uid: 'u2', businessId: 'bizB', businessName: '나 센터',
          accountPlain: '2222222222'),
    ], names: {'u1': '김하나', 'u2': '이둘'});

    expect(plan.rows, hasLength(2),
        reason: 'exporter 는 사업장을 보지 않는다 — 이것이 현재 계약이다');
    final r = await _exportAndRead(t, plan);
    final rows = _dataRows(r.sheet, 2);
    expect(rows.map((x) => x[1]).toList()..sort(), ['김하나', '이둘']);
    // 그리고 파일에는 사업장 열이 아예 없다 — 받는 쪽은 파일명으로만 구분한다.
    expect(_text(r.sheet, 1, 0), PersonLabel.fieldLabel);
    expect([for (var c = 0; c < 7; c++) _text(r.sheet, 1, c)]
        .any((h) => h.contains('사업장')), isFalse);
    expect(t.takeException(), isNull);
  });
}
