import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:intl/intl.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'services/gemini_service.dart';
import 'services/update_service.dart';
import 'screens/preview_screen.dart';
import 'utils/snackbar_util.dart';

void main() {
  runApp(const ScannerNotaApp());
}

class ScannerNotaApp extends StatelessWidget {
  const ScannerNotaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scanner Nota',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F9FE),
      ),
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final List<Widget> _screens = [
    const HomeScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 60,
          indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo);
            return const TextStyle(fontSize: 11, color: Colors.grey);
          }),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          backgroundColor: Colors.white,
          elevation: 10,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, size: 22),
              selectedIcon: Icon(Icons.home, size: 22, color: Colors.indigo),
              label: 'Beranda',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined, size: 22),
              selectedIcon: Icon(Icons.settings, size: 22, color: Colors.indigo),
              label: 'Pengaturan',
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = false;
  String _loadingText = '';
  bool _isAiConfigured = false;
  List<Map<String, dynamic>> _historyList = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _checkAiStatus();
    _loadHistory();
    _initShareIntent();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkUpdate(context);
    });
  }

  Future<void> _checkAiStatus() async {
    final prefs = await SharedPreferences.getInstance();
    String? apiKey = prefs.getString('geminiApiKey');
    if (apiKey == null || apiKey.trim().isEmpty) {
        apiKey = 'AIzaSyBPc7DI4uxBi55_f5HMPaerOYjhxusclZg';
        await prefs.setString('geminiApiKey', apiKey);
    }
    setState(() {
      _isAiConfigured = apiKey!.trim().isNotEmpty;
    });
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString('scanHistory');
    if (historyJson != null) {
      setState(() {
        _historyList = List<Map<String, dynamic>>.from(jsonDecode(historyJson));
      });
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('scanHistory', jsonEncode(_historyList));
  }

  Future<void> _deleteHistoryItem(int originalIndex) async {
    setState(() {
      _historyList.removeAt(originalIndex);
    });
    await _saveHistory();
    if (mounted) {
      showCustomSnackBar(context, 'Riwayat berhasil dihapus', isSuccess: true);
    }
  }

  StreamSubscription? _intentDataStreamSubscription;

  void _initShareIntent() {
    if (kIsWeb) return;
    try {
      _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
        if (value.isNotEmpty) _handleSharedImage(value.first.path);
      }, onError: (err) {
        debugPrint("getIntentDataStream error: $err");
      });
      ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile>? value) {
        if (value != null && value.isNotEmpty) _handleSharedImage(value.first.path);
        ReceiveSharingIntent.instance.reset();
      });
    } catch (e) {
      print("Share intent error: $e");
    }
  }

  void _handleSharedImage(String path) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.file_present_rounded, size: 48, color: Colors.indigo),
              const SizedBox(height: 12),
              const Text('File Diterima', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo)),
              const SizedBox(height: 8),
              const Text('Pilih jenis struk untuk file ini:', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _processImage('Transfer', imagePath: path);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.indigo.shade100, width: 2),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.indigo.shade50,
                        ),
                        child: Column(
                          children: const [
                            Icon(Icons.swap_horiz_rounded, size: 36, color: Colors.indigo),
                            SizedBox(height: 8),
                            Text('BUKTI\nTRANSFER', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _processImage('Token', imagePath: path);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.orange.shade100, width: 2),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.orange.shade50,
                        ),
                        child: Column(
                          children: const [
                            Icon(Icons.bolt_rounded, size: 36, color: Colors.orange),
                            SizedBox(height: 8),
                            Text('TOKEN\nLISTRIK', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal', style: TextStyle(color: Colors.grey)),
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _processImage(String type, {String? imagePath}) async {
    String? path = imagePath;
    if (path == null) {
      bool? isPdf = await showModalBottomSheet<bool>(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Pilih Sumber File', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ListTile(
                  leading: CircleAvatar(backgroundColor: Colors.blue.shade100, child: Icon(Icons.image, color: Colors.blue.shade700)),
                  title: const Text('Gambar (Galeri / Kamera)', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(context, false),
                ),
                ListTile(
                  leading: CircleAvatar(backgroundColor: Colors.red.shade100, child: Icon(Icons.picture_as_pdf, color: Colors.red.shade700)),
                  title: const Text('File PDF', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(context, true),
                ),
              ],
            ),
          ),
        ),
      );
      
      if (isPdf == null) return;
      
      if (isPdf) {
        List<PlatformFile>? files = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          allowMultiple: false,
        );
        if (files == null || files.isEmpty || files.first.path == null) return;
        path = files.first.path;
      } else {
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 60,
          maxWidth: 1200,
          maxHeight: 1200,
        );
        if (image == null) return;
        path = image.path;
      }
    }
    
    setState(() {
      _isLoading = true;
      _loadingText = 'Menganalisis gambar...';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = prefs.getString('geminiApiKey');
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('API Key belum diatur di Pengaturan');
      }

      if (path == null) throw Exception('File tidak ditemukan');
      
      final isPdf = path.toLowerCase().endsWith('.pdf');
      final mimeType = isPdf ? 'application/pdf' : 'image/jpeg';
      
      final bytes = await File(path).readAsBytes();
      final base64Data = base64Encode(bytes);
      final result = await GeminiService.processReceipt(base64Data, type, apiKey, mimeType: mimeType);
      
      if (result == null) throw Exception('Gagal menganalisis struk');
      
      
      String displayName = type == 'Transfer' ? (result['nama_penerima'] ?? 'Transaksi') : (result['nama'] ?? 'Transaksi');
      dynamic nominal = result['nominal'] ?? 0;
      int parsedNominal = 0;
      if (nominal is int) {
        parsedNominal = nominal;
      } else if (nominal is String) parsedNominal = int.tryParse(nominal.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

      setState(() {
        _historyList.insert(0, {
          'name': displayName.toString().isEmpty ? 'Transaksi' : displayName,
          'type': type,
          'date': DateFormat('dd/MM/yyyy').format(DateTime.now()),
          'total': parsedNominal,
          'data': result,
        });
      });
      await _saveHistory();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PreviewScreen(type: type, data: result),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showCustomSnackBar(context, e.toString(), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showScanOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Pilih Jenis Nota', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ListTile(
                  leading: CircleAvatar(backgroundColor: Colors.indigo.shade100, child: Icon(Icons.receipt_long, color: Colors.indigo.shade700)),
                  title: const Text('Bukti Transfer', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () { Navigator.pop(context); _processImage('Transfer'); },
                ),
                ListTile(
                  leading: CircleAvatar(backgroundColor: Colors.orange.shade100, child: Icon(Icons.bolt, color: Colors.orange.shade800)),
                  title: const Text('Token Listrik', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () { Navigator.pop(context); _processImage('Token'); },
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> filteredList = _historyList.where((item) {
      if (_searchQuery.isEmpty) return true;
      String name = item['name']?.toString().toLowerCase() ?? '';
      String type = item['type']?.toString().toLowerCase() ?? '';
      String date = item['date']?.toString().toLowerCase() ?? '';
      String query = _searchQuery.toLowerCase();
      return name.contains(query) || type.contains(query) || date.contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: SizedBox(
        height: 44,
        child: FloatingActionButton.extended(
          onPressed: _showScanOptions,
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.document_scanner_outlined, size: 20),
          label: const Text('Pindai', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          extendedPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('SCANNER NOTA', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -1)),
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isAiConfigured ? Colors.greenAccent : Colors.redAccent,
                          boxShadow: [
                            BoxShadow(color: _isAiConfigured ? Colors.greenAccent.withOpacity(0.6) : Colors.redAccent.withOpacity(0.6), blurRadius: 10, spreadRadius: 3)
                          ]
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: TextField(
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Cari nama, jenis, atau tanggal...',
                        hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
                        prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                        border: InputBorder.none,
                        isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 6),
                  const Text('RIWAYAT CETAK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.grey)),
                  const SizedBox(height: 6),
                  
                  Expanded(
                    child: filteredList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey.shade300),
                              const SizedBox(height: 4),
                              Text(
                                _searchQuery.isEmpty ? 'Belum ada riwayat.\nScan nota pertama Anda!' : 'Tidak ditemukan hasil pencarian.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.black38, fontStyle: FontStyle.italic)
                              ),
                            ]
                          ),
                        )
                      : ListView(
                          children: filteredList.asMap().entries.map((entry) {
                            int index = entry.key;
                            var item = entry.value;
                            
                            int originalIndex = _historyList.indexOf(item);
                            
                            return InkWell(
                              onTap: () {
                                if (item['data'] != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => PreviewScreen(
                                        type: item['type'],
                                        data: Map<String, dynamic>.from(item['data']),
                                      ),
                                    ),
                                  );
                                } else {
                                  showCustomSnackBar(context, 'Data riwayat ini tidak lengkap (versi lama).', isError: true);
                                }
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item['name'].toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 4),
                                          Text('${item["type"]} - ${item["date"]}', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(item['total'] ?? 0),
                                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: item['type'] == 'Transfer' ? Colors.indigo : Colors.orange.shade800),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (BuildContext context) {
                                            return AlertDialog(
                                              title: const Text("Hapus Riwayat"),
                                              content: const Text("Apakah Anda yakin ingin menghapus data riwayat ini?"),
                                              actions: [
                                                TextButton(
                                                  child: const Text("Batal"),
                                                  onPressed: () => Navigator.of(context).pop(),
                                                ),
                                                TextButton(
                                                  child: const Text("Hapus", style: TextStyle(color: Colors.red)),
                                                  onPressed: () {
                                                    Navigator.of(context).pop();
                                                    _deleteHistoryItem(originalIndex);
                                                  },
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                  ),
                ],
              ),
            ),
            if (_isLoading)
              Container(
                color: Colors.white.withOpacity(0.9),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.indigo),
                      const SizedBox(height: 4),
                      Text(_loadingText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.5, color: Colors.indigo)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- SETTINGS SCREEN ---
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _shopNameCtrl = TextEditingController();
  final _shopAddressCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();

  List<Map<String, String>> _senderAccounts = [];

  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;
  bool _connected = false;
  bool _isConnecting = false;
  bool _isBluetoothListening = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initBluetooth();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _shopNameCtrl.text = prefs.getString('shopName') ?? '';
      _shopAddressCtrl.text = prefs.getString('shopAddress') ?? '';
      _apiKeyCtrl.text = prefs.getString('geminiApiKey') ?? '';
      
      final senderJson = prefs.getString('senderAccounts');
      if (senderJson != null) {
        final List<dynamic> decoded = jsonDecode(senderJson);
        _senderAccounts = decoded.map((e) => Map<String, String>.from(e)).toList();
      }
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shopName', _shopNameCtrl.text);
    await prefs.setString('shopAddress', _shopAddressCtrl.text);
    await prefs.setString('geminiApiKey', _apiKeyCtrl.text);
    await prefs.setString('senderAccounts', jsonEncode(_senderAccounts));
    
    if (mounted) {
      showCustomSnackBar(context, 'Pengaturan berhasil disimpan!', isSuccess: true);
    }
  }

  Future<void> _initBluetooth() async {
    if (kIsWeb) return;
    try {
      List<BluetoothDevice> devices = await bluetooth.getBondedDevices();
      setState(() {
        _devices = devices;
      });
      final prefs = await SharedPreferences.getInstance();
      final savedPrinterMac = prefs.getString('printerMac');
      
      if (savedPrinterMac != null && _devices.isNotEmpty) {
        try {
          setState(() {
            _selectedDevice = _devices.firstWhere((d) => d.address == savedPrinterMac);
          });
          _connect(showNotif: false);
        } catch (e) {
          // Device not found
        }
      }
      
      if (!_isBluetoothListening) {
        bluetooth.onStateChanged().listen((state) {
          if (state == BlueThermalPrinter.STATE_ON) {
            _initBluetooth();
          } else if (state == BlueThermalPrinter.STATE_OFF) {
            if (mounted) {
              setState(() {
                _connected = false;
              });
            }
          }
        });
        _isBluetoothListening = true;
      }
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print("Bluetooth init error: \$e");
    }
  }

  void _connect({bool showNotif = true}) async {
    if (_selectedDevice == null) return;
    
    setState(() => _isConnecting = true);
    
    try {
      bool? isConnected = await bluetooth.isConnected;
      if (isConnected == true) {
        if (mounted) {
          setState(() {
            _connected = true;
            _isConnecting = false;
          });
          if (showNotif) showCustomSnackBar(context, 'Printer sudah terhubung!', isSuccess: true);
        }
        return;
      }
      
      await bluetooth.connect(_selectedDevice!);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('printerMac', _selectedDevice!.address!);
      
      if (mounted) {
        setState(() {
          _connected = true;
          _isConnecting = false;
        });
        if (showNotif) showCustomSnackBar(context, 'Printer berhasil terhubung!', isSuccess: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isConnecting = false);
        String errorMsg = e.toString();
        if (errorMsg.contains("read failed") || errorMsg.contains("socket might closed")) {
          errorMsg = "Gagal terhubung! Pastikan printer menyala dan sudah di-Pairing. Hapus (Unpair) lalu sandingkan ulang jika masih gagal.";
        } else {
          errorMsg = "Gagal terhubung: $errorMsg";
        }
        if (showNotif) {
          showCustomSnackBar(
            context, 
            errorMsg, 
            isError: true, 
            actionLabel: 'PENGATURAN', 
            onAction: () => bluetooth.openSettings
          );
        }
      }
    }
  }

  void _showAddSenderDialog() {
    final bankCtrl = TextEditingController();
    final namaCtrl = TextEditingController();
    final rekCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tambah Pengirim'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: bankCtrl, decoration: const InputDecoration(labelText: 'Bank (misal: BCA)')),
            TextField(controller: rekCtrl, decoration: const InputDecoration(labelText: 'No. Rekening'), keyboardType: TextInputType.number),
            TextField(controller: namaCtrl, decoration: const InputDecoration(labelText: 'Nama Pemilik')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          TextButton(
            onPressed: () {
              if (bankCtrl.text.isNotEmpty && rekCtrl.text.isNotEmpty && namaCtrl.text.isNotEmpty) {
                setState(() {
                  _senderAccounts.add({
                    'bank': bankCtrl.text,
                    'no_rek': rekCtrl.text,
                    'nama': namaCtrl.text,
                  });
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Text(
              'PENGATURAN',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -1),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: ListView(
                  children: [
                    const SizedBox(height: 4),
                    const SizedBox(height: 6),
                    const Text('Nama Toko', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _shopNameCtrl,
                      
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Contoh: TOKO BERKAH',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text('Alamat / Kontak', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _shopAddressCtrl,
                      
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Jl. Melati No. 10 | WA: 0812345678',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    
                    const SizedBox(height: 4),
                    const Divider(),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('DATA PENGIRIM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
                        TextButton.icon(
                          onPressed: () {
                            _showAddSenderDialog();
                          },
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('Tambah', style: TextStyle(fontSize: 12)),
                        )
                      ],
                    ),
                    if (_senderAccounts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Belum ada data pengirim', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                      )
                    else
                      ..._senderAccounts.asMap().entries.map((entry) {
                        int index = entry.key;
                        var account = entry.value;
                        return Card(
                          elevation: 0,
                          color: Colors.grey.shade50,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade200)),
                          child: ListTile(
                            title: Text('${account["bank"]} - ${account["nama"]}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text('${account["no_rek"]}', style: const TextStyle(fontSize: 12)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                              onPressed: () {
                                setState(() {
                                  _senderAccounts.removeAt(index);
                                });
                              },
                            ),
                          ),
                        );
                      }),
                      
                    const SizedBox(height: 4),
                    const Divider(),
                    const SizedBox(height: 4),
                    const Text('PRINTER BLUETOOTH', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
                    const SizedBox(height: 4),
                    if (kIsWeb)
                      const Text('Printer tidak didukung di Web', style: TextStyle(color: Colors.red))
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<BluetoothDevice>(
                              initialValue: _selectedDevice,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                prefixIcon: _isConnecting 
                                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                                    : Icon(
                                        _connected ? Icons.bluetooth_connected : Icons.bluetooth,
                                        color: _connected ? Colors.green : Colors.grey,
                                        size: 20,
                                      ),
                              ),
                              style: const TextStyle(fontSize: 13, color: Colors.black),
                              hint: const Text('Pilih Printer'),
                              items: _devices.map((device) {
                                return DropdownMenuItem(
                                  value: device,
                                  child: Text(device.name ?? 'Unknown'),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedDevice = val;
                                });
                                if (val != null) {
                                  _connect();
                                }
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, color: Colors.blue),
                            onPressed: () {
                              _initBluetooth();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Mencari ulang printer...')),
                              );
                            },
                          ),
                        ],
                      ),
                      if (_devices.isEmpty)
                        TextButton.icon(
                          onPressed: () => bluetooth.openSettings,
                          icon: const Icon(Icons.settings_bluetooth),
                          label: const Text('Buka Pengaturan Bluetooth'),
                        )
                    ],
                    const Divider(),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('KONEKSI AI GEMINI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _apiKeyCtrl.text.isNotEmpty ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _apiKeyCtrl.text.isNotEmpty ? 'TERHUBUNG' : 'TERPUTUS',
                            style: TextStyle(
                              color: _apiKeyCtrl.text.isNotEmpty ? Colors.green : Colors.red,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) {
                            final tempCtrl = TextEditingController();
                            return AlertDialog(
                              title: const Text('Edit API Key', style: TextStyle(fontSize: 16)),
                              content: TextField(
                                controller: tempCtrl,
                                decoration: const InputDecoration(
                                  hintText: 'AIza...',
                                  isDense: true,
                                ),
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      if (tempCtrl.text.isNotEmpty) _apiKeyCtrl.text = tempCtrl.text;
                                    });
                                    Navigator.pop(context);
                                  },
                                  child: const Text('Simpan'),
                                ),
                              ],
                            );
                          }
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _apiKeyCtrl.text.length > 4 
                                ? '${_apiKeyCtrl.text.substring(0, 4)}${'•' * 20}' 
                                : (_apiKeyCtrl.text.isEmpty ? 'Belum diatur' : '••••'),
                              style: TextStyle(fontSize: 13, color: _apiKeyCtrl.text.isEmpty ? Colors.grey : Colors.black, letterSpacing: 1.5),
                            ),
                            const Icon(Icons.edit, size: 16, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          UpdateService.checkUpdate(context, showNoUpdateToast: true);
                        },
                        icon: const Icon(Icons.system_update_rounded, size: 18),
                        label: const Text('Cek Pembaruan Aplikasi', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.indigo,
                          side: const BorderSide(color: Colors.indigo),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('SIMPAN PENGATURAN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
