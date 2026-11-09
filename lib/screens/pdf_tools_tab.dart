import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'pdf_page_selection_screen.dart';

class PdfToolsTab extends StatefulWidget {
  const PdfToolsTab({super.key});

  @override
  State<PdfToolsTab> createState() => _PdfToolsTabState();
}

class _PdfToolsTabState extends State<PdfToolsTab> {
  bool _isProcessing = false;

  Future<String?> _promptFileName(BuildContext context, String defaultName) async {
    final TextEditingController controller = TextEditingController(text: defaultName);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save Document As'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'File Name',
              suffixText: '.pdf',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(context, name);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }


  Future<void> _mergePdfs() async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.length > 1) {
        final Map<String, List<int>> selections = {};
        
        for (var f in result.files) {
          if (!mounted) return;
          final List<int>? pages = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PdfPageSelectionScreen(
                pdfPath: f.path!,
                title: 'Select Pages: ${f.name}'
              )
            )
          );
          if (pages == null) return; // User canceled the whole operation
          selections[f.name] = pages;
        }

        setState(() => _isProcessing = true);
        
        final PdfDocument document = PdfDocument();
        
        for (var file in result.files) {
          final pagesToMerge = selections[file.name] ?? [];
          if (pagesToMerge.isEmpty) continue;

          final bytes = await File(file.path!).readAsBytes();
          final PdfDocument loadedDocument = PdfDocument(inputBytes: bytes);
          
          for (int i in pagesToMerge) {
            if (i < loadedDocument.pages.count) {
              final template = loadedDocument.pages[i].createTemplate();
              final page = document.pages.add();
              page.graphics.drawPdfTemplate(template, const Offset(0, 0));
            }
          }
          loadedDocument.dispose();
        }

        if (document.pages.count == 0) {
          setState(() => _isProcessing = false);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No pages selected to merge.')));
          return;
        }

        setState(() => _isProcessing = false);
        final fileName = await _promptFileName(context, 'Merged_Document');
        if (fileName == null) return;
        setState(() => _isProcessing = true);

        final tempDir = await getTemporaryDirectory();
        final outFile = File('${tempDir.path}/$fileName.pdf');
        await outFile.writeAsBytes(await document.save());
        document.dispose();
        
        setState(() => _isProcessing = false);
        
        // Let the user save/share the generated file
        // ignore: deprecated_member_use
        await Share.shareXFiles([XFile(outFile.path)], text: 'Merged PDF Document');
        
      } else if (result != null && result.files.length == 1 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least 2 PDFs to merge.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error merging: $e')));
      }
    }
  }

  Future<void> _splitPdf() async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (!mounted) return;
        
        final List<int>? pagesToExtract = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfPageSelectionScreen(
              pdfPath: file.path!,
              title: 'Extract Pages'
            )
          )
        );

        if (pagesToExtract == null || pagesToExtract.isEmpty) return;

        setState(() => _isProcessing = true);
        
        final bytes = await File(file.path!).readAsBytes();
        final PdfDocument loadedDocument = PdfDocument(inputBytes: bytes);
        
        final PdfDocument newDoc = PdfDocument();
        for (int i in pagesToExtract) {
          if (i < loadedDocument.pages.count) {
            final template = loadedDocument.pages[i].createTemplate();
            final page = newDoc.pages.add();
            page.graphics.drawPdfTemplate(template, const Offset(0, 0));
          }
        }
        loadedDocument.dispose();

        setState(() => _isProcessing = false);
        final defaultName = 'Extracted_${file.name.replaceAll('.pdf', '')}';
        final fileName = await _promptFileName(context, defaultName);
        if (fileName == null) return;
        setState(() => _isProcessing = true);

        final tempDir = await getTemporaryDirectory();
        final outFile = File('${tempDir.path}/$fileName.pdf');
        await outFile.writeAsBytes(await newDoc.save());
        newDoc.dispose();
        
        setState(() => _isProcessing = false);
        
        // Let the user save/share the generated file
        // ignore: deprecated_member_use
        await Share.shareXFiles([XFile(outFile.path)], text: 'Extracted PDF Document');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error splitting: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF Tools')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildToolCard(
                icon: Icons.merge_type,
                title: 'Merge PDFs',
                subtitle: 'Combine multiple PDFs and select specific pages into a single file',
                onTap: _mergePdfs,
              ),
              const SizedBox(height: 16),
              _buildToolCard(
                icon: Icons.call_split,
                title: 'Split / Extract PDF',
                subtitle: 'Extract specific pages or page ranges from a PDF into a new file',
                onTap: _splitPdf,
              ),
            ],
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToolCard({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(icon, size: 48, color: isDarkMode ? Colors.white : Theme.of(context).primaryColor),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(subtitle, style: TextStyle(color: Colors.grey[600])),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
