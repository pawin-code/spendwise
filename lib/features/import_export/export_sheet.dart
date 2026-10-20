import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/services/export_helper.dart';

/// Lets the user choose where an exported file goes. The content is produced
/// only after they pick an option, and a reminder explains exports are readable.
Future<void> showExportSheet(
  BuildContext context,
  WidgetRef ref, {
  required String fileName,
  required String Function() build,
  Future<String> Function()? buildAsync,
  String mimeType = 'text/csv',
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Export $fileName',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(sheetContext).colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Exported files are not encrypted and contain your financial details. Only share them with people and apps you trust.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.save_alt),
              label: const Text('Save to device'),
              onPressed: () async {
                Navigator.pop(sheetContext);
                final content = buildAsync != null
                    ? await buildAsync()
                    : build();
                final r = await const ExportHelper().saveToDevice(
                  fileName: fileName,
                  content: content,
                  mimeType: mimeType,
                );
                if (context.mounted) _report(context, r);
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share…'),
              onPressed: () async {
                Navigator.pop(sheetContext);
                final content = buildAsync != null
                    ? await buildAsync()
                    : build();
                final r = await const ExportHelper().share(
                  fileName: fileName,
                  content: content,
                  mimeType: mimeType,
                );
                if (context.mounted) _report(context, r);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

void _report(BuildContext context, ExportOutcome r) {
  switch (r) {
    case ExportOutcome.saved:
      showSnack(context, 'File saved');
    case ExportOutcome.shared:
      showSnack(context, 'Shared');
    case ExportOutcome.canceled:
      break;
    case ExportOutcome.failed:
      showSnack(context, 'Could not export the file. Please try again.');
  }
}
