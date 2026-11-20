// [UI-3] 지원자 상세 머리줄의 성별·나이 조각 — 없는 값을 `-세`·홀로 남은 구분점으로
//   만들지 않고, 제품 저장 계약('남성'·'여성')이 아닌 값은 추정하지 않는다.
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/widgets/dialogs/worker_detail_dialog.dart';

UserModel _u({String? gender, DateTime? birthDate}) => UserModel(
    uid: 'w1',
    username: 'w1',
    name: '합성',
    email: 'w1@test.local',
    role: UserRole.USER,
    gender: gender,
    birthDate: birthDate);

void main() {
  final adult = DateTime(DateTime.now().year - 30, 1, 1);

  test('PF-1 성별·나이 둘 다 있으면 둘 다', () {
    expect(workerProfileFacts(_u(gender: '여성', birthDate: adult)),
        ['여성', '30세']);
  });

  test('PF-2 외국인처럼 둘 다 없으면 빈 목록(화면은 `성별·나이 정보 없음`)', () {
    expect(workerProfileFacts(_u()), isEmpty);
  });

  test('PF-3 저장 계약 밖의 성별 값은 추정하지 않고 뺀다', () {
    expect(workerProfileFacts(_u(gender: 'male', birthDate: adult)),
        ['30세']);
  });

  test('PF-5 [UI-4] 성별만 있으면 성별은 보인다(나이가 없다고 함께 숨기지 않는다)', () {
    expect(workerProfileFacts(_u(gender: '여성')), ['여성']);
  });

  test('PF-4 생년월일이 오늘이라 0세면 나이를 쓰지 않는다', () {
    final today = DateTime.now();
    expect(workerProfileFacts(_u(gender: '남성', birthDate: today)), ['남성']);
  });
}
