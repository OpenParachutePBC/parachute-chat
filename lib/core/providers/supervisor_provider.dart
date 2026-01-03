import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/supervisor_service.dart';
import 'feature_flags_provider.dart';

/// Provider for the SupervisorService (uses default URL until async loads)
final supervisorServiceProvider = Provider<SupervisorService>((ref) {
  final serverUrlAsync = ref.watch(aiServerUrlProvider);
  final serverUrl = serverUrlAsync.valueOrNull ?? 'http://localhost:3333';
  final supervisorUrl = SupervisorService.supervisorUrlFromServerUrl(serverUrl);
  return SupervisorService(supervisorUrl: supervisorUrl);
});

/// Provider that checks if supervisor is available
final supervisorAvailableProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(supervisorServiceProvider);
  return await service.isAvailable();
});

/// Provider for supervisor status (with auto-refresh)
final supervisorStatusProvider = FutureProvider.autoDispose<SupervisorStatus>((ref) async {
  final service = ref.watch(supervisorServiceProvider);
  return await service.getStatus();
});

/// Notifier for supervisor actions
class SupervisorActionsNotifier extends StateNotifier<AsyncValue<SupervisorActionResult?>> {
  final SupervisorService _service;
  final Ref _ref;

  SupervisorActionsNotifier(this._service, this._ref) : super(const AsyncData(null));

  Future<void> startServer() async {
    state = const AsyncLoading();
    final result = await _service.startServer();
    state = AsyncData(result);
    _ref.invalidate(supervisorStatusProvider);
  }

  Future<void> stopServer() async {
    state = const AsyncLoading();
    final result = await _service.stopServer();
    state = AsyncData(result);
    _ref.invalidate(supervisorStatusProvider);
  }

  Future<void> restartServer() async {
    state = const AsyncLoading();
    final result = await _service.restartServer();
    state = AsyncData(result);
    _ref.invalidate(supervisorStatusProvider);
  }
}

/// Provider for supervisor actions
final supervisorActionsProvider =
    StateNotifierProvider<SupervisorActionsNotifier, AsyncValue<SupervisorActionResult?>>((ref) {
  final service = ref.watch(supervisorServiceProvider);
  return SupervisorActionsNotifier(service, ref);
});
