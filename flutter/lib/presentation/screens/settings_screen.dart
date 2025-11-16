import 'package:flutter/material.dart';
import 'package:quick_click_match/infra/config_service.dart';
import 'package:quick_click_match/constants/app_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quick_click_match/services/localization_service.dart';
import 'package:quick_click_match/services/auth_service.dart';
import 'package:quick_click_match/services/secure_credentials_storage.dart';
import 'package:quick_click_match/services/sound_service.dart';

class SettingsPage extends StatefulWidget {
  final ConfigService config;
  const SettingsPage({required this.config, Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _controller = TextEditingController();
  double _volume = 50;
  bool _soundEffects = true;
  bool _musicEnabled = true;
  bool _isCognitoLoggedIn = false;
  String? _currentDeck;
  String? _cognitoUserName;
  String? _cognitoEmail;
  String? _displayName;
  late final LocalizationService _l10n;
  late final SoundService _soundService;

  @override
  void initState() {
    super.initState();
    _l10n = LocalizationService.instance;
    _l10n.addListener(_onLocalizationChanged);
    _soundService = SoundService.instance;
    _soundService.addListener(_onSoundSettingsChanged);
    _volume = (_soundService.effectsVolume * 100).clamp(0, 100);
    _soundEffects = _soundService.effectsEnabled;
    _musicEnabled = _soundService.ambientEnabled;
    widget.config.getServerIP().then((ip) {
      if (ip != null) _controller.text = ip;
    });
    _loadUserData();
  }

  void _onLocalizationChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onSoundSettingsChanged() {
    if (!mounted) return;
    setState(() {
      _volume = (_soundService.effectsVolume * 100).clamp(0, 100);
      _soundEffects = _soundService.effectsEnabled;
      _musicEnabled = _soundService.ambientEnabled;
    });
  }

  @override
  void dispose() {
    _l10n.removeListener(_onLocalizationChanged);
    _soundService.removeListener(_onSoundSettingsChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final cognitoUserId = await SecureCredentialsStorage.getUserId();
    final cognitoUserName = await SecureCredentialsStorage.getUserName();
    final displayName = prefs.getString('display_name');
    final deckKey = prefs.getString('selected_deck_key');
    final isLoggedIn = await SecureCredentialsStorage.isAwsLoggedIn();

    if (!mounted) return;

    setState(() {
      _isCognitoLoggedIn = isLoggedIn;
      _cognitoUserName = cognitoUserName;
      _cognitoEmail = cognitoUserId;
      _displayName = displayName;
      _currentDeck = deckKey != null ? _getDeckDisplayName(deckKey) : null;
    });
  }

  Future<void> _handleDisconnect() async {
    await AuthService.signOut();
    await _loadUserData();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_l10n.t('auth.snackbar.signedOut')),
        backgroundColor: Colors.green,
      ),
    );
  }

  String _getDeckDisplayName(String deckKey) {
    final parts = deckKey.split('/');
    final deckName = parts.isNotEmpty ? parts.last : deckKey;
    return deckName
        .split('_')
        .map((word) => word.isNotEmpty
            ? word[0].toUpperCase() + word.substring(1).toLowerCase()
            : '')
        .join(' ');
  }

  Future<void> _changeDisplayName() async {
    final controller = TextEditingController(text: _displayName);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_l10n.t('settings.changeDisplayName.title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _l10n.t('settings.changeDisplayName.description'),
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: _l10n.t('settings.changeDisplayName.label'),
                border: const OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              maxLength: 20,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_l10n.t('action.cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: Text(_l10n.t('action.save')),
          ),
        ],
      ),
    );

    if (newName != null && newName != _displayName) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('display_name', newName);

      setState(() {
        _displayName = newName;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l10n.format('settings.snackbar.displayNameUpdated', {
            'name': newName,
          })),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showLanguageSheet() {
    final codes = _l10n.supportedLanguageCodes;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.7,
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    _l10n.t('settings.language.choose'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Scrollbar(
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: codes.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final code = codes[index];
                        return ListTile(
                          title: Text(_l10n.languageName(code)),
                          trailing: code == _l10n.currentLanguageCode
                              ? const Icon(Icons.check,
                                  color: Color(0xFF5E35B1))
                              : null,
                          onTap: () {
                            Navigator.of(context).pop();
                            _l10n.setLanguage(code);
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE3F2FD),
              Color(0xFFF3E5F5),
            ],
          ),
        ),
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
                child: Row(
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
                    Text(
                      l10n.t('settings.title'),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Multiplayer Profile Section
                    _buildSectionTitle(l10n.t('settings.section.profile')),
                    const SizedBox(height: 12),
                    _buildSettingCard(
                      icon: Icons.badge,
                      iconColor: const Color(0xFF2196F3),
                      title: l10n.t('settings.displayName.title'),
                      subtitle: _displayName ??
                          l10n.t('settings.displayName.subtitleUnset'),
                      trailing: ElevatedButton(
                        onPressed: _changeDisplayName,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2196F3),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                        ),
                        child:
                            Text(l10n.t('settings.displayName.changeButton')),
                      ),
                      onTap: null,
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        l10n.t('settings.displayName.helper'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Localization Section
                    _buildSectionTitle(l10n.t('settings.section.localization')),
                    const SizedBox(height: 12),
                    _buildSettingCard(
                      icon: Icons.language,
                      iconColor: const Color(0xFF5E35B1),
                      title: l10n.t('settings.language.title'),
                      subtitle: l10n.languageName(l10n.currentLanguageCode),
                      trailing:
                          const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: _showLanguageSheet,
                    ),
                    const SizedBox(height: 24),

                    // Sound Options Section
                    _buildSectionTitle(l10n.t('settings.section.sound')),
                    const SizedBox(height: 12),
                    Container(
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
                      child: Column(
                        children: [
                          // Volume Control
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEC4899)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.volume_up,
                                    color: Color(0xFFEC4899),
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  l10n.t('settings.sound.volume'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                SizedBox(
                                  width: 120,
                                  child: Slider(
                                    value: _volume,
                                    min: 0,
                                    max: 100,
                                    activeColor: const Color(0xFFEC4899),
                                    onChanged: (value) {
                                      setState(() => _volume = value);
                                      _soundService
                                          .setEffectsVolume(value / 100);
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: 45,
                                  child: Text(
                                    '${_volume.round()}%',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          // Sound Effects Toggle
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF9C27B0)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.music_note,
                                    color: Color(0xFF9C27B0),
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  l10n.t('settings.sound.effects'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Switch(
                                  value: _soundEffects,
                                  activeColor: const Color(0xFFEC4899),
                                  onChanged: (value) {
                                    setState(() => _soundEffects = value);
                                    _soundService.setEffectsEnabled(value);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2196F3)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.audiotrack,
                                    color: Color(0xFF2196F3),
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  l10n.t('settings.sound.music'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Switch(
                                  value: _musicEnabled,
                                  activeColor: const Color(0xFFEC4899),
                                  onChanged: (value) {
                                    setState(() => _musicEnabled = value);
                                    _soundService.setAmbientEnabled(value);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Account Section (Cognito)
                    _buildSectionTitle(l10n.t('settings.section.aws')),
                    const SizedBox(height: 12),
                    _buildSettingCard(
                      icon: Icons.cloud,
                      iconColor: const Color(0xFFFF9800),
                      title: _isCognitoLoggedIn
                          ? l10n.t('settings.aws.signedInTitle')
                          : l10n.t('settings.aws.signedOutTitle'),
                      subtitle: _isCognitoLoggedIn
                          ? _cognitoUserName ??
                              _cognitoEmail ??
                              l10n.t('settings.aws.signedInSubtitle')
                          : l10n.t('settings.aws.signedOutSubtitle'),
                      trailing: ElevatedButton(
                        onPressed: () async {
                          if (_isCognitoLoggedIn) {
                            await _handleDisconnect();
                          } else {
                            Navigator.pushNamed(context, AppRoutes.auth)
                                .then((result) {
                              _loadUserData();
                              if (result == true) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(l10n
                                        .t('settings.snackbar.awsSignedIn')),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9800),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                        ),
                        child: Text(_isCognitoLoggedIn
                            ? l10n.t('settings.aws.button.manage')
                            : l10n.t('settings.aws.button.signIn')),
                      ),
                      onTap: null,
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        l10n.t('settings.aws.helper'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Game Deck Section
                    _buildSectionTitle(l10n.t('settings.section.deck')),
                    const SizedBox(height: 12),
                    _buildSettingCard(
                      icon: Icons.style,
                      iconColor: const Color(0xFFFFA726),
                      title: l10n.t('settings.deck.title'),
                      subtitle:
                          _currentDeck ?? l10n.t('settings.deck.subtitleUnset'),
                      leading: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF6B6B), Color(0xFFEC4899)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      trailing: ElevatedButton(
                        onPressed: () {
                          Navigator.pushNamed(context, AppRoutes.deck_choice)
                              .then((_) => _loadUserData());
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFC107),
                          foregroundColor: const Color(0xFF1F2937),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                        ),
                        child: Text(
                          l10n.t('settings.deck.button'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      onTap: null,
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1F2937),
      ),
    );
  }

  Widget _buildSettingCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    Widget? leading,
    VoidCallback? onTap,
  }) {
    return Container(
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                leading ??
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: iconColor, size: 28),
                    ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
