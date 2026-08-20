# ONNX Runtime: 네이티브 라이브러리(libonnxruntime4j_jni.so)가 JNI로 Java 클래스·
# 메서드 이름을 찾는다. R8이 이름을 바꾸거나 지우면 릴리스 빌드에서 OrtSession.run
# 도중 "JNI GetMethodID … abort"로 앱이 죽는다(실기기 재현: 예시 분석 시 즉사).
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# flutter_onnxruntime 플러그인(플랫폼 채널 핸들러).
-keep class com.masicai.flutteronnxruntime.** { *; }
-dontwarn com.masicai.flutteronnxruntime.**
