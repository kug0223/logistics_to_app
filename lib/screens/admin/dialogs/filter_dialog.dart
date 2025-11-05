import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FilterDialog extends StatefulWidget {
  final String? selectedBusiness;
  final DateTimeRange? selectedDateRange;
  final List<String> businessNames;
  final Function(String?) onBusinessChanged;
  final Function(DateTimeRange?) onDateRangeChanged;

  const FilterDialog({
    super.key,
    this.selectedBusiness,
    this.selectedDateRange,
    required this.businessNames,
    required this.onBusinessChanged,
    required this.onDateRangeChanged,
  });

  @override
  State<FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<FilterDialog> {
  String? _tempBusiness;
  DateTimeRange? _tempDateRange;

  @override
  void initState() {
    super.initState();
    _tempBusiness = (widget.selectedBusiness == null || widget.selectedBusiness == 'ALL') 
      ? null 
      : widget.selectedBusiness;
    _tempDateRange = widget.selectedDateRange;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                border: Border(
                  bottom: BorderSide(color: Colors.blue[200]!),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.filter_list, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  const Text(
                    '필터',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _resetFilters,
                    child: const Text('초기화'),
                  ),
                ],
              ),
            ),

            // 필터 옵션들
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 사업장 필터
                  _buildFilterSection(
                    title: '사업장',
                    child: DropdownButtonFormField<String?>(
                      initialValue: _tempBusiness,
                      decoration: InputDecoration(
                        hintText: '전체',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('전체'),
                        ),
                        ...widget.businessNames.toSet().map((name) => DropdownMenuItem<String?>(
                          value: name,
                          child: Text(name),
                        )),
                      ],
                      onChanged: (String? value) {
                        setState(() {
                          _tempBusiness = value;
                        });
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 날짜 필터
                  _buildFilterSection(
                    title: '날짜 범위',
                    child: Column(
                      children: [
                        // 날짜 범위 표시
                        InkWell(
                          onTap: _selectDateRange,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[400]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today, size: 18, color: Colors.grey[700]),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _tempDateRange == null
                                        ? '전체 기간'
                                        : '${DateFormat('MM/dd').format(_tempDateRange!.start)} - ${DateFormat('MM/dd').format(_tempDateRange!.end)}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: _tempDateRange == null ? Colors.grey[600] : Colors.black87,
                                    ),
                                  ),
                                ),
                                if (_tempDateRange != null)
                                  IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      setState(() {
                                        _tempDateRange = null;
                                      });
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 12),
                        
                        // 🔥 빠른 날짜 선택 버튼
                        Row(
                          children: [
                            Expanded(
                              child: _buildQuickDateButton('오늘', 0),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildQuickDateButton('내일', 1),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildQuickDateButton('3일', 3),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildQuickDateButton('7일', 7),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 하단 버튼
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _applyFilters,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('적용'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection({
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  // 🔥 빠른 날짜 선택 버튼
  Widget _buildQuickDateButton(String label, int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    late final DateTimeRange targetRange;
    
    switch (label) {
      case '오늘':
        targetRange = DateTimeRange(start: today, end: today);
        break;
      case '내일':
        final tomorrow = today.add(const Duration(days: 1));
        targetRange = DateTimeRange(start: tomorrow, end: tomorrow);
        break;
      case '3일':
        // 오늘부터 3일 후까지
        targetRange = DateTimeRange(
          start: today,
          end: today.add(const Duration(days: 2)),  // 오늘 포함 3일
        );
        break;
      case '7일':
        // 오늘부터 7일 후까지
        targetRange = DateTimeRange(
          start: today,
          end: today.add(const Duration(days: 6)),  // 오늘 포함 7일
        );
        break;
      default:
        targetRange = DateTimeRange(start: today, end: today);
    }
    
    final isSelected = _tempDateRange != null &&
        _tempDateRange!.start == targetRange.start &&
        _tempDateRange!.end == targetRange.end;
    
    return OutlinedButton(
      onPressed: () {
        setState(() {
          _tempDateRange = targetRange;
        });
      },
      style: OutlinedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue[50] : null,
        side: BorderSide(
          color: isSelected ? Colors.blue[700]! : Colors.grey[400]!,
          width: isSelected ? 2 : 1,
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.blue[700] : Colors.grey[700],
        ),
      ),
    );
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2026),
      initialDateRange: _tempDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue[700]!,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _tempDateRange = picked;
      });
    }
  }

  void _resetFilters() {
    setState(() {
      _tempBusiness = null;
      _tempDateRange = null;
    });
  }

  void _applyFilters() {
    widget.onBusinessChanged(_tempBusiness);
    widget.onDateRangeChanged(_tempDateRange);
    Navigator.pop(context);
  }
}