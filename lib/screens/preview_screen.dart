import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../utils/snackbar_util.dart';

class PreviewScreen extends StatefulWidget {
  final String type;
  final Map<String, dynamic> data;

  const PreviewScreen({super.key, required this.type, required this.data});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  String shopName = '';
  String shopAddress = '';
  List<Map<String, String>> _senderAccounts = [];
  Map<String, String>? _selectedSender;
  
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

  @override
  void initState() {
    super.initState();
    _loadStoreData();
  }

  Future<void> _loadStoreData() async {
    final prefs = await SharedPreferences.getInstance();
    final accountsJson = prefs.getString('senderAccounts');
    
    setState(() {
      shopName = prefs.getString('shopName') ?? 'TOKO SAYA';
      shopAddress = prefs.getString('shopAddress') ?? 'Alamat Toko';
      
      if (accountsJson != null) {
        final List<dynamic> decoded = jsonDecode(accountsJson);
        _senderAccounts = decoded.map((e) => Map<String, String>.from(e)).toList();
      }
    });
  }

  String formatRp(dynamic number) {
    if (number == null) return 'Rp 0';
    int val = number is int ? number : int.tryParse(number.toString()) ?? 0;
    final formatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return formatter.format(val);
  }

  String _wrapText(String label, String value, {int maxChars = 32}) {
    String res = "";
    int indent = label.length;
    String str = label + value;
    List<String> words = str.split(' ');
    String curr = "";
    int cLen = 0;
    for (String w in words) {
      if (cLen + (cLen > 0 ? 1 : 0) + w.length > maxChars) {
        res += (res.isEmpty ? "" : "\n") + curr;
        curr = (" " * indent) + w;
        cLen = indent + w.length;
      } else {
        curr += (cLen > 0 ? " " : "") + w;
        cLen += w.length + (cLen > 0 ? 1 : 0);
      }
    }
    res += (res.isEmpty ? "" : "\n") + curr;
    return res;
  }

  String _formatLineAlignRight(String label, String value, {int maxChars = 32}) {
    int spacesCount = maxChars - label.length - value.length;
    if (spacesCount < 1) spacesCount = 1;
    return label + (" " * spacesCount) + value;
  }

  Future<void> _printReceipt() async {
    BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
    
    if (kIsWeb) {
      showCustomSnackBar(context, 'Pencetakan tidak didukung di versi Web.', isError: true);
      return;
    }

    bool? isConnected = await bluetooth.isConnected;
    if (isConnected != true) {
      final prefs = await SharedPreferences.getInstance();
      final savedMac = prefs.getString('printerMac');
      if (savedMac != null) {
        try {
          List<BluetoothDevice> devices = await bluetooth.getBondedDevices();
          BluetoothDevice device = devices.firstWhere((d) => d.address == savedMac);
          await bluetooth.connect(device);
          isConnected = true;
        } catch (e) {
          isConnected = false;
        }
      }
      
      if (isConnected != true) {
        if (mounted) showCustomSnackBar(context, 'Printer belum terhubung! Silakan cek menu Pengaturan.', isError: true);
        return;
      }
    }

    showCustomSnackBar(context, 'Mencetak struk...', isSuccess: true);
    
    try {
      int nominal = int.tryParse(widget.data['nominal']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '0') ?? 0;
      int admin = int.tryParse(widget.data['admin']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '0') ?? 0;
      int total = nominal + admin;

      const String ESC = "\x1b";
      const String GS = "\x1d";
      const String INIT = "$ESC@";
      const String alignCenter = "${ESC}a\x01";
      const String alignLeft = "${ESC}a\x00";
      const String boldOn = "${ESC}E\x01"; 
      const String fontLarge = "$GS!\x11"; 
      const String fontNormal = "$GS!\x00";

      String raw = INIT + boldOn; 
      
      if (widget.type == 'Transfer') {
        raw += "$alignCenter$fontLarge${shopName.toUpperCase()}$fontNormal\n\n";
        raw += "${shopAddress.toUpperCase()}\n\n";
        raw += "================================\n";
        raw += "${alignLeft}TGL: ${widget.data['tanggal']?.toString() ?? '--/--/----'}\n";
        raw += "JAM: ${widget.data['waktu']?.toString() ?? '--:--'}\n";
        raw += "================================\n";
        raw += "${alignCenter}KODE REFERENSI:\n";
        raw += "${widget.data['referensi']?.toString() ?? ''}\n";
        raw += "--------------------------------\n";
        raw += alignLeft;
        
        if (_selectedSender != null) {
          raw += "DATA PENGIRIM:\n";
          raw += "${_wrapText("BANK    : ", _selectedSender!['bank']?.toUpperCase() ?? '')}\n";
          raw += "${_wrapText("REK     : ", _selectedSender!['no_rek'] ?? '')}\n";
          raw += "${_wrapText("NAMA    : ", _selectedSender!['nama']?.toUpperCase() ?? '')}\n";
          raw += "--------------------------------\n";
        }
        
        raw += "DATA PENERIMA:\n";
        raw += "${_wrapText("BANK    : ", widget.data['bank_tujuan']?.toString().toUpperCase() ?? '---')}\n";
        raw += "${_wrapText("REK     : ", widget.data['rekening_tujuan']?.toString() ?? '---')}\n";
        raw += "${_wrapText("NAMA    : ", widget.data['nama_penerima']?.toString().toUpperCase() ?? '---')}\n";
        raw += "--------------------------------\n";
        
        raw += "${_formatLineAlignRight("NOMINAL", formatRp(nominal))}\n";
        raw += "${_formatLineAlignRight("ADMIN", formatRp(admin))}\n";
        raw += "${_formatLineAlignRight("TOTAL", formatRp(total))}\n";
        raw += "================================\n";
        raw += "$alignCenter** TRANSAKSI BERHASIL **\n";
        raw += "TERIMA KASIH\n\n\n\n\n";
      } else {
        raw += "$alignCenter$fontLarge${shopName.toUpperCase()}$fontNormal\n\n";
        raw += "${shopAddress.toUpperCase()}\n\n";
        raw += "PEMBELIAN TOKEN PLN\n";
        raw += "${widget.data['tanggal']?.toString() ?? '--/--/----'} ${widget.data['waktu']?.toString() ?? '--:--'}\n";
        raw += "--------------------------------\n";
        raw += alignLeft;
        raw += "${_wrapText("METER : ", widget.data['no_meter']?.toString() ?? widget.data['id_pel']?.toString() ?? '---')}\n";
        raw += "${_wrapText("NAMA  : ", widget.data['nama']?.toString().toUpperCase() ?? '---')}\n";
        raw += "${_wrapText("TRF/DY: ", widget.data['tarif_daya']?.toString().toUpperCase() ?? '---')}\n";
        raw += "${_wrapText("KWH   : ", widget.data['kwh']?.toString() ?? '0.0')}\n";
        raw += "--------------------------------\n";
        
        // Format token
        String rawTk = (widget.data['token']?.toString() ?? '').replaceAll(RegExp(r'[^0-9]'), '');
        String tkLine1 = ""; String tkLine2 = "";
        if (rawTk.length >= 12) {
          tkLine1 = "${rawTk.substring(0,4)}-${rawTk.substring(4,8)}-${rawTk.substring(8,12)}";
          var remaining = rawTk.substring(12);
          if (remaining.isNotEmpty) {
            for(int i = 0; i < remaining.length; i += 4) {
              tkLine2 += "${remaining.substring(i, (i+4 > remaining.length) ? remaining.length : i+4)}-";
            }
            if (tkLine2.endsWith("-")) tkLine2 = tkLine2.substring(0, tkLine2.length - 1);
          }
        } else { 
          String chunks = "";
          for(int i = 0; i < rawTk.length; i += 4) {
            chunks += "${rawTk.substring(i, (i+4 > rawTk.length) ? rawTk.length : i+4)}-";
          }
          if (chunks.endsWith("-")) chunks = chunks.substring(0, chunks.length - 1);
          tkLine1 = chunks;
        }

        raw += alignCenter + fontLarge;
        raw += "$tkLine1\n";
        if (tkLine2.isNotEmpty) raw += "$tkLine2\n";
        raw += fontNormal;
        
        raw += "--------------------------------\n";
        raw += alignLeft;
        raw += "${_formatLineAlignRight("NOMINAL", formatRp(nominal))}\n";
        raw += "${_formatLineAlignRight("ADMIN", formatRp(admin))}\n";
        raw += "--------------------------------\n";
        raw += "${_formatLineAlignRight("TOTAL", formatRp(total))}\n\n";
        raw += "SN:\n${widget.data['sn']?.toString() ?? '---'}\n";
        raw += "\n$alignCenter** TRANSAKSI BERHASIL **\n";
        raw += "TERIMA KASIH\n\n\n\n\n";
      }
      
      Uint8List dataToPrint = Uint8List.fromList(utf8.encode(raw));
      
      // Kirim dalam ukuran kecil seperti di HTML
      int chunkSize = 100;
      for (int i = 0; i < dataToPrint.length; i += chunkSize) {
        int end = (i + chunkSize < dataToPrint.length) ? i + chunkSize : dataToPrint.length;
        await bluetooth.writeBytes(dataToPrint.sublist(i, end));
        await Future.delayed(const Duration(milliseconds: 30));
      }
      
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error mencetak: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    int nominal = int.tryParse(widget.data['nominal']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '0') ?? 0;
    int admin = int.tryParse(widget.data['admin']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '0') ?? 0;
    int total = nominal + admin;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('PRATINJAU NOTA', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (widget.type == 'Transfer') ...[
              DropdownButtonFormField<Map<String, String>?>(
                initialValue: _selectedSender,
                decoration: InputDecoration(
                  labelText: 'Pilih Rekening Pengirim',
                  filled: true,
                  fillColor: Colors.indigo.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Tanpa Data Pengirim'),
                  ),
                  ..._senderAccounts.map((account) => DropdownMenuItem(
                    value: account,
                    child: Text('${account['bank']} - ${account['nama']}'),
                  ))
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedSender = val;
                  });
                },
              ),
              const SizedBox(height: 6),
            ],
            
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 320),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 20,
                    spreadRadius: 5,
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(shopName.toUpperCase(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(shopAddress.toUpperCase(), style: const TextStyle(fontSize: 10), textAlign: TextAlign.center),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('------------------------------------', style: TextStyle(color: Colors.grey)),
                  ),
                  
                  if (widget.type == 'Transfer') ...[
                    _buildRow('TANGGAL', widget.data['tanggal']?.toString() ?? '--/--/----'),
                    _buildRow('WAKTU', widget.data['waktu']?.toString() ?? '--:--'),
                    const SizedBox(height: 4),
                    
                    if (_selectedSender != null) ...[
                      const Text('DATA PENGIRIM:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      _buildRow('BANK', _selectedSender!['bank']?.toUpperCase() ?? ''),
                      _buildRow('REK', _selectedSender!['no_rek'] ?? ''),
                      _buildRow('NAMA', _selectedSender!['nama']?.toUpperCase() ?? ''),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text('------------------------------------', style: TextStyle(color: Colors.grey)),
                      ),
                    ],
                    
                    const Text('DATA PENERIMA:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    _buildRow('BANK', widget.data['bank_tujuan']?.toString().toUpperCase() ?? '---'),
                    _buildRow('REK', widget.data['rekening_tujuan']?.toString() ?? '---'),
                    _buildRow('NAMA', widget.data['nama_penerima']?.toString().toUpperCase() ?? '---'),
                    const SizedBox(height: 4),
                    _buildRow('NOMINAL', formatRp(nominal), onTap: () => _editField('nominal', 'Nominal')),
                    _buildRow('ADMIN', formatRp(admin), onTap: () => _editField('admin', 'Admin Biaya')),
                    const Divider(color: Colors.black54, thickness: 1, height: 8),
                    _buildRow('TOTAL', formatRp(total), isBold: true),
                    const SizedBox(height: 6),
                    const Text('** TRANSAKSI BERHASIL **', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ] else ...[
                  const Text('STRUK PEMBELIAN TOKEN', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(widget.data['tanggal']?.toString() ?? '--/--/----', style: const TextStyle(fontSize: 12)),
                      Text(widget.data['waktu']?.toString() ?? '--:--', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _buildRow('ID PEL', widget.data['no_meter']?.toString() ?? widget.data['id_pel']?.toString() ?? '---'),
                  _buildRow('NAMA', widget.data['nama']?.toString().toUpperCase() ?? '---'),
                  _buildRow('TARIF', widget.data['tarif_daya']?.toString().toUpperCase() ?? '---'),
                  _buildRow('KWH', widget.data['kwh']?.toString() ?? '0.0'),
                  const SizedBox(height: 6),
                  Text(
                    _formatUIToken(widget.data['token']?.toString() ?? 'XXXXXXXXXXXXXXXXXXXX'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  _buildRow('NOMINAL', formatRp(nominal), onTap: () => _editField('nominal', 'Nominal')),
                  _buildRow('ADMIN', formatRp(admin), onTap: () => _editField('admin', 'Admin Biaya')),
                  const Divider(color: Colors.black54, thickness: 1, height: 8),
                  _buildRow('TOTAL', formatRp(total), isBold: true),
                  const SizedBox(height: 4),
                  Text('SN: ${widget.data['sn']?.toString() ?? '---'}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                  const SizedBox(height: 4),
                  const Text('** BERHASIL **', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ],
            ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ElevatedButton(
            onPressed: _printReceipt,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.type == 'Transfer' ? Colors.indigo : Colors.orange.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('SAHKAN & CETAK NOTA', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 12)),
          ),
        ),
      ),
    );
  }

  Future<void> _editField(String key, String title) async {
    String initialValue = widget.data[key]?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '0';
    if (initialValue.isEmpty) initialValue = '0';
    final formattedInitial = NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(int.parse(initialValue)).trim();
    
    final ctrl = TextEditingController(text: formattedInitial);
    ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);

    ctrl.addListener(() {
      String text = ctrl.text.replaceAll(RegExp(r'[^0-9]'), '');
      if (text.isNotEmpty) {
        String formatted = NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(int.parse(text)).trim();
        if (ctrl.text != formatted) {
          ctrl.value = ctrl.value.copyWith(
            text: formatted,
            selection: TextSelection.collapsed(offset: formatted.length),
          );
        }
      }
    });

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit $title', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            isDense: true,
            prefixText: 'Rp ',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                widget.data[key] = ctrl.text.replaceAll(RegExp(r'[^0-9]'), '');
              });
              Navigator.pop(context);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isBold = false, VoidCallback? onTap}) {
    Widget row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal))),
          Expanded(flex: 3, child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal))),
        ],
      ),
    );
    
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: row,
        ),
      );
    }
    return row;
  }

  String _formatUIToken(String token) {
    String raw = token.replaceAll(RegExp(r'[^0-9]'), '');
    if (raw.length >= 20) {
      return "${raw.substring(0,4)}-${raw.substring(4,8)}-${raw.substring(8,12)}\n${raw.substring(12,16)}-${raw.substring(16,20)}";
    } else if (raw.length >= 12) {
      return "${raw.substring(0,4)}-${raw.substring(4,8)}-${raw.substring(8,12)}\n${raw.substring(12)}";
    }
    return token;
  }
}
