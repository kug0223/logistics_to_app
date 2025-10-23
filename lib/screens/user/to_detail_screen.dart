import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/to_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';

/// TO 상세 화면 - 마감 시간 기능 추가 버전
class TODetailScreen extends StatefulWidget {
  final TOModel to;

  const TODetailScreen({
    super.key,
    required this.to,
  });

  @override
  State<TODetailScreen> createState() => _TODetailScreenState();
}

class _TODetailScreenState extends State<TODetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isApplying = false;
  String? _applicationStatus; // null, 'PENDING', 'CONFIRMED', 'REJECTED', 'CANCELED'
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkApplicationStatus();
  }

  /// 내 지원 상태 확인
  Future<void> _checkApplicationStatus() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;

    if (uid == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final myApplications = await _firestoreService.getMyApplications(uid);
      
      // 현재 TO에 대한 지원 내역 찾기
      final myApplication = myApplications.firstWhere(
        (app) => app.toId == widget.to.id,
        orElse: () => throw Exception('Not found'),
      );

      setState(() {
        _applicationStatus = myApplication.status;
        _isLoading = false;
      });
    } catch (e) {
      // 지원 내역이 없으면 null로 설정
      setState(() {
        _applicationStatus = null;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 뒤로가기 시 지원 상태 변경 여부를 알림
        Navigator.pop(context, _applicationStatus != null);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('TO 상세 정보'),
          backgroundColor: Colors.blue[700],
          foregroundColor: Colors.white,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 헤더 (센터명 + 상태)
                    _buildHeader(),

                    // 상세 정보 카드
                    _buildDetailCard(),

                    // 지원하기 버튼
                    _buildApplyButton(),
                  ],
                ),
              ),
      ),
    );
  }

  /// 헤더 위젯
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
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
          // ✅ 마감 시간 정보 카드 (NEW!)
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
                        widget.to.formattedDeadline, // "10월 24일 18:00까지"
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
                        widget.to.deadlineStatus, // "3시간 남음" or "마감됨"
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

          // 기존 정보들
          _buildInfoRow(
            Icons.access_time,
            '근무 시간',
            widget.to.timeRange,
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            Icons.work_outline,
            '업무 유형',
            widget.to.workType,
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            Icons.people_outline,
            '모집 인원',
            '${widget.to.currentCount}/${widget.to.requiredCount}명',
            color: widget.to.currentCount >= widget.to.requiredCount
                ? Colors.red
                : Colors.green,
          ),

          if (widget.to.description != null &&
              widget.to.description!.isNotEmpty) ...[
            const Divider(height: 24),
            const Text(
              '📝 상세 설명',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.to.description!,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 정보 행 빌더
  Widget _buildInfoRow(IconData icon, String label, String value,
      {Color? color}) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: color ?? Colors.blue[700],
        ),
        const SizedBox(width: 12),
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
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color ?? Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 상태 배지
  Widget _buildStatusBadge() {
    final isAvailable = widget.to.isAvailable;
    final color = isAvailable ? Colors.green : Colors.red;
    final text = isAvailable ? '지원 가능' : '마감';
    final icon = isAvailable ? Icons.check_circle : Icons.cancel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// 지원하기 버튼 - 마감 시간 체크 추가 버전
  Widget _buildApplyButton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              // ✅ 마감 여부도 체크 (isDeadlinePassed 추가)
              onPressed: widget.to.isDeadlinePassed ||
                      _applicationStatus == 'PENDING' ||
                      _applicationStatus == 'CONFIRMED' ||
                      !widget.to.isAvailable
                  ? null
                  : _applyToTO,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.grey.shade600,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              // ✅ 버튼 텍스트도 마감 여부에 따라 변경
              child: _isApplying
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      widget.to.isDeadlinePassed
                          ? '마감됨' // ✅ NEW!
                          : _applicationStatus == 'PENDING'
                              ? '지원 완료 (승인 대기)'
                              : _applicationStatus == 'CONFIRMED'
                                  ? '확정됨'
                                  : !widget.to.isAvailable
                                      ? '마감'
                                      : '지원하기',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          
          // ✅ 마감된 경우 추가 안내 메시지 (버튼 아래에 추가)
          if (widget.to.isDeadlinePassed) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700], size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '지원 마감 시간이 지나 더 이상 지원할 수 없습니다',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 지원하기 처리 - 마감 시간 체크 추가 버전
  Future<void> _applyToTO() async {
    // ✅ 마감 시간 체크 추가
    if (widget.to.isDeadlinePassed) {
      ToastHelper.showWarning('지원 마감 시간이 지났습니다');
      return;
    }

    // 기존 유효성 검증들...
    if (!widget.to.isAvailable) {
      ToastHelper.showWarning('이미 인원이 마감되었습니다');
      return;
    }

    if (_applicationStatus != null) {
      ToastHelper.showWarning('이미 지원한 TO입니다');
      return;
    }

    // 확인 다이얼로그
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지원 확인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('이 TO에 지원하시겠습니까?'),
            const SizedBox(height: 12),
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
                    '${widget.to.timeRange} · ${widget.to.workType}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                  // ✅ 마감 시간도 표시
                  const Divider(height: 16),
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 14, color: Colors.orange[700]),
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

    if (confirm != true) return;

    // 지원 처리 로직
    setState(() => _isApplying = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }

      final success = await _firestoreService.applyToTO(
        toId: widget.to.id,
        uid: uid,
      );

      if (success) {
        setState(() {
          _applicationStatus = 'PENDING';
        });
        ToastHelper.showSuccess('지원이 완료되었습니다\n관리자의 승인을 기다려주세요');
        Navigator.pop(context, true);
      } else {
        ToastHelper.showError('지원에 실패했습니다');
      }
    } catch (e) {
      print('❌ 지원 실패: $e');
      ToastHelper.showError('지원 중 오류가 발생했습니다');
    } finally {
      if (mounted) {
        setState(() => _isApplying = false);
      }
    }
  }
}