// ignore_for_file: depend_on_referenced_packages
// [DU1 구현58 · 감사58 §5.1] C1-EDIT-INPUT-KEYBOARD-B/W — 공고 수정 제목 입력 · 합성 키보드 0→300→0 · 입력 줄/저장 CTA 도달(구현48 하네스 복사).
//   LOCAL host route 에서 production AdminEditTOScreen(to:) push(목록 경유 아님). contract 마스터 공고(slot·batch 없음) → getSlots 0.
//   init 의 businesses/biz-local-c1/workTypes query 는 Firestore pigeon queryGet 에 활성 업무 1개 고정 응답. 그 밖 Firestore/Functions 채널은
//   오류 응답으로 **명시 차단·계수**한다. 저장하기는 누르지 않는다(writer 0). dirty 직접 설정 없음.
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/to_management/edit_to_screen.dart';
import 'package:ALfit/screens/business_admin/to_management/widgets/to_action_button.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';

import 'support/du1_vq_capture.dart';

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

class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'owner-local-c1', username: 'owner', name: 'QA 사장', email: 'o@test.local',
      role: UserRole.BUSINESS_ADMIN, businessId: 'biz-local-c1', createdAt: DateTime(2026, 1, 1));
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
}

const kOrigTitle = '물류센터 포장 업무 모집';
const kNewTitle = '물류센터 주간 포장 및 출고 준비 업무 추가 모집';
TOModel kTo() => TOModel(
      id: 'to-local-c1-edit', businessId: 'biz-local-c1', businessName: 'QA 물류센터', type: TOType.contract, title: kOrigTitle,
      description: '[QA] 상품 포장·검수 보조 업무입니다. 주간 근무이며 안전화를 착용합니다.',
      rangeStart: DateTime(2026, 11, 9), rangeEnd: DateTime(2026, 12, 8), workDays: const ['월', '화', '수', '목', '금'],
      workDetails: const [
        WorkDetailData(wdId: 'wd-c1', workType: '포장', workTypeIcon: 'box', workTypeColor: '#3859E8', workTypeBackgroundColor: '#EEF2FF',
            wage: 12000, wageType: 'hourly', requiredCount: 2, startTime: '09:00', endTime: '18:00', order: 0),
      ],
      totalRequired: 2, editRevision: 0, publishMode: 'immediate', isPublished: true,
      creatorUID: 'owner-local-c1', createdAt: DateTime(2026, 11, 1));

Future<void> _settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  final calls = <String, int>{};
  const base = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  void stubFirestore() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = FirebaseFirestoreHostApi.codec;
    // workTypes query — 활성 업무 1개 고정
    m.setMockMessageHandler('$base.queryGet', (msg) async {
      // 요청 본문은 codec 으로 되읽을 수 없다(where 필터 값 쓰기/읽기 비대칭 → FormatException). 원본 바이트의 UTF-8 경로로 구분한다.
      final raw = String.fromCharCodes(msg!.buffer.asUint8List(msg.offsetInBytes, msg.lengthInBytes));
      final path = raw.contains('businesses/biz-local-c1/workTypes') ? 'businesses/biz-local-c1/workTypes' : 'other';
      calls['queryGet $path'] = (calls['queryGet $path'] ?? 0) + 1;
      if (path != 'businesses/biz-local-c1/workTypes') {
        return codec.encodeMessage(<Object?>['du48-blocked', 'query 차단: $path', null]);
      }
      return codec.encodeMessage(<Object?>[
        PigeonQuerySnapshot(
          documents: [
            PigeonDocumentSnapshot(
              path: 'businesses/biz-local-c1/workTypes/wt-c1',
              data: <String?, Object?>{
                'businessId': 'biz-local-c1', 'name': '포장', 'icon': 'box', 'color': '#3859E8', 'backgroundColor': '#EEF2FF',
                'displayOrder': 0, 'isActive': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
              },
              metadata: PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false),
            ),
          ],
          documentChanges: const [],
          metadata: PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false),
        ),
      ]);
    });
    // 그 밖 Firestore 쓰기·읽기 — 명시 차단·계수
    for (final op in const ['documentReferenceGet', 'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete',
      'writeBatchCommit', 'transactionCreate', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$base.$op', (msg) async {
        calls[op] = (calls[op] ?? 0) + 1;
        return codec.encodeMessage(<Object?>['du48-blocked', '$op 차단', null]);
      });
    }
    m.setMockMessageHandler('dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call', (msg) async {
      calls['functions.call'] = (calls['functions.call'] ?? 0) + 1;
      return const StandardMessageCodec().encodeMessage(<Object?>['du48-blocked', 'functions 차단', null]);
    });
  }

  for (final c in const [
    (id: 'C1-EDIT-INPUT-KEYBOARD-B', w: 320.0, h: 640.0, s: 2.0),
    (id: 'C1-EDIT-INPUT-KEYBOARD-W', w: 360.0, h: 780.0, s: 1.0),
  ]) {
    testWidgets('${c.id} 공고 수정 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 제목 입력·키보드 0→300→0', (t) async {
      await t.runAsync(vqLoadFonts);
      calls.clear();
      stubFirestore();
      final overflows = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        final m = d.exceptionAsString();
        if (m.contains('overflowed')) {
          overflows.add(m.split('\n').first);
          // ignore: avoid_print
          print('OVERFLOW-DETAIL ${d.toString().split('\n').where((l) => l.contains('file:///') || l.contains('overflowed') || l.contains('creator')).take(6).join(' / ')}');
        } else {
          prev?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = prev);
      final size = Size(c.w, c.h);
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      final original = kTo();
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>(create: (_) => _Owner()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()), // setUser 없음
        ],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            theme: RoleTheme.businessAdminTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
                onPressed: () async {
                  await Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => AdminEditTOScreen(to: original)));
                },
                child: const Text('host'))))),
          ),
        ),
      ));
      await t.pump();
      await t.tap(find.text('host'));
      await _settle(t, 16);
      void out(String l) {
        // ignore: avoid_print
        print(l);
      }
      expect(find.byType(AdminEditTOScreen), findsOneWidget);
      final mq = MediaQuery.of(t.element(find.byType(AdminEditTOScreen)));
      out('${c.id} screenMQ padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} · physical ${t.view.padding.top},${t.view.padding.bottom},${t.view.viewInsets.bottom} · calls=$calls');
      expect(calls['queryGet businesses/biz-local-c1/workTypes'], 1, reason: '업무 유형 정상 로드(고정 응답)');
      Map<String, Object?> cond(String state) => {
            'entry': 'LOCAL host route → Navigator.push(AdminEditTOScreen(to: contract 마스터)) — 목록 경유 아님',
            'theme': 'RoleTheme.businessAdminTheme', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
            'mq': 'padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets}', 'keyboard': 'MediaQuery/물리 inset 0(합성 IME 없음)',
            'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · FlutterTest 미등록',
            'data': 'TO to-local-c1-edit/biz-local-c1 contract 원제목 "$kOrigTitle" 2026-11-09~12-08 월~금 wd-c1 포장 09:00~18:00 시급12000 필요2 editRevision0 immediate · workTypes 고정 1개',
            'prefs': 'setMockInitialValues({})', 'clock': '미주입', 'state': state, 'calls': calls.toString()};
      bool hits(Finder f, Offset p) {
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
        return hit.path.any((e) => e.target == t.renderObject(f));
      }
      String rr(Finder f) {
        final r = t.getRect(f);
        return '$r(${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)}) hit=${hits(f, r.center)} inScreen=${r.top >= 0 && r.bottom <= c.h && r.left >= 0 && r.right <= c.w}';
      }
      final deferred = <String>[];
      final body = find.descendant(of: find.byType(AdminEditTOScreen), matching: find.byType(Scrollable)).first;
      final pos = t.state<ScrollableState>(body).position;
      final titleField0 = find.byWidgetPredicate((w) => w is EditableText && w.controller.text == kOrigTitle);
      await t.scrollUntilVisible(titleField0, 120, scrollable: body, maxScrolls: 60);
      await t.ensureVisible(titleField0);
      await _settle(t, 2);
      final ctl = t.widget<EditableText>(titleField0).controller;
      final edit = find.byWidgetPredicate((w) => w is EditableText && identical(w.controller, ctl));
      final cta = find.byType(TOActionButton);
      final ctaInk = find.descendant(of: cta, matching: find.byType(InkWell)).first;
      final ctaLabel = find.descendant(of: cta, matching: find.text('저장하기'));
      EditableTextState es() => t.state<EditableTextState>(edit);
      Rect caretRect() {
        final re = es().renderEditable;
        final sel = re.selection;
        final p = (sel == null || !sel.isValid) ? const TextPosition(offset: 0) : sel.extent;
        return MatrixUtils.transformRect(re.getTransformTo(null), re.getLocalRectForCaret(p));
      }
      Map<String, Object?> condNow(String state) {
        final m = MediaQuery.of(t.element(find.byType(AdminEditTOScreen)));
        return {...cond(state), 'mq': 'padding=${m.padding} viewPadding=${m.viewPadding} viewInsets=${m.viewInsets}', 'keyboard': '합성 물리 inset bottom=${t.view.viewInsets.bottom}', 'title': ctl.text};
      }
      // 판정: 키보드 윗변 위·본문 viewport 안 — 합성 키보드는 hit-test 를 막지 않으므로 rect 로 판정한다
      void judge(String tag, double inset) {
        final kbTop = c.h - inset;
        final vp = t.getRect(body);
        final cr = caretRect();
        final sR = t.getRect(cta);
        final iR = t.getRect(ctaInk);
        final lR = t.getRect(ctaLabel);
        final ctaHit = hits(ctaInk, iR.center);
        final caretOk = cr.top >= vp.top - 0.5 && cr.bottom <= kbTop + 0.5 && cr.bottom <= vp.bottom + 0.5;
        final ctaOk = sR.top >= 0 && sR.bottom <= kbTop + 0.5 && sR.left >= 0 && sR.right <= c.w && sR.height >= 52 && iR.height >= 48 && ctaHit && lR.bottom <= kbTop + 0.5;
        out('   [$tag] 키보드 윗변 y=${kbTop.toStringAsFixed(1)} · 본문 viewport=$vp · caret=$cr 도달=$caretOk · 저장 CTA surface=$sR(높이 ${sR.height.toStringAsFixed(1)}) 터치(InkWell)=$iR 라벨=$lR 중심hit=$ctaHit 도달=$ctaOk');
        if (!caretOk) deferred.add('$tag 입력 중인 줄(caret)이 키보드 위·본문 안에 없음');
        if (!ctaOk) deferred.add('$tag 저장 CTA 가 키보드 위에 닿지 않음(surface $sR)');
      }
      void snap(String tag) {
        final m = MediaQuery.of(t.element(find.byType(AdminEditTOScreen)));
        out('$tag · MQ viewInsets=${m.viewInsets} · 물리 inset bottom=${t.view.viewInsets.bottom} · 포커스=${es().widget.focusNode.hasFocus} · 원문="${ctl.text}" · 스크롤 ${pos.pixels.toStringAsFixed(1)}/${pos.maxScrollExtent.toStringAsFixed(1)} · 필드 ${rr(edit)}');
      }

      // ① 제목 실탭 → 입력(키보드 0)
      await t.tap(edit);
      await _settle(t, 4);
      expect(es().widget.focusNode.hasFocus, isTrue, reason: '실제 탭 → 포커스');
      const part1 = '물류센터 주간 포장 모집';
      await t.enterText(edit, part1);
      await _settle(t, 4);
      expect(ctl.text, part1);
      snap('① 입력(키보드 0)');
      judge('키보드0', 0);
      await vqCapture(t, key, '${c.id}_1_input_kb0', conditions: condNow('제목 입력 · 키보드 0'));
      // ② 합성 키보드 300
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      await _settle(t, 12);
      expect(es().widget.focusNode.hasFocus, isTrue, reason: '키보드 중 포커스 유지');
      snap('② 키보드 300');
      judge('키보드300', 300);
      await vqCapture(t, key, '${c.id}_2_kb300', conditions: condNow('키보드 300'));
      // ③ 키보드 중 추가 입력
      const full = '$part1 추가 인원';
      await t.enterText(edit, full);
      await _settle(t, 8);
      expect(ctl.text, full, reason: '키보드 중 추가 입력');
      snap('③ 키보드 300 추가 입력');
      judge('키보드300 추가입력', 300);
      await vqCapture(t, key, '${c.id}_3_kb300_more', conditions: condNow('키보드 300 · 추가 입력'));
      // ④ 키보드 닫힘
      t.view.viewInsets = FakeViewPadding.zero;
      await _settle(t, 12);
      snap('④ 키보드 0 복귀');
      expect(ctl.text, full, reason: '복귀 후 원문 유지');
      expect(find.byType(AdminEditTOScreen), findsOneWidget, reason: '폼 유지');
      out('   복귀 후 CTA 아래 여백=${(c.h - t.getRect(cta).bottom).toStringAsFixed(1)}');
      await vqCapture(t, key, '${c.id}_4_kb0', conditions: condNow('키보드 닫힘 복귀'));

      out('최종 calls=$calls');
      expect(calls, {'queryGet businesses/biz-local-c1/workTypes': 1}, reason: '정확 allowlist — 저장·공개·기타 0');
      FlutterError.onError = prev;
      out('overflows(${overflows.length})=${overflows.join(' | ')}');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
      expect(t.takeException(), isNull);
      out('deferred(${deferred.length})=${deferred.join(' | ')}');
      expect(deferred, isEmpty, reason: deferred.join(' | '));
    });
  }
}
