// 업무 추가 다이얼로그 정보 위계 (CTF-01 / CTF-02)
//
// 이전에는 11개 섹션이 한 화면에 평면 나열돼, 필수 항목과 정산 설정이
// 같은 시각 무게로 놓였다. 첫 공고를 쓰는 관리자가 공제 방식·급여 지급
// 일정을 "지금 정해야 하는 것"으로 오인하기 쉬웠다.
//
// 해결은 필수/선택 이분법이 아니라 **의미 단위 위계**다.
//   ① 핵심 모집조건   무엇을·얼마에·몇 명·언제 (기초 시급은 급여 종속값)
//   ② 추가 근무조건   근무가 실제로 어떻게 이뤄지는가 — 접지 않는다
//   ③ 급여·정산 설정  돈이 어떻게 처리·지급되는가 — 우선순위만 낮춰 접는다
//
// ③을 접는 이유는 "선택이라 덜 중요해서"가 아니다. 실제로 급여 지급
// 일정은 저장 필수다. 그래서 접힌 상태에서도 헤더 요약으로 값을 알 수 있고,
// 그 안에서 검증이 실패하면 먼저 펼친 뒤 스크롤해야 한다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/business_work_type_model.dart';
import 'package:ALfit/widgets/pickers/create_edit_work_detail_dialog.dart';

const _dialogPath = 'lib/widgets/pickers/create_edit_work_detail_dialog.dart';

String _source(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
  return f.readAsStringSync();
}

List<BusinessWorkTypeModel> _workTypes() => [
      BusinessWorkTypeModel(
        id: 'wt1',
        businessId: 'biz1',
        name: '피킹',
        icon: '📦',
        displayOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];

/// 업무 추가 다이얼로그를 띄우고 첫 프레임까지 진행한다.
///
/// 기본 테스트 뷰포트(800×600)는 이 다이얼로그를 잘라내 하단 섹션이
/// 빌드되지 않는다. 위계 전체를 한 번에 보려면 세로를 충분히 키워야 한다.
Future<void> _openAddDialog(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => WorkDetailDialog.showAddDialog(
              context: ctx,
              businessWorkTypes: _workTypes(),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

void main() {
  // ── 위계 구조 ───────────────────────────────────────────────────
  group('WDH-0x 세 묶음으로 나뉜다', () {
    testWidgets('WDH-01 ①②③ 제목이 모두 보인다', (tester) async {
      await _openAddDialog(tester);
      expect(find.text('핵심 모집조건'), findsOneWidget);
      expect(find.text('추가 근무조건'), findsOneWidget);
      expect(find.text('급여·정산 설정'), findsOneWidget);
    });

    testWidgets('WDH-02 ①②는 접히지 않고 내용이 바로 보인다', (tester) async {
      await _openAddDialog(tester);
      // ① 핵심: 업무 유형 / 급여 타입 / 모집 인원 / 근무 시간
      expect(find.text('업무 유형'), findsOneWidget);
      expect(find.text('급여 타입'), findsOneWidget);
      expect(find.text('근무 시간'), findsOneWidget);
      // ② 근무조건: 근무 시간대 섹션이 바로 보인다
      expect(find.text('야간수당 설정'), findsOneWidget);
    });

    testWidgets('WDH-03 ③ 내용은 처음에 접혀 있다', (tester) async {
      await _openAddDialog(tester);
      // 헤더는 보이되 내부 섹션은 빌드되지 않는다
      expect(find.text('급여·정산 설정'), findsOneWidget);
      expect(find.text('공제 방식'), findsNothing);
      expect(find.text('급여 지급 일정'), findsNothing);
    });

    testWidgets('WDH-04 헤더를 누르면 ③이 펼쳐진다', (tester) async {
      await _openAddDialog(tester);
      await tester.tap(find.text('급여·정산 설정'));
      await tester.pumpAndSettle();
      expect(find.text('공제 방식'), findsOneWidget);
      expect(find.text('급여 지급 일정'), findsOneWidget);
    });

    testWidgets('WDH-05 다시 누르면 접힌다', (tester) async {
      await _openAddDialog(tester);
      await tester.tap(find.text('급여·정산 설정'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('급여·정산 설정'));
      await tester.pumpAndSettle();
      expect(find.text('공제 방식'), findsNothing);
    });
  });

  // ── 헤더 요약 ───────────────────────────────────────────────────
  group('WDH-1x 접힌 상태에서도 값을 알 수 있다', () {
    testWidgets('WDH-10 신규 작성 시 현재 값이 요약으로 보인다', (tester) async {
      await _openAddDialog(tester);
      // default: 공제 없음 + 지급 일정 미설정
      expect(find.text('세금 없음 · 지급 일정 미설정'), findsOneWidget);
    });

    testWidgets('WDH-11 값이 바뀌면 요약도 바뀐다', (tester) async {
      await _openAddDialog(tester);
      await tester.tap(find.text('급여·정산 설정'));
      await tester.pumpAndSettle();
      // 공제 방식을 3.3% 원천징수로 변경
      final option = find.text('3.3% 원천징수');
      expect(option, findsWidgets);
      await tester.tap(option.first);
      await tester.pumpAndSettle();
      // 접어도 요약에 반영돼 있다
      await tester.tap(find.text('급여·정산 설정'));
      await tester.pumpAndSettle();
      expect(find.textContaining('3.3% 원천징수'), findsOneWidget);
    });
  });

  // ── 기초 시급 배치 ──────────────────────────────────────────────
  group('WDH-2x 기초 시급은 급여의 종속값', () {
    test('WDH-20 급여 바로 뒤, 모집 인원 앞에 온다', () {
      final s = _source(_dialogPath);
      final wage = s.indexOf('// ③ 급여 금액');
      final base = s.indexOf('// 기초 시급');
      final count = s.indexOf('// ④ 필요 인원');
      expect(wage, greaterThan(-1));
      expect(base, greaterThan(wage), reason: '기초 시급이 급여보다 앞에 있다');
      expect(count, greaterThan(base), reason: '기초 시급이 ① 밖으로 밀려났다');
    });

    test('WDH-21 ③(정산)으로 옮겨지지 않았다', () {
      final s = _source(_dialogPath);
      final base = s.indexOf('// 기초 시급');
      final settlement = s.indexOf('═══ ③ 급여·정산 설정 ═══');
      expect(settlement, greaterThan(base),
          reason: '기초 시급이 정산 묶음 안으로 들어갔다');
    });

    test('WDH-22 일급 조건부 노출이 그대로다', () {
      final s = _source(_dialogPath);
      final base = s.indexOf('// 기초 시급');
      final block = s.substring(base, base + 300);
      expect(block.contains("if (_selectedWageType == 'daily')"), true,
          reason: '기초 시급 노출 조건이 바뀌었다');
    });

    testWidgets('WDH-23 시급 선택 시에는 보이지 않는다', (tester) async {
      await _openAddDialog(tester);
      // default는 시급 — 기초 시급 섹션이 없어야 한다
      expect(find.textContaining('통상시급'), findsNothing);
    });
  });

  // ── 검증 접근성 (③이 접혀도 오류를 찾을 수 있어야) ──────────────
  group('WDH-3x 접힌 섹션의 검증 오류', () {
    late final String s = _source(_dialogPath);

    test('WDH-30 급여 지급 일정은 저장 필수다', () {
      // 이 사실이 ③ 접힘 설계의 전제다 — 선택 항목이 아니다.
      expect(s.contains("ToastHelper.showError('급여 지급 일정을 선택해주세요')"), true);
    });

    test('WDH-31 ③ 내부 오류는 먼저 펼친 뒤 스크롤한다', () {
      final i = s.indexOf('void _scrollToFirstError(GlobalKey key) {');
      expect(i, greaterThan(-1));
      final body = s.substring(i, i + 900);
      expect(body.contains('key == _keyDeduction || key == _keyPaySchedule'), true);
      expect(body.contains('_settlementExpanded = true'), true);
      expect(body.contains('addPostFrameCallback'), true,
          reason: '펼침 직후 같은 프레임에 스크롤하면 context가 아직 없다');
    });

    test('WDH-32 펼친 뒤 mounted를 확인한다', () {
      final i = s.indexOf('void _scrollToFirstError(GlobalKey key) {');
      final body = s.substring(i, i + 900);
      expect(body.contains('if (mounted) _ensureVisible(key);'), true);
    });
  });

  // ── 편집 모드 ───────────────────────────────────────────────────
  group('WDH-4x 편집 모드', () {
    late final String s = _source(_dialogPath);

    test('WDH-40 값 존재만으로 자동 펼침하지 않는다', () {
      // 공제 없음 / 지급 일정 미설정도 값이므로
      // has value != user configured. initState에서 펼침을 켜지 않는다.
      final i = s.indexOf('void initState() {');
      final body = s.substring(i, s.indexOf('\n  }', i));
      expect(body.contains('_settlementExpanded'), false,
          reason: '편집 진입 시 값 유무로 자동 펼침하고 있다');
    });

    test('WDH-41 기본값은 접힘이다', () {
      expect(s.contains('bool _settlementExpanded = false;'), true);
    });
  });

  // ── 범위 불변식 ─────────────────────────────────────────────────
  group('WDH-5x 이번 변경 범위 밖', () {
    late final String s = _source(_dialogPath);

    test('WDH-50 isValid 무변경', () {
      final m = _source('lib/models/work_detail_input.dart');
      expect(
          m.contains('bool get isValid =>\n'
                  '      workType != null &&\n'
                  '      wage != null &&\n'
                  '      requiredCount != null &&\n'
                  '      startTime != null &&\n'
                  '      endTime != null;') ||
              m.replaceAll('\r\n', '\n').contains('bool get isValid =>\n'
                  '      workType != null &&\n'
                  '      wage != null &&\n'
                  '      requiredCount != null &&\n'
                  '      startTime != null &&\n'
                  '      endTime != null;'),
          true,
          reason: 'WorkDetailInput.isValid가 변경됐다');
    });

    test('WDH-51 경고 3종 무변경', () {
      for (final w in const [
        '모집인원 축소 경고',
        '최저임금 미달 경고',
        '통상시급 최저임금 미달 경고',
      ]) {
        expect(s.contains(w), true, reason: '"$w" 가 사라졌다');
      }
    });

    test('WDH-52 업무 유형 잠금·야간 semantics 무변경', () {
      expect(s.contains('4H.0B-IDENTITY-LOCK'), true);
      expect(s.contains('_clearBaseHourlyIfStale'), true);
      expect(s.contains("if (type != 'daily')"), true);
    });

    test('WDH-53 업무 설명은 V1 비노출 상태 그대로다', () {
      // 정보 위계 변경이 숨겨진 입력을 되살리는 계기가 되면 안 된다.
      expect(s.contains('업무 설명 — V1 비노출'), true);
      expect(s.contains('_buildDescriptionField('), true,
          reason: '빌더는 남아 있어야 한다 (v2 복원 대상)');
      final bodyStart = s.indexOf('body: ListView(');
      final bodyEnd = s.indexOf('),   // Scaffold', bodyStart);
      final body = s.substring(bodyStart, bodyEnd);
      expect(body.contains('_buildDescriptionField('), false,
          reason: '숨겨져 있던 업무 설명 입력이 노출됐다');
    });

    test('WDH-54 새 화면/wizard를 만들지 않았다', () {
      for (final banned in const ['PageView', 'Stepper', 'currentStep']) {
        expect(s.contains(banned), false, reason: '$banned 가 추가됐다');
      }
    });
  });
}
