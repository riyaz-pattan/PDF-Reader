import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database_helper.dart';
import '../models/tag_model.dart';

class TagState {
  final List<TagModel> tags;
  final Map<String, List<int>> documentTags;
  final bool isLoading;

  TagState({
    required this.tags,
    required this.documentTags,
    required this.isLoading,
  });

  TagState copyWith({
    List<TagModel>? tags,
    Map<String, List<int>>? documentTags,
    bool? isLoading,
  }) {
    return TagState(
      tags: tags ?? this.tags,
      documentTags: documentTags ?? this.documentTags,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class TagNotifier extends Notifier<TagState> {
  @override
  TagState build() {
    Future.microtask(() => loadTags());
    return TagState(tags: [], documentTags: {}, isLoading: true);
  }

  Future<void> loadTags() async {
    state = state.copyWith(isLoading: true);
    final tagMaps = await DatabaseHelper.instance.getAllTags();
    final tags = tagMaps.map((map) => TagModel.fromMap(map)).toList();
    state = state.copyWith(tags: tags, isLoading: false);
  }

  Future<void> loadTagsForDocument(String path) async {
    final docTags = await DatabaseHelper.instance.getTagsForDocument(path);
    final newDocumentTags = Map<String, List<int>>.from(state.documentTags);
    newDocumentTags[path] = docTags;
    state = state.copyWith(documentTags: newDocumentTags);
  }

  Future<void> createTag(String name, int color) async {
    await DatabaseHelper.instance.insertTag(name, color);
    await loadTags();
  }

  Future<void> deleteTag(int tagId) async {
    await DatabaseHelper.instance.deleteTag(tagId);
    await loadTags();
  }

  Future<void> addTagToDocument(String path, int tagId) async {
    await DatabaseHelper.instance.addTagToDocument(path, tagId);
    await loadTagsForDocument(path);
  }

  Future<void> removeTagFromDocument(String path, int tagId) async {
    await DatabaseHelper.instance.removeTagFromDocument(path, tagId);
    await loadTagsForDocument(path);
  }
}

final tagProvider = NotifierProvider<TagNotifier, TagState>(() {
  return TagNotifier();
});
