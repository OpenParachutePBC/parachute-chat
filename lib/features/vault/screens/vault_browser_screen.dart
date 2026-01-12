import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/features/chat/models/vault_entry.dart';
import 'package:parachute_chat/features/vault/providers/vault_browser_providers.dart';
import 'package:parachute_chat/features/vault/screens/vault_file_editor_screen.dart';
import 'package:parachute_chat/features/settings/screens/settings_screen.dart';

/// Main screen for browsing the Parachute vault
///
/// Shows files and folders from the vault using the Base server API.
/// Supports navigation, viewing text files, and editing markdown.
class VaultBrowserScreen extends ConsumerWidget {
  const VaultBrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final folderName = ref.watch(vaultFolderNameProvider);
    final displayPath = ref.watch(vaultDisplayPathProvider);
    final isAtRoot = ref.watch(isAtVaultRootProvider);
    final contentsAsync = ref.watch(vaultContentsProvider);
    final canGoBack = ref.watch(vaultNavigationHistoryProvider.select((h) => h.length > 1));

    return Scaffold(
      backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
      appBar: AppBar(
        backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
        surfaceTintColor: Colors.transparent,
        leading: canGoBack
            ? IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
                onPressed: () => ref.read(navigateBackProvider)(),
                tooltip: 'Back',
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              folderName,
              style: TextStyle(
                fontSize: TypographyTokens.titleLarge,
                fontWeight: FontWeight.w600,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            if (!isAtRoot)
              Text(
                displayPath,
                style: TextStyle(
                  fontSize: TypographyTokens.labelSmall,
                  color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                ),
              ),
          ],
        ),
        actions: [
          // Refresh button
          IconButton(
            onPressed: () => ref.read(refreshVaultProvider)(),
            icon: Icon(
              Icons.refresh,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
            tooltip: 'Refresh',
          ),
          // Home button (go to root)
          if (!isAtRoot)
            IconButton(
              onPressed: () => ref.read(navigateToVaultRootProvider)(),
              icon: Icon(
                Icons.home_outlined,
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
              tooltip: 'Go to vault root',
            ),
          // Settings button
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsScreen()),
            ),
            icon: Icon(
              Icons.settings_outlined,
              color: isDark ? BrandColors.driftwood : BrandColors.charcoal,
            ),
            tooltip: 'Settings',
          ),
          const SizedBox(width: Spacing.xs),
        ],
      ),
      body: contentsAsync.when(
        data: (entries) => _buildFileList(context, ref, entries, isDark),
        loading: () => _buildLoading(isDark),
        error: (e, _) => _buildError(context, ref, isDark, e.toString()),
      ),
    );
  }

  Widget _buildFileList(
    BuildContext context,
    WidgetRef ref,
    List<VaultEntry> entries,
    bool isDark,
  ) {
    if (entries.isEmpty) {
      return _buildEmptyState(isDark);
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(refreshVaultProvider)(),
      color: BrandColors.forest,
      child: ListView.builder(
        padding: const EdgeInsets.all(Spacing.md),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return _VaultEntryTile(
            entry: entry,
            isDark: isDark,
            onTap: () => _handleEntryTap(context, ref, entry),
          );
        },
      ),
    );
  }

  void _handleEntryTap(BuildContext context, WidgetRef ref, VaultEntry entry) {
    if (entry.isDirectory) {
      // Navigate into the folder
      ref.read(navigateToFolderProvider)(entry.relativePath);
    } else {
      // Open file viewer/editor
      final service = ref.read(vaultBrowserServiceProvider);
      if (service.isTextFile(entry.name)) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VaultFileEditorScreen(
              relativePath: entry.relativePath,
              fileName: entry.name,
            ),
          ),
        );
      } else {
        // Show a message that the file type isn't supported for viewing
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot open ${entry.name} - unsupported file type'),
            backgroundColor: BrandColors.driftwood,
          ),
        );
      }
    }
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(Spacing.xl),
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightSurfaceElevated
                    : BrandColors.stone.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.folder_open_outlined,
                size: 48,
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Text(
              'Empty folder',
              style: TextStyle(
                fontSize: TypographyTokens.headlineSmall,
                fontWeight: FontWeight.w600,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'This folder has no files or subfolders.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TypographyTokens.bodyMedium,
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading(bool isDark) {
    return Center(
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, bool isDark, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'Couldn\'t load folder',
              style: TextStyle(
                fontSize: TypographyTokens.titleMedium,
                fontWeight: FontWeight.w600,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Check that the server is running',
              style: TextStyle(
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            FilledButton.icon(
              onPressed: () => ref.read(refreshVaultProvider)(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: isDark ? BrandColors.nightForest : BrandColors.forest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single file or folder tile in the vault browser
class _VaultEntryTile extends StatelessWidget {
  final VaultEntry entry;
  final bool isDark;
  final VoidCallback onTap;

  const _VaultEntryTile({
    required this.entry,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Material(
        color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
        borderRadius: BorderRadius.circular(Radii.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.md),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(
              children: [
                // Icon
                _buildIcon(),
                const SizedBox(width: Spacing.md),

                // Name and metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name with badges
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              entry.name,
                              style: TextStyle(
                                fontSize: TypographyTokens.bodyMedium,
                                fontWeight: FontWeight.w500,
                                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (entry.hasClaudeMd) ...[
                            const SizedBox(width: Spacing.xs),
                            _buildBadge('CLAUDE.md', BrandColors.turquoise),
                          ],
                          if (entry.isGitRepo) ...[
                            const SizedBox(width: Spacing.xs),
                            _buildBadge('git', BrandColors.forest),
                          ],
                        ],
                      ),

                      // Metadata row
                      if (entry.lastModified != null || entry.size != null)
                        Padding(
                          padding: const EdgeInsets.only(top: Spacing.xs),
                          child: Row(
                            children: [
                              if (entry.lastModified != null)
                                Text(
                                  _formatDate(entry.lastModified!),
                                  style: TextStyle(
                                    fontSize: TypographyTokens.labelSmall,
                                    color: isDark
                                        ? BrandColors.nightTextSecondary
                                        : BrandColors.driftwood,
                                  ),
                                ),
                              if (entry.lastModified != null && entry.size != null)
                                Text(
                                  ' • ',
                                  style: TextStyle(
                                    fontSize: TypographyTokens.labelSmall,
                                    color: isDark
                                        ? BrandColors.nightTextSecondary
                                        : BrandColors.driftwood,
                                  ),
                                ),
                              if (entry.size != null)
                                Text(
                                  _formatSize(entry.size!),
                                  style: TextStyle(
                                    fontSize: TypographyTokens.labelSmall,
                                    color: isDark
                                        ? BrandColors.nightTextSecondary
                                        : BrandColors.driftwood,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                // Chevron for directories
                if (entry.isDirectory)
                  Icon(
                    Icons.chevron_right,
                    color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    IconData iconData;
    Color iconColor;

    if (entry.isDirectory) {
      iconData = Icons.folder;
      iconColor = isDark ? BrandColors.nightTurquoise : BrandColors.turquoise;
    } else {
      // File icon based on extension
      final ext = entry.name.toLowerCase().split('.').last;
      switch (ext) {
        case 'md':
        case 'markdown':
          iconData = Icons.description;
          iconColor = isDark ? BrandColors.nightForest : BrandColors.forest;
          break;
        case 'json':
        case 'yaml':
        case 'yml':
        case 'toml':
          iconData = Icons.data_object;
          iconColor = isDark ? BrandColors.nightTurquoise : BrandColors.turquoise;
          break;
        case 'dart':
        case 'py':
        case 'js':
        case 'ts':
        case 'jsx':
        case 'tsx':
          iconData = Icons.code;
          iconColor = isDark ? BrandColors.nightTurquoise : BrandColors.turquoise;
          break;
        case 'png':
        case 'jpg':
        case 'jpeg':
        case 'gif':
        case 'webp':
        case 'svg':
          iconData = Icons.image;
          iconColor = isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood;
          break;
        case 'mp3':
        case 'wav':
        case 'm4a':
        case 'ogg':
          iconData = Icons.audio_file;
          iconColor = isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood;
          break;
        case 'pdf':
          iconData = Icons.picture_as_pdf;
          iconColor = BrandColors.error;
          break;
        default:
          iconData = Icons.insert_drive_file;
          iconColor = isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood;
      }
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Icon(
        iconData,
        color: iconColor,
        size: 22,
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.xs + 2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: Radii.badge,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: TypographyTokens.labelSmall - 1,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final fileDate = DateTime(date.year, date.month, date.day);

    if (fileDate == today) {
      return 'Today ${_formatTime(date)}';
    } else if (fileDate == yesterday) {
      return 'Yesterday ${_formatTime(date)}';
    } else if (now.difference(date).inDays < 7) {
      return '${_weekdayName(date.weekday)} ${_formatTime(date)}';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }

  String _formatTime(DateTime date) {
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final amPm = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${date.minute.toString().padLeft(2, '0')} $amPm';
  }

  String _weekdayName(int weekday) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[weekday - 1];
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
