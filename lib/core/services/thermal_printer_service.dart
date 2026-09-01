import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class ThermalPrinterService {
  ThermalPrinterService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _savedMacKey = 'default_thermal_printer_mac';

  Future<bool> get bluetoothEnabled => PrintBluetoothThermal.bluetoothEnabled;
  Future<bool> get permissionGranted =>
      PrintBluetoothThermal.isPermissionBluetoothGranted;
  Future<List<BluetoothInfo>> discover() =>
      PrintBluetoothThermal.pairedBluetooths;

  Future<void> saveDefault(BluetoothInfo device) =>
      _storage.write(key: _savedMacKey, value: device.macAdress);

  Future<void> dispose() async {
    if (await PrintBluetoothThermal.connectionStatus)
      await PrintBluetoothThermal.disconnect;
  }

  Future<bool> printReceipt({
    required BluetoothInfo device,
    required String title,
    required List<({String name, String quantity, String total})> lines,
    required String total,
    int millimeters = 80,
  }) async {
    if (millimeters != 58 && millimeters != 80)
      throw ArgumentError('مقاس الطابعة يجب أن يكون 58 أو 80 ملي');
    if (!await PrintBluetoothThermal.connect(
      macPrinterAddress: device.macAdress,
    ))
      throw StateError('تعذر الاتصال بالطابعة Bluetooth');
    try {
      final profile = await CapabilityProfile.load();
      final paper = millimeters == 58 ? PaperSize.mm58 : PaperSize.mm80;
      final generator = Generator(paper, profile);
      final bytes = <int>[];
      bytes.addAll(generator.reset());
      bytes.addAll(
        generator.text(
          title,
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ),
      );
      bytes.addAll(generator.hr());
      for (final line in lines) {
        bytes.addAll(
          generator.row([
            PosColumn(
              text: line.name,
              width: 6,
              styles: const PosStyles(align: PosAlign.right),
            ),
            PosColumn(
              text: line.quantity,
              width: 2,
              styles: const PosStyles(align: PosAlign.center),
            ),
            PosColumn(
              text: line.total,
              width: 4,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]),
        );
      }
      bytes.addAll(generator.hr(ch: '='));
      bytes.addAll(
        generator.text(
          'الإجمالي: $total',
          styles: const PosStyles(
            align: PosAlign.right,
            bold: true,
            height: PosTextSize.size2,
          ),
        ),
      );
      bytes.addAll(generator.feed(2));
      bytes.addAll(generator.cut());
      return await PrintBluetoothThermal.writeBytes(bytes);
    } finally {
      await PrintBluetoothThermal.disconnect;
    }
  }
}
