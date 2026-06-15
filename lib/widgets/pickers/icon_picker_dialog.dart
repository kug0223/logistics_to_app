import 'package:flutter/material.dart';
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

/// ✨ 아이콘 선택 다이얼로그 (순수 아이콘 피커 — 색상은 호출부에서 처리)
class IconPickerDialog {
  /// 아이콘 선택 다이얼로그 표시. 선택된 [IconItem]을 반환, 취소 시 null.
  static Future<IconItem?> show({
    required BuildContext context,
    String? initialIcon,
    String? initialSearchText,
  }) async {
    final theme = Theme.of(context);
    return showDialog<IconItem>(
      context: context,
      builder: (context) => _IconPickerWidget(
        theme: theme,
        initialIcon: initialIcon,
        initialSearchText: initialSearchText,
      ),
    );
  }

  /// 이름 기반으로 관련 아이콘을 스코어링해 [count]개 반환.
  /// 이름이 비어있으면 기본 추천 아이콘 반환.
  static List<IconItem> getSuggestedIcons(String name, {int count = 6}) {
    final all = getAllIcons();

    if (name.trim().isEmpty) {
      // 업종별 기본 대표 아이콘
      const defaults = [
        0xe1b8, // inventory_2 (피킹/재고)
        0xe86c, // category (분류)
        0xe87d, // checklist (검수)
        0xe558, // restaurant (서빙)
        0xf044, // cleaning_services (청소)
        0xef63, // payments (계산)
        0xe86b, // construction (작업)
        0xe7ef, // people (인력)
      ];
      final result = <IconItem>[];
      for (final cp in defaults) {
        final found = all.where((i) => i.icon.codePoint == cp).toList();
        if (found.isNotEmpty) result.add(found.first);
        if (result.length >= count) break;
      }
      return result;
    }

    final query = name.toLowerCase().trim();

    // 한국어 업무 키워드 → 아이콘 codePoint 우선순위 매핑
    const koreanMap = <String, List<int>>{
      '피킹': [0xe1b8, 0xe8fe, 0xe8f5], // inventory_2, checklist, qr_code_scanner
      '패킹': [0xefce, 0xe1b9, 0xe1b2], // shopping_bag, inventory_2_outlined, all_inbox
      '포장': [0xefce, 0xe1b2, 0xe1b8], // shopping_bag, all_inbox, inventory_2
      '분류': [0xe86c, 0xe8fe, 0xef40], // category, checklist, list_alt
      '소팅': [0xe86c, 0xe8fe, 0xef40],
      '선별': [0xe86c, 0xe1f7, 0xe8fe], // category, fact_check, checklist
      '검수': [0xe1f7, 0xe8fe, 0xe862], // fact_check, checklist, assignment_turned_in
      '검사': [0xe1f7, 0xe862, 0xe86f], // fact_check, assignment_turned_in, checklist
      '입고': [0xe5c5, 0xe835, 0xe1b5], // arrow_downward, move_to_inbox, inbox
      '출고': [0xe5c4, 0xe1bd, 0xe1b1], // arrow_upward, outbox, unarchive
      '적재': [0xe53a, 0xf19d, 0xe558], // local_shipping, forklift, warehouse
      '하역': [0xf19d, 0xe53a, 0xe6ca], // forklift, local_shipping, trolley
      '운반': [0xe53a, 0xe6ca, 0xf19d], // local_shipping, trolley, forklift
      '서빙': [0xe558, 0xe7ef, 0xef7a], // restaurant, people, lunch_dining
      '홀서빙': [0xe558, 0xe7ef, 0xef7a],
      '홀': [0xe558, 0xe7ef, 0xeb81],   // restaurant, people, groups
      '주방': [0xe51a, 0xe558, 0xef6d], // kitchen, restaurant, outdoor_grill
      '주방보조': [0xe51a, 0xe558, 0xef6d],
      '바리스타': [0xe1bc, 0xe53e, 0xf049], // coffee, local_cafe, coffee_maker
      '카페': [0xe53e, 0xe1bc, 0xf049],
      '음료': [0xe53e, 0xe1bc, 0xef08],  // local_cafe, coffee, emoji_food_beverage
      '청소': [0xf044, 0xeba1, 0xef3a],  // cleaning_services, delete_sweep, soap
      '청소부': [0xf044, 0xeba1, 0xef3a],
      '위생': [0xef3a, 0xeb85, 0xf044],  // soap, clean_hands, cleaning_services
      '소독': [0xef3a, 0xeb7f, 0xf044],  // soap, sanitizer, cleaning_services
      '계산': [0xef63, 0xe936, 0xe6d4],  // payments, point_of_sale, calculate
      '캐셔': [0xef63, 0xe936, 0xe870],  // payments, point_of_sale, credit_card
      '계산대': [0xe936, 0xef63, 0xe870],
      '진열': [0xef6f, 0xe8d1, 0xef6e],  // storefront, store, shopping_basket
      '정리': [0xf044, 0xe86c, 0xe8fe],  // cleaning_services, category, checklist
      '재고': [0xe1b4, 0xe63f, 0xe1b8],  // inventory, warehouse, inventory_2
      '창고': [0xe63f, 0xe1b4, 0xe1b8],  // warehouse, inventory, inventory_2
      '배달': [0xe558, 0xe53a, 0xe1b8],  // delivery_dining, local_shipping
      '배송': [0xe53a, 0xe558, 0xf22c],  // local_shipping, delivery_dining, fire_truck
      '조립': [0xe6d2, 0xe8d4, 0xe869],  // precision_manufacturing, settings_input_component, build
      '제조': [0xe6d2, 0xf014, 0xe869],  // precision_manufacturing, factory, build
      '생산': [0xe6d2, 0xf014, 0xf134],  // precision_manufacturing, factory, work
      '농': [0xea06, 0xe3a8, 0xea20],    // agriculture, grass, yard
      '수확': [0xea06, 0xe3a8, 0xe8d5],  // agriculture, grass, eco
      '농작업': [0xea06, 0xea20, 0xe3a8],
      '이동': [0xe839, 0xe6ca, 0xf19d],  // directions_car, trolley, forklift
      '안전': [0xe1f3, 0xe8d5, 0xe32a],  // health_and_safety, eco(?), shield
      '관리': [0xe8d3, 0xf083, 0xe8b8],  // manage_accounts, admin_panel_settings, settings
      '사무': [0xe873, 0xe873, 0xe164],  // assignment, description
      '데이터': [0xe19c, 0xef49, 0xe0ca], // analytics, insights, dashboard
      // 농업/자연
      '농업': [0xea06, 0xf80d, 0xe3a8],   // agriculture, grain, grass
      '농장': [0xea06, 0xe60b, 0xe3a8],   // agriculture, energy_savings_leaf, grass
      '식물': [0xea20, 0xe7a0, 0xe3a8],   // yard, local_florist, grass
      '꽃': [0xe7a0, 0xeb4f, 0xe60b],     // local_florist, spa, energy_savings_leaf
      '온도': [0xf00f, 0xe30a, 0xef54],   // thermostat, ac_unit, water
      '반려동물': [0xe532, 0xeb18, 0xe32a], // pets, cruelty_free, shield
      // 서비스/뷰티
      '미용': [0xe150, 0xf29e, 0xf24c],   // content_cut, face_retouching_natural, dry
      '헤어': [0xe150, 0xf24c, 0xf2be],   // content_cut, dry, auto_fix_high
      '네일': [0xf29e, 0xf2be, 0xe150],   // face_retouching_natural, auto_fix_high
      '에스테틱': [0xf29e, 0xeb4f, 0xf2be],
      '돌봄': [0xea0c, 0xf6d4, 0xe3a9],  // child_care, elderly, accessibility_new
      '상담': [0xf22b, 0xe61e, 0xe31d],  // support_agent, psychology, headset_mic
      '세탁': [0xe7fb, 0xe354, 0xe3c1],  // local_laundry_service, wash, dry_cleaning
      // 스포츠/이벤트
      '스포츠': [0xea15, 0xe3b0, 0xef55], // sports, fitness_center, pool
      '헬스': [0xe3b0, 0xea15, 0xef55],  // fitness_center, sports, pool
      '파티': [0xe651, 0xe6e0, 0xefda],  // celebration, emoji_events, festival
      '행사': [0xe651, 0xefda, 0xe7fd],  // celebration, festival, local_activity
      '이벤트': [0xe651, 0xefda, 0xe7fd],
      '공연': [0xf1e9, 0xe663, 0xf048],  // theater_comedy, movie, music_note
      '축제': [0xefda, 0xe651, 0xf09e],  // festival, celebration, attractions
    };

    // 우선순위 codePoint 수집
    final priorityCPs = <int>{};
    for (final entry in koreanMap.entries) {
      if (query.contains(entry.key)) {
        priorityCPs.addAll(entry.value);
      }
    }

    // 스코어 계산
    final scored = all.map((icon) {
      int score = 0;
      if (priorityCPs.contains(icon.icon.codePoint)) score += 30;
      if (icon.label.toLowerCase().contains(query)) score += 10;
      for (final kw in icon.keywords) {
        if (kw.toLowerCase().contains(query)) score += 5;
        if (query.contains(kw.toLowerCase()) && kw.length > 1) score += 3;
      }
      return (icon: icon, score: score);
    }).where((e) => e.score > 0).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final result = scored.take(count).map((e) => e.icon).toList();

    // 부족하면 기본 아이콘으로 채우기
    if (result.length < count) {
      final defaults = getSuggestedIcons('', count: count);
      for (final d in defaults) {
        if (result.length >= count) break;
        if (!result.any((r) => r.icon.codePoint == d.icon.codePoint)) {
          result.add(d);
        }
      }
    }
    return result;
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

      // ========== 🌱 농업/자연 카테고리 (22개) ==========
      IconItem(icon: Icons.agriculture, label: '농업', keywords: ['agriculture', '농업', '트랙터'], category: '농업/자연'),
      IconItem(icon: Icons.grain, label: '곡물', keywords: ['grain', '곡물', '쌀', '밀'], category: '농업/자연'),
      IconItem(icon: Icons.energy_savings_leaf, label: '친환경', keywords: ['leaf', '친환경', '녹색'], category: '농업/자연'),
      IconItem(icon: Icons.grass, label: '잔디밭', keywords: ['grass', '잔디', '풀'], category: '농업/자연'),
      IconItem(icon: Icons.yard, label: '마당', keywords: ['yard', '마당', '정원'], category: '농업/자연'),
      IconItem(icon: Icons.park, label: '공원', keywords: ['park', '공원'], category: '농업/자연'),
      IconItem(icon: Icons.forest, label: '숲', keywords: ['forest', '숲', '나무'], category: '농업/자연'),
      IconItem(icon: Icons.nature, label: '자연', keywords: ['nature', '자연'], category: '농업/자연'),
      IconItem(icon: Icons.local_florist, label: '꽃/화원', keywords: ['florist', '꽃', '화원', '식물'], category: '농업/자연'),
      IconItem(icon: Icons.spa, label: '스파/꽃', keywords: ['spa', '꽃잎', '식물'], category: '농업/자연'),
      IconItem(icon: Icons.landscape, label: '경관', keywords: ['landscape', '경관', '산'], category: '농업/자연'),
      IconItem(icon: Icons.terrain, label: '지형', keywords: ['terrain', '지형', '산지'], category: '농업/자연'),
      IconItem(icon: Icons.water, label: '물', keywords: ['water', '물', '수자원'], category: '농업/자연'),
      IconItem(icon: Icons.water_drop, label: '물방울', keywords: ['drop', '물방울', '이슬'], category: '농업/자연'),
      IconItem(icon: Icons.wb_sunny, label: '햇빛', keywords: ['sunny', '햇빛', '태양'], category: '농업/자연'),
      IconItem(icon: Icons.wb_cloudy, label: '구름', keywords: ['cloudy', '구름', '날씨'], category: '농업/자연'),
      IconItem(icon: Icons.thermostat, label: '온도', keywords: ['thermostat', '온도', '온도계'], category: '농업/자연'),
      IconItem(icon: Icons.ac_unit, label: '냉각/설비', keywords: ['ac', '냉각', '설비'], category: '농업/자연'),
      IconItem(icon: Icons.pets, label: '반려동물', keywords: ['pets', '동물', '반려'], category: '농업/자연'),
      IconItem(icon: Icons.cruelty_free, label: '동물보호', keywords: ['cruelty', '동물보호'], category: '농업/자연'),
      IconItem(icon: Icons.compost, label: '퇴비/유기', keywords: ['compost', '퇴비', '유기농'], category: '농업/자연'),
      IconItem(icon: Icons.beach_access, label: '야외작업', keywords: ['beach', '야외', '파라솔'], category: '농업/자연'),

      // ========== 💆 서비스/뷰티 카테고리 (22개) ==========
      IconItem(icon: Icons.content_cut, label: '미용/이발', keywords: ['cut', '미용', '이발', '헤어'], category: '서비스/뷰티'),
      IconItem(icon: Icons.face_retouching_natural, label: '피부관리', keywords: ['face', '피부', '관리', '에스테틱'], category: '서비스/뷰티'),
      IconItem(icon: Icons.auto_fix_high, label: '스타일링', keywords: ['styling', '스타일링', '마법봉'], category: '서비스/뷰티'),
      IconItem(icon: Icons.dry, label: '드라이', keywords: ['dry', '드라이', '헤어드라이어'], category: '서비스/뷰티'),
      IconItem(icon: Icons.style, label: '패션/스타일', keywords: ['style', '패션', '스타일'], category: '서비스/뷰티'),
      IconItem(icon: Icons.checkroom, label: '의류/옷', keywords: ['checkroom', '옷', '의류', '행거'], category: '서비스/뷰티'),
      IconItem(icon: Icons.self_improvement, label: '명상/요가', keywords: ['self', '명상', '요가', '힐링'], category: '서비스/뷰티'),
      IconItem(icon: Icons.healing, label: '치유/케어', keywords: ['healing', '치유', '케어'], category: '서비스/뷰티'),
      IconItem(icon: Icons.psychology, label: '상담/심리', keywords: ['psychology', '상담', '심리'], category: '서비스/뷰티'),
      IconItem(icon: Icons.support_agent, label: '고객상담', keywords: ['support', '상담', '고객'], category: '서비스/뷰티'),
      IconItem(icon: Icons.headset_mic, label: '헤드셋', keywords: ['headset', '헤드셋', '콜센터'], category: '서비스/뷰티'),
      IconItem(icon: Icons.camera_alt, label: '사진촬영', keywords: ['camera', '사진', '촬영'], category: '서비스/뷰티'),
      IconItem(icon: Icons.child_care, label: '아이돌봄', keywords: ['child', '아이', '돌봄', '베이비시터'], category: '서비스/뷰티'),
      IconItem(icon: Icons.child_friendly, label: '아동친화', keywords: ['friendly', '아동', '유아'], category: '서비스/뷰티'),
      IconItem(icon: Icons.elderly, label: '어르신케어', keywords: ['elderly', '어르신', '노인', '돌봄'], category: '서비스/뷰티'),
      IconItem(icon: Icons.accessibility_new, label: '복지/케어', keywords: ['accessibility', '복지', '장애'], category: '서비스/뷰티'),
      IconItem(icon: Icons.local_laundry_service, label: '세탁서비스', keywords: ['laundry', '세탁', '서비스'], category: '서비스/뷰티'),
      IconItem(icon: Icons.iron, label: '다림질', keywords: ['iron', '다림질', '다리미'], category: '서비스/뷰티'),
      IconItem(icon: Icons.home_repair_service, label: '가정수리', keywords: ['repair', '수리', '가정'], category: '서비스/뷰티'),
      IconItem(icon: Icons.room_service, label: '룸서비스', keywords: ['room', '룸서비스', '호텔'], category: '서비스/뷰티'),
      IconItem(icon: Icons.hotel, label: '호텔/숙박', keywords: ['hotel', '호텔', '숙박'], category: '서비스/뷰티'),
      IconItem(icon: Icons.spa, label: '웰니스', keywords: ['wellness', '웰니스', '릴랙스'], category: '서비스/뷰티'),

      // ========== 🏆 스포츠/이벤트 카테고리 (22개) ==========
      IconItem(icon: Icons.sports, label: '스포츠', keywords: ['sports', '스포츠', '경기'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.fitness_center, label: '헬스장', keywords: ['fitness', '헬스', '운동'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.sports_soccer, label: '축구', keywords: ['soccer', '축구', '풋볼'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.sports_basketball, label: '농구', keywords: ['basketball', '농구'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.sports_baseball, label: '야구', keywords: ['baseball', '야구'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.sports_tennis, label: '테니스', keywords: ['tennis', '테니스'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.pool, label: '수영', keywords: ['pool', '수영', '수영장'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.hiking, label: '하이킹', keywords: ['hiking', '하이킹', '등산'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.celebration, label: '파티/행사', keywords: ['celebration', '파티', '행사', '이벤트'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.emoji_events, label: '트로피', keywords: ['trophy', '트로피', '상', '수상'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.local_activity, label: '티켓/입장', keywords: ['activity', '티켓', '입장'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.theater_comedy, label: '공연/연극', keywords: ['theater', '공연', '연극'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.movie, label: '영화', keywords: ['movie', '영화', '촬영'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.music_note, label: '음악', keywords: ['music', '음악', '노래'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.mic, label: '마이크', keywords: ['mic', '마이크', '방송'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.festival, label: '축제', keywords: ['festival', '축제', '행사'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.attractions, label: '놀이공원', keywords: ['attractions', '놀이공원', '어트랙션'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.casino, label: '카지노/오락', keywords: ['casino', '오락', '게임'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.outdoor_grill, label: '야외바베큐', keywords: ['grill', '바베큐', '야외'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.sports_handball, label: '핸드볼', keywords: ['handball', '핸드볼', '구기'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.sports_martial_arts, label: '격투/무술', keywords: ['martial', '무술', '격투'], category: '스포츠/이벤트'),
      IconItem(icon: Icons.sports_gymnastics, label: '체조', keywords: ['gymnastics', '체조', '운동'], category: '스포츠/이벤트'),
    ];
  }
}

/// ✨ 세련된 아이콘 선택 위젯
class _IconPickerWidget extends StatefulWidget {
  final ThemeData theme;
  final String? initialIcon;
  final String? initialSearchText;

  const _IconPickerWidget({
    required this.theme,
    this.initialIcon,
    this.initialSearchText,
  });

  @override
  State<_IconPickerWidget> createState() => _IconPickerWidgetState();
}

class _IconPickerWidgetState extends State<_IconPickerWidget> {
  late List<IconItem> _allIcons;
  List<IconItem> _filteredIcons = [];
  IconData? _selectedIcon;
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
    '농업/자연',
    '서비스/뷰티',
    '스포츠/이벤트',
  ];

  @override
  void initState() {
    super.initState();
    _allIcons = IconPickerDialog.getAllIcons();

    if (widget.initialIcon != null && widget.initialIcon!.startsWith('material:')) {
      final codePoint = int.tryParse(widget.initialIcon!.substring(9));
      if (codePoint != null) {
        _selectedIcon = IconData(codePoint, fontFamily: 'MaterialIcons');
      }
    }

    if (widget.initialSearchText != null && widget.initialSearchText!.isNotEmpty) {
      _searchController.text = widget.initialSearchText!;
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
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
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
    final h = ResponsiveHelper.spacing(context, 16);
    return Padding(
      padding: EdgeInsets.fromLTRB(h, h, h, h * 0.5),
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
    final h = ResponsiveHelper.spacing(context, 16);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 40,
          child: ListView.builder(
            controller: _categoryScrollController,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: h),
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final category = _categories[index];
              final isSelected = _selectedCategory == category;

              return Padding(
                padding: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
                child: GestureDetector(
                  onTap: () => setState(() {
                    _selectedCategory = category;
                    _filterIcons();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 14),
                      vertical: ResponsiveHelper.spacing(context, 7),
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? widget.theme.primaryColor
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? widget.theme.primaryColor
                            : AppColors.grey300,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      category,
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: isSelected ? Colors.white : AppColors.grey600,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Divider(height: 1, color: AppColors.grey200),
      ],
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
                    color: isSelected ? widget.theme.primaryColor : AppColors.grey100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? widget.theme.primaryColor : AppColors.grey300,
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
                    color: isSelected ? Colors.white : AppColors.grey700,
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

  /// ✨ 액션 버튼
  Widget _buildActionButtons() {
    // 선택된 아이콘의 label 찾기
    final selectedItem = _selectedIcon == null
        ? null
        : _allIcons.firstWhere(
            (i) => i.icon.codePoint == _selectedIcon!.codePoint,
            orElse: () => IconItem(icon: _selectedIcon!, label: '', keywords: [], category: ''),
          );

    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.grey200)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 선택된 아이콘 미리보기
          if (_selectedIcon != null) ...[
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 12),
                vertical: ResponsiveHelper.spacing(context, 8),
              ),
              decoration: BoxDecoration(
                color: widget.theme.primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: widget.theme.primaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(_selectedIcon, color: Colors.white, size: ResponsiveHelper.iconSize(context, 18)),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                  Expanded(
                    child: Text(
                      selectedItem?.label.isNotEmpty == true
                          ? '${selectedItem!.label} 선택됨'
                          : '아이콘 선택됨',
                      style: ResponsiveHelper.smallStyle(context).copyWith(
                        color: widget.theme.primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selectedIcon = null),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '선택 해제',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: AppColors.grey500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          ],
          // 버튼 행
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 14)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('취소', style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.bold)),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _selectedIcon == null
                      ? null
                      : () => Navigator.pop(context, selectedItem),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 14)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    backgroundColor: widget.theme.primaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.grey200,
                  ),
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: Text(
                    '선택 완료',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: _selectedIcon == null ? AppColors.grey400 : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}