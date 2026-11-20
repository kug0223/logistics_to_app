// ignore_for_file: depend_on_referenced_packages
// [DU513 · NCB-52L · 색 예산 · 표시만] S052 전체 사용자 목록(슈퍼관리자 · all_users_screen) — 목록 색 한 묶음.
//   before = 현재 A(all_users_screen 00f02631 · DU500 채택판 — 목록 코드 1–775행은 DU493 후보 0acfc1a6 과 같다) / strict = 후보 r1(실행 전 판정 D1–D3 반영).
//   후보: 역할 필터 선택 = brand(미선택 = 흰 면 · 옅은 테두리 · 보조 글자) · 아바타 = 옅은 brand 원 + 사람 아이콘 한 가지 · 역할 칩 = 세 역할 같은 중립 칩 ·
//   상태 칩은 블랙리스트 error · 제재중 warning 그대로, 승인대기만 brand 짝(brandSurface 면 · brand 글자 · D1). 상태 조건 · 라벨 · 문구 · 배치 · 행동은 그대로다.
//   관측: 역할 셋 + 서브관리자(role USER) + 긴 이름 · 상태(블랙리스트 · 제재중 · 승인대기 · 없음) · 필터 4 + 관리자 필터 실제 탭 · 검색 실제 입력 ·
//   전체 스크롤 끝 도달 · 행 실제 탭 → 상세 시트 열림 · 바깥 탭 닫힘 · 보이는 모든 글자의 실바탕 대비 · 행/칩 받는 자리 · 카드 폭 ·
//   읽기 경계(주입 reader 정확 1 · Cloud Functions 채널 호출 0 · 예상 밖 플랫폼 채널 0 · HTTP 0).
//   before 는 화면 값을 기록만 한다 — 단언은 시험 배선(읽기 1 · cf 0) · 존재(need) · framework 예외 0 · 끝 예외 0 뿐이다.
//   값은 닿은 즉시 지역 값으로 남기고, 화면 판정은 모아 두었다가 넘침 수집기를 되돌린 뒤 한꺼번에 던진다(v6 · v34).
//   기본 skip — TB before/du513-tb/DU_BEFORE_OBSERVE=513 · TA after/du513-ta/없음.
import 'dart:convert';
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

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/super_admin/all_users_reads.dart';
import 'package:ALfit/screens/super_admin/all_users_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';

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

/// RR57 · DU492/493 과 같은 슈퍼관리자 대역.
class _Super extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'sa1', username: 'sa1', name: '운영자', email: 'sa@alfit.local',
        role: UserRole.SUPER_ADMIN, createdAt: DateTime(2026, 1, 1));
  @override
  bool get isSuperAdmin => true;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
}

/// [DU508 r4 F120-3 와 같은 대역] 실제 Cloud Functions 플랫폼 채널(cloud_functions_platform_interface Pigeon).
const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// 이 화면의 목록 읽기는 주입 reader 뿐이다 — 이 채널로 오는 호출(블랙리스트 · 제재 해제 등 쓰기 포함)은 전부 예상 밖이다.
///   함수 이름을 기록하고 오류 응답으로 막는다(성공 응답 0 · 끝에 0 단언).
class _CfMock {
  final calls = <String>[];

  Future<ByteData?> handle(ByteData? message) async {
    final args = (const StandardMessageCodec().decodeMessage(message) as List).first as Map;
    calls.add((args['functionName'] ?? '-').toString());
    return const StandardMessageCodec().encodeMessage(<Object?>['blocked', 'DU513 시험 — 예상 밖 Cloud Functions 호출', null]);
  }
}

/// 모든 플랫폼 메시지 관찰 — CF 채널은 위 모의로, 'flutter/' 프레임워크 채널은 원래 경로로 넘긴다(센다).
///   그 밖의 채널(Firestore · Auth · 저장소 등)은 이름을 기록하고 막는다(응답 null).
class _Wire {
  final unexpected = <String>[];
  var framework = 0;

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
    if (channel == _cfChannel) return handler?.call(message);
    if (channel.startsWith('flutter/')) {
      framework++;
      return handler != null ? handler(message) : m.delegate.send(channel, message);
    }
    unexpected.add(channel);
    return null;
  }
}

/// 외부 HTTP 차단 — 만들려는 시도를 기록하고 실패시킨다(끝에 0 단언).
class _NoHttp extends HttpOverrides {
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    throw const SocketException('DU513 시험 — 외부 HTTP 차단');
  }
}

// callable 응답 모양 그대로(RR57) — Timestamp 는 {_seconds, _nanoseconds}.
Map<String, int> _ts(DateTime t) => {'_seconds': t.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};
final _auto = DateTime.fromMillisecondsSinceEpoch((DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000) * 1000);
const _longName = 'NGUYEN THI MINH KHAI';

/// 여섯 사람 — 역할 셋(지원자 · 사업장관리자 · 슈퍼관리자) + 서브관리자(role USER · subAdminBusinessIds) + 긴 이름(외국인 표기 · 띄어쓰기 있음).
///   상태: 김지원 블랙리스트 + 제재중(노쇼 자동 · 내일까지) · 이대기 승인대기(registration_pending) · 나머지 없음. 연락처 둘 · 근무일 0/3/12/128.
List<Map<String, dynamic>> _users() => [
      {'uid': 'u1', 'username': 'worker01', 'name': '김지원', 'email': 'u1@alfit.local', 'role': 'USER', 'createdAt': _ts(DateTime(2026, 1, 1)),
       'contactPhone': '010-1234-5678', 'totalWorkDays': 12, 'noShowCount': 3, 'recentNoShowCount': 3, 'isBlacklisted': true, 'blacklistReason': '시험',
       'restrictedUntil': _ts(_auto), 'restrictionSource': 'auto', 'restrictionParts': {'auto': _ts(_auto)}},
      {'uid': 'u2', 'username': 'worker02', 'name': '이대기', 'email': 'u2@alfit.local', 'role': 'USER', 'createdAt': _ts(DateTime(2026, 2, 1)),
       'accountStatus': 'registration_pending'},
      {'uid': 'b1', 'username': 'boss01', 'name': '남궁하늘빛', 'email': 'b1@alfit.local', 'role': 'BUSINESS_ADMIN', 'createdAt': _ts(DateTime(2026, 3, 1)),
       'businessName': '강남 물류센터'},
      {'uid': 's1', 'username': 'ops01', 'name': '최운영', 'email': 's1@alfit.local', 'role': 'SUPER_ADMIN', 'createdAt': _ts(DateTime(2026, 4, 1))},
      {'uid': 'm1', 'username': 'sub01', 'name': '정서브', 'email': 'm1@alfit.local', 'role': 'USER', 'createdAt': _ts(DateTime(2026, 5, 1)),
       'subAdminBusinessIds': ['biz1'], 'totalWorkDays': 3},
      {'uid': 'f1', 'username': 'foreign01', 'name': _longName, 'email': 'f1@alfit.local', 'role': 'USER', 'createdAt': _ts(DateTime(2026, 6, 1)),
       'contactPhone': '010-9876-5432', 'totalWorkDays': 128},
    ];

/// 목록 순서(서버 순서 그대로 · 화면은 정렬하지 않는다) · 기대 역할 칩 글자 · 상태 칩 수.
const _rows = <({String id, String name, String role, String label, int st})>[
  (id: 'u1', name: '김지원', role: 'USER', label: '지원자', st: 2),
  (id: 'u2', name: '이대기', role: 'USER', label: '지원자', st: 1),
  (id: 'b1', name: '남궁하늘빛', role: 'BUSINESS_ADMIN', label: '사업장관리자', st: 0),
  (id: 's1', name: '최운영', role: 'SUPER_ADMIN', label: '슈퍼관리자', st: 0),
  (id: 'm1', name: '정서브', role: 'USER', label: '지원자', st: 0),
  (id: 'f1', name: _longName, role: 'USER', label: '지원자', st: 0),
];

/// 역할 필터 4개(화면의 _roleLabels 순서) — 건수는 위 여섯 사람에서 나온다.
const _chipLabels = ['전체 (6)', '지원자 (4)', '관리자 (1)', '슈퍼관리자 (1)'];

/// 상태 칩 strict 기대 — 블랙리스트 · 제재중은 기존 StatusBadge 짝 그대로(C3 · DU492), 승인대기만 brand 짝으로 이행(실행 전 판정 D1).
///   before(base)의 승인대기는 infoBg · textPrimary 다 — 기록만 한다.
const _statusWant = <({String k, String name, String label, Color face, Color ink})>[
  (k: 'black', name: '김지원', label: '블랙리스트', face: AppColors.errorBg, ink: AppColors.errorDark),
  (k: 'restrict', name: '김지원', label: '제재중', face: AppColors.warningBg, ink: AppColors.warningDark),
  (k: 'pending', name: '이대기', label: '승인대기', face: AppColors.brandSurface, ink: AppColors.brand),
];

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f1(double v) => v.toStringAsFixed(1);
String _f2(double v) => v.toStringAsFixed(2);
String _hex(Color? c) => c == null ? 'none' : c.toARGB32().toRadixString(16).padLeft(8, '0');
bool _same(Color? a, Color b) => a != null && a.toARGB32() == b.toARGB32();
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

/// [a] 가 [b] **안**에 있는가(겹침이 아니라 포함 · 0.5px 허용).
bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

/// 글자 줄 수 — 글자마다 선택 상자의 top 을 모아 서로 다른 줄을 센다(DU493 과 같다 · TextPainter 전용 API 없음).
int _lineCount(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final tops = <double>[];
  for (var i = 0; i < s.length; i++) {
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (boxes.isEmpty) continue;
    if (!tops.any((x) => (x - boxes.first.top).abs() < 0.5)) tops.add(boxes.first.top);
  }
  return tops.length;
}

double _cr(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// 놓인 면 — 조상의 칠한 색을 불투명 층까지 모아 합성한다(DU492 · DU476 과 같다).
///   [DU513] 칩 면은 RawChip 의 Ink(ShapeDecoration)에 칠해진다 — Ink 도 면으로 센다. 색 없는 canvas/card Material 은 테마 기본색을 칠한다.
Color? _bgOf(Element e) {
  final layers = <Color>[];
  e.visitAncestorElements((x) {
    final w = x.widget;
    Color? c;
    if (w is Container) {
      c = w.color ?? (w.decoration is BoxDecoration ? (w.decoration! as BoxDecoration).color : null);
    } else if (w is ColoredBox) {
      c = w.color;
    } else if (w is Ink) {
      final d = w.decoration;
      c = d is ShapeDecoration ? d.color : (d is BoxDecoration ? d.color : null);
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color ?? (w.type == MaterialType.canvas ? Theme.of(x).canvasColor : (w.type == MaterialType.card ? Theme.of(x).cardColor : null));
    }
    // preflight v16 — 투명(알파 0) Material 은 칠한 면이 아니다.
    if (c != null && c.a > 0) {
      layers.add(c);
      if (c.a >= 1) return false;
    }
    return true;
  });
  if (layers.isEmpty) return null;
  var out = layers.last;
  for (final c in layers.reversed.skip(1)) {
    out = Color.alphaBlend(c, out);
  }
  return out;
}

/// 화면에 실제로 보이지 않는 글 — 아이콘 글리프(Icon 안 RichText) · 투명(Opacity/AnimatedOpacity/FadeTransition 0 · 입력 힌트 · 라벨) ·
///   Offstage · Visibility 숨김(DU454 · DU507 함정).
bool _hidden(Element e) {
  var gone = false;
  e.visitAncestorElements((x) {
    final w = x.widget;
    if (w is Icon ||
        (w is Opacity && w.opacity == 0) ||
        (w is AnimatedOpacity && w.opacity == 0) ||
        (w is FadeTransition && w.opacity.value == 0) ||
        (w is Offstage && w.offstage) ||
        (w is Visibility && !w.visible)) {
      gone = true;
      return false;
    }
    return true;
  });
  return gone;
}

/// 보이는 칸 — 가장 가까운 Scrollable 의 viewport ∩ 화면(DU508 r2 — 화면 경계만 보면 스크롤 칸 밖을 '보임'으로 오판).
Rect _clipOf(Element e, Rect screen) {
  Rect? vp;
  e.visitAncestorElements((x) {
    if (x.widget is Scrollable) {
      final ro = x.renderObject;
      if (ro is RenderBox && ro.hasSize) vp = ro.localToGlobal(Offset.zero) & ro.size;
      return false;
    }
    return true;
  });
  final got = vp;
  return got == null ? screen : got.intersect(screen);
}

typedef _Chip = ({bool lab, bool sel, Color? face, Color? tx, Color? side, Color? mark, double cr, Rect r, bool hit, bool look});

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '513';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du513-tb' && _env['DU_BEFORE_OBSERVE'] == '513') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du513-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S052UC-${v.id}-USERS 전체 사용자 목록 — 역할 칩 · 아바타 한 가지 · 선택 brand · 상태 칩 보존 · 실바탕 대비 · 끝 도달 · 행 탭 · 읽기 경계', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S052UC-${v.id}-USERS';
        final mode = _before ? 'before' : 'strict';
        _out('D513 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
        final overflows = <String>[];
        final fwErrors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            final full = d.toString();
            final k = full.indexOf('The relevant error-causing widget was');
            final loc = k < 0 ? '' : full.substring(k).split('\n').skip(1).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
            overflows.add('${m.split('\n').first} @ $loc');
          } else {
            fwErrors.add(m.split('\n').first);
            prev?.call(d);
          }
        };
        addTearDown(() => FlutterError.onError = prev);
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        // 시험 배선 · 존재(뒤 측정이 기대는 것)는 바로 단언한다. 화면 판정은 모아 두었다가 넘침 수집기를 되돌린 뒤 한꺼번에(v34).
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        // 읽기 경계 — 실제 Pigeon CF 채널에 모의를 붙이고, 모든 플랫폼 메시지와 HTTP 를 관찰 · 차단한다(DU508 r4 와 같은 대역).
        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final cf = _CfMock();
        final wire = _Wire();
        messenger.setMockMessageHandler(_cfChannel, cf.handle);
        messenger.allMessagesHandler = (channel, handler, message) => wire.route(messenger, channel, handler, message);
        addTearDown(() {
          messenger.allMessagesHandler = null;
          messenger.setMockMessageHandler(_cfChannel, null);
        });
        final net = _NoHttp();
        final prevHttp = HttpOverrides.current;
        HttpOverrides.global = net;
        addTearDown(() => HttpOverrides.global = prevHttp);

        var nReads = 0;
        final key = GlobalKey();
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: ChangeNotifierProvider<UserProvider>(
            create: (_) => _Super(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.superAdminTheme,
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: AllUsersScreen(reads: AllUsersReads(allUsersRaw: () async {
                nReads++;
                return _users();
              })),
            ),
          ),
        ));
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        final screen = Offset.zero & Size(v.w, v.h);
        // 세로 목록 Scrollable — 이름 finder 의 조상으로 잡으면 첫 행이 캐시 밖으로 빠질 때 사라진다. 방향으로 한 번 고정한다.
        final listF = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down, skipOffstage: false);
        final nList = listF.evaluate().length;
        need('세로 목록 Scrollable 1', nList == 1, '개수 $nList');
        final scroll = listF.first;
        final pad = t.widget<ListView>(find.byType(ListView)).padding as EdgeInsets;

        // 보이는 모든 글자의 실바탕 대비 — 보이는 칸(가장 가까운 Scrollable ∩ 화면) 안 · 숨김/아이콘 글리프 제외. 측정마다 모은다.
        var tN = 0;
        var tBad = 0;
        var tUnk = 0;
        var tMin = 99.0;
        var tWorst = '-';
        final tFails = <String>[];
        void scan(String where) {
          for (final e in find.byType(RichText).evaluate()) {
            if (_hidden(e)) continue;
            final box = e.renderObject;
            if (box is! RenderBox || !box.hasSize) continue;
            final at = box.localToGlobal(Offset.zero) & box.size;
            if (!at.overlaps(_clipOf(e, screen))) continue;
            final txt = _plainOf(e.widget);
            if (txt.trim().isEmpty) continue;
            final fg0 = (e.widget as RichText).text.style?.color;
            final bg = _bgOf(e) ?? AppColors.surface;
            if (fg0 == null) {
              tUnk++;
              tFails.add('$where 색 없음 $txt');
              continue;
            }
            final fg = fg0.a < 1 ? Color.alphaBlend(fg0, bg) : fg0;
            final ratio = _cr(fg, bg);
            tN++;
            if (ratio < tMin) {
              tMin = ratio;
              tWorst = '${_hex(fg)}/${_hex(bg)}';
            }
            if (ratio < 4.5) {
              tBad++;
              tFails.add('$where $txt ${_hex(fg)}/${_hex(bg)} ${_f2(ratio)}');
            }
          }
        }

        // ① 머리 — 전체 수 제목 · 전체 필터 건수(보존).
        final titleN = rt((p) => p == '전체 사용자 관리 (6명)').evaluate().length;
        final allN = rt((p) => p == '전체 (6)').evaluate().length;
        final headTitle = titleN == 1;
        final headAll = allN == 1;
        _out('D513 $tok att head title=$headTitle all=$headAll');
        if (!_before) {
          chk('strict 머리 제목 전체 수 · 전체 필터 건수', headTitle && headAll, 'title $titleN all $allN');
        }

        // ② 검색 힌트 — 보임(투명 힌트 아님) · 실바탕 대비. 입력은 아래 ⑤에서.
        final hintF = rt((p) => p == '이름 · 아이디 · 연락처 검색');
        final hintN = hintF.evaluate().length;
        need('검색 힌트 1', hintN == 1, '개수 $hintN');
        final hintEl = hintF.evaluate().first;
        final hintShown = !_hidden(hintEl);
        final hintC = (hintEl.widget as RichText).text.style?.color;
        final hintBg = _bgOf(hintEl) ?? AppColors.surface;
        final hintCr = hintC == null ? 0.0 : _cr(hintC.a < 1 ? Color.alphaBlend(hintC, hintBg) : hintC, hintBg);
        scan('top');
        var shots = 0;
        _out('D513 $tok shot 1list ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_1list', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'USERS',
          'state': 'user-list-top-all-selected',
        });
        shots++;

        // ③ 역할 필터 4개 — 실제 면(Ink ShapeDecoration) · 테두리 · 글자 · 체크 색 · 대비 · 받는 자리. 가로 스크롤 줄이라 칩마다 보이게 한 뒤 잰다.
        final chipsF = find.byType(FilterChip);
        final nChips = chipsF.evaluate().length;
        need('필터 칩 4', nChips == 4, '개수 $nChips');
        Future<_Chip> measChip(int i) async {
          await t.ensureVisible(chipsF.at(i));
          await t.pump(const Duration(milliseconds: 50));
          final chipW = t.widget<FilterChip>(chipsF.at(i));
          final chipLab = chipW.label;
          final lab = chipLab is Text && chipLab.data == _chipLabels[i];
          final deco = t.widget<Ink>(find.descendant(of: chipsF.at(i), matching: find.byType(Ink), skipOffstage: false).first).decoration;
          final face = deco is ShapeDecoration ? deco.color : null;
          final shape = deco is ShapeDecoration ? deco.shape : null;
          final side = shape is OutlinedBorder ? shape.side.color : null;
          final labEl = find.descendant(of: chipsF.at(i), matching: find.byType(RichText), skipOffstage: false).evaluate().first;
          final tx = (labEl.widget as RichText).text.style?.color;
          final bg = _bgOf(labEl) ?? AppColors.surface;
          final cr = tx == null ? 0.0 : _cr(tx.a < 1 ? Color.alphaBlend(tx, bg) : tx, bg);
          final r = t.getRect(chipsF.at(i));
          final hs = t.getRect(find.ancestor(of: chipsF.at(i), matching: find.byType(Scrollable)).first).intersect(screen);
          final chipRo = t.renderObject(chipsF.at(i));
          final hit = r.overlaps(hs) && t.hitTestOnBinding(r.intersect(hs).center).path.any((e) => e.target == chipRo);
          final sel = chipW.selected;
          final look = sel
              ? _same(face, AppColors.brandSurface) && _same(tx, AppColors.brand) && _same(side, AppColors.brand) && _same(chipW.checkmarkColor, AppColors.brand)
              : _same(face, AppColors.surface) && _same(tx, AppColors.textSecondary) && _same(side, AppColors.grey200);
          return (lab: lab, sel: sel, face: face, tx: tx, side: side, mark: chipW.checkmarkColor, cr: cr, r: r, hit: hit, look: look);
        }

        for (var i = 0; i < 4; i++) {
          final c0 = await measChip(i);
          need('필터 칩 $i 이름 ${_chipLabels[i]}', c0.lab);
          final okC = c0.cr >= 4.5;
          final rxC = c0.r.height >= 48 - 0.01 && c0.r.width >= 48 - 0.01;
          _out('D513 $tok att filter idx=$i sel=${c0.sel} face=${_hex(c0.face)} tx=${_hex(c0.tx)} side=${_hex(c0.side)} mark=${_hex(c0.mark)} '
              'cr=${_f2(c0.cr)} rh=${_f1(c0.r.height)} look=${c0.look} ok=$okC rx=$rxC hit=${c0.hit}');
          scan('chip$i');
          if (!_before) {
            chk('strict 필터 칩 $i — 선택 brand · 미선택 중립(흰 면 · 옅은 테두리 · 보조 글자) · 대비 ≥ 4.5 · 받는 자리 ≥ 48 · 중심 hit', c0.look && okC && rxC && c0.hit,
                'sel ${c0.sel} face ${_hex(c0.face)} tx ${_hex(c0.tx)} side ${_hex(c0.side)} mark ${_hex(c0.mark)} cr ${_f2(c0.cr)} h ${_f1(c0.r.height)} hit ${c0.hit}');
          }
        }

        // ④ '관리자' 필터 실제 탭 → 목록 1장 · 선택 칩 brand · 전체 칩 중립 → '전체' 실제 탭으로 되돌림(필터 동작 보존).
        await t.ensureVisible(chipsF.at(2));
        await t.pump(const Duration(milliseconds: 50));
        await t.tap(chipsF.at(2));
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        final pickCards = find.byType(Card).evaluate().length;
        final pickName = rt((p) => p == '남궁하늘빛').evaluate().length == 1;
        final pk = await measChip(2);
        final pa = await measChip(0);
        final pickSel = pk.sel && !pa.sel;
        await t.ensureVisible(chipsF.at(2));
        await t.pump(const Duration(milliseconds: 50));
        scan('pick');
        _out('D513 $tok shot 2filter ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_2filter', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'USERS',
          'state': 'user-list-filter-admin-selected',
        });
        shots++;
        await t.ensureVisible(chipsF.at(0));
        await t.pump(const Duration(milliseconds: 50));
        await t.tap(chipsF.at(0));
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        final backCards = find.byType(Card).evaluate().length;
        final backFirst = rt((p) => p == '김지원').evaluate().length == 1;
        final pickBack = backFirst && backCards > 1;
        _out('D513 $tok att pick cards=$pickCards name=$pickName sel=$pickSel look=${pk.look} was=${pa.look} back=$pickBack');
        if (!_before) {
          chk('strict 관리자 필터 — 1장 · 이름 · 선택 brand · 전체 칩 중립 · 다시 전체', pickCards == 1 && pickName && pickSel && pk.look && pa.look && pickBack,
              'cards $pickCards name $pickName sel $pickSel look ${pk.look} was ${pa.look} back $backCards/$backFirst');
        }

        // ⑤ 검색 실제 입력 → 1건 → 지우면 전체(검색 동작 보존). 끝나면 포커스를 놓는다.
        final fieldF = find.byType(TextField);
        final nField = fieldF.evaluate().length;
        need('검색 칸 1', nField == 1, '개수 $nField');
        await t.enterText(fieldF, 'nguyen');
        for (var i = 0; i < 3; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        final oneCards = find.byType(Card).evaluate().length;
        final oneName = rt((p) => p == _longName).evaluate().length;
        final searchOne = oneCards == 1 && oneName == 1;
        await t.enterText(fieldF, '');
        for (var i = 0; i < 3; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        final againCards = find.byType(Card).evaluate().length;
        final againFirst = rt((p) => p == '김지원').evaluate().length;
        final searchBack = againCards > 1 && againFirst == 1;
        FocusManager.instance.primaryFocus?.unfocus();
        for (var i = 0; i < 3; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        _out('D513 $tok att search hint=$hintShown hintCr=${_f2(hintCr)} one=$searchOne back=$searchBack');
        if (!_before) {
          chk('strict 검색 — 힌트 보임 · 대비 ≥ 4.5 · 입력 1건 · 지우면 전체', hintShown && hintCr >= 4.5 && searchOne && searchBack,
              'hint $hintShown cr ${_f2(hintCr)} one $oneCards/$oneName back $againCards/$againFirst');
        }

        // ⑥ 행마다(실제 끌기로 차례로 내려 닿게 한다 · DU493 경로) — 아바타 · 역할 칩 실제 색(raw ARGB) · 대비 · 상태 칩 · 받는 자리 · 카드 폭.
        final rowSeen = <({String id, bool avOk, bool avIc, bool chipOk, bool crOk, bool rx, bool hit, bool inOk, bool fit})>[];
        final statusSeen = <({String k, bool keep, bool ok})>[];
        for (final row in _rows) {
          final nameF = rt((p) => p == row.name);
          await t.scrollUntilVisible(nameF, 120, scrollable: scroll, maxScrolls: 40);
          await t.pump(const Duration(milliseconds: 50));
          final cardF = find.ancestor(of: nameF, matching: find.byType(Card));
          final nCard = cardF.evaluate().length;
          need('${row.id} 카드 1', nCard == 1, '개수 $nCard');
          final vpR = t.getRect(scroll);
          final vis = vpR.intersect(screen);
          final cardR = t.getRect(find.descendant(of: cardF, matching: find.byType(Material), skipOffstage: false).first);
          final fit = (cardR.left - (vpR.left + pad.left)).abs() <= 0.5 && (cardR.right - (vpR.right - pad.right)).abs() <= 0.5;
          final inkF = find.descendant(of: cardF, matching: find.byType(InkWell), skipOffstage: false);
          final nInk = inkF.evaluate().length;
          need('${row.id} 행 InkWell 1', nInk == 1, '개수 $nInk');
          final inkR = t.getRect(inkF);
          final rowRo = t.renderObject(inkF);
          final hit = inkR.overlaps(vis) && t.hitTestOnBinding(inkR.intersect(vis).center).path.any((e) => e.target == rowRo);
          final rx = inkR.height >= 48 - 0.01 && inkR.width >= 48 - 0.01;
          final avF = find.descendant(of: cardF, matching: find.byType(CircleAvatar), skipOffstage: false);
          final nAv = avF.evaluate().length;
          need('${row.id} 아바타 1', nAv == 1, '개수 $nAv');
          final avDeco = t.widget<DecoratedBox>(find.descendant(of: avF, matching: find.byType(DecoratedBox), skipOffstage: false).first).decoration;
          final av = avDeco is BoxDecoration ? avDeco.color : null;
          final avI = t.widget<RichText>(find.descendant(of: avF, matching: find.byType(RichText), skipOffstage: false).first).text.style?.color;
          // [r1 · 판정 D2] 색만으로는 아이콘 모양을 입증하지 못한다 — 아바타 안 Icon 의 IconData 가 사람(person)인지도 본다(base 블랙리스트 행은 block).
          final avIcon = t.widget<Icon>(find.descendant(of: avF, matching: find.byType(Icon), skipOffstage: false).first).icon;
          final avIc = avIcon == Icons.person;
          final chipTxF = find.descendant(
              of: cardF, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == row.label, skipOffstage: false), skipOffstage: false);
          final nChipTx = chipTxF.evaluate().length;
          need('${row.id} 역할 칩 ${row.label} 1', nChipTx == 1, '개수 $nChipTx');
          final chipEl = chipTxF.evaluate().first;
          final chipTx = (chipEl.widget as RichText).text.style?.color;
          final chipDeco = t.widget<Container>(find.ancestor(of: chipTxF, matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration)).first)
              .decoration as BoxDecoration?;
          final chipBg = chipDeco?.color;
          final chipBorder = chipDeco?.border;
          final chipBd = chipBorder is Border ? _hex(chipBorder.top.color) : 'none';
          final chipFace = _bgOf(chipEl) ?? AppColors.surface;
          final chipCr = chipTx == null ? 0.0 : _cr(chipTx.a < 1 ? Color.alphaBlend(chipTx, chipFace) : chipTx, chipFace);
          final chipR = t.getRect(chipTxF);
          final nameR = t.getRect(nameF);
          final nameL = _lineCount(t.renderObject(nameF) as RenderParagraph);
          final inOk = _inside(nameR, vis) && _inside(chipR, vis) && _inside(nameR, cardR) && _inside(chipR, cardR);
          final nSt = find.descendant(
                  of: cardF,
                  matching: find.byWidgetPredicate((w) => w is RichText && const {'블랙리스트', '제재중', '승인대기'}.contains(_plainOf(w)), skipOffstage: false),
                  skipOffstage: false)
              .evaluate()
              .length;
          need('${row.id} 상태 칩 수 ${row.st}', nSt == row.st, '개수 $nSt');
          for (final s in _statusWant.where((x) => x.name == row.name)) {
            final stF = find.descendant(
                of: cardF, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == s.label, skipOffstage: false), skipOffstage: false);
            final stEl = stF.evaluate().first;
            final stTx = (stEl.widget as RichText).text.style?.color;
            final stDeco = t.widget<Container>(find.ancestor(of: stF, matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration)).first)
                .decoration as BoxDecoration?;
            final stFace = stDeco?.color;
            final stBg = _bgOf(stEl) ?? AppColors.surface;
            final stCr = stTx == null ? 0.0 : _cr(stTx, stBg);
            final keep = _same(stFace, s.face) && _same(stTx, s.ink);
            final stOk = stCr >= 4.5;
            statusSeen.add((k: s.k, keep: keep, ok: stOk));
            _out('D513 $tok att status k=${s.k} face=${_hex(stFace)} tx=${_hex(stTx)} cr=${_f2(stCr)} keep=$keep ok=$stOk');
          }
          final avOk = _same(av, AppColors.brandSurface) && _same(avI, AppColors.brand);
          final chipOk = _same(chipBg, AppColors.grey200) && chipBd == 'none' && _same(chipTx, AppColors.grey700);
          final crOk = chipCr >= 4.5;
          rowSeen.add((id: row.id, avOk: avOk, avIc: avIc, chipOk: chipOk, crOk: crOk, rx: rx, hit: hit, inOk: inOk, fit: fit));
          _out('D513 $tok att row id=${row.id} role=${row.role} st=$nSt av=${_hex(av)} avI=${_hex(avI)} chipBg=${_hex(chipBg)} chipBd=$chipBd '
              'chipTx=${_hex(chipTx)} cr=${_f2(chipCr)} nameL=$nameL rh=${_f1(inkR.height)} avOk=$avOk avIc=$avIc chipOk=$chipOk crOk=$crOk rx=$rx hit=$hit in=$inOk fit=$fit');
          scan('row-${row.id}');
        }
        if (!_before) {
          for (final x in rowSeen) {
            chk('strict 행 ${x.id} — 아바타 옅은 brand 원 + 사람 아이콘 한 가지 · 역할 칩 중립 · 대비 ≥ 4.5 · 받는 자리 ≥ 48 · 중심 hit · 이름/칩 보임 · 카드 폭 = 목록 폭',
                x.avOk && x.avIc && x.chipOk && x.crOk && x.rx && x.hit && x.inOk && x.fit, '값 $x');
          }
          for (final x in statusSeen) {
            chk('strict 상태 칩 ${x.k} — 블랙리스트 error · 제재중 warning 짝 보존 · 승인대기 brand 짝 · 대비 ≥ 4.5', x.keep && x.ok, '값 $x');
          }
        }

        // ⑦ 끝 도달 — 실제 끌기로 목록 끝까지 · 마지막 카드 전체가 보이는 칸 안 · 그 카드 중심 hit.
        await t.drag(scroll, const Offset(0, -3000));
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        final endPos = t.state<ScrollableState>(scroll).position;
        final endPx = endPos.pixels;
        final endMax = endPos.maxScrollExtent;
        final endAt = endPx >= endMax - 0.5;
        final lastF = rt((p) => p == _longName);
        final nLast = lastF.evaluate().length;
        need('마지막 행 이름 1', nLast == 1, '개수 $nLast');
        final lastCardF = find.ancestor(of: lastF, matching: find.byType(Card));
        final lastR = t.getRect(find.descendant(of: lastCardF, matching: find.byType(Material), skipOffstage: false).first);
        final endVis = t.getRect(scroll).intersect(screen);
        final lastInkF = find.descendant(of: lastCardF, matching: find.byType(InkWell), skipOffstage: false);
        final lastInkR = t.getRect(lastInkF);
        final tapPt = lastInkR.intersect(endVis).center;
        final lastRo = t.renderObject(lastInkF);
        final endHit = lastInkR.overlaps(endVis) && t.hitTestOnBinding(tapPt).path.any((e) => e.target == lastRo);
        final endIn = _inside(lastR, endVis);
        _out('D513 $tok att end px=${_f1(endPx)} max=${_f1(endMax)} at=$endAt in=$endIn hit=$endHit');
        if (!_before) {
          chk('strict 끝 도달 — 끝 · 마지막 카드 보이는 칸 안 · 중심 hit', endAt && endIn && endHit, 'px ${_f1(endPx)} max ${_f1(endMax)} in $endIn hit $endHit');
        }
        scan('end');
        _out('D513 $tok shot 3end ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_3end', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'USERS',
          'state': 'user-list-end',
        });
        shots++;

        // ⑧ 행 실제 탭 → 상세 시트(O107) 열림 · 대상 @아이디 → 바깥(막) 실제 탭 → 닫힘 · 목록 남음(행 탭 보존 · 시트는 이 셀 범위 밖이라 보지 않는다).
        await t.tapAt(tapPt);
        await t.pump();
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        final sheetN = find.byType(BottomSheet).evaluate().length;
        final whoN = rt((p) => p == '@foreign01 · 지원자').evaluate().length;
        await t.tapAt(Offset(v.w / 2, 8));
        await t.pump();
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        final sheetAfter = find.byType(BottomSheet).evaluate().length;
        final rowsAfter = rt((p) => p == _longName).evaluate().length;
        final tapWho = whoN == 1;
        final tapClosed = sheetAfter == 0;
        final tapRows = rowsAfter == 1;
        _out('D513 $tok att tap sheet=$sheetN who=$tapWho closed=$tapClosed rows=$tapRows');
        if (!_before) {
          chk('strict 행 탭 — 상세 시트 열림 · 대상 @아이디 · 바깥 탭 닫힘 · 목록 남음', sheetN == 1 && tapWho && tapClosed && tapRows,
              'sheet $sheetN who $whoN after $sheetAfter rows $rowsAfter');
        }

        // ⑨ 읽기 경계 — 연 뒤 · 필터 · 검색 · 시트 열고 닫은 뒤까지 주입 reader 정확 1 · CF 채널 0 · 예상 밖 채널 0 · HTTP 0.
        final nCalls = nReads;
        final nCf = cf.calls.length;
        final cfNames = cf.calls.join(',');
        final nUnexp = wire.unexpected.length;
        final unexpNames = wire.unexpected.join(' | ');
        final nHttp = net.tries.length;
        final nFrame = wire.framework;
        _out('D513 $tok att reader calls=$nCalls cf=$nCf unexpected=$nUnexp http=$nHttp fw=$nFrame');
        chk('읽기 경계 — 주입 reader 정확 1 · Cloud Functions 호출 0', nCalls == 1 && nCf == 0, 'calls $nCalls cf [$cfNames]');
        if (!_before) {
          chk('strict 예상 밖 플랫폼 채널 0 · HTTP 0', nUnexp == 0 && nHttp == 0, '예상 밖 [$unexpNames] http $nHttp');
        }

        // ⑩ 글자 대비 합계 — 머리 · 검색 · 필터(칩마다) · 관리자 필터 · 행마다 · 끝.
        final textMin = tN == 0 ? 0.0 : tMin;
        _out('D513 $tok att text n=$tN min=${_f2(textMin)} bad=$tBad unk=$tUnk worst=$tWorst');
        if (!_before) {
          chk('strict 보이는 글자 실바탕 대비 ≥ 4.5(전체 스크롤 · 필터 · 머리 · 검색)', tN > 0 && tBad == 0 && tUnk == 0, '미달 ${tFails.take(8).join(' | ')}');
        }

        // 측정 끝 — 값은 모두 위에서 변수로 잡았다. 넘침 수집기를 되돌린 뒤 모은 단언을 던진다(v34 · 이 뒤 화면 읽기 0).
        final nOvf = overflows.length;
        final ovfRaw = overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '');
        final ovfText = overflows.join(' | ');
        final nFwErr = fwErrors.length;
        final fwText = fwErrors.join(' | ');
        if (!_before) {
          chk('strict 넘침 0', nOvf == 0, ovfText);
        }
        chk('미처리 framework 예외 0', nFwErr == 0, fwText);
        FlutterError.onError = prev;
        for (final c in checks) {
          expect(c.$2, isTrue, reason: '$tok ${c.$1} ${c.$3}');
        }
        final exc = t.takeException();
        _out('D513 $tok done state=USERS mode=$mode captures=$shots overflows=$nOvf exc=${exc != null} ovfRaw=$ovfRaw');
        expect(exc, isNull, reason: '$tok 끝 예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
