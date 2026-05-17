import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simple_barcode_scanner/simple_barcode_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_saver/file_saver.dart';
import '../main.dart';
import 'detail_screen.dart';

const String kCompanyName = "Sárosi IT Systems";

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomeScreenPage();
  }
  
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final CollectionReference _products = FirebaseFirestore.instance.collection('products');
  final CollectionReference _movements = FirebaseFirestore.instance.collection('movements');
  final CollectionReference _documentsArchived = FirebaseFirestore.instance.collection('documents'); 
  
  final _searchController = TextEditingController();
  String _searchText = "";
  
  bool _isSelectionMode = false;
  final Set<String> _selectedItems = {};
  List<String> _currentCategories = [];

  void _msg(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  Future<String> _scanBarcode() async {
    var res = await Navigator.push(context, MaterialPageRoute(builder: (context) => const SimpleBarcodeScannerPage()));
    if (res is String && res != '-1' && res.isNotEmpty) return res;
    return "";
  }

  List<String> _parseSNs(Map<String, dynamic> data) {
    List<String> snList = [];
    if (data['serialNumbers'] != null && data['serialNumbers'] is List) {
      for (var item in data['serialNumbers']) {
        if (item.toString().contains(';')) {
          snList.addAll(item.toString().split(';').map((e) => e.trim()));
        } else {
          snList.add(item.toString().trim());
        }
      }
    } else if (data['serialNumber'] != null && data['serialNumber'].toString().trim().isNotEmpty) {
      String oldSn = data['serialNumber'].toString();
      if (oldSn.contains(';')) snList = oldSn.split(';').map((e) => e.trim()).toList();
      else snList.add(oldSn.trim());
    }
    snList.removeWhere((element) => element.isEmpty);
    return snList;
  }

  // --- ÚJ: KARAKTERJAVÍTÓ A PDF-HEZ (Megakadályozza az ékezet hibákat) ---
  String _pdfSafe(String text) {
    return text.replaceAll('ő', 'ö').replaceAll('Ő', 'Ö')
               .replaceAll('ű', 'ü').replaceAll('Ű', 'Ü');
  }

  Future<void> _downloadFile(Uint8List bytes, String fileName, String mimeType) async {
    try {
      MimeType type = MimeType.other;
      if (fileName.toLowerCase().endsWith('.pdf')) type = MimeType.pdf;
      if (fileName.toLowerCase().endsWith('.csv')) type = MimeType.csv;

      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: bytes,
        mimeType: type,
      );
    } catch (e) {
      _msg("Hiba a helyi mentés során: $e", Colors.red);
    }
  }

  // --- BIZONYLATGENERÁLÓ (BEVÉTEL ÉS KIADÁS IS!) ---
  Future<void> _generateInternalDocumentPDF({required String docType, required Map<String, dynamic> data, required int moveQty, required List<String> movedSNs}) async {
    try {
      final pdf = pw.Document();
      final dt = DateTime.now();
      final dateStr = "${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
      final price = data['price'] ?? 0;
      final total = price * moveQty;
      final bizonylatId = "SIS-${dt.millisecondsSinceEpoch}";
      
      String title = '';
      String sig1 = '';
      String sig2 = '';
      PdfColor badgeColor = const PdfColor.fromInt(0xFFD32F2F); // Piros (Kiadás)
      String badgeText = "KIADVA";
      String prefix = "";

      if (docType == 'bevetel') {
        title = 'BELSO BEVETELI BIZONYLAT';
        sig1 = 'Beszallito / Atado';
        sig2 = 'Raktaros ($kCompanyName)';
        badgeColor = const PdfColor.fromInt(0xFF388E3C); // Zöld (Bevétel)
        badgeText = "BEVETELEZVE";
        prefix = 'Beveteli_Bizonylat';
      } else if (docType == 'bizonylat') {
        title = 'BELSO KIADASI BIZONYLAT';
        sig1 = 'Raktaros';
        sig2 = 'Eszkoz Igenylo';
        prefix = 'Kiadasi_Bizonylat';
      } else {
        title = 'ESZKOZ ATADAS-ATVETELI NYILATKOZAT';
        sig1 = 'Atado ($kCompanyName)';
        sig2 = 'Atvevo (Felelos)';
        prefix = 'Atveteli_Nyilatkozat';
      }

      final fileName = '${prefix}_${dt.millisecondsSinceEpoch}.pdf';

      // Adatbázis archiválás
      await _documentsArchived.add({
        'bizonylatId': bizonylatId,
        'tipus': docType,
        'megnevezes': title,
        'eszkozNev': data['name'],
        'kategoria': data['category'] ?? 'Egyeb',
        'mennyiseg': moveQty,
        'sorozatszamok': movedSNs,
        'ertek': total,
        'datum': FieldValue.serverTimestamp()
      });

      // PDF Grafika
      pdf.addPage(pw.Page(build: (pw.Context context) {
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text("$kCompanyName - IT & Raktar", style: pw.TextStyle(fontSize: 13, color: const PdfColor.fromInt(0xFF555555))),
                  ]
                ),
              ),
              pw.SizedBox(width: 15),
              pw.Row(
                children: [
                  pw.Container(
                    height: 45, width: 45,
                    child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: bizonylatId, color: const PdfColor.fromInt(0xFF000000)),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: const PdfColor.fromInt(0xFFCCCCCC))),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text("Datum: $dateStr", style: const pw.TextStyle(fontSize: 9)),
                        pw.Text("Azonosito: $bizonylatId", style: const pw.TextStyle(fontSize: 9)),
                      ]
                    )
                  ),
                ]
              )
            ]
          ),
          pw.SizedBox(height: 25),
          pw.Text(docType == 'bevetel' ? "BEERKEZETT ESZKOZ ADATAI" : "KIOZTOTT ESZKOZ ADATAI", style: pw.TextStyle(fontSize: 11, color: const PdfColor.fromInt(0xFF888888))),
          pw.Divider(),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 2,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("Megnevezes: ${_pdfSafe(data['name'])}", style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 8),
                    pw.Text("Kategoria: ${_pdfSafe(data['category'] ?? 'Egyeb')}"),
                    pw.Text("Vonalkod: ${data['barcode']?.toString().isNotEmpty == true ? data['barcode'] : '-'}"),
                  ]
                )
              ),
              pw.Expanded(
                flex: 1,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  color: const PdfColor.fromInt(0xFFF0F0F0),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(badgeText, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: badgeColor)),
                      pw.SizedBox(height: 4),
                      pw.Text("$moveQty db", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: badgeColor)),
                    ]
                  )
                )
              )
            ]
          ),
          pw.SizedBox(height: 20),
          if (movedSNs.isNotEmpty) ...[
            pw.Text("ERINTETT EGYEDI GYARI SZAMOK (SN):", style: pw.TextStyle(fontSize: 11, color: const PdfColor.fromInt(0xFF888888))),
            pw.Divider(),
            pw.SizedBox(height: 8),
            pw.Wrap(
              spacing: 6, runSpacing: 6,
              children: movedSNs.map((sn) => pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE3F2FD), borderRadius: pw.BorderRadius.all(pw.Radius.circular(4))),
                child: pw.Text(_pdfSafe(sn), style: const pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFF1565C0)))
              )).toList(),
            ),
          ],
          pw.SizedBox(height: 25),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: const PdfColor.fromInt(0xFF4CAF50), width: 1.5), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text("Keszletertek (egysegar):", style: const pw.TextStyle(fontSize: 10)), pw.Text("$price Ft", style: const pw.TextStyle(fontSize: 10))]),
                pw.Divider(color: const PdfColor.fromInt(0xFF4CAF50), thickness: 0.5),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(docType == 'bevetel' ? "KÉSZLET ÉRTÉK NÖVEKMÉNY:" : "BELSO NYILVANTARTASI ERTEK:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)), pw.Text("$total Ft", style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF4CAF50)))]),
              ]
            )
          ),
          if (docType == 'nyilatkozat') ...[
            pw.SizedBox(height: 15),
            pw.Text("Az Atvevo jelen nyilatkozat alairasaval elismeri, hogy a fent reszletezett eszkoz(oke)t hiany- es serulesmentes allapotban atvette, es az(ok) rendeltetesszeru hasznalataert teljes anyagi felelosseget vallal.", style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF555555))),
          ],
          pw.Spacer(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(children: [pw.Container(width: 130, height: 1, color: const PdfColor(0, 0, 0)), pw.SizedBox(height: 4), pw.Text(sig1, style: const pw.TextStyle(fontSize: 10))]),
            pw.Column(children: [pw.Container(width: 130, height: 1, color: const PdfColor(0, 0, 0)), pw.SizedBox(height: 4), pw.Text(sig2, style: const pw.TextStyle(fontSize: 10))]),
          ])
        ]);
      }));

      final bytes = await pdf.save();

      // Helyi mentés
      await _downloadFile(bytes, fileName, 'application/pdf');
      _msg("$title sikeresen mentve és archiválva!", Colors.green);

    } catch (e) {
      _msg("Váratlan hiba a PDF generáláskor: $e", Colors.red);
    }
  }

  // --- FELFEJLESZTETT VEZETŐI LELTÁR PDF PÉNZÜGYI ÖSSZESÍTŐVEL ---
  Future<void> _exportPDF() async {
    try {
      _msg("Leltár PDF készítése...", Colors.blue);
      QuerySnapshot snapshot = await _products.get();
      final pdf = pw.Document();
      
      List<List<String>> tableData = [['Név', 'Készlet', 'Kategória', 'Egységár', 'Összérték']];
      Map<String, int> categoryCounts = {};
      int totalItems = 0;
      int totalInventoryValue = 0; // PÉNZÜGYI ÖSSZESÍTŐ

      // Rendezés kategóriák, majd név szerint
      var docs = snapshot.docs.map((d) => d.data() as Map<String, dynamic>).toList();
      docs.sort((a, b) {
        int catCmp = (a['category']?.toString() ?? 'Egyeb').compareTo(b['category']?.toString() ?? 'Egyeb');
        if (catCmp != 0) return catCmp;
        return (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? '');
      });
      
      for (var d in docs) {
        int qty = d['quantity'] ?? 0;
        int price = d['price'] ?? 0;
        int limit = d['minLimit'] ?? 0;
        int rowValue = qty * price;
        String cat = d['category']?.toString() ?? 'Egyeb';
        if (cat.isEmpty) cat = 'Egyeb';
        
        bool isLow = qty <= limit;
        String displayName = _pdfSafe(d['name'] ?? "");
        if (isLow) displayName = "[HIANY] " + displayName; // Riasztás!
        
        tableData.add([displayName, "$qty db", _pdfSafe(cat), "$price Ft", "$rowValue Ft"]);
        categoryCounts[cat] = (categoryCounts[cat] ?? 0) + qty;
        totalItems += qty;
        totalInventoryValue += rowValue; // Adjuk hozzá a vagyonhoz
      }

      int maxCatCount = categoryCounts.isEmpty ? 1 : categoryCounts.values.reduce((a, b) => a > b ? a : b);

      pdf.addPage(pw.MultiPage(build: (c) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("$kCompanyName RAKTAR LELTAR", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Keszult: ${DateTime.now().year}.${DateTime.now().month.toString().padLeft(2,'0')}.${DateTime.now().day.toString().padLeft(2,'0')} - Osszes eszkoz: $totalItems db"),
                  pw.SizedBox(height: 4),
                  // ÚJ: PÉNZÜGYI VAGYON KIÍRÁSA A FEJLÉCBE
                  pw.Text("TELJES KESZLETERTEK: $totalInventoryValue Ft", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF2E7D32))),
                ]
              )
            ),
            pw.SizedBox(width: 15),
            pw.Container(height: 35, width: 35, child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: "LELTAR-${DateTime.now().millisecondsSinceEpoch}"))
          ]
        ),
        pw.SizedBox(height: 15),
        pw.Text("Keszlet Eloszlasa Kategoriakent (Diagram):", style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFF9F9F9), border: pw.Border.all(color: const PdfColor.fromInt(0xFFDDDDDD))),
          child: pw.Column(
            children: categoryCounts.entries.map((e) {
              double widthPercentage = e.value / maxCatCount;
              return pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Row(
                  children: [
                    pw.Container(width: 90, child: pw.Text(_pdfSafe(e.key), style: const pw.TextStyle(fontSize: 9))),
                    pw.Container(height: 10, width: 240 * widthPercentage, color: const PdfColor.fromInt(0xFF2196F3)),
                    pw.SizedBox(width: 6),
                    pw.Text("${e.value} db", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ]
                )
              );
            }).toList(),
          ),
        ),
        pw.SizedBox(height: 15),
        pw.Text("Reszletes Tetellista:", style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          context: c, data: tableData,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFFFFFFFF), fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF424242)),
          rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFEEEEEE)))),
        )
      ]));
      
      final bytes = await pdf.save();
      await _downloadFile(bytes, '${kCompanyName}_Leltar_${DateTime.now().millisecondsSinceEpoch}.pdf', 'application/pdf');
    } catch (e) { _msg("PDF hiba: $e", Colors.red); }
  }

  Future<void> _importCSV() async {
    try {
      final picker = ImagePicker();
      final XFile? result = await picker.pickMedia();
      if (result == null) return;
      _msg("Beolvasás...", Colors.blue);
      final input = await result.readAsString(encoding: utf8);
      final cleanInput = input.startsWith('\uFEFF') ? input.substring(1) : input;
      List<String> lines = cleanInput.split('\n');

      int count = 0;
      for (int i = 1; i < lines.length; i++) {
        String line = lines[i].trim();
        if (line.isEmpty) continue;
        List<String> cells = line.split('","').map((e) => e.replaceAll('"', '')).toList();
        if (cells.length < 5) continue;
        String priceStr = cells.length > 5 ? cells[5] : "0";
        String barcodeStr = cells.length > 6 ? cells[6] : "";
        String snRaw = cells.length > 4 ? cells[4] : "";
        List<String> importedSNs = snRaw.isNotEmpty ? snRaw.split(';').map((e) => e.trim()).toList() : [];

        await _products.add({
          'name': cells[0], 'quantity': importedSNs.isNotEmpty ? importedSNs.length : (int.tryParse(cells[1]) ?? 0),
          'minLimit': int.tryParse(cells[2]) ?? 0, 'category': cells.length > 3 ? cells[3] : "Egyéb",
          'serialNumbers': importedSNs, 'price': int.tryParse(priceStr) ?? 0, 'barcode': barcodeStr, 'updatedAt': FieldValue.serverTimestamp(),
        });
        count++;
      }
      _msg("$count tétel importálva!", Colors.green);
    } catch (e) { _msg("Hiba történt: ${e.toString()}", Colors.red); }
  }

  Future<void> _exportCSV() async {
    try {
      _msg("CSV generálása...", Colors.blue);
      QuerySnapshot snapshot = await _products.get();
      String csv = '"Név","Készlet","Limit","Kategória","SN","Ár","Vonalkód"\n';
      for (var doc in snapshot.docs) {
        final d = doc.data() as Map<String, dynamic>;
        List<String> snList = _parseSNs(d);
        String snExport = snList.join('; ');
        csv += '"${d['name']}","${d['quantity']}","${d['minLimit']}","${d['category']}","$snExport","${d['price']}","${d['barcode'] ?? ''}"\n';
      }
      final bytes = Uint8List.fromList(utf8.encode('\uFEFF' + csv));
      await _downloadFile(bytes, 'raktar_export.csv', 'text/csv');
    } catch (e) { _msg("Export hiba!", Colors.red); }
  }

  Future<void> _deleteSelectedItems() async {
    showDialog(
      context: context,
      builder: (BuildContext confirmContext) {
        return AlertDialog(
          title: const Text('Tömeges törlés megerősítése'),
          content: Text('Biztosan törölni szeretnéd a kijelölt ${_selectedItems.length} db terméket?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(confirmContext), child: const Text('Mégse')),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () async { Navigator.pop(confirmContext); WriteBatch batch = FirebaseFirestore.instance.batch(); for (String id in _selectedItems) batch.delete(_products.doc(id)); await batch.commit(); setState(() { _isSelectionMode = false; _selectedItems.clear(); }); _msg("Törölve!", Colors.green); }, child: const Text('Törlés', style: TextStyle(color: Colors.white))),
          ],
        );
      },
    );
  }

  void _showMovementDialog(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final qtyC = TextEditingController();
    bool isAddition = true;
    
    List<String> snList = _parseSNs(data);
    Set<String> selectedSNsToRemove = {};
    List<String> newSNsToAdd = [];
    
    final newSnC = TextEditingController();
    final bulkAddC = TextEditingController(); 
    final autoSelectC = TextEditingController(); 

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${data['name']} mozgatása'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ChoiceChip(label: const Text('Bevétel (+)'), selected: isAddition, selectedColor: Colors.green.shade200, onSelected: (val) => setDialogState(() { isAddition = true; selectedSNsToRemove.clear(); })),
                    ChoiceChip(label: const Text('Kiadás (-)'), selected: !isAddition, selectedColor: Colors.red.shade200, onSelected: (val) => setDialogState(() { isAddition = false; newSNsToAdd.clear(); qtyC.clear(); })),
                  ],
                ),
                const SizedBox(height: 16),
                
                if (isAddition) ...[
                  const Text('Egyesével szkennelés (vagy beírás):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: newSnC, decoration: InputDecoration(labelText: 'SN szkennelése', suffixIcon: IconButton(icon: const Icon(Icons.qr_code_scanner, color: Colors.blue), onPressed: () async { String scanned = await _scanBarcode(); if (scanned.isNotEmpty) newSnC.text = scanned; })))),
                      IconButton(icon: const Icon(Icons.add_circle, color: Colors.green, size: 36), onPressed: () { if (newSnC.text.trim().isNotEmpty) { setDialogState(() { String newSn = newSnC.text.trim(); if (!newSNsToAdd.contains(newSn) && !snList.contains(newSn)) { newSNsToAdd.add(newSn); qtyC.text = newSNsToAdd.length.toString(); } newSnC.clear(); }); } })
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('VAGY: Tömeges beillesztés (Lista bemásolása)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 12)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: TextField(controller: bulkAddC, maxLines: 3, decoration: const InputDecoration(hintText: 'Illeszd be ide a rengeteg gyári számot...', border: OutlineInputBorder()))),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20)),
                        onPressed: () {
                          if (bulkAddC.text.trim().isEmpty) return;
                          setDialogState(() {
                            List<String> bulkParsed = bulkAddC.text.split(RegExp(r'[\n\r,;]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                            for (var sn in bulkParsed) if (!newSNsToAdd.contains(sn) && !snList.contains(sn)) newSNsToAdd.add(sn);
                            qtyC.text = newSNsToAdd.length.toString(); bulkAddC.clear(); _msg("${bulkParsed.length} SN feldolgozva!", Colors.green);
                          });
                        },
                        child: const Text("Feldolgoz", style: TextStyle(color: Colors.white))
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (newSNsToAdd.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 8.0, bottom: 8.0), child: Wrap(spacing: 6, runSpacing: 6, children: newSNsToAdd.map((sn) => Chip(label: Text(sn, style: const TextStyle(fontSize: 12)), deleteIcon: const Icon(Icons.cancel, size: 18), onDeleted: () => setDialogState(() { newSNsToAdd.remove(sn); if (newSNsToAdd.isEmpty) qtyC.clear(); else qtyC.text = newSNsToAdd.length.toString(); }))).toList())),
                  const SizedBox(height: 16),
                  TextField(controller: qtyC, enabled: newSNsToAdd.isEmpty && snList.isEmpty, decoration: InputDecoration(labelText: (newSNsToAdd.isNotEmpty || snList.isNotEmpty) ? 'Mennyiség (Auto)' : 'Mennyiség', filled: (newSNsToAdd.isNotEmpty || snList.isNotEmpty), border: const OutlineInputBorder()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                ] 
                
                else if (!isAddition && snList.isNotEmpty) ...[
                  const Text('Válaszd ki a kiadandó eszközt:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  const SizedBox(height: 8),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8, runSpacing: 8,
                    children: [
                      ElevatedButton(onPressed: () { setDialogState(() { selectedSNsToRemove.addAll(snList); }); }, child: const Text('Mind')),
                      ElevatedButton(onPressed: () { setDialogState(() { selectedSNsToRemove.clear(); }); }, child: const Text('Töröl')),
                      SizedBox(
                        width: 100, 
                        child: TextField(controller: autoSelectC, decoration: const InputDecoration(labelText: 'Auto (db)', isDense: true, contentPadding: EdgeInsets.all(8)), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])
                      ),
                      IconButton(icon: const Icon(Icons.flash_auto, color: Colors.orange), onPressed: () { int toSelect = int.tryParse(autoSelectC.text.trim()) ?? 0; if (toSelect > 0 && toSelect <= snList.length) { setDialogState(() { selectedSNsToRemove.clear(); selectedSNsToRemove.addAll(snList.take(toSelect)); }); } else { _msg("Hibás vagy túl nagy szám!", Colors.red); } })
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: snList.map((sn) { final isSelected = selectedSNsToRemove.contains(sn); return FilterChip(label: Text(sn, style: const TextStyle(fontSize: 12)), selected: isSelected, selectedColor: Colors.red.shade100, checkmarkColor: Colors.red, onSelected: (bool selected) { setDialogState(() { if (selected) selectedSNsToRemove.add(sn); else selectedSNsToRemove.remove(sn); }); }); }).toList()),
                  const SizedBox(height: 16), Text('Levonandó mennyiség: ${selectedSNsToRemove.length} db', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 16)),
                ] else ...[
                  TextField(controller: qtyC, decoration: const InputDecoration(labelText: 'Mennyiség', border: OutlineInputBorder()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Mégse')),
            ElevatedButton(
              onPressed: () async {
                int moveQty = 0;
                if (isAddition) {
                  if (snList.isNotEmpty && newSNsToAdd.isEmpty) { _msg("Ehhez a termékhez kötelező megadni az új egyedi SN-eket!", Colors.red); return; }
                  moveQty = newSNsToAdd.isNotEmpty ? newSNsToAdd.length : (int.tryParse(qtyC.text.trim()) ?? 0);
                } else {
                  if (snList.isNotEmpty && selectedSNsToRemove.isEmpty) { _msg("Jelölj ki legalább egy kiadandó eszközt!", Colors.red); return; }
                  moveQty = snList.isNotEmpty ? selectedSNsToRemove.length : (int.tryParse(qtyC.text.trim()) ?? 0);
                }

                if (moveQty <= 0) { _msg("Hibás mennyiség!", Colors.red); return; }
                
                final currentQty = data['quantity'] ?? 0;
                final newQty = isAddition ? currentQty + moveQty : currentQty - moveQty;
                if (newQty < 0) { _msg("Nincs elég készlet!", Colors.red); return; }

                Map<String, dynamic> updateData = {'quantity': newQty};
                if (isAddition && newSNsToAdd.isNotEmpty) {
                  List<String> updatedSnList = List<String>.from(snList);
                  updatedSnList.addAll(newSNsToAdd);
                  updateData['serialNumbers'] = updatedSnList; 
                } else if (!isAddition && selectedSNsToRemove.isNotEmpty) {
                  List<String> updatedSnList = List<String>.from(snList);
                  updatedSnList.removeWhere((sn) => selectedSNsToRemove.contains(sn));
                  updateData['serialNumbers'] = updatedSnList; 
                }

                _products.doc(doc.id).update(updateData);
                
                String logDetail = "";
                if (isAddition && newSNsToAdd.isNotEmpty) logDetail = " (+SN: ${newSNsToAdd.join(', ')})";
                if (!isAddition && selectedSNsToRemove.isNotEmpty) logDetail = " (-SN: ${selectedSNsToRemove.join(', ')})";
                
                _movements.add({'productId': doc.id, 'productName': "${data['name']}$logDetail", 'type': isAddition ? 'in' : 'out', 'amount': moveQty, 'date': FieldValue.serverTimestamp()});
                
                Navigator.pop(context); 
                _msg("Készlet frissítve!", Colors.green);
                
                // MENTÉS UTÁN AUTOMATA PDF KÉSZÍTÉS KIADÁS ÉS BEVÉTEL ESETÉN IS!
                if (!isAddition) {
                  final staticSNList = selectedSNsToRemove.toList();
                  await _generateInternalDocumentPDF(docType: 'bizonylat', data: data, moveQty: moveQty, movedSNs: staticSNList);
                  await _generateInternalDocumentPDF(docType: 'nyilatkozat', data: data, moveQty: moveQty, movedSNs: staticSNList);
                } else {
                  final staticSNList = newSNsToAdd.toList();
                  await _generateInternalDocumentPDF(docType: 'bevetel', data: data, moveQty: moveQty, movedSNs: staticSNList);
                }
              },
              child: const Text('Mentés'),
            ),
          ],
        ),
      ),
    );
  }

  void _openProductDialog({DocumentSnapshot? doc}) {
    final bool isEdit = doc != null;
    final Map<String, dynamic>? data = isEdit ? doc.data() as Map<String, dynamic> : null;
    final nameC = TextEditingController(text: isEdit ? data!['name'] : "");
    final qtyC = TextEditingController(text: isEdit ? data!['quantity'].toString() : "");
    final limitC = TextEditingController(text: isEdit ? (data!['minLimit'] ?? 0).toString() : "5");
    final catC = TextEditingController(text: isEdit ? data!['category'] : "");
    final barcodeC = TextEditingController(text: isEdit ? data!['barcode'] : ""); 
    final priceC = TextEditingController(text: isEdit ? data!['price'].toString() : "");
    final descC = TextEditingController(text: isEdit ? data!['description'] : "");
    
    List<String> snList = isEdit ? _parseSNs(data!) : [];
    final newSnC = TextEditingController();
    String? localImagePath = isEdit ? data!['imagePath'] : null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (snList.isNotEmpty) qtyC.text = snList.length.toString();

          return AlertDialog(
            title: Text(isEdit ? 'Termék módosítása' : 'Új termék felvétele'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(alignment: Alignment.center, child: GestureDetector(onTap: () async { if (kIsWeb) return; final pickedFile = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70); if (pickedFile != null) { final appDir = await getApplicationDocumentsDirectory(); final savedImage = await File(pickedFile.path).copy('${appDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg'); setDialogState(() { localImagePath = savedImage.path; }); } }, child: Container(height: 120, width: 120, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceVariant, borderRadius: BorderRadius.circular(15), image: localImagePath != null && !kIsWeb && File(localImagePath!).existsSync() ? DecorationImage(image: FileImage(File(localImagePath!)), fit: BoxFit.cover) : null), child: localImagePath == null ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.camera_alt, size: 40), Text("Fotó")]) : null))),
                  const SizedBox(height: 16), TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Eszköz neve *')), const SizedBox(height: 12),
                  DropdownMenu<String>(initialSelection: catC.text.isNotEmpty ? catC.text : null, controller: catC, label: const Text('Csoport / Típus választása *'), expandedInsets: EdgeInsets.zero, dropdownMenuEntries: _currentCategories.map<DropdownMenuEntry<String>>((String value) => DropdownMenuEntry<String>(value: value, label: value)).toList()),
                  const SizedBox(height: 12),
                  Row(children: [Expanded(child: TextField(controller: qtyC, enabled: snList.isEmpty, decoration: InputDecoration(labelText: snList.isNotEmpty ? 'Készlet (Auto) *' : 'Készlet *', filled: snList.isNotEmpty), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])), const SizedBox(width: 10), Expanded(child: TextField(controller: limitC, decoration: const InputDecoration(labelText: 'Min. limit'), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]))]),
                  TextField(controller: barcodeC, decoration: InputDecoration(labelText: 'Közös Vonalkód', suffixIcon: IconButton(icon: const Icon(Icons.qr_code_scanner, color: Colors.blue), onPressed: () async { String scanned = await _scanBarcode(); if (scanned.isNotEmpty) barcodeC.text = scanned.replaceAll(RegExp(r'[^0-9]'), ''); })), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                  const SizedBox(height: 20), const Text("Egyedi Sorozatszámok (SN)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const Divider(),
                  Row(children: [Expanded(child: TextField(controller: newSnC, decoration: InputDecoration(labelText: 'Új SN hozzáadása', suffixIcon: IconButton(icon: const Icon(Icons.qr_code_scanner, color: Colors.blue), onPressed: () async { String scanned = await _scanBarcode(); if (scanned.isNotEmpty) newSnC.text = scanned; })))), IconButton(icon: const Icon(Icons.add_circle, color: Colors.green, size: 36), onPressed: () { if (newSnC.text.trim().isNotEmpty) { setDialogState(() { if (!snList.contains(newSnC.text.trim())) snList.add(newSnC.text.trim()); newSnC.clear(); }); } })]),
                  const SizedBox(height: 10), Wrap(spacing: 8, runSpacing: 4, children: snList.map((sn) => Chip(label: Text(sn), deleteIcon: const Icon(Icons.cancel, size: 18), onDeleted: () { setDialogState(() { snList.remove(sn); if (snList.isEmpty) qtyC.clear(); }); })).toList()),
                  const SizedBox(height: 10), TextField(controller: priceC, decoration: const InputDecoration(labelText: 'Ár (Ft)'), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                  TextField(controller: descC, decoration: const InputDecoration(labelText: 'Leírás'), maxLines: 2),
                ],
              ),
            ),
            actions: [
              if (isEdit) TextButton(onPressed: () { showDialog(context: context, builder: (BuildContext confirmContext) { return AlertDialog(title: const Text('Törlés megerősítése'), content: const Text('Biztosan törölni szeretnéd ezt a terméket?'), actions: [TextButton(onPressed: () => Navigator.pop(confirmContext), child: const Text('Mégse')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () async { await _products.doc(doc.id).delete(); Navigator.pop(confirmContext); Navigator.pop(context); _msg("Termék törölve!", Colors.red); }, child: const Text('Törlés', style: TextStyle(color: Colors.white)))]); }); }, child: const Text('Törlés', style: TextStyle(color: Colors.red))),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Mégse')),
              ElevatedButton(
                onPressed: () {
                  final name = nameC.text.trim();
                  final qty = snList.isNotEmpty ? snList.length : (int.tryParse(qtyC.text.trim()) ?? 0);
                  if (name.isEmpty) { _msg("Az eszköz neve kötelező!", Colors.red); return; }
                  final payload = {'name': name, 'quantity': qty, 'minLimit': int.tryParse(limitC.text.trim()) ?? 0, 'category': catC.text.isEmpty ? "Egyéb" : catC.text.trim(), 'serialNumbers': snList, 'barcode': barcodeC.text, 'price': int.tryParse(priceC.text.trim()) ?? 0, 'description': descC.text, 'imagePath': localImagePath, 'updatedAt': FieldValue.serverTimestamp()};
                  if (isEdit) { _products.doc(doc.id).update(payload); } else { _products.add(payload).then((newDoc) { if (qty > 0) _movements.add({'productId': newDoc.id, 'productName': name, 'type': 'in', 'amount': qty, 'date': FieldValue.serverTimestamp()}); }); }
                  Navigator.pop(context); _msg("Mentve!", Colors.green);
                },
                child: const Text('Mentés'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isSelectionMode
          ? AppBar(title: Text('${_selectedItems.length} kiválasztva', style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Theme.of(context).colorScheme.errorContainer, leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _isSelectionMode = false; _selectedItems.clear(); })), actions: [if (_selectedItems.isNotEmpty) IconButton(icon: const Icon(Icons.delete, color: Colors.red), tooltip: 'Kijelöltek törlése', onPressed: _deleteSelectedItems)])
          : AppBar(title: const Text('Raktár Cloud', style: TextStyle(fontWeight: FontWeight.bold)), elevation: 2, actions: [IconButton(icon: const Icon(Icons.checklist), tooltip: 'Többes kijelölés', onPressed: () => setState(() => _isSelectionMode = true)), IconButton(icon: const Icon(Icons.upload_file), tooltip: 'Import', onPressed: _importCSV), IconButton(icon: const Icon(Icons.table_view), tooltip: 'CSV letöltés', onPressed: _exportCSV), IconButton(icon: const Icon(Icons.picture_as_pdf), tooltip: 'Leltár PDF letöltés', onPressed: _exportPDF), IconButton(icon: const Icon(Icons.brightness_6), onPressed: () => themeNotifier.value = themeNotifier.value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light)]),
      body: Column(
        children: [
          if (!_isSelectionMode) Padding(padding: const EdgeInsets.all(12.0), child: TextField(controller: _searchController, decoration: InputDecoration(labelText: 'Keresés (Név, SN vagy VK)...', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(icon: const Icon(Icons.qr_code_scanner, color: Colors.blue), onPressed: () async { String s = await _scanBarcode(); if (s.isNotEmpty) setState(() { _searchText = s.toLowerCase(); _searchController.text = s; }); }), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), onChanged: (val) => setState(() => _searchText = val.toLowerCase()))),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _products.orderBy('name').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs.where((d) {
                  final name = d['name'].toString().toLowerCase();
                  final dataMap = d.data() as Map<String, dynamic>;
                  final bc = dataMap['barcode']?.toString().toLowerCase() ?? "";
                  List<String> snList = _parseSNs(dataMap);
                  final bool hasSnMatch = snList.any((sn) => sn.toLowerCase().contains(_searchText));
                  return name.contains(_searchText) || bc.contains(_searchText) || hasSnMatch;
                }).toList();
                _currentCategories = snapshot.data!.docs.map((d) => (d.data() as Map<String, dynamic>)['category']?.toString() ?? "Egyéb").toSet().toList();
                if (_currentCategories.isEmpty) _currentCategories = ["Számítógépek", "Perifériák", "Kábelek"];

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final int qty = data['quantity'] ?? 0;
                    final int limit = data['minLimit'] ?? 0;
                    final bool isLow = qty <= limit;
                    final String? img = data['imagePath'];
                    final String docId = docs[index].id;
                    List<String> snList = _parseSNs(data);
                    String snDisplay = snList.isEmpty ? "-" : "${snList.length} db rögzítve";

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), elevation: 3, color: _selectedItems.contains(docId) ? Colors.blue.withOpacity(0.1) : (isLow ? Colors.red.withOpacity(0.08) : null), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        onTap: _isSelectionMode ? () { setState(() { if (_selectedItems.contains(docId)) _selectedItems.remove(docId); else _selectedItems.add(docId); }); } : () => Navigator.push(context, MaterialPageRoute(builder: (c) => DetailScreen(doc: docs[index]))),
                        onLongPress: _isSelectionMode ? null : () => _openProductDialog(doc: docs[index]),
                        leading: _isSelectionMode ? Checkbox(value: _selectedItems.contains(docId), onChanged: (bool? value) { setState(() { if (value == true) _selectedItems.add(docId); else _selectedItems.remove(docId); }); }) : (img != null && !kIsWeb && File(img).existsSync() ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(img), width: 50, height: 50, fit: BoxFit.cover)) : Container(width: 50, height: 50, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.inventory))),
                        title: Text(data['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${data['category'] ?? 'Egyéb'} | SN: $snDisplay\nVK: ${data['barcode']?.toString().isNotEmpty == true ? data['barcode'] : '-'}"),
                        trailing: _isSelectionMode ? null : Row(mainAxisSize: MainAxisSize.min, children: [Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('$qty db', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isLow ? Colors.red : Colors.blueGrey)), if (isLow) const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16)]), IconButton(icon: const Icon(Icons.swap_horiz, color: Colors.blue), onPressed: () => _showMovementDialog(docs[index]))]),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _isSelectionMode ? null : FloatingActionButton.extended(onPressed: () => _openProductDialog(), label: const Text('Új Termék'), icon: const Icon(Icons.add)),
    );
  }
}

class HomeScreenPage extends StatelessWidget {
  const HomeScreenPage({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}