// lib/utils/encryption_helper.dart
//
// ⚠️ 현재: AES 클라이언트 암호화 (개발 단계)
// 🔮 나중에: 이 파일만 교체하면 Cloud Functions로 전환 가능
//
// 키는 dart-define 환경변수로 주입 → GitHub에 절대 노출 안 됨
// dart_defines.json / config/dev / config/prod 모두 .gitignore 제외 확인 완료 (2026-07-09)
//
// [AES-IV-AUDIT] 고정 IV → 랜덤 IV 전환 완료 — 재탐색 금지.
//   encrypt(): enc.IV.fromSecureRandom(16)으로 매 호출마다 랜덤 IV 생성.
//   저장 형식: base64(randomIV) + ":" + base64(ciphertext)
//   decrypt(): ":" 포함 여부로 신규(랜덤 IV) / 레거시(고정 IV) 자동 구분.
//   ENCRYPT_IV(_legacyIvString)는 이전 데이터 복호화 전용 — 신규 암호화에 미사용.

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';

class EncryptionHelper {
  EncryptionHelper._();

  // ── 환경변수에서 키 읽기 (dart-define으로 주입) ──
  static const String _keyString =
      String.fromEnvironment('ENCRYPT_KEY', defaultValue: '');
  // ENCRYPT_IV는 레거시 데이터 복호화 전용 — 신규 암호화는 랜덤 IV 사용
  static const String _legacyIvString =
      String.fromEnvironment('ENCRYPT_IV', defaultValue: '');

  static enc.Encrypter? _encrypter;
  static enc.IV? _legacyIv;
  static bool _keyMissing = false;

  static void _init() {
    if (_encrypter != null) return;
    if (_keyMissing) return;

    if (_keyString.isEmpty || _legacyIvString.isEmpty) {
      _keyMissing = true;
      debugPrint('❌ [EncryptionHelper] 암호화 키가 설정되지 않았습니다!');
      debugPrint('   launch.json 또는 빌드 명령어에 --dart-define 확인하세요');
      // 릴리즈 빌드에서 키 미설정은 치명적 오류 — 평문 저장 방지
      if (kReleaseMode) {
        throw StateError(
          '[EncryptionHelper] ENCRYPT_KEY / ENCRYPT_IV must be set in release builds.',
        );
      }
      return;
    }

    final key = enc.Key.fromBase64(_keyString);
    _legacyIv = enc.IV.fromBase64(_legacyIvString);
    _encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  }

  /// 암호화 — 평문 → "randomIV:암호문" (base64 각각)
  ///
  /// [H-7] 매 호출마다 랜덤 IV 생성 — 동일 평문도 항상 다른 암호문 반환.
  /// 저장 형식: base64(randomIV) + ":" + base64(ciphertext)
  /// base64 문자셋에 ":"이 없으므로 첫 번째 ":" 기준으로 안전하게 분리 가능.
  static String? encrypt(String? plainText) {
    if (plainText == null || plainText.isEmpty) return null;
    try {
      _init();
      if (_encrypter == null) return plainText; // 디버그 전용 폴백
      final randomIv = enc.IV.fromSecureRandom(16);
      final ciphertext = _encrypter!.encrypt(plainText, iv: randomIv).base64;
      return '${randomIv.base64}:$ciphertext';
    } catch (e) {
      // 릴리즈 빌드에서 암호화 실패 시 평문 저장 방지 — null 반환으로 안전 실패
      debugPrint('❌ [EncryptionHelper] 암호화 실패: ${e.runtimeType}');
      return null;
    }
  }

  /// 복호화 — "randomIV:암호문" 또는 레거시 "암호문" → 평문
  ///
  /// [H-7] ":" 포함 여부로 신규(랜덤 IV) / 레거시(고정 IV) 자동 구분.
  /// 암호화 키 없이 저장된 평문 데이터(기존 레거시 or 디버그 빌드 누락)는
  /// base64 디코딩 실패 → catch에서 원문 그대로 반환(폴백).
  /// $e 메시지에 입력값이 포함될 수 있어 runtimeType만 로깅.
  static String? decrypt(String? encryptedText) {
    if (encryptedText == null || encryptedText.isEmpty) return null;
    try {
      _init();
      if (_encrypter == null) return encryptedText;
      if (encryptedText.contains(':')) {
        // 신규 형식: base64(IV):base64(암호문)
        final colonIndex = encryptedText.indexOf(':');
        final ivBase64 = encryptedText.substring(0, colonIndex);
        final cipherBase64 = encryptedText.substring(colonIndex + 1);
        final iv = enc.IV.fromBase64(ivBase64);
        return _encrypter!.decrypt64(cipherBase64, iv: iv);
      } else {
        // 레거시 형식: 고정 IV (ENCRYPT_IV) 사용
        // 암호화 도입 이전 평문 데이터는 base64 디코딩 실패 → 경고 없이 그대로 반환
        try {
          return _encrypter!.decrypt64(encryptedText, iv: _legacyIv!);
        } on FormatException {
          return encryptedText;
        }
      }
    } catch (e) {
      // 레거시 평문 데이터 폴백 — $e에 민감 데이터 포함 가능하므로 타입만 로깅
      debugPrint('⚠️ [EncryptionHelper] 복호화 실패 - 평문으로 처리 (${e.runtimeType})');
      return encryptedText;
    }
  }

  /// 주민번호 마스킹 (화면 표시용)
  /// "9901011234567" → "990101-1******"
  static String maskResidentNumber(String? plain) {
    if (plain == null || plain.length < 7) return '***';
    final cleaned = plain.replaceAll('-', '');
    if (cleaned.length < 7) return '***';
    return '${cleaned.substring(0, 6)}-${cleaned[6]}******';
  }

  /// 계좌번호 마스킹 (화면 표시용)
  /// "12345678901234" → "1234-****-5678"
  static String maskAccountNumber(String? plain) {
    if (plain == null || plain.length < 4) return '***';
    final cleaned = plain.replaceAll('-', '');
    final last4 = cleaned.substring(cleaned.length - 4);
    final first4 = cleaned.substring(0, 4);
    return '$first4-****-$last4';
  }
}
