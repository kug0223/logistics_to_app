// ignore_for_file: depend_on_referenced_packages
// [DU463 · 자체 판정 셀 · 표시만] S073 내 일정 — 근무 가능일 수정 모드 안내 둘째 줄 grey500 → grey600(첫 줄 · 같은 화면 짝).
//   DU442 시험 harness(수정 화면 진입)를 그대로 쓰고 측정만 안내 두 줄로 바꿨다. before = 현재 A(my_schedule_screen 579b0125 = DU442 후보) / strict = 후보.
//   기본 skip — TB before/du463-tb/DU_BEFORE_OBSERVE=463 · TA after/du463-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/invite_region_preference.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/worker_availability_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_schedule_reads.dart';
import 'package:ALfit/screens/user/my_schedule_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
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

const kUid = 'worker-local-463';

class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: kUid, username: 'worker', name: 'QA 근로자', email: 'w@test.local', role: UserRole.USER,
        homeRegion: const UserRegion(province: '서울특별시', city: '송파구'), accountStatus: 'active',
      );
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '463';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du463-tb' && _env['DU_BEFORE_OBSERVE'] == '463') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du463-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f2(double v) => v.toStringAsFixed(2);

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'brand': AppColors.brand, 'info': AppColors.info, 'infoDark': AppColors.infoDark,
  'textSecondary': AppColors.textSecondary, 'grey300': AppColors.grey300, 'grey200': AppColors.grey200,
  'grey50': AppColors.grey50, 'grey500': AppColors.grey500, 'grey600': AppColors.grey600, 'textTertiary': AppColors.textTertiary,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${c.toARGB32().toRadixString(16).padLeft(8, '0')}';
}

double _cr(Color? a, Color? b) {
  if (a == null || b == null) return 0;
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// 글자 뒤 채움색 — 가장 가까운 불투명 Material(버튼 면) · BoxDecoration 색.

/// 놓인 면 — 가장 가까운 조상의 칠한 색(Container color · BoxDecoration color · ColoredBox · Material(투명 아님)).
Color? _bgOf(Element e) {
  Color? found;
  e.visitAncestorElements((x) {
    final w = x.widget;
    Color? c;
    if (w is Container) {
      c = w.color ?? (w.decoration is BoxDecoration ? (w.decoration! as BoxDecoration).color : null);
    } else if (w is ColoredBox) {
      c = w.color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color;
    }
    if (c != null) {
      found = c;
      return false;
    }
    return true;
  });
  return found;
}

void main() {
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  const fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initializeDateFormatting('ko_KR', null);
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // ── KST 날짜 고정(du1_c3_s073 과 같은 식) ──
  final kNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  DateTime kstMidnight(int plus) => DateTime.utc(kNow.year, kNow.month, kNow.day + plus).subtract(const Duration(hours: 9));
  final qKey = WorkerAvailabilityModel.dateKeyFrom(kstMidnight(1));
  final uKey = WorkerAvailabilityModel.dateKeyFrom(kstMidnight(2));

  final calls = <String, int>{};
  void inc(String k) => calls[k] = (calls[k] ?? 0) + 1;
  MyScheduleReads reads() => MyScheduleReads(
        myApplications: (uid) async {
          inc('myApplications');
          return const <ApplicationModel>[];
        },
        myMonthlyAttendances: ({required String userId, required int year, required int month}) async {
          inc('myMonthlyAttendances');
          return const <AttendanceModel>[];
        },
        myAvailability: (uid) async {
          inc('myAvailability');
          return WorkerAvailabilityModel(uid: uid, dates: [qKey, uKey], city: '송파구');
        },
        invitePreference: (uid) async {
          inc('invitePreference');
          return const InviteRegionPreference(enabled: true, regions: [UserRegion(province: '서울특별시', city: '송파구')]);
        },
      );
  void stubChannels() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMessageHandler(fnChannel, (msg) async {
      final args = (const StandardMessageCodec().decodeMessage(msg) as List).first as Map;
      inc('BLOCKED functions ${args['functionName']}');
      return const StandardMessageCodec().encodeMessage(<Object?>['not-found', 'du463-blocked', <String, Object?>{'code': 'not-found'}]);
    });
    for (final op in const ['documentReferenceGet', 'queryGet', 'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete',
      'writeBatchCommit', 'transactionCreate', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$fsBase.$op', (msg) async {
        inc('BLOCKED firestore $op');
        return null;
      });
    }
  }

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S073EH-${v.id}-EDIT 근무 가능일 수정 — 안내 둘째 줄 grey600 · 대비 · 쓰기 0', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S073EH-${v.id}-EDIT';
        final mode = _before ? 'before' : 'strict';
        _out('D463 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
        calls.clear();
        stubChannels();
        final overflows = <String>[];
        final fwErrors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            overflows.add(m.split('\n').first);
          } else {
            fwErrors.add(m.split('\n').first);
            prev?.call(d);
          }
        };
        addTearDown(() => FlutterError.onError = prev);
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');

        final key = GlobalKey();
        await t.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => _Worker()),
            ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ],
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              navigatorKey: navigatorKey,
              theme: RoleTheme.workerTheme,
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: MyScheduleScreen(reads: reads()),
            ),
          ),
        ));
        for (var r = 0; r < 4; r++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          for (var i = 0; i < 5; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
        }
        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D463 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'EDIT',
            'state': state,
          });
          shots++;
        }

        // ── 수정 화면으로 ──
        final cta = find.text('가능일 설정');
        must('가능일 설정 행동 1', cta.evaluate().length == 1, '${cta.evaluate().length}개');
        await t.tap(cta.first);
        for (var i = 0; i < 10; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        final editTitle = find.text('근무 가능일 선택');
        final saveF = find.text('2일 저장');
        final cancelF = find.text('취소');
        must('수정 화면 · 저장 · 취소', editTitle.evaluate().length == 1 && saveF.evaluate().length == 1 && cancelF.evaluate().length == 1,
            '제목 ${editTitle.evaluate().length} 저장 ${saveF.evaluate().length} 취소 ${cancelF.evaluate().length}');
        // ── 수정 모드 안내 두 줄(값은 스크롤 · 캡처 뒤 즉시) ──
        Finder rt(String s) => find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText(includeSemanticsLabels: false) == s, skipOffstage: false);
        final h1F = rt('등록한 날 내 지역에 새 공고가 열리면 알림을 받아요.\n사업장이 먼저 제안하게 하려면 \'초대 받을 지역\'도 설정하세요.');
        final h2F = rt('제안을 수락해야 근무가 확정돼요 · 최대 60일, 오늘~90일 이내');
        must('안내 두 줄 1/1', h1F.evaluate().length == 1 && h2F.evaluate().length == 1, '${h1F.evaluate().length}/${h2F.evaluate().length}');
        await t.ensureVisible(h2F);
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        await shot('1edit', 'edit-mode-hint');
        final h1C = (t.widget(h1F) as RichText).text.style?.color;
        final h2C = (t.widget(h2F) as RichText).text.style?.color;
        final h1Bg = _bgOf(h1F.evaluate().first);
        final h2Bg = _bgOf(h2F.evaluate().first);
        final h1Cr = _cr(h1C, h1Bg);
        final h2Cr = _cr(h2C, h2Bg);
        final writes = calls.keys.where((k) => k.startsWith('BLOCKED')).toList();
        _out('D463 $tok att hint1 text=${_tok(h1C)} bg=${_tok(h1Bg)} cr=${_f2(h1Cr)}');
        _out('D463 $tok att hint2 text=${_tok(h2C)} bg=${_tok(h2Bg)} cr=${_f2(h2Cr)} writes=${writes.length}');
        must('쓰기 0(저장 미탭 · 채널 차단)', writes.isEmpty, '쓰기 $writes');
        // 첫 줄은 두 모드 공통 grey600(4.61 · 바뀌지 않는다).
        must('첫 줄 grey600 · 대비 ≥ 4.5', h1C == AppColors.grey600 && h1Cr >= 4.5, '${_tok(h1C)} ${_f2(h1Cr)}');
        if (_before) {
          // 음성 기대(코드 확정) — 둘째 줄 grey500(2.68).
          must('before 둘째 줄 grey500 · 대비 미달 검출', h2C == AppColors.grey500 && h2Cr < 4.5, '${_tok(h2C)} ${_f2(h2Cr)}');
        } else {
          must('strict 둘째 줄 grey600 · 대비 ≥ 4.5', h2C == AppColors.grey600 && h2Cr >= 4.5, '${_tok(h2C)} ${_f2(h2Cr)}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D463 $tok done state=EDIT mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
