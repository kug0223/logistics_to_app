import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

/// [L30 · 탭 분석 §3-15] PDF 한글 폰트(NotoSansKR 2종 · 각 약 6.2MB) 앱 세션 공용 캐시.
///
///   계약서 PDF 는 만들 때마다 두 폰트를 번들에서 읽고 해석했다(서명 완료마다 1회씩).
///   임금명세서(`PayslipPdfBuilder`)가 이미 쓰던 static 캐시 방식과 같다 — 세션 안 최초 1회만 해석한다.
///   · 값(Font)을 담는다 — Future 를 공유하지 않는다(zone 에 갇히지 않게 · r3). 동시 첫 요청은 각자 해석할 수 있다.
///   · 실패하면 담지 않는다 — 다음 요청이 다시 읽는다.
///   다른 PDF(근태 목록 · 임금명세서)도 이 캐시로 모을 수 있다 — 그 파일들은 이번 셀에서 바꾸지 않았다.
class PdfFontCache {
  PdfFontCache._();

  static const regularAsset = 'assets/fonts/NotoSansKR-Regular.ttf';
  static const boldAsset = 'assets/fonts/NotoSansKR-Bold.ttf';

  /// 시험이 번들 읽기를 바꿔 끼울 수 있는 자리(production = rootBundle.load).
  @visibleForTesting
  static Future<ByteData> Function(String key) loader = rootBundle.load;

  // [L30 r3] **값**을 담는다 — Future 를 담지 않는다.
  //   완료된 Future 도 listener 를 그 Future 가 만들어진 zone 에서 부른다. 정적 Future 를 여러 zone(시험의 FakeAsync 등)이
  //   공유하면 이미 끝난 zone 에서 만든 Future 를 기다리다 멈춘다. 값이면 매 호출이 호출자 zone 의 새 Future 를 돌려준다.
  //   동시 첫 요청은 각자 해석할 수 있다(결과 동일 · 마지막 값 유지 · 예전 임금명세서 캐시와 같은 방식). 실패는 담지 않는다.
  static pw.Font? _regular;
  static pw.Font? _bold;

  // async 함수 = 보통 Future(번들 읽기가 SynchronousFuture 여도 `Future.wait` 가 값을 받는다 · PF-5).
  static Future<pw.Font> regular() async =>
      _regular ??= pw.Font.ttf(await loader(regularAsset));

  static Future<pw.Font> bold() async => _bold ??= pw.Font.ttf(await loader(boldAsset));

  /// [PERF-L41 · impl_17] 폰트 **원본 바이트** — 해석을 다른 isolate 로 넘길 때 쓴다(번들 읽기는 이 isolate 에서만 된다).
  ///   시험이 바꿔 끼운 [loader] 를 그대로 따른다. 캐시하지 않는다(해석 결과 캐시는 위 [regular]/[bold]).
  static Future<ByteData> loadBytes(String asset) => loader(asset);

  @visibleForTesting
  static void resetForTest() {
    _regular = null;
    _bold = null;
    loader = rootBundle.load;
  }
}
