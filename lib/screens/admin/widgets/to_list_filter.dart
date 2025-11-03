import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// TO 목록 필터 섹션
class TOListFilter extends StatelessWidget {
  final DateTime? selectedDate;
  final String selectedBusiness;
  final List<String> businessNames;
  final VoidCallback onSelectDate;
  final VoidCallback onClearDate;
  final ValueChanged<String> onBusinessChanged;

  const TOListFilter({
    Key? key,
    required this.selectedDate,
    required this.selectedBusiness,
    required this.businessNames,
    required this.onSelectDate,
    required this.onClearDate,
    required this.onBusinessChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 날짜 필터
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSelectDate,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    selectedDate != null
                        ? DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(selectedDate!)
                        : '날짜 선택',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
              if (selectedDate != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onClearDate,
                  icon: const Icon(Icons.clear),
                  tooltip: '날짜 필터 해제',
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          
          // 사업장 필터
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildBusinessFilterChip(context, '전체', 'ALL'),
                const SizedBox(width: 8),
                ...businessNames.map((name) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildBusinessFilterChip(context, name, name),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessFilterChip(BuildContext context, String label, String value) {
    final isSelected = selectedBusiness == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onBusinessChanged(value),
      backgroundColor: Colors.white,
      selectedColor: Colors.blue[100],
      checkmarkColor: Colors.blue[700],
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue[900] : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected ? Colors.blue[700]! : Colors.grey[300]!,
        width: isSelected ? 2 : 1,
      ),
    );
  }
}