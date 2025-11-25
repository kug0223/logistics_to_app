import 'package:flutter/material.dart';

/// 공통 다이얼로그 헬퍼
class DialogHelper {
  /// 확인 다이얼로그 (예/아니오)
  /// 
  /// 사용 예:
  /// ```dart
  /// final confirmed = await DialogHelper.showConfirm(
  ///   context,
  ///   title: '삭제',
  ///   message: '정말 삭제하시겠습니까?',
  ///   confirmText: '삭제',
  ///   confirmColor: Colors.red,
  /// );
  /// if (confirmed) { ... }
  /// ```
  static Future<bool> showConfirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = '확인',
    String cancelText = '취소',
    Color? confirmColor,
    IconData? icon,
    Color? iconColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: icon != null
            ? Row(
                children: [
                  Icon(icon, color: iconColor ?? confirmColor),
                  const SizedBox(width: 12),
                  Text(title),
                ],
              )
            : Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: confirmColor != null
                ? ElevatedButton.styleFrom(
                    backgroundColor: confirmColor,
                    foregroundColor: Colors.white,
                  )
                : null,
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 위험한 작업 확인 다이얼로그 (빨간색 강조)
  /// 
  /// 사용 예:
  /// ```dart
  /// final confirmed = await DialogHelper.showDangerConfirm(
  ///   context,
  ///   title: '삭제',
  ///   message: '이 작업은 되돌릴 수 없습니다.',
  /// );
  /// ```
  static Future<bool> showDangerConfirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = '삭제',
    String cancelText = '취소',
  }) {
    return showConfirm(
      context,
      title: title,
      message: message,
      confirmText: confirmText,
      cancelText: cancelText,
      confirmColor: Colors.red,
      icon: Icons.warning,
      iconColor: Colors.red[700],
    );
  }

  /// 알림 다이얼로그 (확인만)
  /// 
  /// 사용 예:
  /// ```dart
  /// await DialogHelper.showAlert(
  ///   context,
  ///   title: '오류',
  ///   message: '권한이 없습니다.',
  /// );
  /// ```
  static Future<void> showAlert(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = '확인',
    IconData? icon,
    Color? iconColor,
  }) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: icon != null
            ? Row(
                children: [
                  Icon(icon, color: iconColor),
                  const SizedBox(width: 12),
                  Text(title),
                ],
              )
            : Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  /// 에러 알림 다이얼로그
  static Future<void> showError(
    BuildContext context, {
    String title = '오류',
    required String message,
  }) {
    return showAlert(
      context,
      title: title,
      message: message,
      icon: Icons.error_outline,
      iconColor: Colors.red[700],
    );
  }

  /// 성공 알림 다이얼로그
  static Future<void> showSuccess(
    BuildContext context, {
    String title = '완료',
    required String message,
  }) {
    return showAlert(
      context,
      title: title,
      message: message,
      icon: Icons.check_circle_outline,
      iconColor: Colors.green[700],
    );
  }

  /// 정보 알림 다이얼로그
  static Future<void> showInfo(
    BuildContext context, {
    String title = '안내',
    required String message,
  }) {
    return showAlert(
      context,
      title: title,
      message: message,
      icon: Icons.info_outline,
      iconColor: Colors.blue[700],
    );
  }

  /// 로딩 다이얼로그 표시
  /// 
  /// 사용 예:
  /// ```dart
  /// DialogHelper.showLoading(context, message: '처리 중...');
  /// // 작업 수행
  /// Navigator.pop(context); // 닫기
  /// ```
  static void showLoading(
    BuildContext context, {
    String message = '처리 중...',
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(message),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 선택 다이얼로그 (여러 옵션 중 선택)
  /// 
  /// 사용 예:
  /// ```dart
  /// final selected = await DialogHelper.showOptions<String>(
  ///   context,
  ///   title: '정렬',
  ///   options: ['최신순', '오래된순', '이름순'],
  /// );
  /// if (selected != null) { ... }
  /// ```
  static Future<T?> showOptions<T>(
    BuildContext context, {
    required String title,
    required List<T> options,
    String Function(T)? optionLabel,
  }) {
    return showDialog<T>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((option) {
            final label = optionLabel?.call(option) ?? option.toString();
            return ListTile(
              title: Text(label),
              onTap: () => Navigator.pop(context, option),
            );
          }).toList(),
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

  /// 커스텀 콘텐츠 다이얼로그
  /// 
  /// 사용 예:
  /// ```dart
  /// await DialogHelper.showCustom(
  ///   context,
  ///   title: '상세 정보',
  ///   content: MyCustomWidget(),
  /// );
  /// ```
  static Future<T?> showCustom<T>(
    BuildContext context, {
    String? title,
    required Widget content,
    List<Widget>? actions,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => AlertDialog(
        title: title != null ? Text(title) : null,
        content: content,
        actions: actions,
      ),
    );
  }

  /// 로그아웃 확인 다이얼로그 (자주 쓰는 패턴)
  static Future<bool> showLogoutConfirm(BuildContext context) {
    return showConfirm(
      context,
      title: '로그아웃',
      message: '로그아웃 하시겠습니까?',
      confirmText: '로그아웃',
      confirmColor: Colors.red,
    );
  }

  /// 삭제 확인 다이얼로그 (자주 쓰는 패턴)
  static Future<bool> showDeleteConfirm(
    BuildContext context, {
    String itemName = '항목',
    String? additionalMessage,
  }) {
    final message = additionalMessage != null
        ? '$itemName을(를) 삭제하시겠습니까?\n\n$additionalMessage'
        : '$itemName을(를) 삭제하시겠습니까?';

    return showDangerConfirm(
      context,
      title: '삭제',
      message: message,
      confirmText: '삭제',
    );
  }

  /// 취소 확인 다이얼로그 (자주 쓰는 패턴)
  static Future<bool> showCancelConfirm(
    BuildContext context, {
    String title = '취소',
    String message = '정말 취소하시겠습니까?',
  }) {
    return showConfirm(
      context,
      title: title,
      message: message,
      confirmText: '취소하기',
      confirmColor: Colors.orange,
    );
  }
  /// 서류 미등록 안내 다이얼로그 (서류 관리로 이동)
  /// 
  /// 사용 예:
  /// ```dart
  /// final shouldNavigate = await DialogHelper.showDocumentRequired(
  ///   context,
  ///   title: '서류 등록 필요',
  ///   missingDocuments: ['신분증', '통장사본'],
  /// );
  /// if (shouldNavigate) {
  ///   // 서류 관리 화면으로 이동
  /// }
  /// ```
  static Future<bool> showDocumentRequired(
    BuildContext context, {
    required String title,
    required List<String> missingDocuments,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange[700],
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '지원하기 전에 서류 등록이 필요합니다.',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),
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
                      Icon(
                        Icons.description_outlined,
                        size: 20,
                        color: Colors.orange[900],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '미등록 항목:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[900],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...missingDocuments.map((doc) => Padding(
                        padding: const EdgeInsets.only(left: 8, top: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.circle,
                              size: 6,
                              color: Colors.orange[700],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              doc,
                              style: TextStyle(
                                color: Colors.orange[900],
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '설정 > 내 서류 관리에서\n서류를 등록해주세요.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('서류 등록하기'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}