import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('themeMode') ?? 'light';
  final mode = saved == 'dark' ? ThemeMode.dark : ThemeMode.light;
  runApp(EscanerApp(initialThemeMode: mode));
}

/// Paleta “PDF”: rojos vivos y alto contraste
const _pdfRed = Color(0xFFD32F2F); // rojo principal
const _pdfDarkRed = Color(0xFFB71C1C); // rojo para oscuro

final _lightScheme = ColorScheme.fromSeed(
  seedColor: _pdfRed,
  brightness: Brightness.light,
);

final _darkScheme = ColorScheme.fromSeed(
  seedColor: _pdfDarkRed,
  brightness: Brightness.dark,
);

class EscanerApp extends StatefulWidget {
  final ThemeMode initialThemeMode;
  const EscanerApp({super.key, required this.initialThemeMode});

  @override
  State<EscanerApp> createState() => _EscanerAppState();
}

class _EscanerAppState extends State<EscanerApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'themeMode',
      mode == ThemeMode.dark ? 'dark' : 'light',
    );
    setState(() => _themeMode = mode);
  }

  void _toggleTheme() {
    _setThemeMode(
      _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Escáner (Fotos → PDF)',
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: _lightScheme,
        appBarTheme: AppBarTheme(
          backgroundColor: _lightScheme.surface,
          foregroundColor: _lightScheme.onSurface,
          elevation: 0,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: _lightScheme.primary,
          foregroundColor: _lightScheme.onPrimary,
        ),
        cardTheme: const CardThemeData(
          clipBehavior: Clip.antiAlias,
          elevation: 2,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: _darkScheme.copyWith(secondary: const Color(0xFFFFCDD2)),
        appBarTheme: AppBarTheme(
          backgroundColor: _darkScheme.surface,
          foregroundColor: _darkScheme.onSurface,
          elevation: 0,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: _darkScheme.primary,
          foregroundColor: _darkScheme.onPrimary,
        ),
        cardTheme: const CardThemeData(
          clipBehavior: Clip.antiAlias,
          elevation: 2,
        ),
      ),
      home: HomePage(
        onToggleTheme: _toggleTheme,
        isDark: _themeMode == ThemeMode.dark,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDark;
  const HomePage({
    super.key,
    required this.onToggleTheme,
    required this.isDark,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // --- Estado de pestañas ---
  int _tabIndex = 0;

  // --- Estado del escaneo/recorte ---
  final ImagePicker _picker = ImagePicker();
  final List<CapturedImage> _images = [];
  bool _creatingPdf = false;

  // ==================== LÓGICA ESCANEAR ====================
  Future<void> _addFromCamera() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 100,
      maxWidth: null,
      maxHeight: null,
    );
    if (photo == null) return;
    await _cropAndAdd(photo);
  }

  Future<void> _addFromGallery() async {
    final List<XFile> photos = await _picker.pickMultiImage(
      imageQuality: 100,
      maxWidth: null,
      maxHeight: null,
    );
    if (photos.isEmpty) return;
    for (final p in photos) {
      await _cropAndAdd(p);
    }
  }

  Future<void> _cropAndAdd(XFile original) async {
    try {
      final cs = Theme.of(context).colorScheme;
      final CroppedFile? cropped = await ImageCropper().cropImage(
        sourcePath: original.path,
        compressQuality: 100,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Recortar',
            toolbarWidgetColor: Colors.white,
            toolbarColor: cs.primary,
            statusBarLight: false,
            activeControlsWidgetColor: cs.primary,
            hideBottomControls: false,
            lockAspectRatio: false,
          ),
        ],
      );

      final String fileToUse = cropped?.path ?? original.path;
      final bytes = await File(fileToUse).readAsBytes();
      setState(
        () => _images.add(CapturedImage(bytes: bytes, filename: original.name)),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cropped != null
                ? 'Foto añadida (recortada).'
                : 'Foto añadida (sin recortar).',
          ),
        ),
      );
    } catch (e) {
      try {
        final bytes = await File(original.path).readAsBytes();
        setState(
          () =>
              _images.add(CapturedImage(bytes: bytes, filename: original.name)),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recorte falló, añadida sin recortar. ($e)')),
        );
      } catch (e2) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo añadir la foto: $e2')),
        );
      }
    }
  }

  Future<String> _saveInternalCopy(
    Uint8List bytes, {
    String baseName = 'Escaner',
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/escaner_saved');
    if (!(await dir.exists())) {
      await dir.create(recursive: true);
    }
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final path = '${dir.path}/${ts}_$baseName.pdf';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  Future<void> _saveAsPdf() async {
    if (_images.isEmpty) return;
    setState(() => _creatingPdf = true);
    try {
      // 1) Construir PDF
      final pdf = pw.Document();
      for (final img in _images) {
        final image = pw.MemoryImage(img.bytes);
        pdf.addPage(
          pw.Page(
            build: (_) =>
                pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
          ),
        );
      }
      final bytes = await pdf.save();

      // 2) Copia interna
      final internalPath = await _saveInternalCopy(bytes, baseName: 'Escaner');

      // 3) Guardado externo (Android usa SAF)
      if (Platform.isAndroid) {
        final result = await FileSaver.instance.saveAs(
          name: 'Escaner',
          bytes: bytes,
          ext: 'pdf',
          mimeType: MimeType.pdf,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'PDF guardado.\nCopia interna: $internalPath\nExterno: ${result ?? "(sin ruta visible)"}',
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        final FileSaveLocation? saveLocation = await getSaveLocation(
          suggestedName: 'Escaner.pdf',
          acceptedTypeGroups: const [
            XTypeGroup(
              label: 'PDF',
              extensions: ['pdf'],
              mimeTypes: ['application/pdf'],
            ),
          ],
        );
        if (saveLocation != null) {
          final path = saveLocation.path;
          if (path != null && path.isNotEmpty) {
            await File(path).writeAsBytes(bytes, flush: true);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'PDF guardado.\nCopia interna: $internalPath\n$path',
                  ),
                ),
              );
            }
          }
        }
      }

      // 4) Compartir (opcional)
      await Share.shareXFiles(
        [XFile(internalPath, mimeType: 'application/pdf')],
        subject: 'PDF generado',
        text: 'Documento generado con Escáner (Fotos → PDF)',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al crear/guardar el PDF: $e')),
      );
    } finally {
      if (mounted) setState(() => _creatingPdf = false);
    }
  }

  // ==================== UI ====================
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canSave = _images.isNotEmpty && !_creatingPdf;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tabIndex == 0
              ? 'Escáner: Fotos → PDF'
              : _tabIndex == 1
              ? 'Mis PDFs'
              : 'Acerca de',
        ),
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Icon(Icons.picture_as_pdf, color: cs.primary),
        ),
        actions: [
          IconButton(
            onPressed: widget.onToggleTheme,
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
            tooltip: widget.isDark ? 'Cambiar a claro' : 'Cambiar a oscuro',
          ),
          if (_tabIndex == 0)
            IconButton(
              onPressed: canSave ? _saveAsPdf : null,
              icon: const Icon(Icons.save_alt),
              tooltip: 'Guardar como PDF',
            ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [_buildScanTab(), const SavedPdfsView(), const AboutView()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            selectedIcon: Icon(Icons.document_scanner),
            label: 'Escanear',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_open),
            selectedIcon: Icon(Icons.folder),
            label: 'Mis PDFs',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons.info),
            label: 'Acerca de',
          ),
        ],
      ),
    );
  }

  Widget _buildScanTab() {
    return Column(
      children: [
        const SizedBox(height: 8),
        _buildActions(),
        const Divider(),
        Expanded(child: _buildReorderableList()),
        if (_creatingPdf) const LinearProgressIndicator(minHeight: 3),
      ],
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _addFromCamera,
            icon: const Icon(Icons.photo_camera),
            label: const Text('Cámara'),
          ),
          OutlinedButton.icon(
            onPressed: _addFromGallery,
            icon: const Icon(Icons.photo_library),
            label: const Text('Galería'),
          ),
          OutlinedButton.icon(
            onPressed: _images.isEmpty
                ? null
                : () => setState(() => _images.clear()),
            icon: const Icon(Icons.delete_sweep),
            label: const Text('Limpiar'),
          ),
        ],
      ),
    );
  }

  Widget _buildReorderableList() {
    if (_images.isEmpty) {
      return const Center(
        child: Text(
          'Agrega fotos desde la cámara o la galería.\nLuego puedes recortar y acomodarlas.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: _images.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = _images.removeAt(oldIndex);
          _images.insert(newIndex, item);
        });
      },
      itemBuilder: (context, index) {
        final img = _images[index];
        return _ThumbTile(
          key: ValueKey('img_$index'),
          bytes: img.bytes,
          index: index,
          onRemove: () => setState(() => _images.removeAt(index)),
          onRecrop: () async {
            final tmp = await getTemporaryDirectory();
            final p = '${tmp.path}/to_crop_$index.jpg';
            await File(p).writeAsBytes(img.bytes, flush: true);
            await _cropAndAdd(XFile(p));
            setState(() => _images.removeAt(index));
          },
        );
      },
    );
  }
}

// ================ VISTAS SECUNDARIAS ================
class SavedPdfsView extends StatefulWidget {
  const SavedPdfsView({super.key});
  @override
  State<SavedPdfsView> createState() => _SavedPdfsViewState();
}

class _SavedPdfsViewState extends State<SavedPdfsView> {
  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/escaner_saved');
    if (!(await dir.exists())) await dir.create(recursive: true);
    return dir;
  }

  Future<List<FileSystemEntity>> _listPdfs() async {
    final d = await _dir();
    final items = d.existsSync()
        ? d
              .listSync()
              .where((e) => e.path.toLowerCase().endsWith('.pdf'))
              .toList()
        : <FileSystemEntity>[];
    items.sort((a, b) {
      final am = File(a.path).statSync().modified;
      final bm = File(b.path).statSync().modified;
      return bm.compareTo(am); // recientes primero
    });
    return items;
  }

  Future<void> _delete(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
    setState(() {});
  }

  Future<void> _open(String path) async {
    await OpenFilex.open(path);
  }

  Future<void> _share(String path) async {
    await Share.shareXFiles([XFile(path, mimeType: 'application/pdf')]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<FileSystemEntity>>(
      future: _listPdfs(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final files = snap.data ?? [];
        if (files.isEmpty) {
          return Center(
            child: Text(
              'Aún no hay PDFs guardados por la app.\nGenera uno desde “Guardar”.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          );
        }
        return ListView.separated(
          itemCount: files.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final f = File(files[i].path);
            final name = f.uri.pathSegments.isNotEmpty
                ? f.uri.pathSegments.last
                : f.path.split(Platform.pathSeparator).last;
            final st = f.statSync();
            final sizeKb = (st.size / 1024).toStringAsFixed(1);
            final date = st.modified;
            return ListTile(
              leading: Icon(Icons.picture_as_pdf, color: cs.primary),
              title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${date.toLocal()} — ${sizeKb} KB', maxLines: 1),
              onTap: () => _open(f.path),
              trailing: Wrap(
                spacing: 8,
                children: [
                  IconButton(
                    tooltip: 'Compartir',
                    icon: const Icon(Icons.share),
                    onPressed: () => _share(f.path),
                  ),
                  IconButton(
                    tooltip: 'Eliminar',
                    icon: const Icon(Icons.delete),
                    onPressed: () => _delete(f.path),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class AboutView extends StatelessWidget {
  const AboutView({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.picture_as_pdf, size: 96, color: cs.primary),
              const SizedBox(height: 16),
              Text(
                'Escáner — Fotos → PDF',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                'App desarrollada como proyecto final para la materia de Programación Móvil '
                'por María Fernanda Amador Salais y Alexis Yahir Villar Escorcia.\n\n'
                'Profesor: José Manuel Hernández Reyes.',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                'Versión 1.2.0',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: cs.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============== MODELOS/COMPONENTES ===============
class CapturedImage {
  final Uint8List bytes;
  final String? filename;
  CapturedImage({required this.bytes, this.filename});
}

class _ThumbTile extends StatelessWidget {
  final Uint8List bytes;
  final int index;
  final VoidCallback onRemove;
  final VoidCallback onRecrop;

  const _ThumbTile({
    required Key key,
    required this.bytes,
    required this.index,
    required this.onRemove,
    required this.onRecrop,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      key: key,
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.all(8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(bytes, width: 72, height: 72, fit: BoxFit.cover),
        ),
        title: Text('Foto ${index + 1}'),
        subtitle: const Text('Mantén presionado para arrastrar'),
        trailing: Wrap(
          spacing: 8,
          children: [
            IconButton(
              onPressed: onRecrop,
              icon: const Icon(Icons.crop),
              tooltip: 'Recortar de nuevo',
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.delete),
              tooltip: 'Eliminar',
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle),
            ),
          ],
        ),
      ),
    );
  }
}
