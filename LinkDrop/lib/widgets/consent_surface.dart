import 'package:flutter/material.dart';

import '../models/manifest_entry.dart';
import '../widgets/linkdrop_shell.dart';
import '../widgets/transfer_progress_view.dart';

/// The accept/reject decision for a whole incoming batch.
///
/// This is a security decision, not a notification, so the surface is built
/// to be answered deliberately:
///
/// - It is **not dismissible** by tapping outside, swiping, or dragging.
/// - **Neither button is autofocused** — there is no Enter-to-accept.
/// - A dismissal of any kind (back gesture, app backgrounded, timeout)
///   resolves to *declined*. Consent is never inferred from silence.
/// - It names what arrives, from whom, how much, where it will be saved, and
///   the fingerprint to compare — enough to actually be checked.
///
/// Desktop gets a 560dp modal; phone gets a bottom sheet with 54dp actions.
/// The switch at the phone breakpoint is a different presentation, not a
/// resize of the same one.
Future<bool> showIncomingRequest(
  BuildContext context, {
  required List<ManifestEntry> files,
  required String senderIp,
  required String destination,
  String? fingerprint,
  bool senderIsPhone = true,
}) async {
  final isPhone = MediaQuery.sizeOf(context).width < Bp.phone;

  final body = _ConsentBody(
    files: files,
    senderIp: senderIp,
    destination: destination,
    fingerprint: fingerprint,
    senderIsPhone: senderIsPhone,
    isPhone: isPhone,
  );

  final bool? result;
  if (isPhone) {
    result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => body,
    );
  } else {
    result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: body,
        ),
      ),
    );
  }

  // Anything other than an explicit Accept is a decline.
  return result ?? false;
}

class _ConsentBody extends StatelessWidget {
  const _ConsentBody({
    required this.files,
    required this.senderIp,
    required this.destination,
    required this.fingerprint,
    required this.senderIsPhone,
    required this.isPhone,
  });

  final List<ManifestEntry> files;
  final String senderIp;
  final String destination;
  final String? fingerprint;
  final bool senderIsPhone;
  final bool isPhone;

  int get _totalBytes => files.fold(0, (sum, f) => sum + f.size);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final count = files.length;

    final header = Padding(
      padding: EdgeInsets.fromLTRB(isPhone ? 0 : 22, isPhone ? 0 : 20, isPhone ? 0 : 22, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              senderIsPhone ? Icons.smartphone_outlined : Icons.laptop_outlined,
              size: 22,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$senderIp wants to send $count '
                  '${count == 1 ? 'file' : 'files'}',
                  style: text.headlineMedium?.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 2),
                Text(
                  'same network',
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: scheme.primary, width: 1),
            ),
            child: Text(
              formatBytes(_totalBytes),
              style: TextStyle(fontSize: 11, color: scheme.primary),
            ),
          ),
        ],
      ),
    );

    final list = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: isPhone ? 200 : 250),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.symmetric(horizontal: isPhone ? 0 : 22),
        itemCount: files.length,
        itemBuilder: (context, i) {
          final file = files[i];
          return Container(
            constraints: const BoxConstraints(minHeight: 46),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: scheme.outlineVariant, width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.insert_drive_file_outlined,
                    size: 17, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(fontSize: 13),
                  ),
                ),
                Text(
                  formatBytes(file.size),
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        },
      ),
    );

    final footer = Padding(
      padding: EdgeInsets.fromLTRB(
          isPhone ? 0 : 22, 14, isPhone ? 0 : 22, isPhone ? 0 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fingerprint != null) ...[
            Row(
              children: [
                Icon(Icons.fingerprint, size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  fingerprint!,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Compare this on the sending device before accepting.',
              style:
                  text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            'Saves to $destination',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          // Decline is a full peer of Accept, never a text link tucked away.
          Row(
            children: [
              Expanded(
                flex: 10,
                child: SizedBox(
                  height: isPhone ? 54 : 44,
                  child: TextButton(
                    // Explicitly not autofocused — the decision must be an act.
                    autofocus: false,
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Decline'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 14,
                child: SizedBox(
                  height: isPhone ? 54 : 44,
                  child: OutlinedButton(
                    autofocus: false,
                    onPressed: () => Navigator.of(context).pop(true),
                    // The action names its own consequence.
                    child: Text('Accept $count '
                        '${count == 1 ? 'file' : 'files'}'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [header, Flexible(child: list), footer],
    );

    if (!isPhone) return content;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Flexible(child: content),
        ],
      ),
    );
  }
}
