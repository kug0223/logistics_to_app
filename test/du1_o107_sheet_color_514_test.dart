// ignore_for_file: depend_on_referenced_packages
// [DU514 · NCB-52D · 색 예산 · 표시만] O107 사용자 상세 시트(슈퍼관리자 · all_users_screen `_UserDetailSheet`) — 시트 색 한 묶음.
//   before = 현재 A(all_users_screen c266bab4 · DU513 채택판) / strict = 후보 r1(NCB-52D — 시트 + 사유 창 공개 안내 error→errorDark 한 토큰 · 목록 원바이트).
//   [r1 · 실행 전 판정] 사유 창 공개 안내 존재 · 원문 · errorDark · 대비와 창 관측 글자 양수 · 미달 0 · 미확인 0 을 strict 로 단언한다(입력칸 힌트는 따로 기록) ·
//   오류 처리기 · 그림자 설정은 본문 finally 에서 되돌리고 원실패를 전파한다 · 위젯 해제 뒤 읽기 경계를 최종 집계한다.
//   [r2 · 힌트 판정 H1 (가)] 사유 창 strict = '힌트 제외 관측 텍스트 요소 미달 0 · 미확인 0, 최종 등록 버튼 별도 대비 ≥ 4.5'.
//   제외는 StyledDialogTextField 의 원문 힌트 정확 1개뿐이고, 그 힌트의 존재 · 실제 grey400/grey50 · 관측 성공은 단언한다(대비만 면제 · NCB-52D-HINT-1 OPEN).
//   후보: 머리 역할 칩 중립 · 아바타 옅은 brand 원 + 사람 아이콘(목록과 같음) · 통계 칸 중립 면(값 textPrimary · 낮춘 값 textSecondary · 라벨 textSecondary) ·
//   계정 상태 = 중립 행 + 상태 이름만 작은 칩(블랙리스트 error · 제한 warning · 확인 불가 warning · 승인대기 brand · 정상 중립) ·
//   관리 행동 진입 버튼 = 같은 중립 외곽선. 위험색은 확인 창의 최종 실행 버튼(readableFill errorDark)에만 남는다.
//   상태 6(BLACK 블랙리스트+노쇼 자동 제한 · PEND 승인대기 + 등록 진입 → 사유 창 → 취소 · MANUAL 관리자 수동 제한 · UNREAD 제한 확인 불가 ·
//   SUPER 슈퍼관리자 정상(행동 0) · BIZ 사업장관리자 정상 · 긴 이름) × W390×844@1 / B320×640@2.
//   BLACK 은 시트를 열기 전 목록에서 시험 한정 debugDisableShadows=false 일반 그림자 캡처(0shadow)를 한 장 더 찍고 즉시 되돌린다
//   (전후 값 · 카드 실제 side/elevation 기록 · 원 캡처는 따로 · 같은 호출 안 · 후속123 §1).
//   before 는 화면 값을 기록만 한다 — 단언은 시험 배선(읽기 1 · cf 0 · 그림자 설정 복구) · 존재(need) · framework 예외 0 · 끝 예외 0 뿐이다.
//   기본 skip — TB before/du514-tb/DU_BEFORE_OBSERVE=514 · TA after/du514-ta/없음.
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
import 'package:ALfit/widgets/dialogs/styled_dialog.dart';

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

/// RR57 · DU492/493 · DU513 과 같은 슈퍼관리자 대역.
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

/// [DU508 r4 · DU513 과 같은 대역] 실제 Cloud Functions 플랫폼 채널(Pigeon).
const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// 목록 읽기는 주입 reader 뿐이다 — 이 채널 호출(블랙리스트 · 제재 해제 등 쓰기)은 전부 예상 밖이다. 이름을 남기고 오류로 막는다(끝에 0 단언).
class _CfMock {
  final calls = <String>[];

  Future<ByteData?> handle(ByteData? message) async {
    final args = (const StandardMessageCodec().decodeMessage(message) as List).first as Map;
    calls.add((args['functionName'] ?? '-').toString());
    return const StandardMessageCodec().encodeMessage(<Object?>['blocked', 'DU514 시험 — 예상 밖 Cloud Functions 호출', null]);
  }
}

/// 모든 플랫폼 메시지 관찰 — CF 채널은 모의로, 'flutter/' 프레임워크 채널은 원래 경로로(센다), 그 밖은 기록 · 차단.
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

/// 외부 HTTP 차단 — 시도를 기록하고 실패시킨다(끝에 0 단언).
class _NoHttp extends HttpOverrides {
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    throw const SocketException('DU514 시험 — 외부 HTTP 차단');
  }
}

// callable 응답 모양 그대로(RR57 · RM58) — Timestamp 는 {_seconds, _nanoseconds}.
Map<String, int> _ts(DateTime t) => {'_seconds': t.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};
DateTime _sec(DateTime t) => DateTime.fromMillisecondsSinceEpoch((t.millisecondsSinceEpoch ~/ 1000) * 1000);
final _auto = _sec(DateTime.now().add(const Duration(days: 1)));
final _manual = _sec(DateTime.now().add(const Duration(days: 30)));
const _longName = 'NGUYEN THI MINH KHAI';

/// 여섯 사람(목록은 모든 사례에서 같다 · 사례마다 한 사람의 시트를 연다).
List<Map<String, dynamic>> _users() => [
      {'uid': 'u1', 'username': 'worker01', 'name': '김지원', 'email': 'u1@alfit.local', 'role': 'USER', 'createdAt': _ts(DateTime(2026, 1, 1)),
       'contactPhone': '010-1234-5678', 'totalWorkDays': 12, 'noShowCount': 3, 'recentNoShowCount': 3, 'recentLateCount': 0, 'averageRating': 4.5,
       'reviewCount': 3, 'isBlacklisted': true, 'blacklistReason': '시험',
       'restrictedUntil': _ts(_auto), 'restrictionSource': 'auto', 'restrictionParts': {'auto': _ts(_auto)}},
      {'uid': 'u2', 'username': 'worker02', 'name': '이대기', 'email': 'u2@alfit.local', 'role': 'USER', 'createdAt': _ts(DateTime(2026, 2, 1)),
       'accountStatus': 'registration_pending'},
      {'uid': 'm1', 'username': 'worker03', 'name': '박수동', 'email': 'm1@alfit.local', 'role': 'USER', 'createdAt': _ts(DateTime(2026, 3, 1)),
       'restrictedUntil': _ts(_manual), 'restrictionSource': 'manual', 'restrictionParts': {'base': _ts(_manual), 'baseSource': 'manual'}},
      {'uid': 'x1', 'username': 'worker04', 'name': '최확인', 'email': 'x1@alfit.local', 'role': 'USER', 'createdAt': _ts(DateTime(2026, 4, 1)),
       'restrictedUntil': {'unexpected': 1}, 'restrictionSource': 'manual'},
      {'uid': 's1', 'username': 'ops01', 'name': '최운영', 'email': 's1@alfit.local', 'role': 'SUPER_ADMIN', 'createdAt': _ts(DateTime(2026, 5, 1))},
      {'uid': 'b1', 'username': 'boss01', 'name': _longName, 'email': 'b1@alfit.local', 'role': 'BUSINESS_ADMIN', 'createdAt': _ts(DateTime(2026, 6, 1)),
       'businessName': '강남 물류센터', 'totalWorkDays': 128, 'recentLateCount': 5},
    ];

/// 사례 — 연 사람 · 머리 부제 · 통계 값/낮춤 · 상태 행 · 관리 행동 진입(순서 그대로).
const _states = <({String id, String name, String who, String role, List<String> stats, List<bool> muted, List<String> rows, List<String> acts})>[
  (id: 'BLACK', name: '김지원', who: '@worker01 · 지원자', role: '지원자', stats: ['12일', '3회', '0회', '4.5점', '3건'],
   muted: [false, false, true, false, false], rows: ['black', 'restrict'], acts: ['블랙리스트 해제', '제재 해제 (노쇼 카운트 초기화)']),
  (id: 'PEND', name: '이대기', who: '@worker02 · 지원자', role: '지원자', stats: ['0일', '0회', '0회', '-', '0건'],
   muted: [false, true, true, false, false], rows: ['pend'], acts: ['블랙리스트 등록']),
  (id: 'MANUAL', name: '박수동', who: '@worker03 · 지원자', role: '지원자', stats: ['0일', '0회', '0회', '-', '0건'],
   muted: [false, true, true, false, false], rows: ['restrict'], acts: ['블랙리스트 등록', '관리자 수동 제한 해제']),
  (id: 'UNREAD', name: '최확인', who: '@worker04 · 지원자', role: '지원자', stats: ['0일', '0회', '0회', '-', '0건'],
   muted: [false, true, true, false, false], rows: ['unread'], acts: ['블랙리스트 등록']),
  (id: 'SUPER', name: '최운영', who: '@ops01 · 슈퍼관리자', role: '슈퍼관리자', stats: ['0일', '0회', '0회', '-', '0건'],
   muted: [false, true, true, false, false], rows: ['normal'], acts: []),
  (id: 'BIZ', name: _longName, who: '@boss01 · 사업장관리자', role: '사업장관리자', stats: ['128일', '0회', '5회', '-', '0건'],
   muted: [false, true, false, false, false], rows: ['normal'], acts: ['블랙리스트 등록']),
];
const _statLabels = ['총 근무', '노쇼', '지각(90일)', '평점', '리뷰'];

/// [r1 · 판정 D3] 사유 창 공개 안내 원문(all_users_screen `_toggleBlacklist` visibilityNote 그대로 · 문구 · 공개 범위 불변).
/// [r2 · H1] 대비 미달 집계에서 빼는 **유일한** 글 — 사유 창 공용 입력칸(StyledDialogTextField)의 이 힌트 원문 하나.
const _hint = '예: 반복 노쇼, 이용 약관 위반 등';

const _note = '입력한 사유는 이 사용자에게 그대로 보입니다(로그인·지원이 막힐 때 안내). 신고자 정보 같은 내부 메모는 적지 마세요.';

/// 상태 행 strict 기대 — 상태 이름 · 칩 짝 · 설명(근거/기간 문구 그대로).
({String label, Color bg, Color ink}) _rowWant(String k) => switch (k) {
      'black' => (label: '블랙리스트', bg: AppColors.errorBg, ink: AppColors.errorDark),
      'restrict' => (label: '이용 제한 중', bg: AppColors.warningBg, ink: AppColors.warningDark),
      'unread' => (label: '제한 상태 확인 불가', bg: AppColors.warningBg, ink: AppColors.warningDark),
      'pend' => (label: '가입 승인 대기', bg: AppColors.brandSurface, ink: AppColors.brand),
      _ => (label: '정상', bg: AppColors.grey200, ink: AppColors.grey700),
    };
bool _descOk(String k, String d) => switch (k) {
      'black' => d == '시험',
      'restrict' => (d.startsWith('노쇼 자동 제한 ') || d.startsWith('관리자 수동 제한 ')) && d.endsWith('까지'),
      'unread' => d == '저장된 제한 값을 읽지 못했습니다. 새로고침 후 다시 확인해 주세요.',
      'pend' => d == '슈퍼관리자 승인 필요 (외국인 계정)',
      _ => d == '이용 제한 없음',
    };

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f1(double v) => v.toStringAsFixed(1);
String _f2(double v) => v.toStringAsFixed(2);
String _hex(Color? c) => c == null ? 'none' : c.toARGB32().toRadixString(16).padLeft(8, '0');
bool _same(Color? a, Color b) => a != null && a.toARGB32() == b.toARGB32();
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

/// [a] 가 [b] **안**에 있는가(포함 · 0.5px 허용).
bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

double _cr(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// 놓인 면 — 조상의 칠한 색을 불투명 층까지 합성한다(DU513 과 같다 · Ink · 색 없는 canvas/card Material 포함).
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
    } else if (w is InputDecorator && (w.decoration.filled ?? false)) {
      // [r1] 입력칸 채움 면(StyledDialogTextField grey50) — 힌트 바탕을 흰 면으로 가정하지 않는다.
      c = w.decoration.fillColor;
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

/// 보이지 않는 글 — 아이콘 글리프 · 투명(Opacity/AnimatedOpacity/FadeTransition 0) · Offstage · Visibility 숨김.
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

/// [r2 · H1] 예외 힌트인가 — 글이 정확히 [_hint] 이고, 가장 가까운 InputDecorator 의 hintText 도 [_hint] 이며, 그 위에 StyledDialogTextField 가 있다.
///   다른 hintText · 라벨 · 본문은 참이 아니다(일반 제외 0) — 그런 글은 기존 strict 미달/미확인 집계로 간다.
bool _isHint(Element e) {
  if (_plainOf(e.widget) != _hint) return false;
  var deco = false;
  var field = false;
  e.visitAncestorElements((x) {
    final w = x.widget;
    if (w is InputDecorator && !deco) deco = (w.decoration.hintText ?? '') == _hint;
    if (w is StyledDialogTextField) {
      field = true;
      return false;
    }
    return true;
  });
  return deco && field;
}

/// 보이는 칸 — 가장 가까운 Scrollable 의 viewport ∩ 화면.
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

/// [후속123 §1] debugDisableShadows 를 바꾼 뒤 이미 칠한 층을 다시 칠하게 한다(그림자 대체선 ↔ 일반 그림자).
void _repaintAll(WidgetTester t) {
  void walk(RenderObject r) {
    r.markNeedsPaint();
    r.visitChildren(walk);
  }

  for (final rv in t.binding.renderViews) {
    walk(rv);
  }
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '514';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du514-tb' && _env['DU_BEFORE_OBSERVE'] == '514') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du514-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    for (final c in _states) {
      testWidgets('S052DC-${v.id}-${c.id} 사용자 상세 시트 — 역할 칩 · 아바타 · 통계 중립 · 상태 작은 칩 · 진입 버튼 중립 · 최종 버튼 · 실바탕 대비 · 끝 도달 · 읽기 경계', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        // [r1 · 판정 §3-5] 이전 오류 처리기 · 그림자 설정은 try 밖에서 잡고, 본문 finally 에서 되돌린 뒤 원실패를 그대로 전파한다
        //   (need · 캡처가 먼저 실패해도 정상 경로 복구 줄에 기대지 않는다). tearDown 복구는 이중 안전장치로 남긴다.
        final prev = FlutterError.onError;
        final ds0 = debugDisableShadows;
        try {
          final tok = 'S052DC-${v.id}-${c.id}';
          final mode = _before ? 'before' : 'strict';
          _out('D514 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
          await t.runAsync(vqLoadFonts);
          final overflows = <String>[];
          final fwErrors = <String>[];
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
          void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
          final checks = <(String, bool, String)>[];
          void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

          // 읽기 경계 — DU513 과 같은 대역. [r1] 관측 범위: 이 줄 앞 준비(글꼴 적재 · 오류 처리기 · 화면 크기)는 감시 밖이다.
          //   감시 뒤 'flutter/' 프레임워크 채널(입력 · 플랫폼 · 커서 등)은 허용하고 수만 센다(fw). 그 밖 채널 · HTTP · CF 는 0 이어야 한다.
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
          addTearDown(() => debugDisableShadows = ds0);

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
          final screen = Offset.zero & Size(v.w, v.h);
          final appF = find.byType(AllUsersScreen);
          // 목록 세로 Scrollable — 시트 안 ListView 와 섞이지 않게 목록 화면 아래에서만 찾는다.
          final listF = find.descendant(
              of: appF, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down), skipOffstage: false);
          final nList = listF.evaluate().length;
          need('목록 세로 Scrollable 1', nList == 1, '개수 $nList');
          var shots = 0;

          // ⓪ [BLACK · 후속123 §1] 일반 그림자 목록 비교 — 시험 한정으로 끄고 한 장 · 즉시 되돌림 · 카드 실제 side/elevation 기록.
          if (c.id == 'BLACK') {
            final cardsF = find.descendant(of: appF, matching: find.byType(Card), skipOffstage: false);
            final nCards = cardsF.evaluate().length;
            need('목록 카드 1 이상', nCards > 0, '개수 $nCards');
            final card0 = t.widget<Card>(cardsF.first);
            final elev = card0.elevation ?? -1.0;
            final cShape = card0.shape;
            final cSide = cShape is OutlinedBorder ? cShape.side : BorderSide.none;
            final sideTxt = cSide.style == BorderStyle.none ? 'none' : 'w${_f1(cSide.width)}c${_hex(cSide.color)}';
            var ds1 = true;
            try {
              debugDisableShadows = false;
              _repaintAll(t);
              await t.pump();
              ds1 = debugDisableShadows;
              _out('D514 $tok shot 0shadow ovf=${overflows.length}');
              await vqCapture(t, key, '${tok}_0shadow', conditions: {
                'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': c.id,
                'state': 'list-ordinary-shadow',
              });
              shots++;
            } finally {
              debugDisableShadows = ds0;
              _repaintAll(t);
            }
            await t.pump();
            final ds2 = debugDisableShadows;
            _out('D514 $tok att card cards=$nCards elev=${_f1(elev)} side=$sideTxt ds0=$ds0 ds1=$ds1 ds2=$ds2');
            chk('그림자 설정 — 시험 기본 true → 비교 중 false → 되돌림 true', ds0 && !ds1 && ds2, 'ds $ds0/$ds1/$ds2');
          }

          // ① 목록 행 실제 탭 → 시트(DU513 경로 · 행 InkWell ∩ 보이는 칸 중심).
          final rowNameF = find.descendant(
              of: appF, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == c.name), skipOffstage: false);
          await t.scrollUntilVisible(rowNameF, 120, scrollable: listF.first, maxScrolls: 40);
          await t.pump(const Duration(milliseconds: 50));
          final rowCardF = find.ancestor(of: rowNameF, matching: find.byType(Card));
          final rowInkF = find.descendant(of: rowCardF, matching: find.byType(InkWell), skipOffstage: false);
          final nRowInk = rowInkF.evaluate().length;
          need('목록 행 InkWell 1', nRowInk == 1, '개수 $nRowInk');
          final rowVis = t.getRect(listF.first).intersect(screen);
          final rowPt = t.getRect(rowInkF).intersect(rowVis).center;
          await t.tapAt(rowPt);
          await t.pump();
          for (var i = 0; i < 6; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          final sheetF = find.byType(BottomSheet);
          final nSheet = sheetF.evaluate().length;
          need('상세 시트 1', nSheet == 1, '개수 $nSheet');
          Finder srt(bool Function(String p) p) => find.descendant(
              of: sheetF, matching: find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false), skipOffstage: false);
          final sheetScroll = find.descendant(of: sheetF, matching: find.byType(Scrollable, skipOffstage: false), skipOffstage: false).first;
          Rect sheetVis() => t.getRect(sheetScroll).intersect(t.getRect(sheetF)).intersect(screen);

          // 시트 안 보이는 모든 글자의 실바탕 대비 — 측정 위치마다 모은다(시트 범위만 · 뒤 목록 제외).
          var tN = 0;
          var tBad = 0;
          var tUnk = 0;
          var tMin = 99.0;
          var tWorst = '-';
          final tFails = <String>[];
          void scan(String where) {
            for (final e in find.descendant(of: sheetF, matching: find.byType(RichText)).evaluate()) {
              if (_hidden(e)) continue;
              final box = e.renderObject;
              if (box is! RenderBox || !box.hasSize) continue;
              final at = box.localToGlobal(Offset.zero) & box.size;
              if (!at.overlaps(_clipOf(e, screen).intersect(t.getRect(sheetF)))) continue;
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

          // ② 머리 — 아바타 실제 면 · 아이콘 색 · IconData · 역할 칩 면/테두리/글자 · 대비 · 부제(@아이디 · 역할).
          final avF = find.descendant(of: sheetF, matching: find.byType(CircleAvatar), skipOffstage: false);
          final nAv = avF.evaluate().length;
          need('시트 아바타 1', nAv == 1, '개수 $nAv');
          final avDeco = t.widget<DecoratedBox>(find.descendant(of: avF, matching: find.byType(DecoratedBox), skipOffstage: false).first).decoration;
          final av = avDeco is BoxDecoration ? avDeco.color : null;
          final avI = t.widget<RichText>(find.descendant(of: avF, matching: find.byType(RichText), skipOffstage: false).first).text.style?.color;
          final avIcon = t.widget<Icon>(find.descendant(of: avF, matching: find.byType(Icon), skipOffstage: false).first).icon;
          final avIc = avIcon == Icons.person;
          final roleF = srt((p) => p == c.role);
          final nRole = roleF.evaluate().length;
          need('시트 역할 칩 ${c.role} 1', nRole == 1, '개수 $nRole');
          final roleEl = roleF.evaluate().first;
          final roleTx = (roleEl.widget as RichText).text.style?.color;
          final roleDeco = t.widget<Container>(find.ancestor(of: roleF, matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration)).first)
              .decoration as BoxDecoration?;
          final roleBg = roleDeco?.color;
          final roleBorder = roleDeco?.border;
          final roleBd = roleBorder is Border ? _hex(roleBorder.top.color) : 'none';
          final roleFace = _bgOf(roleEl) ?? AppColors.surface;
          final roleCr = roleTx == null ? 0.0 : _cr(roleTx.a < 1 ? Color.alphaBlend(roleTx, roleFace) : roleTx, roleFace);
          final whoOk = srt((p) => p == c.who).evaluate().length == 1 && srt((p) => p == c.name).evaluate().length == 1;
          final avOk = _same(av, AppColors.brandSurface) && _same(avI, AppColors.brand);
          final chipOk = _same(roleBg, AppColors.grey200) && roleBd == 'none' && _same(roleTx, AppColors.grey700);
          final headCr = roleCr >= 4.5;
          _out('D514 $tok att head av=${_hex(av)} avI=${_hex(avI)} chipBg=${_hex(roleBg)} chipBd=$roleBd chipTx=${_hex(roleTx)} cr=${_f2(roleCr)} '
              'avOk=$avOk avIc=$avIc chipOk=$chipOk crOk=$headCr who=$whoOk');
          if (!_before) {
            chk('strict 머리 — 아바타 옅은 brand 원 + 사람 · 역할 칩 중립 · 대비 ≥ 4.5 · 이름 · @아이디 · 역할 부제', avOk && avIc && chipOk && headCr && whoOk,
                'av ${_hex(av)}/${_hex(avI)} icon $avIcon chip ${_hex(roleBg)}/$roleBd/${_hex(roleTx)} cr ${_f2(roleCr)} who $whoOk');
          }
          scan('head');
          _out('D514 $tok shot 1head ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_1head', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': c.id,
            'state': 'user-detail-head',
          });
          shots++;

          // ③ 통계 칸 다섯 — 칸 실제 면 · 값/라벨 글자색 · 대비 · 값 원문 · 말줄임 0. 칸마다 라벨까지 내려 닿게 한 뒤 잰다(DU500 경로).
          final statSeen = <({int i, bool neutral, bool ok, bool val})>[];
          for (var i = 0; i < 5; i++) {
            final labF = srt((p) => p == _statLabels[i]);
            await t.scrollUntilVisible(labF, 120, scrollable: sheetScroll, maxScrolls: 40);
            await t.pump(const Duration(milliseconds: 50));
            final nLab = labF.evaluate().length;
            need('통계 라벨 ${_statLabels[i]} 1', nLab == 1, '개수 $nLab');
            final cellF = find.ancestor(of: labF, matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration)).first;
            final cellDeco = t.widget<Container>(cellF).decoration as BoxDecoration?;
            final face = cellDeco?.color;
            final texts = find.descendant(of: cellF, matching: find.byType(RichText), skipOffstage: false).evaluate().toList();
            need('통계 칸 ${_statLabels[i]} 글자 2', texts.length == 2, '개수 ${texts.length}');
            final valEl = texts.first;
            final labEl = texts.last;
            final valTxt = _plainOf(valEl.widget);
            final vtx = (valEl.widget as RichText).text.style?.color;
            final ltx = (labEl.widget as RichText).text.style?.color;
            final cellBg = _bgOf(valEl) ?? AppColors.surface;
            final vcr = vtx == null ? 0.0 : _cr(vtx.a < 1 ? Color.alphaBlend(vtx, cellBg) : vtx, cellBg);
            final lcr = ltx == null ? 0.0 : _cr(ltx.a < 1 ? Color.alphaBlend(ltx, cellBg) : ltx, cellBg);
            final ell = (valEl.renderObject as RenderParagraph).didExceedMaxLines || (labEl.renderObject as RenderParagraph).didExceedMaxLines;
            final neutral = _same(face, AppColors.background) && _same(vtx, c.muted[i] ? AppColors.textSecondary : AppColors.textPrimary) &&
                _same(ltx, AppColors.textSecondary);
            final okS = vcr >= 4.5 && lcr >= 4.5 && !ell;
            final valOk = valTxt == c.stats[i];
            statSeen.add((i: i, neutral: neutral, ok: okS, val: valOk));
            _out('D514 $tok att stat idx=$i face=${_hex(face)} vtx=${_hex(vtx)} ltx=${_hex(ltx)} vcr=${_f2(vcr)} lcr=${_f2(lcr)} neutral=$neutral ok=$okS val=$valOk');
            scan('stat$i');
          }
          _out('D514 $tok shot 2stats ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_2stats', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': c.id,
            'state': 'user-detail-stats',
          });
          shots++;
          if (!_before) {
            for (final x in statSeen) {
              chk('strict 통계 칸 ${x.i} — 중립 면 · 값 textPrimary(낮춘 값 textSecondary) · 라벨 textSecondary · 대비 ≥ 4.5 · 말줄임 0 · 값 원문',
                  x.neutral && x.ok && x.val, '값 $x');
            }
          }

          // ④ 계정 상태 행 — 행 면 · 아이콘(중립) · 상태 이름 칩 짝 · 설명(근거/기간) · 대비.
          final rowSeen = <({String k, bool neutral, bool keep, bool ok, bool desc})>[];
          for (final k in c.rows) {
            final want = _rowWant(k);
            final chipLabF = srt((p) => p == want.label);
            await t.scrollUntilVisible(chipLabF, 120, scrollable: sheetScroll, maxScrolls: 40);
            await t.pump(const Duration(milliseconds: 50));
            final nChipLab = chipLabF.evaluate().length;
            need('상태 이름 ${want.label} 1', nChipLab == 1, '개수 $nChipLab');
            final chipEl = chipLabF.evaluate().first;
            final ink = (chipEl.widget as RichText).text.style?.color;
            final chipDeco = t.widget<Container>(find.ancestor(of: chipLabF, matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration)).first)
                .decoration as BoxDecoration?;
            final chip = chipDeco?.color;
            final rowF = find.ancestor(
                of: chipLabF,
                matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null)).first;
            final rowFace = (t.widget<Container>(rowF).decoration as BoxDecoration?)?.color;
            final iconC = t.widget<RichText>(find.descendant(of: find.descendant(of: rowF, matching: find.byType(Icon), skipOffstage: false).first,
                    matching: find.byType(RichText), skipOffstage: false).first)
                .text
                .style
                ?.color;
            final others = find.descendant(of: rowF, matching: find.byType(RichText), skipOffstage: false)
                .evaluate()
                .where((e) => !_hidden(e) && _plainOf(e.widget) != want.label)
                .toList();
            final descEl = others.isEmpty ? null : others.first;
            final descTxt = descEl == null ? '' : _plainOf(descEl.widget);
            final dtx = descEl == null ? null : (descEl.widget as RichText).text.style?.color;
            final dbg = descEl == null ? AppColors.surface : (_bgOf(descEl) ?? AppColors.surface);
            final chipBgC = _bgOf(chipEl) ?? AppColors.surface;
            final cr = ink == null ? 0.0 : _cr(ink, chipBgC);
            final dcr = dtx == null ? 0.0 : _cr(dtx, dbg);
            final neutral = _same(rowFace, AppColors.background) && _same(iconC, AppColors.textSecondary);
            final keep = _same(chip, want.bg) && _same(ink, want.ink);
            final okR = cr >= 4.5 && dcr >= 4.5;
            final descOk = _descOk(k, descTxt);
            rowSeen.add((k: k, neutral: neutral, keep: keep, ok: okR, desc: descOk));
            _out('D514 $tok att state k=$k chip=${_hex(chip)} ink=${_hex(ink)} face=${_hex(rowFace)} icon=${_hex(iconC)} cr=${_f2(cr)} dcr=${_f2(dcr)} '
                'neutral=$neutral keep=$keep ok=$okR desc=$descOk');
            scan('state-$k');
          }
          if (!_before) {
            for (final x in rowSeen) {
              chk('strict 상태 ${x.k} — 중립 행 · 중립 아이콘 · 상태 이름만 칩 짝 · 대비 ≥ 4.5 · 근거/기간 문구', x.neutral && x.keep && x.ok && x.desc, '값 $x');
            }
          }

          // ⑤ 관리 행동 진입 — 실제 Material 면 · 선 · 글자색 · 대비 · 받는 자리 ≥ 48 · 보이는 칸 중심 hit · 이름 순서.
          final actSeen = <({int i, bool neutral, bool ok, bool rx, bool hit})>[];
          var entryPt = Offset.zero;
          for (var i = 0; i < c.acts.length; i++) {
            final aLabF = srt((p) => p == c.acts[i]);
            await t.scrollUntilVisible(aLabF, 120, scrollable: sheetScroll, maxScrolls: 40);
            await t.pump(const Duration(milliseconds: 50));
            final nALab = aLabF.evaluate().length;
            need('행동 ${c.acts[i]} 1', nALab == 1, '개수 $nALab');
            final btnF = find.ancestor(of: aLabF, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
            final mat = t.widget<Material>(find.descendant(of: btnF, matching: find.byType(Material), skipOffstage: false).first);
            final fill = mat.color;
            final mShape = mat.shape;
            final mSide = mShape is OutlinedBorder ? mShape.side : BorderSide.none;
            final sideTx = mSide.style == BorderStyle.none ? 'none' : _hex(mSide.color);
            final aEl = aLabF.evaluate().first;
            final fg = (aEl.widget as RichText).text.style?.color;
            final aBg = _bgOf(aEl) ?? AppColors.surface;
            final aCr = fg == null ? 0.0 : _cr(fg, aBg);
            final bR = t.getRect(btnF);
            final vis = sheetVis();
            final btnRo = t.renderObject(btnF);
            final hitA = bR.overlaps(vis) && t.hitTestOnBinding(bR.intersect(vis).center).path.any((e) => e.target == btnRo);
            final rxA = bR.height >= 48 - 0.01 && bR.width >= 48 - 0.01;
            if (c.acts[i] == '블랙리스트 등록') entryPt = bR.intersect(vis).center;
            final neutral = (fill == null || fill.a == 0) && _same(fg, AppColors.textPrimary) && sideTx == _hex(AppColors.border);
            final okA = aCr >= 4.5;
            actSeen.add((i: i, neutral: neutral, ok: okA, rx: rxA, hit: hitA));
            _out('D514 $tok att act idx=$i fill=${_hex(fill)} side=$sideTx fg=${_hex(fg)} cr=${_f2(aCr)} rh=${_f1(bR.height)} neutral=$neutral ok=$okA rx=$rxA hit=$hitA');
            scan('act$i');
          }
          if (!_before) {
            for (final x in actSeen) {
              chk('strict 행동 진입 ${x.i} — 중립 외곽선(투명 면 · border 선 · textPrimary) · 대비 ≥ 4.5 · 받는 자리 ≥ 48 · 중심 hit', x.neutral && x.ok && x.rx && x.hit,
                  '값 $x');
            }
          }

          // ⑥ 끝 도달 — 실제 끌기로 시트 끝까지 · 마지막 요소(마지막 행동 또는 '관리 액션' 제목)가 보이는 칸 안 · 중심 hit.
          await t.drag(sheetScroll, const Offset(0, -3000));
          for (var i = 0; i < 8; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          final endPos = t.state<ScrollableState>(sheetScroll).position;
          final endPx = endPos.pixels;
          final endMax = endPos.maxScrollExtent;
          final endAt = endPx >= endMax - 0.5;
          final lastF = srt((p) => p == (c.acts.isEmpty ? '관리 액션' : c.acts.last));
          final nLast = lastF.evaluate().length;
          need('끝 요소 1', nLast == 1, '개수 $nLast');
          final lastR = t.getRect(lastF);
          final endVis = sheetVis();
          final lastRo = t.renderObject(lastF);
          final endHit = lastR.overlaps(endVis) && t.hitTestOnBinding(lastR.intersect(endVis).center).path.any((e) => e.target == lastRo);
          final endIn = _inside(lastR, endVis);
          if (c.acts.contains('블랙리스트 등록')) {
            final eF = find.ancestor(of: srt((p) => p == '블랙리스트 등록'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
            entryPt = t.getRect(eF).intersect(endVis).center;
          }
          _out('D514 $tok att end px=${_f1(endPx)} max=${_f1(endMax)} at=$endAt in=$endIn hit=$endHit');
          if (!_before) {
            chk('strict 끝 도달 — 끝 · 마지막 요소 보이는 칸 안 · 중심 hit', endAt && endIn && endHit, 'px ${_f1(endPx)} max ${_f1(endMax)} in $endIn hit $endHit');
          }
          scan('end');
          _out('D514 $tok shot 3end ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_3end', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': c.id,
            'state': 'user-detail-end',
          });
          shots++;

          // ⑦ PEND — '블랙리스트 등록' 진입 실제 탭 → 사유 창(최종 '등록' 실제 면 · 글자 · 대비 · 창 글자 대비 기록) → '취소' 실제 탭 → 닫힘(쓰기 0).
          //   그 밖 — 바깥 막 실제 탭으로 시트를 닫는다(DU513 경로).
          if (c.id == 'PEND') {
            await t.tapAt(entryPt);
            await t.pump();
            for (var i = 0; i < 6; i++) {
              await t.pump(const Duration(milliseconds: 100));
            }
            final dlgF = find.byType(Dialog);
            final nDlg = dlgF.evaluate().length;
            need('사유 창 1', nDlg == 1, '개수 $nDlg');
            final titleOk = find.descendant(of: dlgF, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == '블랙리스트 등록'), skipOffstage: false)
                    .evaluate()
                    .length ==
                1;
            final regF = find.descendant(of: dlgF, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == '등록'), skipOffstage: false);
            final nReg = regF.evaluate().length;
            need('최종 등록 버튼 1', nReg == 1, '개수 $nReg');
            final regDeco = t.widget<DecoratedBox>(find.ancestor(of: regF, matching: find.byType(DecoratedBox)).first).decoration;
            final regFill = regDeco is BoxDecoration ? regDeco.color : null;
            final regFg = (regF.evaluate().first.widget as RichText).text.style?.color;
            final regCr = regFg == null || regFill == null ? 0.0 : _cr(regFg, regFill);
            // [r1 · 판정 D3 · §3-1] 공개 안내 — 존재 · 원문 · 실제 errorDark · 실바탕 대비 ≥ 4.5 를 strict 로 본다.
            final noteF = find.descendant(of: dlgF, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == _note), skipOffstage: false);
            final nNote = noteF.evaluate().length;
            final noteEl = nNote == 1 ? noteF.evaluate().first : null;
            final noteTx = noteEl == null ? null : (noteEl.widget as RichText).text.style?.color;
            final noteBg = noteEl == null ? null : _bgOf(noteEl);
            final noteCr = noteTx == null || noteBg == null ? 0.0 : _cr(noteTx, noteBg);
            final noteOk = nNote == 1 && _same(noteTx, AppColors.errorDark) && noteCr >= 4.5;
            // 창 안 보이는 모든 글자 — 색 · 놓인 면을 모르면 '미확인'(unk)으로 센다(흰 면 가정 · 건너뛰기 0).
            //   따로 재는 것 둘은 이 집계에서 빼고 따로 출력한다: 최종 '등록' 글자(면이 DecoratedBox 라 위 regCr) · 공용 입력칸 힌트(hcr · 잔여).
            final regEl = regF.evaluate().first;
            var dN = 0;
            var dBad = 0;
            var dUnk = 0;
            var dMin = 99.0;
            var hintCr = 0.0;
            var nHint = 0;
            Color? hintTx;
            Color? hintBg;
            for (final e in find.descendant(of: dlgF, matching: find.byType(RichText), skipOffstage: false).evaluate()) {
              if (_hidden(e) || _plainOf(e.widget).trim().isEmpty || identical(e, regEl)) continue;
              final fgD = (e.widget as RichText).text.style?.color;
              final bgD = _bgOf(e);
              if (_isHint(e)) {
                nHint++;
                hintTx = fgD;
                hintBg = bgD;
                hintCr = fgD == null || bgD == null ? 0.0 : _cr(fgD.a < 1 ? Color.alphaBlend(fgD, bgD) : fgD, bgD);
                continue;
              }
              if (fgD == null || bgD == null) {
                dUnk++;
                continue;
              }
              final rD = _cr(fgD.a < 1 ? Color.alphaBlend(fgD, bgD) : fgD, bgD);
              dN++;
              if (rD < dMin) dMin = rD;
              if (rD < 4.5) dBad++;
            }
            _out('D514 $tok shot 4dialog ovf=${overflows.length}');
            await vqCapture(t, key, '${tok}_4dialog', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': c.id,
              'state': 'reason-dialog-final-button',
            });
            shots++;
            final cancelF = find.descendant(of: dlgF, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == '취소'), skipOffstage: false);
            final nCancel = cancelF.evaluate().length;
            need('취소 1', nCancel == 1, '개수 $nCancel');
            await t.tap(cancelF);
            await t.pump();
            for (var i = 0; i < 6; i++) {
              await t.pump(const Duration(milliseconds: 100));
            }
            final dlgAfter = find.byType(Dialog).evaluate().length;
            final finalOk = _same(regFill, AppColors.errorDark);
            final regOk = regCr >= 4.5;
            final dClosed = dlgAfter == 0;
            // [r2 · H1] 힌트 관측 성공 — 정확 1개 · 실제 글자 grey400 · 실제 바탕 grey50(색 · 바탕 null 은 실패 · 대비 값은 요구하지 않는다).
            final hintOk = nHint == 1 && _same(hintTx, AppColors.grey400) && _same(hintBg, AppColors.grey50);
            _out('D514 $tok att dialog fill=${_hex(regFill)} fg=${_hex(regFg)} cr=${_f2(regCr)} ntx=${_hex(noteTx)} ncr=${_f2(noteCr)} dn=$dN '
                'dmin=${_f2(dN == 0 ? 0.0 : dMin)} dbad=$dBad dunk=$dUnk hints=$nHint htx=${_hex(hintTx)} hbg=${_hex(hintBg)} hcr=${_f2(hintCr)} title=$titleOk final=$finalOk ok=$regOk note=$noteOk hint=$hintOk closed=$dClosed');
            if (!_before) {
              chk('strict 사유 창 — 제목 · 최종 등록 = errorDark 채움 · 흰 글자 대비 ≥ 4.5 · 취소 실제 탭 뒤 닫힘', titleOk && finalOk && regOk && dClosed,
                  'fill ${_hex(regFill)} fg ${_hex(regFg)} cr ${_f2(regCr)} 창 $dlgAfter');
              chk('strict 사유 창 공개 안내 — 1개 · 원문 · errorDark · 실바탕 대비 ≥ 4.5', noteOk, '개수 $nNote 색 ${_hex(noteTx)} 면 ${_hex(noteBg)} cr ${_f2(noteCr)}');
              chk('strict 사유 창 — 힌트 제외 관측 텍스트 요소 양수 · 미달 0 · 미확인 0(최종 등록 버튼은 별도 대비)', dN > 0 && dBad == 0 && dUnk == 0, 'n $dN bad $dBad unk $dUnk');
              chk('strict 사유 창 힌트(NCB-52D-HINT-1) — 원문 정확 1개 · 실제 grey400/grey50 관측 성공(대비 면제)', hintOk,
                  '개수 $nHint 색 ${_hex(hintTx)} 면 ${_hex(hintBg)} cr ${_f2(hintCr)}');
            }
          } else {
            await t.tapAt(Offset(v.w / 2, 8));
            await t.pump();
            for (var i = 0; i < 6; i++) {
              await t.pump(const Duration(milliseconds: 100));
            }
          }
          final sheetsAfter = find.byType(BottomSheet).evaluate().length;
          final dialogsAfter = find.byType(Dialog).evaluate().length;
          final listBack = find.descendant(
                  of: appF, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == c.name), skipOffstage: false)
              .evaluate()
              .length;
          final closed = sheetsAfter == 0 && dialogsAfter == 0;
          final listOk = listBack == 1;
          _out('D514 $tok att close closed=$closed list=$listOk');
          if (!_before) {
            chk('strict 닫힘 — 시트 0 · 창 0 · 목록 그 행 남음', closed && listOk, 'sheet $sheetsAfter dialog $dialogsAfter list $listBack');
          }

          // ⑧ 시트 글자 대비 합계.
          final textMin = tN == 0 ? 0.0 : tMin;
          _out('D514 $tok att text n=$tN min=${_f2(textMin)} bad=$tBad unk=$tUnk worst=$tWorst');
          if (!_before) {
            chk('strict 시트 보이는 글자 실바탕 대비 ≥ 4.5(머리 · 통계 · 상태 · 행동 · 끝)', tN > 0 && tBad == 0 && tUnk == 0, '미달 ${tFails.take(8).join(' | ')}');
          }

          // ⑨ [r1 · 판정 §3-5] 위젯을 먼저 해제하고 남은 일을 흘린 **뒤** 읽기 경계를 최종 집계한다(감시 대역은 tearDown 까지 유지).
          //   주입 reader 정확 1 · CF 호출 0(취소 경로 포함 쓰기 0) · 예상 밖 채널 0 · HTTP 0.
          await t.pumpWidget(const SizedBox.shrink());
          for (var i = 0; i < 3; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          final nCalls = nReads;
          final nCf = cf.calls.length;
          final cfNames = cf.calls.join(',');
          final nUnexp = wire.unexpected.length;
          final unexpNames = wire.unexpected.join(' | ');
          final nHttp = net.tries.length;
          final nFrame = wire.framework;
          _out('D514 $tok att reader calls=$nCalls cf=$nCf unexpected=$nUnexp http=$nHttp fw=$nFrame');
          chk('읽기 경계(위젯 해제 뒤) — 주입 reader 정확 1 · Cloud Functions 호출 0', nCalls == 1 && nCf == 0, 'calls $nCalls cf [$cfNames]');
          if (!_before) {
            chk('strict 예상 밖 플랫폼 채널 0 · HTTP 0(위젯 해제 뒤)', nUnexp == 0 && nHttp == 0, '예상 밖 [$unexpNames] http $nHttp');
          }

          // 측정 끝 — 넘침 수집기를 되돌린 뒤 모은 단언을 던진다(v34 · 이 뒤 화면 읽기 0).
          final nOvf = overflows.length;
          final ovfRaw = overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '');
          final ovfText = overflows.join(' | ');
          final nFwErr = fwErrors.length;
          final fwText = fwErrors.join(' | ');
          if (!_before) {
            chk('strict 넘침 0(시트 · 사유 창 포함)', nOvf == 0, ovfText);
          }
          chk('미처리 framework 예외 0', nFwErr == 0, fwText);
          FlutterError.onError = prev;
          for (final c in checks) {
            expect(c.$2, isTrue, reason: '$tok ${c.$1} ${c.$3}');
          }
          final exc = t.takeException();
          _out('D514 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null} ovfRaw=$ovfRaw');
          expect(exc, isNull, reason: '$tok 끝 예외 $exc');
        } catch (e) {
          _anyFail = true;
          rethrow;
        } finally {
          FlutterError.onError = prev;
          debugDisableShadows = ds0;
        }
      }, skip: !_optIn);
    }
  }
}
