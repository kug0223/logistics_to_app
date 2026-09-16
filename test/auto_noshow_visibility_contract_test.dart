// [PREDEVICE] 자동 NO_SHOW 기록은 관리자에게 보여야 한다
//
// READ에서 확인된 것:
//   · processAutoNoShow는 attendance 문서를 createdAt 없이 썼다.
//   · AttendanceModel.fromMap은 createdAt이 없으면 ArgumentError를 던지고,
//     모든 읽기 경로가 tryFromMap + whereType로 감싸므로 그 문서는 null이 되어
//     관리자 근태 목록에서 통째로 사라졌다.
//   · 같은 문서를 서버의 srvHomeUnclosed는 status === "NO_SHOW"로 읽어
//     그 날짜를 "마감 완료"로 처리했다.
//   → 관리자에게는 "처리할 일 없음 + 근태 기록 없음"으로 보였다. 무단결근이
//     조용히 사라지는 경로다. NO_SHOW를 정상 근무와 같게 취급한 것과 같다.
//
//   · 또, 단기 경로만 status == "CONFIRMED"로 조회했다. 좌석을 차지하는 상태는
//     CONFIRMED + CONTRACT_PENDING인데(callableCheckIn 허용 목록과 동일),
//     계약 대기 상태로 근무일을 배정받은 단기 근로자의 무단결근은
//     자동 NO_SHOW 대상이 아니었다. 장기 경로는 이미 두 상태를 모두 봤다.
//
// 계약:
//   자동 NO_SHOW가 쓰는 문서는 수동 NO_SHOW(callableBatchSetNoShow)가 쓰는
//   문서와 같은 모양이어야 하고, 대상 상태 집합도 좌석 정의와 같아야 한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnsPath = 'functions/src/index.ts';
const _attModelPath = 'lib/models/core/attendance_model.dart';
const _attFsPath = 'lib/services/firestore/attendance_firestore.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

/// 이름 붙은 함수 선언부터 다음 `export ` 또는 파일 끝까지를 잘라낸다.
String _fnSliceOf(String source, String decl) {
  final start = source.indexOf(decl);
  if (start < 0) throw StateError('$decl 을 찾지 못함');
  final next = source.indexOf('\nexport ', start + decl.length);
  return source.substring(start, next == -1 ? source.length : next);
}

void main() {
  final fns = _src(_fnsPath);
  final noShow = _codeOf(_fnSliceOf(fns, 'async function processAutoNoShow('));

  group('자동 NO_SHOW 문서는 클라이언트가 읽을 수 있어야 한다', () {
    test('AttendanceModel은 createdAt이 없으면 여전히 거부한다 — 계약의 전제', () {
      // 이 단언이 깨지면 아래 테스트들의 근거가 사라진다. 모델을 느슨하게 만드는
      // 방향으로 고치지 않았음을 고정한다 — 깨진 문서를 조용히 통과시키는 대신
      // 쓰는 쪽이 온전한 문서를 쓰는 것이 이 수정의 방향이다.
      final model = _src(_attModelPath);
      expect(
        _flat(model).contains(
          "throw ArgumentError('AttendanceModel: createdAt 필드 누락",
        ),
        true,
        reason: 'AttendanceModel.fromMap의 createdAt 필수 계약이 사라졌다',
      );
    });

    test('읽기 경로는 tryFromMap으로 감싸 있으므로 깨진 문서는 조용히 버려진다', () {
      // 즉, 쓰는 쪽이 온전하지 않으면 사용자에게는 오류가 아니라 "없음"이 된다.
      final attFs = _flat(_codeOf(_src(_attFsPath)));
      expect(
        attFs.contains('AttendanceModel.tryFromMap(m, id);') &&
            attFs.contains('.whereType<AttendanceModel>()'),
        true,
        reason: '근태 파싱 경로가 바뀌었다면 이 계약을 다시 판단해야 한다',
      );
    });

    test('processAutoNoShow의 두 쓰기 모두 createdAt을 쓴다', () {
      final writes =
          'createdAt: admin.firestore.FieldValue.serverTimestamp(),'
              .allMatches(noShow)
              .length;
      expect(writes, 2,
          reason: '단기/장기 두 경로 모두 createdAt을 써야 한다 (현재 $writes곳)');
    });

    test('processAutoNoShow는 workType을 지원서에서 가져와 쓴다', () {
      expect(
        'workType: (d.selectedWorkType ?? "") as string,'
            .allMatches(noShow)
            .length,
        2,
        reason: '수동 NO_SHOW(callableBatchSetNoShow)와 같은 필드를 채워야 한다',
      );
    });

    test('자동 NO_SHOW 문서 모양이 수동 NO_SHOW와 어긋나지 않는다', () {
      // 원문은 키 정렬 공백을 쓰므로 공백을 접어서 비교한다.
      final flat = _flat(noShow);
      for (final field in [
        'status: "NO_SHOW",',
        'wageStatus: "confirmed",',
        'finalWage: 0,',
        'isModified: false,',
        'modifyRequested: false,',
      ]) {
        expect(field.allMatches(flat).length, 2,
            reason: '$field 가 두 경로 모두에 있어야 한다');
      }
    });
  });

  group('자동 NO_SHOW 대상 상태는 좌석 정의와 같아야 한다', () {
    test('단기 경로가 CONTRACT_PENDING을 더 이상 빠뜨리지 않는다', () {
      expect(
        noShow.contains('.where("status", "==", "CONFIRMED")'),
        false,
        reason: '단기 경로가 CONFIRMED만 조회하면 계약 대기 근로자의 무단결근을 놓친다',
      );
    });

    test('단기·장기 모두 CONFIRMED + CONTRACT_PENDING을 본다', () {
      expect(
        '.where("status", "in", ["CONFIRMED", "CONTRACT_PENDING"])'
            .allMatches(noShow)
            .length,
        2,
        reason: '두 경로가 같은 좌석 정의를 써야 한다',
      );
    });

    test('출근 허용 상태 집합과 같은 정의다 — callableCheckIn', () {
      expect(
        _flat(_codeOf(fns)).contains(
          'const confirmedStatuses = ["CONFIRMED", "CONTRACT_PENDING"];',
        ),
        true,
        reason: '출근 가능한 사람만 무단결근할 수 있다. 두 집합은 같아야 한다',
      );
    });
  });
}
