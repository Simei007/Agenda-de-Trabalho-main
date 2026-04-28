import 'dart:io';

import 'package:flutter/material.dart';

class PhotoRegistryWidget extends StatelessWidget {
  final String selectedDayLabel;
  final List<Map<String, String>> photos;
  final Future<void> Function() onTakePhoto;
  final Future<void> Function() onDeleteAllPhotos;
  final Future<void> Function(int index) onDeletePhoto;

  const PhotoRegistryWidget({
    super.key,
    required this.selectedDayLabel,
    required this.photos,
    required this.onTakePhoto,
    required this.onDeleteAllPhotos,
    required this.onDeletePhoto,
  });

  String _watermarkLabel(String rawDate) {
    final parsed = DateTime.tryParse(rawDate)?.toLocal();
    if (parsed == null) return rawDate;
    final d = parsed.day.toString().padLeft(2, '0');
    final m = parsed.month.toString().padLeft(2, '0');
    final y = parsed.year.toString().padLeft(4, '0');
    final h = parsed.hour.toString().padLeft(2, '0');
    final min = parsed.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }

  void _openFullScreen(
    BuildContext context, {
    required String path,
    required String watermark,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PhotoPreviewPage(
          path: path,
          watermark: watermark,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140F172A),
                blurRadius: 16,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Registro de fotos',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Dia: $selectedDayLabel',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () {
                  onTakePhoto();
                },
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text('Tirar foto'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (photos.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () {
                onDeleteAllPhotos();
              },
              icon: const Icon(Icons.delete_sweep_rounded),
              label: const Text('Excluir todas'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB91C1C),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: photos.isEmpty
              ? Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Nenhuma foto registrada.\nUse "Tirar foto" para comecar.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                )
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: photos.length,
                  itemBuilder: (context, index) {
                    final photo = photos[index];
                    final path = photo['path'] ?? '';
                    final watermark =
                        _watermarkLabel(photo['capturedAt'] ?? '');
                    final file = File(path);
                    final exists = file.existsSync();

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Material(
                        color: Colors.white,
                        child: InkWell(
                          onTap: exists
                              ? () => _openFullScreen(
                                    context,
                                    path: path,
                                    watermark: watermark,
                                  )
                              : null,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (exists)
                                Image.file(file, fit: BoxFit.cover)
                              else
                                const ColoredBox(
                                  color: Color(0xFFF1F5F9),
                                  child: Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      size: 34,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: IconButton.filledTonal(
                                  onPressed: () {
                                    onDeletePhoto(index);
                                  },
                                  icon:
                                      const Icon(Icons.delete_outline_rounded),
                                  style: IconButton.styleFrom(
                                    foregroundColor: const Color(0xFFB91C1C),
                                    backgroundColor: const Color(0xFFFEE2E2),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 8,
                                right: 8,
                                bottom: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xB2000000),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    watermark,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PhotoPreviewPage extends StatelessWidget {
  final String path;
  final String watermark;

  const _PhotoPreviewPage({
    required this.path,
    required this.watermark,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final exists = file.existsSync();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Visualizacao'),
      ),
      body: Center(
        child: exists
            ? Stack(
                fit: StackFit.expand,
                children: [
                  InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5,
                    child: Center(
                      child: Image.file(
                        file,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xB2000000),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        watermark,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : const Text(
                'Arquivo de foto nao encontrado.',
                style: TextStyle(color: Colors.white70),
              ),
      ),
    );
  }
}
