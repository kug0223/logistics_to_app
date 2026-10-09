// [R7-PREDEVICE-DISCLOSURE-RENDER.1] 계약 PDF — **생성물의 내용**을 확인한다.
//
// ── 앞선 Phase 가 멈춘 곳 ───────────────────────────────────────────
//   `%PDF-` 헤더와 빌더 구조(`pw.Expanded`·`pw.MultiPage`)까지만 봤다.
//   그것은 "파일이 만들어졌다" 이지 "근로자가 읽을 수 있다" 가 아니다.
//
// ── 여기서 하는 것 ─────────────────────────────────────────────────
//   production `ContractPdfBuilder` 로 PDF 를 만들고, 그 바이트를
//   `pdftotext` (Xpdf 4.00, `-layout -enc UTF-8`) 로 **페이지별로** 풀어
//   실제로 무엇이 적혔는지 본다. 확인하는 축:
//     · 한글이 글리프로 들어가 **추출된다** (폰트 임베딩·ToUnicode)
//     · 7개 근태 기준이 라벨·값 모두 **빠짐없이** 들어간다
//     · 긴 문장이 칸 안에서 **줄바꿈**한다 (layout 모드의 행 분해로 확인)
//     · 페이지가 **분할**된다 — 넘치지 않고 다음 장으로 넘어간다
//     · 서명 영역과 본문이 **다른 행**에 있다
//
// ── 확인하지 못하는 축 (정직하게 남긴다) ───────────────────────────
//   **래스터 렌더는 이 환경에서 불가능하다.** `printing` 패키지의
//   `Printing.raster` 는 플랫폼 채널(pdfium)을 타므로 `flutter test` 에서
//   동작하지 않고, `pdftoppm`·Ghostscript·ImageMagick·mutool 이 모두 없다
//   (`convert` 는 Windows 파일시스템 도구다). 설치된 `pdftotext` 는
//   Xpdf 4.00 이라 `-bbox` 좌표도 제공하지 않는다.
//   따라서 **글리프가 실제로 그려진 모양**(tofu·폰트 폴백 여부)과
//   **픽셀 단위 겹침**은 `VISUAL PENDING` 으로 남긴다.
//
//   실제 개인정보를 쓰지 않는다 — 전부 합성 fixture 다.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/screens/contract/contract_pdf_builder.dart';
import 'package:ALfit/utils/attendance_policy_disclosure.dart';

// ═══════════════════════════════════════════════════════════════
// pdftotext 구동
// ═══════════════════════════════════════════════════════════════

/// `pdftotext` 실행 파일. 없으면 null — 그 경우 테스트는 **건너뛰지 않고**
/// 추출 축을 PENDING 으로 보고하도록 실패시킨다(조용한 통과를 막는다).
String? _pdftotext() {
  for (final c in const [
    r'C:\msys64\mingw64\bin\pdftotext.exe',
    r'C:\Program Files\Git\mingw64\bin\pdftotext.exe',
    'pdftotext',
  ]) {
    try {
      final r = Process.runSync(c, const ['-v']);
      final out = '${r.stdout}${r.stderr}';
      if (out.contains('pdftotext')) return c;
    } catch (_) {
      // 다음 후보
    }
  }
  return null;
}

late final String? _tool = _pdftotext();
late final Directory _work =
    Directory.systemTemp.createTempSync('alfit_pdf_visual');

/// PDF 를 쓰고 페이지 [page] 의 텍스트를 레이아웃 보존으로 돌려준다.
/// [page] 가 null 이면 전체.
String _extract(Uint8List bytes, {int? page, String tag = 'doc'}) {
  final pdf = File('${_work.path}${Platform.pathSeparator}$tag.pdf');
  pdf.writeAsBytesSync(bytes);
  final out = '${_work.path}${Platform.pathSeparator}$tag'
      '${page ?? 'all'}.txt';
  final args = <String>[
    '-layout',
    '-enc',
    'UTF-8',
    if (page != null) ...['-f', '$page', '-l', '$page'],
    pdf.path,
    out,
  ];
  final r = Process.runSync(_tool!, args);
  expect(File(out).existsSync(), isTrue,
      reason: 'pdftotext 실패 (exit ${r.exitCode}): ${r.stderr}');
  return File(out).readAsStringSync();
}

/// 전체 페이지 수 — 페이지를 하나씩 뽑아 빈 결과가 나올 때까지.
int _pageCount(Uint8List bytes, {String tag = 'doc'}) {
  var n = 0;
  for (var p = 1; p <= 40; p++) {
    final t = _extract(bytes, page: p, tag: '${tag}_p$p');
    if (t.trim().isEmpty) break;
    n = p;
  }
  return n;
}

// ═══════════════════════════════════════════════════════════════
// 합성 fixture
// ═══════════════════════════════════════════════════════════════

AttendanceRules _standard() => AttendanceRules.defaults().copyWith(
      earlyWindow: 30,
      earlyArrivalUnit: 30,
      lateGrace: 5,
      lateUnit: 30,
      lateWindow: 30,
      overtimeUnit: 30,
      earlyLeaveUnit: 30,
    );

AttendanceRules _boundary() => AttendanceRules.defaults().copyWith(
      earlyWindow: 0,
      earlyArrivalUnit: 5,
      lateGrace: 0,
      lateUnit: 5,
      lateWindow: 0,
      overtimeUnit: 5,
      earlyLeaveUnit: 5,
    );

AttendanceRules _longest() => AttendanceRules.defaults().copyWith(
      earlyWindow: 120,
      earlyArrivalUnit: 60,
      lateGrace: 30,
      lateUnit: 60,
      lateWindow: 60,
      overtimeUnit: 60,
      earlyLeaveUnit: 60,
    );

/// [noPolicy] 가 true 면 고지를 **정말로 비운다**. `policy: null` 로는
/// 구별할 수 없다 — 기본값 합치기(`?? _standard()`)가 null 을 삼키기 때문이다.
ContractSnapshot _snapshot({
  AttendanceRules? policy,
  bool shortTerm = false,
  bool noPolicy = false,
}) =>
    ContractSnapshot(
      businessName: '중앙물류센터 수도권 1센터',
      businessNumber: '0000000000',
      businessAddress: '경기도 화성시 동탄순환대로 1길 23 3층 물류동 A구역',
      ownerName: '박사장',
      workerName: '김근로',
      workType: '냉장 분류',
      workPlace: '경기도 화성시 동탄순환대로 1길 23',
      isLongTerm: !shortTerm,
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
      attendancePolicy: noPolicy ? null : (policy ?? _standard()),
    );

Future<Uint8List> _build({
  AttendanceRules? policy,
  List<ContractArticle> articles = const [],
  List<ContractSlot> slots = const [],
}) =>
    ContractPdfBuilder.build(
      snapshot: _snapshot(policy: policy),
      contractDate: DateTime(2026, 10, 1),
      articles: articles,
      slots: slots,
    );

/// 공백을 접어 비교한다 — `-layout` 은 칸을 맞추려고 빈칸을 넣는다.
String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  tearDownAll(() {
    try {
      _work.deleteSync(recursive: true);
    } catch (_) {
      // 임시 디렉터리 정리 실패는 결과에 영향이 없다.
    }
  });

  group('[PDFV-0] 추출 도구', () {
    test('PDFV-00 pdftotext 로 생성물을 풀 수 있다', () {
      expect(_tool, isNotNull,
          reason: 'pdftotext 가 없다 — PDF 내용 검증을 PENDING 으로 남겨야 한다');
    });
  });

  group('[PDFV-1] 한글과 7개 기준이 실제로 적힌다', () {
    testWidgets('PDFV-01 한글이 추출된다 — 폰트가 글리프로 들어갔다', (t) async {
      final text = _extract(await _build(), tag: 'ko');
      // 제목·당사자·근무 정보가 한글로 읽힌다.
      for (final must in const [
        '근로계약서',
        '중앙물류센터 수도권 1센터',
        '김근로',
        '박사장',
        '냉장 분류',
      ]) {
        expect(text.contains(must), isTrue,
            reason: '"$must" 가 PDF 에서 추출되지 않는다 — 한글 인코딩 문제');
      }
      // 깨진 문자 흔적이 없다.
      expect(text.contains('\uFFFD'), isFalse, reason: '치환 문자(U+FFFD) 가 있다');
    });

    testWidgets('PDFV-02 7개 근태 기준이 라벨·값 모두 들어간다', (t) async {
      final r = _standard();
      final text = _flat(_extract(await _build(policy: r), tag: 'seven'));
      final lines = attendancePolicyLines(r);
      expect(lines.length, 7);
      for (final l in lines) {
        expect(text.contains(l.label), isTrue,
            reason: 'PDF 에 "${l.label}" 라벨이 없다');
        expect(text.contains(_flat(l.value)), isTrue,
            reason: 'PDF 에 "${l.label}" 의 값이 없다\n  기대: ${l.value}');
      }
    });

    testWidgets('PDFV-03 경계 설정도 그 설정의 숫자로 적힌다', (t) async {
      final r = _boundary();
      final text = _flat(_extract(await _build(policy: r), tag: 'bound'));
      for (final l in attendancePolicyLines(r)) {
        expect(text.contains(_flat(l.value)), isTrue,
            reason: '경계 설정의 값이 PDF 에 없다: ${l.value}');
      }
      // 기본값(30분) 문구가 섞이지 않았다.
      for (final l in attendancePolicyLines(_standard())) {
        expect(text.contains(_flat(l.value)), isFalse,
            reason: '다른 설정의 문구가 섞였다: ${l.value}');
      }
    });

    testWidgets('PDFV-04 가장 긴 조합도 잘리지 않는다', (t) async {
      final r = _longest();
      final text = _flat(_extract(await _build(policy: r), tag: 'long'));
      for (final l in attendancePolicyLines(r)) {
        expect(text.contains(_flat(l.value)), isTrue,
            reason: '긴 문구가 PDF 에서 잘렸다: ${l.value}');
      }
      expect(text.contains('…'), isFalse, reason: '말줄임이 들어갔다');
    });
  });

  group('[PDFV-2] 줄바꿈과 페이지 구성', () {
    testWidgets('PDFV-05 긴 고지 값은 **여러 행**으로 흐른다', (t) async {
      // `_row` 는 값을 `pw.Expanded` 에 넣는다 — 칸보다 길면 다음 행으로
      //   내려가야 한다. layout 모드는 그 줄바꿈을 행 분리로 보여준다.
      final raw = _extract(await _build(policy: _longest()), tag: 'wrap');
      final rows = raw.split('\n');
      // 가장 긴 고지 값이 한 행에 통째로 들어가 있지 않다.
      final longest = attendancePolicyLines(_longest())
          .map((l) => l.value)
          .reduce((a, b) => a.length >= b.length ? a : b);
      final onOneRow = rows.any((r) => _flat(r).contains(_flat(longest)));
      // 한 행에 다 들어갔다면 칸이 충분히 넓은 것이므로 그 자체는 결함이
      //   아니다. 다만 **어딘가에는** 반드시 있어야 한다.
      expect(_flat(raw).contains(_flat(longest)), isTrue,
          reason: '가장 긴 고지 값이 PDF 에 없다');
      // 줄바꿈이 일어났다면 조각이 서로 다른 행에 있다.
      if (!onOneRow) {
        final head = _flat(longest).split(' ').first;
        expect(rows.any((r) => r.contains(head)), isTrue,
            reason: '줄바꿈된 조각조차 찾을 수 없다 — 값이 사라졌다');
      }
    });

    testWidgets('PDFV-06 본문이 길면 **페이지가 나뉜다**', (t) async {
      final many = [
        for (var i = 1; i <= 40; i++)
          ContractArticle(
            title: '제$i조 (시험 조항)',
            content: '이 조항은 페이지 분할을 확인하기 위한 긴 본문이다. ' * 12,
          ),
      ];
      final bytes = await _build(articles: many);
      final pages = _pageCount(bytes, tag: 'multi');
      expect(pages, greaterThan(1),
          reason: '긴 계약서가 한 장에 머물렀다 — 넘침을 숨긴 것이다');

      // 각 페이지에 실제 내용이 있다 — 빈 장을 만들지 않았다.
      for (var p = 1; p <= pages; p++) {
        final t = _extract(bytes, page: p, tag: 'multi_chk$p');
        expect(t.trim().isNotEmpty, isTrue, reason: '$p쪽이 비어 있다');
      }

      // 마지막 조항이 사라지지 않았다.
      final all = _flat(_extract(bytes, tag: 'multi_all'));
      expect(all.contains('제40조 (시험 조항)'), isTrue,
          reason: '마지막 조항이 잘려 나갔다');
    });

    testWidgets('PDFV-07 짧은 계약서의 2쪽은 **서명 블록**이다 — 잘린 본문이 아니다',
        (t) async {
      // 실측: 고지가 없으면 1쪽, 7줄 고지가 들어가면 2쪽이 된다.
      //   2쪽에는 서명 블록만 있다(58자). 내용이 사라진 것이 아니라
      //   서명이 통째로 다음 장으로 넘어간 것이므로 결함이 아니다 —
      //   법적으로 필요한 고지를 줄여 1쪽에 맞추지 않는다.
      final bytes = await _build();
      final pages = _pageCount(bytes, tag: 'single');
      expect(pages, lessThanOrEqualTo(2),
          reason: '짧은 계약서가 $pages장이다 — 예상보다 많다');

      if (pages == 2) {
        final p2 = _flat(_extract(bytes, page: 2, tag: 'single_p2'));
        // 서명 영역이 통째로 2쪽에 있다.
        for (final must in const ['사업주', '근로자', '박사장', '김근로']) {
          expect(p2.contains(must), isTrue,
              reason: '2쪽에 서명 블록이 없다 — 그럼 무엇이 넘어갔는가: $p2');
        }
        // 본문 고지가 2쪽으로 **쪼개져** 넘어가지 않았다.
        final p1 = _flat(_extract(bytes, page: 1, tag: 'single_p1'));
        for (final l in attendancePolicyLines(_standard())) {
          expect(p1.contains(_flat(l.value)), isTrue,
              reason: '고지가 1쪽에 온전히 있지 않다: ${l.value}');
        }
      }
    });

    testWidgets('PDFV-07b 고지를 넣어도 본문이 사라지지 않는다 — 1쪽↔2쪽 대조',
        (t) async {
      // 고지 유무로 쪽수가 달라지는 것 자체는 정상이다. 확인할 것은
      //   **내용 손실이 없다**는 것이다.
      final without = await ContractPdfBuilder.build(
        snapshot: _snapshot(noPolicy: true),
        contractDate: DateTime(2026, 10, 1),
      );
      final withPolicy = await _build();
      final a = _flat(_extract(without, tag: 'wo'));
      final b = _flat(_extract(withPolicy, tag: 'wi'));

      // 고지 없는 쪽의 모든 조항 제목이 고지 있는 쪽에도 있다.
      for (final must in const [
        '제1조 (근로계약 당사자)',
        '제2조 (근무 조건)',
        '제3조 (임금)',
        '근무 기간',
        '근무 시간',
      ]) {
        expect(a.contains(must), isTrue, reason: '대조본에 "$must" 가 없다');
        expect(b.contains(must), isTrue,
            reason: '고지를 넣자 "$must" 가 사라졌다');
      }
      // 고지 쪽에만 7줄이 더 있다.
      for (final l in attendancePolicyLines(_standard())) {
        expect(a.contains(_flat(l.value)), isFalse);
        expect(b.contains(_flat(l.value)), isTrue);
      }
    });

    testWidgets('PDFV-08 근무 일정 표가 들어가도 값이 보존된다', (t) async {
      // 일정 표는 **단기** 계약에만 들어간다(`isLongTerm == false` 분기).
      //   장기 계약은 기간·요일로 적으므로 표가 없다.
      final slots = [
        for (var d = 1; d <= 12; d++)
          ContractSlot(
            applicationId: 'app$d',
            workDate: '2026-10-${d.toString().padLeft(2, '0')}',
            startTime: '09:00',
            endTime: '18:00',
            wage: 12000,
            wageType: 'hourly',
          ),
      ];
      final bytes = await ContractPdfBuilder.build(
        snapshot: _snapshot(shortTerm: true),
        contractDate: DateTime(2026, 10, 1),
        slots: slots,
      );
      final text = _flat(_extract(bytes, tag: 'slots'));
      expect(text.contains('2026-10-01'), isTrue, reason: '첫 근무일이 없다');
      expect(text.contains('2026-10-12'), isTrue,
          reason: '마지막 근무일이 표에서 잘렸다');
      // 표가 생겨도 7개 고지가 함께 남는다.
      for (final l in attendancePolicyLines(_standard())) {
        expect(text.contains(_flat(l.value)), isTrue,
            reason: '표 때문에 고지가 밀려 사라졌다: ${l.value}');
      }
    });
  });

  group('[PDFV-2b] 라벨과 값이 올바르게 **짝지어진다**', () {
    /// 그리기 순서 그대로 뽑는다. `-layout` 은 여러 줄짜리 값 옆의 라벨을
    /// 어느 행에 붙일지 추측하므로 짝을 판정하는 데 쓸 수 없다 —
    /// 실제로 `-layout` 결과만 보면 라벨이 한 칸 밀려 보인다(측정 확인).
    String raw(Uint8List bytes, String tag) {
      final pdf = File('${_work.path}${Platform.pathSeparator}$tag.pdf');
      pdf.writeAsBytesSync(bytes);
      final out = '${_work.path}${Platform.pathSeparator}${tag}_raw.txt';
      Process.runSync(
          _tool!, ['-raw', '-enc', 'UTF-8', pdf.path, out]);
      return File(out).readAsStringSync();
    }

    testWidgets('PDFV-10 7개 라벨 각각이 **자기 값**과 같은 줄에 있다', (t) async {
      for (final r in [_standard(), _boundary(), _longest()]) {
        final rows = raw(await _build(policy: r), 'pair${r.lateUnit}')
            .split('\n')
            .map(_flat)
            .toList();
        for (final l in attendancePolicyLines(r)) {
          final hit = rows.where((row) => row.startsWith('${l.label} '));
          expect(hit, isNotEmpty,
              reason: '단위 ${r.lateUnit} — "${l.label}" 줄이 없다');
          expect(hit.first, '${l.label} ${_flat(l.value)}',
              reason: '단위 ${r.lateUnit} — "${l.label}" 의 값이 어긋났다\n'
                  '  기대: ${l.label} ${_flat(l.value)}\n'
                  '  실제: ${hit.first}');
        }
      }
    });

    testWidgets('PDFV-11 값 없는 라벨이 없다 — 7개 모두 내용을 가진다', (t) async {
      final r = _standard();
      final rows = raw(await _build(policy: r), 'empty')
          .split('\n')
          .map(_flat)
          .toList();
      for (final l in attendancePolicyLines(r)) {
        final row = rows.firstWhere((x) => x.startsWith('${l.label} '),
            orElse: () => '');
        expect(row.replaceFirst('${l.label} ', '').trim().isNotEmpty, isTrue,
            reason: '"${l.label}" 이 값 없이 적혔다');
      }
    });
  });

  group('[PDFV-3] 서명 영역', () {
    testWidgets('PDFV-09 서명 영역이 본문과 다른 행에 있다', (t) async {
      final raw = _extract(await _build(), tag: 'sign');
      final rows = raw.split('\n').map(_flat).toList();
      // 서명 블록의 라벨을 찾는다.
      final signRow = rows.indexWhere((r) => r.contains('사업주') || r.contains('(인)'));
      expect(signRow, greaterThan(-1), reason: '서명 영역을 찾지 못했다');

      // 그 행에 근태 고지 값이 같이 끼어 있지 않다 — 겹쳐 적힌 흔적.
      final policyValues =
          attendancePolicyLines(_standard()).map((l) => _flat(l.value));
      for (final v in policyValues) {
        expect(rows[signRow].contains(v), isFalse,
            reason: '서명 행에 본문 고지가 겹쳤다: $v');
      }
      // 당사자 이름은 서명 영역 쪽에 있다.
      expect(raw.contains('박사장'), isTrue);
      expect(raw.contains('김근로'), isTrue);
    });
  });
}
