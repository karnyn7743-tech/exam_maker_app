# تجاهل فئات ML Kit غير المستخدمة
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# الاحتفاظ بفئات ML Kit المستخدمة
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }

# تجاهل تحذيرات R8
-dontwarn com.google.mlkit.vision.text.TextRecognizer
# تجاهل كلاسات اللغات غير المستخدمة في ML Kit
-dontwarn com.google.mlkit.vision.text.**
-keep class com.google.mlkit.vision.text.** { *; }

# الحفاظ على كلاسات Mobile Scanner و ML Kit
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
