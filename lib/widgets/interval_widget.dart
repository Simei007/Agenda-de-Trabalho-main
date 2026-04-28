import 'package:flutter/material.dart';

class IntervalWidget extends StatefulWidget {
  final Function(TimeOfDay?, TimeOfDay?) onChanged;
  final VoidCallback onDelete;
  final TimeOfDay? initialStart;
  final TimeOfDay? initialEnd;

  const IntervalWidget({
    super.key,
    required this.onChanged,
    required this.onDelete,
    this.initialStart,
    this.initialEnd,
  });

  @override
  State<IntervalWidget> createState() => _IntervalWidgetState();
}

class _IntervalWidgetState extends State<IntervalWidget> {
  TimeOfDay? start;
  TimeOfDay? end;

  @override
  void initState() {
    super.initState();
    start = widget.initialStart;
    end = widget.initialEnd;
  }

  @override
  void didUpdateWidget(covariant IntervalWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStart != widget.initialStart ||
        oldWidget.initialEnd != widget.initialEnd) {
      setState(() {
        start = widget.initialStart;
        end = widget.initialEnd;
      });
    }
  }

  String _formatTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> pickStart() async {
    final t = await showTimePicker(
      context: context,
      initialTime: start ?? TimeOfDay.now(),
    );
    if (t != null) {
      setState(() => start = t);
      widget.onChanged(start, end);
    }
  }

  Future<void> pickEnd() async {
    final t = await showTimePicker(
      context: context,
      initialTime: end ?? TimeOfDay.now(),
    );
    if (t != null) {
      setState(() => end = t);
      widget.onChanged(start, end);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: pickStart,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0F172A),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              ),
              icon: const Icon(Icons.login_rounded, size: 16),
              label: Text(start == null ? 'Inicio' : _formatTime(start!)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: pickEnd,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0F172A),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              ),
              icon: const Icon(Icons.logout_rounded, size: 16),
              label: Text(end == null ? 'Fim' : _formatTime(end!)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }
}
