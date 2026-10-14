import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:epubx/epubx.dart' as epub;
import 'package:flutter_html/flutter_html.dart';
import 'package:pdfx/pdfx.dart';

void main() {
  runApp(const TFlowApp());
}

class TFlowApp extends StatelessWidget {
  const TFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'T-Flow',
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF9F7F1), // Warm paper tone
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2C3E50),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF181818),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF34495E),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = false;

  Future<void> _pickDocument() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub', 'pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final isEpub = path.toLowerCase().endsWith('.epub');

      if (!mounted) return;

      if (isEpub) {
        _loadEpub(path);
      } else {
        _loadPdf(path);
      }
    }
  }

  Future<void> _loadEpub(String path) async {
    setState(() => _isLoading = true);
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final book = await epub.EpubReader.readBook(bytes);

      if (!mounted) return;
      setState(() => _isLoading = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EpubReaderView(book: book, filePath: path),
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to parse EPUB: $e');
    }
  }

  void _loadPdf(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfReaderView(filePath: path),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'T-Flow',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.auto_stories_outlined,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Reflow Books & Documents',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'EPUB and standard linear PDFs',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _pickDocument,
                    icon: const Icon(Icons.folder_open),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      child: Text('Open File', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ---------------- EPUB Reflow Viewer ----------------
class EpubReaderView extends StatefulWidget {
  final epub.EpubBook book;
  final String filePath;

  const EpubReaderView({super.key, required this.book, required this.filePath});

  @override
  State<EpubReaderView> createState() => _EpubReaderViewState();
}

class _EpubReaderViewState extends State<EpubReaderView> {
  int _currentChapterIndex = 0;
  List<epub.EpubChapter> _chapters = [];
  double _fontSize = 18.0;

  @override
  void initState() {
    super.initState();
    _chapters = widget.book.Chapters ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.book.Title ?? 'Book';
    final hasChapters = _chapters.isNotEmpty;
    final currentHtml = hasChapters
        ? (_chapters[_currentChapterIndex].HtmlContent ?? '<p>Empty</p>')
        : '<p>No content available</p>';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.text_decrease),
            onPressed: () {
              if (_fontSize > 12) setState(() => _fontSize -= 1.5);
            },
          ),
          IconButton(
            icon: const Icon(Icons.text_increase),
            onPressed: () {
              if (_fontSize < 32) setState(() => _fontSize += 1.5);
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ...List.generate(_chapters.length, (index) {
              final ch = _chapters[index];
              return ListTile(
                title: Text(ch.Title ?? 'Chapter ${index + 1}'),
                selected: index == _currentChapterIndex,
                onTap: () {
                  setState(() => _currentChapterIndex = index);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
      body: SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Html(
            data: currentHtml,
            style: {
              "body": Style(
                fontSize: FontSize(_fontSize),
                lineHeight: const LineHeight(1.6),
                margin: Margins.zero,
                padding: HtmlPaddings.zero,
              ),
              "p": Style(
                margin: Margins.only(bottom: 12),
              ),
            },
          ),
        ),
      ),
      bottomNavigationBar: hasChapters && _chapters.length > 1
          ? BottomAppBar(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _currentChapterIndex > 0
                        ? () => setState(() => _currentChapterIndex--)
                        : null,
                  ),
                  Text(
                    '${_currentChapterIndex + 1} of ${_chapters.length}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _currentChapterIndex < _chapters.length - 1
                        ? () => setState(() => _currentChapterIndex++)
                        : null,
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

// ---------------- Standard PDF Linear Viewer ----------------
class PdfReaderView extends StatefulWidget {
  final String filePath;

  const PdfReaderView({super.key, required this.filePath});

  @override
  State<PdfReaderView> createState() => _PdfReaderViewState();
}

class _PdfReaderViewState extends State<PdfReaderView> {
  late PdfControllerPinch _pdfController;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfControllerPinch(
      document: PdfDocument.openFile(widget.filePath),
    );
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.filePath.split('/').last,
          style: const TextStyle(fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          PdfPageNumber(
            controller: _pdfController,
            builder: (_, loadingState, page, pagesCount) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '$page / ${pagesCount ?? 0}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
      body: PdfViewPinch(
        controller: _pdfController,
      ),
    );
  }
}
