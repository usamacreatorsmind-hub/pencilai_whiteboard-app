import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class AiService {
  static const String apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: 'AQ.Ab8RN6Jr6kp32XGFtpjoix-jRW6xXS-IE98HTna1gDLfVpyeBQ',
  );
  static const String _modelName = 'gemini-flash-lite-latest';

  Future<String> _generate(
    String prompt,
    String label, {
    List<String>? imagePaths,
    List<Uint8List>? directBytes,
  }) async {
    if (apiKey.isEmpty) {
      return '⚠️ Gemini API Key is missing. Please run the app with --dart-define-from-file=env.json.';
    }
    try {
      final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$_modelName:generateContent');

      List<Map<String, dynamic>> parts = [
        {'text': prompt},
      ];

      // Direct in-memory image bytes (instant, zero disk I/O)
      if (directBytes != null && directBytes.isNotEmpty) {
        for (var bytes in directBytes) {
          final base64Image = base64Encode(bytes);
          parts.add({
            'inline_data': {'mime_type': 'image/png', 'data': base64Image},
          });
        }
      }

      // Convert local slide image files to Base64 so Gemini can read visual slides
      if (imagePaths != null && imagePaths.isNotEmpty) {
        for (var path in imagePaths) {
          try {
            final file = File(path);
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              final base64Image = base64Encode(bytes);
              String mimeType = 'image/png';
              if (path.endsWith('.jpg') || path.endsWith('.jpeg')) {
                mimeType = 'image/jpeg';
              }
              parts.add({
                'inline_data': {'mime_type': mimeType, 'data': base64Image},
              });
            }
          } catch (_) {}
        }
      }

      final isOcr = label == 'Handwriting OCR';
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
        body: jsonEncode({
          'contents': [
            {'parts': parts},
          ],
          'generationConfig': {
            'maxOutputTokens': isOcr ? 40 : 1500,
            'temperature': isOcr ? 0.0 : 0.7,
          },
        }),
      );

      if (res.statusCode != 200) {
        return 'Error generating $label (${res.statusCode}): ${utf8.decode(res.bodyBytes)}';
      }

      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final resParts = data['candidates']?[0]?['content']?['parts'] as List?;
      final text = resParts?.map((p) => p['text'] ?? '').join('').trim();
      return (text == null || text.isEmpty) ? 'No $label generated.' : text;
    } catch (e) {
      return 'Error generating $label: $e';
    }
  }

  Future<String> generateQuickQuiz(String contentText, {List<String>? imagePaths}) => _generate(
    'Act as an expert educator. Based on the following teaching content/slide image, '
        'generate a maximum of 10 multiple-choice questions (MCQs) with 4 options '
        'each (A, B, C, D) and clearly indicate the correct answer.\n\n'
        'Content:\n$contentText',
    'Quick Quiz',
    imagePaths: imagePaths,
  );

  Future<String> generateHomework(String contentText, {List<String>? imagePaths}) => _generate(
    'Based on the following lesson content/slide image, create engaging homework '
        'questions or short assignments for students to test their '
        'understanding.\n\nContent:\n$contentText',
    'Homework',
    imagePaths: imagePaths,
  );

  Future<String> generateSummary(String contentText, {List<String>? imagePaths}) => _generate(
    'Act as an expert educator. Provide a comprehensive, in-depth professional summary '
        '(at least 100 to 150 words) of the topic, core concepts, and detailed teaching talking points '
        'based on the following teaching content/slide image. Ensure the explanation is thorough, clear, '
        'and structured with bullet points so a teacher can easily explain it in depth to students in class.\n\n'
        'Content:\n$contentText',
    'Summary',
    imagePaths: imagePaths,
  );

  Future<String> recognizeHandwriting({
    String? imagePath,
    Uint8List? imageBytes,
  }) async {
    final result = await _generate(
      'Transcribe the handwritten text or notes in this whiteboard image. '
      'Extract ONLY the exact handwritten text, word, or sentence written in the image. '
      'Return strictly the plain text string with zero extra explanation, markdown, or quotation marks.',
      'Handwriting OCR',
      imagePaths: imagePath != null ? [imagePath] : null,
      directBytes: imageBytes != null ? [imageBytes] : null,
    );
    return result.trim();
  }

  Future<String> translateWithAi(String prompt) => _generate(prompt, 'Translation');

  Future<String> generateMindMap(String prompt) => _generate(prompt, 'MindMap');
}
