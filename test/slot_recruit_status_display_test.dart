// [R7-SLOT-STATUS-OWNER] 날짜 칩의 '모집중/마감'은 slot.status 를 읽는다.
//
//   DEV 실측 결함: 초대 수락으로 정원이 찼는데 `slot.status` 가 open 으로
//   남았다(낡은 트리거 실행이 최신 FULL 을 덮었다). 그때 지원자 화면의 날짜
//   칩은 그 날짜를 '모집중'으로 보여 주고 탭도 열려 있었다.
//
//   이 테스트는 **왜 서버 쪽 한 줄이 화면을 바꾸는지**를 고정한다 —
//   `isEffectivelyClosed` 에서 인원 충족을 뜻하는 유일한 신호가 `isFull`
//   (= slot.status == 'full') 이라는 사실. workDetailCounts 가 아무리 정확해도
//   이 필드가 틀리면 칩은 틀린다. 그래서 상태의 주인을 카운터와 같은
//   트랜잭션으로 옮겼다.
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';

WorkDetailData _wd({int requiredCount = 1}) => WorkDetailData(
      wdId: 'w1',
      workType: 'QA',
      startTime: '23:50',
      endTime: '23:59',
      wage: 10000,
      wageType: 'hourly',
      requiredCount: requiredCount,
      // 마감 시각은 아직 오지 않았다 — 시간 축으로 닫히지 않게 둔다.
      applicationDeadline: DateTime.now().add(const Duration(days: 1)),
    );

SlotModel _slot({
  required String status,
  required int confirmedCount,
  int requiredCount = 1,
}) =>
    SlotModel(
      id: 'slot1',
      toId: 'to1',
      // 오늘 — 날짜 경과로 닫히지 않게 둔다.
      date: DateTime.now(),
      status: status,
      confirmedCount: confirmedCount,
      workDetails: [_wd(requiredCount: requiredCount)],
      workDetailCounts: {
        'w1': SlotWorkTypeCount(
          confirmedCount: confirmedCount,
          pendingCount: 0,
        ),
      },
      createdAt: DateTime(2025),
    );

void main() {
  group('날짜 칩 — 인원 충족의 표시 신호', () {
    test('slot.status=full 이면 마감으로 본다', () {
      final s = _slot(status: SlotStatus.full, confirmedCount: 1);
      expect(s.isFull, isTrue);
      expect(s.isEffectivelyClosed, isTrue,
          reason: '정원이 찬 날짜는 칩이 열려 있으면 안 된다');
    });

    test('정원이 찼는데 status 가 open 이면 칩이 열린 채로 남는다 (결함의 모양)', () {
      final s = _slot(status: SlotStatus.open, confirmedCount: 1);
      // 업무 단위 카운터는 정확하다 — 그래도 칩은 틀린다.
      expect(s.isWorkDetailFull(s.workDetails.first), isTrue);
      expect(s.isEffectivelyClosed, isFalse,
          reason: 'isEffectivelyClosed 의 인원 충족 신호는 slot.status 하나뿐이다');
    });

    test('인원 부족이면 열려 있다', () {
      final s = _slot(status: SlotStatus.open, confirmedCount: 1, requiredCount: 2);
      expect(s.isWorkDetailFull(s.workDetails.first), isFalse);
      expect(s.isEffectivelyClosed, isFalse);
    });

    test('모집 완료는 근무 종료가 아니다 — closed 와 구별된다', () {
      final full = _slot(status: SlotStatus.full, confirmedCount: 1);
      final closed = _slot(status: SlotStatus.closed, confirmedCount: 0);
      expect(full.isClosed, isFalse, reason: 'full 을 closed 로 승격하지 않는다');
      expect(full.isFull, isTrue);
      expect(closed.isClosed, isTrue);
      expect(closed.isFull, isFalse);
    });
  });
}
