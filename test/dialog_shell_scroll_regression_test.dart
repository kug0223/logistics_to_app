// [R7-PREDEVICE-DISCLOSURE-RENDER.1A] 공용 다이얼로그 셸 — 회귀.
//
// ── 무엇을 바꿨고 왜 확인하는가 ─────────────────────────────────────
//   `.1` 에서 `DialogHelper._buildDialog` 의 본문을
//   `Flexible(child: SingleChildScrollView(...))` 로 감쌌다. 초대 수락
//   확인창의 근태·급여 고지가 바닥으로 78~3,347px 넘쳤기 때문이다.
//
//   그 셸은 **6개 helper** 가 공유한다. 스크롤 주인을 새로 만든 변경이라
//   다음이 깨질 수 있다:
//     · 짧은 내용이 괜히 늘어나거나 줄어든다
//     · 입력 다이얼로그에서 키보드가 올라올 때 스크롤이 두 겹이 된다
//     · 내용 자체가 스크롤이면 주인이 둘이 되어 터진다
//     · 버튼이 스크롤 안으로 들어가 닿지 못한다
//     · 닫기가 값을 잘못 돌려준다
//
//   그래서 helper 별로 **대표 사용처와 같은 모양**으로 실제 열고 눌러 본다.
//   104개 호출부를 기계적으로 다시 돌리지 않는다.
//
// ── 실제 호출부 분포 (측정) ────────────────────────────────────────
//   showConfirm 74 · showAlert 7 · showCustom 7 · showTextInput 7
//   showOptions 0 · showDocumentRequired 0   ← production 소비자 없음
//   뒤의 둘은 공개 API 이고 같은 셸을 쓰므로 직접 열어 확인한다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/utils/dialog_helper.dart';

const _widths = <double>[320, 360, 411];
const _scales = <double>[1.0, 1.3, 2.0];

/// 긴 한국어 본문 — 대표 사용처의 가장 긴 문구보다 길게 만든다.
const _longMessage =
    '이 작업은 되돌릴 수 없습니다. 확정된 근무와 연결된 급여 기록, 근태 기록, '
    '계약서 보관본이 함께 정리되며 근로자에게 알림이 발송됩니다. '
    '정리 이후에는 같은 조건으로 다시 만들 수 없고, 필요한 경우 새 공고를 '
    '등록해 처음부터 다시 진행해야 합니다. 계속하시겠습니까?';

/// 다이얼로그를 띄울 호스트. [insetBottom] 이 키보드 높이다.
Future<BuildContext> _host(
  WidgetTester t, {
  required Size size,
  required double textScale,
  double insetBottom = 0,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  late BuildContext ctx;
  await t.pumpWidget(
    MaterialApp(
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: insetBottom),
        ),
        child: child!,
      ),
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox.expand());
      }),
    ),
  );
  return ctx;
}

Future<void> _settle(WidgetTester t, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// 화면에 그려진 Text 전부.
String _visible(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .where((s) => s.isNotEmpty)
    .join('\n');

/// 버튼이 **눌릴 수 있는 상태로** 트리에 있는가.
void expectTappable(WidgetTester t, String label, String where) {
  final f = find.text(label);
  expect(f, findsWidgets, reason: '$where — "$label" 버튼이 없다');
  // 버튼이 화면 밖으로 밀려나지 않았다 — 스크롤 밖 고정 영역이어야 한다.
  final box = t.renderObject<RenderBox>(f.first);
  final pos = box.localToGlobal(Offset.zero);
  final screen = t.view.physicalSize / t.view.devicePixelRatio;
  expect(pos.dy, lessThan(screen.height),
      reason: '$where — "$label" 이 화면 아래로 밀려났다 (y=${pos.dy})');
  expect(pos.dy + box.size.height, greaterThan(0),
      reason: '$where — "$label" 이 화면 위로 밀려났다');
}

void main() {
  // ═══════════════════════════════════════════════════════════
  // 1. showConfirm — 74곳. 대표: 사업장 삭제·계약 가져오기 확인
  // ═══════════════════════════════════════════════════════════
  group('[H1] showConfirm', () {
    testWidgets('H1-1 긴 본문에서 확인·취소가 모두 닿는다', (t) async {
      final ctx = await _host(t,
          size: const Size(320, 760), textScale: 2.0);
      bool? result;
      DialogHelper.showConfirm(ctx,
              title: '사업장 삭제',
              message: _longMessage,
              confirmText: '삭제',
              icon: Icons.delete_outline,
              iconColor: AppColors.error)
          .then((v) => result = v);
      await _settle(t);

      expect(t.takeException(), isNull, reason: '320dp × 2.0 에서 넘친다');
      expect(_visible(t).contains('사업장 삭제'), isTrue);
      expectTappable(t, '삭제', 'showConfirm 320×2.0');
      expectTappable(t, '취소', 'showConfirm 320×2.0');

      // 닫기 동작 — 취소는 false 를 돌려준다.
      await t.tap(find.text('취소'));
      await _settle(t);
      expect(result, isFalse, reason: '취소가 false 를 돌려주지 않는다');
    });

    testWidgets('H1-2 확인은 true 를 돌려준다', (t) async {
      final ctx = await _host(t, size: const Size(360, 780), textScale: 1.0);
      bool? result;
      DialogHelper.showConfirm(ctx, title: '확정', message: '진행할까요?')
          .then((v) => result = v);
      await _settle(t);
      await t.tap(find.text('확인'));
      await _settle(t);
      expect(result, isTrue);
    });

    testWidgets('H1-3 짧은 본문은 세로로 늘어나지 않는다 — 내용 크기로 접힌다',
        (t) async {
      // 스크롤 주인을 넣은 변경이 짧은 다이얼로그를 키우지 않았는지 본다.
      final ctx = await _host(t, size: const Size(360, 780), textScale: 1.0);
      DialogHelper.showConfirm(ctx, title: '확인', message: '진행할까요?');
      await _settle(t);
      // `Dialog` 의 RenderBox 는 전체 화면이다(배리어·센터링 포함) —
      //   실제 카드는 그 안의 `ConstrainedBox(maxWidth: 380)` 다.
      final card = t.renderObject<RenderBox>(find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(ConstrainedBox),
          )
          .first);
      expect(card.size.height, lessThan(780 * 0.5),
          reason: '짧은 확인창이 ${card.size.height}px 로 늘어났다');
    });

    for (final w in _widths) {
      for (final s in _scales) {
        testWidgets('H1-4 ${w.toInt()}dp × 배율 $s — 넘침 0', (t) async {
          final ctx = await _host(t, size: Size(w, 760), textScale: s);
          DialogHelper.showConfirm(ctx,
              title: '사업장 삭제', message: _longMessage, confirmText: '삭제');
          await _settle(t);
          expect(t.takeException(), isNull);
          expectTappable(t, '삭제', '${w.toInt()}dp × $s');
        });
      }
    }
  });

  // ═══════════════════════════════════════════════════════════
  // 2. showAlert — 7곳. 대표: 급여 확정 다이얼로그의 안내
  // ═══════════════════════════════════════════════════════════
  group('[H2] showAlert', () {
    testWidgets('H2-1 긴 안내에서 확인 버튼이 닿고 닫힌다', (t) async {
      final ctx = await _host(t, size: const Size(320, 760), textScale: 2.0);
      var closed = false;
      DialogHelper.showAlert(ctx, title: '급여 확정 안내', message: _longMessage)
          .then((_) => closed = true);
      await _settle(t);

      expect(t.takeException(), isNull);
      expectTappable(t, '확인', 'showAlert 320×2.0');
      await t.tap(find.text('확인'));
      await _settle(t);
      expect(closed, isTrue, reason: '확인이 다이얼로그를 닫지 않는다');
    });

    for (final w in _widths) {
      for (final s in _scales) {
        testWidgets('H2-2 ${w.toInt()}dp × 배율 $s — 넘침 0', (t) async {
          final ctx = await _host(t, size: Size(w, 760), textScale: s);
          DialogHelper.showAlert(ctx, title: '안내', message: _longMessage);
          await _settle(t);
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  // ═══════════════════════════════════════════════════════════
  // 3. showOptions — production 소비자 **0**. 공개 API 로 직접 확인
  // ═══════════════════════════════════════════════════════════
  group('[H3] showOptions (호출부 0 — API 직접 검증)', () {
    testWidgets('H3-1 항목이 많아도 넘치지 않고 선택이 전달된다', (t) async {
      final ctx = await _host(t, size: const Size(320, 760), textScale: 2.0);
      String? picked;
      DialogHelper.showOptions<String>(
        ctx,
        title: '처리 사유 선택',
        options: [for (var i = 1; i <= 12; i++) '사유 $i — 근태 기록 정정 요청'],
      ).then((v) => picked = v);
      await _settle(t);

      expect(t.takeException(), isNull, reason: '12개 항목이 넘친다');
      // 스크롤 안에서 첫 항목에 닿아 고를 수 있다.
      final first = find.text('사유 1 — 근태 기록 정정 요청');
      expect(first, findsOneWidget);
      await t.ensureVisible(first);
      await t.pump();
      await t.tap(first);
      await _settle(t);
      expect(picked, '사유 1 — 근태 기록 정정 요청');
    });

    testWidgets('H3-2 스크롤로 마지막 항목까지 닿는다', (t) async {
      final ctx = await _host(t, size: const Size(320, 700), textScale: 2.0);
      String? picked;
      DialogHelper.showOptions<String>(
        ctx,
        title: '사유',
        options: [for (var i = 1; i <= 12; i++) '사유 $i'],
      ).then((v) => picked = v);
      await _settle(t);

      final last = find.text('사유 12');
      expect(last, findsOneWidget, reason: '마지막 항목이 트리에 없다');
      await t.ensureVisible(last);
      await t.pump();
      await t.tap(last);
      await _settle(t);
      expect(picked, '사유 12', reason: '스크롤 끝 항목을 고를 수 없다');
      expect(t.takeException(), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 4. showCustom — 7곳. 대표: 내 지원 수락 확인창 · 공고 상세 확인
  //    여기서 **중첩 스크롤**(내용 자체가 스크롤)을 본다.
  // ═══════════════════════════════════════════════════════════
  group('[H4] showCustom', () {
    testWidgets('H4-1 내용이 스크롤을 가져도 주인이 충돌하지 않는다', (t) async {
      // 셸이 스크롤을 주는데 내용도 스크롤이면 높이가 unbounded 가 되어
      //   터질 수 있다. 실제 호출부에 그런 모양이 있을 수 있으므로 본다.
      final ctx = await _host(t, size: const Size(360, 700), textScale: 1.0);
      DialogHelper.showCustom<void>(
        ctx,
        title: '근태 기준 비교',
        content: SizedBox(
          height: 200,
          child: ListView(
            children: [
              for (var i = 1; i <= 30; i++) Text('내부 항목 $i'),
            ],
          ),
        ),
        actions: const [SizedBox.shrink()],
      );
      await _settle(t);
      expect(t.takeException(), isNull,
          reason: '내용 스크롤과 셸 스크롤이 충돌한다');
      expect(find.text('내부 항목 1'), findsOneWidget);
    });

    testWidgets('H4-2 제목 없는 변형(AlertDialog 경로)은 영향받지 않았다',
        (t) async {
      // title 이 null 이면 `_buildDialog` 를 타지 않는다 — 회귀 범위 밖임을
      //   못 박는다.
      final ctx = await _host(t, size: const Size(360, 700), textScale: 1.0);
      DialogHelper.showCustom<void>(
        ctx,
        content: const Text('제목 없는 커스텀'),
        actions: const [SizedBox.shrink()],
      );
      await _settle(t);
      expect(t.takeException(), isNull);
      expect(find.text('제목 없는 커스텀'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget,
          reason: 'title 없는 경로는 AlertDialog 다');
    });

    testWidgets('H4-3 긴 내용 + 버튼 — 버튼이 스크롤 밖에 고정이다', (t) async {
      final ctx = await _host(t, size: const Size(320, 700), textScale: 2.0);
      var result = false;
      DialogHelper.showCustom<bool>(
        ctx,
        title: '초대 수락',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= 20; i++) Text('고지 줄 $i — $_longMessage'),
          ],
        ),
        actions: [
          Builder(
            builder: (c) => ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('동의하고 수락'),
            ),
          ),
        ],
      ).then((v) => result = v ?? false);
      await _settle(t);

      expect(t.takeException(), isNull, reason: '긴 내용이 넘친다');
      expectTappable(t, '동의하고 수락', 'showCustom 320×2.0');
      await t.tap(find.text('동의하고 수락'));
      await _settle(t);
      expect(result, isTrue, reason: '버튼이 값을 돌려주지 않는다');
    });

    for (final w in _widths) {
      for (final s in _scales) {
        testWidgets('H4-4 ${w.toInt()}dp × 배율 $s — 넘침 0', (t) async {
          final ctx = await _host(t, size: Size(w, 760), textScale: s);
          DialogHelper.showCustom<void>(
            ctx,
            title: '확인',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 1; i <= 10; i++) Text('$i. $_longMessage'),
              ],
            ),
            actions: const [SizedBox.shrink()],
          );
          await _settle(t);
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  // ═══════════════════════════════════════════════════════════
  // 5. showTextInput — 7곳. 대표: 근태 정정 사유 · 미이체 사유
  //    **키보드**가 올라온 상태를 본다 — 가장 위험한 축이다.
  // ═══════════════════════════════════════════════════════════
  group('[H5] showTextInput', () {
    testWidgets('H5-1 키보드 OFF — 입력하고 확인하면 값이 돌아온다', (t) async {
      final ctx = await _host(t, size: const Size(360, 780), textScale: 1.0);
      String? reason;
      DialogHelper.showTextInput(ctx,
              title: '정정 사유', message: '사유를 입력해 주세요', hintText: '예: 기기 오류')
          .then((v) => reason = v);
      await _settle(t);

      expect(t.takeException(), isNull);
      await t.enterText(find.byType(TextField).first, '단말기 오류로 미기록');
      await t.pump();
      expectTappable(t, '확인', 'showTextInput 키보드 OFF');
      await t.tap(find.text('확인'));
      await _settle(t);
      expect(reason, '단말기 오류로 미기록');
    });

    testWidgets('H5-2 키보드 ON · 배율 2.0 — 넘치지 않고 입력란·버튼에 닿는다',
        (t) async {
      final ctx = await _host(t,
          size: const Size(320, 760), textScale: 2.0, insetBottom: 320);
      String? reason;
      DialogHelper.showTextInput(ctx,
              title: '미이체 사유',
              message: _longMessage,
              hintText: '사유',
              maxLines: 3,
              maxLength: 200)
          .then((v) => reason = v);
      await _settle(t);

      expect(t.takeException(), isNull,
          reason: '키보드 ON · 배율 2.0 에서 입력 다이얼로그가 넘친다');
      expect(find.byType(TextField), findsOneWidget);
      await t.enterText(find.byType(TextField).first, '계좌 정보 확인 중');
      await t.pump();
      expectTappable(t, '확인', 'showTextInput 키보드 ON 320×2.0');
      await t.tap(find.text('확인'));
      await _settle(t);
      expect(reason, '계좌 정보 확인 중');
    });

    testWidgets('H5-3 취소는 null 을 돌려준다 — 입력을 저장하지 않는다', (t) async {
      final ctx = await _host(t, size: const Size(360, 780), textScale: 1.0);
      var called = false;
      String? reason;
      DialogHelper.showTextInput(ctx, title: '사유').then((v) {
        called = true;
        reason = v;
      });
      await _settle(t);
      await t.enterText(find.byType(TextField).first, '쓰다가 취소');
      await t.pump();
      await t.tap(find.text('취소'));
      await _settle(t);
      expect(called, isTrue);
      expect(reason, isNull, reason: '취소했는데 입력이 돌아왔다');
    });

    testWidgets('H5-4 validator 가 막으면 닫히지 않는다', (t) async {
      final ctx = await _host(t, size: const Size(360, 780), textScale: 1.0);
      var closed = false;
      DialogHelper.showTextInput(ctx,
              title: '사유', validator: (v) => (v ?? '').trim().length >= 5)
          .then((_) => closed = true);
      await _settle(t);

      await t.enterText(find.byType(TextField).first, '짧음');
      await t.pump();
      await t.tap(find.text('확인'));
      await _settle(t);
      expect(closed, isFalse, reason: '검증 실패인데 닫혔다');
      expect(t.takeException(), isNull);

      // 고쳐 넣으면 닫힌다.
      await t.enterText(find.byType(TextField).first, '충분히 긴 사유');
      await t.pump();
      await t.tap(find.text('확인'));
      await _settle(t);
      expect(closed, isTrue);
    });

    for (final w in _widths) {
      for (final s in _scales) {
        testWidgets('H5-5 ${w.toInt()}dp × 배율 $s — 키보드 ON/OFF 넘침 0',
            (t) async {
          for (final inset in const [0.0, 320.0]) {
            final ctx = await _host(t,
                size: Size(w, 760), textScale: s, insetBottom: inset);
            DialogHelper.showTextInput(ctx,
                title: '사유', message: _longMessage, maxLines: 3);
            await _settle(t);
            expect(t.takeException(), isNull,
                reason: '${w.toInt()}dp × $s · 키보드 '
                    '${inset == 0 ? 'OFF' : 'ON'}');
          }
        });
      }
    }
  });

  // ═══════════════════════════════════════════════════════════
  // 6. showDocumentRequired — production 소비자 **0**. API 직접 검증
  // ═══════════════════════════════════════════════════════════
  group('[H6] showDocumentRequired (호출부 0 — API 직접 검증)', () {
    testWidgets('H6-1 서류가 많아도 넘치지 않고 CTA 가 값을 돌려준다', (t) async {
      final ctx = await _host(t, size: const Size(320, 760), textScale: 2.0);
      bool? go;
      DialogHelper.showDocumentRequired(
        ctx,
        title: '서류 등록이 필요합니다',
        missingDocuments: const [
          '신분증 사본',
          '통장 사본 (급여 계좌와 예금주가 같아야 합니다)',
          '외국인등록증 (해당자)',
          '본인인증 완료',
        ],
      ).then((v) => go = v);
      await _settle(t);

      expect(t.takeException(), isNull);
      final shown = _visible(t);
      for (final d in const ['신분증 사본', '본인인증 완료']) {
        expect(shown.contains(d), isTrue, reason: '"$d" 가 목록에 없다');
      }
      expect(go, isNull, reason: '아직 고르지 않았다');
    });

    for (final w in _widths) {
      for (final s in _scales) {
        testWidgets('H6-2 ${w.toInt()}dp × 배율 $s — 넘침 0', (t) async {
          final ctx = await _host(t, size: Size(w, 760), textScale: s);
          DialogHelper.showDocumentRequired(ctx,
              title: '서류 등록이 필요합니다',
              missingDocuments: const [
                '신분증 사본',
                '통장 사본 (급여 계좌와 예금주가 같아야 합니다)',
                '외국인등록증 (해당자)',
                '본인인증 완료',
              ]);
          await _settle(t);
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  // ═══════════════════════════════════════════════════════════
  // 7. 셸 구조 — 스크롤 주인이 하나이고 버튼은 밖에 있다
  // ═══════════════════════════════════════════════════════════
  group('[H7] 셸 구조', () {
    testWidgets('H7-1 본문만 스크롤하고 헤더·버튼은 고정이다', (t) async {
      final ctx = await _host(t, size: const Size(320, 700), textScale: 2.0);
      DialogHelper.showConfirm(ctx,
          title: '제목은 고정이다',
          message: _longMessage,
          confirmText: '삭제');
      await _settle(t);

      // 셸이 만든 스크롤은 **하나**다.
      final scrolls = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(SingleChildScrollView),
      );
      expect(scrolls, findsOneWidget,
          reason: '셸 안 스크롤 주인이 ${scrolls.evaluate().length}개다');

      // 제목과 버튼은 그 스크롤 **밖**에 있다.
      for (final label in const ['제목은 고정이다', '삭제', '취소']) {
        final inside = find.descendant(
          of: scrolls,
          matching: find.text(label),
        );
        expect(inside, findsNothing,
            reason: '"$label" 이 스크롤 안에 있다 — 길어지면 밀려 사라진다');
      }
    });

    test('H7-2 눌러 담는 우회를 쓰지 않았다', () {
      // 금지어를 주석에도 적지 않는다 — 전역 사용처 집계가 리터럴을 센다.
      final src = File('lib/utils/dialog_helper.dart').readAsStringSync();
      for (final bad in const ['FittedBox', 'Transform.scale']) {
        expect(src.contains(bad), isFalse, reason: '$bad 가 들어 있다');
      }
      // 스크롤 주인을 실제로 넣었다.
      expect(src.contains('Flexible('), isTrue);
      expect(src.contains('SingleChildScrollView('), isTrue);
    });
  });
}
