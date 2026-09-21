// [R8-P7] 한 슬롯의 좌석을 세려고 그 TO 의 모든 날짜 지원서를 받아오지 않는다.
//
//   예전 주석은 "slotId 쿼리는 보안 규칙 제한"이라 TO 전체를 받아 클라이언트에서
//   거른다고 적혀 있었다. 그 제약은 이 경로가 Firestore 직접 쿼리이던 시절의 것이고,
//   지금은 callableGetApplicationsByBiz(Admin SDK) 경유라 해당하지 않는다.
//   DEV 실측에서 18건을 받아 1건만 쓰고 있었다.
//
//   그리고 USER 경로의 조회 실패를 빈 목록으로 바꾸지 않는다 —
//   모르는 것을 "지원 내역 없음"으로 말하면 안 된다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final f = File(path);
  if (!f.existsSync()) throw StateError('파일을 찾지 못했다: $path');
  return f.readAsStringSync();
}

/// 주석을 지운 코드만 남긴다 — 표지를 주석에 두지 않기 위해.
String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _slice(String raw, String from, String to) {
  final s = raw.indexOf(from);
  if (s < 0) throw StateError('시작 표지를 찾지 못했다: $from');
  final e = raw.indexOf(to, s + from.length);
  if (e < 0) throw StateError('끝 표지를 찾지 못했다: $to');
  return raw.substring(s, e);
}

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  const appSvc = 'lib/services/firestore/application_firestore.dart';
  const fsSvc = 'lib/services/firestore_service.dart';

  group('[R8P7] 슬롯 범위 조회', () {
    test('APLC-1 getApplicationsByTOId 가 slotId 를 받는다', () {
      final code = _codeOf(_read(appSvc));
      final sig = _flat(_slice(code,
          'Future<List<ApplicationModel>> getApplicationsByTOId(',
          'async {'));
      expect(sig.contains('String? slotId'), isTrue,
          reason: 'slotId 파라미터가 사라졌다 — 다시 TO 전체를 받게 된다');
    });

    test('APLC-2 관리자 경로가 slotId 를 CF 에 넘긴다', () {
      final code = _codeOf(_read(appSvc));
      final body = _flat(_slice(code,
          "'businessId': businessId,",
          "final statusSet = statuses != null"));
      expect(body.contains("'slotId': slotId"), isTrue,
          reason: '서버 필터가 빠지면 TO 전체를 받아 클라이언트에서 거르게 된다');
    });

    test('APLC-3 loadTOWorkDetails 가 slotId 를 전달한다', () {
      final code = _codeOf(_read(fsSvc));
      final body = _flat(_slice(code,
          'final allApps = await getApplicationsByTOId(',
          'const activeStatuses'));
      expect(body.contains('slotId: slotId'), isTrue,
          reason: '한 슬롯을 세려고 TO 전체를 받는 상태로 되돌아갔다');
    });

    test('APLC-4 USER 경로가 좌석 계산 술어를 바꾸지 않는다', () {
      // 서버가 걸러도 클라이언트 술어는 그대로여야 같은 사실을 말한다.
      final code = _codeOf(_read(fsSvc));
      final body = _flat(_slice(code,
          'const activeStatuses',
          "workStats[key] ??="));
      expect(body.contains('!a.isStaffingReleased'), isTrue,
          reason: '좌석을 반납한 확정은 정원을 소모하지 않는다 — 이 술어가 빠지면 Home 과 어긋난다');
      expect(body.contains("'PENDING', 'CONFIRMED', 'CONTRACT_PENDING'"), isTrue);
    });
  });

  group('[R8P7] UNKNOWN ≠ EMPTY', () {
    test('APLC-5 USER 경로 조회 실패를 빈 목록으로 바꾸지 않는다', () {
      final code = _codeOf(_read(appSvc));
      // 표지는 반드시 코드여야 한다 — _codeOf 가 주석 줄을 지운다.
      // [R8-P7.1] 관리자 경로가 페이징 헬퍼로 바뀌어 끝 표지를 옮겼다.
      final body = _flat(_slice(code,
          "httpsCallable('callableGetMyApplications'",
          'fetchApplicationsByBizPaged({'));
      expect(body.contains('rethrow'), isTrue,
          reason: '조회 실패를 "지원 내역 없음"으로 표시하면 안 된다');
      expect(body.contains('return [];'), isFalse,
          reason: '빈 목록 반환이 되살아났다');
    });

    test('APLC-6 관리자 경로도 계속 rethrow 한다', () {
      final code = _codeOf(_read(appSvc));
      expect(
        _flat(code).contains("지원자 목록 조회 실패(admin): \$e'); rethrow;"),
        isTrue,
        reason: '관리자에게 빈 목록을 보여 주면 지원자가 없는 것으로 오인한다',
      );
    });
  });
}
