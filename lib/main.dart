import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as ms;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart'
    as mlkit;
import 'dart:io' show Platform; // Para detectar Android/iOS

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lector QR Pro',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: const QRScannerPage(),
    );
  }
}

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  final ms.MobileScannerController controller = ms.MobileScannerController();
  final ImagePicker _picker = ImagePicker();

  String? lastScanned;
  bool hasScanned = false;
  List<ms.Barcode> detectedBarcodes = [];
  bool showQRBox = false;

  Future<void> _saveScan(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> history = prefs.getStringList('qr_history') ?? [];
    history.add(code);
    await prefs.setStringList('qr_history', history);
  }

  Future<void> _onDetect(String code) async {
    if (hasScanned) return;

    setState(() {
      lastScanned = code;
      hasScanned = true;
      showQRBox = false;
    });
    await _saveScan(code);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Código escaneado: $code"),
        backgroundColor: Colors.greenAccent[700],
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _goToHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HistoryPage()),
    );
  }

  Future<void> _resetScanner() async {
    setState(() {
      lastScanned = null;
      hasScanned = false;
      detectedBarcodes = [];
      showQRBox = false;
    });
    try {
      await controller.start();
    } catch (_) {}
  }

  Future<void> _handleScannedContent(String content) async {
    final wifiData = _parseWifiQR(content);
    if (wifiData != null) {
      _showWifiDialog(wifiData);
    } else {
      _showUrlDialog(content);
    }
  }

  Map<String, String>? _parseWifiQR(String raw) {
    if (!raw.startsWith('WIFI:') || !raw.endsWith(';;')) return null;

    final parts = raw.substring(5, raw.length - 2).split(';');
    final Map<String, String> data = {};

    for (final part in parts) {
      if (part.contains(':')) {
        final key = part.substring(0, part.indexOf(':'));
        final value = part.substring(part.indexOf(':') + 1);
        data[key] = value;
      }
    }

    if (data.containsKey('S')) {
      return {
        'ssid': data['S']!,
        'type': data['T'] ?? 'nopass',
        'password': data['P'] ?? '',
      };
    }
    return null;
  }

  void _showWifiDialog(Map<String, String> wifi) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Conectar a Wi-Fi"),
          content: Text("Red: ${wifi['ssid']}\nSeguridad: ${wifi['type']}"),
          actions: [
            TextButton(
              child: const Text("Cancelar"),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text("Ver detalles"),
              onPressed: () async {
                Navigator.pop(context);
                await _connectToWifi(wifi);
              },
            ),
          ],
        );
      },
    );
  }

  void _showUrlDialog(String url) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            "Abrir enlace",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text("¿Qué deseas hacer con este enlace?\n\n$url"),
          actions: [
            TextButton(
              child: const Text("Cancelar"),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text("Copiar"),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Enlace copiado al portapapeles"),
                  ),
                );
              },
            ),
            TextButton(
              child: const Text("Abrir"),
              onPressed: () async {
                Navigator.pop(context);
                final Uri uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("No se pudo abrir el enlace")),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _connectToWifi(Map<String, String> wifi) async {
    final ssid = wifi['ssid']!;
    final password = wifi['password'];
    final security = wifi['type'] ?? 'nopass';

    if (Platform.isAndroid) {
      final uri = Uri.parse(
        'intent:#Intent;action=android.settings.WIFI_SETTINGS;end',
      );
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Ve a la red \"$ssid\" y conéctate manualmente."),
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        _showWifiCredentials(wifi);
      }
    } else if (Platform.isIOS) {
      _showWifiCredentials(wifi);
    }
  }

  void _showWifiCredentials(Map<String, String> wifi) {
    final ssid = wifi['ssid']!;
    final password = wifi['password'];
    final security = wifi['type'] ?? 'Sin seguridad';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Detalles de la red Wi-Fi"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("SSID: $ssid"),
              const SizedBox(height: 8),
              Text("Seguridad: ${security.toUpperCase()}"),
              if (password != null && password.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text("Contraseña: $password"),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cerrar"),
            ),
            if (password != null && password.isNotEmpty && Platform.isAndroid)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: password));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Contraseña copiada")),
                  );
                },
                child: const Text("Copiar contraseña"),
              ),
          ],
        );
      },
    );
  }

  Future<void> _scanFromGallery() async {
    try {
      final XFile? xfile = await _picker.pickImage(source: ImageSource.gallery);
      if (xfile == null) return;

      final inputImage = mlkit.InputImage.fromFilePath(xfile.path);
      final barcodeScanner = mlkit.BarcodeScanner();
      final List<mlkit.Barcode> barcodes = await barcodeScanner.processImage(
        inputImage,
      );
      await barcodeScanner.close();

      if (barcodes.isNotEmpty) {
        for (final mlkit.Barcode barcode in barcodes) {
          if (barcode.format == mlkit.BarcodeFormat.qrCode &&
              barcode.rawValue != null) {
            await _onDetect(barcode.rawValue!);
            return;
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No se detectó ningún QR en la imagen")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al procesar la imagen: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Lector QR Pro"),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white),
            onPressed: _goToHistory,
          ),
          IconButton(
            icon: const Icon(Icons.photo_library, color: Colors.white),
            onPressed: _scanFromGallery,
          ),
        ],
      ),
      body: Stack(
        children: [
          ms.MobileScanner(
            controller: controller,
            onDetect: (capture) {
              if (!hasScanned) {
                setState(() {
                  detectedBarcodes = capture.barcodes;
                });

                for (final ms.Barcode barcode in capture.barcodes) {
                  final code = barcode.rawValue;
                  if (code != null) {
                    _onDetect(code);
                    break;
                  }
                }

                if (!hasScanned && detectedBarcodes.isNotEmpty) {
                  setState(() {
                    showQRBox = true;
                  });

                  Future.delayed(const Duration(milliseconds: 600), () {
                    if (mounted && !hasScanned) {
                      setState(() {
                        showQRBox = false;
                      });
                    }
                  });
                }
              }
            },
          ),

          if (showQRBox && detectedBarcodes.isNotEmpty)
            CustomPaint(painter: QRBoxPainter(barcodes: detectedBarcodes)),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.9),
                    Colors.black.withOpacity(0.4),
                  ],
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.flash_on),
                    label: const Text("Linterna"),
                    onPressed: () {
                      controller.toggleTorch();
                    },
                  ),
                  const SizedBox(height: 12),
                  lastScanned != null
                      ? Column(
                        children: [
                          const Text(
                            "Último escaneo:",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () => _handleScannedContent(lastScanned!),
                            child: Text(
                              lastScanned!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.blueAccent,
                                decoration: TextDecoration.underline,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed: _resetScanner,
                            icon: const Icon(Icons.refresh),
                            label: const Text("Escanear otro QR"),
                          ),
                        ],
                      )
                      : const Text(
                        "Apunta a un código QR",
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class QRBoxPainter extends CustomPainter {
  final List<ms.Barcode> barcodes;

  QRBoxPainter({required this.barcodes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.greenAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    for (final barcode in barcodes) {
      if (barcode.rawValue != null &&
          barcode.corners != null &&
          barcode.corners!.length == 4) {
        final corners = barcode.corners!;

        final path = Path();
        path.moveTo(corners[0].dx, corners[0].dy);
        path.lineTo(corners[1].dx, corners[1].dy);
        path.lineTo(corners[2].dx, corners[2].dy);
        path.lineTo(corners[3].dx, corners[3].dy);
        path.close();

        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// =============== PÁGINA DE HISTORIAL ===============
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<String> history = [];
  String searchQuery = "";

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      history = prefs.getStringList('qr_history') ?? [];
    });
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('qr_history');
    setState(() {
      history.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _handleScannedContent(String content) async {
    final wifiData = _parseWifiQR(content);
    if (wifiData != null) {
      _showWifiDialog(wifiData);
    } else {
      _showUrlDialog(content);
    }
  }

  Map<String, String>? _parseWifiQR(String raw) {
    if (!raw.startsWith('WIFI:') || !raw.endsWith(';;')) return null;

    final parts = raw.substring(5, raw.length - 2).split(';');
    final Map<String, String> data = {};

    for (final part in parts) {
      if (part.contains(':')) {
        final key = part.substring(0, part.indexOf(':'));
        final value = part.substring(part.indexOf(':') + 1);
        data[key] = value;
      }
    }

    if (data.containsKey('S')) {
      return {
        'ssid': data['S']!,
        'type': data['T'] ?? 'nopass',
        'password': data['P'] ?? '',
      };
    }
    return null;
  }

  void _showWifiDialog(Map<String, String> wifi) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Conectar a Wi-Fi"),
          content: Text("Red: ${wifi['ssid']}\nSeguridad: ${wifi['type']}"),
          actions: [
            TextButton(
              child: const Text("Cancelar"),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text("Ver detalles"),
              onPressed: () async {
                Navigator.pop(context);
                _showWifiCredentials(wifi);
              },
            ),
          ],
        );
      },
    );
  }

  void _showUrlDialog(String url) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Abrir enlace"),
          content: Text("¿Qué deseas hacer con este enlace?\n\n$url"),
          actions: [
            TextButton(
              child: const Text("Cancelar"),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text("Copiar"),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("Enlace copiado")));
              },
            ),
            TextButton(
              child: const Text("Abrir"),
              onPressed: () async {
                Navigator.pop(context);
                final Uri uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("No se pudo abrir el enlace")),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showWifiCredentials(Map<String, String> wifi) {
    final ssid = wifi['ssid']!;
    final password = wifi['password'];
    final security = wifi['type'] ?? 'Sin seguridad';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Detalles de la red Wi-Fi"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("SSID: $ssid"),
              const SizedBox(height: 8),
              Text("Seguridad: ${security.toUpperCase()}"),
              if (password != null && password.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text("Contraseña: $password"),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cerrar"),
            ),
            if (password != null && password.isNotEmpty && Platform.isAndroid)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: password));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Contraseña copiada")),
                  );
                },
                child: const Text("Copiar contraseña"),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredHistory =
        history
            .where(
              (item) => item.toLowerCase().contains(searchQuery.toLowerCase()),
            )
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Historial"),
        actions: [
          IconButton(icon: const Icon(Icons.delete), onPressed: _clearHistory),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Buscar en historial",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value;
                });
              },
            ),
          ),
          Expanded(
            child:
                filteredHistory.isEmpty
                    ? const Center(
                      child: Text(
                        "No hay escaneos guardados",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                    : ListView.builder(
                      itemCount: filteredHistory.length,
                      itemBuilder: (context, index) {
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: const Icon(
                              Icons.qr_code,
                              color: Colors.blue,
                            ),
                            title: Text(
                              filteredHistory[index],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              'Escaneado',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            onTap:
                                () => _handleScannedContent(
                                  filteredHistory[index],
                                ),
                            trailing: const Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
