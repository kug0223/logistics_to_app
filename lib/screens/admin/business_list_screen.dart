import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/business_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/loading_widget.dart';
import '../../utils/toast_helper.dart';
import 'business_registration_screen.dart';  // ⭐ 같은 admin 폴더!

/// 사업장 목록 화면 (관리자의 사업장 관리)
class BusinessListScreen extends StatefulWidget {
  const BusinessListScreen({Key? key}) : super(key: key);

  @override
  State<BusinessListScreen> createState() => _BusinessListScreenState();
}

class _BusinessListScreenState extends State<BusinessListScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<BusinessModel> _businesses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBusinesses();
  }

  /// 내 사업장 목록 불러오기
  Future<void> _loadBusinesses() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      print('🔍 [DEBUG] 현재 사용자 UID: $uid');

      if (uid == null) {
        ToastHelper.showError('로그인이 필요합니다.');
        return;
      }

      // ownerId가 현재 사용자인 사업장들만 조회
      print('🔍 [DEBUG] Firestore 쿼리 시작...');
      final snapshot = await FirebaseFirestore.instance
          .collection('businesses')
          .where('ownerId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .get();

      print('🔍 [DEBUG] 조회된 문서 개수: ${snapshot.docs.length}');
      
      // 각 문서의 ownerId 출력
      for (var doc in snapshot.docs) {
        print('🔍 [DEBUG] 문서 ID: ${doc.id}, ownerId: ${doc.data()['ownerId']}, 이름: ${doc.data()['name']}');
      }

      final List<BusinessModel> businesses = snapshot.docs
          .map((doc) => BusinessModel.fromMap(doc.data(), doc.id))
          .toList();

      setState(() {
        _businesses = businesses;
        _isLoading = false;
      });

      print('✅ 조회된 사업장: ${businesses.length}개');
      
      if (businesses.isEmpty) {
        print('⚠️ [WARNING] 사업장이 없습니다. Firebase Console에서 businesses 컬렉션을 확인하세요!');
      }
    } catch (e) {
      print('❌ 사업장 목록 로드 실패: $e');
      print('❌ 에러 스택: ${StackTrace.current}');
      ToastHelper.showError('사업장 목록을 불러오는데 실패했습니다: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 사업장 삭제
  Future<void> _deleteBusiness(String businessId, String businessName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('사업장 삭제'),
        content: Text('$businessName을(를) 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // TODO: 이 사업장에 연결된 TO가 있는지 확인하고 삭제 방지 로직 추가 가능
      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .delete();

      ToastHelper.showSuccess('사업장이 삭제되었습니다.');
      _loadBusinesses(); // 목록 새로고침
    } catch (e) {
      print('❌ 사업장 삭제 실패: $e');
      ToastHelper.showError('사업장 삭제에 실패했습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 사업장 관리'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const LoadingWidget(message: '사업장 목록을 불러오는 중...')
          : _businesses.isEmpty
              ? _buildEmptyState()
              : _buildBusinessList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          // 사업장 등록 화면으로 이동
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => BusinessRegistrationScreen(
                isFromSignUp: false, // 홈에서 온 경우
              ),
            ),
          );

          // 등록 완료 후 돌아오면 목록 새로고침
          if (result == true) {
            _loadBusinesses();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('사업장 추가'),
        backgroundColor: Colors.blue[700],
      ),
    );
  }

  /// 빈 화면 (등록된 사업장이 없을 때)
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.business_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '등록된 사업장이 없습니다',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '아래 버튼을 눌러 사업장을 등록해보세요',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  /// 사업장 목록
  Widget _buildBusinessList() {
    return RefreshIndicator(
      onRefresh: _loadBusinesses,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _businesses.length,
        itemBuilder: (context, index) {
          final business = _businesses[index];
          return _buildBusinessCard(business);
        },
      ),
    );
  }

  /// 사업장 카드
  Widget _buildBusinessCard(BusinessModel business) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더 (사업장명 + 버튼들)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    business.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Row(
                  children: [
                    // 수정 버튼
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      color: Colors.blue[700],
                      onPressed: () async {
                        // TODO: 사업장 수정 화면으로 이동
                        ToastHelper.showInfo('사업장 수정 기능은 준비 중입니다.');
                      },
                    ),
                    // 삭제 버튼
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20),
                      color: Colors.red[700],
                      onPressed: () => _deleteBusiness(business.id, business.name),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),

            // 사업자등록번호
            _buildInfoRow(
              icon: Icons.numbers,
              label: '사업자등록번호',
              value: business.formattedBusinessNumber,
            ),
            const SizedBox(height: 8),

            // 업종
            _buildInfoRow(
              icon: Icons.category,
              label: '업종',
              value: '${business.category} / ${business.subCategory}',
            ),
            const SizedBox(height: 8),

            // 주소
            _buildInfoRow(
              icon: Icons.location_on,
              label: '주소',
              value: business.address,
            ),

            // 연락처 (있을 경우)
            if (business.phone != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                icon: Icons.phone,
                label: '연락처',
                value: business.phone!,
              ),
            ],

            // 설명 (있을 경우)
            if (business.description != null && business.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                business.description!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            // 승인 상태
            const SizedBox(height: 12),
            _buildApprovalStatus(business.isApproved),
          ],
        ),
      ),
    );
  }

  /// 정보 행
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 14, color: Colors.grey[800]),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 승인 상태 표시
  Widget _buildApprovalStatus(bool isApproved) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isApproved ? Colors.green[50] : Colors.orange[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isApproved ? Colors.green : Colors.orange,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isApproved ? Icons.check_circle : Icons.access_time,
            size: 16,
            color: isApproved ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 6),
          Text(
            isApproved ? '승인됨' : '승인 대기중',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isApproved ? Colors.green[800] : Colors.orange[800],
            ),
          ),
        ],
      ),
    );
  }
}