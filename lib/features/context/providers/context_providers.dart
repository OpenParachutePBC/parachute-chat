import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/providers/file_system_provider.dart';
import '../services/vault_context_service.dart';

// ============================================================
// Service Provider
// ============================================================

/// Provider for VaultContextService
final vaultContextServiceProvider = Provider<VaultContextService>((ref) {
  final fileSystem = ref.watch(fileSystemServiceProvider);
  return VaultContextService(fileSystem);
});

// ============================================================
// Status Providers
// ============================================================

/// Check if vault context files are initialized
final vaultContextStatusProvider = FutureProvider<VaultContextStatus>((ref) async {
  final service = ref.watch(vaultContextServiceProvider);
  return service.checkStatus();
});

/// Whether vault needs setup (CLAUDE.md missing)
final vaultNeedsSetupProvider = FutureProvider<bool>((ref) async {
  final status = await ref.watch(vaultContextStatusProvider.future);
  return status.needsSetup;
});

// ============================================================
// Content Providers
// ============================================================

/// Load CLAUDE.md content
final claudeMdProvider = FutureProvider<String?>((ref) async {
  final service = ref.watch(vaultContextServiceProvider);
  return service.loadClaudeMd();
});

// ============================================================
// Actions
// ============================================================

/// Initialize default vault context files
final initializeVaultContextProvider = Provider<Future<void> Function()>((ref) {
  final service = ref.watch(vaultContextServiceProvider);
  return () async {
    await service.initializeDefaults();
    // Invalidate status and content providers to refresh
    ref.invalidate(vaultContextStatusProvider);
    ref.invalidate(claudeMdProvider);
  };
});

/// Initialize vault context with optional Claude memories
final initializeVaultWithMemoriesProvider = Provider<Future<void> Function(String?)>((ref) {
  final service = ref.watch(vaultContextServiceProvider);
  return (String? memoriesContext) async {
    await service.initializeWithClaudeMemories(memoriesContext);
    // Invalidate status and content providers to refresh
    ref.invalidate(vaultContextStatusProvider);
    ref.invalidate(claudeMdProvider);
  };
});

/// Save updated CLAUDE.md content
final saveClaudeMdProvider = Provider<Future<bool> Function(String)>((ref) {
  final service = ref.watch(vaultContextServiceProvider);
  return (String content) async {
    final success = await service.saveClaudeMd(content);
    if (success) {
      ref.invalidate(claudeMdProvider);
    }
    return success;
  };
});
