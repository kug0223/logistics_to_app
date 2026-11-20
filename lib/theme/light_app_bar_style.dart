import 'package:flutter/material.dart';

import 'app_colors.dart';

/// [E2-APPBAR-ON-LIGHT] 흰 배경 AppBar 의 제목·아이콘 색.
///
///   앱 테마(`RoleTheme`)의 `AppBarTheme` 은 파란 배경용이라 `titleTextStyle`
///   과 `iconTheme` 에 **흰색을 직접** 적는다. Flutter(3.35) AppBar 는
///   `widget.titleTextStyle ?? appBarTheme.titleTextStyle ?? defaults(fg)` 순서라
///   위젯의 `foregroundColor` 는 테마 값이 있으면 **쓰이지 않는다**
///   (iconTheme 도 같다). 그래서 흰 배경 + `foregroundColor: textPrimary` 로
///   만든 화면의 제목과 뒤로가기가 흰 글씨로 사라졌다.
///
///   앱 전체 테마를 바꾸면 파란 AppBar 전부가 움직인다. 흰 배경 화면만 이
///   두 값을 명시해 테마보다 앞서게 한다. 글꼴 크기·굵기는 테마 값을 그대로 쓴다.
abstract final class LightAppBarStyle {
  static const IconThemeData iconTheme =
      IconThemeData(color: AppColors.textPrimary);

  /// 테마 제목 스타일(크기·굵기)에 색만 바꾼다. [base] 는 화면이 이미 쓰던
  /// 제목 스타일(색이 없어 테마 흰색을 물려받던 것)이 있으면 그것을 준다.
  static TextStyle title(BuildContext context, {TextStyle? base}) {
    final themeTitle = Theme.of(context).appBarTheme.titleTextStyle ??
        Theme.of(context).textTheme.titleLarge ??
        const TextStyle(fontSize: 20, fontWeight: FontWeight.bold);
    return themeTitle.merge(base).copyWith(color: AppColors.textPrimary);
  }
}
