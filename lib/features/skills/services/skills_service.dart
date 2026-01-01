import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/skill.dart';

/// Service for managing Agent Skills
///
/// Communicates with parachute-base server to:
/// - List available skills
/// - Get skill details
/// - Create new skills
/// - Delete skills
class SkillsService {
  final String baseUrl;
  final http.Client _client;

  static const Duration requestTimeout = Duration(seconds: 30);

  SkillsService({required this.baseUrl}) : _client = http.Client();

  /// List all available skills
  Future<List<Skill>> listSkills() async {
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/skills'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to list skills: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final skillsList = data['skills'] as List<dynamic>? ?? [];
      return skillsList
          .map((json) => Skill.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[SkillsService] Error listing skills: $e');
      rethrow;
    }
  }

  /// Get full skill content by name/directory
  Future<Skill?> getSkill(String name) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/skills/$name'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(requestTimeout);

      if (response.statusCode == 404) {
        return null;
      }

      if (response.statusCode != 200) {
        throw Exception('Failed to get skill: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Skill.fromJson(data);
    } catch (e) {
      debugPrint('[SkillsService] Error getting skill $name: $e');
      rethrow;
    }
  }

  /// Create a new skill
  Future<Skill> createSkill(CreateSkillInput input) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/skills'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(input.toJson()),
          )
          .timeout(requestTimeout);

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
        throw Exception('Failed to create skill: $error');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Skill.fromJson(data['skill'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[SkillsService] Error creating skill: $e');
      rethrow;
    }
  }

  /// Delete a skill
  Future<bool> deleteSkill(String name) async {
    try {
      final response = await _client
          .delete(
            Uri.parse('$baseUrl/api/skills/$name'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(requestTimeout);

      if (response.statusCode == 404) {
        return false;
      }

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
        throw Exception('Failed to delete skill: $error');
      }

      return true;
    } catch (e) {
      debugPrint('[SkillsService] Error deleting skill $name: $e');
      rethrow;
    }
  }

  void dispose() {
    _client.close();
  }
}
