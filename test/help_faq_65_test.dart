// [.65] 도움말 FAQ — 사용자 화면(HelpScreen)이 SA 가 저장한 내용을 그대로, 실패와 구분해서 보이는가.
//
// 근거(기기 c64b 반례):
//   - SA 가 '공고 & 지원'으로 추가한 질문(맨 끝 순서)이 '계정 & 서류' 아래에 보였다 — 분류가 아니라 순서로 묶었다.
//   - 로그인 없이 읽기가 거절되자 서버에 없는 내장 질문을 현재 내용처럼 보였다 — 실패를 빈 목록으로 삼켰다.
import 'dart:async';

import 'support/visible_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/help_faq_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/help_screen.dart';
import 'package:ALfit/services/help_faq_service.dart';

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

class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'W', username: 'w', name: '김근로', email: 'w@alfit.local', role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구'), accountStatus: 'active');
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => false;
}

HelpFaqModel _h(int o, String c) => HelpFaqModel(id: 'h$o', role: 'user', order: o, category: c, question: c, answer: '', isHeader: true, isActive: true);
HelpFaqModel _q(int o, String c, String q, [String a = '답변']) => HelpFaqModel(id: 'q$o', role: 'user', order: o, category: c, question: q, answer: a, isHeader: false, isActive: true);

const _long = '야간 물류센터에서 분류 작업을 마친 뒤 연장 근무를 했는데 그 시간이 급여에 어떻게 반영되는지 알고 싶어요';
const _longAnswer = '연장 근무는 관리자가 실제 퇴근 시간을 확인해 급여 확정 때 반영합니다.\n\n'
    '확정 뒤에는 근무 일정의 임금명세서에서 반영된 시간과 금액을 확인할 수 있습니다.';

Future<void> _pump(WidgetTester t, Future<HelpFaqLoad> Function(String) load, {Size size = const Size(392, 1600), double scale = 1.0}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _P(),
    child: MaterialApp(
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: HelpScreen(load: load),
    ),
  ));
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('[F65-a] 저장된 분류로 묶는다 — 맨 끝 순서로 추가한 질문도 자기 분류 아래', (t) async {
    await _pump(t, (_) async => HelpFaqLoad([
          _h(0, '📋 공고 & 지원'), _q(1, '📋 공고 & 지원', '공고에 어떻게 지원하나요?'),
          _h(2, '👤 계정 & 서류'), _q(3, '👤 계정 & 서류', '본인인증은 언제 하나요?'),
          _q(20, '📋 공고 & 지원', 'T65 새 질문'),
        ], configured: true));
    final apply = t.getTopLeft(findVisibleText('공고 & 지원')).dy;
    final account = t.getTopLeft(findVisibleText('계정 & 서류')).dy;
    final newQ = t.getTopLeft(findVisibleText('T65 새 질문')).dy;
    expect(newQ, greaterThan(apply));
    expect(newQ, lessThan(account), reason: '공고 & 지원 묶음 안');
  });

  testWidgets('[F65-b] 읽기 실패 — 내장 FAQ 를 보이지 않고 오류·다시 시도, 회복하면 서버 내용', (t) async {
    var fail = true;
    await _pump(t, (_) async {
      if (fail) throw Exception('permission-denied');
      return HelpFaqLoad([_h(0, '📋 공고 & 지원'), _q(1, '📋 공고 & 지원', '서버 질문')], configured: true);
    });
    expect(findVisibleText('도움말을 불러오지 못했습니다'), findsOneWidget);
    expect(findVisibleText('공고에 어떻게 지원하나요?'), findsNothing, reason: '내장 질문');
    expect(findVisibleText('등록된 도움말이 없습니다'), findsNothing);
    fail = false;
    await t.tap(findVisibleText('다시 시도'));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(findVisibleText('서버 질문'), findsOneWidget);
  });

  testWidgets('[F65-c] 모두 비활성(문서는 있음) → 빈 안내 · 문서가 아예 없음 → 내장 FAQ(기존 계약)', (t) async {
    await _pump(t, (_) async => const HelpFaqLoad([], configured: true));
    expect(findVisibleText('등록된 도움말이 없습니다'), findsOneWidget);
    expect(findVisibleText('공고에 어떻게 지원하나요?'), findsNothing);
    await _pump(t, (_) async => const HelpFaqLoad([], configured: false));
    expect(findVisibleText('공고에 어떻게 지원하나요?'), findsOneWidget);
  });

  testWidgets('[F65-d] 로딩 중에는 내장 FAQ 를 먼저 보이지 않는다', (t) async {
    final never = Completer<HelpFaqLoad>().future; // 끝나지 않는 읽기
    await _pump(t, (_) => never);
    expect(findVisibleText('공고에 어떻게 지원하나요?'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('[F65-e] 질문 행 전체가 조작점 · 펼침 상태를 낭독', (t) async {
    final h = t.ensureSemantics();
    await _pump(t, (_) async => HelpFaqLoad([_h(0, '📋 공고 & 지원'), _q(1, '📋 공고 & 지원', '공고에 어떻게 지원하나요?', '서버 답변')], configured: true));
    SemanticsNode node() => t.getSemantics(find.ancestor(of: findVisibleText('공고에 어떻게 지원하나요?'), matching: find.byType(Semantics)).first);
    expect(node().hasFlag(SemanticsFlag.hasExpandedState), isTrue);
    expect(node().hasFlag(SemanticsFlag.isExpanded), isFalse);
    await t.tap(findVisibleText('공고에 어떻게 지원하나요?'));
    await t.pump();
    expect(findVisibleText('서버 답변'), findsOneWidget);
    expect(node().hasFlag(SemanticsFlag.isExpanded), isTrue);
    h.dispose();
  });

  for (final c in const [(Size(392, 844), 1.0), (Size(320, 640), 1.3), (Size(392, 844), 2.0)]) {
    testWidgets('[F65-f] 긴 질문·여러 문단 답변 — 말줄임·넘침 없음 ${c.$1.width.toInt()}·${c.$2}', (t) async {
      await _pump(t, (_) async => HelpFaqLoad([_h(0, '💰 급여 & 임금명세서 — 연장 근무와 공제 항목 안내'), _q(1, '💰 급여 & 임금명세서 — 연장 근무와 공제 항목 안내', _long, _longAnswer)], configured: true),
          size: c.$1, scale: c.$2);
      await t.tap(findVisibleTextContaining('야간 물류센터에서'));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(findVisibleTextContaining('임금명세서에서 반영된 시간'), findsOneWidget);
      final q = t.widget<Text>(findVisibleTextContaining('야간 물류센터에서'));
      expect(q.overflow, isNot(TextOverflow.ellipsis));
      expect(q.maxLines, isNull);
    });
  }
}
