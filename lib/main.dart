import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';

const String API_BASE = 'http://34.18.76.47:3000/api';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return Future.value(true);
      await syncCallLogs(token, prefs);
      return Future.value(true);
    } catch (e) {
      return Future.value(false);
    }
  });
}

Future<void> syncCallLogs(String token, SharedPreferences prefs) async {
  final lastSync = prefs.getInt('last_call_sync') ?? 0;
  Iterable<CallLogEntry> entries = await CallLog.query(
    dateFrom: lastSync > 0 ? lastSync : DateTime.now().subtract(Duration(days: 7)).millisecondsSinceEpoch,
    dateTo: DateTime.now().millisecondsSinceEpoch,
  );
  if (entries.isEmpty) return;
  final deviceId = prefs.getString('device_id') ?? 'unknown';
  final calls = entries.map((e) {
    String ct = 'incoming';
    if (e.callType == CallType.outgoing) ct = 'outgoing';
    if (e.callType == CallType.missed) ct = 'missed';
    return {'contact_name': e.name ?? e.number ?? 'Unknown', 'phone_number': e.number ?? '', 'call_type': ct, 'duration': e.duration ?? 0, 'timestamp': DateTime.fromMillisecondsSinceEpoch(e.timestamp ?? 0).toIso8601String(), 'device_id': deviceId};
  }).toList();
  for (var i = 0; i < calls.length; i += 50) {
    final batch = calls.sublist(i, i + 50 > calls.length ? calls.length : i + 50);
    await http.post(Uri.parse('$API_BASE/sync/calls'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({'calls': batch}));
  }
  await prefs.setInt('last_call_sync', DateTime.now().millisecondsSinceEpoch);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  await Workmanager().registerPeriodicTask('cm-sync', 'callLogSync', frequency: Duration(minutes: 15), constraints: Constraints(networkType: NetworkType.connected));
  runApp(CleverMetalApp());
}

class CleverMetalApp extends StatelessWidget {
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Clever Metal', debugShowCheckedModeBanner: false, theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFF9C6C3C)), useMaterial3: true), home: SplashScreen());
  }
}

class SplashScreen extends StatefulWidget { State<SplashScreen> createState() => _SplashState(); }
class _SplashState extends State<SplashScreen> {
  void initState() { super.initState(); _check(); }
  Future<void> _check() async {
    await Future.delayed(Duration(seconds: 1));
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('token') != null) { if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen())); }
    else { if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LoginScreen())); }
  }
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Color(0xFFF5F4F1), body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 80, height: 80, decoration: BoxDecoration(color: Color(0xFF9C6C3C), borderRadius: BorderRadius.circular(16)), child: Center(child: Text('CM', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)))),
      SizedBox(height: 16), Text('CLEVER METAL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 2)),
      Text('INDUSTRIES LLC', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 3, color: Color(0xFF9C6C3C))),
      SizedBox(height: 32), CircularProgressIndicator(color: Color(0xFF9C6C3C))
    ])));
  }
}

class LoginScreen extends StatefulWidget { State<LoginScreen> createState() => _LoginState(); }
class _LoginState extends State<LoginScreen> {
  final _u = TextEditingController(), _p = TextEditingController();
  bool _loading = false; String? _error;
  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await http.post(Uri.parse('$API_BASE/auth/login'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'username': _u.text, 'password': _p.text}));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('user_name', data['user']['name']);
        await prefs.setString('emp_id', data['user']['emp_id'] ?? '');
        final di = DeviceInfoPlugin(); final android = await di.androidInfo;
        await prefs.setString('device_id', android.id);
        await http.post(Uri.parse('$API_BASE/auth/register-device'), headers: {'Authorization': 'Bearer ${data['token']}', 'Content-Type': 'application/json'}, body: jsonEncode({'device_id': android.id, 'device_model': '${android.brand} ${android.model}', 'android_version': android.version.release}));
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen()));
      } else { setState(() { _error = 'Invalid credentials'; }); }
    } catch (e) { setState(() { _error = 'Connection error: $e'; }); }
    setState(() { _loading = false; });
  }
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Color(0xFFF5F4F1), body: SafeArea(child: Center(child: SingleChildScrollView(padding: EdgeInsets.all(32), child: Column(children: [
      Container(width: 64, height: 64, decoration: BoxDecoration(color: Color(0xFF9C6C3C), borderRadius: BorderRadius.circular(12)), child: Center(child: Text('CM', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)))),
      SizedBox(height: 12), Text('CLEVER METAL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 2)), SizedBox(height: 32),
      TextField(controller: _u, decoration: InputDecoration(labelText: 'Username', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white)),
      SizedBox(height: 12), TextField(controller: _p, obscureText: true, decoration: InputDecoration(labelText: 'Password', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white), onSubmitted: (_) => _login()),
      if (_error != null) Padding(padding: EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Colors.red, fontSize: 12))),
      SizedBox(height: 20), SizedBox(width: double.infinity, height: 48, child: ElevatedButton(onPressed: _loading ? null : _login, style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF9C6C3C), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: _loading ? CircularProgressIndicator(color: Colors.white) : Text('LOGIN', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1))))
    ])))));
  }
}

class HomeScreen extends StatefulWidget { State<HomeScreen> createState() => _HomeState(); }
class _HomeState extends State<HomeScreen> {
  String _name = '', _empId = ''; bool _syncing = false; String _lastSync = 'Never'; int _callCount = 0;
  Map<String, bool> _perms = {};
  void initState() { super.initState(); _load(); _checkPerms(); }
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _name = prefs.getString('user_name') ?? 'Employee'; _empId = prefs.getString('emp_id') ?? '';
      final ls = prefs.getInt('last_call_sync') ?? 0;
      if (ls > 0) _lastSync = DateFormat('dd MMM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ls));
    });
  }
  Future<void> _checkPerms() async {
    final c = await Permission.phone.status; final ct = await Permission.contacts.status; final n = await Permission.notification.status;
    setState(() { _perms = {'Call Log': c.isGranted, 'Contacts': ct.isGranted, 'Notifications': n.isGranted}; });
  }
  Future<void> _reqPerms() async { await [Permission.phone, Permission.contacts, Permission.notification].request(); _checkPerms(); }
  Future<void> _sync() async {
    setState(() { _syncing = true; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token != null) await syncCallLogs(token, prefs);
      await _load();
      final today = DateTime.now(); final sod = DateTime(today.year, today.month, today.day);
      final entries = await CallLog.query(dateFrom: sod.millisecondsSinceEpoch, dateTo: today.millisecondsSinceEpoch);
      setState(() { _callCount = entries.length; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync complete!'), backgroundColor: Color(0xFF3A6E48)));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync failed: $e'), backgroundColor: Colors.red)); }
    setState(() { _syncing = false; });
  }
  Future<void> _logout() async { final prefs = await SharedPreferences.getInstance(); await prefs.clear(); if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LoginScreen())); }
  Widget build(BuildContext context) {
    final allOk = _perms.values.isNotEmpty && _perms.values.every((v) => v);
    return Scaffold(backgroundColor: Color(0xFFF5F4F1),
      appBar: AppBar(title: Text('CLEVER METAL', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5, fontSize: 16)), backgroundColor: Color(0xFF9C6C3C), foregroundColor: Colors.white, actions: [IconButton(icon: Icon(Icons.logout), onPressed: _logout)]),
      body: SingleChildScrollView(padding: EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: double.infinity, padding: EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Color(0xFFD4D0C8))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Welcome, $_name', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)), SizedBox(height: 4), Text('ID: $_empId', style: TextStyle(color: Color(0xFF908878), fontSize: 12)), SizedBox(height: 8), Text('Last sync: $_lastSync', style: TextStyle(color: Color(0xFF9C6C3C), fontSize: 12, fontWeight: FontWeight.w600))])),
        SizedBox(height: 16),
        Container(width: double.infinity, padding: EdgeInsets.all(16), decoration: BoxDecoration(color: allOk ? Color(0xFFF0F7F2) : Color(0xFFFFF3F0), borderRadius: BorderRadius.circular(12), border: Border.all(color: (allOk ? Color(0xFF3A6E48) : Colors.red).withOpacity(0.2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(allOk ? Icons.check_circle : Icons.warning, color: allOk ? Color(0xFF3A6E48) : Colors.red, size: 20), SizedBox(width: 8), Text(allOk ? 'All permissions granted' : 'Permissions needed', style: TextStyle(fontWeight: FontWeight.w700, color: allOk ? Color(0xFF3A6E48) : Colors.red))]),
            SizedBox(height: 8), ..._perms.entries.map((e) => Padding(padding: EdgeInsets.symmetric(vertical: 2), child: Row(children: [Icon(e.value ? Icons.check : Icons.close, size: 14, color: e.value ? Color(0xFF3A6E48) : Colors.red), SizedBox(width: 6), Text(e.key, style: TextStyle(fontSize: 12))]))),
            if (!allOk) ...[SizedBox(height: 8), SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _reqPerms, style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF9C6C3C), foregroundColor: Colors.white), child: Text('GRANT PERMISSIONS')))]
          ])),
        SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 56, child: ElevatedButton.icon(onPressed: _syncing ? null : _sync, icon: _syncing ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(Icons.sync, size: 24),
          label: Text(_syncing ? 'SYNCING...' : 'SYNC NOW', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1, fontSize: 16)),
          style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF3A6E48), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
        SizedBox(height: 12), Center(child: Text('Auto-sync every 15 min', style: TextStyle(fontSize: 11, color: Colors.grey[600]))),
        SizedBox(height: 24), Text('TODAY', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1, color: Color(0xFF908878), fontSize: 11)), SizedBox(height: 8),
        Row(children: [
          Expanded(child: Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Color(0xFFD4D0C8))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('CALLS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9C6C3C), letterSpacing: 1)), SizedBox(height: 4), Text('$_callCount', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF9C6C3C), fontFamily: 'monospace'))]))),
          SizedBox(width: 8),
          Expanded(child: Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Color(0xFFD4D0C8))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('STATUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: allOk ? Color(0xFF3A6E48) : Colors.red, letterSpacing: 1)), SizedBox(height: 4), Text(allOk ? 'ACTIVE' : 'SETUP', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: allOk ? Color(0xFF3A6E48) : Colors.red, fontFamily: 'monospace'))])))
        ]),
        SizedBox(height: 16), Center(child: Text('v1.0.0 | Clever Metal Industries LLC', style: TextStyle(fontSize: 10, color: Colors.grey[500])))
      ])));
  }
}
