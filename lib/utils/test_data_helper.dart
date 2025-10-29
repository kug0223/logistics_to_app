import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

class TestDataHelper {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final Random _random = Random();

  // 더미 이름 풀
  static final List<String> _firstNames = [
    '김', '이', '박', '최', '정', '강', '조', '윤', '장', '임',
    '한', '오', '서', '신', '권', '황', '안', '송', '류', '전'
  ];

  static final List<String> _lastNames = [
    '민준', '서준', '예준', '도윤', '시우', '주원', '하준', '지호', '지후', '준서',
    '서연', '서윤', '지우', '서현', '민서', '하은', '윤서', '지민', '지유', '채원'
  ];

  /// 더미 지원자 생성
  static Future<List<String>> createDummyApplicants(int count) async {
    print('👥 더미 지원자 $count명 생성 시작...');
    
    List<String> uids = [];

    for (int i = 0; i < count; i++) {
      final firstName = _firstNames[_random.nextInt(_firstNames.length)];
      final lastName = _lastNames[_random.nextInt(_lastNames.length)];
      final name = '$firstName$lastName';
      
      final uid = 'dummy_user_${DateTime.now().millisecondsSinceEpoch}_$i';
      final phone = '010-${_random.nextInt(9000) + 1000}-${_random.nextInt(9000) + 1000}';
      final email = 'dummy$i@test.com';

      await _firestore.collection('users').doc(uid).set({
        'uid': uid,
        'name': name,
        'email': email,
        'phone': phone,
        'role': 'user',
        'createdAt': FieldValue.serverTimestamp(),
        'isDummy': true,  // ✅ 더미 데이터 표시
      });

      uids.add(uid);
      print('✅ 지원자 생성: $name ($phone)');
    }

    print('🎉 더미 지원자 $count명 생성 완료!');
    return uids;
  }

  /// 특정 TO에 더미 지원서 생성
  static Future<void> createDummyApplications({
    required String toId,
    required List<String> workTypes,
    required int pendingCount,
    required int confirmedCount,
  }) async {
    print('📝 TO $toId에 지원서 생성 중...');
    print('   - 대기: $pendingCount명');
    print('   - 확정: $confirmedCount명');

    // 1. 더미 지원자 생성
    final totalCount = pendingCount + confirmedCount;
    final uids = await createDummyApplicants(totalCount);

    // 2. TO 정보 조회
    final toDoc = await _firestore.collection('tos').doc(toId).get();
    if (!toDoc.exists) {
      print('❌ TO를 찾을 수 없습니다: $toId');
      return;
    }

    final toData = toDoc.data()!;
    final businessId = toData['businessId'];
    final date = (toData['date'] as Timestamp).toDate();

    // 3. WorkDetails 조회
    final workDetailsSnapshot = await _firestore
        .collection('tos')
        .doc(toId)
        .collection('workDetails')
        .get();

    if (workDetailsSnapshot.docs.isEmpty) {
      print('❌ WorkDetails가 없습니다');
      return;
    }

    final workDetails = workDetailsSnapshot.docs;

    // 4. 지원서 생성
    int uidIndex = 0;

    // 대기 중인 지원서
    for (int i = 0; i < pendingCount && uidIndex < uids.length; i++) {
      final workDetail = workDetails[_random.nextInt(workDetails.length)];
      final workData = workDetail.data();

      await _firestore.collection('applications').add({
        'uid': uids[uidIndex],
        'toId': toId,
        'businessId': businessId,
        'selectedWorkType': workData['workType'],
        'wage': workData['wage'],
        'workDate': Timestamp.fromDate(date),
        'startTime': workData['startTime'],
        'endTime': workData['endTime'],
        'status': 'PENDING',
        'appliedAt': FieldValue.serverTimestamp(),
        'isDummy': true,  // ✅ 더미 데이터 표시
      });

      print('✅ 대기 지원서 생성: ${uids[uidIndex]} → ${workData['workType']}');
      uidIndex++;
    }

    // 확정된 지원서
    for (int i = 0; i < confirmedCount && uidIndex < uids.length; i++) {
      final workDetail = workDetails[_random.nextInt(workDetails.length)];
      final workData = workDetail.data();

      await _firestore.collection('applications').add({
        'uid': uids[uidIndex],
        'toId': toId,
        'businessId': businessId,
        'selectedWorkType': workData['workType'],
        'wage': workData['wage'],
        'workDate': Timestamp.fromDate(date),
        'startTime': workData['startTime'],
        'endTime': workData['endTime'],
        'status': 'CONFIRMED',
        'appliedAt': FieldValue.serverTimestamp(),
        'confirmedAt': FieldValue.serverTimestamp(),
        'confirmedBy': 'admin_test',
        'isDummy': true,  // ✅ 더미 데이터 표시
      });

      print('✅ 확정 지원서 생성: ${uids[uidIndex]} → ${workData['workType']}');
      uidIndex++;
    }

    print('🎉 지원서 생성 완료!');
  }

  /// 모든 더미 데이터 삭제
  static Future<void> clearAllDummyData() async {
    print('🗑️ 더미 데이터 삭제 시작...');

    // 1. 더미 지원자 삭제
    final usersSnapshot = await _firestore
        .collection('users')
        .where('isDummy', isEqualTo: true)
        .get();

    for (var doc in usersSnapshot.docs) {
      await doc.reference.delete();
    }
    print('✅ 더미 지원자 ${usersSnapshot.docs.length}명 삭제');

    // 2. 더미 지원서 삭제
    final appsSnapshot = await _firestore
        .collection('applications')
        .where('isDummy', isEqualTo: true)
        .get();

    for (var doc in appsSnapshot.docs) {
      await doc.reference.delete();
    }
    print('✅ 더미 지원서 ${appsSnapshot.docs.length}개 삭제');

    print('🎉 더미 데이터 삭제 완료!');
  }
}