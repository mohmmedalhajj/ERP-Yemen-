import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.code128, BarcodeFormat.code39, BarcodeFormat.upcA, BarcodeFormat.upcE, BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('مسح الباركود'),
      actions: [IconButton(onPressed: () => _controller.toggleTorch(), icon: const Icon(Icons.flash_on_outlined))],
    ),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: _controller, onDetect: (capture) {
          if (_handled) return;
          final value = capture.barcodes.map((barcode) => barcode.rawValue).whereType<String>().firstWhere((raw) => raw.trim().isNotEmpty, orElse: () => '');
          if (value.isEmpty) return;
          _handled = true;
          Navigator.of(context).pop(value);
        }),
        IgnorePointer(child: CustomPaint(painter: _ScannerFramePainter())),
        const Positioned(bottom: 44, left: 24, right: 24, child: Text('وجّه الكاميرا إلى الباركود، وسيتم إرجاع المنتج تلقائيًا', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 4, color: Colors.black)]))),
      ],
    ),
  );
}

class _ScannerFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Paint()..color = Colors.black54;
    final frame = Rect.fromCenter(center: size.center(Offset.zero), width: size.width * .78, height: size.height * .28);
    canvas.drawPath(Path()..addRect(Offset.zero & size)..addRect(frame), overlay..style = PaintingStyle.fill..blendMode = BlendMode.srcOver);
    final border = Paint()..color = Colors.tealAccent..style = PaintingStyle.stroke..strokeWidth = 3;
    canvas.drawRect(frame, border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
