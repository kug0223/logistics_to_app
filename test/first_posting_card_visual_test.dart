// [R7-P4.4E.4] Home 첫 공고 준비 카드 — 시각 정리.
//
//   기능·정책·네비게이션은 건드리지 않았다. 바뀐 것은 네 가지다:
//     ① 헤더의 `2 / 4 완료` 제거 — 제목이 이미 같은 사실을 말한다
//     ② 미완료 행의 chevron 하나만 brand blue — 지금 할 수 있는 일로 읽히게
//     ③ 설명문 색을 비활성 톤(grey400)에서 보조 톤으로
//     ④ leading 아이콘을 고정 폭 grid 에 맞춤
//
//   이 파일은 **실제로 그려서** 본다 — 줄바꿈·넘침은 소스를 읽어서 알 수 없다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/ui/admin_home_summary_model.dart';
import 'package:ALfit/models/ui/staffing_readiness_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/screens/business_admin/admin_home_reads.dart';
import 'package:ALfit/screens/business_admin/business_admin_home_screen.dart';
import 'package:ALfit/theme/app_colors.dart';

// ── Firebase 가짜 코어 ────────────────────────────────────────
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

class _FakeApp extends FirebaseAppPlatform {
  _FakeApp()
      : super(
            defaultFirebaseAppName,
            const FirebaseOptions(
                apiKey: 'k',
                appId: 'a',
                messagingSenderId: 's',
                projectId: 'p'));
}

class _AdminProvider extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'admin1',
        username: 'admin1',
        name: '김관리',
        email: 'admin1@alfit.local',
        role: UserRole.BUSINESS_ADMIN,
        managedBusinessIds: const ['biz1'],
        createdAt: DateTime(2026, 1, 1),
      );
}

class _Template extends Fake implements ContractTemplateModel {
  @override
  bool get isSupportedForNewUse => true;
}

BusinessModel _biz() => BusinessModel(
      id: 'biz1',
      name: '테스트 사업장',
      ownerId: 'admin1',
      businessNumber: '000-00-00000',
      address: '서울시 어딘가',
      category: '물류',
      subCategory: '창고',
      isApproved: true,
      createdAt: DateTime(2026, 1, 1),
    );

/// 준비 축을 원하는 조합으로 만든다 — 1/4 ~ 4/4 를 그릴 수 있어야 한다.
AdminHomeReads _reads({
  bool workTypes = false,
  bool template = false,
  bool seal = false,
}) {
  return AdminHomeReads(
    summary: ({String? selectedBusinessId}) async =>
        AdminHomeSummaryModel.fromMap(const {'actions': {}, 'upcoming': {}}),
    businessesByIds: (ids) async => [_biz()],
    staffingReadiness: ({String? selectedBusinessId}) async =>
        StaffingReadinessModel(available: true, days: const []),
    attendanceByDate:
        ({required String businessId, required DateTime date}) async => const [],
    confirmedWorkers:
        ({required DateTime date, required String businessId}) async => const [],
    workDetailTimes: (_) async => <String, dynamic>{},
    postingReadiness: (bizs) async => {
      for (final b in bizs)
        b.id: BusinessPostingReadiness(
          bizId: b.id,
          isApproved: true,
          hasCanonicalLicense: true,
          hasOwnerLegacyLicense: false,
          hasActiveWorkTypes: workTypes,
          hasEmployerSeal: seal,
        ),
    },
    contractTemplates: (_) async => template
        ? <ContractTemplateModel>[_Template()]
        : <ContractTemplateModel>[],
    tourCompleted: () async => true,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required AdminHomeReads reads,
  Size size = const Size(390, 1800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _AdminProvider()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(home: BusinessAdminHomeScreen(reads: reads)),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  group('[R7-P4.4E.4] 카드 구조 — 바뀌지 않은 것', () {
    testWidgets('CARD-UI-01 네 단계가 그 순서로 있다', (tester) async {
      await _pump(tester, reads: _reads());
      final labels = ['사업장 등록', '업무 등록', '계약서 템플릿', '인감/서명'];
      final ys = <double>[];
      for (final l in labels) {
        expect(find.text(l), findsOneWidget, reason: '$l 이 사라졌다');
        ys.add(tester.getTopLeft(find.text(l)).dy);
      }
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]),
            reason: '완료됐다고 순서를 바꾸지 않는다');
      }
    });

    testWidgets('CARD-UI-02 완료는 초록 체크, 미완료는 그렇지 않다', (tester) async {
      // 사업장만 완료(1/4).
      await _pump(tester, reads: _reads());
      final checks = tester.widgetList<Icon>(find.byIcon(Icons.check_circle));
      expect(checks.length, 1, reason: '완료 한 칸만 체크다');
      expect(checks.first.color, AppColors.success);
    });

    testWidgets('CARD-UI-03 미완료 행 전체가 눌린다', (tester) async {
      await _pump(tester, reads: _reads());
      // 라벨을 감싸는 InkWell 이 있어야 한다 — chevron 만 누르게 바꾸지 않았다.
      final ink = find.ancestor(
        of: find.text('업무 등록'),
        matching: find.byType(InkWell),
      );
      expect(ink, findsWidgets);
      final w = tester.widgetList<InkWell>(ink).first;
      expect(w.onTap, isNotNull, reason: '행 전체가 tappable 이어야 한다');
    });
  });

  group('[R7-P4.4E.4] 바뀐 것', () {
    testWidgets('CARD-UI-08 헤더가 같은 사실을 두 번 말하지 않는다', (tester) async {
      await _pump(tester, reads: _reads());
      expect(find.text('공고 등록까지 3단계 남았어요'), findsOneWidget);
      expect(find.textContaining('/ 4 완료'), findsNothing,
          reason: '제목이 이미 말한 것을 같은 무게로 반복하지 않는다');
    });

    testWidgets('CARD-UI-04 설명문이 비활성 톤이 아니다', (tester) async {
      await _pump(tester, reads: _reads());
      final t = tester.widget<Text>(
          find.text('한 번 만들면 이후 계약에도 계속 사용할 수 있어요'));
      expect(t.style?.color, AppColors.textSecondary);
      expect(t.style?.color, isNot(AppColors.grey400),
          reason: 'grey400 은 이 화면에서 꺼진 항목의 톤이다');
    });

    testWidgets('CARD-UI-10 지금 할 수 있는 행동만 파랗다', (tester) async {
      await _pump(tester, reads: _reads());
      final chevrons =
          tester.widgetList<Icon>(find.byIcon(Icons.chevron_right)).toList();
      expect(chevrons, isNotEmpty);
      for (final c in chevrons) {
        expect(c.color, AppColors.info, reason: '미완료 행의 chevron 은 brand blue');
      }
      // 완료 체크는 여전히 초록 — 행동과 경쟁하지 않는다.
      final checks =
          tester.widgetList<Icon>(find.byIcon(Icons.check_circle)).toList();
      for (final c in checks) {
        expect(c.color, AppColors.success);
      }
    });
  });

  group('[R7-P4.4E.4] 좁은 화면에서 깨지지 않는다', () {
    for (final w in const [320.0, 360.0, 411.0]) {
      testWidgets('CARD-UI-0${w == 320.0 ? 5 : (w == 360.0 ? 6 : 7)} '
          '${w.toInt()}dp 넘침 없음', (tester) async {
        await _pump(tester, reads: _reads(), size: Size(w, 1800));
        expect(tester.takeException(), isNull);
        expect(find.text('공고 등록까지 3단계 남았어요'), findsOneWidget);
        expect(find.text('계약서 템플릿'), findsOneWidget);
      });
    }

    // 상태마다 **새 test** 다 — 한 test 안에서 pumpWidget 을 반복하면
    //   같은 State 가 재사용되고, `reads` 가 `late final` 이라 첫 주입이
    //   끝까지 고정된다(두 번째 fixture 가 적용되지 않는다).
    testWidgets('CARD-UI-09a 2/4 에서 레이아웃이 선다', (tester) async {
      await _pump(tester,
          reads: _reads(workTypes: true), size: const Size(320, 1800));
      expect(tester.takeException(), isNull);
      expect(find.text('공고 등록까지 2단계 남았어요'), findsOneWidget);
    });

    testWidgets('CARD-UI-09b 3/4 에서 레이아웃이 선다', (tester) async {
      await _pump(tester,
          reads: _reads(workTypes: true, template: true),
          size: const Size(320, 1800));
      expect(tester.takeException(), isNull);
      expect(find.text('공고 등록까지 1단계 남았어요'), findsOneWidget);
    });

    testWidgets('CARD-UI-09c 4/4 면 카드가 사라진다', (tester) async {
      await _pump(tester,
          reads: _reads(workTypes: true, template: true, seal: true),
          size: const Size(320, 1800));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('공고 등록까지'), findsNothing,
          reason: '준비가 끝나면 할 말이 없다 — 기존 동작 유지');
    });
  });
}
