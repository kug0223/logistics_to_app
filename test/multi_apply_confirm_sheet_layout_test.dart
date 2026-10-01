// [R7-P4.4E.6C] 지원 확인 시트(여러 건)의 세로 넘침과 동의 안내 구조.
//
// DEVICE 반례: `3개 업무에 지원합니다` 화면에서 **BOTTOM OVERFLOWED BY 165
//   PIXELS**. 위아래로 스크롤되지도 않아 동의 안내와 하단 CTA 가 서로 밀렸다.
//
// root cause (실측으로 확정): `multi_apply_confirm_sheet.dart` 의 root
//   `Column(mainAxisSize: min)` 에 `Flexible` 이 **하나도 없었다**.
//   묶여 있던 것은 업무 목록뿐(`ConstrainedBox(0.42×화면높이)` + 자체 스크롤)이고
//   헤더·동의 안내·CTA 는 전부 intrinsic 이라, 합이 시트 높이를 넘는 순간
//   그대로 잘렸다. 본문 scroll owner 가 없어 스크롤로 볼 수도 없었다.
//
//   패치 전 실측(이 하네스):
//     360×800 3건  **87px**      320×640 3건  **290px**
//     411×823 3건  27px          360×800 5건  145px
//     360×800 1건  0  (시트 701.9 — 내용 크기대로)
//   기기 165px 은 이 범위 안이고 **같은 RenderFlex** 다. 테스트 폰트가
//   실제 폰트와 달라 수치는 다르지만 기제가 같다.
//
//   덧붙여 하단 여백을 두 번 세고 있었다 — `DialogHelper.showSheet` 가
//   `useSafeArea: true` + `Padding(bottom: sheetBottomInset)` 를 넣는데
//   시트가 또 `max(20, viewPadding.bottom)` 을 더했다. 공용
//   `sheetBottomInset` 은 건드리지 않고 이쪽 중복만 걷었다.
//
// 이 파일이 고정하는 계약
//   1. 넘침 0 — 1건·3건·5건 × 320/360/411 × 배율 1.0/1.3/2.0.
//   2. 1건이면 시트가 **내용 크기**다 — 고정 높이로 키우지 않는다.
//   3. 본문에 scroll owner 가 있고, 동의 안내 끝과 CTA 에 **도달**할 수 있다.
//   4. 선택한 업무의 날짜·업무명·시간·임금이 **전부** 남는다.
//   5. 동의 문구는 글자 하나도 바뀌지 않았다 — `partsFor.join('\n') == copyFor`.
//   6. 레이아웃 수정이 제출 의미를 바꾸지 않았다(§19).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';
import 'package:ALfit/widgets/dialogs/apply/multi_apply_confirm_sheet.dart';

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

class _Applicant extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 2, 1),
        isIdVerified: true,
        idCardImagePath: 'users/u1/id.png',
        bankName: '국민은행',
        accountNumber: '1234',
        accountHolder: '김근로',
        bankbookImagePath: 'users/u1/bb.png',
        createdAt: DateTime(2026, 1, 1),
      );
}

const kBizName = '강남 물류센터 주식회사';

final kFuture = DateTime(
  DateTime.now().year,
  DateTime.now().month,
  DateTime.now().day,
).add(const Duration(days: 5));

TOModel _to() => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: kBizName,
      type: 'flex',
      title: '단기 모집',
      creatorUID: 'a',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 50,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      rangeStart: kFuture,
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

WorkDetailData _wd(int i) => WorkDetailData(
      wdId: 'wd$i',
      workType: '냉장분류',
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: 12000,
      wageType: 'hourly',
      requiredCount: 10,
      startTime: '18:00',
      endTime: '22:30',
      breakMinutes: 30,
    );

SlotModel _slot(int i) => SlotModel(
      id: 'slot$i',
      toId: 'to1',
      date: kFuture.add(Duration(days: i)),
      workDetails: [_wd(i)],
      status: SlotStatus.open,
    );

List<String> _overflows(List<String> sink) =>
    sink.where((e) => e.contains('overflowed')).toList();

Future<List<String>> _open(
  WidgetTester tester, {
  required double w,
  required double h,
  required double scale,
  required int count,
  List<ApplicationModel> myApps = const [],
  double safeBottom = 48,
}) async {
  final sink = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final s = d.exception.toString();
    if (s.contains('overflowed')) {
      sink.add(s.split('\n').first);
    } else {
      prev?.call(d);
    }
  };
  addTearDown(() => FlutterError.onError = prev);

  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final items = <({SlotModel? slot, WorkDetailData work})>[
    for (var i = 0; i < count; i++) (slot: _slot(i), work: _wd(i)),
  ];

  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => _Applicant(),
      child: MaterialApp(
        home: Builder(
          builder: (c) => MediaQuery(
            data: MediaQuery.of(c).copyWith(
              textScaler: TextScaler.linear(scale),
              viewPadding: EdgeInsets.only(bottom: safeBottom),
              padding: EdgeInsets.only(bottom: safeBottom),
            ),
            child: Scaffold(
              body: Center(
                child: Builder(
                  builder: (inner) => ElevatedButton(
                    // production 과 같은 인자다 — 공고 상세가 이렇게 띄운다.
                    onPressed: () => DialogHelper.showSheet<MultiApplyResult>(
                      inner,
                      useRootNavigator: true,
                      isScrollControlled: true,
                      builder: (_) => MultiApplyConfirmSheet(
                        items: items,
                        to: _to(),
                        myApplications: myApps,
                      ),
                    ),
                    child: const Text('열기'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('열기'));
  // 충돌 체크는 실제 플랫폼 채널을 탄다 — 가짜 시계로는 그 future 가 끝나지
  //   않아 `_isCheckingConflicts` 가 풀리지 않고 CTA 문구·배지가 눌린다.
  //   진짜 async 를 두 틱 준다(항목 수만큼 조회가 이어진다).
  for (var t = 0; t < 2; t++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
  return sink;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async => FirebasePlatform.instance = _FakeCore());

  // ── 1) 넘침 — 건수 × 폭 × 배율 ────────────────────────────────
  group('MAC-1x 넘침 0', () {
    for (final n in [1, 3, 5]) {
      for (final cell in <List<double>>[
        [320, 640],
        [360, 800],
        [411, 823],
      ]) {
        for (final s in [1.0, 1.3, 2.0]) {
          testWidgets(
              'MAC-10 ${n}건 ${cell[0].toInt()}x${cell[1].toInt()} 배율 $s',
              (tester) async {
            final sink = await _open(tester,
                w: cell[0], h: cell[1], scale: s, count: n);
            expect(find.byType(MultiApplyConfirmSheet), findsOneWidget,
                reason: '시트가 열리지 않았다 — 측정 대상에 도달 못 함');
            expect(_overflows(sink), isEmpty,
                reason: '${n}건 ${cell[0].toInt()}dp 배율 $s 에서 넘쳤다: '
                    '${_overflows(sink)}');
            await tester.pump(const Duration(seconds: 5));
          });
        }
      }
    }
  });

  // ── 2) 내용이 적으면 시트도 작다 ──────────────────────────────
  testWidgets('MAC-20 1건이면 시트가 내용 크기다 (고정 높이로 키우지 않는다)',
      (tester) async {
    // 내용이 들어갈 만한 화면에서 본다. 360×800 에서는 1건이어도 동의 7조건 +
    //   안내 + CTA 가 800 을 거의 채워 `< max` 가 성립하지 않는다(실측 800.0)
    //   — 그건 시트가 억지로 커진 게 아니라 내용이 정말 그만큼이라는 뜻이다.
    //   "내용이 작으면 작게" 는 내용이 실제로 작을 때 검증해야 한다.
    await _open(tester, w: 412, h: 1200, scale: 1.0, count: 1);
    final box = tester.renderObject<RenderBox>(find.byType(BottomSheet));
    expect(box.size.height, lessThan(box.constraints.maxHeight),
        reason: '1건인데 화면 전체를 차지하면 안 된다');
    await tester.pump(const Duration(seconds: 5));
  });

  // 한 test 안에서 시트를 두 번 띄워 높이를 비교하려 했으나, 앞 시트가
  //   navigator 에 남아 `find.byType(BottomSheet)` 가 같은 것을 집었다
  //   (두 셀 모두 798.0). 비교는 하네스 성질에 기대므로 걷고, 아래 두 셀로
  //   같은 계약을 고정한다 —
  //     MAC-20: 내용이 들어가는 화면에서 1건이면 `시트 < 상한`  → content-driven
  //     MAC-21: 좁은 화면 5건이면 본문 `maxScrollExtent > 0`    → bounded + scroll
  //   "3건에만 맞춘 고정 높이" 라면 둘 중 하나가 깨진다.

  testWidgets('MAC-21 건수가 늘면 본문이 스크롤된다', (tester) async {
    await _open(tester, w: 320, h: 640, scale: 1.0, count: 5);
    // 본문 scroll owner — 예전에는 업무 목록만 스크롤했고 본문엔 없었다.
    final sv = find.byType(Scrollable);
    expect(sv, findsWidgets, reason: '본문에 스크롤 주인이 있어야 한다');
    final pos = tester.widget<Scrollable>(sv.first).controller?.position ??
        Scrollable.of(tester.element(sv.first)).position;
    expect(pos.maxScrollExtent, greaterThan(0.0),
        reason: '내용이 넘치면 스크롤로 볼 수 있어야 한다');
    await tester.pump(const Duration(seconds: 5));
  });

  // ── 3) 선택 업무 정보가 전부 남는다 ───────────────────────────
  testWidgets('MAC-30 3건 — 날짜·업무명·시간·임금이 모두 있다', (tester) async {
    await _open(tester, w: 320, h: 640, scale: 1.0, count: 3);

    // 업무명 3건
    expect(find.textContaining('냉장분류'), findsNWidgets(3),
        reason: '일부만 보여주고 "외 N건" 으로 줄이지 않는다');
    // 시간·임금 — 축약·ellipsis 없이 남아야 한다
    expect(find.textContaining('18:00'), findsWidgets);
    expect(find.textContaining('12,000'), findsWidgets);
    // 날짜 — 각 항목이 자기 날짜를 말한다
    expect(find.textContaining('월'), findsWidgets);
    await tester.pump(const Duration(seconds: 5));
  });

  // ── 4) 동의 끝과 CTA 에 도달할 수 있다 ───────────────────────
  testWidgets('MAC-40 320dp 배율 2.0 — 동의 마지막 문단과 CTA 도달', (tester) async {
    final sink = await _open(tester, w: 320, h: 640, scale: 2.0, count: 3);

    final parts = DocumentAccessConsent.partsFor(kBizName);
    final tail = find.text(parts.last);
    expect(tail, findsOneWidget, reason: '동의 마지막 문단이 트리에 있어야 한다');
    await tester.ensureVisible(tail);
    await tester.pump();

    // CTA 는 footer 라 스크롤과 무관하게 접근 가능해야 한다.
    final cta = find.textContaining('지원하기');
    expect(cta, findsWidgets, reason: 'CTA 가 사라졌다');
    await tester.ensureVisible(cta.last);
    await tester.pump();

    expect(_overflows(sink), isEmpty, reason: '도달 과정에서 넘쳤다');
    await tester.pump(const Duration(seconds: 5));
  });

  // ── 5) 동의 문구 — 글자가 바뀌지 않았다 ──────────────────────
  group('MAC-5x 동의 canonical 보존', () {
    test('MAC-50 partsFor 를 다시 합치면 canonical 문구와 같다', () {
      final parts = DocumentAccessConsent.partsFor(kBizName);
      expect(parts.join('\n'), DocumentAccessConsent.copyFor(kBizName),
          reason: '구조만 바꿨다 — 문자열은 한 글자도 바뀌지 않는다');
    });

    test('MAC-51 consent version 은 그대로다', () {
      // 서버 allowlist(`DOCUMENT_ACCESS_CONSENT_V3`)와 같은 값이어야 한다.
      expect(DocumentAccessConsent.version, '2026-09-18-v3');
    });

    test('MAC-52 문단이 실제로 나뉘어 있다 (한 덩어리가 아니다)', () {
      final parts = DocumentAccessConsent.partsFor(kBizName);
      expect(parts.length, greaterThan(1),
          reason: '일곱 조건이 한 덩어리로 붙어 있던 것을 끊었다');
      for (final p in parts) {
        expect(p.trim(), isNotEmpty);
      }
    });

    testWidgets('MAC-53 모든 문단이 화면에 그려진다', (tester) async {
      await _open(tester, w: 360, h: 800, scale: 1.0, count: 1);
      for (final p in DocumentAccessConsent.partsFor(kBizName)) {
        expect(find.text(p), findsOneWidget,
            reason: '동의 내용이 일부라도 사라지면 안 된다: $p');
      }
      await tester.pump(const Duration(seconds: 5));
    });
  });

  // ── 6) §19 제출 의미 회귀 — 레이아웃 수정이 동작을 바꾸지 않았다 ──
  group('MAC-6x 제출 의미 보존', () {
    testWidgets('MAC-60 N 은 신규 지원 가능한 건수다', (tester) async {
      await _open(tester, w: 360, h: 800, scale: 1.0, count: 3);
      expect(find.textContaining('3개 업무 지원하기'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('MAC-61 이미 지원한 건은 N 에서 빠진다 (E7 관계 판정 유지)',
        (tester) async {
      // slot0 / wd0 에 이미 PENDING — 제출 대상이 아니다.
      final already = ApplicationModel(
        id: 'to1_slot0_wd0_u1',
        uid: 'u1',
        toId: 'to1',
        slotId: 'slot0',
        businessId: 'biz1',
        businessName: kBizName,
        toTitle: '단기 모집',
        selectedWorkType: '냉장분류',
        wdId: 'wd0',
        startTime: '18:00',
        endTime: '22:30',
        wage: 12000,
        wageType: 'hourly',
        status: AppStatus.pending,
        workDate: kFuture,
        appliedAt: DateTime(2026, 10, 1),
      );
      await _open(tester,
          w: 360, h: 800, scale: 1.0, count: 3, myApps: [already]);

      expect(find.text('이미 지원중'), findsOneWidget,
          reason: '그 한 건만 이미 지원중이어야 한다');
      expect(find.textContaining('2개 업무 지원하기'), findsOneWidget,
          reason: '3건 중 1건이 관계로 빠져 N=2 다 — 레이아웃이 N 을 바꾸지 않는다');
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
