import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/providers/feature_flags_provider.dart';
import '../models/skill.dart';
import '../services/skills_service.dart';

// ============================================================
// Service Provider
// ============================================================

/// Provider for SkillsService
///
/// Creates a new SkillsService instance with the configured server URL.
final skillsServiceProvider = Provider<SkillsService>((ref) {
  final urlAsync = ref.watch(aiServerUrlProvider);
  final baseUrl = urlAsync.valueOrNull ?? 'http://localhost:3333';

  final service = SkillsService(baseUrl: baseUrl);

  ref.onDispose(() {
    service.dispose();
  });

  return service;
});

// ============================================================
// Data Providers
// ============================================================

/// Provider for fetching all skills
///
/// Returns the list of available agent skills.
final skillsProvider = FutureProvider<List<Skill>>((ref) async {
  final service = ref.watch(skillsServiceProvider);

  try {
    final skills = await service.listSkills();
    debugPrint('[SkillsProviders] Loaded ${skills.length} skills');
    return skills;
  } catch (e) {
    debugPrint('[SkillsProviders] Error loading skills: $e');
    rethrow;
  }
});

/// Provider for getting a specific skill with full content
final skillDetailProvider =
    FutureProvider.family<Skill?, String>((ref, name) async {
  final service = ref.watch(skillsServiceProvider);

  try {
    return await service.getSkill(name);
  } catch (e) {
    debugPrint('[SkillsProviders] Error getting skill $name: $e');
    rethrow;
  }
});

// ============================================================
// Mutation Helpers
// ============================================================

/// Create a new skill and refresh the list
Future<Skill> createSkill(
  WidgetRef ref, {
  required String name,
  String? description,
  String? content,
  List<String>? allowedTools,
}) async {
  final service = ref.read(skillsServiceProvider);
  final result = await service.createSkill(CreateSkillInput(
    name: name,
    description: description,
    content: content,
    allowedTools: allowedTools,
  ));
  ref.invalidate(skillsProvider);
  return result;
}

/// Delete a skill and refresh the list
Future<bool> deleteSkill(WidgetRef ref, String name) async {
  final service = ref.read(skillsServiceProvider);
  final result = await service.deleteSkill(name);
  ref.invalidate(skillsProvider);
  return result;
}

/// Refresh the skills list
void refreshSkills(WidgetRef ref) {
  ref.invalidate(skillsProvider);
}
