import 'package:flutter/material.dart';

import '../../core/call_ringtone_service.dart';

class RingtoneSettingsSheet extends StatefulWidget {
  const RingtoneSettingsSheet({super.key});

  @override
  State<RingtoneSettingsSheet> createState() => _RingtoneSettingsSheetState();
}

class _RingtoneSettingsSheetState extends State<RingtoneSettingsSheet> {
  final _service = CallRingtoneService.instance;
  bool _loading = true;
  IncomingRingtone _selected = IncomingRingtone.defaultTone;
  IncomingRingtone? _previewing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _service.init();
    if (mounted) {
      setState(() {
        _selected = _service.selected;
        _loading = false;
      });
    }
  }

  Future<void> _select(IncomingRingtone ringtone) async {
    await _service.setIncomingRingtone(ringtone);
    if (mounted) setState(() => _selected = ringtone);
  }

  Future<void> _preview(IncomingRingtone ringtone) async {
    setState(() => _previewing = ringtone);
    await _service.preview(ringtone);
    if (mounted) setState(() => _previewing = null);
  }

  @override
  void dispose() {
    _service.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFDFF),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF201B4C).withValues(alpha: 0.18),
            blurRadius: 34,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: _loading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Incoming call ringtone',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Color(0xFF1B1B1B),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Choose the sound callers hear on this device.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Color(0xFF8A8A8A),
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 14),
                for (final ringtone in IncomingRingtone.values)
                  _RingtoneOption(
                    ringtone: ringtone,
                    selected: ringtone == _selected,
                    previewing: ringtone == _previewing,
                    onSelect: () => _select(ringtone),
                    onPreview: () => _preview(ringtone),
                  ),
              ],
            ),
    ),
  );
}

class _RingtoneOption extends StatelessWidget {
  const _RingtoneOption({
    required this.ringtone,
    required this.selected,
    required this.previewing,
    required this.onSelect,
    required this.onPreview,
  });

  final IncomingRingtone ringtone;
  final bool selected;
  final bool previewing;
  final VoidCallback onSelect;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: selected ? const Color(0xFFEFEAFF) : const Color(0xFFF6F6FA),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: selected ? const Color(0xFF9A8EFF) : Colors.transparent,
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onSelect,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: selected
                        ? const Color(0xFF5D4EF5)
                        : const Color(0xFF9A9AA5),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    ringtone.label,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Color(0xFF1B1B1B),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Play preview',
          onPressed: onPreview,
          icon: Icon(
            previewing
                ? Icons.volume_up_rounded
                : Icons.play_circle_outline_rounded,
          ),
          color: const Color(0xFF5D4EF5),
        ),
      ],
    ),
  );
}
