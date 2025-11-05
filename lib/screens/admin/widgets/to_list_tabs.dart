import 'package:flutter/material.dart';

/// TO 목록 탭 위젯 (진행중/마감됨)
class TOListTabs extends StatelessWidget {
  final String selectedTab;
  final ValueChanged<String> onTabChanged;

  const TOListTabs({
    super.key,
    required this.selectedTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (selectedTab != 'ACTIVE') {
                  onTabChanged('ACTIVE');
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selectedTab == 'ACTIVE' ? const Color(0xFF1E88E5) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: selectedTab == 'ACTIVE'
                      ? [
                          BoxShadow(
                            color: const Color(0xFF1E88E5).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  '진행중',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: selectedTab == 'ACTIVE' ? Colors.white : const Color(0xFF757575),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (selectedTab != 'CLOSED') {
                  onTabChanged('CLOSED');
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selectedTab == 'CLOSED' ? const Color(0xFF1E88E5) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: selectedTab == 'CLOSED'
                      ? [
                          BoxShadow(
                            color: const Color(0xFF1E88E5).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  '마감됨',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: selectedTab == 'CLOSED' ? Colors.white : const Color(0xFF757575),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}