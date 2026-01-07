import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/vault_entry.dart';
import '../providers/chat_providers.dart';

/// A dialog for picking context folders from the vault (multi-select)
///
/// This uses the same directory browsing pattern as [DirectoryPickerDialog]
/// but allows selecting multiple folders with AGENTS.md/CLAUDE.md files.
class ContextFolderPickerDialog extends ConsumerStatefulWidget {
  final List<String> initialSelection;

  const ContextFolderPickerDialog({
    super.key,
    this.initialSelection = const [""],
  });

  @override
  ConsumerState<ContextFolderPickerDialog> createState() =>
      _ContextFolderPickerDialogState();
}

class _ContextFolderPickerDialogState
    extends ConsumerState<ContextFolderPickerDialog> {
  late String _currentPath;
  late Set<String> _selectedPaths;
  final List<String> _pathHistory = [];

  @override
  void initState() {
    super.initState();
    _currentPath = '';
    _selectedPaths = Set.from(widget.initialSelection);
  }

  void _navigateTo(String path) {
    setState(() {
      _pathHistory.add(_currentPath);
      _currentPath = path;
    });
  }

  void _navigateBack() {
    if (_pathHistory.isNotEmpty) {
      setState(() {
        _currentPath = _pathHistory.removeLast();
      });
    }
  }

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
        // Ensure at least root is selected
        if (_selectedPaths.isEmpty) {
          _selectedPaths.add("");
        }
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  bool _isSelected(String path) => _selectedPaths.contains(path);

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(vaultDirectoryProvider(_currentPath));
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      child: Container(
        width: 450,
        height: 550,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with back button and path
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _pathHistory.isNotEmpty ? _navigateBack : null,
                ),
                Expanded(
                  child: Text(
                    _currentPath.isEmpty ? 'Vault Root' : _currentPath,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),

            // Selected count chip
            if (_selectedPaths.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _selectedPaths.map((path) {
                    final label = path.isEmpty ? 'Root' : path.split('/').last;
                    return Chip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: _selectedPaths.length > 1
                          ? () => _toggleSelection(path)
                          : null, // Can't remove if it's the only one
                      backgroundColor: isDark
                          ? Colors.green.withValues(alpha: 0.2)
                          : Colors.green.withValues(alpha: 0.1),
                    );
                  }).toList(),
                ),
              ),
            const Divider(),

            // Current folder selection tile (for selecting current path)
            _CurrentFolderTile(
              path: _currentPath,
              isSelected: _isSelected(_currentPath),
              onToggle: () => _toggleSelection(_currentPath),
            ),
            const Divider(),

            // Directory list
            Expanded(
              child: entriesAsync.when(
                data: (entries) {
                  final directories =
                      entries.where((e) => e.isDirectory).toList();
                  if (directories.isEmpty) {
                    return const Center(
                      child: Text('No subdirectories'),
                    );
                  }
                  return ListView.builder(
                    itemCount: directories.length,
                    itemBuilder: (context, index) {
                      final entry = directories[index];
                      return _ContextFolderTile(
                        entry: entry,
                        isSelected: _isSelected(entry.relativePath),
                        onNavigate: () => _navigateTo(entry.relativePath),
                        onToggle: () => _toggleSelection(entry.relativePath),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      const SizedBox(height: 8),
                      Text('Error: $e'),
                    ],
                  ),
                ),
              ),
            ),

            const Divider(),

            // Done button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_selectedPaths.toList()),
                child: Text('Done (${_selectedPaths.length} selected)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tile for the current folder (allows selecting it)
class _CurrentFolderTile extends StatelessWidget {
  final String path;
  final bool isSelected;
  final VoidCallback onToggle;

  const _CurrentFolderTile({
    required this.path,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListTile(
      leading: Icon(
        isSelected ? Icons.check_circle : Icons.check_circle_outline,
        color: isSelected ? Colors.green : null,
      ),
      title: Text(path.isEmpty ? 'Select vault root' : 'Select this folder'),
      subtitle: path.isNotEmpty
          ? Text(path, style: theme.textTheme.bodySmall)
          : const Text('Root AGENTS.md context',
              style: TextStyle(fontSize: 12)),
      tileColor: isSelected
          ? (isDark
              ? Colors.green.withValues(alpha: 0.1)
              : Colors.green.withValues(alpha: 0.05))
          : null,
      onTap: onToggle,
    );
  }
}

/// Tile for a folder entry with context file indicators
class _ContextFolderTile extends StatelessWidget {
  final VaultEntry entry;
  final bool isSelected;
  final VoidCallback onNavigate;
  final VoidCallback onToggle;

  const _ContextFolderTile({
    required this.entry,
    required this.isSelected,
    required this.onNavigate,
    required this.onToggle,
  });

  String? get _contextFileLabel {
    if (entry.hasAgentsMd && entry.hasClaudeMd) {
      return 'AGENTS.md & CLAUDE.md';
    } else if (entry.hasAgentsMd) {
      return 'AGENTS.md';
    } else if (entry.hasClaudeMd) {
      return 'CLAUDE.md';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListTile(
      leading: Icon(
        entry.hasContextFile
            ? Icons.folder_special
            : entry.isGitRepo
                ? Icons.source
                : Icons.folder,
        color: entry.hasContextFile ? Colors.amber : null,
      ),
      title: Text(entry.name),
      subtitle: _contextFileLabel != null
          ? Text(_contextFileLabel!, style: const TextStyle(fontSize: 12))
          : entry.isGitRepo
              ? const Text('Git repository', style: TextStyle(fontSize: 12))
              : null,
      tileColor: isSelected
          ? (isDark
              ? Colors.green.withValues(alpha: 0.1)
              : Colors.green.withValues(alpha: 0.05))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle selection checkbox
          IconButton(
            icon: Icon(
              isSelected ? Icons.check_circle : Icons.check_circle_outline,
              color: isSelected ? Colors.green : null,
            ),
            tooltip: isSelected ? 'Deselect' : 'Select',
            onPressed: onToggle,
          ),
          // Navigate into folder
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Browse folder',
            onPressed: onNavigate,
          ),
        ],
      ),
      onTap: onNavigate,
    );
  }
}

/// Shows a context folder picker dialog and returns selected paths.
///
/// Returns null if cancelled, or a list of selected folder paths.
/// Empty string ("") means vault root.
Future<List<String>?> showContextFolderPicker(
  BuildContext context, {
  List<String> initialSelection = const [""],
}) {
  return showDialog<List<String>?>(
    context: context,
    builder: (context) =>
        ContextFolderPickerDialog(initialSelection: initialSelection),
  );
}
