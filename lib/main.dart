import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const GoldApp());
}

class GoldApp extends StatelessWidget {
  const GoldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'محاسبه وزن و برش طلا',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.amber,
        useMaterial3: true,
      ),
      home: const GoldCalculatorPage(),
    );
  }
}

class GoldCalculatorPage extends StatefulWidget {
  const GoldCalculatorPage({super.key});

  @override
  State<GoldCalculatorPage> createState() => _GoldCalculatorPageState();
}

enum MeasureMode { regularBox, irregularImage }
enum CutDirection { horizontalFromLeft, verticalFromTop }

class _GoldCalculatorPageState extends State<GoldCalculatorPage> {
  final _karatController = TextEditingController();
  final _lengthController = TextEditingController();
  final _widthController = TextEditingController();
  final _thicknessController = TextEditingController();
  final _targetWeightController = TextEditingController();

  MeasureMode _mode = MeasureMode.regularBox;
  CutDirection _cutDirection = CutDirection.horizontalFromLeft;

  File? _imageFile;
  final _picker = ImagePicker();

  Offset? _rulerStart;
  Offset? _rulerEnd;
  double _rulerCmValue = 1.0;

  final List<Offset> _polygonPoints = [];

  Offset? _cutLineStart;
  Offset? _cutLineEnd;
  String _cutSummaryText = '';

  double? _density;
  double? _areaCm2;
  double? _totalWeightGrams;
  double? _weightPerCmLengthGrams;

  double? _parseDouble(TextEditingController c) {
    final text = c.text.trim().replaceAll('/', '.').replaceAll('،', '.');
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  double _calcDensityFromKarat(double karat) {
    final purity = karat <= 24 ? (karat / 24.0) : (karat / 1000.0);
    final p = purity.clamp(0.0, 1.0);
    const double pureGoldDensity = 19.32;
    const double baseAlloyDensity = 9.7;
    const double alloyAdjustment = 0.5;
    return (p * pureGoldDensity) + ((1.0 - p) * baseAlloyDensity) + alloyAdjustment;
  }

  double _polygonAreaPx2(List<Offset> pts) {
    if (pts.length < 3) return 0.0;
    double sum = 0.0;
    for (int i = 0; i < pts.length; i++) {
      final p1 = pts[i];
      final p2 = pts[(i + 1) % pts.length];
      sum += (p1.dx * p2.dy) - (p2.dx * p1.dy);
    }
    return sum.abs() * 0.5;
  }

  double? _pixelsPerCm() {
    if (_rulerStart == null || _rulerEnd == null || _rulerCmValue <= 0) {
      return null;
    }
    final distPx = (_rulerEnd! - _rulerStart!).distance;
    if (distPx <= 0) return null;
    return distPx / _rulerCmValue;
  }

  void _calculateAll() {
    final karat = _parseDouble(_karatController);
    final thicknessCm = _parseDouble(_thicknessController);

    if (karat == null || karat <= 0) {
      _showSnack('لطفاً عیار طلا را وارد کن.');
      return;
    }
    if (thicknessCm == null || thicknessCm <= 0) {
      _showSnack('لطفاً ضخامت را (به سانتی‌متر) وارد کن.');
      return;
    }

    final density = _calcDensityFromKarat(karat);
    double? area;
    double? volume;
    double? totalWeight;
    double? perCmLength;

    if (_mode == MeasureMode.regularBox) {
      final lengthCm = _parseDouble(_lengthController);
      final widthCm = _parseDouble(_widthController);
      if (lengthCm == null || lengthCm <= 0 || widthCm == null || widthCm <= 0) {
        _showSnack('طول و عرض را به سانتی‌متر وارد کن.');
        return;
      }
      area = lengthCm * widthCm;
      volume = area * thicknessCm;
      totalWeight = volume * density;
      perCmLength = totalWeight / lengthCm;
    } else {
      final pxPerCm = _pixelsPerCm();
      if (pxPerCm == null) {
        _showSnack('ابتدا دو نقطه روی خط‌کش روی عکس علامت بزن.');
        return;
      }
      if (_polygonPoints.length < 3) {
        _showSnack('حداقل ۳ نقطه دور شکل نامتقارن روی عکس بزن.');
        return;
      }
      final areaPx2 = _polygonAreaPx2(_polygonPoints);
      area = areaPx2 / (pxPerCm * pxPerCm);
      volume = area * thicknessCm;
      totalWeight = volume * density;

      final minX = _polygonPoints.map((e) => e.dx).reduce(math.min);
      final maxX = _polygonPoints.map((e) => e.dx).reduce(math.max);
      final minY = _polygonPoints.map((e) => e.dy).reduce(math.min);
      final maxY = _polygonPoints.map((e) => e.dy).reduce(math.max);
      final spanCm = (_cutDirection == CutDirection.horizontalFromLeft
              ? (maxX - minX)
              : (maxY - minY)) /
          pxPerCm;
      perCmLength = spanCm > 0 ? totalWeight / spanCm : null;
    }

    Offset? cutStart;
    Offset? cutEnd;
    String cutSummary = '';

    final targetWeight = _parseDouble(_targetWeightController);
    if (targetWeight != null && targetWeight > 0) {
      final requiredVolumeCm3 = targetWeight / density;
      final requiredAreaCm2 = requiredVolumeCm3 / thicknessCm;

      if (_mode == MeasureMode.regularBox) {
        final widthCm = _parseDouble(_widthController) ?? 0;
        if (widthCm > 0) {
          final cutLenCm = requiredAreaCm2 / widthCm;
          cutSummary =
              'برای رسیدن به ${targetWeight.toStringAsFixed(3)} گرم، باید ${cutLenCm.toStringAsFixed(2)} سانتی‌متر از طول قطعه برش بخورد.';
        }
      } else {
        final pxPerCm = _pixelsPerCm();
        if (pxPerCm != null && _polygonPoints.length >= 3) {
          final requiredAreaPx2 = requiredAreaCm2 * pxPerCm * pxPerCm;
          final minX = _polygonPoints.map((e) => e.dx).reduce(math.min);
          final maxX = _polygonPoints.map((e) => e.dx).reduce(math.max);
          final minY = _polygonPoints.map((e) => e.dy).reduce(math.min);
          final maxY = _polygonPoints.map((e) => e.dy).reduce(math.max);

          if (_cutDirection == CutDirection.horizontalFromLeft) {
            final cutX = _findCutXForArea(requiredAreaPx2, minX, maxX, minY, maxY);
            final cutLenCm = (cutX - minX) / pxPerCm;
            cutStart = Offset(cutX, minY);
            cutEnd = Offset(cutX, maxY);
            cutSummary =
                'خط برش از سمت چپ در فاصله ${cutLenCm.toStringAsFixed(2)} سانتی‌متری رسم شد (وزن هدف: ${targetWeight.toStringAsFixed(3)} گرم).';
          } else {
            final cutY = _findCutYForArea(requiredAreaPx2, minX, maxX, minY, maxY);
            final cutLenCm = (cutY - minY) / pxPerCm;
            cutStart = Offset(minX, cutY);
            cutEnd = Offset(maxX, cutY);
            cutSummary =
                'خط برش از بالا در فاصله ${cutLenCm.toStringAsFixed(2)} سانتی‌متری رسم شد (وزن هدف: ${targetWeight.toStringAsFixed(3)} گرم).';
          }
        }
      }
    }

    setState(() {
      _density = density;
      _areaCm2 = area;
      _totalWeightGrams = totalWeight;
      _weightPerCmLengthGrams = perCmLength;
      _cutLineStart = cutStart;
      _cutLineEnd = cutEnd;
      _cutSummaryText = cutSummary;
    });
  }

  double _findCutXForArea(
    double targetAreaPx2,
    double minX,
    double maxX,
    double minY,
    double maxY,
  ) {
    final totalArea = _polygonAreaPx2(_polygonPoints);
    if (totalArea <= 0 || maxX <= minX) return minX;
    final ratio = (targetAreaPx2 / totalArea).clamp(0.0, 1.0);
    return minX + ((maxX - minX) * ratio);
  }

  double _findCutYForArea(
    double targetAreaPx2,
    double minX,
    double maxX,
    double minY,
    double maxY,
  ) {
    final totalArea = _polygonAreaPx2(_polygonPoints);
    if (totalArea <= 0 || maxY <= minY) return minY;
    final ratio = (targetAreaPx2 / totalArea).clamp(0.0, 1.0);
    return minY + ((maxY - minY) * ratio);
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 90);
    if (picked == null) return;
    setState(() {
      _mode = MeasureMode.irregularImage;
      _imageFile = File(picked.path);
      _rulerStart = null;
      _rulerEnd = null;
      _polygonPoints.clear();
      _cutLineStart = null;
      _cutLineEnd = null;
      _cutSummaryText = '';
    });
  }

  void _onTapImageCanvas(TapUpDetails details) {
    final pt = details.localPosition;
    setState(() {
      if (_rulerStart == null) {
        _rulerStart = pt;
      } else if (_rulerEnd == null) {
        _rulerEnd = pt;
      } else {
        _polygonPoints.add(pt);
      }
    });
  }

  void _resetPoints() {
    setState(() {
      _rulerStart = null;
      _rulerEnd = null;
      _polygonPoints.clear();
      _cutLineStart = null;
      _cutLineEnd = null;
      _cutSummaryText = '';
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _karatController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _thicknessController.dispose();
    _targetWeightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('محاسبه وزن و برش طلا'),
          backgroundColor: Colors.amber.shade200,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '۱. عیار و ابعاد (سانتی‌متر)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _karatController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'عیار طلا (مثلاً 750 یا 18 یا 999)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _lengthController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'طول (cm)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _widthController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'عرض (cm)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _thicknessController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'ضخامت (cm)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '۲. شکل نامتقارن + عکس کنار خط‌کش',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<MeasureMode>(
                        segments: const [
                          ButtonSegment(
                            value: MeasureMode.regularBox,
                            label: Text('ابعاد طول/عرض'),
                          ),
                          ButtonSegment(
                            value: MeasureMode.irregularImage,
                            label: Text('عکس + خط‌کش'),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (s) {
                          setState(() => _mode = s.first);
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickImage(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('عکس با دوربین'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickImage(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library),
                              label: const Text('انتخاب از گالری'),
                            ),
                          ),
                        ],
                      ),
                      if (_imageFile != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Text('فاصله خط‌کش (cm): '),
                            SizedBox(
                              width: 80,
                              child: DropdownButton<double>(
                                value: _rulerCmValue,
                                items: const [
                                  DropdownMenuItem(value: 1.0, child: Text('1 cm')),
                                  DropdownMenuItem(value: 2.0, child: Text('2 cm')),
                                  DropdownMenuItem(value: 5.0, child: Text('5 cm')),
                                  DropdownMenuItem(value: 10.0, child: Text('10 cm')),
                                ],
                                onChanged: (v) {
                                  if (v != null) setState(() => _rulerCmValue = v);
                                },
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _resetPoints,
                              icon: const Icon(Icons.refresh),
                              label: const Text('پاک کردن نقاط'),
                            ),
                          ],
                        ),
                        const Text(
                          'راهنما: ۲ لمس اول روی خط‌کش، و لمس‌های بعدی دور تا دور شکل نامتقارن.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 300,
                          width: double.infinity,
                          child: GestureDetector(
                            onTapUp: _onTapImageCanvas,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(_imageFile!, fit: BoxFit.contain),
                                CustomPaint(
                                  painter: _ShapeOverlayPainter(
                                    rulerStart: _rulerStart,
                                    rulerEnd: _rulerEnd,
                                    polygonPoints: _polygonPoints,
                                    cutStart: _cutLineStart,
                                    cutEnd: _cutLineEnd,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '۳. برش به وزن دلخواه (مثلاً ۲۰ گرم)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _targetWeightController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'وزن مورد نظر برای برش (گرم)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<CutDirection>(
                        segments: const [
                          ButtonSegment(
                            value: CutDirection.horizontalFromLeft,
                            label: Text('برش از چپ به راست'),
                          ),
                          ButtonSegment(
                            value: CutDirection.verticalFromTop,
                            label: Text('برش از بالا به پایین'),
                          ),
                        ],
                        selected: {_cutDirection},
                        onSelectionChanged: (s) {
                          setState(() => _cutDirection = s.first);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: _calculateAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'محاسبه وزن و رسم خط برش',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(height: 14),
              if (_density != null || _totalWeightGrams != null)
                Card(
                  color: Colors.amber.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'نتایج محاسبه',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        if (_density != null)
                          Text('چگالی محاسبه‌شده: ${_density!.toStringAsFixed(2)} گرم بر سانتی‌متر مکعب'),
                        if (_areaCm2 != null)
                          Text('مساحت سطح: ${_areaCm2!.toStringAsFixed(2)} سانتی‌متر مربع'),
                        if (_totalWeightGrams != null)
                          Text(
                            'وزن کل دقیق: ${_totalWeightGrams!.toStringAsFixed(3)} گرم',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        if (_weightPerCmLengthGrams != null)
                          Text(
                            'وزن هر سانتی‌متر طول: ${_weightPerCmLengthGrams!.toStringAsFixed(3)} گرم',
                          ),
                        if (_cutSummaryText.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _cutSummaryText,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShapeOverlayPainter extends CustomPainter {
  final Offset? rulerStart;
  final Offset? rulerEnd;
  final List<Offset> polygonPoints;
  final Offset? cutStart;
  final Offset? cutEnd;

  _ShapeOverlayPainter({
    this.rulerStart,
    this.rulerEnd,
    required this.polygonPoints,
    this.cutStart,
    this.cutEnd,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (rulerStart != null) {
      canvas.drawCircle(rulerStart!, 6, Paint()..color = Colors.blue);
    }
    if (rulerEnd != null) {
      canvas.drawCircle(rulerEnd!, 6, Paint()..color = Colors.blue);
    }
    if (rulerStart != null && rulerEnd != null) {
      canvas.drawLine(
        rulerStart!,
        rulerEnd!,
        Paint()
          ..color = Colors.blue
          ..strokeWidth = 2.5,
      );
    }

    if (polygonPoints.isNotEmpty) {
      final path = Path()..moveTo(polygonPoints.first.dx, polygonPoints.first.dy);
      for (int i = 1; i < polygonPoints.length; i++) {
        path.lineTo(polygonPoints[i].dx, polygonPoints[i].dy);
      }
      if (polygonPoints.length >= 3) {
        path.close();
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.amber.withValues(alpha: 0.25)
            ..style = PaintingStyle.fill,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.green
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke,
      );
      for (final p in polygonPoints) {
        canvas.drawCircle(p, 5, Paint()..color = Colors.green);
      }
    }

    if (cutStart != null && cutEnd != null) {
      canvas.drawLine(
        cutStart!,
        cutEnd!,
        Paint()
          ..color = Colors.red
          ..strokeWidth = 3.0,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShapeOverlayPainter oldDelegate) => true;
}
