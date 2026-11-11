import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'services/db_helper.dart';

// Live Server Endpoint
const String API_BASE = "https://hplinfra.com/erp/api/field_app_api.php";
const String SYNC_BASE = "https://hplinfra.com/erp/api/app_sync.php";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: NativeFieldAppHome(),
  ));
}

class NativeFieldAppHome extends StatefulWidget {
  const NativeFieldAppHome({super.key});
  @override
  State<NativeFieldAppHome> createState() => _NativeFieldAppHomeState();
}

class _NativeFieldAppHomeState extends State<NativeFieldAppHome> {
  int currentTab = 0;
  bool isPunchedIn = false;
  Position? currentGps;
  int offlinePoints = 0;
  List<dynamic> assignedTasks = [];

  @override
  void initState() {
    super.initState();
    _initGpsTracker();
    _fetchTasks();
  }

  // 1. Hardware GPS Tracker (Works Without Internet)
  void _initGpsTracker() async {
    await Geolocator.requestPermission();
    Timer.periodic(const Duration(minutes: 2), (t) async {
      try {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        setState(() => currentGps = pos);
        
        // Save to Phone Local SQLite DB
        final db = await LocalDatabase.instance;
        await db.insert('offline_gps_trail', {
          'lat': pos.latitude.toString(),
          'lng': pos.longitude.toString(),
          'log_time': DateFormat('HH:mm:ss').format(DateTime.now()),
          'is_synced': 0
        });

        var count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM offline_gps_trail WHERE is_synced=0')) ?? 0;
        setState(() => offlinePoints = count);

        // Try background silent sync
        _silentBackgroundSync();
      } catch (_) {}
    });
  }

  // 2. Silent Cloud Sync when network returns
  void _silentBackgroundSync() async {
    try {
      final db = await LocalDatabase.instance;
      List<Map<String, dynamic>> unsynced = await db.query('offline_gps_trail', where: 'is_synced=0', limit: 50);
      if (unsynced.isEmpty) return;

      var res = await http.post(
        Uri.parse("$API_BASE?action=sync_offline_route"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": 1, "route_points": unsynced}),
      );

      if (res.statusCode == 200) {
        await db.update('offline_gps_trail', {'is_synced': 1}, where: 'is_synced=0');
        setState(() => offlinePoints = 0);
      }
    } catch (_) {}
  }

  void _fetchTasks() async {
    try {
      var res = await http.get(Uri.parse("$API_BASE?action=get_my_tasks&user_id=1"));
      if (res.statusCode == 200) {
        var data = jsonDecode(res.body);
        if (data['status'] == true) {
          setState(() => assignedTasks = data['tasks']);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text("HPL Native Field App", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.sync), onPressed: _silentBackgroundSync)
        ],
      ),
      body: currentTab == 0 ? _buildDutyScreen() : _buildTaskScreen(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentTab,
        onTap: (i) => setState(() => currentTab = i),
        selectedItemColor: const Color(0xFF2563EB),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.location_on), label: "Duty & GPS"),
          BottomNavigationBarItem(icon: Icon(Icons.assignment), label: "My Tasks"),
        ],
      ),
    );
  }

  Widget _buildDutyScreen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Offline Status Card
        Card(
          color: offlinePoints > 0 ? Colors.orange.shade50 : Colors.green.shade50,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(offlinePoints > 0 ? Icons.cloud_off : Icons.cloud_done, color: offlinePoints > 0 ? Colors.orange : Colors.green),
                const SizedBox(width: 12),
                Expanded(child: Text(offlinePoints > 0 ? "$offlinePoints Checkpoints saved in Phone SQLite (Will sync on network)" : "Hardware GPS Active & Cloud Synced", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Live GPS Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("LIVE HARDWARE GPS (NO NET NEEDED)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 6),
                Text(currentGps != null ? "${currentGps!.latitude.toStringAsFixed(6)}, ${currentGps!.longitude.toStringAsFixed(6)}" : "Locking Satellite GPS...", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Punch In / Out
        ElevatedButton.icon(
          onPressed: () {
            setState(() => isPunchedIn = !isPunchedIn);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isPunchedIn ? "Duty Started! Start Point Locked." : "Duty Ended! End Point Locked.")));
          },
          icon: Icon(isPunchedIn ? Icons.stop : Icons.play_arrow),
          label: Text(isPunchedIn ? "PUNCH OUT (End Duty)" : "PUNCH IN (Start Day Duty)"),
          style: ElevatedButton.styleFrom(
            backgroundColor: isPunchedIn ? Colors.red : Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Widget _buildTaskScreen() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: assignedTasks.length,
      itemBuilder: (ctx, i) {
        var t = assignedTasks[i];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(t['gp_name'] ?? 'Site', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("${t['block_name']} • Due: ${t['target_date']}"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          ),
        );
      },
    );
  }
}