import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../models/pdf_document.dart' as model;
import '../utils/thumbnail_helper.dart';

class PdfThumbnail extends StatefulWidget {
  final model.PdfDocument document;
  
  const PdfThumbnail({super.key, required this.document});

  @override
  State<PdfThumbnail> createState() => _PdfThumbnailState();
}

class _PdfThumbnailState extends State<PdfThumbnail> {
  ImageProvider? _imageProvider;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant PdfThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document.path != widget.document.path) {
      _imageProvider = null;
      _hasError = false;
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    try {
      final cacheFile = await ThumbnailHelper.getThumbnailFile(widget.document.path);
      
      // Check if cache exists
      if (await cacheFile.exists()) {
        if (!mounted) return;
        setState(() {
          _imageProvider = FileImage(cacheFile);
        });
        return;
      }

      // Render it live since it's missing in cache
      PdfDocument? pdfDoc;
      try {
        pdfDoc = await PdfDocument.openFile(widget.document.path);
        if (pdfDoc.pages.isNotEmpty && mounted) {
          final page = pdfDoc.pages.first;
          final pdfImage = await page.render(fullWidth: 300, fullHeight: 400);
          if (pdfImage != null && mounted) {
            final image = await pdfImage.createImage();
            final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            pdfImage.dispose();

            if (byteData != null) {
              await cacheFile.writeAsBytes(byteData.buffer.asUint8List());
              if (!mounted) return;
              setState(() {
                _imageProvider = FileImage(cacheFile);
              });
            }
          }
        }
      } finally {
        pdfDoc?.dispose();
      }
    } catch (e) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const Center(child: Icon(Icons.error, color: Colors.red, size: 40));
    }
    if (_imageProvider == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Image(image: _imageProvider!, fit: BoxFit.cover);
  }
}
