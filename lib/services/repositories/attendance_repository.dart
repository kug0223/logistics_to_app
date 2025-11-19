import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/core/attendance_model.dart';
import 'base_repository.dart';

/// 출근 관련 DB 작업
class AttendanceRepository extends BaseRepository {
  
  /// 출근 체크
  Future<String?> checkIn({
    required String applicationId,
    required String userId,
    required String businessId,
    required String businessName,
    required DateTime workDate,
    required String workType,
    required double latitude,
    required double longitude,
    String method = 'gps',
  }) async {
    try {
      print('🕐 출근 체크 시작...');
      
      // 1. 이미 출근했는지 확인
      final existing = await _getAttendanceByApplicationId(applicationId);
      if (existing != null && existing.checkIn != null) {
        print('⚠️ 이미 출근 처리되었습니다');
        return null;
      }

      // 2. 출근 시간 포맷
      final now = DateTime.now();
      final checkInTimeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      // 3. 출근 기록 생성
      final attendance = AttendanceModel(
        id: '',
        applicationId: applicationId,
        userId: userId,
        businessId: businessId,
        businessName: businessName,
        workDate: workDate,
        workType: workType,
        checkIn: checkInTimeStr,
        checkInLat: latitude,
        checkInLng: longitude,
        checkInMethod: method,
        checkInTime: now,
        status: 'present',
        createdAt: now,
      );

      final docRef = await firestore
          .collection('attendance')
          .add(attendance.toMap());

      print('✅ 출근 체크 완료: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ 출근 체크 실패: $e');
      return null;
    }
  }

  /// 퇴근 체크
  Future<bool> checkOut({
    required String attendanceId,
    required double latitude,
    required double longitude,
    String method = 'gps',
  }) async {
    try {
      // 1. 출근 기록 조회
      final doc = await firestore
          .collection('attendance')
          .doc(attendanceId)
          .get();
      
      if (!doc.exists) {
        throw Exception('출근 기록을 찾을 수 없습니다.');
      }
      
      final data = doc.data()!;
      if (data['checkOut'] != null) {
        throw Exception('이미 퇴근하셨습니다.');
      }
      
      // 2. 퇴근 시간 포맷
      final now = DateTime.now();
      final checkOutTimeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      
      // 3. 근무 시간 계산
      final checkInTimeStr = data['checkIn'] as String;
      final workHours = _calculateWorkHours(checkInTimeStr, checkOutTimeStr);

      // 4. 퇴근 기록 저장
      await firestore.collection('attendance').doc(attendanceId).update({
        'checkOut': checkOutTimeStr,
        'checkOutLat': latitude,
        'checkOutLng': longitude,
        'checkOutMethod': method,
        'checkOutTime': FieldValue.serverTimestamp(),
        'workHours': workHours,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ 퇴근 체크 완료');
      return true;
    } catch (e) {
      print('❌ 퇴근 체크 실패: $e');
      return false;
    }
  }

  /// 특정 날짜 출근 기록 조회
  Future<List<AttendanceModel>> getAttendanceByDate({
    required String businessId,
    required DateTime date,
  }) async {
    try {
      final dateStart = DateTime(date.year, date.month, date.day);
      final dateEnd = dateStart.add(const Duration(days: 1));
      
      final snapshot = await firestore
          .collection('attendance')
          .where('businessId', isEqualTo: businessId)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
          .where('workDate', isLessThan: Timestamp.fromDate(dateEnd))
          .get();
      
      return snapshot.docs
          .map((doc) => AttendanceModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 출근 기록 조회 실패: $e');
      return [];
    }
  }

  /// 지원서별 출근 기록 조회 (private)
  Future<AttendanceModel?> _getAttendanceByApplicationId(
    String applicationId,
  ) async {
    try {
      final snapshot = await firestore
          .collection('attendance')
          .where('applicationId', isEqualTo: applicationId)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      return AttendanceModel.fromFirestore(snapshot.docs.first);
    } catch (e) {
      print('❌ 출근 기록 조회 실패: $e');
      return null;
    }
  }

  /// 근무 시간 계산 (private helper)
  double _calculateWorkHours(String checkIn, String checkOut) {
    try {
      final inParts = checkIn.split(':');
      final outParts = checkOut.split(':');
      
      final inMinutes = int.parse(inParts[0]) * 60 + int.parse(inParts[1]);
      final outMinutes = int.parse(outParts[0]) * 60 + int.parse(outParts[1]);
      
      final diffMinutes = outMinutes - inMinutes;
      return diffMinutes / 60.0;
    } catch (e) {
      print('❌ 근무 시간 계산 실패: $e');
      return 0.0;
    }
  }
}