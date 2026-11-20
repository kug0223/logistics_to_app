import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/utils/resign_auto_approval.dart';
import 'package:ALfit/utils/responsive_helper.dart';
import 'package:ALfit/widgets/dialogs/long_term_work_management_dialog.dart';
import 'support/visible_text.dart'; // [DU271] 상세 문구가 keepWords 라 보이는 글자로 찾는다
import 'package:ALfit/widgets/dialogs/styled_dialog.dart';

// ═══════════════════════════════════════════════════════════════
// [D3-RETRO-EXCLUDE] 소급 퇴사 요청 — 앱 문구(4곳)가 서버 정책과 같은 말을 하는가.
//
//   서버(후보 307e·4cbe):
//     · 소급 = 희망일 KST 일 < 요청 KST 일 → masterScheduler 가 자동 승인하지 않는다.
//     · 정상 = resignRequestedAt <= (오늘 KST 자정 − 3일) 인 실행에서 자동 승인.
//   앱:
//     · 소급 → "관리자 검토" + 현재 상태(대기). 자동 승인 약속 없음.
//     · 정상 → 기존 일정 문구 그대로("N일 후 자동 승인" / "오늘 자정 자동 승인").
//     · 예정 자정이 지났는데 대기 → 음수 일수·지난 약속 없이 "예정일 지남".
//
//   RRM-A: 날짜를 고정한 순수 판정·문구(관리자 카드·관리자 배너·근로자 배너 문자열 그대로).
//   RRM-B: 근로자 퇴사 상태 배너 — **실제 위젯**(LongTermWorkManagementDialog) 320·360·411dp.
//          위젯이 DateTime.now() 를 직접 읽으므로 fixture 는 오늘(KST)에서 일 단위로 파생한다.
//   RRM-C: 관리자 두 다이얼로그는 initState 에서 Firestore 를 읽어 카드를 띄울 수 없다 →
//          해당 줄의 **소스 중첩을 그대로 옮긴 구조 복제**로 폭을 잰다(문자열은 production getter).
//   폰트는 번들 NotoSansKR(테스트 기본 폰트는 한글 폭이 실제보다 넓다).
// ═══════════════════════════════════════════════════════════════

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

/// KST 벽시계 → UTC instant.
DateTime _kst(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min).subtract(const Duration(hours: 9));

/// 고정 '지금' — 2026-10-22(목) KST 12:00.
final _now = _kst(2026, 10, 22, 12);

/// 서버 masterScheduler 의 D+3 판정(가장 최근 자정 실행이 이미 승인했는가)을 그대로 옮긴 대조식.
bool _schedulerAlreadyApproved(DateTime requestedAt, DateTime now) {
  final k = now.toUtc().add(const Duration(hours: 9));
  final todayKstMidnight = _kst(k.year, k.month, k.day);
  final threeDaysAgo = todayKstMidnight.subtract(const Duration(days: 3));
  return !requestedAt.isAfter(threeDaysAgo);
}

ApplicationModel _longTermApp({
  required String id,
  required DateTime requestedAt,
  required DateTime requestDate,
}) =>
    ApplicationModel(
      id: id, uid: 'W', toId: 'TO', businessId: 'BIZ',
      businessName: '강남 물류센터', toTitle: '장기 상하차',
      selectedWorkType: '상하차', startTime: '09:00', endTime: '18:00',
      wage: 12000, wageType: 'hourly', status: AppStatus.confirmed,
      applicationType: AppType.longTerm,
      workDays: const ['월', '화', '수', '목', '금'],
      workDate: _kst(2026, 9, 1),
      workEndDate: _kst(2027, 2, 28),
      appliedAt: _kst(2026, 8, 20),
      resignStatus: AppStatus.pending,
      resignRequestedAt: requestedAt,
      resignRequestDate: requestDate,
    );

Future<void> _loadKoreanFont() async {
  for (final e in {
    'NotoSansKR': 'assets/fonts/NotoSansKR-Regular.ttf',
  }.entries) {
    final f = File(e.value);
    if (!f.existsSync()) fail('번들 폰트 없음: ${e.value}');
    final loader = FontLoader(e.key)
      ..addFont(f.readAsBytes().then((b) => ByteData.view(b.buffer)));
    await loader.load();
  }
  final bold = File('assets/fonts/NotoSansKR-Bold.ttf');
  if (bold.existsSync()) {
    final loader = FontLoader('NotoSansKR')
      ..addFont(bold.readAsBytes().then((b) => ByteData.view(b.buffer)));
    await loader.load();
  }
}

/// [bundledFont] true = 번들 NotoSansKR(기기 근사, 줄 수 판정) · false = 테스트 기본 폰트
///   (한글이 약 30% 넓다 — 여기서 안 넘치면 기기에서도 안 넘친다).
Future<void> _pumpAt(WidgetTester tester, double width, Widget child,
    {bool bundledFont = true}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: bundledFont ? ThemeData(fontFamily: 'NotoSansKR') : null,
    home: Scaffold(body: child),
  ));
  await tester.pump();
}

/// 한 Text 가 몇 줄로 그려졌는가.
int _linesOf(WidgetTester tester, Finder text) {
  // [DU271 r1] Text 에 semanticsLabel 이 붙으면 첫 렌더 객체가 의미 주석이다 — 안의 문단(RichText)을 센다.
  final p = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText), matchRoot: true).first);
  // 같은 스타일·배율의 한 줄 높이로 나눈다(폰트별 줄 높이를 추정하지 않는다).
  final one = TextPainter(
    text: TextSpan(text: '가', style: p.text.style),
    textDirection: TextDirection.ltr,
    textScaler: p.textScaler,
  )..layout();
  return (p.size.height / one.height).round();
}

/// RRM-C 구조 복제 — resign_request_management_dialog.dart '퇴사 요청 정보' 상자와 같은 중첩.
///   AppModalShell → ListView(cardPadding) → 카드 Container(cardPadding) → 정보 Container(cardPadding).
Widget _adminCardReplica(ResignAutoApproval plan) => Builder(builder: (context) {
      final isUrgent = plan.isUrgent;
      return AppModalShell(children: [
        Expanded(
          child: ListView(padding: ResponsiveHelper.cardPadding(context), children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.grey200),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: ResponsiveHelper.cardPadding(context),
                child: Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  child: Row(children: [
                    Icon(isUrgent ? Icons.warning : Icons.info_outline,
                        size: ResponsiveHelper.iconSize(context, 16)),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: Text(
                        plan.adminCardText,
                        key: const Key('admin-card-plan'),
                        style: ResponsiveHelper.smallStyle(context,
                                color: isUrgent ? AppColors.error : AppColors.warning)
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ]);
    });

/// RRM-C 구조 복제 — fixed_worker_management_dialog.dart 상태 배너와 같은 중첩.
///   AppModalShell → 목록 cardPadding → 근로자 카드 Padding(16·scale) → 배너 Container.
Widget _adminBannerReplica(ResignAutoApproval plan) => Builder(builder: (context) {
      return AppModalShell(children: [
        Expanded(
          child: ListView(padding: ResponsiveHelper.cardPadding(context), children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12),
                    vertical: ResponsiveHelper.spacing(context, 8),
                  ),
                  child: Row(children: [
                    Icon(Icons.exit_to_app, size: ResponsiveHelper.iconSize(context, 16)),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: Text(
                        '퇴사 요청중 (${plan.adminBannerText})',
                        key: const Key('admin-banner-plan'),
                        style: ResponsiveHelper.smallStyle(context)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ]);
    });

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
    await _loadKoreanFont();
  });

  // ══════════════════════════════════════════════════════════
  // RRM-A 날짜 고정 판정·문구
  // ══════════════════════════════════════════════════════════
  group('RRM-A 판정·문구 (지금 = 2026-10-22 KST 12:00)', () {
    test('RRM-A1 정상 요청 당일 → 3일 후 자동 승인', () {
      final p = ResignAutoApproval.of(
          requestedAt: _kst(2026, 10, 22, 10), requestDate: _kst(2026, 10, 31), now: _now);
      expect(p.kind, ResignAutoApprovalKind.scheduled);
      expect(p.daysLeft, 3);
      expect(p.adminCardText, '3일 후 자동 승인');
      expect(p.adminBannerText, '3일 후 자동 승인');
      expect(p.workerDetailText, '3일 후 자동 승인');
      expect(p.isUrgent, isFalse);
    });

    test('RRM-A2 정상 요청 D+3(요청 10/19) → 오늘 자정 자동 승인(기존 문구 유지)', () {
      final p = ResignAutoApproval.of(
          requestedAt: _kst(2026, 10, 19, 23, 50), requestDate: _kst(2026, 10, 25), now: _now);
      expect(p.kind, ResignAutoApprovalKind.scheduled);
      expect(p.daysLeft, 0);
      expect(p.adminCardText, '오늘 자정 자동 승인');
      expect(p.adminBannerText, '오늘 자동 승인');
      expect(p.workerDetailText, '오늘 자정 자동 승인');
      expect(p.isUrgent, isTrue);
    });

    test('RRM-A3 D+3 이후 대기(요청 10/17) → 예정일 지남 · 음수·지난 약속 없음', () {
      final p = ResignAutoApproval.of(
          requestedAt: _kst(2026, 10, 17, 9), requestDate: _kst(2026, 10, 30), now: _now);
      expect(p.kind, ResignAutoApprovalKind.overdue);
      expect(p.dueLabel, '10/20');
      expect(p.adminCardText, '자동 승인 예정일(10/20) 지남 · 아직 대기 중');
      expect(p.adminBannerText, '자동 승인 예정일 10/20 지남');
      expect(p.workerDetailText, '자동 승인 예정일 지남 · 처리 대기');
      for (final s in [p.adminCardText, p.adminBannerText, p.workerDetailText]) {
        expect(s.contains('-'), isFalse, reason: '음수 일수 금지: $s');
        expect(s.contains('일 후'), isFalse, reason: '지난 일정을 다시 약속하지 않는다: $s');
        expect(s.contains('오늘'), isFalse, reason: s);
      }
      expect(p.isUrgent, isTrue);
    });

    test('RRM-A4 소급 요청(희망일 10/20 < 요청 10/22) → 관리자 검토 · 자동 승인 약속 없음', () {
      final p = ResignAutoApproval.of(
          requestedAt: _kst(2026, 10, 22, 10), requestDate: _kst(2026, 10, 20), now: _now);
      expect(p.kind, ResignAutoApprovalKind.manualReview);
      expect(p.adminCardText, '소급 요청 · 자동 승인 안 됨 · 관리자 검토 대기');
      expect(p.adminBannerText, '소급 요청 · 관리자 검토 필요');
      expect(p.workerDetailText, '소급 요청 · 관리자 검토 후 처리');
      for (final s in [p.adminCardText, p.adminBannerText, p.workerDetailText]) {
        expect(RegExp(r'\d+일 후').hasMatch(s), isFalse, reason: s);
        expect(s.contains('자정'), isFalse, reason: s);
      }
      expect(p.isUrgent, isFalse);
    });

    test('RRM-A5 소급 요청은 D+3 이 지나도 "예정일 지남"이 아니라 검토 대기다', () {
      final p = ResignAutoApproval.of(
          requestedAt: _kst(2026, 10, 10, 10), requestDate: _kst(2026, 10, 5), now: _now);
      expect(p.kind, ResignAutoApprovalKind.manualReview);
    });

    test('RRM-A6 희망일이 요청 당일이면 소급이 아니다(서버와 같은 엄격 비교)', () {
      expect(
          ResignAutoApproval.isRetro(
              requestedAt: _kst(2026, 10, 22, 23, 59), requestDate: _kst(2026, 10, 22)),
          isFalse);
    });

    test('RRM-A7 KST 날짜로 판정 — 요청 KST 00:30(UTC 전날)·희망일 전날 KST → 소급', () {
      final req = _kst(2026, 10, 22, 0, 30); // = UTC 10/21 15:30
      expect(req.isUtc && req.day == 21, isTrue);
      expect(ResignAutoApproval.isRetro(requestedAt: req, requestDate: _kst(2026, 10, 21)), isTrue);
      // UTC 자정(=KST 09:00)으로 저장된 같은 날 희망일은 소급이 아니다
      expect(
          ResignAutoApproval.isRetro(requestedAt: req, requestDate: DateTime.utc(2026, 10, 22)),
          isFalse);
    });

    test('RRM-A8 요청 시각을 모르면 일정을 말하지 않는다', () {
      final p = ResignAutoApproval.of(requestedAt: null, requestDate: _kst(2026, 10, 30), now: _now);
      expect(p.kind, ResignAutoApprovalKind.unknown);
      expect(p.adminCardText, '승인 대기 중');
      expect(p.workerDetailText.contains('자동'), isFalse);
    });

    test('RRM-A9 정상 요청 — "예정일 지남" ⇔ 서버 스케줄러가 이미 승인했을 시점(요청 0~6일 전 × 하루 4시각)', () {
      for (var back = 0; back <= 6; back++) {
        for (final h in [0, 1, 12, 23]) {
          final day = _kst(2026, 10, 22).subtract(Duration(days: back));
          final req = day.add(Duration(hours: h, minutes: h == 0 ? 5 : 0));
          if (req.isAfter(_now)) continue;
          final p = ResignAutoApproval.of(
              requestedAt: req, requestDate: _kst(2026, 11, 30), now: _now);
          expect(p.kind == ResignAutoApprovalKind.overdue, _schedulerAlreadyApproved(req, _now),
              reason: 'back=$back h=$h');
          if (p.kind == ResignAutoApprovalKind.scheduled) {
            expect(p.daysLeft, inInclusiveRange(0, 3));
          }
        }
      }
    });
  });

  // ══════════════════════════════════════════════════════════
  // RRM-B 근로자 퇴사 상태 배너 — 실제 위젯
  // ══════════════════════════════════════════════════════════
  group('RRM-B 근로자 LongTermWorkManagementDialog 실제 렌더', () {
    // 위젯이 DateTime.now() 를 읽는다 — 오늘(KST)에서 일 단위로 파생한다.
    final kstToday = () {
      final k = DateTime.now().toUtc().add(const Duration(hours: 9));
      return _kst(k.year, k.month, k.day);
    }();
    final cases = <String, ({DateTime req, DateTime date, String expect})>{
      '정상(오늘 요청)': (
        req: kstToday.add(const Duration(minutes: 1)),
        date: kstToday.add(const Duration(days: 10)),
        expect: '3일 후 자동 승인'
      ),
      '정상 D+3': (
        req: kstToday.subtract(const Duration(days: 3)).add(const Duration(hours: 10)),
        date: kstToday.add(const Duration(days: 10)),
        expect: '오늘 자정 자동 승인'
      ),
      'D+3 이후 대기': (
        req: kstToday.subtract(const Duration(days: 6)).add(const Duration(hours: 10)),
        date: kstToday.add(const Duration(days: 10)),
        expect: '자동 승인 예정일 지남 · 처리 대기'
      ),
      '소급': (
        req: kstToday.add(const Duration(minutes: 1)),
        date: kstToday.subtract(const Duration(days: 2)),
        expect: '소급 요청 · 관리자 검토 후 처리'
      ),
    };
    for (final width in [320.0, 360.0, 411.0]) {
      for (final c in cases.entries) {
        testWidgets('RRM-B ${width.toInt()}dp · ${c.key} · 테스트 폰트(보수적)', (tester) async {
          await _pumpAt(
            tester,
            width,
            LongTermWorkManagementDialog(
              applications: [
                _longTermApp(id: 'A1', requestedAt: c.value.req, requestDate: c.value.date),
              ],
              onChanged: () {},
            ),
            bundledFont: false,
          );
          expect(tester.takeException(), isNull, reason: '넓은 폰트에서도 넘침 없음');
          expect(findVisibleTextContaining('퇴사 요청 (${c.value.expect})'), findsOneWidget);
        });
        testWidgets('RRM-B ${width.toInt()}dp · ${c.key}', (tester) async {
          await _pumpAt(
            tester,
            width,
            LongTermWorkManagementDialog(
              applications: [
                _longTermApp(id: 'A1', requestedAt: c.value.req, requestDate: c.value.date),
              ],
              onChanged: () {},
            ),
          );
          expect(tester.takeException(), isNull, reason: '넘침·예외 없음');
          final detail = findVisibleTextContaining('퇴사 요청 (${c.value.expect})');
          expect(detail, findsOneWidget);
          // [DU271] 보이는 글자 위 정규식 — 결합 문자 때문에 빈 단언이 되지 않게
          expect(find.byWidgetPredicate((w) => w is Text && RegExp(r'-\d+일').hasMatch(visibleText(w.data ?? ''))),
              findsNothing, reason: '음수 일수 금지');
          // ignore: avoid_print
          print('RRM-B ${width.toInt()}dp ${c.key}: ${_linesOf(tester, detail)}줄');
        });
      }
    }
  });

  // ══════════════════════════════════════════════════════════
  // RRM-C 관리자 두 다이얼로그 — 해당 줄 구조 복제(문자열은 production getter)
  // ══════════════════════════════════════════════════════════
  group('RRM-C 관리자 카드·배너 줄 구조 복제', () {
    final plans = <String, ResignAutoApproval>{
      '정상 3일': ResignAutoApproval.of(
          requestedAt: _kst(2026, 10, 22, 10), requestDate: _kst(2026, 10, 31), now: _now),
      '정상 오늘': ResignAutoApproval.of(
          requestedAt: _kst(2026, 10, 19, 10), requestDate: _kst(2026, 10, 31), now: _now),
      'D+3 이후': ResignAutoApproval.of(
          requestedAt: _kst(2026, 10, 12, 10), requestDate: _kst(2026, 10, 31), now: _now),
      '소급': ResignAutoApproval.of(
          requestedAt: _kst(2026, 10, 22, 10), requestDate: _kst(2026, 10, 20), now: _now),
    };
    for (final width in [320.0, 360.0, 411.0]) {
      for (final e in plans.entries) {
        testWidgets('RRM-C ${width.toInt()}dp · ${e.key}', (tester) async {
          await _pumpAt(tester, width, _adminCardReplica(e.value));
          expect(tester.takeException(), isNull);
          final card = find.byKey(const Key('admin-card-plan'));
          final cardLines = _linesOf(tester, card);
          await _pumpAt(tester, width, _adminBannerReplica(e.value));
          expect(tester.takeException(), isNull);
          final banner = find.byKey(const Key('admin-banner-plan'));
          final bannerLines = _linesOf(tester, banner);
          // ignore: avoid_print
          print('RRM-C ${width.toInt()}dp ${e.key}: 카드 $cardLines줄 · 배너 $bannerLines줄');
          expect(cardLines, lessThanOrEqualTo(2), reason: '카드 일정 줄은 두 줄 안');
          expect(bannerLines, lessThanOrEqualTo(2), reason: '배너는 두 줄 안');
        });
      }
    }
  });
}
