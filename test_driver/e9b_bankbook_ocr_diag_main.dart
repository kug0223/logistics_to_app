// [E9B-DIAG] 통장사본 기기 OCR 진단 — 디버그·테스트 전용 진입점.
//
// 실행(디버그 빌드만):
//   flutter run -t test_driver/e9b_bankbook_ocr_diag_main.dart -d <기기>
//
// 격리:
//   · `lib/` 어디에서도 이 파일을 import 하지 않는다 — 정식 앱(`lib/main.dart`)
//     빌드에 들어가지 않는다.
//   · Firebase 를 초기화하지 않는다. Auth·Firestore·Storage·callable 을 부르지 않는다.
//     서류 등록 화면·계좌 변경·통장사본 업로드 경로도 부르지 않는다.
//   · release/profile 빌드면 진단 자체가 꺼진다(`kDebugMode`).
//
// 무엇을 보는가:
//   서류 등록 화면과 **같은 플러그인·같은 판정 함수**(ML Kit Korean →
//   `_verifyBankbookFromText`)로 낸 판정 + 숫자 후보별 분류 근거.
//
// 개인정보:
//   비교 기준(은행·계좌·예금주)은 실행 중 입력받아 메모리에만 둔다.
//   OCR 원문·후보 숫자·입력값은 화면·로그에 내보내지 않는다 —
//   화면에는 [E9bDiagReport] 의 마스킹 요약만 나온다.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'package:ALfit/utils/identity_identifier.dart';
import 'package:ALfit/utils/ocr_verification_helper.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const E9bDiagApp(enabled: kDebugMode));
}

/// 최종 판정 — 서류 등록 화면의 분기와 같은 기준.
///   일치(`isDocumentConsistent`) → MATCHED
///   근거 있는 불일치(계좌·예금주, 보조 판정이면 은행까지) → MISMATCH
///   그 밖(못 읽음·대조 기준 없음·OCR 오류) → OCR_UNCERTAIN
String e9bVerdictOf(Map<String, dynamic> r, {bool includeBank = false}) {
  if (r['error'] != null) return 'OCR_UNCERTAIN';
  if (r['isDocumentConsistent'] == true) return 'MATCHED';
  final fields = <Object?>[
    r['accountOutcome'],
    r['holderOutcome'],
    if (includeBank) r['bankOutcome'],
  ];
  if (fields.contains(DocFieldOutcome.mismatch)) return 'MISMATCH';
  return 'OCR_UNCERTAIN';
}

String _wire(Object? o) => o is DocFieldOutcome ? o.wire : 'UNASSESSED';
String _yn(bool b) => b ? '예' : '아니오';

/// 마스킹 요약. **숫자·이름·원문을 담지 않는다** — 형태와 동일 여부만.
class E9bDiagReport {
  E9bDiagReport._(this.lines);
  final List<String> lines;

  factory E9bDiagReport.from(
    BankbookDiagnosis d, {
    String? expectedAccountNumber,
    String? expectedBankName,
  }) {
    final expectedDigits =
        (expectedAccountNumber ?? '').replaceAll(RegExp(r'\D'), '');
    final p = d.production;
    final lines = <String>[
      '최종 판정(서류 등록 화면과 같은 인자): ${e9bVerdictOf(p)}',
      '  계좌: ${_wire(p['accountOutcome'])} · 예금주: ${_wire(p['holderOutcome'])}'
          ' · 은행: ${_wire(p['bankOutcome'])}(등록 화면은 은행명을 넘기지 않음)',
      if (d.withBank != null)
        '보조 판정(은행명 포함): ${e9bVerdictOf(d.withBank!, includeBank: true)}'
            ' · 은행: ${_wire(d.withBank!['bankOutcome'])}',
      '예금주: 읽음 ${_yn((p['extractedName'] as String?)?.isNotEmpty ?? false)}'
          ' · 라벨 옆에서 읽음 ${_yn(d.holderLabeled)}',
      '은행 인식: ${d.canonicalBank ?? '인식 못 함'}'
          '${expectedBankName == null || expectedBankName.isEmpty ? '' : ' · 입력 은행과 같음 ${_yn(d.canonicalBank != null && _norm(d.canonicalBank!) == _norm(expectedBankName))}'}',
      '숫자 후보 ${d.candidates.length}개 · 계좌 후보 ${d.candidates.where((c) => c.usable).length}개',
    ];
    var i = 0;
    for (final c in d.candidates) {
      i++;
      final cls = c.usable
          ? '계좌 후보'
          : switch (c.rejectReason) {
              AccountCandidateDiagnosis.rejectPhone => '비계좌(전화 형태/문맥)',
              AccountCandidateDiagnosis.rejectDate => '비계좌(날짜)',
              _ => '비계좌(자릿수 범위 밖)',
            };
      lines.add('  #$i 구간 ${c.shape} · ${c.digits.length}자리'
          ' · 010 시작 ${_yn(c.digits.startsWith('010'))}'
          ' · 계좌 라벨 ${_yn(c.positiveLabel)} · 비계좌 라벨 ${_yn(c.negativeLabel)}'
          ' · $cls'
          '${expectedDigits.isEmpty ? '' : ' · 입력 계좌와 같음 ${_yn(c.digits == expectedDigits)}'}');
    }
    return E9bDiagReport._(lines);
  }

  static String _norm(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();
}

class E9bDiagApp extends StatelessWidget {
  const E9bDiagApp({super.key, required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'E9B OCR 진단',
        home: enabled
            ? const E9bDiagScreen()
            : const Scaffold(
                body: Center(child: Text('진단은 디버그 빌드에서만 동작합니다')),
              ),
      );
}

class E9bDiagScreen extends StatefulWidget {
  const E9bDiagScreen({super.key, this.picker, this.recognize});

  /// 테스트 경계 — 기본은 실제 image_picker · ML Kit Korean.
  final Future<String?> Function()? picker;
  final Future<({String text, RecognizedText? recognized})> Function(String path)?
      recognize;

  @override
  State<E9bDiagScreen> createState() => _E9bDiagScreenState();
}

class _E9bDiagScreenState extends State<E9bDiagScreen> {
  final _bank = TextEditingController();
  final _account = TextEditingController();
  final _holder = TextEditingController();
  bool _busy = false;
  List<String> _lines = const [];
  String? _status;

  @override
  void dispose() {
    _bank.dispose();
    _account.dispose();
    _holder.dispose();
    super.dispose();
  }

  Future<String?> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    return x?.path;
  }

  Future<({String text, RecognizedText? recognized})> _recognize(String path) async {
    // 서류 등록 화면(verifyBankbook)과 같은 인식기 설정.
    final r = TextRecognizer(script: TextRecognitionScript.korean);
    try {
      final t = await r.processImage(InputImage.fromFilePath(path));
      return (text: t.text, recognized: t);
    } finally {
      await r.close();
    }
  }

  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
      _lines = const [];
    });
    String? path;
    try {
      path = await (widget.picker ?? _pick)();
      if (!mounted) return;
      if (path == null) {
        setState(() => _status = '이미지를 선택하지 않았습니다');
        return;
      }
      final ocr = await (widget.recognize ?? _recognize)(path);
      if (!mounted) return;
      final d = OcrVerificationHelper.diagnoseBankbookText(
        ocr.text,
        recognizedText: ocr.recognized,
        expectedName: _holder.text.trim().isEmpty ? null : _holder.text.trim(),
        expectedAccountNumber:
            _account.text.trim().isEmpty ? null : _account.text.trim(),
        expectedBankName: _bank.text.trim().isEmpty ? null : _bank.text.trim(),
      );
      final report = E9bDiagReport.from(
        d,
        expectedAccountNumber: _account.text,
        expectedBankName: _bank.text,
      );
      setState(() => _lines = report.lines);
    } catch (e) {
      // 오류 문구에 원문이 섞일 수 있어 종류만 보인다.
      if (mounted) setState(() => _status = 'OCR 오류: ${e.runtimeType}');
    } finally {
      // image_picker 가 앱 캐시에 만든 사본 — 남기지 않는다.
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clear() {
    _bank.clear();
    _account.clear();
    _holder.clear();
    setState(() {
      _lines = const [];
      _status = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('E9B 통장 OCR 진단 (디버그 전용)')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('서버 접근 없음 · 업로드 없음 · 입력값은 메모리에만 둡니다.'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('e9b-bank'),
              controller: _bank,
              decoration: const InputDecoration(labelText: '비교할 은행(선택)'),
            ),
            TextField(
              key: const Key('e9b-account'),
              controller: _account,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '비교할 계좌번호'),
            ),
            TextField(
              key: const Key('e9b-holder'),
              controller: _holder,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '비교할 예금주'),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ElevatedButton(
                key: const Key('e9b-run'),
                onPressed: _busy ? null : _run,
                child: Text(_busy ? '확인 중…' : '이미지 선택 후 OCR'),
              ),
              OutlinedButton(
                key: const Key('e9b-clear'),
                onPressed: _busy ? null : _clear,
                child: const Text('입력·결과 지우기'),
              ),
            ]),
            const SizedBox(height: 16),
            if (_status != null) Text(_status!),
            for (final l in _lines) Text(l, key: const Key('e9b-line')),
          ],
        ),
      ),
    );
  }
}
