import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'ai_service.dart';

class SupportedLanguage {
  final String name;
  final String nativeName;
  final TranslateLanguage mlKitLanguage;
  final String code;

  const SupportedLanguage({
    required this.name,
    required this.nativeName,
    required this.mlKitLanguage,
    required this.code,
  });
}

class TranslationService {
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal();

  final OnDeviceTranslatorModelManager _modelManager = OnDeviceTranslatorModelManager();

  static final List<SupportedLanguage> supportedLanguages = [
    const SupportedLanguage(name: 'Afrikaans', nativeName: 'Afrikaans', mlKitLanguage: TranslateLanguage.afrikaans, code: 'af'),
    const SupportedLanguage(name: 'Albanian', nativeName: 'Shqip', mlKitLanguage: TranslateLanguage.albanian, code: 'sq'),
    const SupportedLanguage(name: 'Arabic', nativeName: 'العربية', mlKitLanguage: TranslateLanguage.arabic, code: 'ar'),
    const SupportedLanguage(name: 'Belarusian', nativeName: 'Беларуская', mlKitLanguage: TranslateLanguage.belarusian, code: 'be'),
    const SupportedLanguage(name: 'Bulgarian', nativeName: 'Български', mlKitLanguage: TranslateLanguage.bulgarian, code: 'bg'),
    const SupportedLanguage(name: 'Bengali', nativeName: 'বাংলা', mlKitLanguage: TranslateLanguage.bengali, code: 'bn'),
    const SupportedLanguage(name: 'Catalan', nativeName: 'Català', mlKitLanguage: TranslateLanguage.catalan, code: 'ca'),
    const SupportedLanguage(name: 'English', nativeName: 'English', mlKitLanguage: TranslateLanguage.english, code: 'en'),
    const SupportedLanguage(name: 'Hindi', nativeName: 'हिन्दी', mlKitLanguage: TranslateLanguage.hindi, code: 'hi'),
    const SupportedLanguage(name: 'Spanish', nativeName: 'Español', mlKitLanguage: TranslateLanguage.spanish, code: 'es'),
    const SupportedLanguage(name: 'French', nativeName: 'Français', mlKitLanguage: TranslateLanguage.french, code: 'fr'),
    const SupportedLanguage(name: 'German', nativeName: 'Deutsch', mlKitLanguage: TranslateLanguage.german, code: 'de'),
    const SupportedLanguage(name: 'Italian', nativeName: 'Italiano', mlKitLanguage: TranslateLanguage.italian, code: 'it'),
    const SupportedLanguage(name: 'Japanese', nativeName: '日本語', mlKitLanguage: TranslateLanguage.japanese, code: 'ja'),
    const SupportedLanguage(name: 'Korean', nativeName: '한국어', mlKitLanguage: TranslateLanguage.korean, code: 'ko'),
    const SupportedLanguage(name: 'Marathi', nativeName: 'मराठी', mlKitLanguage: TranslateLanguage.marathi, code: 'mr'),
    const SupportedLanguage(name: 'Portuguese', nativeName: 'Português', mlKitLanguage: TranslateLanguage.portuguese, code: 'pt'),
    const SupportedLanguage(name: 'Russian', nativeName: 'Русский', mlKitLanguage: TranslateLanguage.russian, code: 'ru'),
    const SupportedLanguage(name: 'Tamil', nativeName: 'தமிழ்', mlKitLanguage: TranslateLanguage.tamil, code: 'ta'),
    const SupportedLanguage(name: 'Telugu', nativeName: 'తెలుగు', mlKitLanguage: TranslateLanguage.telugu, code: 'te'),
    const SupportedLanguage(name: 'Turkish', nativeName: 'Türkçe', mlKitLanguage: TranslateLanguage.turkish, code: 'tr'),
    const SupportedLanguage(name: 'Chinese', nativeName: '中文', mlKitLanguage: TranslateLanguage.chinese, code: 'zh'),
    const SupportedLanguage(name: 'Urdu', nativeName: 'اردو', mlKitLanguage: TranslateLanguage.urdu, code: 'ur'),
  ];

  /// Checks if an offline language model is downloaded
  Future<bool> isModelDownloaded(TranslateLanguage lang) async {
    try {
      return await _modelManager.isModelDownloaded(lang.bcpCode);
    } catch (_) {
      return false;
    }
  }

  /// Downloads an offline language model package
  Future<bool> downloadLanguageModel(TranslateLanguage lang) async {
    try {
      return await _modelManager.downloadModel(lang.bcpCode);
    } catch (e) {
      debugPrint('Error downloading model $lang: $e');
      return false;
    }
  }

  /// Translates text using On-Device ML Kit with AI Fallback
  Future<String> translateText({
    required String text,
    SupportedLanguage? sourceLang,
    required SupportedLanguage targetLang,
  }) async {
    if (text.trim().isEmpty) return '';

    try {
      final sourceMlLang = sourceLang?.mlKitLanguage ?? TranslateLanguage.english;
      final targetMlLang = targetLang.mlKitLanguage;

      final translator = OnDeviceTranslator(
        sourceLanguage: sourceMlLang,
        targetLanguage: targetMlLang,
      );

      final translated = await translator.translateText(text);
      await translator.close();

      if (translated.isNotEmpty && translated.trim() != text.trim()) {
        return translated.trim();
      }
    } catch (e) {
      debugPrint('MLKit translation note/fallback: $e');
    }

    // AI Service Fallback
    try {
      final aiPrompt = 'Translate the following text to ${targetLang.name} (${targetLang.nativeName}). '
          'Return ONLY the translated result without quotes or extra explanation:\n\n$text';
      final aiResult = await AiService().translateWithAi(aiPrompt);
      if (aiResult.isNotEmpty && !aiResult.startsWith('Error') && !aiResult.startsWith('⚠️')) {
        return aiResult.trim();
      }
    } catch (_) {}

    return text;
  }
}
