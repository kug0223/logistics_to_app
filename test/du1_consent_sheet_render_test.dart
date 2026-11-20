// ignore_for_file: depend_on_referenced_packages
// [DU1-F2 · R4 · followup_6] 지원 확인 시트(동의 안내) LOCAL 실제 위젯 렌더 — 기본/큰 글씨, 본문 스크롤 끝(마지막 동의 문구 viewport 안), 본문 대비 토큰, 취소 실제 탭.
//   [정정] 하단 취소·CTA 는 스크롤 밖이라 항상 보인다 — 구현5 의 "끝까지 스크롤해 하단 행동 도달"은 실제 관측이 아니었다.
//   제출하지 않는다(Firestore 는 응답하지 않는 가짜 플랫폼). 모든 warning/info 소비처의 RUNTIME 통과를 뜻하지 않는다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';
import 'package:ALfit/widgets/dialogs/apply/multi_apply_confirm_sheet.dart';

import 'support/visible_text.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

final kDay = DateTime(2026, 11, 8);
final _nav = GlobalKey<NavigatorState>();

TOModel _to() => TOModel(
    id: 'to1', businessId: 'biz1', businessName: '[QA] 아주 긴 이름의 물류센터 사업장 평택 2공장', type: 'flex', title: '단기 모집',
    creatorUID: 'admin1', status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0, workDetails: const [],
    totalRequired: 2, totalConfirmed: 0, totalPending: 0, isPublished: true, publishMode: 'immediate',
    createdAt: DateTime(2026, 11, 1), statusUpdatedAt: DateTime(2026, 11, 1));

WorkDetailData _wd() => WorkDetailData(
    wdId: 'wd1', workType: 'QA 분류', workTypeIcon: 'box', workTypeColor: '#000000', workTypeBackgroundColor: '#FFFFFF',
    wage: 13000, wageType: 'hourly', requiredCount: 2, startTime: '15:30', endTime: '18:30', order: 0);

SlotModel _slot() => SlotModel(id: 's1', toId: 'to1', date: kDay, workDetails: [_wd()], status: SlotStatus.open, createdAt: DateTime(2026, 11, 1));

Future<List<String>> _pump(WidgetTester tester, {required Size size, required double scale}) async {
  final overflows = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final m = d.exceptionAsString();
    if (m.contains('overflowed')) {
      overflows.add(m.split('\n').first);
    } else {
      prev?.call(d);
    }
  };
  addTearDown(() => FlutterError.onError = prev);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: RoleTheme.workerTheme,
    builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    navigatorKey: _nav,
    home: const Scaffold(body: Text('공고 상세')),
  ));
  // 실제 사용처처럼 별도 route 로 연다 — 하단 '취소'가 Navigator.pop 으로 닫히는지까지 본다
  unawaited(_nav.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(body: MultiApplyConfirmSheet(items: [(slot: _slot(), work: _wd())], to: _to(), myApplications: const [])))));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return overflows;
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  for (final c in const [(Size(392, 844), 1.0), (Size(320, 640), 2.0)]) {
    testWidgets('동의 시트 ${c.$1.width.toInt()}dp×${c.$2} — 넘침 0 · 본문 warningDark · 본문 스크롤 끝의 마지막 동의 문구가 viewport 안 · 취소가 실제로 닫는다', (tester) async {
      final o = await _pump(tester, size: c.$1, scale: c.$2);
      final body = findVisibleTextContaining('지원하기를 누르면'); // [DU288] 보이는 글자(낱말 묶음 문자 제외)
      expect(body, findsOneWidget);
      expect(tester.widget<Text>(body).style?.color, AppColors.warningDark, reason: 'F2 — 경고 카드 본문 4.96:1');

      // [DU1 followup_6 §1] 하단 '취소'·CTA 는 스크롤 **밖**(항상 보임)이다 — 그 존재로 스크롤 도달을 판정하지 않는다.
      //   본문 SingleChildScrollView 를 끝(maxScrollExtent)까지 실제로 끌고, 마지막 동의 문구가 그 viewport 안에 온전히 있는지 본다.
      final bodyScroll = find.descendant(of: find.byType(MultiApplyConfirmSheet), matching: find.byType(Scrollable)).first;
      final pos = tester.state<ScrollableState>(bodyScroll).position;
      var drags = 0;
      while (pos.pixels < pos.maxScrollExtent && drags < 60) {
        await tester.drag(bodyScroll, const Offset(0, -200));
        await tester.pump(const Duration(milliseconds: 50));
        drags++;
      }
      expect(pos.pixels, moreOrLessEquals(pos.maxScrollExtent, epsilon: 0.5), reason: '본문 스크롤 끝에 도달');
      // ignore: avoid_print
      print('CONSENT-SCROLL ${c.$1.width.toInt()}x${c.$1.height.toInt()}@${c.$2}: max=${pos.maxScrollExtent.toStringAsFixed(1)} drags=$drags');
      final lastPart = DocumentAccessConsent.partsFor(_to().businessName).last.trim();
      final last = find.byWidgetPredicate((w) =>
          w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').replaceAll('\u2060', '').contains(lastPart.substring(0, 12)));
      expect(last, findsOneWidget, reason: '마지막 동의 문구');
      final vp = tester.getRect(bodyScroll);
      final r = tester.getRect(last);
      expect(r.top, greaterThanOrEqualTo(vp.top - 0.5));
      expect(r.bottom, lessThanOrEqualTo(vp.bottom + 0.5), reason: '마지막 동의 문구가 본문 viewport 안에 온전히');

      // 실제로 눌린다 — 시트 route 가 닫히고 공고 상세로 돌아온다(제출 writer 는 부르지 않는다)
      await tester.tap(find.widgetWithText(TextButton, '취소'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('공고 상세'), findsOneWidget);
      expect(find.byType(MultiApplyConfirmSheet), findsNothing);
      expect(o, isEmpty, reason: o.join(' | '));
    });
  }
}
