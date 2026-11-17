# خطتي (Khutati)

تطبيق عربي أولاً، يعمل دون إنترنت، لخطة الدراسة المكوّنة من 68 يوماً
للدكتور MedX. مبني بـ Flutter و Dart، وقاعدة بيانات SQLite عبر Drift،
وتسجيل دخول جوجل لمرة واحدة عبر Supabase، وطبقة Kotlin أصلية لمؤقت
التركيز في الخلفية.

النموذج HTML المعتمد (`خطتي اليومية، الإصدار 3.html`) هو المرجع البصري
الوحيد. ومحتوى الخطة يأتي حصراً من `khutati_plan_data.json`، ولا يُكتب
داخل الشيفرة أبداً.

## الحالة

اكتملت المرحلتان 0 و1، وأساس محرّك المرحلة 2 (الاستيراد والتواريخ
والتقدم) جاهز:

- هيكل مشروع Flutter يتبع تقسيم الطبقات في القسم 7 من PRD.
- رموز التصميم مستخرجة من النموذج آلياً إلى `design/tokens.json` ثم
  مولّدة في `lib/core/design/tokens.dart`.
- الخطوط العربية (IBM Plex Sans Arabic و Reem Kufi) مضمّنة للعمل دون
  إنترنت، مع اتجاه RTL من أول إطار، وهيكل بخمسة تبويبات: اليوم، الخطة،
  التركيز، الإنجازات، الإعدادات.
- مخطط Drift يفصل بوضوح بين جداول القالب وجداول المستخدم.
- استيراد بيانات الخطة والتحقق منها قبل أول إطار، وبشكل آمن قابل
  للتكرار (`lib/data/import/plan_importer.dart`).
- محرّكات التواريخ وحالة اليوم والتقدم والساعات مكتوبة بـ Dart خالص
  (`lib/domain/plan/`).
- تحديثات داخل التطبيق: Supabase أولاً ثم GitHub Releases كبديل، مع
  فحص صامت محدود التكرار ولوحة في الإعدادات (`docs/updates.md`).
- خط GitHub Actions يتحقق من رموز التصميم والبيانات وتطابق الإصدار، ثم
  يبني `Khutati.apk` للأجهزة الحديثة (arm64) وينشر `update.json`.

## المتطلبات

- Flutter 3.29.x (Dart 3.7)
- JDK 17
- Node.js 18 أو أحدث (لأدوات التصميم والتحقق من البيانات فقط)

## الأوامر

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift codegen
flutter analyze
flutter test
flutter run

# Rebuild the design tokens after editing the prototype
node tools/extract_tokens.mjs
node tools/extract_tokens.mjs --check   # CI guard: fails on drift

# Re-validate the plan dataset against PRD section 3.1
node tools/validate_plan_data.mjs
node tools/validate_plan_data.mjs --self-test

# The update checker reads AppInfo; keep it equal to pubspec.yaml
node tools/check_version.mjs
```

طريقة نشر التحديثات وإعداد Supabase والبديل عبر GitHub موثّقة في
[`docs/updates.md`](docs/updates.md).

## هيكل المشروع

```
lib/
  app/            هيكل التطبيق والموجّه والسمة
  core/
    design/       الرموز المولّدة (لا تُعدّل يدوياً)، محلل SVG، مجموعة الودجات
    typography/   مداخل الخطوط
    l10n/         النصوص العربية (ملفات ARB)
    utils/        أدوات التنسيق (الأرقام، المدد، الأوقات العربية)
    settings/     التفضيلات المحفوظة (وضع السمة)
  data/           قاعدة بيانات Drift والمستودعات
  domain/         محرّك الخطة، بلا اعتماد على Flutter (المرحلة 2)
  features/       اليوم، الخطة، التركيز، الإنجازات، المعرض (للتطوير)
tools/            استخراج الرموز والتحقق من البيانات
design/           ملف tokens.json المولّد
docs/             تقرير التحقق من البيانات والتوثيق
android/          مضيف Kotlin وخدمة الخلفية (المرحلة 4.1)
```

## نظام التصميم

كل عنصر هو نقل مباشر لقاعدة في النموذج، لا اجتهاد شخصي:

| الودجة | مصدرها في النموذج |
| --- | --- |
| `KCard` | `.hero` / `.pd` — بطاقة بحد رفيع ونقشة سداسية ولون اختياري |
| `KPill` | `.pill` — كبسولة 32dp بقيمة ذهبية |
| `KTag` | `.tag` — لون المادة الصلب ونص داكن |
| `KChip` | `.chip` — مفتاح خطوة 52dp، وتعبئة `--ok` عند الضغط |
| `KButton` | `.btn` / `.btn2` — 44dp، تعبئة حمراء أو حد رفيع |
| `KProgressBar` | `.bar` — 8dp، حواف دائرية، `--redtx` |
| `KProgressRing` | `.ring` — 240dp، r104، سماكة 10px، نهاية دائرية، بداية -90° |
| `KEcgLine` | `.ecg` — المسار نفسه، معكوساً، ويظهر خلال 600ms |
| `KBreakDivider` | `.br` — عنوان في الوسط بين خطين رفيعين |
| `KSectionHeader` | `h2` — هوامش 24/12 |
| `KToast` / `KConfetti` | `#toast` / `.cf` — كبسولة معكوسة، وانفجار 26 قطعة |

يعرض `/gallery` كل هذه العناصر بالسمة الحيّة (يُفتح من شاشة اليوم في
نسخ التطوير). تقارن الاختبارات مسار ECG وهندسة الحلقة والبلاطة السداسية
ورموز التنقل مع HTML، ليبقى النموذج هو المرجع.

## التعريب

كل النصوص الظاهرة للمستخدم موجودة في `lib/l10n/app_ar.arb`، ويولّد
`flutter gen-l10n` (عبر `l10n.yaml`) واجهات مطبوعة يُصل إليها بـ
`context.l10n`. وإضافة الإنجليزية تعني إضافة `app_en.arb` فقط، دون أي
تعديل على الودجات.

## التكامل المستمر والتوقيع

يعمل `.github/workflows/android.yml` عند كل دفعة:

1. `node tools/extract_tokens.mjs --check` — يجب أن تطابق السمة النموذج.
2. `node tools/validate_plan_data.mjs` — يجب أن تتطابق البيانات مع 480 س 9 د.
3. `flutter analyze` و`flutter test`.
4. بناء APK للتطوير عند كل دفعة.
5. بناء `Khutati.apk` للأجهزة الحديثة (arm64 فقط) باستخدام
   `--split-per-abi`، ورفعه كأثر، ثم نشره في GitHub Releases مع
   `update.json`: إصدار مرقّم عند وسوم `v*`، وإصدار `latest` متجدد عند
   الدفع إلى `main`.

يستخدم توقيع الإصدار أسرار المستودع التالية (كلها اختيارية، وبدونها
يُوقَّع APK الإصدار بمفتاح التطوير):

| السر | الغرض |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | نسخة Base64 من مخزن مفاتيح الإصدار |
| `ANDROID_KEYSTORE_PASSWORD` | كلمة مرور مخزن المفاتيح |
| `ANDROID_KEY_ALIAS` | اسم المفتاح داخل المخزن |
| `ANDROID_KEY_PASSWORD` | كلمة مرور المفتاح |

## الاصطلاحات

- لا ألوان أو أنصاف أقطار أو أحجام خطوط خارج `lib/core/design/tokens.dart`.
- لا محتوى للخطة خارج `khutati_plan_data.json`.
- لا نصوص عربية مكتوبة مباشرة داخل الشيفرة؛ استخدم `context.l10n`.
- استخدم خصائص الاتجاه (`start`/`end`) ولا تستخدم `left`/`right`.
- الأرقام غربية في كل مكان (القسم 13.1 من PRD).
