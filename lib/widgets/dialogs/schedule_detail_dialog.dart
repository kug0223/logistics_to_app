import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/core/application_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/to_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/common/loading_widget.dart';
import '../../utils/responsive_helper.dart';  // ⭐ 추가

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
      debugPrint('상세 정보 로드 실패: $e');
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
                      padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildBusinessInfo(),
                          SizedBox(height: ResponsiveHelper.spacing(context, 20)),  // ⭐ 변경
                          _buildWorkInfo(),
                          SizedBox(height: ResponsiveHelper.spacing(context, 20)),  // ⭐ 변경
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
      padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline, 
            color: Colors.white, 
            size: ResponsiveHelper.iconSize(context, 28),  // ⭐ 변경
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '근무 상세 정보',
                  style: ResponsiveHelper.tinyStyle(context).copyWith(  // ⭐ 변경
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                Text(
                  widget.application.businessName,
                  style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                    context,
                    color: Colors.white.withValues(alpha: 0.9),
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
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
        
        if (_business != null) ...[
          _buildInfoRow(Icons.business, '사업장명', _business!.name),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
          _buildInfoRow(Icons.location_on, '주소', _business!.address),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
          
          // 전화 버튼
          if (_business!.phone != null && _business!.phone!.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () => _makePhoneCall(_business!.phone!),
              icon: Icon(
                Icons.phone, 
                size: ResponsiveHelper.iconSize(context, 18),  // ⭐ 변경
              ),
              label: Text('전화하기 (${_business!.phone})'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          
          // 센터 안내사항
          if (_business!.description != null && _business!.description!.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
            Container(
              padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline, 
                        size: ResponsiveHelper.iconSize(context, 16),  // ⭐ 변경
                        color: Theme.of(context).primaryColor,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 6)),  // ⭐ 변경
                      Text(
                        '센터 안내사항',
                        style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                          context,
                          color: Theme.of(context).primaryColor,
                        ).copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                  Text(
                    _business!.description!,
                    style: ResponsiveHelper.smallStyle(context),  // ⭐ 변경
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
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
        
        _buildInfoRow(Icons.work_outline, '업무 유형', widget.application.selectedWorkType),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
        _buildInfoRow(Icons.access_time, '근무 시간', 
          '${widget.application.startTime} ~ ${widget.application.endTime}'),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
        _buildInfoRow(Icons.attach_money, '급여', widget.application.formattedWage),
        
        if (widget.application.isLongTermApplication) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
          _buildInfoRow(Icons.calendar_month, '근무 기간', widget.application.workPeriodDisplay),
          if (widget.application.workDaysDisplay != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
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
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
        
        _buildInfoRow(Icons.title, 'TO 제목', _to!.title),
        
        if (_to!.description != null && _to!.description!.isNotEmpty) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
          Container(
            padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.description, 
                      size: ResponsiveHelper.iconSize(context, 16),  // ⭐ 변경
                      color: Colors.orange,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),  // ⭐ 변경
                    Text(
                      '업무 설명',
                      style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                        context,
                        color: Colors.orange,
                      ).copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                Text(
                  _to!.description!,
                  style: ResponsiveHelper.smallStyle(context),  // ⭐ 변경
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
      style: ResponsiveHelper.subtitleStyle(context),  // ⭐ 변경
    );
  }
  
  /// 정보 행
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon, 
          size: ResponsiveHelper.iconSize(context, 18),  // ⭐ 변경
          color: Theme.of(context).textTheme.bodySmall?.color,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                  context,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 2)),  // ⭐ 변경
              Text(
                value,
                style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 변경
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