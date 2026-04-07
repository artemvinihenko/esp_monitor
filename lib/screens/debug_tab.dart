import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../services/work_manager_service.dart';

class DebugTab extends StatefulWidget {
  const DebugTab({super.key});

  @override
  State<DebugTab> createState() => _DebugTabState();
}

class _DebugTabState extends State<DebugTab> {
  List<String> _logs = [];
  bool _isLoading = true;
  bool _isWorkManagerRunning = false;
  int _pollingInterval = 15;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _checkWorkManagerStatus();
    _loadPollingInterval();
  }

  Future<void> _checkWorkManagerStatus() async {
    // Проверяем статус WorkManager
    final isScheduled = await WorkManagerService.isScheduled();
    setState(() {
      _isWorkManagerRunning = isScheduled;
    });
  }

  Future<void> _loadPollingInterval() async {
    final prefs = await SharedPreferences.getInstance();
    final interval = prefs.getInt('polling_interval') ?? 15;
    setState(() {
      _pollingInterval = interval;
    });
  }

  Future<void> _savePollingInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('polling_interval', minutes);
    await WorkManagerService.setPollingInterval(minutes);
    setState(() {
      _pollingInterval = minutes;
    });
  }

  Future<Directory> _getLogDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${appDir.path}/mqtt_logs');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }
    return logDir;
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final logDir = await _getLogDirectory();
      final today = DateTime.now().toString().substring(0, 10);
      final logFile = File('${logDir.path}/mqtt_service_$today.log');

      if (await logFile.exists()) {
        final lines = await logFile.readAsLines();
        setState(() {
          _logs = lines.length > 500 ? lines.sublist(lines.length - 500) : lines;
        });
      } else {
        setState(() {
          _logs = [];
        });
      }
    } catch (e) {
      debugPrint('Error loading logs: $e');
      setState(() {
        _logs = [];
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _clearLogs() async {
    try {
      final logDir = await _getLogDirectory();
      final today = DateTime.now().toString().substring(0, 10);
      final logFile = File('${logDir.path}/mqtt_service_$today.log');
      if (await logFile.exists()) {
        await logFile.writeAsString('');
      }
      setState(() {
        _logs = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Логи очищены')),
      );
    } catch (e) {
      debugPrint('Error clearing logs: $e');
    }
  }

  void _exportLogs() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Логи сервиса'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              _logs.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _logs.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Логи скопированы')),
              );
            },
            child: const Text('Копировать'),
          ),
        ],
      ),
    );
  }

  Future<void> _runNow() async {
    await WorkManagerService.runNow();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Запущен внеочередной опрос')),
    );
    // Обновляем логи через несколько секунд
    Future.delayed(const Duration(seconds: 10), () {
      _loadLogs();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Панель управления
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              const Text('Интервал:'),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _pollingInterval,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 мин')),
                  DropdownMenuItem(value: 5, child: Text('5 мин')),
                  DropdownMenuItem(value: 10, child: Text('10 мин')),
                  DropdownMenuItem(value: 15, child: Text('15 мин')),
                  DropdownMenuItem(value: 30, child: Text('30 мин')),
                  DropdownMenuItem(value: 60, child: Text('60 мин')),
                ],
                onChanged: (value) async {
                  if (value != null) {
                    await _savePollingInterval(value);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Интервал изменён на $value минут')),
                    );
                  }
                },
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.play_arrow, color: Colors.green),
                onPressed: _runNow,
                tooltip: 'Запустить сейчас',
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadLogs,
                tooltip: 'Обновить логи',
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep, color: Colors.red),
                onPressed: _clearLogs,
                tooltip: 'Очистить логи',
              ),
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: _exportLogs,
                tooltip: 'Экспорт логов',
              ),
            ],
          ),
        ),

        // Отображение логов
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _logs.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bug_report, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Логи отсутствуют',
                            style: TextStyle(color: Colors.grey),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Нажмите "Обновить" для загрузки логов',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        final color = _getLogColor(log);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Text(
                            log,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: color,
                            ),
                          ),
                        );
                      },
                    ),
        ),

        // Информация
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            border: Border(top: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Фоновый сервис: ${_isWorkManagerRunning ? "Активен" : "Остановлен"}',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isWorkManagerRunning ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: _runNow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(100, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('Опрос сейчас'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getLogColor(String log) {
    if (log.contains('ERROR') || log.contains('error') || log.contains('failed')) {
      return Colors.red;
    } else if (log.contains('WARNING') || log.contains('warning')) {
      return Colors.orange;
    } else if (log.contains('CONNECTED') || log.contains('connected') || log.contains('SUCCESS')) {
      return Colors.green;
    } else if (log.contains('POLLING') || log.contains('polling')) {
      return Colors.blue;
    }
    return Colors.black;
  }
}