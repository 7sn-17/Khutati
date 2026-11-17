/// Arabic UI copy for the foundation layer.
///
/// Every string is centralized here so Phase 1.6 can move it into ARB files
/// without touching widget code. No feature widget may contain a literal
/// Arabic string (PRD section 7, "RTL / i18n").
abstract final class AppStrings {
  static const String appName = 'خطتي';

  // Sections
  static const String today = 'اليوم';
  static const String plan = 'الخطة';
  static const String focus = 'التركيز';
  static const String achievements = 'إنجازاتي';

  // Scaffold placeholders (Phase 0 skeleton)
  static const String foundationReady = 'الأساس جاهز';
  static const String foundationSubtitle = 'المرحلة 0 — الأساس جاهز';
  static const String foundationProof =
      'الاتجاه من اليمين إلى اليسار، الخطوط العربية مضمّنة، والألوان مستخرجة من النموذج.';
  static const String todayPlaceholder = 'شاشة اليوم تُبنى في المرحلة 3';
  static const String planPlaceholder = 'شاشة الخطة تُبنى في المرحلة 3';
  static const String focusPlaceholder = 'المؤقت يُبنى في المرحلة 4';
  static const String achievementsPlaceholder = 'الإنجازات تُبنى في المرحلة 6';

  // Component gallery (debug only)
  static const String galleryTitle = 'معرض المكوّنات';
  static const String galleryOpen = 'افتح معرض المكوّنات';
  static const String galleryTheme = 'تبديل المظهر';
  static const String galleryToast = 'أحسنت، أكملت الخطوة';
  static const String galleryToastAction = 'أظهر التنبيه';
  static const String galleryConfettiAction = 'أطلق الاحتفال';
  static const String galleryDemoTask = 'فيديو تأسيسي الذرة 1';
  static const String galleryDemoRange = '8:00 صباحاً – 9:14 صباحاً';
  static const String galleryFocusCaption = 'وقت التركيز';

  // Units
  static const String hourShort = 'س';
  static const String minuteShort = 'د';
  static const String morning = 'صباحاً';
  static const String noon = 'ظهراً';
  static const String afternoon = 'عصراً';
  static const String evening = 'مساءً';
}
