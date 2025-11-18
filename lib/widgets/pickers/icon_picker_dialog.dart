import 'package:flutter/material.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';

/// 아이콘 아이템 클래스
class IconItem {
  final dynamic icon;
  final List<String> keywords;
  final String category;
  final bool isMaterial;
  final bool isPopular;
  
  IconItem({
    required this.icon,
    required this.keywords,
    required this.category,
    this.isMaterial = false,
    this.isPopular = false,
  });
}

/// 아이콘 선택 다이얼로그
class IconPickerDialog {
  /// 아이콘 선택 다이얼로그 표시
  static Future<Map<String, dynamic>?> show({
    required BuildContext context,
    String? initialIcon,
    String? initialIconColor,
    String? initialBackgroundColor,
  }) async {
    final allIcons = _getAllIcons();
    
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _IconPickerWidget(
        allIcons: allIcons,
        initialIcon: initialIcon,
        initialIconColor: initialIconColor,
        initialBackgroundColor: initialBackgroundColor,
      ),
    );
  }

  /// 모든 아이콘 목록 반환 (대폭 확장!)
  static List<IconItem> _getAllIcons() {
    return [
      // ========== 물류/배송 카테고리 (50개+) ==========
      IconItem(icon: '📦', keywords: ['box', '상자', '박스', '포장'], category: '물류/배송', isPopular: true),
      IconItem(icon: '🚚', keywords: ['truck', '트럭', '배송', '운송'], category: '물류/배송', isPopular: true),
      IconItem(icon: '📋', keywords: ['clipboard', '목록', '리스트'], category: '물류/배송', isPopular: true),
      IconItem(icon: '✅', keywords: ['check', '체크', '완료'], category: '물류/배송', isPopular: true),
      IconItem(icon: Icons.inventory, keywords: ['inventory', '재고', '창고'], category: '물류/배송', isMaterial: true, isPopular: true),
      IconItem(icon: Icons.local_shipping, keywords: ['shipping', '배송', '운송'], category: '물류/배송', isMaterial: true, isPopular: true),
      IconItem(icon: '📪', keywords: ['mailbox', '우편함', '메일'], category: '물류/배송'),
      IconItem(icon: '📬', keywords: ['mailbox', '우편함', '메일'], category: '물류/배송'),
      IconItem(icon: '📮', keywords: ['postbox', '우체통', '우편'], category: '물류/배송'),
      IconItem(icon: '📫', keywords: ['mailbox', '우편함'], category: '물류/배송'),
      IconItem(icon: '📭', keywords: ['mailbox', '빈우편함'], category: '물류/배송'),
      IconItem(icon: '🚛', keywords: ['truck', '대형트럭', '운송'], category: '물류/배송'),
      IconItem(icon: '🚐', keywords: ['van', '밴', '배송'], category: '물류/배송'),
      IconItem(icon: '🏭', keywords: ['factory', '공장', '제조'], category: '물류/배송'),
      IconItem(icon: '🏗️', keywords: ['construction', '건설', '공사'], category: '물류/배송'),
      IconItem(icon: '⚙️', keywords: ['gear', '톱니바퀴', '설정'], category: '물류/배송'),
      IconItem(icon: '🔧', keywords: ['wrench', '렌치', '수리'], category: '물류/배송'),
      IconItem(icon: '🔨', keywords: ['hammer', '망치', '작업'], category: '물류/배송'),
      IconItem(icon: '⚒️', keywords: ['tools', '도구', '작업'], category: '물류/배송'),
      IconItem(icon: '🛠️', keywords: ['tools', '도구', '수리'], category: '물류/배송'),
      IconItem(icon: '📊', keywords: ['chart', '차트', '통계'], category: '물류/배송'),
      IconItem(icon: '📈', keywords: ['chart', '상승', '그래프'], category: '물류/배송'),
      IconItem(icon: '📉', keywords: ['chart', '하락', '그래프'], category: '물류/배송'),
      IconItem(icon: '🎯', keywords: ['target', '타겟', '목표'], category: '물류/배송'),
      IconItem(icon: '✔️', keywords: ['check', '체크', '확인'], category: '물류/배송'),
      IconItem(icon: '☑️', keywords: ['checkbox', '체크박스'], category: '물류/배송'),
      IconItem(icon: Icons.warehouse, keywords: ['warehouse', '창고', '보관'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.archive, keywords: ['archive', '보관', '아카이브'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.inbox, keywords: ['inbox', '입고', '받은편지함'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.unarchive, keywords: ['unarchive', '출고'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.category, keywords: ['category', '분류'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.check_box, keywords: ['checkbox', '체크'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.check_circle, keywords: ['check', '완료'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.verified, keywords: ['verified', '검증'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.task_alt, keywords: ['task', '작업', '완료'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.fact_check, keywords: ['check', '검사'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.inventory_2, keywords: ['inventory', '재고2'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.fire_truck, keywords: ['truck', '소방차'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.delivery_dining, keywords: ['delivery', '배달'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.airport_shuttle, keywords: ['shuttle', '셔틀'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.garage, keywords: ['garage', '차고'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.factory, keywords: ['factory', '공장'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.precision_manufacturing, keywords: ['manufacturing', '제조'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.engineering, keywords: ['engineering', '엔지니어링'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.schedule, keywords: ['schedule', '일정'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.today, keywords: ['today', '오늘'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.event, keywords: ['event', '이벤트'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.calendar_month, keywords: ['calendar', '달력'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.qr_code_scanner, keywords: ['qr', '스캔', 'barcode'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.qr_code, keywords: ['qr', 'code'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.production_quantity_limits, keywords: ['quantity', '수량'], category: '물류/배송', isMaterial: true),
      
      // ========== 음식/음료 카테고리 (40개+) ==========
      IconItem(icon: '☕', keywords: ['coffee', '커피', '음료'], category: '음식/음료', isPopular: true),
      IconItem(icon: '🍕', keywords: ['pizza', '피자'], category: '음식/음료', isPopular: true),
      IconItem(icon: '🍔', keywords: ['burger', '햄버거'], category: '음식/음료'),
      IconItem(icon: '🍟', keywords: ['fries', '감자튀김'], category: '음식/음료'),
      IconItem(icon: '🍜', keywords: ['ramen', '라면', '국수'], category: '음식/음료'),
      IconItem(icon: '🍱', keywords: ['bento', '도시락'], category: '음식/음료'),
      IconItem(icon: '🍺', keywords: ['beer', '맥주', '술'], category: '음식/음료'),
      IconItem(icon: '🍰', keywords: ['cake', '케이크', '디저트'], category: '음식/음료'),
      IconItem(icon: '🍪', keywords: ['cookie', '쿠키', '과자'], category: '음식/음료'),
      IconItem(icon: '🍩', keywords: ['donut', '도넛'], category: '음식/음료'),
      IconItem(icon: '🍫', keywords: ['chocolate', '초콜릿'], category: '음식/음료'),
      IconItem(icon: '🍬', keywords: ['candy', '사탕'], category: '음식/음료'),
      IconItem(icon: '🍭', keywords: ['lollipop', '막대사탕'], category: '음식/음료'),
      IconItem(icon: '🍮', keywords: ['custard', '푸딩'], category: '음식/음료'),
      IconItem(icon: '🍯', keywords: ['honey', '꿀'], category: '음식/음료'),
      IconItem(icon: '🥛', keywords: ['milk', '우유'], category: '음식/음료'),
      IconItem(icon: '🧃', keywords: ['juice', '주스'], category: '음식/음료'),
      IconItem(icon: '🧋', keywords: ['bubble', 'tea', '버블티'], category: '음식/음료'),
      IconItem(icon: '🍵', keywords: ['tea', '차', '녹차'], category: '음식/음료'),
      IconItem(icon: '🍶', keywords: ['sake', '사케', '술'], category: '음식/음료'),
      IconItem(icon: '🍷', keywords: ['wine', '와인'], category: '음식/음료'),
      IconItem(icon: '🍸', keywords: ['cocktail', '칵테일'], category: '음식/음료'),
      IconItem(icon: '🍹', keywords: ['drink', '음료', '주스'], category: '음식/음료'),
      IconItem(icon: '🥤', keywords: ['soda', '탄산', '음료'], category: '음식/음료'),
      IconItem(icon: '🍞', keywords: ['bread', '빵'], category: '음식/음료'),
      IconItem(icon: '🥐', keywords: ['croissant', '크루아상'], category: '음식/음료'),
      IconItem(icon: '🥖', keywords: ['baguette', '바게트'], category: '음식/음료'),
      IconItem(icon: '🥨', keywords: ['pretzel', '프레첼'], category: '음식/음료'),
      IconItem(icon: '🥯', keywords: ['bagel', '베이글'], category: '음식/음료'),
      IconItem(icon: '🥞', keywords: ['pancake', '팬케이크'], category: '음식/음료'),
      IconItem(icon: '🧇', keywords: ['waffle', '와플'], category: '음식/음료'),
      IconItem(icon: '🧀', keywords: ['cheese', '치즈'], category: '음식/음료'),
      IconItem(icon: '🍖', keywords: ['meat', '고기'], category: '음식/음료'),
      IconItem(icon: '🍗', keywords: ['chicken', '치킨'], category: '음식/음료'),
      IconItem(icon: '🥩', keywords: ['steak', '스테이크'], category: '음식/음료'),
      IconItem(icon: '🥓', keywords: ['bacon', '베이컨'], category: '음식/음료'),
      IconItem(icon: '🍝', keywords: ['pasta', '파스타'], category: '음식/음료'),
      IconItem(icon: '🍛', keywords: ['curry', '카레'], category: '음식/음료'),
      IconItem(icon: '🍲', keywords: ['pot', '냄비', '스튜'], category: '음식/음료'),
      IconItem(icon: Icons.restaurant, keywords: ['restaurant', '식당'], category: '음식/음료', isMaterial: true),
      IconItem(icon: Icons.restaurant_menu, keywords: ['menu', '메뉴'], category: '음식/음료', isMaterial: true),
      IconItem(icon: Icons.fastfood, keywords: ['fastfood', '패스트푸드'], category: '음식/음료', isMaterial: true),
      IconItem(icon: Icons.local_cafe, keywords: ['cafe', '카페'], category: '음식/음료', isMaterial: true),
      IconItem(icon: Icons.local_bar, keywords: ['bar', '바'], category: '음식/음료', isMaterial: true),
      IconItem(icon: Icons.local_pizza, keywords: ['pizza', '피자'], category: '음식/음료', isMaterial: true),
      IconItem(icon: Icons.local_dining, keywords: ['dining', '식사'], category: '음식/음료', isMaterial: true),
      IconItem(icon: Icons.lunch_dining, keywords: ['lunch', '점심'], category: '음식/음료', isMaterial: true),
      IconItem(icon: Icons.dinner_dining, keywords: ['dinner', '저녁'], category: '음식/음료', isMaterial: true),
      IconItem(icon: Icons.breakfast_dining, keywords: ['breakfast', '아침'], category: '음식/음료', isMaterial: true),
      IconItem(icon: Icons.set_meal, keywords: ['meal', '식사'], category: '음식/음료', isMaterial: true),
      
      // ========== 청소/관리 카테고리 (35개+) ==========
      IconItem(icon: '🧹', keywords: ['broom', '빗자루', '청소'], category: '청소/관리', isPopular: true),
      IconItem(icon: Icons.cleaning_services, keywords: ['cleaning', '청소'], category: '청소/관리', isMaterial: true, isPopular: true),
      IconItem(icon: '🧽', keywords: ['sponge', '스펀지'], category: '청소/관리'),
      IconItem(icon: '🧴', keywords: ['bottle', '병', '세제'], category: '청소/관리'),
      IconItem(icon: '🧺', keywords: ['basket', '바구니', '세탁'], category: '청소/관리'),
      IconItem(icon: '🧼', keywords: ['soap', '비누'], category: '청소/관리'),
      IconItem(icon: '🪣', keywords: ['bucket', '양동이'], category: '청소/관리'),
      IconItem(icon: '🪠', keywords: ['plunger', '뚫어뻥'], category: '청소/관리'),
      IconItem(icon: '🧯', keywords: ['extinguisher', '소화기'], category: '청소/관리'),
      IconItem(icon: '🗑️', keywords: ['trash', '쓰레기통'], category: '청소/관리'),
      IconItem(icon: '♻️', keywords: ['recycle', '재활용'], category: '청소/관리'),
      IconItem(icon: '🚮', keywords: ['litter', '쓰레기'], category: '청소/관리'),
      IconItem(icon: '💧', keywords: ['water', '물'], category: '청소/관리'),
      IconItem(icon: '💦', keywords: ['water', '물', '청소'], category: '청소/관리'),
      IconItem(icon: '🌊', keywords: ['wave', '물결', '세척'], category: '청소/관리'),
      IconItem(icon: Icons.delete, keywords: ['delete', '삭제'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.delete_outline, keywords: ['delete', '삭제'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.delete_forever, keywords: ['delete', '영구삭제'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.delete_sweep, keywords: ['sweep', '청소'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.restore_from_trash, keywords: ['restore', '복원'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.recycling, keywords: ['recycle', '재활용'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.water_drop, keywords: ['water', '물'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.water, keywords: ['water', '물'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.waves, keywords: ['waves', '물결'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.shower, keywords: ['shower', '샤워'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.bathtub, keywords: ['bathtub', '욕조'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.wash, keywords: ['wash', '세탁'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.dry_cleaning, keywords: ['dry', 'cleaning', '드라이'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.local_laundry_service, keywords: ['laundry', '세탁'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.soap, keywords: ['soap', '비누'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.sanitizer, keywords: ['sanitizer', '소독'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.clean_hands, keywords: ['clean', 'hands', '손세척'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.eco, keywords: ['eco', '친환경'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.home_repair_service, keywords: ['repair', '수리'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.plumbing, keywords: ['plumbing', '배관'], category: '청소/관리', isMaterial: true),
      
      // ========== 도구/작업 카테고리 (40개+) ==========
      IconItem(icon: '🔧', keywords: ['wrench', '렌치', '수리'], category: '도구/작업', isPopular: true),
      IconItem(icon: '🔨', keywords: ['hammer', '망치'], category: '도구/작업'),
      IconItem(icon: '⚙️', keywords: ['gear', '톱니바퀴'], category: '도구/작업'),
      IconItem(icon: '🛠️', keywords: ['tools', '도구'], category: '도구/작업'),
      IconItem(icon: '⚒️', keywords: ['hammer', '도구'], category: '도구/작업'),
      IconItem(icon: '🔩', keywords: ['nut', '너트', '볼트'], category: '도구/작업'),
      IconItem(icon: '⚡', keywords: ['electric', '전기'], category: '도구/작업'),
      IconItem(icon: '🔌', keywords: ['plug', '플러그'], category: '도구/작업'),
      IconItem(icon: '💡', keywords: ['bulb', '전구', '아이디어'], category: '도구/작업'),
      IconItem(icon: '🔦', keywords: ['flashlight', '손전등'], category: '도구/작업'),
      IconItem(icon: '🪛', keywords: ['screwdriver', '드라이버'], category: '도구/작업'),
      IconItem(icon: '🪚', keywords: ['saw', '톱'], category: '도구/작업'),
      IconItem(icon: '🪜', keywords: ['ladder', '사다리'], category: '도구/작업'),
      IconItem(icon: '🧰', keywords: ['toolbox', '공구함'], category: '도구/작업'),
      IconItem(icon: '🔗', keywords: ['link', '연결'], category: '도구/작업'),
      IconItem(icon: '⛓️', keywords: ['chain', '체인'], category: '도구/작업'),
      IconItem(icon: '🧲', keywords: ['magnet', '자석'], category: '도구/작업'),
      IconItem(icon: '🗜️', keywords: ['clamp', '클램프'], category: '도구/작업'),
      IconItem(icon: Icons.build, keywords: ['build', '제작'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.handyman, keywords: ['handyman', '수리공'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.construction, keywords: ['construction', '건설'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.carpenter, keywords: ['carpenter', '목수'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.hardware, keywords: ['hardware', '하드웨어'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.settings, keywords: ['settings', '설정'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.settings_applications, keywords: ['settings', '앱설정'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.tune, keywords: ['tune', '조정'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.build_circle, keywords: ['build', '제작'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.home_repair_service, keywords: ['repair', '수리'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.electrical_services, keywords: ['electrical', '전기'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.power, keywords: ['power', '전원'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.flash_on, keywords: ['flash', '번개'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.lightbulb, keywords: ['lightbulb', '전구'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.lightbulb_outline, keywords: ['light', '전구'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.tips_and_updates, keywords: ['tips', '팁'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.design_services, keywords: ['design', '디자인'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.architecture, keywords: ['architecture', '건축'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.roofing, keywords: ['roofing', '지붕'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.foundation, keywords: ['foundation', '기초'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.fence, keywords: ['fence', '울타리'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.stairs, keywords: ['stairs', '계단'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.meeting_room, keywords: ['door', '문'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.window, keywords: ['window', '창문'], category: '도구/작업', isMaterial: true),
      
      // ========== 사무/문서 카테고리 (35개+) ==========
      IconItem(icon: '📝', keywords: ['memo', '메모', '작성'], category: '사무/문서', isPopular: true),
      IconItem(icon: '📄', keywords: ['document', '문서'], category: '사무/문서'),
      IconItem(icon: '📊', keywords: ['chart', '차트'], category: '사무/문서'),
      IconItem(icon: '📋', keywords: ['clipboard', '클립보드'], category: '사무/문서'),
      IconItem(icon: '📌', keywords: ['pin', '핀'], category: '사무/문서'),
      IconItem(icon: '📍', keywords: ['pin', '위치'], category: '사무/문서'),
      IconItem(icon: '✏️', keywords: ['pencil', '연필'], category: '사무/문서'),
      IconItem(icon: '✒️', keywords: ['pen', '펜'], category: '사무/문서'),
      IconItem(icon: '🖊️', keywords: ['pen', '볼펜'], category: '사무/문서'),
      IconItem(icon: '🖋️', keywords: ['pen', '만년필'], category: '사무/문서'),
      IconItem(icon: '🖍️', keywords: ['crayon', '크레용'], category: '사무/문서'),
      IconItem(icon: '📏', keywords: ['ruler', '자'], category: '사무/문서'),
      IconItem(icon: '📐', keywords: ['triangle', '삼각자'], category: '사무/문서'),
      IconItem(icon: '📁', keywords: ['folder', '폴더'], category: '사무/문서'),
      IconItem(icon: '📂', keywords: ['folder', '열린폴더'], category: '사무/문서'),
      IconItem(icon: '📃', keywords: ['page', '페이지'], category: '사무/문서'),
      IconItem(icon: '📑', keywords: ['tabs', '탭'], category: '사무/문서'),
      IconItem(icon: '📓', keywords: ['notebook', '노트'], category: '사무/문서'),
      IconItem(icon: '📔', keywords: ['notebook', '노트'], category: '사무/문서'),
      IconItem(icon: '📕', keywords: ['book', '책'], category: '사무/문서'),
      IconItem(icon: '📖', keywords: ['book', '책'], category: '사무/문서'),
      IconItem(icon: '📗', keywords: ['book', '녹색책'], category: '사무/문서'),
      IconItem(icon: '📘', keywords: ['book', '파란책'], category: '사무/문서'),
      IconItem(icon: '📙', keywords: ['book', '주황책'], category: '사무/문서'),
      IconItem(icon: Icons.assignment, keywords: ['assignment', '과제'], category: '사무/문서', isMaterial: true),
      IconItem(icon: Icons.description, keywords: ['description', '설명'], category: '사무/문서', isMaterial: true),
      IconItem(icon: Icons.article, keywords: ['article', '기사'], category: '사무/문서', isMaterial: true),
      IconItem(icon: Icons.note, keywords: ['note', '노트'], category: '사무/문서', isMaterial: true),
      IconItem(icon: Icons.notes, keywords: ['notes', '노트'], category: '사무/문서', isMaterial: true),
      IconItem(icon: Icons.sticky_note_2, keywords: ['sticky', '포스트잇'], category: '사무/문서', isMaterial: true),
      IconItem(icon: Icons.edit_note, keywords: ['edit', '편집'], category: '사무/문서', isMaterial: true),
      IconItem(icon: Icons.folder, keywords: ['folder', '폴더'], category: '사무/문서', isMaterial: true),
      IconItem(icon: Icons.folder_open, keywords: ['folder', '열린폴더'], category: '사무/문서', isMaterial: true),
      IconItem(icon: Icons.folder_copy, keywords: ['copy', '복사'], category: '사무/문서', isMaterial: true),
      IconItem(icon: Icons.folder_shared, keywords: ['shared', '공유'], category: '사무/문서', isMaterial: true),
      IconItem(icon: Icons.insert_drive_file, keywords: ['file', '파일'], category: '사무/문서', isMaterial: true),
      IconItem(icon: Icons.file_copy, keywords: ['copy', '복사'], category: '사무/문서', isMaterial: true),
      IconItem(icon: Icons.file_present, keywords: ['present', '발표'], category: '사무/문서', isMaterial: true),
      IconItem(icon: Icons.feed, keywords: ['feed', '피드'], category: '사무/문서', isMaterial: true),
      IconItem(icon: Icons.summarize, keywords: ['summarize', '요약'], category: '사무/문서', isMaterial: true),
      IconItem(icon: Icons.receipt_long, keywords: ['receipt', '영수증'], category: '사무/문서', isMaterial: true),
      IconItem(icon: Icons.request_quote, keywords: ['quote', '견적'], category: '사무/문서', isMaterial: true),
      
      // ========== 기타 카테고리 (30개+) ==========
      IconItem(icon: '⭐', keywords: ['star', '별', '즐겨찾기'], category: '기타'),
      IconItem(icon: '❤️', keywords: ['heart', '하트', '좋아요'], category: '기타'),
      IconItem(icon: '👍', keywords: ['thumbsup', '좋아요'], category: '기타'),
      IconItem(icon: '🎯', keywords: ['target', '타겟', '목표'], category: '기타'),
      IconItem(icon: '🏆', keywords: ['trophy', '트로피', '우승'], category: '기타'),
      IconItem(icon: '🎖️', keywords: ['medal', '메달'], category: '기타'),
      IconItem(icon: '🥇', keywords: ['gold', '금메달'], category: '기타'),
      IconItem(icon: '🥈', keywords: ['silver', '은메달'], category: '기타'),
      IconItem(icon: '🥉', keywords: ['bronze', '동메달'], category: '기타'),
      IconItem(icon: '⚡', keywords: ['lightning', '번개', '빠름'], category: '기타'),
      IconItem(icon: '🔥', keywords: ['fire', '불', '인기'], category: '기타'),
      IconItem(icon: '💯', keywords: ['hundred', '백점', '완벽'], category: '기타'),
      IconItem(icon: '✨', keywords: ['sparkle', '반짝'], category: '기타'),
      IconItem(icon: '💎', keywords: ['diamond', '다이아몬드'], category: '기타'),
      IconItem(icon: '👑', keywords: ['crown', '왕관'], category: '기타'),
      IconItem(icon: '🎉', keywords: ['party', '파티', '축하'], category: '기타'),
      IconItem(icon: '🎊', keywords: ['confetti', '축하'], category: '기타'),
      IconItem(icon: '🎈', keywords: ['balloon', '풍선'], category: '기타'),
      IconItem(icon: '🎁', keywords: ['gift', '선물'], category: '기타'),
      IconItem(icon: '🔔', keywords: ['bell', '벨', '알림'], category: '기타'),
      IconItem(icon: '🔕', keywords: ['mute', '음소거'], category: '기타'),
      IconItem(icon: '⏰', keywords: ['alarm', '알람'], category: '기타'),
      IconItem(icon: '⏱️', keywords: ['stopwatch', '스톱워치'], category: '기타'),
      IconItem(icon: '⏲️', keywords: ['timer', '타이머'], category: '기타'),
      IconItem(icon: '📞', keywords: ['phone', '전화'], category: '기타'),
      IconItem(icon: '📱', keywords: ['mobile', '휴대폰'], category: '기타'),
      IconItem(icon: '💻', keywords: ['computer', '컴퓨터'], category: '기타'),
      IconItem(icon: '⌨️', keywords: ['keyboard', '키보드'], category: '기타'),
      IconItem(icon: '🖱️', keywords: ['mouse', '마우스'], category: '기타'),
      IconItem(icon: '🖥️', keywords: ['desktop', '데스크톱'], category: '기타'),
      IconItem(icon: Icons.work, keywords: ['work', '일', '업무'], category: '기타', isMaterial: true),
      IconItem(icon: Icons.star, keywords: ['star', '별'], category: '기타', isMaterial: true),
      IconItem(icon: Icons.star_outline, keywords: ['star', '별'], category: '기타', isMaterial: true),
      IconItem(icon: Icons.favorite, keywords: ['favorite', '좋아요'], category: '기타', isMaterial: true),
      IconItem(icon: Icons.thumb_up, keywords: ['thumbup', '좋아요'], category: '기타', isMaterial: true),
      IconItem(icon: Icons.emoji_events, keywords: ['trophy', '트로피'], category: '기타', isMaterial: true),
      IconItem(icon: Icons.celebration, keywords: ['celebration', '축하'], category: '기타', isMaterial: true),
      IconItem(icon: Icons.notifications, keywords: ['notifications', '알림'], category: '기타', isMaterial: true),
      IconItem(icon: Icons.alarm, keywords: ['alarm', '알람'], category: '기타', isMaterial: true),
      IconItem(icon: Icons.phone, keywords: ['phone', '전화'], category: '기타', isMaterial: true),
    ];
  }
}

/// 아이콘 선택 위젯
class _IconPickerWidget extends StatefulWidget {
  final List<IconItem> allIcons;
  final String? initialIcon;
  final String? initialIconColor;
  final String? initialBackgroundColor;

  const _IconPickerWidget({
    required this.allIcons,
    this.initialIcon,
    this.initialIconColor,
    this.initialBackgroundColor,
  });

  @override
  State<_IconPickerWidget> createState() => _IconPickerWidgetState();
}

class _IconPickerWidgetState extends State<_IconPickerWidget> {
  final TextEditingController _searchController = TextEditingController();
  List<IconItem> _filteredIcons = [];
  dynamic _selectedIcon;
  Color? _selectedIconColor;
  String _selectedBackgroundColor = '#2196F3';
  String _selectedCategory = '전체 (인기)';

  final List<String> _categories = [
    '전체 (인기)',
    '물류/배송',
    '음식/음료',
    '청소/관리',
    '도구/작업',
    '사무/문서',
    '기타',
  ];

  final List<String> _predefinedColors = [
    '#FFFFFF', // ⭐ 흰색 추가!
    '#F44336', // Red
    '#E91E63', // Pink
    '#9C27B0', // Purple
    '#673AB7', // Deep Purple
    '#3F51B5', // Indigo
    '#2196F3', // Blue (default)
    '#03A9F4', // Light Blue
    '#00BCD4', // Cyan
    '#009688', // Teal
    '#4CAF50', // Green
    '#8BC34A', // Light Green
    '#CDDC39', // Lime
    '#FFEB3B', // Yellow
    '#FFC107', // Amber
    '#FF9800', // Orange
    '#FF5722', // Deep Orange
    '#795548', // Brown
    '#9E9E9E', // Grey
    '#607D8B', // Blue Grey
    '#000000', // Black
  ];

  @override
  void initState() {
    super.initState();
    
    _selectedBackgroundColor = widget.initialBackgroundColor ?? '#2196F3';
    if (widget.initialIconColor != null) {
      _selectedIconColor = FormatHelper.parseColor(widget.initialIconColor!);
    }
    
    if (widget.initialIcon != null) {
      final matchingIcon = widget.allIcons.firstWhere(
        (icon) => icon.icon.toString() == widget.initialIcon,
        orElse: () => widget.allIcons.first,
      );
      _selectedIcon = matchingIcon.icon;
    }
    
    _filteredIcons = widget.allIcons.where((icon) => icon.isPopular).toList();
    _searchController.addListener(_filterIcons);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterIcons() {
    final query = _searchController.text.toLowerCase().trim();
    
    setState(() {
      if (query.isEmpty && _selectedCategory == '전체 (인기)') {
        _filteredIcons = widget.allIcons.where((icon) => icon.isPopular).toList();
      } else if (query.isEmpty) {
        _filteredIcons = widget.allIcons
            .where((icon) => icon.category == _selectedCategory)
            .toList();
      } else if (_selectedCategory == '전체 (인기)') {
        _filteredIcons = widget.allIcons.where((icon) {
          return icon.keywords.any((keyword) => keyword.contains(query));
        }).toList();
      } else {
        _filteredIcons = widget.allIcons.where((icon) {
          return icon.category == _selectedCategory &&
                 icon.keywords.any((keyword) => keyword.contains(query));
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('아이콘 선택'),
      content: SizedBox(
        width: double.maxFinite,
        height: ResponsiveHelper.dialogHeight(context),
        child: Column(
          children: [
            // 검색창
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '검색 (예: 입고, 배송, 커피)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            
            // 카테고리 드롭다운
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(
                labelText: '카테고리',
                border: OutlineInputBorder(),
              ),
              items: _categories.map((category) {
                return DropdownMenuItem(
                  value: category,
                  child: Text(category),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCategory = value!;
                  _filterIcons();
                });
              },
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            
            // 아이콘 그리드 - 반응형
            Expanded(
              child: _filteredIcons.isEmpty
                  ? const Center(child: Text('검색 결과가 없습니다'))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final crossAxisCount = width < 300 ? 4 : width < 400 ? 5 : 6;
                        
                        return GridView.builder(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            mainAxisSpacing: ResponsiveHelper.spacing(context, 8),
                            crossAxisSpacing: ResponsiveHelper.spacing(context, 8),
                          ),
                          itemCount: _filteredIcons.length,
                          itemBuilder: (context, index) {
                            final iconItem = _filteredIcons[index];
                            final isSelected = _selectedIcon == iconItem.icon;
                            
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedIcon = iconItem.icon;
                                  _selectedIconColor = iconItem.isMaterial ? Colors.white : null;
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isSelected 
                                      ? FormatHelper.parseColor(_selectedBackgroundColor) 
                                      : Theme.of(context).colorScheme.surface,
                                  border: Border.all(
                                    color: isSelected 
                                        ? Theme.of(context).primaryColor
                                        : Theme.of(context).dividerColor,
                                    width: isSelected ? 2 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: iconItem.isMaterial
                                      ? Icon(
                                          iconItem.icon as IconData,
                                          color: isSelected 
                                              ? (_selectedIconColor ?? Colors.white)
                                              : Theme.of(context).textTheme.bodyMedium?.color,
                                          size: ResponsiveHelper.iconSize(context, 28),
                                        )
                                      : Text(
                                          iconItem.icon.toString(),
                                          style: TextStyle(
                                            fontSize: ResponsiveHelper.iconSize(context, 28),
                                          ),
                                        ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
            
            // Material 아이콘 색상 선택
            if (_selectedIcon != null && _selectedIcon is IconData) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              Text(
                '아이콘 색상', 
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              Wrap(
                spacing: ResponsiveHelper.spacing(context, 8),
                runSpacing: ResponsiveHelper.spacing(context, 8),
                children: _predefinedColors.map((colorHex) {
                  final isSelected = _selectedIconColor != null && 
                                    '#${_selectedIconColor!.value.toRadixString(16).padLeft(8, '0').substring(2)}' == colorHex;
                  final isWhite = colorHex == '#FFFFFF';
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedIconColor = FormatHelper.parseColor(colorHex);
                      });
                    },
                    child: Container(
                      width: ResponsiveHelper.iconSize(context, 32),
                      height: ResponsiveHelper.iconSize(context, 32),
                      decoration: BoxDecoration(
                        color: FormatHelper.parseColor(colorHex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected 
                              ? Colors.black 
                              : (isWhite ? Colors.grey : Theme.of(context).dividerColor),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: isSelected 
                          ? Icon(
                              Icons.check, 
                              color: isWhite ? Colors.black : Colors.white,
                              size: ResponsiveHelper.iconSize(context, 16),
                            ) 
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
            
            // 배경색 선택
            if (_selectedIcon != null) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              Text(
                '배경색', 
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              Wrap(
                spacing: ResponsiveHelper.spacing(context, 8),
                runSpacing: ResponsiveHelper.spacing(context, 8),
                children: _predefinedColors.map((colorHex) {
                  final isSelected = _selectedBackgroundColor == colorHex;
                  final isWhite = colorHex == '#FFFFFF';
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedBackgroundColor = colorHex;
                      });
                    },
                    child: Container(
                      width: ResponsiveHelper.iconSize(context, 32),
                      height: ResponsiveHelper.iconSize(context, 32),
                      decoration: BoxDecoration(
                        color: FormatHelper.parseColor(colorHex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected 
                              ? Colors.black 
                              : (isWhite ? Colors.grey : Theme.of(context).dividerColor),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: isSelected 
                          ? Icon(
                              Icons.check, 
                              color: isWhite ? Colors.black : Colors.white,
                              size: ResponsiveHelper.iconSize(context, 16),
                            ) 
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: _selectedIcon == null
              ? null
              : () {
                  String iconString;
                  if (_selectedIcon is IconData) {
                    iconString = 'material:${_selectedIcon.codePoint}';
                  } else {
                    iconString = _selectedIcon.toString();
                  }
                  
                  String? colorHex;
                  if (_selectedIconColor != null) {
                    colorHex = '#${_selectedIconColor!.value.toRadixString(16).padLeft(8, '0').substring(2)}';
                  }
                  
                  Navigator.pop(context, {
                    'icon': iconString,
                    'iconColor': colorHex,
                    'backgroundColor': _selectedBackgroundColor,
                  });
                },
          child: const Text('선택'),
        ),
      ],
    );
  }
}