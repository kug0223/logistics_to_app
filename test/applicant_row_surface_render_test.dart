// [R7-P1-2 DEVICE.1H.1] 실제 사람 행 표면을 **그려서** 확인한다.
//
//   DEVICE.1H 는 확정 카드의 전체 tint 를 테두리로 낮췄지만 그 변경을 렌더한
//   적이 없었다. 카드 builder 가 Firebase 의존 State 안의 private 메서드였고,
//   "Firebase 의존이라 못 한다" 는 정직한 한계 설명이었을 뿐 요구 완료가 아니었다.
//
//   그래서 표면만 떼어 냈다 — `ApplicantRowSurface` + `dayApplicantRowColors`.
//   **production 두 화면이 그 위젯을 쓴다**(day/work 모두). 도메인(권한·capacity·
//   상태 분류)은 다이얼로그에 그대로 남아 있고, 색 규칙도 화면마다 따로다 —
//   두 카드의 다른 의미를 강제로 합치지 않았다.
//
//   ── 이 테스트가 증명하는 것 ─────────────────────────────────────
//     · production 표면 위젯(`ApplicantRowSurface`)의 실제 렌더
//     · production 배지(`IdCardHelper.buildStatusBadge`)의 실제 렌더
//     · 확정 행에 배경 tint 가 없고 테두리만 남았다는 사실
//     · 좁은 폭 + 글자 2.0 에서 겹침·잘림·overflow 없음, 버튼 접근 가능
//     · **실제 부모 제약**(모달 shell + 스크롤) 안에서의 동작
//
//   ── 증명하지 않는 것 ───────────────────────────────────────────
//     · 권한 게이팅, capacity 계산, 어떤 action 이 뜰지 결정하는 규칙
//     · 실기기 대비·터치영역 수치 (→ P4)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/utils/id_card_helper.dart';
import 'package:ALfit/widgets/admin/applicant_row_surface.dart';
import 'package:ALfit/widgets/dialogs/styled_dialog.dart';

/// 실제 행에 있는 요소들. 문자열은 production formatter 가 만드는 모양이다
/// (`지원 4일 전` = DEVICE.1H, `계약 종료` = DEVICE.1E.1).
Widget _rowContent({
  required String name,
  required bool confirmed,
  required bool ended,
  required List<String> badges,
  required String idCardStatus,
  required String appliedLabel,
  List<Widget> actions = const [],
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // ① 사람 식별 — production 과 같은 구조.
      //   지원 시각 칸은 `Flexible` 이다(DEVICE.1H.1). 맨 `Text` 로 두면
      //   큰 글자에서 이 Row 가 overflow 한다 — 실제 렌더로 확인한 결함이다.
      Row(children: [
        Expanded(
          child: Text('$name · 010-0000-0000',
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Flexible(
          child: Text(appliedLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.grey500)),
        ),
      ]),
      const SizedBox(height: 3),
      // ② 의사결정에 필요한 상태 — production 배지 포함
      Wrap(
        spacing: 4,
        runSpacing: 3,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final b in badges)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.grey500),
              ),
              child: Text(b, style: const TextStyle(fontSize: 10)),
            ),
          // production 위젯
          Builder(
              builder: (c) => IdCardHelper.buildStatusBadge(c, idCardStatus)),
        ],
      ),
      // ③ 수행 가능한 행동
      if (actions.isNotEmpty) ...[
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: actions),
        ),
      ],
    ],
  );
}

/// [R7-P1-2 DEVICE.1H.1] **실제 렌더 표면**을 그 크기로 만든다.
///
///   `MediaQuery` 만 덮으면 위젯이 *믿는* 크기만 바뀌고 실제 캔버스는
///   기본 800x600 이라 좁은 폭이 강제되지 않는다. 그 상태에서는 320dp 에서
///   버튼이 오른쪽으로 밀려도 테스트가 통과한다 — 처음 작성한 harness 가
///   그랬고, `right=583 > 320` 으로 드러났다.
///
///   그래서 `tester.view` 로 물리 표면을 바꾼다. 글자 배율도 view 쪽에 준다.
void _setSurface(WidgetTester tester, Size size, double textScale) {
  tester.view
    ..devicePixelRatio = 1.0
    ..physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// 실제 부모 제약: 모달 shell + 스크롤. 단독 위젯을 넓은 화면에 띄우는 것으로
/// 대체하지 않는다.
Widget _harness({
  required Size size,
  required double textScale,
  required List<Widget> rows,
  EdgeInsets padding = EdgeInsets.zero,
  double keyboard = 0,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
        padding: padding,
        viewInsets: EdgeInsets.only(bottom: keyboard),
      ),
      child: AppModalShell(children: [
        const AppModalHeader(
            title: '사무업무 · 인력 현황',
            subtitle: '2026년 9월 28일 월요일 · 공고 2개 · 업무 3개'),
        Flexible(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: rows),
            ),
          ),
        ),
        const SizedBox(height: 56, child: Center(child: Text('닫기'))),
      ]),
    ),
  );
}

/// 확정 행 — DEVICE.1H 가 tint 를 내린 그 행.
Widget _confirmedRow({String name = '가나다라마바사아자차카타파하영업(W-014)'}) {
  final c = dayApplicantRowColors(
    isSelected: false,
    isStarred: false,
    isPending: false,
    selectedBg: AppColors.warningBg,
    selectedBorder: AppColors.warning,
    starredBg: AppColors.amber.withValues(alpha: 0.1),
    starredBorder: AppColors.amberLight,
    confirmedBorder: AppColors.successLight.withValues(alpha: 0.7),
    plainBorder: AppColors.grey200,
  );
  return ApplicantRowSurface(
    background: c.background,
    border: c.border,
    borderWidth: c.width,
    onTap: () {},
    child: _rowContent(
      name: name,
      confirmed: true,
      ended: false,
      badges: const ['최근 90일 노쇼 7회', '계약서 작성 필요', '주3회'],
      idCardStatus: 'none',
      appliedLabel: '지원 4일 전',
      actions: [
        OutlinedButton(onPressed: () {}, child: const Text('계약서 작성')),
        OutlinedButton(onPressed: () {}, child: const Text('고정근무 관리')),
      ],
    ),
  );
}

/// 종료(기록) 행 — 행동 없음, 낮은 강조.
Widget _endedRow() {
  final c = dayApplicantRowColors(
    isSelected: false,
    isStarred: false,
    isPending: false,
    selectedBg: AppColors.warningBg,
    selectedBorder: AppColors.warning,
    starredBg: AppColors.amber.withValues(alpha: 0.1),
    starredBorder: AppColors.amberLight,
    confirmedBorder: AppColors.successLight.withValues(alpha: 0.7),
    plainBorder: AppColors.grey200,
  );
  return ApplicantRowSurface(
    background: c.background,
    border: c.border,
    borderWidth: c.width,
    child: _rowContent(
      name: '박서준(W-002)',
      confirmed: false,
      ended: true,
      badges: const ['계약 종료', '계약서 미작성', '주0회'],
      idCardStatus: 'approved',
      appliedLabel: '지원 09/15 09:00',
    ),
  );
}

/// 대기 행 — 선택 가능.
Widget _pendingRow({bool selected = false}) {
  final c = dayApplicantRowColors(
    isSelected: selected,
    isStarred: false,
    isPending: true,
    selectedBg: AppColors.warningBg,
    selectedBorder: AppColors.warning,
    starredBg: AppColors.amber.withValues(alpha: 0.1),
    starredBorder: AppColors.amberLight,
    confirmedBorder: AppColors.successLight.withValues(alpha: 0.7),
    plainBorder: AppColors.grey200,
  );
  return ApplicantRowSurface(
    background: c.background,
    border: c.border,
    borderWidth: c.width,
    onTap: () {},
    child: _rowContent(
      name: '이수민(W-003)',
      confirmed: false,
      ended: false,
      badges: const ['주1회'],
      idCardStatus: 'pending',
      appliedLabel: '지원 2시간 전',
      actions: [
        OutlinedButton(onPressed: () {}, child: const Text('거절')),
        FilledButton(onPressed: () {}, child: const Text('확정')),
      ],
    ),
  );
}

void main() {
  // ══════════════════════════════════════════════════════════════
  // A. 색 규칙 — DEVICE.1H 가 바꾼 한 줄
  // ══════════════════════════════════════════════════════════════

  group('ARS-A 강조 규칙', () {
    ApplicantRowColors colors(
            {bool sel = false, bool star = false, bool pending = true}) =>
        dayApplicantRowColors(
          isSelected: sel,
          isStarred: star,
          isPending: pending,
          selectedBg: AppColors.warningBg,
          selectedBorder: AppColors.warning,
          starredBg: AppColors.amber.withValues(alpha: 0.1),
          starredBorder: AppColors.amberLight,
          confirmedBorder: AppColors.successLight.withValues(alpha: 0.7),
          plainBorder: AppColors.grey200,
        );

    test('ARS-A1 확정 행에 배경 tint 가 없다', () {
      final c = colors(pending: false);
      expect(c.background, Colors.white,
          reason: '전체 초록 tint 를 테두리로 낮췄다 (D0: 완료 정보 낮은 강조)');
      expect(c.border, isNot(AppColors.grey200), reason: '테두리로는 구분된다');
    });

    test('ARS-A2 선택은 여전히 강하다 — 강조를 전부 없앤 것이 아니다', () {
      final c = colors(sel: true);
      expect(c.background, AppColors.warningBg);
      expect(c.width, 1.5);
    });

    test('ARS-A3 선택이 확정보다 우선한다', () {
      expect(colors(sel: true, pending: false).background, AppColors.warningBg);
    });

    test('ARS-A4 대기 행은 평범하다', () {
      final c = colors();
      expect(c.background, Colors.white);
      expect(c.border, AppColors.grey200);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // B. 실제 렌더 — 좁은 폭 + 큰 글자 중심
  // ══════════════════════════════════════════════════════════════

  group('ARS-B 실제 사람 행 렌더', () {
    /// (폭, 높이, 글자배율)
    const cases = [
      (320.0, 640.0, 2.0), // 좁은 지원 폭 + 최대 배율 — 가장 가혹
      (320.0, 640.0, 1.0),
      (360.0, 740.0, 1.0), // 일반 기본
      (360.0, 740.0, 1.3), // 일반 확대
      (412.0, 892.0, 2.0),
    ];

    for (final (w, h, s) in cases) {
      testWidgets('ARS-B ${w.toInt()}x${h.toInt()} scale$s — 혼합 행',
          (tester) async {
        _setSurface(tester, Size(w, h), s);
        await tester.pumpWidget(_harness(
          size: Size(w, h),
          textScale: s,
          rows: [
            _confirmedRow(),
            _endedRow(),
            _pendingRow(),
            _pendingRow(selected: true),
          ],
        ));
        await tester.pump();

        expect(tester.takeException(), isNull,
            reason: 'overflow/clipping 발생');

        // 표면이 실제로 그려졌다.
        expect(find.byType(ApplicantRowSurface), findsNWidgets(4));

        // 필수 상태 글자가 살아 있다 — 색에만 의존하지 않는다.
        expect(find.text('계약 종료'), findsOneWidget);
        expect(find.text('최근 90일 노쇼 7회'), findsOneWidget);

        // 행동 버튼이 화면 폭 안에 있고 눌릴 수 있다.
        for (final label in ['계약서 작성', '확정', '거절']) {
          final f = find.text(label);
          expect(f, findsWidgets, reason: '$label 이 사라졌다');
          final r = tester.getRect(f.first);
          expect(r.left, greaterThanOrEqualTo(-0.5),
              reason: '$label 이 왼쪽으로 잘렸다 (left=${r.left})');
          expect(r.right, lessThanOrEqualTo(w + 0.5),
              reason: '$label 이 행 밖으로 밀렸다 (right=${r.right}, 폭 $w)');
        }

        // 닫기 접근 가능.
        final close = tester.getRect(find.text('닫기'));
        expect(close.bottom, lessThanOrEqualTo(h + 0.5));

        // 스크롤로 마지막 행까지 닿는다.
        expect(find.byType(Scrollable), findsWidgets);
      });
    }

    testWidgets('ARS-B-LONG 아주 긴 이름이 행을 밀어내지 않는다', (tester) async {
      _setSurface(tester, const Size(320, 640), 2.0);
      await tester.pumpWidget(_harness(
        size: const Size(320, 640),
        textScale: 2.0,
        rows: [
          _confirmedRow(
              name: '가나다라마바사아자차카타파하가나다라마바사아자차카타파하(W-999)'),
        ],
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // 이름은 ellipsis 로 줄어도 배지·행동은 남아야 한다.
      expect(find.text('계약서 작성'), findsOneWidget);
      expect(find.text('최근 90일 노쇼 7회'), findsOneWidget);
      final r = tester.getRect(find.text('계약서 작성'));
      expect(r.right, lessThanOrEqualTo(320.5));
    });

    testWidgets('ARS-B-MANY 행이 많아도 마지막 행과 닫기에 닿는다', (tester) async {
      _setSurface(tester, const Size(360, 740), 1.3);
      await tester.pumpWidget(_harness(
        size: const Size(360, 740),
        textScale: 1.3,
        rows: [for (var i = 0; i < 12; i++) _confirmedRow(name: '근무자$i(W-0$i)')],
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('닫기'), findsOneWidget);
      // 마지막 행까지 스크롤해서 닿는다.
      await tester.scrollUntilVisible(find.text('근무자11(W-011) · 010-0000-0000'),
          200, scrollable: find.byType(Scrollable).first);
      expect(find.text('근무자11(W-011) · 010-0000-0000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ARS-B-KB 키보드가 올라와도 닫기에 닿는다', (tester) async {
      _setSurface(tester, const Size(360, 740), 1.0);
      await tester.pumpWidget(_harness(
        size: const Size(360, 740),
        textScale: 1.0,
        rows: [for (var i = 0; i < 8; i++) _confirmedRow(name: '근무자$i')],
        keyboard: 300,
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final r = tester.getRect(find.text('닫기'));
      expect(r.bottom, lessThanOrEqualTo(740 - 300 + 0.5));
    });

    testWidgets('ARS-B-SA safe area 에서도 잘리지 않는다', (tester) async {
      _setSurface(tester, const Size(390, 844), 1.3);
      await tester.pumpWidget(_harness(
        size: const Size(390, 844),
        textScale: 1.3,
        rows: [_confirmedRow(), _endedRow(), _pendingRow()],
        padding: const EdgeInsets.only(top: 47, bottom: 34),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('닫기'), findsOneWidget);
    });

    testWidgets('ARS-B-ENDED 종료 행에는 행동 버튼이 없다', (tester) async {
      _setSurface(tester, const Size(360, 740), 1.0);
      await tester.pumpWidget(_harness(
        size: const Size(360, 740),
        textScale: 1.0,
        rows: [_endedRow()],
      ));
      await tester.pump();
      expect(find.text('계약 종료'), findsOneWidget);
      expect(find.text('계약서 작성'), findsNothing,
          reason: '끝난 관계에 새 계약을 요구하지 않는다 (DEVICE.1E)');
      expect(find.byType(OutlinedButton), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // C. production 연결 (보조 증거)
  // ══════════════════════════════════════════════════════════════

  group('ARS-C production 사용', () {
    test('ARS-C1 두 화면이 이 표면 위젯을 쓴다', () {
      for (final p in const [
        'lib/screens/business_admin/dialogs/day_applicants_dialog.dart',
        'lib/screens/business_admin/dialogs/work_applicants_dialog.dart',
      ]) {
        final src = File(p).readAsStringSync();
        expect(src.contains('ApplicantRowSurface('), isTrue, reason: p);
      }
    });

    test('ARS-C2 홈 일자별이 추출한 색 규칙을 쓴다', () {
      final src = File(
              'lib/screens/business_admin/dialogs/day_applicants_dialog.dart')
          .readAsStringSync();
      expect(src.contains('dayApplicantRowColors('), isTrue);
      // 인라인 데코레이션 복사본이 남아 있지 않다.
      expect(src.contains('border: Border.all(color: cardBorder'), isFalse);
    });
  });
}
