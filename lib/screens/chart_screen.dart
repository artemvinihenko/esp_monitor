import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/device_model.dart';
import '../services/preferences_manager.dart';

class ChartScreen extends StatefulWidget {
  final DeviceModel device;
  final String dataType; // 'temperature' или 'humidity'


  const ChartScreen({
    super.key,
    required this.device,
    required this.dataType,
  });

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  final _prefs = PreferencesManager();
  List<DataPoint> _dataPoints = [];
  bool _isLoading = true;
  String _timeRange = '24h'; // 6h, 24h, 7d

  String? _currentServer;
  String? _currentLogin;
   
  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    _currentServer = await _prefs.getCurrentServer();
    final credentials = await _prefs.getMqttCredentials();
    _currentLogin = credentials.login;

    try {
      final history = await _prefs.getHistory(widget.device.mac, widget.dataType,_currentServer!,_currentLogin!);
      debugPrint('Loaded ${history.length} data points for ${widget.device.mac}');
      
      setState(() {
        _dataPoints = _filterByTimeRange(history);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading chart data: $e');
      setState(() {
        _isLoading = false;
        _dataPoints = [];
      });
    }
  }
  
  List<DataPoint> _filterByTimeRange(List<DataPoint> allData) {
    final now = DateTime.now();
    Duration duration;
    
    switch (_timeRange) {
      case '6h':
        duration = const Duration(hours: 6);
        break;
      case '24h':
        duration = const Duration(hours: 24);
        break;
      case '7d':
        duration = const Duration(days: 7);
        break;
      default:
        duration = const Duration(hours: 24);
    }
    
    final cutoff = now.subtract(duration);
    return allData.where((point) => point.timestamp.isAfter(cutoff)).toList();
  }
  
  void _changeTimeRange(String range) {
    setState(() {
      _timeRange = range;
    });
    _loadData();
  }
  
  String _getTitle() {
    if (widget.dataType == 'temperature') {
      return '${widget.device.name} - Температура';
    } else {
      return '${widget.device.name} - Влажность';
    }
  }
  

  double _getMinY() {
    if (_dataPoints.isEmpty) return 0;
    final values = _dataPoints.map((p) => p.value);
    final min = values.reduce((a, b) => a < b ? a : b);
    if (widget.dataType == 'temperature') {
      return (min - 2).floorToDouble();
    } else {
      return 0.0;
    }
  }
  
  double _getMaxY() {
    if (_dataPoints.isEmpty) return 100;
    final values = _dataPoints.map((p) => p.value);
    final max = values.reduce((a, b) => a > b ? a : b);
    if (widget.dataType == 'temperature') {
      return (max + 2).ceilToDouble();
    } else {
      return 100.0;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getTitle()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _dataPoints.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.show_chart, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Нет данных для отображения',
                        style: TextStyle(color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Данные появятся после получения показаний',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildTimeRangeButton('6h', '6 часов'),
                          const SizedBox(width: 8),
                          _buildTimeRangeButton('24h', '24 часа'),
                          const SizedBox(width: 8),
                          _buildTimeRangeButton('7d', '7 дней'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: LineChart(
                          LineChartData(
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: true,
                              horizontalInterval: _getYAxisInterval(),
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 30,
                                  interval: _getXAxisInterval(),
                                  getTitlesWidget: _bottomTitleWidgets,
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 40,
                                  getTitlesWidget: _leftTitleWidgets,
                                ),
                              ),
                            ),
                            borderData: FlBorderData(
                              show: true,
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            minX: 0,
                            maxX: _dataPoints.length.toDouble() - 1,
                            minY: _getMinY(),
                            maxY: _getMaxY(),
                            lineBarsData: [
                              LineChartBarData(
                                spots: _getSpots(),
                                isCurved: true,
                                color: widget.dataType == 'temperature'
                                    ? Colors.red
                                    : Colors.blue,
                                barWidth: 2,
                                isStrokeCapRound: true,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: (widget.dataType == 'temperature'
                                          ? Colors.red
                                          : Colors.blue)
                                      .withOpacity(0.1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildInfoCard(
                            'Текущее',
                            _dataPoints.isNotEmpty
                                ? '${_dataPoints.last.value.toStringAsFixed(1)}${widget.dataType == 'temperature' ? '°C' : '%'}'
                                : '---',
                            widget.dataType == 'temperature'
                                ? Colors.red
                                : Colors.blue,
                          ),
                          _buildInfoCard(
                            'Максимум',
                            _dataPoints.isNotEmpty
                                ? '${_dataPoints.map((p) => p.value).reduce((a, b) => a > b ? a : b).toStringAsFixed(1)}${widget.dataType == 'temperature' ? '°C' : '%'}'
                                : '---',
                            Colors.orange,
                          ),
                          _buildInfoCard(
                            'Минимум',
                            _dataPoints.isNotEmpty
                                ? '${_dataPoints.map((p) => p.value).reduce((a, b) => a < b ? a : b).toStringAsFixed(1)}${widget.dataType == 'temperature' ? '°C' : '%'}'
                                : '---',
                            Colors.green,
                          ),
                          _buildInfoCard(
                            'Среднее',
                            _dataPoints.isNotEmpty
                                ? '${(_dataPoints.map((p) => p.value).reduce((a, b) => a + b) / _dataPoints.length).toStringAsFixed(1)}${widget.dataType == 'temperature' ? '°C' : '%'}'
                                : '---',
                            Colors.purple,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
  
  Widget _buildTimeRangeButton(String range, String label) {
    return FilterChip(
      label: Text(label),
      selected: _timeRange == range,
      onSelected: (selected) {
        if (selected) {
          _changeTimeRange(range);
        }
      },
      selectedColor: Colors.blue.shade100,
    );
  }
  
  Widget _buildInfoCard(String title, String value, Color color) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
  
  List<FlSpot> _getSpots() {
    final spots = <FlSpot>[];
    for (int i = 0; i < _dataPoints.length; i++) {
      spots.add(FlSpot(i.toDouble(), _dataPoints[i].value));
    }
    return spots;
  }
  
  double _getXAxisInterval() {
    if (_dataPoints.length <= 12) return 1;
    if (_dataPoints.length <= 24) return 2;
    if (_dataPoints.length <= 72) return 6;
    return 12;
  }
  
  double _getYAxisInterval() {
    if (widget.dataType == 'temperature') {
      return 5;
    } else {
      return 10;
    }
  }
  
  Widget _bottomTitleWidgets(double value, TitleMeta meta) {
    final index = value.toInt();
    if (index >= _dataPoints.length) return const SizedBox();
    
    final timestamp = _dataPoints[index].timestamp;
    String text;
    
    switch (_timeRange) {
      case '6h':
        text = DateFormat('HH:mm').format(timestamp);
        break;
      case '24h':
        text = DateFormat('HH:mm').format(timestamp);
        break;
      case '7d':
        text = DateFormat('dd.MM').format(timestamp);
        break;
      default:
        text = DateFormat('HH:mm').format(timestamp);
    }
    
    if (index % _getXAxisInterval().toInt() != 0 && index != 0) {
      return const SizedBox();
    }
    
    return SideTitleWidget(
      axisSide: meta.axisSide,
      child: Text(
        text,
        style: const TextStyle(fontSize: 10),
      ),
    );
  }
  
  Widget _leftTitleWidgets(double value, TitleMeta meta) {
    return SideTitleWidget(
      axisSide: meta.axisSide,
      child: Text(
        value.toInt().toString(),
        style: const TextStyle(fontSize: 10),
      ),
    );
  }
}