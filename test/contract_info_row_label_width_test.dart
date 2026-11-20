// [DEVICE-GOLDEN-PATH §7] 계약서 본문의 라벨이 값과 뒤섞여 읽히면 안 된다.
//
// ── 기기에서 본 것 ─────────────────────────────────────────────────────
//   Pixel_5(393dp, 배율 0.9) 에뮬레이터의 계약 상세 제2조에서
//     `기본 근무 시10:00 ~ 11:00 (휴게 30분) · 0.5h` / `간`
//   으로 보였다. 라벨 `기본 근무 시간` 이 고정폭 칸(76×0.9=68.4dp) 안에서
//   두 줄로 접히면서, 값이 라벨의 첫 줄 옆에 붙은 것이다.
//
// ── 측정 등급 ───────────────────────────────────────────────────────────
//   · W 셀 — 번들 `NotoSansKR` 을 실제로 로드해 `TextPainter` 로 잰다.
//     앱은 `fontFamily` 를 지정하지 않아 기기 기본 한글 폰트(Noto Sans CJK KR)
//     를 쓴다. 번들본은 그 **proxy** 다.
//   · R 셀 — production `ContractSignScreen` 을 실제로 그린다. 줄 수를
//     판정해야 하므로 테스트 기본 폰트(한글이 약 30% 넓다) 대신
//     번들 폰트를 테마에 걸어 그린다.
import 'dart:io';
import 'dart:typed_data';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/contract/contract_sign_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/visible_text.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── production 상수(복제 아님 — 같은 식을 쓴다) ─────────────────────────
//   라벨 칸: min 76 · max 124 · 오른쪽 여백 8 (전부 ResponsiveHelper.spacing)
const double _kMin = 76;
const double _kMax = 124;
const double _kGap = 8;

/// 393dp(Pixel 5) 의 배율. `ResponsiveHelper.getScale` 과 같은 식.
double _scaleOf(double width) {
  if (width < 360) return 0.85;
  if (width < 400) return 0.9;
  return 1.0;
}

double _textWidth(String s, {double fontSize = 13}) {
  final tp = TextPainter(
    text: TextSpan(
        text: s, style: TextStyle(fontFamily: 'NKR', fontSize: fontSize)),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return tp.width;
}

Future<void> _loadBundledFonts() async {
  for (final e in {
    'NKR': 'assets/fonts/NotoSansKR-Regular.ttf',
    'NKB': 'assets/fonts/NotoSansKR-Bold.ttf',
  }.entries) {
    final loader = FontLoader(e.key);
    final b = File(e.value).readAsBytesSync();
    loader.addFont(
        Future.value(ByteData.view(b.buffer, b.offsetInBytes, b.length)));
    await loader.load();
  }
}

// ── Firebase 가짜 코어 ──────────────────────────────────────────────────
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
      storageBucket: 'p.appspot.com');
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

class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '서울특별시', city: '강남구'),
        accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 1, 1),
        isIdVerified: true,
        createdAt: DateTime(2026, 1, 1),
      );
}

// ── 계약 fixture — 기기에서 본 그 계약과 같은 모양(단기·일급) ───────────
ContractSnapshot _snapshot() => ContractSnapshot(
      businessName: '[QA] 골든패스 테스트 사업장',
      businessNumber: '0000000000',
      businessAddress: '경기도 평택시 (QA 테스트) QA',
      ownerName: 'QA 관리자',
      workerName: 'QA 지원자1',
      workType: 'QA 분류',
      workPlace: '[QA] 골든패스 테스트 사업장',
      isLongTerm: false,
      contractStart: '2026-10-13',
      contractEnd: '2026-10-13',
      workDays: const ['화'],
      startTime: '10:00',
      endTime: '11:00',
      breakMinutes: 30,
      wage: 53000,
      wageType: 'daily',
      paymentMethod: '계좌입금',
      wagePaymentDay: 10,
      taxDeductionType: 'rate3_3',
      attendancePolicy: AttendanceRules.defaults(),
    );

EmploymentContractModel _contract() => EmploymentContractModel(
      id: 'c1',
      applicationId: 'to1_s1_wd1_u1',
      businessId: 'biz1',
      workerId: 'u1',
      isLongTerm: false,
      toId: 'to1',
      workDetailId: 'wd1',
      slots: const [
        ContractSlot(
          applicationId: 'to1_s1_wd1_u1',
          workDate: '2026-10-13',
          startTime: '10:00',
          endTime: '11:00',
          wage: 53000,
          wageType: 'daily',
        ),
      ],
      applicationIds: const ['to1_s1_wd1_u1'],
      status: ContractStatus.completed,
      snapshot: _snapshot(),
      articles: const [
        ContractArticle(title: '제1조 근로시간', content: 'QA 테스트 조항'),
      ],
      templateId: 'tpl1',
      createdAt: DateTime(2026, 10, 10),
    );

Future<void> _pump(WidgetTester t, {required Size size, double scale = 1.0}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _Worker()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        // 줄 수를 판정하려면 한글 폭이 기기와 비슷해야 한다.
        theme: ThemeData(fontFamily: 'NKR'),
        builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: ContractSignScreen(contract: _contract(), role: 'worker'),
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

RenderParagraph _paragraph(WidgetTester t, Finder f) => t.renderObject<RenderParagraph>(
    find.descendant(of: f, matching: find.byType(RichText), matchRoot: true).first);

/// 화면에 그려진 `text` 라벨의 줄 수.
int _lineCount(WidgetTester t, String text) {
  // [.29] 라벨은 줄바꿈 제어 문자(WORD JOINER)를 품는다 — 보이는 글자로 찾고 렌더는 안쪽 RichText 에서 본다.
  final finder = findVisibleText(text);
  expect(finder, findsOneWidget, reason: '라벨 "$text" 를 찾지 못했다');
  final rp = _paragraph(t, finder);
  // 줄 수 = 글자 상자들의 서로 다른 top 개수.
  final boxes = rp.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: rp.text.toPlainText().length));
  return boxes.map((b) => b.top.round()).toSet().length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await _loadBundledFonts();
    initializeDateFormatting('ko');
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // 계약 본문에서 실제로 쓰이는 라벨들.
  const labels = <String>[
    '사업장명', '대표자', '사업자번호', '소재지', '연락처',
    '근로자 성명', '생년월일', '주소',
    '근무 장소', '담당 업무', '근무 기간', '근무 요일', '근무 시간',
    '기본 근무 시간',
    '통상시급', '지급 방법', '지급 방식', '지급 일정',
  ];

  group('[W] 번들 폰트 실측 — 라벨 칸', () {
    test('W-1 옛 고정폭(76)은 `기본 근무 시간` 을 한 줄에 담지 못한다', () {
      final w = _textWidth('기본 근무 시간');
      for (final width in [360.0, 393.0, 412.0]) {
        final old = _kMin * _scaleOf(width);
        expect(w > old, isTrue,
            reason: '${width.toInt()}dp: 라벨 ${w.toStringAsFixed(1)}px '
                '> 옛 칸 ${old.toStringAsFixed(1)}px — 그래서 접혔다');
      }
    });

    test('W-2 새 상한(124) 안에는 한 줄로 들어간다', () {
      for (final width in [360.0, 393.0, 412.0]) {
        final s = _scaleOf(width);
        final room = _kMax * s - _kGap * s;
        for (final l in labels) {
          expect(_textWidth(l) <= room, isTrue,
              reason: '${width.toInt()}dp: "$l" '
                  '${_textWidth(l).toStringAsFixed(1)}px '
                  '> 상한 ${room.toStringAsFixed(1)}px — 잘린다');
        }
      }
    });

    test('W-3 짧은 라벨은 최소폭 안에 들어 정렬이 유지된다', () {
      const short = ['사업장명', '대표자', '소재지', '연락처', '담당 업무', '지급 방법'];
      for (final width in [360.0, 393.0, 412.0]) {
        final s = _scaleOf(width);
        final room = _kMin * s - _kGap * s;
        for (final l in short) {
          expect(_textWidth(l) <= room, isTrue,
              reason: '${width.toInt()}dp: "$l" 가 최소폭을 넘으면 '
                  '값 시작 위치가 흔들린다');
        }
      }
    });

    test('W-4 가장 긴 라벨이 무엇인지 기록한다', () {
      final sorted = [...labels]
        ..sort((a, b) => _textWidth(b).compareTo(_textWidth(a)));
      expect(sorted.first, '기본 근무 시간',
          reason: '가장 긴 라벨이 바뀌면 상한(124)을 다시 재야 한다');
    });
  });

  group('[R] 실제 계약 화면 렌더', () {
    for (final size in [const Size(360, 1200), const Size(393, 1200)]) {
      testWidgets('R-1 ${size.width.toInt()}dp — `기본 근무 시간` 이 한 줄이다',
          (t) async {
        await _pump(t, size: size);
        expect(_lineCount(t, '기본 근무 시간'), 1,
            reason: '라벨이 접히면 값과 뒤섞여 읽힌다');
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('R-2 라벨과 값이 겹치지 않는다 — 값은 라벨 오른쪽에서 시작한다',
        (t) async {
      await _pump(t, size: const Size(393, 1200));
      final labelRect = t.getRect(findVisibleText('기본 근무 시간'));
      final valueRect = t.getRect(findVisibleTextContaining('10:00 ~ 11:00').first);
      expect(valueRect.left >= labelRect.right, isTrue,
          reason: '값이 라벨 글자 위로 올라왔다 '
              '(라벨 right=${labelRect.right}, 값 left=${valueRect.left})');
    });

    testWidgets('R-3 짧은 라벨들의 값 시작 위치는 서로 같다 — 정렬 유지', (t) async {
      await _pump(t, size: const Size(393, 1200));
      // 사업장명·근무 장소 — 둘 다 짧은 라벨 줄이고 값이 같은 문자열이다.
      final rects = find
          .byWidgetPredicate((w) => w is Text && visibleText(w.data ?? '') == '[QA] 골든패스 테스트 사업장')
          .evaluate()
          .map((e) => t.getRect(find.byWidget(e.widget)).left)
          .toList();
      expect(rects.length >= 2, isTrue, reason: '비교할 짧은 라벨 줄이 모자란다');
      final a = rects[0];
      final b = rects[1];
      expect((a - b).abs() < 0.5, isTrue,
          reason: '짧은 라벨 줄의 값이 서로 어긋났다 ($a vs $b)');
    });

    testWidgets('R-4 라벨이 잘리지 않는다 — 말줄임 없음', (t) async {
      await _pump(t, size: const Size(360, 1200));
      for (final l in ['근로자 성명', '기본 근무 시간', '담당 업무']) {
        final rp = _paragraph(t, findVisibleText(l));
        expect(rp.didExceedMaxLines, isFalse, reason: '"$l" 이 잘렸다');
      }
    });

    testWidgets('R-5 넘침 0 — 360dp', (t) async {
      await _pump(t, size: const Size(360, 1200));
      expect(t.takeException(), isNull);
    });

    // [DU1 followup_7 §2 · S048] 실제 높이 320×640 · 글씨 2.0 — 스크롤로 제2조 아래 라벨에 닿아 라벨이 잘리지 않고 값과 겹치지 않는다.
    //   서명·제출·DEV 쓰기 없음(서비스 미주입 — worker 하네스의 남은 읽기는 _checkTOType 의 TO 조회이며 가짜 플랫폼에서 끝나지 않는다).
    testWidgets('R-6 320×640@2.0 — 제2조 라벨 스크롤 도달·잘림 없음·값과 겹침 없음·읽기색·넘침 0', (t) async {
      await _pump(t, size: const Size(320, 640), scale: 2.0);
      final sc = find.byType(Scrollable).first;
      for (final l in const ['근무 장소', '담당 업무', '근무 형태', '기본 근무 시간']) {
        final lf = findVisibleText(l);
        await t.scrollUntilVisible(lf, 120, scrollable: sc, maxScrolls: 80);
        await t.pump(const Duration(milliseconds: 60));
        final lr = t.getRect(lf);
        expect(lr.left >= 0 && lr.right <= 320, isTrue, reason: '"$l" 가로 화면 안 ($lr)');
        expect(lr.top >= 0 && lr.bottom <= 640, isTrue, reason: '"$l" 세로 viewport 안 ($lr)');
        expect(_paragraph(t, lf).didExceedMaxLines, isFalse, reason: '"$l" 잘림');
        final w = t.widget<Text>(lf);
        expect(w.style?.color, AppColors.textSecondary, reason: '"$l" 라벨 읽기색');
      }
      // 값('10:00 ~ 11:00')은 라벨과 겹치지 않는다 — 옆이면 오른쪽, 쌓이면 아래
      final lr = t.getRect(findVisibleText('기본 근무 시간'));
      final vr = t.getRect(findVisibleTextContaining('10:00 ~ 11:00').first);
      // ignore: avoid_print
      print('R-6 label=$lr value=$vr');
      expect(!lr.overlaps(vr), isTrue, reason: '라벨 $lr 와 값 $vr 가 겹친다');
      expect(t.takeException(), isNull);
    });
  });
}
