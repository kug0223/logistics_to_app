// [DU396] S014 사업장 목록 행동색(소급 25 §3–§4) — 하네스는 du1_s014_copy_395 바탕(4곳 fixture · 공용 fake · vqLoadFonts).
//   W 392x844@1.0 · B 320x640@2.0 = 정확 2 public 시험. 한 시험 안에서 세 구성을 차례로 그린다:
//     ① 소유자 · 관리 권한 — 4카드 더보기(48 · viewport · 중앙 hit → 실제 탭 → 시트 1 → 비파괴 닫힘) · 시트 전체 항목(집합 · 중복 0 · 실제 순서)
//        · 새 사업장 추가 타일(존재 · ≥48 · hit, 누르지 않음) · b1 '운영 종료' 진입 → debugPreview 사전 조회 → 위험 확인창(최종 errorDark) → 취소
//     ② SubAdmin — b1 메뉴 = 공고 등록 · 상세보기(수정 · 운영 종료 없음) · 추가 타일 없음
//     ③ 소유자 · 관리 권한 없음 — b1 메뉴 = 상세보기 · 수정 · 운영 종료(공고 등록 없음)
//   제품 기대(행동색, 기본 단언 · DU_BEFORE_OBSERVE=396 은 기록만):
//     더보기 grey600 · 메뉴 아이콘 공고 등록/상세보기/수정 = brand, 운영 종료 = grey600 · 라벨 모두 grey800(운영 종료 isDanger:false)
//     · 추가 타일 라벨 brandDark · 아이콘 brand · 작은 글 대비 ≥ 4.5 · 의미 아이콘 ≥ 3(실제 바탕/칩)
//   불변(항상 단언): 도달 · 메뉴 48/hit/시트/닫힘 · 항목 집합/순서/조건 · 추가 타일 존재(소유자)/부재(SubAdmin) · 확인창 errorDark ·
//     사전 조회 = 같은 businessId 1회 · 취소 뒤 archive 0 · 목록 유지 · 넘침 0 · 예외 0 · 색 검사 계수.
// ignore_for_file: depend_on_referenced_packages, unused_element
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_list_reads.dart';
import 'package:ALfit/screens/business_admin/business_list_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options =>
      const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p', storageBucket: 'p.appspot.com');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _Provider extends UserProvider {
  _Provider({required this.subAdmin, required this.canManage, required this.ids});

  final bool subAdmin;
  final bool canManage;
  final List<String> ids;

  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김사장',
        email: 'u1@alfit.local',
        role: subAdmin ? UserRole.USER : UserRole.BUSINESS_ADMIN,
        managedBusinessIds: ids,
        subAdminBusinessIds: subAdmin ? ids : const [],
      );
  @override
  bool get isSubAdmin => subAdmin;
  @override
  bool get isBusinessAdmin => !subAdmin;
  @override
  String? get effectiveBusinessId => null;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) =>
      canManage ? PermissionCheck.allowed : PermissionCheck.denied;
}

BusinessModel _biz(String id, String name,
        {bool approved = true,
        String address = '서울특별시 강남구 테헤란로 152',
        double? rating,
        bool parking = false,
        List<String>? meals,
        bool closed = false}) =>
    BusinessModel(
      id: id,
      businessNumber: '000-00-00000',
      name: name,
      category: '물류',
      subCategory: '창고',
      address: address,
      ownerId: 'u1',
      isApproved: approved,
      createdAt: DateTime(2026, 10, 1),
      rating: rating,
      parkingAvailable: parking,
      mealsProvided: meals,
      deactivatedAt: closed ? DateTime(2026, 11, 1) : null,
      archivedAt: closed ? DateTime(2026, 11, 1) : null,
    );

// 392 · 395 와 같은 4곳: b1 승인 · b2 승인 대기 · b3 운영 종료 · b4 승인(긴 이름)
final _four = [
  _biz('b1', '강남 물류센터', rating: 4.6, parking: true, meals: const ['중식']),
  _biz('b2', '송파 신선 분류센터', approved: false),
  _biz('b3', '성수 소형 창고', closed: true),
  _biz('b4', '[QA] 아주 긴 이름의 강남 물류센터 평택 제2공장 냉장 분류동',
      address: '경기도 평택시 포승읍 평택항로 268번길 45-12 물류단지 B동 3층', rating: 3.9, parking: true),
];

// 메뉴 조건(제품 호출부를 독립으로 적은 기대): [공고 등록] 승인 · 관리 권한 / [상세보기, 수정(SubAdmin 아님)] / [운영 종료] SubAdmin 아님 · 소유자 · 종료 아님
List<String> _menuExpect(BusinessModel b, {required bool subAdmin, required bool canManage}) => [
      if (b.isApproved && canManage) '공고 등록',
      '상세보기',
      if (!subAdmin) '수정',
      if (!subAdmin && b.ownerId == 'u1' && !b.isDeactivated) '운영 종료',
    ];

// 행동색 기대(채택표): 아이콘 — 운영 종료 grey600, 나머지 brand · 라벨 — 모두 grey800(운영 종료 isDanger:false)
Color _iconExpect(String label) => label == '운영 종료' ? AppColors.grey600 : AppColors.brand;

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '396';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

// 실제 바탕 — 가장 가까운 불투명(흰 위 합성) 면(392 · 395 와 같은 helper). 반투명 면은 그 아래 첫 불투명 면과 합성한다.
Color _bgOf(Element e) {
  final layers = <Color>[];
  Color? base;
  Decoration? lastDeco; // [DU396 수리 후보 2] Container 는 안쪽에 같은 decoration 의 DecoratedBox 를 만든다 — 한 면을 두 번 겹치지 않는다
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is Container && w.decoration != null && identical(w.decoration, lastDeco)) {
      return true;
    }
    if (w is DecoratedBox) lastDeco = w.decoration;
    if (w is Container && w.decoration is BoxDecoration) {
      c = (w.decoration! as BoxDecoration).color;
    } else if (w is Container && w.color != null) {
      c = w.color;
    } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
      c = (w.decoration as BoxDecoration).color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color ?? Theme.of(a).colorScheme.surface;
    } else if (w is ColoredBox) {
      c = w.color;
    } else if (w is Scaffold) {
      c = w.backgroundColor ?? Theme.of(a).scaffoldBackgroundColor;
    }
    if (c == null || c.a == 0) return true;
    if (c.a >= 0.999) {
      base = c;
      return false;
    }
    layers.add(c);
    return true;
  });
  var out = base ?? Colors.white;
  for (final l in layers.reversed) {
    out = Color.alphaBlend(l, out);
  }
  return out;
}

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _hex(Color? c) => '0x${(c ?? Colors.transparent).toARGB32().toRadixString(16)}';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    const codec = StandardMessageCodec();
    for (final m in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
          'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$m',
          (_) async => codec.encodeMessage(<Object?>['du396.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du396.fake.$m'), (_) async => null);
    }
  });

  for (final c in const [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('S014A-${c.id} 행동색 · 더보기 · 메뉴 · 추가 타일 · 운영 종료 진입 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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
      t.view.physicalSize = Size(c.w, c.h);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final previewCalls = <String>[];
      var archiveCalls = 0;
      BusinessListScreen.debugPreview = (id) async {
        previewCalls.add(id);
        return <String, dynamic>{
          'truncated': false,
          for (final k in const [
            'inProgressShifts', 'ongoingLongTerm', 'contractPendingWorked',
            'openPostings', 'pendingApplications', 'invites', 'futureConfirmed', 'contractsVoided',
            'keptStarted', 'contractsKept', 'unpaidWages', 'workedUncalculated',
            'interimPending', 'interimApproved',
          ])
            k: 0,
        };
      };
      BusinessListScreen.debugArchive = (id, expected) async {
        archiveCalls++;
      };
      addTearDown(() {
        BusinessListScreen.debugPreview = null;
        BusinessListScreen.debugArchive = null;
      });
      final tag = 'S014A-${c.id}';
      final cond = {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s};
      final screen = Offset.zero & Size(c.w, c.h);
      bool inRect(Rect o, Rect r) => r.top >= o.top - 0.5 && r.bottom <= o.bottom + 0.5 && r.left >= o.left - 0.5 && r.right <= o.right + 0.5;
      final checks = <String, bool>{}; // 행동색(제품 기대)
      var colorChecks = 0;
      void must(String k, bool v, [String why = '']) => expect(v, isTrue, reason: '$tag $k $why');
      Future<void> settle([int n = 10]) async {
        for (var i = 0; i < n; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
      }

      Future<GlobalKey> pumpList({required bool subAdmin, required bool canManage}) async {
        final key = GlobalKey();
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>(
                  create: (_) => _Provider(subAdmin: subAdmin, canManage: canManage, ids: [for (final b in _four) b.id])),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.businessAdminTheme,
              builder: (ctx, child) =>
                  MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
              home: BusinessListScreen(
                  reads: BusinessListReads(businessById: (_) async => _four.first, businessesByIds: (_) async => _four)),
            ),
          ),
        ));
        await settle(16);
        return key;
      }

      Finder scroll() => find.byType(Scrollable).first;
      // 카드 위로 맞춘 뒤 그 카드의 더보기 → 실제 탭 → 시트 1. 반환: 시트 Finder
      Future<Finder> openMenu(BusinessModel b, String phase) async {
        final name = findVisibleText(b.name);
        await t.scrollUntilVisible(name, 120, scrollable: scroll(), maxScrolls: 40); // 아래로만 — 위 카드는 호출 전에 맨 위로 올린다
        await settle(4);
        must('$phase ${b.id} 이름 도달', name.evaluate().length == 1);
        final card = find.ancestor(of: name, matching: find.byType(InkWell)).first;
        await t.ensureVisible(card);
        await settle(6);
        final more = find.descendant(of: card, matching: find.byType(IconButton));
        must('$phase ${b.id} 카드 귀속 더보기 1', more.evaluate().length == 1);
        final vp = t.getRect(scroll());
        final mr = t.getRect(more);
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, mr.center, t.view.viewId);
        final glyph = t.renderObject(find.descendant(of: more, matching: find.byType(RichText)).first);
        must('$phase ${b.id} 더보기 48 · viewport · 중앙 hit',
            inRect(vp, mr) && inRect(screen, mr) && mr.width >= 47.99 && mr.height >= 47.99 && hit.path.any((e) => e.target == glyph), '$mr / $vp');
        final ic = t.widget<Icon>(find.descendant(of: more, matching: find.byType(Icon)));
        final icBg = _bgOf(t.element(find.descendant(of: more, matching: find.byType(Icon))));
        checks['$phase ${b.id} 더보기 grey600'] = ic.color == AppColors.grey600;
        checks['$phase ${b.id} 더보기 대비 ≥ 3'] = _contrast(ic.color ?? Colors.black, icBg) >= 3;
        colorChecks++;
        _out('$tag $phase ${b.id} more=$mr color=${_hex(ic.color)} bg=${_hex(icBg)} contrast=${_contrast(ic.color ?? Colors.black, icBg).toStringAsFixed(2)}');
        await t.tapAt(mr.center);
        await settle(12);
        final sheet = find.byType(BottomSheet);
        must('$phase ${b.id} 메뉴 탭 → 시트 1', sheet.evaluate().length == 1);
        return sheet;
      }

      // 시트 항목을 위젯 실제 순서(트리 = 화면 위→아래)로 모은다: 라벨 · 아이콘 색 · 칩 면 · 라벨 색 · rect
      List<({String label, Color? icon, Color chip, Color? text, Rect rect, Color textBg})> items(Finder sheet) {
        final f = find.descendant(of: sheet, matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuItem'));
        final out = <({String label, Color? icon, Color chip, Color? text, Rect rect, Color textBg})>[];
        for (var i = 0; i < f.evaluate().length; i++) {
          final it = f.at(i);
          final texts = find.descendant(of: it, matching: find.byType(Text));
          final icons = find.descendant(of: it, matching: find.byType(Icon));
          must('시트 항목 $i 글 1 · 아이콘 2(항목 · 화살표)', texts.evaluate().length == 1 && icons.evaluate().length == 2);
          final tx = t.widget<Text>(texts);
          final rp = t.renderObject<RenderParagraph>(find.descendant(of: texts, matching: find.byType(RichText), matchRoot: true).first);
          final ic = t.widget<Icon>(icons.first);
          out.add((
            label: visibleText(tx.data ?? ''),
            icon: ic.color,
            chip: _bgOf(t.element(icons.first)),
            text: rp.text.style?.color,
            rect: t.getRect(it),
            textBg: _bgOf(t.element(texts)),
          ));
        }
        return out;
      }

      void menuCheck(String phase, BusinessModel b, Finder sheet, {required bool subAdmin, required bool canManage}) {
        final got = items(sheet);
        final labels = [for (final x in got) x.label];
        final want = _menuExpect(b, subAdmin: subAdmin, canManage: canManage);
        must('$phase ${b.id} 시트 항목 집합 · 순서 = 조건 기대', labels.join('|') == want.join('|'), 'got=$labels want=$want');
        must('$phase ${b.id} 시트 항목 중복 0', labels.toSet().length == labels.length);
        must('$phase ${b.id} 시트 항목 위→아래', [for (var i = 1; i < got.length; i++) got[i].rect.top >= got[i - 1].rect.bottom - 0.5].every((x) => x));
        for (final x in got) {
          must('$phase ${b.id} ${x.label} 항목 화면 안', inRect(screen, x.rect), '${x.rect}');
          checks['$phase ${b.id} ${x.label} 아이콘 색'] = x.icon == _iconExpect(x.label);
          checks['$phase ${b.id} ${x.label} 라벨 grey800'] = x.text == AppColors.grey800;
          checks['$phase ${b.id} ${x.label} 아이콘 대비 ≥ 3(칩)'] = _contrast(x.icon ?? Colors.black, x.chip) >= 3;
          checks['$phase ${b.id} ${x.label} 라벨 대비 ≥ 4.5'] = _contrast(x.text ?? Colors.black, x.textBg) >= 4.5;
          colorChecks += 2;
          _out('$tag $phase ${b.id} item "${x.label}" icon=${_hex(x.icon)} chip=${_hex(x.chip)} '
              'c=${_contrast(x.icon ?? Colors.black, x.chip).toStringAsFixed(2)} text=${_hex(x.text)} bg=${_hex(x.textBg)} '
              'c=${_contrast(x.text ?? Colors.black, x.textBg).toStringAsFixed(2)} rect=${x.rect}');
        }
      }

      Future<void> closeSheet(String phase, BusinessModel b, Finder sheet) async {
        await Navigator.of(t.element(sheet)).maybePop();
        await settle(12);
        must('$phase ${b.id} 시트 비파괴 닫힘', find.byType(BottomSheet).evaluate().isEmpty);
        must('$phase ${b.id} 목록 그대로', findVisibleText(b.name).evaluate().length == 1);
      }

      // ── ① 소유자 · 관리 권한 ──
      var key = await pumpList(subAdmin: false, canManage: true);
      await vqCapture(t, key, '${tag}_1top', conditions: {...cond, 'state': '소유자 4곳 첫 화면'});
      var expectedColor = 0;
      for (final b in _four) {
        final sheet = await openMenu(b, '①');
        menuCheck('①', b, sheet, subAdmin: false, canManage: true);
        expectedColor += 1 + 2 * _menuExpect(b, subAdmin: false, canManage: true).length;
        if (b.id == 'b1') {
          await vqCapture(t, key, '${tag}_2menu_b1', conditions: {...cond, 'state': '소유자 b1 메뉴 시트'});
        }
        await closeSheet('①', b, sheet);
      }
      // 새 사업장 추가 타일 — 존재 · ≥48 · hit · 색/대비(누르지 않는다)
      final addLabel = findVisibleText('새 사업장 추가');
      await t.scrollUntilVisible(addLabel, 200, scrollable: scroll(), maxScrolls: 40);
      await settle(6);
      must('① 추가 타일 1', addLabel.evaluate().length == 1);
      final addInk = find.ancestor(of: addLabel, matching: find.byType(InkWell)).first;
      final ar = t.getRect(addInk);
      final ahit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(ahit, ar.center, t.view.viewId);
      must('① 추가 타일 ≥ 48 · viewport · 중앙 hit',
          ar.height >= 47.99 && inRect(t.getRect(scroll()), ar) && ahit.path.any((e) => e.target == t.renderObject(addInk)), '$ar');
      final alRp = t.renderObject<RenderParagraph>(find.descendant(of: addLabel, matching: find.byType(RichText), matchRoot: true).first);
      final alColor = alRp.text.style?.color;
      final alBg = _bgOf(t.element(addLabel));
      final aIcon = find.descendant(of: addInk, matching: find.byType(Icon));
      must('① 추가 타일 아이콘 1', aIcon.evaluate().length == 1);
      final aiColor = t.widget<Icon>(aIcon).color;
      final aiBg = _bgOf(t.element(aIcon));
      checks['① 추가 타일 라벨 brandDark'] = alColor == AppColors.brandDark;
      checks['① 추가 타일 라벨 대비 ≥ 4.5'] = _contrast(alColor ?? Colors.black, alBg) >= 4.5;
      checks['① 추가 타일 아이콘 brand'] = aiColor == AppColors.brand;
      checks['① 추가 타일 아이콘 대비 ≥ 3'] = _contrast(aiColor ?? Colors.black, aiBg) >= 3;
      colorChecks += 2;
      expectedColor += 2;
      _out('$tag ① add tile=$ar label=${_hex(alColor)} bg=${_hex(alBg)} c=${_contrast(alColor ?? Colors.black, alBg).toStringAsFixed(2)} '
          'icon=${_hex(aiColor)} bg=${_hex(aiBg)} c=${_contrast(aiColor ?? Colors.black, aiBg).toStringAsFixed(2)}');
      await vqCapture(t, key, '${tag}_3add', conditions: {...cond, 'state': '목록 끝 새 사업장 추가 타일'});
      // b1 '운영 종료' 진입 → 사전 조회(fake) → 위험 확인창 → 취소
      final b1 = _four.first;
      await t.drag(scroll(), const Offset(0, 4000)); // 맨 위로(b1 은 위쪽 — 아래 방향 탐색만 쓴다)
      await settle(10);
      final s1 = await openMenu(b1, '①종료');
      expectedColor += 1; // [DU396 수리 후보 1] 종료 진입 전 더보기 색 검사 1건(TB: 기대 51 · 실제 52)
      final endItem = find.descendant(of: s1, matching: findVisibleText('운영 종료'));
      must('①종료 시트 운영 종료 1', endItem.evaluate().length == 1);
      final er = t.getRect(endItem);
      must('①종료 운영 종료 항목 화면 안', inRect(screen, er), '$er');
      await t.tapAt(er.center);
      await settle(16);
      final title = findVisibleText('사업장 운영 종료');
      must('①종료 사전 조회 = 같은 businessId 1회', previewCalls.length == 1 && previewCalls.first == b1.id, '$previewCalls');
      must('①종료 위험 확인창 제목 1', title.evaluate().length == 1);
      final dialog = find.ancestor(of: title, matching: find.byType(Dialog));
      must('①종료 확인창 Dialog 1', dialog.evaluate().length == 1);
      final okText = find.descendant(of: dialog, matching: findVisibleText('운영 종료'));
      must('①종료 확인창 최종 버튼 운영 종료 1', okText.evaluate().length == 1);
      final okFill = t.widget<Material>(find.ancestor(of: okText, matching: find.byType(Material)).first).color;
      must('①종료 최종 실행 채움 errorDark(그대로)', okFill == AppColors.errorDark, _hex(okFill));
      final cancel = find.descendant(of: dialog, matching: findVisibleText('취소'));
      must('①종료 확인창 취소 1', cancel.evaluate().length == 1);
      _out('$tag ①종료 preview=$previewCalls okFill=${_hex(okFill)}');
      await vqCapture(t, key, '${tag}_4confirm', conditions: {...cond, 'state': '운영 종료 위험 확인창(취소 전)'});
      await t.tap(cancel);
      await settle(16);
      must('①종료 취소 → 확인창 닫힘', title.evaluate().isEmpty);
      must('①종료 취소 뒤 archive 호출 0', archiveCalls == 0, '$archiveCalls');
      must('①종료 취소 뒤 목록 유지', findVisibleText(b1.name).evaluate().length == 1);
      await t.pumpWidget(const SizedBox.shrink());
      await settle(4);
      // ── ② SubAdmin ──
      key = await pumpList(subAdmin: true, canManage: true);
      {
        final sheet = await openMenu(b1, '②');
        menuCheck('②', b1, sheet, subAdmin: true, canManage: true);
        expectedColor += 1 + 2 * _menuExpect(b1, subAdmin: true, canManage: true).length;
        await vqCapture(t, key, '${tag}_5menu_subadmin', conditions: {...cond, 'state': 'SubAdmin b1 메뉴 시트'});
        await closeSheet('②', b1, sheet);
        final b3 = _four[2];
        final s3 = await openMenu(b3, '②');
        menuCheck('②', b3, s3, subAdmin: true, canManage: true);
        expectedColor += 1 + 2 * _menuExpect(b3, subAdmin: true, canManage: true).length;
        await closeSheet('②', b3, s3);
        await t.scrollUntilVisible(findVisibleText(_four.last.name), 200, scrollable: scroll(), maxScrolls: 40);
        await t.drag(scroll(), const Offset(0, -2000));
        await settle(8);
        must('② SubAdmin 추가 타일 0', findVisibleText('새 사업장 추가').evaluate().isEmpty);
      }
      await t.pumpWidget(const SizedBox.shrink());
      await settle(4);
      // ── ③ 소유자 · 관리 권한 없음 ──
      key = await pumpList(subAdmin: false, canManage: false);
      {
        final sheet = await openMenu(b1, '③');
        menuCheck('③', b1, sheet, subAdmin: false, canManage: false);
        expectedColor += 1 + 2 * _menuExpect(b1, subAdmin: false, canManage: false).length;
        await closeSheet('③', b1, sheet);
      }
      must('색 검사 계수(더보기 · 항목 아이콘/라벨 · 추가 타일) = 기대 $expectedColor', colorChecks == expectedColor, '$colorChecks');
      must('사전 조회 총 1 · archive 0', previewCalls.length == 1 && archiveCalls == 0);
      _out('$tag checks=$checks overflows=${overflows.length} beforeObs=$_beforeObs colorChecks=$colorChecks');
      final ok = checks.values.every((v) => v);
      _out('KNOWN ${ok ? 'ok' : 'NG'} $tag ${checks.entries.where((e) => !e.value).map((e) => e.key).toList()}');
      final exc = t.takeException();
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 1));
      expect(exc, isNull);
      expect(overflows, isEmpty, reason: '$tag 넘침(불변)');
      if (!_beforeObs) {
        for (final e in checks.entries) {
          expect(e.value, isTrue, reason: '$tag ${e.key}');
        }
      }
    });
  }
}
