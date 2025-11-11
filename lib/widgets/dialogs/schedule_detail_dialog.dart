import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/core/application_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/to_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/common/loading_widget.dart';

/// 일정 상세 정보 다이얼로그
class ScheduleDetailDialog extends StatefulWidget {
  final ApplicationModel application;
  
  const ScheduleDetailDialog({
    super.key,
    required this.application,
  });
  
  @override
  State<ScheduleDetailDialog> createState() => _ScheduleDetailDialogState();
}

class _ScheduleDetailDialogState extends State<ScheduleDetailDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoading = true;
  BusinessModel? _business;
  TOModel? _to;
  
  @override
  void initState() {
    super.initState();
    _loadDetails();
  }
  
  Future<void> _loadDetails() async {
    try {
      final results = await Future.wait([
        _firestoreService.getBusinessById(widget.application.businessId),
        _firestoreService.getTOByApplication(widget.application),
      ]);
      
      setState(() {
        _business = results[0] as BusinessModel?;
        _to = results[1] as TOModel?;
        _isLoading = false;
      });
    } catch (e) {
      print('상세 정보 로드 실패: $e');
      setState(() => _isLoading = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: _isLoading
            ? const LoadingWidget(message: '정보를 불러오는 중...')
            : Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildBusinessInfo(),
                          const SizedBox(height: 20),
                          _buildWorkInfo(),
                          const SizedBox(height: 20),
                          _buildTOInfo(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
  
  /// 헤더
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue[700],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(4),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '근무 상세 정보',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.application.businessName,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }
  
  /// 사업장 정보
  Widget _buildBusinessInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('📍 사업장 정보'),
        const SizedBox(height: 12),
        
        if (_business != null) ...[
          _buildInfoRow(Icons.business, '사업장명', _business!.name),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.location_on, '주소', _business!.address),
          const SizedBox(height: 8),
          
          // 전화 버튼
          if (_business!.phone != null && _business!.phone!.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () => _makePhoneCall(_business!.phone!),
              icon: const Icon(Icons.phone, size: 18),
              label: Text('전화하기 (${_business!.phone})'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
              ),
            ),
          
          // 센터 안내사항
          if (_business!.description != null && _business!.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                      const SizedBox(width: 6),
                      Text(
                        '센터 안내사항',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[900],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _business!.description!,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
  
  /// 업무 정보
  Widget _buildWorkInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('💼 업무 정보'),
        const SizedBox(height: 12),
        
        _buildInfoRow(Icons.work_outline, '업무 유형', widget.application.selectedWorkType),
        const SizedBox(height: 8),
        _buildInfoRow(Icons.access_time, '근무 시간', 
          '${widget.application.startTime} ~ ${widget.application.endTime}'),
        const SizedBox(height: 8),
        _buildInfoRow(Icons.attach_money, '급여', widget.application.formattedWage),
        
        if (widget.application.isLongTermApplication) ...[
          const SizedBox(height: 8),
          _buildInfoRow(Icons.calendar_month, '근무 기간', widget.application.workPeriodDisplay),
          if (widget.application.workDaysDisplay != null) ...[
            const SizedBox(height: 8),
            _buildInfoRow(Icons.event_repeat, '근무 요일', widget.application.workDaysDisplay!),
          ],
        ],
      ],
    );
  }
  
  /// TO 정보
  Widget _buildTOInfo() {
    if (_to == null) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('📋 공고 정보'),
        const SizedBox(height: 12),
        
        _buildInfoRow(Icons.title, 'TO 제목', _to!.title),
        
        if (_to!.description != null && _to!.description!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.description, size: 16, color: Colors.orange[700]),
                    const SizedBox(width: 6),
                    Text(
                      '업무 설명',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[900],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _to!.description!,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
  
  /// 섹션 제목
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }
  
  /// 정보 행
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  /// 전화 걸기
  Future<void> _makePhoneCall(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}