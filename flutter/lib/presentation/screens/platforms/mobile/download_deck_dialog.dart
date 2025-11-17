import 'dart:io';
import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'package:quick_click_match/services/auth_service.dart';
import 'package:quick_click_match/services/localization_service.dart';
import 'package:quick_click_match/utils/debug_logger.dart';

Future<List<String>> fetchFileList() async {
  final authCredentials = AuthService.getCurrentAuthCredentials();

  if (authCredentials == null) {
    throw Exception('User not authenticated. Please sign in.');
  }
  final apiUrl =
      'https://375k05yif7.execute-api.eu-north-1.amazonaws.com/dev/GetPresignedS3Url';
  final userId = authCredentials.id;
  debugLog('Attempting to call API: $apiUrl');

  try {
    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {
        'Authorization': 'Bearer ${authCredentials.cognitoIdToken}',
        'Content-Type': 'application/json',
      },
      body: json.encode({'userId': userId, 'action': 'getPermittedDecks'}),
    );

    debugLog('Response Status Code: ${response.statusCode}');
    if (response.statusCode == 200) {
      final Map<String, dynamic> jsonResponse = json.decode(response.body);
      List<dynamic> permittedDecks = jsonResponse['permitted_decks'];
      return List<String>.from(permittedDecks);
    } else {
      throw Exception('Failed to load file list');
    }
  } catch (e) {
    debugLog('Network or API Error: $e');
    throw Exception('Failed to connect to API or parse response: $e');
  }
}

Future<String?> showFilePickerDialog(BuildContext context) async {
  final files = await fetchFileList();
  if (!context.mounted) return null;
  final l10n = LocalizationService.instance;

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      bool isDownloading = false;
      String? downloadingFile;
      String? errorMessage;

      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.t('downloadDialog.title')),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDownloading)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            (downloadingFile?.isNotEmpty ?? false)
                                ? l10n.format('downloadDialog.downloading',
                                    {'file': downloadingFile!})
                                : l10n.t('downloadDialog.downloadingNoName'),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: AbsorbPointer(
                    absorbing: isDownloading,
                    child: Scrollbar(
                      child: ListView.separated(
                        itemCount: files.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final file = files[index];
                          return ListTile(
                            title: Text(file),
                            onTap: () async {
                              if (isDownloading) return;
                              setState(() {
                                isDownloading = true;
                                downloadingFile = file;
                                errorMessage = null;
                              });
                              try {
                                await downloadAndUnzipDeck(file);
                                if (Navigator.of(dialogContext).canPop()) {
                                  Navigator.of(dialogContext).pop(file);
                                }
                              } catch (e) {
                                setState(() {
                                  isDownloading = false;
                                  downloadingFile = null;
                                  errorMessage = l10n.format(
                                    'downloadDialog.error',
                                    {'reason': '$e'},
                                  );
                                });
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isDownloading
                  ? null
                  : () => Navigator.pop(dialogContext, null),
              child: Text(l10n.t('action.cancel')),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> downloadAndUnzipDeck(String file) async {
  final authCredentials = AuthService.getCurrentAuthCredentials();
  debugLog('authCredentials: $authCredentials');
  if (authCredentials == null) {
    throw Exception('User not authenticated. Please sign in.');
  }
  final apiUrl =
      'https://375k05yif7.execute-api.eu-north-1.amazonaws.com/dev/GetPresignedS3Url';
  final userId = authCredentials.id;
  final fileName = file;

  final response = await http.post(
    Uri.parse(apiUrl),
    headers: {
      'Authorization': 'Bearer ${authCredentials.cognitoIdToken}',
      'Content-Type': 'application/json',
    },
    body: json.encode(
        {'userId': userId, 'fileName': fileName, 'action': 'getPresignedUrl'}),
  );

  if (response.statusCode == 200) {
    final presignedUrl = json.decode(response.body);
    final fileResponse =
        await http.get(Uri.parse(presignedUrl['presigned_url']));
    if (fileResponse.statusCode == 200) {
      final bytes = fileResponse.bodyBytes;
      final archive = ZipDecoder().decodeBytes(bytes);

      final directory = await getApplicationDocumentsDirectory();
      final outputDir = Directory('${directory.path}/deck_assets/');
      await outputDir.create(recursive: true);
      debugLog('${directory.path}/deck_assets');
      for (final file in archive) {
        debugLog('file name: ${file.name}');

        // Skip macOS metadata files
        if (file.name.contains('__MACOSX') ||
            file.name.contains('.DS_Store') ||
            file.name.startsWith('._')) {
          debugLog('Skipping macOS metadata file: ${file.name}');
          continue;
        }

        final filename = '${outputDir.path}/${file.name}';
        if (file.isFile) {
          final outFile = File(filename);
          debugLog(filename);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(filename).create(recursive: true);
        }
      }

      debugLog('Deck downloaded and extracted to: ${outputDir.path}');
    }
  } else {
    throw Exception('Failed to download: ${response.statusCode}');
  }
}
