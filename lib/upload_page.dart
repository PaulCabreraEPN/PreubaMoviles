import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class VisitasPage extends StatefulWidget {
  const VisitasPage({super.key});

  @override
  State<VisitasPage> createState() => _VisitasPageState();
}

class _VisitasPageState extends State<VisitasPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _motivoController = TextEditingController();
  List<PlatformFile> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  Future<void> _logout(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> _checkAndRequestPermissions() async {
    final cameraStatus = await Permission.camera.status;
    final photosStatus = await Permission.photos.status;

    if (!cameraStatus.isGranted || !photosStatus.isGranted) {
      final result = await [Permission.camera, Permission.photos].request();

      if (result[Permission.camera] != PermissionStatus.granted ||
          result[Permission.photos] != PermissionStatus.granted) {
        throw 'Permisos de cámara y galería no concedidos';
      }
    }
  }

  Future<void> _showImageSourceDialog(BuildContext context) async {
    try {
      await _checkAndRequestPermissions();

      final result = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text('Seleccionar fuente de imagen'),
          content: const Text('¿Cómo deseas agregar las imágenes?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, ImageSource.camera),
              child: const Text('Tomar foto'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ImageSource.gallery),
              child: const Text('Elegir de galería'),
            ),
          ],
        ),
      );

      if (result != null) {
        await _pickImages(result);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _pickImages(ImageSource source) async {
    try {
      final List<XFile> pickedFiles = [];

      if (source == ImageSource.gallery) {
        pickedFiles.addAll(
          await _picker.pickMultiImage(
            maxWidth: 1800,
            maxHeight: 1800,
            imageQuality: 90,
          ),
        );
      } else {
        final XFile? image = await _picker.pickImage(
          source: source,
          maxWidth: 1800,
          maxHeight: 1800,
          imageQuality: 90,
        );
        if (image != null) {
          pickedFiles.add(image);
        }
      }

      if (pickedFiles.isNotEmpty) {
        final List<PlatformFile> platformFiles = [];

        for (final xfile in pickedFiles.take(5)) {
          final file = File(xfile.path);
          final bytes = await file.readAsBytes();

          platformFiles.add(
            PlatformFile(
              name: xfile.name,
              size: bytes.length,
              bytes: bytes,
              path: xfile.path,
            ),
          );
        }

        setState(() {
          _selectedImages = platformFiles;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_selectedImages.length} imagen(es) seleccionada(s)',
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al seleccionar imágenes: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _registrarVisita() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final supabase = Supabase.instance.client;
    final nombre = _nombreController.text.trim();
    final motivo = _motivoController.text.trim();

    try {
      List<String> imagenesUrls = [];

      if (_selectedImages.isNotEmpty) {
        for (int i = 0; i < _selectedImages.length; i++) {
          final file = _selectedImages[i];
          final fileName =
              'visita_${DateTime.now().millisecondsSinceEpoch}_$i.${file.extension}';
          await supabase.storage
              .from('uploads')
              .uploadBinary(fileName, file.bytes!);
          imagenesUrls.add(fileName);
        }
      }

      await supabase.from('visitas').insert({
        'nombre_visitante': nombre,
        'motivo_visita': motivo,
        'hora_visita': DateTime.now().toIso8601String(),
        'fotos': imagenesUrls.isNotEmpty ? imagenesUrls : null,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Visita registrada exitosamente'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );

      setState(() {
        _nombreController.clear();
        _motivoController.clear();
        _selectedImages = [];
      });

      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al registrar visita: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddVisitaDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Nueva Visita',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nombreController,
                  decoration: InputDecoration(
                    labelText: 'Nombre del visitante',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: Icon(
                      Icons.person_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.surfaceVariant.withOpacity(0.5),
                  ),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Campo requerido' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _motivoController,
                  decoration: InputDecoration(
                    labelText: 'Motivo de la visita',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: Icon(
                      Icons.description_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.surfaceVariant.withOpacity(0.5),
                  ),
                  maxLines: 3,
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Campo requerido' : null,
                ),
                const SizedBox(height: 24),
                Text(
                  'Fotos (opcional)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _showImageSourceDialog(context),
                  icon: Icon(
                    Icons.camera_alt_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  label: Text(
                    'Agregar fotos',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                if (_selectedImages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final image in _selectedImages)
                          Chip(
                            label: Text(image.name),
                            deleteIcon: const Icon(Icons.close),
                            onDeleted: () {
                              setState(() {
                                _selectedImages.remove(image);
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              if (_formKey.currentState!.validate()) {
                                _registrarVisita();
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Registrar Visita'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de Visitas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => _logout(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddVisitaDialog,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 4,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: Supabase.instance.client
            .from('visitas')
            .select()
            .order('hora_visita', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_alt_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No hay visitas registradas',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            );
          }

          final visitas = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: visitas.length,
            itemBuilder: (context, index) {
              final visita = visitas[index];
              final fotos = visita['fotos'] as List<dynamic>? ?? [];
              final horaVisita = visita['hora_visita'] != null
                  ? DateTime.parse(visita['hora_visita'] as String).toLocal()
                  : null;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.person_pin,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              visita['nombre_visitante'] ??
                                  'Visitante sin nombre',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 20,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              visita['motivo_visita'] ??
                                  'Sin motivo especificado',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (horaVisita != null)
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 20,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${horaVisita.day}/${horaVisita.month}/${horaVisita.year} - ${horaVisita.hour}:${horaVisita.minute.toString().padLeft(2, '0')}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                  ),
                            ),
                          ],
                        ),
                      if (fotos.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 180,
                          child: PageView.builder(
                            itemCount: fotos.length,
                            controller: PageController(viewportFraction: 0.9),
                            itemBuilder: (context, imgIdx) {
                              final url = Supabase.instance.client.storage
                                  .from('uploads')
                                  .getPublicUrl(fotos[imgIdx]);
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    loadingBuilder:
                                        (context, child, loadingProgress) {
                                          if (loadingProgress == null)
                                            return child;
                                          return Center(
                                            child: CircularProgressIndicator(
                                              value:
                                                  loadingProgress
                                                          .expectedTotalBytes !=
                                                      null
                                                  ? loadingProgress
                                                            .cumulativeBytesLoaded /
                                                        loadingProgress
                                                            .expectedTotalBytes!
                                                  : null,
                                            ),
                                          );
                                        },
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Container(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.surfaceVariant,
                                              child: Center(
                                                child: Icon(
                                                  Icons.broken_image,
                                                  size: 48,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.outline,
                                                ),
                                              ),
                                            ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
