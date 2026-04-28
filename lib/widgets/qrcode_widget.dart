import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrCodeWidget extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onUpdateQr;
  final VoidCallback onCopyLink;
  final VoidCallback onUseDefault;
  final String qrData;

  const QrCodeWidget({
    super.key,
    required this.controller,
    required this.onUpdateQr,
    required this.onCopyLink,
    required this.onUseDefault,
    required this.qrData,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFE2E8F0),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120F172A),
                      blurRadius: 10,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: qrData,
                  size: 210,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  IconButton(
                    onPressed: onUpdateQr,
                    tooltip: 'Atualizar QR',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFE2E8F0),
                    ),
                    icon: const Icon(Icons.qr_code_2_rounded),
                  ),
                  IconButton(
                    onPressed: onCopyLink,
                    tooltip: 'Copiar link',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFE2E8F0),
                    ),
                    icon: const Icon(Icons.copy_rounded),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Mais opcoes',
                    onSelected: (value) {
                      if (value == 'default') {
                        onUseDefault();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem<String>(
                        value: 'default',
                        child: Text('Usar link padrao'),
                      ),
                    ],
                    child: const CircleAvatar(
                      radius: 19,
                      backgroundColor: Color(0xFFE2E8F0),
                      child: Icon(Icons.more_horiz_rounded),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 6),
            leading: const Icon(Icons.tune_rounded),
            title: const Text(
              'Configurar link do QR (opcional)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  hintText: 'Cole o link do APK (http/https)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: onUpdateQr,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Aplicar link'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
