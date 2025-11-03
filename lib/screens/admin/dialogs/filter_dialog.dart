import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FilterDialog extends StatefulWidget {
  final String? selectedBusiness;
  final String? selectedStatus;
  final DateTimeRange? selectedDateRange;
  final List<String> businessNames;
  final Function(String?) onBusinessChanged;
  final Function(String?) onStatusChanged;
  final Function(DateTimeRange?) onDateRangeChanged;

  const FilterDialog({
    Key? key,
    this.selectedBusiness,
    this.selectedStatus,
    this.selectedDateRange,
    required this.businessNames,
    required this.onBusinessChanged,
    required this.onStatusChanged,
    required this.onDateRangeChanged,
  }) : super(key: key);

  @override
  State<FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<FilterDialog> {
  String? _tempBusiness;
  String? _tempStatus;
  DateTimeRange? _tempDateRange;

  @override
  void initState() {
    super.initState();
    _tempBusiness = (widget.selectedBusiness == null || widget.selectedBusiness == 'ALL') 
      ? null 
      : widget.selectedBusiness;
    _tempStatus = (widget.selectedStatus == null || widget.selectedStatus == 'ALL') 
      ? null 
      : widget.selectedStatus;
    _tempDateRange = widget.selectedDateRange;
  }

  @override
  Widget build(BuildContext context) {
    print('🔍 _tempBusiness: $_tempBusiness');
    print('🔍 _tempStatus: $_tempStatus');
    print('🔍 businessNames: ${widget.businessNames}');
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
                    child: DropdownButtonFormField<String?>(  // 🔥 String? 타입
                      value: _tempBusiness,
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
                        // 🔥 중복 제거
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

                  // 상태 필터
                  _buildFilterSection(
                    title: '상태',
                    child: DropdownButtonFormField<String>(
                      value: _tempStatus == '' ? null : _tempStatus,  // 🔥 빈 문자열 처리
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
                      items: const [
                        DropdownMenuItem<String>(  // 🔥 타입 명시
                          value: null,
                          child: Text('전체'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'CONFIRMED',
                          child: Text('확정됨'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'PENDING',
                          child: Text('대기중'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'FULL',
                          child: Text('인원충족'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _tempStatus = value;
                        });
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 날짜 필터
                  _buildFilterSection(
                    title: '날짜 범위',
                    child: InkWell(
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
      _tempStatus = null;
      _tempDateRange = null;
    });
  }

  void _applyFilters() {
    widget.onBusinessChanged(_tempBusiness);
    widget.onStatusChanged(_tempStatus);
    widget.onDateRangeChanged(_tempDateRange);
    Navigator.pop(context);
  }
}