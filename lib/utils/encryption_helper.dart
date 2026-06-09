// lib/utils/encryption_helper.dart
//
// ⚠️ 현재: AES 클라이언트 암호화 (개발 단계)
// 🔮 나중에: 이 파일만 교체하면 Cloud Functions로 전환 가능
//
// 키는 dart-define 환경변수로 주입 → GitHub에 절대 노출 안 됨

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';

class EncryptionHelper {
  EncryptionHelper._();

  // ── 환경변수에서 키 읽기 (dart-define으로 주입) ──
  static const String _keyString =
      String.fromEnvironment('ENCRYPT_KEY', defaultValue: '');
  static const String _ivString =
      String.fromEnvironment('ENCRYPT_IV', defaultValue: '');

  static enc.Encrypter? _encrypter;
  static enc.IV? _iv;
  static bool _keyMissing = false;

  static void _init() {
    if (_encrypter != null) return;
    if (_keyMissing) return;

    if (_keyString.isEmpty || _ivString.isEmpty) {
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
    _iv = enc.IV.fromBase64(_ivString);
    _encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  }

  /// 암호화 — 평문 → Base64 암호문
  static String? encrypt(String? plainText) {
    if (plainText == null || plainText.isEmpty) return null;
    try {
      _init();
      if (_encrypter == null) return plainText;
      return _encrypter!.encrypt(plainText, iv: _iv!).base64;
    } catch (e) {
      debugPrint('❌ [EncryptionHelper] 암호화 실패: $e');
      return plainText;
    }
  }

  /// 복호화 — Base64 암호문 → 평문
  static String? decrypt(String? encryptedText) {
    if (encryptedText == null || encryptedText.isEmpty) return null;
    try {
      _init();
      if (_encrypter == null) return encryptedText;
      return _encrypter!.decrypt64(encryptedText, iv: _iv!);
    } catch (e) {
      // 기존 평문 데이터 호환 (암호화 적용 전 데이터)
      debugPrint('⚠️ [EncryptionHelper] 복호화 실패 - 평문으로 처리: $e');
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