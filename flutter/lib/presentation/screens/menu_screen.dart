// lib/presentation/screens/menu_screen.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:quick_click_match/constants/app_routes.dart';
import 'package:quick_click_match/services/localization_service.dart';
import 'package:quick_click_match/utils/debug_logger.dart';
import 'package:quick_click_match/services/sound_service.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.85);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final deckJson = args != null ? args['deckJson'] : null;
    final deckJsonKey = args != null ? args['deckJsonKey'] : null;
    final l10n = LocalizationService.instance;
    final modes = _buildGameModes(context, deckJson, deckJsonKey);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFAB7FF),
              Color(0xFFFBCAFF),
              Color(0xFFFFF59D),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 48),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          l10n.t('menu.headerTitle'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                offset: Offset(0, 2),
                                blurRadius: 4,
                                color: Colors.black26,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.settings, color: Colors.white),
                        onPressed: () {
                          SoundService.instance.playTap();
                          Navigator.pushNamed(context, AppRoutes.settings);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: LayoutBuilder(
                    builder: (context, contentConstraints) {
                      final mediaHeight = MediaQuery.of(context).size.height;
                      final hasBoundedHeight =
                          contentConstraints.hasBoundedHeight &&
                              contentConstraints.maxHeight.isFinite;
                      final availableHeight = hasBoundedHeight
                          ? contentConstraints.maxHeight
                          : mediaHeight * 0.75;

                      const navRowHeight = 62.0;
                      final rawMaxCarouselHeight =
                          availableHeight - navRowHeight;
                      double maxCarouselHeight =
                          rawMaxCarouselHeight.clamp(0.0, availableHeight);

                      const double minSpacingPixels = 24.0;
                      final double minSpacingRest =
                          math.max(minSpacingPixels, availableHeight * 0.08);
                      final double maxSpacingRest =
                          math.max(minSpacingRest, availableHeight * 0.2);

                      double carouselHeight = maxCarouselHeight.clamp(
                        0.0,
                        availableHeight,
                      );

                      double spacingRest =
                          availableHeight - navRowHeight - carouselHeight;

                      final double minCarouselHeight = math.min(carouselHeight,
                          math.max(220.0, availableHeight * 0.4));

                      if (spacingRest < minSpacingRest) {
                        final double reduction = minSpacingRest - spacingRest;
                        carouselHeight = (carouselHeight - reduction)
                            .clamp(minCarouselHeight, maxCarouselHeight);
                        spacingRest =
                            (availableHeight - navRowHeight - carouselHeight)
                                .clamp(minSpacingPixels, maxSpacingRest);
                      } else if (spacingRest > maxSpacingRest) {
                        final double expansion = spacingRest - maxSpacingRest;
                        carouselHeight = (carouselHeight + expansion)
                            .clamp(minCarouselHeight, maxCarouselHeight);
                        spacingRest =
                            (availableHeight - navRowHeight - carouselHeight)
                                .clamp(minSpacingRest, maxSpacingRest);
                      }

                      if (!carouselHeight.isFinite ||
                          carouselHeight <= 0 ||
                          spacingRest.isNaN) {
                        carouselHeight = math
                            .max(maxCarouselHeight, availableHeight * 0.6)
                            .clamp(0.0, maxCarouselHeight);
                        spacingRest =
                            (availableHeight - navRowHeight - carouselHeight)
                                .clamp(minSpacingRest, maxSpacingRest);
                      }

                      const double topRatio = 25.0;
                      const double betweenRatio = 70.0;
                      const double bottomRatio = 5.0;
                      const double ratioSum =
                          topRatio + betweenRatio + bottomRatio;

                      double unit = ratioSum > 0 ? spacingRest / ratioSum : 0;
                      double topSpacing = unit * topRatio;
                      double betweenSpacing = unit * betweenRatio;
                      double bottomSpacing = unit * bottomRatio;

                      if (spacingRest > 0) {
                        const double minGap = 4.0;
                        const double minBottomGap = 6.0;

                        topSpacing = topSpacing.clamp(minGap, spacingRest);
                        betweenSpacing =
                            betweenSpacing.clamp(minGap, spacingRest);
                        bottomSpacing =
                            bottomSpacing.clamp(minBottomGap, spacingRest);

                        final totalSpacing =
                            topSpacing + betweenSpacing + bottomSpacing;
                        if (totalSpacing > spacingRest && totalSpacing > 0) {
                          final scale = spacingRest / totalSpacing;
                          topSpacing *= scale;
                          betweenSpacing *= scale;
                          bottomSpacing *= scale;
                        }
                      } else {
                        topSpacing = betweenSpacing = bottomSpacing = 0;
                      }

                      return Column(
                        children: [
                          SizedBox(height: topSpacing),
                          SizedBox(
                            height: carouselHeight,
                            child: PageView.builder(
                              controller: _pageController,
                              onPageChanged: (index) {
                                setState(() {
                                  _currentPage = index;
                                });
                              },
                              itemCount: modes.length,
                              itemBuilder: (context, index) {
                                final mode = modes[index];
                                return Align(
                                  alignment: Alignment.center,
                                  child: FractionallySizedBox(
                                    heightFactor: 1,
                                    widthFactor: 0.96,
                                    child: _GameModeCard(item: mode),
                                  ),
                                );
                              },
                            ),
                          ),
                          SizedBox(height: betweenSpacing),
                          SizedBox(
                            height: navRowHeight,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildArrowButton(
                                  icon: Icons.arrow_back_ios_new,
                                  enabled: _currentPage > 0,
                                  onPressed: () {
                                    if (_currentPage > 0) {
                                      _pageController.previousPage(
                                        duration:
                                            const Duration(milliseconds: 300),
                                        curve: Curves.easeOut,
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(width: 16),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(
                                    modes.length,
                                    (index) => AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 250),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      width: _currentPage == index ? 14 : 10,
                                      height: _currentPage == index ? 14 : 10,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: _currentPage == index ? 1 : 0.5,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                _buildArrowButton(
                                  icon: Icons.arrow_forward_ios,
                                  enabled: _currentPage < modes.length - 1,
                                  onPressed: () {
                                    if (_currentPage < modes.length - 1) {
                                      _pageController.nextPage(
                                        duration:
                                            const Duration(milliseconds: 300),
                                        curve: Curves.easeOut,
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: bottomSpacing),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_GameModeCarouselItem> _buildGameModes(
    BuildContext context,
    String? deckJson,
    String? deckJsonKey,
  ) {
    final l10n = LocalizationService.instance;
    return [
      _GameModeCarouselItem(
        title: l10n.t('menu.train.title'),
        subtitle: l10n.t('menu.train.subtitle'),
        accentColor: const Color(0xFF4CAF50),
        assetPath: 'assets/menu/train_mode.png',
        onStart: () {
          SoundService.instance.playTap();
          Navigator.pushNamed(
            context,
            AppRoutes.game,
            arguments: {
              'gameMode': 'train',
              'deckJson': deckJson,
              'jsonKey': deckJsonKey,
            },
          );
        },
      ),
      _GameModeCarouselItem(
        title: l10n.t('menu.computer.title'),
        subtitle: l10n.t('menu.computer.subtitle'),
        accentColor: const Color(0xFF5E35B1),
        assetPath: 'assets/menu/computer_mode.png',
        onStart: () {
          SoundService.instance.playTap();
          _showComputerLevelSheet(context, deckJson, deckJsonKey);
        },
      ),
      _GameModeCarouselItem(
        title: l10n.t('menu.hotseat.title'),
        subtitle: l10n.t('menu.hotseat.subtitle'),
        accentColor: const Color(0xFFFF9800),
        assetPath: 'assets/menu/hot_seat_mode.png',
        onStart: () {
          SoundService.instance.playTap();
          _showHotSeatDialog(context, deckJson, deckJsonKey);
        },
      ),
      _GameModeCarouselItem(
        title: l10n.t('menu.friend.title'),
        subtitle: l10n.t('menu.friend.subtitle'),
        accentColor: const Color(0xFF2196F3),
        assetPath: 'assets/menu/friend_mode.png',
        onStart: () {
          SoundService.instance.playTap();
          Navigator.pushNamed(
            context,
            AppRoutes.lobby,
            arguments: {
              'deckJson': deckJson,
              'deckJsonKey': deckJsonKey,
            },
          );
        },
      ),
    ];
  }

  Widget _buildArrowButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white
            .withValues(alpha: enabled ? 0.9 : 0.4),
        borderRadius: BorderRadius.circular(24),
      ),
      child: IconButton(
        icon: Icon(icon, color: const Color(0xFF5E35B1)),
        onPressed: enabled
            ? () {
                SoundService.instance.playTap();
                onPressed();
              }
            : null,
      ),
    );
  }

  void _showHotSeatDialog(
    BuildContext context,
    String? deckJson,
    String? deckJsonKey,
  ) {
    final parentContext = context;
    final player1Controller = TextEditingController(text: '');
    final player2Controller = TextEditingController(text: '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _HotSeatSetupSheet(
          parentContext: parentContext,
          player1Controller: player1Controller,
          player2Controller: player2Controller,
          onStart: (player1, player2) {
            SoundService.instance.playTap();
            Navigator.pushNamed(
              parentContext,
              AppRoutes.game,
              arguments: {
                'gameMode': 'hotseat',
                'deckJson': deckJson,
                'jsonKey': deckJsonKey,
                'player1Name': player1,
                'player2Name': player2,
              },
            );
          },
        );
      },
    ).whenComplete(() {
      player1Controller.dispose();
      player2Controller.dispose();
    });
  }

  void _showComputerLevelSheet(
    BuildContext context,
    String? deckJson,
    String? deckJsonKey,
  ) {
    final parentContext = context;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _ComputerLevelSheet(
          onSelect: (levelId) {
            SoundService.instance.playTap();
            Navigator.pushNamed(
              parentContext,
              AppRoutes.game,
              arguments: {
                'gameMode': 'computer',
                'deckJson': deckJson,
                'jsonKey': deckJsonKey,
                'computerLevel': levelId,
              },
            );
          },
        );
      },
    );
  }
}

class _GameModeCarouselItem {
  const _GameModeCarouselItem({
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.assetPath,
    required this.onStart,
  });

  final String title;
  final String subtitle;
  final Color accentColor;
  final String assetPath;
  final VoidCallback onStart;
}

class _ComputerLevelSheet extends StatelessWidget {
  const _ComputerLevelSheet({required this.onSelect});

  final void Function(String levelId) onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = LocalizationService.instance;
    final levels = [
      _ComputerLevelOption(
        id: 'rookie',
        title: l10n.t('menu.computer.level.rookie.title'),
        subTitle: l10n.t('menu.computer.level.rookie.subtitle'),
        accent: const Color(0xFF66BB6A),
        badgeAsset: 'assets/menu/computer_levels/rookie.png',
      ),
      _ComputerLevelOption(
        id: 'ace',
        title: l10n.t('menu.computer.level.ace.title'),
        subTitle: l10n.t('menu.computer.level.ace.subtitle'),
        accent: const Color(0xFFFFA726),
        badgeAsset: 'assets/menu/computer_levels/ace.png',
      ),
      _ComputerLevelOption(
        id: 'legend',
        title: l10n.t('menu.computer.level.legend.title'),
        subTitle: l10n.t('menu.computer.level.legend.subtitle'),
        accent: const Color(0xFFEC407A),
        badgeAsset: 'assets/menu/computer_levels/legend.png',
      ),
    ];

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFB3E5FC),
              Color(0xFFE1BEE7),
              Color(0xFFFFCDD2),
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final hasHeight = constraints.hasBoundedHeight &&
                  constraints.maxHeight.isFinite;
              final minHeight = hasHeight ? constraints.maxHeight : 0.0;
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: minHeight,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 56,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: Text(
                          l10n.t('menu.computer.sheet.title'),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: Text(
                          l10n.t('menu.computer.sheet.subtitle'),
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ...levels.map(
                        (level) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _ComputerLevelCard(
                            option: level,
                            onSelect: () => onSelect(level.id),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Text(l10n.t('menu.computer.sheet.cancel')),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ComputerLevelOption {
  const _ComputerLevelOption({
    required this.id,
    required this.title,
    required this.subTitle,
    required this.accent,
    required this.badgeAsset,
  });

  final String id;
  final String title;
  final String subTitle;
  final Color accent;
  final String badgeAsset;
}

class _ComputerLevelCard extends StatelessWidget {
  const _ComputerLevelCard({
    required this.option,
    required this.onSelect,
  });

  final _ComputerLevelOption option;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: option.accent, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: option.accent.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  option.badgeAsset,
                  height: 72,
                  width: 72,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 72,
                      width: 72,
                      color: option.accent.withValues(alpha: 0.15),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.smart_toy,
                        size: 38,
                        color: option.accent,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _darkenColor(option.accent),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    option.subTitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.play_arrow_rounded, color: option.accent, size: 36),
          ],
        ),
      ),
    );
  }
}

class _HotSeatSetupSheet extends StatefulWidget {
  const _HotSeatSetupSheet({
    required this.parentContext,
    required this.player1Controller,
    required this.player2Controller,
    required this.onStart,
  });

  final BuildContext parentContext;
  final TextEditingController player1Controller;
  final TextEditingController player2Controller;
  final void Function(String player1Name, String player2Name) onStart;

  @override
  State<_HotSeatSetupSheet> createState() => _HotSeatSetupSheetState();
}

class _HotSeatSetupSheetState extends State<_HotSeatSetupSheet> {
  bool get _canStart =>
      widget.player1Controller.text.trim().isNotEmpty &&
      widget.player2Controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.player1Controller.addListener(_onNameChanged);
    widget.player2Controller.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    widget.player1Controller.removeListener(_onNameChanged);
    widget.player2Controller.removeListener(_onNameChanged);
    super.dispose();
  }

  void _onNameChanged() {
    setState(() {});
  }

  void _handleStart(BuildContext sheetContext) {
    final player1 = widget.player1Controller.text.trim();
    final player2 = widget.player2Controller.text.trim();
    final l10n = LocalizationService.instance;

    if (player1.isEmpty || player2.isEmpty) {
      ScaffoldMessenger.of(widget.parentContext).showSnackBar(
        SnackBar(
          content: Text(l10n.t('menu.hotseat.sheet.snackbar')),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    FocusScope.of(sheetContext).unfocus();
    Navigator.of(sheetContext).pop();
    widget.onStart(player1, player2);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFE082),
              Color(0xFFFFB4D6),
              Color(0xFFB39DFF),
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                LocalizationService.instance.t('menu.hotseat.sheet.title'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                LocalizationService.instance.t('menu.hotseat.sheet.subtitle'),
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: _PlayerNameCard(
                      title: LocalizationService.instance
                          .t('menu.hotseat.player1'),
                      controller: widget.player1Controller,
                      accentColor: const Color(0xFF4CAF50),
                      placeholderAsset:
                          'assets/menu/avatars/player1_placeholder.png',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _PlayerNameCard(
                      title: LocalizationService.instance
                          .t('menu.hotseat.player2'),
                      controller: widget.player2Controller,
                      accentColor: const Color(0xFFEF6C00),
                      placeholderAsset:
                          'assets/menu/avatars/player2_placeholder.png',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: _canStart ? () => _handleStart(context) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(LocalizationService.instance
                      .t('menu.hotseat.sheet.start')),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(LocalizationService.instance
                    .t('menu.hotseat.sheet.maybeLater')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerNameCard extends StatelessWidget {
  const _PlayerNameCard({
    required this.title,
    required this.controller,
    required this.accentColor,
    required this.placeholderAsset,
  });

  final String title;
  final TextEditingController controller;
  final Color accentColor;
  final String placeholderAsset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accentColor, width: 5),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                placeholderAsset,
                height: 125,
                width: 125,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 125,
                    width: 125,
                    color: accentColor.withValues(alpha: 0.15),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.person,
                      size: 60,
                      color: accentColor,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _darkenColor(accentColor),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: LocalizationService.instance.t('menu.hotseat.nameHint'),
              hintStyle: TextStyle(color: Colors.grey.shade500),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    BorderSide(color: accentColor.withValues(alpha: 0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: accentColor, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _darkenColor(Color color, [double amount = 0.2]) {
  final hsl = HSLColor.fromColor(color);
  final adjusted = hsl.withLightness(
    (hsl.lightness - amount).clamp(0.0, 1.0),
  );
  return adjusted.toColor();
}

class _SpacingRule {
  _SpacingRule(this.minPct, this.maxPct, this.idealPct);

  final double minPct;
  final double maxPct;
  final double idealPct;
  double minVal = 0;
  double maxVal = 0;
  double value = 0;
}

class _GameModeCard extends StatelessWidget {
  const _GameModeCard({required this.item});

  final _GameModeCarouselItem item;

  double _measureTextHeight({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required int maxLines,
  }) {
    if (text.isEmpty || maxWidth <= 0) return 0;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth, minWidth: 0);
    return painter.size.height;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = LocalizationService.instance;
    const titleStyle = TextStyle(
      fontSize: 27,
      height: 1.0,
      fontWeight: FontWeight.bold,
      color: Colors.black87,
    );
    final subtitleStyle = TextStyle(
      fontSize: 16,
      height: 1.0,
      color: Colors.grey.shade700,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Semantics(
        button: true,
        label: l10n.format(
          'menu.card.semantics',
          {'title': item.title, 'subtitle': item.subtitle},
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: item.onStart,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final hasFiniteHeight = constraints.maxHeight.isFinite;
                final hasFiniteWidth = constraints.maxWidth.isFinite;
                final cardHeight =
                    hasFiniteHeight ? constraints.maxHeight : 380.0;
                final cardWidth = hasFiniteWidth ? constraints.maxWidth : 280.0;
                final textWidth = (cardWidth - 40).clamp(120.0, cardWidth);

                final titleHeight = _measureTextHeight(
                  text: item.title,
                  style: titleStyle,
                  maxWidth: textWidth,
                  maxLines: 2,
                );
                final subtitleHeight = _measureTextHeight(
                  text: item.subtitle,
                  style: subtitleStyle,
                  maxWidth: textWidth,
                  maxLines: 3,
                );

                const baseButtonHeight = 48.0;
                const minSpacingAllowance = 36.0;

                final maxAvailableForImage = cardHeight -
                    (titleHeight +
                        subtitleHeight +
                        baseButtonHeight +
                        minSpacingAllowance);

                double imageHeight;
                if (maxAvailableForImage <= 0) {
                  imageHeight = (cardHeight -
                          (titleHeight + subtitleHeight + baseButtonHeight))
                      .clamp(0.0, cardHeight);
                } else {
                  final desiredImageHeight = cardHeight * 0.45;
                  final lowerBound = (maxAvailableForImage < 100.0
                          ? maxAvailableForImage
                          : 100.0)
                      .clamp(0.0, cardHeight)
                      .toDouble();
                  final upperBound = [
                    maxAvailableForImage,
                    cardHeight * 0.6,
                  ].reduce(
                      (value, element) => value < element ? value : element);
                  final safeUpperBound = upperBound < lowerBound
                      ? lowerBound
                      : upperBound.clamp(lowerBound, cardHeight).toDouble();
                  imageHeight = desiredImageHeight
                      .clamp(lowerBound, safeUpperBound)
                      .toDouble();
                }

                double spacingBudget = cardHeight -
                    (imageHeight +
                        titleHeight +
                        subtitleHeight +
                        baseButtonHeight);
                const double spacingSafetyMargin = 36.0;
                spacingBudget =
                    math.max(spacingBudget - spacingSafetyMargin, 0.0);
                if (spacingBudget < 0) {
                  spacingBudget = 0;
                }

                double topPadding = 0;
                double imageTextSpacing = 0;
                double titleSubtitleSpacing = 0;
                double subtitleButtonSpacing = 0;
                double bottomPadding = 0;

                const double minTopPaddingPx = 12.0;
                const double minImageTextSpacingPx = 12.0;
                const double minTitleSubtitleSpacingPx = 6.0;
                const double minSubtitleButtonSpacingPx = 10.0;
                const double minBottomPaddingPx = 4.0;

                if (spacingBudget > 0) {
                  final rules = [
                    _SpacingRule(0.01, 0.05, 0.03), // top padding
                    _SpacingRule(0.30, 0.50, 0.45), // image -> title
                    _SpacingRule(0.05, 0.10, 0.075), // title -> subtitle
                    _SpacingRule(0.10, 0.30, 0.20), // subtitle -> button
                    _SpacingRule(0.01, 0.05, 0.03), // button -> bottom
                  ];

                  double minSum = 0;
                  for (final rule in rules) {
                    rule.minVal = spacingBudget * rule.minPct;
                    rule.maxVal = spacingBudget * rule.maxPct;
                    rule.value = rule.minVal;
                    minSum += rule.minVal;
                  }

                  double leftover = (spacingBudget - minSum).clamp(
                    0.0,
                    double.infinity,
                  );

                  double ratioSum = rules.fold<double>(
                    0,
                    (sum, rule) => (rule.maxVal - rule.minVal) > 0
                        ? sum + rule.idealPct
                        : sum,
                  );

                  if (leftover > 0 && ratioSum > 0) {
                    for (final rule in rules) {
                      final capacity = rule.maxVal - rule.minVal;
                      if (capacity <= 0) continue;
                      final share = leftover * (rule.idealPct / ratioSum);
                      final addition = share.clamp(0.0, capacity);
                      rule.value += addition;
                    }
                  }

                  double used = rules.fold<double>(
                    0,
                    (sum, rule) => sum + rule.value,
                  );
                  double remainder = (spacingBudget - used).clamp(
                    0.0,
                    double.infinity,
                  );
                  int guard = 0;
                  while (remainder > 0.1 && guard < 6) {
                    final expandable = rules
                        .where((rule) => rule.value < rule.maxVal - 0.1)
                        .toList();
                    if (expandable.isEmpty) break;
                    final perRule = remainder / expandable.length;
                    for (final rule in expandable) {
                      final capacity = rule.maxVal - rule.value;
                      final delta = perRule.clamp(0.0, capacity);
                      rule.value += delta;
                      remainder -= delta;
                      if (remainder <= 0.1) break;
                    }
                    guard++;
                  }

                  topPadding = rules[0].value;
                  imageTextSpacing = rules[1].value;
                  titleSubtitleSpacing = rules[2].value;
                  subtitleButtonSpacing = rules[3].value;
                  bottomPadding = rules[4].value;
                }

                void ensureMinimumSpacing(
                  double minValue,
                  double Function() getter,
                  void Function(double) setter,
                  List<double Function()> donorGetters,
                  List<void Function(double)> donorSetters,
                  List<double> donorMins,
                ) {
                  double current = getter();
                  if (current >= minValue) return;
                  double deficit = minValue - current;
                  for (var i = 0; i < donorGetters.length && deficit > 0; i++) {
                    final donorValue = donorGetters[i]();
                    final available = donorValue - donorMins[i];
                    if (available <= 0) continue;
                    final take = math.min(available, deficit);
                    donorSetters[i](donorValue - take);
                    deficit -= take;
                  }
                  setter(minValue - deficit);
                }

                ensureMinimumSpacing(
                  minTopPaddingPx,
                  () => topPadding,
                  (value) => topPadding = value,
                  [
                    () => subtitleButtonSpacing,
                    () => imageTextSpacing,
                    () => titleSubtitleSpacing,
                    () => bottomPadding,
                  ],
                  [
                    (value) => subtitleButtonSpacing = value,
                    (value) => imageTextSpacing = value,
                    (value) => titleSubtitleSpacing = value,
                    (value) => bottomPadding = value,
                  ],
                  [
                    minSubtitleButtonSpacingPx,
                    minImageTextSpacingPx,
                    minTitleSubtitleSpacingPx,
                    minBottomPaddingPx,
                  ],
                );

                topPadding = math.max(topPadding, minTopPaddingPx);
                imageTextSpacing =
                    math.max(imageTextSpacing, minImageTextSpacingPx);
                titleSubtitleSpacing =
                    math.max(titleSubtitleSpacing, minTitleSubtitleSpacingPx);
                subtitleButtonSpacing = math.max(
                  subtitleButtonSpacing,
                  minSubtitleButtonSpacingPx,
                );
                bottomPadding = math.max(bottomPadding, minBottomPaddingPx);

                const double buttonHeight = baseButtonHeight;
                final double minImageHeightPx =
                    math.max(cardHeight * 0.22, 96.0);

                final double totalSpacingInitial = topPadding +
                    imageTextSpacing +
                    titleSubtitleSpacing +
                    subtitleButtonSpacing +
                    bottomPadding;
                final double totalFixedHeight =
                    imageHeight + titleHeight + subtitleHeight + buttonHeight;

                void reduceOverflow(double amount) {
                  if (amount <= 0) return;

                  void reduceSpacing(
                    double minValue,
                    double Function() getter,
                    void Function(double) setter,
                  ) {
                    if (amount <= 0) return;
                    final current = getter();
                    final reducible = current - minValue;
                    if (reducible <= 0) return;
                    final delta = math.min(reducible, amount);
                    setter(current - delta);
                    amount -= delta;
                  }

                  reduceSpacing(
                    minSubtitleButtonSpacingPx,
                    () => subtitleButtonSpacing,
                    (value) => subtitleButtonSpacing = value,
                  );
                  reduceSpacing(
                    minTitleSubtitleSpacingPx,
                    () => titleSubtitleSpacing,
                    (value) => titleSubtitleSpacing = value,
                  );
                  reduceSpacing(
                    minImageTextSpacingPx,
                    () => imageTextSpacing,
                    (value) => imageTextSpacing = value,
                  );
                  reduceSpacing(
                    minBottomPaddingPx,
                    () => bottomPadding,
                    (value) => bottomPadding = value,
                  );
                  reduceSpacing(
                    minTopPaddingPx,
                    () => topPadding,
                    (value) => topPadding = value,
                  );

                  if (amount > 0) {
                    final reducibleImage = imageHeight - minImageHeightPx;
                    if (reducibleImage > 0) {
                      final delta = math.min(reducibleImage, amount);
                      imageHeight -= delta;
                      amount -= delta;
                    }
                  }
                }

                final double initialOverflow =
                    (totalFixedHeight + totalSpacingInitial) - cardHeight;
                if (initialOverflow > 0) {
                  reduceOverflow(initialOverflow + 8);
                }

                final double recomputedTotal = imageHeight +
                    titleHeight +
                    subtitleHeight +
                    buttonHeight +
                    topPadding +
                    imageTextSpacing +
                    titleSubtitleSpacing +
                    subtitleButtonSpacing +
                    bottomPadding;
                final double secondOverflow = recomputedTotal - cardHeight;
                if (secondOverflow > 0) {
                  reduceOverflow(secondOverflow + 4);
                }

                const double contentSafetyMargin = 18.0;
                final double spacingAvailableBuffer = math.max(
                  cardHeight -
                      (imageHeight +
                          titleHeight +
                          subtitleHeight +
                          buttonHeight) -
                      contentSafetyMargin,
                  0,
                );
                final double finalSpacing = topPadding +
                    imageTextSpacing +
                    titleSubtitleSpacing +
                    subtitleButtonSpacing +
                    bottomPadding;
                if (finalSpacing > spacingAvailableBuffer && finalSpacing > 0) {
                  final double ratio = spacingAvailableBuffer / finalSpacing;
                  topPadding *= ratio;
                  imageTextSpacing *= ratio;
                  titleSubtitleSpacing *= ratio;
                  subtitleButtonSpacing *= ratio;
                  bottomPadding *= ratio;
                }

                assert(() {
                  debugLog(
                    '[MenuCard] cardHeight=$cardHeight, imageHeight=$imageHeight, '
                    'titleHeight=$titleHeight, subtitleHeight=$subtitleHeight, '
                    'buttonHeight=$baseButtonHeight, spacingBudget=$spacingBudget, '
                    'top=$topPadding, imageText=$imageTextSpacing, '
                    'titleSubtitle=$titleSubtitleSpacing, subtitleButton=$subtitleButtonSpacing, '
                    'bottom=$bottomPadding, total=${imageHeight + titleHeight + subtitleHeight + buttonHeight + topPadding + imageTextSpacing + titleSubtitleSpacing + subtitleButtonSpacing + bottomPadding}',
                  );
                  return true;
                }());

                return Column(
                  children: [
                    SizedBox(height: topPadding),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        height: imageHeight,
                        child: Image.asset(
                          item.assetPath,
                          fit: BoxFit.contain,
                          errorBuilder: (context, _, __) {
                            return Icon(
                              Icons.image_not_supported_outlined,
                              size: 140,
                              color: Colors.grey.shade400,
                            );
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: imageTextSpacing),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.title,
                            style: titleStyle,
                            textAlign: TextAlign.center,
                            softWrap: true,
                            maxLines: 2,
                          ),
                          SizedBox(height: titleSubtitleSpacing),
                          Text(
                            item.subtitle,
                            style: subtitleStyle,
                            textAlign: TextAlign.center,
                            softWrap: true,
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: subtitleButtonSpacing),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SizedBox(
                        width: double.infinity,
                        height: buttonHeight,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: item.accentColor,
                            foregroundColor: Colors.white,
                            minimumSize: Size(double.infinity, buttonHeight),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: item.onStart,
                          child: Text(
                            l10n.t('action.letsGo'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: bottomPadding),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
