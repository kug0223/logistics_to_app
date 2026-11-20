// ignore_for_file: depend_on_referenced_packages
// [DU1 후속89·90] S038 DocumentManagementScreen — 국내 USER · 신분증/급여계좌/세무정보 미등록 · 세무상태 성공 응답 뒤 정상 화면.
//   host: LOCAL dummy route → 보통 MaterialPageRoute push(USER 마이탭 진입과 같은 route 종류 — 실제 마이탭/auth/readiness 아님).
//   Theme: RoleTheme.getThemeByRole('USER'). Core fake(storageBucket 포함 — StorageService 필드). 국내 USER 대역(active·isIdVerified=false).
//   세무상태: init 의 callableGetTaxIdentityStatus(asia-northeast3) 를 Functions 채널 fake 로 성공 응답:
//     {registered:false, collectionEnabled:true, identifierType:null, foreignRecoveryAvailable:false, documentMatch:'UNASSESSED', documentMatchCurrent:false}
//     호출 1회 + **응답 처리 뒤 상태**(세무정보 카드·'세무정보 등록하기'·세무 '미등록' 표시, 로딩/조회실패 문구 없음)를 단언.
//     다른 Functions 이름은 not-found 로 막고 0, Firestore 10 op 는 막고 0 을 단언. 그 밖의 채널(Storage 등)은 계측하지 않는다.
//   등록·수정·삭제·사진·업로드·저장·뒤로·링크는 누르지 않는다(hitTest 만).
//   셀: N 392×851@1.0(상30/하24) · B 320×640@2.0(inset 0) — 같은 fixture, 본문 owner 실제 drag 로 말단까지, 프레임별 보이는 글 전부 기록.
//   [DU1 구현134] taxMismatch=true(새 2 case 만): 세무 fake 를 {registered:true, identifierType:'KOREAN_RRN', documentMatch:'MISMATCH', documentMatchCurrent:true}
//     로 바꿔 D 의 불일치 안내(blocksApply)를 LOCAL 주입 상태로 그린다. 실제 신원 대조 writer·서버 정책·지원 차단은 검증하지 않는다.
//   [DU1 구현139] taxMismatch → tax(_Tax.unregistered / mismatch / matched). matched 는 documentMatch:'MATCHED'(등록 완료, 불일치 안내 없음).
//     국내 세무 registered(mismatch · matched)의 '수정' receiver ≥48×48 · 중심 hit 를 after 계약으로 단언한다(DU139_ASSERT_TAX_RECEIVER, 기본 true).
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/foundation.dart' show DiagnosticsTreeStyle, TextTreeRenderer;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/document_management_screen.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p', storageBucket: 'p.appspot.com');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _UserDouble extends UserProvider {
  // [DU1 구현128] registered = 신분증·계좌·통장사본 제출 합성값(test/document_destination_target_test.dart _UserDouble(registered) 63~76 이식). 기본 false 는 예전과 같다.
  _UserDouble({this.registered = false});
  final bool registered;
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER,
        accountStatus: 'active', isIdVerified: registered,
        idCardImagePath: registered ? 'id_cards/u1/id.jpg' : null,
        bankName: registered ? '국민은행' : null,
        accountNumber: registered ? '123456789012' : null,
        accountHolder: registered ? '김근로' : null,
        bankbookImagePath: registered ? 'bankbooks/u1/bb.jpg' : null);
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
}

const _fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
const _registerLabels = ['신분증 등록하기', '세무정보 등록하기', '급여정보 등록하기'];
// [DU1 구현128] 등록 완료 상태의 행동 라벨(신분증 재등록·세무 미등록 그대로·계좌 변경). 이 상태에서는 도달만 단언하고 크기·hit 는 관측한다.
const _doneLabels = ['다시 등록하기', '세무정보 등록하기', '계좌 변경하기'];
// [DU1 구현134 · 139] 국내 세무 registered(불일치 · 일치) 상태의 행동 라벨 — 세무 등록 CTA 대신 '수정' 글자 버튼. 도달 단언, '수정'만 48 단언(구현139).
const _taxRegisteredLabels = ['다시 등록하기', '수정', '계좌 변경하기'];
// [DU1 구현139] 세무 응답 상태(LOCAL 주입). unregistered 는 기존 기본값이다.
enum _Tax { unregistered, mismatch, matched }
// [DU1 구현139 ③] 수정 receiver 48×48 after 계약 — before 실행만 --dart-define=DU139_ASSERT_TAX_RECEIVER=false 로 끈다.
const _assertTaxReceiver = bool.fromEnvironment('DU139_ASSERT_TAX_RECEIVER', defaultValue: true);
const _mismatchNotice = '등록한 세무정보와 신분증 정보가 달라 보입니다.\n세무정보를 수정하거나 신분증을 다시 등록해주세요.';

Future<void> _cell(WidgetTester t, {required String id, required Size size, required double scale, required bool insets,
    required double dragDy, bool ko = false, bool registered = false, _Tax tax = _Tax.unregistered}) async {
  final taxMismatch = tax == _Tax.mismatch;
  final taxRegistered = tax != _Tax.unregistered; // 국내 세무 registered(불일치 · 일치) — '수정' 버튼 분기
  final labels = taxRegistered ? _taxRegisteredLabels : (registered ? _doneLabels : _registerLabels);
  await t.runAsync(vqLoadFonts);
  SharedPreferences.setMockInitialValues({});
  final calls = <String, int>{};
  void inc(String k) => calls[k] = (calls[k] ?? 0) + 1;
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMessageHandler(_fnChannel, (msg) async {
    const c = StandardMessageCodec();
    final args = (c.decodeMessage(msg) as List).first as Map;
    final name = args['functionName'];
    final region = args['region'];
    inc('functions $name@$region');
    if (name == 'callableGetTaxIdentityStatus' && region == 'asia-northeast3') {
      return c.encodeMessage(<Object?>[
        taxRegistered
            // [DU1 구현134] 국내 정본 identifierType(functions/src/index.ts:2533) · MISMATCH parser(identity_identifier.dart:44~48) · 지금 신분증 기준
            // [DU1 구현139] matched 는 'MATCHED'(parser 같은 곳) — blocksApply false · 칩 '등록 완료'
            ? <String, Object?>{
                'registered': true, 'collectionEnabled': true, 'identifierType': 'KOREAN_RRN',
                'foreignRecoveryAvailable': false, 'documentMatch': taxMismatch ? 'MISMATCH' : 'MATCHED', 'documentMatchCurrent': true,
              }
            : <String, Object?>{
                'registered': false, 'collectionEnabled': true, 'identifierType': null,
                'foreignRecoveryAvailable': false, 'documentMatch': 'UNASSESSED', 'documentMatchCurrent': false,
              }
      ]);
    }
    return c.encodeMessage(<Object?>['not-found', 'blocked', <String, Object?>{'code': 'not-found'}]);
  });
  for (final op in const ['documentReferenceGet', 'queryGet', 'documentReferenceSet', 'documentReferenceUpdate',
    'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
    m.setMockMessageHandler('$_fsBase.$op', (msg) async {
      inc('firestore $op');
      return null;
    });
  }
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  if (insets) {
    t.view.padding = const FakeViewPadding(top: 30, bottom: 24);
    t.view.viewPadding = const FakeViewPadding(top: 30, bottom: 24);
  }
  addTearDown(t.view.reset);
  final overflows = <String>[];
  // [DU1 구현135] 넘침 원 진단 — 예외 전문 · context · 진단 트리(관련 위젯 생성 위치 포함) · stack 앞 12줄. 실패 단언 전에 print 한다.
  final overflowDetails = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final s = d.exceptionAsString();
    if (s.contains('overflowed')) {
      overflows.add(s.split('\n').first);
      String tree;
      try {
        tree = TextTreeRenderer(wrapWidth: 160).render(d.toDiagnosticsNode(style: DiagnosticsTreeStyle.error)).trimRight();
      } catch (e) {
        tree = '(진단 트리 렌더 실패 $e)';
      }
      overflowDetails.add('예외: $s\ncontext: ${d.context?.toDescription()}\n--- 진단 트리 ---\n$tree'
          '\n--- stack(앞 12줄) ---\n${(d.stack?.toString() ?? '(stack 없음)').split('\n').take(12).join('\n')}');
    } else {
      prev?.call(d);
    }
  };
  addTearDown(() => FlutterError.onError = prev); // 보조 — 주 복구는 _cell 끝의 finally
  // [DU1 구현135] handler 교체 범위 — 중간 단언·촬영·비동기 실패도 binding 에 전달되기 전에 원 handler 로 복구한다(감사135 §4).
  //   아래 본문은 들여쓰기를 바꾸지 않고 이 try 안에 둔다(diff 최소화). 끝은 _cell 맨 아래 finally.
  try {
  final key = GlobalKey();
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _UserDouble(registered: registered),
    child: RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RoleTheme.getThemeByRole('USER'),
        // [DU1 구현121] ko 이면 앱 main(209~217)의 delegates·지원 목록 + LOCAL ko_KR 명시. 기본(ko=false)은 기존과 같은 무지정·기본값이다.
        locale: ko ? const Locale('ko', 'KR') : null,
        localizationsDelegates: ko
            ? const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate]
            : null,
        supportedLocales: ko ? const [Locale('ko', 'KR'), Locale('en', 'US')] : const <Locale>[Locale('en', 'US')],
        builder: (ctx, child) =>
            MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const DocumentManagementScreen())),
            child: const Text('host'))))),
      ),
    ),
  ));
  await t.tap(find.text('host'));
  for (var i = 0; i < 14; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  expect(t.takeException(), isNull);
  final screen = find.byType(DocumentManagementScreen);
  expect(screen, findsOneWidget);
  expect(calls['functions callableGetTaxIdentityStatus@asia-northeast3'], 1, reason: '세무상태 1회');
  // 응답 처리 뒤 상태 — 세무 카드·등록 CTA·세무 '미등록' 표시(조회 실패/확인 불가가 아니다)
  expect(find.text('세무정보'), findsOneWidget, reason: '세무 카드(collectionEnabled=true 응답 처리 뒤)');
  if (taxMismatch) {
    // [DU1 구현134] 불일치 상태 — 세무 등록 CTA 없음, 칩 '정보 확인 필요'·대상 안내 두 문장·'수정' 버튼이 구성됐다.
    expect(find.text('세무정보 등록하기'), findsNothing, reason: '불일치 상태에는 세무 등록 CTA 없음');
    expect(find.text('정보 확인 필요'), findsOneWidget, reason: '세무 칩 정보 확인 필요');
    expect(find.text(_mismatchNotice), findsOneWidget, reason: '불일치 안내 두 문장');
    expect(find.text('수정'), findsOneWidget, reason: '세무 수정 글자 버튼');
  } else if (tax == _Tax.matched) {
    // [DU1 구현139] 등록 일치 상태 — 세무 등록 CTA 없음, 칩 '등록 완료', 불일치 안내 없음, '수정' 1, 번호 비표시 안내 전문.
    expect(find.text('세무정보 등록하기'), findsNothing, reason: '등록 일치 상태에는 세무 등록 CTA 없음');
    expect(find.text('등록 완료'), findsOneWidget, reason: '세무 칩 등록 완료');
    expect(find.text(_mismatchNotice), findsNothing, reason: '등록 일치 상태에는 불일치 안내 없음');
    expect(find.text('수정'), findsOneWidget, reason: '세무 수정 글자 버튼');
    expect(find.text('등록된 번호는 표시되지 않습니다'), findsOneWidget, reason: '번호 비표시 안내 전문');
  } else {
    expect(find.text('세무정보 등록하기'), findsOneWidget, reason: '세무 등록 CTA');
  }
  expect(find.text('확인 불가'), findsNothing, reason: '조회 실패 칩 아님');
  final mq = MediaQuery.of(t.element(screen));
  bool hits(Finder f, Offset p) {
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
    return hit.path.any((e) => e.target == t.renderObject(f));
  }
  final scroll = find.descendant(of: screen, matching: find.byType(Scrollable)).first;
  final pos = t.state<ScrollableState>(scroll).position;
  final vp = t.getRect(scroll);
  final out = <String>[
    'mq padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} size=${mq.size}',
    '본문 [${pos.axis.name}] $vp max=${pos.maxScrollExtent.toStringAsFixed(1)} off=${pos.pixels.toStringAsFixed(1)}',
  ];
  final ml = MaterialLocalizations.of(t.element(screen));
  final localeNote = 'locale requested=${ko ? 'ko_KR' : '없음(기본)'} · resolved=${Localizations.localeOf(t.element(screen))}'
      ' · ${ml.runtimeType} · scriptCategory=${ml.scriptCategory} · semanticsEnabled=${t.binding.semanticsEnabled}';
  if (ko) out.insert(0, localeNote);
  // 프레임별 viewport 와 교차하는 모든 Text(개수 제한 없음) — 연속 읽기 근거
  String visible(String when) {
    final parts = <String>[];
    for (final e in find.descendant(of: screen, matching: find.byType(Text)).evaluate()) {
      final w = e.widget as Text;
      final s = (w.data ?? w.textSpan?.toPlainText() ?? '').replaceAll('⁠', '');
      if (s.trim().isEmpty) continue;
      final box = e.renderObject as RenderBox;
      final r = box.localToGlobal(Offset.zero) & box.size;
      final v = r.intersect(vp);
      if (v.width > 0 && v.height > 0) {
        parts.add('"${s.replaceAll('\n', '⏎')}"(${v.height.toStringAsFixed(0)}/${r.height.toStringAsFixed(0)})');
      }
    }
    return '$when off=${pos.pixels.toStringAsFixed(1)} 보이는 글 ${parts.length}: ${parts.join(' ')}';
  }
  final back = find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton)).first;
  final rb = t.getRect(back);
  out.add('뒤로 IconButton $rb ${rb.width.toStringAsFixed(1)}×${rb.height.toStringAsFixed(1)} hit=${hits(back, rb.center)}');
  final btn = <String, ({Rect r, bool hit, String when})>{};
  void btnFrame(String when) {
    for (final l in labels) {
      final txt = find.text(l);
      if (txt.evaluate().isEmpty) continue;
      final b = find.ancestor(of: txt, matching: find.byType(InkWell)).first;
      final r = t.getRect(b);
      if (r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5 && !btn.containsKey(l)) {
        btn[l] = (r: r, hit: hits(b, r.center), when: when);
        out.add('$when 버튼 "$l" $r ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} hit=${btn[l]!.hit}');
      }
    }
  }
  // [DU1 구현129 C128-1] 등록 완료 상태의 '삭제' 글자 버튼 2개 — 각자 표시 영역에 든 첫 프레임의 receiver·hit·왼쪽 글자 버튼과의 겹침(출력만).
  final delSeen = <int>{};
  void delFrame(String when) {
    if (!registered) return;
    final tf = find.text('삭제');
    for (var i = 0; i < tf.evaluate().length; i++) {
      if (delSeen.contains(i)) continue;
      final tb = find.ancestor(of: tf.at(i), matching: find.byType(TextButton)).first;
      final r = t.getRect(tb);
      if (r.top < vp.top - 0.5 || r.bottom > vp.bottom + 0.5) continue;
      delSeen.add(i);
      String pairNote = '같은 행 왼쪽 글자 버튼 없음';
      for (final l in const ['다시 등록하기', '계좌 변경하기']) {
        final lf = find.text(l);
        if (lf.evaluate().isEmpty) continue;
        final lr = t.getRect(find.ancestor(of: lf, matching: find.byType(TextButton)).first);
        if ((lr.center.dy - r.center.dy).abs() < 1.0) {
          pairNote = '같은 행 "$l" $lr 겹침=${lr.overlaps(r)} 사이 ${(r.left - lr.right).toStringAsFixed(1)}';
        }
      }
      out.add('$when 삭제#${i + 1} TextButton $r ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} hit=${hits(tb, r.center)} · $pairNote');
    }
  }
  out.add(visible('초기'));
  btnFrame('초기');
  delFrame('초기');
  // [DU1 구현122 S038 V3] ko 전용 단계 머리 관측(출력만, 단언 아님) — 배지 rect·제목/설명 문단 rect·TextPainter 재배치 줄 상자.
  //   중심은 문단 상자·줄 상자 기준이다(광학 글리프 중심 아님). out 과 따로 모아 맨 뒤에 print 한다(sidecar measure 무변경).
  final probe = <String>[];
  String f1(double v) => v.toStringAsFixed(1);
  void labelProbe(String when) {
    for (final (n, title, desc) in const [
      ('1', '신원 확인', '지원자 본인 확인을 위해 필요해요'),
      ('2', '급여정보 준비', '근무 후 급여 지급을 위해 필요해요'),
    ]) {
      final nf = find.descendant(of: screen, matching: find.text(n));
      final tf = find.descendant(of: screen, matching: find.text(title));
      final df = find.descendant(of: screen, matching: find.text(desc));
      if (nf.evaluate().isEmpty || tf.evaluate().isEmpty || df.evaluate().isEmpty) {
        probe.add('$when 단계$n 미구성(번호 ${nf.evaluate().length} 제목 ${tf.evaluate().length} 설명 ${df.evaluate().length})');
        continue;
      }
      final badge = t.getRect(find.ancestor(of: nf.first, matching: find.byType(Container)).first);
      ({Rect r, int lines, double top, double bottom}) para(Finder f) {
        final rp = t.renderObject(f.first) as RenderParagraph;
        final r = t.getRect(f.first);
        final tp = TextPainter(
          text: rp.text, textAlign: rp.textAlign, textDirection: rp.textDirection, textScaler: rp.textScaler,
          maxLines: rp.maxLines, ellipsis: rp.overflow == TextOverflow.ellipsis ? '\u2026' : null, locale: rp.locale,
          strutStyle: rp.strutStyle, textWidthBasis: rp.textWidthBasis, textHeightBehavior: rp.textHeightBehavior,
        )..layout(minWidth: rp.constraints.minWidth, maxWidth: rp.constraints.maxWidth);
        final lm = tp.computeLineMetrics();
        tp.dispose();
        final l0 = lm.first;
        return (r: r, lines: lm.length, top: r.top + l0.baseline - l0.ascent, bottom: r.top + l0.baseline + l0.descent);
      }
      final ti = para(tf);
      final de = para(df);
      final bc = badge.center.dy;
      final tc = (ti.top + ti.bottom) / 2;
      final dc = (de.top + de.bottom) / 2;
      final gc = (ti.r.top + de.r.bottom) / 2;
      probe.add('$when 단계$n 배지 $badge c${f1(bc)}'
          ' | 제목 ${ti.r} 줄${ti.lines} 1줄[${f1(ti.top)}~${f1(ti.bottom)}] c${f1(tc)}'
          ' | 설명 ${de.r} 줄${de.lines} 1줄[${f1(de.top)}~${f1(de.bottom)}] c${f1(dc)}'
          ' | 배지c−제목1줄c ${f1(bc - tc)} · 배지c−설명1줄c ${f1(bc - dc)} · 배지c−묶음c ${f1(bc - gc)}'
          ' · 제목x ${f1(ti.r.left)} 설명x ${f1(de.r.left)}');
    }
  }
  if (ko) labelProbe('초기');
  // [DU1 구현123 S038 V7] ko 전용 표식·글자 비중 관측(출력만, 단언 아님) — 등록 버튼 아이콘/라벨 · 단계 배지 원/숫자.
  //   크기는 위젯 rect·명목값·textScaler 적용값이고, 라벨 여유는 제약 maxWidth − 한 줄 고유 폭이다(래스터 잉크는 별도 python).
  void markProbe(String when) {
    for (final l in registered ? const <String>[] : labels) {
      final tf = find.descendant(of: screen, matching: find.text(l));
      if (tf.evaluate().isEmpty) {
        probe.add('$when 버튼 "$l" 미구성');
        continue;
      }
      final rp = t.renderObject(tf.first) as RenderParagraph;
      final lr = t.getRect(tf.first);
      final row = find.ancestor(of: tf.first, matching: find.byType(Row)).first;
      final rr = t.getRect(row);
      final rowMax = (t.renderObject(row) as RenderBox).constraints.maxWidth;
      final icf = find.descendant(of: row, matching: find.byType(Icon));
      final ir = icf.evaluate().isEmpty ? null : t.getRect(icf.first);
      final isz = icf.evaluate().isEmpty ? null : t.widget<Icon>(icf.first).size;
      final fs = rp.text.style?.fontSize ?? 14;
      final intrinsic = rp.getMaxIntrinsicWidth(double.infinity);
      final br = t.getRect(find.ancestor(of: tf.first, matching: find.byType(InkWell)).first);
      probe.add('$when 버튼 "$l" receiver $br | Row $rr max${f1(rowMax)} | 아이콘 ${ir ?? '없음'} size${isz ?? '-'}'
          ' | 라벨 $lr 명목${f1(fs)}→${f1(rp.textScaler.scale(fs))} 제약max${f1(rp.constraints.maxWidth)}'
          ' 고유폭${f1(intrinsic)} 여유${f1(rp.constraints.maxWidth - intrinsic)} 넘침${rp.didExceedMaxLines}'
          ' | 아이콘h/라벨h ${ir == null ? '-' : (ir.height / lr.height).toStringAsFixed(2)}');
    }
    for (final n in const ['1', '2']) {
      final nf = find.descendant(of: screen, matching: find.text(n));
      if (nf.evaluate().isEmpty) {
        probe.add('$when 배지$n 미구성');
        continue;
      }
      final rp = t.renderObject(nf.first) as RenderParagraph;
      final cr = t.getRect(find.ancestor(of: nf.first, matching: find.byType(Container)).first);
      final dr = t.getRect(nf.first);
      final fs = rp.text.style?.fontSize ?? 12;
      probe.add('$when 배지$n 원 $cr | 숫자 $dr 명목${f1(fs)}→${f1(rp.textScaler.scale(fs))}'
          ' | 숫자h/원h ${(dr.height / cr.height).toStringAsFixed(2)} · 위/아래 여백 ${f1(dr.top - cr.top)}/${f1(cr.bottom - dr.bottom)}');
    }
    if (!registered) return;
    // [DU1 구현128] 등록 완료 관측(출력만) — 완료 배지 원·체크 아이콘(명목 size) · 행동 글자 링크와 삭제 링크의 TextButton receiver·hit.
    final checks = find.descendant(of: screen, matching: find.byIcon(Icons.check_rounded));
    for (var i = 0; i < checks.evaluate().length; i++) {
      final ic = checks.at(i);
      final ir = t.getRect(ic);
      final cr = t.getRect(find.ancestor(of: ic, matching: find.byType(Container)).first);
      probe.add('$when 완료배지${i + 1} 원 $cr | 체크 $ir 명목 size${t.widget<Icon>(ic).size}'
          ' | 아이콘h/원h ${(ir.height / cr.height).toStringAsFixed(2)} · 위/아래 여백 ${f1(ir.top - cr.top)}/${f1(cr.bottom - ir.bottom)}');
    }
    for (final l in taxRegistered ? const ['다시 등록하기', '수정', '계좌 변경하기', '삭제'] : const ['다시 등록하기', '계좌 변경하기', '삭제']) {
      final tf = find.descendant(of: screen, matching: find.text(l));
      for (var i = 0; i < tf.evaluate().length; i++) {
        final tb = find.ancestor(of: tf.at(i), matching: find.byType(TextButton)).first;
        final br = t.getRect(tb);
        final st = (t.renderObject(tf.at(i)) as RenderParagraph).text.style;
        probe.add('$when 링크 "$l"#${i + 1} TextButton $br ${f1(br.width)}×${f1(br.height)} hit=${hits(tb, br.center)}'
            ' · 글 ${t.getRect(tf.at(i))} 명목 ${st?.fontSize}→${f1((t.renderObject(tf.at(i)) as RenderParagraph).textScaler.scale(st?.fontSize ?? 13))} 색 ${st?.color}');
      }
    }
    // [DU1 구현131 C128-2] 삭제 아이콘의 실제 적용 색(IconTheme 상속, 출력만).
    final dels = find.descendant(of: screen, matching: find.byIcon(Icons.delete_outline));
    for (var i = 0; i < dels.evaluate().length; i++) {
      final c = IconTheme.of(t.element(dels.at(i))).color;
      probe.add('$when 삭제아이콘#${i + 1} ${t.getRect(dels.at(i))} size${t.widget<Icon>(dels.at(i)).size}'
          ' 적용색 ${c == null ? 'null' : '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}'}');
    }
    // [DU1 구현130 C128-3] 카드 머리 관측(출력만) — 제목 · 부제 · 상태 칩 글자의 rect · 줄 수(TextPainter 재배치) · 제약 · 고유 폭.
    for (final l in const ['신분증', '급여 계좌', '국민은행', '제출 완료']) {
      final tf = find.descendant(of: screen, matching: find.text(l));
      for (var i = 0; i < tf.evaluate().length; i++) {
        final rp = t.renderObject(tf.at(i)) as RenderParagraph;
        final tp = TextPainter(
          text: rp.text, textAlign: rp.textAlign, textDirection: rp.textDirection, textScaler: rp.textScaler,
          maxLines: rp.maxLines, locale: rp.locale, strutStyle: rp.strutStyle,
          textWidthBasis: rp.textWidthBasis, textHeightBehavior: rp.textHeightBehavior,
        )..layout(minWidth: rp.constraints.minWidth, maxWidth: rp.constraints.maxWidth);
        final lines = tp.computeLineMetrics().length;
        tp.dispose();
        probe.add('$when 머리 "$l"#${i + 1} ${t.getRect(tf.at(i))} 줄$lines 제약max${f1(rp.constraints.maxWidth)}'
            ' 고유폭${f1(rp.getMaxIntrinsicWidth(double.infinity))}');
      }
    }
  }
  if (ko) markProbe('초기');
  // [DU1 구현134] 세무 불일치 안내 관측(출력만, 단언 아님) — 안내 글 rect·명목/적용 크기·유효 weight·색·줄·제약·maxLines/ellipsis,
  //   바로 위 면 Container 의 rect·decoration 색(ARGB), 칩 '정보 확인 필요' 글·아이콘 색, '수정' TextButton receiver·hit, 회색 안내 글.
  String hex(Color? c) => c == null ? 'null' : '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
  void taxProbe(String when) {
    if (!taxRegistered) return;
    final nf = find.descendant(of: screen, matching: find.text(_mismatchNotice));
    // [DU1 구현139] 불일치 안내 probe 는 mismatch 전용 — 예전처럼 안내가 없을 때 return 하면 matched 의 세무글 · 수정 계측이 조용히 빠진다.
    if (taxMismatch && nf.evaluate().isEmpty) probe.add('$when 세무안내 미구성');
    if (taxMismatch && nf.evaluate().isNotEmpty) {
    final rp = t.renderObject(nf.first) as RenderParagraph;
    final st = rp.text.style;
    final tp = TextPainter(
      text: rp.text, textAlign: rp.textAlign, textDirection: rp.textDirection, textScaler: rp.textScaler,
      maxLines: rp.maxLines, locale: rp.locale, strutStyle: rp.strutStyle,
      textWidthBasis: rp.textWidthBasis, textHeightBehavior: rp.textHeightBehavior,
    )..layout(minWidth: rp.constraints.minWidth, maxWidth: rp.constraints.maxWidth);
    final lm = tp.computeLineMetrics();
    tp.dispose();
    final nr = t.getRect(nf.first);
    final face = find.ancestor(of: nf.first, matching: find.byType(Container)).first;
    final dec = t.widget<Container>(face).decoration;
    probe.add('$when 세무안내 글 $nr 명목${st?.fontSize}→${f1(rp.textScaler.scale(st?.fontSize ?? 14))}'
        ' weight ${st?.fontWeight ?? 'null(엔진 기본 w400)'} family ${st?.fontFamily} 색 ${hex(st?.color)}'
        ' 줄${lm.length} 줄폭[${lm.map((l) => f1(l.width)).join(',')}] 제약max${f1(rp.constraints.maxWidth)}'
        ' 고유폭${f1(rp.getMaxIntrinsicWidth(double.infinity))} maxLines ${rp.maxLines} overflow ${rp.overflow.name} 넘침${rp.didExceedMaxLines}'
        ' | 면 ${t.getRect(face)} 색 ${hex(dec is BoxDecoration ? dec.color : null)} radius ${dec is BoxDecoration ? dec.borderRadius : null}'
        ' | 보임 ${nr.intersect(vp).height.toStringAsFixed(1)}/${nr.height.toStringAsFixed(1)}');
    } // [DU1 구현139] 불일치 안내 probe 끝(위 블록은 들여쓰기를 바꾸지 않았다)
    for (final l in const ['정보 확인 필요', '등록 완료', '세무정보', '등록된 번호는 표시되지 않습니다']) {
      final tf = find.descendant(of: screen, matching: find.text(l));
      for (var i = 0; i < tf.evaluate().length; i++) {
        final rp2 = t.renderObject(tf.at(i)) as RenderParagraph;
        final s2 = rp2.text.style;
        // [DU1 구현135] 줄 수 · 제약 · 고유폭 · 넘침(출력만)
        final tp2 = TextPainter(text: rp2.text, textDirection: rp2.textDirection, textScaler: rp2.textScaler, maxLines: rp2.maxLines, locale: rp2.locale)
          ..layout(minWidth: rp2.constraints.minWidth, maxWidth: rp2.constraints.maxWidth);
        final n2 = tp2.computeLineMetrics().length;
        tp2.dispose();
        probe.add('$when 세무글 "$l"#${i + 1} ${t.getRect(tf.at(i))} 명목${s2?.fontSize} weight ${s2?.fontWeight} 색 ${hex(s2?.color)}'
            ' 줄$n2 제약max${f1(rp2.constraints.maxWidth)} 고유폭${f1(rp2.getMaxIntrinsicWidth(double.infinity))} 넘침${rp2.didExceedMaxLines}');
      }
    }
    final eo = find.descendant(of: screen, matching: find.byIcon(Icons.error_outline));
    for (var i = 0; i < eo.evaluate().length; i++) {
      probe.add('$when 세무칩아이콘#${i + 1} ${t.getRect(eo.at(i))} size${t.widget<Icon>(eo.at(i)).size}'
          ' 적용색 ${hex(IconTheme.of(t.element(eo.at(i))).color)} 위젯색 ${hex(t.widget<Icon>(eo.at(i)).color)}');
    }
    final ef = find.descendant(of: screen, matching: find.text('수정'));
    for (var i = 0; i < ef.evaluate().length; i++) {
      final tb = find.ancestor(of: ef.at(i), matching: find.byType(TextButton)).first;
      final br = t.getRect(tb);
      final vis = br.top >= vp.top - 0.5 && br.bottom <= vp.bottom + 0.5;
      final pf = find.ancestor(of: ef.at(i), matching: find.byWidgetPredicate((w) => w is Wrap || w is Row)).first;
      probe.add('$when 수정#${i + 1} TextButton $br ${f1(br.width)}×${f1(br.height)} 표시영역안=$vis hit=${vis ? hits(tb, br.center) : '-'}'
          ' · 글 ${t.getRect(ef.at(i))} · 줄 부모 ${t.widget(pf).runtimeType} ${t.getRect(pf)} 제약max${f1((t.renderObject(pf) as RenderBox).constraints.maxWidth)}');
    }
  }
  if (ko) taxProbe('초기');
  // [DU1 구현134] 대상 안내가 표시 영역에 든 프레임 — 처음 걸친 프레임부터 전부 든 프레임까지 촬영(최대 4장), 초기 전부 보임이면 _top 이 그 프레임이다.
  var noticeFull = false;
  var noticeShots = 0;
  String? noticeState(String when) {
    if (!taxMismatch || noticeFull) return null;
    final nf = find.descendant(of: screen, matching: find.text(_mismatchNotice));
    if (nf.evaluate().isEmpty) return null;
    final nr = t.getRect(nf.first);
    final v = nr.intersect(vp);
    if (v.width <= 0 || v.height <= 0) return null;
    final full = nr.top >= vp.top - 0.5 && nr.bottom <= vp.bottom + 0.5;
    if (full) noticeFull = true;
    final note = '$when 세무안내 ${full ? '전부' : '일부'} 보임 ${v.height.toStringAsFixed(1)}/${nr.height.toStringAsFixed(1)} rect $nr';
    out.add(note);
    return note;
  }
  noticeState('초기(top 프레임)');
  // [DU1 구현135] 수정 줄(수정 + 번호 비표시 안내)이 둘 다 표시 영역(가로·세로)에 전부 든 첫 프레임 — 촬영 1장. 초기 전부 보임이면 _top 이 그 프레임이다.
  var editRowFull = false;
  String? editRowState(String when) {
    if (!taxRegistered || editRowFull) return null; // [DU1 구현139] 불일치 · 일치 공통
    final ef = find.descendant(of: screen, matching: find.text('수정'));
    final hf = find.descendant(of: screen, matching: find.text('등록된 번호는 표시되지 않습니다'));
    if (ef.evaluate().isEmpty || hf.evaluate().isEmpty) return null;
    final er = t.getRect(find.ancestor(of: ef.first, matching: find.byType(TextButton)).first);
    final hr = t.getRect(hf.first);
    bool inVp(Rect r) => r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5 && r.left >= vp.left - 0.5 && r.right <= vp.right + 0.5;
    if (!(inVp(er) && inVp(hr))) return null;
    editRowFull = true;
    final note = '$when 수정 줄 전부 보임 · 수정 $er · 안내 $hr';
    out.add(note);
    return note;
  }
  editRowState('초기(top 프레임)');
  // [DU1 구현137] 카드 머리 3곳(신분증 · 세무정보 · 급여 계좌) 관측(출력만, 모든 case) — 머리 Row 안 모든 Text 의 rect · 줄 · 제약 · 고유폭 · 넘침,
  //   제목의 가장 가까운 Wrap / Row 부모 형식. 머리가 표시 영역(가로 · 세로)에 처음 전부 든 프레임을 촬영한다(초기 전부면 _top 이 그 프레임).
  const heads = ['신분증', '세무정보', '급여 계좌'];
  final headSeen = <String>{};
  Finder? headRow(String title) {
    final tf = find.descendant(of: screen, matching: find.text(title));
    if (tf.evaluate().isEmpty) return null;
    return find.ancestor(of: tf.first, matching: find.byType(Row)).first;
  }
  void headProbe(String when) {
    for (final h in heads) {
      final rf = headRow(h);
      if (rf == null) {
        probe.add('$when 머리 "$h" 미구성');
        continue;
      }
      final tf = find.descendant(of: screen, matching: find.text(h)).first;
      final pf = find.ancestor(of: tf, matching: find.byWidgetPredicate((w) => w is Wrap || w is Row)).first;
      probe.add('$when 머리 "$h" 행 ${t.getRect(rf)} · 제목 부모 ${t.widget(pf).runtimeType} ${t.getRect(pf)}');
      final texts = find.descendant(of: rf, matching: find.byType(RichText));
      for (var i = 0; i < texts.evaluate().length; i++) {
        final rp = t.renderObject(texts.at(i)) as RenderParagraph;
        if ((rp.text.style?.fontFamily ?? '').contains('MaterialIcons')) continue; // 칩 아이콘 글리프는 글이 아니다
        final tp = TextPainter(text: rp.text, textDirection: rp.textDirection, textScaler: rp.textScaler, maxLines: rp.maxLines, locale: rp.locale)
          ..layout(minWidth: rp.constraints.minWidth, maxWidth: rp.constraints.maxWidth);
        final lm = tp.computeLineMetrics();
        tp.dispose();
        final txt = rp.text.toPlainText().replaceAll('\n', '⏎');
        if (txt.trim().isEmpty) continue;
        probe.add('$when 머리 "$h" 글#${i + 1} "$txt" ${t.getRect(texts.at(i))} 줄${lm.length} 줄폭[${lm.map((l) => f1(l.width)).join(',')}]'
            ' 제약max${f1(rp.constraints.maxWidth)} 고유폭${f1(rp.getMaxIntrinsicWidth(double.infinity))} 넘침${rp.didExceedMaxLines} maxLines ${rp.maxLines} overflow ${rp.overflow.name}');
      }
    }
  }
  headProbe('초기');
  String? headState(String when) {
    final notes = <String>[];
    for (final h in heads) {
      if (headSeen.contains(h)) continue;
      final rf = headRow(h);
      if (rf == null) continue;
      final r = t.getRect(rf);
      if (r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5 && r.left >= vp.left - 0.5 && r.right <= vp.right + 0.5) {
        headSeen.add(h);
        notes.add('"$h" 머리 전부 보임 $r');
      }
    }
    if (notes.isEmpty) return null;
    final note = '$when ${notes.join(' · ')}';
    out.add(note);
    return note;
  }
  headState('초기(top 프레임)');
  await vqCapture(t, key, '${id}_top', conditions: {
    'screen': 'DocumentManagementScreen — dummy route → MaterialPageRoute push(마이탭 아님)', 'theme': "RoleTheme.getThemeByRole('USER')",
    'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'dpr': 1.0, 'textScaler': scale,
    'inset': insets ? '선언 padding/viewPadding top30 bottom24 · viewInsets 0' : '모두 0',
    'fixture': taxRegistered
        ? '국내 USER active · 신분증·계좌·통장사본 제출(DDT 합성값) · 세무 등록 · 지금 신분증 대조 ${taxMismatch ? 'MISMATCH' : 'MATCHED'}(LOCAL 주입) · 세무상태 성공(collectionEnabled:true)'
        : registered
        ? '국내 USER active · 신분증·계좌·통장사본 제출(DDT 합성값) · 세무 미등록 · 세무상태 성공(collectionEnabled:true)'
        : '국내 USER active · 신분증/계좌/세무 미등록 · 세무상태 성공(collectionEnabled:true)', 'fonts': 'vqLoadFonts 근사',
    if (ko) 'locale': localeNote,
    'scroll': 'off 0', 'measure': out.join(' | ')});
  var k = 0;
  while (pos.pixels < pos.maxScrollExtent - 0.5 && k < 60) {
    await t.dragFrom(Offset(vp.left + 4, vp.center.dy), Offset(0, -dragDy));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    k++;
    out.add(visible('drag$k'));
    final before = btn.length;
    btnFrame('drag$k');
    delFrame('drag$k');
    if (ko && btn.length > before) {
      await vqCapture(t, key, '${id}_btn${btn.length}_drag$k', conditions: {
        'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'textScaler': scale, 'locale': localeNote,
        'scroll': '본문 실제 dragFrom(left+4,center) -${dragDy.toInt()} × $k · off ${pos.pixels.toStringAsFixed(1)} · 새로 든 등록 버튼 ${btn.keys.skip(before).join(',')}',
        'measure': out[out.length - 1]});
    }
    final ns = noticeState('drag$k');
    if (ns != null && noticeShots < 4) {
      noticeShots++;
      await vqCapture(t, key, '${id}_notice_drag$k', conditions: {
        'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'textScaler': scale, 'locale': localeNote,
        'scroll': '본문 실제 dragFrom(left+4,center) -${dragDy.toInt()} × $k · off ${pos.pixels.toStringAsFixed(1)} · 세무 불일치 안내 표시 영역',
        'measure': '$ns | ${visible('drag$k')}'});
    }
    final hs = headState('drag$k');
    if (hs != null) {
      await vqCapture(t, key, '${id}_head_drag$k', conditions: {
        'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'textScaler': scale, if (ko) 'locale': localeNote,
        'scroll': '본문 실제 dragFrom(left+4,center) -${dragDy.toInt()} × $k · off ${pos.pixels.toStringAsFixed(1)} · 카드 머리 전부 표시 영역',
        'measure': '$hs | ${visible('drag$k')}'});
    }
    final es = editRowState('drag$k');
    if (es != null) {
      await vqCapture(t, key, '${id}_editrow_drag$k', conditions: {
        'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'textScaler': scale, 'locale': localeNote,
        'scroll': '본문 실제 dragFrom(left+4,center) -${dragDy.toInt()} × $k · off ${pos.pixels.toStringAsFixed(1)} · 수정 줄 전부 표시 영역',
        'measure': '$es | ${visible('drag$k')}'});
    }
    if (k == 2) {
      await vqCapture(t, key, '${id}_mid', conditions: {
        'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'textScaler': scale,
        'scroll': '본문 실제 dragFrom(left+4,center) -${dragDy.toInt()} × 2 · off ${pos.pixels.toStringAsFixed(1)}', 'measure': out[out.length - 1]});
    }
  }
  if (ko) labelProbe('말단');
  if (ko) taxProbe('말단');
  final atEnd = (pos.pixels - pos.maxScrollExtent).abs() < 0.5;
  out.add('말단=$atEnd off=${pos.pixels.toStringAsFixed(1)} max=${pos.maxScrollExtent.toStringAsFixed(1)} drag=$k · calls=$calls · overflows=${overflows.length}'
      ' · 수정receiver48단언=${taxRegistered && _assertTaxReceiver}(flag DU139_ASSERT_TAX_RECEIVER=$_assertTaxReceiver)');
  for (final l in out) {
    // ignore: avoid_print
    print('$id $l');
  }
  for (final l in probe) {
    // ignore: avoid_print
    print('$id V3 $l');
  }
  // [DU1 구현135] 넘침 원 진단 — 실패 단언 전에 전문을 남긴다(첫 줄/count 만 남기지 않는다).
  for (var i = 0; i < overflowDetails.length; i++) {
    for (final line in overflowDetails[i].split('\n')) {
      // ignore: avoid_print
      print('$id OVERFLOW#${i + 1} $line');
    }
  }
  // [DU1 구현135] 말단 관측 촬영은 최종 성공 단언보다 앞 — 이름 _end 는 관측 도달이며 PASS 인증이 아니다.
  await vqCapture(t, key, '${id}_end', conditions: {
    'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'textScaler': scale,
    'scroll': '본문 실제 drag → 말단 off ${pos.pixels.toStringAsFixed(1)}', 'measure': out.last,
    'note': '관측 도달 촬영(최종 단언 전) — PASS 인증 아님'});
  expect(atEnd || pos.maxScrollExtent < 0.5, isTrue, reason: '말단 도달');
  for (final l in labels) {
    expect(btn.containsKey(l), isTrue, reason: '$l 이 표시 영역 안에 들어온 프레임이 있다');
    if (registered) continue; // [DU1 구현128] 등록 완료 상태의 글자 링크 크기·hit 는 관측만 한다(단언 아님)
    expect(btn[l]!.r.height, greaterThanOrEqualTo(52 - 0.01), reason: '$l 주 행동 52');
    expect(btn[l]!.hit, isTrue, reason: '$l hit');
  }
  // [DU1 구현139 ③] 국내 세무 registered 의 '수정' receiver(InkWell = TextButton 최소 크기 상자) ≥48×48 · 중심 hit — after 계약.
  //   표시 영역 안에 처음 전부 든 프레임의 rect · hit(btnFrame) 을 쓴다. 다른 등록 완료 링크의 관측 계약은 넓히지 않는다.
  if (taxRegistered && _assertTaxReceiver) {
    final e = btn['수정']!;
    expect(e.r.width, greaterThanOrEqualTo(48 - 0.01), reason: '수정 receiver 폭 48 (${e.when} ${e.r})');
    expect(e.r.height, greaterThanOrEqualTo(48 - 0.01), reason: '수정 receiver 높이 48 (${e.when} ${e.r})');
    expect(e.hit, isTrue, reason: '수정 receiver 중심 hit (${e.when})');
  }
  expect(rb.width >= 48 - 0.01 && rb.height >= 48 - 0.01 && hits(back, rb.center), isTrue, reason: '뒤로 receiver');
  expect(calls.keys.where((x) => x.startsWith('firestore')), isEmpty, reason: 'Firestore 0');
  expect(calls.keys.where((x) => x.startsWith('functions') && !x.contains('callableGetTaxIdentityStatus')), isEmpty, reason: '다른 Functions 0');
  expect(overflows, isEmpty, reason: overflows.join(' | '));
  expect(t.takeException(), isNull);
  } finally {
    // [DU1 구현135] 주 복구 — 성공·실패 어느 쪽이든 binding 에 전달되기 전에 원 handler 로 되돌린다.
    FlutterError.onError = prev;
  }
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('S038-N 서류 관리 국내 USER 미등록 392×851@1.0 — 세무상태 성공 · 전체·실제 drag·receiver', (t) async {
    await _cell(t, id: 'S038-N_documents_unregistered_392x1', size: const Size(392, 851), scale: 1.0, insets: true, dragDy: 200);
  });

  testWidgets('S038-B 서류 관리 국내 USER 미등록 320×640@2.0 — 연속 읽기·마지막 CTA·overflow 0', (t) async {
    await _cell(t, id: 'S038-B_documents_unregistered_320x2', size: const Size(320, 640), scale: 2.0, insets: false, dragDy: 150);
  });

  // [DU1 후속121] S038 V6/V10 한국어 대표 — 같은 fixture·같은 실제 drag·같은 단언, MaterialApp 만 ko_KR + Global delegates(앱 main 의 목록 + LOCAL 명시).
  testWidgets('S038-N-ko 서류 관리 국내 USER 미등록 392×851@1.0 ko_KR — 세무상태 성공 · 전체·실제 drag·receiver', (t) async {
    await _cell(t, id: 'S038-N-ko_documents_unregistered_392x1', size: const Size(392, 851), scale: 1.0, insets: true, dragDy: 200, ko: true);
  });

  testWidgets('S038-B-ko 서류 관리 국내 USER 미등록 320×640@2.0 ko_KR — 연속 읽기·마지막 CTA·overflow 0', (t) async {
    await _cell(t, id: 'S038-B-ko_documents_unregistered_320x2', size: const Size(320, 640), scale: 2.0, insets: false, dragDy: 150, ko: true);
  });

  // [DU1 후속128] 등록 완료(신분증·계좌·통장사본 제출, 세무 미등록) 관측 — 같은 호스트·같은 조건, 완료 배지 체크·재등록/변경/삭제 글자 링크를 본다.
  testWidgets('S038-N-ko-done 서류 관리 국내 USER 제출 완료 392×851@1.0 ko_KR — 완료 배지·글자 링크 관측', (t) async {
    await _cell(t, id: 'S038-N-ko-done_documents_registered_392x1', size: const Size(392, 851), scale: 1.0, insets: true, dragDy: 200, ko: true, registered: true);
  });

  testWidgets('S038-B-ko-done 서류 관리 국내 USER 제출 완료 320×640@2.0 ko_KR — 완료 배지·글자 링크 관측', (t) async {
    await _cell(t, id: 'S038-B-ko-done_documents_registered_320x2', size: const Size(320, 640), scale: 2.0, insets: false, dragDy: 150, ko: true, registered: true);
  });

  // [DU1 후속134] 세무 불일치(등록 · 지금 신분증 MISMATCH, LOCAL 주입) — 현행 색 그대로 D:1301~1305 안내를 직접 관측한다. 같은 호스트·조건·실제 drag.
  testWidgets('S038-N-ko-mismatch 서류 관리 국내 USER 제출 완료 · 세무 불일치 392×851@1.0 ko_KR — 불일치 안내 직접 관측', (t) async {
    await _cell(t, id: 'S038-N-ko-mismatch_documents_taxmismatch_392x1', size: const Size(392, 851), scale: 1.0, insets: true, dragDy: 200, ko: true, registered: true, tax: _Tax.mismatch);
  });

  testWidgets('S038-B-ko-mismatch 서류 관리 국내 USER 제출 완료 · 세무 불일치 320×640@2.0 ko_KR — 불일치 안내 직접 관측', (t) async {
    await _cell(t, id: 'S038-B-ko-mismatch_documents_taxmismatch_320x2', size: const Size(320, 640), scale: 2.0, insets: false, dragDy: 150, ko: true, registered: true, tax: _Tax.mismatch);
  });

  // [DU1 후속139 ③] 국내 세무 등록 일치(MATCHED, LOCAL 주입) — 대부분의 등록 사용자가 '수정'을 보는 상태. 같은 호스트 · 조건 · 실제 drag.
  testWidgets('S038-N-ko-taxdone 서류 관리 국내 USER 제출 완료 · 세무 등록 일치 392×851@1.0 ko_KR — 수정 receiver', (t) async {
    await _cell(t, id: 'S038-N-ko-taxdone_documents_taxmatched_392x1', size: const Size(392, 851), scale: 1.0, insets: true, dragDy: 200, ko: true, registered: true, tax: _Tax.matched);
  });

  testWidgets('S038-B-ko-taxdone 서류 관리 국내 USER 제출 완료 · 세무 등록 일치 320×640@2.0 ko_KR — 수정 receiver', (t) async {
    await _cell(t, id: 'S038-B-ko-taxdone_documents_taxmatched_320x2', size: const Size(320, 640), scale: 2.0, insets: false, dragDy: 150, ko: true, registered: true, tax: _Tax.matched);
  });
}
