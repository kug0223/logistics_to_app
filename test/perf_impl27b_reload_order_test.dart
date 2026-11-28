// [PERF impl_27b · L48 같은 꼴 · 2026-11-27] 나머지 화면 — 처리 뒤 다시 읽기의 명단 유지(잠금) · 버리던 다시 읽기 · 읽기 차례.
//
//   BL  내 사업장 관리(_loadBusinesses) — 읽는 중의 다시 읽기를 버리지 않는다(예전: return → 처리 전 목록이 앉음) ·
//       다시 읽는 중 목록 유지·잠금 · 동치
//   SRC 같은 꼴 배선(소스) — 업무 유형 · 마감 필요 · 계약서 템플릿 · 연장 제안 · 멤버 관리 · 통계 근태 · 근무자 서류 검토 ·
//       지원 상태 새로고침 · 내 지원 변경 제안
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/business_member_model.dart' show MemberPermissions;
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_list_reads.dart';
import 'package:ALfit/screens/business_admin/business_list_screen.dart';

import 'support/visible_text.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options =>
      const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _Owner extends UserProvider {
  _Owner(this.ids);
  final List<String> ids;
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1', username: 'u1', name: '김사장', email: 'u1@x.local', role: UserRole.BUSINESS_ADMIN,
        managedBusinessIds: ids,
      );
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => true;
  @override
  String? get effectiveBusinessId => null;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  bool can(bool Function(MemberPermissions p) c) => true;
  @override
  bool canForBusiness(String b, bool Function(MemberPermissions p) c) => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
}

BusinessModel _biz(String id, String name) => BusinessModel(
      id: id, businessNumber: '000-00-00000', name: name, category: '물류', subCategory: '창고',
      address: '서울특별시 강남구 테헤란로 152', ownerId: 'u1', isApproved: true, createdAt: DateTime(2026, 10, 1),
    );

class _BizReads {
  List<BusinessModel> data;
  _BizReads(this.data);
  final gates = <Completer<void>>[];
  bool holdNext = false;
  int calls = 0;
  BusinessListReads build() => BusinessListReads(
        businessById: (_) async => data.first,
        businessesByIds: (_) async {
          calls++;
          final snap = [...data];
          if (holdNext) {
            holdNext = false;
            final g = Completer<void>();
            gates.add(g);
            await g.future;
          }
          return snap;
        },
      );
}

Future<void> _settle(WidgetTester t, [int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

String _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => visibleText(w.data ?? w.textSpan?.toPlainText() ?? ''))
    .where((s) => s.isNotEmpty)
    .join(' | ');

bool _spinner(WidgetTester t) =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == 'LoadingWidget').evaluate().isNotEmpty;

Future<void> _pumpBl(WidgetTester t, _BizReads r, {bool settle = true}) async {
  t.view.physicalSize = const Size(411, 2000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _Owner(['b1', 'b2'])),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(home: BusinessListScreen(key: UniqueKey(), reads: r.build())),
  ));
  if (settle) await _settle(t);
}

String _src(String p) => File(p).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  group('BL 내 사업장 관리', () {
    testWidgets('BL1 다시 읽는 중 목록 유지·진행 표시·잠금 → 새 목록 · 동치', (t) async {
      final r = _BizReads([_biz('b1', '강남 물류센터'), _biz('b2', '성수 창고')]);
      await _pumpBl(t, r);
      expect(_texts(t), contains('성수 창고'));
      r.holdNext = true;
      r.data = [_biz('b1', '강남 물류센터')];
      await t.tap(find.byIcon(Icons.refresh_rounded));
      await t.pump(const Duration(milliseconds: 100));
      expect(_spinner(t), isFalse, reason: '다시 읽기가 목록을 지우고 스피너를 띄웠다');
      expect(find.byKey(const ValueKey('business-list-refresh-after-mutation')), findsOneWidget);
      expect(_texts(t), contains('성수 창고'));
      final absorbing = t
          .widgetList<AbsorbPointer>(find.ancestor(
              of: findVisibleText('성수 창고').first, matching: find.byType(AbsorbPointer)))
          .any((w) => w.absorbing);
      expect(absorbing, isTrue);
      r.gates.single.complete();
      await _settle(t);
      final via = _texts(t);
      expect(via, isNot(contains('성수 창고')));
      expect(find.byKey(const ValueKey('business-list-refresh-after-mutation')), findsNothing);
      await _pumpBl(t, _BizReads([_biz('b1', '강남 물류센터')]));
      expect(_texts(t), via, reason: '다시 읽은 최종 화면이 새로 연 화면과 다르다');
    });

    testWidgets('BL2 읽는 중 들어온 다시 읽기를 버리지 않는다 — 처리 전에 출발한 조회가 앉아도 한 번 더 읽어 최신으로', (t) async {
      final r = _BizReads([_biz('b1', '강남 물류센터'), _biz('b2', '성수 창고')]);
      await _pumpBl(t, r);
      r.holdNext = true; // 진행 중 조회(처리 전 목록 둘)
      await t.tap(find.byIcon(Icons.refresh_rounded));
      await t.pump(const Duration(milliseconds: 50));
      r.data = [_biz('b1', '강남 물류센터')]; // 처리(사업장 정리) 뒤
      await t.tap(find.byIcon(Icons.refresh_rounded), warnIfMissed: false); // 처리 뒤 다시 읽기 요청
      await t.pump(const Duration(milliseconds: 50));
      r.gates.single.complete();
      await _settle(t);
      expect(r.calls, 3, reason: '진행 중이라는 이유로 처리 뒤 다시 읽기를 버렸다');
      expect(_texts(t), isNot(contains('성수 창고')), reason: '처리 전에 출발한 조회가 최종 화면으로 남았다');
      expect(find.byKey(const ValueKey('business-list-refresh-after-mutation')), findsNothing);
    });
  });

  group('SRC 같은 꼴 배선', () {
    test('SRC1 업무 유형 — 읽는 중 요청은 끝난 뒤 한 번 더 · 첫 읽기 뒤 목록 유지 잠금', () {
      final s = _src('lib/screens/business_admin/work_type_management_screen.dart');
      expect(s, contains('_reloadAgain = true;'));
      expect(s, contains('unawaited(_loadWorkTypes());'));
      expect(s, contains('_hasLoadedOnce = true;'));
      expect(s, contains('body: _isLoading && !_hasLoadedOnce'));
      expect(s, contains('absorbing: _isLoading,'));
      expect(s.contains('if (_fetchInProgress) return;'), isFalse, reason: '진행 중 요청을 버리는 꼴이 남았다');
    });

    test('SRC2 마감 필요 — 차례 확인 뒤에만 앉고 첫 읽기 뒤 목록 유지 잠금 · 겹친 읽기 잠금은 마지막이 끝날 때만', () {
      final s = _src('lib/screens/business_admin/unclosed_action_queue_screen.dart');
      expect(s, contains('final gen = ++_loadGen;'));
      expect(s, contains('if (!mounted || gen != _loadGen) return;'));
      expect(s, contains(': isLoading && !_hasLoadedOnce'));
      expect(s, contains('absorbing: _reloadingKeepRows'));
      expect(s, contains('if (_loadsInFlight > 0) return;'));
    });

    test('SRC3 계약서 템플릿 — 읽는 중 요청을 버리지 않고 끝난 뒤 한 번 더 · 옛 결과·옛 실패를 앉히지 않음', () {
      final s = _src('lib/screens/business_admin/contract_template_list_screen.dart');
      expect(s, contains('_reloadAgain = true;'));
      expect(s, contains('if (_reloadAgain) return;'));
      expect(s, contains('if (mounted && !_reloadAgain) {'));
      expect(s, contains('unawaited(_load());'));
      expect(s.contains('if (!mounted || _loading) return;'), isFalse);
    });

    test('SRC4 연장 제안 · 통계 근태 · 근무자 서류 검토 · 내 지원 변경 제안 — 마지막 읽기만 앉는다', () {
      final rp = _src('lib/screens/user/renewal_proposal_screen.dart');
      expect('gen != _loadGen'.allMatches(rp).length, 2, reason: '성공·실패 둘 다 차례 확인');
      final sal = _src('lib/screens/business_admin/stats_attendance_list_screen.dart');
      expect(sal, contains('if (!mounted || gen != _reloadGen) return;'));
      final wdd = _src('lib/widgets/dialogs/worker_detail_dialog.dart');
      expect('gen != _docReviewGen'.allMatches(wdd).length, 2, reason: '승인 열림 근거 — 성공·실패 둘 다');
      final mya = _src('lib/screens/user/my_applications_screen.dart');
      expect(mya, contains('if (!mounted || gen != _proposalsGen) return;'));
    });

    test('SRC5 멤버 관리 — 전체 읽기 중의 요청(전체·사업장 하나)을 버리지 않음 · 사업장별 차례', () {
      final s = _src('lib/screens/business_admin/member_management_screen.dart');
      expect('_reloadAgain = true;'.allMatches(s).length, 2, reason: '_load 와 _reloadSection 둘 다');
      expect(s, contains('if (!mounted || _loading || _sectionGen[businessId] != g) return;'));
      expect(s, contains('unawaited(_load());'));
    });

    test('SRC6 지원 상태 새로고침 — 날짜별 차례', () {
      final s = _src('lib/widgets/dialogs/apply/apply_work_dialog.dart');
      expect(s, contains('final Map<DateTime, int> _refreshStatusGen = {};'));
      expect(s, contains('if (mounted && _refreshStatusGen[dateKey] == g) {'));
    });
  });
}
