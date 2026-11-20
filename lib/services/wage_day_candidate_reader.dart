// [DU1 후속22 §2] 급여 일자 후보(B) **전용** reader 후보 — 원 응답 envelope(items·limitReached·wageDay·projection)를 축약 없이 돌려준다.
//   기존 일반 attendance reader(attendance_firestore.dart `_callableGetAdminAttendancesWithLimit`)는 purpose 를 보내지 않고
//   모델 목록으로 줄이므로 그대로 쓰지 않는다. 이 파일은 **어느 화면·급여창·확정 버튼에도 연결되지 않는다**.
//   사용: `WageDayCandidateLoader.load(read: reader.read, ...)` — loader 의 필수 주입 구조를 그대로 둔다.
import 'package:cloud_functions/cloud_functions.dart';

/// callable 호출 경계. 실제 앱은 [WageDayCandidateReader.firebase], 시험은 fake transport 를 넣는다.
typedef CandidateCallableTransport = Future<Object?> Function(String callableName, Map<String, dynamic> data);

class WageDayCandidateReader {
  WageDayCandidateReader({required CandidateCallableTransport transport}) : _transport = transport;

  /// 기본 callable transport — 기존 일반 reader 와 같은 callable 이름·region·timeout(attendance_firestore.dart:510).
  factory WageDayCandidateReader.firebase() => WageDayCandidateReader(transport: _firebaseTransport);

  static const callableName = 'callableGetAdminAttendances';
  final CandidateCallableTransport _transport;

  static Future<Object?> _firebaseTransport(String name, Map<String, dynamic> data) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
    final result = await callable.call<Object?>(data);
    return result.data;
  }

  /// 요청 map(loader 가 만든 purpose/businessId/startMs/endMs)을 **그대로** 보내고 `result.data` 를 그대로 돌려준다.
  ///   transport 오류는 그대로 던진다. Map 이 아닌 응답은 형식 오류로 던진다 — 빈 결과·정상 0 으로 바꾸지 않는다.
  ///   재수화·모델·약속 병합은 하지 않는다(lib 소비 구현 consumeCandidateWageDay 가 한다).
  Future<Map<String, dynamic>> read(Map<String, dynamic> request) async {
    final data = await _transport(callableName, Map<String, dynamic>.from(request));
    if (data is! Map) {
      throw StateError('wageDay 응답이 map 이 아니다: ${data.runtimeType}');
    }
    return Map<String, dynamic>.from(data);
  }
}
