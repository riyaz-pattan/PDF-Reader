import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/pdf_document.dart' as model;
import '../database/database_helper.dart';
import '../utils/thumbnail_helper.dart';

class PdfState {
  final List<model.PdfDocument> docs;
  final bool isLoading;
  final String? error;

  PdfState({
    required this.docs,
    this.isLoading = false,
    this.error,
  });

  PdfState copyWith({
    List<model.PdfDocument>? docs,
    bool? isLoading,
    String? error,
  }) {
    return PdfState(
      docs: docs ?? this.docs,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class PdfNotifier extends Notifier<PdfState> {
  bool _isScanning = false;

  @override
  PdfState build() {
    // Schedule loadPdfs to run after build
    Future.microtask(() => loadPdfs());
    return PdfState(docs: [], isLoading: true);
  }

  Future<void> loadPdfs() async {
    if (_isScanning) return;
    _isScanning = true;
    
    state = state.copyWith(isLoading: true, error: null);

    try {
      // 1. Load from DB
      final savedDocs = await DatabaseHelper.instance.getAllDocuments();
      state = state.copyWith(docs: savedDocs, isLoading: false);

      // 2. Scan for new files
      await _scanForPdfs(savedDocs);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    } finally {
      _isScanning = false;
    }
  }

  Future<void> _scanForPdfs(List<model.PdfDocument> existingDocs) async {
    if (Platform.isAndroid) {
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.request();
      }
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      
      if (status.isGranted) {
        final directories = [
          Directory('/storage/emulated/0/Download'),
          Directory('/storage/emulated/0/Documents'),
        ];

        List<File> foundFiles = [];
        for (var dir in directories) {
          if (await dir.exists()) {
            final files = dir.listSync(recursive: true, followLinks: false);
            for (var entity in files) {
              if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
                foundFiles.add(entity);
              }
            }
          }
        }

        List<model.PdfDocument> updatedList = List.from(existingDocs);
        bool hasChanges = false;
        
        for (var file in foundFiles) {
          final isExisting = existingDocs.any((doc) => doc.path == file.path);
          if (!isExisting) {
            final stat = await file.stat();
            final newDoc = model.PdfDocument(
              path: file.path,
              name: p.basename(file.path),
              size: stat.size,
              lastRead: DateTime.now(),
            );
            await DatabaseHelper.instance.insertOrUpdate(newDoc);
            updatedList.add(newDoc);
            hasChanges = true;
          }
        }

        if (hasChanges) {
          updatedList.sort((a, b) => b.lastRead.compareTo(a.lastRead));
          state = state.copyWith(docs: updatedList);
        }
        
        // Start background thumbnail generation (doesn't block the UI)
        _generateThumbnailsInBackground(updatedList);
      }
    }
  }

  Future<void> _generateThumbnailsInBackground(List<model.PdfDocument> docs) async {
    for (var doc in docs) {
      try {
        final cacheFile = await ThumbnailHelper.getThumbnailFile(doc.path);
        if (await cacheFile.exists()) continue; // Already generated

        PdfDocument? pdfDoc;
        try {
          pdfDoc = await PdfDocument.openFile(doc.path);
          if (pdfDoc.pages.isNotEmpty) {
            final page = pdfDoc.pages.first;
            final pdfImage = await page.render(fullWidth: 300, fullHeight: 400);
            if (pdfImage != null) {
              final image = await pdfImage.createImage();
              final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
              image.dispose();
              pdfImage.dispose();

              if (byteData != null) {
                await cacheFile.writeAsBytes(byteData.buffer.asUint8List());
              }
            }
          }
        } finally {
          pdfDoc?.dispose();
        }
      } catch (e) {
        // Silently skip broken PDFs during background generation
      }
    }
  }

  Future<void> toggleFavorite(model.PdfDocument doc) async {
    final updatedDoc = doc.copyWith(isFavorite: !doc.isFavorite);
    await DatabaseHelper.instance.insertOrUpdate(updatedDoc);
    
    final updatedDocs = state.docs.map((d) => d.path == doc.path ? updatedDoc : d).toList();
    state = state.copyWith(docs: updatedDocs);
  }

  Future<void> updateProgress(model.PdfDocument doc, int lastPage, int totalPages) async {
    final updatedDoc = doc.copyWith(
      lastPage: lastPage,
      totalPages: totalPages,
      lastRead: DateTime.now(),
    );
    await DatabaseHelper.instance.insertOrUpdate(updatedDoc);
    
    final updatedDocs = state.docs.map((d) => d.path == doc.path ? updatedDoc : d).toList();
    updatedDocs.sort((a, b) => b.lastRead.compareTo(a.lastRead));
    state = state.copyWith(docs: updatedDocs);
  }
}

final pdfProvider = NotifierProvider<PdfNotifier, PdfState>(PdfNotifier.new);
