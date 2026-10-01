// [R7-P4.4E.6A] 계약서 가져오기 — "자동으로 조항을 나누지 못했습니다" 시트의
// 세로 넘침.
//
// E6 에서 가설만 세웠고, 여기서 실측해 확정했다:
//   `DialogHelper.showSheet` 에 `isScrollControlled` 를 주지 않으면 바텀시트
//   최대 높이가 **화면 높이의 9/16** 으로 잠긴다. 이 시트 본문은 ~356px 를
//   요구하므로 화면 높이 640 기기(9/16 = 360)에서 그대로 넘쳤다.
//
//   측정값(패치 전):
//     360×640  maxHeight 360.0  본문 intrinsic 356.0 → 실제 319.6 → 넘침 36px
//     320×640  maxHeight 360.0  본문 intrinsic 370.3 → 실제 321.4 → 넘침 49px
//     360×800  maxHeight 450.0  본문 intrinsic 356.0 → 넘침 없음
//
// 고른 해법은 A(isScrollControlled) + B(본문 스크롤) 둘 다다.
//   A 만 쓰면 배율을 올려 본문이 화면 전체보다 길어지는 순간 다시 넘친다.
//   B 만 쓰면 9/16 안에 갇힌 채로 스크롤하게 되어, 넘치지 않는 기기에서도
//   버튼을 보려고 스크롤해야 한다.
//   둘을 합친 모양은 이 앱의 `ApplyConfirmDialog` 가 이미 쓰는 형태다 —
//   새 패턴을 만든 것이 아니다. 공용 `sheetBottomInset` 은 건드리지 않았다.
//
// 이 테스트가 고정하는 계약:
//   1. 넘침 0.
//   2. 버튼 세 개가 **모두 도달 가능**하다 — 셋 다 CTA 이므로 어느 것도
//      화면 밖에 남겨둘 수 없다. 짧은 화면에서는 스크롤로 도달하면 된다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/screens/business_admin/contract_import_paste_screen.dart';

// 화면 AppBar 의 알림 배지가 NotificationProvider → FirestoreService 를 타므로
// core 플랫폼만 가짜로 세운다. 실제 읽기·쓰기는 하지 않는다.
class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k',
      appId: 'a',
      messagingSenderId: 's',
      projectId: 'p',
      storageBucket: 'b');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp(
          {String? name, FirebaseOptions? options}) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

/// "제N조" 가 없어서 ArticleParser 가 0개를 돌려주는 텍스트 — 실패 시트 경로.
const String kUnparsable = '근로조건은 다음과 같다. 급여는 월말에 지급한다.';

const String kSheetTitle = '자동으로 조항을 나누지 못했습니다.';
const String kCtaWhole = '전체 내용을 하나의 조항으로 가져오기';
const String kCtaClear = '다시 붙여넣기';
const String kCtaBack = '돌아가서 수정하기';

/// 실패 시트를 실제 화면에서 띄운다. production parent 를 그대로 쓴다.
Future<void> _openFailureSheet(
  WidgetTester tester, {
  required double w,
  required double h,
  required double textScale,
  double safeBottom = 48,
}) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<NotificationProvider>(
      create: (_) => NotificationProvider(),
      child: MaterialApp(
        home: Builder(
          builder: (c) => MediaQuery(
            data: MediaQuery.of(c).copyWith(
              textScaler: TextScaler.linear(textScale),
              viewPadding: EdgeInsets.only(bottom: safeBottom),
              padding: EdgeInsets.only(bottom: safeBottom),
            ),
            child: const ContractImportPasteScreen(
              businessId: 'biz1',
              templateType: 'standard',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField).first, kUnparsable);
  await tester.pumpAndSettle();

  await tester.tap(find.byType(ElevatedButton).first);
  await tester.pumpAndSettle();
}

/// 버튼이 지금 보이거나, 스크롤해서 보이게 할 수 있어야 한다.
Future<void> _expectReachable(
  WidgetTester tester,
  String label,
) async {
  final finder = find.text(label);
  expect(finder, findsOneWidget, reason: '$label 버튼이 트리에 없다');
  // 스크롤이 있으면 끌어와서 보이게 한다 — 없어도 에러가 아니다.
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(tester.getSize(finder).height, greaterThan(0),
      reason: '$label 버튼 높이가 0 이다');
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FirebasePlatform.instance = _FakeCore();
  });

  // 넘침이 실제로 났던 짧은 화면 두 칸 + 넘치지 않던 긴 화면 + 배율 상향.
  const cells = <List<double>>[
    [360, 640, 1.0],
    [320, 640, 1.0],
    [360, 800, 1.0],
    [411, 823, 1.0],
    [360, 640, 1.3],
    [360, 800, 1.3],
    [320, 640, 2.0],
    [360, 800, 2.0],
  ];

  for (final c in cells) {
    final w = c[0], h = c[1], s = c[2];
    testWidgets(
        '조항 분리 실패 시트 ${w.toInt()}x${h.toInt()} 배율 $s — 넘침 0 + CTA 도달',
        (tester) async {
      await _openFailureSheet(tester, w: w, h: h, textScale: s);

      expect(find.text(kSheetTitle), findsOneWidget,
          reason: '실패 시트가 뜨지 않았다 — 측정 대상에 도달하지 못했다');

      expect(tester.takeException(), isNull,
          reason: '${w.toInt()}x${h.toInt()} 배율 $s 에서 넘쳤다');

      // 세 버튼 전부 도달 가능해야 한다.
      await _expectReachable(tester, kCtaWhole);
      await _expectReachable(tester, kCtaClear);
      await _expectReachable(tester, kCtaBack);

      expect(tester.takeException(), isNull,
          reason: 'CTA 를 끌어오는 과정에서 넘쳤다');
    });
  }

  testWidgets('짧은 화면에서도 시트가 9/16 에 갇히지 않는다', (tester) async {
    // 패치 전 360x640 의 시트 maxHeight 는 360.0(=9/16) 이었고 본문 356 이
    // 319.6 으로 눌려 36px 넘쳤다. isScrollControlled 로 그 상한이 풀려야 한다.
    await _openFailureSheet(tester, w: 360, h: 640, textScale: 1.0);
    expect(find.text(kSheetTitle), findsOneWidget);
    tester.takeException();

    final sheet = tester
        .renderObject<RenderBox>(find.byType(BottomSheet))
        .constraints
        .maxHeight;
    expect(sheet, greaterThan(360.0),
        reason: '시트 상한이 여전히 9/16(360.0)에 잠겨 있다 — '
            'isScrollControlled 가 적용되지 않았다');
  });
}
