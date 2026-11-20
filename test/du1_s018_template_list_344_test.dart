// ignore_for_file: depend_on_referenced_packages
// [DU344] S018 계약서 템플릿 목록(ContractTemplateListScreen) + 생성 방법 시트(O092) 렌더 관측 —
//   최소 표시 seam(templateService 주입, 호출 글자 그대로)과 권한 가짜(SubAdmin 계약 관리 권한).
//   자료: 단기 기본 · 기간제 기본 · 옛 분류(외주, 긴 이름) · 추가 조항 없는 양식. 상태: 목록 · 빈 목록 · 생성 방법 시트.
//   W 392x844 1.0 / B 320x640 2.0. 가장 가까운 바탕 대비(아이콘 글리프 제외) · 공용 판정기(DU338) · 넘침.
//   단언(기본): 예외 0 · 넘침 0 · 끊김 0 · 대비 미달 0. DU_BEFORE_OBSERVE=344 이면 끊김 · 대비는 KNOWN 으로 기록만 한다.
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

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    // [DU344 시험 수리 1/3] 화면이 FirebaseAuth.instance 를 만지면 pigeon 채널로 token/auth listener 를 등록한다 —
    //   시험 환경에는 그 채널이 없어 PlatformException(channel-error)이 첫 시험 실패로 드러났다(TB_try0 W list).
    //   applicant_row_overflow_test(DU1 후속38 §2.1)와 같은 방식으로 두 등록 채널에만 '등록됨' 응답을 준다(이벤트는 오지 않는다).
    const codec = StandardMessageCodec();
    for (final m in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
          'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$m',
          (_) async => codec.encodeMessage(<Object?>['du344.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du344.fake.$m'), (_) async => null);
    }
  });

  final items = [
    _tpl('t1', '단기 일용 기본 양식', ContractTemplateType.daily),
    _tpl('t2', '기간제 장기 근무 기본 양식', ContractTemplateType.period),
    _tpl('t3', '[QA] 아주 긴 이름의 예전 외주 업무위탁 계약서 양식', ContractTemplateType.outsource),
    _tpl('t4', '추가 조항 없는 양식', ContractTemplateType.daily, noArticles: true),
  ];

  for (final c in const [(id: 'S018-W', w: 392.0, h: 844.0, s: 1.0), (id: 'S018-B', w: 320.0, h: 640.0, s: 2.0)]) {
    for (final st in const ['list', 'empty', 'sheet']) {
      testWidgets('${c.id} 계약서 템플릿 $st ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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
                home: ContractTemplateListScreen(
                    businessId: kBiz, templateService: _FakeTemplates(st == 'empty' ? const [] : items)),
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
              final k = '$tag|$s@${bg.toARGB32()}@${col?.toARGB32()}';
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

          if (st == 'sheet') {
            final add = findVisibleText('새 계약서 템플릿 추가');
            for (var k = 0; k < 20 && add.evaluate().isEmpty; k++) {
              await t.drag(find.byType(Scrollable).first, const Offset(0, -200));
              await t.pump(const Duration(milliseconds: 50));
            }
            await t.ensureVisible(add.first);
            await t.pump(const Duration(milliseconds: 50));
            await t.tap(add.first);
            for (var i = 0; i < 12; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            expect(findVisibleText('새 템플릿 만들기'), findsOneWidget, reason: '${c.id} 생성 방법 시트');
            dump('${c.id}_sheet');
            await vqCapture(t, key, '${c.id}_3_sheet', conditions: {'state': '생성 방법 시트(O092)', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
          } else {
            dump('${c.id}_$st');
            await vqCapture(t, key, '${c.id}_${st == 'list' ? '1_list' : '2_empty'}', conditions: {'state': st, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
            if (st == 'list') {
              final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
              var guard = 0;
              while (pos.pixels < pos.maxScrollExtent - 0.5 && guard++ < 20) {
                pos.jumpTo(math.min(pos.pixels + c.h * 0.5, pos.maxScrollExtent));
                await t.pump(const Duration(milliseconds: 50));
                dump('${c.id}_list_walk');
              }
              await vqCapture(t, key, '${c.id}_1_list_end', conditions: {'state': '목록 끝', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
            }
          }
          expect(t.takeException(), isNull);
          out('${c.id}_$st summary overflows=${overflows.length} $overflows avoidable=$avoid forced=${forced.length} $forced low=$low beforeObs=$_beforeObs');
          out('KNOWN ${avoid == 0 ? 'ok' : 'NG'} ${c.id}_$st 피할 수 있는 끊김 0(실측 $avoid)');
          out('KNOWN ${low == 0 ? 'ok' : 'NG'} ${c.id}_$st 대비 미달 0(실측 $low)');
          expect(overflows, isEmpty, reason: '${c.id}_$st 넘침');
          if (!_beforeObs) {
            expect(avoid, 0, reason: '${c.id}_$st 피할 수 있는 끊김');
            expect(low, 0, reason: '${c.id}_$st 대비 미달');
          }
          await t.pumpWidget(const SizedBox.shrink());
        } finally {
          FlutterError.onError = prev;
        }
      });
    }
  }
}
