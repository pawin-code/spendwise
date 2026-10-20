import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

enum ExportOutcome { saved, shared, canceled, failed }

/// Hands a generated file to the user via Android's system "save as" dialog
/// (no storage permission needed) or the share sheet. Files are never written
/// to shared storage without the user choosing a destination.
class ExportHelper {
  const ExportHelper();

  Future<ExportOutcome> saveToDevice({
    required String fileName,
    required String content,
    String mimeType = 'text/csv',
  }) async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(content));
      final uri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
        dialogTitle: 'Save $fileName',
      );
      return uri == null ? ExportOutcome.canceled : ExportOutcome.saved;
    } catch (_) {
      return ExportOutcome.failed;
    }
  }

  Future<ExportOutcome> share({
    required String fileName,
    required String content,
    String mimeType = 'text/csv',
  }) async {
    File? temp;
    try {
      final dir = await getTemporaryDirectory();
      temp = File(p.join(dir.path, fileName));
      await temp.writeAsString(content, flush: true);
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(temp.path, mimeType: mimeType)],
          subject: fileName,
        ),
      );
      return result.status == ShareResultStatus.dismissed
          ? ExportOutcome.canceled
          : ExportOutcome.shared;
    } catch (_) {
      return ExportOutcome.failed;
    } finally {
      // Remove the temporary copy once the share sheet has been handled.
      try {
        if (temp != null && await temp.exists()) await temp.delete();
      } catch (_) {}
    }
  }

  /// Reads a user-picked text file. Returns null if the user cancels.
  Future<String?> pickTextFile({
    List<String> extensions = const ['csv', 'txt'],
  }) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (result.isEmpty) return null;
    final file = result.first;
    final bytes = await file.readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }
}
