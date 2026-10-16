import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:epubx/epubx.dart' as epub;
import 'package:flutter_html/flutter_html.dart';
import 'package:pdfx/pdfx.dart' as px;
import 'package:syncfusion_flutter_pdf/pdf.dart' as spdf;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';

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
        scaffoldBackgroundColor: const Color(0xFFF9F7F1),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
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

late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initIncomingLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initIncomingLinks() async {
    _appLinks = AppLinks();

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleIncomingUri(initialUri);
      }
    } catch (e) {
      debugPrint('Error getting initial link: $e');
    }

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) => _handleIncomingUri(uri),
      onError: (err) => debugPrint('Error in uriLinkStream: $err'),
    );
  }

static const _contentChannel = MethodChannel('com.reader.tflow.t_flow/content_resolver');

  Future<void> _handleIncomingUri(Uri uri) async {
    setState(() => _isLoading = true);
    try {
      String localFilePath;

      if (uri.scheme == 'content') {
        final String? resolvedPath = await _contentChannel.invokeMethod<String>(
          'getFilePathFromContentUri',
          {'uri': uri.toString()},
        );

        if (resolvedPath == null) {
          throw Exception("Could not resolve content URI");
        }
        localFilePath = resolvedPath;
      } else {
        localFilePath = uri.toFilePath();
      }

      if (!mounted) return;
      setState(() => _isLoading = false);

      final isEpub = localFilePath.toLowerCase().endsWith('.epub');
      if (isEpub) {
        _loadEpub(localFilePath);
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UnifiedDocumentReader(filePath: localFilePath, isPdf: true),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error processing incoming document URI: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

Future<void> _pickDocument() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub', 'pdf'],
      );
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final isEpub = path.toLowerCase().endsWith('.epub');

      if (!mounted) return;

      if (isEpub) {
        _loadEpub(path);
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => UnifiedDocumentReader(filePath: path, isPdf: true)),
        );
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
          builder: (_) => UnifiedDocumentReader(filePath: path, isPdf: false, epubBook: book),
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load EPUB: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('T-Flow'), centerTitle: true),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.manage_search, size: 90, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  const Text('T-Flow Document Engine', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('EPUB & PDF Force-Reflow with TTS', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _pickDocument,
                    icon: const Icon(Icons.file_open),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      child: Text('Open Document', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class UnifiedDocumentReader extends StatefulWidget {
  final String filePath;
  final bool isPdf;
  final epub.EpubBook? epubBook;

  const UnifiedDocumentReader({super.key, required this.filePath, required this.isPdf, this.epubBook});

  @override
  State<UnifiedDocumentReader> createState() => _UnifiedDocumentReaderState();
}

class _UnifiedDocumentReaderState extends State<UnifiedDocumentReader> {
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  double _fontSize = 18.0;

  bool _forceReflowPdf = false;
  bool _isExtractingText = false;
  String _extractedPdfText = '';
  px.PdfControllerPinch? _pdfPinchController;

  int _currentEpubChapter = 0;
  List<epub.EpubChapter> _chapters = [];

  @override
  void initState() {
    super.initState();
    _initTts();

    if (widget.isPdf) {
      _pdfPinchController = px.PdfControllerPinch(
        document: px.PdfDocument.openFile(widget.filePath),
      );
    } else if (widget.epubBook != null) {
      _chapters = widget.epubBook!.Chapters ?? [];
    }
  }

  void _initTts() {
    _tts.setStartHandler(() => setState(() => _isSpeaking = true));
    _tts.setCompletionHandler(() => setState(() => _isSpeaking = false));
    _tts.setErrorHandler((_) => setState(() => _isSpeaking = false));
  }

  Future<void> _extractPdfText() async {
    setState(() => _isExtractingText = true);
    try {
      final file = File(widget.filePath);
      final bytes = await file.readAsBytes();
      final spdf.PdfDocument document = spdf.PdfDocument(inputBytes: bytes);
      final text = spdf.PdfTextExtractor(document).extractText();
      document.dispose();

      setState(() {
        _extractedPdfText = text.isEmpty ? "No readable text stream found in this PDF." : text;
        _isExtractingText = false;
        _forceReflowPdf = true;
      });
    } catch (e) {
      setState(() => _isExtractingText = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to extract text: $e')));
    }
  }

  String _getCurrentReadableText() {
    if (widget.isPdf) {
      return _extractedPdfText;
    } else {
      if (_chapters.isNotEmpty) {
        final raw = _chapters[_currentEpubChapter].HtmlContent ?? '';
        return raw.replaceAll(RegExp(r'<[^>]*>'), ' ');
      }
      return '';
    }
  }

  Future<void> _toggleTts() async {
    if (_isSpeaking) {
      await _tts.stop();
      setState(() => _isSpeaking = false);
    } else {
      if (widget.isPdf && !_forceReflowPdf) {
        await _extractPdfText();
      }
      final text = _getCurrentReadableText();
      if (text.isNotEmpty) {
        await _tts.speak(text);
      }
    }
  }

  @override
  void dispose() {
    _tts.stop();
    _pdfPinchController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.filePath.split('/').last;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: Icon(_isSpeaking ? Icons.stop_circle : Icons.volume_up),
            tooltip: _isSpeaking ? 'Stop TTS' : 'Read Aloud (TTS)',
            color: _isSpeaking ? Colors.red : null,
            onPressed: _toggleTts,
          ),
          if (widget.isPdf)
            IconButton(
              icon: Icon(_forceReflowPdf ? Icons.picture_as_pdf : Icons.zoom_in),
              tooltip: _forceReflowPdf ? 'Switch to Original PDF' : 'Force Text Reflow',
              onPressed: () {
                if (!_forceReflowPdf && _extractedPdfText.isEmpty) {
                  _extractPdfText();
                } else {
                  setState(() => _forceReflowPdf = !_forceReflowPdf);
                }
              },
            ),
          if (!widget.isPdf || _forceReflowPdf) ...[
            IconButton(
              icon: const Icon(Icons.text_decrease),
              onPressed: () => setState(() => _fontSize = (_fontSize - 2).clamp(12.0, 36.0)),
            ),
            IconButton(
              icon: const Icon(Icons.text_increase),
              onPressed: () => setState(() => _fontSize = (_fontSize + 2).clamp(12.0, 36.0)),
            ),
          ],
        ],
      ),
      drawer: (!widget.isPdf && _chapters.isNotEmpty)
          ? Drawer(
              child: ListView(
                children: [
                  const DrawerHeader(
                    child: Text('Chapters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  ...List.generate(_chapters.length, (i) {
                    return ListTile(
                      title: Text(_chapters[i].Title ?? 'Chapter ${i + 1}'),
                      selected: i == _currentEpubChapter,
                      onTap: () {
                        setState(() => _currentEpubChapter = i);
                        Navigator.pop(context);
                      },
                    );
                  }),
                ],
              ),
            )
          : null,
      body: widget.isPdf
          ? (_isExtractingText
              ? const Center(child: CircularProgressIndicator())
              : _forceReflowPdf
                  ? _buildReflowTextView(_extractedPdfText)
                  : px.PdfViewPinch(controller: _pdfPinchController!))
          : _buildEpubReflowView(),
    );
  }

  Widget _buildReflowTextView(String text) {
    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Text(
          text,
          style: TextStyle(fontSize: _fontSize, height: 1.6),
        ),
      ),
    );
  }

  Widget _buildEpubReflowView() {
    final html = _chapters.isNotEmpty
        ? (_chapters[_currentEpubChapter].HtmlContent ?? '<p>Empty</p>')
        : '<p>No content</p>';

    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Html(
          data: html,
          style: {
            "body": Style(fontSize: FontSize(_fontSize), lineHeight: const LineHeight(1.6)),
          },
        ),
      ),
    );
  }
}
