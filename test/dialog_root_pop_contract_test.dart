// [INVITE-ACCEPT-POP] DialogHelper.showCustom 의 버튼은 **루트 Navigator** 를 닫아야 한다.
//
//   showCustom 은 showDialog(기본 useRootNavigator: true)로 루트에 뜬다. 버튼 위젯은 호출한
//   화면의 context 로 만들어지는데, 그 화면이 탭 안의 중첩 Navigator 에 있으면
//   `Navigator.pop(context)` 는 탭 Navigator 를 닫는다 — 확인창은 그대로, 뒤 화면이 사라지거나
//   아무 일도 없다(Pixel 5 10-23: 초대 수락 취소·관리자 지원 승인).
//   그래서 showCustom 인자 안에서 바깥 context 로 pop 하는 코드가 없어야 한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('showCustom 인자 안에 Navigator.pop(context …) 가 없다', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final s = f.readAsStringSync();
      var i = 0;
      while ((i = s.indexOf('DialogHelper.showCustom', i)) >= 0) {
        final j = s.indexOf('(', i);
        var d = 0;
        var k = j;
        for (; k < s.length; k++) {
          if (s[k] == '(') d++;
          if (s[k] == ')' && --d == 0) break;
        }
        // 주석 줄은 빼고 본다.
        final body = s
            .substring(j, k)
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        if (RegExp(r'Navigator\.pop\(context\b').hasMatch(body)) {
          offenders.add('${f.path}:${s.substring(0, i).split('\n').length}');
        }
        i = k;
      }
    }
    expect(offenders, isEmpty,
        reason: 'Navigator.of(context, rootNavigator: true).pop(...) 를 쓴다: $offenders');
  });
}
