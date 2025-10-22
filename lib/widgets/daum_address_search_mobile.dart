// ============================================
// daum_address_search_mobile.dart (Android/iOS) - 수동 입력으로 변경
// ============================================
import 'package:flutter/material.dart';
import 'daum_address_search.dart';

/// Mobile 플랫폼 구현체 - 수동 입력 다이얼로그
class DaumAddressSearchImpl {
  static Future<AddressResult?> searchAddress(BuildContext context) async {
    return _showManualInputDialog(context);
  }

  /// Android/iOS용 수동 입력 다이얼로그
  static Future<AddressResult?> _showManualInputDialog(BuildContext context) async {
    final addressController = TextEditingController();
    final zoneController = TextEditingController();
    
    return showDialog<AddressResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.location_on, color: Colors.blue),
            const SizedBox(width: 8),
            const Text('주소 입력'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: zoneController,
                decoration: const InputDecoration(
                  labelText: '우편번호',
                  hintText: '예: 06000',
                  prefixIcon: Icon(Icons.markunread_mailbox),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: '주소',
                  hintText: '예: 서울특별시 강남구 테헤란로 123',
                  prefixIcon: Icon(Icons.home),
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Android에서는 수동 입력만 가능합니다.\n웹 브라우저에서는 자동 검색이 지원됩니다.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              if (addressController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('주소를 입력해주세요'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              final result = AddressResult(
                fullAddress: addressController.text.trim(),
                roadAddress: addressController.text.trim(),
                jibunAddress: '',
                zonecode: zoneController.text.trim(),
                latitude: null,
                longitude: null,
              );
              
              Navigator.pop(context, result);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}