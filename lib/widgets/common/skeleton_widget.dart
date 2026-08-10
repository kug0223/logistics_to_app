import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../utils/responsive_helper.dart';

// ─── 기본 블록 ────────────────────────────────────────────────────────────────

/// 단일 shimmer 박스. 모든 스켈레톤의 빌딩 블록.
class _Box extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _Box({
    required this.width,
    required this.height,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// 화면 너비 전체를 채우는 shimmer 박스.
class _FullBox extends StatelessWidget {
  final double height;

  const _FullBox({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

// ─── Shimmer 래퍼 ─────────────────────────────────────────────────────────────

/// [child] 전체에 shimmer 애니메이션을 씌운다.
/// 다크모드를 감지해 베이스/하이라이트 색상을 자동 조정.
class AppShimmer extends StatelessWidget {
  final Widget child;

  const AppShimmer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0),
      highlightColor: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5),
      child: child,
    );
  }
}

// ─── 공고 목록 스켈레톤 (UserTOCard 접힌 상태) ────────────────────────────────

class TOListSkeleton extends StatelessWidget {
  const TOListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // TO카드 높이(~260dp) + margin(12dp) ≈ 272dp 기준, +2로 마지막 카드 반쪽 노출
    final s = ResponsiveHelper.spacing(context, 1);
    final availableHeight = MediaQuery.sizeOf(context).height;
    final cardHeight = s * 272;
    final count = (availableHeight / cardHeight).ceil() + 2;

    return AppShimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.all(s * 16),
        itemCount: count,
        itemBuilder: (_, __) => const _TOCardSkeleton(),
      ),
    );
  }
}

/// 실제 UserTOCard 접힌(collapsed) 상태와 1:1 대응
/// Stack: 컬러바(left spacing(5)) + 콘텐츠
///   ① topRow: 타입배지 + location아이콘 + 위치텍스트 + 즐겨찾기
///   ② 공고 제목 (maxLines:2 → 두 줄 스켈레톤)
///   ③ dateTimeRow: calendar아이콘 + 날짜
///   ④ businessRow: store아이콘 + 사업장명 + timeAgo
///   ⑤ 구분선
///   ⑥ wageRow: 급여pill + 금액
///   ⑦ actionRow: 상세보기 + 지원하기 버튼
///   ⑧ expandBar
class _TOCardSkeleton extends StatelessWidget {
  const _TOCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final s = ResponsiveHelper.spacing(context, 1);
    return Container(
      margin: EdgeInsets.only(bottom: s * 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0), width: 0.8),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 좌측 컬러바
          Positioned(
            left: 0, top: 0, bottom: 0,
            child: Container(width: s * 5, color: Colors.white),
          ),
          // 콘텐츠
          Padding(
            padding: EdgeInsets.only(left: s * 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(s * 12, s * 12, s * 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ① topRow
                      Row(
                        children: [
                          _Box(width: s * 45, height: s * 20, radius: 4),
                          SizedBox(width: s * 8),
                          _Box(width: s * 13, height: s * 13, radius: 2),
                          SizedBox(width: s * 3),
                          Expanded(child: _FullBox(height: s * 12)),
                          SizedBox(width: s * 4),
                          _Box(width: s * 36, height: s * 36, radius: 18),
                        ],
                      ),
                      SizedBox(height: s * 8),
                      // ② 공고 제목 (2줄)
                      _FullBox(height: s * 18),
                      SizedBox(height: s * 4),
                      _Box(width: s * 140, height: s * 18),
                      SizedBox(height: s * 8),
                      // ③ dateTimeRow
                      Row(
                        children: [
                          _Box(width: s * 13, height: s * 13, radius: 2),
                          SizedBox(width: s * 4),
                          _Box(width: s * 80, height: s * 12),
                        ],
                      ),
                      SizedBox(height: s * 5),
                      // ④ businessRow
                      Row(
                        children: [
                          _Box(width: s * 13, height: s * 13, radius: 2),
                          SizedBox(width: s * 4),
                          Expanded(child: _FullBox(height: s * 12)),
                          _Box(width: s * 30, height: s * 11),
                        ],
                      ),
                      SizedBox(height: s * 10),
                      // ⑤ 구분선
                      _FullBox(height: s * 1),
                      SizedBox(height: s * 10),
                      // ⑥ wageRow
                      Row(
                        children: [
                          _Box(width: s * 50, height: s * 21, radius: 4),
                          SizedBox(width: s * 6),
                          _Box(width: s * 80, height: s * 14),
                        ],
                      ),
                      SizedBox(height: s * 10),
                      // ⑦ actionRow
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _Box(width: s * 70, height: s * 33, radius: 8),
                          SizedBox(width: s * 8),
                          _Box(width: s * 70, height: s * 33, radius: 8),
                        ],
                      ),
                      SizedBox(height: s * 12),
                    ],
                  ),
                ),
                // ⑧ expandBar
                Container(height: s * 21, color: Colors.white),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 내 지원 내역 스켈레톤 ────────────────────────────────────────────────────

class ApplicationListSkeleton extends StatelessWidget {
  const ApplicationListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // 카드 높이(~94dp) + 구분선(6dp) = 100dp 기준으로 화면을 채우는 개수 계산
    // +2: 상하 패딩 여유 + 마지막 카드 반쪽 노출(나오다가 마는 효과)
    final s = ResponsiveHelper.spacing(context, 1);
    final availableHeight = MediaQuery.sizeOf(context).height;
    final cardHeight = s * 100;
    final count = (availableHeight / cardHeight).ceil() + 2;

    return AppShimmer(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: ResponsiveHelper.listPadding(context),
        itemCount: count,
        separatorBuilder: (_, __) =>
            SizedBox(height: s * 6),
        itemBuilder: (_, __) => const _ApplicationCardSkeleton(),
      ),
    );
  }
}

/// 실제 _buildApplicationCard 레이아웃과 1:1 대응
///   padding(h:12, v:8) → Column:
///     ① 헤더행: icon + [사업장·날짜] + 상태배지
///     ② 공고 제목
///     ③ 날짜·시간 행
///     ④ 업무유형아이콘 + 업무명 + 급여칩
class _ApplicationCardSkeleton extends StatelessWidget {
  const _ApplicationCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final s = ResponsiveHelper.spacing(context, 1);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: s * 12,
        vertical: s * 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ① 헤더: 사업장명·지원일시 텍스트 + 상태 배지
          Row(
            children: [
              _Box(width: s * 13, height: s * 13, radius: 2),
              SizedBox(width: s * 4),
              Expanded(child: _FullBox(height: s * 12)),
              SizedBox(width: s * 6),
              _Box(width: s * 44, height: s * 20, radius: 6),
            ],
          ),
          SizedBox(height: s * 3),
          // ② 공고 제목 (body bold, full width)
          _FullBox(height: s * 16),
          SizedBox(height: s * 3),
          // ③ 날짜·시간 행 (calendar icon + date + clock icon + time)
          Row(
            children: [
              _Box(width: s * 14, height: s * 14, radius: 2),
              SizedBox(width: s * 4),
              _Box(width: s * 90, height: s * 12),
              SizedBox(width: s * 12),
              _Box(width: s * 14, height: s * 14, radius: 2),
              SizedBox(width: s * 4),
              _Box(width: s * 70, height: s * 12),
            ],
          ),
          SizedBox(height: s * 2),
          // ④ 업무유형 원형 아이콘 + 업무명 + 급여 칩
          Row(
            children: [
              _Box(width: s * 20, height: s * 20, radius: 10),
              SizedBox(width: s * 5),
              _Box(width: s * 60, height: s * 12),
              SizedBox(width: s * 12),
              _Box(width: s * 80, height: s * 20, radius: 4),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── 인력 관리 스켈레톤 (TOGroupCard 접힌 상태) ───────────────────────────────

class WorkforceListSkeleton extends StatelessWidget {
  const WorkforceListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // TOGroupCard 접힌 높이(~170dp) + margin(4dp) ≈ 174dp 기준, +2로 마지막 카드 반쪽 노출
    final s = ResponsiveHelper.spacing(context, 1);
    final availableHeight = MediaQuery.sizeOf(context).height;
    final cardHeight = s * 174;
    final count = (availableHeight / cardHeight).ceil() + 2;

    return AppShimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.all(s * 16),
        itemCount: count,
        itemBuilder: (_, __) => const _WorkforceSectionSkeleton(),
      ),
    );
  }
}

/// 실제 TOGroupCard 접힌(collapsed) 상태와 1:1 대응
/// Stack: 좌측 컬러바(4px, borderRadius left 16) + 메인카드(marginLeft 4)
///   ① 1행: 타입배지 + 사업장명 + 등록시간 + 메뉴버튼
///   ② 공고 제목 (maxLines:2 → 두 줄 스켈레톤)
///   ③ 날짜 + 인원현황 배지
///   ④ 펼침 힌트 아이콘
/// 근로자 목록은 펼친 상태에서만 표시 — 스켈레톤에 포함하지 않음
class _WorkforceSectionSkeleton extends StatelessWidget {
  const _WorkforceSectionSkeleton();

  @override
  Widget build(BuildContext context) {
    final s = ResponsiveHelper.spacing(context, 1);
    return Stack(
      children: [
        // 메인 카드 (컬러바 공간 확보: marginLeft 4)
        Container(
          margin: EdgeInsets.only(left: 4, bottom: s * 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: s * 12, vertical: s * 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ① 타입배지 + 사업장명 + 등록시간 + 메뉴버튼
                Row(
                  children: [
                    _Box(width: s * 40, height: s * 22, radius: 6),
                    SizedBox(width: s * 8),
                    Expanded(child: _FullBox(height: s * 12)),
                    SizedBox(width: s * 6),
                    _Box(width: s * 30, height: s * 11),
                    SizedBox(width: s * 8),
                    _Box(width: s * 20, height: s * 20, radius: 2),
                  ],
                ),
                SizedBox(height: s * 4),
                // ② 공고 제목 (2줄)
                _FullBox(height: s * 18),
                SizedBox(height: s * 4),
                _Box(width: s * 150, height: s * 18),
                SizedBox(height: s * 6),
                // ③ 날짜 아이콘 + 날짜텍스트 + 인원현황 배지
                Row(
                  children: [
                    _Box(width: s * 14, height: s * 14, radius: 2),
                    SizedBox(width: s * 4),
                    Expanded(child: _FullBox(height: s * 12)),
                    SizedBox(width: s * 12),
                    _Box(width: s * 80, height: s * 28, radius: 20),
                  ],
                ),
                SizedBox(height: s * 6),
                // ④ 펼침 힌트 아이콘 (Center)
                Center(child: _Box(width: s * 20, height: s * 20, radius: 2)),
              ],
            ),
          ),
        ),
        // 좌측 컬러바
        Positioned(
          left: 0, top: 0, bottom: s * 4,
          child: Container(
            width: 4,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── 급여 개요 스켈레톤 (월별 그리드 _buildMonthCard) ────────────────────────

class PayrollGridSkeleton extends StatelessWidget {
  const PayrollGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final s = ResponsiveHelper.spacing(context, 1);
    return AppShimmer(
      child: Padding(
        padding: EdgeInsets.all(s * 16),
        child: LayoutBuilder(
          builder: (_, constraints) {
            final itemWidth = (constraints.maxWidth - s * 12) / 2;
            return GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: s * 12,
                mainAxisSpacing: s * 12,
                childAspectRatio: itemWidth / 100.0,
              ),
              itemCount: 12,
              itemBuilder: (_, __) => _buildCell(s),
            );
          },
        ),
      ),
    );
  }

  /// 실제 _buildMonthCard와 1:1 대응
  ///   ① 월 레이블 + chevron_right 아이콘
  ///   ② 총 지급액
  ///   ③ N명 · N건
  Widget _buildCell(double s) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.all(s * 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ① 월 레이블 + chevron
          Row(
            children: [
              _Box(width: s * 20, height: s * 12),
              const Spacer(),
              _Box(width: s * 13, height: s * 13, radius: 2),
            ],
          ),
          SizedBox(height: s * 6),
          // ② 총 지급액 (successDark bold)
          _Box(width: s * 80, height: s * 12),
          SizedBox(height: s * 2),
          // ③ N명 · N건
          _Box(width: s * 60, height: s * 11),
        ],
      ),
    );
  }
}

// ─── 급여 근로자 목록 스켈레톤 (_buildWorkerTile) ─────────────────────────────

class PayrollWorkerListSkeleton extends StatelessWidget {
  const PayrollWorkerListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // WorkerTile 높이(~54dp) + 구분선(8dp) ≈ 62dp 기준, +2로 마지막 카드 반쪽 노출
    final s = ResponsiveHelper.spacing(context, 1);
    final availableHeight = MediaQuery.sizeOf(context).height;
    final cardHeight = s * 62;
    final count = (availableHeight / cardHeight).ceil() + 2;

    return AppShimmer(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.all(s * 16),
        itemCount: count,
        separatorBuilder: (_, __) => SizedBox(height: s * 8),
        itemBuilder: (_, __) => const _PayrollWorkerTileSkeleton(),
      ),
    );
  }
}

/// 실제 _buildWorkerTile 레이아웃과 1:1 대응
/// Stack: 좌측 컬러바(4px) + Padding(ltrb: 4+14, 13, 14, 13)
///   Row: Expanded[이름 + N일근무] / Column[금액 + chevron]
class _PayrollWorkerTileSkeleton extends StatelessWidget {
  const _PayrollWorkerTileSkeleton();

  @override
  Widget build(BuildContext context) {
    final s = ResponsiveHelper.spacing(context, 1);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          // 콘텐츠 (컬러바 4px + 내부여백 14)
          Padding(
            padding: EdgeInsets.fromLTRB(
              4 + s * 14, s * 13, s * 14, s * 13),
            child: Row(
              children: [
                // 왼쪽: 이름 + 근무일수
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FullBox(height: s * 14),
                      SizedBox(height: s * 2),
                      _Box(width: s * 50, height: s * 11),
                    ],
                  ),
                ),
                // 오른쪽: 금액 + chevron
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Box(width: s * 60, height: s * 14),
                    SizedBox(height: s * 2),
                    _Box(width: s * 14, height: s * 14, radius: 2),
                  ],
                ),
              ],
            ),
          ),
          // 좌측 컬러바
          Positioned(
            top: 0, left: 0, bottom: 0,
            child: Container(width: 4, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

