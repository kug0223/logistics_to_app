// ignore_for_file: depend_on_referenced_packages
// [DU1 구현48 · 감사48 §4 다음 대표] C1 S031 AdminEditTOScreen — 제목 편집 → 실제 뒤로 → 미저장 경고 → 계속 수정(입력 보존) → 다시 뒤로 → 나가기.
//   LOCAL host route 에서 production AdminEditTOScreen(to:) push(목록 경유 아님). contract 마스터 공고(slot·batch 없음) → getSlots 0.
//   init 의 businesses/biz-local-c1/workTypes query 는 Firestore pigeon queryGet 에 활성 업무 1개 고정 응답. 그 밖 Firestore/Functions 채널은
//   오류 응답으로 **명시 차단·계수**한다. 저장하기는 누르지 않는다(writer 0). dialog 직접 렌더·dirty 직접 설정 없이 controller listener·PopScope·showConfirm 통과.
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
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';

import 'support/du1_vq_capture.dart';
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
    (id: 'C1-EDIT-DISCARD-B', w: 320.0, h: 640.0, s: 2.0),
    // [구현49 · 감사49 §2] 넓은 폭 기본 배율 대조 — 업무 목록 헤더 양 끝 배치·확인창 가로 배치
    (id: 'C1-EDIT-DISCARD-W', w: 360.0, h: 780.0, s: 1.0),
  ]) {
    testWidgets('${c.id} 공고 수정 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 제목 편집→뒤로→미저장 경고→계속 수정(보존)→뒤로→나가기', (t) async {
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
      Object? popResult = 'not-returned';
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
                  popResult = await Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => AdminEditTOScreen(to: original)));
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
      final titleField = find.byWidgetPredicate((w) => w is EditableText && w.controller.text == kOrigTitle);
      final body = find.descendant(of: find.byType(AdminEditTOScreen), matching: find.byType(Scrollable)).first;
      // [구현49] 업무 목록 헤더(제목·업무 추가) 실제 배치 측정 — 본문을 헤더까지 스크롤한 뒤(지연 생성) 잰다
      final addText = findVisibleText('업무 추가');
      await t.scrollUntilVisible(addText, 120, scrollable: body, maxScrolls: 60);
      await _settle(t, 2);
      final addBtn = find.ancestor(of: addText.first, matching: find.byType(InkWell)).first;
      final headTitle = findVisibleTextContaining('업무 목록').first;
      final hr = t.getRect(headTitle);
      final br = t.getRect(addBtn);
      out('◎ 업무 목록 글 $hr · 업무 추가 버튼 ${rr(addBtn)} · 같은 줄=${(hr.center.dy - br.center.dy).abs() < 8} · 버튼 오른쪽 끝=${br.right.toStringAsFixed(1)}');
      if (find.byType(Scrollable).evaluate().isNotEmpty) {
        final f = findVisibleTextContaining('근무 요일');
        out('◎ 근무 요일 글 ${f.evaluate().isEmpty ? '없음' : t.getRect(f.first)}');
      }
      // 헤더가 제목 필드 아래에 있으므로 위로 되돌아간다
      await t.scrollUntilVisible(titleField, -120, scrollable: body, maxScrolls: 60);
      await _settle(t, 2);
      out('① 제목 필드 ${rr(titleField)} pixels=${t.state<ScrollableState>(body).position.pixels.toStringAsFixed(1)} bodyViewport=${t.getRect(body)}');
      // 제목 입력(controller listener → _markChanged)
      await t.tap(titleField);
      await t.enterText(find.ancestor(of: titleField, matching: find.byType(TextField)).first, kNewTitle);
      await _settle(t, 4);
      out('① 입력 뒤 viewInsets=${MediaQuery.of(t.element(find.byType(AdminEditTOScreen))).viewInsets} 제목="${t.widget<EditableText>(find.byWidgetPredicate((w) => w is EditableText && w.controller.text == kNewTitle)).controller.text}"');
      FocusManager.instance.primaryFocus?.unfocus(); // 키보드 닫힘(합성)
      await _settle(t, 3);
      await vqCapture(t, key, '${c.id}_1_edited', conditions: cond('제목 편집 뒤'));
      // ② 실제 AppBar 뒤로
      final back = find.descendant(of: find.byType(AdminEditTOScreen), matching: find.byWidgetPredicate((w) => w is BackButton || (w is IconButton && w.icon is Icon && ((w.icon as Icon).icon == Icons.arrow_back || (w.icon as Icon).icon == Icons.arrow_back_ios_new || (w.icon as Icon).icon == Icons.arrow_back_ios)))).first;
      out('② 뒤로 ${rr(back)}');
      await t.tap(back);
      await _settle(t, 8);
      expect(findVisibleText('변경사항 취소'), findsOneWidget, reason: '미저장 경고');
      final keep = find.ancestor(of: findVisibleText('계속 수정'), matching: find.byType(InkWell)).first;
      final leave = find.ancestor(of: findVisibleText('나가기'), matching: find.byType(InkWell)).first;
      out('② 경고 title=${t.getRect(findVisibleText('변경사항 취소'))} msg=${findVisibleTextContaining('저장하지 않은 변경사항').evaluate().length} 계속수정=${rr(keep)} 나가기=${rr(leave)}');
      await vqCapture(t, key, '${c.id}_2_warning', conditions: cond('첫 미저장 경고'));
      // ③ 계속 수정 → 입력 보존
      await t.tap(keep);
      await _settle(t, 8);
      expect(find.byType(AdminEditTOScreen), findsOneWidget);
      final kept = find.byWidgetPredicate((w) => w is EditableText && w.controller.text == kNewTitle);
      expect(kept, findsOneWidget, reason: '계속 수정 — 입력 보존');
      out('③ 계속 수정 → 화면 유지·입력 보존 ${t.getRect(kept)}');
      await vqCapture(t, key, '${c.id}_3_kept', conditions: cond('계속 수정 뒤 입력 보존'));
      // ④ 다시 뒤로 → 나가기
      await t.tap(back);
      await _settle(t, 8);
      expect(findVisibleText('변경사항 취소'), findsOneWidget);
      await t.tap(find.ancestor(of: findVisibleText('나가기'), matching: find.byType(InkWell)).first);
      await _settle(t, 10);
      expect(find.byType(AdminEditTOScreen), findsNothing, reason: '편집 route 소멸');
      expect(popResult, isNull, reason: 'host 복귀 result null(_serverChanged false)');
      expect(original.title, kOrigTitle, reason: '원본 TO 불변');
      out('④ 나가기 → host 복귀 result=$popResult 원본제목="${original.title}" calls=$calls');
      await vqCapture(t, key, '${c.id}_4_host', conditions: cond('나가기 → host 복귀'));
      final writes = calls.entries.where((e) => !e.key.startsWith('queryGet businesses/biz-local-c1/workTypes')).toList();
      out('writer·기타 호출=$writes');
      expect(writes, isEmpty, reason: '저장·공개·지원관계 조회 0');
      FlutterError.onError = prev;
      out('overflows(${overflows.length})=${overflows.join(' | ')}');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
      expect(t.takeException(), isNull);
    });
  }
}
