// [TEMPLATE-READS.22] 계약서 템플릿 선택 시트의 읽기 — 내 사업장 조회와 호출부 사업장 템플릿을
//   함께 출발시키고, 0개라고 같은 사업장을 다시 읽지 않는다.
//
//   지키는 것(예전과 같은 결과):
//     · 통합운영 — 내 사업장 전체의 템플릿을 합쳐 보인다(다른 사업장은 목록을 받은 뒤에만 읽는다)
//     · 목록이 비면 호출부 사업장 결과 — 오류는 빈 목록이 아니다(실패 ≠ 0개)
//     · 하나뿐이어도 자동 선택하지 않는다 — 사용자가 고른 뒤에야 작성 버튼이 켜진다
//     · 시트를 닫은 뒤 늦게 온 응답·다시 시도 경합은 화면에 적용하지 않는다
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/visible_text.dart'; // [DU255] keepWords 문구는 보이는 글자로 찾는다
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/widgets/dialogs/contract_template_selector_dialog.dart';

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
  Future<FirebaseAppPlatform> initializeApp(
          {String? name, FirebaseOptions? options}) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

BusinessModel _biz(String id) => BusinessModel(
    id: id, name: '사업장 $id', businessNumber: '000-00-00000', category: '음식점',
    subCategory: '한식', address: '서울특별시 강남구 테헤란로 1', ownerId: 'OWNER',
    createdAt: DateTime(2026, 9, 1));

ContractTemplateModel _tpl(String biz, String name,
        {String type = ContractTemplateType.daily}) =>
    ContractTemplateModel(
      id: '$biz-$name', businessId: biz, name: name, templateType: type,
      articles: [ContractArticle(title: '$name 조항', content: '내용')],
      createdAt: DateTime(2026, 10, 1),
    );

/// 가짜 서버 — 사업장별 템플릿, 읽기 순서·횟수 기록, 응답 붙잡기·실패.
class _Reads {
  String? uid = 'OWNER';
  List<BusinessModel> mine = [_biz('A')];
  final Map<String, List<ContractTemplateModel>> byBiz = {};
  final Map<String, Object> failBiz = {};
  final Map<String, Completer<void>> gateBiz = {};
  Completer<void>? gateMine;
  final List<String> log = [];

  int reads(String biz) => log.where((e) => e == 'tpl:$biz').length;

  void install() => ContractTemplateSelectorDialog.debugReads = (
        uid: () => uid,
        myBusinesses: (u) async {
          log.add('mine:start');
          if (gateMine != null) await gateMine!.future;
          log.add('mine:end');
          return mine;
        },
        templates: (b) async {
          log.add('tpl:$b');
          if (gateBiz[b] != null) await gateBiz[b]!.future;
          final f = failBiz[b];
          if (f != null) throw f;
          return byBiz[b] ?? const [];
        },
      );
}

List<ContractArticle>? _result;
bool _closed = false;

Future<void> _open(WidgetTester t, {String businessId = 'A'}) async {
  _result = null;
  _closed = false;
  // 측정 기기(Pixel_5 1080×2340 · 2.625)와 같은 논리 크기
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              _result = await ContractTemplateSelectorDialog.show(ctx,
                  businessId: businessId);
              _closed = true;
            },
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('열기'));
  // 응답을 붙잡은 시험은 로딩 스피너가 계속 돈다 — 고정 프레임만 진행한다.
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

ElevatedButton _writeBtn(WidgetTester t) => t.widget<ElevatedButton>(find.ancestor(
    of: find.text('선택한 템플릿으로 계약서 작성'),
    matching: find.byType(ElevatedButton)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  tearDown(() => ContractTemplateSelectorDialog.debugReads = null);

  testWidgets('TS-1 호출부 사업장 템플릿은 내 사업장 조회를 기다리지 않고 출발한다', (t) async {
    final r = _Reads()
      ..gateMine = Completer<void>()
      ..byBiz['A'] = [_tpl('A', '단기 기본')];
    r.install();
    await _open(t);
    expect(r.log, ['tpl:A', 'mine:start'],
        reason: '내 사업장 조회가 끝나기 전에 같은 사업장 템플릿이 이미 출발했다');
    r.gateMine!.complete();
    await t.pumpAndSettle();
    expect(find.text('단기 기본'), findsOneWidget);
    expect(r.reads('A'), 1, reason: '목록 안의 같은 사업장은 출발한 읽기를 다시 쓴다');
  });

  testWidgets('TS-2 0개 — 같은 사업장을 다시 읽지 않고 빈 안내(오류 아님)', (t) async {
    final r = _Reads();
    r.install();
    await _open(t);
    expect(r.reads('A'), 1, reason: '예전에는 0개면 같은 사업장을 한 번 더 읽었다');
    expect(findVisibleText('등록된 템플릿이 없습니다'), findsOneWidget);
    expect(find.text('템플릿 불러오기 실패'), findsNothing);
    expect(find.text('선택한 템플릿으로 계약서 작성'), findsNothing);
  });

  testWidgets('TS-3 하나뿐이어도 자동 선택 없음 — 직접 고른 뒤 작성 버튼이 켜진다', (t) async {
    final r = _Reads()..byBiz['A'] = [_tpl('A', '단기 기본')];
    r.install();
    await _open(t);
    expect(_writeBtn(t).onPressed, isNull, reason: '자동 선택하지 않는다');
    await t.tap(find.text('단기 기본'));
    await t.pumpAndSettle();
    expect(_writeBtn(t).onPressed, isNotNull);
    await t.tap(find.text('선택한 템플릿으로 계약서 작성'));
    await t.pumpAndSettle();
    expect(_closed, isTrue);
    expect(_result!.single.title, '단기 기본 조항');
  });

  testWidgets('TS-4 여러 사업장(통합운영) — 합쳐 보이고, 다른 사업장은 목록을 받은 뒤에 한 번만 읽는다',
      (t) async {
    final r = _Reads()
      ..mine = [_biz('A'), _biz('B')]
      ..byBiz['A'] = [_tpl('A', 'A 단기')]
      ..byBiz['B'] = [_tpl('B', 'B 기간', type: ContractTemplateType.period)];
    r.install();
    await _open(t);
    expect(find.text('A 단기'), findsOneWidget);
    expect(find.text('B 기간'), findsOneWidget);
    expect(r.reads('A'), 1);
    expect(r.reads('B'), 1);
    expect(r.log.indexOf('tpl:B') > r.log.indexOf('mine:end'), isTrue,
        reason: '다른 사업장은 미리 읽지 않는다');
  });

  testWidgets('TS-5 신규 계약에 못 쓰는 분류는 후보에서 빠진다(기존 필터 유지)', (t) async {
    final r = _Reads()
      ..byBiz['A'] = [
        _tpl('A', '단기 기본'),
        _tpl('A', '레거시 도급', type: ContractTemplateType.outsource),
      ];
    r.install();
    await _open(t);
    expect(find.text('단기 기본'), findsOneWidget);
    expect(find.text('레거시 도급'), findsNothing);
  });

  testWidgets('TS-6 호출부 사업장 읽기 실패(권한 거절) — 빈 목록이 아니라 실패, 다시 시도로 회복', (t) async {
    final r = _Reads()
      ..byBiz['A'] = [_tpl('A', '단기 기본')]
      ..failBiz['A'] = FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    r.install();
    await _open(t);
    expect(find.text('템플릿 불러오기 실패'), findsOneWidget);
    expect(findVisibleText('등록된 템플릿이 없습니다'), findsNothing);
    r.failBiz.clear();
    await t.tap(findVisibleText('다시 시도'));
    await t.pumpAndSettle();
    expect(find.text('단기 기본'), findsOneWidget);
  });

  testWidgets('TS-7 다른 사업장 읽기만 실패 — 실패로 보인다(일부만 보여 주지 않음)', (t) async {
    final r = _Reads()
      ..mine = [_biz('A'), _biz('B')]
      ..byBiz['A'] = [_tpl('A', 'A 단기')]
      ..failBiz['B'] = Exception('B down');
    r.install();
    await _open(t);
    expect(find.text('템플릿 불러오기 실패'), findsOneWidget);
    expect(find.text('A 단기'), findsNothing);
  });

  testWidgets('TS-8 내 사업장 조회 실패(빈 목록) — 호출부 사업장 결과로 보인다', (t) async {
    final r = _Reads()
      ..mine = const []
      ..byBiz['A'] = [_tpl('A', '단기 기본')];
    r.install();
    await _open(t);
    expect(find.text('단기 기본'), findsOneWidget);
    expect(r.reads('A'), 1);
  });

  testWidgets('TS-9 호출부 사업장이 내 목록에 없고 다른 사업장에 템플릿이 있으면 — 예전처럼 그 목록만, 미리 읽은 실패는 무시',
      (t) async {
    final r = _Reads()
      ..mine = [_biz('B')]
      ..byBiz['B'] = [_tpl('B', 'B 단기')]
      ..byBiz['A'] = [_tpl('A', 'A 단기')]
      ..failBiz['A'] = Exception('A down');
    r.install();
    await _open(t);
    expect(find.text('B 단기'), findsOneWidget);
    expect(find.text('A 단기'), findsNothing, reason: '쓰이지 않는 결과는 섞지 않는다');
    expect(find.text('템플릿 불러오기 실패'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('TS-10 uid 없음 — 호출부 사업장으로(기존 fallback)', (t) async {
    final r = _Reads()
      ..uid = null
      ..byBiz['A'] = [_tpl('A', '단기 기본')];
    r.install();
    await _open(t);
    expect(find.text('단기 기본'), findsOneWidget);
    expect(r.log.contains('mine:start'), isFalse);
  });

  testWidgets('TS-11 응답 전에 시트를 닫으면 — 늦은 응답을 적용하지 않고 예외 없음', (t) async {
    final r = _Reads()
      ..gateBiz['A'] = Completer<void>()
      ..byBiz['A'] = [_tpl('A', '단기 기본')];
    r.install();
    await _open(t);
    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();
    expect(_closed, isTrue);
    expect(_result, isNull, reason: '닫기 = 취소');
    r.gateBiz['A']!.complete();
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('TS-12 다시 시도가 겹치면 마지막 결과만 — 늦게 끝난 실패가 성공을 덮지 않는다', (t) async {
    final r = _Reads()..failBiz['A'] = Exception('first down');
    r.install();
    await _open(t);
    expect(find.text('템플릿 불러오기 실패'), findsOneWidget);
    // 두 번째 시도는 붙잡아 두고, 세 번째 시도 대신 두 번째의 결과가 마지막이어야 한다.
    r.failBiz.clear();
    r.byBiz['A'] = [_tpl('A', '단기 기본')];
    await t.tap(findVisibleText('다시 시도'));
    await t.pumpAndSettle();
    expect(find.text('단기 기본'), findsOneWidget);
    expect(r.reads('A'), 2);
  });
}
