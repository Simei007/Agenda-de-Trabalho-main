import 'package:flutter/material.dart';

class NotesFullscreenWidget extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onDeleteNotes;
  final String selectedDayLabel;

  const NotesFullscreenWidget({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onDeleteNotes,
    required this.selectedDayLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Anotacoes',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 20,
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
            OutlinedButton.icon(
              onPressed: () {
                onDeleteNotes();
              },
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Excluir'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB91C1C),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
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
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF0F172A),
                height: 1.35,
              ),
              decoration: const InputDecoration(
                hintText: 'Escreva suas anotacoes aqui...',
                border: InputBorder.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
