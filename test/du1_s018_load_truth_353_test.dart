// [DU353] S018 계약서 템플릿 목록 — 조회 실패 진실성(소급 감사 9 §2-1). 하네스(main 앞)는 du1_s018_template_list_344_test 를 글자 그대로
//   (생성기 work/du353-s018-load-truth/mk.py). 각본 서비스가 호출마다 정해진 응답(목록 또는 예외)을 낸다.
//   ① 첫 조회 실패 → 실패 본문(빈 상태 문구 아님) · outlined 다시 시도 48 → 다시 시도 성공(빈 목록) → '등록된 템플릿이 없습니다'
//   ② 목록 있음 → 새로 고침 실패 → 목록 유지 + 갱신 실패 안내 · 다시 시도 → 성공 → 안내 사라짐
//   단언(기본): 위 흐름 · 넘침 0 · 끊김 0 · 대비 미달 0. DU_BEFORE_OBSERVE=353 이면 흐름 · 시각 단언을 기록만 한다.
// ignore_for_file: depend_on_referenced_packages, unused_element
// [DU344] S018 계약서 템플릿 목록(ContractTemplateListScreen) + 생성 방법 시트(O092) 렌더 관측 —
//   최소 표시 seam(templateService 주입, 호출 글자 그대로)과 권한 가짜(SubAdmin 계약 관리 권한).
//   자료: 단기 기본 · 기간제 기본 · 옛 분류(외주, 긴 이름) · 추가 조항 없는 양식. 상태: 목록 · 빈 목록 · 생성 방법 시트.
//   W 392x844 1.0 / B 320x640 2.0. 가장 가까운 바탕 대비(아이콘 글리프 제외) · 공용 판정기(DU338) · 넘침.
//   단언(기본): 예외 0 · 넘침 0 · 끊김 0 · 대비 미달 0. DU_BEFORE_OBSERVE=344 이면 끊김 · 대비는 KNOWN 으로 기록만 한다.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/contract_template_list_screen.dart';
import 'package:ALfit/services/contract_template_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';

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
final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '344';

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

class _FakeTemplates extends ContractTemplateService {
  _FakeTemplates(this.items);
  final List<ContractTemplateModel> items;
  @override
  Future<List<ContractTemplateModel>> getTemplates(String businessId, {int limit = 100}) async => items;
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

ContractTemplateModel _tpl(String id, String name, String type, {bool noArticles = false}) => ContractTemplateModel(
    id: id, businessId: kBiz, name: name, templateType: type,
    articles: noArticles ? const [] : ContractTemplateModel.defaultArticlesFor(type), createdAt: DateTime(2026, 11, 1));


final bool _beforeObs353 = Platform.environment['DU_BEFORE_OBSERVE'] == '353';

class _Scripted extends ContractTemplateService {
  _Scripted(this.script);
  final List<Object> script; // List<ContractTemplateModel> 또는 Exception
  int calls = 0;
  @override
  Future<List<ContractTemplateModel>> getTemplates(String businessId, {int limit = 100}) async {
    final r = script[calls < script.length ? calls : script.length - 1];
    calls++;
    if (r is Exception) throw r;
    return r as List<ContractTemplateModel>;
  }
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    const codec = StandardMessageCodec();
    for (final m in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
          'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$m',
          (_) async => codec.encodeMessage(<Object?>['du353.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du353.fake.$m'), (_) async => null);
    }
  });

  final items = [
    _tpl('t1', '단기 일용 기본 양식', ContractTemplateType.daily),
    _tpl('t2', '기간제 장기 근무 기본 양식', ContractTemplateType.period),
  ];

  for (final c in const [(id: 'S018L-W', w: 392.0, h: 844.0, s: 1.0), (id: 'S018L-B', w: 320.0, h: 640.0, s: 2.0)]) {
    for (final flow in const ['firstFail', 'refreshFail']) {
      testWidgets('${c.id} 조회 실패 진실성 $flow ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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

          final svc = _Scripted(flow == 'firstFail'
              ? <Object>[Exception('합성: 첫 조회 실패'), <ContractTemplateModel>[]]
              : <Object>[items, Exception('합성: 새로 고침 실패'), items]);
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider<UserProvider>(create: (_) => _SubAdmin()),
                ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                navigatorKey: navigatorKey,
                theme: RoleTheme.businessAdminTheme,
                builder: (ctx, child) =>
                    MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
                home: ContractTemplateListScreen(businessId: kBiz, templateService: svc),
              ),
            ),
          ));
          Future<void> settle([int n = 12]) async {
            for (var i = 0; i < n; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
          }

          await settle();
          // [수리 1/3] 실패 토스트(ToastHelper.showError, 4초)가 사라진 뒤 본문을 잰다. 토스트 대비는 공용 부품 후보로 따로 적는다.
          Future<void> waitToast() async {
            await t.pump(const Duration(milliseconds: 4500));
            await settle(2);
          }

          if (flow == 'firstFail') await waitToast();
          var avoid = 0, low = 0;
          final seen = <String>{};
          void dump(String tg) {
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
                if (!b.forced) {
                  avoid++;
                  out('$tg avoidable $b');
                }
              }
              final cst = col == null ? 99.0 : _contrast(_overWhite(col), bg);
              if (cst < 4.5) {
                low++;
                out('$tg low "$s" contrast=${cst.toStringAsFixed(2)}');
              }
            }
          }

          final failTitle = findVisibleText('계약서 템플릿을 불러오지 못했습니다');
          final emptyTitle = findVisibleText('등록된 템플릿이 없습니다');
          final banner = findVisibleTextContaining('목록을 새로 고치지 못했어요');
          final tag = '${c.id}_$flow';
          final steps = <String, bool>{};
          if (flow == 'firstFail') {
            steps['첫 실패 = 실패 본문'] = failTitle.evaluate().isNotEmpty;
            steps['첫 실패 ≠ 빈 상태'] = emptyTitle.evaluate().isEmpty;
            dump('${tag}_fail');
            await vqCapture(t, key, '${tag}_1_fail', conditions: {'state': '첫 조회 실패', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
            final retry = findVisibleText('다시 시도');
            var retryOk = false;
            if (retry.evaluate().isNotEmpty) {
              final btn = find.ancestor(of: retry.first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
              retryOk = t.widget(btn) is OutlinedButton && t.getRect(btn).height >= 48 - 1e-6;
              out('$tag retry type=${t.widget(btn).runtimeType} h=${t.getRect(btn).height.toStringAsFixed(1)}');
              await t.tap(btn);
              await settle();
            }
            steps['다시 시도 outlined 48'] = retryOk;
            steps['재시도 성공 → 빈 상태'] = emptyTitle.evaluate().isNotEmpty && failTitle.evaluate().isEmpty;
            out('$tag calls=${svc.calls}');
            await vqCapture(t, key, '${tag}_2_retry_empty', conditions: {'state': '다시 시도 성공(빈 목록)', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
          } else {
            steps['처음 목록'] = findVisibleText('단기 일용 기본 양식').evaluate().isNotEmpty;
            // [수리 1/3] show() 는 프레임이 돌아야 끝난다 — await 하지 않고 펌프한다.
            unawaited(t.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show());
            await settle(20);
            await waitToast();
            steps['갱신 실패 뒤 목록 유지'] = findVisibleText('단기 일용 기본 양식').evaluate().isNotEmpty;
            steps['갱신 실패 안내'] = banner.evaluate().isNotEmpty;
            dump('${tag}_banner');
            await vqCapture(t, key, '${tag}_1_refresh_fail', conditions: {'state': '목록 있음 → 새로 고침 실패', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
            final retry = findVisibleText('다시 시도');
            if (retry.evaluate().isNotEmpty) {
              final btn = find.ancestor(of: retry.first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
              out('$tag banner retry h=${t.getRect(btn).height.toStringAsFixed(1)}');
              steps['안내 다시 시도 48'] = t.getRect(btn).height >= 48 - 1e-6;
              await t.tap(btn);
              await settle(20);
            } else {
              steps['안내 다시 시도 48'] = false;
            }
            steps['재시도 성공 → 안내 사라짐 · 목록'] = banner.evaluate().isEmpty && findVisibleText('단기 일용 기본 양식').evaluate().isNotEmpty;
            out('$tag calls=${svc.calls}');
            await vqCapture(t, key, '${tag}_2_retry_ok', conditions: {'state': '다시 시도 성공', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
          }
          expect(t.takeException(), isNull);
          final flowOk = steps.values.every((v) => v);
          out('$tag steps=$steps');
          out('$tag summary overflows=${overflows.length} avoidable=$avoid low=$low flowOk=$flowOk beforeObs=$_beforeObs353');
          out('KNOWN ${flowOk ? 'ok' : 'NG'} $tag 조회 실패 진실성 흐름');
          out('KNOWN ${avoid == 0 && low == 0 ? 'ok' : 'NG'} $tag 시각(끊김 $avoid · 대비 $low)');
          expect(overflows, isEmpty, reason: '$tag 넘침');
          if (!_beforeObs353) {
            for (final en in steps.entries) {
              expect(en.value, isTrue, reason: '$tag ${en.key}');
            }
            expect(avoid, 0, reason: '$tag 끊김');
            expect(low, 0, reason: '$tag 대비');
          }
          await t.pumpWidget(const SizedBox.shrink());
        } finally {
          FlutterError.onError = prev;
        }
      });
    }
  }
}
