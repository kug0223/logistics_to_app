// ignore_for_file: depend_on_referenced_packages
// [DU347] S020 계약 확인 필요(ExpiringContractsScreen) — 소급 감사 8 §1 재개: reads seam(ExpiringContractsReads)으로 세 조회만 가짜로 준다.
//   판정(needsManagerRenewalAction) · 정렬 · 표시는 실제 화면이다. 오늘(KST) 기준 상대 날짜 자료(두 사업장 교차):
//     만료 2일 · D-Day · D-1(내일) · D-3 · D-4 · D-7 · D-8 · D-15(창 상한) · D-16(창 밖, 빠져야 함) · 대기 제안 D-5(빠져야 함) · 이름 없음 D-9.
//     D-3 은 두 표현으로 넣는다: 기기 로컬(모델 파서 `.toLocal()`) / UTC instant(같은 KST 자정).
//   날짜 단언(DU347_PHASE=before 이면 KNOWN 기록만): 행 라벨 · 날짜 글자(M/d(E), KST 날짜) · 칩 색 구간(≤3 error · 4–7 warning · ≥8 primary —
//     칩 바탕 12% · 글자 진한 짝 · 실바탕 대비 4.5) · 정렬(남은 날 오름차순, 사업장 교차) · 머리 인원(만료 1 · 곧 종료 8).
//   [N352-1 구조 적응] 화면이 이니셜 원 · 왼쪽 4px 막대를 빼고 기한 묶음 카드로 바뀌었다. 행 수집은 Text[1](이니셜 다음 글자) 대신
//     행 InkWell 의 ObjectKey(ApplicationModel) — 지원서 identity — 로, 막대 색의 의미(남은 날 구간)는 그 행 D-day 칩의 색 · 라벨 · 실바탕 대비로 옮겼다.
//     기대 이름 선필터 없이 방문한 모든 행 · 정확 10 · 중복 0 · 제외 2 · 정렬 · 날짜 · 머리 · 변이 · 전체 RichText 대비/낱말 · 회색 판정기 표본 ·
//     빈 목록 · 조회 실패 · outlined 48 · 넘침 · 예외 · 기본 strict(DU347_PHASE 미설정)는 그대로다.
//   [F122-1 보완] ID 로 모은 행마다 실제 표시 이름(_shownName — 이름 · 읽기 이름을 가진 첫 Text, 기대 이름으로 고르지 않음)을 함께 모아
//     expectIds 의 기대 이름과 정확 비교한다(목록: 날짜 단언 묶음 · 변이: 나타난 두 행). ID 수집 · 정확 집합 · 중복 · 정렬 · 제외는 그대로.
//   시각 단언(DU347_PHASE=before|date 이면 기록만): 가장 가까운 바탕 대비 · 공용 판정기 avoidable · 실패 '다시 시도' outlined 48.
//   넘침 · 예외는 항상 단언한다. W 392x844 1.0 / B 320x640 2.0 × {목록, 빈 목록, 조회 실패}.
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/screens/business_admin/expiring_contracts_reads.dart';
import 'package:ALfit/screens/business_admin/expiring_contracts_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';

import 'support/du1_vq_capture.dart';
import 'support/du_word_break.dart';
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

final String _phase = Platform.environment['DU347_PHASE'] ?? '';
bool get _dateStrict => _phase != 'before';
bool get _visualStrict => _phase != 'before' && _phase != 'date';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

Color _overWhite(Color c) => Color.alphaBlend(c, Colors.white);

/// [F122-1] 행의 **실제 표시 이름** — 행 안 Text 중 화면 읽기 이름(semanticsLabel)을 가진 첫 Text(트리 순서: 이름 → 사업장)의 보이는 글자.
///   기대 이름으로 고르지 않는다(선필터 0). 보이는 글자와 semanticsLabel 이 다르면 '보이는≠읽기' 로 돌려 정확 비교에서 드러낸다.
String _shownName(List<Element> paras) {
  for (final x in paras) {
    final w = x.widget as Text;
    final label = w.semanticsLabel;
    if (label == null) continue;
    final shown = visibleText(w.data ?? '');
    return shown == label ? shown : '$shown≠$label';
  }
  return '';
}

/// [DU352 시험 수정 — 소급 9] 실제 조상 알파 합성: 글자에서 위로 올라가며 반투명 면들을 모으고, 처음 만나는 불투명 면(없으면
///   테마 scaffold 바탕)을 밑에 깐 뒤 바깥 → 안쪽 순서로 합성한다. 예전 판정(반투명 면을 흰색 위로만 합성)은 4–7일 칩을
///   #FFF3E0 로 보고 4.78 로 통과시켰다(실제 #F7ECDC 위 4.49).
Color _bgOf(Element e) {
  final layers = <Color>[]; // 안쪽 → 바깥
  Color? base;
  // [DU352 시험 수리 2/3] Container 는 안에 DecoratedBox 를, CircleAvatar 는 AnimatedContainer → Container → DecoratedBox 를 만든다 —
  //   같은 면을 2~3번 합성해 바탕을 너무 어둡게 봤다(TB_try0 이니셜 #F5BEBC). 같은 색 값이 가까운 조상(4단계 안)에서
  //   이어 나오면 같은 면의 구현 중첩으로 보고 한 번만 센다.
  Color? lastColor;
  var depth = 0, lastDepth = -100;
  e.visitAncestorElements((a) {
    depth++;
    final w = a.widget;
    Color? c;
    if (w is ButtonStyleButton) {
      c = w.style?.backgroundColor?.resolve(w.enabled ? <WidgetState>{} : {WidgetState.disabled});
      if (c == null && w is ElevatedButton) c = Theme.of(a).colorScheme.primary;
    } else if (w is Container && w.decoration is BoxDecoration) {
      c = (w.decoration! as BoxDecoration).color;
    } else if (w is Container && w.color != null) {
      c = w.color;
    } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
      c = (w.decoration as BoxDecoration).color;
    } else if (w is CircleAvatar) {
      c = w.backgroundColor;
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color ?? Theme.of(a).colorScheme.surface;
    } else if (w is ColoredBox) {
      c = w.color;
    }
    if (c == null || c.a == 0) return true;
    if (lastColor != null && c.toARGB32() == lastColor!.toARGB32() && depth - lastDepth <= 4) {
      lastDepth = depth;
      return true; // 같은 면의 구현 중첩
    }
    lastColor = c;
    lastDepth = depth;
    if (c.a >= 1.0) {
      base = c;
      return false;
    }
    layers.add(c);
    return true;
  });
  var out = base ?? Theme.of(e).scaffoldBackgroundColor;
  for (final l in layers.reversed) {
    out = Color.alphaBlend(l, out);
  }
  return out;
}

// 모델 파서는 Timestamp 를 `.toLocal()` 로 준다 — 기본은 로컬 표현. utc=true 면 같은 KST 자정 instant 의 UTC 표현.
DateTime _kstMidnight(DateTime kstDate, {bool utc = false}) {
  final i = DateTime.utc(kstDate.year, kstDate.month, kstDate.day).subtract(const Duration(hours: 9));
  return utc ? i : i.toLocal();
}

ApplicationModel _app(String id, String biz, String uid, int endInDays, DateTime today, {bool utc = false}) => ApplicationModel(
    id: id, businessId: biz, businessName: biz == 'b1' ? '[QA] 아주 긴 이름의 골든패스 테스트 물류센터 사업장' : '강남 물류센터',
    toTitle: 'QA 장기', workDate: _kstMidnight(today.subtract(const Duration(days: 60))), startTime: '09:00', endTime: '18:00',
    uid: uid, selectedWorkType: 'QA 분류', wage: 12000, wageType: 'hourly', status: AppStatus.confirmed,
    appliedAt: _kstMidnight(today.subtract(const Duration(days: 70))), applicationType: AppType.longTerm,
    workEndDate: _kstMidnight(today.add(Duration(days: endInDays)), utc: utc));

BusinessModel _biz(String id, String name) => BusinessModel(
    id: id, name: name, ownerId: 'admin1', businessNumber: '000-00-00000',
    address: '서울시 어딘가', category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1));

UserModel _user(String uid, String name) =>
    UserModel(uid: uid, username: uid, name: name, email: '$uid@test.local', role: UserRole.USER);

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });

  final today = FormatHelper.toKstDate(DateTime.now()); // UTC 키(y/m/d 가 KST 오늘)
  final todayLocal = DateTime(today.year, today.month, today.day);
  // (이름, 사업장, 남은 날, utc 표현?) — 사업장 교차
  const rows = [
    ('만료둘', 'b1', -2, false),
    ('디데이', 'b2', 0, false),
    ('내일', 'b1', 1, false),
    ('셋로컬', 'b2', 3, false),
    ('셋유티시', 'b1', 3, true),
    ('넷', 'b2', 4, false),
    ('일곱', 'b1', 7, false),
    ('여덟', 'b2', 8, false),
    ('열다섯', 'b1', 15, false),
    ('열여섯', 'b2', 16, false), // 창 밖
    ('대기제안', 'b1', 5, false), // 대기 제안 — 빠진다
  ];
  final apps = <String, List<ApplicationModel>>{'b1': [], 'b2': []};
  final users = <String, UserModel>{};
  for (final r in rows) {
    apps[r.$2]!.add(_app('a-${r.$1}', r.$2, 'u-${r.$1}', r.$3, today, utc: r.$4));
    users['u-${r.$1}'] = _user('u-${r.$1}', r.$1);
  }
  apps['b2']!.add(_app('a-noname', 'b2', 'u-none', 9, today)); // 이름 조회 결과 없음
  RenewalProposalModel? proposal() => RenewalProposalModel.tryFromMap({
        'oldApplicationId': 'a-대기제안', 'businessId': 'b1', 'workerUid': 'u-대기제안', 'status': 'PENDING',
        'effectiveStart': {'_seconds': _kstMidnight(today.add(const Duration(days: 6))).millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0},
        'effectiveEnd': {'_seconds': _kstMidnight(today.add(const Duration(days: 96))).millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0},
      }, 'p1');

  ExpiringContractsReads reads({bool fail = false, bool empty = false}) => ExpiringContractsReads(
        expiringApplications: ({required businessId, required fromDate}) async {
          if (fail) throw StateError('expiring cf down');
          return empty ? <ApplicationModel>[] : apps[businessId] ?? [];
        },
        pendingRenewalProposals: (businessId) async {
          final p = proposal();
          return (businessId == 'b1' && p != null) ? [p] : [];
        },
        usersBatch: (uids, {required businessId}) async => {for (final u in uids) if (users[u] != null) u: users[u]!},
      );

  // 기대: 이름 → (남은 날)
  final expectDays = <String, int>{
    '만료둘': -2, '디데이': 0, '내일': 1, '셋로컬': 3, '셋유티시': 3, '넷': 4, '일곱': 7, '여덟': 8, '열다섯': 15, '알 수 없음': 9,
  };
  // [N352-1 구조 적응] 행 identity — 지원서 id → 기대 이름(고정 자료의 id 규칙 'a-<이름>' · 이름 조회 결과 없음 = 'a-noname').
  //   수집은 id 로 하고(기대 이름 선필터 0), 판정은 이 표로 기대 남은 날을 찾는다.
  final expectIds = <String, String>{for (final n in expectDays.keys) (n == '알 수 없음' ? 'a-noname' : 'a-$n'): n};
  String label(int d) => d < 0 ? '만료 ${-d}일' : (d == 0 ? 'D-Day' : 'D-$d');
  // [N352-1 구조 적응] 예전 막대 색의 의미(남은 날 구간 ≤3 error · 4–7 warning · ≥8 primary)를 그 행 D-day 칩으로 옮겼다 —
  //   칩 바탕 = 구간 색 12% · 칩 글자 = 진한 짝(errorDark · warningInk · brandDark). 대비는 실제 조상 바탕(_bgOf)으로 따로 본다.
  Color chipColor(int d, Color primary) => (d <= 3 ? AppColors.error : (d <= 7 ? AppColors.warning : primary)).withValues(alpha: 0.12);
  Color inkColor(int d) => d <= 3 ? AppColors.errorDark : (d <= 7 ? AppColors.warningInk : AppColors.brandDark);

  // [DU352] 판정기 독립 기대값(소급 9): 회색 바탕 #F6F7FA 위 반투명 칩 바탕과 글자 대비를 손으로 계산한 값과 맞춘다.
  test('S020 판정기 표본 — 회색 바탕 위 주황 · brand 칩', () {
    const listBg = Color(0xFFF6F7FA);
    final orangeChip = Color.alphaBlend(AppColors.warning.withValues(alpha: 0.12), listBg);
    final brandChip = Color.alphaBlend(AppColors.brand.withValues(alpha: 0.12), listBg);
    // ignore: avoid_print
    print('표본 orangeChip=0x${orangeChip.toARGB32().toRadixString(16)} warningDark=${_contrast(AppColors.warningDark, orangeChip).toStringAsFixed(4)} '
        'warningInk=${_contrast(AppColors.warningInk, orangeChip).toStringAsFixed(4)} brandChip=0x${brandChip.toARGB32().toRadixString(16)} '
        'brandDark=${_contrast(AppColors.brandDark, brandChip).toStringAsFixed(4)}');
    expect(orangeChip.toARGB32() & 0xFFFFFF, closeTo(0xF7ECDC, 0x020202), reason: '주황 12% over #F6F7FA ≈ #F7ECDC');
    // [DU352 시험 수리 2/3] 소급 9 값 4.4896 과 이 식(sRGB 문턱 0.03928)의 4.4788 은 반올림 차이 — 둘 다 4.5 미만이라는 사실을 단언한다.
    expect(_contrast(AppColors.warningDark, orangeChip), allOf(greaterThan(4.47), lessThan(4.5)), reason: 'warningDark 는 실제 바탕 4.5 미만(소급 9)');
    expect(_contrast(AppColors.warningInk, orangeChip), greaterThan(5.5), reason: 'warningInk 은 여유 있게 4.5 위');
    expect(_contrast(AppColors.brandDark, brandChip), closeTo(6.04, 0.05), reason: 'brandDark 실제 바탕 6.04(소급 9 계산)');
  });

  // [DU352] 제외 검사가 자명한 참이 아님을 보이는 고정 자료 변이(제품 무변경): 대기 제안을 비우고 16일 행을 15일로 옮기면
  //   두 행이 목록에 '보여야' 한다 — 수집기가 실제 방문 행 전체를 보고 있다는 증거.
  testWidgets('S020 제외 검사 변이 — 대기 제안 없음 · 16일 → 15일이면 두 행이 나타난다', (t) async {
    await t.runAsync(vqLoadFonts);
    t.view.physicalSize = const Size(392, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final mutApps = <String, List<ApplicationModel>>{
      'b1': [for (final a in apps['b1']!) a],
      'b2': [for (final a in apps['b2']!) if (a.id != 'a-열여섯') a, _app('a-열여섯', 'b2', 'u-열여섯', 15, today)],
    };
    final mutReads = ExpiringContractsReads(
      expiringApplications: ({required businessId, required fromDate}) async => mutApps[businessId] ?? [],
      pendingRenewalProposals: (businessId) async => [],
      usersBatch: (uids, {required businessId}) async => {for (final u in uids) if (users[u] != null) u: users[u]!},
    );
    await t.pumpWidget(ChangeNotifierProvider<NotificationProvider>(
      create: (_) => NotificationProvider(),
      child: MaterialApp(
        theme: RoleTheme.businessAdminTheme,
        home: ExpiringContractsScreen(
          businessIds: const ['b1', 'b2'],
          businesses: [_biz('b1', '[QA] 아주 긴 이름의 골든패스 테스트 물류센터 사업장'), _biz('b2', '강남 물류센터')],
          reads: mutReads,
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final listScroll = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    final pos = t.state<ScrollableState>(listScroll).position;
    // [N352-1 구조 적응] 행 식별 = 행 InkWell 의 ObjectKey(ApplicationModel) — 지원서 id(예전 Text[1] = 이니셜 다음 글자).
    //   방문한 모든 행을 센다. 키 없는 행은 따로 세어 0 이어야 수집이 참이다.
    final ids = <String>{};
    // [F122-1] ID 별 실제 표시 이름(처음 방문 때 값) — 키로 모은 행마다 그 행의 이름 글자를 따로 적는다.
    final shownById = <String, String>{};
    var unkeyed = 0;
    void visit() {
      for (final e in find.descendant(of: find.byType(ListView), matching: find.byType(InkWell)).evaluate()) {
        final k = e.widget.key;
        final app = k is ObjectKey ? k.value : null;
        if (app is ApplicationModel) {
          ids.add(app.id);
          shownById.putIfAbsent(app.id,
              () => _shownName(find.descendant(of: find.byElementPredicate((x) => identical(x, e)), matching: find.byType(Text), skipOffstage: false)
                  .evaluate()
                  .toList()));
        } else {
          unkeyed++;
        }
      }
    }
    visit();
    var guard = 0;
    while (pos.pixels < pos.maxScrollExtent - 0.5 && guard++ < 40) {
      pos.jumpTo(math.min(pos.pixels + 422, pos.maxScrollExtent));
      await t.pump(const Duration(milliseconds: 50));
      visit();
    }
    // ignore: avoid_print
    print('S020 변이 행 id=$ids 키 없음=$unkeyed 표시=$shownById');
    expect(unkeyed, 0, reason: '행 식별 키 없는 행(수집기 무효)');
    expect(ids, contains('a-대기제안'), reason: '대기 제안이 없으면 그 행이 보여야 한다(수집기 유효)');
    expect(ids, contains('a-열여섯'), reason: '15일로 옮기면 그 행이 보여야 한다(수집기 유효)');
    expect(shownById['a-대기제안'], '대기제안', reason: '[F122-1] 그 행의 실제 표시 이름(정확)');
    expect(shownById['a-열여섯'], '열여섯', reason: '[F122-1] 그 행의 실제 표시 이름(정확)');
    await t.pumpWidget(const SizedBox.shrink());
  });

  for (final c in const [(id: 'S020-W', w: 392.0, h: 844.0, s: 1.0), (id: 'S020-B', w: 320.0, h: 640.0, s: 2.0)]) {
    for (final st in const ['list', 'empty', 'error']) {
      testWidgets('${c.id} 계약 확인 필요 $st ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
        await t.runAsync(vqLoadFonts);
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
        try {
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          final key = GlobalKey();
          void out(String l) {
            // ignore: avoid_print
            print(l);
          }

          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: ChangeNotifierProvider<NotificationProvider>(
              create: (_) => NotificationProvider(),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.businessAdminTheme,
                builder: (ctx, child) =>
                    MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
                home: ExpiringContractsScreen(
                  businessIds: const ['b1', 'b2'],
                  businesses: [_biz('b1', '[QA] 아주 긴 이름의 골든패스 테스트 물류센터 사업장'), _biz('b2', '강남 물류센터')],
                  reads: reads(fail: st == 'error', empty: st == 'empty'),
                ),
              ),
            ),
          ));
          for (var i = 0; i < 10; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          expect(t.takeException(), isNull);
          final primary = Theme.of(t.element(find.byType(ExpiringContractsScreen))).primaryColor;
          var avoid = 0, low = 0;
          final seen = <String>{};
          void dump(String tag) {
            for (final e in find.byType(RichText).evaluate()) {
              final rp = e.renderObject! as RenderParagraph;
              final s = visibleText(rp.text.toPlainText());
              if (s.isEmpty) continue;
              final self = find.byElementPredicate((x) => identical(x, e));
              final r = t.getRect(self);
              if (r.bottom < 0 || r.top > c.h || r.width == 0) continue;
              if (find.ancestor(of: self, matching: find.byType(Icon)).evaluate().isNotEmpty) continue;
              final col = rp.text.style?.color;
              final bg = _bgOf(e);
              final k = '$tag|${r.top.round()}|$s@${bg.toARGB32()}@${col?.toARGB32()}';
              if (seen.contains(k)) continue;
              seen.add(k);
              for (final b in wordBreaks(rp)) {
                if (!b.forced) {
                  avoid++;
                  out('$tag avoidable $b');
                }
              }
              final cst = col == null ? 99.0 : _contrast(_overWhite(col), bg);
              if (cst < 4.5) {
                low++;
                out('$tag low "$s" color=0x${col?.toARGB32().toRadixString(16)} bg=0x${bg.toARGB32().toRadixString(16)} contrast=${cst.toStringAsFixed(2)}');
              }
            }
          }

          final tag = '${c.id}_$st';
          if (st == 'list') {
            // 날짜 — 목록 전체를 반 화면씩 내리며 행마다 identity · 라벨 · 날짜 글자 · 칩 색 · 위치를 모은다
            final listScroll = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
            final pos = t.state<ScrollableState>(listScroll).position;
            // [F122-1] name = 그 행의 실제 표시 이름(_shownName — 기대 이름으로 고르지 않는다).
            final got = <String, ({String name, String label, String date, Color? chip, Color? ink, double cr, double y})>{};
            // [DU352 시험 수정 — 소급 9] 제외 검사가 자명한 참이 되지 않게, 기대 이름이 아니라 실제 방문한 **모든 행**의
            //   identity · 절대 위치를 모은다. 정확 10행 집합 · 중복 0 · 제외 2 부재를 따로 단언한다.
            // [N352-1 구조 적응] identity = 행 InkWell 의 ObjectKey(ApplicationModel) — 지원서 id(예전 Text[1] = 이니셜 다음 글자).
            //   키 없는 행은 '?<순번>' 으로 남겨 정확 집합 단언에서 드러낸다(조용히 빼지 않는다).
            final allRows = <String, Set<int>>{};
            void collect() {
              for (final e in find.descendant(of: find.byType(ListView), matching: find.byType(InkWell)).evaluate()) {
                final row = find.byElementPredicate((x) => identical(x, e));
                final paras = find.descendant(of: row, matching: find.byType(Text)).evaluate().toList();
                final texts = paras.map((x) => visibleText((x.widget as Text).data ?? '')).toList();
                if (texts.isEmpty) continue;
                final k = e.widget.key;
                final app = k is ObjectKey ? k.value : null;
                final id = app is ApplicationModel ? app.id : '?${allRows.length}';
                final y = t.getRect(row).top + pos.pixels;
                allRows.putIfAbsent(id, () => <int>{}).add(y.round());
                if (got.containsKey(id)) continue;
                final li = texts.indexWhere((s) => s.startsWith('D-') || s.startsWith('만료 '));
                final lab = li < 0 ? '' : texts[li];
                final date = texts.firstWhere((s) => RegExp(r'^\d{1,2}/\d{1,2}\(').hasMatch(s), orElse: () => '');
                // [N352-1 구조 적응] 막대 대신 그 행 D-day 칩 — 칩 바탕(라벨에서 가장 가까운 칠한 Container) · 칩 글자색 ·
                //   실바탕 대비(전체 글자 판정과 같은 _bgOf · _overWhite).
                Color? chip;
                Color? ink;
                var cr = 0.0;
                if (li >= 0) {
                  final le = paras[li];
                  ink = (le.widget as Text).style?.color;
                  le.visitAncestorElements((a) {
                    final w = a.widget;
                    final d = w is Container ? w.decoration : null;
                    if (d is BoxDecoration && d.color != null) {
                      chip = d.color;
                      return false;
                    }
                    return true;
                  });
                  final rts = find.descendant(of: find.byElementPredicate((x) => identical(x, le)), matching: find.byType(RichText)).evaluate();
                  final fg = ink;
                  if (fg != null && rts.isNotEmpty) cr = _contrast(_overWhite(fg), _bgOf(rts.first));
                }
                got[id] = (name: _shownName(paras), label: lab, date: date, chip: chip, ink: ink, cr: cr, y: y);
              }
            }

            collect();
            dump(tag);
            await vqCapture(t, key, '${tag}_1_top', conditions: {'state': '목록 위', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
            var guard = 0;
            while (pos.pixels < pos.maxScrollExtent - 0.5 && guard++ < 40) {
              pos.jumpTo(math.min(pos.pixels + c.h * 0.5, pos.maxScrollExtent));
              await t.pump(const Duration(milliseconds: 50));
              collect();
              dump('${tag}_walk');
            }
            await vqCapture(t, key, '${tag}_2_end', conditions: {'state': '목록 끝', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
            final header = find.byWidgetPredicate((w) => w is Text && visibleText(w.data ?? '').contains('결정 필요')).evaluate()
                .map((e) => visibleText((e.widget as Text).data ?? '')).toList();
            // 날짜 판정
            var dateNg = 0;
            var chipLow = 0;
            var nameNg = 0;
            final fmt = DateFormat('M/d(E)', 'ko_KR');
            for (final en in expectIds.entries) {
              final days = expectDays[en.value]!;
              final g = got[en.key];
              // [F122-1] ID 별 실제 표시 이름 = expectIds 의 기대 이름(정확 일치 — 다른 이름 · 빈 이름 · 보이는/읽기 불일치 모두 NG).
              final nameOk = g != null && g.name == en.value;
              if (!nameOk) nameNg++;
              out('$tag name ${en.key}: shown=${g?.name} want=${en.value} ${nameOk ? 'ok' : 'NG'}');
              final want = label(days);
              final wantDate = fmt.format(todayLocal.add(Duration(days: days)));
              final wantChip = chipColor(days, primary);
              final wantInk = inkColor(days);
              final chipOk = g != null && g.chip == wantChip && g.ink == wantInk;
              final ok = g != null && g.label == want && g.date == wantDate && chipOk;
              if (!ok) dateNg++;
              if (g == null || g.cr < 4.5) chipLow++;
              out('$tag row ${en.value}(${en.key}): label=${g?.label} want=$want date=${g?.date} want=$wantDate '
                  'chip=${chipOk ? 'ok' : 'NG(${g?.chip} ${g?.ink})'} cr=${g?.cr.toStringAsFixed(2)} ${ok ? 'ok' : 'NG'}');
            }
            // [DU352] 실제 방문 행 전체로 판정: 정확히 기대 10행, 같은 행 다른 위치(중복) 0, 제외 2 부재
            final rowIds = allRows.keys.toSet();
            final dupRows = allRows.entries.where((en) => en.value.length > 1).map((en) => en.key).toList();
            final exactSet = rowIds.length == expectIds.length && rowIds.containsAll(expectIds.keys);
            out('$tag allRows=${rowIds.toList()} dup=$dupRows exactSet=$exactSet');
            final excluded = exactSet && dupRows.isEmpty && !rowIds.contains('a-열여섯') && !rowIds.contains('a-대기제안');
            final order = got.entries.toList()..sort((a, b) => a.value.y.compareTo(b.value.y));
            final orderDays = order.map((e) => expectDays[expectIds[e.key]] ?? 99).toList();
            var sorted = true;
            for (var i = 1; i < orderDays.length; i++) {
              if (orderDays[i] < orderDays[i - 1]) sorted = false;
            }
            final headerOk = header.isNotEmpty && header.first == '만료 · 결정 필요 1명 · 곧 종료 9명';
            out('$tag order=${order.map((e) => e.key).toList()} days=$orderDays sorted=$sorted excluded=$excluded header=$header');
            out('KNOWN ${dateNg == 0 && sorted && excluded && headerOk ? 'ok' : 'NG'} $tag 날짜(라벨 · 날짜 글자 · 칩 색 · 정렬 · 제외 · 머리) NG=$dateNg sorted=$sorted excluded=$excluded headerOk=$headerOk');
            out('KNOWN ${chipLow == 0 ? 'ok' : 'NG'} $tag 칩 실바탕 대비 4.5 미달 $chipLow');
            final shownAll = {for (final en in got.entries) en.key: en.value.name};
            out('KNOWN ${nameNg == 0 ? 'ok' : 'NG'} $tag [F122-1] ID 별 표시 이름 불일치 $nameNg 방문 표시=$shownAll');
            if (_dateStrict) {
              expect(nameNg, 0, reason: '$tag [F122-1] ID 별 실제 표시 이름 = 기대 이름(정확)');
              expect(dateNg, 0, reason: '$tag 행 라벨 · 날짜 글자 · 칩 색');
              expect(sorted, isTrue, reason: '$tag 남은 날 오름차순(사업장 교차)');
              expect(excluded, isTrue, reason: '$tag 창 밖 · 대기 제안 제외');
              expect(headerOk, isTrue, reason: '$tag 머리 인원');
            }
            if (_visualStrict) {
              expect(chipLow, 0, reason: '$tag 칩 실바탕 대비(예전 막대 색 의미)');
            }
          } else if (st == 'empty') {
            dump(tag);
            await vqCapture(t, key, '${tag}_3_empty', conditions: {'state': '빈 목록', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
          } else {
            dump(tag);
            final retry = findVisibleText('다시 시도');
            expect(retry, findsOneWidget, reason: '$tag 실패 다시 시도');
            final btn = find.ancestor(of: retry, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
            final isOutlined = t.widget(btn) is OutlinedButton;
            final h = t.getRect(btn).height;
            out('$tag retry type=${t.widget(btn).runtimeType} h=${h.toStringAsFixed(1)}');
            out('KNOWN ${isOutlined && h >= 48 - 1e-6 ? 'ok' : 'NG'} $tag 실패 본문 outlined 다시 시도 48');
            if (_visualStrict) {
              expect(isOutlined, isTrue, reason: '$tag 실패 본문 outlined(소급 5 일관 방향)');
              expect(h, greaterThanOrEqualTo(48 - 1e-6));
            }
            await vqCapture(t, key, '${tag}_4_error', conditions: {'state': '조회 실패', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
          }
          expect(t.takeException(), isNull);
          out('$tag summary overflows=${overflows.length} avoidable=$avoid low=$low phase=$_phase');
          out('KNOWN ${avoid == 0 && low == 0 ? 'ok' : 'NG'} $tag 시각(끊김 $avoid · 대비 $low)');
          expect(overflows, isEmpty, reason: '$tag 넘침');
          if (_visualStrict) {
            expect(avoid, 0, reason: '$tag 피할 수 있는 끊김');
            expect(low, 0, reason: '$tag 대비 미달');
          }
          await t.pumpWidget(const SizedBox.shrink());
        } finally {
          FlutterError.onError = prev;
        }
      });
    }
  }
}
