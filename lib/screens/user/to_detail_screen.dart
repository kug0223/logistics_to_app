import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/to_model.dart';
import '../../models/work_detail_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';

/// TO 상세 화면 - 신버전 (업무유형 선택)
class TODetailScreen extends StatefulWidget {
  final TOModel to;

  const TODetailScreen({
    Key? key,
    required this.to,
  }) : super(key: key);

  @override
  State<TODetailScreen> createState() => _TODetailScreenState();
}

class _TODetailScreenState extends State<TODetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<WorkDetailModel> _workDetails = [];
  bool _isLoadingWorkDetails = true;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _loadWorkDetails();
  }

  /// WorkDetails 조회
  Future<void> _loadWorkDetails() async {
    setState(() {
      _isLoadingWorkDetails = true;
    });

    try {
      final workDetails = await _firestoreService.getWorkDetails(widget.to.id);
      setState(() {
        _workDetails = workDetails;
        _isLoadingWorkDetails = false;
      });
      print('✅ WorkDetails 조회 완료: ${workDetails.length}개');
    } catch (e) {
      print('❌ WorkDetails 조회 실패: $e');
      setState(() {
        _isLoadingWorkDetails = false;
      });
      ToastHelper.showError('업무 정보를 불러오는데 실패했습니다.');
    }
  }

  /// 지원하기 - 업무유형 선택 다이얼로그 표시
  Future<void> _handleApply() async {
    if (widget.to.isDeadlinePassed) {
      ToastHelper.showWarning('지원 마감된 TO입니다.');
      return;
    }

    if (_workDetails.isEmpty) {
      ToastHelper.showError('업무 정보를 불러올 수 없습니다.');
      return;
    }

    // 업무유형 선택 다이얼로그
    final selectedWork = await _showWorkTypeSelectionDialog();
    if (selectedWork == null) return;

    // 지원 확인 다이얼로그
    final confirmed = await _showConfirmDialog(selectedWork);
    if (confirmed != true) return;

    // 지원 처리
    setState(() => _isApplying = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }

      final success = await _firestoreService.applyToTOWithWorkType(
        toId: widget.to.id,
        uid: uid,
        selectedWorkType: selectedWork.workType,
        wage: selectedWork.wage,
      );

      if (success && mounted) {
        Navigator.pop(context); // 화면 닫기
      }
    } catch (e) {
      print('❌ 지원 실패: $e');
      ToastHelper.showError('지원 중 오류가 발생했습니다.');
    } finally {
      if (mounted) {
        setState(() => _isApplying = false);
      }
    }
  }

  /// 업무유형 선택 다이얼로그
  Future<WorkDetailModel?> _showWorkTypeSelectionDialog() async {
    return showDialog<WorkDetailModel>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('업무 선택'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '지원할 업무를 선택해주세요',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ..._workDetails.map((work) => _buildWorkDetailOption(work)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
        ],
      ),
    );
  }

  /// 업무유형 선택 옵션
  Widget _buildWorkDetailOption(WorkDetailModel work) {
    final isFull = work.isFull;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isFull
              ? null
              : () => Navigator.pop(context, work),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isFull ? Colors.grey[100] : Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isFull ? Colors.grey[300]! : Colors.blue[200]!,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                // 아이콘
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isFull ? Colors.grey[300] : Colors.blue[100],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.work_outline,
                    color: isFull ? Colors.grey[600] : Colors.blue[700],
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),

                // 업무 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        work.workType,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isFull ? Colors.grey[600] : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        work.formattedWage,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isFull ? Colors.grey[500] : Colors.blue[700],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${work.countInfo} ${isFull ? "(마감)" : "(${work.remainingCount}명 남음)"}',
                        style: TextStyle(
                          fontSize: 13,
                          color: isFull ? Colors.red[700] : Colors.grey[700],
                          fontWeight: isFull ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),

                // 선택 아이콘
                if (!isFull)
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.blue[700],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 지원 확인 다이얼로그
  Future<bool?> _showConfirmDialog(WorkDetailModel selectedWork) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지원 확인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('이 TO에 지원하시겠습니까?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.to.businessName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.to.formattedDate} (${widget.to.weekday})',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                  Text(
                    widget.to.timeRange,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                  const Divider(height: 16),
                  Row(
                    children: [
                      Icon(Icons.work_outline, size: 16, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Text(
                        '${selectedWork.workType} | ${selectedWork.formattedWage}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[900],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 14, color: Colors.orange[700]),
                      const SizedBox(width: 4),
                      Text(
                        '지원 마감: ${widget.to.formattedDeadline}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
            ),
            child: const Text('지원하기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TO 상세'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: _isApplying
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('지원하는 중...'),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 헤더
                  _buildHeader(),

                  // 상세 정보 카드
                  _buildDetailCard(),

                  // 업무 목록
                  _buildWorkDetailsSection(),

                  // 설명
                  if (widget.to.description != null && widget.to.description!.isNotEmpty)
                    _buildDescriptionSection(),

                  const SizedBox(height: 80), // 버튼 여백
                ],
              ),
            ),
      bottomNavigationBar: _isApplying
          ? null
          : _buildBottomButton(),
    );
  }

  /// 헤더
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[700]!, Colors.blue[500]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.to.businessName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              _buildStatusBadge(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.to.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.to.formattedDate} (${widget.to.weekday})',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 상세 정보 카드
  Widget _buildDetailCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 마감 시간 정보
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.to.isDeadlinePassed ? Colors.red[50] : Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.to.isDeadlinePassed
                    ? Colors.red.shade200
                    : Colors.blue.shade200,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: widget.to.isDeadlinePassed
                        ? Colors.red[100]
                        : Colors.blue[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    widget.to.isDeadlinePassed
                        ? Icons.lock_clock
                        : Icons.access_time,
                    color: widget.to.isDeadlinePassed
                        ? Colors.red[700]
                        : Colors.blue[700],
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.to.isDeadlinePassed ? '지원 마감됨' : '지원 마감',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.to.formattedDeadline,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: widget.to.isDeadlinePassed
                              ? Colors.red[700]
                              : Colors.blue[900],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.to.deadlineStatus,
                        style: TextStyle(
                          fontSize: 13,
                          color: widget.to.isDeadlinePassed
                              ? Colors.red[600]
                              : Colors.orange[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 근무 시간
          _buildInfoRow(
            Icons.access_time,
            '근무 시간',
            widget.to.timeRange,
          ),
          const SizedBox(height: 16),

          // 전체 모집 인원
          _buildInfoRow(
            Icons.people_outline,
            '전체 모집',
            '${widget.to.totalConfirmed}/${widget.to.totalRequired}명',
            color: widget.to.totalConfirmed >= widget.to.totalRequired
                ? Colors.red[700]!
                : Colors.blue[700]!,
          ),
        ],
      ),
    );
  }

  /// 업무 목록 섹션
  Widget _buildWorkDetailsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '업무 목록',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (_isLoadingWorkDetails)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_workDetails.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('업무 정보가 없습니다'),
              ),
            )
          else
            ..._workDetails.map((work) => _buildWorkDetailCard(work)),
        ],
      ),
    );
  }

  /// 업무 카드
  /// WorkDetail 카드 위젯
  Widget _buildWorkDetailCard(WorkDetailModel work) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 업무 유형
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                work.workType,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: work.isFull ? Colors.red[50] : Colors.blue[50],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  work.countInfo,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: work.isFull ? Colors.red[700] : Colors.blue[700],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ✅ NEW: 근무 시간 표시
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text(
                work.timeRange, // "09:00 ~ 18:00"
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 금액
          Row(
            children: [
              Icon(Icons.payments, size: 16, color: Colors.green[600]),
              const SizedBox(width: 6),
              Text(
                work.formattedWage,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 설명 섹션
  Widget _buildDescriptionSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '상세 설명',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.to.description!,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[800],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 정보 행
  Widget _buildInfoRow(IconData icon, String label, String value, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color ?? Colors.grey[600]),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 15,
              color: color ?? Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  /// 상태 배지
  Widget _buildStatusBadge() {
    if (widget.to.isDeadlinePassed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red[700],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '마감',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (widget.to.isFull) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange[700],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '인원마감',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green[700],
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        '모집중',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 하단 버튼
  Widget _buildBottomButton() {
    final canApply = !widget.to.isDeadlinePassed && !widget.to.isFull;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade300,
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: canApply ? _handleApply : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              disabledBackgroundColor: Colors.grey[400],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              canApply
                  ? '지원하기'
                  : widget.to.isDeadlinePassed
                      ? '지원 마감'
                      : '인원 마감',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}