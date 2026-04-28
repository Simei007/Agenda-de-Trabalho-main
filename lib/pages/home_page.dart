import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_constants.dart';
import '../data/ctb_articles.dart';
import '../models/day_record.dart';
import '../services/app_storage_service.dart';
import '../services/app_update_service.dart';
import '../services/ctb_catalog_service.dart';
import '../services/report_export_service.dart';
import '../utils/date_utils.dart';
import '../utils/workday_calculator.dart';
import '../widgets/interval_widget.dart';
import '../widgets/notes_fullscreen_widget.dart';
import '../widgets/photo_registry_widget.dart';
import '../widgets/qrcode_widget.dart';
import '../widgets/time_input.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const String _defaultApkInstallUrl = defaultApkInstallUrl;
  static const int _normalWorkMinutes = normalWorkMinutes;
  static final DateTime _firstAllowedDay = firstAllowedDay;
  static final DateTime _lastAllowedDay = lastAllowedDay;

  int _currentTabIndex = 0;

  DateTime selectedDay = DateTime.now();
  DateTime focusedDay = DateTime.now();
  DateTime rangeStart = DateTime.now();
  DateTime rangeEnd = DateTime.now();

  TimeOfDay? start;
  TimeOfDay? end;

  List<Map<String, TimeOfDay?>> intervals = [];
  List<Map<String, String>> _photos = [];
  final Map<String, DayRecord> _savedByDay = {};
  final TextEditingController _apkUrlController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final AppStorageService _storageService = AppStorageService();
  final AppUpdateService _appUpdateService = AppUpdateService();
  final CtbCatalogService _ctbCatalogService = CtbCatalogService();
  final ReportExportService _reportExportService = ReportExportService();
  final WorkdayCalculator _calculator = const WorkdayCalculator();
  String? _apkInstallUrl;
  bool _isLoading = true;
  String _installedVersion = '...';
  String? _latestVersion;
  String? _latestApkUrl;
  bool _isCheckingForUpdate = false;
  bool _isUpdateAvailable = false;
  String? _updateErrorMessage;
  List<CtbArticle> _ctbArticles = fallbackCtbArticles;
  bool _isLoadingCtbArticles = false;
  String? _ctbStatusMessage;
  bool _isExportingRangeXlsx = false;
  Timer? _notesPersistDebounce;

  @override
  void initState() {
    super.initState();
    final initial = _dateOnly(DateTime.now());
    selectedDay = initial;
    focusedDay = initial;
    rangeStart = initial;
    rangeEnd = initial;
    _loadSavedData();
  }

  @override
  void dispose() {
    final pendingRecord = _currentDayRecord();
    final pendingKey = _dayKey(selectedDay);
    _notesPersistDebounce?.cancel();
    unawaited(
      _storageService.saveDayRecord(
        pendingKey,
        pendingRecord.isEmpty ? null : pendingRecord,
      ),
    );
    _apkUrlController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Duration calculateWorkedTime() {
    return _calculator.workedDurationForRecord(_currentDayRecord());
  }

  DayRecord _currentDayRecord() {
    return DayRecord(
      start: start,
      end: end,
      intervals: intervals.map(WorkInterval.fromLegacyMap).toList(),
      photos: _photos.map(RecordedPhoto.fromLegacyMap).toList(),
      notes: _notesController.text,
    );
  }

  String _dayKey(DateTime day) {
    return dayKey(day);
  }

  DateTime _dateOnly(DateTime day) {
    return dateOnly(day);
  }

  void _cacheDayRecord(String key, DayRecord record) {
    if (record.isEmpty) {
      _savedByDay.remove(key);
      return;
    }
    _savedByDay[key] = record;
  }

  Future<void> _persistDayRecord(String key, DayRecord record) {
    _cacheDayRecord(key, record);
    return _storageService.saveDayRecord(
      key,
      record.isEmpty ? null : record,
    );
  }

  Future<void> _saveCurrentDay({bool cancelPending = true}) {
    if (cancelPending) {
      _notesPersistDebounce?.cancel();
    }
    final key = _dayKey(selectedDay);
    return _persistDayRecord(key, _currentDayRecord());
  }

  void _scheduleCurrentDayPersist() {
    final key = _dayKey(selectedDay);
    final record = _currentDayRecord();
    _cacheDayRecord(key, record);
    _notesPersistDebounce?.cancel();
    _notesPersistDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(
        _storageService.saveDayRecord(
          key,
          record.isEmpty ? null : record,
        ),
      );
    });
  }

  Future<void> _loadSavedData() async {
    final loaded = await _storageService.loadAppData();
    if (!mounted) return;

    setState(() {
      _savedByDay
        ..clear()
        ..addAll(loaded.savedByDay);
      _apkInstallUrl = loaded.apkInstallUrl;
      _apkUrlController.text = loaded.apkInstallUrl;
      _loadDayDataIntoState(selectedDay);
      _isLoading = false;
    });

    unawaited(_loadVersionAndCheckForUpdates());
    unawaited(_loadCtbArticles());
  }

  void _loadDayDataIntoState(DateTime day) {
    final dayData = _savedByDay[_dayKey(day)];
    if (dayData == null) {
      start = null;
      end = null;
      intervals = [];
      _photos = [];
      _notesController.text = '';
      return;
    }

    start = dayData.start;
    end = dayData.end;
    intervals = dayData.toLegacyIntervals();
    _photos = dayData.toLegacyPhotos();
    _notesController.text = dayData.notes;
  }

  Future<void> _saveInstallLink() async {
    final value = _apkUrlController.text.trim();
    if (!_storageService.isValidInstallUrl(value)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe um link valido (http/https) para o APK.'),
        ),
      );
      return;
    }

    await _storageService.saveInstallLink(value);

    if (!mounted) return;
    setState(() {
      _apkInstallUrl = value;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('QR Code atualizado com o link informado.'),
      ),
    );
  }

  Future<void> _copyInstallLink() async {
    if (_apkInstallUrl == null || _apkInstallUrl!.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _apkInstallUrl!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copiado para a area de transferencia.'),
      ),
    );
  }

  Future<void> _useDefaultInstallLink() async {
    await _storageService.saveInstallLink(_defaultApkInstallUrl);
    if (!mounted) return;
    setState(() {
      _apkInstallUrl = _defaultApkInstallUrl;
      _apkUrlController.text = _defaultApkInstallUrl;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link padrao do GitHub aplicado ao QR Code.'),
      ),
    );
  }

  Future<void> _copyBackupToClipboard() async {
    await _saveCurrentDay();
    final serialized = await _storageService.buildBackupJson(
      savedByDay: _savedByDay,
      installUrl: _apkInstallUrl ?? _defaultApkInstallUrl,
    );
    await Clipboard.setData(ClipboardData(text: serialized));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Backup copiado. Guarde esse texto em local seguro.'),
      ),
    );
  }

  Future<void> _openRestoreBackupDialog() async {
    final controller = TextEditingController();
    final backupText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurar backup'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 14,
            decoration: const InputDecoration(
              hintText: 'Cole aqui o JSON do backup',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (backupText == null || backupText.isEmpty || !mounted) return;

    final confirmed = await _confirmAction(
      title: 'Confirmar restauracao',
      message: 'A restauracao substitui os dados atuais. Deseja continuar?',
      confirmLabel: 'Restaurar',
    );
    if (!confirmed || !mounted) return;

    try {
      await _saveCurrentDay();
      final restored = await _storageService.restoreBackup(backupText);
      await _storageService.saveInstallLink(restored.apkInstallUrl);
      await _storageService.replaceAllDays(restored.savedByDay);

      if (!mounted) return;
      setState(() {
        _savedByDay
          ..clear()
          ..addAll(restored.savedByDay);
        _apkInstallUrl = restored.apkInstallUrl;
        _apkUrlController.text = restored.apkInstallUrl;
        _loadDayDataIntoState(selectedDay);
      });

      if (!mounted) return;
      final restoredMessage = restored.embeddedPhotosRestored > 0
          ? 'Backup restaurado com ${restored.savedByDay.length} dia(s) e '
              '${restored.embeddedPhotosRestored} foto(s) incorporada(s).'
          : 'Backup restaurado com ${restored.savedByDay.length} dia(s).';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(restoredMessage),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Backup invalido. Verifique o texto e tente novamente.'),
        ),
      );
    }
  }

  Future<void> _loadCtbArticles() async {
    if (_isLoadingCtbArticles) return;

    setState(() {
      _isLoadingCtbArticles = true;
      _ctbStatusMessage = null;
    });

    try {
      final result = await _ctbCatalogService.loadArticles();
      if (!mounted) return;
      setState(() {
        _ctbArticles = result.articles;
        _ctbStatusMessage = result.statusMessage;
        _isLoadingCtbArticles = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ctbStatusMessage = 'Nao foi possivel atualizar a base do CTB agora.';
        _isLoadingCtbArticles = false;
      });
    }
  }

  Future<void> _loadVersionAndCheckForUpdates() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _installedVersion = packageInfo.version;
      });
      await _checkForUpdates();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _updateErrorMessage = 'Nao foi possivel verificar atualizacoes agora.';
      });
    }
  }

  Future<void> _checkForUpdates({
    bool userInitiated = false,
    bool openDownloadIfAvailable = false,
  }) async {
    if (_isCheckingForUpdate) return;

    setState(() {
      _isCheckingForUpdate = true;
      _updateErrorMessage = null;
    });

    try {
      final release = await _appUpdateService.fetchLatestRelease(
        fallbackApkUrl: _apkInstallUrl ?? _defaultApkInstallUrl,
      );
      final hasUpdate =
          _appUpdateService.compareVersions(_installedVersion, release.version) < 0;

      if (!mounted) return;
      setState(() {
        _latestVersion = release.version;
        _latestApkUrl = release.apkUrl;
        _isUpdateAvailable = hasUpdate;
      });

      if (userInitiated && mounted && !hasUpdate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voce ja esta na versao mais recente.'),
          ),
        );
      }

      if (userInitiated && hasUpdate && openDownloadIfAvailable && mounted) {
        await _openUpdateDownloadLink(overrideLink: release.apkUrl);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _updateErrorMessage = 'Nao foi possivel verificar atualizacoes agora.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingForUpdate = false;
        });
      }
    }
  }

  Future<void> _openUpdateDownloadLink({String? overrideLink}) async {
    final link =
        overrideLink ?? _latestApkUrl ?? _apkInstallUrl ?? _defaultApkInstallUrl;
    final uri = Uri.tryParse(link);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link de atualizacao invalido.')),
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      await Clipboard.setData(ClipboardData(text: link));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Nao abriu automatico. Link copiado para a area de transferencia.'),
        ),
      );
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    String confirmLabel = 'Excluir',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteFileSafe(String path) async {
    if (path.trim().isEmpty) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _takePhoto() async {
    try {
      final captured = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 90,
      );
      if (captured == null) return;

      final photosDir = await getApplicationDocumentsDirectory();
      final targetDir = Directory(
        '${photosDir.path}${Platform.pathSeparator}agenda_fotos',
      );
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final now = DateTime.now();
      final extension =
          captured.path.toLowerCase().endsWith('.png') ? '.png' : '.jpg';
      final targetPath =
          '${targetDir.path}${Platform.pathSeparator}foto_${now.microsecondsSinceEpoch}$extension';

      await File(captured.path).copy(targetPath);

      if (!mounted) return;
      setState(() {
        _photos.insert(0, {
          'path': targetPath,
          'capturedAt': now.toIso8601String(),
        });
      });
      unawaited(_saveCurrentDay());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto registrada com sucesso.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel abrir a camera neste momento.'),
        ),
      );
    }
  }

  Future<void> _deletePhotoAt(int index) async {
    if (index < 0 || index >= _photos.length) return;

    final confirmed = await _confirmAction(
      title: 'Excluir foto',
      message: 'Deseja excluir esta foto do registro?',
    );
    if (!confirmed || !mounted) return;

    final removed = _photos[index];
    setState(() {
      _photos.removeAt(index);
    });
    await _saveCurrentDay();
    await _deleteFileSafe(removed['path'] ?? '');
  }

  Future<void> _deleteAllPhotos() async {
    if (_photos.isEmpty) return;

    final confirmed = await _confirmAction(
      title: 'Excluir todas as fotos',
      message: 'Deseja remover todas as fotos do dia selecionado?',
    );
    if (!confirmed || !mounted) return;

    final paths = _photos.map((p) => p['path'] ?? '').toList();
    setState(() {
      _photos.clear();
    });
    await _saveCurrentDay();

    for (final path in paths) {
      await _deleteFileSafe(path);
    }
  }

  void _onNotesChanged(String value) {
    _scheduleCurrentDayPersist();
  }

  Future<void> _deleteNotes() async {
    if (_notesController.text.trim().isEmpty) return;
    final confirmed = await _confirmAction(
      title: 'Excluir anotacoes',
      message: 'Deseja apagar todas as anotacoes do dia selecionado?',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _notesController.clear();
    });
    await _saveCurrentDay();
  }

  Color _weekdayColor(int weekday) {
    if (weekday == DateTime.sunday) return const Color(0xFFE53935);
    if (weekday == DateTime.saturday) return const Color(0xFF1D4ED8);
    return const Color(0xFF334155);
  }

  String _weekdayLabel(DateTime day) {
    switch (day.weekday) {
      case DateTime.monday:
        return 'Seg';
      case DateTime.tuesday:
        return 'Ter';
      case DateTime.wednesday:
        return 'Qua';
      case DateTime.thursday:
        return 'Qui';
      case DateTime.friday:
        return 'Sex';
      case DateTime.saturday:
        return 'Sab';
      default:
        return 'Dom';
    }
  }

  String _monthLabel(DateTime day) {
    const months = <String>[
      'Janeiro',
      'Fevereiro',
      'Marco',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    return '${months[day.month - 1]} ${day.year}';
  }

  Widget _dayCell({
    required DateTime day,
    required Color backgroundColor,
    required Color borderColor,
    Color? textColor,
  }) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        '${day.day}',
        style: TextStyle(
          color: textColor ?? _weekdayColor(day.weekday),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF1D4ED8)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  String _minutesLabel(int totalMinutes) {
    final safe = totalMinutes < 0 ? 0 : totalMinutes;
    final hours = safe ~/ 60;
    final minutes = safe % 60;
    return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
  }

  String _workedLabel(Duration worked) {
    return _minutesLabel(worked.inMinutes);
  }

  String _signedMinutesLabel(int totalMinutes) {
    final sign = totalMinutes >= 0 ? '+' : '-';
    final absValue = totalMinutes.abs();
    return '$sign ${_minutesLabel(absValue)}';
  }

  String _dateLabel(DateTime day) {
    final d = day.day.toString().padLeft(2, '0');
    final m = day.month.toString().padLeft(2, '0');
    final y = day.year.toString().padLeft(4, '0');
    return '$d/$m/$y';
  }

  CtbArticle _ctbArticleOfTheDay(DateTime day) {
    final base = _ctbArticles.isNotEmpty ? _ctbArticles : fallbackCtbArticles;
    final safeDay = _dateOnly(day);
    final reference = DateTime(2020, 1, 1);
    final dayOffset = safeDay.difference(reference).inDays;
    final index = dayOffset % base.length;
    return base[index];
  }

  Future<void> _openCtbOfficialSource() async {
    final uri = Uri.parse(ctbOfficialUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      await Clipboard.setData(const ClipboardData(text: ctbOfficialUrl));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nao abriu automaticamente. Link oficial do CTB copiado.',
          ),
        ),
      );
    }
  }

  Future<void> _openCtbArticle(CtbArticle article) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.9,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.number,
                    style: const TextStyle(
                      color: Color(0xFF92400E),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    article.title,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEFCE8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          article.fullText,
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _openCtbOfficialSource();
                          },
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('Fonte oficial'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Fechar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _ctbArticleBanner(DateTime day) {
    final article = _ctbArticleOfTheDay(day);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF59E0B)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1AF59E0B),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFFDE68A),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.gavel_rounded,
                  color: Color(0xFF92400E),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Codigo de Transito Brasileiro',
                      style: TextStyle(
                        color: Color(0xFF78350F),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Artigo do dia - ${_dateLabel(day)}',
                      style: const TextStyle(
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${article.number} - ${article.title}',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            article.summary,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isLoadingCtbArticles
                ? 'Atualizando base oficial do CTB...'
                : _ctbStatusMessage ??
                    'Base ativa: ${_ctbArticles.length} artigos do CTB.',
            style: TextStyle(
              color: _isLoadingCtbArticles
                  ? const Color(0xFF92400E)
                  : const Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => _openCtbArticle(article),
            icon: const Icon(Icons.menu_book_rounded),
            label: const Text('Ler artigo completo'),
          ),
        ],
      ),
    );
  }

  Future<File?> _exportRangeXlsx({
    bool showSuccessMessage = true,
  }) async {
    if (_isExportingRangeXlsx) return null;

    setState(() {
      _isExportingRangeXlsx = true;
    });

    try {
      await _saveCurrentDay();
      final file = await _reportExportService.buildRangeXlsxFile(
        records: _savedByDay,
        startDay: rangeStart,
        endDay: rangeEnd,
      );

      if (showSuccessMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('XLSX salvo em: ${file.path}'),
            action: SnackBarAction(
              label: 'Copiar caminho',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: file.path));
              },
            ),
          ),
        );
      }
      return file;
    } catch (error) {
      var message = 'Nao foi possivel gerar o arquivo XLSX agora.';
      if (error is StateError) {
        final stateMessage = error.message.toString().trim();
        if (stateMessage.isNotEmpty) {
          message = stateMessage;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isExportingRangeXlsx = false;
        });
      }
    }
  }

  Future<void> _shareRangeXlsx() async {
    final generated = await _exportRangeXlsx(showSuccessMessage: false);
    if (generated == null) return;

    try {
      await Share.shareXFiles(
        [XFile(generated.path)],
        subject:
            'Relatorio de jornada ${_dateLabel(rangeStart)} ate ${_dateLabel(rangeEnd)}',
        text:
            'Segue o relatorio de jornada em Excel (${_dateLabel(rangeStart)} ate ${_dateLabel(rangeEnd)}).',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Arquivo criado em ${generated.path}, mas nao foi possivel abrir o compartilhamento.',
          ),
        ),
      );
    }
  }

  Future<void> _pickRangeStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOnly(rangeStart),
      firstDate: _firstAllowedDay,
      lastDate: _lastAllowedDay,
    );
    if (picked == null || !mounted) return;

    setState(() {
      rangeStart = _dateOnly(picked);
      if (rangeStart.isAfter(rangeEnd)) {
        rangeEnd = rangeStart;
      }
    });
  }

  Future<void> _pickRangeEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOnly(rangeEnd),
      firstDate: _firstAllowedDay,
      lastDate: _lastAllowedDay,
    );
    if (picked == null || !mounted) return;

    setState(() {
      rangeEnd = _dateOnly(picked);
      if (rangeEnd.isBefore(rangeStart)) {
        rangeStart = rangeEnd;
      }
    });
  }

  String _tabTitle() {
    switch (_currentTabIndex) {
      case 0:
        return 'Calendario';
      case 1:
        return 'Jornada';
      case 2:
        return 'Consumo';
      case 3:
        return 'Intervalos';
      case 4:
        return 'Instalar';
      case 5:
        return 'Fotos';
      default:
        return 'Anotacoes';
    }
  }

  Widget _quickSummaryMetric({
    required String title,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x29FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFDBEAFE),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final currentRecord = _currentDayRecord();
    final worked = calculateWorkedTime();
    final workedMinutes = worked.inMinutes;
    final extraMinutes = workedMinutes > _normalWorkMinutes
        ? workedMinutes - _normalWorkMinutes
        : 0;
    final balanceMinutes = workedMinutes - _normalWorkMinutes;
    final nightWorkedMinutes =
        _calculator.nightWorkedMinutesForRecord(selectedDay, currentRecord);
    final monthSummary = _calculator.monthSummary(_savedByDay, selectedDay);
    final monthWorkedMinutes = monthSummary.worked;
    final monthExtraMinutes = monthSummary.extra;
    final monthBalanceMinutes = monthSummary.balance;
    final monthNightMinutes = monthSummary.night;
    final rangeSummary = _calculator.rangeSummary(_savedByDay, rangeStart, rangeEnd);
    final rangeExtraMinutes = rangeSummary.extra;
    final rangeBalanceMinutes = rangeSummary.balance;
    final rangeWorkedMinutes = rangeSummary.worked;
    final rangeNightMinutes = rangeSummary.night;
    final rangeDaysWithData = rangeSummary.days;
    final canExportRangeXlsx =
        rangeDaysWithData > 0 && !_isExportingRangeXlsx;

    return Scaffold(
      appBar: AppBar(
        title: Text(_tabTitle()),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF0F172A),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF8FBFF), Color(0xFFEFF5FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: (_currentTabIndex == 5 || _currentTabIndex == 6)
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: _currentTabIndex == 5
                      ? PhotoRegistryWidget(
                          selectedDayLabel: _dateLabel(selectedDay),
                          photos: _photos,
                          onTakePhoto: _takePhoto,
                          onDeleteAllPhotos: _deleteAllPhotos,
                          onDeletePhoto: _deletePhotoAt,
                        )
                      : NotesFullscreenWidget(
                          controller: _notesController,
                          onChanged: _onNotesChanged,
                          onDeleteNotes: _deleteNotes,
                          selectedDayLabel: _dateLabel(selectedDay),
                        ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_currentTabIndex == 0)
                        _sectionCard(
                          title: 'Calendario',
                          icon: Icons.calendar_month_rounded,
                          child: TableCalendar(
                            focusedDay: focusedDay,
                            firstDay: _firstAllowedDay,
                            lastDay: _lastAllowedDay,
                            selectedDayPredicate: (day) =>
                                isSameDay(day, selectedDay),
                            startingDayOfWeek: StartingDayOfWeek.sunday,
                            calendarFormat: CalendarFormat.month,
                            availableCalendarFormats: const {
                              CalendarFormat.month: 'Mes'
                            },
                            daysOfWeekHeight: 44,
                            rowHeight: 50,
                            onDaySelected: (selected, focused) {
                              setState(() {
                                selectedDay = selected;
                                focusedDay = focused;
                                _loadDayDataIntoState(selectedDay);
                              });
                            },
                            onPageChanged: (focused) => focusedDay = focused,
                            headerStyle: const HeaderStyle(
                              titleCentered: true,
                              formatButtonVisible: false,
                              leftChevronIcon: Icon(
                                Icons.chevron_left_rounded,
                                color: Color(0xFF1F2A44),
                              ),
                              rightChevronIcon: Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFF1F2A44),
                              ),
                            ),
                            calendarStyle: const CalendarStyle(
                              outsideDaysVisible: false,
                              cellMargin: EdgeInsets.all(3),
                            ),
                            calendarBuilders: CalendarBuilders(
                              headerTitleBuilder: (context, day) {
                                return Text(
                                  _monthLabel(day),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                );
                              },
                              dowBuilder: (context, day) {
                                return Center(
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 2),
                                    child: Text(
                                      _weekdayLabel(day),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: _weekdayColor(day.weekday),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                );
                              },
                              defaultBuilder: (context, day, focused) {
                                return _dayCell(
                                  day: day,
                                  backgroundColor: Colors.white,
                                  borderColor: const Color(0xFFE2E8F0),
                                );
                              },
                              todayBuilder: (context, day, focused) {
                                return _dayCell(
                                  day: day,
                                  backgroundColor: const Color(0xFFDBEAFE),
                                  borderColor: const Color(0xFF60A5FA),
                                  textColor: const Color(0xFF1E3A8A),
                                );
                              },
                              selectedBuilder: (context, day, focused) {
                                return Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF2563EB),
                                        Color(0xFF1D4ED8)
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x332563EB),
                                        blurRadius: 10,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    '${day.day}',
                                    style: TextStyle(
                                      color: day.weekday == DateTime.sunday
                                          ? const Color(0xFFFFD6D6)
                                          : day.weekday == DateTime.saturday
                                              ? const Color(0xFFDBEAFE)
                                              : Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      if (_currentTabIndex == 0)
                        _ctbArticleBanner(_dateOnly(DateTime.now())),
                      if (_currentTabIndex == 2)
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x1F0F172A),
                                blurRadius: 14,
                                offset: Offset(0, 7),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Resumo rapido - ${_dateLabel(selectedDay)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _quickSummaryMetric(
                                    title: 'Trabalhadas',
                                    value: _minutesLabel(workedMinutes),
                                    valueColor: Colors.white,
                                  ),
                                  _quickSummaryMetric(
                                    title: 'Extras',
                                    value: _minutesLabel(extraMinutes),
                                    valueColor: const Color(0xFF86EFAC),
                                  ),
                                  _quickSummaryMetric(
                                    title: 'Saldo',
                                    value: _signedMinutesLabel(balanceMinutes),
                                    valueColor: balanceMinutes >= 0
                                        ? const Color(0xFFBFDBFE)
                                        : const Color(0xFFFECACA),
                                  ),
                                  _quickSummaryMetric(
                                    title: 'Total mes',
                                    value: _minutesLabel(monthWorkedMinutes),
                                    valueColor: const Color(0xFFFDE68A),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      if (_currentTabIndex == 1)
                        _sectionCard(
                          title: 'Jornada',
                          icon: Icons.schedule_rounded,
                          child: Column(
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: const Color(0xFFE2E8F0)),
                                ),
                                child: Text(
                                  'Dia selecionado: ${_dateLabel(selectedDay)}',
                                  style: const TextStyle(
                                    color: Color(0xFF334155),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TimeInput(
                                label: 'Inicio',
                                value: start,
                                icon: Icons.login_rounded,
                                onSelected: (t) {
                                  setState(() => start = t);
                                  unawaited(_saveCurrentDay());
                                },
                                onClear: () {
                                  setState(() => start = null);
                                  unawaited(_saveCurrentDay());
                                },
                              ),
                              const SizedBox(height: 12),
                              TimeInput(
                                label: 'Fim',
                                value: end,
                                icon: Icons.logout_rounded,
                                onSelected: (t) {
                                  setState(() => end = t);
                                  unawaited(_saveCurrentDay());
                                },
                                onClear: () {
                                  setState(() => end = null);
                                  unawaited(_saveCurrentDay());
                                },
                              ),
                              const SizedBox(height: 10),
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Se o fim for menor que o inicio (ou igual), conta virada de dia.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() => _currentTabIndex = 3);
                                  },
                                  icon:
                                      const Icon(Icons.free_breakfast_outlined),
                                  label: const Text('Ir para Intervalos'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_currentTabIndex == 3)
                        _sectionCard(
                          title: 'Intervalos',
                          icon: Icons.free_breakfast_rounded,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Dia: ${_dateLabel(selectedDay)}',
                                      style: const TextStyle(
                                        color: Color(0xFF334155),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      setState(() => _currentTabIndex = 1);
                                    },
                                    icon: const Icon(Icons.schedule_outlined,
                                        size: 16),
                                    label: const Text('Jornada'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              if (intervals.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: const Text(
                                    'Nenhum intervalo adicionado.',
                                    style: TextStyle(color: Color(0xFF64748B)),
                                  ),
                                )
                              else
                                ...intervals.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  return IntervalWidget(
                                    key: ValueKey(
                                        '${_dayKey(selectedDay)}-$index'),
                                    initialStart: entry.value['start'],
                                    initialEnd: entry.value['end'],
                                    onChanged: (s, e) {
                                      setState(() {
                                        intervals[index] = {
                                          'start': s,
                                          'end': e
                                        };
                                      });
                                      unawaited(_saveCurrentDay());
                                    },
                                    onDelete: () {
                                      setState(() => intervals.removeAt(index));
                                      unawaited(_saveCurrentDay());
                                    },
                                  );
                                }),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.tonalIcon(
                                  onPressed: () {
                                    setState(() {
                                      intervals
                                          .add({'start': null, 'end': null});
                                    });
                                    unawaited(_saveCurrentDay());
                                  },
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('Adicionar intervalo'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_currentTabIndex == 4)
                        _sectionCard(
                          title: 'Atualizacao do app',
                          icon: Icons.system_update_alt_rounded,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Versao instalada: $_installedVersion',
                                style: const TextStyle(
                                  color: Color(0xFF334155),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (_latestVersion != null)
                                Text(
                                  'Ultima versao publicada: $_latestVersion',
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (_updateErrorMessage != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  _updateErrorMessage!,
                                  style: const TextStyle(
                                    color: Color(0xFFB91C1C),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    onPressed: _isCheckingForUpdate
                                        ? null
                                        : () => _checkForUpdates(
                                              userInitiated: true,
                                              openDownloadIfAvailable: true,
                                            ),
                                    icon: _isCheckingForUpdate
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.refresh_rounded),
                                    label: Text(
                                      _isCheckingForUpdate
                                          ? 'Verificando...'
                                          : 'Verificar e baixar',
                                    ),
                                  ),
                                  if (_isUpdateAvailable)
                                    FilledButton.tonalIcon(
                                      onPressed: _openUpdateDownloadLink,
                                      icon: const Icon(Icons.download_rounded),
                                      label: const Text('Baixar atualizacao'),
                                    ),
                                ],
                              ),
                              if (_latestVersion != null &&
                                  !_isCheckingForUpdate &&
                                  !_isUpdateAvailable &&
                                  _updateErrorMessage == null) ...[
                                const SizedBox(height: 10),
                                const Text(
                                  'Seu app ja esta atualizado.',
                                  style: TextStyle(
                                    color: Color(0xFF166534),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              if (_isUpdateAvailable) ...[
                                const SizedBox(height: 10),
                                const Text(
                                  'Uma nova versao foi encontrada. Toque em "Baixar atualizacao" para instalar por cima, sem desinstalar.',
                                  style: TextStyle(
                                    color: Color(0xFF1E3A8A),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      if (_currentTabIndex == 4)
                        _sectionCard(
                          title: 'Backup e restauracao',
                          icon: Icons.backup_rounded,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Copie o backup e salve em local seguro (Drive, e-mail, bloco de notas).',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    onPressed: _copyBackupToClipboard,
                                    icon: const Icon(Icons.copy_all_rounded),
                                    label: const Text('Copiar backup'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _openRestoreBackupDialog,
                                    icon: const Icon(Icons.restore_rounded),
                                    label: const Text('Restaurar backup'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      if (_currentTabIndex == 4)
                        _sectionCard(
                          title: 'Instalar em outro aparelho',
                          icon: Icons.qr_code_rounded,
                          child: QrCodeWidget(
                            controller: _apkUrlController,
                            onUpdateQr: _saveInstallLink,
                            onCopyLink: _copyInstallLink,
                            onUseDefault: _useDefaultInstallLink,
                            qrData: _apkInstallUrl ?? _defaultApkInstallUrl,
                          ),
                        ),
                      if (_currentTabIndex == 2)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x1F0F172A),
                                blurRadius: 14,
                                offset: Offset(0, 7),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF1E293B),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.timer_outlined,
                                  color: Color(0xFFBFDBFE),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Horas trabalhadas no dia',
                                      style: TextStyle(
                                        color: Color(0xFFCBD5E1),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _workedLabel(worked),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Carga normal: ${_minutesLabel(_normalWorkMinutes)}',
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Horas extras: ${_minutesLabel(extraMinutes)}',
                                      style: const TextStyle(
                                        color: Color(0xFF86EFAC),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Saldo do dia: ${_signedMinutesLabel(balanceMinutes)}',
                                      style: TextStyle(
                                        color: balanceMinutes >= 0
                                            ? const Color(0xFFBFDBFE)
                                            : const Color(0xFFFECACA),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Adicional noturno (22h-5h): ${_minutesLabel(nightWorkedMinutes)}',
                                      style: const TextStyle(
                                        color: Color(0xFF93C5FD),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Extras no mes: ${_minutesLabel(monthExtraMinutes)}',
                                      style: const TextStyle(
                                        color: Color(0xFFFDE68A),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Saldo do mes: ${_signedMinutesLabel(monthBalanceMinutes)}',
                                      style: TextStyle(
                                        color: monthBalanceMinutes >= 0
                                            ? const Color(0xFFBBF7D0)
                                            : const Color(0xFFFECACA),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Noturno no mes: ${_minutesLabel(monthNightMinutes)}',
                                      style: const TextStyle(
                                        color: Color(0xFF93C5FD),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E293B),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: const Color(0xFF334155),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Periodo personalizado',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  onPressed: _pickRangeStart,
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        const Color(0xFFBFDBFE),
                                                    side: const BorderSide(
                                                      color: Color(0xFF475569),
                                                    ),
                                                  ),
                                                  icon: const Icon(Icons.event),
                                                  label: Text(
                                                    'De ${_dateLabel(rangeStart)}',
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  onPressed: _pickRangeEnd,
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        const Color(0xFFBFDBFE),
                                                    side: const BorderSide(
                                                      color: Color(0xFF475569),
                                                    ),
                                                  ),
                                                  icon: const Icon(
                                                      Icons.event_available),
                                                  label: Text(
                                                    'Ate ${_dateLabel(rangeEnd)}',
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Dias com registro: $rangeDaysWithData',
                                            style: const TextStyle(
                                              color: Color(0xFF94A3B8),
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Trabalhadas no periodo: ${_minutesLabel(rangeWorkedMinutes)}',
                                            style: const TextStyle(
                                              color: Color(0xFFE2E8F0),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Extras no periodo: ${_minutesLabel(rangeExtraMinutes)}',
                                            style: const TextStyle(
                                              color: Color(0xFFFDE68A),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Saldo do periodo: ${_signedMinutesLabel(rangeBalanceMinutes)}',
                                            style: TextStyle(
                                              color: rangeBalanceMinutes >= 0
                                                  ? const Color(0xFFBBF7D0)
                                                  : const Color(0xFFFECACA),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Noturno no periodo: ${_minutesLabel(rangeNightMinutes)}',
                                            style: const TextStyle(
                                              color: Color(0xFF93C5FD),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              FilledButton.icon(
                                                onPressed: canExportRangeXlsx
                                                    ? () => _exportRangeXlsx()
                                                    : null,
                                                icon: _isExportingRangeXlsx
                                                    ? const SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                      )
                                                    : const Icon(
                                                        Icons.download_rounded,
                                                      ),
                                                label: Text(
                                                  _isExportingRangeXlsx
                                                      ? 'Gerando...'
                                                      : 'Baixar XLSX',
                                                ),
                                              ),
                                              OutlinedButton.icon(
                                                onPressed: canExportRangeXlsx
                                                    ? () => _shareRangeXlsx()
                                                    : null,
                                                style:
                                                    OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      const Color(0xFFBFDBFE),
                                                  side: const BorderSide(
                                                    color: Color(0xFF475569),
                                                  ),
                                                ),
                                                icon: const Icon(
                                                  Icons.share_rounded,
                                                ),
                                                label: const Text(
                                                  'Compartilhar',
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (rangeDaysWithData == 0) ...[
                                            const SizedBox(height: 6),
                                            const Text(
                                              'Defina um periodo com registros para habilitar a exportacao.',
                                              style: TextStyle(
                                                color: Color(0xFF94A3B8),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 76,
          backgroundColor: Colors.black,
          indicatorColor: const Color(0xFF1F2937),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(
                color: Color(0xFFE2E8F0),
                size: 32,
              );
            }
            return const IconThemeData(
              color: Color(0xFF6B7280),
              size: 30,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _currentTabIndex,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
          onDestinationSelected: (index) {
            setState(() => _currentTabIndex = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'Calendario',
            ),
            NavigationDestination(
              icon: Icon(Icons.schedule_outlined),
              selectedIcon: Icon(Icons.schedule),
              label: 'Jornada',
            ),
            NavigationDestination(
              icon: Icon(Icons.analytics_outlined),
              selectedIcon: Icon(Icons.analytics),
              label: 'Consumo',
            ),
            NavigationDestination(
              icon: Icon(Icons.free_breakfast_outlined),
              selectedIcon: Icon(Icons.free_breakfast),
              label: 'Intervalos',
            ),
            NavigationDestination(
              icon: Icon(Icons.qr_code_2_outlined),
              selectedIcon: Icon(Icons.qr_code_2),
              label: 'Instalar',
            ),
            NavigationDestination(
              icon: Icon(Icons.photo_camera_outlined),
              selectedIcon: Icon(Icons.photo_camera),
              label: 'Fotos',
            ),
            NavigationDestination(
              icon: Icon(Icons.notes_outlined),
              selectedIcon: Icon(Icons.notes),
              label: 'Anotacoes',
            ),
          ],
        ),
      ),
    );
  }
}
