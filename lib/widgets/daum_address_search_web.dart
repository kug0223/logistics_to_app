// ============================================
// daum_address_search_web.dart (Web 전용) - 수동 입력 방식 (에러 처리 강화)
// ============================================
import 'package:flutter/material.dart';
import 'daum_address_search.dart';

/// Web 플랫폼 구현체 - 수동 입력 다이얼로그
class DaumAddressSearchImpl {
  static Future<AddressResult?> searchAddress(BuildContext context) async {
    return _showManualInputDialog(context);
  }

  /// 웹용 수동 입력 다이얼로그
  static Future<AddressResult?> _showManualInputDialog(BuildContext context) async {
    final addressController = TextEditingController();
    final zoneController = TextEditingController();
    
    return showDialog<AddressResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.location_on,
                      color: Colors.blue.shade700,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '주소 입력',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: '닫기',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // 안내 메시지
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.amber.shade200,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.amber.shade900,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '웹 테스트용 임시 직접 입력 모드입니다.\n시/도부터 상세주소까지 정확하게 입력해주세요.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.amber.shade900,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // 우편번호 입력
              TextField(
                controller: zoneController,
                decoration: InputDecoration(
                  labelText: '우편번호 (선택)',
                  hintText: '예: 06000',
                  prefixIcon: const Icon(Icons.markunread_mailbox),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  helperText: '선택사항입니다',
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
              const SizedBox(height: 16),
              
              // 주소 입력
              TextField(
                controller: addressController,
                decoration: InputDecoration(
                  labelText: '주소 *',
                  hintText: '예: 서울특별시 강남구 테헤란로 123',
                  prefixIcon: const Icon(Icons.home),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  helperText: '* 필수 입력 항목',
                  helperStyle: const TextStyle(color: Colors.red),
                ),
                maxLines: 3,
                autofocus: true,
                // 엔터키로 확인 가능
                onSubmitted: (_) => _handleConfirm(context, addressController, zoneController),
              ),
              const SizedBox(height: 8),
              
              // 입력 예시
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline, 
                          color: Colors.blue.shade700, 
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '입력 예시',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• 서울특별시 강남구 테헤란로 123\n'
                      '• 경기도 성남시 분당구 판교역로 235\n'
                      '• 부산광역시 해운대구 마린시티1로 30',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // 하단 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      '취소',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _handleConfirm(context, addressController, zoneController),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text(
                      '확인',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// 확인 버튼 처리
  static void _handleConfirm(
    BuildContext context,
    TextEditingController addressController,
    TextEditingController zoneController,
  ) {
    final address = addressController.text.trim();
    final zonecode = zoneController.text.trim();
    
    // 유효성 검증
    if (address.isEmpty) {
      _showErrorSnackBar(context, '주소를 입력해주세요');
      return;
    }
    
    if (address.length < 5) {
      _showErrorSnackBar(context, '주소가 너무 짧습니다. 정확한 주소를 입력해주세요');
      return;
    }
    
    // 기본적인 주소 형식 검증 (시/도 포함 확인)
    final hasCity = address.contains('시') || 
                    address.contains('도') || 
                    address.contains('특별') ||
                    address.contains('광역');
    
    if (!hasCity) {
      _showErrorSnackBar(context, '시/도 정보를 포함한 전체 주소를 입력해주세요\n예: 서울특별시 강남구 테헤란로 123');
      return;
    }
    
    // 우편번호 검증 (입력했을 경우)
    if (zonecode.isNotEmpty && zonecode.length < 5) {
      _showErrorSnackBar(context, '우편번호는 5~6자리여야 합니다');
      return;
    }
    
    // 성공 - AddressResult 생성
    final result = AddressResult(
      fullAddress: address,
      roadAddress: address,
      jibunAddress: '',
      zonecode: zonecode,
      latitude: null,  // 수동 입력이므로 좌표는 null
      longitude: null,
    );
    
    print('✅ 주소 입력 완료: $address');
    if (zonecode.isNotEmpty) {
      print('✅ 우편번호: $zonecode');
    }
    print('⚠️ 좌표 정보 없음 (수동 입력 모드)');
    
    Navigator.pop(context, result);
  }
  
  /// 에러 SnackBar 표시
  static void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: '확인',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }
}