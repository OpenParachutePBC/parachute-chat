import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/features/chat/providers/chat_providers.dart';
import 'package:parachute_chat/features/chat/models/vault_entry.dart';
import 'package:parachute_chat/features/vault/services/vault_browser_service.dart';

/// Provider for the VaultBrowserService
final vaultBrowserServiceProvider = Provider<VaultBrowserService>((ref) {
  final chatService = ref.watch(chatServiceProvider);
  return VaultBrowserService(chatService);
});

/// Current path being browsed (relative to vault root)
/// Empty string means vault root
final currentVaultPathProvider = StateProvider<String>((ref) => '');

/// Trigger to force refresh of vault contents
final vaultRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// Contents of the current vault folder
final vaultContentsProvider = FutureProvider<List<VaultEntry>>((ref) async {
  final service = ref.watch(vaultBrowserServiceProvider);
  final path = ref.watch(currentVaultPathProvider);

  // Watch refresh trigger to allow manual refresh
  ref.watch(vaultRefreshTriggerProvider);

  debugPrint('[VaultBrowser] Loading contents for: "$path"');

  try {
    final entries = await service.listDirectory(path);
    debugPrint('[VaultBrowser] Loaded ${entries.length} entries');
    return entries;
  } catch (e) {
    debugPrint('[VaultBrowser] Error loading contents: $e');
    rethrow;
  }
});

/// Whether we're at the vault root
final isAtVaultRootProvider = Provider<bool>((ref) {
  final service = ref.watch(vaultBrowserServiceProvider);
  final path = ref.watch(currentVaultPathProvider);
  return service.isAtRoot(path);
});

/// Display path for the current location
final vaultDisplayPathProvider = Provider<String>((ref) {
  final service = ref.watch(vaultBrowserServiceProvider);
  final path = ref.watch(currentVaultPathProvider);
  return service.getDisplayPath(path);
});

/// Current folder name (for app bar title)
final vaultFolderNameProvider = Provider<String>((ref) {
  final service = ref.watch(vaultBrowserServiceProvider);
  final path = ref.watch(currentVaultPathProvider);
  return service.getFolderName(path);
});

/// Navigation history for back button support
final vaultNavigationHistoryProvider = StateNotifierProvider<VaultNavigationHistoryNotifier, List<String>>((ref) {
  return VaultNavigationHistoryNotifier();
});

class VaultNavigationHistoryNotifier extends StateNotifier<List<String>> {
  VaultNavigationHistoryNotifier() : super(['']);

  void push(String path) {
    state = [...state, path];
  }

  String? pop() {
    if (state.length <= 1) return null;
    final newState = [...state];
    newState.removeLast();
    state = newState;
    return state.last;
  }

  void reset() {
    state = [''];
  }

  bool get canGoBack => state.length > 1;
}

/// Provider to navigate into a folder
final navigateToFolderProvider = Provider<void Function(String)>((ref) {
  return (String relativePath) {
    debugPrint('[VaultBrowser] Navigating to folder: "$relativePath"');
    ref.read(vaultNavigationHistoryProvider.notifier).push(relativePath);
    ref.read(currentVaultPathProvider.notifier).state = relativePath;
  };
});

/// Provider to navigate back to parent folder
final navigateBackProvider = Provider<void Function()>((ref) {
  return () {
    final previousPath = ref.read(vaultNavigationHistoryProvider.notifier).pop();
    if (previousPath != null) {
      debugPrint('[VaultBrowser] Navigating back to: "$previousPath"');
      ref.read(currentVaultPathProvider.notifier).state = previousPath;
    }
  };
});

/// Provider to refresh the current folder contents
final refreshVaultProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    ref.read(vaultRefreshTriggerProvider.notifier).state++;
    await ref.read(vaultContentsProvider.future);
  };
});

/// Provider to navigate to vault root
final navigateToVaultRootProvider = Provider<void Function()>((ref) {
  return () {
    debugPrint('[VaultBrowser] Navigating to vault root');
    ref.read(vaultNavigationHistoryProvider.notifier).reset();
    ref.read(currentVaultPathProvider.notifier).state = '';
  };
});
