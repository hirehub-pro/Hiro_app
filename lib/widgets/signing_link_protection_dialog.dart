import 'package:flutter/material.dart';

class SigningLinkProtectionDialog extends StatelessWidget {
  const SigningLinkProtectionDialog({super.key, required this.isRtl});

  final bool isRtl;

  static Future<bool?> show(BuildContext context, {required bool isRtl}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => SigningLinkProtectionDialog(isRtl: isRtl),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.shield_outlined,
                      color: colors.onPrimaryContainer,
                      size: 29,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  isRtl ? 'להגן על קישור החתימה?' : 'Protect the signing link?',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isRtl
                      ? 'קוד גישה אקראי יגן על המסמך. הקישור והקוד ישותפו עם הלקוח בשתי הודעות נפרדות.'
                      : 'A random access code will protect the document. The link and code will be shared with the client in two separate messages.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 20,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isRtl
                              ? 'מומלץ כשבמסמך יש מידע אישי או כספי.'
                              : 'Recommended when the document contains personal or financial information.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.lock_outline_rounded),
                    label: Text(
                      isRtl ? 'אבטח באמצעות קוד' : 'Protect with a code',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(
                      isRtl ? 'המשך ללא קוד' : 'Continue without a code',
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(isRtl ? 'ביטול' : 'Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
