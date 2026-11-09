import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfPageSelectionScreen extends StatefulWidget {
  final String pdfPath;
  final String title;

  const PdfPageSelectionScreen({super.key, required this.pdfPath, required this.title});

  @override
  State<PdfPageSelectionScreen> createState() => _PdfPageSelectionScreenState();
}

class _PdfPageSelectionScreenState extends State<PdfPageSelectionScreen> {
  PdfDocument? _document;
  Set<int> _selectedPages = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    try {
      final doc = await PdfDocument.openFile(widget.pdfPath);
      setState(() {
        _document = doc;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading PDF: $e')));
      }
    }
  }

  void _togglePage(int pageIndex) {
    setState(() {
      if (_selectedPages.contains(pageIndex)) {
        _selectedPages.remove(pageIndex);
      } else {
        _selectedPages.add(pageIndex);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () {
              // Return selected pages as 0-indexed list sorted
              final sorted = _selectedPages.toList()..sort();
              Navigator.pop(context, sorted);
            },
            child: Text(
              'Done (${_selectedPages.length})',
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.purple, 
                fontSize: 16, 
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _document == null
              ? const Center(child: Text('Could not load PDF.'))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.7, // PDF standard aspect ratio approx
                  ),
                  itemCount: _document!.pages.length,
                  itemBuilder: (context, index) {
                    final isSelected = _selectedPages.contains(index);
                    return GestureDetector(
                      onTap: () => _togglePage(index),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: isSelected ? Colors.blue : Colors.grey.shade300,
                                width: isSelected ? 4 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: PdfPageView(
                              document: _document,
                              pageNumber: index + 1,
                              alignment: Alignment.center,
                            ),
                          ),
                          if (isSelected)
                            const Positioned(
                              top: 8,
                              right: 8,
                              child: CircleAvatar(
                                radius: 12,
                                backgroundColor: Colors.blue,
                                child: Icon(Icons.check, size: 16, color: Colors.white),
                              ),
                            ),
                          Positioned(
                            bottom: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
