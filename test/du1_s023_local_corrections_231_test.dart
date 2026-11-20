// ignore_for_file: depend_on_referenced_packages
// [DU231 S023 교정 baseline/after] 공고 탭 F1·F2·F3·F4·F7·F9 — 같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다.
//   DU231_RUN=1 이고 DU231_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip). production 편집 0.
//   phase 하나 = testWidgets 하나: 장면 14개를 차례로 돌리고, 필수 계측 누락·locale·reader 차이·쓰기·허용 밖 호출·
//   예외/overflow·단언 실패가 나오면 그 자리에서 멈춘다(다음 장면·추가 캡처·재실행 없음).
//   조건: W360×780 배율1 / B320×640 배율2, DPR1. ko_KR — 앱과 같은 delegate·supportedLocales, 기기 locale 로 해석.
//   표시 문자(U+2060·U+200B·NBSP)는 TextLayout.plain 으로 정규화해 찾는다(표시 원문·semantics 는 그대로).
//   baseline 의 알려진 결함값(작은 receiver·배지 가림·말줄임·저대비·고정 머리)은 기록만 하고, after 에서만 성공조건을 단언한다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/controllers/workforce_controller.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/jobs_root_screen.dart';
import 'package:ALfit/screens/business_admin/workforce_management/workforce_list_view.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/services/posting_quota_summary.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/admin/cards/admin_to_group_card.dart';
import 'package:ALfit/widgets/common/app_empty_state.dart';
import 'package:ALfit/widgets/inputs/filter_dialog.dart';

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

const kBiz = 'biz-local-d231';
const kOwner = 'owner-local-d231';
const kSub = 'sub-local-d231';
const kTo = 'to-local-d231';
const kWd = 'wd-local-d231';
const kTitle = '송파 물류센터 주말 오전 상하차·분류 보조 단기 인력 모집 안전화 지참 필수';
// F3 — 긴 업무명 뒤의 남은 기간이 보이는지 본다(229 의 같은 문구).
const kWorkType = '상하차·분류·검수 보조 및 출고 정리 단기 야간';

class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: kOwner, username: 'owner', name: 'QA 사장', email: 'o@test.local',
      role: UserRole.BUSINESS_ADMIN, businessId: kBiz, managedBusinessIds: const [kBiz], createdAt: DateTime(2026, 1, 1));
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
}

/// 확인된 거부 SubAdmin — checkCurrentBusiness·checkForBusiness·subAdminBusinessesFor 가 같은 판정(229 대역과 같다).
class _SubDenied extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: kSub, username: 'sub', name: 'QA 서브', email: 's@test.local',
      role: UserRole.USER, subAdminBusinessIds: const [kBiz], createdAt: DateTime(2026, 1, 1));
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSubAdmin => true;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
  @override
  String? get effectiveBusinessId => kBiz;
  @override
  Map<String, String> get subAdminBusinessNames => const {kBiz: 'QA 물류센터'};
  @override
  bool can(bool Function(MemberPermissions p) check) => false;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => false;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.denied;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.denied;
  @override
  ({List<String> allowed, List<String> unresolved}) subAdminBusinessesFor(bool Function(MemberPermissions p) check) =>
      (allowed: const <String>[], unresolved: const <String>[]);
}

Object? _wire(Object? v) {
  if (v is Timestamp) return {'_seconds': v.seconds, '_nanoseconds': v.nanoseconds};
  if (v is DateTime) {
    final ms = v.millisecondsSinceEpoch;
    return {'_seconds': ms ~/ 1000, '_nanoseconds': (ms % 1000) * 1000000};
  }
  if (v is Map) return v.map((k, x) => MapEntry(k, _wire(x)));
  if (v is List) return v.map(_wire).toList();
  return v;
}

String _kst(DateTime d) {
  final k = d.toUtc().add(const Duration(hours: 9));
  String p(int x) => x.toString().padLeft(2, '0');
  return '${k.year}-${p(k.month)}-${p(k.day)} ${p(k.hour)}:${p(k.minute)} KST';
}

String _key(DateTime d) {
  final k = d.toUtc().add(const Duration(hours: 9));
  return '${k.year}-${k.month.toString().padLeft(2, '0')}-${k.day.toString().padLeft(2, '0')}';
}

int _lines(RenderParagraph p) {
  final len = p.text.toPlainText().length;
  final boxes = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len));
  return boxes.map((b) => b.top.round()).toSet().length;
}

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a);
  final y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}'
    '${c.a < 1 ? '@${c.a.toStringAsFixed(2)}' : ''}';

Color? _spanColor(InlineSpan s) {
  Color? found = s.style?.color;
  if (s is TextSpan) {
    for (final c in s.children ?? const <InlineSpan>[]) {
      final cc = _spanColor(c);
      if (cc != null) return cc;
    }
  }
  return found;
}

void _out(String l) {
  // ignore: avoid_print
  print(l);
}

void main() {
  final phase = Platform.environment['DU231_PHASE'] ?? '';
  final run = Platform.environment['DU231_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);
  final wj = String.fromCharCode(0x2060);
  final zw = String.fromCharCode(0x200B);
  final nbsp = String.fromCharCode(0xA0);

  final calls = <String, int>{};
  const base = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  void inc(String k) => calls[k] = (calls[k] ?? 0) + 1;
  final meta = PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false);

  // 실행 시계 기준 fixture(시계 미주입) — 근무 첫날 = 오늘(KST)+7 의 KST 자정, 지원 마감 = 그날 08:00 KST.
  final now = DateTime.now();
  final kstNow = now.toUtc().add(const Duration(hours: 9));
  final workDate = DateTime.utc(kstNow.year, kstNow.month, kstNow.day)
      .add(const Duration(days: 7))
      .subtract(const Duration(hours: 9))
      .toLocal();
  final created = now.subtract(const Duration(days: 1));

  // 'single'(단기 하루) / 'multi'(단기 사흘) / 'contract'(계약형 1개월)
  var variant = 'single';
  List<DateTime> dates() => variant == 'multi'
      ? [workDate, workDate.add(const Duration(days: 1)), workDate.add(const Duration(days: 2))]
      : [workDate];
  WorkDetailData wd(DateTime day) => WorkDetailData(
        wdId: kWd, workType: kWorkType, workTypeId: 'wt-d231', startTime: '10:00', endTime: '13:00',
        requiredCount: 3, wage: 12000, wageType: 'hourly', applicationDeadline: day.add(const Duration(hours: 8)),
      );
  TOModel master() {
    if (variant == 'contract') {
      return TOModel(
        id: kTo, businessId: kBiz, businessName: 'QA 물류센터', type: TOType.contract, title: kTitle, creatorUID: kOwner,
        status: TOStatus.active, workDetails: [wd(workDate)],
        totalRequired: 3, totalConfirmed: 0, totalPending: 0,
        isPublished: true, publishMode: 'immediate', rangeStart: workDate, rangeEnd: workDate.add(const Duration(days: 30)),
        contractPeriodType: '1month', workDays: const ['월', '화', '수', '목', '금'],
        createdAt: created, statusUpdatedAt: created,
      );
    }
    final ds = dates();
    return TOModel(
      id: kTo, businessId: kBiz, businessName: 'QA 물류센터', type: TOType.flex, title: kTitle, creatorUID: kOwner,
      status: TOStatus.active, workDetails: [wd(ds.first)], totalSlots: ds.length, slotDateKeys: ds.map(_key).toList(),
      totalRequired: 3 * ds.length, totalConfirmed: 0, totalPending: 0,
      isPublished: true, publishMode: 'immediate', rangeStart: ds.first, rangeEnd: ds.last,
      deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2,
      createdAt: created, statusUpdatedAt: created,
    );
  }

  SlotModel slot(int i, DateTime day) => SlotModel(
        id: 'slot-local-d231-$i', toId: kTo, date: day, workDetails: [wd(day)],
        workDetailCounts: const {kWd: SlotWorkTypeCount(confirmedCount: 0, pendingCount: 0)},
        status: SlotStatus.open, confirmedCount: 0, pendingCount: 0,
        applicationDeadline: day.add(const Duration(hours: 8)), visibleFrom: created, createdAt: created,
      );

  var templatesEmpty = false;
  void stubFirestore() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = FirebaseFirestoreHostApi.codec;
    m.setMockMessageHandler('$base.documentReferenceGet', (msg) async {
      final args = codec.decodeMessage(msg) as List;
      final path = (args[1] as DocumentReferenceRequest).path;
      Map<String?, Object?>? data;
      if (path == 'businesses/$kBiz') {
        data = {
          'name': 'QA 물류센터', 'businessNumber': '000-00-00000', 'category': '물류', 'subCategory': '상하차', 'address': '서울시 QA구 1',
          'ownerId': kOwner, 'adminIds': [kOwner], 'isApproved': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
          'businessLicenseImageUrl': 'https://example.invalid/qa-license.png',
        };
      } else if (path == 'users/$kOwner') {
        data = {'role': 'BUSINESS_ADMIN', 'name': 'QA 사장', 'sealBase64': 'LOCAL-QA-SEAL'};
      } else {
        inc('get.blocked $path');
        return codec.encodeMessage(<Object?>['du231-blocked', 'get 차단: $path', null]);
      }
      inc('get $path');
      return codec.encodeMessage(<Object?>[PigeonDocumentSnapshot(path: path, data: data, metadata: meta)]);
    });
    m.setMockMessageHandler('$base.queryGet', (msg) async {
      final bytes = msg!.buffer.asUint8List(msg.offsetInBytes, msg.lengthInBytes);
      final raw = String.fromCharCodes(bytes);
      final String key;
      final List<PigeonDocumentSnapshot> docs;
      if (raw.contains('businesses/$kBiz/workTypes')) {
        key = 'query businesses/$kBiz/workTypes';
        docs = [
          PigeonDocumentSnapshot(path: 'businesses/$kBiz/workTypes/wt-d231', data: <String?, Object?>{
            'businessId': kBiz, 'name': kWorkType, 'icon': 'box', 'color': '#3859E8', 'backgroundColor': '#EEF2FF',
            'displayOrder': 0, 'isActive': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
          }, metadata: meta),
        ];
      } else if (raw.contains('businesses/$kBiz/contract_templates')) {
        key = 'query businesses/$kBiz/contract_templates';
        docs = templatesEmpty
            ? const []
            : [
                PigeonDocumentSnapshot(path: 'businesses/$kBiz/contract_templates/tpl-d231', data: <String?, Object?>{
                  'businessId': kBiz, 'name': '단기 근무 기본', 'templateType': 'daily', 'articles': const [],
                  'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
                }, metadata: meta),
              ];
      } else if (raw.contains('tos/$kTo/slots')) {
        key = 'query tos/$kTo/slots';
        final ds = dates();
        docs = [
          for (var i = 0; i < ds.length; i++)
            PigeonDocumentSnapshot(
                path: 'tos/$kTo/slots/slot-local-d231-$i', data: Map<String?, Object?>.from(slot(i, ds[i]).toMap()), metadata: meta),
        ];
      } else {
        inc('query.blocked');
        _out('D231-BLOCKED-QUERY ${raw.replaceAll(RegExp('[^ -~]'), '.')}');
        return codec.encodeMessage(<Object?>['du231-blocked', 'query 차단', null]);
      }
      inc(key);
      return codec.encodeMessage(<Object?>[PigeonQuerySnapshot(documents: docs, documentChanges: const [], metadata: meta)]);
    });
    for (final op in const ['documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit',
      'transactionCreate', 'transactionStoreResult', 'transactionGet', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$base.$op', (msg) async {
        inc('write.blocked $op');
        return codec.encodeMessage(<Object?>['du231-blocked', '$op 차단', null]);
      });
    }
  }

  // 목록 callable 응답 계획 — 호출마다 하나씩: 'one'(카드1) / 'empty'(성공 0) / 'error'(일반 네트워크 실패). 비면 'error'.
  final listPlan = <String>[];
  final fnLog = <String>[];
  void stubFunctions() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(fnChannel, (msg) async {
      const c = StandardMessageCodec();
      final args = (c.decodeMessage(msg) as List).first as Map;
      final name = args['functionName'];
      final region = args['region'];
      fnLog.add('$name@$region ${args['parameters']}');
      const allowed = {'callableGetPostingQuotaSummary', 'callableGetAdminTOs'};
      if (region != 'asia-northeast3' || !allowed.contains(name)) {
        inc('functions.blocked $name@$region');
        return c.encodeMessage(<Object?>['not-found', 'du231-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      inc('functions $name');
      if (name == 'callableGetPostingQuotaSummary') {
        return c.encodeMessage(<Object?>[
          <String, Object?>{
            'scopes': [
              {'scopeToken': 'owner:$kOwner', 'businessIds': [kBiz], 'used': 1, 'limit': 10, 'remaining': 9},
            ],
            'denied': const [],
            'failed': const [],
          }
        ]);
      }
      final plan = listPlan.isEmpty ? 'error' : listPlan.removeAt(0);
      if (plan == 'error') {
        return c.encodeMessage(<Object?>['unavailable', 'du231 local network failure',
          <String, Object?>{'code': 'unavailable', 'message': 'du231 local network failure'}]);
      }
      final Object? item;
      if (plan == 'empty') {
        item = null;
      } else {
        final m = Map<String, Object?>.from(_wire(master().toMap()) as Map)..['id'] = kTo;
        if (variant != 'contract') m['dates'] = dates().map(_key).toList();
        item = m;
      }
      return c.encodeMessage(<Object?>[
        <String, Object?>{'items': item == null ? const <Object?>[] : <Object?>[item]}
      ]);
    });
  }

  // 사전 고정 읽기표(229 출발점 + 새 두 변형). 캡처 직전(pre)과 장면 끝(post)에 정확히 같아야 한다.
  const ready = {
    'get businesses/$kBiz': 1, 'get users/$kOwner': 1,
    'query businesses/$kBiz/workTypes': 1, 'query businesses/$kBiz/contract_templates': 1,
    'functions callableGetPostingQuotaSummary': 1, 'functions callableGetAdminTOs': 1,
  };
  final predictedPre = <String, Map<String, int>>{
    'denied': const {},
    'setup': {...ready, 'get businesses/$kBiz': 2},
    'emptyRoot': ready,
    'filter0': {...ready, 'query tos/$kTo/slots': 1},
    'listError': ready,
    'stale': {...ready, 'query tos/$kTo/slots': 1, 'functions callableGetAdminTOs': 2, 'functions callableGetPostingQuotaSummary': 2},
    'multiDay': {...ready, 'query tos/$kTo/slots': 1},
    'contract': ready,
  };
  // after 의 B320 목록오류 '다시 시도' 1회 = 같은 실패 재조회(목록 +1·한도 +1, 성공 fixture 로 바꾸지 않는다). 그 밖 추가 0.
  Map<String, int> predictedPost(String state, String cond) => after && cond == 'B320' && state == 'listError'
      ? {...ready, 'functions callableGetAdminTOs': 2, 'functions callableGetPostingQuotaSummary': 2}
      : predictedPre[state]!;

  const stateTitle = {
    'denied': '접근 권한이 없습니다',
    'setup': '아직 공고를 등록할 준비가 끝나지 않았어요',
    'emptyRoot': '등록된 공고가 없습니다',
    'filter0': '조건에 맞는 공고가 없습니다',
    'listError': '공고 목록을 불러오지 못했습니다',
    'stale': '최신 정보를 불러오지 못했습니다. 다시 시도해 주세요.',
  };
  const stateSubtitle = {
    'denied': '공고 관리 권한이 있는 관리자에게 문의하세요.',
    'emptyRoot': '상단 + 버튼에서 새 공고를 등록할 수 있습니다',
    'filter0': '필터를 초기화하거나 조건을 변경해 보세요',
    'listError': '네트워크 상태를 확인한 뒤 다시 시도해주세요',
  };
  String expectWork(String state) => switch (state) {
        'multiDay' => '$kWorkType · 남은 3일',
        'contract' => '$kWorkType · 계약 1개월',
        _ => '$kWorkType · 남은 1일',
      };
  String expectRemaining(String state) => switch (state) {
        'multiDay' => '남은 3일',
        'contract' => '계약 1개월',
        _ => '남은 1일',
      };

  testWidgets('D231 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);

    // 실사용량 — phase 한도(셀 전체 한도의 절반, 이월 없음).
    var nPump = 0, nMount = 0, nTap = 0, nDrag = 0, nPng = 0;
    const maxFrames = 1200, maxTap = 20, maxDrag = 12, maxPng = 16;
    final tapLog = <String>[];
    var curScene = '(시작)';
    Map<String, int> counts() => {'pump': nPump, 'pumpWidget': nMount, 'tap': nTap, 'drag': nDrag, 'png': nPng};
    Never stop(String why) {
      _out('D231-STOP ${jsonEncode({'phase': phase, 'scene': curScene, 'why': why, 'errors': errors, 'counts': counts(), 'calls': calls})}');
      fail('$curScene: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    void budget() => need(nPump + nMount <= maxFrames && nTap <= maxTap && nDrag <= maxDrag && nPng <= maxPng, '사용량 한도 초과 ${counts()}');
    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        budget();
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> tapAt(Offset p, String what) async {
      nTap++;
      budget();
      tapLog.add('$curScene $what');
      await t.tapAt(p);
    }

    Future<void> dragFrom(Offset from, Offset by) async {
      nDrag++;
      budget();
      await t.dragFrom(from, by);
    }

    final key = GlobalKey();
    Future<void> shot(String id, Map<String, Object?> cond) async {
      nPng++;
      budget();
      await vqCapture(t, key, id, conditions: cond);
    }

    String plainOf(InlineSpan s) => TextLayout.plain(s.toPlainText());
    Finder rich(bool Function(String p) f, {Finder? within}) {
      final m = find.byWidgetPredicate((w) => w is RichText && f(plainOf(w.text)));
      return within == null ? m : find.descendant(of: within, matching: m);
    }

    // 빈 후보에 .first 를 쓰면 예외다 — 첫 원소를 직접 고른다(없으면 null).
    Finder? firstOf(Finder f) {
      final els = f.evaluate().toList();
      if (els.isEmpty) return null;
      final e = els.first;
      return find.byElementPredicate((x) => identical(x, e));
    }

    double r1(double v) => double.parse(v.toStringAsFixed(1));
    List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom].map(r1).toList();
    bool inside(Rect r, Rect box) =>
        r.left >= box.left - 0.5 && r.top >= box.top - 0.5 && r.right <= box.right + 0.5 && r.bottom <= box.bottom + 0.5;

    void noErrors(String at) {
      final ex = t.takeException();
      need(errors.isEmpty && ex == null, '$at 예외/overflow: ${errors.take(3).toList()} / $ex');
    }

    Map<String, int> reads() => Map.of(calls)..removeWhere((k, _) => k.startsWith('write.') || k.contains('blocked'));
    List<String> readDiff(Map<String, int> pred) {
      final r = reads();
      return [
        for (final k in {...pred.keys, ...r.keys})
          if ((pred[k] ?? 0) != (r[k] ?? 0)) '$k 예측${pred[k] ?? 0}/실제${r[k] ?? 0}',
      ];
    }

    void safe(String at) {
      need(calls.keys.where((k) => k.contains('blocked')).isEmpty, '$at 쓰기·허용 밖 호출·차단 읽기: ${calls.keys.where((k) => k.contains('blocked')).toList()}');
      noErrors(at);
    }

    try {
      final conds = const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ];
      final scenes = [
        for (final c in conds)
          for (final st in const ['denied', 'setup', 'emptyRoot', 'filter0', 'listError', 'stale']) (c: c, state: st),
        (c: conds[1], state: 'multiDay'),
        (c: conds[1], state: 'contract'),
      ];
      var first = true;
      for (final sc in scenes) {
        final c = sc.c;
        final state = sc.state;
        curScene = '${c.id} $state';
        final frames0 = nPump + nMount;
        // ── 이전 장면을 완전히 내린다(같은 navigatorKey·GlobalKey 를 새 트리로 옮기지 않게) ──
        if (!first) {
          nMount++;
          budget();
          await t.pumpWidget(const SizedBox.shrink());
          await frames(1);
          noErrors('unmount');
        }
        first = false;
        FirstPostingReadinessStore.reset();
        PostingQuotaStore.reset();
        PostingQuotaStore.fetchCount = 0;
        calls.clear();
        fnLog.clear();
        variant = switch (state) { 'multiDay' => 'multi', 'contract' => 'contract', _ => 'single' };
        listPlan
          ..clear()
          ..addAll(switch (state) {
            'setup' || 'emptyRoot' => const ['empty'],
            'filter0' || 'multiDay' || 'contract' => const ['one'],
            'listError' => const ['error'],
            'stale' => const ['one', 'error'],
            _ => const <String>[],
          });
        templatesEmpty = state == 'setup';
        stubFirestore();
        stubFunctions();
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        final screen = Rect.fromLTWH(0, 0, c.w, c.h);
        final UserProvider provider = state == 'denied' ? _SubDenied() : _Owner();
        nMount++;
        budget();
        await t.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => provider),
            ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ],
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              navigatorKey: navigatorKey,
              theme: RoleTheme.businessAdminTheme,
              // 앱(main.dart)과 같은 delegate·supportedLocales — locale 은 기기(ko_KR)에서 해석한다.
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
              home: const JobsRootScreen(),
            ),
          ),
        ));
        await frames(24);
        noErrors('진입');

        final hasList = find.byType(WorkforceListView).evaluate().isNotEmpty;
        WorkforceController? ctl() =>
            hasList ? Provider.of<WorkforceController>(t.element(find.byType(WorkforceListView)), listen: false) : null;

        // ── 조건 확인: locale·theme 글꼴·viewport·DPR·배율·inset ──
        final sctx = t.element(find.byType(Scaffold).first);
        final mq = MediaQuery.of(sctx);
        final locale = Localizations.localeOf(sctx).toString();
        final env = {
          'locale': locale, 'size': '${mq.size.width.toInt()}x${mq.size.height.toInt()}', 'dpr': mq.devicePixelRatio,
          'scaler': mq.textScaler.scale(14) / 14, 'padding': '${mq.padding}', 'viewPadding': '${mq.viewPadding}',
          'viewInsets': '${mq.viewInsets}', 'themeFont': Theme.of(sctx).textTheme.bodyMedium?.fontFamily,
        };
        need(locale == 'ko_KR', 'locale 이 ko_KR 이 아니다: $locale');
        need(mq.size == Size(c.w, c.h) && mq.devicePixelRatio == 1.0 && mq.textScaler.scale(14) / 14 == c.s, '조건 불일치 $env');

        // ── 상태 단계(공개 경로만) ──
        final steps = <String>[];
        if (state == 'filter0') {
          final cc = ctl();
          need(cc != null, 'filter0: WorkforceListView 없음');
          cc!.setDateRangeFilter(DateTimeRange(start: workDate.add(const Duration(days: 60)), end: workDate.add(const Duration(days: 90))));
          steps.add('setDateRangeFilter(+60d..+90d)');
          await frames(10);
        } else if (state == 'stale') {
          final cc = ctl();
          need(cc != null, 'stale: WorkforceListView 없음');
          unawaited(cc!.reload(t.element(find.byType(WorkforceListView))));
          steps.add('controller.reload()');
          await frames(24);
        }
        await frames(8);
        safe('상태 단계');

        // ── 머리 receiver(H2)·배지(F2)·한도 문단 — 끌기 전에 잰다 ──
        Map<String, Object?> recv(String name, Finder? f) {
          if (f == null) return {'name': name, 'present': false};
          final r = t.getRect(f);
          final ro = t.renderObject(f);
          bool hitAt(Offset p) {
            final hit = HitTestResult();
            WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
            return hit.path.any((e) => e.target == ro);
          }

          final hit = HitTestResult();
          WidgetsBinding.instance.hitTestInView(hit, r.center, t.view.viewId);
          return {
            'name': name, 'present': true, 'rect': lt(r), 'w': r1(r.width), 'h': r1(r.height),
            'ge48': r.width >= 48 - 0.01 && r.height >= 48 - 0.01, 'centerHit': hitAt(r.center),
            'path': hit.path.take(4).map((e) => e.target.runtimeType.toString()).join('>'), 'inScreen': inside(r, screen),
          };
        }

        final filterF = firstOf(find.ancestor(of: find.byIcon(Icons.filter_list_rounded), matching: find.byType(InkWell)));
        final createF = firstOf(find.ancestor(of: find.byIcon(Icons.add_rounded), matching: find.byType(InkWell)));
        final tabAF = firstOf(find.ancestor(of: rich((p) => p.startsWith('진행중')), matching: find.byType(GestureDetector)));
        final tabCF = firstOf(find.ancestor(of: rich((p) => p == '마감됨'), matching: find.byType(GestureDetector)));
        final h2 = [recv('filter', filterF), recv('create', createF), recv('tabActive', tabAF), recv('tabClosed', tabCF)];
        final present = h2.where((x) => x['present'] == true).toList();
        final overlaps = <String>[];
        for (var i = 0; i < present.length; i++) {
          for (var j = i + 1; j < present.length; j++) {
            final a = present[i]['rect']! as List<double>;
            final b = present[j]['rect']! as List<double>;
            if (Rect.fromLTRB(a[0], a[1], a[2], a[3]).deflate(0.5).overlaps(Rect.fromLTRB(b[0], b[1], b[2], b[3]).deflate(0.5))) {
              overlaps.add('${present[i]['name']}×${present[j]['name']}');
            }
          }
        }
        final needRecv = switch (state) {
          'denied' => const <String>[],
          'setup' => const ['filter'],
          _ => const ['filter', 'create', 'tabActive', 'tabClosed'],
        };
        for (final n in needRecv) {
          need(h2.firstWhere((x) => x['name'] == n)['present'] == true, '필수 receiver 누락: $n');
        }

        Map<String, Object?> badge = {'present': false};
        if (state == 'filter0') {
          final stack = firstOf(find.ancestor(of: find.byIcon(Icons.filter_list_rounded), matching: find.byType(Stack)));
          final txt = stack == null
              ? null
              : firstOf(find.descendant(
                  of: stack, matching: find.byWidgetPredicate((w) => w is Text && int.tryParse(w.data ?? '') != null)));
          need(txt != null && filterF != null, 'F2 배지 또는 필터 receiver 누락');
          final badgeText = txt!;
          final box = firstOf(find.ancestor(of: badgeText, matching: find.byType(Container)))!;
          final br = t.getRect(box);
          final ro = t.renderObject(filterF!);
          final hit = HitTestResult();
          WidgetsBinding.instance.hitTestInView(hit, br.center, t.view.viewId);
          badge = {
            'present': true, 'text': t.widget<Text>(badgeText).data, 'rect': lt(br),
            'hitSameReceiver': hit.path.any((e) => e.target == ro),
            'path': hit.path.take(4).map((e) => e.target.runtimeType.toString()).join('>'),
            'activeFilterCount': ctl()?.activeFilterCount,
          };
        }

        Map<String, Object?> para(String name, Finder? f) {
          if (f == null) return {'name': name, 'present': false};
          final rp = t.renderObject<RenderParagraph>(f);
          final r = t.getRect(f);
          return {
            'name': name, 'present': true, 'plain': plainOf(rp.text), 'maxLines': rp.maxLines,
            'didExceedMaxLines': rp.didExceedMaxLines, 'lines': _lines(rp), 'rect': lt(r), 'inScreen': inside(r, screen),
          };
        }

        final quotaShown = !const {'denied', 'setup'}.contains(state);
        final quota = para('quota', firstOf(rich((p) => p.startsWith('진행 중 공고 1 / 10개'))));
        if (quotaShown) need(quota['present'] == true, '한도 문단 누락');

        // ── 카드 변형: 캡처 전에 근무 줄을 화면에 올린다(최대 2회, 공개 스크롤) ──
        final card = find.byType(TOGroupCard);
        final hasCard = const {'stale', 'multiDay', 'contract'}.contains(state);
        if (hasCard) need(card.evaluate().length == 1, '카드 누락(${card.evaluate().length})');
        Finder workF() => rich((p) => p == expectWork(state), within: card);
        Finder listScroll() => find.ancestor(of: card, matching: find.byType(Scrollable)).first;
        // 공개 스크롤 1회 — 목록 아래쪽에서 손가락을 위로 [want] 만큼(화면 안에서만) 끈다. 끌기 시작 slop(약 20px)은
        //   스크롤되지 않을 수 있어 부르는 쪽이 보정한다. 실제 이동은 pixels 전후로 기록한다.
        Future<Map<String, Object?>> dragUp(Finder scrollable, double want, String what) async {
          final vp = t.getRect(scrollable);
          final from = Offset(vp.left + 24, vp.bottom - 8);
          final d = math.min(want, from.dy - 8);
          final px0 = t.state<ScrollableState>(scrollable).position.pixels;
          await dragFrom(from, Offset(0, -d));
          await frames(6);
          final px1 = t.state<ScrollableState>(scrollable).position.pixels;
          return {'what': what, 'request': r1(want), 'moved': r1(d), 'pixels': [r1(px0), r1(px1)]};
        }

        final dragLog = <Map<String, Object?>>[];
        if (state == 'multiDay' || state == 'contract') {
          for (var k = 1; k <= 2; k++) {
            final f = firstOf(workF());
            need(f != null, '근무 줄 누락(끌기 전)');
            final vp = t.getRect(listScroll());
            final r = t.getRect(f!);
            if (inside(r, vp) && inside(r, screen)) break;
            if (r.top <= vp.top + 8) break;
            // 윗변을 viewport 위 +24(slop 20 이 빠질 때)~+4(빠지지 않을 때)에 맞춘다 — 어느 쪽이든 윗변이 잘리지 않는다.
            dragLog.add(await dragUp(listScroll(), r.top - vp.top - 4, 'F3 work'));
            steps.add('drag F3 $k');
          }
          safe('변형 끌기');
        }

        // ── 근무 줄(F3) ──
        Map<String, Object?> work = {'present': false};
        if (hasCard) {
          final wf = firstOf(workF());
          need(wf != null, '근무 줄 누락(원문 불일치 — 기존 산식 값 ${expectWork(state)})');
          final f = wf!;
          final rp = t.renderObject<RenderParagraph>(f);
          final disp = rp.text.toPlainText();
          final map = <int>[];
          final sb = StringBuffer();
          for (var i = 0; i < disp.length; i++) {
            final ch = disp[i];
            if (ch == wj || ch == zw) continue;
            map.add(i);
            sb.write(ch == nbsp ? ' ' : ch);
          }
          final rem = expectRemaining(state);
          final at = sb.toString().indexOf(rem);
          need(at >= 0, '근무 줄에 남은 기간 원문 없음');
          final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: map[at], extentOffset: map[at + rem.length - 1] + 1));
          Rect? remRect;
          for (final b in boxes) {
            final g = MatrixUtils.transformRect(rp.getTransformTo(null), b.toRect());
            remRect = remRect == null ? g : remRect.expandToInclude(g);
          }
          final r = t.getRect(f);
          final vp = t.getRect(listScroll());
          work = {
            'present': true, 'plain': plainOf(rp.text), 'maxLines': rp.maxLines, 'didExceedMaxLines': rp.didExceedMaxLines,
            'lines': _lines(rp), 'rect': lt(r), 'inScreen': inside(r, screen), 'inListViewport': inside(r, vp),
            'remaining': rem, 'remainingRect': remRect == null ? null : lt(remRect),
            'remainingShown': !rp.didExceedMaxLines && remRect != null,
            'remainingInViewport': remRect != null && !rp.didExceedMaxLines && inside(remRect, vp) && inside(remRect, screen),
            'listViewport': lt(vp),
          };
        }

        // ── 글자색·대비(F7 부제, F9 준비 CTA) ──
        Map<String, Object?> colorOf(String name, Finder? f, {required bool onMaterial}) {
          if (f == null) return {'name': name, 'present': false};
          final rt = t.widget<RichText>(f);
          final fg = _spanColor(rt.text);
          Color? bg;
          if (onMaterial) {
            final mf = firstOf(find.ancestor(of: f, matching: find.byType(Material)));
            bg = mf == null ? null : t.widget<Material>(mf).color;
          } else {
            final sf = firstOf(find.ancestor(of: f, matching: find.byType(Scaffold)));
            bg = sf == null ? null : t.widget<Scaffold>(sf).backgroundColor;
          }
          return {
            'name': name, 'present': true, 'plain': plainOf(rt.text), 'fg': fg == null ? null : _hex(fg),
            'bg': bg == null ? null : _hex(bg),
            'contrast': fg == null || bg == null ? null : double.parse(_contrast(fg, bg).toStringAsFixed(2)),
            'textSecondary': fg == AppColors.textSecondary, 'grey400': fg == AppColors.grey400,
          };
        }

        final sub = stateSubtitle[state];
        final subColor = sub == null ? {'present': false} : colorOf('subtitle', firstOf(rich((p) => p == sub)), onMaterial: false);
        if (sub != null) need(subColor['present'] == true && subColor['contrast'] != null, '부제 문단/색 측정 누락');
        final cta = state == 'setup'
            ? colorOf('setupCta', firstOf(rich((p) => p == '준비 단계 보기')), onMaterial: true)
            : {'present': false};
        if (state == 'setup') need(cta['present'] == true && cta['contrast'] != null, '준비 CTA 측정 누락');

        // ── 도달·필수 계측·reader 를 캡처 직전에 확인 ──
        final title = stateTitle[state];
        if (title != null) need(firstOf(rich((p) => p == title)) != null, '상태 문구 미도달: $title');
        final preDiff = readDiff(predictedPre[state]!);
        need(preDiff.isEmpty, '캡처 전 reader 차이 $preDiff');
        safe('캡처 전');
        final shotId = 'D231-$phase-${c.id}_$state';
        await shot(shotId, {
          'phase': phase, 'state': state, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
          'locale': locale, 'theme': 'RoleTheme.businessAdminTheme', 'clock': '미주입(now=${_kst(now)})',
          'fixture': 'variant=$variant firstWorkDate=${_kst(workDate)}', 'steps': steps.join(' / '),
        });

        // ── 캡처 뒤 행동 ──
        final post = <String, Object?>{};
        // F4: B320 stale — 공개 스크롤 최대 2회로 제목·일시·업무/남은기간을 읽을 수 있는가(양 phase 기록, after 단언).
        if (state == 'stale' && c.id == 'B320') {
          final staleF = rich((p) => p == stateTitle['stale']);
          final targets = <String, Finder Function()>{
            'title': () => rich((p) => p == kTitle, within: card),
            'when': () => rich((p) => p.endsWith('QA 물류센터') && p.contains('·'), within: card),
            'work': workF,
          };
          final seenAt = <String, int>{};
          void look(int k) {
            final vp = t.getRect(listScroll());
            for (final e in targets.entries) {
              if (seenAt.containsKey(e.key)) continue;
              final f = firstOf(e.value());
              if (f == null) continue;
              final r = t.getRect(f);
              if (inside(r, vp) && inside(r, screen)) seenAt[e.key] = k;
            }
          }

          look(0);
          final vp0 = t.getRect(listScroll());
          for (var k = 1; k <= 2; k++) {
            final next = targets.keys.firstWhere((n) => !seenAt.containsKey(n), orElse: () => '');
            if (next.isEmpty) break;
            final f = firstOf(targets[next]!());
            if (f == null) break;
            final vp = t.getRect(listScroll());
            final r = t.getRect(f);
            if (r.top <= vp.top + 8) break;
            dragLog.add(await dragUp(listScroll(), r.top - vp.top - 4, 'F4 $next'));
            look(k);
            await shot('${shotId}_d$k', {'phase': phase, 'state': 'stale-F4-drag$k', 'textScaler': c.s, 'locale': locale});
          }
          final sf = firstOf(staleF);
          final staleVisible = sf != null && inside(t.getRect(sf), screen);
          post['F4'] = {'listViewportAt0': lt(vp0), 'seenAt': seenAt, 'staleBannerVisibleAfterDrags': staleVisible};
          if (after) {
            need(seenAt.length == 3, 'F4 2회 안에 제목·일시·업무를 모두 읽지 못함 $seenAt');
            need(staleVisible, 'F4 끈 뒤 오래된 데이터 경고가 사라짐');
          }
          safe('F4');
        }

        // F1·F2 필터 시트: after filter0 — 중심 tap 1회로 열고 X 로 닫는다. 필터 상태 보존·추가 reader 0.
        if (after && state == 'filter0') {
          final cc = ctl()!;
          final before = (cc.activeFilterCount, cc.selectedDateRange);
          final readsBefore = reads();
          await tapAt(t.getRect(filterF!).center, '필터 중심');
          await frames(10);
          final opened = find.byType(FilterDialog).evaluate().isNotEmpty;
          need(opened, '필터 시트가 열리지 않음');
          final x = firstOf(find.descendant(of: find.byType(FilterDialog), matching: find.byIcon(Icons.close)));
          need(x != null, '필터 시트 닫기 버튼 누락');
          await tapAt(t.getRect(x!).center, '시트 닫기');
          await frames(10);
          final closed = find.byType(FilterDialog).evaluate().isEmpty;
          final kept = cc.activeFilterCount == before.$1 && cc.selectedDateRange == before.$2;
          final sameReads = jsonEncode(reads()) == jsonEncode(readsBefore);
          post['sheet'] = {'opened': opened, 'closed': closed, 'filterKept': kept, 'readsSame': sameReads};
          need(closed && kept && sameReads, '필터 시트 닫힘/상태/reader ${post['sheet']}');
          safe('필터 시트');
        }

        // F8 회귀: B320 filter0·listError — AppEmptyState 실제 스크롤 최대 2회로 복구 버튼 전체가 보이는가.
        if (c.id == 'B320' && (state == 'filter0' || state == 'listError')) {
          final label = state == 'filter0' ? '필터 초기화' : '다시 시도';
          final btnOrNull = firstOf(find.ancestor(
              of: rich((p) => p == label, within: find.byType(AppEmptyState)),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
          need(btnOrNull != null, 'F8 복구 버튼 누락: $label');
          final btn = btnOrNull!;
          final scr = find.ancestor(of: btn, matching: find.byType(Scrollable)).first;
          bool full() => inside(t.getRect(btn), t.getRect(scr)) && inside(t.getRect(btn), screen);
          var reachedAt = full() ? 0 : -1;
          final f8 = <Map<String, Object?>>[];
          for (var k = 1; k <= 2 && reachedAt < 0; k++) {
            final vp = t.getRect(scr);
            final r = t.getRect(btn);
            // 아랫변을 viewport 안 8px 로 — slop 20 + 여유 4 를 더한다(넘쳐도 버튼 높이보다 작아 윗변은 남는다).
            f8.add(await dragUp(scr, r.bottom - (vp.bottom - 8) + 24, 'F8 $label'));
            if (full()) reachedAt = k;
          }
          final br = t.getRect(btn);
          post['F8'] = {'label': label, 'reachedAt': reachedAt, 'buttonRect': lt(br), 'w': r1(br.width), 'h': r1(br.height), 'drags': f8};
          if (after) {
            need(reachedAt >= 0, 'F8 2회 안에 $label 버튼에 닿지 못함');
            await tapAt(br.center, label);
            await frames(10);
            if (state == 'filter0') {
              final cc = ctl()!;
              final restored = cc.activeFilterCount == 0 && card.evaluate().length == 1;
              post['F8tap'] = {'filtersCleared': cc.activeFilterCount == 0, 'cards': card.evaluate().length};
              need(restored, 'F8 필터 초기화 뒤 상태 ${post['F8tap']}');
            } else {
              final still = firstOf(rich((p) => p == stateTitle['listError'])) != null;
              post['F8tap'] = {'stillError': still, 'fn': List.of(fnLog)};
              need(still, 'F8 다시 시도 뒤 같은 실패 상태가 아님');
            }
          }
          safe('F8');
        }

        // ── 장면 끝 안전 검사(다음 장면 전) ──
        final postDiff = readDiff(predictedPost(state, c.id));
        need(postDiff.isEmpty, '장면 끝 reader 차이 $postDiff');
        safe('장면 끝');

        // ── after 성공조건(F1·F2·F3·F7·F9) ──
        if (after) {
          for (final x in present) {
            need(x['ge48'] == true && x['inScreen'] == true && x['centerHit'] == true, 'F1 receiver ${x['name']} $x');
          }
          need(overlaps.isEmpty, 'F1 receiver 겹침 $overlaps');
          if (state == 'filter0') need(badge['hitSameReceiver'] == true, 'F2 배지 위 hit 이 필터 receiver 가 아님 $badge');
          if (hasCard) {
            need(work['maxLines'] == null && work['didExceedMaxLines'] == false && work['remainingShown'] == true,
                'F3 남은 기간이 온전히 표시되지 않음 $work');
            if (c.id == 'W360') need(work['remainingInViewport'] == true, 'F3 W 남은 기간이 화면 밖 $work');
          }
          if (sub != null) {
            need(subColor['textSecondary'] == true && (subColor['contrast']! as double) >= 4.5, 'F7 부제 대비 $subColor');
          }
          if (state == 'setup' && c.id == 'W360') {
            need((cta['contrast']! as double) >= 4.5 && cta['bg'] == _hex(AppColors.brand), 'F9 준비 CTA $cta');
          }
        }

        _out('D231 ${jsonEncode({
              'phase': phase, 'cond': c.id, 'state': state, 'variant': variant, 'env': env, 'steps': steps,
              'cards': card.evaluate().length, 'readiness': '${FirstPostingReadinessStore.current.value.status}',
              'quotaStatus': '${PostingQuotaStore.current.value.status}', 'quotaFetch': PostingQuotaStore.fetchCount,
              'calls': calls, 'readDiffPre': preDiff, 'readDiffPost': postDiff, 'fn': fnLog,
              'h2': h2, 'h2Overlaps': overlaps, 'badge': badge, 'quotaLine': quota, 'workLine': work,
              'subtitle': subColor, 'setupCta': cta, 'drags': dragLog, 'post': post,
              'sceneFrames': nPump + nMount - frames0, 'counts': counts(), 'taps': List.of(tapLog),
              'kst': _kst(DateTime.now()),
            })}');
      }
      nMount++;
      budget();
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      noErrors('끝');
      _out('D231-END ${jsonEncode({'phase': phase, 'counts': counts(), 'taps': tapLog})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 4)));
}
