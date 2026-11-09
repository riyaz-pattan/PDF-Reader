import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/pdf_provider.dart';
import '../providers/tag_provider.dart';
import '../providers/settings_provider.dart';
import '../models/pdf_document.dart';
import '../widgets/pdf_thumbnail.dart';
import 'pdf_viewer_screen.dart';

enum SortOption { date, name, size }

class LibraryTab extends ConsumerStatefulWidget {
  const LibraryTab({super.key});

  @override
  ConsumerState<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends ConsumerState<LibraryTab> {
  bool _isGridView = false;
  bool _isSearching = false;
  String _searchQuery = '';
  SortOption _sortOption = SortOption.date;
  
  // -1: All, -2: Favorites, otherwise tag ID
  int _selectedFilterId = -1; 

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pdfProvider.notifier).loadPdfs();
      ref.read(tagProvider.notifier).loadTags();
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (bytes > 0) ? (bytes.toString().length - 1) ~/ 3 : 0;
    return '${(bytes / [1, 1024, 1048576, 1073741824, 1099511627776][i]).toStringAsFixed(1)} ${suffixes[i]}';
  }

  void _openPdf(PdfDocument doc) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(document: doc),
      ),
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final settings = ref.watch(settingsProvider);
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(
                    title: Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.brightness_6),
                    title: const Text('Toggle Theme'),
                    trailing: Switch(
                      value: settings.themeMode == ThemeMode.dark || 
                          (settings.themeMode == ThemeMode.system && MediaQuery.of(context).platformBrightness == Brightness.dark),
                      onChanged: (val) {
                        ref.read(settingsProvider.notifier).toggleThemeMode();
                      },
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.lock),
                    title: const Text('App Lock'),
                    trailing: Switch(
                      value: settings.appLockEnabled,
                      onChanged: (val) {
                        ref.read(settingsProvider.notifier).toggleAppLock();
                      },
                    ),
                  ),
                ],
              ),
            );
          }
        );
      }
    );
  }

  void _showTagDialog(PdfDocument doc) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final tagState = ref.watch(tagProvider);
            final docTags = tagState.documentTags[doc.path] ?? [];
            
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tags for ${doc.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: tagState.tags.map((tag) {
                      final isSelected = docTags.contains(tag.id);
                      return FilterChip(
                        label: Text(tag.name),
                        selected: isSelected,
                        selectedColor: Color(tag.colorValue).withValues(alpha: 0.3),
                        onSelected: (val) {
                          if (val) {
                            ref.read(tagProvider.notifier).addTagToDocument(doc.path, tag.id!);
                          } else {
                            ref.read(tagProvider.notifier).removeTagFromDocument(doc.path, tag.id!);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Create New Tag'),
                    onTap: () async {
                      Navigator.pop(context);
                      _showCreateTagDialog();
                    },
                  )
                ],
              ),
            );
          }
        );
      }
    );
  }

  void _showCreateTagDialog() {
    String tagName = '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Tag'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Tag Name (e.g. Work)'),
          onChanged: (val) => tagName = val,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (tagName.trim().isNotEmpty) {
                // ignore: deprecated_member_use
                ref.read(tagProvider.notifier).createTag(tagName.trim(), Colors.blue.value);
              }
              Navigator.pop(context);
            }, 
            child: const Text('Create')
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final pdfState = ref.watch(pdfProvider);
    final tagState = ref.watch(tagProvider);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching ? TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search files...',
            border: InputBorder.none,
          ),
          onChanged: (val) => setState(() => _searchQuery = val),
        ) : const Text('My Library'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) _searchQuery = '';
              });
            },
          ),
          if (!_isSearching) ...[
            IconButton(
              icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
              onPressed: () => setState(() => _isGridView = !_isGridView),
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showSettingsSheet,
            ),
            PopupMenuButton<SortOption>(
              onSelected: (option) => setState(() => _sortOption = option),
              itemBuilder: (context) => [
                const PopupMenuItem(value: SortOption.date, child: Text('Sort by Date')),
                const PopupMenuItem(value: SortOption.name, child: Text('Sort by Name')),
                const PopupMenuItem(value: SortOption.size, child: Text('Sort by Size')),
              ],
            ),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All Files'),
                  selected: _selectedFilterId == -1,
                  onSelected: (_) => setState(() => _selectedFilterId = -1),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Favorites'),
                  selected: _selectedFilterId == -2,
                  onSelected: (_) => setState(() => _selectedFilterId = -2),
                  selectedColor: Colors.redAccent.withValues(alpha: 0.2),
                ),
                const SizedBox(width: 8),
                ...tagState.tags.map((tag) => Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(tag.name),
                    selected: _selectedFilterId == tag.id,
                    onSelected: (_) => setState(() => _selectedFilterId = tag.id!),
                    selectedColor: Color(tag.colorValue).withValues(alpha: 0.3),
                  ),
                )),
                ActionChip(
                  label: const Text('+ Tag'),
                  onPressed: _showCreateTagDialog,
                )
              ],
            ),
          ),
        ),
      ),
      body: Builder(
        builder: (context) {
          if (pdfState.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (pdfState.error != null) {
            return Center(child: Text('Error: ${pdfState.error}'));
          }

          var docs = pdfState.docs;
          
          // Apply Filters
          if (_selectedFilterId == -2) {
            docs = docs.where((d) => d.isFavorite).toList();
          } else if (_selectedFilterId >= 0) {
            docs = docs.where((d) {
              final docTags = tagState.documentTags[d.path] ?? [];
              return docTags.contains(_selectedFilterId);
            }).toList();
          }
          
          if (_searchQuery.trim().isNotEmpty) {
            docs = docs.where((d) => d.name.toLowerCase().contains(_searchQuery.trim().toLowerCase())).toList();
          }

          // Apply Sort
          docs.sort((a, b) {
            if (_sortOption == SortOption.name) return a.name.compareTo(b.name);
            if (_sortOption == SortOption.size) return b.size.compareTo(a.size);
            return b.lastRead.compareTo(a.lastRead);
          });

          if (docs.isEmpty) {
            return const Center(child: Text('No PDFs found.'));
          }

          if (_isGridView) {
            return GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.75,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: docs.length,
              itemBuilder: (context, index) => _buildGridItem(docs[index]),
            );
          } else {
            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, index) => _buildListItem(docs[index]),
            );
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ref.read(pdfProvider.notifier).loadPdfs(),
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildListItem(PdfDocument doc) {
    double progress = doc.totalPages > 0 ? (doc.lastPage / doc.totalPages) : 0;
    return ListTile(
      leading: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 40),
      title: Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_formatBytes(doc.size)} • ${DateFormat('MMM d, yyyy').format(doc.lastRead)}'),
          if (doc.totalPages > 0) LinearProgressIndicator(value: progress),
        ],
      ),
      trailing: IconButton(
        icon: Icon(doc.isFavorite ? Icons.favorite : Icons.favorite_border, color: Colors.redAccent),
        onPressed: () => ref.read(pdfProvider.notifier).toggleFavorite(doc),
      ),
      onTap: () => _openPdf(doc),
      onLongPress: () => _showTagDialog(doc),
    );
  }

  Widget _buildGridItem(PdfDocument doc) {
    double progress = doc.totalPages > 0 ? (doc.lastPage / doc.totalPages) : 0;
    return GestureDetector(
      onTap: () => _openPdf(doc),
      onLongPress: () => _showTagDialog(doc),
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  child: SizedBox(
                    width: double.infinity,
                    child: PdfThumbnail(document: doc),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(doc.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if (doc.totalPages > 0) LinearProgressIndicator(value: progress),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatBytes(doc.size), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  IconButton(
                    icon: Icon(doc.isFavorite ? Icons.favorite : Icons.favorite_border, size: 20, color: Colors.redAccent),
                    onPressed: () => ref.read(pdfProvider.notifier).toggleFavorite(doc),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
