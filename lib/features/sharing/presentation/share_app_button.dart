import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../updates/update_service.dart' show releasesOrigin;

const appDownloadUrl = '$releasesOrigin/latest/download/reading-library.apk';
const appShareMessage =
    'Read with me on Reading Library — a place for your books and reading.\n\n'
    'Download for Android:\n$appDownloadUrl\n\n'
    'Open the downloaded APK and tap Install. If Android asks, allow installation from your browser.\n'
    'Already installed? Choose Update to keep your library.';

Future<void> copyAppDownloadLink(BuildContext context) async {
  String message;
  try {
    await Clipboard.setData(const ClipboardData(text: appDownloadUrl));
    message = 'Download link copied.';
  } catch (_) {
    message = 'Could not copy the link. Please try again.';
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Opens the native chooser; the reader chooses the app and recipient.
class ShareAppButton extends StatefulWidget {
  final bool iconOnly;
  const ShareAppButton({super.key, this.iconOnly = false});

  @override
  State<ShareAppButton> createState() => _ShareAppButtonState();
}

class _ShareAppButtonState extends State<ShareAppButton> {
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _sharing = true);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: appShareMessage,
          subject: 'Reading Library for Android',
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Could not open sharing. You can copy the link instead.',
          ),
          action: SnackBarAction(
            label: 'Copy link',
            onPressed: () => copyAppDownloadLink(context),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.iconOnly
      ? IconButton(
          tooltip: 'Share app',
          onPressed: _sharing ? null : _share,
          icon: const Icon(Icons.share_outlined),
        )
      : OutlinedButton.icon(
          onPressed: _sharing ? null : _share,
          icon: const Icon(Icons.share_outlined),
          label: const Text('Share app'),
        );
}
