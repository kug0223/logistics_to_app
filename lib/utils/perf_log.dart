import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// [PERF-FIRST-LOAD · 판정289 §8 C289-07] 첫 진입 최소 계측.
///
/// ## 켜는 법
///   `flutter run --profile --dart-define=ALFIT_PERF=true` (프레임) ·
///   `flutter run --release --dart-define=ALFIT_PERF=true` (절대 시간).
///   **기본 빌드(debug 포함)는 꺼져 있다** — `enabled` 가 컴파일 상수 false 라 [mark] 본문이
///   비고, `extra` 는 함수로 받아서 꺼진 빌드에서는 **계산하지 않는다**(출력 0 · 추가 계산 0).
///
/// ## 출력 — 이 파일의 `print` 한 곳이 LOG-01 의 유일한 예외다
///   main 은 debug 가 아니면 `debugPrint` 를 no-op 으로 바꾼다(main.dart) — release perf 빌드에서
///   debugPrint 로는 아무것도 남지 않는다. 그래서 전용 sink 하나만 `print` 를 쓴다.
///   다른 곳의 print 허용 · debugPrint 복원 · lint 전역 무시가 아니다.
///   로컬 기기 로그(logcat · `flutter logs`)로만 나간다. Analytics/Crashlytics 로 보내지 않는다.
///
/// ## 형식
///   `[PERF] +<ms>ms #<seq> run=<runId> <event> k=v ...`
///   · ms = main 첫 Dart 줄에서 시작한 **단조 Stopwatch** 기준(이벤트를 취득한 시각). 네이티브
///     시작(프로세스 생성 · 엔진 로드 · 네이티브 스플래시 이전)은 들어 있지 않다.
///   · seq = 이 실행에서 몇 번째 표식인지 · runId = 사람과 무관한 실행 번호(시작 시각 마이크로초 하위 자리).
///   · event = 정적 이름(코드에 박힌 문자열)만. extra = 소요·개수·크기·성공 여부/코드만.
///   **uid·이름·전화·주소·토큰·URL·본문·계약/신분/임금 값·예외 문자열을 넣지 않는다.**
///
/// ## 상한
///   한 실행에 최대 [_kMaxLines] 줄 — 넘으면 한 번 알리고 멈춘다. 프레임은 매 프레임 찍지 않고
///   [_kFrameWindow] 프레임마다 요약 한 줄(예산 초과 수 · 최대 build/raster).
class PerfLog {
  PerfLog._();

  /// 컴파일 상수 — `--dart-define=ALFIT_PERF=true` 일 때만 true.
  static const bool enabled = bool.fromEnvironment('ALFIT_PERF');

  static const int _kMaxLines = 600;
  static const int _kFrameWindow = 120;

  static final Stopwatch _clock = Stopwatch();
  static int _seq = 0;
  static int _lines = 0;
  static int _runId = 0;
  static bool _framesWatched = false;

  /// main() 첫 줄에서 부른다 — t0.
  static void start() {
    if (!enabled) return;
    if (_clock.isRunning) return;
    _clock.start();
    _runId = DateTime.now().microsecondsSinceEpoch % 100000;
    mark('main.start');
  }

  /// 정적 이름 [event] 에 지금 시각을 찍는다. [extra] 는 켜진 빌드에서만 계산한다.
  static void mark(String event, [Map<String, Object?> Function()? extra]) {
    if (!enabled) return;
    if (!_clock.isRunning) _clock.start();
    final ms = _clock.elapsedMilliseconds;
    if (_lines >= _kMaxLines) return;
    _lines++;
    final seq = ++_seq;
    final buf = StringBuffer('[PERF] +${ms}ms #$seq run=$_runId $event');
    if (extra != null) {
      Map<String, Object?> kv;
      try {
        kv = extra();
      } catch (_) {
        kv = const {'extraError': true};
      }
      kv.forEach((k, v) {
        // 값은 숫자·불리언·짧은 코드만 — 긴 문자열은 잘라 쓴다(본문이 새지 않게).
        final s = v is String && v.length > 24 ? v.substring(0, 24) : v;
        buf.write(' $k=$s');
      });
    }
    if (_lines == _kMaxLines) buf.write(' (line cap reached)');
    _sink(buf.toString());
  }

  /// 프레임 요약을 켠다(한 번만). [_kFrameWindow] 프레임마다 한 줄.
  static void watchFrames() {
    if (!enabled || _framesWatched) return;
    _framesWatched = true;
    var frames = 0;
    var overBudget = 0;
    var maxBuild = 0;
    var maxRaster = 0;
    final budgetUs = _frameBudgetUs();
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        frames++;
        final b = t.buildDuration.inMicroseconds;
        final r = t.rasterDuration.inMicroseconds;
        if (b > maxBuild) maxBuild = b;
        if (r > maxRaster) maxRaster = r;
        if (t.totalSpan.inMicroseconds > budgetUs) overBudget++;
        if (frames >= _kFrameWindow) {
          mark('frames', () => {
                'n': frames,
                'over': overBudget,
                'budgetUs': budgetUs,
                'maxBuildUs': maxBuild,
                'maxRasterUs': maxRaster,
              });
          frames = 0;
          overBudget = 0;
          maxBuild = 0;
          maxRaster = 0;
        }
      }
    });
  }

  /// 실제 주사율 기준 프레임 예산(µs). 모르면 60Hz.
  static int _frameBudgetUs() {
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      final hz = views.isEmpty ? 60.0 : views.first.display.refreshRate;
      return (1e6 / (hz <= 0 ? 60.0 : hz)).round();
    } catch (_) {
      return 16667;
    }
  }

  static void _sink(String line) {
    // [LOG-01 예외 · 판정289 §8] 전용 sink 의 직접 print 1곳. 켜진 perf 빌드에서만 도달한다.
    // ignore: avoid_print
    print(line);
  }
}
