import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:gal/gal.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../models/pdf_document.dart' as my_models;
import '../providers/pdf_provider.dart';
import '../database/database_helper.dart';
import 'package:url_launcher/url_launcher.dart';

enum DrawTool { pencil, brush, eraser }

class _DrawingStroke {
  final int pageNumber;
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final DrawTool tool; // We store if it was pencil or brush (eraser just deletes)
  List<Rect>? rects;

  _DrawingStroke(this.pageNumber, this.points, this.color, this.strokeWidth, {this.tool = DrawTool.pencil, this.rects});
  
  Map<String, dynamic> toJson() => {
    'pageNumber': pageNumber,
    'points_json': jsonEncode({
      'color': color.value,
      'strokeWidth': strokeWidth,
      'tool': tool.name,
      'points': points.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
      if (rects != null) 'rects': rects!.map((r) => {'l': r.left, 't': r.top, 'r': r.right, 'b': r.bottom}).toList()
    }),
  };
}

class PdfViewerScreen extends ConsumerStatefulWidget {
  final my_models.PdfDocument document;

  const PdfViewerScreen({super.key, required this.document});

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  PdfTextSearcher? _textSearcher;
  final FlutterTts _flutterTts = FlutterTts();
  
  bool _isReadingAloud = false;
  bool _isSearching = false;
  bool _isAutoScrolling = false;
  double _autoScrollSpeed = 1.0;
  Timer? _autoScrollTimer;
  final FocusNode _searchFocusNode = FocusNode();

  // Drawing state
  List<_DrawingStroke> _strokes = [];
  final List<_DrawingStroke> _strokesHistory = [];
  _DrawingStroke? _currentStroke;
  PdfPageRawText? _currentText;
  final ValueNotifier<int> _dragNotifier = ValueNotifier<int>(0);
  DrawTool _currentTool = DrawTool.pencil;
  final double _pencilThickness = 3.0;
  final double _brushThickness = 12.0;
  Color _pencilColor = Colors.red;
  Color _brushColor = const Color.fromARGB(255, 255, 235, 59); // Yellow
  bool _hideAnnotations = false;

  bool _isDrawMode = false;
  Map<int, Rect> _pageRects = {};

  final GlobalKey _drawingAreaKey = GlobalKey();
  
  final TextEditingController _searchController = TextEditingController();

  // Reading Session Tracking
  late final DateTime _sessionStartTime;

  @override
  void initState() {
    super.initState();
    _sessionStartTime = DateTime.now();
    _loadAnnotations();
  }

  Future<void> _loadAnnotations() async {
    final anns = await DatabaseHelper.instance.getAnnotations(widget.document.path);
    setState(() {
      _strokes = anns.map((a) {
        final dynamic decoded = jsonDecode(a['points_json']);
        if (decoded is List) {
          // Legacy format
          return _DrawingStroke(
            a['page'],
            decoded.map((p) => Offset(p['dx'].toDouble(), p['dy'].toDouble())).toList(),
            Colors.red, 
            3.0,
            tool: DrawTool.pencil,
          );
        } else {
          // New format
          final Map<String, dynamic> data = decoded;
          final List<dynamic> pointsList = data['points'];
          final toolName = data['tool'] as String?;
          final tool = DrawTool.values.firstWhere((e) => e.name == toolName, orElse: () => DrawTool.pencil);
          
          final List<Rect>? loadedRects = data['rects'] != null 
              ? (data['rects'] as List).map((r) => Rect.fromLTRB(r['l'].toDouble(), r['t'].toDouble(), r['r'].toDouble(), r['b'].toDouble())).toList()
              : null;
          
          return _DrawingStroke(
            a['page'],
            pointsList.map((p) => Offset(p['dx'].toDouble(), p['dy'].toDouble())).toList(),
            Color(data['color']),
            data['strokeWidth'].toDouble(),
            tool: tool,
            rects: loadedRects,
          );
        }
      }).toList();
    });
  }

  Future<void> _saveAnnotationsToDb() async {
    final anns = _strokes.map((s) => s.toJson()).toList();
    await DatabaseHelper.instance.saveAnnotations(widget.document.path, anns);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Annotations saved!')));
    }
  }

  void _updateState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _saveReadingSession();
    _autoScrollTimer?.cancel();
    _flutterTts.stop();
    _textSearcher?.removeListener(_updateState);
    _textSearcher?.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _saveReadingSession() {
    final duration = DateTime.now().difference(_sessionStartTime).inSeconds;
    if (duration >= 10) { // Only save if they read for at least 10 seconds
      DatabaseHelper.instance.addReadingSession(widget.document.path, duration);
    }
  }

  void _saveProgress() {
    if (!_pdfController.isReady) return;
    final currentPage = _pdfController.pageNumber;
    final totalPages = _pdfController.pages.length;
    ref.read(pdfProvider.notifier).updateProgress(widget.document, currentPage ?? widget.document.lastPage, totalPages);
    _updateState(); // Update the floating page indicator
  }

  Future<void> _toggleTts() async {
    if (_isReadingAloud) {
      await _flutterTts.stop();
      setState(() => _isReadingAloud = false);
    } else {
      if (!_pdfController.isReady || _pdfController.pageNumber == null) return;
      setState(() => _isReadingAloud = true);
      
      try {
         final pageIndex = _pdfController.pageNumber! - 1;
         final page = _pdfController.document.pages[pageIndex];
         final text = await page.loadText();
         
         if (text != null && text.fullText.trim().isNotEmpty) {
           await _flutterTts.speak(text.fullText);
         } else {
           await _flutterTts.speak("No text found on this page.");
         }
      } catch (e) {
         await _flutterTts.speak("Could not read this page.");
      }
      
      _flutterTts.setCompletionHandler(() {
        if (mounted) setState(() => _isReadingAloud = false);
      });
    }
  }

  void _toggleAutoScroll() {
    setState(() => _isAutoScrolling = !_isAutoScrolling);
    if (_isAutoScrolling) {
      _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!_pdfController.isReady) return;
        final m = _pdfController.value.clone();
        // ignore: deprecated_member_use
        m.translate(0.0, -_autoScrollSpeed);
        _pdfController.value = m;
      });
    } else {
      _autoScrollTimer?.cancel();
    }
  }


  Future<String?> _showPasswordDialog() async {
    String? password;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        final passwordController = TextEditingController();
        return AlertDialog(
          title: const Text('Password Required'),
          content: TextField(
            controller: passwordController,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter PDF password',
            ),
            onSubmitted: (val) {
              password = val;
              Navigator.pop(dialogContext);
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                password = passwordController.text;
                Navigator.pop(dialogContext);
              },
              child: const Text('Unlock'),
            ),
          ],
        );
      },
    );
    return password;
  }

  @override
  Widget build(BuildContext context) {
    final bool canPop = !_isSearching && !_isDrawMode;
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSearching) {
          setState(() {
            _isSearching = false;
            _searchController.clear();
            _textSearcher?.resetTextSearch();
          });
        } else if (_isDrawMode) {
          setState(() {
            _isDrawMode = false;
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_isSearching) {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                  _textSearcher?.resetTextSearch();
                });
              } else if (_isDrawMode) {
                setState(() {
                  _isDrawMode = false;
                });
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: _isSearching 
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search text...',
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _textSearcher?.resetTextSearch();
                    },
                  ),
                ),
                onSubmitted: (val) {
                  _textSearcher?.startTextSearch(val, caseInsensitive: true);
                },
              )
            : Text(widget.document.name, style: const TextStyle(fontSize: 16)),
          actions: [
            if (!_isSearching) IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                setState(() => _isSearching = true);
                _searchFocusNode.requestFocus();
              },
              tooltip: 'Search Document',
            ),
            if (!_isSearching) IconButton(
              icon: Icon(_isAutoScrolling ? Icons.pause_circle_filled : Icons.play_circle_fill),
              onPressed: _toggleAutoScroll,
              tooltip: 'Auto Scroll',
              color: _isAutoScrolling ? Colors.red : null,
            ),
            if (!_isSearching) IconButton(
              icon: Icon(_isReadingAloud ? Icons.stop : Icons.record_voice_over),
              onPressed: _toggleTts,
              tooltip: 'Text-to-Speech',
              color: _isReadingAloud ? Colors.red : null,
            ),
            if (_isSearching && _textSearcher != null && _textSearcher!.matches.isNotEmpty) ...[
              Center(child: Text('${(_textSearcher!.currentIndex ?? 0) + 1}/${_textSearcher!.matches.length}', style: const TextStyle(fontSize: 14))),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: () => _textSearcher!.goToPrevMatch(),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: () => _textSearcher!.goToNextMatch(),
              ),
              if (_isDrawMode) IconButton(
                icon: const Icon(Icons.save),
                onPressed: _saveAnnotationsToDb,
                tooltip: 'Save Copy',
              ),
            ]
          ],
        ),
        body: Stack(
          children: [
            PdfViewer.file(
              widget.document.path,
              controller: _pdfController,
              passwordProvider: _showPasswordDialog,
              params: PdfViewerParams(
                customizeContextMenuItems: (params, items) {
                  // Keep only standard options to prevent any system 'Translate' options from appearing
                  items.removeWhere((item) => 
                    item.type != ContextMenuButtonType.copy && 
                    item.type != ContextMenuButtonType.selectAll
                  );

                  // Add Web Search Option
                  items.add(ContextMenuButtonItem(
                    onPressed: () async {
                      final text = await params.textSelectionDelegate.getSelectedText();
                      if (text.isNotEmpty) {
                        final uri = Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(text)}');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      }
                      params.dismissContextMenu();
                    },
                    label: 'Web Search',
                  ));
                },
                viewerOverlayBuilder: (context, size, handleLinkTap) {
                  return [
                    if (_isDrawMode)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: _handlePanStart,
                        onPanUpdate: _handlePanUpdate,
                        onPanEnd: _handlePanEnd,
                        child: Container(
                          color: Colors.transparent,
                        ),
                      ),
                    if (_isDrawMode)
                      ValueListenableBuilder<int>(
                        valueListenable: _dragNotifier,
                        builder: (context, _, child) {
                          if (_currentStroke == null) return const SizedBox.shrink();
                          return CustomPaint(
                            size: size,
                            painter: _ActiveStrokePainter(
                              stroke: _currentStroke!,
                              matrix: _pdfController.value,
                            ),
                          );
                        },
                      ),
                  ];
                },
                pageDropShadow: const BoxShadow(color: Colors.black26, blurRadius: 4),
                pagePaintCallbacks: [
                  if (_textSearcher != null) _textSearcher!.pageTextMatchPaintCallback,
                  if (!_hideAnnotations) _paintStrokes,
                ],
                onViewerReady: (document, controller) {
                   _textSearcher ??= PdfTextSearcher(controller)..addListener(_updateState);
                   if (widget.document.lastPage > 1) {
                      controller.goToPage(pageNumber: widget.document.lastPage);
                   }
                   _updateState();
                },
                onPageChanged: (pageNumber) {
                   _saveProgress();
                },
              ),
            ),
            if (_pdfController.isReady && _pdfController.pageNumber != null)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Page ${_pdfController.pageNumber} of ${_pdfController.pages.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            if (_isAutoScrolling)
              Positioned(
                bottom: 80,
                left: 20,
                right: 20,
                child: Card(
                  color: Colors.black87,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.speed, color: Colors.white),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Slider(
                            value: _autoScrollSpeed,
                            min: 0.1,
                            max: 5.0,
                            onChanged: (val) => setState(() => _autoScrollSpeed = val),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: _toggleAutoScroll,
                        )
                      ],
                    ),
                  ),
                ),
              ),
            if (_isDrawMode)
              Positioned(
                left: 16,
                right: 16,
                bottom: 30,
                child: Center(
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(30),
                    color: Colors.black87,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.green),
                              onPressed: _toggleDrawMode,
                              tooltip: 'Done',
                            ),
                            Container(width: 1, height: 24, color: Colors.grey, margin: const EdgeInsets.symmetric(horizontal: 4)),
                            IconButton(
                              icon: Icon(Icons.edit, color: _currentTool == DrawTool.pencil ? Colors.blue : Colors.white),
                              onPressed: () => setState(() => _currentTool = DrawTool.pencil),
                              tooltip: 'Pencil',
                            ),
                            IconButton(
                              icon: Icon(Icons.brush, color: _currentTool == DrawTool.brush ? Colors.yellow : Colors.white),
                              onPressed: () => setState(() => _currentTool = DrawTool.brush),
                              tooltip: 'Highlighter',
                            ),
                            IconButton(
                              icon: Icon(Icons.cleaning_services, color: _currentTool == DrawTool.eraser ? Colors.red : Colors.white),
                              onPressed: () => setState(() => _currentTool = DrawTool.eraser),
                              tooltip: 'Eraser',
                            ),
                            Container(width: 1, height: 24, color: Colors.grey, margin: const EdgeInsets.symmetric(horizontal: 4)),
                            IconButton(
                              icon: const Icon(Icons.undo, color: Colors.white),
                              onPressed: _strokes.isEmpty ? null : _undoStroke,
                              tooltip: 'Undo',
                            ),
                            IconButton(
                              icon: const Icon(Icons.redo, color: Colors.white),
                              onPressed: _strokesHistory.isEmpty ? null : _redoStroke,
                              tooltip: 'Redo',
                            ),
                            Container(width: 1, height: 24, color: Colors.grey, margin: const EdgeInsets.symmetric(horizontal: 4)),
                            IconButton(
                              icon: Icon(_hideAnnotations ? Icons.visibility_off : Icons.visibility, color: Colors.white),
                              onPressed: () => setState(() => _hideAnnotations = !_hideAnnotations),
                              tooltip: 'Toggle Annotations',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (!_isSearching && !_isDrawMode)
              Positioned(
                right: 16,
                bottom: 30,
                child: FloatingActionButton(
                  heroTag: "draw_btn",
                  backgroundColor: Colors.blue,
                  onPressed: _toggleDrawMode,
                  child: const Icon(Icons.draw, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _undoStroke() {
    if (_strokes.isNotEmpty) {
      setState(() {
        _strokesHistory.add(_strokes.removeLast());
      });
    }
  }

  void _redoStroke() {
    if (_strokesHistory.isNotEmpty) {
      setState(() {
        _strokes.add(_strokesHistory.removeLast());
      });
    }
  }

  void _toggleDrawMode() {
    setState(() {
      _isDrawMode = !_isDrawMode;
    });
  }

  void _eraseAt(Offset docPoint) {
    setState(() {
      _strokes.removeWhere((stroke) {
        return stroke.points.any((p) => (p - docPoint).distance < 20.0);
      });
    });
  }

  void _handlePanStart(DragStartDetails details) {
    if (_isDrawMode) {
      final inv = Matrix4.copy(_pdfController.value)..invert();
      final docPoint = MatrixUtils.transformPoint(inv, details.localPosition);
      
      if (_currentTool == DrawTool.eraser) {
        _eraseAt(docPoint);
      } else {
        int? pageNum;
        for (int i = 0; i < _pdfController.pages.length; i++) {
          final rect = _pdfController.layout.pageLayouts[i];
          if (rect.contains(docPoint)) {
            pageNum = i + 1;
            break;
          }
        }
        
        if (pageNum != null) {
          _strokesHistory.clear();
          final color = _currentTool == DrawTool.pencil ? _pencilColor : _brushColor;
          final thickness = _currentTool == DrawTool.pencil ? _pencilThickness : _brushThickness;
          _currentStroke = _DrawingStroke(pageNum, [docPoint], color, thickness, tool: _currentTool);
          
          if (_currentTool == DrawTool.brush) {
            final page = _pdfController.document?.pages[pageNum - 1];
            if (page != null) {
              page.loadText().then((text) {
                if (!mounted) return;
                _currentText = text;
              });
            }
          }
          _dragNotifier.value++;
        }
      }
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_isDrawMode) {
      final inv = Matrix4.copy(_pdfController.value)..invert();
      final docPoint = MatrixUtils.transformPoint(inv, details.localPosition);
      
      if (_currentTool == DrawTool.eraser) {
        _eraseAt(docPoint);
      } else if (_currentStroke != null) {
        _currentStroke!.points.add(docPoint);
        if (_currentTool == DrawTool.brush && _currentText != null) {
          _updateHighlighterRects(_currentStroke!, _currentText!);
        }
        _dragNotifier.value++;
      }
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_isDrawMode) {
      if (_currentStroke != null) {
        if (_currentTool == DrawTool.brush && _currentText != null) {
          _updateHighlighterRects(_currentStroke!, _currentText!);
        }
        setState(() {
          _strokes.add(_currentStroke!);
        });
      }
      _currentStroke = null;
      _currentText = null;
      _dragNotifier.value++;
    }
  }

  void _updateHighlighterRects(_DrawingStroke stroke, PdfPageRawText text) {
    if (stroke.points.isEmpty || text.charRects.isEmpty) return;
    
    final page = _pdfController.document?.pages[stroke.pageNumber - 1];
    final pageRect = _pageRects[stroke.pageNumber];
    if (page == null || pageRect == null) return;

    double minX = stroke.points[0].dx, maxX = stroke.points[0].dx;
    double minY = stroke.points[0].dy, maxY = stroke.points[0].dy;
    for (var p in stroke.points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final pathRect = Rect.fromLTRB(minX, minY, maxX, maxY).inflate(10.0);

    final List<Rect> matchedChars = [];
    for (var charRect in text.charRects) {
      final fRect = charRect.toRect(page: page).translate(pageRect.left, pageRect.top);
      if (pathRect.overlaps(fRect)) {
        bool isNear = false;
        for (var p in stroke.points) {
          if (fRect.inflate(10.0).contains(p)) {
            isNear = true;
            break;
          }
        }
        if (isNear) {
          matchedChars.add(fRect);
        }
      }
    }

    final List<Rect> intersectingRects = [];
    if (matchedChars.isNotEmpty) {
      matchedChars.sort((a, b) {
        if ((a.top - b.top).abs() < 10) return a.left.compareTo(b.left);
        return a.top.compareTo(b.top);
      });
      
      Rect? currentLine;
      for (var r in matchedChars) {
        if (currentLine == null) {
          currentLine = r;
        } else {
          if ((currentLine.top - r.top).abs() < 10) {
            currentLine = currentLine.expandToInclude(r);
          } else {
            intersectingRects.add(currentLine);
            currentLine = r;
          }
        }
      }
      if (currentLine != null) intersectingRects.add(currentLine);
    }

    if (intersectingRects.isEmpty) {
      intersectingRects.add(Rect.fromLTRB(minX, minY - 10, maxX, maxY + 10));
    }

    stroke.rects = intersectingRects;
  }

  void _paintStrokes(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    _pageRects[page.pageNumber] = pageRect;
    final pageStrokes = _strokes.where((s) => s.pageNumber == page.pageNumber);
    for (final stroke in pageStrokes) {
      if (stroke.rects != null) {
        final paint = Paint()
          ..color = stroke.color
          ..style = PaintingStyle.fill
          ..blendMode = BlendMode.multiply;
        for (final rect in stroke.rects!) {
          canvas.drawRect(rect, paint);
        }
      } else {
        final paint = Paint()
          ..color = stroke.color
          ..strokeWidth = stroke.strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;

        if (stroke.points.isNotEmpty) {
          final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
          for (var i = 1; i < stroke.points.length; i++) {
            path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
          }
          canvas.drawPath(path, paint);
        }
      }
    }
  }
}

class _ActiveStrokePainter extends CustomPainter {
  final _DrawingStroke stroke;
  final Matrix4 matrix;

  _ActiveStrokePainter({required this.stroke, required this.matrix});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.transform(matrix.storage);
    
    if (stroke.rects != null) {
      final paint = Paint()
        ..color = stroke.color
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.multiply;
      for (final rect in stroke.rects!) {
        canvas.drawRect(rect, paint);
      }
    } else {
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.isNotEmpty) {
        final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (var i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ActiveStrokePainter oldDelegate) => true;
}

