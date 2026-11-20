// ignore_for_file: depend_on_referenced_packages
// [CORE-GOLDEN-PATH-CONNECTED.1 · LOCAL] 직접 지원 흐름에서 **앱 코드가 만드는 payload** 를 파일로 꺼낸다.
//
//   노드 하네스(AlFit-release-candidates/core-golden-path-20261025/tools/gp.js)가 이 파일들을
//   배포 번들 실핸들러에 그대로 넘긴다. 입력은 그 하네스가 에뮬레이터에서 읽은 writer 출력(run/*.json)이다.
//   GP_RUN 환경변수가 없으면 건너뛴다(일반 스위트에 영향 없음).
//
//   - fingerprint: AttendanceRules.fromMap → attendancePolicyFingerprint (지원 payload 의 expectedAttendancePolicy)
//   - employer:    ContractService.buildPreviewContract → saveEmployerSignature 가 서버로 보낼 cfData
//                  (서명 호출은 주입으로 가로채 응답하지 않는다 — 실제 호출은 노드가 배포 핸들러로 한다)
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/utils/attendance_policy_disclosure.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options =>
      const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

final _run = Platform.environment['GP_RUN'];

/// 하네스가 남긴 {__ts: ms} 를 Firestore Timestamp 로 되돌린다(앱이 Firestore 에서 받는 모양).
Object? _restore(Object? v) {
  if (v is Map) {
    if (v.length == 1 && v.containsKey('__ts')) {
      return Timestamp.fromMillisecondsSinceEpoch((v['__ts'] as num).toInt());
    }
    return v.map((k, x) => MapEntry(k as String, _restore(x)));
  }
  if (v is List) return v.map(_restore).toList();
  return v;
}

Map<String, dynamic> _doc(String name) =>
    (_restore(jsonDecode(File('$_run/$name.json').readAsStringSync())) as Map).cast<String, dynamic>();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  test('GP-A fingerprint · 동의 버전 (앱 함수)', () {
    if (_run == null) return markTestSkipped('GP_RUN 없음');
    final b = _doc('business');
    final rules = AttendanceRules.fromMap((b['attendanceRules'] as Map).cast<String, dynamic>());
    File('$_run/app-fingerprint.txt').writeAsStringSync(attendancePolicyFingerprint(rules));
    File('$_run/app-consent-version.txt').writeAsStringSync(DocumentAccessConsent.version);
  }, skip: _run == null || !File('$_run/business.json').existsSync());

  test('GP-B 사업주 서명 cfData (앱 ContractService)', () async {
    final st = (jsonDecode(File('$_run/state.json').readAsStringSync()) as Map).cast<String, dynamic>();
    final app = ApplicationModel.fromMap(_doc('application'), st['applicationId'] as String);
    final biz = BusinessModel.fromMap(_doc('business'), (_doc('application')['businessId'] as String?) ?? 'biz_gp');
    final worker = UserModel.fromMap(_doc('worker'), (_doc('application')['uid'] as String));
    // 앱 _getWorkForApp 과 같은 출처: 그 슬롯의 workDetails 중 지원서 workDetailId 와 같은 항목
    final slot = _doc('slot');
    final wdMap = (slot['workDetails'] as List).cast<Map>().firstWhere(
        // 앱 WorkDetailHelper 와 같은 순서: workDetailId, 없으면 업무·시작·종료 복합키(초대 지원서는 workDetailId 없이 wdId 만 있다)
        (w) => (w['wdId'] ?? w['id']) == app.workDetailId ||
            (app.workDetailId == null && w['workType'] == app.selectedWorkType && w['startTime'] == app.startTime && w['endTime'] == app.endTime)).cast<String, dynamic>();
    final wd = WorkDetailData.fromMap(wdMap, wdMap['wdId'] as String?);
    Map<String, dynamic>? captured;
    final svc = ContractService(employerSignatureCall: (data) async {
      captured = data;
      return {'employerSignatureStoragePath': 'captured-only'}; // 서버 호출은 노드가 한다
    });
    final contract = await svc.buildPreviewContract(application: app, business: biz, worker: worker, workDetail: wd);
    final sig = File('C:/Users/kug02/AlFit-release-candidates/full13-tax-20261024/e6/fixtures/arc_synth.png').readAsBytesSync();
    // GP_NOBYTES=1 — [CONTRACT-DISPATCH-B1] 발송 화면(일별·업무별·검토 큐)의 실제 호출: 바이트 없이(서버가 owner 날인)
    final noBytes = Platform.environment['GP_NOBYTES'] == '1';
    await svc.saveEmployerSignature(
        contract: contract, signatureBytes: noBytes ? null : Uint8List.fromList(sig));
    expect(captured, isNotNull);
    expect(captured!['isNewUnsaved'], isTrue);
    // Timestamp 등은 앱 callable 직렬화와 같은 규칙으로 보내야 한다 — 여기서는 노드가 읽을 수 있게 표식만 바꾼다.
    Object? wire(Object? v) => v is Timestamp
        ? {'__ts': v.millisecondsSinceEpoch}
        : v is DateTime
            ? {'__dt': v.millisecondsSinceEpoch}
            : v is Map
                ? v.map((k, x) => MapEntry(k, wire(x)))
                : v is List
                    ? v.map(wire).toList()
                    : v;
    File('$_run/employer-cfdata.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(wire(captured)));
  }, skip: _run == null || !File('$_run/application.json').existsSync());

  // 급여 계산 확정 payload — wage_confirm_dialog._calculateWageForWorker 의 _wageParams 와 같은 규칙.
  //   값은 앱 모델이 writer 출력(지원서·근태·슬롯 문서)을 읽은 결과에서만 가져온다.
  test('GP-C 급여 계산 확정 params (앱 모델이 읽은 근태)', () {
    final st = (jsonDecode(File('$_run/state.json').readAsStringSync()) as Map).cast<String, dynamic>();
    final app = ApplicationModel.fromMap(_doc('application'), st['applicationId'] as String);
    final att = AttendanceModel.fromMap(_doc('attendance'), st['attendanceId'] as String);
    final slot = _doc('slot');
    final baseWage = att.snapshotWage ?? app.wage;
    var wageType = app.wageType ?? 'hourly';
    var breakMinutes = 0;
    var nightAllowanceApplied = true;
    var nightIncluded = false;
    int? baseHourlyWage;
    var taxDeductionType = InsuranceRateModel.typeNone;
    for (final w in (slot['workDetails'] as List).cast<Map>()) {
      final type = w['workType'] as String? ?? '';
      final composite = '${type}_${w['startTime'] ?? ''}_${w['endTime'] ?? ''}';
      if (type == app.selectedWorkType || composite == app.workDetailId) {
        wageType = w['wageType'] as String? ?? 'hourly';
        breakMinutes = (w['breakMinutes'] as num?)?.toInt() ?? 0;
        nightAllowanceApplied = w['nightAllowanceApplied'] as bool? ?? true;
        nightIncluded = w['nightIncluded'] as bool? ?? false;
        baseHourlyWage = (w['baseHourlyWage'] as num?)?.toInt();
        taxDeductionType = w['taxDeductionType'] as String? ?? InsuranceRateModel.typeNone;
        break;
      }
    }
    if (att.snapshotWageType != null) wageType = att.snapshotWageType!;
    final kst = att.workDate.toUtc().add(const Duration(hours: 9));
    final params = {
      'wageType': wageType,
      'baseWage': baseWage,
      'workDate': FormatHelper.formatDateISO(DateTime(kst.year, kst.month, kst.day)),
      'scheduledStart': app.startTime,
      'scheduledEnd': app.endTime,
      'actualStart': att.checkIn!.split(':').take(2).join(':'),
      'actualEnd': att.checkOut!.split(':').take(2).join(':'),
      'breakMinutes': breakMinutes,
      'scheduledBreakMinutes': breakMinutes,
      'appliedScheduledBreakMinutes': breakMinutes,
      'additionalBreakMinutes': 0,
      'nightAllowanceApplied': nightAllowanceApplied,
      'nightIncluded': nightIncluded,
      'additionalAmount': 0,
      if (baseHourlyWage != null) 'baseHourlyWage': baseHourlyWage,
      'taxDeductionType': taxDeductionType,
      'attendanceId': att.id,
      'yearMonth': '${kst.year}-${kst.month.toString().padLeft(2, '0')}',
    };
    File('$_run/calc-params.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(params));
  }, skip: _run == null || !File('$_run/attendance.json').existsSync());
}
