import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/core/business_work_type_model.dart';
import '../../utils/toast_helper.dart';
import '../../utils/labor_standards.dart';
import '../../utils/responsive_helper.dart';
import '../../models/work_detail_input.dart'; 
import '../work_type_icon.dart';
import '../../utils/format_helper.dart';

// ============================================================
// 🎨 업무 추가 다이얼로그 (공통)
// ============================================================

class WorkDetailDialog {
  /// 업무 추가 다이얼로그 표시
  static Future<WorkDetailInput?> showAddDialog({
    required BuildContext context,
    required List<BusinessWorkTypeModel> businessWorkTypes,
  }) async {
    BusinessWorkTypeModel? selectedWorkType;
    String selectedWageType = 'hourly';
    String? startTime;
    String? endTime;
    final wageController = TextEditingController();
    final countController = TextEditingController();

    return await showDialog<WorkDetailInput>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('업무 추가'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 업무 유형 선택
                  Text(
                    '업무 유형', 
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  DropdownButtonFormField<BusinessWorkTypeModel>(
                    isExpanded: true,
                    initialValue: selectedWorkType,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '업무 선택',
                    ),
                    items: businessWorkTypes.map((workType) {
                      return DropdownMenuItem<BusinessWorkTypeModel>(
                        value: workType,
                        child: Row(
                          children: [
                            Container(
                              width: ResponsiveHelper.iconSize(context, 32),
                              height: ResponsiveHelper.iconSize(context, 32),
                              decoration: BoxDecoration(
                                color: FormatHelper.parseColor(workType.backgroundColor ?? '#2196F3'),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: WorkTypeIcon.buildSmall(workType),
                              ),
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                            Flexible(
                              child: Text(
                                workType.name,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedWorkType = value);
                    },
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  
                  // ✅ 급여 타입 선택
                  Text(
                    '급여 타입', 
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  Row(
                    children: [
                      Expanded(
                        child: _buildWageTypeButton(
                          context: context,
                          label: '시급',
                          value: 'hourly',
                          selectedValue: selectedWageType,
                          onTap: () {
                            setDialogState(() {
                              selectedWageType = 'hourly';
                            });
                          },
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Expanded(
                        child: _buildWageTypeButton(
                          context: context,
                          label: '일급',
                          value: 'daily',
                          selectedValue: selectedWageType,
                          onTap: () {
                            setDialogState(() {
                              selectedWageType = 'daily';
                            });
                          },
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Expanded(
                        child: _buildWageTypeButton(
                          context: context,
                          label: '월급',
                          value: 'monthly',
                          selectedValue: selectedWageType,
                          onTap: () {
                            setDialogState(() {
                              selectedWageType = 'monthly';
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                  // 근무 시간
                  Text(
                    '근무 시간', 
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: startTime,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: '시작',
                          ),
                          items: FormatHelper.generateTimeList().map((time) {
                            return DropdownMenuItem(value: time, child: Text(time));
                          }).toList(),
                          onChanged: (value) => setDialogState(() => startTime = value),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 8),
                        ),
                        child: Text(
                          '~', 
                          style: ResponsiveHelper.titleStyle(context),
                        ),
                      ),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: endTime,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: '종료',
                          ),
                          items: FormatHelper.generateTimeList().map((time) {
                            return DropdownMenuItem(value: time, child: Text(time));
                          }).toList(),
                          onChanged: (value) => setDialogState(() => endTime = value),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                  // 급여 입력
                  Text(
                    _getWageLabelFromType(selectedWageType),
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  TextFormField(
                    controller: wageController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      // ✅ 천단위 콤마 포맷터
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        if (newValue.text.isEmpty) {
                          return newValue;
                        }
                        
                        final number = int.tryParse(newValue.text.replaceAll(',', ''));
                        if (number == null) {
                          return oldValue;
                        }
                        
                        final formatted = number.toString().replaceAllMapped(
                          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                          (Match m) => '${m[1]},',
                        );
                        
                        return TextEditingValue(
                          text: formatted,
                          selection: TextSelection.collapsed(offset: formatted.length),
                        );
                      }),
                    ],
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: '금액을 입력하세요.',
                      suffixText: '원',
                      helperText: selectedWageType == 'hourly'
                          ? '2025년 최저시급: ${LaborStandards.formatCurrencyWithUnit(LaborStandards.currentMinimumWage)}'
                          : null,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                  // 필요 인원
                  Text(
                    '필요 인원', 
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  TextFormField(
                    controller: countController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '필요 인원 수 입력하세요.',
                      suffixText: '명',
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
                  if (selectedWorkType == null ||
                      startTime == null ||
                      endTime == null ||
                      wageController.text.isEmpty ||
                      countController.text.isEmpty) {
                    ToastHelper.showError('모든 정보를 입력해주세요');
                    return;
                  }

                  final wage = int.tryParse(wageController.text.replaceAll(',', ''));
                  final count = int.tryParse(countController.text);

                  if (wage == null || wage <= 0) {
                    ToastHelper.showError('유효한 급여를 입력해주세요');
                    return;
                  }

                  if (count == null || count <= 0) {
                    ToastHelper.showError('유효한 인원 수를 입력해주세요');
                    return;
                  }

                  Navigator.pop(
                    context,
                    WorkDetailInput(
                      workType: selectedWorkType!.name,
                      workTypeIcon: selectedWorkType!.icon,
                      workTypeColor: selectedWorkType!.color ?? '#FFFFFF',
                      workTypeBackgroundColor: selectedWorkType!.backgroundColor,
                      wage: wage,
                      requiredCount: count,
                      startTime: startTime,
                      endTime: endTime,
                      wageType: selectedWageType,
                    ),
                  );
                },
                child: const Text('추가'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // 🛠️ 헬퍼 함수들
  // ============================================================

  /// 급여 타입에 따른 라벨 반환
  static String _getWageLabelFromType(String wageType) {
    switch (wageType) {
      case 'hourly':
        return '시급';
      case 'daily':
        return '일급';
      case 'monthly':
        return '월급';
      default:
        return '급여';
    }
  }

  /// 급여 타입 선택 버튼
  static Widget _buildWageTypeButton({
    required BuildContext context,
    required String label,
    required String value,
    required String selectedValue,
    required VoidCallback onTap,
  }) {
    final isSelected = value == selectedValue;
    
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 12),
        ),
        decoration: BoxDecoration(
          color: isSelected 
              ? Theme.of(context).primaryColor.withOpacity(0.1)
              : Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: isSelected 
                ? Theme.of(context).primaryColor
                : Theme.of(context).dividerColor,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: ResponsiveHelper.bodyStyle(
              context,
              color: isSelected 
                  ? Theme.of(context).primaryColor
                  : Theme.of(context).textTheme.bodyMedium?.color,
            ).copyWith(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}