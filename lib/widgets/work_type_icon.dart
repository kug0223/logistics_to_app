import 'package:flutter/material.dart';
import '../models/business_work_type_model.dart';

/// 업무 유형 아이콘/이모지 렌더링 유틸리티
class WorkTypeIcon {
  /// 아이콘 또는 이모지를 렌더링 (큰 사이즈)
  static Widget build(
    BusinessWorkTypeModel workType, {
    Color color = Colors.white,
    double size = 20,
  }) {
    return buildFromString(
      workType.icon,
      color: color,
      size: size,
    );
  }

  /// 아이콘 또는 이모지를 렌더링 (작은 사이즈 - 드롭다운용)
  static Widget buildSmall(
    BusinessWorkTypeModel workType, {
    double size = 16,
  }) {
    return buildFromString(
      workType.icon,
      color: Colors.white,
      size: size,
    );
  }

  /// 문자열로부터 아이콘 렌더링 (공통)
  static Widget buildFromString(
    String iconString, {
    Color color = Colors.white,
    double size = 20,
  }) {
    // 이모지 체크 (유니코드 범위)
    if (_isEmoji(iconString)) {
      return Text(
        iconString,
        style: TextStyle(fontSize: size),
      );
    }
    
    // Material 아이콘
    final iconData = _getIconData(iconString);
    return Icon(
      iconData,
      color: color,
      size: size,
    );
  }

  /// 이모지 여부 확인
  static bool _isEmoji(String text) {
    if (text.isEmpty) return false;
    
    final firstChar = text.runes.first;
    
    // 이모지 유니코드 범위
    return (firstChar >= 0x1F300 && firstChar <= 0x1F9FF) || // 기타 심볼
           (firstChar >= 0x2600 && firstChar <= 0x26FF) ||   // 기타 심볼
           (firstChar >= 0x2700 && firstChar <= 0x27BF) ||   // Dingbats
           (firstChar >= 0xFE00 && firstChar <= 0xFE0F) ||   // Variation Selectors
           (firstChar >= 0x1F600 && firstChar <= 0x1F64F) || // 이모티콘
           (firstChar >= 0x1F680 && firstChar <= 0x1F6FF) || // 교통/지도 심볼
           (firstChar >= 0x1F900 && firstChar <= 0x1F9FF);   // 보조 심볼
  }

  /// Material 아이콘 이름 → IconData 변환
  static IconData _getIconData(String iconName) {
    // 아이콘 매핑 (자주 사용하는 것들)
    const iconMap = {
      'work': Icons.work,
      'business': Icons.business,
      'local_shipping': Icons.local_shipping,
      'inventory': Icons.inventory,
      'category': Icons.category,
      'shopping_cart': Icons.shopping_cart,
      'warehouse': Icons.warehouse,
      'factory': Icons.factory,
      'construction': Icons.construction,
      'handyman': Icons.handyman,
      'build': Icons.build,
      'cleaning_services': Icons.cleaning_services,
      'assignment': Icons.assignment,
      'description': Icons.description,
      'list_alt': Icons.list_alt,
      'check_box': Icons.check_box,
      'archive': Icons.archive,
      'unarchive': Icons.unarchive,
      'inventory_2': Icons.inventory_2,
      'move_to_inbox': Icons.move_to_inbox,
      'all_inbox': Icons.all_inbox,
      'storage': Icons.storage,
      'package': Icons.inbox, // package 아이콘 대체
      'forklift': Icons.local_shipping, // forklift 대체
    };

    return iconMap[iconName] ?? Icons.work;
  }

  /// 색상 파싱
  static Color parseColor(String? colorString) {
    if (colorString == null || colorString.isEmpty) {
      return Colors.blue;
    }
    
    try {
      return Color(int.parse(colorString.replaceFirst('#', '0xFF')));
    } catch (e) {
      return Colors.blue;
    }
  }
}