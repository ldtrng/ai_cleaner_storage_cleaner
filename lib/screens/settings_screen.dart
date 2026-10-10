import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ads/ads_service.dart';
import '../core/config.dart';
import '../core/format.dart';
import '../core/settings.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => GradientScaffold(
        title: 'Settings',
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            AppCard(
              color: context.isDark ? Palette.moss : Palette.forest,
              child: Row(
                children: [
                  const PillIcon(
                    icon: Icons.eco_rounded,
                    size: 52,
                    background: Palette.cream,
                    foreground: Palette.forest,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total cleaned',
                          style: font(13, FontWeight.w500, color: Palette.mist),
                        ),
                        Text(
                          formatBytes(s.totalCleanedBytes),
                          style: font(
                            26,
                            FontWeight.w700,
                            color: Palette.cream,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _Group(
              children: [
                _Tile(
                  icon: Icons.palette_outlined,
                  title: 'Themes',
                  value: switch (s.themeMode) {
                    ThemeMode.system => 'Automatic',
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark',
                  },
                  onTap: () => _pick<ThemeMode>(
                    context,
                    title: 'Choose your theme',
                    subtitle: 'Choose the theme that best suits you',
                    current: s.themeMode,
                    options: const {
                      ThemeMode.system: 'Automatic',
                      ThemeMode.light: 'Light',
                      ThemeMode.dark: 'Dark',
                    },
                    onSelected: (v) => s.themeMode = v,
                  ),
                ),
                _Tile(
                  icon: Icons.restore_from_trash_outlined,
                  title: 'Media Recovery',
                  value: s.mediaRecovery == MediaRecovery.trash
                      ? 'Keep in Trash'
                      : 'Delete automatically',
                  onTap: () => _pick<MediaRecovery>(
                    context,
                    title: 'Manage your deleted media',
                    subtitle:
                        'Choose whether media is saved in Trash or is deleted right after cleaning.',
                    current: s.mediaRecovery,
                    options: const {
                      MediaRecovery.trash:
                          'Keep in Trash — recover from the "Trash" album for 30 days',
                      MediaRecovery.delete:
                          'Delete automatically — free up storage instantly, no recovery',
                    },
                    onSelected: (v) => s.mediaRecovery = v,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Group(
              children: [
                _Tile(
                  icon: Icons.star_outline_rounded,
                  title: 'Rate App',
                  onTap: () async {
                    final r = InAppReview.instance;
                    if (await r.isAvailable()) {
                      r.requestReview();
                    } else {
                      r.openStoreListing();
                    }
                  },
                ),
                _Tile(
                  icon: Icons.share_outlined,
                  title: 'Share App',
                  onTap: () => _leave(
                    SharePlus.instance.share(
                      ShareParams(
                        text:
                            'Clean your phone with $appName: ${AppConfig.storeUrl}',
                        subject: '$appName has been shared with you!',
                      ),
                    ),
                  ),
                ),
                _Tile(
                  icon: Icons.mail_outline_rounded,
                  title: 'Contact Us',
                  onTap: () => _leave(
                    launchUrl(
                      Uri(
                        scheme: 'mailto',
                        path: AppConfig.supportEmail,
                        query:
                            'subject=${Uri.encodeComponent('Support for $appName (Android)')}',
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Group(
              children: [
                _Tile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  onTap: () => _leave(
                    launchUrl(
                      Uri.parse(AppConfig.privacyPolicyUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ),
                // Required by Google's EU consent policy when UMP says so.
                if (AdsService.instance.privacyOptionsRequired)
                  _Tile(
                    icon: Icons.tune_rounded,
                    title: 'Privacy settings',
                    value: 'Manage ad consent',
                    onTap: AdsService.instance.showPrivacyOptions,
                  ),
                _Tile(
                  icon: Icons.description_outlined,
                  title: 'Terms of Use',
                  onTap: () => _leave(
                    launchUrl(
                      Uri.parse(AppConfig.termsUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick<T>(
    BuildContext context, {
    required String title,
    required String subtitle,
    required T current,
    required Map<T, String> options,
    required ValueChanged<T> onSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: context.text.titleLarge),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: context.text.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              RadioGroup<T>(
                groupValue: current,
                onChanged: (v) {
                  if (v != null) onSelected(v);
                  Navigator.pop(context);
                },
                child: Column(
                  children: [
                    for (final e in options.entries)
                      RadioListTile<T>(
                        value: e.key,
                        title: Text(e.value, style: context.text.bodyLarge),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Marks that the user is leaving for another app, so no app-open ad greets them on return.
void _leave(Future<Object?> launched) {
  AdsService.instance.suppressNextAppOpen();
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: children),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.value,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: value != null ? Text(value!) : null,
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
