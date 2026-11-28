// ignore_for_file: depend_on_referenced_packages
// [impl_58 · 11] 근무자 상세 — 인력 관리 권한(canManageWorkers)이 확인된 거부인 서브관리자는 리뷰 작성 입구 대신 '리뷰 권한 없음'.
//   rules monthly_reviews(ADMIN_TO_USER create · get) 축이 canManageWorkers 라, 예전에는 읽기가 막혀 '리뷰 작성'(미작성)으로 보였고
//   작성 폼까지 열린 뒤 저장이 거절됐다. 허용이면 예전 그대로 '리뷰 작성'.
//   하네스 = du1_workerdetail_cancel_picker_611b_test 의 대역(Firebase 코어 · 읽기 CF · Firestore 차단 · HTTP 차단 · Auth 리스너) 축소판.
//   보는 것: 320×640@1.3 · 320×640@2.0 · 392×800@2.0 — 글 전문 · 화면 안 · 넘침 0 · 누르면 이유 안내 · 쓰기 0.
import 'dart:io';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/widgets/dialogs/worker_detail_dialog.dart';

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

const _biz = 'biz1';
const _worker = 'w9';

/// 서브관리자 — 이 사업장 권한 중 canManageWorkers 만 [workers] 로 둔다(나머지 허용). checkForBusiness 는 실제 판정식으로 평가한다.
class _Sub extends UserProvider {
  _Sub(this.workers);
  final bool workers;
  MemberPermissions get _p => MemberPermissions(
      canManageTo: true, canManageWorkers: workers, canManageWage: true, canManageContract: true, canCancelTransfer: true);
  @override
  UserModel? get currentUser => UserModel(
      uid: 'sub1', username: 'sub1', name: '김부관리', email: 'sub1@alfit.local', role: UserRole.USER,
      subAdminBusinessIds: const [_biz]);
  @override
  bool get isSubAdmin => true;
  @override
  String? get effectiveBusinessId => _biz;
  @override
  bool get subAdminPermissionsLoaded => true;
  @override
  PermissionWatchState get currentBusinessPermissionHealth => PermissionWatchState.verified;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) =>
      check(_p) ? PermissionCheck.allowed : PermissionCheck.denied;
  @override
  bool can(bool Function(MemberPermissions p) check) => check(_p);
  @override
  bool canForAnyBusiness(bool Function(MemberPermissions p) check, {required bool whenUnknown}) => check(_p);
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => check(_p);
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      check(_p) ? PermissionCheck.allowed : PermissionCheck.denied;
  @override
  VoidCallback watchBusinessPermissions(String businessId) => () {};
}

UserModel _user() => UserModel(
      uid: _worker, username: _worker, name: '큐에이일', email: 'w9@test.local', role: UserRole.USER,
      gender: '여성', birthDate: DateTime(1995, 3, 2), contactPhone: '010-0000-0000',
      bankName: 'QA테스트은행', accountNumber: '0000000000', accountHolder: '큐에이일', bankbookImagePath: 'users/w9/bankbook.jpg',
      totalWorkDays: 0, averageRating: 0.0, reviewCount: 0, rehireRate: 0.0, recentNoShowCount: 0, recentLateCount: 0, isBlacklisted: false,
    );

ApplicationModel _application() => ApplicationModel(
      id: 'app1', uid: _worker, toId: 'to1', slotId: 'slot1', wdId: 'wd1', businessId: _biz, businessName: '테스트 사업장', toTitle: '테스트 공고',
      selectedWorkType: 'QA 분류', startTime: '10:00', endTime: '11:00', wage: 12000, wageType: 'hourly',
      status: AppStatus.confirmed, workDate: DateTime.utc(2030, 1, 14, 15), appliedAt: DateTime.utc(2030, 1, 10, 1),
      confirmedAt: DateTime.utc(2030, 1, 11, 2), documentAccessConsentGiven: true, documentAccessConsentVersion: '2026-09-18-v3',
    );

const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'impl58rv.fake.auth.';
const _authListeners = ['registerIdTokenListener', 'registerAuthStateListener'];
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

class _Wire {
  final fsWrites = <String>[];
  final fsOps = <String>[];
  final cf = <String>[];

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
    if (channel == _cfChannel) return Future<ByteData?>.value(_cf(message));
    if (channel.startsWith('$_fsBase.')) {
      final op = channel.substring(_fsBase.length + 1);
      (_fsWrites.contains(op) ? fsWrites : fsOps).add(op);
      return Future<ByteData?>.value(FirebaseFirestoreHostApi.codec.encodeMessage(<Object?>['impl58-blocked', '$op 차단', null]));
    }
    for (final name in _authListeners) {
      if (channel == '$_authBase$name' || channel == '$_authFake$name') return handler?.call(message);
    }
    if (channel.startsWith('flutter/')) return handler != null ? handler(message) : m.delegate.send(channel, message);
    return null;
  }

  ByteData? _cf(ByteData? message) {
    const codec = StandardMessageCodec();
    final args = (codec.decodeMessage(message) as List).first as Map;
    final fn = args['functionName'].toString();
    cf.add(fn);
    final Object? data = switch (fn) {
      'callableGetApplicationsByBiz' => <String, Object?>{'applications': const <Object?>[]},
      'callableGetMonthlyReviewsForUser' => <String, Object?>{'items': const <Object?>[]},
      'callableGetReviewsForUser' => <String, Object?>{'reviews': const <Object?>[]},
      'callableCheckIdCardAccess' => <String, Object?>{'request': null},
      'callableAdminHasAttendanceRecord' => <String, Object?>{'hasRecord': true},
      'callableGetContractsByBiz' => <String, Object?>{'contracts': const <Object?>[]},
      'callableGetTaxIdentityReview' => <String, Object?>{
          'state': 'UNREVIEWED', 'valid': true, 'idDocumentVersion': 1, 'taxIdentityFingerprint': 'fp1', 'hasIdDocument': true,
          'reviewedAtMs': null, 'officialName': '큐에이일', 'hasTaxIdentity': false},
      _ => null,
    };
    if (data == null) return codec.encodeMessage(<Object?>['not-found', 'impl58-blocked', <String, Object?>{'code': 'not-found'}]);
    return codec.encodeMessage(<Object?>[data]);
  }
}

class _NoHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => throw const SocketException('impl58 — 외부 HTTP 차단');
}

Future<void> _loadFonts() async {
  Future<ByteData> b(String p) => File(p).readAsBytes().then((x) => ByteData.view(x.buffer));
  for (final fam in const ['NotoSansKR', 'Roboto']) {
    await (FontLoader(fam)
          ..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))
          ..addFont(b('assets/fonts/NotoSansKR-Bold.ttf')))
        .load();
  }
  await (FontLoader('FlutterTest')..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))).load();
}

const _noPermText = '리뷰는 인력 관리 권한이 있어야 작성·확인할 수 있어요';

void main() {
  setUpAll(() async {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final wire = _Wire();
    final prevAll = m.allMessagesHandler;
    m.allMessagesHandler = (channel, handler, message) => wire.route(m, channel, handler, message);
    try {
      FirebasePlatform.instance = _FakeCore();
      await Firebase.initializeApp();
      await initializeDateFormatting('ko_KR');
      await _loadFonts();
      const codec = StandardMessageCodec();
      for (final name in _authListeners) {
        m.setMockMessageHandler('$_authBase$name', (_) async => codec.encodeMessage(<Object?>['$_authFake$name']));
        m.setMockMethodCallHandler(MethodChannel('$_authFake$name'), (_) async => null);
      }
    } finally {
      m.allMessagesHandler = prevAll;
    }
  });

  for (final v in const [(w: 320.0, h: 640.0, s: 1.3), (w: 320.0, h: 640.0, s: 2.0), (w: 392.0, h: 800.0, s: 2.0)]) {
    for (final workers in const [false, true]) {
      testWidgets('IMPL58-RV ${v.w.toInt()}x${v.h.toInt()}@${v.s} canManageWorkers=$workers', (t) async {
        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final wire = _Wire();
        final prevAll = messenger.allMessagesHandler;
        final prevHttp = HttpOverrides.current;
        final prevOnError = FlutterError.onError;
        messenger.allMessagesHandler = (channel, handler, message) => wire.route(messenger, channel, handler, message);
        HttpOverrides.global = _NoHttp();
        final overflows = <String>[];
        FlutterError.onError = (d) {
          final s = d.exceptionAsString();
          if (s.contains('overflowed')) {
            overflows.add(s.split('\n').first);
          } else {
            prevOnError?.call(d);
          }
        };
        addTearDown(() {
          messenger.allMessagesHandler = prevAll;
          HttpOverrides.global = prevHttp;
          FlutterError.onError = prevOnError;
        });
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        Future<void> frames(int n) async {
          for (var i = 0; i < n; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
        }

        await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
          value: _Sub(workers),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            theme: RoleTheme.businessAdminTheme,
            locale: const Locale('ko', 'KR'),
            supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
            home: Scaffold(
              body: WorkerDetailDialog(
                user: _user(),
                application: _application(),
                businessId: _biz,
                isConfirmed: true,
                showApprovalButtons: false,
              ),
            ),
          ),
        ));
        await frames(40);
        final dlg = find.byType(WorkerDetailDialog);
        expect(dlg, findsOneWidget);
        final denied = find.descendant(of: dlg, matching: find.text('리뷰 권한 없음'), skipOffstage: false);
        final write = find.descendant(of: dlg, matching: find.text('리뷰 작성'), skipOffstage: false);
        if (!workers) {
          expect(denied, findsOneWidget, reason: '확인된 거부 → 권한 없음 칸');
          expect(write, findsNothing, reason: '작성 입구 숨김');
          await t.ensureVisible(denied);
          await frames(4);
          final r = t.getRect(denied);
          expect(r.left >= -0.5 && r.right <= v.w + 0.5 && r.top >= -0.5 && r.bottom <= v.h + 0.5, isTrue, reason: '화면 안 $r');
          await t.tap(denied);
          await frames(4);
          expect(find.text(_noPermText), findsOneWidget, reason: '누르면 이유');
        } else {
          expect(write, findsOneWidget, reason: '허용이면 예전 그대로');
          expect(denied, findsNothing);
        }
        expect(wire.fsWrites, isEmpty, reason: '쓰기 0');
        await t.pump(const Duration(seconds: 5)); // 토스트 타이머
        await frames(2);
        expect(overflows, isEmpty, reason: overflows.join(' | '));
      });
    }
  }
}
