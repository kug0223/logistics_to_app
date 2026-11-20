// [DU346] S006 계약서 관리 좁은 검증(시험 전용, 제품 무변경) — 소급 감사 8 §2 CORRECTION_OPEN.
//   하네스(main 앞)는 du1_s006_contract_mgmt_342_test.dart 를 글자 그대로 복사했다(work/du346-s006-verify/mk_test.py).
//   ① 세로 목록: ListView 안 세로 Scrollable 을 직접 잡아 끝까지 내리고 offset 증가 · 말단 카드(무효 '이서준') 화면 안 도달을 단언한다.
//   ② '무효 처리'(근무자 서명 대기 '김민수' 카드): 버튼 실기하 높이 ≥ 48, 글자 밖 확장부(버튼 안 왼쪽 끝 · 오른쪽 끝 가운데) hit 대상 일치,
//      탭 → 확인창('계약서 무효화') → '취소' → 확인창 닫힘 · 예외 0(무효 writer 미실행 — 가짜 reads 에는 writer 가 없다).
// ignore_for_file: depend_on_referenced_packages, unused_element, unused_import
// [DU342] S006 계약서 관리(AdminContractManagementScreen) 렌더 관측 — 기존 주입 지점(AdminContractReads)과 권한 가짜(SubAdmin, 계약 관리 권한).
//   하네스는 action_context_truth_test 와 같은 모양이다. 상태: ① '전체' 탭 계약 4건(사업주 서명 대기 · 근무자 서명 대기 · 완료 · 무효)
//   ② '미발송' 탭 확정 지원 2건 ③ 목록 조회 실패. W 392x844 1.0 / B 320x640 2.0.
//   글자마다 가장 가까운 바탕과 대비(아이콘 글리프 제외), 공용 판정기(DU338) avoidable, 넘침.
//   단언(기본): 예외 0 · 넘침 0 · 끊김 0 · 대비 미달 0. DU_BEFORE_OBSERVE=342 이면 끊김 · 대비는 KNOWN 으로 기록만 한다.
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_contract_management_screen.dart';
import 'package:ALfit/screens/business_admin/admin_contract_reads.dart';
import 'package:ALfit/theme/role_theme.dart';

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

const kBiz = 'biz1';
final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '342';

class _SubAdmin extends UserProvider {
  MemberPermissions get _perms =>
      MemberPermissions(canManageTo: true, canManageWorkers: true, canManageWage: false, canManageContract: true);
  @override
  UserModel? get currentUser => UserModel(
      uid: 'sub1', username: 'sub1', name: '이대리', email: 'sub1@alfit.local', role: UserRole.USER,
      subAdminBusinessIds: const [kBiz], createdAt: DateTime(2026, 1, 1));
  @override
  bool get isSubAdmin => true;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
  @override
  String? get selectedSubAdminBusinessId => kBiz;
  @override
  MemberPermissions? permissionsForBusiness(String businessId) => _perms;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) =>
      check(_perms) ? PermissionCheck.allowed : PermissionCheck.denied;
  @override
  bool can(bool Function(MemberPermissions p) check) => check(_perms);
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => check(_perms);
  @override
  VoidCallback watchBusinessPermissions(String businessId) => () {};
}

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

Color _overWhite(Color c) => Color.alphaBlend(c, Colors.white);

Color _bgOf(Element e) {
  Color? found;
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is ButtonStyleButton) {
      c = w.style?.backgroundColor?.resolve(w.enabled ? <WidgetState>{} : {WidgetState.disabled});
      if (c == null && w is ElevatedButton) c = Theme.of(a).colorScheme.primary;
      if (c == null) return true;
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
    found = _overWhite(c);
    return false;
  });
  return found ?? Colors.white;
}

EmploymentContractModel _contract(String id, ContractStatus st, String worker) => EmploymentContractModel(
    id: id, applicationId: 'app_$id', businessId: kBiz, workerId: 'wk_$id', isLongTerm: false, toId: '', workDetailId: 'wd1',
    status: st,
    snapshot: ContractSnapshot(
        businessName: '[QA] 아주 긴 이름의 강남 물류센터 평택 2공장', businessNumber: '000-00-00000', businessAddress: '서울',
        ownerName: '사업주', workerName: worker, workType: '냉장 피킹·검수 보조', workPlace: '서울', isLongTerm: false,
        contractStart: '2026-10-20', contractEnd: '2026-10-20', workDays: const [], startTime: '10:00', endTime: '11:00',
        breakMinutes: 0, wage: 12000, wageType: 'hourly', paymentMethod: '계좌이체', wagePaymentDay: 10, taxDeductionType: 'none'),
    createdAt: DateTime(2026, 10, 17));

ApplicationModel _unsent(String id, String name) => ApplicationModel(
    id: id, businessId: kBiz, businessName: '[QA] 아주 긴 이름의 강남 물류센터 평택 2공장', toTitle: 'QA 단기',
    workDate: DateTime(2026, 11, 20), startTime: '09:00', endTime: '18:00', uid: 'u_$id', selectedWorkType: '냉장 피킹·검수 보조',
    wage: 12000, wageType: 'hourly', status: AppStatus.confirmed, appliedAt: DateTime(2026, 11, 1), applicantName: name);

AdminContractReads _reads({bool fail = false}) => AdminContractReads(
      contractsPaged: (businessId, {startAfterId, statusFilter}) async {
        if (fail) throw StateError('contracts cf down');
        final all = [
          _contract('c1', ContractStatus.pendingEmployer, '아주긴이름의지원자홍길동'),
          _contract('c2', ContractStatus.pendingWorker, '김민수'),
          _contract('c3', ContractStatus.completed, '박지영'),
          _contract('c4', ContractStatus.voided, '이서준'),
        ];
        return (items: statusFilter == null ? all : all.where((c) => c.status == statusFilter).toList(), lastDocId: null, hasMore: false);
      },
      unsentApplications: (businessId) async {
        if (fail) throw StateError('unsent cf down');
        return [_unsent('u1', '최지원'), _unsent('u2', '아주긴이름의미발송지원자')];
      },
    );


void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });

  for (final c in const [(id: 'S006V-W', w: 392.0, h: 844.0, s: 1.0), (id: 'S006V-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 세로 목록 끝 · 무효 처리 진입 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
      await t.runAsync(vqLoadFonts);
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
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => _SubAdmin()),
            ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.businessAdminTheme,
            builder: (ctx, child) =>
                MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: AdminContractManagementScreen(
                businessId: kBiz, businessName: '[QA] 아주 긴 이름의 강남 물류센터 평택 2공장', initialTab: 0, reads: _reads()),
          ),
        ),
      ));
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(t.takeException(), isNull);

      // ① 세로 목록 — ListView 안의 세로 Scrollable(owner = ListView, axis = vertical)
      final listScroll = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
      final st = t.state<ScrollableState>(listScroll);
      final pos = st.position;
      out('${c.id} list owner=${t.widget(find.ancestor(of: listScroll, matching: find.byType(ListView)).first).runtimeType} axis=${pos.axis} max=${pos.maxScrollExtent.toStringAsFixed(1)}');
      expect(pos.axis, Axis.vertical, reason: '${c.id} 세로 목록');
      final before = pos.pixels;
      // 사용자처럼 끌어서 끝까지
      for (var k = 0; k < 40 && pos.pixels < pos.maxScrollExtent - 0.5; k++) {
        await t.drag(listScroll, Offset(0, -c.h * 0.4));
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
      }
      final last = findVisibleTextContaining('이서준');
      expect(last, findsWidgets, reason: '${c.id} 말단 카드(이서준) 생성');
      // [DU346 시험 수리 1/3] 말단 도달 = 마지막 카드의 아래 끝이 목록 표시 영역 안(끝까지 내렸을 때 키 큰 카드의 머리는
      //   위로 일부 나갈 수 있다 — TV_try0 B 이름 2.2px 위). 카드 = 이름을 품은 가장 가까운 흰 카드 Container.
      final lastCard = find.ancestor(of: last.first, matching: find.byWidgetPredicate((w) =>
          w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).borderRadius != null &&
          (w.decoration! as BoxDecoration).boxShadow != null)).first;
      final lr = t.getRect(lastCard);
      final vr = t.getRect(listScroll);
      out('${c.id} offset ${before.toStringAsFixed(1)} → ${pos.pixels.toStringAsFixed(1)} / ${pos.maxScrollExtent.toStringAsFixed(1)} lastCard=$lr viewport=$vr');
      if (pos.maxScrollExtent > 0) {
        expect(pos.pixels, greaterThan(before), reason: '${c.id} offset 증가');
        expect(pos.pixels, closeTo(pos.maxScrollExtent, 0.5), reason: '${c.id} 끝까지');
      }
      expect(lr.bottom <= vr.bottom + 0.5 && lr.bottom > vr.top, isTrue, reason: '${c.id} 말단 카드 아래 끝이 표시 영역 안');
      await vqCapture(t, key, '${c.id}_1_list_end', conditions: {'state': '세로 목록 끝(말단 무효 카드)', 'offset': pos.pixels, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});

      // ② 무효 처리 진입 — '김민수'(근무자 서명 대기) 카드
      pos.jumpTo(0);
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      // [DU346 시험 수리 2/3] B 는 카드가 커서 둘째 카드가 처음엔 지연 생성 범위 밖이다(TV_try1 B No element) — 생길 때까지 내린다.
      final kim = findVisibleTextContaining('김민수');
      for (var k = 0; k < 20 && kim.evaluate().isEmpty; k++) {
        await t.drag(listScroll, Offset(0, -c.h * 0.3));
        for (var i = 0; i < 3; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
      }
      final card = find.ancestor(of: kim.first, matching: find.byType(InkWell)).first;
      final voidBtn = find.descendant(of: find.ancestor(of: card, matching: find.byType(Container)).first,
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
      await t.ensureVisible(voidBtn);
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      final br = t.getRect(voidBtn);
      final label = t.getRect(find.descendant(of: voidBtn, matching: find.byType(RichText)).last);
      out('${c.id} 무효처리 btn=$br h=${br.height.toStringAsFixed(1)} label=$label');
      expect(br.height, greaterThanOrEqualTo(48 - 1e-6), reason: '${c.id} 무효 처리 실기하 높이 48');
      // 확장부: 버튼 안이면서 글자 사각형 밖인 점(왼쪽 끝 · 오른쪽 끝 · 위 가장자리 가운데)
      bool hits(Offset p) {
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
        return hit.path.any((e) => identical(e.target, t.renderObject(voidBtn)));
      }
      final pts = [Offset(br.left + 2, br.center.dy), Offset(br.right - 2, br.center.dy), Offset(br.center.dx, br.top + 2)];
      final hitRes = pts.map(hits).toList();
      out('${c.id} 확장부 hit $pts → $hitRes');
      expect(hitRes.every((h) => h), isTrue, reason: '${c.id} 확장부 hit 대상 일치');
      await t.tapAt(Offset(br.left + 2, br.center.dy));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(findVisibleText('계약서 무효화'), findsOneWidget, reason: '${c.id} 확인창');
      await vqCapture(t, key, '${c.id}_2_void_confirm', conditions: {'state': '무효 처리 → 확인창', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
      // [DU346 시험 수리 1/3] 공용 확인창의 '취소'는 ButtonStyleButton 이 아니다(TV_try0 W No element) — 보이는 글자를 누른다.
      final cancel = findVisibleText('취소');
      expect(cancel, findsOneWidget, reason: '${c.id} 확인창 취소');
      await t.tap(cancel);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(findVisibleText('계약서 무효화'), findsNothing, reason: '${c.id} 취소 → 확인창 닫힘');
      expect(t.takeException(), isNull);
      out('${c.id} summary listEnd=ok voidH=${br.height.toStringAsFixed(1)} hit=$hitRes confirm→cancel=ok');
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
}
