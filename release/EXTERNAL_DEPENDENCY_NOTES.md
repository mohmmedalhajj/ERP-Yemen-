# مراجع الاعتماديات الخارجية

تمت مراجعة صفحات Pub.dev التالية قبل الدمج:

| الحزمة | الإصدار المستخدم | الغرض | المرجع |
|---|---:|---|---|
| mobile_scanner | 7.4.0 | مسح الباركود وQR بالكاميرا عبر CameraX/ML Kit على Android | https://pub.dev/packages/mobile_scanner |
| print_bluetooth_thermal | 1.2.2 | اكتشاف الطابعات المقترنة والاتصال والكتابة عبر Bluetooth على Android | https://pub.dev/packages/print_bluetooth_thermal |
| esc_pos_utils_plus | 2.0.4 | توليد أوامر ESC/POS لمقاسي 58mm و80mm | https://pub.dev/packages/esc_pos_utils_plus |
| flutter_local_notifications | 19.5.0 | إشعارات محلية | https://pub.dev/packages/flutter_local_notifications |

ملاحظة التوافق: unified_esc_pos_printer استُبعد لأنه يسحب flutter_libserialport الذي يستخدم jcenter() ويتعارض مع AGP 9 في بيئة البناء الحالية. استُخدم print_bluetooth_thermal بدلاً منه.

مراجع Flutter/Android العامة:

- https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers
- https://developer.android.com/studio/write/java8-support.html
