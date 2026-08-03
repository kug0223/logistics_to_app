import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// iBeacon / Eddystone 비콘 스캔 유틸
///
/// 사업장에 설치된 BLE 비콘 기기를 스캔하여
/// 출퇴근 체크에 사용할 근접 여부를 판단한다.
class BeaconHelper {
  BeaconHelper._();

  // ─── 권한 요청 ──────────────────────────────────────────────

  /// BLE 스캔 권한 확인 및 요청
  /// 반환: true = 권한 있음, false = 거부됨
  static Future<bool> requestPermission() async {
    // 블루투스 활성화 확인 — timeout 3초 (일부 기기에서 무한 대기 방지)
    final adapterState = await FlutterBluePlus.adapterState.first
        .timeout(const Duration(seconds: 3),
            onTimeout: () => BluetoothAdapterState.unknown);
    if (adapterState != BluetoothAdapterState.on) {
      debugPrint('⚠️ [Beacon] 블루투스가 꺼져 있습니다');
      return false;
    }

    // Android 12+ 는 BLUETOOTH_SCAN 권한 필요
    final scanPerm = await Permission.bluetoothScan.request();
    final connectPerm = await Permission.bluetoothConnect.request();

    if (!scanPerm.isGranted || !connectPerm.isGranted) {
      debugPrint('⚠️ [Beacon] 블루투스 권한 거부됨');
      // 영구 거부 시 설정 안내
      if (scanPerm.isPermanentlyDenied || connectPerm.isPermanentlyDenied) {
        await openAppSettings();
      }
      return false;
    }
    return true;
  }

  // ─── 비콘 근접 확인 ────────────────────────────────────────

  /// 지정된 UUID의 비콘이 근처에 있는지 확인
  ///
  /// [uuid]            비콘 UUID (대문자, 하이픈 포함)
  /// [major]           Major 값 (null = 무시)
  /// [minor]           Minor 값 (null = 무시)
  /// [rssiThreshold]   신호 강도 임계값 (dBm, 기본 -75 ≈ 3~5m)
  /// [timeout]         스캔 최대 대기 시간
  ///
  /// 반환: null = 스캔 실패/권한없음, true/false = 근접 여부
  static Future<bool?> isBeaconNearby({
    required String uuid,
    int? major,
    int? minor,
    int rssiThreshold = -75,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;

    final normalizedUUID = uuid.toUpperCase();
    bool? found;

    try {
      final completer = Completer<bool>();
      StreamSubscription? sub;

      // startScan은 스캔 완료(timeout)까지 resolve하는 Future이므로 await 불가.
      // 에러(BT off 등)만 completer로 전파하여 catch 없이 누수되지 않도록 처리.
      FlutterBluePlus.startScan(timeout: timeout).catchError((Object e) {
        debugPrint('❌ [Beacon] startScan 실패: $e');
        if (!completer.isCompleted) completer.complete(false);
      });

      sub = FlutterBluePlus.scanResults.listen(
        (results) {
          for (final result in results) {
            if (!completer.isCompleted &&
                _matchesBeacon(result, normalizedUUID, major, minor) &&
                result.rssi >= rssiThreshold) {
              debugPrint(
                '✅ [Beacon] 비콘 감지: UUID=$normalizedUUID, RSSI=${result.rssi}dBm, '
                '거리≈${rssiToDistance(result.rssi).toStringAsFixed(1)}m',
              );
              completer.complete(true);
            }
          }
        },
        onError: (e) {
          debugPrint('⚠️ [Beacon] 스캔 에러: $e');
          if (!completer.isCompleted) completer.complete(false);
        },
        cancelOnError: true,
      );

      // timeout 후 미발견
      Future.delayed(timeout, () {
        if (!completer.isCompleted) {
          debugPrint('⚠️ [Beacon] 타임아웃: UUID=$normalizedUUID 비콘 미발견');
          completer.complete(false);
        }
      });

      found = await completer.future;
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('❌ [Beacon] 스캔 실패: $e');
      // 예외 시 리소스 정리 (stopScan 누수 방지)
      try { await FlutterBluePlus.stopScan(); } catch (_) {}
      return null;
    }

    return found;
  }

  // ─── 비콘 매칭 ────────────────────────────────────────────

  /// iBeacon 광고 데이터에서 UUID/Major/Minor 추출 후 매칭
  static bool _matchesBeacon(
    ScanResult result,
    String uuid,
    int? major,
    int? minor,
  ) {
    // iBeacon: manufacturer data (company 0x004C, type 0x02)
    final mfrData = result.advertisementData.manufacturerData;
    if (mfrData.containsKey(0x004C)) {
      final data = mfrData[0x004C]!;
      if (data.length >= 23 && data[0] == 0x02 && data[1] == 0x15) {
        final beaconUUID = _parseUUID(data.sublist(2, 18));
        final beaconMajor = (data[18] << 8) | data[19];
        final beaconMinor = (data[20] << 8) | data[21];

        if (beaconUUID != uuid) return false;
        if (major != null && beaconMajor != major) return false;
        if (minor != null && beaconMinor != minor) return false;
        return true;
      }
    }

    // service UUID로 폴백 (Eddystone 등)
    final serviceUUIDs = result.advertisementData.serviceUuids;
    return serviceUUIDs.any((u) => u.str.toUpperCase() == uuid);
  }

  static String _parseUUID(List<int> bytes) {
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}'
        .toUpperCase();
  }

  // ─── 거리 추정 ────────────────────────────────────────────

  /// RSSI → 거리(m) 변환 (Log-Distance Path Loss 모델)
  ///
  /// [rssi]    측정된 신호 강도 (dBm, 음수)
  /// [txPower] 비콘의 기준 신호 강도 (보통 -59 dBm @1m)
  static double rssiToDistance(int rssi, {int txPower = -59}) {
    if (rssi == 0) return -1;
    final ratio = rssi / txPower;
    if (ratio < 1.0) return pow(ratio, 10).toDouble();
    return 0.89976 * pow(ratio, 7.7095) + 0.111;
  }

  /// 거리(m) → RSSI 임계값 역산 (관리자 UI 힌트용)
  static int distanceToRssi(double meters, {int txPower = -59}) {
    if (meters <= 1) return txPower;
    return (txPower - 10 * log(meters) / ln10).round();
  }

  /// RSSI 기반 근접도 레이블
  static String proximityLabel(int rssi) {
    if (rssi >= -55) return '매우 가까움 (~1m)';
    if (rssi >= -70) return '가까움 (1~3m)';
    if (rssi >= -80) return '보통 (3~8m)';
    return '멀음 (8m+)';
  }
}
