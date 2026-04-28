import 'package:flutter/material.dart';

class TimeInput extends StatelessWidget {
  final String label;
  final TimeOfDay? value;
  final IconData icon;
  final ValueChanged<TimeOfDay> onSelected;
  final VoidCallback? onClear;

  const TimeInput({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onSelected,
    this.onClear,
  });

  String _formatTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pickTime(BuildContext context) async {
    final time = await showTimePicker(
      context: context,
      initialTime: value ?? TimeOfDay.now(),
    );
    if (time != null) onSelected(time);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _pickTime(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFDBEAFE),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: const Color(0xFF1D4ED8)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value == null ? 'Toque para selecionar' : _formatTime(value!),
                    style: TextStyle(
                      color: value == null
                          ? const Color(0xFF64748B)
                          : const Color(0xFF1E293B),
                      fontWeight: value == null ? FontWeight.w500 : FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: () => _pickTime(context),
              child: Text(value == null ? 'Selecionar' : 'Alterar'),
            ),
            if (value != null && onClear != null) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'Remover',
                child: IconButton.filledTonal(
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_outline_rounded),
                  style: IconButton.styleFrom(
                    foregroundColor: const Color(0xFFB91C1C),
                    backgroundColor: const Color(0xFFFEE2E2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
