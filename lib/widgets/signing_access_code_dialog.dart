import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SigningAccessCodeDialog extends StatefulWidget {
  const SigningAccessCodeDialog({
    super.key,
    required this.accessCode,
    required this.isRtl,
  });

  final String accessCode;
  final bool isRtl;

  static Future<bool> show(
    BuildContext context, {
    required String accessCode,
    required bool isRtl,
  }) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              SigningAccessCodeDialog(accessCode: accessCode, isRtl: isRtl),
        ) ??
        false;
  }

  @override
  State<SigningAccessCodeDialog> createState() =>
      _SigningAccessCodeDialogState();
}

class _SigningAccessCodeDialogState extends State<SigningAccessCodeDialog> {
  bool _copied = false;

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.accessCode));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.isRtl ? 'הקוד הועתק' : 'Code copied'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Directionality(
      textDirection: widget.isRtl ? TextDirection.rtl : TextDirection.ltr,
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
                      Icons.key_rounded,
                      color: colors.onPrimaryContainer,
                      size: 29,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.isRtl ? 'קוד הגישה מוכן' : 'Access code ready',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isRtl
                      ? 'שלח את הקוד ללקוח בהודעה נפרדת מהקישור.'
                      : 'Send this code to the client in a separate message from the link.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                Semantics(
                  label: widget.isRtl
                      ? 'קוד גישה ${widget.accessCode}'
                      : 'Access code ${widget.accessCode}',
                  button: true,
                  child: InkWell(
                    onTap: _copyCode,
                    borderRadius: BorderRadius.circular(18),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                widget.accessCode,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2.4,
                                  color: colors.onSurface,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: Icon(
                              _copied
                                  ? Icons.check_circle_rounded
                                  : Icons.copy_rounded,
                              key: ValueKey(_copied),
                              color: _copied ? colors.tertiary : colors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.isRtl
                      ? 'אפשר ללחוץ על הקוד כדי להעתיק אותו'
                      : 'Tap the code to copy it',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.send_rounded),
                    label: Text(widget.isRtl ? 'שלח את הקוד' : 'Send code'),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(widget.isRtl ? 'אישור' : 'OK'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
