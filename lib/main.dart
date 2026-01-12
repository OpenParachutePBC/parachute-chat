import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/design_tokens.dart';
import 'core/services/logging_service.dart';
import 'core/services/transcription_service.dart';
import 'features/onboarding/screens/onboarding_flow.dart';
import 'features/chat/screens/agent_hub_screen.dart';
import 'features/vault/screens/vault_browser_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logging (file logging only)
  await logger.initialize();

  // Global error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    logger.captureException(
      details.exception,
      stackTrace: details.stack,
      tag: 'FlutterError',
      extras: {
        'library': details.library ?? 'unknown',
        'context': details.context?.toString() ?? 'unknown',
      },
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    logger.captureException(error, stackTrace: stack, tag: 'PlatformDispatcher');
    return true;
  };

  // Initialize transcription service (Parakeet) in background
  // Don't await - let it initialize while app loads
  _initializeTranscription();

  runApp(const ProviderScope(child: ParachuteChatApp()));
}

/// Initialize transcription model in background for faster voice input
void _initializeTranscription() async {
  try {
    logger.info('TranscriptionInit', 'Starting transcription model initialization...');
    final transcriptionService = TranscriptionService();

    await transcriptionService.initialize(
      onProgress: (progress) {
        debugPrint('[Main] Transcription init progress: ${(progress * 100).toInt()}%');
      },
      onStatus: (status) {
        debugPrint('[Main] Transcription init status: $status');
      },
    );

    logger.info('TranscriptionInit', 'Transcription model initialized successfully');
    debugPrint('[Main] ✅ Transcription model ready');
  } catch (e, stackTrace) {
    logger.captureException(e, stackTrace: stackTrace, tag: 'TranscriptionInit');
    debugPrint('[Main] ⚠️ Failed to initialize transcription: $e');
  }
}

class ParachuteChatApp extends StatelessWidget {
  const ParachuteChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parachute Chat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const MainScreen(),
    );
  }
}

/// Main screen - shows onboarding or chat
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  bool _hasSeenWelcome = true;
  bool _isCheckingWelcome = true;
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _checkWelcomeScreen();
  }

  Future<void> _checkWelcomeScreen() async {
    final hasSeenWelcome = await OnboardingFlow.hasCompletedOnboarding();
    if (mounted) {
      setState(() {
        _hasSeenWelcome = hasSeenWelcome;
        _isCheckingWelcome = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingWelcome) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_hasSeenWelcome) {
      return OnboardingFlow(
        onComplete: () => setState(() => _hasSeenWelcome = true),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Main app with bottom navigation
    return Scaffold(
      body: IndexedStack(
        index: _currentTabIndex,
        children: const [
          AgentHubScreen(),
          VaultBrowserScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) {
          setState(() => _currentTabIndex = index);
        },
        backgroundColor: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
        indicatorColor: isDark
            ? BrandColors.nightTurquoise.withValues(alpha: 0.2)
            : BrandColors.turquoise.withValues(alpha: 0.2),
        destinations: [
          NavigationDestination(
            icon: Icon(
              Icons.chat_bubble_outline,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
            selectedIcon: Icon(
              Icons.chat_bubble,
              color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
            ),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.folder_outlined,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
            selectedIcon: Icon(
              Icons.folder,
              color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
            ),
            label: 'Vault',
          ),
        ],
      ),
    );
  }
}
