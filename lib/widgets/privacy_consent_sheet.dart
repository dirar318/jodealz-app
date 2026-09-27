import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:jodeals/services/trusted_hosts.dart';
import 'package:jodeals/theme/app_colors.dart';

/// Prominent disclosure + opt-in for optional analytics (Google Play User Data
/// policy, App Store Guideline 5.1.1). Returns true only if the user opts in.
Future<bool> showPrivacyConsentSheet(BuildContext context) async {
  final bool isArabic = Localizations.localeOf(context).languageCode != 'en';
  String t(String ar, String en) => isArabic ? ar : en;

  final bool? result = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Directionality(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.privacy_tip_outlined, color: AppColors.primary, size: 36),
                const SizedBox(height: 12),
                Text(
                  t('خصوصيتك تهمنا', 'Your privacy matters'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 12),
                Text(
                  t(
                    'نود جمع بيانات استخدام مجهولة المصدر لتحسين التطبيق واقتراح عروض أفضل لك، مثل: الصفحات والعروض والفئات التي تشاهدها، وسرعة تحميل الصفحات، ونوع الجهاز والشبكة. لا نبيع بياناتك ولا نشاركها مع معلنين. يمكنك تغيير اختيارك في أي وقت من الإعدادات.',
                    'We would like to collect usage data to improve the app and suggest better deals: pages, deals and categories you view, page load times, and your device and network type. We never sell your data or share it with advertisers. You can change this at any time in Settings.',
                  ),
                  style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF475569)),
                ),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse('${TrustedHosts.baseUrl}/privacy'),
                    mode: LaunchMode.inAppBrowserView,
                  ),
                  child: Text(t('سياسة الخصوصية', 'Privacy Policy')),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(t('السماح', 'Allow')),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(t('لا شكراً', 'No thanks')),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}
