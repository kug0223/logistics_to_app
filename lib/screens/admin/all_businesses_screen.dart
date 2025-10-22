import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/business_model.dart';
import '../../models/user_model.dart';
import '../../widgets/loading_widget.dart';
import '../../utils/toast_helper.dart';

/// ✅ 모든 사업장 조회 화면 (최고관리자 전용)
/// ownerId 필터 없이 모든 사업장 표시
class AllBusinessesScreen extends StatefulWidget {
  const AllBusinessesScreen({Key? key}) : super(key: key);

  @override
  State<AllBusinessesScreen> createState() => _AllBusinessesScreenState();
}

class _AllBusinessesScreenState extends State<AllBusinessesScreen> {
  List<_BusinessWithOwner> _businesses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllBusinesses();
  }

  /// 모든 사업장 로드 (소유자 정보 포함)
  Future<void> _loadAllBusinesses() async {
    setState(() {
      _isLoading = true;
    });

    try {
      print('🔍 [SUPER_ADMIN] 모든 사업장 조회 시작...');
      
      // 1. 모든 사업장 조회
      final businessSnapshot = await FirebaseFirestore.instance
          .collection('businesses')
          .orderBy('createdAt', descending: true)
          .get();

      print('✅ [SUPER_ADMIN] 조회된 사업장: ${businessSnapshot.docs.length}개');

      // 2. 각 사업장의 소유자 정보 조회
      final List<_BusinessWithOwner> businessesWithOwner = [];
      
      for (var doc in businessSnapshot.docs) {
        final business = BusinessModel.fromMap(doc.data(), doc.id);
        
        // 소유자 정보 조회
        String ownerName = '알 수 없음';
        String ownerEmail = '';
        
        try {
          final ownerDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(business.ownerId)
              .get();
          
          if (ownerDoc.exists) {
            final ownerData = ownerDoc.data()!;
            ownerName = ownerData['name'] ?? '알 수 없음';
            ownerEmail = ownerData['email'] ?? '';
          }
        } catch (e) {
          print('⚠️ 소유자 정보 조회 실패: $e');
        }

        businessesWithOwner.add(_BusinessWithOwner(
          business: business,
          ownerName: ownerName,
          ownerEmail: ownerEmail,
        ));
      }

      setState(() {
        _businesses = businessesWithOwner;
        _isLoading = false;
      });

      print('✅ [SUPER_ADMIN] 사업장 로드 완료: ${_businesses.length}개');
    } catch (e) {
      print('❌ [SUPER_ADMIN] 사업장 로드 실패: $e');
      ToastHelper.showError('사업장 목록을 불러오는데 실패했습니다: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('전체 사업장 관리'),
        backgroundColor: Colors.purple[700],
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllBusinesses,
            tooltip: '새로고침',
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget(message: '사업장 목록을 불러오는 중...')
          : _businesses.isEmpty
              ? _buildEmptyState()
              : _buildBusinessList(),
    );
  }

  /// 빈 상태
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
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 사업장 목록
  Widget _buildBusinessList() {
    return RefreshIndicator(
      onRefresh: _loadAllBusinesses,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _businesses.length,
        itemBuilder: (context, index) {
          final item = _businesses[index];
          return _buildBusinessCard(item);
        },
      ),
    );
  }

  /// 사업장 카드
  Widget _buildBusinessCard(_BusinessWithOwner item) {
    final business = item.business;
    
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
            // 사업장명 + 상태
            Row(
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: business.isApproved
                        ? Colors.green[50]
                        : Colors.orange[50],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    business.isApproved ? '승인됨' : '대기중',
                    style: TextStyle(
                      color: business.isApproved
                          ? Colors.green[700]
                          : Colors.orange[700],
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            // 소유자 정보
            _buildInfoRow(
              icon: Icons.person,
              label: '소유자',
              value: '${item.ownerName}${item.ownerEmail.isNotEmpty ? " (${item.ownerEmail})" : ""}',
              color: Colors.purple,
            ),
            const SizedBox(height: 12),

            // 사업자등록번호
            _buildInfoRow(
              icon: Icons.numbers,
              label: '사업자등록번호',
              value: business.formattedBusinessNumber,
              color: Colors.blue,
            ),
            const SizedBox(height: 12),

            // 업종
            _buildInfoRow(
              icon: Icons.category,
              label: '업종',
              value: '${business.category} / ${business.subCategory}',
              color: Colors.green,
            ),
            const SizedBox(height: 12),

            // 주소
            _buildInfoRow(
              icon: Icons.location_on,
              label: '주소',
              value: business.address,
              color: Colors.red,
            ),

            // 연락처 (있을 경우)
            if (business.phone != null) ...[
              const SizedBox(height: 12),
              _buildInfoRow(
                icon: Icons.phone,
                label: '연락처',
                value: business.phone!,
                color: Colors.orange,
              ),
            ],

            // 설명 (있을 경우)
            if (business.description != null && business.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  business.description!,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],

            // 등록일
            const SizedBox(height: 12),
            Text(
              '등록일: ${_formatDate(business.createdAt)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
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
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
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

  /// 날짜 포맷팅
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

/// 사업장 + 소유자 정보를 담는 클래스
class _BusinessWithOwner {
  final BusinessModel business;
  final String ownerName;
  final String ownerEmail;

  _BusinessWithOwner({
    required this.business,
    required this.ownerName,
    required this.ownerEmail,
  });
}