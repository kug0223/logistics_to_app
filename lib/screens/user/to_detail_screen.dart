import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/to_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';

/// TO 상세 화면
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
  bool _isApplying = false;
  bool _hasApplied = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkIfApplied();
  }

  /// 이미 지원했는지 확인
  Future<void> _checkIfApplied() async {
    print('🔍 _checkIfApplied 시작');
    
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;

    print('🔍 현재 사용자 UID: $uid');
    print('🔍 현재 TO ID: ${widget.to.id}');

    if (uid == null) {
      print('❌ UID가 null입니다');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final myApps = await _firestoreService.getMyApplications(uid);
      print('✅ 내 지원 내역 개수: ${myApps.length}');
      
      for (var app in myApps) {
        print('  - TO ID: ${app.toId}, 상태: ${app.status}');
      }
      
      final applied = myApps.any((app) =>
          app.toId == widget.to.id &&
          (app.status == 'PENDING' || app.status == 'CONFIRMED'));

      print('✅ 지원 여부: $applied');

      setState(() {
        _hasApplied = applied;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 에러 발생: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 뒤로가기 시 true 반환 (지원 상태를 결과로 전달)
        Navigator.pop(context, _hasApplied);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('TO 상세 정보'),
          backgroundColor: Colors.blue[700],
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
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
                  widget.to.centerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _buildStatusBadge(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.to.workType,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
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
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📋 근무 정보',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),

          _buildInfoRow(
            Icons.calendar_today,
            '날짜',
            '${widget.to.formattedDate} (${widget.to.weekday})',
          ),

          const Divider(height: 24),

          _buildInfoRow(
            Icons.access_time,
            '시간',
            widget.to.timeRange,
          ),

          const Divider(height: 24),

          _buildInfoRow(
            Icons.people,
            '모집 인원',
            '${widget.to.requiredCount}명',
          ),

          const Divider(height: 24),

          _buildInfoRow(
            Icons.person_add,
            '현재 지원자',
            '${widget.to.currentCount}명',
          ),

          const Divider(height: 24),

          _buildInfoRow(
            Icons.event_available,
            '남은 자리',
            '${widget.to.remainingCount}명',
            color: widget.to.isAvailable ? Colors.green : Colors.red,
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

  /// 지원하기 버튼
  Widget _buildApplyButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton(
        onPressed: _isLoading
            ? null
            : (_hasApplied || !widget.to.isAvailable ? null : _handleApply),
        style: ElevatedButton.styleFrom(
          backgroundColor: _hasApplied
              ? Colors.grey[400]
              : (widget.to.isAvailable ? Colors.blue[700] : Colors.grey[400]),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
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
                _hasApplied
                    ? '✅ 지원 완료 (승인 대기 중)'
                    : (widget.to.isAvailable ? '지원하기' : '마감됨'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  /// 지원하기 처리
  Future<void> _handleApply() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;

    if (uid == null) {
      ToastHelper.showError('로그인이 필요합니다.');
      return;
    }

    // 확인 다이얼로그
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지원 확인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('이 TO에 지원하시겠습니까?'),
            const SizedBox(height: 12),
            Text(
              '센터: ${widget.to.centerName}',
              style: const TextStyle(fontSize: 14),
            ),
            Text(
              '날짜: ${widget.to.formattedDate}',
              style: const TextStyle(fontSize: 14),
            ),
            Text(
              '시간: ${widget.to.timeRange}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              '※ 관리자 승인 후 확정됩니다.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange,
                fontWeight: FontWeight.bold,
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
            child: const Text('지원하기'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isApplying = true;
    });

    final success = await _firestoreService.applyToTO(widget.to.id, uid);

    setState(() {
      _isApplying = false;
    });

    if (success) {
      setState(() {
        _hasApplied = true;
      });
    }
  }
}