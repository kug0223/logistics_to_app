import 'package:flutter/material.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';

/// 🎨 세련된 아이콘 아이템 클래스
class IconItem {
  final IconData icon;
  final String label;
  final List<String> keywords;
  final String category;
  
  IconItem({
    required this.icon,
    required this.label,
    required this.keywords,
    required this.category,
  });
}

/// ✨ 세련된 아이콘 선택 다이얼로그
class IconPickerDialog {
  /// 아이콘 선택 다이얼로그 표시
  static Future<Map<String, dynamic>?> show({
    required BuildContext context,
    String? initialIcon,
    String? initialIconColor,
    String? initialBackgroundColor,
  }) async {
    final theme = Theme.of(context);
    
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _IconPickerWidget(
        theme: theme,
        initialIcon: initialIcon,
        initialIconColor: initialIconColor,
        initialBackgroundColor: initialBackgroundColor,
      ),
    );
  }

  /// 🎯 세련된 Material Icons 컬렉션 (300개)
  static List<IconItem> getAllIcons() {
    return [
      // ========== 📦 물류/배송 카테고리 (40개) ==========
      IconItem(icon: Icons.inventory_2, label: '재고관리', keywords: ['inventory', '재고', '창고'], category: '물류/배송'),
      IconItem(icon: Icons.warehouse, label: '창고', keywords: ['warehouse', '창고', '보관'], category: '물류/배송'),
      IconItem(icon: Icons.local_shipping, label: '배송', keywords: ['shipping', '배송', '트럭'], category: '물류/배송'),
      IconItem(icon: Icons.arrow_downward, label: '입고', keywords: ['move', 'down', '입고'], category: '물류/배송'),
      IconItem(icon: Icons.arrow_upward, label: '출고', keywords: ['move', 'up', '출고'], category: '물류/배송'),
      IconItem(icon: Icons.input, label: '상품투입', keywords: ['input', '투입', '입력'], category: '물류/배송'),
      IconItem(icon: Icons.category, label: '분류', keywords: ['category', '분류', '카테고리'], category: '물류/배송'),
      IconItem(icon: Icons.qr_code_scanner, label: 'QR스캔', keywords: ['qr', '스캔', 'barcode'], category: '물류/배송'),
      IconItem(icon: Icons.qr_code, label: 'QR코드', keywords: ['qr', 'code', '코드'], category: '물류/배송'),
      IconItem(icon: Icons.assignment_turned_in, label: '검수완료', keywords: ['check', '검수', '완료'], category: '물류/배송'),
      IconItem(icon: Icons.checklist, label: '체크리스트', keywords: ['checklist', '목록', '체크'], category: '물류/배송'),
      IconItem(icon: Icons.list_alt, label: '목록', keywords: ['list', '목록', '리스트'], category: '물류/배송'),
      IconItem(icon: Icons.fact_check, label: '검사', keywords: ['fact', 'check', '검사'], category: '물류/배송'),
      IconItem(icon: Icons.production_quantity_limits, label: '수량제한', keywords: ['quantity', '수량'], category: '물류/배송'),
      IconItem(icon: Icons.precision_manufacturing, label: '제조', keywords: ['manufacturing', '제조'], category: '물류/배송'),
      IconItem(icon: Icons.settings_input_component, label: '컴포넌트', keywords: ['component', '부품'], category: '물류/배송'),
      IconItem(icon: Icons.agriculture, label: '농업', keywords: ['agriculture', '농업'], category: '물류/배송'),
      IconItem(icon: Icons.fire_truck, label: '트럭', keywords: ['truck', '트럭'], category: '물류/배송'),
      IconItem(icon: Icons.airport_shuttle, label: '셔틀', keywords: ['shuttle', '셔틀'], category: '물류/배송'),
      IconItem(icon: Icons.delivery_dining, label: '배달', keywords: ['delivery', '배달'], category: '물류/배송'),
      IconItem(icon: Icons.home_work, label: '작업장', keywords: ['work', '작업장', '진열'], category: '물류/배송'),
      IconItem(icon: Icons.inventory, label: '인벤토리', keywords: ['inventory', '재고'], category: '물류/배송'),
      IconItem(icon: Icons.inventory_2_outlined, label: '패키지', keywords: ['package', '박스', '포장'], category: '물류/배송'),
      IconItem(icon: Icons.all_inbox, label: '전체함', keywords: ['inbox', '함', '전체'], category: '물류/배송'),
      IconItem(icon: Icons.inbox, label: '수신함', keywords: ['inbox', '수신'], category: '물류/배송'),
      IconItem(icon: Icons.outbox, label: '발신함', keywords: ['outbox', '발신'], category: '물류/배송'),
      IconItem(icon: Icons.archive, label: '보관함', keywords: ['archive', '보관'], category: '물류/배송'),
      IconItem(icon: Icons.unarchive, label: '꺼내기', keywords: ['unarchive', '꺼내기'], category: '물류/배송'),
      IconItem(icon: Icons.move_to_inbox, label: '이동', keywords: ['move', '이동'], category: '물류/배송'),
      IconItem(icon: Icons.markunread_mailbox, label: '우편함', keywords: ['mailbox', '우편'], category: '물류/배송'),
      IconItem(icon: Icons.conveyor_belt, label: '컨베이어', keywords: ['conveyor', '컨베이어'], category: '물류/배송'),
      IconItem(icon: Icons.forklift, label: '지게차', keywords: ['forklift', '지게차'], category: '물류/배송'),
      IconItem(icon: Icons.trolley, label: '트롤리', keywords: ['trolley', '카트'], category: '물류/배송'),
      IconItem(icon: Icons.shopping_cart, label: '카트', keywords: ['cart', '카트', '쇼핑'], category: '물류/배송'),
      IconItem(icon: Icons.add_shopping_cart, label: '장바구니추가', keywords: ['cart', 'add', '추가'], category: '물류/배송'),
      IconItem(icon: Icons.remove_shopping_cart, label: '장바구니제거', keywords: ['cart', 'remove', '제거'], category: '물류/배송'),
      IconItem(icon: Icons.shopping_bag, label: '쇼핑백', keywords: ['bag', '백', '쇼핑'], category: '물류/배송'),
      IconItem(icon: Icons.shopping_basket, label: '바구니', keywords: ['basket', '바구니'], category: '물류/배송'),
      IconItem(icon: Icons.storefront, label: '매장', keywords: ['store', '매장', '가게'], category: '물류/배송'),
      IconItem(icon: Icons.store, label: '스토어', keywords: ['store', '스토어'], category: '물류/배송'),
      IconItem(icon: Icons.point_of_sale, label: 'POS', keywords: ['pos', '판매', '결제'], category: '물류/배송'),
      
      // ========== 🍕 음식/음료 카테고리 (35개) ==========
      IconItem(icon: Icons.restaurant, label: '식당', keywords: ['restaurant', '식당', '음식'], category: '음식/음료'),
      IconItem(icon: Icons.local_cafe, label: '카페', keywords: ['cafe', '카페', '커피'], category: '음식/음료'),
      IconItem(icon: Icons.coffee, label: '커피', keywords: ['coffee', '커피'], category: '음식/음료'),
      IconItem(icon: Icons.local_pizza, label: '피자', keywords: ['pizza', '피자'], category: '음식/음료'),
      IconItem(icon: Icons.fastfood, label: '패스트푸드', keywords: ['fastfood', '햄버거'], category: '음식/음료'),
      IconItem(icon: Icons.ramen_dining, label: '라면', keywords: ['ramen', '라면', '국수'], category: '음식/음료'),
      IconItem(icon: Icons.lunch_dining, label: '점심', keywords: ['lunch', '점심', '식사'], category: '음식/음료'),
      IconItem(icon: Icons.dinner_dining, label: '저녁', keywords: ['dinner', '저녁'], category: '음식/음료'),
      IconItem(icon: Icons.breakfast_dining, label: '아침', keywords: ['breakfast', '아침'], category: '음식/음료'),
      IconItem(icon: Icons.brunch_dining, label: '브런치', keywords: ['brunch', '브런치'], category: '음식/음료'),
      IconItem(icon: Icons.liquor, label: '주류', keywords: ['liquor', '술', '주류'], category: '음식/음료'),
      IconItem(icon: Icons.local_bar, label: '바', keywords: ['bar', '바', '술집'], category: '음식/음료'),
      IconItem(icon: Icons.icecream, label: '아이스크림', keywords: ['icecream', '아이스크림'], category: '음식/음료'),
      IconItem(icon: Icons.cake, label: '케이크', keywords: ['cake', '케이크', '디저트'], category: '음식/음료'),
      IconItem(icon: Icons.cookie, label: '쿠키', keywords: ['cookie', '쿠키'], category: '음식/음료'),
      IconItem(icon: Icons.bakery_dining, label: '베이커리', keywords: ['bakery', '빵', '베이커리'], category: '음식/음료'),
      IconItem(icon: Icons.takeout_dining, label: '테이크아웃', keywords: ['takeout', '포장'], category: '음식/음료'),
      IconItem(icon: Icons.dining, label: '식사', keywords: ['dining', '식사'], category: '음식/음료'),
      IconItem(icon: Icons.kitchen, label: '주방', keywords: ['kitchen', '주방'], category: '음식/음료'),
      IconItem(icon: Icons.egg_alt, label: '계란', keywords: ['egg', '계란'], category: '음식/음료'),
      IconItem(icon: Icons.rice_bowl, label: '밥', keywords: ['rice', '밥', '쌀'], category: '음식/음료'),
      IconItem(icon: Icons.set_meal, label: '정식', keywords: ['meal', '정식', '세트'], category: '음식/음료'),
      IconItem(icon: Icons.soup_kitchen, label: '수프', keywords: ['soup', '수프', '국'], category: '음식/음료'),
      IconItem(icon: Icons.emoji_food_beverage, label: '음료', keywords: ['beverage', '음료'], category: '음식/음료'),
      IconItem(icon: Icons.local_drink, label: '드링크', keywords: ['drink', '드링크'], category: '음식/음료'),
      IconItem(icon: Icons.wine_bar, label: '와인', keywords: ['wine', '와인'], category: '음식/음료'),
      IconItem(icon: Icons.sports_bar, label: '맥주', keywords: ['beer', '맥주'], category: '음식/음료'),
      IconItem(icon: Icons.nightlife, label: '나이트', keywords: ['night', '나이트'], category: '음식/음료'),
      IconItem(icon: Icons.outdoor_grill, label: '그릴', keywords: ['grill', '그릴', '바베큐'], category: '음식/음료'),
      IconItem(icon: Icons.microwave, label: '전자레인지', keywords: ['microwave', '전자레인지'], category: '음식/음료'),
      IconItem(icon: Icons.blender, label: '블렌더', keywords: ['blender', '블렌더'], category: '음식/음료'),
      IconItem(icon: Icons.coffee_maker, label: '커피머신', keywords: ['coffee', 'maker', '커피머신'], category: '음식/음료'),
      IconItem(icon: Icons.tapas, label: '타파스', keywords: ['tapas', '타파스'], category: '음식/음료'),
      IconItem(icon: Icons.kebab_dining, label: '케밥', keywords: ['kebab', '케밥'], category: '음식/음료'),
      IconItem(icon: Icons.bento, label: '도시락', keywords: ['bento', '도시락'], category: '음식/음료'),
      
      // ========== 🧹 청소/관리 카테고리 (30개) ==========
      IconItem(icon: Icons.cleaning_services, label: '청소', keywords: ['cleaning', '청소'], category: '청소/관리'),
      IconItem(icon: Icons.sanitizer, label: '소독', keywords: ['sanitizer', '소독', '살균'], category: '청소/관리'),
      IconItem(icon: Icons.clean_hands, label: '손세척', keywords: ['clean', 'hands', '손세척'], category: '청소/관리'),
      IconItem(icon: Icons.shower, label: '샤워', keywords: ['shower', '샤워'], category: '청소/관리'),
      IconItem(icon: Icons.bathtub, label: '욕조', keywords: ['bathtub', '욕조'], category: '청소/관리'),
      IconItem(icon: Icons.wash, label: '세탁', keywords: ['wash', '세탁', '빨래'], category: '청소/관리'),
      IconItem(icon: Icons.dry_cleaning, label: '드라이클리닝', keywords: ['dry', 'cleaning', '드라이'], category: '청소/관리'),
      IconItem(icon: Icons.local_laundry_service, label: '세탁소', keywords: ['laundry', '세탁소'], category: '청소/관리'),
      IconItem(icon: Icons.soap, label: '비누', keywords: ['soap', '비누'], category: '청소/관리'),
      IconItem(icon: Icons.water_drop, label: '물방울', keywords: ['water', '물'], category: '청소/관리'),
      IconItem(icon: Icons.waves, label: '물결', keywords: ['waves', '물결'], category: '청소/관리'),
      IconItem(icon: Icons.delete_sweep, label: '쓸기', keywords: ['sweep', '쓸기'], category: '청소/관리'),
      IconItem(icon: Icons.recycling, label: '재활용', keywords: ['recycle', '재활용'], category: '청소/관리'),
      IconItem(icon: Icons.eco, label: '친환경', keywords: ['eco', '친환경'], category: '청소/관리'),
      IconItem(icon: Icons.delete, label: '삭제', keywords: ['delete', '삭제', '쓰레기'], category: '청소/관리'),
      IconItem(icon: Icons.restore_from_trash, label: '복원', keywords: ['restore', '복원'], category: '청소/관리'),
      IconItem(icon: Icons.hvac, label: '환기', keywords: ['hvac', '환기'], category: '청소/관리'),
      IconItem(icon: Icons.air, label: '공기', keywords: ['air', '공기'], category: '청소/관리'),
      IconItem(icon: Icons.window, label: '창문', keywords: ['window', '창문'], category: '청소/관리'),
      IconItem(icon: Icons.iron, label: '다리미', keywords: ['iron', '다리미'], category: '청소/관리'),
      IconItem(icon: Icons.grass, label: '잔디', keywords: ['grass', '잔디'], category: '청소/관리'),
      IconItem(icon: Icons.yard, label: '마당', keywords: ['yard', '마당'], category: '청소/관리'),
      IconItem(icon: Icons.compost, label: '퇴비', keywords: ['compost', '퇴비'], category: '청소/관리'),
      IconItem(icon: Icons.pest_control, label: '방역', keywords: ['pest', '방역', '해충'], category: '청소/관리'),
      IconItem(icon: Icons.pest_control_rodent, label: '쥐방역', keywords: ['rodent', '쥐', '방역'], category: '청소/관리'),
      IconItem(icon: Icons.vaccines, label: '백신', keywords: ['vaccine', '백신'], category: '청소/관리'),
      IconItem(icon: Icons.medical_services, label: '의료', keywords: ['medical', '의료'], category: '청소/관리'),
      IconItem(icon: Icons.health_and_safety, label: '안전보건', keywords: ['health', 'safety', '안전'], category: '청소/관리'),
      IconItem(icon: Icons.coronavirus, label: '바이러스', keywords: ['virus', '바이러스'], category: '청소/관리'),
      IconItem(icon: Icons.masks, label: '마스크', keywords: ['mask', '마스크'], category: '청소/관리'),
      
      // ========== 🔧 도구/작업 카테고리 (35개) ==========
      IconItem(icon: Icons.construction, label: '건설', keywords: ['construction', '건설', '공사'], category: '도구/작업'),
      IconItem(icon: Icons.handyman, label: '수리공', keywords: ['handyman', '수리공'], category: '도구/작업'),
      IconItem(icon: Icons.build, label: '제작', keywords: ['build', '제작', '만들기'], category: '도구/작업'),
      IconItem(icon: Icons.carpenter, label: '목수', keywords: ['carpenter', '목수'], category: '도구/작업'),
      IconItem(icon: Icons.home_repair_service, label: '수리', keywords: ['repair', '수리'], category: '도구/작업'),
      IconItem(icon: Icons.plumbing, label: '배관', keywords: ['plumbing', '배관'], category: '도구/작업'),
      IconItem(icon: Icons.electrical_services, label: '전기', keywords: ['electrical', '전기'], category: '도구/작업'),
      IconItem(icon: Icons.engineering, label: '엔지니어링', keywords: ['engineering', '엔지니어링'], category: '도구/작업'),
      IconItem(icon: Icons.architecture, label: '건축', keywords: ['architecture', '건축'], category: '도구/작업'),
      IconItem(icon: Icons.design_services, label: '디자인', keywords: ['design', '디자인'], category: '도구/작업'),
      IconItem(icon: Icons.hardware, label: '하드웨어', keywords: ['hardware', '하드웨어'], category: '도구/작업'),
      IconItem(icon: Icons.settings, label: '설정', keywords: ['settings', '설정'], category: '도구/작업'),
      IconItem(icon: Icons.tune, label: '조정', keywords: ['tune', '조정'], category: '도구/작업'),
      IconItem(icon: Icons.power, label: '전원', keywords: ['power', '전원'], category: '도구/작업'),
      IconItem(icon: Icons.lightbulb, label: '전구', keywords: ['lightbulb', '전구'], category: '도구/작업'),
      IconItem(icon: Icons.roofing, label: '지붕', keywords: ['roofing', '지붕'], category: '도구/작업'),
      IconItem(icon: Icons.foundation, label: '기초', keywords: ['foundation', '기초'], category: '도구/작업'),
      IconItem(icon: Icons.fence, label: '울타리', keywords: ['fence', '울타리'], category: '도구/작업'),
      IconItem(icon: Icons.stairs, label: '계단', keywords: ['stairs', '계단'], category: '도구/작업'),
      IconItem(icon: Icons.meeting_room, label: '문', keywords: ['door', '문'], category: '도구/작업'),
      IconItem(icon: Icons.build_circle, label: '도구', keywords: ['tool', '도구'], category: '도구/작업'),
      IconItem(icon: Icons.gavel, label: '망치', keywords: ['hammer', '망치'], category: '도구/작업'),
      IconItem(icon: Icons.content_cut, label: '가위', keywords: ['scissors', '가위', '자르기'], category: '도구/작업'),
      IconItem(icon: Icons.straighten, label: '자', keywords: ['ruler', '자'], category: '도구/작업'),
      IconItem(icon: Icons.square_foot, label: '면적', keywords: ['area', '면적'], category: '도구/작업'),
      IconItem(icon: Icons.palette, label: '팔레트', keywords: ['palette', '팔레트', '색상'], category: '도구/작업'),
      IconItem(icon: Icons.brush, label: '브러시', keywords: ['brush', '브러시', '붓'], category: '도구/작업'),
      IconItem(icon: Icons.format_paint, label: '페인트', keywords: ['paint', '페인트'], category: '도구/작업'),
      IconItem(icon: Icons.roller_shades, label: '롤러', keywords: ['roller', '롤러'], category: '도구/작업'),
      IconItem(icon: Icons.key, label: '열쇠', keywords: ['key', '열쇠'], category: '도구/작업'),
      IconItem(icon: Icons.vpn_key, label: '키', keywords: ['key', '키'], category: '도구/작업'),
      IconItem(icon: Icons.lock, label: '잠금', keywords: ['lock', '잠금'], category: '도구/작업'),
      IconItem(icon: Icons.lock_open, label: '열림', keywords: ['unlock', '열림'], category: '도구/작업'),
      IconItem(icon: Icons.shield, label: '방패', keywords: ['shield', '방패', '보안'], category: '도구/작업'),
      IconItem(icon: Icons.security, label: '보안', keywords: ['security', '보안'], category: '도구/작업'),
      
      // ========== 📝 사무/문서 카테고리 (30개) ==========
      IconItem(icon: Icons.assignment, label: '과제', keywords: ['assignment', '과제', '업무'], category: '사무/문서'),
      IconItem(icon: Icons.description, label: '문서', keywords: ['description', '문서', '설명'], category: '사무/문서'),
      IconItem(icon: Icons.article, label: '기사', keywords: ['article', '기사', '글'], category: '사무/문서'),
      IconItem(icon: Icons.note, label: '노트', keywords: ['note', '노트', '메모'], category: '사무/문서'),
      IconItem(icon: Icons.sticky_note_2, label: '포스트잇', keywords: ['sticky', '포스트잇'], category: '사무/문서'),
      IconItem(icon: Icons.edit_note, label: '편집', keywords: ['edit', '편집'], category: '사무/문서'),
      IconItem(icon: Icons.folder, label: '폴더', keywords: ['folder', '폴더'], category: '사무/문서'),
      IconItem(icon: Icons.folder_open, label: '열린폴더', keywords: ['folder', 'open', '열림'], category: '사무/문서'),
      IconItem(icon: Icons.insert_drive_file, label: '파일', keywords: ['file', '파일'], category: '사무/문서'),
      IconItem(icon: Icons.file_copy, label: '복사', keywords: ['copy', '복사'], category: '사무/문서'),
      IconItem(icon: Icons.summarize, label: '요약', keywords: ['summarize', '요약'], category: '사무/문서'),
      IconItem(icon: Icons.receipt_long, label: '영수증', keywords: ['receipt', '영수증'], category: '사무/문서'),
      IconItem(icon: Icons.request_quote, label: '견적', keywords: ['quote', '견적'], category: '사무/문서'),
      IconItem(icon: Icons.print, label: '인쇄', keywords: ['print', '인쇄'], category: '사무/문서'),
      IconItem(icon: Icons.scanner, label: '스캔', keywords: ['scanner', '스캔'], category: '사무/문서'),
      IconItem(icon: Icons.create, label: '작성', keywords: ['create', '작성', '쓰기'], category: '사무/문서'),
      IconItem(icon: Icons.edit, label: '수정', keywords: ['edit', '수정'], category: '사무/문서'),
      IconItem(icon: Icons.draw, label: '그리기', keywords: ['draw', '그리기'], category: '사무/문서'),
      IconItem(icon: Icons.text_fields, label: '텍스트', keywords: ['text', '텍스트'], category: '사무/문서'),
      IconItem(icon: Icons.format_list_bulleted, label: '목록', keywords: ['list', '목록'], category: '사무/문서'),
      IconItem(icon: Icons.format_list_numbered, label: '번호목록', keywords: ['numbered', '번호'], category: '사무/문서'),
      IconItem(icon: Icons.table_chart, label: '표', keywords: ['table', '표', '차트'], category: '사무/문서'),
      IconItem(icon: Icons.grid_on, label: '그리드', keywords: ['grid', '그리드'], category: '사무/문서'),
      IconItem(icon: Icons.dashboard, label: '대시보드', keywords: ['dashboard', '대시보드'], category: '사무/문서'),
      IconItem(icon: Icons.analytics, label: '분석', keywords: ['analytics', '분석'], category: '사무/문서'),
      IconItem(icon: Icons.insights, label: '인사이트', keywords: ['insights', '인사이트'], category: '사무/문서'),
      IconItem(icon: Icons.assessment, label: '평가', keywords: ['assessment', '평가'], category: '사무/문서'),
      IconItem(icon: Icons.trending_up, label: '상승', keywords: ['trending', 'up', '상승'], category: '사무/문서'),
      IconItem(icon: Icons.trending_down, label: '하락', keywords: ['trending', 'down', '하락'], category: '사무/문서'),
      IconItem(icon: Icons.bar_chart, label: '막대차트', keywords: ['bar', 'chart', '막대'], category: '사무/문서'),
      
      // ========== ⏰ 시간/일정 카테고리 (25개) ==========
      IconItem(icon: Icons.schedule, label: '스케줄', keywords: ['schedule', '스케줄', '일정'], category: '시간/일정'),
      IconItem(icon: Icons.access_time, label: '시간', keywords: ['time', '시간'], category: '시간/일정'),
      IconItem(icon: Icons.alarm, label: '알람', keywords: ['alarm', '알람'], category: '시간/일정'),
      IconItem(icon: Icons.timer, label: '타이머', keywords: ['timer', '타이머'], category: '시간/일정'),
      IconItem(icon: Icons.today, label: '오늘', keywords: ['today', '오늘'], category: '시간/일정'),
      IconItem(icon: Icons.event, label: '이벤트', keywords: ['event', '이벤트'], category: '시간/일정'),
      IconItem(icon: Icons.calendar_month, label: '달력', keywords: ['calendar', '달력'], category: '시간/일정'),
      IconItem(icon: Icons.calendar_today, label: '오늘날짜', keywords: ['calendar', '오늘'], category: '시간/일정'),
      IconItem(icon: Icons.date_range, label: '기간', keywords: ['date', 'range', '기간'], category: '시간/일정'),
      IconItem(icon: Icons.watch_later, label: '나중에', keywords: ['watch', 'later', '나중'], category: '시간/일정'),
      IconItem(icon: Icons.update, label: '업데이트', keywords: ['update', '업데이트'], category: '시간/일정'),
      IconItem(icon: Icons.history, label: '기록', keywords: ['history', '기록', '히스토리'], category: '시간/일정'),
      IconItem(icon: Icons.pending, label: '대기중', keywords: ['pending', '대기'], category: '시간/일정'),
      IconItem(icon: Icons.hourglass_bottom, label: '모래시계', keywords: ['hourglass', '모래시계'], category: '시간/일정'),
      IconItem(icon: Icons.timelapse, label: '타임랩스', keywords: ['timelapse', '타임랩스'], category: '시간/일정'),
      IconItem(icon: Icons.alarm_on, label: '알람설정', keywords: ['alarm', 'on', '설정'], category: '시간/일정'),
      IconItem(icon: Icons.alarm_off, label: '알람해제', keywords: ['alarm', 'off', '해제'], category: '시간/일정'),
      IconItem(icon: Icons.snooze, label: '스누즈', keywords: ['snooze', '스누즈'], category: '시간/일정'),
      IconItem(icon: Icons.timer_off, label: '타이머해제', keywords: ['timer', 'off'], category: '시간/일정'),
      IconItem(icon: Icons.more_time, label: '시간추가', keywords: ['more', 'time', '추가'], category: '시간/일정'),
      IconItem(icon: Icons.av_timer, label: 'AV타이머', keywords: ['av', 'timer'], category: '시간/일정'),
      IconItem(icon: Icons.free_breakfast, label: '휴식', keywords: ['break', '휴식'], category: '시간/일정'),
      IconItem(icon: Icons.nights_stay, label: '야간', keywords: ['night', '야간', '밤'], category: '시간/일정'),
      IconItem(icon: Icons.wb_sunny, label: '주간', keywords: ['sunny', '주간', '낮'], category: '시간/일정'),
      IconItem(icon: Icons.bedtime, label: '취침', keywords: ['bedtime', '취침'], category: '시간/일정'),
      
      // ========== 👥 사람/팀 카테고리 (25개) ==========
      IconItem(icon: Icons.person, label: '사람', keywords: ['person', '사람', '개인'], category: '사람/팀'),
      IconItem(icon: Icons.group, label: '그룹', keywords: ['group', '그룹', '팀'], category: '사람/팀'),
      IconItem(icon: Icons.people, label: '사람들', keywords: ['people', '사람들'], category: '사람/팀'),
      IconItem(icon: Icons.groups, label: '여러그룹', keywords: ['groups', '그룹들'], category: '사람/팀'),
      IconItem(icon: Icons.supervisor_account, label: '관리자', keywords: ['supervisor', '관리자'], category: '사람/팀'),
      IconItem(icon: Icons.badge, label: '배지', keywords: ['badge', '배지', '신분증'], category: '사람/팀'),
      IconItem(icon: Icons.contact_page, label: '연락처', keywords: ['contact', '연락처'], category: '사람/팀'),
      IconItem(icon: Icons.account_circle, label: '계정', keywords: ['account', '계정'], category: '사람/팀'),
      IconItem(icon: Icons.manage_accounts, label: '계정관리', keywords: ['manage', '관리'], category: '사람/팀'),
      IconItem(icon: Icons.admin_panel_settings, label: '관리자패널', keywords: ['admin', '관리자'], category: '사람/팀'),
      IconItem(icon: Icons.person_add, label: '추가', keywords: ['add', '추가', '사람'], category: '사람/팀'),
      IconItem(icon: Icons.person_remove, label: '제거', keywords: ['remove', '제거', '사람'], category: '사람/팀'),
      IconItem(icon: Icons.person_search, label: '검색', keywords: ['search', '검색', '사람'], category: '사람/팀'),
      IconItem(icon: Icons.group_add, label: '그룹추가', keywords: ['group', 'add', '추가'], category: '사람/팀'),
      IconItem(icon: Icons.group_remove, label: '그룹제거', keywords: ['group', 'remove', '제거'], category: '사람/팀'),
      IconItem(icon: Icons.face, label: '얼굴', keywords: ['face', '얼굴'], category: '사람/팀'),
      IconItem(icon: Icons.sentiment_satisfied, label: '만족', keywords: ['satisfied', '만족'], category: '사람/팀'),
      IconItem(icon: Icons.sentiment_dissatisfied, label: '불만족', keywords: ['dissatisfied', '불만족'], category: '사람/팀'),
      IconItem(icon: Icons.emoji_people, label: '이모지', keywords: ['emoji', '이모지'], category: '사람/팀'),
      IconItem(icon: Icons.waving_hand, label: '손흔들기', keywords: ['wave', '손', '인사'], category: '사람/팀'),
      IconItem(icon: Icons.front_hand, label: '손', keywords: ['hand', '손'], category: '사람/팀'),
      IconItem(icon: Icons.back_hand, label: '손등', keywords: ['hand', 'back', '손등'], category: '사람/팀'),
      IconItem(icon: Icons.handshake, label: '악수', keywords: ['handshake', '악수'], category: '사람/팀'),
      IconItem(icon: Icons.volunteer_activism, label: '봉사', keywords: ['volunteer', '봉사'], category: '사람/팀'),
      IconItem(icon: Icons.diversity_3, label: '다양성', keywords: ['diversity', '다양성'], category: '사람/팀'),
      
      // ========== ✅ 상태/액션 카테고리 (30개) ==========
      IconItem(icon: Icons.check_circle, label: '완료', keywords: ['check', '완료', '체크'], category: '상태/액션'),
      IconItem(icon: Icons.verified, label: '검증완료', keywords: ['verified', '검증'], category: '상태/액션'),
      IconItem(icon: Icons.task_alt, label: '작업완료', keywords: ['task', '작업'], category: '상태/액션'),
      IconItem(icon: Icons.done_all, label: '모두완료', keywords: ['done', '완료'], category: '상태/액션'),
      IconItem(icon: Icons.pending_actions, label: '대기중', keywords: ['pending', '대기'], category: '상태/액션'),
      IconItem(icon: Icons.error, label: '에러', keywords: ['error', '에러', '오류'], category: '상태/액션'),
      IconItem(icon: Icons.warning, label: '경고', keywords: ['warning', '경고'], category: '상태/액션'),
      IconItem(icon: Icons.info, label: '정보', keywords: ['info', '정보'], category: '상태/액션'),
      IconItem(icon: Icons.help, label: '도움말', keywords: ['help', '도움말'], category: '상태/액션'),
      IconItem(icon: Icons.cancel, label: '취소', keywords: ['cancel', '취소'], category: '상태/액션'),
      IconItem(icon: Icons.close, label: '닫기', keywords: ['close', '닫기'], category: '상태/액션'),
      IconItem(icon: Icons.add, label: '추가', keywords: ['add', '추가', '더하기'], category: '상태/액션'),
      IconItem(icon: Icons.remove, label: '제거', keywords: ['remove', '제거', '빼기'], category: '상태/액션'),
      IconItem(icon: Icons.refresh, label: '새로고침', keywords: ['refresh', '새로고침'], category: '상태/액션'),
      IconItem(icon: Icons.sync, label: '동기화', keywords: ['sync', '동기화'], category: '상태/액션'),
      IconItem(icon: Icons.check, label: '체크', keywords: ['check', '체크'], category: '상태/액션'),
      IconItem(icon: Icons.done, label: '완료', keywords: ['done', '완료'], category: '상태/액션'),
      IconItem(icon: Icons.clear, label: '지우기', keywords: ['clear', '지우기'], category: '상태/액션'),
      IconItem(icon: Icons.block, label: '차단', keywords: ['block', '차단'], category: '상태/액션'),
      IconItem(icon: Icons.do_not_disturb, label: '방해금지', keywords: ['disturb', '방해금지'], category: '상태/액션'),
      IconItem(icon: Icons.priority_high, label: '긴급', keywords: ['priority', '긴급', '중요'], category: '상태/액션'),
      IconItem(icon: Icons.flag, label: '플래그', keywords: ['flag', '플래그'], category: '상태/액션'),
      IconItem(icon: Icons.bookmark, label: '북마크', keywords: ['bookmark', '북마크'], category: '상태/액션'),
      IconItem(icon: Icons.star, label: '별', keywords: ['star', '별', '즐겨찾기'], category: '상태/액션'),
      IconItem(icon: Icons.favorite, label: '좋아요', keywords: ['favorite', '좋아요', '하트'], category: '상태/액션'),
      IconItem(icon: Icons.thumb_up, label: '추천', keywords: ['thumb', 'up', '추천'], category: '상태/액션'),
      IconItem(icon: Icons.thumb_down, label: '비추천', keywords: ['thumb', 'down', '비추천'], category: '상태/액션'),
      IconItem(icon: Icons.visibility, label: '보기', keywords: ['visibility', '보기'], category: '상태/액션'),
      IconItem(icon: Icons.visibility_off, label: '숨기기', keywords: ['visibility', 'off', '숨기기'], category: '상태/액션'),
      IconItem(icon: Icons.notifications, label: '알림', keywords: ['notification', '알림'], category: '상태/액션'),
      
      // ========== 🏢 건물/장소 카테고리 (25개) ==========
      IconItem(icon: Icons.business, label: '사업장', keywords: ['business', '사업장', '회사'], category: '건물/장소'),
      IconItem(icon: Icons.apartment, label: '아파트', keywords: ['apartment', '아파트'], category: '건물/장소'),
      IconItem(icon: Icons.home, label: '홈', keywords: ['home', '홈', '집'], category: '건물/장소'),
      IconItem(icon: Icons.house, label: '집', keywords: ['house', '집'], category: '건물/장소'),
      IconItem(icon: Icons.location_city, label: '도시', keywords: ['city', '도시'], category: '건물/장소'),
      IconItem(icon: Icons.domain, label: '빌딩', keywords: ['domain', '빌딩'], category: '건물/장소'),
      IconItem(icon: Icons.factory, label: '공장', keywords: ['factory', '공장'], category: '건물/장소'),
      IconItem(icon: Icons.school, label: '학교', keywords: ['school', '학교'], category: '건물/장소'),
      IconItem(icon: Icons.local_hospital, label: '병원', keywords: ['hospital', '병원'], category: '건물/장소'),
      IconItem(icon: Icons.local_pharmacy, label: '약국', keywords: ['pharmacy', '약국'], category: '건물/장소'),
      IconItem(icon: Icons.local_library, label: '도서관', keywords: ['library', '도서관'], category: '건물/장소'),
      IconItem(icon: Icons.church, label: '교회', keywords: ['church', '교회'], category: '건물/장소'),
      IconItem(icon: Icons.mosque, label: '모스크', keywords: ['mosque', '모스크'], category: '건물/장소'),
      IconItem(icon: Icons.temple_buddhist, label: '사찰', keywords: ['temple', '사찰'], category: '건물/장소'),
      IconItem(icon: Icons.museum, label: '박물관', keywords: ['museum', '박물관'], category: '건물/장소'),
      IconItem(icon: Icons.stadium, label: '경기장', keywords: ['stadium', '경기장'], category: '건물/장소'),
      IconItem(icon: Icons.local_mall, label: '쇼핑몰', keywords: ['mall', '쇼핑몰'], category: '건물/장소'),
      IconItem(icon: Icons.local_grocery_store, label: '마트', keywords: ['grocery', '마트'], category: '건물/장소'),
      IconItem(icon: Icons.local_gas_station, label: '주유소', keywords: ['gas', '주유소'], category: '건물/장소'),
      IconItem(icon: Icons.local_parking, label: '주차장', keywords: ['parking', '주차장'], category: '건물/장소'),
      IconItem(icon: Icons.local_atm, label: 'ATM', keywords: ['atm', '현금'], category: '건물/장소'),
      IconItem(icon: Icons.local_post_office, label: '우체국', keywords: ['post', '우체국'], category: '건물/장소'),
      IconItem(icon: Icons.local_police, label: '경찰서', keywords: ['police', '경찰서'], category: '건물/장소'),
      IconItem(icon: Icons.local_fire_department, label: '소방서', keywords: ['fire', '소방서'], category: '건물/장소'),
      IconItem(icon: Icons.local_airport, label: '공항', keywords: ['airport', '공항'], category: '건물/장소'),
      
      // ========== 🚗 교통/이동 카테고리 (25개) ==========
      IconItem(icon: Icons.directions_car, label: '자동차', keywords: ['car', '자동차'], category: '교통/이동'),
      IconItem(icon: Icons.directions_bus, label: '버스', keywords: ['bus', '버스'], category: '교통/이동'),
      IconItem(icon: Icons.directions_subway, label: '지하철', keywords: ['subway', '지하철'], category: '교통/이동'),
      IconItem(icon: Icons.directions_railway, label: '기차', keywords: ['railway', '기차'], category: '교통/이동'),
      IconItem(icon: Icons.directions_boat, label: '배', keywords: ['boat', '배'], category: '교통/이동'),
      IconItem(icon: Icons.flight, label: '비행기', keywords: ['flight', '비행기'], category: '교통/이동'),
      IconItem(icon: Icons.directions_bike, label: '자전거', keywords: ['bike', '자전거'], category: '교통/이동'),
      IconItem(icon: Icons.directions_walk, label: '걷기', keywords: ['walk', '걷기'], category: '교통/이동'),
      IconItem(icon: Icons.directions_run, label: '달리기', keywords: ['run', '달리기'], category: '교통/이동'),
      IconItem(icon: Icons.two_wheeler, label: '오토바이', keywords: ['motorcycle', '오토바이'], category: '교통/이동'),
      IconItem(icon: Icons.electric_scooter, label: '전동킥보드', keywords: ['scooter', '킥보드'], category: '교통/이동'),
      IconItem(icon: Icons.electric_bike, label: '전기자전거', keywords: ['electric', 'bike', '전기'], category: '교통/이동'),
      IconItem(icon: Icons.electric_car, label: '전기차', keywords: ['electric', 'car', '전기차'], category: '교통/이동'),
      IconItem(icon: Icons.local_taxi, label: '택시', keywords: ['taxi', '택시'], category: '교통/이동'),
      IconItem(icon: Icons.commute, label: '출퇴근', keywords: ['commute', '출퇴근'], category: '교통/이동'),
      IconItem(icon: Icons.transfer_within_a_station, label: '환승', keywords: ['transfer', '환승'], category: '교통/이동'),
      IconItem(icon: Icons.location_on, label: '위치', keywords: ['location', '위치'], category: '교통/이동'),
      IconItem(icon: Icons.my_location, label: '내위치', keywords: ['my', 'location', '내위치'], category: '교통/이동'),
      IconItem(icon: Icons.gps_fixed, label: 'GPS', keywords: ['gps', '위성'], category: '교통/이동'),
      IconItem(icon: Icons.map, label: '지도', keywords: ['map', '지도'], category: '교통/이동'),
      IconItem(icon: Icons.navigation, label: '네비게이션', keywords: ['navigation', '네비'], category: '교통/이동'),
      IconItem(icon: Icons.near_me, label: '근처', keywords: ['near', '근처'], category: '교통/이동'),
      IconItem(icon: Icons.explore, label: '탐색', keywords: ['explore', '탐색'], category: '교통/이동'),
      IconItem(icon: Icons.route, label: '경로', keywords: ['route', '경로'], category: '교통/이동'),
      IconItem(icon: Icons.signpost, label: '표지판', keywords: ['signpost', '표지판'], category: '교통/이동'),
      
      // ========== 💰 금융/결제 카테고리 (25개) ==========
      IconItem(icon: Icons.payments, label: '결제', keywords: ['payment', '결제'], category: '금융/결제'),
      IconItem(icon: Icons.credit_card, label: '카드', keywords: ['card', '카드', '신용'], category: '금융/결제'),
      IconItem(icon: Icons.account_balance, label: '은행', keywords: ['bank', '은행'], category: '금융/결제'),
      IconItem(icon: Icons.account_balance_wallet, label: '지갑', keywords: ['wallet', '지갑'], category: '금융/결제'),
      IconItem(icon: Icons.money, label: '돈', keywords: ['money', '돈'], category: '금융/결제'),
      IconItem(icon: Icons.attach_money, label: '달러', keywords: ['dollar', '달러'], category: '금융/결제'),
      IconItem(icon: Icons.euro, label: '유로', keywords: ['euro', '유로'], category: '금융/결제'),
      IconItem(icon: Icons.currency_yen, label: '엔', keywords: ['yen', '엔'], category: '금융/결제'),
      IconItem(icon: Icons.currency_bitcoin, label: '비트코인', keywords: ['bitcoin', '비트코인'], category: '금융/결제'),
      IconItem(icon: Icons.savings, label: '저금', keywords: ['savings', '저금'], category: '금융/결제'),
      IconItem(icon: Icons.price_check, label: '가격확인', keywords: ['price', '가격'], category: '금융/결제'),
      IconItem(icon: Icons.price_change, label: '가격변동', keywords: ['price', 'change', '변동'], category: '금융/결제'),
      IconItem(icon: Icons.sell, label: '판매', keywords: ['sell', '판매'], category: '금융/결제'),
      IconItem(icon: Icons.shopping_cart_checkout, label: '결제하기', keywords: ['checkout', '결제'], category: '금융/결제'),
      IconItem(icon: Icons.receipt, label: '영수증', keywords: ['receipt', '영수증'], category: '금융/결제'),
      IconItem(icon: Icons.calculate, label: '계산', keywords: ['calculate', '계산'], category: '금융/결제'),
      IconItem(icon: Icons.percent, label: '퍼센트', keywords: ['percent', '퍼센트', '할인'], category: '금융/결제'),
      IconItem(icon: Icons.discount, label: '할인', keywords: ['discount', '할인'], category: '금융/결제'),
      IconItem(icon: Icons.local_offer, label: '태그', keywords: ['offer', '태그', '제안'], category: '금융/결제'),
      IconItem(icon: Icons.loyalty, label: '포인트', keywords: ['loyalty', '포인트'], category: '금융/결제'),
      IconItem(icon: Icons.card_giftcard, label: '기프트카드', keywords: ['gift', 'card', '기프트'], category: '금융/결제'),
      IconItem(icon: Icons.redeem, label: '교환', keywords: ['redeem', '교환'], category: '금융/결제'),
      IconItem(icon: Icons.monetization_on, label: '수익', keywords: ['monetization', '수익'], category: '금융/결제'),
      IconItem(icon: Icons.paid, label: '결제완료', keywords: ['paid', '완료'], category: '금융/결제'),
      IconItem(icon: Icons.request_page, label: '청구서', keywords: ['request', '청구서'], category: '금융/결제'),
    ];
  }
}

/// ✨ 세련된 아이콘 선택 위젯
class _IconPickerWidget extends StatefulWidget {
  final ThemeData theme;
  final String? initialIcon;
  final String? initialIconColor;
  final String? initialBackgroundColor;

  const _IconPickerWidget({
    required this.theme,
    this.initialIcon,
    this.initialIconColor,
    this.initialBackgroundColor,
  });

  @override
  State<_IconPickerWidget> createState() => _IconPickerWidgetState();
}

class _IconPickerWidgetState extends State<_IconPickerWidget> {
  late List<IconItem> _allIcons;
  List<IconItem> _filteredIcons = [];
  IconData? _selectedIcon;
  Color _selectedIconColor = AppColors.surface;
  String _selectedBackgroundColor = '#2196F3';
  String _selectedCategory = '전체';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _categoryScrollController = ScrollController();

  final List<String> _categories = [
    '전체',
    '물류/배송',
    '음식/음료',
    '청소/관리',
    '도구/작업',
    '사무/문서',
    '시간/일정',
    '사람/팀',
    '상태/액션',
    '건물/장소',
    '교통/이동',
    '금융/결제',
  ];

  final List<String> _predefinedColors = [
    '#FFFFFF', // 흰색
    '#000000', // 검정
    '#F44336', // 빨강
    '#E91E63', // 핑크
    '#9C27B0', // 보라
    '#3F51B5', // 인디고
    '#2196F3', // 파랑
    '#00BCD4', // 시안
    '#4CAF50', // 초록
    '#8BC34A', // 라이트그린
    '#FFEB3B', // 노랑
    '#FF9800', // 주황
    '#795548', // 브라운
    '#607D8B', // 블루그레이
  ];

  @override
  void initState() {
    super.initState();
    _allIcons = IconPickerDialog.getAllIcons();
    _selectedBackgroundColor = widget.initialBackgroundColor ?? '#2196F3';
    
    if (widget.initialIconColor != null) {
      _selectedIconColor = FormatHelper.parseColor(widget.initialIconColor!);
    }
    
    if (widget.initialIcon != null && widget.initialIcon!.startsWith('material:')) {
      final codePoint = int.tryParse(widget.initialIcon!.substring(9));
      if (codePoint != null) {
        _selectedIcon = IconData(codePoint, fontFamily: 'MaterialIcons');
      }
    }
    
    _filterIcons();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _categoryScrollController.dispose();
    super.dispose();
  }

  void _filterIcons() {
    setState(() {
      var filtered = _allIcons;
      
      // 카테고리 필터
      if (_selectedCategory != '전체') {
        filtered = filtered.where((icon) => icon.category == _selectedCategory).toList();
      }
      
      // 검색 필터
      if (_searchController.text.isNotEmpty) {
        final query = _searchController.text.toLowerCase();
        filtered = filtered.where((icon) {
          return icon.label.toLowerCase().contains(query) ||
                 icon.keywords.any((keyword) => keyword.toLowerCase().contains(query));
        }).toList();
      }
      
      _filteredIcons = filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 24)),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ✨ 세련된 헤더
            _buildHeader(),
            
            // ✨ 메인 컨텐츠 (스크롤 가능)
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // ✨ 검색바
                    _buildSearchBar(),
                    
                    // ✨ 색상 설정 (선택시에만 표시)
                    if (_selectedIcon != null) _buildColorSettings(),
                    
                    // ✨ 카테고리 탭
                    _buildCategoryTabs(),
                    
                    // ✨ 아이콘 그리드
                    _buildIconGrid(),
                  ],
                ),
              ),
            ),
            
            // ✨ 액션 버튼
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  /// ✨ 세련된 헤더
  Widget _buildHeader() {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            widget.theme.primaryColor,
            widget.theme.primaryColor.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.auto_awesome,
              color: AppColors.surface,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '아이콘 선택',
                  style: ResponsiveHelper.titleStyle(context).copyWith(
                    color: AppColors.surface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  '${_filteredIcons.length}개 아이콘',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: AppColors.surface.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: AppColors.surface.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                child: Icon(
                  Icons.close,
                  color: AppColors.surface,
                  size: ResponsiveHelper.iconSize(context, 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 검색바
  Widget _buildSearchBar() {
    return Padding(
      padding: ResponsiveHelper.cardPadding(context),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '아이콘 검색...',
          prefixIcon: Icon(Icons.search, color: widget.theme.primaryColor),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _filterIcons();
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: AppColors.grey100,
        ),
        onChanged: (_) => _filterIcons(),
      ),
    );
  }

  /// ✨ 카테고리 탭
  Widget _buildCategoryTabs() {
    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      child: Row(
        children: [
          // 왼쪽 화살표
          IconButton(
            icon: Icon(Icons.chevron_left, color: widget.theme.primaryColor),
            onPressed: () {
              _categoryScrollController.animateTo(
                _categoryScrollController.offset - 150,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
          ),
          // 카테고리 목록
          Expanded(
            child: ListView.builder(
              controller: _categoryScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == category;
                
                return Padding(
                  padding: EdgeInsets.only(
                    right: ResponsiveHelper.spacing(context, 8),
                  ),
                  child: Material(
                    color: isSelected
                        ? widget.theme.primaryColor
                        : AppColors.grey200,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedCategory = category;
                          _filterIcons();
                        });
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 16),
                          vertical: ResponsiveHelper.spacing(context, 8),
                        ),
                        child: Text(
                          category,
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: isSelected ? AppColors.surface : AppColors.grey700,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 오른쪽 화살표
          IconButton(
            icon: Icon(Icons.chevron_right, color: widget.theme.primaryColor),
            onPressed: () {
              _categoryScrollController.animateTo(
                _categoryScrollController.offset + 150,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
          ),
        ],
      ),
    );
  }

  /// ✨ 아이콘 그리드
  Widget _buildIconGrid() {
    if (_filteredIcons.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: ResponsiveHelper.iconSize(context, 64),
                color: AppColors.grey400,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              Text(
                '검색 결과가 없습니다',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // 그리드 높이 계산 (반응형)
    final iconSize = ResponsiveHelper.iconSize(context, 56);
    final gapSize = ResponsiveHelper.spacing(context, 8);
    final labelHeight = 30.0;
    final rows = (_filteredIcons.length / 5).ceil();
    final itemHeight = iconSize + gapSize + labelHeight;
    final mainSpacing = ResponsiveHelper.spacing(context, 8);
    final gridHeight = (rows * itemHeight) + (rows - 1) * mainSpacing + 16.0;
    
    return Container(
      height: gridHeight,
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: ResponsiveHelper.spacing(context, 8),
          crossAxisSpacing: ResponsiveHelper.spacing(context, 8),
          mainAxisExtent: itemHeight,
        ),
        itemCount: _filteredIcons.length,
        itemBuilder: (context, index) {
          final iconItem = _filteredIcons[index];
          final isSelected = _selectedIcon == iconItem.icon;
          
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedIcon = iconItem.icon;
              });
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 아이콘
                Container(
                  width: ResponsiveHelper.iconSize(context, 56),
                  height: ResponsiveHelper.iconSize(context, 56),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? LinearGradient(
                            colors: [
                              FormatHelper.parseColor(_selectedBackgroundColor),
                              FormatHelper.parseColor(_selectedBackgroundColor).withValues(alpha: 0.8),
                            ],
                          )
                        : null,
                    color: isSelected ? null : AppColors.grey100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? widget.theme.primaryColor
                          : AppColors.grey300,
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: widget.theme.primaryColor.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    iconItem.icon,
                    color: isSelected ? _selectedIconColor : AppColors.grey700,
                    size: ResponsiveHelper.iconSize(context, 28),
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                // 라벨
                SizedBox(
                  height: 30,
                  child: Center(
                    child: Text(
                      iconItem.label,
                      style: ResponsiveHelper.tinyStyle(context).copyWith(
                        color: isSelected ? widget.theme.primaryColor : AppColors.textSecondary,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: ResponsiveHelper.getFontSize(context, 10),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// ✨ 색상 설정
  Widget _buildColorSettings() {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.grey500.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        title: Row(
          children: [
            Icon(
              Icons.palette,
              color: widget.theme.primaryColor,
              size: ResponsiveHelper.iconSize(context, 20),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '색상 설정',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 아이콘 색상
                Text(
                  '아이콘 색상',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Wrap(
                  spacing: ResponsiveHelper.spacing(context, 8),
                  runSpacing: ResponsiveHelper.spacing(context, 8),
                  children: _predefinedColors.map((colorHex) {
                    final color = FormatHelper.parseColor(colorHex);
                    final isSelected = _selectedIconColor.value == color.value;
                    
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedIconColor = color;
                        });
                      },
                      child: Container(
                        width: ResponsiveHelper.iconSize(context, 32),
                        height: ResponsiveHelper.iconSize(context, 32),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? widget.theme.primaryColor : AppColors.grey400,
                            width: isSelected ? 3 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: widget.theme.primaryColor.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? Icon(
                                Icons.check,
                                color: colorHex == '#FFFFFF' ? Colors.black : AppColors.surface,
                                size: ResponsiveHelper.iconSize(context, 16),
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                
                // 배경색
                Text(
                  '배경색',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Wrap(
                  spacing: ResponsiveHelper.spacing(context, 8),
                  runSpacing: ResponsiveHelper.spacing(context, 8),
                  children: _predefinedColors.map((colorHex) {
                    final color = FormatHelper.parseColor(colorHex);
                    final isSelected = _selectedBackgroundColor == colorHex;
                    
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedBackgroundColor = colorHex;
                        });
                      },
                      child: Container(
                        width: ResponsiveHelper.iconSize(context, 32),
                        height: ResponsiveHelper.iconSize(context, 32),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? widget.theme.primaryColor : AppColors.grey400,
                            width: isSelected ? 3 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: widget.theme.primaryColor.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? Icon(
                                Icons.check,
                                color: colorHex == '#FFFFFF' ? Colors.black : AppColors.surface,
                                size: ResponsiveHelper.iconSize(context, 16),
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 액션 버튼
  Widget _buildActionButtons() {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 16),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                '취소',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    widget.theme.primaryColor,
                    widget.theme.primaryColor.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: widget.theme.primaryColor.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _selectedIcon == null
                      ? null
                      : () {
                          final iconString = 'material:${_selectedIcon!.codePoint}';
                          final colorHex = '#${_selectedIconColor.value.toRadixString(16).padLeft(8, '0').substring(2)}';
                          
                          Navigator.pop(context, {
                            'icon': iconString,
                            'iconColor': colorHex,
                            'backgroundColor': _selectedBackgroundColor,
                          });
                        },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: AppColors.surface,
                          size: ResponsiveHelper.iconSize(context, 20),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Text(
                          '선택 완료',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: AppColors.surface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
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