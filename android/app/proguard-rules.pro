# ML Kit Text Recognition ProGuard / R8 keep rules
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.**
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }

# ML Kit Digital Ink Recognition ProGuard / R8 keep rules
-dontwarn com.google.mlkit.vision.digitalink.**
-keep class com.google.mlkit.vision.digitalink.** { *; }
-keep class com.google_mlkit_digital_ink_recognition.** { *; }
