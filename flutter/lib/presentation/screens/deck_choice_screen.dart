// lib/presentation/screens/deck_choice_screen.dart
import 'package:flutter/material.dart';
import '../../infra/platform/file_manager_factory.dart';
import '../../infra/platform/file_manager.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quick_click_match/presentation/screens/platforms/mobile/download_deck_dialog.dart';
import 'package:quick_click_match/services/auth_service.dart';
import 'package:quick_click_match/constants/app_routes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quick_click_match/services/localization_service.dart';
import 'package:quick_click_match/utils/debug_logger.dart';
import 'package:quick_click_match/utils/deck_config.dart';
import 'package:quick_click_match/presentation/widgets/card_shape_utils.dart';

class DeckPreview {
  final String deckKey;
  final Uint8List? imageBytes;
  final String jsonKey;
  final String storageKey;
  final CardShape? _cardShape;

  CardShape get cardShape => _cardShape ?? CardShape.circle;

  DeckPreview({
    required this.deckKey,
    required this.jsonKey,
    required this.storageKey,
    CardShape cardShape = CardShape.circle,
    this.imageBytes,
  }) : _cardShape = cardShape;
}

class DeckChoiceScreen extends StatefulWidget {
  const DeckChoiceScreen({Key? key}) : super(key: key);

  @override
  _DeckChoiceScreen createState() => _DeckChoiceScreen();
}

class _DeckChoiceScreen extends State<DeckChoiceScreen> {
  List<DeckPreview> _decks = [];
  bool _loading = true;
  Timer? _singleTapTimer;
  String? _pendingTapDeckKey;
  String? _deckPendingRemovalKey;

  String _cleanDeckLabel(String value) {
    return value.trim().replaceFirst(RegExp(r'^/+'), '');
  }

  String _normalizeFolder(String value) {
    final cleaned = _cleanDeckLabel(value);
    if (cleaned.startsWith('deck_assets/')) {
      return cleaned.substring('deck_assets/'.length);
    }
    return cleaned;
  }

  bool _isUsablePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.contains('[') || trimmed.contains(']')) return false;
    const allowedExt = ['.png', '.jpg', '.jpeg', '.webp'];
    return allowedExt.any((ext) => trimmed.toLowerCase().endsWith(ext));
  }

  String? _extractPreviewSrc(Map<String, dynamic> jsonData) {
    final cardImages = jsonData['card_images'];

    if (cardImages is List && cardImages.isNotEmpty) {
      final first = cardImages.first;
      if (first is Map) {
        final src = first['src'];
        if (src is String && _isUsablePath(src)) return src;
      }
    } else if (cardImages is Map && cardImages.isNotEmpty) {
      for (final value in cardImages.values) {
        if (value is Map) {
          final src = value['src'];
          if (src is String && _isUsablePath(src)) return src;
        }
      }
    }

    final cards = jsonData['cards'];
    if (cards is List) {
      for (final card in cards) {
        if (card is Map) {
          final src = card['src'];
          if (src is String && _isUsablePath(src)) return src;

          final legacy = card['card_image_url'];
          if (legacy is String && legacy.trim().isNotEmpty) {
            final folder = jsonData['deck_folder_name'];
            if (folder is String && folder.trim().isNotEmpty) {
              final combined = '$folder/$legacy';
              if (_isUsablePath(combined)) return combined;
            }
            if (_isUsablePath(legacy)) return legacy;
          }
        }
      }
    }

    return null;
  }

  Future<Uint8List?> _loadPreviewImage({
    required FileManager fileManager,
    required String jsonKey,
    required String deckFolder,
    required String rawSrc,
  }) async {
    final normalizedSrc = rawSrc.trim().replaceAll('\\', '/');
    if (normalizedSrc.isEmpty) {
      return null;
    }
    final withoutLeadingSlash = normalizedSrc.startsWith('/')
        ? normalizedSrc.substring(1)
        : normalizedSrc;
    final strippedDeckAssets = withoutLeadingSlash.startsWith('deck_assets/')
        ? withoutLeadingSlash.substring('deck_assets/'.length)
        : withoutLeadingSlash;
    final fileName = strippedDeckAssets.split('/').last;
    if (fileName.isEmpty) return null;

    final relativeCandidates = <String>{
      strippedDeckAssets,
      '$deckFolder/$fileName',
      '$jsonKey/$fileName',
    }
        .map(
            (path) => path.replaceAll(RegExp(r'^/+'), '').replaceAll('//', '/'))
        .where((path) => path.isNotEmpty)
        .toList();

    for (final candidate in relativeCandidates) {
      try {
        final bytes = await fileManager.readImage(candidate);
        return Uint8List.fromList(bytes);
      } catch (_) {
        // Continue trying other candidates
        debugLog('[DeckChoice] FileManager read failed for "$candidate"');
      }
    }

    final assetCandidates = <String>{
      if (withoutLeadingSlash.startsWith('assets/'))
        withoutLeadingSlash
      else
        'assets/$withoutLeadingSlash',
      'assets/deck_assets/$deckFolder/$fileName',
      'assets/deck_assets/$jsonKey/$fileName',
      'assets/$deckFolder/$fileName',
    }
        .map((path) => path.replaceAll(RegExp(r'/+'), '/'))
        .where((path) => path.split('/').last.isNotEmpty)
        .toSet();

    for (final assetPath in assetCandidates) {
      try {
        final byteData = await rootBundle.load(assetPath);
        return byteData.buffer.asUint8List();
      } on FlutterError {
        // Asset not found, continue with next candidate
        debugLog('[DeckChoice] Asset load failed for "$assetPath"');
      }
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadDecks();
  }

  @override
  void dispose() {
    _singleTapTimer?.cancel();
    super.dispose();
  }

  Future<void> _seedDefaultDecksForWeb(FileManager fileManager) async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);
      final defaultDecks = _extractDefaultDeckAssets(manifestMap);

      for (final entry in defaultDecks.entries) {
        final deckKey = entry.key;
        final jsonAsset = entry.value
            .firstWhere((asset) => asset.endsWith('.json'), orElse: () => '');

        if (jsonAsset.isNotEmpty) {
          final existingJson = await _tryReadDeckJson(fileManager, deckKey);
          if (existingJson == null) {
            try {
              final jsonString = await rootBundle.loadString(jsonAsset);
              await fileManager.writeJSON(deckKey, jsonString);
            } catch (e) {
              debugLog(
                  'Failed to seed deck JSON for $deckKey from $jsonAsset: $e');
              continue;
            }
          }
        }

        for (final asset in entry.value.where(_isImageAsset)) {
          try {
            final relativePath = _relativeDeckAssetPath(asset);
            if (relativePath == null) continue;

            final data = await rootBundle.load(asset);
            final bytes =
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
            await fileManager.writeImage(relativePath, bytes);
          } catch (e) {
            debugLog('Failed to seed deck image $asset: $e');
          }
        }
      }
    } catch (e, stack) {
      debugLog('Error seeding default decks for web: $e\n$stack');
    }
  }

  Future<String?> _tryReadDeckJson(
      FileManager fileManager, String deckKey) async {
    try {
      return await fileManager.readJSON(deckKey);
    } catch (_) {
      return null;
    }
  }

  Map<String, List<String>> _extractDefaultDeckAssets(
      Map<String, dynamic> manifest) {
    const prefix = 'assets/deck_assets/';
    final Map<String, List<String>> decks = {};

    for (final asset in manifest.keys) {
      if (!asset.startsWith(prefix)) continue;
      final relative = asset.substring(prefix.length);
      if (relative.isEmpty || _isHiddenAsset(relative)) continue;

      String deckKey;
      if (relative.contains('/')) {
        deckKey = relative.split('/').first;
      } else if (relative.endsWith('.json')) {
        deckKey = relative.substring(0, relative.length - 5);
      } else {
        continue;
      }

      decks.putIfAbsent(deckKey, () => []).add(asset);
    }

    return decks;
  }

  bool _isImageAsset(String assetPath) {
    return assetPath.endsWith('.png') ||
        assetPath.endsWith('.jpg') ||
        assetPath.endsWith('.jpeg');
  }

  String? _relativeDeckAssetPath(String assetPath) {
    const prefix = 'assets/deck_assets/';
    if (!assetPath.startsWith(prefix)) {
      return null;
    }
    var relative = assetPath.substring(prefix.length);
    if (relative.startsWith('/')) {
      relative = relative.substring(1);
    }
    if (_isHiddenAsset(relative)) {
      return null;
    }
    return relative;
  }

  Future<void> _loadDecks() async {
    final fileManager = FileManagerFactory.create();
    List<DeckPreview> decks = [];
    try {
      if (kIsWeb) {
        await _seedDefaultDecksForWeb(fileManager);
      }

      final allJsonKeys = await fileManager.getSubfolders('deck_assets/');

      for (final jsonKey in allJsonKeys) {
        try {
          final normalizedJsonKey = _normalizeFolder(jsonKey);
          String? resolvedJsonKey;
          String? jsonString;

          for (final candidate in {
            normalizedJsonKey,
            jsonKey,
            '$normalizedJsonKey/$normalizedJsonKey',
          }) {
            if (candidate.isEmpty) continue;
            try {
              jsonString = await fileManager.readJSON(candidate);
              if (jsonString != null) {
                resolvedJsonKey = candidate;
                break;
              }
            } catch (_) {
              continue;
            }
          }

          if (jsonString == null || resolvedJsonKey == null) {
            decks.add(DeckPreview(
              deckKey: _cleanDeckLabel(jsonKey),
              jsonKey: jsonKey,
              storageKey: _normalizeFolder(jsonKey),
            ));
            continue;
          }

          final jsonData = jsonDecode(jsonString);
          final rawDeckName =
              (jsonData['deck_folder_name'] as String?) ?? resolvedJsonKey;
          final deckName = _cleanDeckLabel(rawDeckName);
          final deckFolder = _normalizeFolder(rawDeckName);

          Uint8List? previewBytes;
          final previewSrc = _extractPreviewSrc(jsonData);
          if (previewSrc != null) {
            previewBytes = await _loadPreviewImage(
              fileManager: fileManager,
              jsonKey: _normalizeFolder(resolvedJsonKey),
              deckFolder: deckFolder,
              rawSrc: previewSrc,
            );
          }
          decks.add(DeckPreview(
            deckKey: deckName,
            jsonKey: resolvedJsonKey,
            storageKey: _normalizeFolder(resolvedJsonKey),
            cardShape: parseCardShape(jsonData['card_shape'] as String?),
            imageBytes: previewBytes,
          ));
        } catch (e) {
          decks.add(DeckPreview(
            deckKey: _cleanDeckLabel(jsonKey),
            jsonKey: jsonKey,
            storageKey: _normalizeFolder(jsonKey),
            cardShape: CardShape.circle,
          ));
        }
      }
    } catch (e) {
      // handle error
    }
    setState(() {
      _decks = decks;
      _loading = false;
    });
  }

  bool _isHiddenAsset(String relativePath) {
    return relativePath.startsWith('.') ||
        relativePath.contains('/.') ||
        relativePath.contains('__MACOSX') ||
        relativePath.endsWith('.DS_Store');
  }

  void _cancelPendingTap() {
    _singleTapTimer?.cancel();
    _pendingTapDeckKey = null;
  }

  void _showDeleteHandle(DeckPreview deck) {
    setState(() {
      _deckPendingRemovalKey = deck.jsonKey;
    });
  }

  void _hideDeleteHandle() {
    if (_deckPendingRemovalKey != null) {
      setState(() {
        _deckPendingRemovalKey = null;
      });
    }
  }

  Future<void> _selectDeck(DeckPreview deck) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_deck_key', deck.jsonKey);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _handleDeckTap(DeckPreview deck) {
    if (_deckPendingRemovalKey != null) {
      _hideDeleteHandle();
      _cancelPendingTap();
      return;
    }
    final isPendingSameDeck =
        _pendingTapDeckKey == deck.jsonKey && _singleTapTimer?.isActive == true;

    if (isPendingSameDeck) {
      _cancelPendingTap();
      _showDeleteHandle(deck);
      return;
    }

    _cancelPendingTap();
    _pendingTapDeckKey = deck.jsonKey;
    _singleTapTimer = Timer(const Duration(milliseconds: 300), () {
      _pendingTapDeckKey = null;
      unawaited(_selectDeck(deck));
    });
  }

  Future<void> _promptDeleteDeck(DeckPreview deck) async {
    final l10n = LocalizationService.instance;
    _cancelPendingTap();
    _hideDeleteHandle();
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('deckChoice.delete.confirmTitle')),
        content: Text(
          l10n.format(
            'deckChoice.delete.confirmMessage',
            {'deck': deck.deckKey},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.t('action.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.t('deckChoice.delete.confirmAction')),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      await _deleteDeckFromDisk(deck);
    }
  }

  Future<void> _deleteDeckFromDisk(DeckPreview deck) async {
    final l10n = LocalizationService.instance;
    final fileManager = FileManagerFactory.create();

    try {
      await fileManager.deleteDeck(deck.storageKey);
      final prefs = await SharedPreferences.getInstance();
      final selectedDeckKey = prefs.getString('selected_deck_key');
      if (selectedDeckKey == deck.jsonKey) {
        await prefs.remove('selected_deck_key');
      }

      if (!mounted) return;
      setState(() {
        _decks = _decks.where((item) => item.jsonKey != deck.jsonKey).toList();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('deckChoice.snackbar.deleteComplete'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.format(
              'deckChoice.snackbar.deleteFailed',
              {'reason': '$e'},
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = LocalizationService.instance;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(color: Color(0xFFECE8FF)),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 640;
                    final downloadButton = _buildDownloadDeckButton();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFF5E35B1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back,
                                    color: Colors.white, size: 20),
                                padding: EdgeInsets.zero,
                                onPressed: () => Navigator.pop(context),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                l10n.t('deckChoice.title'),
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                            ),
                            if (isWide) downloadButton,
                          ],
                        ),
                        if (!isWide) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: downloadButton,
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Content
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _decks.isEmpty
                        ? Center(
                            child: Text(
                              l10n.t('deckChoice.empty'),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: GridView.builder(
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 16,
                                      mainAxisSpacing: 16,
                                      childAspectRatio: 0.9,
                                    ),
                                    itemCount: _decks.length,
                                    itemBuilder: (context, index) {
                                      final deck = _decks[index];
                                      return _buildDeckCard(deck);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeckCard(DeckPreview deck) {
    final shape = buildCardShapeBorder(deck.cardShape);
    final shapeWithBorder = buildCardShapeBorder(
      deck.cardShape,
      side: BorderSide(
        color: Colors.white.withValues(alpha: 0.9),
        width: 5,
      ),
    );
    final shapeClipper = ShapeBorderClipper(shape: shape);
    final isShowingDelete = _deckPendingRemovalKey == deck.jsonKey;

    return GestureDetector(
      onTap: () => _handleDeckTap(deck),
      onLongPress: () {
        if (isShowingDelete) {
          _hideDeleteHandle();
        } else {
          _showDeleteHandle(deck);
        }
      },
      onTapCancel: _cancelPendingTap,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          shape: shapeWithBorder,
                          gradient: const RadialGradient(
                            colors: [
                              Color(0xFFE6DEFF),
                              Color(0xFFFDFBFF),
                              Color(0xFFFFFFFF),
                            ],
                            radius: 0.85,
                            center: Alignment(-0.2, -0.25),
                          ),
                          shadows: [
                            BoxShadow(
                              color:
                                  Colors.deepPurpleAccent.withValues(alpha: 0.15),
                              blurRadius: 22,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: ClipPath(
                          clipper: shapeClipper,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.white,
                            ),
                            child: deck.imageBytes != null
                                ? Image.memory(
                                    deck.imageBytes!,
                                    fit: BoxFit.cover,
                                  )
                                : Center(
                                    child: Icon(
                                      Icons.style,
                                      size: 42,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    deck.deckKey,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: isShowingDelete ? 1 : 0,
              child: IgnorePointer(
                ignoring: !isShowingDelete,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.redAccent.withValues(alpha: 0.4),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => _promptDeleteDeck(deck),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDownloadDeck() async {
    final l10n = LocalizationService.instance;
    final authCredentials = AuthService.getCurrentAuthCredentials();

    if (authCredentials != null) {
      // User is signed in, proceed to download
      try {
        final downloadedFile = await showFilePickerDialog(context);
        if (downloadedFile != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l10n.t('deckChoice.snackbar.downloadComplete'),
              ),
            ),
          );
          // ✨ Crucial: Reload decks to show the new one!
          _loadDecks();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l10n.format(
                  'deckChoice.snackbar.downloadFailed',
                  {'reason': '$e'},
                ),
              ),
            ),
          );
        }
      }
    } else {
      // User is NOT signed in, show the sign-in prompt
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            l10n.t('deckChoice.authRequired.title'),
          ),
          content: Text(
            l10n.t('deckChoice.authRequired.message'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.t('action.cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                // 1. Close the alert dialog
                Navigator.of(dialogContext).pop();

                // 2. Navigate to the Auth screen and wait for it to be closed
                final result =
                    await Navigator.pushNamed(context, AppRoutes.auth);

                // 3. After returning from AuthScreen, re-run this logic
                // This will check credentials again and open the download dialog if successful.
                if (result == true) {
                  _handleDownloadDeck();
                }
              },
              child: Text(l10n.t('action.signIn')),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildDownloadDeckButton() {
    final l10n = LocalizationService.instance;
    return GestureDetector(
      onTap: () async {
        _handleDownloadDeck();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF009688).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.download,
                color: Color(0xFF009688),
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('deckChoice.download.title'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.t('deckChoice.download.subtitle'),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
