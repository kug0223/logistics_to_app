import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/theme_provider.dart';
import 'all_to_list_screen.dart';
import '../../utils/dialog_helper.dart';
import 'my_schedule_screen.dart';
import 'attendance_check_screen.dart';
import 'my_schedule_requests_screen.dart';

class UserHomeScreen extends StatelessWidget {
  const UserHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alfit(알핏)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final confirmed = await DialogHelper.showLogoutConfirm(context);
              
              if (confirmed && context.mounted) {
                context.read<ThemeProvider>().reset();
                context.read<UserProvider>().signOut();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(  // ⭐ 전체를 LayoutBuilder로 감싸기
          builder: (context, constraints) {
            final screenWidth = MediaQuery.of(context).size.width;
            final scale = screenWidth < 360 ? 0.85 : screenWidth < 400 ? 0.9 : 1.0;
            final spacing = screenWidth < 360 ? 12.0 : 16.0;
            
            return Padding(
              padding: EdgeInsets.all(24.0 * scale),  // ⭐ 패딩도 스케일 적용
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 환영 메시지 - 반응형
                  Container(
                    padding: EdgeInsets.all(20 * scale),  // ⭐ 스케일 적용
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).primaryColor,
                          Theme.of(context).primaryColor.withOpacity(0.7),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '안녕하세요! 👋',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20 * scale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8 * scale),
                        Text(
                          '${userProvider.currentUser?.name ?? '사용자'}님',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24 * scale,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 4 * scale),
                        Text(
                          userProvider.currentUser?.email ?? '',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14 * scale,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 32 * scale),  // ⭐ 스케일 적용

                  // 메뉴 카드들 - 항상 2열, 크기만 반응형
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 2,  // ⭐ 항상 2열 고정
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: spacing,
                      children: [
                        _buildMenuCard(
                          context,
                          scale: scale,  // ⭐ scale 전달
                          icon: Icons.warehouse_rounded,
                          title: '근무 지원하기',
                          subtitle: '사업장 선택',
                          color: Colors.blue,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const AllTOListScreen(),
                              ),
                            );
                          },
                        ),
                        _buildMenuCard(
                          context,
                          scale: scale,
                          icon: Icons.calendar_month,
                          title: '근무 스케줄',
                          subtitle: '일정 한눈에 보기',
                          color: Colors.purple,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const MyScheduleScreen(),
                              ),
                            );
                          },
                        ),
                        _buildMenuCard(
                          context,
                          scale: scale,
                          icon: Icons.access_time_outlined,
                          title: '출퇴근 체크',
                          subtitle: '근무 시간 기록',
                          color: Colors.purple,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const AttendanceCheckScreen(),
                              ),
                            );
                          },
                        ),
                        _buildMenuCard(
                          context,
                          scale: scale,
                          icon: Icons.person_outline,
                          title: '내 정보',
                          subtitle: '프로필 확인',
                          color: Colors.orange,
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('준비 중입니다')),
                            );
                          },
                        ),
                        _buildMenuCard(
                          context,
                          scale: scale,
                          icon: Icons.settings_outlined,
                          title: '설정',
                          subtitle: '앱 설정',
                          color: Colors.grey,
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('준비 중입니다')),
                            );
                          },
                        ),
                        _buildMenuCard(  // ⭐ 신규 추가!
                          context,
                          scale: scale,
                          icon: Icons.edit_calendar,
                          title: '내 요청 내역',
                          subtitle: '스케줄 변경 요청',
                          color: Colors.teal,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const MyScheduleRequestsScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // 반응형 메뉴 카드
  Widget _buildMenuCard(
    BuildContext context, {
    required double scale,  // ⭐ scale 파라미터 추가
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(16.0 * scale),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(12 * scale),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 32 * scale,
                  color: color,
                ),
              ),
              SizedBox(height: 12 * scale),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16 * scale,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 4 * scale),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12 * scale,
                  color: Colors.grey[600],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}