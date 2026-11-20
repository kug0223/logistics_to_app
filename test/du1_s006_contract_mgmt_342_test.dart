// ignore_for_file: depend_on_referenced_packages
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

  for (final c in const [(id: 'S006-W', w: 392.0, h: 844.0, s: 1.0), (id: 'S006-B', w: 320.0, h: 640.0, s: 2.0)]) {
    for (final st in const [(k: 'all', tab: 0, fail: false), (k: 'unsent', tab: 1, fail: false), (k: 'fail', tab: 0, fail: true)]) {
      testWidgets('${c.id} 계약서 관리 ${st.k} ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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
                    businessId: kBiz, businessName: '[QA] 아주 긴 이름의 강남 물류센터 평택 2공장', initialTab: st.tab, reads: _reads(fail: st.fail)),
              ),
            ),
          ));
          for (var i = 0; i < 12; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          expect(t.takeException(), isNull);
          var avoid = 0, low = 0;
          final forced = <WordBreak>[];
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
              final k = '$s@${bg.toARGB32()}@${col?.toARGB32()}';
              if (seen.contains(k)) continue;
              seen.add(k);
              for (final b in wordBreaks(rp)) {
                if (b.forced) {
                  forced.add(b);
                } else {
                  avoid++;
                  out('$tag avoidable $b');
                }
              }
              final cst = col == null ? 99.0 : _contrast(_overWhite(col), bg);
              if (cst < 4.5) {
                low++;
                out('$tag low "${s.length > 30 ? '${s.substring(0, 30)}…' : s}" color=0x${col?.toARGB32().toRadixString(16)} bg=0x${bg.toARGB32().toRadixString(16)} contrast=${cst.toStringAsFixed(2)}');
              }
            }
          }

          dump('${c.id}_${st.k}');
          await vqCapture(t, key, '${c.id}_${st.k}_1_top', conditions: {'state': st.k, 'tab': st.tab, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
          final lists = find.byType(Scrollable);
          if (!st.fail && lists.evaluate().length > 1) {
            final sc = lists.last;
            final pos = t.state<ScrollableState>(sc).position;
            if (pos.maxScrollExtent > 0) {
              pos.jumpTo(pos.maxScrollExtent);
              for (var i = 0; i < 4; i++) {
                await t.pump(const Duration(milliseconds: 50));
              }
              dump('${c.id}_${st.k}_end');
              await vqCapture(t, key, '${c.id}_${st.k}_2_end', conditions: {'state': '${st.k} 끝', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
            }
          }
          expect(t.takeException(), isNull);
          out('${c.id}_${st.k} summary overflows=${overflows.length} $overflows avoidable=$avoid forced=${forced.length} $forced low=$low beforeObs=$_beforeObs');
          out('KNOWN ${avoid == 0 ? 'ok' : 'NG'} ${c.id}_${st.k} 피할 수 있는 끊김 0(실측 $avoid)');
          out('KNOWN ${low == 0 ? 'ok' : 'NG'} ${c.id}_${st.k} 대비 미달 0(실측 $low)');
          expect(overflows, isEmpty, reason: '${c.id}_${st.k} 넘침');
          if (!_beforeObs) {
            expect(avoid, 0, reason: '${c.id}_${st.k} 피할 수 있는 끊김');
            expect(low, 0, reason: '${c.id}_${st.k} 대비 미달');
          }
          await t.pumpWidget(const SizedBox.shrink());
        } finally {
          FlutterError.onError = prev;
        }
      });
    }
  }
}
