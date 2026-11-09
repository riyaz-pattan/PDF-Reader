import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'library_tab.dart';
import 'pdf_tools_tab.dart';
import 'statistics_tab.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import '../models/pdf_document.dart' as my_models;
import '../database/database_helper.dart';
import 'pdf_viewer_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  final List<Widget> _tabs = [
    const LibraryTab(),
    const PdfToolsTab(),
    const StatisticsTab(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSharedPdf();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSharedPdf();
    }
  }

  Future<void> _checkSharedPdf() async {
    const channel = MethodChannel('app.docreader/intent');
    try {
      final String? filePath = await channel.invokeMethod('getSharedPdf');
      if (filePath != null) {
        final file = File(filePath);
        int size = 0;
        if (file.existsSync()) {
          size = file.lengthSync();
        }
        final doc = my_models.PdfDocument(
          path: filePath,
          name: filePath.split('/').last,
          size: size,
          lastRead: DateTime.now(),
        );
        await DatabaseHelper.instance.insertOrUpdate(doc);
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(document: doc)));
      }
    } catch (e) {
      debugPrint('Error checking shared pdf: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.library_books), label: 'Library'),
          BottomNavigationBarItem(icon: Icon(Icons.build), label: 'Tools'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Statistics'),
        ],
      ),
    );
  }
}
