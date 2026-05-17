import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DetailScreen extends StatelessWidget {
  final DocumentSnapshot doc;
  const DetailScreen({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final String? imgPath = data['imagePath'];

    return Scaffold(
      appBar: AppBar(
        title: Text(data['name'] ?? 'Termék részletei'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          if (imgPath != null && !kIsWeb && File(imgPath).existsSync())
            Container(
              width: double.infinity,
              height: 250,
              decoration: BoxDecoration(
                image: DecorationImage(image: FileImage(File(imgPath)), fit: BoxFit.cover),
              ),
            ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoCard(context, data),
                  const SizedBox(height: 10),
                  if (data['description']?.toString().isNotEmpty == true) ...[
                    const Text("Leírás:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(data['description']),
                  ],
                  const Divider(thickness: 2, height: 40),
                  const Text("Mozgásnapló", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('movements').where('productId', isEqualTo: doc.id).snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) return Text("Hiba: ${snapshot.error}");
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Text("Még nincs rögzített mozgás.");

                      final docs = snapshot.data!.docs.toList();
                      docs.sort((a, b) {
                        final aData = a.data() as Map<String, dynamic>;
                        final bData = b.data() as Map<String, dynamic>;
                        final Timestamp? aDate = aData['date'] as Timestamp?;
                        final Timestamp? bDate = bData['date'] as Timestamp?;
                        if (aDate == null || bDate == null) return 0;
                        return bDate.compareTo(aDate);
                      });

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final move = docs[index].data() as Map<String, dynamic>;
                          final bool isIn = move['type'] == 'in';
                          
                          String dateStr = "Épp most";
                          if (move['date'] != null) {
                            final DateTime dt = (move['date'] as Timestamp).toDate();
                            dateStr = "${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
                          }

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isIn ? Colors.green.shade100 : Colors.red.shade100, 
                              child: Icon(isIn ? Icons.arrow_downward : Icons.arrow_upward, color: isIn ? Colors.green : Colors.red)
                            ),
                            title: Text(isIn ? "Bevételezés" : "Kiadás", style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(dateStr),
                            trailing: Text("${isIn ? '+' : '-'}${move['amount']} db", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isIn ? Colors.green : Colors.red)),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(BuildContext context, Map<String, dynamic> data) {
    // --- BIZTONSÁGI SZŰRŐ: Az összeragadt adatok azonnali szétvágása ---
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
      if (oldSn.contains(';')) {
        snList = oldSn.split(';').map((e) => e.trim()).toList();
      } else {
        snList.add(oldSn.trim());
      }
    }
    snList.removeWhere((element) => element.isEmpty); // Üres elemek kidobása

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _rowInfo(Icons.category, "Kategória", data['category'] ?? "Egyéb"),
            _rowInfo(Icons.view_week, "Közös Vonalkód", data['barcode']?.toString().isNotEmpty == true ? data['barcode'] : "Nincs"),
            _rowInfo(Icons.inventory_2, "Összes Készlet", "${data['quantity']} db (Min: ${data['minLimit'] ?? 0})"),
            _rowInfo(Icons.euro, "Egységár", "${data['price'] ?? 0} Ft"),
            
            const SizedBox(height: 12),
            const Divider(),
            
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code, size: 20, color: Colors.blue),
                  const SizedBox(width: 12),
                  Text("Egyedi Sorozatszámok (${snList.length} db):", style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            
            if (snList.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8.0, top: 4.0, bottom: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: snList.asMap().entries.map((entry) {
                    int idx = entry.key + 1;
                    String sn = entry.value;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Container(
                            width: 24, height: 24, alignment: Alignment.center,
                            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle),
                            child: Text("$idx", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue)),
                          ),
                          const SizedBox(width: 12),
                          Text(sn, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.5)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(left: 32.0, bottom: 8.0), 
                child: Text("Nincs rögzített azonosító.", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))
              ),
          ],
        ),
      ),
    );
  }

  Widget _rowInfo(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blue),
          const SizedBox(width: 12),
          Text("$label: ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}